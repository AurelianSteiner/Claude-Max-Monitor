//
//  TeamSettingsCard.swift
//  Usage4Claude
//
//  Team einrichten — die letzte Karte im Reiter „Konten".
//
//  Oben die Server-Verbindung (`TeamServerSection`) — der normale Weg.
//  Darunter der geteilte Ordner als Rückfallweg, mit seinen zwei Zuständen:
//  Ohne Team ein Namensfeld und ein Knopf — darunter die zweite Zeile für
//  alle, die schon eine Team-ID bekommen haben. Mit Team der Name, die ID
//  zum Weitergeben, der geteilte Ordner und die Zahl der gefundenen
//  Meldungen. Besteht eine Server-Verbindung, wird der Ordner-Teil gedimmt —
//  er funktioniert weiter, ist aber nicht mehr die Quelle der Übersicht.
//
//  Die Beitreten-Zeile ist keine Zierde: Wer ein eigenes Team anlegt, würfelt
//  eine neue ID — und sieht dann im geteilten Ordner nichts, weil dort alle
//  Meldungen die ID des Teams tragen, das jemand anderes angelegt hat. Ohne
//  diesen Weg funktioniert die Übersicht nur für genau eine Person.
//
//  Der Teamname steht hier als Text und nicht in einem Eingabefeld: Jede
//  Änderung meldet `TeamStore` per Notification weiter, und `TeamReportStore`
//  liest daraufhin den Ordner neu ein — bei einem Textfeld also einmal pro
//  Tastenanschlag. Umbenennen ist das nicht wert.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

struct TeamSettingsCard: View {

    @ObservedObject private var teamStore = TeamStore.shared
    @ObservedObject private var folder = TeamFolderAccess.shared
    @ObservedObject private var reportStore = TeamReportStore.shared
    @ObservedObject private var server = TeamServerConnection.shared

    @State private var newTeamName = ""
    @State private var joinId = ""
    @State private var showLeaveConfirmation = false

    /// „Kopiert"-Hinweis, verschwindet nach zwei Sekunden von selbst
    @State private var showCopied = false
    @State private var copyToken = 0

    @State private var isPasteExpanded = false
    @State private var pastedText = ""
    @State private var pasteMessage: String?
    @State private var pasteFailed = false

    var body: some View {
        SettingCard(
            icon: "person.3.fill",
            iconColor: .teal,
            title: L.Team.settingsTitle
        ) {
            TeamServerSection()

            Divider()

            folderContent
        }
        .alert(L.Team.leaveConfirmTitle, isPresented: $showLeaveConfirmation) {
            Button(L.Account.cancel, role: .cancel) {}
            Button(L.Team.leaveConfirmButton, role: .destructive) {
                teamStore.leaveTeam()
            }
        } message: {
            Text(L.Team.leaveConfirmMessage)
        }
        // Die Zahl der Meldungen ist nur dann eine Auskunft, wenn sie stimmt,
        // sobald jemand hinsieht. `activate()` hält dabei seinen Mindestabstand
        // ein, öffnet die Einstellungen also nicht in einen Lesevorgang hinein.
        .onAppear { reportStore.activate() }
        // Zeigt keine Ansicht mehr auf die Meldungen, ruht der Zeitgeber —
        // sonst liefe alle zwei Minuten eine Abfrage gegen einen Cloud-Ordner,
        // deren Ergebnis niemand sieht.
        .onDisappear { reportStore.deactivate() }
    }

    // MARK: - Ordner-Teil

