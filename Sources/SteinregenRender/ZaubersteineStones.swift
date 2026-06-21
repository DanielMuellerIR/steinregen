// ZaubersteineStones.swift
// Drei „optisch angenehme" Steine-Sets, komplett aus dem Schwester-Projekt *Zaubersteine*
// uebernommen (Daniels eigenes MIT-Projekt). Es sind die drei dortigen Render-Styles —
// in Zaubersteine heissen sie:
//   • „Zaubersteine" = .svg        (glaenzende, gerasterte SVG-Steine; eigene PNGs svg_<typ>.png)
//   • „G20"          = .procedural (prozedural gezeichnete, kraeftig gefaerbte Tasten-Steine)
//   • „Juwelen"      = .png        (detailreiche Foto-Kristalle, per Hue/Saettigung umgefaerbt)
//
// Diese Sets passen bewusst NICHT zur Black-Metal-Optik — sie sind die freundliche Alternative,
// wenn man genug Finsternis hatte. Unterschieden werden die Steine hier ueber kraeftige, klar
// getrennte FARBEN (kein Symbol). Der Magic Jewel zykelt durch die sechs Farben (klassisch).
//
// Mapping unserer sechs Gem-Slots auf die Zaubersteine-Typen (es gibt dort 11; wir nehmen die
// passenden sechs): ruby, topaz, emerald, sapphire, amethyst und — als brillantes Weiss fuer den
// „diamond"-Slot — turquoise.

import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import SteinregenCore

@MainActor
enum ZaubersteineStones {

    /// Die drei Darstellungsarten (= die drei Sets).
    enum Style { case svg, procedural, png }

    /// Steinregen-Gem → Zaubersteine-Typname (steuert Asset-Dateinamen + Farb-Transform).
    private static func ztype(_ gem: Gem) -> String {
        switch gem {
        case .ruby:     return "ruby"
        case .topaz:    return "topaz"
        case .emerald:  return "emerald"
        case .sapphire: return "sapphire"
        case .amethyst: return "amethyst"
        case .diamond:  return "turquoise"   // brillantes Weiss als sechste, klar getrennte Farbe
        case .magic:    return "ruby"        // tritt nicht direkt auf (Magic zykelt die Farben)
        }
    }

    /// Zeichnet einen Stein im gewaehlten Stil. `magic` wird ignoriert — der Magic Jewel zykelt
    /// in diesen Sets durch die sechs normalen Farben (siehe GemTextures.magicTextures).
    static func draw(_ gem: Gem, style: Style) -> CGImage {
        switch style {
        case .procedural: return drawGem(ztype(gem))
        case .svg:        return svgImage(ztype(gem))
        case .png:        return pngImage(ztype(gem))
        }
    }

    // MARK: - Bundle / PNG laden (nutzt den robusten Finder aus Theme)

    private static func loadPNG(_ name: String) -> CGImage? {
        guard let url = Theme.resourceBundle.url(forResource: name, withExtension: "png"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return img
    }

    // MARK: - „Zaubersteine" (.svg): vorgerasterte SVG-Steine

    private static func svgImage(_ ztype: String) -> CGImage {
        loadPNG("svg_\(ztype)") ?? drawGem(ztype)
    }

    // MARK: - „Juwelen" (.png): Foto-Kristalle, per CoreImage umgefaerbt

    /// (Quell-PNG, Hue°, Saettigung×, Helligkeit+, Kontrast×) je Typ — exakt wie in Zaubersteine.
    private static func pngTransform(_ ztype: String) -> (source: String, hue: CGFloat, sat: CGFloat, brightness: CGFloat, contrast: CGFloat) {
        switch ztype {
        case "ruby":      return ("ruby",      0, 1.15, -0.14, 1.05)
        case "topaz":     return ("topaz",     0, 1.05,  0.00, 1.05)
        case "emerald":   return ("emerald",   0, 1.45, -0.26, 1.05)
        case "sapphire":  return ("sapphire",  0, 1.35, -0.22, 1.05)
        case "amethyst":  return ("amethyst",  0, 1.05,  0.00, 1.00)
        case "turquoise": return ("diamond",   0, 0.00,  0.22, 1.05)   // entsaettigt → brillantes Weiss
        default:          return ("ruby",      0, 1.00,  0.00, 1.00)
        }
    }

    private static let ciContext = CIContext(options: nil)

    private static func pngImage(_ ztype: String) -> CGImage {
        let t = pngTransform(ztype)
        guard let base = loadPNG(t.source) else { return drawGem(ztype) }
        var ci = CIImage(cgImage: base)
        if t.hue != 0, let f = CIFilter(name: "CIHueAdjust") {
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(t.hue * .pi / 180.0, forKey: kCIInputAngleKey)
            ci = f.outputImage ?? ci
        }
        if let cc = CIFilter(name: "CIColorControls") {
            cc.setValue(ci, forKey: kCIInputImageKey)
            cc.setValue(t.sat, forKey: kCIInputSaturationKey)
            cc.setValue(t.brightness, forKey: kCIInputBrightnessKey)
            cc.setValue(t.contrast, forKey: kCIInputContrastKey)
            ci = cc.outputImage ?? ci
        }
        let extent = CIImage(cgImage: base).extent
        return ciContext.createCGImage(ci, from: extent) ?? base
    }

    // MARK: - „G20" (.procedural): gezeichneter Edelstein mit Facetten-Schliff

    /// Basisfarbe je Typ (RGB), kraeftig und klar getrennt — exakt wie in Zaubersteine.
    private static func baseColor(_ ztype: String) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch ztype {
        case "ruby":      return (0.70, 0.05, 0.10)   // dunkles Rot
        case "topaz":     return (0.98, 0.80, 0.06)   // Gelb
        case "emerald":   return (0.03, 0.40, 0.13)   // dunkles Gruen
        case "sapphire":  return (0.06, 0.14, 0.66)   // dunkles Blau
        case "amethyst":  return (0.66, 0.20, 0.92)   // Violett
        case "turquoise": return (0.96, 0.98, 1.00)   // brillantes Weiss
        default:          return (0.70, 0.05, 0.10)
        }
    }

