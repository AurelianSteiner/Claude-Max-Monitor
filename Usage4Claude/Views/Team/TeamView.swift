//
//  TeamView.swift
//  Usage4Claude
//
//  Die Team-Übersicht: eine Karte je gemeldeter Person, am stärksten
//  Ausgelastete oben. Sie beantwortet genau eine Frage — wer im Team ist
//  gerade am Ende und wer hat noch Luft.
//
//  Alles hier ist Anzeige. Die Meldungen kommen vom Team-Server
//  (`TeamReportStore`), es gibt keinen anderen Weg mehr.
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
    @StateObject private var localization = LocalizationManager.shared

    /// Am stärksten Ausgelastete zuerst
    private var reports: [TeamReport] {
        TeamSummary.sortedByLoad(reportStore.reports)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(
            minWidth: 320, idealWidth: 380, maxWidth: .infinity,
            minHeight: 240, idealHeight: 460, maxHeight: .infinity
        )
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

            Spacer(minLength: 8)

            if !reports.isEmpty {
                countPill(L.Team.peopleCount(reports.count), help: nil)

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

    /// Zeile unter dem Titel: verbunden als wer. `nil`, solange keine
    /// Verbindung besteht oder die Rolle (Token abgelehnt) fehlt.
    private var connectionLine: String? {
        guard server.isConnected, let role = server.role else { return nil }
        return L.Team.connectedAs(role.displayName)
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

    /// Drei leere Zustände plus die Kartenliste: nicht verbunden, Server
    /// gerade nicht erreichbar, noch keine Meldungen.
    @ViewBuilder
    private var content: some View {
        if !server.isConnected {
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
        } else if reports.isEmpty {
            emptyState(
                symbol: "tray",
                title: L.Team.emptyNoReports,
                step: L.Team.emptyServerNoReportsStep,
                buttonTitle: L.Usage.refresh
            ) {
                reportStore.refresh(force: true)
            }
        } else {
            cardList
        }
    }

    private var cardList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(reports) { report in
                    TeamReportCard(report: report)
                }

                // Ein Mitglied sieht nur die eigene Karte — das ist Absicht
                // des Servers, kein Fehler. Eine leise Zeile erklärt es,
                // bevor jemand nach den Kollegen sucht.
                if server.role == .member {
                    Text(L.Team.membersOwnOnly)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
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
