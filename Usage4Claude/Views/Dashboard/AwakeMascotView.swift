//
//  AwakeMascotView.swift
//  Usage4Claude
//
//  Die Claudie-Parade im Kopf der Übersicht: Solange „Claude Always On" aktiv
//  ist, laufen kleine korallenfarbene Pixel-Wesen von links nach rechts durch
//  einen schmalen Streifen — links blenden sie ein, rechts aus. Ist der Modus
//  aus, bleibt der Streifen leer.
//
//  Die kleine Parade-Engine: Jeder Läufer ist eine Nummer im unendlichen
//  Strom. Aus der Nummer werden deterministisch (Splitmix-Hash) sein
//  Startzeitpunkt (Abstände zufällig zwischen ~1,6 s und ~3,2 s — nie so
//  knapp, dass zwei aufeinandersitzen) und seine Art abgeleitet: Die Hälfte
//  läuft normal, die andere Hälfte fällt auf — Partyhut, Zylinder, ein
//  Raucher mit Rauchfahne, ein Sprinter, der alle überholt, und einer, der
//  seelenruhig rückwärts stapft.
//  Alle Normalen laufen exakt gleich schnell, damit die Abstände stabil
//  bleiben und niemand auf den Vordermann aufläuft.
//
//  Technik: `TimelineView(.periodic)` treibt eine reine Funktion der Uhrzeit —
//  kein eigener Timer, kein gespeicherter Zustand, nichts läuft, wenn die
//  Ansicht unsichtbar ist. Die Wesen sind einzelne Canvas-Rechtecke im festen
//  Pixelraster (Zelle 4 pt) — eigenes Sprite, kein fremdes Bildmaterial,
//  nur an Claudes Pixel-Look angelehnt.
//
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

struct AwakeMascotView: View {

    @ObservedObject private var sleepGuard = SleepGuard.shared

    /// Wunschbreite des Streifens; in engen Layouts darf SwiftUI ihn stauchen,
    /// die Zeichnung richtet sich nach der tatsächlichen Breite.
    static let idealWidth: CGFloat = 300
    static let height: CGFloat = 34

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
        .clipped()   // Rauch & Hüte bleiben im Streifen, nichts ragt ins Dashboard
        .help(sleepGuard.isAwake ? L.Dashboard.mascotAwakeHelp : L.Dashboard.mascotAsleepHelp)
        .accessibilityLabel(sleepGuard.isAwake ? L.Dashboard.mascotAwakeHelp : L.Dashboard.mascotAsleepHelp)
    }
}

// MARK: - Parade-Engine

/// Art eines Läufers. `internal`, damit der Vorschau-Renderer im Modul die
/// Varianten einzeln zeichnen kann.
enum MascotVariant {
    case normal
    case partyHat
    case topHat
    case smoker
    case sprinter
    /// Läuft verkehrt herum — kommt von rechts und schaut nach links
    case backwards
}

/// Eine Momentaufnahme der Parade. Alle Maße leben im Pixelraster (Zelle 4 pt);
/// die Läufer verteilen sich über die tatsächliche Breite.
struct MascotParadeCanvas: View {

    let time: TimeInterval

    static let cell: CGFloat = 4

    // Korallen-Pixel, an Claudes Pixel-Look angelehnt, plus Deko-Töne
    static let coral = Color(red: 0.910, green: 0.573, blue: 0.486)     // #e8927c
    static let coralDark = Color(red: 0.753, green: 0.416, blue: 0.333) // #c06a55
    static let faceInk = Color(red: 0.227, green: 0.122, blue: 0.086)   // #3a1f16
    static let partyPink = Color(red: 0.855, green: 0.353, blue: 0.545) // Partyhut
    static let partyTip = Color(red: 0.980, green: 0.800, blue: 0.235)  // Bommel
    static let hatBlack = Color(red: 0.16, green: 0.16, blue: 0.19)     // Zylinder
    static let smoke = Color.secondary

