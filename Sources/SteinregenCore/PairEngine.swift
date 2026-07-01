// PairEngine.swift
// Deterministische Spiel-Engine des dritten Modus „Blutklumpen" (Puyo-Stil): fallende
// Zweier-Paare, Gruppen ab vier verbundenen gleichen Steinen raeumen, Ketten-Kaskaden.
//
// Determinismus-Regel (CLAUDE.md): KEIN globaler Zufall, KEINE Wanduhr. Die Farbfolge der
// Paare laeuft ueber den injizierten, seed-bestimmten `Xoshiro256StarStar`. Gleicher Seed
// + gleiche Eingaben ⇒ gleicher Verlauf.
//
// Die anderen Engines bleiben voellig unberuehrt — dieser Modus ist eine eigene, parallele
// Engine, die nur die gemeinsamen Bausteine (`Board`, `Gem`, `Phase`, `ClearStep`, PRNG,
// `settle`) wiederverwendet. Besonderheiten gegenueber den Saeulen:
//   - Nur VIER Farben (statt sechs): Mit sechs Farben kaemen Vierergruppen kaum zustande —
//     vier ist der spielbare Klassiker des Genres.
//   - Nach dem Aufsetzen fallen die beiden Haelften UNABHAENGIG (eine quer liegende Haelfte
//     ohne Boden rutscht allein weiter) — das erledigt `settle` vor der Treffer-Suche.
//   - Kein Magic-Stein.
//
// Ablauf aus Sicht der Render-Schicht (analog zu den anderen Engines):
//   1. Wiederholt `gravityTick()` im Fall-Takt.
//   2. `.locked(result)` ⇒ Paar sitzt, Kaskade ist bereits berechnet (Brett/Punkte final).
//   3. Render animiert `result.steps`; danach `spawnNext()` → neues Paar oder `.gameOver`.

public struct PairEngine: Sendable {

    // MARK: Konstanten

    /// Ab so vielen verbundenen gleichfarbigen Steinen raeumt eine Gruppe.
    public static let groupSize = 4
    /// Die vier Spielfarben dieses Modus (Teilmenge der sechs Stein-Sorten).
    public static let pairColors: [Gem] = Array(Gem.colors.prefix(4))

    /// Mittlere Spalte, in der jedes neue Paar erscheint — haengt von der Brettbreite ab.
    public var spawnColumn: Int { board.width / 2 }
    /// Reihe des Pivots beim Einwurf (oberste Brettreihe). Das Paar schwebt von oben ein:
    /// der Satellit (Lage `.up`) liegt anfangs noch UEBER dem Brett (Reihe >= board.height,
    /// dort als frei behandelt) und wird von der Render-Schicht ausgeblendet.
    public var spawnRow: Int { board.height - 1 }

    // MARK: Zustand (von aussen nur lesbar)

    public private(set) var board: Board
    public private(set) var current: PairPiece
    /// Vorschau auf das naechste Paar: Index 0 = Pivot, Index 1 = Satellit.
    public private(set) var nextGems: [Gem]
    public private(set) var score: Int
    public private(set) var gemsCleared: Int
    public let startLevel: Int
    public private(set) var phase: Phase
    public let seed: UInt64

    private var rng: Xoshiro256StarStar

    /// Aktuelles Level: steigt mit der Zahl geraeumter Steine (30 je Stufe, wie die Saeulen).
    public var level: Int { startLevel + gemsCleared / Engine.gemsPerLevel }

    // MARK: Initialisierung

    public init(seed: UInt64, startLevel: Int = 0,
                width: Int = Board.defaultWidth, height: Int = Board.defaultHeight) {
        self.seed = seed
        self.startLevel = max(0, startLevel)
        self.board = Board(width: width, height: height)
        self.score = 0
        self.gemsCleared = 0
        self.phase = .falling

        var r = Xoshiro256StarStar(seed: seed)
        let first = PairEngine.drawPair(&r)
        self.nextGems = PairEngine.drawPair(&r)
        self.rng = r
        // spawnColumn/spawnRow sind berechnete Eigenschaften (brauchen `board`); hier direkt
        // aus den Brettmaßen, weil im Initializer noch nicht alle Felder gesetzt sind.
        self.current = PairPiece(gems: first, col: width / 2, row: height - 1)
    }

    /// Test-Initialisierer: setzt Brett und Paare direkt (nur via `@testable import`).
    init(board: Board, current: PairPiece, next: [Gem], seed: UInt64 = 1, startLevel: Int = 0) {
        self.seed = seed
        self.startLevel = max(0, startLevel)
        self.board = board
        self.current = current
        self.nextGems = next
        self.score = 0
        self.gemsCleared = 0
        self.phase = .falling
        self.rng = Xoshiro256StarStar(seed: seed)
    }

    // MARK: Eingaben (nur in Phase .falling)

    /// Paar eine Spalte nach links. Liefert `true`, wenn der Zug moeglich war.
    public mutating func moveLeft() -> Bool { shift(-1) }

    /// Paar eine Spalte nach rechts.
    public mutating func moveRight() -> Bool { shift(1) }

