//
//  TeamClipboard.swift
//  Usage4Claude
//
//  Was in die Zwischenablage geht: die Team-ID und die fertige Anleitung für
//  die Kollegen.
//
//  Die Anleitung liegt bewusst als ein Text in der Lokalisierung und nicht als
//  zusammengesetzte Schnipsel: Sie wird an Menschen verschickt, also muss man
//  sie am Stück lesen und übersetzen können. Sie nennt die Team-ID, den Befehl
//  und den Satz, auf den es ankommt — der Session Key bleibt auf dem Rechner
//  der Kollegin.
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

    /// Kopiert die fertige Anleitung inklusive Team-ID.
    /// - Returns: `false`, wenn (noch) kein Team eingerichtet ist.
    @discardableResult
    static func copyInstructions(teamId: String?) -> Bool {
        guard let teamId, !teamId.isEmpty else { return false }
        return copy(L.Team.instructions(teamId))
    }
}
