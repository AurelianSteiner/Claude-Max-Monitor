//
//  AwakeMascotView.swift
//  Usage4Claude
//
//  Das Maskottchen im Kopf der Übersicht: ein kleiner runder Arbeiter an
//  einem winzigen Laptop, 40 × 24 pt. Er macht den Wach-Zustand sichtbar,
//  ohne dass man den Schalter lesen muss:
//
//  „Bleib wach" AN — Endlosschleife über 23 Sekunden:
//    0 s – 20 s   tippen, die Arme wechseln alle 0,4 s
//    20 s – 22,5 s einnicken: Augen zu, Kopf kippt, ein „z" steigt auf
//    22,5 s – 23 s BONK — kleiner Sternblitz, der Kopf schnellt hoch,
//                  dann wieder tippen. Niemand schläft hier ein.
//
//  „Bleib wach" AUS — friedlicher Schlaf: Kopf gesenkt, „z z" steigen
//  langsam auf. Ein stilles Bild dafür, dass nichts wach gehalten wird.
//
//  Technik: `TimelineView(.periodic)` treibt eine reine Phasenfunktion über
//  das Datum — kein eigener Timer, nichts läuft weiter, wenn die Ansicht
//  nicht sichtbar ist (Popover zu, Fenster zu). Die Periode ist 1/3 s im
//  Wach-Zustand und 1/2 s im Schlaf, effektiv also höchstens ~3 fps —
//  die CPU-Last ist nicht messbar. Kein eigenes Bildmaterial, keine Logos:
//  alles sind einfache Canvas-Formen in warmen Orangetönen.
//
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

// MARK: - Phasenautomat

/// Der Zustand des Maskottchens zu einem Zeitpunkt — eine reine Funktion der
/// Uhrzeit, damit `TimelineView` genügt und kein Zustand gehalten werden muss.
enum AwakeMascotPhase: Equatable {
    /// Tippt; `armUp` wechselt im Takt der Arm-Alternation
    case typing(armUp: Bool)
    /// Nickt ein; `progress` 0…1 über die Doz-Dauer (Kopf kippt, „z" steigt)
    case dozing(progress: Double)
    /// Der Weck-BONK; `progress` 0…1 über die Blitz-Dauer
    case bonk(progress: Double)
    /// „Bleib wach" ist aus; `zPhase` 0…1 lässt die „z z" langsam aufsteigen
    case sleeping(zPhase: Double)

    // Die Taktung der Wach-Schleife (Sekunden)
    static let typingDuration: TimeInterval = 20
    static let armSwitchInterval: TimeInterval = 0.4
    static let dozingDuration: TimeInterval = 2.5
    static let bonkDuration: TimeInterval = 0.5
    static var cycleDuration: TimeInterval { typingDuration + dozingDuration + bonkDuration }
    /// Periode der aufsteigenden „z z" im Schlaf
    static let sleepZPeriod: TimeInterval = 4

    static func at(_ time: TimeInterval, isAwake: Bool) -> AwakeMascotPhase {
        guard isAwake else {
            let cycle = time.truncatingRemainder(dividingBy: sleepZPeriod)
            return .sleeping(zPhase: cycle / sleepZPeriod)
        }
        let cycle = time.truncatingRemainder(dividingBy: cycleDuration)
        if cycle < typingDuration {
            return .typing(armUp: Int(cycle / armSwitchInterval) % 2 == 0)
        }
        if cycle < typingDuration + dozingDuration {
            return .dozing(progress: (cycle - typingDuration) / dozingDuration)
        }
        return .bonk(progress: (cycle - typingDuration - dozingDuration) / bonkDuration)
    }
}

// MARK: - View

struct AwakeMascotView: View {

