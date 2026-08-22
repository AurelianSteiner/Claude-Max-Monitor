//
//  MascotIncident.swift
//  Usage4Claude
//
//  Der seltene Zwischenfall auf dem Laufsteg.
//
//  Sehr selten (im Schnitt alle gut dreizehn Minuten) bleibt ein Claudie mitten im
//  Streifen stehen. Die beiden Nachbarn in der Parade halten an, drehen sich zu
//  ihm um und schießen ihn ab. Er kippt um, zerplatzt zu orangem Matsch, und ein
//  paar Sekunden später wächst an der Stelle ein kleiner Grabstein aus dem
//  Boden. Der steht gut drei Minuten. Alle, die danach vorbeikommen, bleiben
//  kurz davor stehen und weinen, bevor sie weitergehen.
//
//  Warum das ohne gespeicherten Zustand geht: Die Parade ist eine reine Funktion
//  der Uhrzeit, und dieser Zwischenfall auch. Ob eine Läufer-Nummer das Opfer
//  ist, entscheidet allein ihr Hash (`rawVictim`) — nicht der Zufall des
//  Augenblicks. Daraus folgt alles Weitere: Wer die Schützen sind (die Nummern
//  davor und danach), wann der Vorfall beginnt (wenn das Opfer die Mitte
//  erreicht) und wie lange er dauert. Das Fenster kann zwischendurch zu sein,
//  der Rechner schlafen, die Ansicht neu gebaut werden — beim nächsten Blick
//  steht der Grabstein trotzdem an der richtigen Stelle und ist genau so alt,
//  wie er sein müsste.
//
//  Der heikle Teil sind die Pausen. Solange alle Läufer exakt gleich schnell
//  sind, bleiben ihre Abstände stabil und niemand läuft auf den Vordermann auf.
//  Steht jemand still, schrumpft die Lücke um `Pause × Tempo`. Deshalb ist die
//  Pause (a) für alle Trauernden gleich lang, (b) eine reine Funktion aus
//  Nummer und Vorfall — nie davon abhängig, wo der Läufer gerade steht, sonst
//  spränge seine Position in dem Moment, in dem der Grabstein auftaucht — und
//  (c) kurz genug, dass die vergrößerten Startabstände der Parade (siehe
//  `MascotParadeCanvas.minInterval`) sie auffangen.
//
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

// MARK: - Rollen

/// Rolle eines Läufers in einem Zwischenfall — reine Funktion seiner Nummer,
/// deshalb steht schon beim Einlaufen fest, wer wer ist.
enum MascotIncidentRole: Equatable {
    /// Bleibt in der Mitte stehen und wird abgeschossen
    case victim
    /// Steht rechts vom Opfer (früher gestartet) und dreht sich zum Zielen um
    case shooterRight
    /// Steht links vom Opfer (später gestartet) und zielt nach rechts
    case shooterLeft
}

/// Ein gerade laufender Zwischenfall, abgeleitet aus Uhrzeit und Streifenbreite.
struct MascotIncidentState: Equatable {
    /// Nummer des Opfers im Läuferstrom
    let victimIndex: Int
    /// Absoluter Zeitpunkt, an dem das Opfer stehen bleibt — Nullpunkt des Ablaufs
    let start: TimeInterval
    /// Linke Kante des Opfer-Sprites; dort steht später der Grabstein
    let x: CGFloat
    /// Sekunden seit `start`
    let elapsed: TimeInterval
}

// MARK: - Ablauf und Zeitplan

enum MascotIncident {

    // MARK: Wie oft

    /// Wahrscheinlichkeit je Läufer, das Opfer zu sein — zusammen mit der
    /// Sperrfrist unten kommt im Schnitt alle gut dreizehn Minuten einer heraus:
    /// selten genug, dass es eine Überraschung bleibt, häufig genug, dass man
    /// es überhaupt einmal zu sehen bekommt.
    static let chance: Double = 1.0 / 90.0

    /// So viele Nummern zurück darf kein zweites Opfer liegen. Muss über der
    /// Lebensdauer eines Vorfalls in Startabständen liegen
    /// (`lifetime / minInterval` ≈ 78), sonst stünden zwei Gräber gleichzeitig
    /// auf demselben Fleck. Reine Funktion der Nummer — bewusst ohne die
    /// Streifenbreite, denn `MascotParadeCanvas.variant` fragt sie mit ab und
    /// kennt keine Breite.
    static let cooldown = 82

    /// Unter dieser Streifenbreite fällt der Zwischenfall aus: Die Schützen
    /// stehen gut 80 pt neben dem Opfer und wären sonst außerhalb des Bildes.
    static let minimumWidth: CGFloat = 260

