#!/usr/bin/env swift
// tools/make-social-preview.swift — erzeugt das GitHub-Social-Preview-Bild (assets/social-preview.png).
//
// GitHub zeigt dieses Bild, wenn der Repo-Link geteilt wird (Slack, X, Discord, Link-Vorschau).
// Empfohlenes Format: 1280×640 (2:1). Optik = das Spiel: pechschwarz, ein echter Nebel-Friedhof
// als Hintergrund (abgedunkelt), Ochsenblut-Schimmer, das von Hand getuschte Logo. Es zeigt BEIDE
// Spielmodi: oben ein Band aus Tetromino-Formen (Modus „Eingemauert", schlichte Blöcke, alle bündig
// auf einer Baseline), rechts die fallende Säule aus drei echten Sigil-Steinen (Modus „Steinschlag").
//
// Wie der DMG-Hintergrund-Composer ist dies ein eigenständiges Swift-Skript (kein Modul-Import):
// die Sigil-Pfade sind 1:1 aus `SigilStones.swift` übernommen, die Tetromino-Formen 1:1 aus
// `Tetromino.swift`, die Farben 1:1 aus `Theme.swift` — damit alles exakt wie im Spiel aussieht.
//
// Es wird in eine FESTE 1280×640-Bitmap gezeichnet (1 Punkt = 1 Pixel) — sonst rendert
// `NSGraphicsContext` auf Retina mit 2× und das Ergebnis wäre nicht reproduzierbar.
//
// Aufruf:  swift tools/make-social-preview.swift [out.png] [hintergrund.png]
//          (Default-Ausgabe: assets/social-preview.png; ins Repo eingecheckt.)

import AppKit
import CoreText
import Foundation

// --- Maße = GitHub-Social-Preview-Empfehlung ---
let W: CGFloat = 1280
let H: CGFloat = 640

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/social-preview.png"
let resDir  = "Sources/SteinregenRender/Resources"
let backdropName = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "hintergrund.png"

// --- Farben 1:1 aus Theme.swift (RGB 0..1) ---
typealias RGB = (r: CGFloat, g: CGFloat, b: CGFloat)
let ink:     RGB = (0.039, 0.039, 0.047)   // dunkle Aussparungen in Sigillen
let bone:    RGB = (0.804, 0.780, 0.729)   // räudiges Off-White: Text + Sigille
let boneDim: RGB = (0.420, 0.400, 0.360)   // gedämpftes Knochenweiß (Sekundärtext)
let oxblood: RGB = (0.480, 0.102, 0.102)   // Akzent

// Die sechs Stein-Tönungen (gedeckt/entsättigt) — exakt wie Theme.tint(for:).
enum Gem: CaseIterable { case ruby, sapphire, emerald, topaz, diamond, amethyst }
func tint(_ gem: Gem) -> RGB {
    switch gem {
    case .ruby:     return (0.26, 0.10, 0.11)
    case .sapphire: return (0.11, 0.15, 0.24)
    case .emerald:  return (0.11, 0.20, 0.13)
    case .topaz:    return (0.24, 0.19, 0.09)
    case .diamond:  return (0.20, 0.21, 0.23)
    case .amethyst: return (0.19, 0.12, 0.23)
    }
}

// --- Schrift aus den Resources registrieren (sonst System-Font als Fallback) ---
func registerFont(_ path: String) {
    if FileManager.default.fileExists(atPath: path) {
        CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, nil)
    }
}
registerFont("\(resDir)/GrenzeGotisch-Regular.ttf")
registerFont("\(resDir)/GrenzeGotisch-Bold.ttf")

// --- Feste 1280×640-Bitmap (8 Bit RGBA), 1 Punkt = 1 Pixel ---
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

// Kleiner Helfer: Füll-/Strichfarbe direkt aus einem RGB setzen.
func setColor(_ c: RGB, _ alpha: CGFloat) {
    ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: alpha)
    ctx.setStrokeColor(red: c.r, green: c.g, blue: c.b, alpha: alpha)
}

