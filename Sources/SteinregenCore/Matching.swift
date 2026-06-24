// Matching.swift
// Reine Hilfsfunktionen fuer die Spiellogik: Treffer-Erkennung und Nachrutschen (Schwerkraft).
// Bewusst freie, zustandslose Funktionen — leicht isoliert testbar.

/// Findet alle Zellen, die Teil eines Laufs von **mindestens 3 gleichfarbigen** Steinen sind —
/// in allen vier Orientierungen: horizontal, vertikal und beide Diagonalen.
/// Magic-Steine zaehlen nie als Treffer (sie liegen ohnehin nie im Brett).
func findMatches(_ board: Board) -> [Cell] {
    // Vier Richtungen: → (horizontal), ↑ (vertikal), ↗ und ↘ (Diagonalen).
    let directions = [(1, 0), (0, 1), (1, 1), (1, -1)]
    var marked = Set<Cell>()

    for row in 0..<board.height {
        for col in 0..<board.width {
            guard let gem = board[col, row], !gem.isMagic else { continue }
            for (dx, dy) in directions {
                // Nur am Anfang eines Laufs starten: die vorige Zelle in -Richtung darf nicht
                // dieselbe Farbe haben (sonst zaehlten wir denselben Lauf mehrfach).
                let pc = col - dx, pr = row - dy
                if board.inBounds(col: pc, row: pr), board[pc, pr] == gem { continue }

                // Lauflaenge in Vorwaertsrichtung zaehlen.
                var length = 0
                var cc = col, rr = row
                while board.inBounds(col: cc, row: rr), board[cc, rr] == gem {
                    length += 1
                    cc += dx; rr += dy
                }

                if length >= 3 {
                    cc = col; rr = row
                    for _ in 0..<length {
                        marked.insert(Cell(col: cc, row: rr))
                        cc += dx; rr += dy
                    }
                }
            }
        }
    }
    return Array(marked)
}

/// Laesst in jeder Spalte alle Steine nach unten auf die freien Plaetze nachrutschen
/// (Columns kennt kein Ueberhaengen — Schwerkraft wirkt rein spaltenweise).
func settle(_ board: inout Board) {
    for col in 0..<board.width {
        var writeRow = 0
        for row in 0..<board.height {
            if let gem = board[col, row] {
                if writeRow != row {
                    board[col, writeRow] = gem
                    board[col, row] = nil
                }
                writeRow += 1
            }
        }
    }
}
