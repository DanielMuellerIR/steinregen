import XCTest
@testable import SteinregenCore

/// Tests des fuenften Modus „Austreibung" (Kapsel-Paare, vorplatzierte klebende Flueche,
/// Vierer-Laeufe in Reihe/Spalte, Sieg bei geraeumten Fluechen). Die Tests der anderen
/// Engines bleiben unberuehrt — alle Engines sind unabhaengig.
final class CapsuleEngineTests: XCTestCase {

    /// Kurzform: leeres 8×16-Brett (Standard-Maße des Modus).
    private func emptyBoard() -> Board { Board(width: 8, height: 16) }

    // MARK: - Lauf-Erkennung (nur Reihe/Spalte, ab 4)

    func testHorizontalRunOfFourIsFound() {
        var b = emptyBoard()
        for col in 0..<4 { b[col, 0] = .ruby }
        XCTAssertEqual(Set(findLines(b, minRun: 4)),
                       Set((0..<4).map { Cell(col: $0, row: 0) }))
    }

    func testVerticalRunOfFourIsFound() {
        var b = emptyBoard()
        for row in 2..<6 { b[5, row] = .topaz }
        XCTAssertEqual(findLines(b, minRun: 4).count, 4)
    }

    func testThreeInARowDoNotClear() {
        // Drei gleiche reichen NICHT (anders als im Saeulen-Modus).
        var b = emptyBoard()
        for col in 0..<3 { b[col, 0] = .ruby }
        XCTAssertTrue(findLines(b, minRun: 4).isEmpty)
    }

    func testDiagonalRunDoesNotClear() {
        // Vier gleiche auf der Diagonalen zaehlen NICHT (nur Reihe/Spalte).
        var b = emptyBoard()
        for i in 0..<4 { b[i, i] = .emerald }
        XCTAssertTrue(findLines(b, minRun: 4).isEmpty)
    }

    // MARK: - Flueche kleben (settle mit pinned)

    func testPinnedCellStaysWhenClearedBelow() {
        // Fluch bei (0,5); darunter alles leer; ein loser Stein darueber bei (0,8):
        // Nachrutschen laesst den losen Stein AUF den Fluch fallen (Reihe 6) —
        // der Fluch selbst bleibt bei Reihe 5 stehen, nichts rutscht an ihm vorbei.
        var b = emptyBoard()
        b[0, 5] = .ruby          // der Fluch
        b[0, 8] = .topaz         // loser Stein darueber
        settle(&b, pinned: [Cell(col: 0, row: 5)])
        XCTAssertEqual(b[0, 5], .ruby, "Fluch klebt an seinem Platz")
        XCTAssertEqual(b[0, 6], .topaz, "loser Stein faellt bis AUF den Fluch")
        XCTAssertNil(b[0, 8])
        XCTAssertNil(b[0, 0], "unter dem Fluch bleibt es leer — nichts faellt an ihm vorbei")
    }

    func testSettleWithEmptyPinnedBehavesLikePlainSettle() {
        var a = emptyBoard(); a[2, 7] = .ruby
        var b = a
        settle(&a)
        settle(&b, pinned: [])
        XCTAssertEqual(a, b)
    }

    // MARK: - Fluch-Vorbefuellung (deterministisch)

    func testCursePlacementIsDeterministic() {
        let e1 = CapsuleEngine(seed: 0xC0FFEE, startLevel: 5)
        let e2 = CapsuleEngine(seed: 0xC0FFEE, startLevel: 5)
        XCTAssertEqual(e1.curses, e2.curses)
        XCTAssertFalse(e1.curses.isEmpty)
    }

    func testCurseCountMatchesLevel() {
        // 4 Flueche je Stufe; Stufe 10 auf 8×16 laeuft in den Kapazitaets-Deckel
        // (8 Spalten × 9 Fluch-Reihen / 2 = 36 < 40).
        XCTAssertEqual(CapsuleEngine.curseCount(level: 1, width: 8, height: 16), 4)
        XCTAssertEqual(CapsuleEngine.curseCount(level: 5, width: 8, height: 16), 20)
        XCTAssertEqual(CapsuleEngine.curseCount(level: 10, width: 8, height: 16), 36)
        XCTAssertEqual(CapsuleEngine(seed: 7, startLevel: 1).curses.count, 4)
        XCTAssertEqual(CapsuleEngine(seed: 7, startLevel: 1).curseCountAtStart, 4)
    }

