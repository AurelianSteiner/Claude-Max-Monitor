//
//  MenuBarAccountDots.swift
//  Usage4Claude
//
//  Datenquelle der Menüleisten-Punktreihe (`IconDisplayMode.accountDots`).
//
//  Der klassische Menüleisten-Pfad (`DataRefreshManager`) kennt nur das *aktuelle*
//  Konto. Für „ein Punkt je Konto" braucht es alle Konten — die liegen bereits in
//  `DashboardRefreshManager.shared.snapshots`. Diese Klasse abonniert sie einmalig,
//  bringt sie über `AccountUsageSnapshot.ordered(_:mode:)` in *dieselbe* Reihenfolge
//  wie die Übersicht, destilliert jeden Snapshot auf das, was ein Punkt tatsächlich
//  zeigt (Wochen-Ampelstufe + Sitzung aufgebraucht), und legt das Ergebnis hinter
//  einem Lock ab: Der Renderer darf so von jedem Thread lesen, ohne den Main-Thread
//  zu blockieren oder `@Published`-State nebenläufig anzufassen.
//
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import Combine

// MARK: - Zustand eines Punkts

/// Was ein einzelner Menüleisten-Punkt anzeigt — bewusst schon auf die
/// Ampelstufe reduziert (statt roher Prozentzahlen), damit der Icon-Cache
/// nur dann verworfen wird, wenn sich das *Bild* wirklich ändert.
struct MenuBarDotState: Equatable {

    /// Dieselbe dreistufige Skala wie `WeeklyTrafficLight` in der Übersicht —
    /// die Schwellen werden von dort übernommen, damit Menüleiste und Übersicht
    /// nie unterschiedliche Farben für dasselbe Konto zeigen.
    enum WeeklyBucket: String {
        /// noch keine Wochendaten → grau
        case noData = "n"
        /// frisch/unbenutzt (bis einschließlich 5 %) → grün
        case fresh = "g"
        /// in Benutzung (über 5 % und unter 90 %) → blau
        case inUse = "b"
        /// praktisch aufgebraucht (ab 90 %) → rot
        case exhausted = "r"

        static func bucket(for utilization: Double?) -> WeeklyBucket {
            guard let value = utilization else { return .noData }
            if value <= WeeklyTrafficLight.freshThreshold { return .fresh }
            if value < WeeklyTrafficLight.exhaustedThreshold { return .inUse }
            return .exhausted
        }
    }

    /// Füllung des Punkts: Wochenlage des Kontos
    let bucket: WeeklyBucket
    /// Roter Ring außen: das 5-Stunden-Fenster (bzw. Codex primary) ist aufgebraucht
    let sessionExhausted: Bool

    /// Kürzel für den Icon-Cache-Key in `MenuBarUI` („g", „b!", …)
    var cacheToken: String { sessionExhausted ? "\(bucket.rawValue)!" : bucket.rawValue }
}

// MARK: - Store

/// Thread-sicherer Zwischenspeicher der Punktreihe.
///
/// Schreiben passiert ausschließlich auf dem Main-Thread (Combine-Abos mit
/// `receive(on: .main)`), Lesen über `currentStates()` von überall — deshalb das
/// `NSLock` statt eines `DispatchQueue.main.sync`, das aus dem Renderer heraus
/// im ungünstigen Fall verklemmen könnte.
final class MenuBarAccountDots {

    /// Menüleiste und (später) andere Leser teilen sich einen Stand
    static let shared = MenuBarAccountDots()

    /// Meldet jede *tatsächliche* Änderung der Punktreihe, bereits auf dem Main-Thread.
    /// `MenuBarUI` hängt sich hier ein und zeichnet das Statusleisten-Symbol neu.
    var didChange: AnyPublisher<Void, Never> { changeSubject.eraseToAnyPublisher() }

