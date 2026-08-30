//
//  TeamHistorySample.swift
//  Usage4Claude
//
//  Team-Übersicht — der Auslastungs-Verlauf einer Person. So liefert ihn der
//  Team-Server (GET /v1/teams/<ID>/members/<memberId>/history?days=7):
//
//      {
//        "memberId": "nina-3f2a",
//        "days": 7,
//        "samples": [
//          { "t": "2026-08-29T09:12:00Z",
//            "limits": [ { "label": "7 Tage", "kind": "weekly", "percent": 62 } ] },
//          …
//        ]
//      }
//
//  Eine Zeile je angenommener Meldung, 30 Tage Aufbewahrung. Gelesen wird so
//  misstrauisch wie bei `TeamReport`: Eine kaputte Zeile fliegt einzeln raus,
//  ein kaputter Limit-Eintrag ebenso — nie kippt der ganze Verlauf.
//
//  Diese Datei ist reines Foundation (kein AppKit, keine Lokalisierung) und
//  hängt darum im SwiftPM-Testtarget, siehe Package.swift.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

// MARK: - Ein Verlaufspunkt

/// Eine Zeile des Verlaufs: Zeitpunkt plus die damals gemeldeten Limits.
/// Die Limits sind dieselben `TeamLimit` wie in einer Meldung — nur ohne
/// Reset-Zeitpunkt, den speichert der Server im Verlauf nicht.
struct TeamHistorySample: Equatable {
    let t: Date
    let limits: [TeamLimit]

    init(t: Date, limits: [TeamLimit]) {
        self.t = t
        self.limits = limits
    }
}

extension TeamHistorySample: Decodable {
    private enum CodingKeys: String, CodingKey { case t, limits }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Zeitstempel: ISO-8601-Text, ersatzweise Unix-Sekunden. Ohne Zeit
        // ist ein Verlaufspunkt nicht einzeichenbar — dann weg damit.
        if let raw = try? container.decode(String.self, forKey: .t),
           let date = TeamDateFormat.parse(raw) {
            t = date
        } else if let epoch = try? container.decode(Double.self, forKey: .t),
                  epoch > 0, epoch.isFinite {
            t = Date(timeIntervalSince1970: epoch)
        } else {
            throw TeamReportError.missingField("t")
        }

        // Kaputte Einträge einzeln wegwerfen statt das ganze Array.
        let raw = (try? container.decode([LenientDecodable<TeamLimit>].self, forKey: .limits)) ?? []
        limits = Array(raw.compactMap(\.value).prefix(TeamReport.maxLimits))
    }
}

extension TeamHistorySample {

    /// Größere Antworten werden gar nicht erst dekodiert. 30 Tage à höchstens
    /// 96 Zeilen sind ein paar hundert Kilobyte — alles darüber ist keine
    /// Verlaufs-Antwort.
    static let maxBytes = 4 * 1024 * 1024

    /// Liest die Antwort des Verlaufs-Endpunkts ({"samples": […]}).
    /// Kaputte Zeilen fliegen einzeln raus; sortiert wird aufsteigend nach
    /// Zeit, damit die Linie ohne weiteres Zutun zeichenbar ist.
    /// - Throws: `TeamReportError`, wenn zu groß oder kein {"samples"}-JSON
    static func parseList(_ data: Data) throws -> [TeamHistorySample] {
        guard data.count <= maxBytes else { throw TeamReportError.tooLarge }
        struct Envelope: Decodable { let samples: [LenientDecodable<TeamHistorySample>] }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw TeamReportError.notJSON
        }
        return envelope.samples.compactMap(\.value).sorted { $0.t < $1.t }
    }
}

// MARK: - Auswertung

/// Ein Punkt einer Verlaufslinie: Zeit und Prozentwert einer Limit-Zeile.
struct TeamHistoryPoint: Equatable {
    let t: Date
    let percent: Int
}

extension Array where Element == TeamHistorySample {

    /// Die Verlaufslinie einer bestimmten Limit-Zeile, über die Beschriftung
    /// gefunden — sie ist je Person stabil („7 Tage", „Opus 7 Tage", …).
    /// Punkte ohne diese Zeile fallen aus (Meldung von vor der Umstellung,
    /// Konto zwischenzeitlich abgemeldet).
    func points(label: String) -> [TeamHistoryPoint] {
        compactMap { sample in
            sample.limits.first { $0.label == label }
                .map { TeamHistoryPoint(t: sample.t, percent: $0.percent) }
        }
    }

    /// Der Verlaufspunkt, der einem Zeitpunkt am nächsten liegt — `nil`, wenn
    /// keiner innerhalb der Toleranz liegt (Lücke im Verlauf, Rechner war aus).
    func nearestSample(to date: Date, tolerance: TimeInterval) -> TeamHistorySample? {
        let nearest = self.min {
            abs($0.t.timeIntervalSince(date)) < abs($1.t.timeIntervalSince(date))
        }
        guard let nearest, abs(nearest.t.timeIntervalSince(date)) <= tolerance else { return nil }
        return nearest
    }
}

// MARK: - Trend

/// Wochenlage jetzt gegen ~24 Stunden zuvor — die Grundlage des Trend-Pfeils
/// in der Team-Liste.
struct TeamWeeklyTrend: Equatable {
    /// Wochenwert vor ungefähr 24 Stunden
    let previous: Int
    /// Wochenwert der aktuellen Meldung
    let current: Int

    var delta: Int { current - previous }

    /// Ab dieser Differenz gilt eine Bewegung als Trend — darunter ist es
    /// Zappeln, und ein Pfeil an jeder Zeile wäre nur Lärm.
    static let significantDelta = 5

    var isSignificant: Bool { abs(delta) >= Self.significantDelta }
}
