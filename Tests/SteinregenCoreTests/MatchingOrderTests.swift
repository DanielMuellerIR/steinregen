// MatchingOrderTests.swift
// Sichert die deterministische REIHENFOLGE der Match-Rueckgaben ab (Projekt-Regel 2:
// gleicher Seed ⇒ exakt gleicher Verlauf). Die Match-Finder sammeln intern in einem
// `Set<Cell>` — Swift-Sets iterieren aber pro Prozess zufaellig geseedet. Ohne Sortierung
// waere die Reihenfolge von `ClearStep.cells` prozess-abhaengig (Replays/Vergleiche
// braechen still). Deshalb geben `findMatches`/`findLines` (und `SquareEngine.harvest`)
// ihre Zellen in fester Brett-Reihenfolge zurueck: erst Zeile, dann Spalte.

import XCTest
@testable import SteinregenCore

final class MatchingOrderTests: XCTestCase {

    /// `findMatches` (Saeulen-Regel: ≥3 in Linie, mit Diagonalen) liefert die Zellen
    /// sortiert, ohne Duplikate und vollstaendig.
    func testFindMatchesReturnsSortedCells() {
        var b = Board()
        // Horizontale Dreierreihe unten links ...
        b[0, 0] = .ruby; b[1, 0] = .ruby; b[2, 0] = .ruby
        // ... und eine vertikale Dreierreihe in Spalte 4.
        b[4, 0] = .topaz; b[4, 1] = .topaz; b[4, 2] = .topaz

        let cells = findMatches(b)
        XCTAssertEqual(cells.count, 6, "beide Dreierreihen muessen komplett markiert sein")
        XCTAssertEqual(Set(cells).count, cells.count, "keine Duplikate")
        XCTAssertEqual(cells, cells.sorted(), "Rueckgabe muss in Brett-Reihenfolge sortiert sein")
    }

    /// `findLines` (Austreibung-Regel: ≥minRun in Reihe ODER Spalte, keine Diagonalen)
    /// liefert die Zellen ebenfalls sortiert.
    func testFindLinesReturnsSortedCells() {
        var b = Board(width: 8, height: 16)
        // Ein horizontaler Viererlauf in Reihe 3 und ein vertikaler in Spalte 6.
        for col in 1...4 { b[col, 3] = .emerald }
        for row in 5...8 { b[6, row] = .sapphire }

        let cells = findLines(b, minRun: 4)
        XCTAssertEqual(cells.count, 8, "beide Viererlaeufe muessen komplett markiert sein")
        XCTAssertEqual(cells, cells.sorted(), "Rueckgabe muss in Brett-Reihenfolge sortiert sein")
    }

    /// Die Cell-Ordnung selbst: erst Zeile, dann Spalte (Brett-Reihenfolge von unten links).
    func testCellComparable() {
        XCTAssertLessThan(Cell(col: 5, row: 0), Cell(col: 0, row: 1), "niedrigere Zeile kommt zuerst")
        XCTAssertLessThan(Cell(col: 2, row: 3), Cell(col: 4, row: 3), "gleiche Zeile: niedrigere Spalte zuerst")
    }
}
