//
//  MenuBarIconRenderer.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-02.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI
import AppKit

/// 菜单栏图标渲染器
/// 负责所有图标的绘制逻辑，支持彩色和单色两种模式
/// 从 MenuBarUI 中提取以实现职责分离
class MenuBarIconRenderer {
    
    // MARK: - Settings Reference
    
    /// 用户设置实例
    private let settings: UserSettings
    /// 菜单栏品牌图标尺寸
    private let providerBrandIconSize: CGFloat = 16
    /// 菜单栏指标图标尺寸
    private let metricIconSize: CGFloat = 18
    
    // MARK: - Initialization
    
    init(settings: UserSettings = .shared) {
        self.settings = settings
    }

    // MARK: - Display Mode

    /// Anzeigemodus für die *Ring*-Pfade weiter unten.
    /// Die Punktreihe wird ganz oben in `createIcon` abgefangen; kommt der Code
    /// trotzdem hier an, liegen für die Punkte noch keine Kontodaten vor — dann
    /// zeigt die Menüleiste weiter das gewohnte Bild statt gar nichts.
    private var effectiveDisplayMode: IconDisplayMode {
        settings.iconDisplayMode == .accountDots ? .percentageOnly : settings.iconDisplayMode
    }

    // MARK: - Public API

    /// 创建菜单栏图标
    /// - Parameters:
    ///   - usageData: Claude 用量数据
    ///   - codexUsageData: Codex 用量数据（nil 表示无 Codex 账号）
    ///   - hasUpdate: 是否有可用更新
    ///   - button: 状态栏按钮（用于获取外观模式）
    /// - Returns: 生成的图标图像
    func createIcon(
        usageData: UsageData?,
        codexUsageData: CodexUsageData? = nil,
        hasUpdate: Bool,
        button: NSStatusBarButton?
    ) -> NSImage {
        // Punktreihe aller Konten: eigener, sehr schmaler Pfad — er ersetzt die
        // Ringe komplett und interessiert sich weder für UsageData des aktuellen
        // Kontos noch für die Limit-Auswahl.
        if settings.iconDisplayMode == .accountDots {
            let dots = MenuBarAccountDots.shared.currentStates()
            if !dots.isEmpty {
                // Für die Punkte zählt allein die Theme-Wahl: die Farben sind unsere
                // eigene Ampel, nicht die limitabhängige Palette der Ringe.
                let dotsMonochrome = settings.iconStyleMode == .monochrome
                var icon = createAccountDotsIcon(states: dots, isMonochrome: dotsMonochrome, button: button)
                if hasUpdate { icon = addBadgeToImage(icon) }
                return icon
            }
            // Noch keine Daten geladen → unten weiter mit der bisherigen Darstellung
            // (siehe `effectiveDisplayMode`), statt eine leere Fläche zu zeigen.
        }

        // 确定单色/彩色模式
        let isMonochrome: Bool
        if let data = usageData {
            let canUseColor = settings.canUseColoredTheme(usageData: data)
            let forceMonochrome = !canUseColor && settings.iconStyleMode != .monochrome
            isMonochrome = settings.iconStyleMode == .monochrome || forceMonochrome
        } else {
            isMonochrome = settings.iconStyleMode == .monochrome
        }

        var icon: NSImage

        if let codex = codexUsageData {
            // 有 Codex 数据路径
            let allTypes = settings.getActiveDisplayTypes(usageData: usageData, codexUsageData: codex, forMenuBar: true)
            let codexTypes = allTypes.filter { $0.provider == .codex }

            if settings.isMultiProviderActive, let data = usageData {
                // 双 Provider 模式
                let claudeTypes = allTypes.filter { $0.provider == .claude }
                icon = createMultiProviderIcon(data: data, codex: codex, claudeTypes: claudeTypes, codexTypes: codexTypes, isMonochrome: isMonochrome, button: button)
            } else {
                // Codex-only（无 Claude 账号）或降级路径
                icon = createCodexOnlyIcon(codex: codex, codexTypes: codexTypes, isMonochrome: isMonochrome, button: button)
            }
        } else {
            // Claude-only 路径（原有逻辑）
            guard let data = usageData else {
                let size = NSSize(width: 22, height: 22)
                let defaultIcon: NSImage
                if effectiveDisplayMode == .none {
                    defaultIcon = createMenuBarDividerIcon(isMonochrome: isMonochrome)
                } else {
                    defaultIcon = isMonochrome ?
                        createCircleTemplateImage(percentage: 0, size: size, button: button, removeBackground: true) :
                        createCircleImage(percentage: 0, size: size, button: button, removeBackground: true)
                }
                if hasUpdate { return addBadgeToImage(defaultIcon) }
                return defaultIcon
            }

            let activeTypes = settings.getActiveDisplayTypes(usageData: data, forMenuBar: true)

            switch effectiveDisplayMode {
            // `.accountDots` landet hier nur als Rückfall (noch keine Kontodaten),
            // dann sieht die Menüleiste aus wie bisher: Ringe des aktuellen Kontos.
            case .percentageOnly, .accountDots:
                icon = createCombinedPercentageIcon(data: data, types: activeTypes, isMonochrome: isMonochrome, button: button)
            case .iconOnly:
                let iconName = isMonochrome ? "AppIconReverse" : "AppIcon"
                if let iconCopy = ImageHelper.createSquareIcon(named: iconName, size: providerBrandIconSize, isTemplate: isMonochrome) {
                    icon = iconCopy
                } else {
                    icon = createSimpleCircleIcon()
                }
            case .both:
                icon = createCombinedIconWithAppIcon(data: data, types: activeTypes, isMonochrome: isMonochrome, button: button)
            case .none:
                icon = createMenuBarDividerIcon(isMonochrome: isMonochrome)
            }
        }

        if hasUpdate { icon = addBadgeToImage(icon) }
        return icon
    }

