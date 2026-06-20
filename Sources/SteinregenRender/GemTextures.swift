// GemTextures.swift
// Laedt die sechs Stein-PNGs als SpriteKit-Texturen. Bewusst OHNE Farb-Transform — jede
// gewaehlte Datei hat bereits die richtige Farbe (Rainbow + Tuerkis).
//
// Der Bundle-Finder kommt aus Zaubersteine: er meidet `Bundle.module` (dessen generierter
// Zugriff loest auf fremden Rechnern/nach Notarisierung einen harten fatalError aus) und sucht
// das Ressourcen-Bundle robust an den ueblichen Orten ab.

import CoreGraphics
import ImageIO
import SpriteKit
import SteinregenCore

@MainActor
public enum GemTextures {
    private static var cache: [Gem: SKTexture] = [:]

    /// Textur fuer einen normalen Stein (Magic wird separat ueber `colorTextures` animiert).
    public static func texture(for gem: Gem) -> SKTexture {
        if let cached = cache[gem] { return cached }
        let texture: SKTexture
        if let image = loadPNG(named: filename(for: gem)) {
            texture = SKTexture(cgImage: image)
        } else {
            texture = SKTexture(cgImage: fallbackImage(for: gem))
        }
        texture.filteringMode = .linear
        cache[gem] = texture
        return texture
    }

    /// Die sechs Farb-Texturen in fester Reihenfolge — fuer die pulsierende Magic-Jewel-Animation.
    public static var colorTextures: [SKTexture] { Gem.colors.map { texture(for: $0) } }

    private static func filename(for gem: Gem) -> String {
        switch gem {
        case .ruby:     return "ruby"
        case .topaz:    return "topaz"
        case .emerald:  return "emerald"
        case .diamond:  return "diamond"
        case .sapphire: return "sapphire"
        case .amethyst: return "amethyst"
        case .magic:    return "ruby"   // nie direkt genutzt
        }
    }

    // MARK: - Bundle + PNG laden

    private static let resourceBundle: Bundle = {
        let name = "Steinregen_SteinregenRender.bundle"
        let selfBundle = Bundle(for: BundleToken.self)
        var bases: [URL] = []
        if let u = Bundle.main.resourceURL { bases.append(u) }
        bases.append(Bundle.main.bundleURL)
        if let u = selfBundle.resourceURL { bases.append(u) }
        bases.append(selfBundle.bundleURL)
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() { bases.append(exe) }
        for base in bases {
            if let b = Bundle(url: base.appendingPathComponent(name)) { return b }
        }
        return selfBundle
    }()

    private static func loadPNG(named filename: String) -> CGImage? {
        guard let url = resourceBundle.url(forResource: filename, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image
    }

    // MARK: - Prozeduraler Ersatz (falls ein PNG fehlt — App bleibt lauffaehig)

    /// Repraesentative Farbe je Stein, fuer den Notfall-Ersatzstein.
    private static func color(for gem: Gem) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch gem {
        case .ruby:     return (0.85, 0.13, 0.21)
        case .topaz:    return (0.95, 0.75, 0.15)
        case .emerald:  return (0.13, 0.72, 0.36)
        case .diamond:  return (0.55, 0.86, 0.86)
        case .sapphire: return (0.16, 0.36, 0.85)
        case .amethyst: return (0.62, 0.30, 0.80)
        case .magic:    return (0.90, 0.90, 0.95)
        }
    }

    private static func fallbackImage(for gem: Gem) -> CGImage {
        let size = 220
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let c = color(for: gem)
        let rect = CGRect(x: 14, y: 14, width: size - 28, height: size - 28)
        let path = CGPath(roundedRect: rect, cornerWidth: 28, cornerHeight: 28, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        ctx.fillPath()
        // dezenter Glanz oben links
        ctx.addPath(path); ctx.clip()
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.22)
        ctx.fill(CGRect(x: 14, y: CGFloat(size) * 0.55, width: CGFloat(size) - 28, height: CGFloat(size) * 0.31))
        return ctx.makeImage()!
    }
}

/// Hilfsklasse nur dazu da, das eigene Bundle ueber `Bundle(for:)` zu finden.
private final class BundleToken {}
