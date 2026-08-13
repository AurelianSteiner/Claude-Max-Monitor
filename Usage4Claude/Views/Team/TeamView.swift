//
//  TeamView.swift
//  Usage4Claude
//
//  Die Team-Übersicht: eine Karte je gemeldeter Person, am stärksten
//  Ausgelastete oben. Sie beantwortet genau eine Frage — wer im Team ist
//  gerade am Ende und wer hat noch Luft.
//
//  Alles hier ist Anzeige. Geschrieben wird nur an einer Stelle im Programm
//  (eingefügte Meldung in den Einstellungen), und der geteilte Ordner selbst
//  bleibt unangetastet.
//
//  Die vier leeren Zustände (kein Team / kein Ordner / Ordner weg / keine
//  Meldungen) sind absichtlich unterschieden: Jeder braucht einen anderen
//  nächsten Schritt, und „nichts da" ohne Grund ist die nutzloseste aller
//  Meldungen.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

struct TeamView: View {
    /// Rückkanal für die Einstellungen — dieselbe Aktionsliste wie in der Übersicht
    var onMenuAction: ((MenuAction) -> Void)?

    @ObservedObject private var teamStore = TeamStore.shared
    @ObservedObject private var folder = TeamFolderAccess.shared
    @ObservedObject private var reportStore = TeamReportStore.shared
    @StateObject private var localization = LocalizationManager.shared

    /// Rückmeldung des Knopfs im leeren Zustand: Ohne sie sieht ein Klick auf
    /// „Anleitung kopieren" aus, als wäre nichts passiert.
    @State private var showCopied = false
    @State private var copyToken = 0

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
            Text(L.Team.windowTitle)
                .font(.headline)
                .lineLimit(1)

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
        .frame(height: 36)
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

    @ViewBuilder
    private var content: some View {
        if !teamStore.hasTeam {
            emptyState(
                symbol: "person.2",
                title: L.Team.emptyNoTeam,
                step: L.Team.emptyNoTeamStep,
                buttonTitle: L.Team.emptyOpenSettings
            ) {
                onMenuAction?(.authSettings)
            }
        } else if !folder.hasFolder {
            emptyState(
                symbol: "folder.badge.questionmark",
                title: L.Team.emptyNoFolder,
                step: L.Team.emptyNoFolderStep,
                buttonTitle: L.Team.folderChoosePrompt
            ) {
                folder.chooseFolder()
            }
        } else if reports.isEmpty && isFolderUnreachable {
            emptyState(
                symbol: "exclamationmark.triangle",
                title: L.Team.emptyUnreachable,
                step: L.Team.emptyUnreachableStep,
                buttonTitle: L.Team.folderChoosePrompt
            ) {
                folder.chooseFolder()
            }
        } else if reports.isEmpty {
            emptyState(
                symbol: "tray",
                title: L.Team.emptyNoReports,
                step: L.Team.emptyNoReportsStep,
                buttonTitle: showCopied ? L.Team.copied : L.Team.copyInstructions
            ) {
                TeamClipboard.copyInstructions(teamId: teamStore.teamId)
                flashCopied()
            }
        } else {
            cardList
        }
    }

    /// Der Ordner ist eingerichtet, war beim letzten Blick aber nicht lesbar.
    /// Beide Quellen zählen: Der Speicher merkt es beim Einlesen, der
    /// Ordnerzugriff schon beim Auflösen des Lesezeichens.
    private var isFolderUnreachable: Bool {
        reportStore.folderUnavailable || folder.isUnreachable
    }

    private var cardList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(reports) { report in
                    TeamReportCard(report: report)
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

    /// Beschriftung des Knopfs zwei Sekunden lang auf „Kopiert" stellen. Der
    /// Token sorgt dafür, dass ein zweiter Klick den Hinweis verlängert, statt
    /// dass die erste Abblendung ihn mitten im zweiten Mal wegnimmt.
    private func flashCopied() {
        copyToken += 1
        let token = copyToken
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copyToken == token { showCopied = false }
        }
    }
}
