//
//  TeamSummary.swift
//  Usage4Claude
//
//  Rechenregeln der Team-Übersicht: Reihenfolge der Zeilen und die Zahlen
//  im Kopf. Steht getrennt von der View, weil beides eine Entscheidung
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

    /// Woran ein Wochenlimit in der Beschriftung erkannt wird — der Rückfall
    /// für alte Meldungen ohne maschinenlesbares `kind`. Neue Meldungen tragen
    /// die Art im Feld selbst (`TeamLimitKind`), da entscheidet nicht mehr der
    /// freie Text.
    private static let weeklyMarkers = ["woche", "7 tage", "7tage", "week", "7 day", "7day"]

    /// Woran das Sitzungsfenster in der Beschriftung erkannt wird (Rückfall).
    private static let sessionMarkers = ["stunde", "hour", "sitzung", "session"]

    /// Zählt diese Zeile zur Wochenlage?
    static func isWeekly(_ limit: TeamLimit) -> Bool {
        if let kind = limit.kind { return kind.isWeekly }
        let label = limit.label.lowercased()
        return weeklyMarkers.contains { label.contains($0) }
    }

    /// Ist diese Zeile das Sitzungsfenster?
    static func isSession(_ limit: TeamLimit) -> Bool {
        if let kind = limit.kind { return kind == .session }
        let label = limit.label.lowercased()
        return sessionMarkers.contains { label.contains($0) }
    }

    /// Höchster Prozentwert unter den Wochenlimits der Meldung.
    ///
    /// - Returns: `nil`, wenn die Meldung gar kein Wochenlimit enthält. Dann
    ///   zählt die Person bewusst **nicht** in die „fast am Limit"-Zahl: ein
    ///   volles 5-Stunden-Fenster ist in Stunden zurück und wäre dort ein
    ///   falscher Alarm.
    static func weeklyPercent(of report: TeamReport) -> Int? {
        report.limits.filter(isWeekly).map(\.percent).max()
    }

    /// Prozentwert des Sitzungsfensters — `nil`, wenn keines gemeldet wurde.
    static func sessionPercent(of report: TeamReport) -> Int? {
        report.limits.filter(isSession).map(\.percent).max()
    }

    /// Wie viele Personen ihr Wochenlimit praktisch ausgeschöpft haben.
    /// Veraltete Meldungen zählen nicht mit: Eine 95 %-Woche von vorgestern
    /// ist längst wieder frei und würde die Zahl dauerhaft aufblähen.
    static func atLimitCount(_ reports: [TeamReport]) -> Int {
        reports
            .filter { !$0.isStale }
            .filter { (weeklyPercent(of: $0) ?? 0) >= atLimitThreshold }
            .count
    }

    /// Wie viele Meldungen frisch sind (jünger als 24 Stunden).
    static func freshCount(_ reports: [TeamReport]) -> Int {
        reports.filter { !$0.isStale }.count
    }

    /// Reihenfolge der Übersicht: Die Woche entscheidet zuerst — sie ist die
    /// bindende Sperre; ein volles 5-Stunden-Fenster ist in Stunden zurück und
    /// darf eine 85 %-Woche nicht überholen. Die Sitzung bricht Gleichstände,
    /// der Name hält die Reihenfolge zwischen zwei Aktualisierungen ruhig.
    /// Veraltete Meldungen sinken geschlossen ans Ende: Ihre Zahlen sind
    /// Vergangenheit und sollen nicht zwischen den frischen stehen.
    static func sortedByLoad(_ reports: [TeamReport]) -> [TeamReport] {
        reports.sorted { lhs, rhs in
            if lhs.isStale != rhs.isStale { return !lhs.isStale }
            let leftWeekly = weeklyPercent(of: lhs) ?? -1
            let rightWeekly = weeklyPercent(of: rhs) ?? -1
            if leftWeekly != rightWeekly { return leftWeekly > rightWeekly }
            if lhs.highestPercent != rhs.highestPercent {
                return lhs.highestPercent > rhs.highestPercent
            }
            return lhs.person.localizedCaseInsensitiveCompare(rhs.person) == .orderedAscending
        }
    }
}
