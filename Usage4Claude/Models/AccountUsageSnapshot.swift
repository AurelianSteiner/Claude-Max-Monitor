//
//  AccountUsageSnapshot.swift
//  Usage4Claude
//
//  Dashboard（多账户总览）的单账户状态容器。
//  经典 popover 一次只看当前账户，Dashboard 则为每个账户各拉一次用量，
//  把「数据 / 错误 / 加载中 / 更新时间」打包在一起，卡片视图直接渲染，
//  不用在视图层再去拼多个并行字典。
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// 单个账户在 Dashboard 中的用量快照
struct AccountUsageSnapshot: Identifiable {
    /// 快照所属账户（含 provider、displayName 等展示信息）
    let account: Account
    /// Claude 用量数据（provider == .claude 时有效）
    var usageData: UsageData?
    /// Codex 用量数据（provider == .codex 时有效）
    var codexUsageData: CodexUsageData?
    /// 本账户最近一次拉取的错误描述，nil 表示无错误
    var errorMessage: String?
    /// 是否正在拉取
    var isLoading: Bool = false
    /// 最近一次成功拉取的时间
    var updatedAt: Date?

    var id: UUID { account.id }
    var provider: ProviderType { account.provider }

    /// 是否已有可展示的数据
    var hasData: Bool {
        switch provider {
        case .claude: return usageData != nil
        case .codex:  return codexUsageData != nil
        }
    }

    // MARK: - 排序 / 高亮用的派生值

    /// 本账户所有限制里最紧张的一项的使用率（0-100）。
    /// Dashboard 用它排序、并标出"还最空的账户"——也就是用户要的
    /// "welcher Claude ist gerade am Ende"。nil 表示尚无数据。
    var peakUtilization: Double? { criticalLimit?.percentage }

    /// 圆环要展示的一项限制，标签已解析好
    struct RingLimit {
        let type: LimitType
        let percentage: Double
        let resetsAt: Date?
        /// 圆环中心的短标签（"5h" / "7d" / Modellname …），damit klar ist,
        /// worauf sich die Prozentzahl bezieht
        let label: String

        var isExhausted: Bool { percentage >= 100 }
    }

    /// 本账户所有限制的清单（顺序无关，仅用于挑选与排序）
    private var allLimits: [RingLimit] {
        switch provider {
        case .claude:
            guard let data = usageData else { return [] }
            var result: [RingLimit] = []
            if let fiveHour = data.fiveHour {
                result.append(RingLimit(type: .fiveHour, percentage: fiveHour.percentage,
                                        resetsAt: fiveHour.resetsAt, label: L.Usage.fiveHourLimitShort))
            }
            if let sevenDay = data.sevenDay {
                result.append(RingLimit(type: .sevenDay, percentage: sevenDay.percentage,
                                        resetsAt: sevenDay.resetsAt, label: L.Usage.sevenDayLimitShort))
            }
            for (index, model) in data.weeklyModels.enumerated() {
                // 槽位仅决定配色，标签优先用 API 返回的真实模型名
                let type: LimitType = index % 2 == 0 ? .opusWeekly : .sonnetWeekly
                let fallback = type == .opusWeekly ? L.Dashboard.ringOpus : L.Dashboard.ringSonnet
                result.append(RingLimit(type: type, percentage: model.limit.percentage,
                                        resetsAt: model.limit.resetsAt, label: model.modelName ?? fallback))
            }
            if let extra = data.extraUsage, extra.enabled, let percentage = extra.percentage {
                result.append(RingLimit(type: .extraUsage, percentage: percentage,
                                        resetsAt: nil, label: L.Dashboard.ringExtra))
            }
            return result

        case .codex:
            guard let codex = codexUsageData else { return [] }
            var result: [RingLimit] = []
            if let primary = codex.primary {
                result.append(RingLimit(type: .codexPrimary, percentage: primary.percentage,
                                        resetsAt: primary.resetsAt, label: L.Usage.fiveHourLimitShort))
            }
            if let secondary = codex.secondary {
                result.append(RingLimit(type: .codexSecondary, percentage: secondary.percentage,
                                        resetsAt: secondary.resetsAt, label: L.Usage.sevenDayLimitShort))
            }
            if let extra = codex.extraUsage, let percentage = extra.percentage {
                result.append(RingLimit(type: .codexExtraUsage, percentage: percentage,
                                        resetsAt: nil, label: L.Dashboard.ringExtra))
            }
            return result
        }
    }

    /// Der große Ring zeigt das **engste** Limit, nicht fix das 5-Stunden-Fenster.
    /// Sonst steht auf der Karte „0 %", während in Wahrheit das Wochenlimit voll ist —
    /// genau die Verwechslung, die die Übersicht verhindern soll.
    var criticalLimit: RingLimit? {
        allLimits.max { $0.percentage < $1.percentage }
    }

    /// Das schnell laufende Sitzungsfenster (5 Stunden bzw. Codex primary).
    /// Füllt die Wasserstandsanzeige auf der Karte.
    var sessionLimit: RingLimit? {
        let type: LimitType = provider == .claude ? .fiveHour : .codexPrimary
        return allLimits.first { $0.type == type }
    }

    /// Das Wochenfenster — die Zahl, an der laut Nutzer "eigentlich alles hängt".
    var weeklyLimit: RingLimit? {
        let type: LimitType = provider == .claude ? .sevenDay : .codexSecondary
        return allLimits.first { $0.type == type }
    }
}
