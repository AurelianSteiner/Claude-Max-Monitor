//
//  TeamReportStore.swift
//  Usage4Claude
//
//  Team-Übersicht — die Meldungen. EINE Quelle der Wahrheit für alle
//  Ansichten, und dahinter genau EIN Weg: der Team-Server. Besteht eine
//  Verbindung (`TeamServerConnection`), holt `refresh()` GET /reports —
//  Super und Admin bekommen alle Meldungen, Mitglieder nur die eigene.
//
//  Veröffentlicht wird `[TeamReport]`, eine Meldung pro Person.
//
//  Aktualisiert wird sparsam: alle zwei Minuten, beim Aktivwerden der App
//  und wenn sich die Verbindung ändert. Und all das nur, solange eine
//  Ansicht die Meldungen auch zeigt (`activate()` / `deactivate()`); sind
//  Fenster und Einstellungen zu, ruht der Zeitgeber.
//
//  Thread-Regel wie im übrigen Projekt: Öffentliche Methoden werden vom
//  Hauptthread aufgerufen, alle `@Published` werden auf dem Hauptthread
//  geschrieben.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import AppKit
import Combine
import OSLog

final class TeamReportStore: ObservableObject {

    /// Gemeinsame Instanz — Menü, Übersicht und Einstellungen teilen sich die Daten
    static let shared = TeamReportStore()

    // MARK: - Veröffentlichter Zustand

    /// Alle Meldungen des Teams, neueste zuerst
    @Published private(set) var reports: [TeamReport] = []
    /// Wann zuletzt beim Server nachgefragt wurde
    @Published private(set) var lastRefreshAt: Date?
    /// Läuft gerade ein Abruf?
    @Published private(set) var isRefreshing = false
    /// Server-Verbindung besteht, der letzte Abruf schlug aber fehl
    /// (Netz weg, Token abgelehnt, Serverfehler)
    @Published private(set) var serverUnavailable = false

    // MARK: - Konfiguration

    /// Abstand der automatischen Aktualisierung
    private static let autoInterval: TimeInterval = 120
    /// Mindestabstand zweier Abrufe (gegen Sturmläufe aus mehreren Auslösern)
    private static let minimumGap: TimeInterval = 10

    // MARK: - Intern

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Zählt Verbindungswechsel. Jeder Abruf merkt sich den Stand beim Start
    /// und verwirft sein Ergebnis, wenn er inzwischen nicht mehr stimmt —
    /// sonst könnte ein noch laufender Abruf nach dem Trennen alte Meldungen
    /// in die frische Ansicht schieben.
    private var configurationGeneration = 0

    /// Wie viele Ansichten die Meldungen gerade zeigen (Team-Fenster,
    /// Einstellungskarte). Ohne Zuschauer ruht der Zeitgeber — ein Abruf,
    /// dessen Ergebnis niemand sieht, kostet nur Netz und Akku.
    private var viewers = 0

    private init() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.viewers > 0 else { return }
                self.refresh()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .teamServerChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleConfigurationChange() }
            .store(in: &cancellables)

        // Beim Erzeugen wird noch nichts gelesen: Erzeugt wird dieser Speicher
        // von der ersten Ansicht, die ihn zeigt, und die ruft gleich darauf
        // `activate()` auf.
    }

    // MARK: - Abfragen

    /// Ist die Team-Übersicht eingerichtet (= Server-Verbindung vorhanden)?
    var isConfigured: Bool {
        TeamServerConnection.shared.isConnected
    }

    /// Meldungen, die älter als 24 Stunden sind
    var staleReports: [TeamReport] {
        reports.filter(\.isStale)
    }

    // MARK: - Aktualisieren

    /// Für `onAppear`: sofort nachsehen und den Zeitgeber laufen lassen.
    /// Jedes `activate()` braucht genau ein `deactivate()`.
    func activate() {
        dispatchPrecondition(condition: .onQueue(.main))
        viewers += 1
        updateTimer()
        refresh()
    }

    /// Für `onDisappear`: Zeigt niemand mehr hin, ruht der Zeitgeber.
    func deactivate() {
        dispatchPrecondition(condition: .onQueue(.main))
        viewers = max(0, viewers - 1)
        updateTimer()
    }

    /// Holt die Meldungen neu vom Server.
    /// - Parameter force: Ignoriert den Mindestabstand (z. B. Knopf „Aktualisieren").
    func refresh(force: Bool = false) {
        dispatchPrecondition(condition: .onQueue(.main))

        guard let client = TeamServerConnection.shared.client else {
            reports = []
            serverUnavailable = false
            return
        }
        guard !isRefreshing else { return }
        if !force, let last = lastRefreshAt, Date().timeIntervalSince(last) < Self.minimumGap {
            return
        }

        isRefreshing = true
        let generation = configurationGeneration
        Task { [weak self] in
            do {
                let fetched = try await client.reports()
                await MainActor.run {
                    guard let self, generation == self.configurationGeneration else { return }
                    self.isRefreshing = false
                    self.lastRefreshAt = Date()
                    self.serverUnavailable = false
                    // Pro Person nur die jüngste Meldung.
                    let cleaned = TeamReport.deduplicatedByPerson(fetched)
                    guard self.reports != cleaned else { return }
                    self.reports = cleaned
                }
            } catch {
                await MainActor.run {
                    guard let self, generation == self.configurationGeneration else { return }
                    // Alte Karten stehen lassen und das Problem melden,
                    // statt die Übersicht leer zu räumen.
                    self.isRefreshing = false
                    self.lastRefreshAt = Date()
                    self.serverUnavailable = true
                    Logger.team.error("Server-Meldungen nicht ladbar: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    // MARK: - Zeitgeber

    private func handleConfigurationChange() {
        // Laufende Abrufe gehören zur alten Verbindung: Ihr Ergebnis wird
        // verworfen (Generation stimmt nicht mehr), und `isRefreshing` wird
        // hier zurückgesetzt, damit es den erzwungenen Neuabruf nicht blockiert.
        configurationGeneration += 1
        isRefreshing = false

        updateTimer()
        if isConfigured {
            refresh(force: true)
        } else {
            reports = []
            serverUnavailable = false
            lastRefreshAt = nil
        }
    }

    /// Der Zeitgeber läuft nur, solange eine Verbindung besteht **und**
    /// jemand die Meldungen ansieht.
    private func updateTimer() {
        dispatchPrecondition(condition: .onQueue(.main))

        guard isConfigured, viewers > 0 else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }

        let timer = Timer(timeInterval: Self.autoInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // `.common`, damit die Übersicht auch während eines geöffneten Menüs
        // aktuell bleibt.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