    private let changeSubject = PassthroughSubject<Void, Never>()
    private let lock = NSLock()
    private var states: [MenuBarDotState] = []
    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false
    /// Hält die Dashboard-Datenquelle am Leben, solange der Punktmodus aktiv ist.
    /// Das Flag garantiert, dass `activate()`/`deactivate()` paarweise laufen —
    /// der Referenzzähler dort wird auch vom Übersichtsfenster benutzt.
    private var isDrivingDashboardRefresh = false

    private init() {}

    // MARK: - Lifecycle

    /// Beobachtung starten (idempotent). Muss auf dem Main-Thread aufgerufen werden;
    /// `MenuBarUI` tut das beim Aufbau der Statusleiste.
    func start() {
        guard !isStarted else { return }
        isStarted = true

        DashboardRefreshManager.shared.$snapshots
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshots in
                self?.apply(snapshots, mode: UserSettings.shared.dashboardSortMode)
            }
            .store(in: &cancellables)

        // Sortierwunsch: Die Punktreihe muss auch dann neu sortieren, wenn sich
        // *nur* der Modus ändert — sonst behielte die Menüleiste bis zum nächsten
        // Refresh die alte Folge, während die Übersicht schon umsortiert hat.
        // Der Modus kommt aus dem Sink (ein `@Published` meldet sich im `willSet`,
        // gelesen würde also unter Umständen noch der alte Wert).
        UserSettings.shared.$dashboardSortMode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.apply(DashboardRefreshManager.shared.snapshots, mode: mode)
            }
            .store(in: &cancellables)

        // Der Punktmodus braucht Daten *aller* Konten. Ohne geöffnete Übersicht
        // holt sie sonst niemand — deshalb hängt sich die Menüleiste als
        // zusätzlicher „Zuschauer" an den DashboardRefreshManager.
        UserSettings.shared.$iconDisplayMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.syncDashboardRefresh(for: mode)
            }
            .store(in: &cancellables)

        apply(DashboardRefreshManager.shared.snapshots, mode: UserSettings.shared.dashboardSortMode)
        syncDashboardRefresh(for: UserSettings.shared.iconDisplayMode)
    }

    // MARK: - Lesen

    /// Aktueller Stand der Punktreihe.
    /// Leeres Ergebnis heißt „noch nichts zu zeigen" — die Aufrufer fallen dann
    /// bewusst auf die bisherige Ring-Darstellung zurück, statt eine Reihe
    /// nichtssagender grauer Punkte in die Menüleiste zu hängen.
    func currentStates() -> [MenuBarDotState] {
        lock.lock()
        defer { lock.unlock() }
        return states
    }

    // MARK: - Schreiben (nur Main-Thread)

    private func apply(_ snapshots: [AccountUsageSnapshot], mode: DashboardSortMode) {
        // Dieselbe Reihenfolge wie die Übersicht — die Regel steht nur einmal,
        // in `AccountUsageSnapshot.ordered(_:mode:)`.
        let ordered = AccountUsageSnapshot.ordered(snapshots, mode: mode)

        // Solange kein einziges Konto Daten geliefert hat, bleibt die Reihe leer.
        let hasAnyData = ordered.contains { $0.hasData }
        let next: [MenuBarDotState] = hasAnyData
            ? ordered.map {
                MenuBarDotState(
                    bucket: .bucket(for: $0.weeklyPeakUtilization),
                    sessionExhausted: $0.sessionExhausted
                )
            }
            : []

        lock.lock()
        let changed = next != states
        if changed { states = next }
        lock.unlock()

        if changed { changeSubject.send() }
    }

    private func syncDashboardRefresh(for mode: IconDisplayMode) {
        let needsData = (mode == .accountDots)
        guard needsData != isDrivingDashboardRefresh else { return }
        isDrivingDashboardRefresh = needsData

        if needsData {
            DashboardRefreshManager.shared.activate()
        } else {
            DashboardRefreshManager.shared.deactivate()
        }
    }
}
