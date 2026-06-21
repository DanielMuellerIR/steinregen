// SigilStones.swift
// Das ERSTE Steine-Set ("Sigille"): ein nahezu schwarzer, leicht getoenter Koerper mit einem
// fein gezeichneten, knochenweissen Sigil. Unterscheidung ueber die FORM des Sigils. Dieser Code
// war urspruenglich Teil von GemTextures; er ist jetzt ein eigenstaendiger Set-Renderer, damit
// weitere Sets daneben existieren koennen (siehe StoneSets).

import CoreGraphics
import SpriteKit
import SteinregenCore

@MainActor
enum SigilStones {

    /// Zeichnet einen Stein dieses Sets als CGImage. `magic` = heller Sonderfall (Magic Jewel).
    static func draw(_ gem: Gem, magic: Bool) -> CGImage {
        let size = 220
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let S = CGFloat(size)

        // Koerper: abgerundetes Quadrat. Normal = dunkle Toenung, Magic = knochenweiss.
        let inset: CGFloat = magic ? 9 : 11
        let body = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
        let corner = body.width * 0.16
        let bodyPath = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)
        let bodyColor = magic ? Theme.bone : Theme.tint(for: gem)
        set(ctx, bodyColor, 1); ctx.addPath(bodyPath); ctx.fillPath()

        // Rahmen: Magic = Ochsenblut (kraeftig), normal = knochenweiss (dezent).
        ctx.addPath(bodyPath)
        if magic { set(ctx, Theme.oxblood, 0.9); ctx.setLineWidth(5) }
        else      { set(ctx, Theme.bone, 0.22);  ctx.setLineWidth(3) }
        ctx.strokePath()

        // Sigil: normal knochenweiss auf dunkel, Magic dunkel auf knochenweiss.
        let sigilColor = magic ? Theme.ink : Theme.bone
        let m = body.width * 0.16
        let area = body.insetBy(dx: m, dy: m)
        drawSigil(ctx, gem: gem, area: area, color: sigilColor, cut: bodyColor)

        return ctx.makeImage()!
    }

    // MARK: - Sigille
    //
    // Alle Sigille sind in einem gedachten 100×100-Feld definiert (Ursprung OBEN links, y nach
    // unten). `P` bildet das auf den CoreGraphics-Bereich `area` ab, `len` skaliert eine Laenge.

    private static func drawSigil(_ ctx: CGContext, gem: Gem, area: CGRect, color: Theme.RGB, cut: Theme.RGB) {
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: area.minX + x / 100 * area.width, y: area.maxY - y / 100 * area.height)
        }
        func len(_ v: CGFloat) -> CGFloat { v / 100 * area.width }
        func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }

        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let lw = len(6)

        switch gem {
        case .ruby:
            set(ctx, color, 1)
            ctx.setLineWidth(len(3.5))
            ctx.addEllipse(in: circle(P(50, 50), len(40)))
            ctx.strokePath()
            ctx.setLineWidth(lw)
            ctx.addLines(between: [P(50, 90), P(26.5, 17.6), P(88, 62.4), P(12, 62.4), P(73.5, 17.6)])
            ctx.closePath(); ctx.strokePath()

        case .sapphire:
            set(ctx, color, 1); ctx.setLineWidth(lw)
            ctx.move(to: P(50, 12)); ctx.addLine(to: P(50, 88))
            ctx.move(to: P(30, 68)); ctx.addLine(to: P(70, 68))
            ctx.strokePath()

        case .emerald:
            set(ctx, color, 1); ctx.setLineWidth(lw)
            ctx.move(to: P(50, 20)); ctx.addLine(to: P(50, 86))
            ctx.move(to: P(50, 14)); ctx.addLine(to: P(30, 36))
            ctx.move(to: P(50, 14)); ctx.addLine(to: P(70, 36))
            ctx.strokePath()

        case .topaz:
            set(ctx, color, 1); ctx.setLineWidth(len(4))
            for c in [P(50, 33), P(31, 64), P(69, 64)] { ctx.addEllipse(in: circle(c, len(23))) }
            ctx.strokePath()

        case .diamond:
            set(ctx, color, 1)
            ctx.addEllipse(in: circle(P(50, 40), len(26))); ctx.fillPath()
            ctx.addLines(between: [P(34, 57), P(66, 57), P(62, 82), P(55, 77), P(50, 84), P(45, 77), P(38, 82)])
            ctx.closePath(); ctx.fillPath()
            set(ctx, cut, 1)
            ctx.addEllipse(in: circle(P(39, 42), len(7.5))); ctx.fillPath()
            ctx.addEllipse(in: circle(P(61, 42), len(7.5))); ctx.fillPath()
            ctx.addLines(between: [P(50, 50), P(45, 60), P(55, 60)]); ctx.closePath(); ctx.fillPath()

        case .amethyst:
            set(ctx, color, 1)
            ctx.addEllipse(in: circle(P(50, 50), len(33))); ctx.fillPath()
            set(ctx, cut, 1)
            ctx.addEllipse(in: circle(P(63, 43), len(28))); ctx.fillPath()

        case .magic:
            break
        }
    }

    /// Setzt Fuell-/Strichfarbe direkt aus den (r,g,b)-Werten.
    private static func set(_ ctx: CGContext, _ c: Theme.RGB, _ alpha: Double) {
        ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: alpha)
        ctx.setStrokeColor(red: c.r, green: c.g, blue: c.b, alpha: alpha)
    }
}
