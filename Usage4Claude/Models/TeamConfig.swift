//
//  TeamConfig.swift
//  Usage4Claude
//
//  Team-Übersicht — Teil 1: das Team selbst.
//
//  Ein „Team" ist hier bewusst nichts weiter als ein Name plus eine kurze,
//  vorlesbare ID. Es gibt keinen Server: Die ID taucht im Dateinamen und im
//  Inhalt jeder Meldung auf und dient nur als Plausibilitätsprüfung, ob eine
//  Datei im geteilten Ordner überhaupt zu diesem Team gehört (in einem
//  gemeinsamen Dropbox-/iCloud-Ordner liegen schnell auch fremde Dateien).
//
//  Diese Datei bleibt absichtlich frei von AppKit, UserSettings und
//  Localization — sie hängt im SwiftPM-Testtarget (siehe Package.swift).
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation
import Combine

// MARK: - Persistenz-Schlüssel

/// UserDefaults-Schlüssel der Team-Übersicht.
///
/// Wie im Rest des Projekts bekommt der DEBUG-Build ein eigenes Präfix, damit
/// eine Entwicklerversion nicht in die Konfiguration der installierten App
/// hineinschreibt (siehe `AccountStore`, `UserSettings`).
enum TeamDefaultsKeys {
    #if DEBUG
    private static let prefix = "DEBUG_"
    #else
    private static let prefix = ""
    #endif

    /// JSON-kodierte `TeamConfig`
    static let config = prefix + "teamConfig"
    /// Sicherheits-Lesezeichen (Bookmark-`Data`) des geteilten Ordners.
    /// Bewusst kein Pfad-String: Ein Pfad allein nützt der Sandbox nichts.
    static let folderBookmark = prefix + "teamFolderBookmark"
}

// MARK: - Team-Konfiguration

/// Name + ID des Teams, dessen Meldungen die App anzeigt.
struct TeamConfig: Codable, Equatable, Identifiable {

    /// Kurze, von Hand weitergebbare Team-ID, z. B. „K7QP2M9X"
    let id: String
    /// Anzeigename, frei wählbar
    var name: String
    /// Wann das Team angelegt (oder beigetreten) wurde
    let createdAt: Date

    init(id: String, name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = TeamConfig.cleanName(name)
        self.createdAt = createdAt
    }

    // MARK: - Team-ID

    /// Alphabet der Team-ID: Base32 aus Großbuchstaben und Ziffern, ohne die
    /// Zeichen, die beim Vorlesen oder Abtippen ständig verwechselt werden
    /// (kein I, kein O, keine 0, keine 1).
    ///
    ///     ABCDEFGHJKLMNPQRSTUVWXYZ23456789   (24 Buchstaben + 8 Ziffern = 32)
    ///
    /// 8 Zeichen ergeben 32^8 ≈ 1,1 Billionen Möglichkeiten — für „zwei Teams
    /// im selben Ordner erwischen zufällig dieselbe ID" reicht das dicke.
    static let idAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    /// Länge einer generierten Team-ID
    static let idLength = 8

    /// Erzeugt eine neue Team-ID.
    static func makeId(length: Int = idLength) -> String {
        let characters = Array(idAlphabet)
        guard !characters.isEmpty, length > 0 else { return "" }
        var result = ""
        result.reserveCapacity(length)
        for _ in 0..<length {
            result.append(characters[Int.random(in: 0..<characters.count)])
        }
        return result
    }

    /// Räumt eine von Hand eingetippte oder eingefügte Team-ID auf.
    ///
    /// Groß-/Kleinschreibung, Leerzeichen und Trennstriche sind egal
    /// („k7qp-2m9x" → „K7QP2M9X"). Alles, was nicht im Alphabet vorkommt,
    /// fliegt raus; stimmt die Länge danach nicht, ist die Eingabe ungültig
    /// (dann lieber ehrlich `nil` als eine stillschweigend falsche ID).
    static func normalizeId(_ raw: String) -> String? {
        let allowed = Set(idAlphabet)
        let cleaned = String(raw.uppercased().filter { allowed.contains($0) })
        guard cleaned.count == idLength else { return nil }
        return cleaned
    }