    // MARK: Ablauf (Sekunden nach `start`)

    /// Das Opfer steht, die Schützen zielen — dann fällt der Schuss
    static let shotAt: TimeInterval = 0.9
    /// Die Geschosse sind da
    static let hitAt: TimeInterval = 1.3
    /// Das Opfer liegt
    static let fallEnd: TimeInterval = 1.9
    /// So lange blendet der Körper aus, während der Matsch einblendet
    static let splatFade: TimeInterval = 0.3
    /// Ab hier wächst der Grabstein aus dem Boden, der Matsch verblasst
    static let stoneRiseAt: TimeInterval = 5.0
    static let stoneRiseEnd: TimeInterval = 6.0
    /// Ab hier verblasst der Grabstein
    static let stoneFadeAt: TimeInterval = 186
    /// Gesamtdauer des *sichtbaren* Teils — danach ist die Stelle wieder leer
    static let total: TimeInterval = 189

    /// Nachlauf: So lange bleibt der Vorfall über sein Ende hinaus bekannt,
    /// obwohl längst nichts mehr zu sehen ist.
    ///
    /// Das ist keine Kosmetik, sondern Pflicht. Wer am Grab gestanden hat,
    /// hinkt für den Rest seines Wegs um `mournHold × Tempo` hinterher — diese
    /// Standzeit steckt in der Positionsformel und wird bei jedem Bild neu
    /// abgezogen. Verschwände der Vorfall, während so jemand noch im Bild ist,
    /// fiele der Abzug weg und er spränge einen halben Streifen nach vorn.
    /// Der Nachlauf reicht, bis auch der Letzte hinausgelaufen ist; für sehr
    /// breite Fenster sichert `pause` das zusätzlich einzeln ab.
    static let trailingGrace: TimeInterval = 45

    /// So lange kennt `active` den Vorfall insgesamt
    static var lifetime: TimeInterval { total + trailingGrace }

    /// So lange stehen die beiden Schützen — bis der Körper liegt, keine
    /// Sekunde länger: Jede zusätzliche Sekunde frisst 26 pt Abstand zu dem,
    /// der hinter ihnen kommt.
    static let shooterHold: TimeInterval = 1.9
    /// So lange bleibt ein Vorbeikommender am Grab stehen und weint
    static let mournHold: TimeInterval = 1.2
    /// Längste Pause überhaupt — die Parade rechnet damit, wie weit sie in der
    /// Vergangenheit nach noch sichtbaren Läufern suchen muss
    static let maxHold: TimeInterval = 1.9

    // MARK: Farben

    /// Der Matsch: Claudes Korallenton, aber deutlich sattere Tomate
    static let splat = Color(red: 0.878, green: 0.478, blue: 0.196)
    static let splatDark = Color(red: 0.718, green: 0.353, blue: 0.133)
    /// Mittleres Grau — trägt in hellem wie dunklem Erscheinungsbild
    static let stone = Color(red: 0.612, green: 0.620, blue: 0.659)
    static let stoneDark = Color(red: 0.427, green: 0.435, blue: 0.478)
    static let earth = Color(red: 0.408, green: 0.337, blue: 0.267)
    /// Träne
    static let tear = Color(red: 0.478, green: 0.706, blue: 0.937)
    /// Mündungsfeuer
    static let flash = Color(red: 0.996, green: 0.855, blue: 0.400)

    // MARK: - Wer ist wer

    /// Roher Würfelwurf: Wäre diese Nummer ein Opfer, wenn nichts dagegenspräche?
    /// Getrennt von `isVictim`, damit die Sperrfrist unten nicht in eine
    /// Endlosschleife läuft (sie fragt ausschließlich den rohen Wurf ab).
    private static func rawVictim(_ index: Int) -> Bool {
        MascotParadeCanvas.roll(index, 101) < chance
    }

    /// Ist diese Nummer das Opfer eines Zwischenfalls?
    static func isVictim(_ index: Int) -> Bool {
        guard rawVictim(index) else { return false }
        // Sperrfrist: Solange der letzte Grabstein noch stehen könnte, gibt es
        // kein zweites Opfer. Die Schleife läuft nur im Trefferfall (1 von 90),
        // kostet also praktisch nichts.
        for back in 1...cooldown where rawVictim(index - back) { return false }
        return true
    }

