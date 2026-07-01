// TetrominoEngine.swift
// Deterministische Spiel-Engine der Reihen-Raeum-Modi: „Verschuettet" (Vierlinge) UND — mit dem
// Fuenfling-Formen-Satz gefuettert — „Fuenfling"/„Erdrueckt" (Pentominoes). Der Formen-Satz wird
// beim Erzeugen injiziert (`types`), die Spielregeln sind identisch (volle Reihen raeumen).
//
// Determinismus-Regel (CLAUDE.md): KEIN globaler Zufall, KEINE Wanduhr. Die Stein-Reihenfolge
// laeuft ueber den injizierten, seed-bestimmten `Xoshiro256StarStar` (als „Bag": jede Form des
// Formen-Satzes kommt pro Beutel genau einmal, Beutel deterministisch gemischt). Gleicher Seed
// + gleiche Eingaben ⇒ gleicher Verlauf.
//
// Die Columns-`Engine` bleibt voellig unberuehrt — dieser Modus ist eine eigene, parallele Engine,
// die nur die gemeinsamen Bausteine (`Board`, `Gem`, `Phase`, `ClearStep`, PRNG) wiederverwendet.
//
// Ablauf aus Sicht der Render-Schicht (analog zur Columns-Engine):
//   1. Wiederholt `gravityTick()` im Fall-Takt.
//   2. `.locked(result)` ⇒ Vierling sitzt, volle Reihen sind bereits geraeumt (Brett/Punkte final).
//   3. Render animiert `result.steps`; danach `spawnNext()` → neuer Vierling oder `.gameOver`.

public struct TetrominoEngine: Sendable {

    // MARK: Konstanten

    /// Standard-Brettmaße des Vierling-Modus (breiter/hoeher als die Saeulen, gutes Vierling-Gefuehl).
    public static let defaultWidth = 10
    public static let defaultHeight = 18
    /// Standard-Brettmaße des Fuenfling-Modus (noch breiter/hoeher — die groesseren Formen brauchen Raum).
    public static let pentominoDefaultWidth = 12
    public static let pentominoDefaultHeight = 20
    /// So viele geraeumte Reihen heben das Level um eins (klassisch: zehn).
    public static let linesPerLevel = 10

    // MARK: Zustand (von aussen nur lesbar)

    public private(set) var board: Board
    public private(set) var current: Tetromino
    /// Vorschau auf die naechste Form.
    public private(set) var nextType: TetrominoType
    public private(set) var score: Int
    /// Anzahl geraeumter REIHEN (treibt das Level — nicht die Steinzahl wie bei den Saeulen).
    public private(set) var linesCleared: Int
    public let startLevel: Int
    public private(set) var phase: Phase
    public let seed: UInt64
    /// Der Formen-Satz dieser Partie (Vierlinge oder Fuenflinge) — Grundmenge des Beutels.
    public let types: [TetrominoType]

    private var rng: Xoshiro256StarStar
    /// Aktueller „Beutel" noch nicht gezogener Formen. Leer ⇒ beim naechsten Zug neu mischen.
    private var bag: [TetrominoType]

    /// Aktuelles Level: steigt mit der Zahl geraeumter Reihen, beginnend bei `startLevel`.
    public var level: Int { startLevel + linesCleared / TetrominoEngine.linesPerLevel }

    // MARK: Initialisierung

    public init(seed: UInt64, startLevel: Int = 0,
                width: Int = TetrominoEngine.defaultWidth,
                height: Int = TetrominoEngine.defaultHeight,
                types: [TetrominoType] = TetrominoType.tetrominoes) {
        self.seed = seed
        self.startLevel = max(0, startLevel)
        self.board = Board(width: width, height: height)
        self.score = 0
        self.linesCleared = 0
        self.phase = .falling
        self.types = types

        // Erste Form + Vorschau aus dem Bag ziehen. Statisch gezogen, weil im Initializer noch
        // nicht alle gespeicherten Felder gesetzt sind (keine Instanz-Methoden moeglich).
        var r = Xoshiro256StarStar(seed: seed)
        var b: [TetrominoType] = []
        let firstType = TetrominoEngine.draw(&b, from: types, &r)
        self.nextType = TetrominoEngine.draw(&b, from: types, &r)
        self.rng = r
        self.bag = b

        // Spawn mittig oben (Box-Oberkante an der Brett-Oberkante).
        let n = firstType.boxSize
        self.current = Tetromino(type: firstType, col: (width - n) / 2, row: height - n)
    }

