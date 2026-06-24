import XCTest
@testable import SteinregenCore

/// Tests des zweiten Modus „Verschuettet" (Vierlinge + volle-Reihen-Raeumen). Die Columns-Tests
/// in `EngineTests` bleiben unberuehrt — beide Engines sind unabhaengig.
final class TetrominoEngineTests: XCTestCase {

    // MARK: - Form & Drehung (rein geometrisch)

    func testEachTypeHasFourDistinctCells() {
        for type in TetrominoType.allCases {
            let t = Tetromino(type: type, col: 0, row: 0)
            XCTAssertEqual(t.offsets.count, 4, "\(type) sollte vier Zellen haben")
            XCTAssertEqual(Set(t.offsets).count, 4, "\(type) Zellen muessen verschieden sein")
        }
    }

    func testTRotationPointUpToPointRight() {
        let t = Tetromino(type: .t, col: 0, row: 0)
        XCTAssertEqual(Set(t.offsets),
                       [Cell(col: 0, row: 1), Cell(col: 1, row: 1), Cell(col: 2, row: 1), Cell(col: 1, row: 2)])
        // 90° im Uhrzeigersinn → Spitze nach rechts.
        XCTAssertEqual(Set(t.rotatedOffsets()),
                       [Cell(col: 1, row: 0), Cell(col: 1, row: 1), Cell(col: 1, row: 2), Cell(col: 2, row: 1)])
    }

    func testOPieceIsRotationInvariant() {
        let o = Tetromino(type: .o, col: 0, row: 0)
        XCTAssertEqual(Set(o.rotatedOffsets()), Set(o.offsets))
    }

    func testFourRotationsReturnToStart() {
        for type in TetrominoType.allCases {
            var t = Tetromino(type: type, col: 0, row: 0)
            let start = Set(t.offsets)
            for _ in 0..<4 { t.offsets = t.rotatedOffsets() }
            XCTAssertEqual(Set(t.offsets), start, "\(type): 4× Drehen muss Ausgangslage ergeben")
        }
    }

    // MARK: - Spawn & Maße

    func testDefaultBoardIsTenByEighteen() {
        let e = TetrominoEngine(seed: 1)
        XCTAssertEqual(e.board.width, 10)
        XCTAssertEqual(e.board.height, 18)
        // Vierling sitzt mittig oben und vollstaendig im Brett.
        for cell in e.current.boardCells() {
            XCTAssertTrue(e.board.inBounds(col: cell.col, row: cell.row))
        }
    }

    // MARK: - Volle Reihe raeumen

    func testFullRowClearsAndBlocksDrop() {
        // Untere Reihe bis auf die Spalten 0/1 voll; ein O-Block fuellt die Luecke → Reihe 0 raeumt.
        var b = Board(width: 10, height: 18)
        for col in 2..<10 { b[col, 0] = .ruby }
        let o = Tetromino(type: .o, col: 0, row: 0)        // belegt (0,0),(1,0),(0,1),(1,1)
        var e = TetrominoEngine(board: b, current: o, next: .t)

        guard case let .locked(result) = e.gravityTick() else {
            return XCTFail("O-Block haette aufsetzen muessen (sitzt am Boden)")
        }
        XCTAssertEqual(result.steps.count, 1, "genau eine Raeum-Welle")
        XCTAssertEqual(result.steps[0].cells.count, 10, "die ganze Reihe 0 (10 Zellen) verschwindet")
        // 1 Reihe × 100 × Level(0→min 1) = 100.
        XCTAssertEqual(e.score, 100)
        XCTAssertEqual(e.linesCleared, 1)
        // Die zwei oberen O-Steine sind auf Reihe 0 nachgerutscht; sonst ist das Brett leer.
        XCTAssertEqual(e.board[0, 0], TetrominoType.o.gem)
        XCTAssertEqual(e.board[1, 0], TetrominoType.o.gem)
        XCTAssertNil(e.board[2, 0])
        XCTAssertEqual(e.board.filledCount, 2)
    }

    func testNoClearKeepsBlocks() {
        let o = Tetromino(type: .o, col: 0, row: 0)
        var e = TetrominoEngine(board: Board(width: 10, height: 18), current: o, next: .t)
        guard case let .locked(result) = e.gravityTick() else {
            return XCTFail("O-Block haette aufsetzen muessen")
        }
        XCTAssertTrue(result.steps.isEmpty, "keine volle Reihe → keine Welle")
        XCTAssertEqual(e.score, 0)
        XCTAssertEqual(e.board.filledCount, 4, "die vier O-Steine bleiben liegen")
    }

