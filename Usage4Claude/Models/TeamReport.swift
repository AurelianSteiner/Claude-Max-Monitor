//
//  TeamReport.swift
//  Usage4Claude
//
//  Team-Übersicht — das Format einer Meldung. So liefert sie der Team-Server
//  (GET /reports), und so schreibt sie das Melde-Skript
//  (scripts/team-report.sh) als kleine JSON-Datei. Dateiname:
//
//      report-<TEAMID>-<slug>.json          z. B. report-K7QP2M9X-aurelian.json
//
//  Inhalt:
//
//      {
//        "schema": 1,
//        "teamId": "K7QP2M9X",
//        "person": "Aurelian",
//        "reportedAt": "2026-08-13T09:12:00Z",
//        "limits": [
//          { "label": "5 Stunden", "percent": 42, "resetsAt": "2026-08-13T14:00:00Z" },
//          { "label": "7 Tage",    "percent": 88, "resetsAt": "2026-08-18T09:00:00Z" }
//        ]
//      }
//
//  Gelesen wird betont misstrauisch: Die Meldungen kommen von fremden
//  Rechnern, irgendwann ist auch Müll dabei. Unbekannte Schlüssel werden
//  ignoriert, `resetsAt`
//  darf fehlen, eine kaputte Zeile im `limits`-Array wirft nur diesen einen
//  Eintrag weg, und eine kaputte Datei wird übersprungen — nie wird der
//  gesamte Lesevorgang abgebrochen.
//
//  Diese Datei ist reines Foundation (kein AppKit, keine Lokalisierung) und
//  hängt darum im SwiftPM-Testtarget, siehe Package.swift.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

// MARK: - Fehler

/// Warum eine Meldung nicht gelesen werden konnte.
enum TeamReportError: Error, Equatable {
    /// Datei/Text größer als `TeamReport.maxBytes`
    case tooLarge
    /// Kein gültiges JSON
    case notJSON
    /// Pflichtfeld fehlt oder ist leer
    case missingField(String)
    /// Meldung gehört zu einem anderen Team
    case wrongTeam(expected: String, found: String)
}

// MARK: - Ein einzelnes Limit

/// Maschinenlesbare Art einer Limit-Zeile. Optional und additiv: Alte
/// Meldungen ohne `kind` bleiben gültig, die Auswertung fällt dann auf die
/// Beschriftungs-Erkennung zurück (siehe `TeamSummary`). Der Server speichert
/// unbekannte Schlüssel unverändert, deshalb braucht das keine neue
/// Schema-Version.
enum TeamLimitKind: String, Codable {
    /// Das schnelle Sitzungsfenster (5 Stunden bzw. Codex primary)
    case session
    /// Das Wochenfenster des Kontos
    case weekly
    /// Wochenlimit eines einzelnen Modells („Opus 7 Tage", …)
    case modelWeekly = "model_weekly"
    /// Wochenlage eines weiteren Kontos („<Kontoname> 7 Tage")
    case accountWeekly = "account_weekly"

    /// Zählt diese Zeile zur Wochenlage? (Alles außer dem Sitzungsfenster.)
    var isWeekly: Bool { self != .session }
}

/// Eine Zeile einer Meldung: Beschriftung, Prozentwert, optional Reset und Art.
struct TeamLimit: Codable, Identifiable, Equatable {

    /// Position innerhalb der Meldung — steckt nicht im JSON, sondern wird
    /// beim Dekodieren vergeben, damit `ForEach` eine stabile Identität hat
    /// (zwei Zeilen dürfen dieselbe Beschriftung tragen).
    var index: Int = 0

    /// z. B. „5 Stunden"
    let label: String
    /// 0…100, beim Einlesen hart geklemmt
    let percent: Int
    /// Wann das Limit wieder frei ist — darf fehlen
    let resetsAt: Date?
    /// Maschinenlesbare Art der Zeile — darf fehlen (alte Meldungen)
    let kind: TeamLimitKind?

    var id: String { "\(index)-\(label)" }

