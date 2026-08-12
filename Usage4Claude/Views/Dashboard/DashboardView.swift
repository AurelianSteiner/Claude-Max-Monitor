//
//  DashboardView.swift
//  Usage4Claude
//
//  多账户总览：一屏之内并排显示所有已添加的 Claude / Codex 账户，
//  不再需要先切账户才能看另一个账号的余量。点任意卡片即把该账户设为当前账户。
//
//  同一个视图既用于菜单栏 popover，也用于独立的总览窗口（isStandaloneWindow）。
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

// MARK: - 尺寸计算

/// Dashboard 的布局常量与高度推算。
/// popover 依赖 `NSHostingController.sizingOptions = .preferredContentSize` 取内容
/// 理想尺寸，因此这里必须给出确定的高度——把卡片高度按行数算出来，而不是交给
/// 会无限伸展的 ScrollView 自行决定。
enum DashboardMetrics {
    static let cardWidth: CGFloat = 372
    static let ringSlotWidth: CGFloat = 68
    static let cardSpacing: CGFloat = 10
    static let outerPadding: CGFloat = 12
    static let headerHeight: CGFloat = 36
    static let footerHeight: CGFloat = 24
    /// 网格区域的最大高度，超过则内部滚动
    static let maxGridHeight: CGFloat = 520

    private static let rowHeight: CGFloat = 26
    private static let rowSpacing: CGFloat = 4
    // Innenabstand oben/unten + Kopfzeile (Name + Email) + Abstände + Headline-Block
    private static let cardChromeHeight: CGFloat = 12 * 2 + 30 + 10 + 10

    /// 卡片里要展示的限制行。沿用设置里的"智能 / 自定义显示"规则，
    /// 因此 Dashboard 与详情窗口显示的指标始终一致。
    static func activeTypes(for snapshot: AccountUsageSnapshot) -> [LimitType] {
        switch snapshot.provider {
        case .claude:
            guard let data = snapshot.usageData else { return [] }
            return UserSettings.shared.getActiveDisplayTypes(usageData: data)
                .filter { $0.provider == .claude }
        case .codex:
            guard let codex = snapshot.codexUsageData else { return [] }
            return UserSettings.shared.getActiveDisplayTypes(usageData: nil, codexUsageData: codex)
                .filter { $0.provider == .codex }
        }
    }

    /// 智能模式下第三个及以后的每周模型限制（如同时出现 Fable + Opus + Sonnet），
    /// 与详情窗口一致，避免 Dashboard 少显示指标。
    static func overflowWeeklyModels(for snapshot: AccountUsageSnapshot) -> [(offset: Int, element: UsageData.WeeklyModelLimit)] {
        guard snapshot.provider == .claude,
              UserSettings.shared.displayMode == .smart,
              let data = snapshot.usageData else { return [] }
        return Array(Array(data.weeklyModels.enumerated()).dropFirst(2))
    }

    static func cardHeight(for snapshot: AccountUsageSnapshot) -> CGFloat {
        guard snapshot.hasData else {
            // 错误 / 加载占位：两行文字 + 按钮的高度，取一个足够的固定值
            return cardChromeHeight + (snapshot.errorMessage != nil ? 86 : ringSlotWidth)
        }
        // Sitzungs- und Wochenfenster stehen im Headline-Block, nicht in den Zeilen
        let promoted: Set<LimitType> = snapshot.provider == .claude
            ? [.fiveHour, .sevenDay]
            : [.codexPrimary, .codexSecondary]
        let rowCount = activeTypes(for: snapshot).filter { !promoted.contains($0) }.count
            + overflowWeeklyModels(for: snapshot).count
        var rowsHeight = CGFloat(rowCount) * rowHeight + CGFloat(max(0, rowCount - 1)) * rowSpacing
        if rowCount > 0 { rowsHeight += 10 }
        if snapshot.errorMessage != nil {
            rowsHeight += 16  // Hinweiszeile "Daten möglicherweise veraltet"
        }
        return cardChromeHeight + ringSlotWidth + rowsHeight
    }