    func testCursesLieInLowerRowsOnly() {
        let e = CapsuleEngine(seed: 42, startLevel: 10)
        let maxRow = CapsuleEngine.curseRows(height: 16)   // = 9 → Reihen 0..8
        for cell in e.curses {
            XCTAssertLessThan(cell.row, maxRow, "Fluch \(cell) liegt zu hoch")
            XCTAssertEqual(e.board[cell.col, cell.row] != nil, true, "Fluch-Zelle muss belegt sein")
        }
    }

    func testNoInitialTriplesFromCurses() {
        // Ueber mehrere Seeds: die Vorbefuellung erzeugt nie drei gleiche in Reihe/Spalte
        // (sonst raeumte die erste aufsetzende Kapsel unverdiente Geschenke ab).
        for seed: UInt64 in [1, 2, 3, 99, 0xDEAD] {
            let e = CapsuleEngine(seed: seed, startLevel: 10)
            XCTAssertTrue(findLines(e.board, minRun: 3).isEmpty, "Seed \(seed) erzeugt Dreier-Lauf")
        }
    }

    // MARK: - Aufsetzen, Raeumen, Punkte

    func testRunOfFourClearsOnLockWithCurseBonus() {
        // Drei rote am Boden (der linke ist ein Fluch); eine rote Kapsel setzt senkrecht in
        // Spalte 3 auf → der untere Stein vervollstaendigt den Vierer-Lauf. Geraeumt werden
        // die vier Lauf-Zellen (der obere Kapsel-Stein bleibt liegen und faellt nach).
        var b = emptyBoard()
        b[0, 0] = .ruby; b[1, 0] = .ruby; b[2, 0] = .ruby
        let curse = Cell(col: 0, row: 0)
        let piece = PairPiece(gems: [.ruby, .ruby], col: 3, row: 0)
        var e = CapsuleEngine(board: b, curses: [curse], current: piece, next: [.topaz, .topaz])

        guard case let .locked(result) = e.gravityTick() else {
            return XCTFail("Kapsel haette aufsetzen muessen (steht am Boden)")
        }
        XCTAssertEqual(result.steps.count, 1)
        XCTAssertEqual(result.steps[0].cells.count, 4)
        // Punkte: 4 × 10 × Kette 1 + 1 Fluch × 100 Bonus = 140.
        XCTAssertEqual(e.score, 140)
        XCTAssertTrue(e.curses.isEmpty, "der Fluch im Lauf ist getilgt")
        // Der obere Kapsel-Stein ist auf den Boden nachgerutscht.
        XCTAssertEqual(e.board[3, 0], .ruby)
        XCTAssertEqual(e.board.filledCount, 1)
    }

    func testVictoryWhenLastCurseCleared() {
        // Nur EIN Fluch im Brett; sein Lauf wird vervollstaendigt → Phase .won, kein Einwurf mehr.
        var b = emptyBoard()
        b[0, 0] = .ruby; b[1, 0] = .ruby; b[2, 0] = .ruby
        var e = CapsuleEngine(board: b, curses: [Cell(col: 0, row: 0)],
                              current: PairPiece(gems: [.ruby, .ruby], col: 3, row: 0),
                              next: [.topaz, .topaz])
        guard case .locked = e.gravityTick() else { return XCTFail("haette aufsetzen muessen") }
        XCTAssertEqual(e.phase, .won)
        XCTAssertFalse(e.spawnNext(), "nach dem Sieg wird nichts mehr eingeworfen")
        XCTAssertEqual(e.phase, .won, "der Sieg bleibt bestehen (kein Umkippen in gameOver)")
    }

    func testNoVictoryWhileCursesRemain() {
        // Zwei Flueche, nur einer wird geraeumt → normale Aufloesung, Spiel geht weiter.
        var b = emptyBoard()
        b[0, 0] = .ruby; b[1, 0] = .ruby; b[2, 0] = .ruby   // roter Lauf (Fluch links)
        b[7, 0] = .topaz                                     // zweiter Fluch, unbeteiligt
        var e = CapsuleEngine(board: b,
                              curses: [Cell(col: 0, row: 0), Cell(col: 7, row: 0)],
                              current: PairPiece(gems: [.ruby, .ruby], col: 3, row: 0),
                              next: [.topaz, .topaz])
        guard case .locked = e.gravityTick() else { return XCTFail("haette aufsetzen muessen") }
        XCTAssertEqual(e.phase, .resolving)
        XCTAssertEqual(e.curses, [Cell(col: 7, row: 0)])
        XCTAssertTrue(e.spawnNext())
        XCTAssertEqual(e.phase, .falling)
    }

