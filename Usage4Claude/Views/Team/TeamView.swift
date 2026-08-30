//
//  TeamView.swift
//  Usage4Claude
//
//  Die Team-Übersicht: eine kompakte Zeile je Person, am stärksten
//  Ausgelastete oben, veraltete Meldungen unten. Ein Klick auf eine Zeile
//  öffnet die Detailansicht der Person (`TeamMemberDetailView`) — im selben
//  Container, kein eigenes Fenster. Die Übersicht beantwortet „wer ist am
//  Ende, wer hat noch Luft", das Detail „welche Limits genau, und ab wann
//  wieder frei".
//
//  Seit 2.7 lebt die Ansicht als zweiter Modus in der Übersicht
//  (`DashboardView`), nicht mehr im eigenen Fenster. Die Meldungen kommen vom
//  Team-Server (`TeamReportStore`), es gibt keinen anderen Weg.
//
//  Die leeren Zustände (nicht verbunden / Server nicht erreichbar / noch
//  keine Meldungen) sind absichtlich unterschieden: Jeder braucht einen
//  anderen nächsten Schritt, und „nichts da" ohne Grund ist die nutzloseste
//  aller Meldungen.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

struct TeamView: View {
    /// Rückkanal für die Einstellungen — dieselbe Aktionsliste wie in der Übersicht
    var onMenuAction: ((MenuAction) -> Void)?

    @ObservedObject private var reportStore = TeamReportStore.shared
    @ObservedObject private var server = TeamServerConnection.shared
    @ObservedObject private var historyStore = TeamHistoryStore.shared
    @StateObject private var localization = LocalizationManager.shared

    /// Aufgeklappte Person (Meldungs-ID) — `nil` = Liste. Verschwindet die
    /// Meldung bei einer Aktualisierung, fällt die Ansicht von selbst auf die
    /// Liste zurück (siehe `selectedReport`).
    @State private var selectedReportID: String?

    /// Am stärksten Ausgelastete zuerst, Veraltete unten
    private var reports: [TeamReport] {
        TeamSummary.sortedByLoad(reportStore.reports)
    }

    private var selectedReport: TeamReport? {
        guard let id = selectedReportID else { return nil }
        return reports.first { $0.id == id }
    }

    /// Mitglieder, von denen noch keine Meldung vorliegt — nur Super/Admin
    /// bekommen die Mitgliederliste, für alle anderen bleibt das leer.
    /// Ohne diese Zeilen sähe ein Team von zehn, in dem drei melden, wie ein
    /// Team von drei aus.
    private var silentMembers: [TeamServerMember] {
        guard !reportStore.members.isEmpty else { return [] }
        let reportedIDs = Set(reportStore.reports.map(\.id))
        let reportedNames = Set(reportStore.reports.map { $0.person.lowercased() })
        return reportStore.members
            .filter { member in
                !reportedIDs.contains("server-\(member.id)")
                    && !reportedNames.contains(member.name.lowercased())
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onAppear { reportStore.activate() }
        .onDisappear { reportStore.deactivate() }
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L.Team.windowTitle)
                    .font(.headline)
                    .lineLimit(1)

                // „Verbunden als Admin" — eine Zeile, keine Zierde. Solange
                // keine Verbindung besteht, erklärt der leere Zustand alles.
                if let line = connectionLine {
                    Text(line)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            // Ein Wasserstand je Person, dieselbe Miniatur wie die Konten in
            // der Kopfzeile der Übersicht: Pegel = Woche, roter Ring =
            // Sitzung voll. Veraltete Meldungen erscheinen gedämpft.
            if !reports.isEmpty {
                HStack(spacing: MiniGaugeMetrics.spacing) {
                    ForEach(reports) { report in
                        MiniWaterGauge(
                            weeklyUtilization: TeamSummary.weeklyPercent(of: report).map(Double.init),
                            sessionExhausted: (TeamSummary.sessionPercent(of: report) ?? 0) >= 100,
                            diameter: 13
                        )
                        .opacity(report.isStale ? 0.45 : 1)
                        .help(gaugeHelp(for: report))
                    }
                }
                .fixedSize()
            }

            Spacer(minLength: 8)

            if !reports.isEmpty {
                countPill(peopleText, help: nil)

                let atLimit = TeamSummary.atLimitCount(reports)
                if atLimit > 0 {
                    countPill(
                        L.Team.atLimitCount(atLimit),
                        help: L.Team.atLimitHelp,
                        tint: DashboardPalette.ink(100)
                    )
                }
            }

            refreshButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(minHeight: 36)
    }

    /// „3 von 8 gemeldet", sobald die Mitgliederliste bekannt ist —
    /// sonst schlicht „Personen: 3".
    private var peopleText: String {
        let fresh = TeamSummary.freshCount(reports)
        let total = max(reportStore.members.count, reports.count)
        if !reportStore.members.isEmpty, total > reports.count || fresh < total {
            return L.Team.membersReported(fresh, total)
        }
        return L.Team.peopleCount(reports.count)
    }

    /// Zeile unter dem Titel: verbunden als wer. `nil`, solange keine
    /// Verbindung besteht oder die Rolle (Token abgelehnt) fehlt.
    private var connectionLine: String? {
        guard server.isConnected, let role = server.role else { return nil }
        return L.Team.connectedAs(role.displayName)
    }

    private func gaugeHelp(for report: TeamReport) -> String {
        var parts: [String] = [report.person]
        if let weekly = TeamSummary.weeklyPercent(of: report) {
            parts.append("\(L.Dashboard.weeklyLimit) \(weekly)%")
        }
        if let session = TeamSummary.sessionPercent(of: report) {
            parts.append("\(L.Dashboard.sessionLimit) \(session)%")
        }
        return parts.joined(separator: " · ")
    }

    private func countPill(_ text: String, help: String?, tint: Color = .secondary) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
            .help(help ?? "")
    }

