//
//  TeamReportStore.swift
//  Usage4Claude
//
//  Team-Übersicht — Teil 4: die Meldungen. EINE Quelle der Wahrheit für
//  alle Ansichten, mit zwei möglichen Wegen dahinter:
//
//    • Server: Besteht eine Verbindung zum Team-Relay
//      (`TeamServerConnection`), holt `refresh()` GET /reports — Super und
//      Admin bekommen alle Meldungen, Mitglieder nur die eigene. Welcher
//      Weg gerade gilt, sagt `source` (Server / Ordner / keiner).
//    • Ordner (Rückfallweg): Liest alle JSON-Dateien des geteilten
//      Ordners, wirft alles weg, was nicht zum eigenen Team gehört oder
//      kaputt ist. Rein lesend — geschrieben wird nur, wenn jemand eine
//      Meldung von Hand einfügt (`importPasted(_:)`, Ordner-Weg).
//
//  Veröffentlicht wird in beiden Fällen dasselbe: `[TeamReport]`,
//  neueste Meldung zuerst, eine pro Person.
//
//  Aktualisiert wird sparsam — der Ordner liegt in iCloud/Dropbox, und
//  ständiges Nachsehen kostet dort mehr als hier: alle zwei Minuten, beim
//  Aktivwerden der App und wenn sich Team oder Ordner ändern. Und all das
//  nur, solange eine Ansicht die Meldungen auch zeigt (`activate()` /
//  `deactivate()`); sind Fenster und Einstellungen zu, ruht der Zeitgeber.
//
//  Thread-Regel wie im übrigen Projekt: Öffentliche Methoden werden vom
//  Hauptthread aufgerufen, das Lesen der Dateien läuft auf einer eigenen
//  Queue, alle `@Published` werden auf dem Hauptthread geschrieben.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import AppKit
import Combine
import OSLog

// MARK: - Fehler beim Einfügen

/// Warum eine eingefügte Meldung nicht übernommen wurde.
enum TeamImportError: Error, Equatable {
    /// Kein Team eingerichtet
    case noTeam
    /// Kein Ordner gewählt oder gerade nicht erreichbar
    case noFolder
    /// Text ist kein gültiges JSON im Meldeformat
    case invalidJSON
    /// Text ist größer als erlaubt
    case tooLarge
    /// Meldung gehört zu einem anderen Team
    case wrongTeam
    /// Datei ließ sich nicht in den Ordner schreiben
    case writeFailed
}

// MARK: - Datenquelle

/// Woher die Meldungen gerade kommen — die Oberfläche zeigt das als
/// Verbindungszustand an („Server", „Ordner", nichts eingerichtet).
enum TeamReportSource: Equatable {
    /// Verbindung zum Team-Relay (`TeamServerConnection`)
    case server
    /// Geteilter Ordner (Team + Ordner eingerichtet, keine Server-Verbindung)
    case folder
    /// Weder noch — die Übersicht ist nicht eingerichtet
    case none
}

final class TeamReportStore: ObservableObject {

    /// Gemeinsame Instanz — Menü, Übersicht und Einstellungen teilen sich die Daten
    static let shared = TeamReportStore()

    // MARK: - Veröffentlichter Zustand

    /// Alle Meldungen des Teams, neueste zuerst
    @Published private(set) var reports: [TeamReport] = []
    /// Wann zuletzt in den Ordner geschaut wurde
    @Published private(set) var lastRefreshAt: Date?
    /// Läuft gerade ein Lesevorgang?
    @Published private(set) var isRefreshing = false
    /// Ordner ist eingerichtet, war beim letzten Versuch aber nicht lesbar
    @Published private(set) var folderUnavailable = false
    /// Server-Verbindung besteht, der letzte Abruf schlug aber fehl
    /// (Netz weg, Token abgelehnt, Serverfehler)
    @Published private(set) var serverUnavailable = false

    // MARK: - Konfiguration

    /// Abstand der automatischen Aktualisierung
    private static let autoInterval: TimeInterval = 120
    /// Mindestabstand zweier Lesevorgänge (gegen Sturmläufe aus mehreren Auslösern)
    private static let minimumGap: TimeInterval = 10
    /// Mehr Dateien sieht sich die App in einem fremden Ordner nicht an
    private static let maxFilesScanned = 500

    // MARK: - Intern

    private let io = DispatchQueue(label: "xyz.fi5h.Usage4Claude.team-reports", qos: .utility)
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Zählt Konfigurationswechsel (Server verbunden/getrennt, Team oder
    /// Ordner geändert). Jeder Lesevorgang merkt sich den Stand beim Start
    /// und verwirft sein Ergebnis, wenn er inzwischen nicht mehr stimmt —
    /// sonst könnte ein noch laufender Server-Abruf nach dem Trennen
    /// Server-Meldungen in die Ordner-Ansicht schieben (oder umgekehrt).
    private var configurationGeneration = 0

    /// Wie viele Ansichten die Meldungen gerade zeigen (Team-Fenster,
    /// Einstellungskarte). Der geteilte Ordner liegt in iCloud oder Dropbox —
    /// dort nachzusehen, während niemand hinschaut, kostet Netz und Akku und
    /// bringt nichts: Jede Ansicht liest beim Erscheinen ohnehin neu ein.
    private var viewers = 0

    private init() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.viewers > 0 else { return }
                self.refresh()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .teamConfigChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleConfigurationChange() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .teamFolderChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleConfigurationChange() }
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

