// FreeDoomStones.swift
// Bild-basiertes Steine-Set „FreeDoom": jeder der sechs Steine ist ein originaler FreeDoom-Pixel-
// Sprite (BSD-3-Clause, siehe Resources/FREEDOOM-LICENSE.txt), BRUTAL ins Tile gequetscht — auf die
// sichtbaren Pixel zugeschnitten (keine „Luft"), füllend skaliert (cover) und mit OBEN-Anker, damit
// bei zu hohem Inhalt UNTEN angeschnitten wird (Köpfe/Gesichter oben bleiben erhalten). Nearest-
// Neighbor → gewollte harte Pixelkanten. Die sechs Steine unterscheiden sich über das Motiv selbst
// (Form + Eigenfarbe), nicht über eine Hintergrundfarbe; das Tile ist nur dunkel-neutral.
//
// Diese Quetsch-Logik entspricht 1:1 dem Auswahl-Werkzeug tools/freedoom-contact.swift, mit dem das
// Set kuratiert wurde. Neues Set = dieser Renderer + EIN Eintrag in StoneSets.all.

import CoreGraphics
import Foundation
import ImageIO
import SteinregenCore

@MainActor
enum FreeDoomStones {

    /// Welche fd_*.png je Stein geladen wird (Slot → Motiv).
    private static func filename(_ gem: Gem) -> String {
        switch gem {
        case .ruby:     return "fd_ruby"       // rotes Fleisch / Gibs (col5)
        case .topaz:    return "fd_topaz"      // Flamme (fcan)
        case .emerald:  return "fd_emerald"    // grüner Marine (play)
        case .sapphire: return "fd_sapphire"   // Cyberdemon (cybr)
        case .diamond:  return "fd_diamond"    // Spieler-Gesicht, god (stfgod)
        case .amethyst: return "fd_amethyst"   // Pain-Elemental-Fratze (pain)
        case .magic:    return "fd_ruby"       // ungenutzt (Magic zykelt durch alle sechs)
        }
    }

    /// Pro-Stein-Feinjustage der Quetschung (vom Nutzer beim Kuratieren festgelegt):
    /// zoom > 1 = stärker reinzoomen, ybias 0 = oben bündig (unten anschneiden) … 1 = oben anschneiden.
    private static func crop(_ gem: Gem) -> (zoom: CGFloat, ybias: CGFloat) {
        switch gem {
        case .diamond: return (1.05, 0.65)   // Gesicht: Haare oben wegschneiden
        case .ruby:    return (1.0,  0.4)    // Gibs: etwas tiefer ansetzen
        default:       return (1.0,  0.0)    // oben bündig (Kopf/Fratze oben behalten)
        }
    }

    /// Laedt eine PNG-Datei aus dem Render-Resource-Bundle (robuster Weg ohne Bundle.module).
    private static func loadPNG(_ name: String) -> CGImage? {
        guard let url = Theme.resourceBundle.url(forResource: name, withExtension: "png"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return img
    }

    /// Bounding-Box der nicht (fast) durchsichtigen Pixel — zum Wegschneiden der „Luft" ums Sprite.
    /// Rückgabe in CGImage-Koordinaten (Ursprung oben links), passend für CGImage.cropping(to:).
    private static func opaqueBounds(_ img: CGImage, alphaMin: UInt8 = 12) -> CGRect? {
        let w = img.width, h = img.height
        guard w > 0, h > 0 else { return nil }
        let bpr = w * 4
        var data = [UInt8](repeating: 0, count: bpr * h)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let c = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))   // bottom-up: data-Zeile 0 = unten
        var minX = w, minY = h, maxX = -1, maxY = -1
        for yy in 0..<h {
            for xx in 0..<w where data[yy * bpr + xx * 4 + 3] > alphaMin {
                if xx < minX { minX = xx }; if xx > maxX { maxX = xx }
                if yy < minY { minY = yy }; if yy > maxY { maxY = yy }
            }
        }
        if maxX < 0 { return nil }
        return CGRect(x: minX, y: h - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    static func draw(_ gem: Gem, magic: Bool) -> CGImage {
        let size = 256
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return DoomStones.draw(gem, magic: magic)   // Notbremse
        }
        let S = CGFloat(size)
        let inset: CGFloat = 8
        let body = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
        let corner = body.width * 0.13
        let bodyPath = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)

        ctx.saveGState()
        ctx.addPath(bodyPath); ctx.clip()

        // 1) Dunkles, neutrales Tile (nur die abgerundeten Ecken bleiben sichtbar — der Rest wird
        //    vom gequetschten Sprite verdeckt). Die Eigenfarbe des Motivs trägt die Unterscheidung.
        if let grad = CGGradient(colorsSpace: cs,
                                 colors: [CGColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1),
                                          CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)] as CFArray,
                                 locations: [0, 1]) {
            ctx.drawRadialGradient(grad, startCenter: CGPoint(x: body.midX, y: body.midY + body.height * 0.1),
                                   startRadius: 0, endCenter: CGPoint(x: body.midX, y: body.midY),
                                   endRadius: body.width * 0.7, options: [.drawsAfterEndLocation])
        }

        // 2) Sprite brutal quetschen: „Luft" wegschneiden → cover → Oben-Anker (+ Pro-Stein-Justage).
        if let sprite = loadPNG(filename(gem)) {
            let cropped = opaqueBounds(sprite).flatMap { sprite.cropping(to: $0) } ?? sprite
            let sw = CGFloat(cropped.width), sh = CGFloat(cropped.height)
            let (zoom, ybias) = crop(gem)
            let scale = max(body.width / sw, body.height / sh) * zoom
            let dw = sw * scale, dh = sh * scale
            let overflowV = max(0, dh - body.height)
            let topY = body.maxY + ybias * overflowV    // ybias 0 = oben bündig (unten anschneiden)
            let dr = CGRect(x: body.midX - dw / 2, y: topY - dh, width: dw, height: dh)
            ctx.interpolationQuality = .none             // harte Pixelkanten
            ctx.draw(cropped, in: dr)
        }
        ctx.restoreGState()

        // 3) Knochenfarbener Rahmen ums Tile (passt zum übrigen Look).
        ctx.addPath(bodyPath)
        ctx.setStrokeColor(CGColor(red: 0.85, green: 0.83, blue: 0.78, alpha: 0.55))
        ctx.setLineWidth(5)
        ctx.strokePath()

        return ctx.makeImage() ?? DoomStones.draw(gem, magic: magic)
    }
}
