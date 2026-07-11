// SquareEngine.swift
// Deterministische Spiel-Engine des sechsten Modus „Schnitter" (Lumines-Stil): fallende
// 2×2-Bloecke aus ZWEI Sorten; gleichfarbige 2×2-Quadrate werden markiert und von der
// wandernden SENSE (Sweep-Linie) geerntet.
//
// Determinismus-Regel (CLAUDE.md): KEIN globaler Zufall, KEINE Wanduhr. Die Farbfolge der
// Bloecke laeuft ueber den injizierten, seed-bestimmten `Xoshiro256StarStar`. Die Sense ist
// TICK-basiert: `sweepTick()` bewegt sie um genau eine Spalte — der TAKT (Echtzeit) lebt
// ausschliesslich in der Render-Schicht. Gleicher Seed + gleiche Eingaben + gleiche
// Tick-Reihenfolge ⇒ exakt gleicher Verlauf.
//
// Die anderen Engines bleiben voellig unberuehrt — dieser Modus ist eine eigene, parallele
// Engine, die nur die gemeinsamen Bausteine (`Board`, `Gem`, `Phase`, `ClearStep`, PRNG,
// `settle`) wiederverwendet. Besonderheiten gegenueber allen bisherigen Modi:
//   - Geraeumt wird NICHT beim Aufsetzen, sondern durch die Sense: Sie wandert Spalte fuer
//     Spalte nach rechts (zyklisch), sammelt markierte Zellen ein und erntet sie, sobald sie
//     die markierte Sektion verlaesst (naechste Spalte ohne Markierung oder Brett-Ende).
//   - Nur ZWEI Sorten (der Klassiker des Genres — Quadrate entstehen sonst kaum).
//   - Beim Aufsetzen zerfallen die beiden Spalten des Blocks unabhaengig (`settle`).
//   - Keine Ketten-Kaskade, kein Magic-Stein.
//
// Ablauf aus Sicht der Render-Schicht:
//   1. Wiederholt `gravityTick()` im Fall-Takt UND `sweepTick()` im Sense-Takt.
//   2. `.locked(result)` ⇒ Block sitzt (keine Raeum-Wellen!); danach `spawnNext()`.
//   3. Liefert `sweepTick()` einen `ClearStep`, animiert die Szene dieses Ernten.

public struct SquareEngine: Sendable {

    // MARK: Konstanten

    /// Die zwei Spielsorten dieses Modus (kontrastreichstes Paar der sechs Stein-Sorten:
    /// Pentagramm-Rot und Schaedel-Hell).
    public static let blockColors: [Gem] = [.ruby, .diamond]
    /// Standard-Brettmaße. Das Genre-Original ist QUER (16×10) — unsere Fenster/Geraete sind
    /// hochkant, darum ein kompaktes Quadrat als Default; die Original-Proportion laesst sich
    /// ueber die Brettgroessen-Einstellung (bis 16 breit) nachstellen.
    public static let defaultWidth = 12
    public static let defaultHeight = 12

    /// Linke Spalte, in der jeder neue Block erscheint (der Block ist 2 breit, mittig).
    public var spawnColumn: Int { (board.width - 2) / 2 }
    /// Reihe der UNTEREN Block-Zellen beim Einwurf (oberste Brettreihe); die obere Reihe
    /// schwebt anfangs noch ueber dem Brett ein (wie bei Saeule/Paar/Kapsel).
    public var spawnRow: Int { board.height - 1 }

    // MARK: Zustand (von aussen nur lesbar)

    public private(set) var board: Board
    public private(set) var current: SquarePiece
    /// Vorschau auf den naechsten Block (Farb-Reihenfolge wie `SquarePiece.gems`).
    public private(set) var nextGems: [Gem]
    public private(set) var score: Int
    public private(set) var gemsCleared: Int
    public let startLevel: Int
    public private(set) var phase: Phase
    public let seed: UInt64

    /// Alle Zellen, die Teil mindestens eines gleichfarbigen 2×2-Quadrats sind — von der
    /// Sense zu ernten. Wird nach jedem Aufsetzen und jeder Ernte neu berechnet.
    public private(set) var marked: Set<Cell>
    /// Aktuelle Spalte der Sense (0 ≤ sweepCol < Brettbreite, wandert zyklisch nach rechts).
    public private(set) var sweepCol: Int

    private var rng: Xoshiro256StarStar

    /// Aktuelles Level: steigt mit der Zahl geraeumter Steine (30 je Stufe, wie die Saeulen).
    public var level: Int { startLevel + gemsCleared / Engine.gemsPerLevel }