    /// Woher die Meldungen gerade kommen. Die Server-Verbindung hat Vorrang;
    /// der Ordner bleibt der Rückfallweg, wenn keine besteht.
    var source: TeamReportSource {
        if TeamServerConnection.shared.isConnected { return .server }
        if TeamStore.shared.hasTeam && TeamFolderAccess.shared.hasFolder { return .folder }
        return .none
    }

    /// Ist die Team-Übersicht überhaupt eingerichtet (egal auf welchem Weg)?
    var isConfigured: Bool {
        source != .none
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

    /// Holt die Meldungen neu — vom Server, wenn eine Verbindung besteht,
    /// sonst aus dem geteilten Ordner.
    /// - Parameter force: Ignoriert den Mindestabstand (z. B. Knopf „Aktualisieren").
    func refresh(force: Bool = false) {
        dispatchPrecondition(condition: .onQueue(.main))

        let source = self.source
        guard source != .none else {
            reports = []
            folderUnavailable = false
            serverUnavailable = false
            return
        }
        guard !isRefreshing else { return }
        if !force, let last = lastRefreshAt, Date().timeIntervalSince(last) < Self.minimumGap {
            return
        }

        switch source {
        case .server: refreshFromServer()
        case .folder: refreshFromFolder()
        case .none:   break
        }
    }

    /// Server-Weg: GET /reports über den Client der Verbindung. Super und
    /// Admin bekommen alle Meldungen, Mitglieder nur die eigene — das
    /// entscheidet der Server, hier wird nur veröffentlicht.
    private func refreshFromServer() {
        guard let client = TeamServerConnection.shared.client else {
            serverUnavailable = true
            return
        }

        isRefreshing = true
        folderUnavailable = false
        let generation = configurationGeneration
        Task { [weak self] in
            do {
                let fetched = try await client.reports()
                await MainActor.run {
                    guard let self, generation == self.configurationGeneration else { return }
                    self.isRefreshing = false
                    self.lastRefreshAt = Date()
                    self.serverUnavailable = false
                    // Wie beim Ordner: pro Person nur die jüngste Meldung.
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

    /// Ordner-Weg (Rückfall): alle JSON-Dateien des geteilten Ordners lesen.
    private func refreshFromFolder() {
        guard let teamId = TeamStore.shared.teamId else { return }

        isRefreshing = true
        serverUnavailable = false
        let generation = configurationGeneration
        io.async { [weak self] in
            guard let self else { return }
            let loaded = Self.readReports(teamId: teamId)
            DispatchQueue.main.async {
                guard generation == self.configurationGeneration else { return }
                self.isRefreshing = false
                self.lastRefreshAt = Date()
                if let loaded {
                    self.folderUnavailable = false
                    guard self.reports != loaded else { return }
                    self.reports = loaded
                } else {
                    // Ordner nicht lesbar: alte Karten stehen lassen und das
                    // Problem melden, statt die Übersicht leer zu räumen.
                    self.folderUnavailable = true
                }
            }
        }
    }

    // MARK: - Eingefügte Meldung übernehmen

    /// Übernimmt eine per Nachricht geschickte Meldung: prüfen wie eine Datei
    /// aus dem Ordner, dann selbst in den Ordner schreiben. So bekommt auch
    /// jemand ohne Zugriff auf die Freigabe seine Karte.
    /// - Parameter text: Der eingefügte JSON-Text
    /// - Returns: Die übernommene Meldung, oder der Grund der Ablehnung.
    @discardableResult
    func importPasted(_ text: String) -> Result<TeamReport, TeamImportError> {
        dispatchPrecondition(condition: .onQueue(.main))

        guard let teamId = TeamStore.shared.teamId else { return .failure(.noTeam) }
        guard TeamFolderAccess.shared.hasFolder else { return .failure(.noFolder) }

        var report: TeamReport
        do {
            report = try TeamReport.parse(text)
        } catch TeamReportError.tooLarge {
            return .failure(.tooLarge)
        } catch {
            return .failure(.invalidJSON)
        }

        guard report.teamId.caseInsensitiveCompare(teamId) == .orderedSame else {
            Logger.team.notice("Eingefügte Meldung gehört zu einem anderen Team")
            return .failure(.wrongTeam)
        }

        report.fileName = report.preferredFileName

        let fileName = report.fileName
        let written: Bool? = TeamFolderAccess.shared.withFolder { folder -> Bool in
            do {
                let data = try report.canonicalJSONData()
                try data.write(to: folder.appendingPathComponent(fileName), options: .atomic)
                return true
            } catch {
                Logger.team.error("Meldung konnte nicht geschrieben werden: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }

        guard let written else { return .failure(.noFolder) }
        guard written else { return .failure(.writeFailed) }

        Logger.team.notice("Eingefügte Meldung übernommen")
        refresh(force: true)
        return .success(report)
    }

    // MARK: - Lesen

    /// Liest alle Meldungen des Teams aus dem Ordner.
    /// - Returns: Die Meldungen, oder `nil`, wenn der Ordner nicht lesbar war.
    private static func readReports(teamId: String) -> [TeamReport]? {
        let fileManager = FileManager.default

        // Doppelt optional, und das mit Absicht: Das äußere `nil` heißt „kein
        // Zugriff auf den Ordner", das innere „Ordner da, aber nicht auflistbar"
        // (Rechte, Freigabe halb eingehängt). Beide bedeuten dasselbe für die
        // Oberfläche — nicht aber „Ordner ist leer", was ein `[]` behaupten würde.
        let found: [TeamReport]? = TeamFolderAccess.shared.withFolder { folder -> [TeamReport]? in
            guard let urls = try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else {
                Logger.team.error("Team-Ordner ließ sich nicht auflisten")
                return nil
            }

            // In einem gemeinsam genutzten Ordner liegt viel herum. Dateien mit
            // passendem Namen zuerst ansehen, damit die Obergrenze unten nicht
            // ausgerechnet die echten Meldungen abschneidet.
            let candidates = urls
                .filter { $0.pathExtension.lowercased() == "json" }
                .sorted { lhs, rhs in
                    let lhsMatches = TeamReport.looksLikeReportFile(lhs.lastPathComponent, teamId: teamId)
                    let rhsMatches = TeamReport.looksLikeReportFile(rhs.lastPathComponent, teamId: teamId)
                    if lhsMatches != rhsMatches { return lhsMatches }
                    return lhs.lastPathComponent < rhs.lastPathComponent
                }

            var reports: [TeamReport] = []
            for url in candidates.prefix(maxFilesScanned) {

                // Nur gewöhnliche Dateien. Ordner und Sonderdateien (eine
                // benannte Pipe namens „x.json" ließe das Öffnen unten ewig
                // warten) fallen hier raus; die Werte stehen bereits aus dem
                // Auflisten bereit, das kostet also keinen weiteren Zugriff.
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                // Große Dateien gar nicht erst öffnen.
                if let size = values?.fileSize, size > TeamReport.maxBytes { continue }

                guard let data = boundedContents(of: url) else { continue }

                do {
                    let report = try TeamReport.parse(data, fileName: url.lastPathComponent)
                    // Fremde Teams im selben Ordner: still überspringen.
                    guard report.teamId.caseInsensitiveCompare(teamId) == .orderedSame else { continue }
                    reports.append(report)
                } catch {
                    // Eine kaputte Datei darf die anderen nicht mitreißen.
                    Logger.team.debug("Meldung übersprungen: \(url.lastPathComponent, privacy: .public)")
                    continue
                }
            }
            return reports
        } ?? nil

        guard let found else { return nil }
        return TeamReport.deduplicatedByPerson(found)
    }

    /// Liest höchstens `TeamReport.maxBytes + 1` Bytes einer Datei.
    ///
    /// Zwei Gründe für den Umweg über `FileHandle` statt `Data(contentsOf:)`:
    /// Zum einen ist die Größenangabe aus `resourceValues` nicht garantiert —
    /// fehlt sie, läse `Data(contentsOf:)` eine beliebig große Datei komplett
    /// ein. Zum anderen bildet `Data(contentsOf:)` große Dateien in den
    /// Speicher ab; schrumpft die Datei währenddessen (Dropbox schreibt sie
    /// gerade neu), stirbt der Prozess an SIGBUS. Ein gewöhnliches `read`
    /// liefert in dem Fall einfach weniger Bytes, und die kaputte Datei fällt
    /// beim Auswerten durch.
    ///
    /// Das eine Byte über der Grenze ist Absicht: Damit ist eine zu große
    /// Datei am Ergebnis erkennbar und wird von `TeamReport.parse` abgelehnt,
    /// statt abgeschnitten als „kaputtes JSON" zu gelten.
    private static func boundedContents(of url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: TeamReport.maxBytes + 1)) ?? nil
    }

    // MARK: - Zeitgeber

    private func handleConfigurationChange() {
        // Laufende Lesevorgänge gehören zur alten Konfiguration: Ihr Ergebnis
        // wird verworfen (Generation stimmt nicht mehr), und `isRefreshing`
        // wird hier zurückgesetzt, damit es den erzwungenen Neuabruf der
        // neuen Quelle nicht blockiert.
        configurationGeneration += 1
        isRefreshing = false

        updateTimer()
        if isConfigured {
            refresh(force: true)
        } else {
            reports = []
            folderUnavailable = false
            serverUnavailable = false
            lastRefreshAt = nil
        }
    }

    /// Der Zeitgeber läuft nur, solange eine Quelle eingerichtet ist (Server
    /// oder Team + Ordner) **und** jemand die Meldungen ansieht.
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
