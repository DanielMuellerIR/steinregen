// Pair.swift
// Datentypen des dritten Spielmodus „Blutklumpen" (Puyo-Stil): Es faellt ein PAAR aus zwei
// Steinen, das um seinen Dreh-Stein (Pivot) rotiert. Geraeumt werden Gruppen aus mindestens
// vier GLEICHFARBIGEN, seitlich/oben/unten verbundenen Steinen (Flood-Fill — Diagonalen
// verbinden NICHT). Bewusst markenfrei: „fallendes Steinpaar" ist der Gattungsbegriff des
// Genres. Alles wertbasiert (struct/enum) und plattformneutral.
//
// Koordinaten wie im ganzen Spiel: Ursprung unten links, `row` waechst nach oben.

// MARK: - Lage des Satelliten

/// Die vier moeglichen Lagen des zweiten Steins (Satellit) relativ zum Dreh-Stein (Pivot).
/// Drehen im Uhrzeigersinn laeuft zyklisch up → right → down → left → up.
public enum PairOrientation: UInt8, Sendable, CaseIterable {
    case up, right, down, left

    /// (Spalten-, Reihen-)Versatz des Satelliten gegenueber dem Pivot.
    public var offset: (col: Int, row: Int) {
        switch self {
        case .up:    return (0, 1)
        case .right: return (1, 0)
        case .down:  return (0, -1)
        case .left:  return (-1, 0)
        }
    }

    /// Die naechste Lage im Uhrzeigersinn.
    public var rotatedCW: PairOrientation {
        PairOrientation(rawValue: (rawValue + 1) % 4)!
    }
}

// MARK: - Aktives Paar

/// Das aktive, fallende Steinpaar. `col`/`row` ist die Position des PIVOTS (um ihn wird
/// gedreht); der Satellit haengt in `orientation`-Richtung daneben. Beim Einwurf steht der
/// Satellit OBEN (`.up`) — wie die Saeule schwebt das Paar von oben ein: anfangs steht nur
/// der Pivot in der obersten Brettreihe, der Satellit liegt noch ueber dem Brett (Reihe
/// >= board.height, dort als frei behandelt) und wird vom Renderer ausgeblendet.
public struct PairPiece: Sendable, Equatable {
    /// Farbe des Pivots (Index 0) und des Satelliten (Index 1).
    public var gems: [Gem]   // genau 2 Eintraege
    public var col: Int
    public var row: Int
    public var orientation: PairOrientation

    public init(gems: [Gem], col: Int, row: Int, orientation: PairOrientation = .up) {
        self.gems = gems
        self.col = col
        self.row = row
        self.orientation = orientation
    }

    /// Die Brett-Zelle des Pivots.
    public var pivotCell: Cell { Cell(col: col, row: row) }

    /// Die Brett-Zelle des Satelliten (Pivot + Lage-Versatz).
    public var satelliteCell: Cell {
        let o = orientation.offset
        return Cell(col: col + o.col, row: row + o.row)
    }

    /// Beide belegten Brett-Zellen mit ihrer Farbe: Index 0 = Pivot, Index 1 = Satellit.
    public var cells: [(cell: Cell, gem: Gem)] {
        [(pivotCell, gems[0]), (satelliteCell, gems[1])]
    }
}

// MARK: - Ergebnis-Typen

/// Ergebnis des Aufsetzens eines Paars. `boardBefore` ist das Brett direkt nach dem
/// Einschreiben BEIDER Steine an ihrer Aufsetz-Position — also VOR dem Nachrutschen:
/// eine quer liegende Haelfte kann darin noch ueber einem Loch schweben (die Render-Schicht
/// animiert das Herabfallen, siehe `postLockSettle` im PlayEngine-Protokoll). `steps` ist
/// die komplette Ketten-Kaskade wie im Saeulen-Modus (0..n Wellen).
public struct PairLock: Sendable, Equatable {
    public let landed: PairPiece
    public let boardBefore: Board
    public let steps: [ClearStep]
}

/// Ergebnis eines Schwerkraft-Ticks im „Blutklumpen"-Modus.
public enum PairTick: Sendable, Equatable {
    case moved
    case locked(PairLock)
}