    /// Test-Initialisierer: setzt Brett, aktuellen Vierling und naechste Form direkt.
    init(board: Board, current: Tetromino, next: TetrominoType, seed: UInt64 = 1, startLevel: Int = 0,
         types: [TetrominoType] = TetrominoType.tetrominoes) {
        self.seed = seed
        self.startLevel = max(0, startLevel)
        self.board = board
        self.current = current
        self.nextType = next
        self.score = 0
        self.linesCleared = 0
        self.phase = .falling
        self.types = types
        self.rng = Xoshiro256StarStar(seed: seed)
        self.bag = []
    }

    // MARK: Eingaben (nur in Phase .falling)

    /// Vierling eine Spalte nach links. Liefert `true`, wenn der Zug moeglich war.
    public mutating func moveLeft() -> Bool { shift(-1) }

    /// Vierling eine Spalte nach rechts.
    public mutating func moveRight() -> Bool { shift(1) }

    private mutating func shift(_ dx: Int) -> Bool {
        guard phase == .falling else { return false }
        guard fits(offsets: current.offsets, col: current.col + dx, row: current.row) else { return false }
        current.col += dx
        return true
    }

    /// Dreht den Vierling 90° im Uhrzeigersinn. Kollidiert die Drehung an Ort und Stelle, werden
    /// ein paar kleine Versatz-Versuche probiert (vereinfachte „Wall-Kicks"), damit eine Drehung an
    /// Wand oder Boden nicht grundlos scheitert. Passt keiner, bleibt der Vierling unveraendert.
    public mutating func rotate() -> Bool {
        guard phase == .falling else { return false }
        let rotated = current.rotatedOffsets()
        // Reihenfolge: an Ort, dann je einen/zwei Schritte seitlich, zuletzt einen hoch.
        let kicks = [(0, 0), (1, 0), (-1, 0), (2, 0), (-2, 0), (0, 1)]
        for (dx, dy) in kicks {
            if fits(offsets: rotated, col: current.col + dx, row: current.row + dy) {
                current.offsets = rotated
                current.col += dx
                current.row += dy
                return true
            }
        }
        return false
    }

    // MARK: Schwerkraft / Aufsetzen

    /// Kann der Vierling eine Reihe tiefer? Reine Abfrage (kein Zustand) — fuers Lock-Delay.
    public func canFall() -> Bool {
        guard phase == .falling else { return false }
        return fits(offsets: current.offsets, col: current.col, row: current.row - 1)
    }

    /// Laesst den Vierling eine Reihe fallen. Geht das nicht, rastet er ein, volle Reihen werden
    /// geraeumt und das Ganze als `.locked(result)` zurueckgegeben.
    public mutating func gravityTick() -> TetrominoTick {
        guard phase == .falling else { return .moved }
        if fits(offsets: current.offsets, col: current.col, row: current.row - 1) {
            current.row -= 1
            return .moved
        }
        return .locked(lock())
    }

    /// Rastet den aktuellen Vierling ins Brett ein und raeumt entstandene volle Reihen.
    private mutating func lock() -> TetrominoLock {
        let landed = current
        for cell in current.boardCells() where board.inBounds(col: cell.col, row: cell.row) {
            board[cell.col, cell.row] = current.type.gem
        }
        let before = board

        var steps: [ClearStep] = []
        let rows = fullRows(board)
        if !rows.isEmpty {
            let cells = TetrominoEngine.clearRows(&board, rows: rows)
            // Punkte werden mit dem Level VOR dem Hochzaehlen berechnet.
            let pts = TetrominoEngine.linePoints(lines: rows.count, level: level)
            score += pts
            linesCleared += rows.count
            steps.append(ClearStep(cells: cells, kind: .match, color: nil, chain: 1,
                                   points: pts, boardAfter: board))
        }

        phase = .resolving
        return TetrominoLock(landed: landed, boardBefore: before, steps: steps)
    }

