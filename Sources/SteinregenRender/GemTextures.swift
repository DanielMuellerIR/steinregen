// GemTextures.swift
// Set-bewusste Textur-Fabrik. Die eigentlichen Steine zeichnen die Set-Renderer (SigilStones,
// DoomStones, …); hier werden ihre CGImages in SKTexturen verpackt und — getrennt je Set —
// gecacht. `activeSetID` bestimmt, welches Set das Spiel gerade zeichnet (wird beim Spielstart
// aus den Einstellungen gesetzt).

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
}
