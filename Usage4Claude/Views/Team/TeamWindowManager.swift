//
//  TeamWindowManager.swift
//  Usage4Claude
//
//  Eigenständiges Fenster der Team-Übersicht — aufgebaut wie
//  `DashboardWindowManager`, inklusive gemerkter Fensterlage.
//
//  Bewusst kein popover: Die Team-Zahlen schaut man sich beim Planen an, oft
//  neben einem Chatfenster. Ein popover schließt sich, sobald die App den Fokus
//  verliert; dieses Fenster bleibt stehen.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import AppKit
import SwiftUI

final class TeamWindowManager {
    static let shared = TeamWindowManager()

    /// Name, unter dem das System Lage und Größe merkt
    private static let frameAutosaveName = "Usage4Claude.TeamWindow"
    private static let minimumSize = NSSize(width: 320, height: 240)

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    var isVisible: Bool {
        window?.isVisible == true
    }

    /// Zeigt das Fenster (ist es schon offen, kommt es nach vorne).
    /// - Parameter onMenuAction: Rückkanal der leeren Zustände, z. B. „Einstellungen öffnen"
    func show(onMenuAction: @escaping (MenuAction) -> Void) {
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Menüleisten-App ist sonst `accessory` (nicht im Dock) — ein normales
        // Fenster bekommt so keinen Tastaturfokus.
        NSApp.setActivationPolicy(.regular)

        let hostingController = NSHostingController(rootView: TeamView(onMenuAction: onMenuAction))
        hostingController.sizingOptions = [.preferredContentSize]

        let window = NSWindow(contentViewController: hostingController)
        window.title = L.Team.windowTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false

        // Erst die Wunschgröße des Inhalts übernehmen, dann das automatische
        // Nachziehen abschalten: Sonst zieht jede neue Meldung das Fenster auf
        // die Idealgröße zurück und eine selbst eingestellte Größe wäre weg.
        hostingController.view.layoutSubtreeIfNeeded()
        let idealSize = hostingController.preferredContentSize
        hostingController.sizingOptions = []
        if idealSize.width > 0, idealSize.height > 0 {
            window.setContentSize(idealSize)
        }
        window.minSize = Self.minimumSize

        // Zuerst die gemerkte Lage wiederherstellen, erst danach den
        // Autosave-Namen setzen — umgekehrt überschriebe das aktuelle Fenster
        // die gemerkten Werte, bevor sie gelesen werden.
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
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
                TeamWindowManager.shared.window = nil
                // Zurück auf `accessory`, aber nur wenn kein anderes Fenster
                // (Übersicht, Einstellungen) mehr offen ist.
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