    /// Der geteilte Ordner ist der Rückfallweg: Sobald eine Server-Verbindung
    /// besteht, bekommt er eine Überschrift und wird gedimmt — bedienbar
    /// bleibt er, nur die Aufmerksamkeit gehört ihm nicht mehr.
    private var folderContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if server.isConnected {
                Text(L.Team.folderFallback)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            if let team = teamStore.team {
                configuredContent(team)
            } else {
                setupContent
            }
        }
        .opacity(server.isConnected ? 0.55 : 1)
    }

    // MARK: - Ohne Team

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.Team.settingsIntro)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField(L.Team.namePlaceholder, text: $newTeamName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .onSubmit(createTeam)

                Button(L.Team.create, action: createTeam)
                    .disabled(trimmedName.isEmpty)
            }

            Divider()

            joinRow
        }
    }

    /// Beitreten statt anlegen: Die ID kommt von der Person, die das Team
    /// angelegt hat. Der Knopf bleibt aus, bis die Eingabe eine wohlgeformte
    /// ID ist — das fängt Tippfehler ab, bevor sie zu einer stillen,
    /// dauerhaft leeren Übersicht führen.
    private var joinRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.Team.joinHint)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField(L.Team.idLabel, text: $joinId)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: 140)
                    .onSubmit(joinTeam)

                Button(L.Team.join, action: joinTeam)
                    .disabled(!TeamConfig.isValidId(joinId))
            }
        }
    }

    private var trimmedName: String {
        newTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createTeam() {
        guard !trimmedName.isEmpty else { return }
        teamStore.createTeam(name: trimmedName)
        newTeamName = ""
        joinId = ""
    }

    /// Der Name ist beim Beitreten optional — `TeamConfig` macht aus einem
    /// leeren Namen „Team". Wichtig ist allein die ID.
    private func joinTeam() {
        guard teamStore.joinTeam(id: joinId, name: trimmedName) != nil else { return }
        newTeamName = ""
        joinId = ""
    }

    // MARK: - Mit Team

    private func configuredContent(_ team: TeamConfig) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(team.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                idPill(team.id)
            }

            folderRow

            Text(L.Team.reportsCount(reportStore.reports.count))
                .font(.caption)
                .foregroundColor(.secondary)

            actionRow(team)

            Divider()

            pasteSection
        }
    }

    /// Die ID wird vorgelesen und abgetippt — deshalb Schreibmaschinenschrift
    /// (0 und O, 1 und l sind darin unterscheidbar) und ein Knopf zum Kopieren.
    private func idPill(_ id: String) -> some View {
        HStack(spacing: 6) {
            Text(L.Team.idLabel)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(id)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))

            Button(action: {
                TeamClipboard.copy(id)
                flashCopied()
            }) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(L.Team.copyId)
        }
    }

    private var folderRow: some View {
        HStack(spacing: 8) {
            Text(L.Team.folderLabel)
                .font(.caption)
                .foregroundColor(.secondary)

            folderStatus

            Spacer(minLength: 8)

            Button(folder.hasFolder ? L.Team.folderChange : L.Team.folderChoosePrompt) {
                folder.chooseFolder()
            }
            .controlSize(.small)
        }
    }

    /// Drei Fälle, die man auseinanderhalten muss: kein Ordner gewählt, Ordner
    /// gewählt und lesbar, Ordner gewählt aber gerade nicht erreichbar (Volume
    /// nicht eingehängt). Der dritte sieht sonst aus wie der erste.
    @ViewBuilder
    private var folderStatus: some View {
        if folder.isUnreachable {
            Text(L.Team.folderUnreachable)
                .font(.caption)
                .foregroundColor(DashboardPalette.ink(80))
        } else if let name = folder.folderName {
            Text(name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(folder.folderPath ?? name)
        } else {
            Text(L.Team.folderNone)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func actionRow(_ team: TeamConfig) -> some View {
        HStack(spacing: 8) {
            Button(action: {
                TeamClipboard.copyInstructions(teamId: team.id)
                flashCopied()
            }) {
                Label(L.Team.copyInstructions, systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderedProminent)

            if showCopied {
                Text(L.Team.copied)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }

            Spacer(minLength: 8)

            Button(L.Team.leave) {
                showLeaveConfirmation = true
            }
            .controlSize(.small)
        }
        .animation(.easeInOut(duration: 0.2), value: showCopied)
    }

    /// Zeigt „Kopiert" und blendet es nach zwei Sekunden wieder aus. Der Token
    /// sorgt dafür, dass ein zweiter Klick den Hinweis verlängert, statt dass
    /// die erste Abblendung ihn mitten im zweiten Mal wegnimmt.
    private func flashCopied() {
        copyToken += 1
        let token = copyToken
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copyToken == token { showCopied = false }
        }
    }

    // MARK: - Meldung einfügen

    /// Für alle, die nicht an den geteilten Ordner kommen: Der Text aus der
    /// Nachricht landet hier und wird von der App selbst als Datei abgelegt.
    /// Eingeklappt, weil es der seltene Weg ist — der Ordner ist der normale.
    private var pasteSection: some View {
        DisclosureGroup(isExpanded: $isPasteExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L.Team.pasteHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $pastedText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.15))
                    )

                HStack(spacing: 8) {
                    Button(L.Team.pasteApply, action: applyPastedReport)
                        .controlSize(.small)
                        .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let message = pasteMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(pasteFailed ? DashboardPalette.ink(100) : .secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text(L.Team.pasteTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
    }

    private func applyPastedReport() {
        switch reportStore.importPasted(pastedText) {
        case .success(let report):
            pasteFailed = false
            pasteMessage = L.Team.pasteAccepted(report.person)
            pastedText = ""
        case .failure(let error):
            pasteFailed = true
            pasteMessage = error.message
        }
    }
}