    /// Maximale Länge einer Beschriftung (defensiv, gegen aufgeblähte Dateien)
    static let maxLabelLength = 40

    init(index: Int = 0, label: String, percent: Int, resetsAt: Date? = nil,
         kind: TeamLimitKind? = nil) {
        self.index = index
        self.label = String(label.prefix(TeamLimit.maxLabelLength))
        self.percent = min(100, max(0, percent))
        self.resetsAt = resetsAt
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case label, percent, resetsAt, kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let rawLabel = ((try? container.decode(String.self, forKey: .label)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawLabel.isEmpty else { throw TeamReportError.missingField("label") }
        label = String(rawLabel.prefix(TeamLimit.maxLabelLength))

        // Prozent darf Zahl, Kommazahl oder „42 %" als Text sein — Skripte in
        // freier Wildbahn liefern alles davon.
        let value: Double
        if let intValue = try? container.decode(Int.self, forKey: .percent) {
            value = Double(intValue)
        } else if let doubleValue = try? container.decode(Double.self, forKey: .percent) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self, forKey: .percent),
                  let parsed = Double(stringValue
                    .replacingOccurrences(of: "%", with: "")
                    .replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespaces)) {
            value = parsed
        } else {
            throw TeamReportError.missingField("percent")
        }
        guard value.isFinite else { throw TeamReportError.missingField("percent") }
        percent = min(100, max(0, Int(value.rounded())))

        if let raw = try? container.decode(String.self, forKey: .resetsAt) {
            resetsAt = TeamDateFormat.parse(raw)
        } else {
            resetsAt = nil
        }

        // Unbekannte kind-Werte werden wie fehlende behandelt — ein neuerer
        // Client darf Arten erfinden, ohne ältere Leser zu stören.
        kind = (try? container.decodeIfPresent(String.self, forKey: .kind))
            .flatMap { TeamLimitKind(rawValue: $0) }

        index = 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(percent, forKey: .percent)
        if let resetsAt {
            try container.encode(TeamDateFormat.string(from: resetsAt), forKey: .resetsAt)
        }
        if let kind {
            try container.encode(kind.rawValue, forKey: .kind)
        }
    }
}

// MARK: - Eine Meldung

/// Was eine Kollegin oder ein Kollege zuletzt gemeldet hat.
struct TeamReport: Codable, Identifiable, Equatable {

    /// Aktuelle Formatversion
    static let currentSchema = 1
    /// Größere Dateien werden gar nicht erst gelesen — eine Meldung sind ein
    /// paar hundert Bytes, alles darüber ist ein Versehen oder Absicht.
    static let maxBytes = 64 * 1024
    /// Ab wann eine Meldung als veraltet gilt
    static let stalenessThreshold: TimeInterval = 24 * 60 * 60
    /// Mehr Zeilen zeigt keine Karte sinnvoll an
    static let maxLimits = 12
    /// Maximale Länge eines Personennamens
    static let maxPersonLength = 60

    var schema: Int
    /// Zu welchem Team die Meldung gehört (immer in Großbuchstaben)
    let teamId: String
    /// Anzeigename der Person
    let person: String
    /// Zeitpunkt der Meldung
    let reportedAt: Date
    /// Die gemeldeten Limits, in der Reihenfolge der Datei
    let limits: [TeamLimit]

    /// Dateiname, aus dem die Meldung stammt — nicht Teil des JSON.
    /// Dient als stabile Identität: pro Person genau eine Datei.
    var fileName: String = ""

    var id: String {
        fileName.isEmpty ? TeamReport.fileName(teamId: teamId, person: person) : fileName
    }

    init(schema: Int = TeamReport.currentSchema,
         teamId: String,
         person: String,
         reportedAt: Date,
         limits: [TeamLimit],
         fileName: String = "") {
        self.schema = schema
        self.teamId = teamId.uppercased()
        self.person = String(person.prefix(TeamReport.maxPersonLength))
        self.reportedAt = reportedAt
        self.limits = TeamReport.stamped(limits)
        self.fileName = fileName
    }