    private static func mix(_ c: (CGFloat, CGFloat, CGFloat), _ f: CGFloat, alpha: CGFloat = 1.0) -> CGColor {
        CGColor(red: min(1, c.0 * f), green: min(1, c.1 * f), blue: min(1, c.2 * f), alpha: alpha)
    }

    /// Zeichnet einen Edelstein als abgerundetes Quadrat mit Facetten-Bevel, Verlauf, Tafel-Facette,
    /// Glanzlicht und Kontur. Geometrie ist fuer alle Typen gleich, nur die Farbe trennt sie.
    private static func drawGem(_ ztype: String) -> CGImage {
        let pixelSize = 220
        let scale: CGFloat = 2.0
        let total = Int(CGFloat(pixelSize) * scale)
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: total, height: total, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)

        let size = CGFloat(pixelSize)
        let m = size * 0.04
        let s = size - 2 * m
        let corner = s * 0.18
        let c = baseColor(ztype)

        let rect = CGRect(x: m, y: m, width: s, height: s)
        let outer = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

        ctx.saveGState()
        ctx.addPath(outer); ctx.clip()
        if let grad = CGGradient(colorsSpace: cs, colors: [mix(c, 1.25), mix(c, 1.0), mix(c, 0.6)] as CFArray,
                                 locations: [0.0, 0.5, 1.0]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: rect.midX, y: rect.maxY),
                                   end: CGPoint(x: rect.midX, y: rect.minY), options: [])
        }

        let t = s * 0.24
        let oTL = CGPoint(x: rect.minX, y: rect.maxY), oTR = CGPoint(x: rect.maxX, y: rect.maxY)
        let oBR = CGPoint(x: rect.maxX, y: rect.minY), oBL = CGPoint(x: rect.minX, y: rect.minY)
        let iTL = CGPoint(x: rect.minX + t, y: rect.maxY - t), iTR = CGPoint(x: rect.maxX - t, y: rect.maxY - t)
        let iBR = CGPoint(x: rect.maxX - t, y: rect.minY + t), iBL = CGPoint(x: rect.minX + t, y: rect.minY + t)

        func facet(_ pts: [CGPoint], _ factor: CGFloat) {
            let p = CGMutablePath(); p.addLines(between: pts); p.closeSubpath()
            ctx.addPath(p); ctx.setFillColor(mix(c, factor)); ctx.fillPath()
        }
        facet([oTL, oTR, iTR, iTL], 1.30)   // oben hell
        facet([oBL, oTL, iTL, iBL], 1.05)   // links mittel-hell
        facet([oTR, oBR, iBR, iTR], 0.78)   // rechts mittel-dunkel
        facet([oBR, oBL, iBL, iBR], 0.55)   // unten dunkel

        let innerRect = CGRect(x: iBL.x, y: iBL.y, width: iTR.x - iBL.x, height: iTR.y - iBL.y)
        let inner = CGPath(roundedRect: innerRect, cornerWidth: corner * 0.5, cornerHeight: corner * 0.5, transform: nil)
        ctx.addPath(inner); ctx.clip()
        if let grad2 = CGGradient(colorsSpace: cs, colors: [mix(c, 1.35), mix(c, 0.95)] as CFArray, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(grad2, start: CGPoint(x: innerRect.midX, y: innerRect.maxY),
                                   end: CGPoint(x: innerRect.midX, y: innerRect.minY), options: [])
        }

        let hl = CGPoint(x: rect.minX + s * 0.30, y: rect.maxY - s * 0.26)
        if let hlGrad = CGGradient(colorsSpace: cs,
                                   colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.7),
                                            CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)] as CFArray,
                                   locations: [0.0, 1.0]) {
            ctx.setBlendMode(.screen)
            ctx.drawRadialGradient(hlGrad, startCenter: hl, startRadius: 0, endCenter: hl, endRadius: s * 0.34, options: [])
            ctx.setBlendMode(.normal)
        }
        ctx.restoreGState()

        ctx.addPath(outer)
        ctx.setStrokeColor(mix(c, 0.35, alpha: 0.9))
        ctx.setLineWidth(2.5)
        ctx.strokePath()

        return ctx.makeImage()!
    }
}
