// Square.swift
// Datentypen des sechsten Spielmodus „Schnitter" (Lumines-Stil): Es faellt ein 2×2-BLOCK aus
// zwei Stein-Sorten. Gleichfarbige 2×2-Quadrate im Brett werden MARKIERT und von der wandernden
// SENSE (Sweep-Linie) geerntet — das Raeumen passiert also nicht beim Aufsetzen, sondern wenn
// die Sense die markierte Sektion ueberstrichen hat. Bewusst markenfrei: „fallende 2×2-Bloecke
// + Sweep-Linie" ist der Gattungsbegriff des Genres. Alles wertbasiert und plattformneutral.
//
// Koordinaten wie im ganzen Spiel: Ursprung unten links, `row` waechst nach oben.

// MARK: - Aktiver Block

/// Der aktive, fallende 2×2-Block. `col`/`row` ist seine UNTERE LINKE Ecke; er belegt die
/// Spalten col/col+1 und die Reihen row/row+1. `gems` haelt die vier Farben in fester
/// Positions-Reihenfolge: Index 0 = unten links, 1 = unten rechts, 2 = oben rechts,
/// 3 = oben links (gegen den Uhrzeigersinn — so ist die Dreh-Formel ein simples Rotieren
/// des Arrays). Beim Einwurf liegt die untere Reihe in der obersten Brettreihe, die obere
/// schwebt noch UEBER dem Brett ein (wie Saeule/Paar/Kapsel).
public struct SquarePiece: Sendable, Equatable {
    public var gems: [Gem]   // genau 4 Eintraege: [unten-links, unten-rechts, oben-rechts, oben-links]
    public var col: Int
    public var row: Int

    public init(gems: [Gem], col: Int, row: Int) {
        self.gems = gems
        self.col = col
        self.row = row
    }

    /// Die vier belegten Brett-Zellen mit ihrer Farbe (Reihenfolge wie `gems`).
    public var cells: [(cell: Cell, gem: Gem)] {
        [(Cell(col: col,     row: row),     gems[0]),
         (Cell(col: col + 1, row: row),     gems[1]),
         (Cell(col: col + 1, row: row + 1), gems[2]),
         (Cell(col: col,     row: row + 1), gems[3])]
    }

    /// Dreht die FARBEN 90° im Uhrzeigersinn (der Block selbst bleibt ein 2×2 — nur die Steine
    /// wandern: oben-links → oben-rechts → unten-rechts → unten-links → oben-links). In der
    /// [bl, br, tr, tl]-Reihenfolge ist das genau ein Links-Rotieren des Arrays.
    public mutating func rotateCW() {
        gems = [gems[1], gems[2], gems[3], gems[0]]
    }
}

// MARK: - Ergebnis-Typen

/// Ergebnis des Aufsetzens eines Blocks. `boardBefore` ist das Brett direkt nach dem
/// Einschreiben aller vier Steine — also VOR dem Nachrutschen (die beiden Spalten des Blocks
/// zerfallen unabhaengig; die Render-Schicht animiert das via `postLockSettle`). Raeum-Wellen
/// gibt es beim Aufsetzen NIE — das Ernten uebernimmt die Sense (`sweepTick`).
public struct SquareLock: Sendable, Equatable {
    public let landed: SquarePiece
    public let boardBefore: Board
}

/// Ergebnis eines Schwerkraft-Ticks im „Schnitter"-Modus.
public enum SquareTick: Sendable, Equatable {
    case moved
    case locked(SquareLock)
}
