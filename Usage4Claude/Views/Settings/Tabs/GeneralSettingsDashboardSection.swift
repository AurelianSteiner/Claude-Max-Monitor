//
//  GeneralSettingsDashboardSection.swift
//  Usage4Claude
//
//  通用设置里的「多账户总览」卡片：控制点击菜单栏图标时是看总览还是经典单账户详情，
//  以及总览的排序方式和列数。
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

struct GeneralSettingsDashboardSection: View {
    @ObservedObject private var settings = UserSettings.shared

    var body: some View {
        SettingCard(
            icon: "square.grid.2x2",
            iconColor: .teal,
            title: L.SettingsDashboard.section,
            hint: L.SettingsDashboard.hint
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Toggle("", isOn: $settings.dashboardEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .focusable(false)
                        .labelsHidden()
                    Text(L.SettingsDashboard.enable)
                    Spacer()
                }

                if settings.dashboardEnabled {
                    HStack {
                        Text(L.SettingsDashboard.sortLabel)
                            .foregroundColor(.secondary)
                        Picker("", selection: $settings.dashboardSortMode) {
                            ForEach(DashboardSortMode.allCases, id: \.self) { mode in
                                Text(mode.localizedName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 190)
                    }
                    .padding(.leading, 20)

                    HStack {
                        Text(L.SettingsDashboard.columnsLabel)
                            .foregroundColor(.secondary)
                        Picker("", selection: $settings.dashboardColumns) {
                            ForEach(1...3, id: \.self) { count in
                                Text(L.Dashboard.columns(count)).tag(count)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    .padding(.leading, 20)
                }

                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text(settings.canShowDashboard
                         ? L.SettingsDashboard.description
                         : L.SettingsDashboard.needsMoreAccounts)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