    @ObservedObject private var sleepGuard = SleepGuard.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: sleepGuard.isAwake ? 1.0 / 3.0 : 0.5)) { timeline in
            AwakeMascotCanvas(
                phase: AwakeMascotPhase.at(
                    timeline.date.timeIntervalSinceReferenceDate,
                    isAwake: sleepGuard.isAwake
                )
            )
        }
        .frame(width: 40, height: 24)
        .help(sleepGuard.isAwake ? L.Dashboard.mascotAwakeHelp : L.Dashboard.mascotAsleepHelp)
        .accessibilityLabel(sleepGuard.isAwake ? L.Dashboard.mascotAwakeHelp : L.Dashboard.mascotAsleepHelp)
    }
}

// MARK: - Zeichnung

/// Zeichnet eine einzelne Momentaufnahme des Maskottchens.
/// Alle Koordinaten leben in einem festen 40 × 24-Raster (Ursprung oben links);
/// nichts ragt über den Rahmen hinaus.
private struct AwakeMascotCanvas: View {

    let phase: AwakeMascotPhase

    // Warme Orange-/Koralltöne — bewusst generisch, kein Logo, kein Markenbezug
    private static let skin = Color(red: 0.96, green: 0.62, blue: 0.42)
    private static let skinShade = Color(red: 0.85, green: 0.47, blue: 0.30)
    private static let face = Color(red: 0.35, green: 0.2, blue: 0.12)

    var body: some View {
        Canvas { context, _ in
            let asleep: Bool
            if case .sleeping = phase { asleep = true } else { asleep = false }

            drawLaptop(in: context, screenLit: !asleep)
            drawBody(in: context, dimmed: asleep)
            drawArms(in: context)
            drawHead(in: context, dimmed: asleep)
            drawExtras(in: context)
        }
        .frame(width: 40, height: 24)
    }

    // MARK: Kopfneigung je Phase

    /// Neigung des Kopfs in Grad — 0 aufrecht, positiv = nach vorn (zum Laptop)
    private var headTilt: Double {
        switch phase {
        case .typing: return 0
        case .dozing(let progress): return 24 * progress
        case .bonk: return -6   // hochgeschnellt, leicht zurück
        case .sleeping: return 30
        }
    }

    /// Augen zu? (Dozen ab halber Strecke, Schlaf immer)
    private var eyesClosed: Bool {
        switch phase {
        case .typing: return false
        case .dozing(let progress): return progress > 0.3
        case .bonk: return false
        case .sleeping: return true
        }
    }

    // MARK: Laptop (rechts)

    private func drawLaptop(in context: GraphicsContext, screenLit: Bool) {
        // Bildschirmdeckel: steht leicht schräg auf, Klappe zeigt zur Figur
        let lid = Path(roundedRect: CGRect(x: 29, y: 6, width: 8, height: 12), cornerRadius: 1.5)
        context.fill(lid, with: .color(.secondary.opacity(0.55)))

        // Bildschirmfläche: leuchtet beim Arbeiten, dunkel im Schlaf
        let screen = Path(roundedRect: CGRect(x: 30, y: 7, width: 6, height: 10), cornerRadius: 1)
        context.fill(screen, with: .color(
            screenLit ? Color(red: 0.55, green: 0.75, blue: 0.95) : .secondary.opacity(0.25)
        ))

        // Unterteil mit Tastatur
        let base = Path(roundedRect: CGRect(x: 22, y: 18, width: 16, height: 3), cornerRadius: 1.5)
        context.fill(base, with: .color(.secondary.opacity(0.7)))
    }

    // MARK: Körper & Arme (links)

    private func drawBody(in context: GraphicsContext, dimmed: Bool) {
        let body = Path(ellipseIn: CGRect(x: 7, y: 13, width: 13, height: 11))
        context.fill(body, with: .color(Self.skin.opacity(dimmed ? 0.75 : 1)))
    }

