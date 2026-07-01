import XCTest
@testable import SteinregenCore

/// Tests des dritten Modus „Blutklumpen" (fallende Steinpaare + Vierergruppen-Raeumen per
/// Flood-Fill). Die Tests der anderen Engines bleiben unberuehrt — alle Engines sind unabhaengig.
final class PairEngineTests: XCTestCase {

    /// Kurzform: leeres 6×13-Brett (Standard-Maße des Modus).
    private func emptyBoard() -> Board { Board(width: 6, height: 13) }

    // MARK: - Gruppen-Erkennung (Flood-Fill)

    func testSquareOfFourClears() {
        // Ein 2×2-Quadrat gleicher Farbe ist eine Vierergruppe → alle vier Zellen raeumen.
        var b = emptyBoard()
        b[0, 0] = .ruby; b[1, 0] = .ruby; b[0, 1] = .ruby; b[1, 1] = .ruby
        XCTAssertEqual(Set(findGroups(b, minSize: 4)),
                       [Cell(col: 0, row: 0), Cell(col: 1, row: 0),
                        Cell(col: 0, row: 1), Cell(col: 1, row: 1)])
    }

    func testThreeConnectedDoNotClear() {
        // Drei verbundene gleiche Steine reichen NICHT (anders als im Saeulen-Modus).
        var b = emptyBoard()
        b[0, 0] = .ruby; b[1, 0] = .ruby; b[2, 0] = .ruby
        XCTAssertTrue(findGroups(b, minSize: 4).isEmpty)
    }

    func testLShapedGroupClears() {
        // Auch gewinkelte Gruppen zaehlen — Verbundenheit, keine Linie.
        var b = emptyBoard()
        b[0, 0] = .topaz; b[0, 1] = .topaz; b[0, 2] = .topaz; b[1, 0] = .topaz
        XCTAssertEqual(findGroups(b, minSize: 4).count, 4)
    }

    func testDiagonalDoesNotConnect() {
        // Vier gleiche Steine, die sich nur DIAGONAL beruehren, sind KEINE Gruppe.
        var b = emptyBoard()
        b[0, 0] = .ruby; b[1, 1] = .ruby; b[2, 2] = .ruby; b[3, 3] = .ruby
        XCTAssertTrue(findGroups(b, minSize: 4).isEmpty)
    }

    func testDifferentColorsDoNotConnect() {
        // Verbundenheit gilt je Farbe: 2 rote + 2 gelbe nebeneinander sind keine Vierergruppe.
        var b = emptyBoard()
        b[0, 0] = .ruby; b[1, 0] = .ruby; b[2, 0] = .topaz; b[3, 0] = .topaz
        XCTAssertTrue(findGroups(b, minSize: 4).isEmpty)
    }

    // MARK: - Drehen (Satellit um den Pivot) + Kicks

    func testRotationCyclesAroundPivot() {
        // Frei in Brettmitte: 4× Drehen laeuft up → right → down → left → up.
        let piece = PairPiece(gems: [.ruby, .topaz], col: 3, row: 6)
        var e = PairEngine(board: emptyBoard(), current: piece, next: [.ruby, .ruby])
        XCTAssertEqual(e.current.orientation, .up)
        for expected in [PairOrientation.right, .down, .left, .up] {
            XCTAssertTrue(e.rotate())
            XCTAssertEqual(e.current.orientation, expected)
            XCTAssertEqual(e.current.pivotCell, Cell(col: 3, row: 6), "Pivot bleibt beim freien Drehen stehen")
        }
    }

    func testWallKickAtRightEdge() {
        // Pivot an der rechten Wand, Satellit oben: Drehen nach rechts geht nur mit Kick —
        // der Pivot weicht eine Spalte nach links aus.
        let piece = PairPiece(gems: [.ruby, .topaz], col: 5, row: 6)
        var e = PairEngine(board: emptyBoard(), current: piece, next: [.ruby, .ruby])
        XCTAssertTrue(e.rotate())
        XCTAssertEqual(e.current.orientation, .right)
        XCTAssertEqual(e.current.pivotCell, Cell(col: 4, row: 6))
        XCTAssertEqual(e.current.satelliteCell, Cell(col: 5, row: 6))
    }

    func testFloorKickLiftsPiece() {
        // Pivot am Boden, Satellit rechts: Drehen nach unten hebt das Paar eine Reihe an.
        var piece = PairPiece(gems: [.ruby, .topaz], col: 3, row: 0)
        piece.orientation = .right
        var e = PairEngine(board: emptyBoard(), current: piece, next: [.ruby, .ruby])
        XCTAssertTrue(e.rotate())
        XCTAssertEqual(e.current.orientation, .down)
        XCTAssertEqual(e.current.pivotCell, Cell(col: 3, row: 1))
        XCTAssertEqual(e.current.satelliteCell, Cell(col: 3, row: 0))
    }

