//
//  AccountUsageCard.swift
//  Usage4Claude
//
//  Eine Konto-Karte der Übersicht.
//
//  Aufbau: links der Wasserstand für das Sitzungsfenster, rechts groß das
//  Wochenlimit — die Zahl, an der die Planung hängt. Darunter die frei
//  konfigurierbaren übrigen Limits als Balken (Anzeigeoptionen gelten hier
//  genauso wie im klassischen Fenster).
//
//  Klick auf die Karte macht das Konto zum aktiven, dem die Menüleiste folgt.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

struct AccountUsageCard: View {
    let snapshot: AccountUsageSnapshot
    /// Aktives Konto des jeweiligen Anbieters (dem die Menüleiste folgt).
    /// Wird nur noch durch den farbigen Kartenrand angezeigt.
    let isCurrent: Bool
    @Binding var showRemainingMode: Bool
    let onSelect: () -> Void
    let onRefresh: () -> Void
    let onOpenAuthSettings: () -> Void

    @State private var isHovering = false

    /// Unterhalb dieser Restzeit zeigt die Karte einen Countdown statt eines Datums.
    private static let countdownWindow: TimeInterval = 3 * 24 * 3600

    /// Limits für die Zeilen unter dem Kopfbereich. Sitzungs- und Wochenfenster
    /// sind oben schon prominent vertreten und werden hier nicht wiederholt.
    private var rowTypes: [LimitType] {
        let promoted: Set<LimitType> = snapshot.provider == .claude
            ? [.fiveHour, .sevenDay]
            : [.codexPrimary, .codexSecondary]
        return DashboardMetrics.activeTypes(for: snapshot).filter { !promoted.contains($0) }
    }

    private var overflowWeeklyModels: [(offset: Int, element: UsageData.WeeklyModelLimit)] {
        DashboardMetrics.overflowWeeklyModels(for: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .padding(12)
        .frame(width: DashboardMetrics.cardWidth, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(isHovering ? 0.95 : 0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: isCurrent ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { isHovering = $0 }
        .saturation(snapshot.isNearExhausted && !isHovering ? 0.3 : 1)
        .opacity(dimLevel)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button(action: onRefresh) {
                Label(L.Dashboard.refreshAccount, systemImage: "arrow.clockwise")
            }
            if !isCurrent {
                Button(action: onSelect) {
                    Label(L.Dashboard.makeActive, systemImage: "checkmark.circle")
                }
            }
        }
    }

    private var borderColor: Color {
        if isCurrent { return Color.accentColor.opacity(0.55) }
        return Color.primary.opacity(isHovering ? 0.18 : 0.08)
    }

    /// Fast erschöpfte Konten werden gedämpft dargestellt (man nutzt sie bis zum
    /// Reset ohnehin nicht). Beim Überfahren mit der Maus kommen sie zum
    /// Inspizieren wieder nach vorn.
    private var dimLevel: Double {
        guard snapshot.isNearExhausted else { return 1 }
        return isHovering ? 0.85 : 0.45
    }

    // MARK: - Kopfbereich

    private var header: some View {
        HStack(alignment: .top, spacing: 6) {
            providerIcon
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.account.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Anmelde-Email als zweite Zeile — bei Konten, deren Anzeigename
                // ohnehin die Email ist, entfällt sie (siehe Account.secondaryLabel).
                if let email = snapshot.account.secondaryLabel {
                    Text(email)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)

            if isHovering {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(L.Dashboard.refreshAccount)
            }
        }
    }

    @ViewBuilder
    private var providerIcon: some View {
        let size: CGFloat = 14
        if snapshot.provider == .claude {
            if let icon = ImageHelper.createAppIcon(size: size) {
                Image(nsImage: icon).resizable().frame(width: size, height: size)
            } else {
                Image(systemName: "chart.pie.fill").font(.system(size: size)).foregroundColor(.blue)
            }
        } else if let icon = ImageHelper.createCodexIcon(size: size) {
            Image(nsImage: icon).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: size - 2))
        }
    }

    // MARK: - Inhalt

