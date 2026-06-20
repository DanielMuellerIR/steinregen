import XCTest
@testable import SteinregenCore

final class EngineTests: XCTestCase {

    // Kleiner Helfer: Brett-Zelle setzen.
    private func board(_ fill: (inout Board) -> Void) -> Board {
        var b = Board()
        fill(&b)
        return b
    }

    // MARK: - Treffer-Erkennung (findMatches)

    func testMatchHorizontal() {
        let b = board { b in
            b[0, 0] = .ruby; b[1, 0] = .ruby; b[2, 0] = .ruby
        }
        XCTAssertEqual(Set(findMatches(b)),
                       [Cell(col: 0, row: 0), Cell(col: 1, row: 0), Cell(col: 2, row: 0)])
    }

    func testMatchVertical() {
        let b = board { b in
            b[1, 0] = .emerald; b[1, 1] = .emerald; b[1, 2] = .emerald
        }
        XCTAssertEqual(Set(findMatches(b)),
                       [Cell(col: 1, row: 0), Cell(col: 1, row: 1), Cell(col: 1, row: 2)])
    }

    func testMatchDiagonalRising() {
        // ↗-Diagonale
        let b = board { b in
            b[0, 0] = .sapphire; b[1, 1] = .sapphire; b[2, 2] = .sapphire
        }
        XCTAssertEqual(Set(findMatches(b)),
                       [Cell(col: 0, row: 0), Cell(col: 1, row: 1), Cell(col: 2, row: 2)])
    }

    func testMatchDiagonalFalling() {
        // ↘-Diagonale
        let b = board { b in
            b[0, 2] = .topaz; b[1, 1] = .topaz; b[2, 0] = .topaz
        }
        XCTAssertEqual(Set(findMatches(b)),
                       [Cell(col: 0, row: 2), Cell(col: 1, row: 1), Cell(col: 2, row: 0)])
    }

    func testNoMatchForTwo() {
        let b = board { b in
            b[0, 0] = .ruby; b[1, 0] = .ruby
        }
        XCTAssertTrue(findMatches(b).isEmpty)
    }

    func testMagicNeverMatches() {
        let b = board { b in
            b[0, 0] = .magic; b[1, 0] = .magic; b[2, 0] = .magic
        }
        XCTAssertTrue(findMatches(b).isEmpty)
    }

    // MARK: - Nachrutschen (settle)

    func testSettleCompactsColumns() {
        var b = board { b in
            b[0, 0] = .ruby      // unten
            b[0, 2] = .emerald   // schwebt mit Luecke darunter
        }
        settle(&b)
        XCTAssertEqual(b[0, 0], .ruby)
        XCTAssertEqual(b[0, 1], .emerald)
        XCTAssertNil(b[0, 2])
    }

    // MARK: - Kaskade (Kettenreaktion)

    func testCascadeTwoChains() {
        // Aufbau so, dass das Aufsetzen erst eine horizontale Dreierreihe (Rubine) raeumt,
        // und das Nachrutschen DANACH eine vertikale Dreierreihe (Smaragde) bildet.
        let b = board { b in
            // col0: Smaragd, Rubin, Smaragd, Smaragd  (vertikal noch KEIN Treffer)
            b[0, 0] = .emerald; b[0, 1] = .ruby; b[0, 2] = .emerald; b[0, 3] = .emerald
            // col1: Saphir, Rubin
            b[1, 0] = .sapphire; b[1, 1] = .ruby
            // col2: Saphir (die Magic-/Test-Saeule setzt darauf auf)
            b[2, 0] = .sapphire
        }
        // Saeule [Rubin, Topas, Saphir] setzt in col2 direkt auf den Saphir (row 1) auf.
        let piece = Piece(gems: [.ruby, .topaz, .sapphire], col: 2, row: 1)
        var engine = Engine(board: b, current: piece, next: [.ruby, .ruby, .ruby])

        guard case let .locked(result) = engine.gravityTick() else {
            return XCTFail("Saeule haette aufsetzen muessen")
        }
        XCTAssertEqual(result.steps.count, 2, "zwei Wellen erwartet")
        XCTAssertEqual(result.steps[0].chain, 1)
        XCTAssertEqual(result.steps[1].chain, 2)
        // Welle 1: drei Rubine auf Reihe 1.
        XCTAssertEqual(Set(result.steps[0].cells),
                       [Cell(col: 0, row: 1), Cell(col: 1, row: 1), Cell(col: 2, row: 1)])
        // Welle 2: drei Smaragde vertikal in col0.
        XCTAssertEqual(Set(result.steps[1].cells),
                       [Cell(col: 0, row: 0), Cell(col: 0, row: 1), Cell(col: 0, row: 2)])
        // Punkte: 3·10·1 + 3·10·2 = 90; sechs Steine geraeumt.
        XCTAssertEqual(engine.score, 90)
        XCTAssertEqual(engine.gemsCleared, 6)
        XCTAssertEqual(engine.phase, .resolving)
    }

    // MARK: - Magic Jewel

