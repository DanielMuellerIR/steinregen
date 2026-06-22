// icon-compose.swift
// Erzeugt das App-Icon-Master (1024×1024 PNG) fuer Steinregen — PROZEDURAL, im Black-Metal-Look:
// dunkle macOS-„Squircle", ein Ochsenblut-Höllenschein und darauf ein umgekehrtes Pentagramm
// (Spitze nach unten) im Kreis, knochenweiß. Passt zum neuen Spiel-Look (Sigil statt Edelstein).
// Plattformneutral (CoreGraphics + ImageIO), kein AppKit.
//
// Aufruf:  xcrun swift tools/icon-compose.swift <resourcesDir> <output.png>
// (Das Argument <resourcesDir> wird nicht mehr gebraucht — das Icon ist rein prozedural.)

import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: icon-compose.swift <resourcesDir> <output.png>\n".data(using: .utf8)!)
    exit(2)
}
let outPath = args[2]
// iOS-Modus (3. Argument "ios"): full-bleed + DECKEND (kein Alpha, keine eigene Rundung/Schatten —
// iOS rundet die Ecken selbst). Ohne das Argument: klassische macOS-Squircle mit transparentem Rand.
let iosMode = args.count >= 4 && args[3].lowercased() == "ios"

let S = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let bmInfo = iosMode ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: bmInfo) else {
    exit(1)
}
let size = CGFloat(S)

// Palette (synchron zum Spiel-Theme).
let bone = CGColor(red: 0.804, green: 0.780, blue: 0.729, alpha: 1)
let oxblood = CGColor(red: 0.48, green: 0.10, blue: 0.10, alpha: 1)

// MARK: - Squircle-Hintergrund (macOS-Big-Sur-Raster: 824er Rechteck, ~100 Rand)
// macOS: Squircle mit Rand (transparenter Hintergrund). iOS: full-bleed, ganzflaechig deckend.
let inset: CGFloat = iosMode ? 0 : 100
let bgRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let corner: CGFloat = iosMode ? 0 : (size - inset * 2) * 0.225
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil)

if !iosMode {
    // Schlagschatten unter dem Icon — nur bei der macOS-Squircle (full-bleed braucht keinen).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: CGColor(gray: 0, alpha: 0.55))
    ctx.addPath(bgPath)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
}

// Rabenschwarzer Vertikalverlauf + Ochsenblut-Höllenschein hinter dem Pentagramm.
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let grad = CGGradient(colorsSpace: cs,
                      colors: [CGColor(red: 0.075, green: 0.075, blue: 0.085, alpha: 1),
                               CGColor(red: 0.015, green: 0.015, blue: 0.020, alpha: 1)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

let glow = CGGradient(colorsSpace: cs,
                      colors: [CGColor(red: 0.48, green: 0.10, blue: 0.10, alpha: 0.55),
                               CGColor(red: 0.48, green: 0.10, blue: 0.10, alpha: 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow,
                       startCenter: CGPoint(x: size/2, y: size*0.52), startRadius: 0,
                       endCenter: CGPoint(x: size/2, y: size*0.52), endRadius: size*0.46, options: [])
ctx.restoreGState()

// MARK: - Umgekehrtes Pentagramm im Kreis (Spitze nach unten)
// Fuenf Eckpunkte auf einem Kreis; CG-Ursprung unten links (y nach oben), „unten" = kleinstes y.
let center = CGPoint(x: size/2, y: size/2)
let R: CGFloat = 300
func vertex(_ deg: CGFloat) -> CGPoint {
    let r = deg * .pi / 180
    return CGPoint(x: center.x + R * cos(r), y: center.y + R * sin(r))
}
// Winkel: eine Spitze gerade nach unten (270°), dann je +72°.
let v = [vertex(270), vertex(342), vertex(54), vertex(126), vertex(198)]
// Pentagramm = jeden zweiten Punkt verbinden: 0→2→4→1→3→0.
let starOrder = [v[0], v[2], v[4], v[1], v[3]]

func strokeStarAndCircle(color: CGColor, starWidth: CGFloat, circleWidth: CGFloat, circleR: CGFloat) {
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color)
    // Kreis.
    ctx.setLineWidth(circleWidth)
    ctx.addEllipse(in: CGRect(x: center.x - circleR, y: center.y - circleR, width: 2*circleR, height: 2*circleR))
    ctx.strokePath()
    // Stern.
    ctx.setLineWidth(starWidth)
    ctx.move(to: starOrder[0])
    for p in starOrder.dropFirst() { ctx.addLine(to: p) }
    ctx.closePath()
    ctx.strokePath()
}

// Erst breiter Ochsenblut-Schein (Halo), dann knochenweiss obendrauf.
strokeStarAndCircle(color: oxblood.copy(alpha: 0.7)!, starWidth: 58, circleWidth: 46, circleR: 362)
strokeStarAndCircle(color: bone, starWidth: 30, circleWidth: 22, circleR: 360)

// MARK: - PNG schreiben
guard let image = ctx.makeImage() else { exit(1) }
let outURL = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
if CGImageDestinationFinalize(dest) {
    print("Icon-Master geschrieben: \(outPath)")
} else {
    exit(1)
}