// --- 1) Pechschwarzer Grund ---
ctx.setFillColor(NSColor(calibratedRed: 0.043, green: 0.043, blue: 0.051, alpha: 1).cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

// --- 2) Echter Friedhof-Hintergrund, formatfüllend (Cover) und abgedunkelt ---
if let bg = NSImage(contentsOfFile: "\(resDir)/\(backdropName)"), bg.size.width > 0 {
    // Cover: so skalieren, dass das Bild die Leinwand vollständig bedeckt (Überstand wird beschnitten).
    let scale = max(W / bg.size.width, H / bg.size.height)
    let dw = bg.size.width * scale
    let dh = bg.size.height * scale
    let dx = (W - dw) / 2
    let dy = (H - dh) / 2          // vertikal zentriert (Hochformat → oben/unten beschnitten)
    bg.draw(in: NSRect(x: dx, y: dy, width: dw, height: dh),
            from: .zero, operation: .sourceOver, fraction: 1.0)
    // Dunkler Schleier, damit Logo + Steine klar lesbar bleiben.
    ctx.setFillColor(NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.025, alpha: 0.52).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
}

// --- 3) Ochsenblut-Radialschimmer hinter der Stein-Säule (rechte Bildhälfte) ---
let glowCenter = CGPoint(x: 1005, y: 292)
let glowColors = [
    NSColor(calibratedRed: 0.34, green: 0.02, blue: 0.05, alpha: 0.42).cgColor,
    NSColor(calibratedRed: 0.043, green: 0.043, blue: 0.051, alpha: 0.0).cgColor,
] as CFArray
if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: [0, 1]) {
    ctx.drawRadialGradient(grad, startCenter: glowCenter, startRadius: 0,
                           endCenter: glowCenter, endRadius: 360, options: [])
}

// =====================================================================================
//  Sigil-Zeichnung — 1:1 aus SigilStones.swift (100×100-Feld, Ursprung OBEN links).
// =====================================================================================
func drawSigil(_ gem: Gem, area: CGRect, color: RGB, cut: RGB) {
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: area.minX + x / 100 * area.width, y: area.maxY - y / 100 * area.height)
    }
    func len(_ v: CGFloat) -> CGFloat { v / 100 * area.width }
    func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let lw = len(6)

    switch gem {
    case .ruby:     // umgekehrtes Pentagramm im Kreis
        setColor(color, 1)
        ctx.setLineWidth(len(3.5))
        ctx.addEllipse(in: circle(P(50, 50), len(40)))
        ctx.strokePath()
        ctx.setLineWidth(lw)
        ctx.addLines(between: [P(50, 90), P(26.5, 17.6), P(88, 62.4), P(12, 62.4), P(73.5, 17.6)])
        ctx.closePath(); ctx.strokePath()

    case .sapphire: // inverses Kreuz
        setColor(color, 1); ctx.setLineWidth(lw)
        ctx.move(to: P(50, 12)); ctx.addLine(to: P(50, 88))
        ctx.move(to: P(30, 68)); ctx.addLine(to: P(70, 68))
        ctx.strokePath()

    case .emerald:  // Tiwaz-Rune
        setColor(color, 1); ctx.setLineWidth(lw)
        ctx.move(to: P(50, 20)); ctx.addLine(to: P(50, 86))
        ctx.move(to: P(50, 14)); ctx.addLine(to: P(30, 36))
        ctx.move(to: P(50, 14)); ctx.addLine(to: P(70, 36))
        ctx.strokePath()

    case .topaz:    // Triquetra
        setColor(color, 1); ctx.setLineWidth(len(4))
        for c in [P(50, 33), P(31, 64), P(69, 64)] { ctx.addEllipse(in: circle(c, len(23))) }
        ctx.strokePath()

    case .diamond:  // Schädel
        setColor(color, 1)
        ctx.addEllipse(in: circle(P(50, 40), len(26))); ctx.fillPath()
        ctx.addLines(between: [P(34, 57), P(66, 57), P(62, 82), P(55, 77), P(50, 84), P(45, 77), P(38, 82)])
        ctx.closePath(); ctx.fillPath()
        setColor(cut, 1)
        ctx.addEllipse(in: circle(P(39, 42), len(7.5))); ctx.fillPath()
        ctx.addEllipse(in: circle(P(61, 42), len(7.5))); ctx.fillPath()
        ctx.addLines(between: [P(50, 50), P(45, 60), P(55, 60)]); ctx.closePath(); ctx.fillPath()

    case .amethyst: // Mondsichel
        setColor(color, 1)
        ctx.addEllipse(in: circle(P(50, 50), len(33))); ctx.fillPath()
        setColor(cut, 1)
        ctx.addEllipse(in: circle(P(63, 43), len(28))); ctx.fillPath()
    }
}

