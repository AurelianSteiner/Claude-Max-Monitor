//
//  TeamSparkline.swift
//  Usage4Claude
//
//  Eine kleine Verlaufslinie für die Team-Detailansicht: die letzten sieben
//  Tage einer Limit-Zeile als Polylinie, darunter eine hauchdünne Fläche,
//  vorn ein Punkt am aktuellen Wert. Bewusst ein simpler `Path` statt einer
//  Chart-Abhängigkeit — die Linie beantwortet nur „steigt das gerade, und
//  seit wann?", keine Achsen, keine Beschriftung.
//
//  Die Zeitachse ist fest sieben Tage bis jetzt: Wer erst seit gestern
//  meldet, füllt ehrlich nur das rechte Stück. Die Höhe ist fest 0–100 %,
//  damit zwei Linien untereinander vergleichbar sind.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

struct TeamSparkline: View {

    /// Verlaufspunkte, aufsteigend nach Zeit (liefert `points(label:)` so)
    let points: [TeamHistoryPoint]
    /// Aktueller Prozentwert der Zeile — bestimmt den Farbton, damit Linie
    /// und Prozentzahl derselben Zeile zusammengehören.
    let percent: Int
    /// Ende der Zeitachse — im Einbau „jetzt", in Vorschauen fixierbar
    var end: Date = Date()

    /// Sichtbares Zeitfenster
    static let window: TimeInterval = TimeInterval(TeamHistoryStore.days) * 24 * 60 * 60

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let spots = layout(in: size)
            if spots.count >= 2, let last = spots.last {
                area(through: spots, in: size)
                    .fill(DashboardPalette.fill(Double(percent)).opacity(0.12))
                line(through: spots)
                    .stroke(DashboardPalette.ink(Double(percent)),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                Circle()
                    .fill(DashboardPalette.ink(Double(percent)))
                    .frame(width: 3.5, height: 3.5)
                    .position(last)
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }

    // MARK: - Geometrie

    /// Punkte in Ansichts-Koordinaten: x aus der Zeit (7 Tage = volle
    /// Breite), y aus dem Prozentwert (oben = 100). Ein Pixel Rand oben und
    /// unten, damit die Linie bei 0 % und 100 % nicht angeschnitten wird.
    private func layout(in size: CGSize) -> [CGPoint] {
        let start = end.addingTimeInterval(-Self.window)
        let inset: CGFloat = 2
        let height = max(1, size.height - inset * 2)
        return points.compactMap { point in
            let elapsed = point.t.timeIntervalSince(start)
            guard elapsed >= 0 else { return nil }
            // Nach vorn klemmen statt wegwerfen: Eine Server-Uhr, die der
            // eigenen um Minuten vorausgeht, darf nicht den jüngsten Punkt kosten.
            let fraction = CGFloat(min(1, elapsed / Self.window))
            let level = CGFloat(min(100, max(0, point.percent))) / 100
            return CGPoint(x: fraction * size.width,
                           y: inset + (1 - level) * height)
        }
    }

    private func line(through spots: [CGPoint]) -> Path {
        Path { path in
            path.addLines(spots)
        }
    }

    /// Die Fläche unter der Linie, bis zum unteren Rand geschlossen.
    private func area(through spots: [CGPoint], in size: CGSize) -> Path {
        Path { path in
            guard let first = spots.first, let last = spots.last else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLines(spots)
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }
}
