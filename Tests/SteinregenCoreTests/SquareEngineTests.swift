import XCTest
@testable import SteinregenCore

/// Tests des sechsten Modus „Schnitter" (fallende 2×2-Bloecke aus zwei Sorten, gleichfarbige
/// 2×2-Quadrate werden markiert und von der tick-basierten Sense geerntet). Die Tests der
/// anderen Engines bleiben unberuehrt — alle Engines sind unabhaengig.
final class SquareEngineTests: XCTestCase {

    /// Kurzform: leeres 12×12-Brett (Standard-Maße des Modus).
    private func emptyBoard() -> Board { Board(width: 12, height: 12) }

    /// Kurzform: Engine mit gegebenem Brett und neutralem (gemischtem) aktiven Block weit oben.
    private func engine(_ board: Board) -> SquareEngine {
        SquareEngine(board: board,
                     current: SquarePiece(gems: [.ruby, .diamond, .ruby, .diamond], col: 5, row: 11),
                     next: [.ruby, .ruby, .diamond, .diamond])
    }

    // MARK: - Drehen (Farben rotieren, Form bleibt)

    func testRotationCyclesColors() {
        // [bl, br, tr, tl] — CW-Drehung: bl←br, br←tr, tr←tl, tl←bl. Vier Drehungen = Ausgang.
        var piece = SquarePiece(gems: [.ruby, .diamond, .diamond, .ruby], col: 5, row: 5)
        let original = piece.gems
        piece.rotateCW()
        XCTAssertEqual(piece.gems, [.diamond, .diamond, .ruby, .ruby])
        piece.rotateCW(); piece.rotateCW(); piece.rotateCW()
        XCTAssertEqual(piece.gems, original, "vier Drehungen ergeben den Ausgangszustand")
    }

    func testRotationAlwaysSucceedsWhileFalling() {
        var e = engine(emptyBoard())
        XCTAssertTrue(e.rotate(), "die Form aendert sich nicht — Drehen kann nie kollidieren")
    }

    // MARK: - Markierung (gleichfarbige 2×2-Quadrate)

    func testSquareOfFourIsMarked() {
        var b = emptyBoard()
        b[0, 0] = .ruby; b[1, 0] = .ruby; b[0, 1] = .ruby; b[1, 1] = .ruby
        let e = engine(b)
        XCTAssertEqual(e.marked, [Cell(col: 0, row: 0), Cell(col: 1, row: 0),
                                  Cell(col: 0, row: 1), Cell(col: 1, row: 1)])
    }

    func testOverlappingSquaresMarkAllSixCells() {
        // Ein 3×2-Block einer Farbe = zwei ueberlappende Quadrate → alle sechs Zellen markiert.
        var b = emptyBoard()
        for col in 0..<3 { b[col, 0] = .diamond; b[col, 1] = .diamond }
        XCTAssertEqual(engine(b).marked.count, 6)
    }

    func testMixedColorsAreNotMarked() {
        // Schachbrett aus beiden Sorten: kein gleichfarbiges Quadrat → nichts markiert.
        var b = emptyBoard()
        b[0, 0] = .ruby; b[1, 0] = .diamond; b[0, 1] = .diamond; b[1, 1] = .ruby
        XCTAssertTrue(engine(b).marked.isEmpty)
    }

    // MARK: - Aufsetzen: Spalten zerfallen unabhaengig, kein Raeumen

    func testColumnsSettleIndependentlyOnLock() {
        // Unter der linken Blockspalte ein Turm aus 2 Steinen, rechts nichts: Beim Aufsetzen
        // faellt die rechte Blockspalte allein bis zum Boden durch.
        var b = emptyBoard()
        b[5, 0] = .ruby; b[5, 1] = .diamond
        var e = SquareEngine(board: b,
                             current: SquarePiece(gems: [.diamond, .ruby, .diamond, .ruby], col: 5, row: 2),
                             next: [.ruby, .ruby, .ruby, .ruby])
        guard case let .locked(result) = e.gravityTick() else {
            return XCTFail("Block haette aufsetzen muessen (liegt auf dem Turm)")
        }
        // Vorher: alle vier an der Aufsetz-Position (Reihen 2/3).
        XCTAssertEqual(result.boardBefore[6, 2], .ruby)
        XCTAssertEqual(result.boardBefore[6, 3], .diamond)
        // Nachher: die rechte Blockspalte (unten ruby, oben diamond) ist zum Boden durchgefallen,
        // die linke liegt unveraendert auf dem Turm.
        XCTAssertEqual(e.board[6, 0], .ruby)
        XCTAssertEqual(e.board[6, 1], .diamond)
        XCTAssertNil(e.board[6, 2])
        XCTAssertEqual(e.board[5, 2], .diamond)
        XCTAssertEqual(e.phase, .resolving, "kein Raeumen beim Aufsetzen — nur Einrasten")
    }

