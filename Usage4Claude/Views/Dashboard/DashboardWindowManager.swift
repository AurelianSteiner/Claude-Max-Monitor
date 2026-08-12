//
//  DashboardWindowManager.swift
//  Usage4Claude
//
//  独立的多账户总览窗口。popover 会在应用失焦时自动关闭，想把总览一直摆在
//  桌面一角时用这个窗口：内容与 popover 完全一致，只是常驻、可移动。
//  Copyright © 2025 f-is-h. All rights reserved.
//

import AppKit
import SwiftUI

final class DashboardWindowManager {
    static let shared = DashboardWindowManager()

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    var isVisible: Bool {
        window?.isVisible == true
    }

    /// 显示总览窗口（已打开则前置）
    /// - Parameter onMenuAction: 窗口内菜单项的回调，与 popover 共用同一套动作
    func show(onMenuAction: @escaping (UsageDetailView.MenuAction) -> Void) {
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
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("Usage4Claude.DashboardWindow")
        window.center()
        self.window = window

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

    func close() {
        window?.close()
        window = nil
    }
}
