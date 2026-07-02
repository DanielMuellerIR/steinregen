// CapsuleEngine.swift
// Deterministische Spiel-Engine des fuenften Modus „Austreibung" (Dr.-Mario-Stil): fallende
// Kapsel-Paare auf ein mit FLUECHEN vorbefuelltes Brett; Laeufe ab vier gleichfarbigen Steinen
// in Reihe oder Spalte raeumen. Alle Flueche getilgt ⇒ GEWONNEN (Phase `.won`) — der erste
// Modus mit Sieg-Bedingung statt Endlos-Spiel.
//
// Determinismus-Regel (CLAUDE.md): KEIN globaler Zufall, KEINE Wanduhr. Sowohl die
// Fluch-Vorbefuellung als auch die Farbfolge der Kapseln laufen ueber den injizierten,
// seed-bestimmten `Xoshiro256StarStar`. Gleicher Seed + gleiche Eingaben ⇒ gleicher Verlauf.
//
// Die anderen Engines bleiben voellig unberuehrt — dieser Modus ist eine eigene, parallele
// Engine, die nur die gemeinsamen Bausteine (`Board`, `Gem`, `Phase`, `ClearStep`, PRNG,
// `PairPiece`/`PairOrientation` aus dem Klumpen-Modus, `settle(pinned:)`, `findLines`)
// wiederverwendet. Besonderheiten:
//   - Nur DREI Farben (der spielbare Klassiker des Genres — mit mehr Farben kaemen
//     Vierer-Laeufe kaum zustande).
//   - Die Flueche KLEBEN an ihrem Platz: `settle(pinned:)` laesst nur normale Steine
//     nachrutschen, und nur bis AUF den naechsten Fluch (nie an ihm vorbei).
//   - Das Level ist KONSTANT (die Start-Tempostufe): sie bestimmt Fluch-Anzahl UND Tempo —
//     ein Regler fuer die Schwierigkeit. Kein Level-Anstieg waehrend der Partie.
//   - Kein Magic-Stein.
//
// Ablauf aus Sicht der Render-Schicht (analog zu den anderen Engines):
//   1. Wiederholt `gravityTick()` im Fall-Takt.
//   2. `.locked(result)` ⇒ Kapsel sitzt, Kaskade ist bereits berechnet (Brett/Punkte final).
//      Danach ist die Phase `.resolving` — oder `.won`, falls der letzte Fluch fiel.
//   3. Render animiert `result.steps`; danach `spawnNext()` → neue Kapsel, `.gameOver` bei
//      blockiertem Einwurf, oder (bei `.won`) Sieg-Anzeige.

public struct CapsuleEngine: Sendable {

    // MARK: Konstanten

    /// Ab so vielen gleichfarbigen Steinen in Reihe/Spalte raeumt ein Lauf.
    public static let runLength = 4
    /// Die drei Spielfarben dieses Modus (Teilmenge der sechs Stein-Sorten).
    public static let capsuleColors: [Gem] = Array(Gem.colors.prefix(3))
    /// Bonus-Punkte je geraeumtem FLUCH (zusaetzlich zu den normalen Raeum-Punkten).
    public static let curseBonus = 100
    /// Standard-Brettmaße (Genre-Klassik: 8 Spalten × 16 Reihen).
    public static let defaultWidth = 8
    public static let defaultHeight = 16

    /// Mittlere Spalte, in der jede neue Kapsel erscheint — haengt von der Brettbreite ab.
    public var spawnColumn: Int { board.width / 2 }
    /// Reihe des Pivots beim Einwurf (oberste Brettreihe); der Satellit schwebt anfangs noch
    /// UEBER dem Brett ein (wie im Klumpen-Modus).
    public var spawnRow: Int { board.height - 1 }

    // MARK: Zustand (von aussen nur lesbar)

    public private(set) var board: Board
    /// Die noch nicht getilgten Fluch-Zellen. Flueche sind normale Farben im Brett, kleben aber
    /// fest (siehe `settle(pinned:)`) — leer ⇒ die Partie ist gewonnen.
    public private(set) var curses: Set<Cell>
    /// So viele Flueche lagen zu Partiebeginn im Brett (fuer HUD/Statistik).
    public let curseCountAtStart: Int
    public private(set) var current: PairPiece
    /// Vorschau auf die naechste Kapsel: Index 0 = Pivot, Index 1 = Satellit.
    public private(set) var nextGems: [Gem]
    public private(set) var score: Int
    public private(set) var gemsCleared: Int
    public let startLevel: Int
    public private(set) var phase: Phase
    public let seed: UInt64

    private var rng: Xoshiro256StarStar

