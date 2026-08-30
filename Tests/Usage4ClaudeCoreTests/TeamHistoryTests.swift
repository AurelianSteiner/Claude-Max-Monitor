//
//  TeamHistoryTests.swift
//  Usage4ClaudeCoreTests
//
//  Der Verlauf kommt vom Team-Server und ist NDJSON-gewachsen: Irgendwann
//  steht eine halbe Zeile, ein fremder Schlüssel oder eine Uhr von gestern
//  darin. Diese Tests halten fest, dass so etwas einzeln rausfliegt, dass
//  die Punkte einer Linie sauber herauskommen — und dass die Verlaufs-ID
//  einer Meldung zum Ablageschema des Servers passt (Mitglieds-ID bzw.
//  dessen Namens-Slug, nicht unserer).
//

import XCTest
@testable import Usage4ClaudeCore

final class TeamHistoryTests: XCTestCase {

    // MARK: - Einlesen

    func testParsesDocumentedFormatSortedAscending() throws {
        // Absichtlich unsortiert — die Linie braucht aufsteigende Zeiten.
        let json = """
        {
          "memberId": "nina-3f2a",
          "days": 7,
          "samples": [
            { "t": "2026-08-29T09:00:00Z",
              "limits": [ { "label": "7 Tage", "kind": "weekly", "percent": 62 },
                          { "label": "5 Stunden", "kind": "session", "percent": 10 } ] },
            { "t": "2026-08-28T09:00:00Z",
              "limits": [ { "label": "7 Tage", "kind": "weekly", "percent": 48 } ] }
          ]
        }
        """

        let samples = try TeamHistorySample.parseList(Data(json.utf8))

        XCTAssertEqual(samples.count, 2)
        XCTAssertLessThan(samples[0].t, samples[1].t)
        XCTAssertEqual(samples[1].limits.count, 2)
        XCTAssertEqual(samples[1].limits[0].kind, .weekly)
        XCTAssertEqual(samples[1].limits[0].percent, 62)
    }