    /// Rolle dieser Nummer. Die drei Fälle schließen sich gegenseitig aus:
    /// Wegen der Sperrfrist kann neben einem Opfer kein zweites liegen.
    static func role(of index: Int) -> MascotIncidentRole? {
        if isVictim(index) { return .victim }
        // Nummer + 1 ist das Opfer → dieser hier startete früher, läuft also
        // vorneweg und steht rechts vom Opfer.
        if isVictim(index + 1) { return .shooterRight }
        if isVictim(index - 1) { return .shooterLeft }
        return nil
    }

    // MARK: - Zeitplan

    /// Wo das Opfer stehen bleibt: mittig im Streifen.
    static func victimX(width: CGFloat) -> CGFloat {
        (width - MascotParadeCanvas.spriteWidth) / 2
    }

    /// Wann Läufer `index` die Mitte erreicht — der Nullpunkt des Ablaufs.
    static func stopTime(victim index: Int, width: CGFloat) -> TimeInterval {
        MascotParadeCanvas.spawnTime(index)
            + Double(victimX(width: width) + MascotParadeCanvas.overshoot) / MascotParadeCanvas.baseSpeed
    }

    /// Der gerade laufende Zwischenfall — oder nil, wenn gerade keiner läuft.
    ///
    /// Gesucht wird rückwärts vom jüngsten Läufer aus: weit genug, dass auch ein
    /// Grabstein gefunden wird, dessen Opfer längst aus dem Bild wäre.
    static func active(at time: TimeInterval, width: CGFloat) -> MascotIncidentState? {
        guard width >= minimumWidth else { return nil }

        let x = victimX(width: width)
        let travel = Double(x + MascotParadeCanvas.overshoot) / MascotParadeCanvas.baseSpeed
        let lookback = Int(((lifetime + travel) / MascotParadeCanvas.minInterval).rounded(.up)) + 6
        let newest = Int((time / MascotParadeCanvas.avgInterval).rounded(.down)) + 1

        var index = newest
        while index >= newest - lookback {
            if isVictim(index) {
                let start = MascotParadeCanvas.spawnTime(index) + travel
                if time >= start, time < start + lifetime {
                    return MascotIncidentState(victimIndex: index, start: start,
                                               x: x, elapsed: time - start)
                }
            }
            index -= 1
        }
        return nil
    }

    // MARK: - Pausen

    /// Wo ein Vorbeikommender stehen bleibt: knapp links neben dem Grab. Der
    /// kleine Versatz nach Nummer verhindert, dass alle auf exakt demselben
    /// Fleck halten — drei Positionen reichen, dazwischen liegt immer ein
    /// Startabstand.
    static func mournStopX(_ index: Int, incident: MascotIncidentState) -> CGFloat {
        incident.x - MascotParadeCanvas.spriteWidth - 14 - CGFloat(index % 3) * 6
    }

    /// Pause dieses Läufers: ab wann und wie lange er steht. nil = läuft durch.
    ///
    /// Bewusst nur aus Nummer, Rolle und Vorfall gerechnet — nie aus der
    /// aktuellen Position. Sonst bekäme ein Läufer, der den Fleck längst
    /// passiert hat, im Moment des Grabstein-Auftauchens rückwirkend eine Pause
    /// und spränge nach hinten.
    static func pause(
        for index: Int,
        role: MascotIncidentRole?,
        incident: MascotIncidentState?,
        spawn: TimeInterval,
        speed: Double
    ) -> (start: TimeInterval, length: TimeInterval)? {
        guard let incident else { return nil }

        guard let role else {
            // Unbeteiligter: bleibt am Grab stehen, wenn er dort ankommt,
            // *während* dort etwas liegt. Wer schon vorbei war, bekommt keine
            // Pause nachgereicht — sein x spränge sonst zurück.
            let stopX = mournStopX(index, incident: incident)
            let arrival = spawn + Double(stopX + MascotParadeCanvas.overshoot) / speed
            guard arrival > incident.start, arrival < incident.start + total else { return nil }

            // Und nur, wenn er danach das Bild verlässt, bevor der Vorfall aus
            // dem Gedächtnis fällt: Sonst verschwände seine Standzeit unter ihm
            // und er spränge nach vorn. Bei üblichen Breiten greift die Grenze
            // nie — der Grabstein ist längst weg, bevor sie zählt.
            let width = incident.x * 2 + MascotParadeCanvas.spriteWidth
            let exit = arrival + mournHold
                + Double(width + MascotParadeCanvas.overshoot - stopX) / speed
            guard exit < incident.start + lifetime else { return nil }

            return (arrival, mournHold)
        }

        switch role {
        case .victim:
            // Das Opfer bleibt für immer stehen — dafür sorgt die Zeichenroutine.
            return nil

        case .shooterLeft, .shooterRight:
            // Nur die Nachbarn des *aktuellen* Opfers halten an.
            guard abs(index - incident.victimIndex) == 1 else { return nil }
            return (incident.start, shooterHold)
        }
    }

