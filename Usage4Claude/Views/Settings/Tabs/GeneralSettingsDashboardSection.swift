//
//  GeneralSettingsDashboardSection.swift
//  Usage4Claude
//
//  通用设置里的「多账户总览」卡片：只剩排序方式和列数。
//  Der frühere Schalter „Übersicht beim Klick öffnen" ist entfallen — seit dem
//  Wegfall der Einzelkonto-Ansicht gibt es nichts mehr, wozwischen er umschaltet.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

struct GeneralSettingsDashboardSection: View {
    @ObservedObject private var settings = UserSettings.shared

    /// Breite der Beschriftungsspalte — bündig mit der Darstellungs-Karte
    private let labelWidth: CGFloat = 140

    var body: some View {
        SettingCard(
            icon: "square.grid.2x2",
            iconColor: .teal,
            title: L.SettingsDashboard.section,
            hint: L.SettingsDashboard.hint
        ) {
            VStack(alignment: .leading, spacing: 12) {
                settingRow(label: L.SettingsDashboard.sortLabel) {
                    Picker("", selection: $settings.dashboardSortMode) {
                        ForEach(DashboardSortMode.allCases, id: \.self) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                }

                settingRow(label: L.SettingsDashboard.columnsLabel) {
                    Picker("", selection: $settings.dashboardColumns) {
                        ForEach(1...3, id: \.self) { count in
                            Text(L.Dashboard.columns(count)).tag(count)
                        }
                    }
                }
            }
        }
    }

    /// Beschriftung links, Auswahlmenü rechts
    private func settingRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: labelWidth, alignment: .leading)

            content()
                .pickerStyle(.menu)
                .labelsHidden()
                .focusable(false)
                .frame(width: 190)

            Spacer(minLength: 0)
        }
    }
}
