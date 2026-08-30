//
//  IconShapePaths.swift
//  Usage4Claude
//
//  Created by Claude Code on 2025-12-18.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// 图标形状路径工具类
/// 提供所有限制类型图标的 SwiftUI 形状路径生成方法（`MiniProgressIcon` 等视图使用）
struct IconShapePaths {

    // MARK: - SwiftUI Path Methods

    /// 创建圆形路径（从12点钟位置顺时针绘制，支持 trimmedPath 进度弧）
    /// - Parameter rect: 绘制区域
    /// - Returns: 圆形路径
    static func circlePath(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: 3, dy: 3)
        let center = CGPoint(x: inset.midX, y: inset.midY)
        let radius = min(inset.width, inset.height) / 2
        return Path { path in
            // 从12点钟位置（-90°）顺时针绘制整圆
            path.addArc(center: center, radius: radius,
                        startAngle: .degrees(-90), endAngle: .degrees(270),
                        clockwise: false)
        }
    }

    /// 创建圆角正方形路径（Opus，从顶部中点顺时针绘制，随 rect 动态缩放）
    /// - Parameter rect: 绘制区域
    /// - Returns: 圆角正方形路径
    static func roundedSquarePath(in rect: CGRect) -> Path {
        let s = (min(rect.width, rect.height) - 8) / 2  // 半边长（留 4pt inset 避免笔画被裁剪）
        let cx = rect.midX, cy = rect.midY
        let r = s * 0.4  // 圆角半径（与原始 2/10 比例一致）
        return Path { path in
            // 从顶部中点顺时针绘制
            path.move(to: CGPoint(x: cx, y: cy - s))
            path.addLine(to: CGPoint(x: cx + s - r, y: cy - s))
            path.addArc(center: CGPoint(x: cx + s - r, y: cy - s + r),
                        radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: cx + s, y: cy + s - r))
            path.addArc(center: CGPoint(x: cx + s - r, y: cy + s - r),
                        radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: cx - s + r, y: cy + s))
            path.addArc(center: CGPoint(x: cx - s + r, y: cy + s - r),
                        radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: cx - s, y: cy - s + r))
            path.addArc(center: CGPoint(x: cx - s + r, y: cy - s + r),
                        radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: CGPoint(x: cx, y: cy - s))
            path.closeSubpath()
        }
    }

    /// 创建右上角斜切的圆角正方形路径（Sonnet，从顶部中点顺时针绘制，随 rect 动态缩放）
    /// - Parameter rect: 绘制区域
    /// - Returns: 斜切圆角正方形路径
    static func chamferedSquarePath(in rect: CGRect) -> Path {
        let s = (min(rect.width, rect.height) - 8) / 2  // 半边长（留 4pt inset 避免笔画被裁剪）
        let cx = rect.midX, cy = rect.midY
        let r = s * 0.4    // 圆角半径
        let cut = s * 0.5  // 右上角斜切大小（与原始 2.5/5 比例一致）
        return Path { path in
            // 从顶部中点顺时针绘制
            path.move(to: CGPoint(x: cx, y: cy - s))
            path.addLine(to: CGPoint(x: cx + s - cut, y: cy - s))  // 顶边到斜切起点
            path.addLine(to: CGPoint(x: cx + s, y: cy - s + cut))  // 斜切
            path.addLine(to: CGPoint(x: cx + s, y: cy + s - r))    // 右边
            path.addArc(center: CGPoint(x: cx + s - r, y: cy + s - r),
                        radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: cx - s + r, y: cy + s))
            path.addArc(center: CGPoint(x: cx - s + r, y: cy + s - r),
                        radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: cx - s, y: cy - s + r))
            path.addArc(center: CGPoint(x: cx - s + r, y: cy - s + r),
                        radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: CGPoint(x: cx, y: cy - s))
            path.closeSubpath()
        }
    }

    /// 创建菱形路径（Fable，四个顶点：上/右/下/左，随 rect 动态缩放）
    /// - Parameter rect: 绘制区域
    /// - Returns: 菱形路径
    static func diamondPath(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: 3, dy: 3)
        let cx = inset.midX, cy = inset.midY
        let rx = inset.width / 2, ry = inset.height / 2
        return Path { path in
            path.move(to: CGPoint(x: cx, y: cy - ry))       // 顶点（12点）
            path.addLine(to: CGPoint(x: cx + rx, y: cy))    // 右（3点）
            path.addLine(to: CGPoint(x: cx, y: cy + ry))    // 底（6点）
            path.addLine(to: CGPoint(x: cx - rx, y: cy))    // 左（9点）
            path.closeSubpath()
        }
    }

    /// 创建平顶六边形路径（Extra Usage，从右上顶点顺时针绘制）
    /// - Parameters:
    ///   - center: 六边形中心点
    ///   - radius: 六边形半径
    /// - Returns: 六边形路径
    static func hexagonPath(center: CGPoint, radius: CGFloat) -> Path {
        Path { path in
            // 从右上顶点（-60°，最接近12点钟方向）顺时针绘制
            for i in 0..<6 {
                let angleDeg: CGFloat = -60 + CGFloat(i) * 60
                let angle = angleDeg * .pi / 180
                let x = center.x + radius * cos(angle)
                let y = center.y + radius * sin(angle)
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.closeSubpath()
        }
    }

    /// 根据限制类型获取对应的形状路径（动态随 rect 缩放）
    /// - Parameters:
    ///   - type: 限制类型
    ///   - rect: 绘制区域
    /// - Returns: 对应的形状路径
    static func pathForLimitType(_ type: LimitType, in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // 六边形半径：留 3pt inset 保证笔画不被裁剪
        let hexRadius = min(rect.width, rect.height) / 2 - 3

        switch type {
        case .fiveHour, .sevenDay, .codexPrimary, .codexSecondary:
            return circlePath(in: rect)

        case .opusWeekly:
            return roundedSquarePath(in: rect)

        case .sonnetWeekly:
            return chamferedSquarePath(in: rect)

        case .fableWeekly:
            return diamondPath(in: rect)

        case .extraUsage, .codexExtraUsage:
            return hexagonPath(center: center, radius: hexRadius)
        }
    }
}
