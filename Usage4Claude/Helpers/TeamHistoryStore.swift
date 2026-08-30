//
//  TeamHistoryStore.swift
//  Usage4Claude
//
//  Team-Übersicht — die Verläufe. Holt je Person einmal pro Sitzung den
//  7-Tage-Verlauf vom Server (GET /members/<id>/history) und hält ihn im
//  Speicher: Die Detailansicht zeichnet daraus ihre Verlaufslinien, die
//  Liste ihren Trend-Pfeil.
//
//  Geladen wird träge — erst wenn eine Ansicht den Verlauf einer Person
//  wirklich braucht (`load`). Ein Fehlschlag wird ein paar Minuten nicht
//  wiederholt: Läuft draußen noch ein Server ohne Verlaufs-Endpunkt, soll
//  jede Zeile genau einmal fragen, nicht bei jedem Neuzeichnen.
//
//  Thread-Regel wie im übrigen Projekt: Öffentliche Methoden vom
//  Hauptthread, `@Published` wird nur auf dem Hauptthread geschrieben.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Combine
import Foundation
import OSLog

final class TeamHistoryStore: ObservableObject {

    /// Gemeinsame Instanz — Liste und Detailansicht teilen sich die Verläufe
    static let shared = TeamHistoryStore()

    // MARK: - Veröffentlichter Zustand

    /// Verlauf je Person (Schlüssel: `TeamReport.historyMemberId`),
    /// aufsteigend nach Zeit. Ein leeres Array ist eine gültige Antwort:
    /// Die Person hat schlicht noch keinen Verlauf.
    @Published private(set) var histories: [String: [TeamHistorySample]] = [:]

    // MARK: - Konfiguration

    /// Wie viele Tage die Ansichten zeigen
    static let days = 7
    /// Wie lange ein Fehlschlag nicht wiederholt wird
    private static let retryInterval: TimeInterval = 5 * 60
    /// Wie weit die „vor 24 Stunden"-Meldung vom Ziel abweichen darf.
    /// Großzügig, weil Rechner nachts aus sind — eine 30 Stunden alte
    /// Meldung beantwortet „mehr oder weniger als gestern?" immer noch.
    static let trendTolerance: TimeInterval = 12 * 60 * 60

    // MARK: - Intern

    private var inFlight: Set<String> = []
    private var failedAt: [String: Date] = [:]
    private var cancellables = Set<AnyCancellable>()

    /// Zählt Verbindungswechsel — Antworten einer alten Verbindung werden
    /// verworfen, damit kein fremdes Team in den frischen Zustand schreibt.
    private var generation = 0

    private init() {
        NotificationCenter.default.publisher(for: .teamServerChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reset() }
            .store(in: &cancellables)
    }

    // MARK: - Abfragen

    /// Der geladene Verlauf einer Person — `nil`, solange (noch) keiner da ist.
    func samples(for memberId: String) -> [TeamHistorySample]? {
        histories[memberId]
    }

    /// Wochenlage jetzt gegen ~24 Stunden zuvor. `nil`, wenn der Verlauf
    /// fehlt, die Meldung keinen Wochenwert trägt, nichts nahe genug am
    /// Vergleichszeitpunkt liegt — oder die Meldung selbst veraltet ist:
    /// Ein Pfeil an gestrigen Zahlen wäre eine Aussage über vorgestern.
    func weeklyTrend(for report: TeamReport, now: Date = Date()) -> TeamWeeklyTrend? {
        guard !report.isStale(at: now),
              let current = TeamSummary.weeklyPercent(of: report),
              let samples = histories[report.historyMemberId],
              let past = samples.nearestSample(to: now.addingTimeInterval(-24 * 60 * 60),
                                              tolerance: Self.trendTolerance),
              let previous = past.limits.filter(TeamSummary.isWeekly).map(\.percent).max()
        else { return nil }
        return TeamWeeklyTrend(previous: previous, current: current)
    }

    // MARK: - Laden

    /// Holt den Verlauf einer Person, falls er noch fehlt. Mehrfachaufrufe
    /// sind billig: Geladenes und Laufendes wird übersprungen, ein
    /// Fehlschlag erst nach ein paar Minuten wiederholt.
    func load(memberId: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !memberId.isEmpty,
              histories[memberId] == nil,
              !inFlight.contains(memberId) else { return }
        if let failed = failedAt[memberId],
           Date().timeIntervalSince(failed) < Self.retryInterval { return }
        guard let client = TeamServerConnection.shared.client else { return }

        inFlight.insert(memberId)
        let generation = self.generation
        Task { [weak self] in
            do {
                let samples = try await client.history(memberId: memberId, days: Self.days)
                await MainActor.run {
                    guard let self, generation == self.generation else { return }
                    self.inFlight.remove(memberId)
                    self.failedAt[memberId] = nil
                    self.histories[memberId] = samples
                }
            } catch {
                await MainActor.run {
                    guard let self, generation == self.generation else { return }
                    self.inFlight.remove(memberId)
                    self.failedAt[memberId] = Date()
                    // Nur leise notiert: Ohne Verlauf fehlen Linie und Pfeil,
                    // die Übersicht selbst funktioniert unverändert.
                    Logger.team.debug("Verlauf von \(memberId, privacy: .public) nicht ladbar")
                }
            }
        }
    }

    // MARK: - Intern

    /// Verbindungswechsel: alles vergessen — anderes Team, andere Verläufe.
    private func reset() {
        generation += 1
        histories = [:]
        inFlight = []
        failedAt = [:]
    }
}