    private var refreshButton: some View {
        Button(action: { reportStore.refresh(force: true) }) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(reportStore.isRefreshing)
        .focusable(false)
        .help(L.Usage.refresh)
    }

    // MARK: - Inhalt

    /// Drei leere Zustände, die Liste — oder das Detail einer Person.
    @ViewBuilder
    private var content: some View {
        if let report = selectedReport {
            TeamMemberDetailView(report: report) {
                withAnimation(.easeInOut(duration: 0.18)) { selectedReportID = nil }
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if !server.isConnected {
            emptyState(
                symbol: "person.2",
                title: L.Team.emptyNoTeam,
                step: L.Team.emptyNoTeamStep,
                buttonTitle: L.Team.emptyOpenSettings
            ) {
                onMenuAction?(.authSettings)
            }
        } else if reports.isEmpty && reportStore.serverUnavailable {
            emptyState(
                symbol: "wifi.exclamationmark",
                title: L.Team.serverUnreachable,
                step: L.Team.emptyServerUnreachableStep,
                buttonTitle: L.Usage.refresh
            ) {
                reportStore.refresh(force: true)
            }
        } else if reports.isEmpty && silentMembers.isEmpty {
            emptyState(
                symbol: "tray",
                title: L.Team.emptyNoReports,
                step: L.Team.emptyServerNoReportsStep,
                buttonTitle: L.Usage.refresh
            ) {
                reportStore.refresh(force: true)
            }
        } else {
            memberList
        }
    }

    private var memberList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(reports) { report in
                    TeamMemberRow(report: report,
                                  trend: historyStore.weeklyTrend(for: report)) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedReportID = report.id
                        }
                    }
                    // Verlauf träge nachladen — einmal je Person und Sitzung.
                    // Jede sichtbare Zeile ist eine, deren Verlauf diese Rolle
                    // auch abrufen darf (Mitglieder sehen nur sich selbst).
                    .onAppear { historyStore.load(memberId: report.historyMemberId) }
                }

                // Wer noch nie gemeldet hat, steht trotzdem da — gedämpft,
                // mit dem grauen „keine Daten"-Wasserstand. So sieht der
                // Inhaber auf einen Blick, wer die App noch nicht
                // eingerichtet hat.
                ForEach(silentMembers) { member in
                    TeamSilentMemberRow(member: member)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Leerer Zustand

    /// Überschrift, konkreter nächster Schritt, ein Knopf, der genau diesen
    /// Schritt ausführt.
    private func emptyState(
        symbol: String,
        title: String,
        step: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundColor(.secondary)

            Text(title)
                .font(.system(size: 13, weight: .semibold))

            Text(step)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(buttonTitle, action: action)
                .controlSize(.small)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Eine Person als Zeile

/// Kompakte Zeile der Team-Liste: Wasserstand, Name, Meldealter, Wochenwert,
/// Pfeil. Die Details (alle Limits, Reset-Zeiten) stehen bewusst nicht hier —
/// dafür ist die Detailansicht da, sonst wird die Liste ab fünf Personen zur
/// Scrollstrecke.
private struct TeamMemberRow: View {
    let report: TeamReport
    /// Wochenlage gegen ~gestern — `nil`, solange kein Verlauf geladen ist
    let trend: TeamWeeklyTrend?
    let action: () -> Void

    private var weekly: Int? { TeamSummary.weeklyPercent(of: report) }
    private var session: Int? { TeamSummary.sessionPercent(of: report) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                MiniWaterGauge(
                    weeklyUtilization: weekly.map(Double.init),
                    sessionExhausted: (session ?? 0) >= 100,
                    diameter: 16
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(report.person)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(L.Team.reportedAgo(report.reportedAgoText))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let stale = report.staleLabel {
                    Text(stale)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DashboardPalette.ink(80))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(DashboardPalette.fill(80).opacity(0.15)))
                }

                // Der Trend-Pfeil: Woche deutlich höher oder niedriger als
                // ~gestern. Kleine Bewegungen zeigen keinen Pfeil — sonst
                // trüge jede Zeile immer einen.
                if let trend, trend.isSignificant {
                    Image(systemName: trend.delta > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(trend.delta > 0 ? DashboardPalette.ink(80)
                                                         : DashboardPalette.ink(0))
                        .help(L.Team.trendHelp(trend.previous, trend.current))
                }

                if let weekly {
                    Text("\(weekly)%")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundColor(DashboardPalette.ink(Double(weekly)))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .opacity(report.isStale ? 0.55 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

/// Zeile für ein Mitglied, das noch nie gemeldet hat: grauer Wasserstand,
/// Name, „Noch keine Meldung". Nicht klickbar — es gibt nichts zu zeigen.
private struct TeamSilentMemberRow: View {
    let member: TeamServerMember

    var body: some View {
        HStack(spacing: 10) {
            MiniWaterGauge(weeklyUtilization: nil, sessionExhausted: false, diameter: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(member.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(L.Team.rowNoReport)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .opacity(0.7)
    }
}