    func testBlockedRotationFails() {
        // Satellit oben, rechts UND links der Zielzelle Steine: Drehen (samt Kick) scheitert,
        // das Paar bleibt unveraendert.
        var b = emptyBoard()
        b[4, 6] = .emerald   // Zielzelle der Drehung nach rechts
        b[2, 6] = .emerald   // Zielzelle nach dem Kick (Pivot weicht nach links → Satellit auf 3,
                             // Pivot auf 2 — belegt)
        let piece = PairPiece(gems: [.ruby, .topaz], col: 3, row: 6)
        var e = PairEngine(board: b, current: piece, next: [.ruby, .ruby])
        XCTAssertFalse(e.rotate())
        XCTAssertEqual(e.current.orientation, .up)
        XCTAssertEqual(e.current.pivotCell, Cell(col: 3, row: 6))
    }

    // MARK: - Aufsetzen: Haelften fallen unabhaengig

    func testHorizontalHalvesSettleIndependently() {
        // Quer liegendes Paar: unter dem Pivot ein Turm aus 3 Steinen, unter dem Satelliten
        // nichts → beim Aufsetzen faellt die Satelliten-Haelfte allein bis zum Boden durch.
        var b = emptyBoard()
        b[2, 0] = .emerald; b[2, 1] = .emerald; b[2, 2] = .emerald
        var piece = PairPiece(gems: [.ruby, .topaz], col: 2, row: 3)
        piece.orientation = .right   // Satellit rechts auf Spalte 3 (frei bis zum Boden)
        var e = PairEngine(board: b, current: piece, next: [.ruby, .ruby])

        guard case let .locked(result) = e.gravityTick() else {
            return XCTFail("Paar haette aufsetzen muessen (Pivot liegt auf dem Turm)")
        }
        // Vor dem Nachrutschen: beide an der Aufsetz-Position.
        XCTAssertEqual(result.boardBefore[2, 3], .ruby)
        XCTAssertEqual(result.boardBefore[3, 3], .topaz)
        // Nach dem Nachrutschen: die Satelliten-Haelfte ist allein zum Boden gefallen.
        XCTAssertEqual(e.board[2, 3], .ruby)
        XCTAssertEqual(e.board[3, 0], .topaz)
        XCTAssertNil(e.board[3, 3])
        XCTAssertTrue(result.steps.isEmpty, "keine Vierergruppe → keine Raeum-Welle")
    }

    func testGroupOfFourClearsOnLock() {
        // Drei rote am Boden, ein rotes Paar setzt senkrecht daneben auf → Gruppe aus 5 raeumt.
        var b = emptyBoard()
        b[0, 0] = .ruby; b[1, 0] = .ruby; b[2, 0] = .ruby
        let piece = PairPiece(gems: [.ruby, .ruby], col: 3, row: 0)
        var e = PairEngine(board: b, current: piece, next: [.topaz, .topaz])

        guard case let .locked(result) = e.gravityTick() else {
            return XCTFail("Paar haette aufsetzen muessen (steht am Boden)")
        }
        XCTAssertEqual(result.steps.count, 1)
        XCTAssertEqual(result.steps[0].cells.count, 5)
        XCTAssertEqual(e.score, 50, "5 Steine × 10 × Kette 1")
        XCTAssertEqual(e.gemsCleared, 5)
        XCTAssertEqual(e.board.filledCount, 0)
    }

