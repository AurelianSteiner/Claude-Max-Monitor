//
//  DashboardMenuAction.swift
//  Usage4Claude
//
//  Menüaktionen, die aus der Übersicht (Popover / Fenster) heraus ausgelöst
//  werden. Früher als `UsageDetailView.MenuAction` verschachtelt; seit dem
//  Wegfall der Einzelkonto-Detailansicht ein eigenständiger Typ.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import Foundation

/// 菜单操作类型
enum MenuAction {
    case generalSettings
    case authSettings
    case checkForUpdates
    case about
    case quit
    /// Übersicht in einem eigenständigen Fenster öffnen
    case openDashboardWindow
}