    private mutating func shift(_ dx: Int) -> Bool {
        guard phase == .falling else { return false }
        var moved = current
        moved.col += dx
        guard fits(moved) else { return false }
        current = moved
        return true
    }

    /// Dreht den Satelliten 90° im Uhrzeigersinn um den Pivot. Ist die Zielzelle blockiert
    /// (Wand, Boden oder Stein), wird ein einfacher „Kick" probiert: der Pivot weicht um den
    /// GEGEN-Versatz aus (Drehung an die Wand schiebt das Paar von der Wand weg; Drehung nach
    /// unten am Boden hebt es eine Reihe an). Passt auch das nicht, bleibt das Paar unveraendert.
    public mutating func rotate() -> Bool {
        guard phase == .falling else { return false }
        var rotated = current
        rotated.orientation = current.orientation.rotatedCW
        if fits(rotated) {
            current = rotated
            return true
        }
        // Kick: Pivot entgegen der neuen Satelliten-Richtung verschieben.
        let o = rotated.orientation.offset
        rotated.col -= o.col
        rotated.row -= o.row
        if fits(rotated) {
            current = rotated
            return true
        }
        return false
    }

    // MARK: Schwerkraft / Aufsetzen

    /// Kann das Paar eine Reihe tiefer? Reine Abfrage (kein Zustand) — fuers Lock-Delay.
    public func canFall() -> Bool {
        guard phase == .falling else { return false }
        var below = current
        below.row -= 1
        return fits(below)
    }

    /// Laesst das Paar eine Reihe fallen. Geht das nicht, rastet es ein und die komplette
    /// Kaskade wird berechnet und als `.locked(result)` zurueckgegeben.
    public mutating func gravityTick() -> PairTick {
        guard phase == .falling else { return .moved }
        var below = current
        below.row -= 1
        if fits(below) {
            current = below
            return .moved
        }
        return .locked(lock())
    }

    /// Rastet das Paar ins Brett ein, laesst die Haelften unabhaengig nachrutschen und loest
    /// die Ketten-Kaskade vollstaendig auf (wie im Saeulen-Modus, nur mit Gruppen- statt
    /// Linien-Treffern).
    private mutating func lock() -> PairLock {
        let landed = current
        // Beide Steine ins Brett schreiben; Zellen ueber dem Brett (Satellit beim Aufsetzen in
        // der obersten Reihe) verfallen — wie bei der Saeule.
        for (cell, gem) in landed.cells where cell.row < board.height {
            board[cell.col, cell.row] = gem
        }
        // Brett VOR dem Nachrutschen festhalten: die Render-Schicht zeigt diesen Stand und
        // animiert dann das Herabfallen einer evtl. frei schwebenden Haelfte.
        let boardBefore = board
        settle(&board)

        // Treffer-Kaskade: solange Vierergruppen entstehen, raeumen + nachrutschen lassen.
        var steps: [ClearStep] = []
        var chain = 0
        while true {
            let matches = findGroups(board, minSize: PairEngine.groupSize)
            if matches.isEmpty { break }
            chain += 1
            for cell in matches { board[cell.col, cell.row] = nil }
            settle(&board)
            let pts = Engine.points(cleared: matches.count, chain: chain)
            score += pts
            gemsCleared += matches.count
            steps.append(ClearStep(cells: matches, kind: .match, color: nil,
                                   chain: chain, points: pts, boardAfter: board))
        }

        phase = .resolving
        return PairLock(landed: landed, boardBefore: boardBefore, steps: steps)
    }

    /// Wirft das naechste Paar ein. Nur nach abgeschlossener Aufloesung aufrufen.
    /// Liefert `false`, wenn der Einwurf blockiert ist → Spiel vorbei.
    @discardableResult
    public mutating func spawnNext() -> Bool {
        guard phase == .resolving else { return phase != .gameOver }

        // Einwurf blockiert? (mittlere Spalte oben belegt — der Satellit startet UEBER dem
        // Brett und ist damit immer frei)
        if board[spawnColumn, spawnRow] != nil {
            phase = .gameOver
            return false
        }
        current = PairPiece(gems: nextGems, col: spawnColumn, row: spawnRow)
        nextGems = PairEngine.drawPair(&rng)
        phase = .falling
        return true
    }

    // MARK: Hilfen (Kollision, Zufall)

    /// Passt das Paar an seine Position? Beide Zellen muessen seitlich im Feld liegen, nicht
    /// unter dem Boden sein und (falls im Brett) leer sein — Zellen OBERHALB des Bretts gelten
    /// als frei (das Paar schwebt von oben ein, Drehen darf kurz ueber den Rand hinaus).
    private func fits(_ piece: PairPiece) -> Bool {
        for (cell, _) in piece.cells {
            if cell.col < 0 || cell.col >= board.width || cell.row < 0 { return false }
            if cell.row < board.height, board[cell.col, cell.row] != nil { return false }
        }
        return true
    }

    /// Zieht die zwei Farben des naechsten Paars (nur aus den vier Modus-Farben, nie Magic).
    static func drawPair(_ rng: inout Xoshiro256StarStar) -> [Gem] {
        (0..<2).map { _ in pairColors[Int(rng.next() % UInt64(pairColors.count))] }
    }
}
