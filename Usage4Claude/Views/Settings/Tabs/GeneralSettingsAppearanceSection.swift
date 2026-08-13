//
//  GeneralSettingsAppearanceSection.swift
//  Usage4Claude
//
//  Eine Karte für alles Optische: App-Erscheinungsbild, Menüleisten-Stil,
//  Zeitformat und Sprache. Früher vier einzelne Karten mit Radio-Gruppen —
//  als kompakte Auswahlmenüs passt das in einen Block, ohne dass die
//  Einstellungen zur Scrollstrecke werden.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

struct GeneralSettingsAppearanceSection: View {
    @ObservedObject private var settings = UserSettings.shared

    /// Breite der Beschriftungsspalte, damit alle Menüs bündig stehen
    private let labelWidth: CGFloat = 140

    var body: some View {
        SettingCard(
            icon: "paintpalette",
            iconColor: .indigo,
            title: L.SettingsGeneral.displaySection
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // App-Erscheinungsbild
                settingRow(label: L.SettingsGeneralAppearance.section) {
                    Picker("", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                }

                // Menüleiste: nur noch farbig oder einfarbig — den Inhalt
                // (ein Punkt je Konto) legt die App selbst fest.
                settingRow(label: L.DisplayOptions.menuBarLayout) {
                    Picker("", selection: $settings.iconStyleMode) {
                        Text(L.IconStyle.colorTranslucent).tag(IconStyleMode.colorTranslucent)
                        Text(L.IconStyle.monochrome).tag(IconStyleMode.monochrome)
                    }
                }

                caption(L.DisplayOptions.accountDotsDescription)

                // Zeitformat inklusive Vorschau der aktuellen Uhrzeit
                settingRow(label: L.SettingsGeneralTimeFormat.section) {
                    Picker("", selection: $settings.timeFormatPreference) {
                        ForEach(TimeFormatPreference.allCases, id: \.self) { format in
                            Text(format.localizedName).tag(format)
                        }
                    }
                }

                caption("\(L.SettingsGeneralTimeFormat.preview): \(TimeFormatHelper.formatTimeOnly(Date()))")

                // Oberflächensprache
                settingRow(label: L.SettingsGeneral.interfaceLanguage) {
                    Picker("", selection: $settings.language) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(lang.localizedName).tag(lang)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bausteine

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

    /// Erläuterung unter einer Zeile — über die volle Kartenbreite, sonst
    /// bricht der Satz neben der Beschriftungsspalte in zu viele Zeilen um.
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
