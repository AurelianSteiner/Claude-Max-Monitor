//
//  DashboardWindowManager.swift
//  Usage4Claude
//
//  独立的多账户总览窗口。popover 会在应用失焦时自动关闭，想把总览一直摆在
//  桌面一角时用这个窗口：内容与 popover 完全一致，只是常驻、可移动。
//  Copyright © 2025 f-is-h. All rights reserved.
//

import AppKit
import Combine
import SwiftUI

final class DashboardWindowManager {
    static let shared = DashboardWindowManager()

    /// 位置与大小记忆在系统 defaults 里的名字
    private static let frameAutosaveName = "Usage4Claude.DashboardWindow"
    /// 最小尺寸：一列卡片的宽度，高度足够放下表头 + 一张卡片
    private static let minimumSize = NSSize(width: 400, height: 320)

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var widthObserver: AnyCancellable?

    private init() {}

    var isVisible: Bool {
        window?.isVisible == true
    }

    /// 显示总览窗口（已打开则前置）
    /// - Parameter onMenuAction: 窗口内菜单项的回调，与 popover 共用同一套动作
    func show(onMenuAction: @escaping (MenuAction) -> Void) {
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        // 菜单栏应用平时是 accessory（不进 Dock），要让普通窗口能获得焦点需要临时切成 regular
        NSApp.setActivationPolicy(.regular)

        let view = DashboardView(
            manager: DashboardRefreshManager.shared,
            onMenuAction: onMenuAction,
            isStandaloneWindow: true
        )

        let hostingController = NSHostingController(rootView: view)
        hostingController.sizingOptions = [.preferredContentSize]

        let window = NSWindow(contentViewController: hostingController)
        window.title = L.Dashboard.windowTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false

        // 内容的理想尺寸定下初始大小；之后关掉自动尺寸跟随，
        // 否则每次数据变化 hostingController 都会把窗口拉回理想尺寸，
        // 用户自己调过的大小就白调了。
        // 关掉之后没人再纠正尺寸了，所以先把理想尺寸落实到窗口上。
        // 注意用 preferredContentSize（= SwiftUI 的理想尺寸）而不是 fittingSize：
        // 独立窗口的根视图 maxWidth/maxHeight 是 .infinity，fittingSize 给的是
        // 最小尺寸，会把窗口开成一条缝。
        hostingController.view.layoutSubtreeIfNeeded()
        let idealSize = hostingController.preferredContentSize
        hostingController.sizingOptions = []
        if idealSize.width > 0, idealSize.height > 0 {
            window.setContentSize(idealSize)
        }

        // 先恢复上次的位置和大小，再挂上 autosave 名字——反过来会先把当前
        // 帧写回去，把记住的尺寸覆盖掉。
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        self.window = window

        // Karten sind fest breit und die Übersicht scrollt nur senkrecht — wird
        // das Fenster schmaler als der Inhalt, würde rechts eine Spalte
        // abgeschnitten. Weil sizingOptions abgeschaltet ist, wächst das Fenster
        // nicht mehr von allein: Mindestbreite und ggf. die Fensterbreite müssen
        // der Inhaltsbreite folgen, wenn sich Kontenzahl oder Spaltenwahl ändern.
        // (CombineLatest feuert sofort mit den aktuellen Werten — das deckt auch
        // den Fall ab, dass das Fenster vor dem ersten Abruf geöffnet wird.)
        widthObserver = Publishers.CombineLatest(
            DashboardRefreshManager.shared.$snapshots,
            UserSettings.shared.$dashboardColumns
        )
        .receive(on: RunLoop.main)
        .sink { snapshots, columns in
            DashboardWindowManager.shared.enforceContentWidth(
                DashboardMetrics.width(
                    columns: DashboardMetrics.columnCount(for: snapshots.count, setting: columns)
                )
            )
        }

        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                DashboardWindowManager.shared.window = nil
                DashboardWindowManager.shared.widthObserver = nil
                // 回到 accessory：仅当没有别的可见窗口（例如设置窗口）还开着
                let hasOtherWindows = NSApp.windows.contains {
                    $0.isVisible && $0.canBecomeMain && $0 !== window
                }
                if !hasOtherWindows {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Mindestbreite an den Inhalt nachziehen und das Fenster notfalls
    /// verbreitern. Die Höhe bleibt unangetastet — senkrecht scrollt das Gitter
    /// selbst, und die vom Benutzer eingestellte Höhe soll erhalten bleiben.
    private func enforceContentWidth(_ contentWidth: CGFloat) {
        guard let window else { return }

        let screenWidth = (window.screen ?? NSScreen.main)?.visibleFrame.width ?? contentWidth
        let target = max(Self.minimumSize.width, min(contentWidth, screenWidth))
        window.minSize = NSSize(width: target, height: Self.minimumSize.height)

        guard window.frame.width < target else { return }
        var frame = window.frame
        frame.size.width = target
        window.setFrame(frame, display: true)
    }

    func close() {
        window?.close()
        window = nil
        widthObserver = nil
    }
}
