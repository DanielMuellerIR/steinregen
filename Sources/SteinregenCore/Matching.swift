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
    // Sortiert zurueckgeben (nicht `Array(marked)`): Set-Reihenfolge ist prozess-zufaellig,
    // die Brett-Reihenfolge haelt ClearStep.cells deterministisch (Regel 2).
    return marked.sorted()
}

/// Findet alle Zellen, die zu einer GRUPPE aus mindestens `minSize` gleichfarbigen, direkt
/// verbundenen Steinen gehoeren (Flood-Fill ueber die vier Seiten-Nachbarn — Diagonalen
/// verbinden NICHT). Raeum-Regel des „Blutklumpen"-Modus; die Saeulen nutzen weiterhin die
/// Linien-Erkennung `findMatches` oben.
func findGroups(_ board: Board, minSize: Int) -> [Cell] {
    var visited = Set<Cell>()
    var result: [Cell] = []

    for row in 0..<board.height {
        for col in 0..<board.width {
            let start = Cell(col: col, row: row)
            guard !visited.contains(start), let gem = board[col, row] else { continue }
            // Flood-Fill: alle mit `start` verbundenen Zellen derselben Farbe einsammeln.
            var group: [Cell] = []
            var stack = [start]
            visited.insert(start)
            while let cell = stack.popLast() {
                group.append(cell)
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let n = Cell(col: cell.col + dx, row: cell.row + dy)
                    if board.inBounds(col: n.col, row: n.row), !visited.contains(n),
                       board[n.col, n.row] == gem {
                        visited.insert(n)
                        stack.append(n)
                    }
                }
            }
            if group.count >= minSize { result.append(contentsOf: group) }
        }
    }
    return result
}

/// Findet alle Zellen, die Teil eines Laufs von mindestens `minRun` gleichfarbigen Steinen sind —
/// NUR horizontal und vertikal (KEINE Diagonalen). Raeum-Regel des „Austreibung"-Modus
/// (Kapsel-Paare, 4 in Reihe); die Saeulen nutzen weiterhin `findMatches` oben (3+, mit Diagonalen).
func findLines(_ board: Board, minRun: Int) -> [Cell] {
    // Zwei Richtungen: → (horizontal) und ↑ (vertikal).
    let directions = [(1, 0), (0, 1)]
    var marked = Set<Cell>()

    for row in 0..<board.height {
        for col in 0..<board.width {
            guard let gem = board[col, row], !gem.isMagic else { continue }
            for (dx, dy) in directions {
                // Nur am Anfang eines Laufs starten (wie in `findMatches`): die vorige Zelle in
                // -Richtung darf nicht dieselbe Farbe haben.
                let pc = col - dx, pr = row - dy
                if board.inBounds(col: pc, row: pr), board[pc, pr] == gem { continue }

                var length = 0
                var cc = col, rr = row
                while board.inBounds(col: cc, row: rr), board[cc, rr] == gem {
                    length += 1
                    cc += dx; rr += dy
                }

                if length >= minRun {
                    cc = col; rr = row
                    for _ in 0..<length {
                        marked.insert(Cell(col: cc, row: rr))
                        cc += dx; rr += dy
                    }
                }
            }
        }
    }
    // Sortiert zurueckgeben (nicht `Array(marked)`): Set-Reihenfolge ist prozess-zufaellig,
    // die Brett-Reihenfolge haelt ClearStep.cells deterministisch (Regel 2).
    return marked.sorted()
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

/// Nachrutschen mit FESTGENAGELTEN Zellen („Austreibung": die vorplatzierten Flueche kleben an
/// ihrem Platz und fallen NIE). Eine gepinnte Zelle wirkt als Barriere: Steine oberhalb rutschen
/// nur bis AUF sie herab, nie an ihr vorbei; die gepinnte Zelle selbst bleibt unveraendert stehen.
/// Mit leerem `pinned` identisch zu `settle` oben.
func settle(_ board: inout Board, pinned: Set<Cell>) {
    guard !pinned.isEmpty else { return settle(&board) }
    for col in 0..<board.width {
        var writeRow = 0
        for row in 0..<board.height {
            if pinned.contains(Cell(col: col, row: row)) {
                // Fester Stein: trennt den Stapel — alles Weitere landet OBERHALB von ihm.
                writeRow = row + 1
            } else if let gem = board[col, row] {
                if writeRow != row {
                    board[col, writeRow] = gem
                    board[col, row] = nil
                }
                writeRow += 1
            }
        }
    }
}