/// Stein MIT Sigil (für die Hero-Säule) — wie SigilStones.draw, auf beliebige Kachelgröße.
func drawSigilStone(_ gem: Gem, rect: CGRect) {
    let D = rect.width
    let inset = D * 0.05
    let body = rect.insetBy(dx: inset, dy: inset)
    let corner = body.width * 0.16
    let bodyPath = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 18,
                  color: NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.55).cgColor)
    setColor(tint(gem), 1); ctx.addPath(bodyPath); ctx.fillPath()
    ctx.restoreGState()

    ctx.addPath(bodyPath); setColor(bone, 0.22); ctx.setLineWidth(max(2, D * 0.018)); ctx.strokePath()

    let m = body.width * 0.16
    drawSigil(gem, area: body.insetBy(dx: m, dy: m), color: bone, cut: tint(gem))
}

/// Schlichter Block OHNE Sigil (für die Tetromino-Teile) — gerundetes Quadrat + dezenter Rahmen.
func drawPlainStone(_ gem: Gem, rect: CGRect, alpha: CGFloat) {
    let D = rect.width
    let inset = D * 0.06
    let body = rect.insetBy(dx: inset, dy: inset)
    let corner = body.width * 0.20
    let bodyPath = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 9,
                  color: NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.5 * alpha).cgColor)
    setColor(tint(gem), alpha); ctx.addPath(bodyPath); ctx.fillPath()
    ctx.restoreGState()

    ctx.addPath(bodyPath); setColor(bone, 0.22 * alpha); ctx.setLineWidth(max(1.5, D * 0.02)); ctx.strokePath()
}

// =====================================================================================
//  4) Oberes Band: sechs Tetromino-Formen (Offsets 1:1 aus Tetromino.swift), alle
//     mit ihrer Unterkante BÜNDIG auf einer gemeinsamen Baseline, gleichmäßig verteilt.
// =====================================================================================
typealias Cell = (c: Int, r: Int)
func tetWidth(_ offsets: [Cell], cell: CGFloat) -> CGFloat {
    let minc = offsets.map { $0.c }.min()!, maxc = offsets.map { $0.c }.max()!
    return CGFloat(maxc - minc + 1) * cell
}
func drawTetromino(_ offsets: [Cell], gem: Gem, baselineY: CGFloat, leftX: CGFloat, cell: CGFloat, alpha: CGFloat) {
    let minc = offsets.map { $0.c }.min()!
    let maxr = offsets.map { $0.r }.max()!         // unterste belegte Zeile sitzt auf der Baseline
    for cellPos in offsets {
        let x = leftX + CGFloat(cellPos.c - minc) * cell
        let y = baselineY + CGFloat(maxr - cellPos.r) * cell   // Zeile 0 = oben (höheres AppKit-y)
        drawPlainStone(gem, rect: CGRect(x: x, y: y, width: cell, height: cell), alpha: alpha)
    }
}

