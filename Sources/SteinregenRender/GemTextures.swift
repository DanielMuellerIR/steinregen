// GemTextures.swift
// Set-bewusste Textur-Fabrik. Die eigentlichen Steine zeichnen die Set-Renderer (SigilStones,
// DoomStones, …); hier werden ihre CGImages in SKTexturen verpackt und — getrennt je Set —
// gecacht. `activeSetID` bestimmt, welches Set das Spiel gerade zeichnet (wird beim Spielstart
// aus den Einstellungen gesetzt). Korn und Nebel sind set-unabhaengig und liegen ebenfalls hier.

import CoreGraphics
import Foundation
import SpriteKit
import SteinregenCore

@MainActor
public enum GemTextures {
    /// Aktuell aktives Steine-Set (Spielstart setzt das aus `StoneSets.selectedID`).
    public static var activeSetID: String = StoneSets.selectedID

    private static var cache: [String: [Gem: SKTexture]] = [:]      // [setID: [gem: texture]]
    private static var magicCache: [String: [SKTexture]] = [:]      // [setID: sigil-frames]
    private static var previewCache: [String: CGImage] = [:]        // ["setID|gemRaw": image]
    private static var grainCache: SKTexture?

    // MARK: - Stein-Texturen (aktives Set)

    /// Textur eines normalen Steins. Fuer `.magic` das erste Magic-Frame.
    public static func texture(for gem: Gem) -> SKTexture { texture(for: gem, set: activeSetID) }

    public static func texture(for gem: Gem, set id: String) -> SKTexture {
        if gem.isMagic { return magicTextures(set: id).first ?? makeTexture(StoneSets.set(for: id).draw(.ruby, true), smooth: smooth(id)) }
        if let cached = cache[id]?[gem] { return cached }
        let t = makeTexture(StoneSets.set(for: id).draw(gem, false), smooth: smooth(id))
        cache[id, default: [:]][gem] = t
        return t
    }

    /// Ist das Set „glatt" (gemalte/foto-artige Steine) und profitiert von Mipmaps beim Verkleinern?
    /// Das pixelige FreeDoom-Set bleibt bewusst ohne Mipmaps (Retro-Pixelkanten sollen erhalten bleiben).
    private static func smooth(_ id: String) -> Bool { id != "freedoom" }

    /// Die sechs Sigil-Frames des aktiven Sets im Magic-Stil — fuer die Magic-Jewel-Animation.
    public static var magicTextures: [SKTexture] { magicTextures(set: activeSetID) }

    public static func magicTextures(set id: String) -> [SKTexture] {
        if let m = magicCache[id] { return m }
        let m = Gem.colors.map { makeTexture(StoneSets.set(for: id).draw($0, true), smooth: smooth(id)) }
        magicCache[id] = m
        return m
    }

    /// Einzelbild eines Steins als CGImage — fuer die Set-Vorschau im Einstellungsdialog.
    /// Gecacht, damit die (teils zufaellig „handgezeichnete") Grafik in der Vorschau nicht flackert.
    public static func previewImage(_ gem: Gem, set id: String) -> CGImage {
        let key = "\(id)|\(gem.rawValue)"
        if let img = previewCache[key] { return img }
        let img = StoneSets.set(for: id).draw(gem, false)
        previewCache[key] = img
        return img
    }

    /// Verpackt ein CGImage als SKTexture. `smooth` aktiviert Mipmaps fuer die gemalten/foto-artigen
    /// Sets — so wird das Verkleinern auf kleine Kacheln (grosse Bretter, z.B. Verschuettet 10×18 oder
    /// frei eingestellte Maße) sauber statt flimmernd. Das pixelige FreeDoom-Set bekommt keine Mipmaps
    /// (`smooth: false`), damit seine harten Retro-Kanten erhalten bleiben.
    private static func makeTexture(_ image: CGImage, smooth: Bool = true) -> SKTexture {
        let t = SKTexture(cgImage: image)
        t.filteringMode = .linear
        if smooth { t.usesMipmaps = true }
        return t
    }

    // MARK: - Korn (raeudige Textur)

    /// Feines, statisches Korn fuer den Lo-Fi-Look. Knochenweisse Sprenkel mit niedriger Deckkraft;
    /// einmal erzeugt und gecacht. Der Zufall lebt hier in der Render-Schicht — der Core bleibt rein.
    public static func grain() -> SKTexture {
        if let g = grainCache { return g }
        let n = 256
        var data = [UInt8](repeating: 0, count: n * n * 4)
        let r = Theme.bone.r, g = Theme.bone.g, b = Theme.bone.b
        for i in 0..<(n * n) {
            let a = Int(arc4random_uniform(46))                 // 0…45 (max ~0.18 Deckkraft)
            let af = Double(a) / 255.0
            data[i * 4 + 0] = UInt8(r * 255 * af)               // vormultipliziert (premultipliedLast)
            data[i * 4 + 1] = UInt8(g * 255 * af)
            data[i * 4 + 2] = UInt8(b * 255 * af)
            data[i * 4 + 3] = UInt8(a)
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data(data) as CFData)!
        let img = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                          space: cs, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let t = SKTexture(cgImage: img)
        t.filteringMode = .nearest
        grainCache = t
        return t
    }

    // MARK: - Nebel (animierter Hintergrund)
}