    func testMagicJewelClearsColorBoardWide() {
        let b = board { b in
            b[0, 0] = .ruby        // wird vom Magic getroffen
            b[1, 0] = .emerald
            b[3, 0] = .ruby        // weit weg, soll aber auch verschwinden
            b[3, 1] = .sapphire
        }
        // Magic-Saeule setzt in col0 auf den Rubin auf (untester Magic auf row 1, darunter Rubin).
        let piece = Piece(gems: [.magic, .magic, .magic], col: 0, row: 1)
        var engine = Engine(board: b, current: piece, next: [.ruby, .ruby, .ruby])

        guard case let .locked(result) = engine.gravityTick() else {
            return XCTFail("Magic-Saeule haette aufsetzen muessen")
        }
        XCTAssertTrue(result.wasMagic)
        XCTAssertEqual(result.steps.count, 1)
        XCTAssertEqual(result.steps[0].kind, .magic)
        XCTAssertEqual(result.steps[0].color, .ruby)
        XCTAssertEqual(Set(result.steps[0].cells),
                       [Cell(col: 0, row: 0), Cell(col: 3, row: 0)])
        // Keine Rubine mehr im Brett; Magic-Steine landen nie im Brett.
        XCTAssertTrue(engine.board.cells(of: .ruby).isEmpty)
        XCTAssertTrue(engine.board.cells(of: .magic).isEmpty)
        // Saphir aus col3 ist nachgerutscht.
        XCTAssertEqual(engine.board[3, 0], .sapphire)
        XCTAssertEqual(engine.gemsCleared, 2)
        XCTAssertEqual(engine.score, 20)
    }

    func testMagicJewelOnEmptyFloorFizzles() {
        let piece = Piece(gems: [.magic, .magic, .magic], col: 0, row: 0)
        var engine = Engine(board: Board(), current: piece, next: [.ruby, .ruby, .ruby])

        guard case let .locked(result) = engine.gravityTick() else {
            return XCTFail("Magic-Saeule haette aufsetzen muessen")
        }
        XCTAssertTrue(result.wasMagic)
        XCTAssertTrue(result.steps.isEmpty)
        XCTAssertEqual(engine.score, 0)
        XCTAssertEqual(engine.board.filledCount, 0)
    }

    // MARK: - Game Over

    func testGameOverWhenSpawnColumnFull() {
        // Einwurf-Spalte komplett (ohne Treffer) fuellen.
        let b = board { b in
            for r in 0..<Board.height {
                b[Engine.spawnColumn, r] = Gem.colors[r % Gem.colors.count]
            }
        }
        // Harmlose Saeule in col0 aufsetzen, um in die Phase .resolving zu kommen.
        let piece = Piece(gems: [.ruby, .emerald, .sapphire], col: 0, row: 0)
        var engine = Engine(board: b, current: piece, next: [.topaz, .topaz, .topaz])

        guard case .locked = engine.gravityTick() else {
            return XCTFail("Saeule haette aufsetzen muessen")
        }
        XCTAssertFalse(engine.spawnNext(), "Einwurf blockiert → Spiel vorbei")
        XCTAssertEqual(engine.phase, .gameOver)
    }

    // MARK: - Bewegung & Drehung

    func testRotateCyclesGems() {
        var engine = Engine(board: Board(),
                            current: Piece(gems: [.ruby, .topaz, .emerald], col: 3, row: 5),
                            next: [.ruby, .ruby, .ruby])
        XCTAssertTrue(engine.rotate())
        // Jeder Stein rueckt eine Position hoch, der oberste nach unten.
        XCTAssertEqual(engine.current.gems, [.emerald, .ruby, .topaz])
    }

    func testMoveBlockedByOccupiedColumn() {
        let b = board { b in b[2, 5] = .ruby }   // blockiert linke Spalte auf Hoehe der Saeule
        var engine = Engine(board: b,
                            current: Piece(gems: [.ruby, .topaz, .emerald], col: 3, row: 5),
                            next: [.ruby, .ruby, .ruby])
        XCTAssertFalse(engine.moveLeft(), "Zielspalte auf Saeulenhoehe belegt → kein Zug")
        XCTAssertEqual(engine.current.col, 3)
        XCTAssertTrue(engine.moveRight())
        XCTAssertEqual(engine.current.col, 4)
    }

    // MARK: - Determinismus

    /// Spielt ohne Eingaben (Saeulen fallen mittig) eine feste Zahl Schritte und liefert die Engine.
    private func playScripted(seed: UInt64, locks: Int) -> Engine {
        var engine = Engine(seed: seed, startLevel: 0)
        var done = 0
        // Sicherheitsobergrenze gegen Endlosschleifen.
        var safety = 100_000
        while done < locks, engine.phase != .gameOver, safety > 0 {
            safety -= 1
            switch engine.gravityTick() {
            case .moved:
                continue
            case .locked:
                engine.spawnNext()
                done += 1
            }
        }
        return engine
    }

    func testDeterminismSameSeed() {
        let a = playScripted(seed: 0xC0FFEE, locks: 40)
        let b = playScripted(seed: 0xC0FFEE, locks: 40)
        XCTAssertEqual(a.board, b.board)
        XCTAssertEqual(a.score, b.score)
        XCTAssertEqual(a.gemsCleared, b.gemsCleared)
        XCTAssertEqual(a.level, b.level)
        XCTAssertEqual(a.phase, b.phase)
        XCTAssertEqual(a.nextGems, b.nextGems)
    }

    func testDifferentSeedsDiffer() {
        // Die ersten gezogenen Saeulen zweier verschiedener Seeds sollten sich unterscheiden.
        var ra = Xoshiro256StarStar(seed: 1)
        var rb = Xoshiro256StarStar(seed: 2)
        var differs = false
        for _ in 0..<20 where Engine.drawColumn(&ra) != Engine.drawColumn(&rb) {
            differs = true
        }
        XCTAssertTrue(differs)
    }
}
