// Engine.swift
// Die deterministische Spiel-Engine von Steinregen (Columns-Klon).
//
// Determinismus-Regel (CLAUDE.md): KEIN globaler Zufall, KEINE Wanduhr. Aller Zufall
// (Farbfolge der Saeulen, Auftauchen des Magic Jewels) laeuft ueber den injizierten,
// seed-bestimmten `Xoshiro256StarStar`. Gleicher Seed + gleiche Eingaben ⇒ gleicher Verlauf.
//
// Ablauf einer Runde aus Sicht der App-/Render-Schicht:
//   1. Wiederholt `gravityTick()` im Takt der Fallgeschwindigkeit (oder schneller bei Softdrop).
//   2. Liefert ein Tick `.locked(result)`, ist die Saeule aufgesetzt und die komplette Kaskade
//      bereits berechnet (Brett, Punkte, Level sind final). Phase = `.resolving`.
//   3. Render animiert `result.steps`; danach ruft die App `spawnNext()` auf
//      → neue Saeule (Phase `.falling`) oder `.gameOver`, falls der Einwurf blockiert ist.

public struct Engine: Sendable {

    // MARK: Konstanten

    /// Magic-Jewel-Haeufigkeit: im Schnitt 1 von `magicOdds` gezogenen Saeulen.
    /// (Level-Takt und Punktwertung liegen modusuebergreifend in `Scoring`.)
    public static let magicOdds: UInt64 = 40

    /// Mittlere Spalte, in der jede neue Saeule erscheint — haengt von der Brettbreite ab.
    public var spawnColumn: Int { board.width / 2 }
    /// Reihe des untersten Steins beim Einwurf (oberste Brettreihe). Die Saeule schwebt von oben
    /// ein: nur der unterste Stein steht anfangs in der obersten Brettreihe, die beiden oberen
    /// Segmente liegen noch UEBER dem Brett (Reihen >= board.height, dort als frei behandelt) und
    /// werden von der Render-Schicht ausgeblendet, bis sie beim Fallen Reihe fuer Reihe ins Feld
    /// rutschen.
    public var spawnRow: Int { board.height - 1 }

    // MARK: Zustand (von aussen nur lesbar)

    public private(set) var board: Board
    public private(set) var current: Piece
    /// Vorschau auf die naechste Saeule.
    public private(set) var nextGems: [Gem]
    public private(set) var score: Int
    public private(set) var gemsCleared: Int
    public let startLevel: Int
    public private(set) var phase: Phase
    public let seed: UInt64

    private var rng: Xoshiro256StarStar

