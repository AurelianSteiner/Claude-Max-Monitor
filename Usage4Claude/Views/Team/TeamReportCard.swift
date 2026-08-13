//
//  TeamReportCard.swift
//  Usage4Claude
//
//  Eine Meldung vom Team-Server als Karte — reine Anzeige, hier lässt
//  sich nichts bedienen. Kopfzeile: Name und wann gemeldet wurde. Darunter je
//  Limit ein Balken.
//
//  Eine Meldung ist immer eine Momentaufnahme von vorhin, nie ein Live-Wert.
//  Ab einem Tag Alter wird sie deshalb gedämpft und mit „Veraltet" markiert:
//  Eine blasse Karte lädt nicht dazu ein, ihre Zahl für bare Münze zu nehmen.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

struct TeamReportCard: View {
    let report: TeamReport

    private var isStale: Bool { report.isStale }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if report.limits.isEmpty {
                // Kann vorkommen: Datei war gültig, alle Zeilen darin kaputt.
                Text("–")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(report.limits) { limit in
                        TeamLimitBar(
                            label: limit.label,
                            percent: limit.percent,
                            resetsAtText: limit.resetsAtText
                        )
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .opacity(isStale ? 0.55 : 1)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(report.person)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            Text(L.Team.reportedAgo(report.reportedAgoText))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)

            if let stale = report.staleLabel {
                Text(stale)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(DashboardPalette.ink(80))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(DashboardPalette.fill(80).opacity(0.15))
                    )
            }
        }
    }
}