    func testChainReactionWhileCurseStaysPinned() {
        // Kette ueber zwei Wellen, waehrend ein unbeteiligter Fluch in der Luft klebt:
        //   Reihe 0:  rot rot rot [3 frei] gelb gelb gelb .
        //   Fluch:    (7,3) gruen — schwebt frei; OHNE pinned-settle fiele er auf (7,0).
        // Die Kapsel (Pivot rot, Satellit gelb) faellt in Spalte 3 bis zum Boden:
        //   Welle 1: der Pivot vervollstaendigt den roten Lauf (0..3, Reihe 0) → raeumt;
        //   Welle 2: der gelbe Satellit rutscht auf (3,0) nach und vervollstaendigt den
        //            gelben Lauf (3..6, Reihe 0) → Kette 2, doppelte Punkte.
        var b = emptyBoard()
        b[0, 0] = .ruby;  b[1, 0] = .ruby;  b[2, 0] = .ruby
        b[4, 0] = .topaz; b[5, 0] = .topaz; b[6, 0] = .topaz
        b[7, 3] = .emerald
        let curse = Cell(col: 7, row: 3)
        let piece = PairPiece(gems: [.ruby, .topaz], col: 3, row: 5)
        var e = CapsuleEngine(board: b, curses: [curse], current: piece, next: [.emerald, .emerald])

        var outcome = e.gravityTick()
        while case .moved = outcome { outcome = e.gravityTick() }
        guard case let .locked(result) = outcome else {
            return XCTFail("Kapsel haette aufsetzen muessen (Boden erreicht)")
        }
        XCTAssertEqual(result.steps.count, 2, "zwei Wellen: erst rot, dann gelb")
        XCTAssertEqual(result.steps[0].chain, 1)
        XCTAssertEqual(result.steps[1].chain, 2)
        // Punkte: 4×10×1 + 4×10×2 = 120 (kein Fluch in den Laeufen → kein Bonus).
        XCTAssertEqual(e.score, 120)
        // Der Fluch klebt unveraendert in der Luft — nichts liegt unter ihm.
        XCTAssertEqual(e.board[7, 3], .emerald)
        XCTAssertNil(e.board[7, 0])
        XCTAssertEqual(e.curses, [curse])
        XCTAssertEqual(e.board.filledCount, 1, "ausser dem Fluch ist das Brett leer")
    }

    // MARK: - Game Over

    func testGameOverWhenSpawnBlocked() {
        // Einwurf-Spalte (Mitte = 4) bis oben voll (abwechselnde Farben, kein Versehen-Lauf);
        // ein harmloses Paar am Rand bringt die Engine in .resolving, dann scheitert der Einwurf.
        var b = emptyBoard()
        for row in 0..<16 { b[4, row] = (row % 2 == 0) ? .emerald : .ruby }
        var e = CapsuleEngine(board: b, curses: [Cell(col: 4, row: 0)],
                              current: PairPiece(gems: [.topaz, .topaz], col: 0, row: 0),
                              next: [.ruby, .ruby])
        guard case .locked = e.gravityTick() else { return XCTFail("haette aufsetzen muessen") }
        XCTAssertFalse(e.spawnNext(), "Einwurf blockiert → Spiel vorbei")
        XCTAssertEqual(e.phase, .gameOver)
    }

    // MARK: - Determinismus + Farbumfang

    /// Spielt `count` Kapseln mittig per Dauer-Tick und liefert die gezogenen Farben in Reihenfolge.
    private func playColors(seed: UInt64, count: Int) -> [Gem] {
        var e = CapsuleEngine(seed: seed, startLevel: 1, width: 8, height: 24)
        var colors: [Gem] = []
        var safety = 100_000
        while colors.count / 2 < count, e.phase == .falling, safety > 0 {
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

    func testDeterministicSequence() {
        XCTAssertEqual(playColors(seed: 0xBEEF, count: 20), playColors(seed: 0xBEEF, count: 20))
    }

    func testDifferentSeedsDiffer() {
        XCTAssertNotEqual(playColors(seed: 1, count: 14), playColors(seed: 2, count: 14))
    }

    func testOnlyThreeColorsAreDrawn() {
        let allowed = Set(CapsuleEngine.capsuleColors)
        XCTAssertEqual(allowed.count, 3)
        for gem in playColors(seed: 99, count: 30) {
            XCTAssertTrue(allowed.contains(gem), "\(gem) gehoert nicht zu den drei Modus-Farben")
        }
    }
}