    /// Wo ein Schütze steht, während er zielt: genau dort, wo ihn der Halt des
    /// Opfers überrascht hat. Dieselbe Zahl, die auch die Parade über ihre
    /// Pausenrechnung herausbekommt — hier direkt, damit die Geschosse an der
    /// richtigen Stelle losfliegen, ohne dass die Zeichenschleife etwas
    /// zwischenspeichern muss.
    static func frozenX(of index: Int, incident: MascotIncidentState) -> CGFloat {
        CGFloat((incident.start - MascotParadeCanvas.spawnTime(index)) * MascotParadeCanvas.baseSpeed)
            - MascotParadeCanvas.overshoot
    }

    // MARK: - Zeichnen: Boden (Matsch, Grabstein)

    /// Matsch und Grabstein. Wird **vor** den Läufern gezeichnet, damit die
    /// Trauernden davor vorbeigehen und der Stein nicht wie ein Hindernis
    /// mitten im Weg klebt.
    static func drawGround(in ctx: GraphicsContext, incident: MascotIncidentState) {
        let t = incident.elapsed
        // Der Vorfall bleibt danach noch bekannt (siehe `trailingGrace`),
        // sichtbar ist ab hier aber nichts mehr.
        guard t < total else { return }
        let cell = MascotParadeCanvas.cell

        var ground = ctx
        ground.translateBy(x: incident.x, y: 13)

        func px(_ col: Double, _ row: Double, _ color: Color, _ w: Double = 1, _ h: Double = 1) {
            let rect = CGRect(x: col * cell, y: row * cell, width: w * cell, height: h * cell)
            ground.fill(Path(rect), with: .color(color))
        }

        // --- Matsch: blendet ein, während der Körper ausblendet, und verblasst,
        //     sobald der Stein wächst. Ein blasser Rest bleibt am Sockel liegen.
        let splatAlpha: Double = {
            // Der Matsch wächst schon unter dem Einsackenden hervor — dadurch
            // wird aus „Körper weg, Matsch da" ein Übergang statt eines Schnitts.
            let begins = hitAt + 0.3
            if t < begins { return 0 }
            if t < fallEnd + splatFade { return (t - begins) / (fallEnd + splatFade - begins) }
            if t < stoneRiseAt { return 1 }
            if t < stoneRiseEnd {
                let fade = (t - stoneRiseAt) / (stoneRiseEnd - stoneRiseAt)
                return 1 - fade * 0.75          // 25 % bleiben als Fleck
            }
            // Der Fleck bleibt liegen und verblasst am Ende mit dem Stein
            guard t >= stoneFadeAt else { return 0.25 }
            return 0.25 * max(0, 1 - (t - stoneFadeAt) / (total - stoneFadeAt))
        }()

        if splatAlpha > 0.02 {
            let a = splatAlpha
            px(0.4, 4.55, splatDark.opacity(a * 0.85), 7.2, 0.45)
            px(1.4, 4.05, splat.opacity(a), 5.2, 0.6)
            px(2.5, 3.6, splat.opacity(a * 0.9), 3.0, 0.5)
            // Spritzer
            px(-1.4, 4.35, splat.opacity(a * 0.8), 0.6, 0.5)
            px(-2.3, 4.75, splatDark.opacity(a * 0.7), 0.45, 0.35)
            px(8.6, 4.15, splat.opacity(a * 0.8), 0.7, 0.6)
            px(9.6, 4.6, splatDark.opacity(a * 0.7), 0.45, 0.4)
        }

        // --- Grabstein: wächst aus dem Boden (der Streifen ist beschnitten,
        //     der Stein kommt also wirklich von unten) und verblasst am Ende.
        guard t >= stoneRiseAt else { return }
        let stoneAlpha = t < stoneFadeAt ? 1.0 : max(0, 1 - (t - stoneFadeAt) / (total - stoneFadeAt))
        guard stoneAlpha > 0.02 else { return }

        let rise = min(1, max(0, (t - stoneRiseAt) / (stoneRiseEnd - stoneRiseAt)))
        let eased = 1 - pow(1 - rise, 3)        // schnell raus, sanft ankommen

        // Erdhügel bleibt am Boden, nur der Stein fährt hoch
        px(0.9, 4.85, earth.opacity(stoneAlpha * 0.9), 6.2, 0.5)

        var slab = ground
        slab.translateBy(x: 0, y: (1 - eased) * 22)
        func spx(_ col: Double, _ row: Double, _ color: Color, _ w: Double = 1, _ h: Double = 1) {
            let rect = CGRect(x: col * cell, y: row * cell, width: w * cell, height: h * cell)
            slab.fill(Path(rect), with: .color(color))
        }
        spx(2.6, 0.75, stone.opacity(stoneAlpha), 2.8, 0.6)          // gerundete Kuppe
        spx(2.2, 1.3, stone.opacity(stoneAlpha), 3.6, 3.3)           // Korpus
        spx(2.2, 4.35, stoneDark.opacity(stoneAlpha), 3.6, 0.5)      // Schattenkante unten
        spx(1.4, 4.6, stone.opacity(stoneAlpha), 5.2, 0.45)          // Sockel
        spx(3.0, 2.0, stoneDark.opacity(stoneAlpha * 0.8), 2.0, 0.3) // Gravur
        spx(3.2, 2.7, stoneDark.opacity(stoneAlpha * 0.8), 1.6, 0.3)
    }