    private func drawArms(in context: GraphicsContext) {
        var armUpFront = false
        var resting = false
        switch phase {
        case .typing(let armUp): armUpFront = armUp
        case .bonk: armUpFront = true
        case .dozing, .sleeping: resting = true
        }

        // Zwei kurze Arme vom Körper zur Tastatur; beim Tippen wechselt,
        // welcher gerade oben ist. In Ruhe hängen beide auf der Tastatur.
        var front = Path()
        front.move(to: CGPoint(x: 17, y: 16))
        front.addLine(to: CGPoint(x: 24, y: resting ? 18.5 : (armUpFront ? 16.5 : 18.5)))

        var back = Path()
        back.move(to: CGPoint(x: 18, y: 18))
        back.addLine(to: CGPoint(x: 26, y: resting ? 18.5 : (armUpFront ? 18.5 : 16.5)))

        let stroke = StrokeStyle(lineWidth: 2, lineCap: .round)
        context.stroke(back, with: .color(Self.skinShade), style: stroke)
        context.stroke(front, with: .color(Self.skin), style: stroke)
    }

    // MARK: Kopf

    private func drawHead(in context: GraphicsContext, dimmed: Bool) {
        var head = context
        // Um den Halsansatz drehen, damit „einnicken" wie Nicken aussieht
        head.translateBy(x: 13, y: 13)
        head.rotate(by: .degrees(headTilt))

        let radius: CGFloat = 5.5
        let circle = Path(ellipseIn: CGRect(x: -radius, y: -7 - radius, width: radius * 2, height: radius * 2))
        head.fill(circle, with: .color(Self.skin.opacity(dimmed ? 0.75 : 1)))

        // Augen: offen = Punkte, zu = kleine Striche
        let eyeY: CGFloat = -7.5
        for eyeX in [CGFloat(-2), CGFloat(2.2)] {
            if eyesClosed {
                var lid = Path()
                lid.move(to: CGPoint(x: eyeX - 1, y: eyeY))
                lid.addLine(to: CGPoint(x: eyeX + 1, y: eyeY))
                head.stroke(lid, with: .color(Self.face), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            } else {
                let eye = Path(ellipseIn: CGRect(x: eyeX - 0.9, y: eyeY - 0.9, width: 1.8, height: 1.8))
                head.fill(eye, with: .color(Self.face))
            }
        }
    }

    // MARK: Extras: „z", BONK-Stern

    private func drawExtras(in context: GraphicsContext) {
        switch phase {
        case .typing:
            break

        case .dozing(let progress):
            // Ein einzelnes „z" steigt über dem Kopf auf und verblasst
            drawZ(in: context, at: CGPoint(x: 21, y: 7 - 5 * progress),
                  size: 6, opacity: 1 - 0.6 * progress)

        case .bonk(let progress):
            // Sternblitz überm Kopf — kurz und komisch, kein Donnerwetter
            drawStar(in: context, at: CGPoint(x: 13, y: 3.5),
                     outer: 3.5, inner: 1.4, opacity: 1 - 0.5 * progress)

        case .sleeping(let zPhase):
            // Zwei versetzte „z z" steigen gemächlich auf
            drawZ(in: context, at: CGPoint(x: 21, y: 8 - 5 * zPhase),
                  size: 6, opacity: 1 - zPhase)
            let second = (zPhase + 0.5).truncatingRemainder(dividingBy: 1)
            drawZ(in: context, at: CGPoint(x: 25, y: 9 - 5 * second),
                  size: 4.5, opacity: (1 - second) * 0.8)
        }
    }

    private func drawZ(in context: GraphicsContext, at point: CGPoint, size: CGFloat, opacity: Double) {
        guard opacity > 0.05 else { return }
        context.draw(
            Text(verbatim: "z")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundColor(.secondary.opacity(opacity)),
            at: point
        )
    }

    /// Vierzackiger Comic-Stern (Aufprallblitz) um `center`
    private func drawStar(in context: GraphicsContext, at center: CGPoint, outer: CGFloat, inner: CGFloat, opacity: Double) {
        var path = Path()
        for i in 0..<8 {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = Double(i) * .pi / 4 - .pi / 2
            let point = CGPoint(
                x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle))
            )
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        context.fill(path, with: .color(Color.yellow.opacity(opacity)))
        context.stroke(path, with: .color(Color.orange.opacity(opacity)), lineWidth: 0.5)
    }
}