    /// Ist das eine wohlgeformte Team-ID?
    static func isValidId(_ raw: String) -> Bool {
        normalizeId(raw) != nil
    }

    /// Trimmt den Namen und fängt den leeren Fall ab.
    static func cleanName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Team" }
        return String(trimmed.prefix(60))
    }
}

// MARK: - Speicher

/// Hält die Team-Konfiguration und schreibt sie nach UserDefaults.
///
/// Absichtlich winzig: anlegen, umbenennen, verlassen. Den Ordner verwaltet
/// `TeamFolderAccess`, die Meldungen `TeamReportStore` — beide hören auf
/// `.teamConfigChanged` und räumen selbst auf, wenn das Team verschwindet.
/// Dadurch bleibt diese Datei ohne AppKit-Abhängigkeit und damit testbar.
final class TeamStore: ObservableObject {

    /// Gemeinsame Instanz für Menü, Einstellungen und Übersicht
    static let shared = TeamStore()

    /// Aktuelles Team, `nil` solange keines eingerichtet ist
    @Published private(set) var team: TeamConfig?

    private let defaults: UserDefaults

    /// - Parameter defaults: Nur für Tests überschreibbar; die App nutzt `.standard`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.team = TeamStore.load(from: defaults)
    }

    // MARK: - Abfragen

    /// Ist ein Team eingerichtet?
    var hasTeam: Bool { team != nil }

    /// ID des aktuellen Teams
    var teamId: String? { team?.id }

    /// Name des aktuellen Teams
    var teamName: String? { team?.name }

    // MARK: - Ändern

    /// Legt ein neues Team an und würfelt dafür eine frische ID aus.
    @discardableResult
    func createTeam(name: String) -> TeamConfig {
        let config = TeamConfig(id: TeamConfig.makeId(), name: name)
        store(config)
        return config
    }

    /// Tritt einem bestehenden Team bei — die ID kommt von der Person, die das
    /// Team angelegt hat (zusammen mit dem Ordner).
    /// - Returns: Die gespeicherte Konfiguration, oder `nil` bei ungültiger ID.
    @discardableResult
    func joinTeam(id rawId: String, name: String) -> TeamConfig? {
        guard let id = TeamConfig.normalizeId(rawId) else { return nil }
        let config = TeamConfig(id: id, name: name)
        store(config)
        return config
    }

    /// Benennt das Team um. Die ID bleibt, sonst passten die Dateien im
    /// Ordner schlagartig nicht mehr.
    func rename(to newName: String) {
        guard var config = team else { return }
        let cleaned = TeamConfig.cleanName(newName)
        guard cleaned != config.name else { return }
        config.name = cleaned
        store(config)
    }

    /// Verlässt das Team: Konfiguration weg. Ordner-Lesezeichen und geladene
    /// Meldungen räumen die beiden Hörer von `.teamConfigChanged` weg.
    /// Im geteilten Ordner selbst wird nichts gelöscht.
    func leaveTeam() {
        guard team != nil else { return }
        team = nil
        defaults.removeObject(forKey: TeamDefaultsKeys.config)
        NotificationCenter.default.post(name: .teamConfigChanged, object: nil)
    }

    // MARK: - Persistenz

    private func store(_ config: TeamConfig) {
        team = config
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: TeamDefaultsKeys.config)
        }
        NotificationCenter.default.post(name: .teamConfigChanged, object: nil)
    }

    private static func load(from defaults: UserDefaults) -> TeamConfig? {
        guard let data = defaults.data(forKey: TeamDefaultsKeys.config) else { return nil }
        return try? JSONDecoder().decode(TeamConfig.self, from: data)
    }
}