    /// Aktuelles Level: steigt mit der Zahl geraeumter Steine, beginnend bei `startLevel`.
    public var level: Int { startLevel + gemsCleared / Scoring.gemsPerLevel }

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
        // Die allererste aktive Saeule ist nie ein Magic Jewel (auf leerem Brett verpufft er) —
        // die Vorschau darf dagegen schon ein Magic Jewel sein.
        let first = Engine.drawColors(&r)
        self.nextGems = Engine.drawColumn(&r)
        self.rng = r
        // spawnColumn/spawnRow sind berechnete Eigenschaften (brauchen `board`); hier direkt aus
        // den Brettmaßen, weil im Initializer noch nicht alle gespeicherten Felder gesetzt sind.
        self.current = Piece(gems: first, col: width / 2, row: height - 1)
    }

    /// Test-Initialisierer: setzt Brett und Saeulen direkt (nur via `@testable import`).
    init(board: Board, current: Piece, next: [Gem], seed: UInt64 = 1, startLevel: Int = 0) {
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

    /// Saeule eine Spalte nach links. Liefert `true`, wenn der Zug moeglich war.
    public mutating func moveLeft() -> Bool { move(to: current.col - 1) }

    /// Saeule eine Spalte nach rechts.
    public mutating func moveRight() -> Bool { move(to: current.col + 1) }

    private mutating func move(to newCol: Int) -> Bool {
        guard phase == .falling else { return false }
        guard newCol >= 0, newCol < board.width else { return false }
        // Alle drei Zielzellen muessen frei sein (oberhalb des Bretts gilt als frei).
        for i in 0..<3 {
            let r = current.row + i
            if r < board.height, board[newCol, r] != nil { return false }
        }
        current.col = newCol
        return true
    }

    /// Dreht die Saeule: jeder Stein rueckt eine Position nach oben, der oberste wandert nach unten.
    public mutating func rotate() -> Bool {
        guard phase == .falling else { return false }
        current.gems = [current.gems[2], current.gems[0], current.gems[1]]
        return true
    }

    // MARK: Schwerkraft / Aufsetzen

    /// Kann die aktive Saeule eine Reihe tiefer? Reine Abfrage (kein Zustand, kein Zufall) —
    /// die Render-Schicht nutzt sie fuer das Lock-Delay (kurzes Korrektur-Fenster vor dem Aufsetzen).
    public func canFall() -> Bool {
        guard phase == .falling else { return false }
        let below = current.row - 1
        return below >= 0 && board[current.col, below] == nil
    }

    /// Laesst die aktive Saeule eine Reihe fallen. Kann sie nicht weiter, setzt sie auf,
    /// berechnet die komplette Kaskade und liefert sie als `.locked(result)` zurueck.
    public mutating func gravityTick() -> TickOutcome {
        guard phase == .falling else { return .moved }
        let below = current.row - 1
        if below >= 0, board[current.col, below] == nil {
            current.row -= 1
            return .moved
        }
        return .locked(lock())
    }

    /// Setzt die aktuelle Saeule auf und loest Magic-Effekt + Treffer-Kaskade vollstaendig auf.
    private mutating func lock() -> LockResult {
        let landed = current
        let wasMagic = landed.isMagic
        var steps: [ClearStep] = []
        var chain = 0
        let boardBefore: Board

        if wasMagic {
            // Magic-Steine kommen NICHT ins Brett. Sie raeumen die Farbe der Zelle direkt unter
            // dem untersten Magic-Stein brettweit weg. Liegt darunter nichts, verpufft der Effekt.
            boardBefore = board
            let belowRow = landed.row - 1
            if belowRow >= 0, let target = board[landed.col, belowRow], !target.isMagic {
                let cells = board.cells(of: target)
                chain += 1
                for cell in cells { board[cell.col, cell.row] = nil }
                settle(&board)
                let pts = Scoring.points(cleared: cells.count, chain: chain)
                score += pts
                gemsCleared += cells.count
                steps.append(ClearStep(cells: cells, kind: .magic, color: target,
                                       chain: chain, points: pts, boardAfter: board))
            }
        } else {
            // Normale Saeule ins Brett schreiben.
            for i in 0..<3 {
                let r = landed.row + i
                if r < board.height { board[landed.col, r] = landed.gems[i] }
            }
            boardBefore = board
        }

        // Treffer-Kaskade (geteilte Schleife in Matching.swift): solange Drillinge entstehen,
        // raeumen + nachrutschen lassen. `startChain` setzt hinter dem Magic-Effekt fort.
        steps += resolveCascade(&board, startChain: chain,
                                find: { findMatches($0) },
                                settleBoard: { settle(&$0) },
                                score: &score, gemsCleared: &gemsCleared)

        phase = .resolving
        return LockResult(landed: landed, wasMagic: wasMagic, boardBefore: boardBefore, steps: steps)
    }

    /// Wirft die naechste Saeule ein. Nur nach abgeschlossener Aufloesung aufrufen.
    /// Liefert `false`, wenn der Einwurf blockiert ist → Spiel vorbei.
    @discardableResult
    public mutating func spawnNext() -> Bool {
        guard phase == .resolving else { return phase != .gameOver }

        // Einwurf blockiert? (mittlere Spalte oben belegt)
        for i in 0..<3 {
            let r = spawnRow + i
            if r < board.height, board[spawnColumn, r] != nil {
                phase = .gameOver
                return false
            }
        }

        current = Piece(gems: nextGems, col: spawnColumn, row: spawnRow)
        nextGems = Engine.drawColumn(&rng)
        phase = .falling
        return true
    }

    // MARK: Zufall (statisch, rein — Punktwertung liegt in `Scoring`)

    /// Zieht drei normale Farben (nie Magic) — ueber den geteilten Zieh-Baustein `draw`.
    static func drawColors(_ rng: inout Xoshiro256StarStar) -> [Gem] {
        draw(3, from: Gem.colors, using: &rng)
    }

    /// Zieht eine Saeule; mit Wahrscheinlichkeit 1/`magicOdds` ein Magic Jewel (drei Magic-Steine).
    static func drawColumn(_ rng: inout Xoshiro256StarStar) -> [Gem] {
        if rng.next() % magicOdds == 0 {
            return [.magic, .magic, .magic]
        }
        return drawColors(&rng)
    }
}
