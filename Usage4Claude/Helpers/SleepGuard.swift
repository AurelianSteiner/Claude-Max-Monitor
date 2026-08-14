//
//  SleepGuard.swift
//  Usage4Claude
//
//  Hält Bildschirm und Mac wach — wie Amphetamine/Caffeine, aber ohne
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

/// Wach-Wächter: verwaltet die Power-Assertions der App.
///
/// Nach außen gibt es genau EINEN Schalter — „Bleib wach“
/// (`DashboardView.stayAwakeToggle`). Er setzt intern BEIDE Assertions
/// gleichzeitig:
///
/// - `kIOPMAssertionTypeNoDisplaySleep` — der Bildschirm schaltet sich nicht
///   von selbst aus.
/// - `kIOPMAssertionTypePreventUserIdleSystemSleep` — das System geht bei
///   Untätigkeit nicht in den Ruhezustand.
///
/// Früher waren das zwei getrennte Schalter („Bildschirm an“ / „Always On“).
/// In der Praxis wollte niemand nur eines von beidem — wer wach halten will,
/// will wach halten. Die alten UserDefaults-Schlüssel werden beim ersten Start
/// still übernommen: war EINER der beiden an, startet der neue Schalter an
/// (siehe `storedAwakeFlag()`).
///
/// Alles gilt nur, solange die App läuft: `releaseAll()` beim Beenden gibt die
/// Assertions frei, danach greifen wieder die Systemeinstellungen. Zuklappen
/// (Clamshell) schläfert den Mac trotzdem ein — siehe Dateikopf.
final class SleepGuard: ObservableObject {

    // MARK: - Singleton

    static let shared = SleepGuard()

    // MARK: - Published State

    /// „Bleib wach“ ist an: Bildschirm UND Mac werden wach gehalten
    @Published private(set) var isAwake: Bool = false

    // MARK: - Private State

    /// 0 gilt als „keine Assertion aktiv“ — IOKit vergibt nur Werte > 0
    private var displayAssertionID: IOPMAssertionID = 0
    private var systemAssertionID: IOPMAssertionID = 0

    private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        /// Der eine Schalter von heute
        static let awake = "sleepGuard.awake"
        /// Alte Schlüssel der zwei getrennten Schalter. Sie werden nur noch
        /// gelesen (einmalige Übernahme), nie mehr geschrieben — wer auf eine
        /// ältere Version zurückgeht, findet seine Werte unverändert vor.
        static let legacyDisplayAwake = "sleepGuard.displayAwake"
        static let legacySystemAwake = "sleepGuard.systemAwake"
    }

    /// Eigene Log-Kategorie, gleiches Muster wie `Logger.menuBar` & Co.
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "xyz.fi5h.Usage4Claude",
        category: "SleepGuard"
    )

    private init() {}

    // MARK: - Lifecycle

    /// Beim Start den gemerkten Schalter erneut anwenden.
    /// Assertions überleben den Prozess nicht, müssen also neu erzeugt werden.
    func restoreFromDefaults() {
        if storedAwakeFlag() {
            setAwake(true)
        }
    }

    /// Liest den gemerkten Zustand — mit stiller, einmaliger Übernahme der
    /// alten zwei Schlüssel: Gibt es den neuen Schlüssel noch nicht, gilt
    /// „an“, wenn EINER der beiden alten Schalter an war. Das Ergebnis wird
    /// sofort unter dem neuen Schlüssel gemerkt, danach zählt nur noch der.
    private func storedAwakeFlag() -> Bool {
        if defaults.object(forKey: DefaultsKey.awake) != nil {
            return defaults.bool(forKey: DefaultsKey.awake)
        }
        let migrated = defaults.bool(forKey: DefaultsKey.legacyDisplayAwake)
            || defaults.bool(forKey: DefaultsKey.legacySystemAwake)
        defaults.set(migrated, forKey: DefaultsKey.awake)
        if migrated {
            Self.log.notice("Alte Wach-Schalter übernommen: „Bleib wach“ startet an")
        }
        return migrated
    }

    /// Beim Beenden alle Assertions freigeben.
    /// Der gemerkte Schalter in den UserDefaults bleibt unangetastet,
    /// damit er beim nächsten Start wieder greift.
    func releaseAll() {
        releaseAssertion(&displayAssertionID, label: "NoDisplaySleep")
        releaseAssertion(&systemAssertionID, label: "PreventUserIdleSystemSleep")
        isAwake = false
    }

    // MARK: - Toggle

    /// „Bleib wach“ an/aus — setzt bzw. löst immer BEIDE Assertions.
    func setAwake(_ enabled: Bool) {
        let hadAssertions = displayAssertionID != 0 || systemAssertionID != 0
        guard enabled != hadAssertions else {
            // Schon im gewünschten Zustand — trotzdem Flag synchron halten
            isAwake = enabled
            defaults.set(enabled, forKey: DefaultsKey.awake)
            return
        }

        if enabled {
            let displayCreated = createAssertion(
                type: kIOPMAssertionTypeNoDisplaySleep,
                reason: "Claude Max Monitor: Bildschirm wach halten",
                id: &displayAssertionID
            )
            let systemCreated = createAssertion(
                type: kIOPMAssertionTypePreventUserIdleSystemSleep,
                reason: "Claude Max Monitor: Mac wach halten",
                id: &systemAssertionID
            )
            isAwake = displayCreated || systemCreated
        } else {
            releaseAssertion(&displayAssertionID, label: "NoDisplaySleep")
            releaseAssertion(&systemAssertionID, label: "PreventUserIdleSystemSleep")
            isAwake = false
        }

        defaults.set(isAwake, forKey: DefaultsKey.awake)

        // Die Menüleiste zeichnet die Wach-Kapsel um die Punktreihe — sie muss
        // sofort mitziehen. `.settingsChanged` löst in `MenuBarManager` genau
        // das aus: Icon-Cache leeren + neu zeichnen.
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    /// Umschalten für den Kopf der Übersicht
    func toggleAwake() {
        setAwake(!isAwake)
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