    static func gridHeight(for snapshots: [AccountUsageSnapshot], columns: Int) -> CGFloat {
        guard !snapshots.isEmpty else { return 120 }
        let columns = max(1, columns)
        var total: CGFloat = 0
        var index = 0
        while index < snapshots.count {
            let end = min(index + columns, snapshots.count)
            let rowMax = snapshots[index..<end].map { cardHeight(for: $0) }.max() ?? ringSlotWidth
            total += rowMax
            index = end
            if index < snapshots.count { total += cardSpacing }
        }
        return total
    }

    static func width(columns: Int) -> CGFloat {
        let columns = max(1, columns)
        return CGFloat(columns) * cardWidth
            + CGFloat(columns - 1) * cardSpacing
            + outerPadding * 2
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var manager: DashboardRefreshManager
    /// 菜单操作回调，复用详情窗口那套 MenuAction
    var onMenuAction: ((UsageDetailView.MenuAction) -> Void)?
    /// 独立窗口模式：不再提供"在窗口中打开"入口，也不需要退出按钮之外的窗口管理
    var isStandaloneWindow: Bool = false

    @ObservedObject private var settings = UserSettings.shared
    @StateObject private var localization = LocalizationManager.shared

    /// 与详情窗口共用同一个开关，两处的"剩余 / 已用"显示保持一致
    @AppStorage("showRemainingMode") private var savedRemainingMode = false
    @State private var showRemainingMode = UserDefaults.standard.bool(forKey: "showRemainingMode")
    @State private var isSpinning = false

    // MARK: - Derived data

    private var orderedSnapshots: [AccountUsageSnapshot] {
        switch settings.dashboardSortMode {
        case .accountOrder:
            return manager.snapshots
        case .availability:
            return manager.snapshots.sorted { lhs, rhs in
                // 尚无数据的账户排在最后，避免它们抢占"最空闲"的位置
                let left = lhs.peakUtilization ?? .greatestFiniteMagnitude
                let right = rhs.peakUtilization ?? .greatestFiniteMagnitude
                if left == right { return lhs.account.createdAt < rhs.account.createdAt }
                return left < right
            }
        }
    }

    /// 当前最空闲的账户 id：只有存在至少两个有数据的账户时才标注，
    /// 否则这个徽章没有比较意义。
    private var mostFreeAccountId: UUID? {
        let withData = manager.snapshots.filter { $0.peakUtilization != nil }
        guard withData.count >= 2 else { return nil }
        return withData.min {
            ($0.peakUtilization ?? 100) < ($1.peakUtilization ?? 100)
        }?.id
    }

    private var columnCount: Int {
        min(max(1, settings.dashboardColumns), max(1, orderedSnapshots.count))
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(DashboardMetrics.cardWidth), spacing: DashboardMetrics.cardSpacing, alignment: .top),
            count: columnCount
        )
    }

    private var gridHeight: CGFloat {
        min(
            DashboardMetrics.gridHeight(for: orderedSnapshots, columns: columnCount),
            DashboardMetrics.maxGridHeight
        )
    }

    private func isCurrent(_ snapshot: AccountUsageSnapshot) -> Bool {
        switch snapshot.provider {
        case .claude: return snapshot.id == settings.currentAccountId
        case .codex:  return snapshot.id == settings.currentCodexAccountId
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            grid
            Divider()
            footer
        }
        .frame(width: DashboardMetrics.width(columns: columnCount))
        .id(localization.updateTrigger)  // 语言变化时重新创建视图
        .onAppear {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showRemainingMode = savedRemainingMode
            }
            manager.activate()
        }
        .onDisappear {
            manager.deactivate()
        }
        .onChange(of: showRemainingMode) { newValue in
            savedRemainingMode = newValue
        }
        .onChange(of: manager.isRefreshing) { refreshing in
            isSpinning = refreshing
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if let icon = ImageHelper.createAppIcon(size: 18) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            }

            Text(L.Dashboard.title)
                .font(.headline)

            Text("\(orderedSnapshots.count)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))

            Spacer(minLength: 8)

            sortMenu
            refreshButton
            actionMenu
        }
        .padding(.horizontal, DashboardMetrics.outerPadding)
        .frame(height: DashboardMetrics.headerHeight)
    }

    private var sortMenu: some View {
        // Bewusst Buttons mit Häkchen statt Picker: ein Picker mit verstecktem Label
        // rendert im Menü als unbeschriftetes Untermenü — dieselbe Machart wie die
        // Account-Auswahl im klassischen Detailfenster.
        Menu {
            ForEach(DashboardSortMode.allCases, id: \.self) { mode in
                Button(action: { settings.dashboardSortMode = mode }) {
                    HStack {
                        Text(mode.localizedName)
                        if settings.dashboardSortMode == mode {
                            Spacer(); Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            ForEach(1...3, id: \.self) { count in
                Button(action: { settings.dashboardColumns = count }) {
                    HStack {
                        Text(L.Dashboard.columns(count))
                        if settings.dashboardColumns == count {
                            Spacer(); Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .buttonStyle(.plain)
        .focusable(false)
        .help(L.Dashboard.sortHelp)
    }

    private var refreshButton: some View {
        Button(action: { manager.refresh(force: true) }) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .animation(
                    isSpinning
                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                        : .default,
                    value: isSpinning
                )
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(manager.isRefreshing)
        .focusable(false)
        .help(L.Usage.refresh)
    }

    private var actionMenu: some View {
        Menu {
            if !isStandaloneWindow {
                Button(action: { onMenuAction?(.openDashboardWindow) }) {
                    Label(L.Dashboard.openWindow, systemImage: "macwindow")
                }
            }
            Button(action: { onMenuAction?(.showClassicDetail) }) {
                Label(L.Dashboard.showClassicDetail, systemImage: "chart.pie")
            }
            Divider()
            Button(action: { onMenuAction?(.generalSettings) }) {
                Label(L.Menu.generalSettings, systemImage: "gearshape")
            }
            Button(action: { onMenuAction?(.authSettings) }) {
                Label(L.Menu.authSettings, systemImage: "key")
            }
            Button(action: { onMenuAction?(.checkForUpdates) }) {
                Label(L.Menu.checkUpdates, systemImage: "arrow.triangle.2.circlepath")
            }
            Button(action: { onMenuAction?(.about) }) {
                Label(L.Menu.about, systemImage: "info.circle")
            }
            Divider()
            if !settings.accounts.isEmpty {
                Button(action: { onMenuAction?(.claudeStatus) }) {
                    Label(L.Menu.claudeStatus, systemImage: "safari")
                }
            }
            if !settings.codexAccounts.isEmpty {
                Button(action: { onMenuAction?(.codexStatus) }) {
                    Label(L.Menu.codexStatus, systemImage: "safari.fill")
                }
            }
            Divider()
            Button(action: { onMenuAction?(.quit) }) {
                Label(L.Menu.quit, systemImage: "power")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(90))
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .buttonStyle(.plain)
        .focusable(false)
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: DashboardMetrics.cardSpacing) {
                ForEach(orderedSnapshots) { snapshot in
                    AccountUsageCard(
                        snapshot: snapshot,
                        isCurrent: isCurrent(snapshot),
                        showRemainingMode: $showRemainingMode,
                        onSelect: { select(snapshot) },
                        onRefresh: { manager.refreshAccount(id: snapshot.id) },
                        onOpenAuthSettings: { onMenuAction?(.authSettings) }
                    )
                }
            }
            .padding(DashboardMetrics.outerPadding)
        }
        .frame(height: gridHeight + DashboardMetrics.outerPadding * 2)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Text(L.Dashboard.tapHint)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let last = manager.lastRefreshAt {
                Text(L.Dashboard.updatedAt(TimeFormatHelper.formatTimeOnly(last)))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, DashboardMetrics.outerPadding)
        .frame(height: DashboardMetrics.footerHeight)
    }

    // MARK: - Actions

    private func select(_ snapshot: AccountUsageSnapshot) {
        switch snapshot.provider {
        case .claude:
            settings.switchToAccount(snapshot.account)
        case .codex:
            settings.switchToCodexAccount(snapshot.account)
        }
    }
}