    // MARK: - Multi-Provider Icon Creation

    /// 双 Provider 模式图标：[Claude 品牌] + [Claude 指标] + [Codex 品牌] + [Codex 指标]
    private func createMultiProviderIcon(
        data: UsageData,
        codex: CodexUsageData,
        claudeTypes: [LimitType],
        codexTypes: [LimitType],
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) -> NSImage {
        var icons: [NSImage] = []

        // `.accountDots` erreicht diesen Pfad nur als Rückfall ohne Kontodaten und
        // verhält sich dann wie `.percentageOnly` (siehe `effectiveDisplayMode`).
        let mode = effectiveDisplayMode

        switch mode {
        case .iconOnly:
            let iconName = isMonochrome ? "AppIconReverse" : "AppIcon"
            if let copy = ImageHelper.createSquareIcon(named: iconName, size: providerBrandIconSize, isTemplate: isMonochrome) {
                icons.append(copy)
            }

        case .percentageOnly, .both, .accountDots:
            // Claude 部分
            let claudeIcons = claudeTypes.compactMap { createIconForType($0, data: data, isMonochrome: isMonochrome, button: button) }
            if !claudeIcons.isEmpty {
                if mode == .both {
                    let iconName = isMonochrome ? "AppIconReverse" : "AppIcon"
                    if let copy = ImageHelper.createSquareIcon(named: iconName, size: providerBrandIconSize, isTemplate: isMonochrome) {
                        icons.append(copy)
                    }
                }
                icons.append(contentsOf: claudeIcons)
            }

            // Codex 部分
            let codexIcons = buildCodexIcons(codex: codex, types: codexTypes, isMonochrome: isMonochrome, button: button)
            if !codexIcons.isEmpty {
                if mode == .percentageOnly, !claudeIcons.isEmpty {
                    icons.append(createMenuBarDividerIcon(isMonochrome: isMonochrome))
                } else if mode == .both,
                   let brand = createProviderBrandIcon(.codex, isMonochrome: isMonochrome, size: providerBrandIconSize) {
                    icons.append(brand)
                }
                icons.append(contentsOf: codexIcons)
            }

        case .none:
            // 不显示图标：仅显示轻量分隔线，保留可点击的状态栏锚点
            icons.append(createMenuBarDividerIcon(isMonochrome: isMonochrome))
        }

        let combined = icons.isEmpty ? createSimpleCircleIcon() : combineIcons(icons, spacing: 2.0, height: metricIconSize)
        combined.isTemplate = isMonochrome
        return combined
    }

