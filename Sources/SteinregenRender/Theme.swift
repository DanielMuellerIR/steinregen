// Theme.swift
// Zentrale Stelle fuer den Black-Metal-Look: Farbpalette, Font-Namen und das einmalige
// Registrieren der mitgelieferten gotischen Schrift (Grenze Gotisch, SIL OFL).
//
// Sowohl die SpriteKit-Schicht (GameScene) als auch die SwiftUI-Shell (SteinregenApp)
// greifen hierauf zu, damit beide exakt dieselben Farben/Schriften verwenden. Die Farben
// liegen als reine (r,g,b)-Werte vor: SpriteKit nutzt `.sk`, SwiftUI baut daraus `Color`.
//
// Der Bundle-Finder stammt (wie schon bei den Steinen) aus Zaubersteine: er meidet
// `Bundle.module` (dessen generierter Zugriff loest auf fremden Rechnern/nach Notarisierung
// einen harten fatalError aus) und sucht das Ressourcen-Bundle robust an den ueblichen Orten.

import CoreText
import ImageIO
import SpriteKit
import SteinregenCore

@MainActor
public enum Theme {

    // MARK: - Farbe

    /// Eine Farbe als lineare (r,g,b)-Anteile 0…1. `.sk` liefert die SpriteKit-Variante;
    /// die App liest r/g/b direkt aus, um daraus ein SwiftUI-`Color` zu bauen.
    public struct RGB: Sendable {
        public let r, g, b: Double
        public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
        public var sk: SKColor { SKColor(red: r, green: g, blue: b, alpha: 1) }
        /// Dieselbe Farbe mit abweichender Deckkraft (fuer dezente Linien/Schleier).
        public func sk(_ alpha: Double) -> SKColor { SKColor(red: r, green: g, blue: b, alpha: alpha) }
    }

    // Grundtoene: rabenschwarz, knochenweiss, ein einziger Ochsenblut-Akzent.
    public static let canvas  = RGB(0.031, 0.031, 0.039)   // Hintergrund der ganzen Szene
    public static let panel   = RGB(0.043, 0.043, 0.051)   // Brett-Flaeche
    public static let ink     = RGB(0.039, 0.039, 0.047)   // dunkle Aussparungen in Sigillen
    public static let bone    = RGB(0.804, 0.780, 0.729)   // raeudiges Off-White: Text + Sigille
    public static let boneDim = RGB(0.420, 0.400, 0.360)   // gedaempftes Knochenweiss (Sekundaertext)
    public static let oxblood = RGB(0.480, 0.102, 0.102)   // Akzent: Rahmen/Striche/Tints
    public static let oxbloodDark = RGB(0.165, 0.075, 0.075) // dunkler Rahmen ums Brett
    public static let blood   = RGB(0.820, 0.200, 0.170)   // helleres Blutrot fuer LESBAREN roten Text auf Dunkel

    /// Gedeckte, entsaettigte Toenung je Stein — dunkel genug fuer den schwarzen Look, aber jetzt
    /// klar als Farbe erkennbar. Die Hauptunterscheidung bleibt das weisse Sigil (Form).
    public static func tint(for gem: Gem) -> RGB {
        switch gem {
        case .ruby:     return RGB(0.26, 0.10, 0.11)   // gedecktes Ochsenblut-Rot
        case .sapphire: return RGB(0.11, 0.15, 0.24)   // gedecktes Schiefer-Blau
        case .emerald:  return RGB(0.11, 0.20, 0.13)   // gedecktes Moos-Gruen
        case .topaz:    return RGB(0.24, 0.19, 0.09)   // gedecktes Ocker/Olivgold
        case .diamond:  return RGB(0.20, 0.21, 0.23)   // gedecktes Schiefer-Grau
        case .amethyst: return RGB(0.19, 0.12, 0.23)   // gedecktes Pflaumen-Violett
        case .magic:    return bone                     // Magic: heller Sonderfall
        }
    }

    // MARK: - Schrift

    /// Gotische UI-Schrift (Grenze Gotisch) — modernes, deutlich besser lesbares Blackletter als das
    /// fruehere Pirata One. `blackletterFamily` = Family-Name (SwiftUI `Font.custom`),
    /// `blackletterPostScript` = PostScript-Name des Regular-Schnitts (`SKLabelNode(fontNamed:)`),
    /// `blackletterBoldPostScript` = fetter Schnitt fuer Titel/Betonungen/Score.
    public static let blackletterFamily = "Grenze Gotisch"
    public static let blackletterPostScript = "GrenzeGotisch-Regular"
    public static let blackletterBoldPostScript = "GrenzeGotisch-Bold"

    // MARK: - Logo

    private static var triedLogo = false
    private static var logoCached: CGImage?

    /// Lädt das Start-Logo (`logo.png`, weiß auf transparent) aus dem Bundle — oder nil,
    /// falls nicht vorhanden (dann fällt der Startbildschirm auf den Schriftzug zurück).
    public static func logoImage() -> CGImage? {
        if triedLogo { return logoCached }
        triedLogo = true
        if let url = resourceBundle.url(forResource: "logo", withExtension: "png"),
           let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            logoCached = img
        }
        return logoCached
    }

    // MARK: - Hintergrundbilder

    private static var triedBackdrops = false
    private static var backdropsCached: [CGImage] = []

    /// Lädt ALLE Spielfeld-Hintergrundbilder (KI-generierte Nebel-bei-Nacht-Motive) aus dem
    /// Bundle: zuerst `hintergrund.png` (das ursprüngliche Friedhof-Motiv), danach
    /// `hintergrund-2.png`, `hintergrund-3.png`, … fortlaufend, bis keine weitere Datei mehr
    /// existiert. So genügt es, eine neue `hintergrund-N.png` ins Bundle zu legen — sie wird
    /// automatisch Teil des Pools (die Szene wählt pro Partie zufällig eines). Leeres Array ⇒
    /// es bleibt nur die schwarze Grundfläche. Das Ergebnis wird einmalig zwischengespeichert.
    public static func backdropImages() -> [CGImage] {
        if triedBackdrops { return backdropsCached }
        triedBackdrops = true
        // Kandidaten in fester Reihenfolge: erst der unnummerierte „hintergrund", dann -2, -3, …
        var names = ["hintergrund"]
        var n = 2
        while resourceBundle.url(forResource: "hintergrund-\(n)", withExtension: "png") != nil {
            names.append("hintergrund-\(n)")
            n += 1
            if n > 64 { break }   // Sicherheitsdeckel gegen eine versehentliche Endlosschleife
        }
        var imgs: [CGImage] = []
        for name in names {
            if let url = resourceBundle.url(forResource: name, withExtension: "png"),
               let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                imgs.append(img)
            }
        }
        backdropsCached = imgs
        return imgs
    }

    private static var fontsRegistered = false

    /// Registriert die mitgelieferte gotische Schrift (Regular + Bold) einmalig fuer diesen Prozess.
    /// Mehrfachaufruf ist gefahrlos (Flag). App-Shell UND Szene rufen das beim Start auf.
    public static func registerFonts() {
        guard !fontsRegistered else { return }
        fontsRegistered = true
        for postScript in [blackletterPostScript, blackletterBoldPostScript] {
            if let url = resourceBundle.url(forResource: postScript, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    // MARK: - Ressourcen-Bundle (robuster Finder, siehe Datei-Kopf)

    static let resourceBundle: Bundle = {
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
}

/// Hilfsklasse nur dazu da, das eigene Bundle ueber `Bundle(for:)` zu finden.
final class BundleToken {}
