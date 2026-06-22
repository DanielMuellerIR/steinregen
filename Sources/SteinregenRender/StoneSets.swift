// StoneSets.swift
// Registry der waehlbaren Steine-Sets. Ein Set buendelt eine id, einen Anzeigenamen und die
// Zeichen-Funktion (gem, magic) -> CGImage. Spiel, Einstellungsdialog und Vorschau lesen alle
// aus dieser Liste — ein NEUES Set hinzufuegen heisst also nur:
//   1) einen Renderer schreiben (Datei wie DoomStones.swift kopieren + anpassen) und
//   2) hier unten EINEN Eintrag in `all` ergaenzen.
// Die getroffene Auswahl wird in UserDefaults gemerkt (App-Schicht-Zustand, kein Core-Zustand).

import CoreGraphics
import Foundation
import SteinregenCore

/// Ein waehlbares Steine-Set.
@MainActor
public struct StoneSet: Identifiable {
    public let id: String
    public let name: String
    public let subtitle: String
    /// Zeichnet einen Stein dieses Sets. `magic` = heller Sonderfall (Magic Jewel).
    public let draw: @MainActor (Gem, Bool) -> CGImage
}

@MainActor
public enum StoneSets {
    /// UserDefaults-Schluessel der getroffenen Auswahl (geteilt mit `@AppStorage` in der App).
    public static let defaultsKey = "steinregen.stoneSet"

    public static let sigil = StoneSet(id: "sigil", name: "Sigille",
                                       subtitle: "Fein geritzte Zeichen auf Schwarz",
                                       draw: SigilStones.draw)
    public static let doom = StoneSet(id: "doom", name: "Doom",
                                      subtitle: "Räudig, blutig, kräftige Farben",
                                      draw: DoomStones.draw)

    // Drei „optisch angenehme" Sets, komplett aus dem Schwester-Projekt *Zaubersteine* uebernommen
    // (Namen wie dort). Die freundliche Alternative zur Black-Metal-Optik. Siehe ZaubersteineStones.
    public static let zaubersteine = StoneSet(id: "zaubersteine", name: "Zaubersteine",
                                              subtitle: "Glänzende Steine (eigenes SVG-Set)",
                                              draw: { gem, _ in ZaubersteineStones.draw(gem, style: .svg) })
    public static let g20 = StoneSet(id: "g20", name: "G20",
                                     subtitle: "Klare, kräftig gefärbte Tasten-Steine",
                                     draw: { gem, _ in ZaubersteineStones.draw(gem, style: .procedural) })
    public static let juwelen = StoneSet(id: "juwelen", name: "Juwelen",
                                         subtitle: "Detailreiche Foto-Kristalle",
                                         draw: { gem, _ in ZaubersteineStones.draw(gem, style: .png) })

    // Bild-basiertes Set aus originalen FreeDoom-Pickup-Sprites (BSD-3-Clause). Pixeliger Retro-Look:
    // Doom-Emblem auf farbig getoentem Tile. Siehe FreeDoomStones + Resources/FREEDOOM-LICENSE.txt.
    public static let freedoom = StoneSet(id: "freedoom", name: "FreeDoom",
                                          subtitle: "Gequetschte FreeDoom-Pixelkunst (Dämonen, Flamme, Marine)",
                                          draw: FreeDoomStones.draw)

    /// Reihenfolge im Auswahl-Dialog (Doom als Standard ganz oben). Neue Sets hier einsortieren.
    public static let all: [StoneSet] = [doom, sigil, zaubersteine, g20, juwelen, freedoom]

    /// Set zu einer id (faellt auf das Standard-Set zurueck, falls unbekannt).
    public static func set(for id: String) -> StoneSet { all.first { $0.id == id } ?? doom }

    /// Aktuell gewaehlte Set-id (persistiert). Default: Doom-Set.
    public static var selectedID: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? doom.id }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}