    /// Codex-only 模式图标（无 Claude 账号时）
    private func createCodexOnlyIcon(
        codex: CodexUsageData,
        codexTypes: [LimitType],
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) -> NSImage {
        // `.accountDots` erreicht diesen Pfad nur als Rückfall ohne Kontodaten und
        // verhält sich dann wie `.percentageOnly` (siehe `effectiveDisplayMode`).
        let mode = effectiveDisplayMode

        switch mode {
        case .none:
            return createMenuBarDividerIcon(isMonochrome: isMonochrome)

        case .iconOnly:
            return createProviderBrandIcon(.codex, isMonochrome: isMonochrome, size: providerBrandIconSize) ?? createSimpleCircleIcon()

        case .percentageOnly, .both, .accountDots:
            var icons: [NSImage] = []
            if mode == .both,
               let brand = createProviderBrandIcon(.codex, isMonochrome: isMonochrome, size: providerBrandIconSize) {
                icons.append(brand)
            }
            icons.append(contentsOf: buildCodexIcons(codex: codex, types: codexTypes, isMonochrome: isMonochrome, button: button))
            if icons.isEmpty { return createSimpleCircleIcon() }
            let combined = icons.count == 1 ? icons[0] : combineIcons(icons, spacing: 3.0, height: metricIconSize)
            combined.isTemplate = isMonochrome
            return combined
        }
    }

    /// 构建 Codex 指标图标列表
    private func buildCodexIcons(codex: CodexUsageData, types: [LimitType], isMonochrome: Bool, button: NSStatusBarButton?) -> [NSImage] {
        let showPlaceholder = settings.displayMode == .custom
        return types.compactMap { type -> NSImage? in
            switch type {
            case .codexPrimary:
                let percentage = codex.primary?.percentage ?? (showPlaceholder ? 0 : nil)
                return percentage.flatMap { createCodexIcon(type: type, percentage: $0, isMonochrome: isMonochrome, button: button) }
            case .codexSecondary:
                let percentage = codex.secondary?.percentage ?? (showPlaceholder ? 0 : nil)
                return percentage.flatMap { createCodexIcon(type: type, percentage: $0, isMonochrome: isMonochrome, button: button) }
            case .codexExtraUsage:
                let percentage: Double?
                if let extra = codex.extraUsage, extra.enabled {
                    percentage = extra.percentage
                } else if showPlaceholder {
                    percentage = 0
                } else {
                    percentage = nil
                }
                return percentage.flatMap { createCodexIcon(type: type, percentage: $0, isMonochrome: isMonochrome, button: button) }
            default:
                return nil
            }
        }
    }

    /// 创建 Provider 品牌图标（用于多 Provider 模式下的视觉分组）
    private func createProviderBrandIcon(_ provider: ProviderType, isMonochrome: Bool, size: CGFloat = 14) -> NSImage? {
        switch provider {
        case .claude:
            let iconName = isMonochrome ? "AppIconReverse" : "AppIcon"
            return ImageHelper.createSquareIcon(named: iconName, size: size, isTemplate: isMonochrome)
        case .codex:
            let iconName = isMonochrome ? "CodexIconReverse" : "CodexIcon"
            return ImageHelper.createSquareIcon(named: iconName, size: size, isTemplate: isMonochrome, sourceInset: isMonochrome ? 0 : 2)
        }
    }

    /// 创建仅百分比的组合图标
    private func createCombinedPercentageIcon(
        data: UsageData,
        types: [LimitType],
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) -> NSImage {
        guard !types.isEmpty else {
            return createSimpleCircleIcon()
        }

        // 为每个类型创建图标
        let icons = types.compactMap { type in
            createIconForType(type, data: data, isMonochrome: isMonochrome, button: button)
        }

        // 组合图标
        if icons.isEmpty {
            return createSimpleCircleIcon()
        } else if icons.count == 1 {
            return icons[0]
        } else {
            let combined = combineIcons(icons, spacing: 3.0, height: 18)
            combined.isTemplate = isMonochrome
            return combined
        }
    }

    /// 创建 App 图标 + 百分比的组合图标
    private func createCombinedIconWithAppIcon(
        data: UsageData,
        types: [LimitType],
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) -> NSImage {
        // 获取 App 图标（单色模式使用反转图标）
        let iconName = isMonochrome ? "AppIconReverse" : "AppIcon"
        guard let appIconCopy = ImageHelper.createSquareIcon(named: iconName, size: providerBrandIconSize, isTemplate: isMonochrome) else {
            return createCombinedPercentageIcon(data: data, types: types, isMonochrome: isMonochrome, button: button)
        }

        // 创建百分比图标
        let percentageIcons = types.compactMap { type in
            createIconForType(type, data: data, isMonochrome: isMonochrome, button: button)
        }

        // 组合 App 图标 + 百分比图标
        var allIcons = [appIconCopy]
        allIcons.append(contentsOf: percentageIcons)

        let combined = combineIcons(allIcons, spacing: 3.0, height: metricIconSize)
        combined.isTemplate = isMonochrome
        return combined
    }
    