    @ViewBuilder
    private var content: some View {
        if !snapshot.hasData, let error = snapshot.errorMessage {
            errorContent(error)
        } else if !snapshot.hasData {
            placeholderContent
        } else {
            VStack(alignment: .leading, spacing: 9) {
                headline
                // Trennstrich: unten steht ein eigener, frei konfigurierbarer Block —
                // die Kante macht sichtbar, dass er nicht zum Kopfbereich gehört.
                if !rowTypes.isEmpty || !overflowWeeklyModels.isEmpty || snapshot.errorMessage != nil {
                    Divider().opacity(0.6)
                    limitRows
                }
            }
        }
    }

    /// Wasserstand plus große Wochenzahl
    private var headline: some View {
        HStack(alignment: .center, spacing: 14) {
            WaterLevelGauge(
                percentage: snapshot.sessionLimit?.percentage ?? 0,
                caption: snapshot.sessionLimit?.label ?? L.Usage.fiveHourLimitShort,
                diameter: DashboardMetrics.ringSlotWidth
            )

            VStack(alignment: .leading, spacing: 2) {
                let weekly = snapshot.weeklyLimit
                let percentage = weekly?.percentage ?? 0

                Text("\(Int(percentage.rounded()))%")
                    .font(.system(size: 30, weight: .semibold).monospacedDigit())
                    .foregroundColor(DashboardPalette.ink(percentage))

                Text(L.Dashboard.weeklyLimit)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                resetLine(for: weekly)
            }

            Spacer(minLength: 0)
        }
    }

    /// Dritte Zeile: Countdown, wenn die Freischaltung in weniger als drei Tagen
    /// ansteht, sonst das Datum. Der genaue Tag mit Uhrzeit steht immer im Tooltip.
    @ViewBuilder
    private func resetLine(for limit: AccountUsageSnapshot.RingLimit?) -> some View {
        if let limit, let resetsAt = limit.resetsAt {
            let data = UsageData.LimitData(percentage: limit.percentage, resetsAt: resetsAt)
            let remaining = resetsAt.timeIntervalSinceNow
            let isSoon = remaining > 0 && remaining < Self.countdownWindow

            // Die Zeile zählt selbst herunter, ohne dass die ganze Karte neu gebaut wird
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                Text(isSoon ? data.formattedCompactRemaining : data.formattedCompactResetDate)
                    .font(.system(size: 11))
                    .foregroundColor(limit.isExhausted ? DashboardPalette.ink(100) : .secondary)
                    .lineLimit(1)
            }
            .help(fullResetDescription(resetsAt))
        } else {
            Text("–")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private func fullResetDescription(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = UserSettings.shared.appLocale
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        let day = formatter.string(from: date)
        return "\(day) · \(TimeFormatHelper.formatTimeOnly(date))"
    }

    private var limitRows: some View {
        VStack(spacing: 4) {
            ForEach(rowTypes, id: \.self) { type in
                UnifiedLimitRow(
                    type: type,
                    data: snapshot.usageData,
                    codexData: snapshot.codexUsageData,
                    showRemainingMode: showRemainingMode,
                    usesUtilizationTint: true
                )
            }
            ForEach(overflowWeeklyModels, id: \.offset) { entry in
                UnifiedLimitRow(
                    type: entry.offset % 2 == 0 ? .opusWeekly : .sonnetWeekly,
                    data: snapshot.usageData,
                    showRemainingMode: showRemainingMode,
                    weeklyModelOverride: entry.element,
                    usesUtilizationTint: true
                )
            }

            // Abruf fehlgeschlagen, aber alte Daten noch vorhanden: Hinweis, dass
            // die Zahlen veraltet sein können.
            if let error = snapshot.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text(error)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundColor(DashboardPalette.ink(80))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                showRemainingMode.toggle()
            }
        }
    }

    private func errorContent(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundColor(DashboardPalette.ink(80))
                .frame(width: DashboardMetrics.ringSlotWidth)

            VStack(alignment: .leading, spacing: 6) {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(action: onRefresh) {
                        Text(L.Dashboard.retry).font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: onOpenAuthSettings) {
                        Text(L.Usage.goToSettings).font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .frame(minHeight: DashboardMetrics.ringSlotWidth)
    }

    private var placeholderContent: some View {
        HStack(alignment: .center, spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .frame(width: DashboardMetrics.ringSlotWidth)
            Text(L.Usage.loading)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: DashboardMetrics.ringSlotWidth)
    }
}
