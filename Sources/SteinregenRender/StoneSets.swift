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

    /// Reihenfolge im Auswahl-Dialog. Neue Sets hier anhaengen.
    public static let all: [StoneSet] = [sigil, doom]

    /// Set zu einer id (faellt auf das Sigil-Set zurueck, falls unbekannt).
    public static func set(for id: String) -> StoneSet { all.first { $0.id == id } ?? sigil }

    /// Aktuell gewaehlte Set-id (persistiert). Default: Sigil-Set.
    public static var selectedID: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? sigil.id }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}
