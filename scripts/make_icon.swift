//
//  make_icon.swift — erzeugt die App-Symbol-PNGs
//
//  Zeichnet das Symbol (Wasserstand im Ring auf Creme) in allen Größen, die der
//  Asset-Katalog braucht, und schreibt sie direkt dorthin. Damit ist das Symbol
//  Code und keine Binärdatei, die niemand mehr ändern kann.
//
//  Aufruf:  swift scripts/make_icon.swift
//

import AppKit
import Foundation

// Farben aus der Auslastungsskala der App
let cream = NSColor(red: 0xF5 / 255.0, green: 0xF1 / 255.0, blue: 0xEC / 255.0, alpha: 1)
let well = NSColor(red: 0xE8 / 255.0, green: 0xE2 / 255.0, blue: 0xDA / 255.0, alpha: 1)
let water = NSColor(red: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0, alpha: 1)
let outline = NSColor(red: 0x2B / 255.0, green: 0x2A / 255.0, blue: 0x28 / 255.0, alpha: 1)

/// Anteil, bis zu dem der Ring gefüllt ist. Bewusst nicht halb — ein leicht
/// asymmetrischer Pegel liest sich als Messwert, genau in der Mitte als Dekor.
let fillLevel: CGFloat = 0.62

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let context = NSGraphicsContext.current else { fatalError("kein Grafikkontext") }
    context.imageInterpolation = .high
    context.cgContext.setShouldAntialias(true)

    // macOS-Symbole bringen ihre Form selbst mit und lassen aussen Luft:
    // die Kachel nimmt rund 80 % der Kantenlänge ein.
    let inset = size * 0.0977
    let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let corner = tile.width * 0.2245

    let tilePath = NSBezierPath(roundedRect: tile, xRadius: corner, yRadius: corner)
    cream.setFill()
    tilePath.fill()

    // Ring
    let radius = tile.width * 0.34
    let center = NSPoint(x: tile.midX, y: tile.midY)
    let circleRect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    let circle = NSBezierPath(ovalIn: circleRect)

    well.setFill()
    circle.fill()

    // Wasser mit ruhiger Welle an der Oberkante, auf den Ring beschnitten
    NSGraphicsContext.saveGraphicsState()
    circle.addClip()

    let surfaceY = circleRect.minY + circleRect.height * fillLevel
    let waveHeight = radius * 0.075
    let wave = NSBezierPath()
    wave.move(to: NSPoint(x: circleRect.minX - radius, y: surfaceY))
    wave.curve(
        to: NSPoint(x: center.x, y: surfaceY),
        controlPoint1: NSPoint(x: circleRect.minX - radius * 0.4, y: surfaceY + waveHeight),
        controlPoint2: NSPoint(x: circleRect.minX + radius * 0.4, y: surfaceY + waveHeight)
    )
    wave.curve(
        to: NSPoint(x: circleRect.maxX + radius, y: surfaceY),
        controlPoint1: NSPoint(x: center.x + radius * 0.6, y: surfaceY - waveHeight),
        controlPoint2: NSPoint(x: circleRect.maxX + radius * 0.4, y: surfaceY - waveHeight)
    )
    wave.line(to: NSPoint(x: circleRect.maxX + radius, y: circleRect.minY - radius))
    wave.line(to: NSPoint(x: circleRect.minX - radius, y: circleRect.minY - radius))
    wave.close()
    water.setFill()
    wave.fill()

    NSGraphicsContext.restoreGraphicsState()

    // Kontur zuletzt, damit sie über der Wasserkante liegt
    outline.setStroke()
    circle.lineWidth = max(1, radius * 0.1)
    circle.stroke()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL, pixelSize: Int) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize, pixelsHigh: pixelSize,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("Bitmap konnte nicht angelegt werden") }

    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG konnte nicht erzeugt werden")
    }
    try! data.write(to: url)
    print("geschrieben: \(url.lastPathComponent) (\(pixelSize)px)")
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Usage4Claude/Resources/Assets.xcassets/AppIcon.appiconset")

for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = drawIcon(size: CGFloat(size))
    writePNG(image, to: iconset.appendingPathComponent("\(size).png"), pixelSize: size)
}

print("fertig")
