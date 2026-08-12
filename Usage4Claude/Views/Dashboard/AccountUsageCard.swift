//
//  AccountUsageCard.swift
//  Usage4Claude
//
//  Dashboard 里代表一个账户的卡片：左边紧凑圆环，右边复用详情窗口那套
//  `UnifiedLimitRow` 限制行，右上角是状态徽章。点卡片即把该账户设为当前账户，
//  菜单栏图标随之跟随。
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

struct AccountUsageCard: View {
    let snapshot: AccountUsageSnapshot
    /// 是否是对应 Provider 的当前账户（菜单栏图标显示的那个）
    let isCurrent: Bool
    /// 是否是本轮所有账户里最空闲的一个
    let isMostFree: Bool
    @Binding var showRemainingMode: Bool
    let onSelect: () -> Void
    let onRefresh: () -> Void
    let onOpenAuthSettings: () -> Void

    @State private var isHovering = false

    /// 用量到达 90% 视为"接近耗尽"，与通知阈值和圆环红色区间保持一致
    private static let exhaustedThreshold: Double = 90

    private var isExhausted: Bool {
        (snapshot.peakUtilization ?? 0) >= Self.exhaustedThreshold
    }

    // 展示哪些限制行、以及溢出的每周模型限制，都由 DashboardMetrics 统一决定——
    // 卡片渲染和 popover 的高度推算必须用同一份规则，否则高度会算错。
    private var activeTypes: [LimitType] {
        DashboardMetrics.activeTypes(for: snapshot)
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
        .help(snapshot.account.displayName)
    }

    private var borderColor: Color {
        if isCurrent { return Color.accentColor.opacity(0.55) }
        return Color.primary.opacity(isHovering ? 0.18 : 0.08)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            providerIcon

            Text(snapshot.account.displayName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            // Status- und "aktiv"-Badge schließen sich nicht aus: gerade beim
            // aktiven Konto ist die Warnung "fast aufgebraucht" die wichtigste
            // Information — sie darf nicht vom Aktiv-Badge verdeckt werden.
            if isExhausted {
                DashboardBadge(style: .exhausted)
            } else if isMostFree {
                DashboardBadge(style: .mostFree)
            }

            if isCurrent {
                DashboardBadge(style: .active)
            }

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
        .frame(height: 16)
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

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !snapshot.hasData, let error = snapshot.errorMessage {
            errorContent(error)
        } else if !snapshot.hasData {
            placeholderContent
        } else {
            HStack(alignment: .top, spacing: 10) {
                ring
                limitRows
            }
        }
    }

    private var ring: some View {
        // Großer Ring = das engste Limit (nicht fix das 5-Stunden-Fenster),
        // dünner Außenring = das Sitzungsfenster als Kontext.
        let critical = snapshot.criticalLimit
        let context = snapshot.contextLimit
        let percentage = critical?.percentage ?? 0

        return DashboardUsageRing(
            primaryPercentage: percentage,
            primaryColor: DashboardPalette.color(for: critical?.type ?? .fiveHour, percentage: percentage),
            primaryLabel: critical?.label ?? "–",
            secondaryPercentage: context?.percentage,
            secondaryColor: DashboardPalette.color(
                for: context?.type ?? .fiveHour,
                percentage: context?.percentage ?? 0
            ),
            showRemainingMode: showRemainingMode,
            isLoading: snapshot.isLoading && !snapshot.hasData
        )
    }

    private var limitRows: some View {
        VStack(spacing: 4) {
            ForEach(activeTypes, id: \.self) { type in
                UnifiedLimitRow(
                    type: type,
                    data: snapshot.usageData,
                    codexData: snapshot.codexUsageData,
                    showRemainingMode: showRemainingMode
                )
            }
            ForEach(overflowWeeklyModels, id: \.offset) { entry in
                UnifiedLimitRow(
                    type: entry.offset % 2 == 0 ? .opusWeekly : .sonnetWeekly,
                    data: snapshot.usageData,
                    showRemainingMode: showRemainingMode,
                    weeklyModelOverride: entry.element
                )
            }

            // 拉取失败但仍有上一轮数据时，用一行淡色提示说明数字可能过时
            if let error = snapshot.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text(error)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundColor(.orange)
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
                .foregroundColor(.orange)
                .frame(width: DashboardMetrics.ringSlotWidth)

            VStack(alignment: .leading, spacing: 6) {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(action: onRefresh) {
                        Text(L.Dashboard.retry)
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: onOpenAuthSettings) {
                        Text(L.Usage.goToSettings)
                            .font(.system(size: 10))
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
