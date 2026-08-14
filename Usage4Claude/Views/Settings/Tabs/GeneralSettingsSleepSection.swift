//
//  GeneralSettingsSleepSection.swift
//  Usage4Claude
//
//  „Schlaf-Einstellungen des Systems" — oben die Live-Werte aus `pmset -g`
//  (SystemSleepInfo), darunter die drei Terminal-Befehle zum Nachlesen und
//  Kopieren.
//
//  Warum das hier steht: Der Wach-Schalter „Bleib wach" im Kopf der Übersicht
//  setzt IOKit-Power-Assertions (siehe `SleepGuard`). Die halten den Mac wach,
//  solange die App läuft — gegen `pmset disablesleep` kommen sie aber nicht an,
//  und zugeklappt schläft der Mac ohnehin ein. Diese stärkere Einstellung gehört dem
//  System, verlangt Administratorrechte und lässt sich aus einer Sandbox heraus
//  nicht setzen. Deshalb zeigt die App die Befehle nur an und kopiert sie —
//  ausgeführt wird hier nichts.
//
//  Eingeklappt, weil es die seltene Ausnahme ist: Wer sie braucht, sucht sie.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import AppKit
import SwiftUI

struct GeneralSettingsSleepSection: View {

    @State private var isExpanded = false
    /// Zuletzt kopierter Befehl — nur für den kurzen „Kopiert"-Hinweis
    @State private var copiedCommand: String?
    @State private var copyToken = 0

    /// Live-Werte aus `pmset -g` — was das System JETZT eingestellt hat,
    /// steht über den Befehlen, die es ändern würden.
    @ObservedObject private var systemSleep = SystemSleepInfo.shared

    /// Ein Befehl samt kurzer Erklärung. Die Befehle stehen bewusst im Code und
    /// nicht in der Lokalisierung: Sie werden nicht übersetzt, und ein Tippfehler
    /// in einer Sprachdatei wäre hier besonders ärgerlich.
    private struct SleepCommand: Identifiable {
        let command: String
        let caption: String
        var id: String { command }
    }

    private var commands: [SleepCommand] {
        [
            SleepCommand(command: "pmset -g | head -3", caption: L.SettingsSleep.captionStatus),
            SleepCommand(command: "sudo pmset -a disablesleep 1", caption: L.SettingsSleep.captionOff),
            SleepCommand(command: "sudo pmset -a disablesleep 0", caption: L.SettingsSleep.captionOn)
        ]
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                currentValues

                Text(L.SettingsSleep.intro)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(commands) { entry in
                        commandRow(entry)
                    }
                }

                Text(L.SettingsSleep.note)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .onAppear { systemSleep.refresh() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz")
                    .font(.title3)
                    .foregroundColor(.indigo)
                    .frame(width: 24)

                Text(L.SettingsSleep.section)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.03))
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
    }

    /// Die Live-Werte: Was `pmset -g` gerade meldet, in je einem Satz.
    /// Ließ sich nichts lesen (Sandbox, unerwartete Ausgabe), steht das
    /// ehrlich da, statt Werte zu raten.
    @ViewBuilder
    private var currentValues: some View {
        if systemSleep.sleepDisabled == nil && systemSleep.displaySleepMinutes == nil {
            Text(L.SettingsSleep.valueUnknown)
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                if let disabled = systemSleep.sleepDisabled {
                    valueRow(disabled ? L.SettingsSleep.valueSleepOn : L.SettingsSleep.valueSleepOff)
                }
                if let minutes = systemSleep.displaySleepMinutes {
                    valueRow(minutes == 0
                        ? L.SettingsSleep.valueDisplayNever
                        : L.SettingsSleep.valueDisplayMinutes(minutes))
                }
            }
        }
    }

    private func valueRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Eine Zeile: Befehl in Schreibmaschinenschrift, daneben wofür er gut ist,
    /// rechts der Knopf zum Kopieren. Der Text ist zusätzlich markierbar, falls
    /// jemand lieber selbst auswählt.
    private func commandRow(_ entry: SleepCommand) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: entry.command)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.secondary.opacity(0.12))
                )

            Text(entry.caption)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if copiedCommand == entry.command {
                Text(L.SettingsSleep.copied)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }

            Button(action: { copy(entry.command) }) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(L.SettingsSleep.copy)
        }
        .animation(.easeInOut(duration: 0.2), value: copiedCommand)
    }

    /// Kopiert den Befehl und zeigt zwei Sekunden lang „Kopiert". Der Token
    /// sorgt dafür, dass ein zweiter Klick den Hinweis verlängert, statt dass
    /// die erste Abblendung ihn vorzeitig wegnimmt.
    private func copy(_ command: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)

        copyToken += 1
        let token = copyToken
        copiedCommand = command
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copyToken == token { copiedCommand = nil }
        }
    }
}