    // MARK: - Account Dots (Punktreihe aller Konten)

    /// Maße der Menüleisten-Punktreihe. Bewusst kleiner als die Ampelpunkte der
    /// Übersicht (`TrafficDotMetrics`): hier zählt jeder Punkt Breite. Fünf Konten
    /// belegen so ~70 pt statt ~100 pt für fünf Ringe — genau darum geht es auf
    /// MacBooks mit Notch, wo macOS zu breite Statusleisten-Symbole ausblendet.
    private enum AccountDotMetrics {
        /// Durchmesser der farbigen Fläche (Wochenlage)
        static let fillDiameter: CGFloat = 7.5
        /// Luft zwischen Fläche und Sitzungsring
        static let ringGap: CGFloat = 1
        /// Strichstärke des Sitzungsrings
        static let ringWidth: CGFloat = 1
        /// Abstand zwischen zwei Punkten
        static let spacing: CGFloat = 3
        /// Platzbedarf eines Punkts inklusive Ring (7,5 + 2 × (1 + 1) = 11,5)
        static var footprint: CGFloat { fillDiameter + 2 * (ringGap + ringWidth) }

        // Wach-Kapsel: Umriss um die ganze Punktreihe, solange „Bleib wach"
        // aktiv ist — ein Blick auf die Menüleiste genügt dann.
        /// Strichstärke der Kapsel
        static let capsuleLineWidth: CGFloat = 1.5
        /// Luft zwischen Punktreihe und Kapsel-Innenkante
        static let capsuleGap: CGFloat = 2
        /// Zusätzlicher Rand des Bilds je Seite, damit die Kapsel nicht
        /// beschnitten wird (Luft + volle Strichstärke)
        static var capsuleInset: CGFloat { capsuleGap + capsuleLineWidth }
    }

    /// Zeichnet eine Punktreihe: ein Punkt je Konto.
    ///
    /// Die Reihenfolge kommt fertig sortiert aus `MenuBarAccountDots` und ist
    /// **dieselbe wie in der Übersicht** (`AccountUsageSnapshot.ordered(_:mode:)`):
    /// im Standardmodus das freieste Konto links, das vollste rechts. Hier wird
    /// nur noch von links nach rechts gezeichnet, nicht mehr umsortiert.
    /// - Parameters:
    ///   - states: Zustände aus `MenuBarAccountDots` (bereits auf Ampelstufe reduziert
    ///     und in Anzeigereihenfolge)
    ///   - isMonochrome: Einfarbig-Modus → Template-Bild ohne Farbe
    private func createAccountDotsIcon(
        states: [MenuBarDotState],
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) -> NSImage {
        let footprint = AccountDotMetrics.footprint
        let height = metricIconSize
        let dotsWidth = max(
            CGFloat(states.count) * footprint
                + CGFloat(max(0, states.count - 1)) * AccountDotMetrics.spacing,
            footprint
        )

        // „Bleib wach" aktiv → Kapsel um die ganze Reihe. Das Bild bekommt
        // dafür links und rechts etwas Rand, sonst würde der Strich beschnitten.
        // Der Cache-Key in `MenuBarUI.generateCacheKey` enthält dieses Flag,
        // sonst klebte das alte Bild nach dem Umschalten fest.
        let keepAwake = SleepGuard.shared.isAwake
        let inset = keepAwake ? AccountDotMetrics.capsuleInset : 0
        let width = dotsWidth + 2 * inset

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        // Dynamische Systemfarben (systemGreen, labelColor …) lösen sich nach der
        // *aktuellen* Zeichen-Appearance auf. Ohne diesen Wechsel zöge die Fenster-
        // statt der Menüleisten-Darstellung, und die Punkte wären im dunklen Modus
        // zu blass.
        let appearance = button?.effectiveAppearance ?? NSApp.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            drawAccountDots(states, isMonochrome: isMonochrome, height: height, xOffset: inset)
            if keepAwake {
                drawKeepAwakeCapsule(width: width, height: height, isMonochrome: isMonochrome)
            }
        }

