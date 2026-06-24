// Tetromino.swift
// Datentypen des zweiten Spielmodus „Verschuettet": fallende Vierlinge (Tetrominoes), die volle
// Reihen raeumen. Bewusst KEIN Markenname im Spiel — „Tetromino" ist der geometrische Gattungs-
// begriff (vier zusammenhaengende Quadrate). Alles wertbasiert (struct/enum) und plattformneutral.
//
// Koordinaten wie im ganzen Spiel: Ursprung unten links, `row` waechst nach oben. Die Steine
// fallen nach unten (row wird kleiner). Anders als die Columns-Saeule belegt ein Tetromino mehrere
// Spalten und dreht sich in einer quadratischen „Box".

// MARK: - Form

/// Die sieben klassischen Vierling-Formen. Die zugeordnete `gem`-Sorte ist rein kosmetisch:
/// im „Verschuettet"-Modus zaehlen NUR volle Reihen, nicht Farb-Drillinge — die Steine tragen
/// also nur zur Optik bei (jedes Set zeichnet sie wie gewohnt).
public enum TetrominoType: UInt8, CaseIterable, Sendable {
    case i, o, t, l, j, s, z

    /// Kantenlaenge der quadratischen Rotations-Box: I dreht in 4×4, O in 2×2, der Rest in 3×3.
    /// In dieser Box wird gedreht — so bleiben die Formen beim Drehen sauber auf dem Raster.
    public var boxSize: Int {
        switch self {
        case .i: return 4
        case .o: return 2
        default: return 3
        }
    }

    /// Kosmetische Stein-Sorte. Sieben Formen auf sechs Sorten abgebildet (eine Sorte wird doppelt
    /// genutzt) — egal fuers Spiel, da Treffer reihen- und nicht farbbasiert sind.
    public var gem: Gem {
        Gem.colors[Int(rawValue) % Gem.colors.count]
    }

    /// Die vier belegten Zellen im Spawn-Zustand, als (Spalte, Reihe)-Offsets INNERHALB der Box
    /// (row nach oben). Aus diesem Zustand werden die Drehungen rechnerisch erzeugt (siehe
    /// `Tetromino.rotatedOffsets`), darum genuegt hier die Grund-Ausrichtung.
    public var spawnOffsets: [(col: Int, row: Int)] {
        switch self {
        case .i: return [(0, 2), (1, 2), (2, 2), (3, 2)]            // waagerechte Vierer-Linie
        case .o: return [(0, 0), (1, 0), (0, 1), (1, 1)]            // 2×2-Block (dreht sich nicht)
        case .t: return [(0, 1), (1, 1), (2, 1), (1, 2)]            // T, Spitze oben
        case .j: return [(0, 1), (1, 1), (2, 1), (0, 2)]            // J, Nase oben links
        case .l: return [(0, 1), (1, 1), (2, 1), (2, 2)]            // L, Nase oben rechts
        case .s: return [(0, 1), (1, 1), (1, 2), (2, 2)]            // S
        case .z: return [(0, 2), (1, 2), (1, 1), (2, 1)]            // Z (Spiegel von S)
        }
    }
}

// MARK: - Aktiver Vierling

/// Ein aktiver, fallender Vierling. `col`/`row` ist die untere-linke Ecke der Rotations-Box;
/// `offsets` sind die vier belegten Zellen RELATIV zu dieser Ecke (aktuelle Drehlage).
public struct Tetromino: Sendable, Equatable {
    public let type: TetrominoType
    public var col: Int
    public var row: Int
    /// Vier (Spalte, Reihe)-Offsets innerhalb der Box. `Cell` dient hier als reines Zahlenpaar
    /// (Offset), NICHT als Brett-Koordinate.
    public var offsets: [Cell]

    public init(type: TetrominoType, col: Int, row: Int) {
        self.type = type
        self.col = col
        self.row = row
        self.offsets = type.spawnOffsets.map { Cell(col: $0.col, row: $0.row) }
    }

    /// Die aktuell belegten BRETT-Zellen (Box-Ecke + Offset).
    public func boardCells() -> [Cell] {
        offsets.map { Cell(col: col + $0.col, row: row + $0.row) }
    }

    /// Die Offsets nach einer 90°-Drehung im Uhrzeigersinn innerhalb der Box.
    /// Formel der CW-Drehung in einer N×N-Box: (x, y) → (y, N−1−x). Mehrfaches Anwenden ergibt
    /// die weiteren Lagen; 4× ist wieder der Ausgangszustand. Veraendert den Vierling NICHT —
    /// die Engine prueft erst auf Kollision und uebernimmt dann (mit evtl. kleinem Versatz).
    public func rotatedOffsets() -> [Cell] {
        let n = type.boxSize
        return offsets.map { Cell(col: $0.row, row: n - 1 - $0.col) }
    }
}

// MARK: - Ergebnis-Typen

/// Ergebnis des Aufsetzens eines Vierlings im „Verschuettet"-Modus.
/// Anders als bei den Saeulen gibt es KEINE Ketten-Kaskade: volle Reihen verschwinden gemeinsam in
/// genau einem Schritt, darueberliegende Steine rutschen als Block nach (kein erneuter Treffer).
/// `steps` hat darum 0 oder 1 Eintrag — wir nutzen denselben `ClearStep`-Typ wie die Saeulen,
/// damit die Render-Schicht beide Modi gleich animieren kann.
public struct TetrominoLock: Sendable, Equatable {
    public let landed: Tetromino
    public let boardBefore: Board   // direkt nach dem Einrasten, VOR dem Reihen-Loeschen
    public let steps: [ClearStep]   // 0 (nichts voll) oder 1 (volle Reihen verschwinden zusammen)
}

/// Ergebnis eines Schwerkraft-Ticks im „Verschuettet"-Modus.
public enum TetrominoTick: Sendable, Equatable {
    case moved
    case locked(TetrominoLock)
}