    /// Level dieses Modus: KONSTANT die Start-Tempostufe (kein Anstieg — die Partie endet mit
    /// Sieg oder Game Over; die Stufe bestimmt Fluch-Anzahl und Fallgeschwindigkeit).
    public var level: Int { startLevel }

    // MARK: Initialisierung

    public init(seed: UInt64, startLevel: Int = 0,
                width: Int = CapsuleEngine.defaultWidth,
                height: Int = CapsuleEngine.defaultHeight) {
        self.seed = seed
        self.startLevel = max(0, startLevel)
        var b = Board(width: width, height: height)
        self.score = 0
        self.gemsCleared = 0
        self.phase = .falling

        // Erst die Flueche deterministisch platzieren, DANN die Kapsel-Farben ziehen — die
        // Reihenfolge der PRNG-Zugriffe ist Teil des deterministischen Vertrags.
        var r = Xoshiro256StarStar(seed: seed)
        let placed = CapsuleEngine.placeCurses(&b, level: max(1, startLevel), &r)
        self.board = b
        self.curses = placed
        self.curseCountAtStart = placed.count

        let first = CapsuleEngine.drawPair(&r)
        self.nextGems = CapsuleEngine.drawPair(&r)
        self.rng = r
        self.current = PairPiece(gems: first, col: width / 2, row: height - 1)
    }

    /// Test-Initialisierer: setzt Brett, Flueche und Kapseln direkt (nur via `@testable import`).
    init(board: Board, curses: Set<Cell>, current: PairPiece, next: [Gem],
         seed: UInt64 = 1, startLevel: Int = 0) {
        self.seed = seed
        self.startLevel = max(0, startLevel)
        self.board = board
        self.curses = curses
        self.curseCountAtStart = curses.count
        self.current = current
        self.nextGems = next
        self.score = 0
        self.gemsCleared = 0
        self.phase = .falling
        self.rng = Xoshiro256StarStar(seed: seed)
    }

    // MARK: Eingaben (nur in Phase .falling)

    /// Kapsel eine Spalte nach links. Liefert `true`, wenn der Zug moeglich war.
    public mutating func moveLeft() -> Bool { shift(-1) }

    /// Kapsel eine Spalte nach rechts.
    public mutating func moveRight() -> Bool { shift(1) }

    private mutating func shift(_ dx: Int) -> Bool {
        guard phase == .falling else { return false }
        var moved = current
        moved.col += dx
        guard fits(moved) else { return false }
        current = moved
        return true
    }

