//
//  DashboardComponents.swift
//  Usage4Claude
//
//  Bausteine der Mehrkonten-Übersicht: Farbskala, Wasserstand-Anzeige, Statusabzeichen.
//  Die Karte selbst liegt in AccountUsageCard.swift, der Container in DashboardView.swift.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI
import AppKit

// MARK: - Farbskala

/// Vierstufige Auslastungsskala: Blau → Gelb → Orange → Rot.
///
/// Bewusst nicht die Ampelskala der Originalapp — Blau als Ruhezustand nimmt sich
/// zurück, statt ein entspanntes Konto grün anzustrahlen. Die dritte Stufe ist
/// Claudes Clay-Orange, dadurch bleibt die Skala in der Hausfarbe.
///
/// Jede Stufe hat zwei Töne: `fill` für Flächen (Wasser, Balken) und `ink` für Text.
/// Der Flächenton wäre als Schrift auf hellem Grund zu schwach — besonders Gelb.
enum DashboardPalette {

    enum Level {
        case calm       // 0–49 %
        case moderate   // 50–74 %
        case high       // 75–89 %
        case full       // 90–100 %

        static func forPercentage(_ percentage: Double) -> Level {
            switch percentage {
            case ..<50: return .calm
            case ..<75: return .moderate
            case ..<90: return .high
            default:    return .full
            }
        }
    }

    /// Flächenton (Wasser, Balken)
    static func fill(_ percentage: Double) -> Color {
        switch Level.forPercentage(percentage) {
        case .calm:     return dynamic(light: 0x5E86C4, dark: 0x6E96D4)
        case .moderate: return dynamic(light: 0xE0A93F, dark: 0xE8B855)
        case .high:     return dynamic(light: 0xD97757, dark: 0xE08767)
        case .full:     return dynamic(light: 0xC9503F, dark: 0xD9604F)
        }
    }

    /// Textton derselben Stufe — dunkler, damit Zahlen auf hellem Grund tragen
    static func ink(_ percentage: Double) -> Color {
        switch Level.forPercentage(percentage) {
        case .calm:     return dynamic(light: 0x3E6DA8, dark: 0x8FB0DC)
        case .moderate: return dynamic(light: 0xA9761B, dark: 0xE0B45C)
        case .high:     return dynamic(light: 0xB4553A, dark: 0xE59A80)
        case .full:     return dynamic(light: 0xA33528, dark: 0xE8796A)
        }
    }

    /// Farbe für Text, der auf der Wasserfläche liegt
    static let onFill = Color.white

    /// Hex-Paar als NSColor mit Dynamic Provider: heller und dunkler Modus je eigener
    /// Wert, damit die Töne in beiden Erscheinungsbildern tragen.
    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return nsColor(isDark ? dark : light)
        })
    }

    private static func nsColor(_ hex: Int) -> NSColor {
        NSColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

// MARK: - Ampel (Wochen-Auslastung)

/// Klassische Ampelskala für die Punktreihe ganz oben in der Übersicht.
/// Bewusst nicht die blaue Kartenskala von `DashboardPalette`, sondern
/// grün → gelb → orange → rot, damit die Zeile auf einen Blick „grün = frei,
/// rot = voll" liest. `nil` (noch keine Wochendaten) → neutrales Grau.
///
/// Schwellen: <70 grün · 70–89 gelb · 90–99 orange · ab 100 rot. Ein fast
/// erschöpftes Konto (96–99 %) steht damit klar auf Orange, erst der volle
/// Anschlag ist Rot.
enum WeeklyTrafficLight {
    static func color(for utilization: Double?) -> Color {
        guard let value = utilization else { return Color.secondary.opacity(0.35) }
        switch value {
        case ..<70:  return .green
        case ..<90:  return .yellow
        case ..<100: return .orange
        default:     return .red
        }
    }
}

// MARK: - Wasserstand

/// Kreis, der sich wie ein Gefäß füllt — der Pegel ist die Auslastung des
/// Sitzungsfensters (5 Stunden bzw. Codex primary).
///
/// Die Prozentzahl wird zweimal gezeichnet: einmal in der Textfarbe, einmal in Weiß
/// und auf die Wasserfläche beschnitten. Dadurch schneidet die Wellenlinie mitten
/// durch die Ziffern, statt dass die Zahl an einem Schwellwert umspringt — und sie
/// bleibt in jedem Füllstand lesbar.
struct WaterLevelGauge: View {
    let percentage: Double
    let caption: String
    var diameter: CGFloat = 74

    private var clamped: Double { min(100, max(0, percentage)) }

    var body: some View {
        ZStack {
            Circle().fill(Color(NSColor.windowBackgroundColor))

            WaterShape(level: clamped / 100.0)
                .fill(DashboardPalette.fill(clamped))
                .clipShape(Circle())

            Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)

            numberStack(color: DashboardPalette.ink(clamped))
            numberStack(color: DashboardPalette.onFill)
                .clipShape(WaterShape(level: clamped / 100.0))
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeInOut(duration: 0.45), value: clamped)
    }

    private func numberStack(color: Color) -> some View {
        VStack(spacing: 0) {
            // Normale Systemschrift statt Schreibmaschinenschnitt; `monospacedDigit`
            // hält die Ziffern trotzdem in Spur, wenn der Wert springt.
            Text("\(Int(clamped.rounded()))%")
                .font(.system(size: diameter * 0.19, weight: .semibold).monospacedDigit())
                .foregroundColor(color)
            Text(caption)
                .font(.system(size: diameter * 0.11))
                .foregroundColor(color.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: diameter * 0.8)
        }
    }
}

/// Wasserfläche mit leichter Welle an der Oberkante.
/// `level` 0…1 misst von unten: 0 bleibt leer, 1 ist randvoll.
struct WaterShape: Shape {
    var level: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard level > 0 else { return path }

        // Die Welle braucht oben und unten Luft, damit sie bei 0 % und 100 %
        // nicht über den Rand schwappt.
        let waveHeight = min(rect.height * 0.035, 3.0)
        let surfaceY = rect.maxY - (rect.height - waveHeight * 2) * level - waveHeight

        path.move(to: CGPoint(x: rect.minX, y: surfaceY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: surfaceY),
            control: CGPoint(x: rect.width * 0.25, y: surfaceY - waveHeight)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: surfaceY),
            control: CGPoint(x: rect.width * 0.75, y: surfaceY + waveHeight)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
