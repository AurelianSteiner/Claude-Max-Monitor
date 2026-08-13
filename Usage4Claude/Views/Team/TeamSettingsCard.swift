//
//  TeamSettingsCard.swift
//  Usage4Claude
//
//  Team einrichten — die letzte Karte im Reiter „Konten".
//
//  Ein kurzer Erklärsatz, darunter die Server-Verbindung
//  (`TeamServerSection`): Team-ID + Token eintragen, verbinden — fertig.
//  Verbunden zeigt dieselbe Sektion Rolle, Name und „Trennen", der Inhaber
//  zusätzlich die Mitgliederverwaltung. Mehr gibt es hier nicht; der frühere
//  Rückfallweg über einen geteilten Ordner ist abgeschafft.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

struct TeamSettingsCard: View {

    @ObservedObject private var server = TeamServerConnection.shared

    var body: some View {
        SettingCard(
            icon: "person.3.fill",
            iconColor: .teal,
            title: L.Team.settingsTitle
        ) {
            if !server.isConnected {
                Text(L.Team.settingsIntro)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TeamServerSection()
        }
    }
}
