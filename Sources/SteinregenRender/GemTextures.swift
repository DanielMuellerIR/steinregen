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
    private static var fogCache: SKTexture?

    // MARK: - Stein-Texturen (aktives Set)

    /// Textur eines normalen Steins. Fuer `.magic` das erste Magic-Frame.
    public static func texture(for gem: Gem) -> SKTexture { texture(for: gem, set: activeSetID) }

    public static func texture(for gem: Gem, set id: String) -> SKTexture {
        if gem.isMagic { return magicTextures(set: id).first ?? makeTexture(StoneSets.set(for: id).draw(.ruby, true)) }
        if let cached = cache[id]?[gem] { return cached }
        let t = makeTexture(StoneSets.set(for: id).draw(gem, false))
        cache[id, default: [:]][gem] = t
        return t
    }

    /// Die sechs Sigil-Frames des aktiven Sets im Magic-Stil — fuer die Magic-Jewel-Animation.
    public static var magicTextures: [SKTexture] { magicTextures(set: activeSetID) }

    public static func magicTextures(set id: String) -> [SKTexture] {
        if let m = magicCache[id] { return m }
        let m = Gem.colors.map { makeTexture(StoneSets.set(for: id).draw($0, true)) }
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

    private static func makeTexture(_ image: CGImage) -> SKTexture {
        let t = SKTexture(cgImage: image)
        t.filteringMode = .linear
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

    /// Weiche, kalt-graue Nebelschwaden als gekacheltes Wolken-Rauschen (Value Noise). Die Szene
    /// legt zwei dieser Texturen uebereinander und laesst sie langsam driften/pulsieren — das ergibt
    /// den ziehenden Nebel. Zum Rand hin blendet die Textur auf 0 aus, damit beim Driften keine
    /// harten Kanten auftauchen. Einmal erzeugt und gecacht.
    public static func fog() -> SKTexture {
        if let f = fogCache { return f }
        let w = 256, h = 160
        let fr = 0.58, fg = 0.61, fb = 0.67                     // kalt-grauer Nebel

        func lattice(_ cols: Int, _ rows: Int) -> [Double] {
            (0..<(cols * rows)).map { _ in Double(arc4random_uniform(1000)) / 1000.0 }
        }
        func sample(_ grid: [Double], _ cols: Int, _ rows: Int, _ u: Double, _ v: Double) -> Double {
            let x = u * Double(cols - 1), y = v * Double(rows - 1)
            let x0 = Int(x), y0 = Int(y)
            let x1 = min(x0 + 1, cols - 1), y1 = min(y0 + 1, rows - 1)
            let fx = x - Double(x0), fy = y - Double(y0)
            let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
            let top = grid[y0 * cols + x0] + (grid[y0 * cols + x1] - grid[y0 * cols + x0]) * sx
            let bot = grid[y1 * cols + x0] + (grid[y1 * cols + x1] - grid[y1 * cols + x0]) * sx
            return top + (bot - top) * sy
        }
        let g1 = lattice(7, 5), g2 = lattice(15, 9), g3 = lattice(29, 17)

        var data = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let u = Double(x) / Double(w - 1), v = Double(y) / Double(h - 1)
                var n = sample(g1, 7, 5, u, v) * 0.6 + sample(g2, 15, 9, u, v) * 0.3 + sample(g3, 29, 17, u, v) * 0.1
                n = max(0, min(1, (n - 0.42) * 1.9))           // Kontrast: dichtere Stellen = Schwaden
                let edge = min(min(u, 1 - u), min(v, 1 - v)) / 0.12
                let win = max(0, min(1, edge))                 // Randabblendung (keine Kante beim Driften)
                let a = n * win * 0.85
                let i = (y * w + x) * 4
                data[i + 0] = UInt8(fr * 255 * a)
                data[i + 1] = UInt8(fg * 255 * a)
                data[i + 2] = UInt8(fb * 255 * a)
                data[i + 3] = UInt8(a * 255)
            }
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data(data) as CFData)!
        let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                          space: cs, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                          provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        let t = SKTexture(cgImage: img)
        t.filteringMode = .linear
        fogCache = t
        return t
    }
}