    func testLockNeverClears() {
        // Selbst ein perfekt gleichfarbiger Block raeumt beim Aufsetzen NICHTS — er wird nur
        // markiert und wartet auf die Sense.
        var e = SquareEngine(board: emptyBoard(),
                             current: SquarePiece(gems: [.ruby, .ruby, .ruby, .ruby], col: 0, row: 0),
                             next: [.diamond, .diamond, .diamond, .diamond])
        guard case .locked = e.gravityTick() else { return XCTFail("haette aufsetzen muessen") }
        XCTAssertEqual(e.board.filledCount, 4, "alle vier Steine liegen noch")
        XCTAssertEqual(e.score, 0)
        XCTAssertEqual(e.marked.count, 4, "aber sie sind markiert — die Sense erntet spaeter")
    }

    // MARK: - Sense (Sweep-Linie)

    func testSweepHarvestsMarkedSectionWhenLeavingIt() {
        // Quadrat bei Spalten 2–3: Die Sense (Start Spalte 0) erntet es genau beim Tick, der
        // sie von Spalte 3 auf Spalte 4 traegt (Sektion verlassen) — nicht frueher.
        var b = emptyBoard()
        b[2, 0] = .ruby; b[3, 0] = .ruby; b[2, 1] = .ruby; b[3, 1] = .ruby
        var e = engine(b)

        XCTAssertNil(e.sweepTick(), "0→1: nichts zu ernten")   // sweepCol 1
        XCTAssertNil(e.sweepTick(), "1→2: Sektion betreten")   // sweepCol 2
        XCTAssertNil(e.sweepTick(), "2→3: noch in der Sektion")  // sweepCol 3
        let step = e.sweepTick()                                 // 3→4: Sektion verlassen → Ernte
        XCTAssertNotNil(step)
        XCTAssertEqual(Set(step!.cells), [Cell(col: 2, row: 0), Cell(col: 3, row: 0),
                                          Cell(col: 2, row: 1), Cell(col: 3, row: 1)])
        XCTAssertEqual(e.score, 40, "4 Steine × 10 × Welle 1")
        XCTAssertEqual(e.gemsCleared, 4)
        XCTAssertEqual(e.board.filledCount, 0)
        XCTAssertTrue(e.marked.isEmpty)
    }

    func testSweepDoesNothingOnEmptyBoard() {
        var e = engine(emptyBoard())
        for _ in 0..<30 { XCTAssertNil(e.sweepTick()) }
        XCTAssertEqual(e.score, 0)
    }

    func testSweepHarvestsSectionAtRightEdgeOnWrap() {
        // Quadrat am RECHTEN Rand (Spalten 10–11): geerntet beim Umbruch-Tick (11 → 0) —
        // das Brett-Ende beendet jede Sektion.
        var b = emptyBoard()
        b[10, 0] = .diamond; b[11, 0] = .diamond; b[10, 1] = .diamond; b[11, 1] = .diamond
        var e = engine(b)
        var harvested: ClearStep?
        for _ in 0..<12 {                      // genau eine volle Runde: 0→1, …, 11→0
            if let s = e.sweepTick() { harvested = s }
        }
        XCTAssertNotNil(harvested)
        XCTAssertEqual(harvested!.cells.count, 4)
        XCTAssertEqual(e.sweepCol, 0, "nach zwoelf Ticks ist die Sense wieder am Anfang")
        XCTAssertEqual(e.board.filledCount, 0)
    }

    func testStonesAboveHarvestFallDown() {
        // Ueber dem markierten Quadrat (Spalten 2–3, Reihen 0–1) liegt ein gemischtes Paar
        // (Reihe 2): Nach der Ernte rutscht es auf den Boden — und bildet KEIN neues Quadrat.
        var b = emptyBoard()
        b[2, 0] = .ruby; b[3, 0] = .ruby; b[2, 1] = .ruby; b[3, 1] = .ruby
        b[2, 2] = .diamond; b[3, 2] = .ruby
        var e = engine(b)
        var step: ClearStep?
        for _ in 0..<6 { if let s = e.sweepTick() { step = s } }
        XCTAssertNotNil(step)
        XCTAssertEqual(step!.cells.count, 4, "nur das Quadrat wird geerntet, nicht die Steine darueber")
        XCTAssertEqual(e.board[2, 0], .diamond, "der Rest ist auf den Boden gefallen")
        XCTAssertEqual(e.board[3, 0], .ruby)
        XCTAssertEqual(e.board.filledCount, 2)
        XCTAssertTrue(e.marked.isEmpty)
    }

