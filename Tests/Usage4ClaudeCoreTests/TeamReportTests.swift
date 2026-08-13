//
//  TeamReportTests.swift
//  Usage4ClaudeCoreTests
//
//  Das Meldeformat kommt aus einem Ordner, den die App nicht kontrolliert:
//  fremde Dateien, halb geschriebene Dateien, ein Skript in einer älteren
//  Fassung. Diese Tests halten fest, dass so etwas übersprungen wird, statt
//  die ganze Übersicht zu kippen.
//

import XCTest
@testable import Usage4ClaudeCore

final class TeamReportTests: XCTestCase {

    // MARK: - Gutfall

    func testParsesDocumentedFormat() throws {
        let json = """
        {
          "schema": 1,
          "teamId": "K7QP2M9X",
          "person": "Aurelian",
          "reportedAt": "2026-08-13T09:12:00Z",
          "limits": [
            { "label": "5 Stunden", "percent": 42, "resetsAt": "2026-08-13T14:00:00Z" },
            { "label": "7 Tage",    "percent": 88, "resetsAt": "2026-08-18T09:00:00Z" }
          ]
        }
        """

        let report = try TeamReport.parse(json)

        XCTAssertEqual(report.teamId, "K7QP2M9X")
        XCTAssertEqual(report.person, "Aurelian")
        XCTAssertEqual(report.limits.count, 2)
        XCTAssertEqual(report.limits[0].label, "5 Stunden")
        XCTAssertEqual(report.limits[0].percent, 42)
        XCTAssertNotNil(report.limits[0].resetsAt)
        XCTAssertEqual(report.limits[1].percent, 88)
        // Stabile, unterschiedliche Identitäten für ForEach
        XCTAssertNotEqual(report.limits[0].id, report.limits[1].id)
    }

    func testIgnoresUnknownKeysAndAcceptsMissingResetsAt() throws {
        let json = """
        {
          "schema": 1,
          "teamId": "K7QP2M9X",
          "person": "Nina",
          "reportedAt": "2026-08-13T09:12:00Z",
          "hostname": "nina-mbp",
          "limits": [ { "label": "5 Stunden", "percent": 10, "quelle": "skript" } ]
        }
        """

        let report = try TeamReport.parse(json)

        XCTAssertEqual(report.limits.count, 1)
        XCTAssertNil(report.limits[0].resetsAt)
    }

    func testAcceptsFractionalSecondsOffsetsAndNumericPercent() throws {
        let json = """
        {
          "teamId": "k7qp2m9x",
          "person": "Tom",
          "reportedAt": "2026-08-13T11:12:00.500+02:00",
          "limits": [ { "label": "5 Stunden", "percent": 42.6 } ]
        }
        """

        let report = try TeamReport.parse(json)

        // Fehlendes "schema" wird als aktuelle Fassung gelesen, teamId normalisiert
        XCTAssertEqual(report.schema, TeamReport.currentSchema)
        XCTAssertEqual(report.teamId, "K7QP2M9X")
        XCTAssertEqual(report.limits[0].percent, 43)
    }

    // MARK: - Abwehr

    func testSkipsBrokenLimitEntryButKeepsTheRest() throws {
        let json = """
        {
          "teamId": "K7QP2M9X",
          "person": "Nina",
          "reportedAt": "2026-08-13T09:12:00Z",
          "limits": [
            { "label": "5 Stunden", "percent": 42 },
            "kaputt",
            { "percent": 50 },
            { "label": "7 Tage", "percent": 88 }
          ]
        }
        """

        let report = try TeamReport.parse(json)

        XCTAssertEqual(report.limits.map(\.label), ["5 Stunden", "7 Tage"])
    }

    func testClampsPercentIntoRange() throws {
        let json = """
        {
          "teamId": "K7QP2M9X", "person": "Nina", "reportedAt": "2026-08-13T09:12:00Z",
          "limits": [ { "label": "a", "percent": 250 }, { "label": "b", "percent": -20 } ]
        }
        """

        let report = try TeamReport.parse(json)

        XCTAssertEqual(report.limits.map(\.percent), [100, 0])
    }

    func testRejectsMalformedInput() {
        let cases = [
            "kein json",
            "{}",
            #"{ "teamId": "K7QP2M9X", "reportedAt": "2026-08-13T09:12:00Z" }"#,          // person fehlt
            #"{ "teamId": "K7QP2M9X", "person": "Nina" }"#,                              // reportedAt fehlt
            #"{ "teamId": "", "person": "Nina", "reportedAt": "2026-08-13T09:12:00Z" }"#,
            #"{ "teamId": "K7QP2M9X", "person": "Nina", "reportedAt": "irgendwann" }"#
        ]

        for json in cases {
            XCTAssertThrowsError(try TeamReport.parse(json), "sollte abgelehnt werden: \(json)")
        }
    }

