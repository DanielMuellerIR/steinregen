// DoomStones.swift
// Das ZWEITE Steine-Set ("Doom"): vollflaechig gefuellte, kraeftig gefaerbte, raeudige Steine —
// inspiriert von Black Metal, Horror und DOOM. Statt feiner Linien auf Schwarz gibt es satte
// Farbverlaeufe, Dreck (Russflecken + Kratzer + Vignette), Blut/Schliere und grob „handgezeichnete"
// (leicht verwackelte) Motive. Alles prozedural in CoreGraphics, eigenstaendig — eine Blaupause
// dafuer, wie weitere Sets aussehen koennen (Datei kopieren, Palette + Motive anpassen).
//
// Hinweis: Der kleine Zufall (Jitter/Dreck) lebt hier in der Render-Schicht; der Core bleibt rein.
// Die Texturen werden in GemTextures genau einmal erzeugt und gecacht — der Look ist danach stabil.

import CoreGraphics
import Foundation
import SpriteKit
import SteinregenCore

@MainActor
enum DoomStones {

    // MARK: Farbe

    /// Eine Farbe mit Alpha; `cg` liefert das CoreGraphics-Pendant.
    private struct C {
        let r, g, b, a: CGFloat
        init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
            self.r = r; self.g = g; self.b = b; self.a = a
        }
        var cg: CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
    }

    /// Palette je Stein: heller Kern → Grundton → dunkler Rand, plus die Motiv-Farbe.
    private struct Pal { let light, base, dark, motif: C }

    private static func palette(_ gem: Gem) -> Pal {
        switch gem {
        case .ruby:     return Pal(light: C(0.79, 0.16, 0.16), base: C(0.49, 0.05, 0.05), dark: C(0.13, 0.01, 0.01), motif: C(0.10, 0.01, 0.01))
        case .sapphire: return Pal(light: C(0.25, 0.52, 0.78), base: C(0.10, 0.24, 0.41), dark: C(0.02, 0.08, 0.18), motif: C(0.84, 0.88, 0.93))
        case .emerald:  return Pal(light: C(0.34, 0.71, 0.16), base: C(0.13, 0.43, 0.14), dark: C(0.02, 0.14, 0.05), motif: C(0.03, 0.10, 0.04))
        case .topaz:    return Pal(light: C(0.94, 0.66, 0.24), base: C(0.63, 0.35, 0.06), dark: C(0.18, 0.09, 0.02), motif: C(0.12, 0.06, 0.01))
        case .diamond:  return Pal(light: C(0.76, 0.74, 0.67), base: C(0.45, 0.43, 0.38), dark: C(0.11, 0.10, 0.09), motif: C(0.87, 0.85, 0.79))
        case .amethyst: return Pal(light: C(0.56, 0.32, 0.72), base: C(0.30, 0.13, 0.47), dark: C(0.08, 0.02, 0.16), motif: C(0.92, 0.85, 0.97))
        case .magic:    return magicPal
        }
    }
    /// Magic Jewel: fast schwarzer Koerper, weissgluehendes Motiv.
    private static let magicPal = Pal(light: C(0.12, 0.12, 0.14), base: C(0.04, 0.04, 0.05), dark: C(0, 0, 0), motif: C(0.99, 0.98, 0.95))

    // MARK: Zeichnen

    /// Kleiner Zufall 0…1 (Render-Schicht, kein Core-Zufall).
    private static func rnd() -> CGFloat { CGFloat(arc4random_uniform(1000)) / 1000 }

    static func draw(_ gem: Gem, magic: Bool) -> CGImage {
        let size = 220
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let S = CGFloat(size)

        let inset: CGFloat = 8
        let body = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
        let corner = body.width * 0.13
        let bodyPath = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)
        let pal = magic ? magicPal : palette(gem)

        ctx.saveGState()
        ctx.addPath(bodyPath); ctx.clip()

        // 1) Satter Radialverlauf als Koerper (heller Kern oben → dunkler Rand).
        let grad = CGGradient(colorsSpace: cs, colors: [pal.light.cg, pal.base.cg, pal.dark.cg] as CFArray,
                              locations: [0, 0.62, 1])!
        ctx.drawRadialGradient(grad,
                               startCenter: CGPoint(x: body.midX, y: body.maxY - body.height * 0.30), startRadius: 0,
                               endCenter: CGPoint(x: body.midX, y: body.midY), endRadius: body.width * 0.85,
                               options: [.drawsAfterEndLocation])

        // 2) Dreck: dunkle Russflecken + ein paar helle Sprenkel.
        drawGrime(ctx, in: body)

        // 3) Vignette: dunkle Raender.
        let vig = CGGradient(colorsSpace: cs,
                             colors: [CGColor(red: 0, green: 0, blue: 0, alpha: 0),
                                      CGColor(red: 0, green: 0, blue: 0, alpha: 0.55)] as CFArray,
                             locations: [0.55, 1])!
        ctx.drawRadialGradient(vig,
                               startCenter: CGPoint(x: body.midX, y: body.midY), startRadius: body.width * 0.30,
                               endCenter: CGPoint(x: body.midX, y: body.midY), endRadius: body.width * 0.72,
                               options: [.drawsAfterEndLocation])

        // 4) Blut (ruby) bzw. gruene Schliere (emerald) von oben.
        if gem == .ruby, !magic { drawDrips(ctx, in: body, color: C(0.61, 0.07, 0.07, 0.95)) }
        if gem == .emerald, !magic { drawDrips(ctx, in: body, color: C(0.40, 0.74, 0.16, 0.9)) }

        // 5) Motiv (fett, leicht verwackelt). Magic: weissgluehend mit Schein.
        let m = body.width * 0.16
        let area = body.insetBy(dx: m, dy: m)
        let motifColor = magic ? magicPal.motif : pal.motif
        drawMotif(gem, ctx, area: area, color: motifColor, cut: pal.base, glow: magic)

        // 6) Kratzer.
        drawScratches(ctx, in: body)

        ctx.restoreGState()

        // 7) Dunkle Kante.
        ctx.addPath(bodyPath)
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.65))
        ctx.setLineWidth(magic ? 5 : 3.5)
        ctx.strokePath()

        return ctx.makeImage()!
    }

    // MARK: Dreck / Blut / Kratzer

    private static func drawGrime(_ ctx: CGContext, in r: CGRect) {
        for _ in 0..<30 {                                   // dunkle Flecken
            let rad = 3 + rnd() * 14
            let x = r.minX + rnd() * r.width, y = r.minY + rnd() * r.height
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.05 + rnd() * 0.12))
            ctx.fillEllipse(in: CGRect(x: x - rad, y: y - rad, width: 2 * rad, height: 2 * rad))
        }
        for _ in 0..<16 {                                   // helle Sprenkel
            let rad = 1.5 + rnd() * 5
            let x = r.minX + rnd() * r.width, y = r.minY + rnd() * r.height
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.04 + rnd() * 0.07))
            ctx.fillEllipse(in: CGRect(x: x - rad, y: y - rad, width: 2 * rad, height: 2 * rad))
        }
    }

    private static func drawDrips(_ ctx: CGContext, in r: CGRect, color: C) {
        ctx.setFillColor(color.cg)
        let n = 3 + Int(rnd() * 3)
        for i in 0..<n {
            let x = r.minX + (CGFloat(i) + 0.5) / CGFloat(n) * r.width + (rnd() - 0.5) * 16
            let len = r.height * (0.12 + rnd() * 0.30)
            let w = 4 + rnd() * 5
            let top = r.maxY                                 // obere Kante (CG: groesstes y)
            ctx.fill(CGRect(x: x - w / 2, y: top - len, width: w, height: len))
            ctx.fillEllipse(in: CGRect(x: x - w / 2, y: top - len - w / 2, width: w, height: w))   // Tropfen-Bulbe
        }
    }

    private static func drawScratches(_ ctx: CGContext, in r: CGRect) {
        ctx.setLineCap(.round)
        for k in 0..<7 {
            let x1 = r.minX + rnd() * r.width, y1 = r.minY + rnd() * r.height
            let len = 12 + rnd() * 42, ang = rnd() * 6.283
            let x2 = x1 + cos(ang) * len, y2 = y1 + sin(ang) * len
            let mx = (x1 + x2) / 2 + (rnd() - 0.5) * 7, my = (y1 + y2) / 2 + (rnd() - 0.5) * 7
            if k < 5 { ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.18 + rnd() * 0.18)) }
            else      { ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.05 + rnd() * 0.05)) }
            ctx.setLineWidth(0.8 + rnd() * 1.6)
            ctx.move(to: CGPoint(x: x1, y: y1))
            ctx.addQuadCurve(to: CGPoint(x: x2, y: y2), control: CGPoint(x: mx, y: my))
            ctx.strokePath()
        }
    }

    // MARK: Motiv (dieselben sechs Formen wie im Sigil-Set, nur fett + verwackelt)

    private static func drawMotif(_ gem: Gem, _ ctx: CGContext, area: CGRect, color: C, cut: C, glow: Bool) {
        let jit = area.width * 0.018
        func B(_ x: CGFloat, _ y: CGFloat) -> CGPoint {                 // ohne Jitter (Mittelpunkte)
            CGPoint(x: area.minX + x / 100 * area.width, y: area.maxY - y / 100 * area.height)
        }
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {                 // mit Jitter (Eckpunkte)
            let p = B(x, y); return CGPoint(x: p.x + (rnd() - 0.5) * 2 * jit, y: p.y + (rnd() - 0.5) * 2 * jit)
        }
        func len(_ v: CGFloat) -> CGFloat { v / 100 * area.width }
        // Grob „handgezeichneter" Kreis als leicht verwackeltes Vieleck.
        func roughCircle(_ c: CGPoint, _ rad: CGFloat, seg: Int = 20) -> [CGPoint] {
            (0..<seg).map { i in
                let a = CGFloat(i) / CGFloat(seg) * 2 * .pi
                let rr = rad + (rnd() - 0.5) * 2 * (rad * 0.06)
                return CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
            }
        }
        func addPoly(_ pts: [CGPoint]) { ctx.addLines(between: pts); ctx.closePath() }

        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        if glow { ctx.setShadow(offset: .zero, blur: 16, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.9)) }
        let lw = len(8.5)

        switch gem {
        case .ruby:
            ctx.setStrokeColor(color.cg)
            ctx.setLineWidth(len(5))
            addPoly(roughCircle(B(50, 50), len(40))); ctx.strokePath()
            ctx.setLineWidth(lw)
            addPoly([P(50, 90), P(26.5, 17.6), P(88, 62.4), P(12, 62.4), P(73.5, 17.6)]); ctx.strokePath()

        case .sapphire:
            ctx.setStrokeColor(color.cg); ctx.setLineWidth(lw)
            ctx.move(to: P(50, 12)); ctx.addLine(to: P(50, 88))
            ctx.move(to: P(30, 68)); ctx.addLine(to: P(70, 68))
            ctx.strokePath()

        case .emerald:
            ctx.setStrokeColor(color.cg); ctx.setLineWidth(lw)
            ctx.move(to: P(50, 20)); ctx.addLine(to: P(50, 86))
            ctx.move(to: P(50, 14)); ctx.addLine(to: P(30, 36))
            ctx.move(to: P(50, 14)); ctx.addLine(to: P(70, 36))
            ctx.strokePath()

        case .topaz:
            ctx.setStrokeColor(color.cg); ctx.setLineWidth(len(7))
            for c in [B(50, 33), B(31, 64), B(69, 64)] { addPoly(roughCircle(c, len(21))) }
            ctx.strokePath()

        case .diamond:
            ctx.setFillColor(color.cg)
            addPoly(roughCircle(B(50, 40), len(25))); ctx.fillPath()                               // Hirnschale
            addPoly([P(32, 58), P(68, 58), P(63, 84), P(56, 78), P(50, 86), P(44, 78), P(37, 84)]); ctx.fillPath()  // Kiefer
            ctx.setFillColor(cut.cg)
            addPoly(roughCircle(B(40, 44), len(8))); ctx.fillPath()                                // Augen
            addPoly(roughCircle(B(60, 44), len(8))); ctx.fillPath()
            addPoly([P(50, 51), P(44, 63), P(56, 63)]); ctx.fillPath()                             // Nase

        case .amethyst:
            ctx.setFillColor(color.cg)
            addPoly(roughCircle(B(50, 50), len(32))); ctx.fillPath()
            ctx.setFillColor(cut.cg)
            addPoly(roughCircle(B(63, 43), len(27))); ctx.fillPath()

        case .magic:
            break
        }
    }
}
