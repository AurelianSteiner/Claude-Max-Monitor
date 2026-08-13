//
//  TeamSummary.swift
//  Usage4Claude
//
//  Rechenregeln der Team-Übersicht: Reihenfolge der Karten und die beiden
//  Zahlen im Kopf. Steht getrennt von der View, weil beides eine Entscheidung
//  ist und keine Darstellung — und weil `TeamReport` (Models) nichts von der
//  Oberfläche wissen soll.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

enum TeamSummary {

    /// Ab hier gilt eine Woche als praktisch aufgebraucht — dieselbe Schwelle
    /// wie bei den eigenen Konten (`WeeklyTrafficLight.exhaustedThreshold`),
    /// damit „fast am Limit" in beiden Ansichten dasselbe bedeutet.
    static let atLimitThreshold = 90

    /// Woran ein Wochenlimit in der Beschriftung erkannt wird.
    ///
    /// Die Meldung enthält nur freien Text („5 Stunden", „7 Tage"), kein
    /// maschinenlesbares Fenster. Erkannt wird deshalb am Wort — klein
    /// geschrieben und in beiden Sprachen, in denen das Melde-Skript schreibt.
    private static let weeklyMarkers = ["woche", "7 tage", "7tage", "week", "7 day", "7day"]

    /// Höchster Prozentwert unter den Wochenlimits der Meldung.
    ///
    /// - Returns: `nil`, wenn die Meldung gar kein Wochenlimit enthält. Dann
    ///   zählt die Person bewusst **nicht** in die „fast am Limit"-Zahl: ein
    ///   volles 5-Stunden-Fenster ist in Stunden zurück und wäre dort ein
    ///   falscher Alarm.
    static func weeklyPercent(of report: TeamReport) -> Int? {
        report.limits
            .filter { limit in
                let label = limit.label.lowercased()
                return weeklyMarkers.contains { label.contains($0) }
            }
            .map(\.percent)
            .max()
    }

    /// Wie viele Personen ihr Wochenlimit praktisch ausgeschöpft haben.
    static func atLimitCount(_ reports: [TeamReport]) -> Int {
        reports.filter { (weeklyPercent(of: $0) ?? 0) >= atLimitThreshold }.count
    }

    /// Am stärksten Ausgelastete zuerst — die Übersicht beantwortet damit
    /// „wer ist am Ende" ohne Suchen. Bei Gleichstand alphabetisch, damit die
    /// Reihenfolge zwischen zwei Aktualisierungen nicht springt.
    static func sortedByLoad(_ reports: [TeamReport]) -> [TeamReport] {
        reports.sorted { lhs, rhs in
            if lhs.highestPercent != rhs.highestPercent {
                return lhs.highestPercent > rhs.highestPercent
            }
            return lhs.person.localizedCaseInsensitiveCompare(rhs.person) == .orderedAscending
        }
    }
}