    // MARK: Initialisierung

    public init(seed: UInt64, startLevel: Int = 0,
                width: Int = SquareEngine.defaultWidth,
                height: Int = SquareEngine.defaultHeight) {
        self.seed = seed
        self.startLevel = max(0, startLevel)
        self.board = Board(width: width, height: height)
        self.score = 0
        self.gemsCleared = 0
        self.phase = .falling
        self.marked = []
        self.sweepCol = 0

        var r = Xoshiro256StarStar(seed: seed)
        let first = SquareEngine.drawBlock(&r)
        self.nextGems = SquareEngine.drawBlock(&r)
        self.rng = r
        self.current = SquarePiece(gems: first, col: (width - 2) / 2, row: height - 1)
    }

    /// Test-Initialisierer: setzt Brett und Bloecke direkt (nur via `@testable import`).
    /// Markierungen werden aus dem uebergebenen Brett berechnet; die Sense startet bei Spalte 0.
    init(board: Board, current: SquarePiece, next: [Gem], seed: UInt64 = 1, startLevel: Int = 0) {
        self.seed = seed
        self.startLevel = max(0, startLevel)
        self.board = board
        self.current = current
        self.nextGems = next
        self.score = 0
        self.gemsCleared = 0
        self.phase = .falling
        self.marked = []
        self.sweepCol = 0
        self.rng = Xoshiro256StarStar(seed: seed)
        recomputeMarks()
    }

    // MARK: Eingaben (nur in Phase .falling)

    /// Block eine Spalte nach links. Liefert `true`, wenn der Zug moeglich war.
    public mutating func moveLeft() -> Bool { shift(-1) }

    /// Block eine Spalte nach rechts.
    public mutating func moveRight() -> Bool { shift(1) }

    private mutating func shift(_ dx: Int) -> Bool {
        guard phase == .falling else { return false }
        var moved = current
        moved.col += dx
        guard fits(moved) else { return false }
        current = moved
        return true
    }

    /// Dreht die vier FARBEN des Blocks im Uhrzeigersinn. Die Form aendert sich nicht (2×2
    /// bleibt 2×2) — die Drehung kann also nie kollidieren und gelingt immer.
    public mutating func rotate() -> Bool {
        guard phase == .falling else { return false }
        current.rotateCW()
        return true
    }

    // MARK: Schwerkraft / Aufsetzen

    /// Kann der Block eine Reihe tiefer? Reine Abfrage (kein Zustand) — fuers Lock-Delay.
    public func canFall() -> Bool {
        guard phase == .falling else { return false }
        var below = current
        below.row -= 1
        return fits(below)
    }

    /// Laesst den Block eine Reihe fallen. Geht das nicht, rastet er ein und wird als
    /// `.locked(result)` zurueckgegeben — OHNE Raeum-Wellen (das Ernten macht die Sense).
    public mutating func gravityTick() -> SquareTick {
        guard phase == .falling else { return .moved }
        var below = current
        below.row -= 1
        if fits(below) {
            current = below
            return .moved
        }
        return .locked(lock())
    }

    /// Rastet den Block ins Brett ein und laesst die beiden Spalten unabhaengig nachrutschen.
    /// Danach werden die 2×2-Markierungen neu berechnet — geraeumt wird hier NICHTS.
    private mutating func lock() -> SquareLock {
        let landed = current
        for (cell, gem) in landed.cells where cell.row < board.height {
            board[cell.col, cell.row] = gem
        }
        let boardBefore = board
        settle(&board)
        recomputeMarks()
        phase = .resolving
        return SquareLock(landed: landed, boardBefore: boardBefore)
    }

    /// Wirft den naechsten Block ein. Liefert `false`, wenn der Einwurf blockiert ist → Spiel vorbei.
    @discardableResult
    public mutating func spawnNext() -> Bool {
        guard phase == .resolving else { return phase != .gameOver }

        // Einwurf blockiert? (nur die UNTERE Block-Reihe liegt im Brett — die obere schwebt
        // ueber dem Brett und ist immer frei.)
        if board[spawnColumn, spawnRow] != nil || board[spawnColumn + 1, spawnRow] != nil {
            phase = .gameOver
            return false
        }
        current = SquarePiece(gems: nextGems, col: spawnColumn, row: spawnRow)
        nextGems = SquareEngine.drawBlock(&rng)
        phase = .falling
        return true
    }

    // MARK: Sense (Sweep-Linie)

