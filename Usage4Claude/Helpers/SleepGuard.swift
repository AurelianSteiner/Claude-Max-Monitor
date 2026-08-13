//
//  SleepGuard.swift
//  Usage4Claude
//
//  Hält Bildschirm bzw. Mac wach — wie Amphetamine/Caffeine, aber ohne
//  Hilfsprogramm: IOKit-Power-Assertions (IOPMAssertionCreateWithName /
//  IOPMAssertionRelease) brauchen weder root noch ein Extra-Entitlement und
//  funktionieren auch in der Sandbox. Deshalb wird hier bewusst nicht auf
//  `caffeinate`/`pmset` ausgewichen (Sandbox verbietet das Starten fremder
//  Prozesse ohnehin).
//
//  Bewusst NICHT unterstützt: Wachbleiben bei geschlossenem Deckel
//  (Clamshell). Das geht nur über `sudo pmset disablesleep 1`, verlangt also
//  Root-Rechte bzw. ein privilegiertes Helper-Tool — beides passt weder zur
//  Sandbox noch zum Anspruch „kein Passwort nötig“.
//
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import Combine
import OSLog
import IOKit.pwr_mgt

/// Wach-Wächter: verwaltet die beiden Power-Assertions der App.
///
/// Zuordnung zu den beiden Symbolknöpfen im Kopf der Übersicht
/// (`DashboardView.sleepGuardButtons`) — die Tooltips dort erklären dasselbe
/// in Nutzersprache:
///
/// - Sonne (`sun.max`) → `setDisplayAwake` → `isDisplayAwake`
///   → `kIOPMAssertionTypeNoDisplaySleep`
///   Der Bildschirm schaltet sich nicht von selbst aus. Solange der Bildschirm
///   an ist, schläft auch das System nicht — der Mac bleibt also mit wach.
/// - Tasse (`cup.and.saucer`) → `setSystemAwake` → `isSystemAwake`
///   → `kIOPMAssertionTypePreventUserIdleSystemSleep`
///   Das System geht bei Untätigkeit nicht in den Ruhezustand; der Bildschirm
///   darf trotzdem dunkel werden.
///
/// Beides gilt nur, solange die App läuft: `releaseAll()` beim Beenden gibt die
/// Assertions frei, danach greifen wieder die Systemeinstellungen. Zuklappen
/// (Clamshell) schläfert den Mac in beiden Fällen ein — siehe Dateikopf.
///
/// Beide Zustände werden in den UserDefaults gemerkt und beim Start über
/// `restoreFromDefaults()` erneut angefordert.
final class SleepGuard: ObservableObject {

    // MARK: - Singleton

    static let shared = SleepGuard()

    // MARK: - Published State

    /// Bildschirm wird wach gehalten
    @Published private(set) var isDisplayAwake: Bool = false
    /// Mac (System) wird wach gehalten
    @Published private(set) var isSystemAwake: Bool = false

    // MARK: - Private State

    /// 0 gilt als „keine Assertion aktiv“ — IOKit vergibt nur Werte > 0
    private var displayAssertionID: IOPMAssertionID = 0
    private var systemAssertionID: IOPMAssertionID = 0

    private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        static let displayAwake = "sleepGuard.displayAwake"
        static let systemAwake = "sleepGuard.systemAwake"
    }

    /// Eigene Log-Kategorie, gleiches Muster wie `Logger.menuBar` & Co.
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "xyz.fi5h.Usage4Claude",
        category: "SleepGuard"
    )

    private init() {}

    // MARK: - Lifecycle

    /// Beim Start die gemerkten Schalter erneut anwenden.
    /// Assertions überleben den Prozess nicht, müssen also neu erzeugt werden.
    func restoreFromDefaults() {
        if defaults.bool(forKey: DefaultsKey.displayAwake) {
            setDisplayAwake(true)
        }
        if defaults.bool(forKey: DefaultsKey.systemAwake) {
            setSystemAwake(true)
        }
    }

    /// Beim Beenden alle Assertions freigeben.
    /// Die gemerkten Schalter in den UserDefaults bleiben unangetastet,
    /// damit sie beim nächsten Start wieder greifen.
    func releaseAll() {
        releaseAssertion(&displayAssertionID, label: "NoDisplaySleep")
        releaseAssertion(&systemAssertionID, label: "PreventUserIdleSystemSleep")
        isDisplayAwake = false
        isSystemAwake = false
    }

    // MARK: - Toggles

    /// Bildschirm wach halten an/aus
    func setDisplayAwake(_ enabled: Bool) {
        guard enabled != (displayAssertionID != 0) else {
            // Schon im gewünschten Zustand — trotzdem Flags synchron halten
            isDisplayAwake = enabled
            defaults.set(enabled, forKey: DefaultsKey.displayAwake)
            return
        }

        if enabled {
            let created = createAssertion(
                type: kIOPMAssertionTypeNoDisplaySleep,
                reason: "Claude Max Monitor: Bildschirm wach halten",
                id: &displayAssertionID
            )
            isDisplayAwake = created
        } else {
            releaseAssertion(&displayAssertionID, label: "NoDisplaySleep")
            isDisplayAwake = false
        }

        defaults.set(isDisplayAwake, forKey: DefaultsKey.displayAwake)
    }

    /// Mac wach halten an/aus (Idle-System-Sleep)
    func setSystemAwake(_ enabled: Bool) {
        guard enabled != (systemAssertionID != 0) else {
            isSystemAwake = enabled
            defaults.set(enabled, forKey: DefaultsKey.systemAwake)
            return
        }

        if enabled {
            let created = createAssertion(
                type: kIOPMAssertionTypePreventUserIdleSystemSleep,
                reason: "Claude Max Monitor: Mac wach halten",
                id: &systemAssertionID
            )
            isSystemAwake = created
        } else {
            releaseAssertion(&systemAssertionID, label: "PreventUserIdleSystemSleep")
            isSystemAwake = false
        }

        defaults.set(isSystemAwake, forKey: DefaultsKey.systemAwake)
    }

    /// Umschalten für Menüeinträge
    func toggleDisplayAwake() {
        setDisplayAwake(!isDisplayAwake)
    }

    /// Umschalten für Menüeinträge
    func toggleSystemAwake() {
        setSystemAwake(!isSystemAwake)
    }

    // MARK: - IOKit

    /// Assertion anfordern
    /// - Returns: true, wenn IOKit die Assertion vergeben hat
    private func createAssertion(type: String, reason: String, id: inout IOPMAssertionID) -> Bool {
        var newID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &newID
        )

        guard result == kIOReturnSuccess else {
            Self.log.error("Power-Assertion \(type, privacy: .public) fehlgeschlagen: \(result)")
            return false
        }

        id = newID
        Self.log.notice("Power-Assertion \(type, privacy: .public) aktiv (id \(newID))")
        return true
    }

    /// Assertion freigeben (idempotent)
    private func releaseAssertion(_ id: inout IOPMAssertionID, label: String) {
        guard id != 0 else { return }

        let result = IOPMAssertionRelease(id)
        if result != kIOReturnSuccess {
            Self.log.error("Power-Assertion \(label, privacy: .public) konnte nicht freigegeben werden: \(result)")
        } else {
            Self.log.notice("Power-Assertion \(label, privacy: .public) freigegeben")
        }
        id = 0
    }

    deinit {
        // Singleton lebt bis Prozessende; hier nur als Sicherheitsnetz.
        releaseAssertion(&displayAssertionID, label: "NoDisplaySleep")
        releaseAssertion(&systemAssertionID, label: "PreventUserIdleSystemSleep")
    }
}
