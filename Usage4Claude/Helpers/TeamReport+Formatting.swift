//
//  TeamReport+Formatting.swift
//  Usage4Claude
//
//  Anzeigetexte für die Team-Übersicht. Steht bewusst neben `TeamReport`
//  statt darin: Diese Datei hängt an `L.*` und `UserSettings.shared`, das
//  Modell selbst bleibt rein und damit testbar (vgl. `UsageData+Formatting`).
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

// MARK: - Meldung

extension TeamReport {

    /// „vor 5 Min." — wann zuletzt gemeldet wurde
    var reportedAgoText: String {
        TeamReport.agoText(for: reportedAt)
    }

    /// Hinweis „Veraltet", solange die Meldung älter als einen Tag ist
    var staleLabel: String? {
        isStale ? L.Team.stale : nil
    }

    /// Kurzform „vor …" in der eingestellten Sprache.
    /// Unter einer Minute wird das zu Nachkommastellen-Kram, darum ein
    /// eigener Text.
    static func agoText(for date: Date, now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return L.Team.justNow }

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = UserSettings.shared.appLocale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

// MARK: - Einzelnes Limit

extension TeamLimit {

    /// Uhrzeit (heute) bzw. Tag und Uhrzeit, ab wann das Limit wieder frei ist.
    /// `nil`, wenn die Meldung keinen Reset-Zeitpunkt enthält.
    var resetsAtText: String? {
        guard let resetsAt else { return nil }
        if Calendar.current.isDateInToday(resetsAt) {
            return TimeFormatHelper.formatTimeOnly(resetsAt)
        }
        return TimeFormatHelper.formatDateMinute(resetsAt, dateTemplate: "MMMd")
    }
}

// MARK: - Fehler beim Einfügen

extension TeamImportError {

    /// Kurzer Satz, den die Oberfläche unverändert anzeigen kann.
    var message: String {
        switch self {
        case .noTeam:      return L.Team.errorNoTeam
        case .noFolder:    return L.Team.errorNoFolder
        case .invalidJSON: return L.Team.errorInvalidJSON
        case .tooLarge:    return L.Team.errorTooLarge
        case .wrongTeam:   return L.Team.errorWrongTeam
        case .writeFailed: return L.Team.errorWriteFailed
        }
    }
}