    // MARK: - Zeichnen: das Opfer

    /// Das Opfer ab dem Moment, in dem es stehen bleibt: erst still, dann kippt
    /// es, dann blendet es aus und überlässt dem Matsch die Stelle.
    /// Gibt `false` zurück, wenn nichts mehr zu zeichnen ist — dann überspringt
    /// die Parade diese Nummer ganz.
    @discardableResult
    static func drawVictim(in ctx: GraphicsContext, incident: MascotIncidentState,
                           time: TimeInterval, seed: Int) -> Bool {
        let t = incident.elapsed
        guard t < fallEnd + 0.2 else { return false }

        // Zusammensacken: beschleunigt wie unter Schwerkraft — erst kippt er
        // kaum, am Ende geht es schnell.
        var collapse: Double = 0
        if t >= hitAt {
            let progress = min(1, (t - hitAt) / (fallEnd - hitAt))
            collapse = progress * progress
        }
        // Blendet aus, während der Matsch schon steht — die letzten Bilder
        // überlagern sich bewusst.
        let alpha = t <= fallEnd - 0.1 ? 1 : max(0, 1 - (t - (fallEnd - 0.1)) / 0.3)

        MascotParadeCanvas.drawWalker(
            in: ctx, x: incident.x, step: false, alpha: alpha,
            variant: .normal, time: time, seed: seed,
            pose: .standing, collapse: collapse
        )
        return true
    }

    // MARK: - Zeichnen: Schüsse

    /// Mündungsfeuer, Geschosse und der kleine Einschlag. Kommt **nach** den
    /// Läufern, damit nichts davorliegt.
    static func drawShots(in ctx: GraphicsContext, incident: MascotIncidentState) {
        let t = incident.elapsed
        guard t >= shotAt, t < hitAt + 0.35 else { return }

        var shots = ctx
        let cell = MascotParadeCanvas.cell
        let chestY: CGFloat = 13 + 2.2 * cell
        // Brusthöhe des Opfers, je Seite die zugewandte Kante
        let targetLeft = incident.x + 1.5 * cell
        let targetRight = incident.x + 6.5 * cell

        let leftMuzzle = frozenX(of: incident.victimIndex + 1, incident: incident) + 9.3 * cell
        let rightMuzzle = frozenX(of: incident.victimIndex - 1, incident: incident) - 1.3 * cell

        func dot(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
            shots.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
        }

        // Mündungsfeuer — zwei Bilder lang
        if t < shotAt + 0.14 {
            dot(leftMuzzle, chestY - 2, 5, 5, flash)
            dot(rightMuzzle - 5, chestY - 2, 5, 5, flash)
        }

        // Geschosse unterwegs
        if t < hitAt {
            let p = CGFloat((t - shotAt) / (hitAt - shotAt))
            let lx = leftMuzzle + (targetLeft - leftMuzzle) * p
            let rx = rightMuzzle + (targetRight - rightMuzzle) * p
            dot(lx, chestY, 6, 3, MascotParadeCanvas.faceInk)
            dot(rx - 6, chestY, 6, 3, MascotParadeCanvas.faceInk)
        }

        // Einschlag: ein paar Tropfen fliegen weg
        if t >= hitAt {
            let p = (t - hitAt) / 0.35
            let a = 1 - p
            guard a > 0.05 else { return }
            let cx = incident.x + 4 * cell
            for spark in 0..<6 {
                let angle = Double(spark) * (.pi / 3) + 0.4
                let reach = CGFloat(14 * p)
                dot(cx + reach * CGFloat(cos(angle)) - 1.5,
                    chestY + reach * CGFloat(sin(angle)) - 1.5,
                    3, 3, splat.opacity(a))
            }
        }
    }
}