    func testDropsBrokenSamplesAndBrokenLimitsIndividually() throws {
        let json = """
        {
          "samples": [
            { "t": "kaputt", "limits": [ { "label": "7 Tage", "percent": 50 } ] },
            { "limits": [ { "label": "7 Tage", "percent": 50 } ] },
            { "t": "2026-08-29T09:00:00Z",
              "limits": [ { "label": "7 Tage", "percent": 61 },
                          { "percent": 99 },
                          { "label": "Opus 7 Tage", "percent": "44 %" } ] }
          ]
        }
        """

        let samples = try TeamHistorySample.parseList(Data(json.utf8))

        // Zwei Zeilen ohne lesbare Zeit weg, die dritte bleibt — und in ihr
        // fällt nur der Eintrag ohne Beschriftung raus.
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].limits.map(\.label), ["7 Tage", "Opus 7 Tage"])
        XCTAssertEqual(samples[0].limits[1].percent, 44)
        // Verlaufszeilen tragen kein resetsAt — bleibt schlicht leer.
        XCTAssertNil(samples[0].limits[0].resetsAt)
    }

    func testAcceptsEpochSecondsAndMissingKind() throws {
        let json = """
        { "samples": [ { "t": 1756458720, "limits": [ { "label": "7 Tage", "percent": 5 } ] } ] }
        """

        let samples = try TeamHistorySample.parseList(Data(json.utf8))

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].t, Date(timeIntervalSince1970: 1_756_458_720))
        XCTAssertNil(samples[0].limits[0].kind)
    }

    func testRejectsNonEnvelopeJSON() {
        XCTAssertThrowsError(try TeamHistorySample.parseList(Data("[]".utf8))) { error in
            XCTAssertEqual(error as? TeamReportError, .notJSON)
        }
    }

    func testRejectsOversizedData() {
        let data = Data(repeating: 0x20, count: TeamHistorySample.maxBytes + 1)
        XCTAssertThrowsError(try TeamHistorySample.parseList(data)) { error in
            XCTAssertEqual(error as? TeamReportError, .tooLarge)
        }
    }

    // MARK: - Auswertung

    private func sample(_ iso: String, _ pairs: [(String, Int)]) -> TeamHistorySample {
        TeamHistorySample(
            t: TeamDateFormat.parse(iso)!,
            limits: pairs.map { TeamLimit(label: $0.0, percent: $0.1) }
        )
    }

    func testPointsPickTheMatchingLabelAndSkipSamplesWithoutIt() {
        let samples = [
            sample("2026-08-27T09:00:00Z", [("7 Tage", 40), ("5 Stunden", 90)]),
            sample("2026-08-28T09:00:00Z", [("5 Stunden", 10)]),
            sample("2026-08-29T09:00:00Z", [("7 Tage", 55)]),
        ]

        let points = samples.points(label: "7 Tage")

        XCTAssertEqual(points.map(\.percent), [40, 55])
    }

    func testNearestSampleRespectsTolerance() {
        let samples = [
            sample("2026-08-28T06:00:00Z", [("7 Tage", 40)]),
            sample("2026-08-28T18:00:00Z", [("7 Tage", 50)]),
        ]
        let target = TeamDateFormat.parse("2026-08-28T16:00:00Z")!

        let near = samples.nearestSample(to: target, tolerance: 3 * 60 * 60)
        XCTAssertEqual(near?.limits.first?.percent, 50)

        // Nichts innerhalb einer knappen Toleranz → nil statt Fernvergleich
        XCTAssertNil(samples.nearestSample(to: target, tolerance: 60 * 60))
    }

    func testTrendSignificance() {
        XCTAssertTrue(TeamWeeklyTrend(previous: 40, current: 45).isSignificant)
        XCTAssertTrue(TeamWeeklyTrend(previous: 45, current: 40).isSignificant)
        XCTAssertFalse(TeamWeeklyTrend(previous: 45, current: 49).isSignificant)
        XCTAssertEqual(TeamWeeklyTrend(previous: 40, current: 45).delta, 5)
    }

    // MARK: - Verlaufs-ID einer Meldung

    func testHistoryMemberIdPrefersServerMemberId() {
        var report = TeamReport(teamId: "K7QP2M9X", person: "Jürgen",
                                reportedAt: Date(), limits: [])
        report.serverMemberId = "juergen-a1b2"

        XCTAssertEqual(report.historyMemberId, "juergen-a1b2")
    }

    func testHistoryMemberIdFallsBackToServerSlug() {
        let report = TeamReport(teamId: "K7QP2M9X", person: "Jürgen",
                                reportedAt: Date(), limits: [])

        // Der Server streift Akzente ab („jurgen"), er schreibt Umlaute
        // nicht aus wie unser Datei-Slug („juergen") — hier zählt seiner.
        XCTAssertEqual(report.historyMemberId, "jurgen")
        XCTAssertNotEqual(TeamReport.slug("Jürgen"), TeamReport.serverSlug("Jürgen"))
    }

    /// Spiegel von slug() in team-server/server.js — die Fälle decken dessen
    /// Regeln ab: Kleinbuchstaben, Akzente weg, Läufe zu einem Bindestrich,
    /// Ränder gestutzt, 40 Zeichen, Rückfall „anonym".
    func testServerSlugMirrorsServerBehavior() {
        XCTAssertEqual(TeamReport.serverSlug("Aurelian Steiner"), "aurelian-steiner")
        XCTAssertEqual(TeamReport.serverSlug("Jürgen"), "jurgen")
        XCTAssertEqual(TeamReport.serverSlug("  Éva – Kovács  "), "eva-kovacs")
        XCTAssertEqual(TeamReport.serverSlug("A.B."), "a-b")
        XCTAssertEqual(TeamReport.serverSlug("王小明"), "anonym")
        XCTAssertEqual(TeamReport.serverSlug(""), "anonym")
        XCTAssertEqual(TeamReport.serverSlug(String(repeating: "x", count: 60)).count, 40)
    }
}
