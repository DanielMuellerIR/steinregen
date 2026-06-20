// icon-compose.swift
// Erzeugt das App-Icon-Master (1024×1024 PNG) fuer Steinregen aus den echten Stein-PNGs:
// dunkle macOS-„Squircle" + eine fallende Dreier-Saeule (Rubin/Smaragd/Saphir) mit
// dezenten Fall-Streifen. Plattformneutral (CoreGraphics + ImageIO), kein AppKit.
//
// Aufruf:  xcrun swift tools/icon-compose.swift <resourcesDir> <output.png>

import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: icon-compose.swift <resourcesDir> <output.png>\n".data(using: .utf8)!)
    exit(2)
}
let resDir = args[1]
let outPath = args[2]

let S = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}
let size = CGFloat(S)

func loadGem(_ name: String) -> CGImage? {
    let url = URL(fileURLWithPath: resDir).appendingPathComponent("\(name).png")
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return img
}

// MARK: - Squircle-Hintergrund (macOS-Big-Sur-Raster: 824er Rechteck, ~100 Rand)
let inset: CGFloat = 100
let bgRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let corner: CGFloat = (size - inset * 2) * 0.225
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil)

// Schlagschatten unter dem Icon.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: CGColor(gray: 0, alpha: 0.55))
ctx.addPath(bgPath)
ctx.setFillColor(CGColor(gray: 0, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// Dunkler Vertikalverlauf im Squircle.
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let grad = CGGradient(colorsSpace: cs,
                      colors: [CGColor(red: 0.13, green: 0.14, blue: 0.24, alpha: 1),
                               CGColor(red: 0.05, green: 0.05, blue: 0.10, alpha: 1)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

// Sanfter oberer Glanz.
let glow = CGGradient(colorsSpace: cs,
                      colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.10),
                               CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow,
                       startCenter: CGPoint(x: size/2, y: size*0.82), startRadius: 0,
                       endCenter: CGPoint(x: size/2, y: size*0.82), endRadius: size*0.55, options: [])
ctx.restoreGState()

// MARK: - Fallende Dreier-Saeule
// Reihenfolge oben→unten. (CG-Ursprung unten links → groesste y zuerst zeichnen = oben.)
let gemsTopToBottom = ["ruby", "emerald", "sapphire"]
let gemW: CGFloat = 250
let gap: CGFloat = 10
let totalH = gemW * 3 + gap * 2
let firstTopY = size/2 + totalH/2           // obere Kante des obersten Steins
let cx = size/2

for (i, name) in gemsTopToBottom.enumerated() {
    let topY = firstTopY - CGFloat(i) * (gemW + gap)
    let rect = CGRect(x: cx - gemW/2, y: topY - gemW, width: gemW, height: gemW)

    // Dezenter Fall-Streifen oberhalb des Steins.
    ctx.saveGState()
    let streakW: CGFloat = gemW * 0.30
    let streakRect = CGRect(x: cx - streakW/2, y: rect.maxY, width: streakW, height: 150)
    ctx.clip(to: streakRect)
    let streak = CGGradient(colorsSpace: cs,
                            colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0),
                                     CGColor(red: 0.8, green: 0.85, blue: 1, alpha: 0.16)] as CFArray,
                            locations: [0, 1])!
    ctx.drawLinearGradient(streak, start: CGPoint(x: 0, y: streakRect.maxY),
                           end: CGPoint(x: 0, y: streakRect.minY), options: [])
    ctx.restoreGState()

    // Stein mit weichem Schatten.
    if let gem = loadGem(name) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: CGColor(gray: 0, alpha: 0.45))
        ctx.draw(gem, in: rect)
        ctx.restoreGState()
    }
}

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