    func testMarksRecomputedAfterHarvestCanFormNewSquare() {
        // Nach der Ernte faellt ein gleichfarbiges Paar herab und bildet mit dem Boden-Paar
        // ein NEUES Quadrat → es wird frisch markiert (geerntet aber erst in der naechsten
        // Runde — keine Ketten-Kaskade wie bei den Saeulen).
        var b = emptyBoard()
        // Markiertes rotes Quadrat (Spalten 2–3, Reihen 1–2); darunter am Boden zwei Diamanten,
        // darueber zwei Diamanten — nach der Ernte entsteht ein Diamant-Quadrat in Reihen 0–1.
        b[2, 0] = .diamond; b[3, 0] = .diamond
        b[2, 1] = .ruby;    b[3, 1] = .ruby
        b[2, 2] = .ruby;    b[3, 2] = .ruby
        b[2, 3] = .diamond; b[3, 3] = .diamond
        var e = engine(b)
        // Achtung: Auch das rote Quadrat ist anfangs markiert — die Diamant-Paare oben/unten
        // gehoeren zu KEINEM Quadrat (nur je eine Reihe hoch).
        XCTAssertEqual(e.marked.count, 4)
        var step: ClearStep?
        for _ in 0..<6 { if let s = e.sweepTick() { step = s } }
        XCTAssertNotNil(step)
        XCTAssertEqual(step!.cells.count, 4, "nur die roten Zellen werden geerntet")
        // Die Diamanten sind zusammengerutscht (Reihen 0–1) und bilden ein frisch markiertes Quadrat.
        XCTAssertEqual(e.board.filledCount, 4)
        XCTAssertEqual(e.marked.count, 4)
        XCTAssertEqual(e.board[2, 0], .diamond)
        XCTAssertEqual(e.board[2, 1], .diamond)
    }

    // MARK: - Game Over

    func testGameOverWhenSpawnBlocked() {
        // Die beiden Einwurf-Spalten (5+6 bei Breite 12) bis oben fuellen — SCHACHBRETT-Muster,
        // damit nichts markiert ist. Ein harmloser Block am Rand bringt die Engine in
        // .resolving, danach scheitert der Einwurf.
        var b = emptyBoard()
        for row in 0..<12 {
            b[5, row] = (row % 2 == 0) ? .ruby : .diamond
            b[6, row] = (row % 2 == 0) ? .diamond : .ruby
        }
        var e = SquareEngine(board: b,
                             current: SquarePiece(gems: [.ruby, .diamond, .ruby, .diamond], col: 0, row: 0),
                             next: [.ruby, .ruby, .ruby, .ruby])
        XCTAssertTrue(e.marked.isEmpty, "Schachbrett darf nichts markieren")
        guard case .locked = e.gravityTick() else { return XCTFail("haette aufsetzen muessen") }
        XCTAssertFalse(e.spawnNext(), "Einwurf blockiert → Spiel vorbei")
        XCTAssertEqual(e.phase, .gameOver)
        XCTAssertNil(e.sweepTick(), "nach dem Ende erntet die Sense nicht mehr")
    }

    // MARK: - Determinismus + Farbumfang

    /// Spielt `count` Bloecke mittig per Dauer-Tick (inkl. Sense-Ticks) und liefert die
    /// gezogenen Farben in Reihenfolge.
    private func playColors(seed: UInt64, count: Int) -> [Gem] {
        var e = SquareEngine(seed: seed, startLevel: 0, width: 12, height: 24)
        var colors: [Gem] = []
        var safety = 100_000
        while colors.count / 4 < count, e.phase == .falling, safety > 0 {
            safety -= 1
            colors.append(contentsOf: e.current.gems)
            drop: while true {
                _ = e.sweepTick()          // Sense laeuft nebenher (fester Tick je Fall-Schritt)
                switch e.gravityTick() {
                case .moved: continue
                case .locked: break drop
                }
            }
            e.spawnNext()
        }
        return colors
    }

    func testDeterministicSequence() {
        XCTAssertEqual(playColors(seed: 0xFEED, count: 20), playColors(seed: 0xFEED, count: 20))
    }

    func testDifferentSeedsDiffer() {
        XCTAssertNotEqual(playColors(seed: 3, count: 14), playColors(seed: 4, count: 14))
    }

    func testOnlyTwoColorsAreDrawn() {
        let allowed = Set(SquareEngine.blockColors)
        XCTAssertEqual(allowed.count, 2)
        for gem in playColors(seed: 99, count: 30) {
            XCTAssertTrue(allowed.contains(gem), "\(gem) gehoert nicht zu den zwei Modus-Sorten")
        }
    }
}