    func testRejectsOversizedInput() {
        let padding = String(repeating: "x", count: TeamReport.maxBytes)
        let json = """
        { "teamId": "K7QP2M9X", "person": "\(padding)", "reportedAt": "2026-08-13T09:12:00Z", "limits": [] }
        """

        XCTAssertThrowsError(try TeamReport.parse(json)) { error in
            XCTAssertEqual(error as? TeamReportError, .tooLarge)
        }
    }

    func testMissingLimitsBecomesEmptyList() throws {
        let json = #"{ "teamId": "K7QP2M9X", "person": "Nina", "reportedAt": "2026-08-13T09:12:00Z" }"#

        let report = try TeamReport.parse(json)

        XCTAssertTrue(report.limits.isEmpty)
    }

    /// Was `TeamReportStore` beim Einlesen eines fremden Ordners erlebt: eine
    /// Meldung mit Prozent als Text, eine abgeschnittene Datei, eine aus einem
    /// anderen Team, eine ohne `limits`. Entscheidend ist, dass die heile
    /// Meldung dabei durchkommt — eine kaputte Datei darf die Übersicht nicht
    /// leer räumen.
    func testOneBadFileDoesNotTakeTheOthersDown() {
        let ownTeam = "K7QP2M9X"
        let folder: [(name: String, content: String)] = [
            ("report-K7QP2M9X-nina.json", """
             { "teamId": "K7QP2M9X", "person": "Nina", "reportedAt": "2026-08-13T09:12:00Z",
               "limits": [ { "label": "7 Tage", "percent": "88 %" } ] }
             """),
            ("report-K7QP2M9X-halb.json",
             #"{ "teamId": "K7QP2M9X", "person": "Halb", "reportedAt": "2026-08-13T09"#),
            ("report-ZZZZZZZZ-fremd.json", """
             { "teamId": "ZZZZZZZZ", "person": "Fremd", "reportedAt": "2026-08-13T09:12:00Z" }
             """),
            ("urlaub.json", "Kein JSON, nur ein Zettel."),
            ("report-K7QP2M9X-tom.json", """
             { "teamId": "K7QP2M9X", "person": "Tom", "reportedAt": "2026-08-13T10:00:00Z" }
             """)
        ]

        // Genau die Schleife aus `TeamReportStore.readReports`, nur ohne Ordner.
        var loaded: [TeamReport] = []
        for file in folder {
            guard let report = try? TeamReport.parse(Data(file.content.utf8), fileName: file.name) else { continue }
            guard report.teamId.caseInsensitiveCompare(ownTeam) == .orderedSame else { continue }
            loaded.append(report)
        }

        XCTAssertEqual(TeamReport.sortedByRecency(loaded).map(\.person), ["Tom", "Nina"])
        // „88 %" als Text wird zur Zahl, fehlende `limits` werden zur leeren Liste
        XCTAssertEqual(loaded.first?.limits.map(\.percent), [88])
        XCTAssertEqual(loaded.last?.limits, [])
    }

    // MARK: - Dateinamen

    func testFileNameAndSlug() {
        XCTAssertEqual(TeamReport.fileName(teamId: "K7QP2M9X", person: "Aurelian"),
                       "report-K7QP2M9X-aurelian.json")
        XCTAssertEqual(TeamReport.slug("Jürgen Groß"), "juergen-gross")
        XCTAssertEqual(TeamReport.slug("  Anna-Lena  "), "anna-lena")
        XCTAssertEqual(TeamReport.slug("张伟"), "person")
        XCTAssertTrue(TeamReport.looksLikeReportFile("report-k7qp2m9x-nina.json", teamId: "K7QP2M9X"))
        XCTAssertFalse(TeamReport.looksLikeReportFile("urlaub.json", teamId: "K7QP2M9X"))
    }

    // MARK: - Alter und Sortierung

    func testStalenessAfterOneDay() throws {
        let now = Date()
        let report = TeamReport(teamId: "K7QP2M9X",
                                person: "Nina",
                                reportedAt: now.addingTimeInterval(-25 * 3600),
                                limits: [])
        let fresh = TeamReport(teamId: "K7QP2M9X",
                               person: "Tom",
                               reportedAt: now.addingTimeInterval(-3600),
                               limits: [])

        XCTAssertTrue(report.isStale(at: now))
        XCTAssertFalse(fresh.isStale(at: now))
    }

    func testNewestFirstAndOnePerPerson() {
        let now = Date()
        let old = TeamReport(teamId: "K7QP2M9X", person: "Nina",
                             reportedAt: now.addingTimeInterval(-7200), limits: [],
                             fileName: "report-K7QP2M9X-nina-alt.json")
        let new = TeamReport(teamId: "K7QP2M9X", person: "nina",
                             reportedAt: now, limits: [],
                             fileName: "report-K7QP2M9X-nina.json")
        let other = TeamReport(teamId: "K7QP2M9X", person: "Tom",
                               reportedAt: now.addingTimeInterval(-60), limits: [],
                               fileName: "report-K7QP2M9X-tom.json")

        let result = TeamReport.deduplicatedByPerson([old, other, new])

        XCTAssertEqual(result.map(\.person), ["nina", "Tom"])
        XCTAssertEqual(result[0].fileName, "report-K7QP2M9X-nina.json")
    }

    // MARK: - Das Melde-Skript

    /// Wortgleiche Ausgabe von `scripts/team-report.sh` (Lauf mit einer
    /// nachgebauten API-Antwort). Der Test hält die Vereinbarung zwischen
    /// Skript und App fest: Feldnamen, ISO-Zeitstempel mit „Z", Prozentwerte
    /// als Zahl, fehlendes `resetsAt` erlaubt — und den Dateinamen, unter dem
    /// das Skript die Meldung ablegt.
    func testParsesOutputOfTheReportScript() throws {
        let json = """
        {
          "limits": [
            {
              "label": "5 Stunden",
              "percent": 42,
              "resetsAt": "2026-08-13T14:00:00Z"
            },
            {
              "label": "7 Tage",
              "percent": 89,
              "resetsAt": "2026-08-18T09:00:00Z"
            },
            {
              "label": "Opus 7 Tage",
              "percent": 91,
              "resetsAt": "2026-08-18T09:00:00Z"
            },
            {
              "label": "Sonnet 7 Tage",
              "percent": 25
            }
          ],
          "person": "Jürgen Groß",
          "reportedAt": "2026-08-13T11:53:49Z",
          "schema": 1,
          "teamId": "K7QP2M9X"
        }
        """

        let report = try TeamReport.parse(json)

        XCTAssertEqual(report.schema, 1)
        XCTAssertEqual(report.teamId, "K7QP2M9X")
        XCTAssertEqual(report.person, "Jürgen Groß")
        XCTAssertEqual(report.limits.map(\.label),
                       ["5 Stunden", "7 Tage", "Opus 7 Tage", "Sonnet 7 Tage"])
        XCTAssertEqual(report.limits.map(\.percent), [42, 89, 91, 25])
        XCTAssertNotNil(report.limits[0].resetsAt)
        XCTAssertNil(report.limits[3].resetsAt)

        // Genau dieser Name entsteht auch im Skript (slug + Team-ID).
        XCTAssertEqual(report.preferredFileName, "report-K7QP2M9X-juergen-gross.json")
    }

    // MARK: - Zurückschreiben

    func testCanonicalRoundTrip() throws {
        let original = try TeamReport.parse("""
        {
          "schema": 1, "teamId": "K7QP2M9X", "person": "Nina",
          "reportedAt": "2026-08-13T09:12:00Z", "extra": "wird ignoriert",
          "limits": [ { "label": "5 Stunden", "percent": 42, "resetsAt": "2026-08-13T14:00:00Z" } ]
        }
        """)

        let data = try original.canonicalJSONData()
        let again = try TeamReport.parse(data, fileName: original.preferredFileName)

        XCTAssertEqual(again.teamId, original.teamId)
        XCTAssertEqual(again.person, original.person)
        XCTAssertEqual(again.reportedAt.timeIntervalSince1970,
                       original.reportedAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(again.limits, original.limits)
        XCTAssertEqual(again.fileName, "report-K7QP2M9X-nina.json")
    }
}

// MARK: - Team-ID

final class TeamConfigTests: XCTestCase {

    func testGeneratedIdUsesUnambiguousAlphabet() {
        let allowed = Set(TeamConfig.idAlphabet)
        XCTAssertEqual(TeamConfig.idAlphabet.count, 32)
        for forbidden in "IO01" {
            XCTAssertFalse(allowed.contains(forbidden), "\(forbidden) ist zu leicht zu verwechseln")
        }

        for _ in 0..<200 {
            let id = TeamConfig.makeId()
            XCTAssertEqual(id.count, TeamConfig.idLength)
            XCTAssertTrue(id.allSatisfy { allowed.contains($0) }, "unerwartetes Zeichen in \(id)")
            XCTAssertTrue(TeamConfig.isValidId(id))
        }
    }

    func testNormalizeIdForgivesTypingHabits() {
        XCTAssertEqual(TeamConfig.normalizeId("k7qp-2m9x"), "K7QP2M9X")
        XCTAssertEqual(TeamConfig.normalizeId("  K7QP 2M9X "), "K7QP2M9X")
        XCTAssertNil(TeamConfig.normalizeId("K7QP2M9"))     // zu kurz
        XCTAssertNil(TeamConfig.normalizeId("K7QP2M9XY"))   // zu lang
        XCTAssertNil(TeamConfig.normalizeId(""))
    }

    func testNameIsTrimmedAndNeverEmpty() {
        XCTAssertEqual(TeamConfig(id: "K7QP2M9X", name: "  Redaktion  ").name, "Redaktion")
        XCTAssertEqual(TeamConfig(id: "K7QP2M9X", name: "   ").name, "Team")
    }
}
