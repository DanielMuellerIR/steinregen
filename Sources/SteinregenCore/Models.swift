// Models.swift
// Datentypen des Spiels: Steinfarben, Spielfeld, fallende Saeule und die Ergebnis-Typen
// der Aufloesung. Alles wertbasiert (struct) und plattformneutral — keine Grafik, keine Zeit.

// MARK: - Stein

/// Ein Spielstein. Die ersten sechs Faelle sind die normalen Spielfarben; `.magic` ist der
/// seltene Sonder-Stein (Magic Jewel), der nie dauerhaft im Brett liegt, sondern beim
/// Aufsetzen eine ganze Farbe vom Brett raeumt (siehe Engine.lock).
public enum Gem: UInt8, Sendable, CaseIterable, Hashable {
    case ruby       // rot
    case topaz      // gold/gelb
    case emerald    // gruen
    case diamond    // tuerkis/hell
    case sapphire   // blau
    case amethyst   // violett
    case magic      // Sonder-Stein (Magic Jewel)

    /// Die sechs normalen Spielfarben (ohne Magic Jewel) — Reihenfolge ist die Zieh-Reihenfolge.
    public static let colors: [Gem] = [.ruby, .topaz, .emerald, .diamond, .sapphire, .amethyst]

    public var isMagic: Bool { self == .magic }
}

// MARK: - Koordinate

/// Eine Zelle im Spielfeld. Ursprung unten links: `row` 0 ist die unterste Reihe,
/// `row` waechst nach oben; `col` 0 ist die linke Spalte.
public struct Cell: Hashable, Sendable {
    public let col: Int
    public let row: Int
    public init(col: Int, row: Int) {
        self.col = col
        self.row = row
    }
}

// MARK: - Spielfeld

/// Das Spielraster. Die Maße sind frei waehlbar (pro Partie/Modus): `width` Spalten × `height`
/// Reihen. Standard ist 6 × 13 wie im Columns-Original — der „Verschuettet"-Modus und frei
/// eingestellte Brettgroessen geben eigene Maße an. `nil` = leere Zelle. Magic-Steine landen NIE
/// hier — das Brett enthaelt ausschliesslich normale Farben.
public struct Board: Sendable, Equatable {
    /// Standard-Brettmaße (Columns-/„Saeulen"-Klassik). Dienen nur als Default fuer `init` —
    /// die echte Groesse eines Bretts steht in den Instanz-Eigenschaften `width`/`height`.
    public static let defaultWidth = 6
    public static let defaultHeight = 13

    /// Tatsaechliche Maße DIESES Bretts (nach `init` unveraenderlich).
    public let width: Int
    public let height: Int

    // Speicher zeilenweise: index = row * width + col.
    private var cells: [Gem?]

    public init(width: Int = Board.defaultWidth, height: Int = Board.defaultHeight) {
        self.width = width
        self.height = height
        cells = Array(repeating: nil, count: width * height)
    }

    /// Liegt (col, row) innerhalb DIESES Bretts? (Instanz-Methode — kennt die echten Maße.)
    public func inBounds(col: Int, row: Int) -> Bool {
        col >= 0 && col < width && row >= 0 && row < height
    }

    /// Zugriff auf eine Zelle. Get ist oeffentlich (Render liest das Brett); Set ist oeffentlich,
    /// betrifft aber nur die jeweilige Kopie — die Engine schuetzt ihr eigenes Brett via `private(set)`.
    public subscript(_ col: Int, _ row: Int) -> Gem? {
        get { cells[row * width + col] }
        set { cells[row * width + col] = newValue }
    }

    /// Alle Zellen einer bestimmten Farbe (fuer den Magic-Jewel-Effekt).
    public func cells(of gem: Gem) -> [Cell] {
        var result: [Cell] = []
        for row in 0..<height {
            for col in 0..<width where self[col, row] == gem {
                result.append(Cell(col: col, row: row))
            }
        }
        return result
    }

    /// Anzahl belegter Zellen (Debug/Test).
    public var filledCount: Int { cells.lazy.filter { $0 != nil }.count }
}

// MARK: - Fallende Saeule

/// Die aktive, fallende Dreier-Saeule. `gems[0]` ist unten, `gems[2]` oben.
/// `row` ist die Reihe des UNTERSTEN Steins; die Saeule belegt row, row+1, row+2 in `col`.
public struct Piece: Sendable, Equatable {
    public var gems: [Gem]   // genau 3 Eintraege
    public var col: Int
    public var row: Int

    public init(gems: [Gem], col: Int, row: Int) {
        self.gems = gems
        self.col = col
        self.row = row
    }

    /// Ist die ganze Saeule ein Magic Jewel?
    public var isMagic: Bool { gems.allSatisfy { $0.isMagic } }
}

// MARK: - Ergebnis-Typen der Aufloesung

/// Art einer Raeum-Welle: normaler Drilling-Treffer oder Magic-Jewel-Farbraeumung.
public enum ClearKind: Sendable, Equatable {
    case match
    case magic
}

/// Eine einzelne Raeum-Welle der Kaskade. Render spielt diese Schritte nacheinander animiert ab.
public struct ClearStep: Sendable, Equatable {
    public let cells: [Cell]        // in diesem Schritt verschwindende Zellen
    public let kind: ClearKind
    public let color: Gem?          // bei .magic: die getroffene Farbe; sonst nil
    public let chain: Int           // Kettenstufe (1 = erste Welle nach dem Aufsetzen)
    public let points: Int          // in diesem Schritt erzielte Punkte
    public let boardAfter: Board    // Brett-Zustand NACH Entfernen + Nachrutschen
}

/// Ergebnis des Aufsetzens einer Saeule: wo sie landete, ob es ein Magic Jewel war,
/// das Brett direkt nach dem Aufsetzen und die komplette Kaskade.
public struct LockResult: Sendable, Equatable {
    public let landed: Piece
    public let wasMagic: Bool
    public let boardBefore: Board   // bei Magic OHNE die Magic-Steine (die liegen nie im Brett)
    public let steps: [ClearStep]
}

/// Ergebnis eines Schwerkraft-Ticks der aktiven Saeule.
public enum TickOutcome: Sendable, Equatable {
    case moved                 // Saeule ist eine Reihe gefallen
    case locked(LockResult)    // Saeule kam zur Ruhe, Kaskade berechnet
}

/// Spielphase. Steuert, welche Eingaben erlaubt sind.
public enum Phase: Sendable, Equatable {
    case falling       // aktive Saeule faellt; Eingaben erlaubt
    case resolving     // Kaskade laeuft (Render animiert); keine Eingaben, kein Schwerkraft-Tick
    case gameOver
}
