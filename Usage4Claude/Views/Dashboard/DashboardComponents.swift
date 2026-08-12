//
//  DashboardComponents.swift
//  Usage4Claude
//
//  Dashboard（多账户总览）的可复用小部件：紧凑圆环、状态徽章、配色映射。
//  卡片本体见 AccountUsageCard.swift，容器见 DashboardView.swift。
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

// MARK: - 配色映射

/// 把 `LimitType` 映射到既有的 `UsageColorScheme` 配色，Dashboard 与菜单栏 / 详情窗口保持同一套色系
enum DashboardPalette {
    static func color(for type: LimitType, percentage: Double) -> Color {
        switch type {
        case .fiveHour:
            return UsageColorScheme.fiveHourColorSwiftUI(percentage)
        case .sevenDay:
            return UsageColorScheme.sevenDayColorSwiftUI(percentage)
        case .opusWeekly:
            return Color(UsageColorScheme.opusWeeklyColor(percentage))
        case .sonnetWeekly:
            return Color(UsageColorScheme.sonnetWeeklyColor(percentage))
        case .extraUsage:
            return Color(UsageColorScheme.extraUsageColor(percentage))
        case .codexPrimary:
            return UsageColorScheme.codexPrimaryColorSwiftUI(percentage)
        case .codexSecondary:
            return UsageColorScheme.codexSecondaryColorSwiftUI(percentage)
        case .codexExtraUsage:
            return UsageColorScheme.codexExtraUsageColorSwiftUI(percentage)
        }
    }
}

// MARK: - 紧凑圆环

/// 卡片左侧的紧凑双层圆环：内圈主限制（5 小时 / Codex primary），
/// 外圈次级限制（7 天 / Codex secondary）。语义与详情窗口的大圆环一致，
/// 只是尺寸缩到一张卡片放得下的程度。
struct DashboardUsageRing: View {
    let primaryPercentage: Double
    let primaryColor: Color
    /// Kurzname des Limits im Ringzentrum — beantwortet „0 % wovon?"
    let primaryLabel: String
    let secondaryPercentage: Double?
    let secondaryColor: Color
    let showRemainingMode: Bool
    let isLoading: Bool

    private let diameter: CGFloat = 58
    private let outerDiameter: CGFloat = 68

    private var primaryRange: UsageRingTrimRange {
        UsageRingDisplay.displayedTrimRange(
            usedPercentage: primaryPercentage,
            showRemainingMode: showRemainingMode
        )
    }

    private var displayedPercentage: Int {
        Int(UsageRingDisplay.displayedPercentage(
            usedPercentage: primaryPercentage,
            showRemainingMode: showRemainingMode
        ))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 7)
                .frame(width: diameter, height: diameter)

            Circle()
                .trim(from: primaryRange.from, to: primaryRange.to)
                .stroke(primaryColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(-90))
                .opacity(isLoading ? 0.35 : 1)
                .animation(.spring(response: 0.42, dampingFraction: 0.78), value: primaryRange)

            if let secondaryPercentage {
                let outerRange = UsageRingDisplay.displayedTrimRange(
                    usedPercentage: secondaryPercentage,
                    showRemainingMode: showRemainingMode
                )
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 2.5)
                    .frame(width: outerDiameter, height: outerDiameter)
                Circle()
                    .trim(from: outerRange.from, to: outerRange.to)
                    .stroke(secondaryColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: outerDiameter, height: outerDiameter)
                    .rotationEffect(.degrees(-90))
                    .opacity(isLoading ? 0.35 : 1)
                    .animation(.spring(response: 0.42, dampingFraction: 0.78), value: outerRange)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                VStack(spacing: 0) {
                    Text("\(displayedPercentage)%")
                        .font(.system(size: 17, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(primaryPercentage >= 100 ? .red : .primary)
                    // Nicht mehr nur „Verwendet": ohne den Limit-Namen ist unklar,
                    // worauf sich die Zahl bezieht (5-Stunden-Fenster? Woche? Opus?).
                    Text(primaryLabel)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: outerDiameter - 18)
                }
            }
        }
        .frame(width: outerDiameter, height: outerDiameter)
    }
}

// MARK: - 状态徽章

/// 卡片右上角的小徽章（当前账户 / 最空闲 / 已耗尽）
struct DashboardBadge: View {
    enum Style {
        case active
        case mostFree
        case exhausted

        var tint: Color {
            switch self {
            case .active:    return .blue
            case .mostFree:  return .green
            case .exhausted: return .red
            }
        }

        var systemImage: String {
            switch self {
            case .active:    return "checkmark.circle.fill"
            case .mostFree:  return "leaf.fill"
            case .exhausted: return "exclamationmark.triangle.fill"
            }
        }

        var title: String {
            switch self {
            case .active:    return L.Dashboard.badgeActive
            case .mostFree:  return L.Dashboard.badgeMostFree
            case .exhausted: return L.Dashboard.badgeExhausted
            }
        }
    }

    let style: Style

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: style.systemImage)
                .font(.system(size: 8, weight: .semibold))
            Text(style.title)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(style.tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(style.tint.opacity(0.13))
        )
    }
}