    // Taktung der Parade
    static let baseSpeed: Double = 26        // pt/s, alle Normalen exakt gleich
    static let sprintSpeed: Double = 74      // der Eilige
    static let avgInterval: Double = 2.4     // mittlerer Start-Abstand (s)
    static let minInterval: Double = 1.6     // nie enger — verhindert Aufsitzen
    static let stepsPerSecond: Double = 4
    static let fadeZone: CGFloat = 34
    static let spriteWidth: CGFloat = 32
    static let overshoot: CGFloat = 36

    // MARK: Deterministischer Zufall (Splitmix64)

    /// Stabiler Pseudozufall 0…1 aus Läufer-Nummer und Salz — keine gespeicherten
    /// Zustände, dieselbe Nummer würfelt immer dasselbe.
    static func roll(_ index: Int, _ salt: UInt64) -> Double {
        var z = UInt64(bitPattern: Int64(index)) &+ (salt &* 0x9E37_79B9_7F4A_7C15)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z % 1_000_000) / 1_000_000
    }

    /// Startzeitpunkt des Läufers `index`: fixes Raster plus Jitter, der die
    /// Lücken zwischen `minInterval` und ~2 × `avgInterval − minInterval` streut.
    static func spawnTime(_ index: Int) -> Double {
        let jitterMax = avgInterval - minInterval
        return Double(index) * avgInterval + roll(index, 1) * jitterMax
    }

    /// Je 10 % pro Sonderform, die Hälfte läuft ganz normal.
    static func variant(_ index: Int) -> MascotVariant {
        let r = roll(index, 7)
        if r < 0.10 { return .partyHat }
        if r < 0.20 { return .topHat }
        if r < 0.30 { return .smoker }
        if r < 0.40 { return .sprinter }
        if r < 0.50 { return .backwards }
        return .normal
    }

    // MARK: Zeichnen

    var body: some View {
        Canvas { context, size in
            guard size.width > 4 else { return }
            let span = Double(size.width + Self.overshoot * 2)

            // Nur die Nummern anschauen, die jetzt überhaupt sichtbar sein können:
            // Langsamste Reisezeit rückwärts vom aktuellen Zeitpunkt.
            let slowestTravel = span / Self.baseSpeed
            let newest = Int((time / Self.avgInterval).rounded(.down)) + 1
            let oldest = Int(((time - slowestTravel - 1) / Self.avgInterval).rounded(.down))

            for index in oldest...newest {
                let spawn = Self.spawnTime(index)
                let elapsed = time - spawn
                guard elapsed > 0 else { continue }

                let kind = Self.variant(index)
                let speed = kind == .sprinter ? Self.sprintSpeed : Self.baseSpeed
                let x = CGFloat(elapsed * speed) - Self.overshoot
                guard x < size.width + Self.overshoot else { continue }

                var alpha: Double = 1
                if x < Self.fadeZone {
                    alpha = max(0, Double(x / Self.fadeZone))
                }
                let rightStart = size.width - Self.fadeZone - Self.spriteWidth
                if x > rightStart {
                    alpha = min(alpha, max(0, Double((size.width - Self.spriteWidth - x) / Self.fadeZone)))
                }
                guard alpha > 0.02 else { continue }

                let stepRate = kind == .sprinter ? Self.stepsPerSecond * 2.2 : Self.stepsPerSecond
                let step = Int(time * stepRate + Double(index) * 0.7) % 2 == 0
                Self.drawWalker(in: context, x: x, step: step, alpha: alpha,
                                variant: kind, time: time, seed: index)
            }
        }
    }

    // MARK: Ein Läufer

    /// Zeichnet einen Läufer bei `x` (linke Kante). `internal` für den
    /// Vorschau-Renderer; die Engine oben ist der einzige echte Aufrufer.
    static func drawWalker(in ctx: GraphicsContext, x: CGFloat, step: Bool,
                           alpha: Double, variant: MascotVariant,
                           time: TimeInterval, seed: Int) {
        var walker = ctx
        walker.opacity = alpha
        // Leichtes Hüpfen im Schritt-Takt; Grundlinie so, dass die Beinchen
        // am unteren Rand des 24-pt-Streifens aufsetzen
        walker.translateBy(x: x, y: step ? 12.0 : 13.0)

        // Sprinter legen sich in die Kurve: obere Reihen wandern nach vorn
        let lean: Double = variant == .sprinter ? 0.22 : 0

        // Der Rückwärtsläufer wird gespiegelt: Er wandert mit dem Strom nach
        // rechts, blickt und stapft dabei aber nach links — als hätte er die
        // Richtung verpasst. Gespiegelt wird um die Sprite-Mitte (4 Zellen).
        if variant == .backwards {
            walker.translateBy(x: 8 * cell, y: 0)
            walker.scaleBy(x: -1, y: 1)
        }

        func px(_ col: Double, _ row: Double, _ color: Color, _ w: Double = 1, _ h: Double = 1) {
            let shift = lean * (3 - row)
            let rect = CGRect(x: (col + shift) * cell, y: row * cell,
                              width: w * cell, height: h * cell)
            walker.fill(Path(rect), with: .color(color))
        }

        // Ohren-Nubs (der Zylinder verdeckt sie ohnehin fast)
        px(1, -1, coral)
        px(6, -1, coral)

        // Körperblock 8 × 4, Ecken frei, Kanten dunkler
        for row in 0..<4 {
            for col in 0..<8 {
                if row == 0 && (col == 0 || col == 7) { continue }
                let edge = (col == 0 || col == 7 || row == 3)
                px(Double(col), Double(row), edge ? coralDark : coral)
            }
        }

        // Augen — blicken in Laufrichtung
        px(3, 1, faceInk)
        px(6, 1, faceInk)

        // Beinchen alternieren
        if step {
            px(1, 4, coralDark)
            px(4.5, 4, coralDark)
            px(6.5, 4.6, coralDark, 0.9, 0.7)
        } else {
            px(1.5, 4.6, coralDark, 0.9, 0.7)
            px(3.5, 4, coralDark)
            px(6, 4, coralDark)
        }

        // Die Besonderen
        switch variant {
        case .normal:
            break

        case .backwards:
            // Braucht keine Deko: Die Spiegelung oben erledigt den Gag schon.
            break

        case .partyHat:
            // Spitzer Hut mit Bommel, mittig über dem Kopf
            px(3.6, -3.2, partyPink, 0.8, 1)
            px(3.1, -2.3, partyPink, 1.8, 1)
            px(2.6, -1.5, partyPink, 2.8, 0.7)
            px(3.7, -3.8, partyTip, 0.6, 0.6)

        case .topHat:
            // Zylinder: breite Krempe, hohe Krone
            px(1.8, -1.6, hatBlack, 4.4, 0.6)
            px(2.6, -3.6, hatBlack, 2.8, 2.1)

        case .smoker:
            // Zigarette vorn am Gesicht, dahinter eine richtige Rauchfahne:
            // vier Wolken, die aufsteigen, größer werden und verwehen.
            px(8, 2, Color.white.opacity(0.9), 1.6, 0.6)
            px(9.6, 2, Color.orange, 0.5, 0.6)
            for puff in 0..<4 {
                let phase = (time * 0.5 + Double(puff) * 0.25 + roll(seed, 11))
                    .truncatingRemainder(dividingBy: 1)
                let puffAlpha = (1 - phase) * 0.7
                guard puffAlpha > 0.04 else { continue }
                let grow = 0.9 + phase * 1.4          // Wolke wächst beim Aufsteigen
                px(9.4 + Double(puff) * 0.4 + phase * 2.2,
                   1.4 - phase * 5.0,
                   smoke.opacity(puffAlpha), grow, grow)
            }

        case .sprinter:
            // Tempolinien hinter dem Eiligen
            px(-1.6, 1, coralDark.opacity(0.35), 1.2, 0.5)
            px(-2.6, 2.2, coralDark.opacity(0.25), 1.4, 0.5)
        }
    }
}
