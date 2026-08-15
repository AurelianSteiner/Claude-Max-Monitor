//
//  AwakeMascotView.swift
//  Usage4Claude
//
//  Die Claudie-Parade im Kopf der Übersicht: Solange „Claude Always On" aktiv
//  ist, laufen kleine korallenfarbene Pixel-Wesen von links nach rechts durch
//  einen schmalen Streifen — am linken Rand blenden sie ein, am rechten aus.
//  Ist der Modus aus, bleibt der Streifen leer.
//
//  Technik: `TimelineView(.periodic)` treibt eine reine Funktion der Uhrzeit —
//  kein eigener Timer, nichts läuft, wenn die Ansicht unsichtbar ist. Im
//  Aus-Zustand wird gar nicht erst animiert. Die Wesen sind einzelne
//  Canvas-Rechtecke im festen Pixelraster (Zelle 2 pt) — eigenes Sprite,
//  kein fremdes Bildmaterial, nur an Claudes Pixel-Look angelehnt.
//
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

struct AwakeMascotView: View {

    @ObservedObject private var sleepGuard = SleepGuard.shared

    /// Wunschbreite des Streifens; in engen Layouts darf SwiftUI ihn stauchen,
    /// die Zeichnung richtet sich nach der tatsächlichen Breite.
    static let idealWidth: CGFloat = 132
    static let height: CGFloat = 24

    var body: some View {
        Group {
            if sleepGuard.isAwake {
                TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                    MascotParadeCanvas(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                // Aus = leerer Streifen (gleiche Größe, damit der Kopf nicht springt)
                Color.clear
            }
        }
        .frame(maxWidth: Self.idealWidth)
        .frame(height: Self.height)
        .help(sleepGuard.isAwake ? L.Dashboard.mascotAwakeHelp : L.Dashboard.mascotAsleepHelp)
        .accessibilityLabel(sleepGuard.isAwake ? L.Dashboard.mascotAwakeHelp : L.Dashboard.mascotAsleepHelp)
    }
}

// MARK: - Zeichnung

/// Eine Momentaufnahme der Parade. Alle Maße leben im Pixelraster (Zelle 2 pt);
/// die Läufer verteilen sich gleichmäßig über die tatsächliche Breite.
private struct MascotParadeCanvas: View {

    let time: TimeInterval

    private static let cell: CGFloat = 2

    // Korallen-Pixel, an Claudes Pixel-Look angelehnt
    private static let coral = Color(red: 0.910, green: 0.573, blue: 0.486)   // #e8927c
    private static let coralDark = Color(red: 0.753, green: 0.416, blue: 0.333) // #c06a55
    private static let face = Color(red: 0.227, green: 0.122, blue: 0.086)    // #3a1f16

    /// Anzahl der Läufer und ihr Lauftempo (pt/s)
    private static let walkerCount = 5
    private static let speed: Double = 14
    /// Schrittfrequenz (Beinwechsel pro Sekunde) und Breite der Fade-Zonen
    private static let stepsPerSecond: Double = 4
    private static let fadeZone: CGFloat = 20
    /// Sprite-Breite in pt (8 Zellen), plus Auslauf außerhalb des Streifens
    private static let spriteWidth: CGFloat = 16
    private static let overshoot: CGFloat = 15

    var body: some View {
        Canvas { context, size in
            let span = size.width + Self.overshoot * 2
            guard span > 0 else { return }

            for walker in 0..<Self.walkerCount {
                // Gleichmäßig versetzt; ein Hauch Tempo-Varianz, damit die
                // Reihe lebendig bleibt, ohne auseinanderzulaufen
                let offset = Double(walker) * (span / Double(Self.walkerCount))
                let pace = Self.speed * (1 + 0.06 * Double(walker % 3 - 1))
                let x = CGFloat((time * pace + offset)
                    .truncatingRemainder(dividingBy: Double(span))) - Self.overshoot

                // Beinwechsel je Läufer versetzt, sonst marschieren alle im Gleichschritt
                let step = Int(time * Self.stepsPerSecond + Double(walker) * 0.7) % 2 == 0

                var alpha: Double = 1
                if x < Self.fadeZone {
                    alpha = max(0, Double(x / Self.fadeZone))
                }
                let rightEdge = size.width - Self.fadeZone - Self.spriteWidth
                if x > rightEdge {
                    alpha = min(alpha, max(0, Double((size.width - Self.spriteWidth - x) / Self.fadeZone)))
                }
                guard alpha > 0.02 else { continue }

                drawWalker(in: context, x: x, step: step, alpha: alpha)
            }
        }
    }

    // MARK: Läufer

    private func drawWalker(in ctx: GraphicsContext, x: CGFloat, step: Bool, alpha: Double) {
        var walker = ctx
        walker.opacity = alpha
        // Leichtes Hüpfen im Schritt-Takt; Grundlinie so, dass die Beinchen
        // am unteren Rand des 24-pt-Streifens aufsetzen
        walker.translateBy(x: x, y: step ? 7.4 : 8.2)

        func px(_ col: Double, _ row: Double, _ color: Color, _ w: Double = 1, _ h: Double = 1) {
            let rect = CGRect(x: col * Self.cell, y: row * Self.cell,
                              width: w * Self.cell, height: h * Self.cell)
            walker.fill(Path(rect), with: .color(color))
        }

        // Ohren-Nubs
        px(1, -1, Self.coral)
        px(6, -1, Self.coral)

        // Körperblock 8 × 4, Ecken frei, Kanten dunkler
        for row in 0..<4 {
            for col in 0..<8 {
                if row == 0 && (col == 0 || col == 7) { continue }
                let edge = (col == 0 || col == 7 || row == 3)
                px(Double(col), Double(row), edge ? Self.coralDark : Self.coral)
            }
        }

        // Augen — blicken in Laufrichtung
        px(3, 1, Self.face)
        px(6, 1, Self.face)

        // Beinchen alternieren
        if step {
            px(1, 4, Self.coralDark)
            px(4.5, 4, Self.coralDark)
            px(6.5, 4.6, Self.coralDark, 0.9, 0.7)
        } else {
            px(1.5, 4.6, Self.coralDark, 0.9, 0.7)
            px(3.5, 4, Self.coralDark)
            px(6, 4, Self.coralDark)
        }
    }
}