    /// Wirft den naechsten Vierling ein. Nur nach abgeschlossener Aufloesung aufrufen.
    /// Liefert `false`, wenn der Einwurf blockiert ist → Spiel vorbei.
    @discardableResult
    public mutating func spawnNext() -> Bool {
        guard phase == .resolving else { return phase != .gameOver }

        let type = nextType
        let n = type.boxSize
        let piece = Tetromino(type: type, col: (board.width - n) / 2, row: board.height - n)
        // Einwurf blockiert? (Spawn-Zellen schon belegt)
        if !fits(offsets: piece.offsets, col: piece.col, row: piece.row) {
            phase = .gameOver
            return false
        }
        current = piece
        nextType = TetrominoEngine.draw(&bag, from: types, &rng)
        phase = .falling
        return true
    }

    // MARK: Hilfen (Kollision, volle Reihen, Bag, Punkte)

    /// Passen die Offsets bei (col, row) ins Brett (im Feld UND alle Zielzellen leer)?
    private func fits(offsets: [Cell], col: Int, row: Int) -> Bool {
        for o in offsets {
            let c = col + o.col, r = row + o.row
            if !board.inBounds(col: c, row: r) { return false }
            if board[c, r] != nil { return false }
        }
        return true
    }

    /// Alle vollstaendig belegten Reihen (von unten nach oben).
    private func fullRows(_ board: Board) -> [Int] {
        var rows: [Int] = []
        for row in 0..<board.height {
            var full = true
            for col in 0..<board.width where board[col, row] == nil { full = false; break }
            if full { rows.append(row) }
        }
        return rows
    }

    /// Entfernt die angegebenen Reihen und laesst alles darueber als Block nachrutschen.
    /// Liefert die geraeumten Zellen (fuer die Animation). Statisch + rein — leicht testbar.
    static func clearRows(_ board: inout Board, rows: [Int]) -> [Cell] {
        let cleared = Set(rows)
        var clearedCells: [Cell] = []
        for row in rows {
            for col in 0..<board.width { clearedCells.append(Cell(col: col, row: row)) }
        }
        // Neues Brett: die ueberlebenden Reihen von unten nach oben dicht packen.
        var packed = Board(width: board.width, height: board.height)
        var writeRow = 0
        for row in 0..<board.height where !cleared.contains(row) {
            for col in 0..<board.width { packed[col, writeRow] = board[col, row] }
            writeRow += 1
        }
        board = packed
        return clearedCells
    }

    /// Zieht die naechste Form aus dem Bag. Ist der Beutel leer, wird er mit ALLEN Formen des
    /// Formen-Satzes neu gefuellt und deterministisch (Fisher-Yates ueber den injizierten PRNG)
    /// gemischt — jede Form kommt pro Beutel genau einmal (7-bag bzw. 18-bag).
    static func draw(_ bag: inout [TetrominoType], from types: [TetrominoType],
                     _ rng: inout Xoshiro256StarStar) -> TetrominoType {
        if bag.isEmpty {
            bag = types
            var i = bag.count - 1
            while i > 0 {
                let j = Int(rng.next() % UInt64(i + 1))
                bag.swapAt(i, j)
                i -= 1
            }
        }
        return bag.removeLast()
    }

    /// Punkte fuer gleichzeitig geraeumte Reihen (moderne Richtlinie), mit dem Level multipliziert.
    /// 1/2/3/4/5 Reihen = 100/300/500/800/1200 × Level (Mehrfach-Raeumung wird klar belohnt;
    /// die fuenfte Stufe erreicht nur der Fuenfling-Modus mit dem senkrechten I5).
    public static func linePoints(lines: Int, level: Int) -> Int {
        let base = [0, 100, 300, 500, 800, 1200]
        let n = min(max(lines, 0), 5)
        return base[n] * max(1, level)
    }
}