let pieces: [(off: [Cell], gem: Gem)] = [
    ([(0, 2), (1, 2), (2, 2), (3, 2)], .sapphire),   // I
    ([(0, 1), (1, 1), (2, 1), (1, 2)], .amethyst),   // T
    ([(0, 1), (1, 1), (2, 1), (2, 2)], .ruby),       // L
    ([(0, 1), (1, 1), (1, 2), (2, 2)], .emerald),    // S
    ([(0, 2), (1, 2), (1, 1), (2, 1)], .topaz),      // Z
    ([(0, 0), (1, 0), (0, 1), (1, 1)], .diamond),    // O
]
let bandCell: CGFloat = 34
let bandBaseline: CGFloat = 566
let widths = pieces.map { tetWidth($0.off, cell: bandCell) }
let totalPieceW = widths.reduce(0, +)
let bandGap = (W - totalPieceW) / CGFloat(pieces.count + 1)   // gleiche Lücken inkl. Außenränder
var bx = bandGap
for (i, p) in pieces.enumerated() {
    drawTetromino(p.off, gem: p.gem, baselineY: bandBaseline, leftX: bx, cell: bandCell, alpha: 0.92)
    bx += widths[i] + bandGap
}

// --- 5) Hero: fallende Säule aus DREI echten Sigil-Steinen (rechte Bildhälfte, unter dem Band) ---
let stoneSize: CGFloat = 150
let gap: CGFloat = 16
let colX: CGFloat = 1005
let totalH = stoneSize * 3 + gap * 2
let topY = 292 + totalH / 2                          // Säule etwas unterhalb der Bildmitte
let column: [Gem] = [.emerald, .sapphire, .ruby]     // oben→unten; Pentagramm (ruby) landet unten
for (i, gem) in column.enumerated() {
    let oy = topY - CGFloat(i + 1) * stoneSize - CGFloat(i) * gap
    drawSigilStone(gem, rect: CGRect(x: colX - stoneSize/2, y: oy, width: stoneSize, height: stoneSize))
}

// --- 6) Logo (von Hand getuscht, weiß-auf-transparent), linke Bildhälfte unter dem Band ---
if let logo = NSImage(contentsOfFile: "\(resDir)/logo.png"), logo.size.width > 0 {
    let box = NSSize(width: 560, height: 270)
    let scale = min(box.width / logo.size.width, box.height / logo.size.height)
    let lw = logo.size.width * scale
    let lh = logo.size.height * scale
    let cx: CGFloat = 372                             // Mitte der linken Hälfte
    let lx = cx - lw / 2
    let ly: CGFloat = 252                             // Oberkante bleibt unter dem Tetromino-Band
    logo.draw(in: NSRect(x: lx, y: ly, width: lw, height: lh),
              from: .zero, operation: .sourceOver, fraction: 1.0)
}

// --- 7) Grabspruch zweisprachig unter dem Logo (Grenze Gotisch) ---
func drawCentered(_ s: String, font: NSFont, color: RGB, alpha: CGFloat, centerX: CGFloat, baselineY: CGFloat) {
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: color.r, green: color.g, blue: color.b, alpha: alpha),
        .paragraphStyle: para,
    ]
    let size = (s as NSString).size(withAttributes: attrs)
    (s as NSString).draw(at: NSPoint(x: centerX - size.width/2, y: baselineY), withAttributes: attrs)
}
let titleFont = NSFont(name: "GrenzeGotisch-Regular", size: 38) ?? NSFont.systemFont(ofSize: 34)
let subFont   = NSFont(name: "GrenzeGotisch-Regular", size: 23) ?? NSFont.systemFont(ofSize: 20)
drawCentered("Am Ende fällt jeder Stein", font: titleFont, color: bone, alpha: 0.95, centerX: 372, baselineY: 198)
drawCentered("In the end, every stone falls", font: subFont, color: bone, alpha: 0.72, centerX: 372, baselineY: 158)

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
