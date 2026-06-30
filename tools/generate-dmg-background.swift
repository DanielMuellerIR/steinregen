#!/usr/bin/env swift
// tools/generate-dmg-background.swift — erzeugt das DMG-Hintergrundbild (assets/dmg-background.png).
//
// Layout passt exakt zu den Icon-Positionen, die make-dmg.sh per AppleScript im Finder-Fenster
// setzt: App-Icon bei (150,180), Applications-Ordner bei (450,180), Fenster-Innenmaß 600×400.
// Dazwischen ein bone-weißer Pfeil („zieh die App nach Applications"). Optik wie das Spiel:
// pechschwarz, dezenter Ochsenblut-Schimmer, das von Hand getuschte Logo oben.
//
// Wichtig: Es wird in eine FESTE 600×400-Bitmap gezeichnet (1 Punkt = 1 Pixel) — sonst rendert
// `NSImage.lockFocus` auf Retina mit 2× (1200×800) und Finder beschneidet den Hintergrund.
// Dadurch ist die Ausgabe auch reproduzierbar, unabhängig vom Display des bauenden Macs.
//
// Aufruf:  swift tools/generate-dmg-background.swift [out.png]
//          (Default-Ausgabe: assets/dmg-background.png; ins Repo eingecheckt.)

import AppKit
import CoreText
import Foundation

// --- Maße = Finder-Fenster-Innenmaß (siehe macos-app-distribution.md: Bild = Fenstergröße) ---
let W: CGFloat = 600
let H: CGFloat = 400

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/dmg-background.png"
let resDir = "Sources/SteinregenRender/Resources"

// Spiel-Schrift aus den Resources registrieren (sonst System-Font als Fallback).
func registerFont(_ path: String) {
    if FileManager.default.fileExists(atPath: path) {
        CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, nil)
    }
}
registerFont("\(resDir)/GrenzeGotisch-Regular.ttf")

// --- Feste 600×400-Bitmap (8 Bit RGBA), 1 Punkt = 1 Pixel ---
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    fputs("FEHLER: Bitmap konnte nicht angelegt werden\n", stderr); exit(1)
}
rep.size = NSSize(width: W, height: H)

NSGraphicsContext.saveGraphicsState()
guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else {
    fputs("FEHLER: kein Grafik-Kontext\n", stderr); exit(1)
}
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext

// --- Hintergrund: fast schwarz, darüber ein dezenter Ochsenblut-Radialschimmer unten-mittig ---
ctx.setFillColor(NSColor(calibratedRed: 0.043, green: 0.043, blue: 0.051, alpha: 1).cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

let glowColors = [
    NSColor(calibratedRed: 0.34, green: 0.02, blue: 0.05, alpha: 0.32).cgColor,
    NSColor(calibratedRed: 0.043, green: 0.043, blue: 0.051, alpha: 0.0).cgColor,
] as CFArray
if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: [0, 1]) {
    let c = CGPoint(x: W / 2, y: H * 0.30)   // AppKit-Ursprung unten-links
    ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: W * 0.55, options: [])
}

// --- Logo oben-mittig, in eine Box 360×150 eingepasst (Seitenverhältnis erhalten) ---
if let logo = NSImage(contentsOfFile: "\(resDir)/logo.png"), logo.size.width > 0 {
    let box = NSSize(width: 360, height: 150)
    let scale = min(box.width / logo.size.width, box.height / logo.size.height)
    let lw = logo.size.width * scale
    let lh = logo.size.height * scale
    let lx = (W - lw) / 2
    let ly = H - lh - 30          // nahe Oberkante
    logo.draw(in: NSRect(x: lx, y: ly, width: lw, height: lh),
              from: .zero, operation: .sourceOver, fraction: 0.96)
}

// --- Pfeil zwischen den Icon-Plätzen (App 150,180 → Applications 450,180; Finder-Koord. top-left) ---
let yArrow = H - 180            // Finder-y=180 von oben → AppKit-y von unten
let bone = NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.92, alpha: 0.92)
bone.setStroke(); bone.setFill()
let shaft = NSBezierPath()
shaft.lineWidth = 6
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 218, y: yArrow))
shaft.line(to: NSPoint(x: 378, y: yArrow))
shaft.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 392, y: yArrow))
head.line(to: NSPoint(x: 372, y: yArrow + 12))
head.line(to: NSPoint(x: 372, y: yArrow - 12))
head.close()
head.fill()

// --- Hinweistext unten, dezent (zweisprachig-neutral) ---
let hint = "In den Programme-Ordner ziehen  ·  Drag into Applications"
let font = NSFont(name: "GrenzeGotisch-Regular", size: 17)
    ?? NSFont(name: "GrenzeGotisch", size: 17)
    ?? NSFont.systemFont(ofSize: 15)
let para = NSMutableParagraphStyle(); para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(calibratedWhite: 0.86, alpha: 0.6),
    .paragraphStyle: para,
]
(hint as NSString).draw(in: NSRect(x: 0, y: 30, width: W, height: 26), withAttributes: attrs)

NSGraphicsContext.restoreGraphicsState()

// --- als PNG schreiben ---
guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("FEHLER: PNG-Kodierung fehlgeschlagen\n", stderr); exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("geschrieben: \(outPath)  (\(Int(W))×\(Int(H)))")
} catch {
    fputs("FEHLER: \(outPath) nicht schreibbar: \(error)\n", stderr); exit(1)
}