        image.unlockFocus()
        // Einfarbig = Template-Bild: macOS wertet nur die Deckkraft aus und färbt
        // selbst ein. Farbe wäre dort wirkungslos, deshalb codiert im Einfarbig-Modus
        // die *Füllung* den Zustand (siehe `drawAccountDots`).
        image.isTemplate = isMonochrome
        return image
    }

    /// Kapsel-Umriss um die gesamte Punktreihe — das Menüleisten-Zeichen für
    /// „Bleib wach". Farbe: Orange im Farbmodus (warm, passt zum Maskottchen,
    /// kollidiert nicht mit der Grün/Blau/Rot-Ampel der Punkte), `labelColor`
    /// im Einfarbig-/Template-Modus (macOS färbt selbst ein).
    private func drawKeepAwakeCapsule(width: CGFloat, height: CGFloat, isMonochrome: Bool) {
        let lineWidth = AccountDotMetrics.capsuleLineWidth
        let capsuleHeight = AccountDotMetrics.footprint + 2 * AccountDotMetrics.capsuleGap
        let rect = NSRect(
            x: lineWidth / 2,
            y: (height - capsuleHeight) / 2,
            width: width - lineWidth,
            height: capsuleHeight
        )
        let capsule = NSBezierPath(roundedRect: rect, xRadius: capsuleHeight / 2, yRadius: capsuleHeight / 2)
        capsule.lineWidth = lineWidth
        (isMonochrome ? NSColor.labelColor : NSColor.systemOrange).setStroke()
        capsule.stroke()
    }

    private func drawAccountDots(_ states: [MenuBarDotState], isMonochrome: Bool, height: CGFloat, xOffset: CGFloat = 0) {
        let footprint = AccountDotMetrics.footprint
        let fill = AccountDotMetrics.fillDiameter
        let centerY = height / 2
        var x: CGFloat = xOffset

        for state in states {
            let centerX = x + footprint / 2
            let fillRect = NSRect(
                x: centerX - fill / 2,
                y: centerY - fill / 2,
                width: fill,
                height: fill
            )
            let fillPath = NSBezierPath(ovalIn: fillRect)

            if isMonochrome {
                // Ohne Farbe trägt die Füllung die Aussage:
                // voller Punkt = Woche aufgebraucht, hohler Punkt = noch Luft,
                // dünner hohler Punkt = noch keine Daten.
                switch state.bucket {
                case .exhausted:
                    NSColor.labelColor.setFill()
                    fillPath.fill()
                case .fresh, .inUse:
                    NSColor.labelColor.setStroke()
                    fillPath.lineWidth = 1.4
                    fillPath.stroke()
                case .noData:
                    NSColor.labelColor.withAlphaComponent(0.5).setStroke()
                    fillPath.lineWidth = 0.8
                    fillPath.stroke()
                }
            } else {
                weeklyDotColor(for: state.bucket).setFill()
                fillPath.fill()
            }

            if state.sessionExhausted {
                // Sitzungsfenster aufgebraucht → Ring außen, genau wie beim
                // Ampelpunkt der Übersicht: Füllung = Woche, Ring = Sitzung.
                let ringDiameter = footprint - AccountDotMetrics.ringWidth
                let ringRect = NSRect(
                    x: centerX - ringDiameter / 2,
                    y: centerY - ringDiameter / 2,
                    width: ringDiameter,
                    height: ringDiameter
                )
                let ringPath = NSBezierPath(ovalIn: ringRect)
                ringPath.lineWidth = AccountDotMetrics.ringWidth
                (isMonochrome ? NSColor.labelColor : NSColor.systemRed).setStroke()
                ringPath.stroke()
            }

            x += footprint + AccountDotMetrics.spacing
        }
    }

    /// Farben der Punktreihe — dieselbe Ampel wie `WeeklyTrafficLight` in der
    /// Übersicht, nur als `NSColor`, weil hier mit `NSBezierPath` gezeichnet wird.
    private func weeklyDotColor(for bucket: MenuBarDotState.WeeklyBucket) -> NSColor {
        switch bucket {
        case .noData: return NSColor.secondaryLabelColor.withAlphaComponent(0.5)
        case .fresh: return .systemGreen
        case .inUse: return .systemBlue
        case .exhausted: return .systemRed
        }
    }

    // MARK: - Icon Drawing - Colored Mode (彩色模式)

    private func createCircleImage(percentage: Double, size: NSSize, useSevenDayColor: Bool = false, colorOverride: NSColor? = nil, useDashedStyle: Bool = false, button: NSStatusBarButton?, removeBackground: Bool = false) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 2

        if !removeBackground {
            let backgroundCircle = NSBezierPath()
            backgroundCircle.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
            NSColor.white.withAlphaComponent(0.5).setFill()
            backgroundCircle.fill()
        }

        NSColor.gray.withAlphaComponent(0.5).setStroke()
        let backgroundPath = NSBezierPath()
        backgroundPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
        backgroundPath.lineWidth = 1.5

        // 7天/Codex secondary 限制使用虚线以区分实线圆
        if useSevenDayColor || useDashedStyle {
            let dashPattern: [CGFloat] = [3, 1]
            backgroundPath.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        }

        backgroundPath.stroke()

        let color: NSColor
        if let override = colorOverride {
            color = override
        } else {
            color = useSevenDayColor ? UsageColorScheme.sevenDayColorAdaptive(percentage, for: button) : UsageColorScheme.fiveHourColorAdaptive(percentage, for: button)
        }
        color.setStroke()

        let progressPath = NSBezierPath()
        let lineWidth: CGFloat = 2.5

        // 计算进度角度
        let baseAngle = CGFloat(percentage) / 100.0 * 360
        let circumference = 2 * CGFloat.pi * radius  // 圆周长
        let capAngle = (lineWidth / circumference) * 360  // 圆头延伸对应的角度

        let progressAngle: CGFloat
        let startAngle: CGFloat

        if percentage >= 100 {
            // 100%: 使用完整角度和固定起点，因为 .butt 端点无延伸
            progressAngle = baseAngle
            startAngle = 90
        } else {
            // 5小时/7天限制：使用渐进式减法，保持起点固定，实现平滑增长
            // 减去的角度随百分比线性增加，在50%时完成完整减法，50%-100%显示完全精确
            progressAngle = baseAngle - capAngle * min(1.0, CGFloat(percentage / 50.0))
            startAngle = 90 - capAngle / 2 + 0.5
        }

        let endAngle = startAngle - progressAngle

        progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        progressPath.lineWidth = lineWidth
        // 100%时使用平头让圆环完美闭合，其他进度使用圆头
        progressPath.lineCapStyle = percentage >= 100 ? .butt : .round
        progressPath.stroke()

        let fontSize: CGFloat = percentage >= 100 ? size.width * 0.275 : size.width * 0.4
        let font = NSFont.systemFont(ofSize: fontSize, weight: percentage >= 100 ? .bold : .semibold)
        let text = "\(Int(percentage))"
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraphStyle]
        let textSize = text.size(withAttributes: attrs)
        let textOrigin = NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2)
        text.draw(at: textOrigin, withAttributes: attrs)

        image.unlockFocus()
        return image
    }

    // MARK: - Icon Drawing - Template Mode (单色模式)

    private func createCircleTemplateImage(percentage: Double, size: NSSize, useSevenDayStyle: Bool = false, button: NSStatusBarButton? = nil, removeBackground: Bool = false) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 2

        NSColor.labelColor.withAlphaComponent(0.25).setStroke()
        let backgroundPath = NSBezierPath()
        backgroundPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
        backgroundPath.lineWidth = 1.5

        // 7天限制使用虚线以区分5小时限制
        if useSevenDayStyle {
            let dashPattern: [CGFloat] = [3, 1]
            backgroundPath.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        }

        backgroundPath.stroke()

        NSColor.labelColor.setStroke()
        let progressPath = NSBezierPath()
        let lineWidth: CGFloat = 2.5

        // 计算进度角度
        let baseAngle = CGFloat(percentage) / 100.0 * 360
        let circumference = 2 * CGFloat.pi * radius  // 圆周长
        let capAngle = (lineWidth / circumference) * 360  // 圆头延伸对应的角度

        let progressAngle: CGFloat
        let startAngle: CGFloat

        if percentage >= 100 {
            // 100%: 使用完整角度和固定起点，因为 .butt 端点无延伸
            progressAngle = baseAngle
            startAngle = 90
        } else {
            // 单色模式：使用渐进式减法，保持起点固定，实现平滑增长
            // 减去的角度随百分比线性增加，在50%时完成完整减法，50%-100%显示完全精确
            progressAngle = baseAngle - capAngle * min(1.0, CGFloat(percentage / 50.0))
            startAngle = 90 - capAngle / 2 + 0.5
        }

        let endAngle = startAngle - progressAngle

        progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        progressPath.lineWidth = lineWidth
        // 100%时使用平头让圆环完美闭合，其他进度使用圆头
        progressPath.lineCapStyle = percentage >= 100 ? .butt : .round
        progressPath.stroke()

        let fontSize: CGFloat = percentage >= 100 ? size.width * 0.275 : size.width * 0.4
        let font = NSFont.systemFont(ofSize: fontSize, weight: percentage >= 100 ? .bold : .semibold)
        let text = "\(Int(percentage))"
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraphStyle]
        let textSize = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2), withAttributes: attrs)

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - Utility Icons

    /// 创建简单圆形图标（备用）
    private func createSimpleCircleIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(x: 3, y: 3, width: 12, height: 12)
        let path = NSBezierPath(ovalIn: rect)

        NSColor.labelColor.setStroke()
        path.lineWidth = 2.0
        path.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// 在图标上添加徽章（小红点）
    private func addBadgeToImage(_ baseImage: NSImage) -> NSImage {
        let size = baseImage.size
        let expandedSize = NSSize(width: size.width + 2.5, height: size.height + 2.5)
        let badgedImage = NSImage(size: expandedSize)

        badgedImage.lockFocus()
        baseImage.draw(in: NSRect(origin: .zero, size: size))

        let badgeRadius: CGFloat = 2.0
        let badgeDiameter = badgeRadius * 2
        let badgeX = expandedSize.width - badgeDiameter - 1.5
        let badgeY = expandedSize.height - badgeDiameter - 1.5
        let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeDiameter, height: badgeDiameter)

        NSGraphicsContext.saveGraphicsState()
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        badgedImage.unlockFocus()
        badgedImage.isTemplate = baseImage.isTemplate

        return badgedImage
    }

    // MARK: - Icon Combination Methods (v2.0)

    /// 组合多个图标到单个图像
    /// - Parameters:
    ///   - icons: 要组合的图标数组
    ///   - spacing: 图标间距
    ///   - height: 统一高度（默认18）
    /// - Returns: 组合后的图标
    private func combineIcons(_ icons: [NSImage], spacing: CGFloat = 3.0, height: CGFloat = 18) -> NSImage {
        guard !icons.isEmpty else {
            return createSimpleCircleIcon()
        }

        // 计算总宽度
        let totalWidth = icons.reduce(0) { $0 + $1.size.width } + CGFloat(icons.count - 1) * spacing
        let size = NSSize(width: totalWidth, height: height)

        let image = NSImage(size: size)
        image.lockFocus()

        var currentX: CGFloat = 0
        for icon in icons {
            let y = (height - icon.size.height) / 2  // 垂直居中
            icon.draw(at: NSPoint(x: currentX, y: y),
                     from: NSRect(origin: .zero, size: icon.size),
                     operation: .sourceOver,
                     fraction: 1.0)
            currentX += icon.size.width + spacing
        }

        image.unlockFocus()
        return image
    }

    /// 根据限制类型和数据创建单个图标
    /// - Parameters:
    ///   - type: 限制类型
    ///   - data: 用量数据
    ///   - isMonochrome: 是否为单色模式
    ///   - button: 状态栏按钮
    /// - Returns: 图标图像
    func createIconForType(
        _ type: LimitType,
        data: UsageData,
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) -> NSImage? {
        // 根据主题模式决定是否移除背景
        // colorTranslucent: 移除背景（通透）
        // colorWithBackground: 保留背景（半透明白色）
        let removeBackground = settings.iconStyleMode == .colorTranslucent

        // 在自定义模式下，即使数据为 nil 也显示占位图标（0%）
        // 在智能模式下，数据为 nil 时返回 nil
        let showPlaceholder = settings.displayMode == .custom

        switch type {
        case .fiveHour:
            let percentage = data.fiveHour?.percentage ?? (showPlaceholder ? 0 : nil)
            guard let percentage = percentage else { return nil }
            if isMonochrome {
                return createCircleTemplateImage(percentage: percentage, size: NSSize(width: 18, height: 18), button: button, removeBackground: true)
            } else {
                return createCircleImage(percentage: percentage, size: NSSize(width: 18, height: 18), button: button, removeBackground: removeBackground)
            }

        case .sevenDay:
            let percentage = data.sevenDay?.percentage ?? (showPlaceholder ? 0 : nil)
            guard let percentage = percentage else { return nil }
            if isMonochrome {
                return createCircleTemplateImage(percentage: percentage, size: NSSize(width: 18, height: 18), useSevenDayStyle: true, button: button, removeBackground: true)
            } else {
                return createCircleImage(percentage: percentage, size: NSSize(width: 18, height: 18), useSevenDayColor: true, button: button, removeBackground: removeBackground)
            }

        case .opusWeekly:
            // 按模型名解析后取对应的每周模型数据（而非固定槽位），Fable 抢占槽位时 Opus 仍读到正确条目
            let percentage = data.weeklyModel(matching: .opusWeekly)?.limit.percentage ?? (showPlaceholder ? 0 : nil)
            guard let percentage = percentage else { return nil }
            return ShapeIconRenderer.createVerticalRectangleIcon(percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground)

        case .sonnetWeekly:
            let percentage = data.weeklyModel(matching: .sonnetWeekly)?.limit.percentage ?? (showPlaceholder ? 0 : nil)
            guard let percentage = percentage else { return nil }
            return ShapeIconRenderer.createHorizontalRectangleIcon(percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground)

        case .fableWeekly:
            let percentage = data.weeklyModel(matching: .fableWeekly)?.limit.percentage ?? (showPlaceholder ? 0 : nil)
            guard let percentage = percentage else { return nil }
            return ShapeIconRenderer.createDiamondIcon(percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground)

        case .extraUsage:
            let percentage: Double?
            if let extraUsage = data.extraUsage, extraUsage.enabled {
                percentage = extraUsage.percentage
            } else if showPlaceholder {
                percentage = 0
            } else {
                percentage = nil
            }
            guard let percentage = percentage else { return nil }
            return ShapeIconRenderer.createHexagonIcon(percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground)

        case .codexPrimary, .codexSecondary, .codexExtraUsage:
            // Codex 数据在 Phase 4 通过 createCodexIcon 独立渲染
            // createIconForType 仅处理 Claude UsageData，此处返回 nil
            return nil
        }
    }

    /// 根据 Codex 用量数据创建单个图标（Codex 专用，Phase 4 接入 UI）
    func createCodexIcon(
        type: LimitType,
        percentage: Double,
        isMonochrome: Bool,
        button: NSStatusBarButton?
    ) -> NSImage? {
        let removeBackground = settings.iconStyleMode == .colorTranslucent

        switch type {
        case .codexPrimary:
            if isMonochrome {
                return createCircleTemplateImage(percentage: percentage, size: NSSize(width: 18, height: 18), button: button, removeBackground: true)
            }
            let color = UsageColorScheme.codexPrimaryColorAdaptive(percentage, for: button)
            return createCircleImage(percentage: percentage, size: NSSize(width: 18, height: 18), colorOverride: color, button: button, removeBackground: removeBackground)

        case .codexSecondary:
            if isMonochrome {
                return createCircleTemplateImage(percentage: percentage, size: NSSize(width: 18, height: 18), useSevenDayStyle: true, button: button, removeBackground: true)
            }
            let color = UsageColorScheme.codexSecondaryColorAdaptive(percentage, for: button)
            return createCircleImage(percentage: percentage, size: NSSize(width: 18, height: 18), colorOverride: color, useDashedStyle: true, button: button, removeBackground: removeBackground)

        case .codexExtraUsage:
            let color = UsageColorScheme.codexExtraUsageColorAdaptive(percentage, for: button)
            return ShapeIconRenderer.createHexagonIcon(percentage: percentage, isMonochrome: isMonochrome, button: button, removeBackground: removeBackground, colorOverride: color)

        default:
            return nil
        }
    }

    /// 创建轻量分隔线图标（用于"不显示图标"模式）
    private func createMenuBarDividerIcon(isMonochrome: Bool) -> NSImage {
        let width: CGFloat = 5
        let height: CGFloat = metricIconSize
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        let lineRect = NSRect(x: (width - 1) / 2, y: 1, width: 1, height: height - 2)
        let linePath = NSBezierPath(rect: lineRect)
        let lineColor = isMonochrome ? NSColor.labelColor : NSColor.secondaryLabelColor
        let gradient = NSGradient(colors: [
            lineColor.withAlphaComponent(0.0),
            lineColor.withAlphaComponent(0.55),
            lineColor.withAlphaComponent(0.55),
            lineColor.withAlphaComponent(0.0)
        ])
        gradient?.draw(in: linePath, angle: 90)

        image.unlockFocus()
        if isMonochrome { image.isTemplate = true }
        return image
    }

}
