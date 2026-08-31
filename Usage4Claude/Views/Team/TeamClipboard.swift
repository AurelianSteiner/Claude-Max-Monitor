//
//  TeamClipboard.swift
//  Usage4Claude
//
//  Was in die Zwischenablage geht: Tokens und die fertige Einladung aus der
//  Mitgliederverwaltung. Beides sind Geheimnisse — wer das Token hat, ist im
//  Team. Deshalb gibt es hier nur den einen, als geheim markierten Weg.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import AppKit

enum TeamClipboard {

    /// Der Marker aus der Verabredung von nspasteboard.org: „Bitte nicht
    /// merken." Zwischenablage-Verwalter (Maccy, Paste, Alfred …) überspringen
    /// Einträge dieser Art, statt das Token in ihrem Verlauf aufzubewahren.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// Legt ein Geheimnis in die Zwischenablage und markiert es als solches.
    ///
    /// Der Marker muss in denselben Schreibvorgang wie der Text — jedes
    /// `clearContents()` räumt die Ablage komplett leer, ein nachträglich
    /// gesetzter Marker wäre also entweder weg oder gehörte zum nächsten
    /// Inhalt. Er trägt selbst nichts; gelesen wird nur, dass es ihn gibt.
    ///
    /// - Returns: `false` bei leerem Text — dann bleibt die alte Ablage stehen,
    ///   statt sie ohne Not zu leeren.
    @discardableResult
    static func copyConcealed(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("", forType: concealedType)
        return pasteboard.setString(text, forType: .string)
    }
}