    func testFourLinesScoreMost() {
        // „Vierfach": vier untere Reihen bis auf Spalte 9 voll, ein vertikaler I-Stein fuellt sie.
        var b = Board(width: 10, height: 18)
        for row in 0..<4 { for col in 0..<9 { b[col, row] = .emerald } }
        // I vertikal in Spalte 9: aus dem Spawn 1× drehen ergibt eine senkrechte Linie in Box-Spalte 2.
        var i = Tetromino(type: .i, col: 7, row: 0)        // Box-Spalte 2 liegt damit auf Brett-Spalte 9
        i.offsets = i.rotatedOffsets()                     // senkrecht: (2,0),(2,1),(2,2),(2,3)
        var e = TetrominoEngine(board: b, current: i, next: .t)

        guard case let .locked(result) = e.gravityTick() else {
            return XCTFail("I-Stein haette aufsetzen muessen")
        }
        XCTAssertEqual(result.steps.count, 1)
        XCTAssertEqual(result.steps[0].cells.count, 40, "vier volle Reihen = 40 Zellen")
        XCTAssertEqual(e.linesCleared, 4)
        XCTAssertEqual(e.score, 800)                       // 4 Reihen × 800 × Level(min 1)
        XCTAssertEqual(e.board.filledCount, 0)
    }

    // MARK: - Game Over

    func testGameOverWhenSpawnBlocked() {
        // Spawn-Zellen der naechsten Form (.t) vorab belegen; ein harmloser Block bringt die Engine
        // in die Phase .resolving, danach scheitert der Einwurf.
        var b = Board(width: 10, height: 18)
        // .t spawnt bei col (10-3)/2 = 3, row 18-3 = 15; Zellen (3,16),(4,16),(5,16),(4,17).
        b[3, 16] = .ruby; b[4, 16] = .ruby; b[5, 16] = .ruby; b[4, 17] = .ruby
        let o = Tetromino(type: .o, col: 0, row: 0)        // setzt unten auf, raeumt nichts
        var e = TetrominoEngine(board: b, current: o, next: .t)

        guard case .locked = e.gravityTick() else { return XCTFail("haette aufsetzen muessen") }
        XCTAssertFalse(e.spawnNext(), "Einwurf blockiert → Spiel vorbei")
        XCTAssertEqual(e.phase, .gameOver)
    }

    // MARK: - Punkte-Tabelle

    func testLinePointsTable() {
        XCTAssertEqual(TetrominoEngine.linePoints(lines: 0, level: 5), 0)
        XCTAssertEqual(TetrominoEngine.linePoints(lines: 1, level: 1), 100)
        XCTAssertEqual(TetrominoEngine.linePoints(lines: 2, level: 1), 300)
        XCTAssertEqual(TetrominoEngine.linePoints(lines: 3, level: 1), 500)
        XCTAssertEqual(TetrominoEngine.linePoints(lines: 4, level: 1), 800)
        XCTAssertEqual(TetrominoEngine.linePoints(lines: 4, level: 3), 2400)   // × Level
    }

    // MARK: - Determinismus & 7-bag

    /// Spielt `count` Vierlinge mittig per Hard-Drop und liefert ihre Formen in Reihenfolge.
    private func playTypes(seed: UInt64, count: Int, height: Int = 24) -> [TetrominoType] {
        var e = TetrominoEngine(seed: seed, startLevel: 0, width: 10, height: height)
        var types: [TetrominoType] = []
        var safety = 100_000
        while types.count < count, e.phase != .gameOver, safety > 0 {
            safety -= 1
            types.append(e.current.type)
            drop: while true {
                switch e.gravityTick() {
                case .moved: continue
                case .locked: break drop
                }
            }
            e.spawnNext()
        }
        return types
    }

    func testDeterministicPieceSequence() {
        XCTAssertEqual(playTypes(seed: 0xC0FFEE, count: 20),
                       playTypes(seed: 0xC0FFEE, count: 20))
    }

    func testSevenBagContainsEachShapeOnce() {
        // Die ersten sieben Formen sind ein vollstaendiger Beutel — jede Form genau einmal.
        let first7 = playTypes(seed: 42, count: 7, height: 24)
        XCTAssertEqual(first7.count, 7)
        XCTAssertEqual(Set(first7), Set(TetrominoType.allCases))
    }

    func testDifferentSeedsDiffer() {
        XCTAssertNotEqual(playTypes(seed: 1, count: 14), playTypes(seed: 2, count: 14))
    }
}
