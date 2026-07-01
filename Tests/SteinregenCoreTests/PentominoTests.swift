import XCTest
@testable import SteinregenCore

/// Tests des vierten Modus „Fuenfling"/„Erdrueckt" (Pentominoes): dieselbe `TetrominoEngine`
/// wie „Verschuettet", nur mit dem 18er-Formen-Satz gefuettert. Hier stehen die Fuenfling-
/// spezifischen Pruefungen — die gemeinsame Reihen-Raeum-Logik testet `TetrominoEngineTests`.
final class PentominoTests: XCTestCase {

    // MARK: - Formen (rein geometrisch)

    func testEighteenShapesWithFiveDistinctCellsInsideBox() {
        XCTAssertEqual(TetrominoType.pentominoes.count, 18)
        for type in TetrominoType.pentominoes {
            let t = Tetromino(type: type, col: 0, row: 0)
            XCTAssertEqual(t.offsets.count, 5, "\(type) sollte fuenf Zellen haben")
            XCTAssertEqual(Set(t.offsets).count, 5, "\(type) Zellen muessen verschieden sein")
            for o in t.offsets {
                XCTAssertTrue((0..<type.boxSize).contains(o.col) && (0..<type.boxSize).contains(o.row),
                              "\(type): Zelle \(o) liegt ausserhalb der \(type.boxSize)×\(type.boxSize)-Box")
            }
        }
    }

    /// Jede Zelle einer Form muss ueber eine Seite mit einer anderen verbunden sein — sonst ist
    /// ein Offset vertippt und die „Form" zerfaellt in Teile.
    func testShapesAreConnected() {
        for type in TetrominoType.pentominoes {
            let cells = Set(Tetromino(type: type, col: 0, row: 0).offsets)
            var reached: Set<Cell> = [cells.first!]
            var frontier = [cells.first!]
            while let c = frontier.popLast() {
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let n = Cell(col: c.col + dx, row: c.row + dy)
                    if cells.contains(n), !reached.contains(n) { reached.insert(n); frontier.append(n) }
                }
            }
            XCTAssertEqual(reached, cells, "\(type) ist nicht zusammenhaengend — Offset-Tippfehler?")
        }
    }

    /// Alle 18 Formen sind PAARWEISE verschieden — auch nach Verschieben (Normalisierung auf
    /// den Ursprung). Faengt versehentliche Doubletten in den Offset-Tabellen.
    func testShapesArePairwiseDistinct() {
        func normalized(_ type: TetrominoType) -> Set<Cell> {
            let offs = Tetromino(type: type, col: 0, row: 0).offsets
            let minC = offs.map(\.col).min()!, minR = offs.map(\.row).min()!
            return Set(offs.map { Cell(col: $0.col - minC, row: $0.row - minR) })
        }
        let shapes = TetrominoType.pentominoes.map(normalized)
        XCTAssertEqual(Set(shapes).count, 18, "mindestens zwei Fuenflinge sind formgleich")
    }

    func testFourRotationsReturnToStart() {
        for type in TetrominoType.pentominoes {
            var t = Tetromino(type: type, col: 0, row: 0)
            let start = Set(t.offsets)
            for _ in 0..<4 { t.offsets = t.rotatedOffsets() }
            XCTAssertEqual(Set(t.offsets), start, "\(type): 4× Drehen muss Ausgangslage ergeben")
        }
    }

    // MARK: - Engine mit Fuenfling-Satz

    /// Spielt `count` Formen per Dauer-Tick und liefert sie in Reihenfolge. Die Formen werden
    /// zyklisch ueber die Spalten VERTEILT (mittig gestapelt liefe das Brett schon nach ~8
    /// Fuenflingen voll — 5 Zellen je Form tragen dick auf).
    private func playTypes(seed: UInt64, count: Int) -> [TetrominoType] {
        var e = TetrominoEngine(seed: seed, startLevel: 0, width: 12, height: 26,
                                types: TetrominoType.pentominoes)
        let shifts = [-5, 5, -3, 3, -1, 1, -4, 4, -2, 2, 0]
        var types: [TetrominoType] = []
        var safety = 100_000
        while types.count < count, e.phase != .gameOver, safety > 0 {
            safety -= 1
            types.append(e.current.type)
            let s = shifts[(types.count - 1) % shifts.count]
            if s < 0 { for _ in 0..<(-s) { _ = e.moveLeft() } }
            if s > 0 { for _ in 0..<s    { _ = e.moveRight() } }
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

    func testEighteenBagContainsEachShapeOnce() {
        // Die ersten achtzehn Formen sind ein vollstaendiger Beutel — jede Form genau einmal.
        let first18 = playTypes(seed: 42, count: 18)
        XCTAssertEqual(first18.count, 18)
        XCTAssertEqual(Set(first18), Set(TetrominoType.pentominoes))
    }

    func testDeterministicSequence() {
        XCTAssertEqual(playTypes(seed: 0xC0FFEE, count: 25), playTypes(seed: 0xC0FFEE, count: 25))
    }

    // MARK: - Fuenffach-Raeumung (nur mit dem senkrechten I5 moeglich)

    func testFiveLinesClearWithVerticalI5() {
        // Fuenf untere Reihen bis auf Spalte 11 voll; ein senkrechter I5 fuellt sie alle.
        var b = Board(width: 12, height: 20)
        for row in 0..<5 { for col in 0..<11 { b[col, row] = .emerald } }
        // I5 senkrecht: 1× Drehen der waagerechten Linie ergibt Box-Spalte 2.
        var i5 = Tetromino(type: .i5, col: 9, row: 0)      // Box-Spalte 2 liegt auf Brett-Spalte 11
        i5.offsets = i5.rotatedOffsets()                   // senkrecht: (2,0)…(2,4)
        var e = TetrominoEngine(board: b, current: i5, next: .t5, types: TetrominoType.pentominoes)

        guard case let .locked(result) = e.gravityTick() else {
            return XCTFail("I5 haette aufsetzen muessen")
        }
        XCTAssertEqual(result.steps.count, 1)
        XCTAssertEqual(result.steps[0].cells.count, 60, "fuenf volle Reihen = 60 Zellen")
        XCTAssertEqual(e.linesCleared, 5)
        XCTAssertEqual(e.score, 1200)                      // 5 Reihen × 1200 × Level(min 1)
        XCTAssertEqual(e.board.filledCount, 0)
    }

    func testLinePointsFiveRows() {
        XCTAssertEqual(TetrominoEngine.linePoints(lines: 5, level: 1), 1200)
        XCTAssertEqual(TetrominoEngine.linePoints(lines: 5, level: 3), 3600)
        // Bestehende Stufen unveraendert.
        XCTAssertEqual(TetrominoEngine.linePoints(lines: 4, level: 1), 800)
    }
}