    private enum CodingKeys: String, CodingKey {
        case schema, teamId, person, reportedAt, limits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Fehlende oder unlesbare Version: einfach als aktuelle Version lesen.
        // Eine höhere Version wird ebenfalls gelesen — unbekannte Schlüssel
        // ignoriert der Decoder ohnehin, und die bekannten Felder stimmen.
        schema = (try? container.decode(Int.self, forKey: .schema)) ?? TeamReport.currentSchema

        let rawTeamId = ((try? container.decode(String.self, forKey: .teamId)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !rawTeamId.isEmpty else { throw TeamReportError.missingField("teamId") }
        teamId = rawTeamId

        let rawPerson = ((try? container.decode(String.self, forKey: .person)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPerson.isEmpty else { throw TeamReportError.missingField("person") }
        person = String(rawPerson.prefix(TeamReport.maxPersonLength))

        // Zeitstempel: ISO-8601-Text, ersatzweise Unix-Sekunden.
        if let raw = try? container.decode(String.self, forKey: .reportedAt),
           let date = TeamDateFormat.parse(raw) {
            reportedAt = date
        } else if let epoch = try? container.decode(Double.self, forKey: .reportedAt),
                  epoch > 0, epoch.isFinite {
            reportedAt = Date(timeIntervalSince1970: epoch)
        } else {
            // Ohne Zeitstempel ließe sich weder sortieren noch beurteilen, wie
            // alt die Zahlen sind — dann lieber die ganze Datei überspringen.
            throw TeamReportError.missingField("reportedAt")
        }

        // Kaputte Einträge einzeln wegwerfen statt das ganze Array.
        let raw = (try? container.decode([LenientDecodable<TeamLimit>].self, forKey: .limits)) ?? []
        limits = TeamReport.stamped(raw.compactMap(\.value).prefix(TeamReport.maxLimits))

        fileName = ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(teamId, forKey: .teamId)
        try container.encode(person, forKey: .person)
        try container.encode(TeamDateFormat.string(from: reportedAt), forKey: .reportedAt)
        try container.encode(limits, forKey: .limits)
    }

    // MARK: - Einlesen

    /// Liest eine Meldung aus Rohdaten.
    /// - Parameters:
    ///   - data: Dateiinhalt oder eingefügter Text als UTF-8
    ///   - fileName: Dateiname, aus dem die Daten stammen (für die Identität)
    /// - Throws: `TeamReportError`, wenn zu groß, kein JSON oder Pflichtfeld fehlt
    static func parse(_ data: Data, fileName: String = "") throws -> TeamReport {
        guard data.count <= maxBytes else { throw TeamReportError.tooLarge }
        do {
            var report = try JSONDecoder().decode(TeamReport.self, from: data)
            report.fileName = fileName
            return report
        } catch let error as TeamReportError {
            throw error
        } catch {
            throw TeamReportError.notJSON
        }
    }

    /// Bequeme Variante für eingefügten Text.
    static func parse(_ text: String) throws -> TeamReport {
        guard let data = text.data(using: .utf8) else { throw TeamReportError.notJSON }
        return try parse(data)
    }

    /// Kanonische Fassung zum Weitergeben (Server, Melde-Skript): immer
    /// Schema 1, immer ISO-Zeitstempel, ohne den Ballast der Eingabe.
    func canonicalJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    // MARK: - Dateinamen

    /// Dateiname dieser Meldung (so legt sie das Melde-Skript ab)
    var preferredFileName: String {
        TeamReport.fileName(teamId: teamId, person: person)
    }

    /// `report-<TEAMID>-<slug>.json`
    static func fileName(teamId: String, person: String) -> String {
        "report-\(teamId.uppercased())-\(slug(person)).json"
    }

    /// Personenname → dateinamenstauglicher Bestandteil.
    /// Umlaute werden ausgeschrieben („Jürgen" → „juergen"), alles andere auf
    /// a–z, 0–9 und Bindestrich reduziert.
    static func slug(_ person: String) -> String {
        var text = person.lowercased()
        let replacements = [("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss"),
                            ("å", "a"), ("æ", "ae"), ("ø", "oe")]
        for (from, to) in replacements {
            text = text.replacingOccurrences(of: from, with: to)
        }
        text = text.folding(options: [.diacriticInsensitive],
                            locale: Locale(identifier: "en_US_POSIX"))

        var slug = ""
        var pendingSeparator = false
        for character in text {
            if character.isASCII && (character.isLetter || character.isNumber) {
                if pendingSeparator && !slug.isEmpty { slug.append("-") }
                pendingSeparator = false
                slug.append(character)
            } else if !slug.isEmpty {
                pendingSeparator = true
            }
        }
        slug = String(slug.prefix(32))
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "person" : slug
    }

    /// Sieht der Dateiname nach einer Meldung dieses Teams aus?
    /// Nur eine Vorsortierung — verlässlich ist allein die `teamId` im Inhalt.
    static func looksLikeReportFile(_ name: String, teamId: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("report-\(teamId.lowercased())-") && lower.hasSuffix(".json")
    }

    // MARK: - Alter

    /// Ist die Meldung älter als 24 Stunden?
    func isStale(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(reportedAt) > TeamReport.stalenessThreshold
    }

    /// Ist die Meldung älter als 24 Stunden?
    var isStale: Bool { isStale(at: Date()) }

    /// Höchster gemeldeter Prozentwert — praktisch für Sortierung und Ampel.
    var highestPercent: Int { limits.map(\.percent).max() ?? 0 }

    // MARK: - Sortierung

    /// Neueste Meldung zuerst; bei gleicher Zeit alphabetisch nach Person.
    static func sortedByRecency(_ reports: [TeamReport]) -> [TeamReport] {
        reports.sorted { lhs, rhs in
            if lhs.reportedAt != rhs.reportedAt { return lhs.reportedAt > rhs.reportedAt }
            return lhs.person.localizedCaseInsensitiveCompare(rhs.person) == .orderedAscending
        }
    }

    /// Pro Person nur die jüngste Meldung behalten.
    ///
    /// Nötig, weil alte Meldungen liegen bleiben können — etwa wenn jemand
    /// seinen Namen ändert und unter neuem Namen meldet. Ohne das stünde
    /// dieselbe Person doppelt da.
    static func deduplicatedByPerson(_ reports: [TeamReport]) -> [TeamReport] {
        var newest: [String: TeamReport] = [:]
        for report in reports {
            let key = report.person.lowercased().trimmingCharacters(in: .whitespaces)
            if let existing = newest[key], existing.reportedAt >= report.reportedAt { continue }
            newest[key] = report
        }
        return sortedByRecency(Array(newest.values))
    }

    // MARK: - Intern

    /// Vergibt die Positionsnummern für die stabile `id`.
    private static func stamped<S: Sequence>(_ limits: S) -> [TeamLimit] where S.Element == TeamLimit {
        limits.enumerated().map { index, limit in
            var stamped = limit
            stamped.index = index
            return stamped
        }
    }
}

// MARK: - Hilfsmittel

/// Dekodiert ein Element und schluckt dessen Fehler.
///
/// `[TeamLimit]` direkt zu dekodieren würde beim ersten kaputten Eintrag das
/// ganze Array verwerfen; über diesen Umweg bleibt der Rest erhalten.
private struct LenientDecodable<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

/// ISO-8601-Zeitstempel des Meldeformats — mit und ohne Sekundenbruchteile.
enum TeamDateFormat {

    private static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Liest „2026-08-13T09:12:00Z" oder „2026-08-13T11:12:00.500+02:00".
    static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return plain.date(from: trimmed) ?? withFractionalSeconds.date(from: trimmed)
    }

    /// Schreibt immer UTC mit „Z", so wie im Format dokumentiert.
    static func string(from date: Date) -> String {
        plain.string(from: date)
    }
}