    func testChainReactionScoresMultiplied() {
        // Kette bauen: Das Raeumen der roten Gruppe laesst den gelben Stein aus Spalte 1
        // herabfallen, der die gelbe Bodenreihe zur Vierergruppe vervollstaendigt → Kette 2.
        var b = emptyBoard()
        b[1, 0] = .ruby;  b[1, 1] = .ruby;  b[1, 2] = .topaz   // roter Sockel, gelber Stein obenauf
        b[2, 0] = .topaz; b[3, 0] = .topaz; b[4, 0] = .topaz   // drei gelbe am Boden
        // Rotes Paar faellt in Spalte 0 bis zum Boden → 2×2 rote Gruppe (Spalten 0+1, Reihen 0+1).
        let piece = PairPiece(gems: [.ruby, .ruby], col: 0, row: 3)
        var e = PairEngine(board: b, current: piece, next: [.emerald, .emerald])

        var outcome = e.gravityTick()
        while case .moved = outcome { outcome = e.gravityTick() }
        guard case let .locked(result) = outcome else {
            return XCTFail("Paar haette aufsetzen muessen (Boden erreicht)")
        }
        XCTAssertEqual(result.steps.count, 2, "zwei Wellen: erst rot, dann gelb")
        XCTAssertEqual(result.steps[0].chain, 1)
        XCTAssertEqual(result.steps[0].cells.count, 4)
        XCTAssertEqual(result.steps[1].chain, 2)
        XCTAssertEqual(result.steps[1].cells.count, 4)
        // Punkte: 4×10×1 + 4×10×2 = 120.
        XCTAssertEqual(e.score, 120)
        XCTAssertEqual(e.board.filledCount, 0)
    }

    func testSatelliteAboveBoardIsDiscardedOnLock() {
        // Spalte bis zur vorletzten Reihe voll (abwechselnde Farben — keine Versehen-Gruppe):
        // Das frisch eingeworfene Paar (Pivot oberste Reihe, Satellit UEBER dem Brett) sitzt
        // sofort auf — nur der Pivot landet im Brett, der Satellit verfaellt (wie das oberste
        // Saeulen-Segment im Saeulen-Modus).
        var b = emptyBoard()
        for row in 0..<12 { b[3, row] = (row % 2 == 0) ? .emerald : .topaz }
        let piece = PairPiece(gems: [.ruby, .topaz], col: 3, row: 12)   // Satellit auf Reihe 13 (oben raus)
        var e = PairEngine(board: b, current: piece, next: [.ruby, .ruby])

        guard case .locked = e.gravityTick() else {
            return XCTFail("Paar haette sofort aufsetzen muessen (Spalte voll)")
        }
        XCTAssertEqual(e.board[3, 12], .ruby)
        XCTAssertEqual(e.board.filledCount, 13, "12 alte + Pivot; der Satellit verfaellt")
    }

    // MARK: - Game Over

    func testGameOverWhenSpawnBlocked() {
        // Einwurf-Spalte (Mitte = 3) bis oben voll — mit ABWECHSELNDEN Farben, damit der Turm
        // beim Aufsetzen des Rand-Paars nicht selbst als Vierergruppe geraeumt wird. Das
        // harmlose Paar am Rand bringt die Engine in Phase .resolving, danach scheitert der Einwurf.
        var b = emptyBoard()
        for row in 0..<13 { b[3, row] = (row % 2 == 0) ? .emerald : .ruby }
        let piece = PairPiece(gems: [.topaz, .topaz], col: 0, row: 0)
        var e = PairEngine(board: b, current: piece, next: [.ruby, .ruby])

        guard case .locked = e.gravityTick() else { return XCTFail("haette aufsetzen muessen") }
        XCTAssertFalse(e.spawnNext(), "Einwurf blockiert → Spiel vorbei")
        XCTAssertEqual(e.phase, .gameOver)
    }

    // MARK: - Determinismus + Farbumfang

    /// Spielt `count` Paare mittig per Dauer-Tick und liefert die gezogenen Farben in Reihenfolge.
    private func playColors(seed: UInt64, count: Int) -> [Gem] {
        var e = PairEngine(seed: seed, startLevel: 0, width: 6, height: 24)
        var colors: [Gem] = []
        var safety = 100_000
        while colors.count / 2 < count, e.phase != .gameOver, safety > 0 {
            safety -= 1
            colors.append(contentsOf: e.current.gems)
            drop: while true {
                switch e.gravityTick() {
                case .moved: continue
                case .locked: break drop
                }
            }
            e.spawnNext()
        }
        return colors
    }

    func testDeterministicColorSequence() {
        XCTAssertEqual(playColors(seed: 0xC0FFEE, count: 20),
                       playColors(seed: 0xC0FFEE, count: 20))
    }

    func testDifferentSeedsDiffer() {
        XCTAssertNotEqual(playColors(seed: 1, count: 14), playColors(seed: 2, count: 14))
    }

    func testOnlyFourColorsAreDrawn() {
        // Der Modus zieht nur aus den vier Modus-Farben (nie sapphire/amethyst/magic).
        let allowed = Set(PairEngine.pairColors)
        XCTAssertEqual(allowed.count, 4)
        for gem in playColors(seed: 99, count: 40) {
            XCTAssertTrue(allowed.contains(gem), "\(gem) gehoert nicht zu den vier Modus-Farben")
        }
    }
}
