//
//  TeamClipboard.swift
//  Usage4Claude
//
//  Was in die Zwischenablage geht: Tokens und die fertige Einladung aus der
//  Mitgliederverwaltung.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import AppKit

enum TeamClipboard {

    /// Legt Text in die Zwischenablage.
    /// - Returns: `false` bei leerem Text — dann bleibt die alte Ablage stehen,
    ///   statt sie ohne Not zu leeren.
    @discardableResult
    static func copy(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