    /// Bewegt die Sense um EINE Spalte nach rechts (zyklisch). Verlaesst sie dabei das rechte
    /// Ende einer markierten SEKTION (die aktuelle Spalte traegt Markierungen, die naechste
    /// nicht mehr — oder das Brett ist zu Ende), erntet sie die KOMPLETTE zusammenhaengende
    /// Sektion und liefert die Raeum-Welle als `ClearStep` (sonst nil). Der TAKT der Aufrufe
    /// lebt in der Render-Schicht — hier gibt es nur den deterministischen Schritt.
    ///
    /// Bewusste Vereinfachung gegenueber dem Genre-Original: Die Sektion wird komplett
    /// geerntet, auch wenn Teile davon erst WAEHREND des Ueberstreichens entstanden sind
    /// (das Original liesse sie bis zur naechsten Runde liegen) — grosszuegig zum Spieler
    /// und ohne zusaetzlichen Sammel-Zustand, der Randfaelle an Start/Umbruch erzeugt.
    public mutating func sweepTick() -> ClearStep? {
        guard phase != .gameOver else { return nil }
        let cur = sweepCol
        let next = (cur + 1) % board.width
        var step: ClearStep? = nil
        let curHasMarks = marked.contains { $0.col == cur }
        let sectionEnds = (next == 0) || !marked.contains { $0.col == next }
        if curHasMarks && sectionEnds {
            // Die Sektion rueckwaerts einsammeln: alle markierten Zellen der lueckenlosen
            // Spaltenfolge, die bei `cur` endet.
            var cells = Set<Cell>()
            var c = cur
            while c >= 0 {
                let colCells = marked.filter { $0.col == c }
                if colCells.isEmpty { break }
                cells.formUnion(colCells)
                c -= 1
            }
            step = harvest(cells)
        }
        sweepCol = next
        return step
    }

    /// Erntet die uebergebenen markierten Zellen: raeumen, nachrutschen lassen, Markierungen
    /// neu berechnen, Punkte gutschreiben. Keine Ketten — jede Ernte zaehlt als eigene Welle.
    private mutating func harvest(_ cells: Set<Cell>) -> ClearStep? {
        guard !cells.isEmpty else { return nil }
        for cell in cells { board[cell.col, cell.row] = nil }
        settle(&board)
        recomputeMarks()
        let pts = Engine.points(cleared: cells.count, chain: 1)
        score += pts
        gemsCleared += cells.count
        // Sortiert (nicht `Array(cells)`): Set-Reihenfolge ist prozess-zufaellig, die
        // Brett-Reihenfolge haelt ClearStep.cells deterministisch (Regel 2).
        return ClearStep(cells: cells.sorted(), kind: .match, color: nil,
                         chain: 1, points: pts, boardAfter: board)
    }

    /// Berechnet alle markierten Zellen neu: jede Zelle, die Teil mindestens eines
    /// gleichfarbigen 2×2-Quadrats ist (Quadrate duerfen sich ueberlappen — ein 3×2-Block
    /// einer Farbe markiert alle sechs Zellen).
    private mutating func recomputeMarks() {
        var marks = Set<Cell>()
        for row in 0..<(board.height - 1) {
            for col in 0..<(board.width - 1) {
                guard let gem = board[col, row], !gem.isMagic else { continue }
                if board[col + 1, row] == gem, board[col, row + 1] == gem,
                   board[col + 1, row + 1] == gem {
                    marks.insert(Cell(col: col,     row: row))
                    marks.insert(Cell(col: col + 1, row: row))
                    marks.insert(Cell(col: col,     row: row + 1))
                    marks.insert(Cell(col: col + 1, row: row + 1))
                }
            }
        }
        marked = marks
    }

    // MARK: Hilfen (Kollision, Zufall)

    /// Passt der Block an seine Position? Alle vier Zellen muessen seitlich im Feld liegen,
    /// nicht unter dem Boden sein und (falls im Brett) leer — OBERHALB des Bretts gilt als
    /// frei (der Block schwebt von oben ein).
    private func fits(_ piece: SquarePiece) -> Bool {
        for (cell, _) in piece.cells {
            if cell.col < 0 || cell.col >= board.width || cell.row < 0 { return false }
            if cell.row < board.height, board[cell.col, cell.row] != nil { return false }
        }
        return true
    }

    /// Zieht die vier Farben des naechsten Blocks (jede Zelle unabhaengig eine der zwei Sorten).
    static func drawBlock(_ rng: inout Xoshiro256StarStar) -> [Gem] {
        (0..<4).map { _ in blockColors[Int(rng.next() % UInt64(blockColors.count))] }
    }
}