    /// Dreht den Satelliten 90° im Uhrzeigersinn um den Pivot — mit demselben einfachen „Kick"
    /// wie im Klumpen-Modus: ist die Zielzelle blockiert, weicht der Pivot um den Gegen-Versatz
    /// aus. Passt auch das nicht, bleibt die Kapsel unveraendert.
    public mutating func rotate() -> Bool {
        guard phase == .falling else { return false }
        var rotated = current
        rotated.orientation = current.orientation.rotatedCW
        if fits(rotated) {
            current = rotated
            return true
        }
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

    /// Kann die Kapsel eine Reihe tiefer? Reine Abfrage (kein Zustand) — fuers Lock-Delay.
    public func canFall() -> Bool {
        guard phase == .falling else { return false }
        var below = current
        below.row -= 1
        return fits(below)
    }

    /// Laesst die Kapsel eine Reihe fallen. Geht das nicht, rastet sie ein und die komplette
    /// Kaskade wird berechnet und als `.locked(result)` zurueckgegeben.
    public mutating func gravityTick() -> CapsuleTick {
        guard phase == .falling else { return .moved }
        var below = current
        below.row -= 1
        if fits(below) {
            current = below
            return .moved
        }
        return .locked(lock())
    }

    /// Rastet die Kapsel ins Brett ein, laesst die Haelften (fluch-bewusst) nachrutschen und
    /// loest die Ketten-Kaskade vollstaendig auf. Faellt dabei der letzte Fluch, ist die Partie
    /// gewonnen (Phase `.won`).
    private mutating func lock() -> CapsuleLock {
        let landed = current
        // Beide Steine ins Brett schreiben; Zellen ueber dem Brett verfallen (wie bei Saeule/Paar).
        for (cell, gem) in landed.cells where cell.row < board.height {
            board[cell.col, cell.row] = gem
        }
        // Brett VOR dem Nachrutschen festhalten (die Render-Schicht animiert das Nachfallen).
        let boardBefore = board
        settle(&board, pinned: curses)

        // Treffer-Kaskade: solange Vierer-Laeufe entstehen, raeumen + nachrutschen lassen.
        var steps: [ClearStep] = []
        var chain = 0
        while true {
            let matches = findLines(board, minRun: CapsuleEngine.runLength)
            if matches.isEmpty { break }
            chain += 1
            let clearedCurses = curses.intersection(matches)
            for cell in matches { board[cell.col, cell.row] = nil }
            curses.subtract(clearedCurses)
            settle(&board, pinned: curses)
            // Punkte wie im Saeulen-Modus, plus fester Bonus je getilgtem Fluch.
            let pts = Engine.points(cleared: matches.count, chain: chain)
                    + clearedCurses.count * CapsuleEngine.curseBonus
            score += pts
            gemsCleared += matches.count
            steps.append(ClearStep(cells: matches, kind: .match, color: nil,
                                   chain: chain, points: pts, boardAfter: board))
        }

        // Sieg-Check: alle Flueche getilgt ⇒ gewonnen (kein weiterer Einwurf).
        phase = curses.isEmpty ? .won : .resolving
        return CapsuleLock(landed: landed, boardBefore: boardBefore, steps: steps)
    }

    /// Wirft die naechste Kapsel ein. Nur nach abgeschlossener Aufloesung aufrufen.
    /// Liefert `false`, wenn kein Einwurf mehr passiert: Einwurf blockiert (→ `.gameOver`)
    /// ODER die Partie ist bereits gewonnen (Phase `.won` — von `lock()` gesetzt).
    @discardableResult
    public mutating func spawnNext() -> Bool {
        guard phase == .resolving else { return phase == .falling }

        if board[spawnColumn, spawnRow] != nil {
            phase = .gameOver
            return false
        }
        current = PairPiece(gems: nextGems, col: spawnColumn, row: spawnRow)
        nextGems = CapsuleEngine.drawPair(&rng)
        phase = .falling
        return true
    }

    // MARK: Hilfen (Kollision, Zufall, Fluch-Vorbefuellung)

    /// Passt die Kapsel an ihre Position? (identische Regel wie im Klumpen-Modus: seitlich im
    /// Feld, nicht unter dem Boden, Zellen im Brett leer; OBERHALB des Bretts gilt als frei).
    private func fits(_ piece: PairPiece) -> Bool {
        for (cell, _) in piece.cells {
            if cell.col < 0 || cell.col >= board.width || cell.row < 0 { return false }
            if cell.row < board.height, board[cell.col, cell.row] != nil { return false }
        }
        return true
    }

    /// Zieht die zwei Farben der naechsten Kapsel (nur aus den drei Modus-Farben, nie Magic).
    static func drawPair(_ rng: inout Xoshiro256StarStar) -> [Gem] {
        (0..<2).map { _ in capsuleColors[Int(rng.next() % UInt64(capsuleColors.count))] }
    }

    /// Wie viele Flueche die Stufe `level` (1–10) auf diesem Brett bekommt: 4 je Stufe,
    /// gedeckelt auf die halbe Kapazitaet des Fluch-Bereichs (unteres Drittel-Paar des Bretts).
    static func curseCount(level: Int, width: Int, height: Int) -> Int {
        min(4 * max(1, level), (width * curseRows(height: height)) / 2)
    }

    /// So viele Reihen von unten duerfen Flueche enthalten (untere ~60 % — darueber bleibt
    /// Rangier-Raum fuer die fallenden Kapseln, wie im Genre-Klassiker).
    static func curseRows(height: Int) -> Int {
        max(1, (height * 3) / 5)
    }

    /// Platziert die Flueche deterministisch aus dem PRNG: zufaellige freie Zellen in den
    /// unteren Reihen, zufaellige der drei Farben — aber NIE so, dass schon zu Partiebeginn
    /// drei gleiche in Reihe/Spalte liegen (sonst raeumte die erste Kapsel Geschenke ab).
    /// Bricht nach einer festen Versuchszahl ab (volles/zaehes Brett) — dann liegen eben
    /// etwas weniger Flueche; `curseCountAtStart` haelt die echte Zahl fest.
    static func placeCurses(_ board: inout Board, level: Int,
                            _ rng: inout Xoshiro256StarStar) -> Set<Cell> {
        let target = curseCount(level: level, width: board.width, height: board.height)
        let rows = curseRows(height: board.height)
        var placed = Set<Cell>()
        var attempts = 0
        while placed.count < target && attempts < target * 40 {
            attempts += 1
            let col = Int(rng.next() % UInt64(board.width))
            let row = Int(rng.next() % UInt64(rows))
            guard board[col, row] == nil else { continue }
            let gem = capsuleColors[Int(rng.next() % UInt64(capsuleColors.count))]
            board[col, row] = gem
            // Probeweise gesetzt: entstuende ein Dreier-Lauf, wieder zuruecknehmen.
            if !findLines(board, minRun: 3).isEmpty {
                board[col, row] = nil
                continue
            }
            placed.insert(Cell(col: col, row: row))
        }
        return placed
    }
}
