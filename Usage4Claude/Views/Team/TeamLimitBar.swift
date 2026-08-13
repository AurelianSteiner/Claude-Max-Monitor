//
//  TeamLimitBar.swift
//  Usage4Claude
//
//  Eine Limit-Zeile einer Team-Karte: Beschriftung, Balken, Prozentzahl.
//
//  Bewusst eine eigene, kleine Komponente statt `UnifiedLimitRow`: Die Zeilen
//  der eigenen Konten hängen an `LimitType` und `UsageData` — eine Meldung aus
//  dem Ordner kennt beides nicht, sie hat nur eine Beschriftung als freien Text
//  und einen Prozentwert. Die Optik ist absichtlich dieselbe (Balken in der
//  Auslastungsfarbe, Prozentzahl rechts in Ziffern gleicher Breite), damit
//  fremde und eigene Zahlen ohne Umdenken vergleichbar bleiben.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

struct TeamLimitBar: View {
    /// Beschriftung aus der Meldung, z. B. „7 Tage"
    let label: String
    /// 0…100
    let percent: Int
    /// Wann das Limit wieder frei ist — nur als Tooltip, die Zeile bleibt schmal
    var resetsAtText: String?

    private static let labelWidth: CGFloat = 96
    private static let valueWidth: CGFloat = 40

    private var clamped: Double { Double(min(100, max(0, percent))) }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: Self.labelWidth, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.25))
                    Capsule()
                        .fill(DashboardPalette.fill(clamped))
                        .frame(width: max(3, geometry.size.width * clamped / 100))
                }
            }
            .frame(height: 6)

            Text("\(Int(clamped.rounded()))%")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundColor(DashboardPalette.ink(clamped))
                .frame(width: Self.valueWidth, alignment: .trailing)
        }
        .frame(height: 22)
        .help(resetsAtText ?? "")
    }
}
