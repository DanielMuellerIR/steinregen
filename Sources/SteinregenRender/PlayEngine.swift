// PlayEngine.swift
// Schmale, modusneutrale Schnittstelle ueber BEIDE Spiel-Engines, damit die `GameScene` den
// Saeulen-Modus (Columns, `Engine`) UND den Verschuettet-Modus (Vierlinge, `TetrominoEngine`) mit
// EINEM Code-Pfad treiben kann. Die Engines selbst bleiben im Core unveraendert — hier liegt nur
// die duenne Adapter-Schicht (retroaktive Conformance), die ihre jeweils eigene API auf eine
// gemeinsame, vom Renderer benoetigte Form abbildet.
//
// Warum hier (Render) und nicht im Core? Der Core soll modus-agnostisch und frei von
// Render-Belangen bleiben. Das Protokoll buendelt genau das, was die SZENE braucht — also gehoert
// es in die Render-Schicht. Die Conformance ist „retroaktiv" (Typ aus dem Core-Modul, Protokoll
// aus diesem Modul); das ist erlaubt, weil das Protokoll im selben Modul wie die Extension liegt.

import SteinregenCore

// MARK: - Spielmodus

/// Die beiden waehlbaren Spielmodi. „Saeulen" = der klassische Columns-Modus (fallende Dreier-
/// Saeulen, ≥3 gleiche in Linie). „Verschuettet" = der Vierling-Modus (sieben Formen, volle Reihen
/// raeumen). Bewusst markenfrei benannt.
public enum GameMode: Sendable {
    case saeulen
    case verschuettet
}

// MARK: - Vorschau-Form (HUD „als Naechstes")

/// Wie die Vorschau auf den naechsten Stein im HUD gezeichnet wird. Bewusst je Modus eine eigene
/// Variante, weil sich die Optik grundlegend unterscheidet (drei gestapelte Steine vs. eine kleine
/// Vierling-Form) — der Renderer waehlt anhand der Variante den passenden Zeichen-Pfad.
public enum PreviewShape: Sendable {
    /// Saeulen: die drei naechsten Steine, senkrecht gestapelt (Index 0 = unten).
    case columns([Gem])
    /// Verschuettet: die naechste Vierling-Form als auf (0,0) normalisierte Zell-Offsets + Sorte
    /// (alle vier Zellen tragen dieselbe kosmetische Sorte).
    case tetromino(cells: [Cell], gem: Gem)
}

// MARK: - Ergebnis eines Schwerkraft-Schritts

/// Modusneutrales Ergebnis eines `step()`-Aufrufs. Ersetzt die je Engine eigenen Tick-Typen
/// (`TickOutcome` / `TetrominoTick`) gegenueber dem Renderer.
public enum StepResult {
    /// Der aktive Stein ist eine Reihe gefallen.
    case moved
    /// Der aktive Stein ist aufgesetzt. `before` = Brett direkt nach dem Einrasten (vor dem Raeumen),
    /// `steps` = die Raeum-Wellen (0..n, von der Szene nacheinander animiert), `magicLanding` =
    /// Brett-Position (Spalte, Reihe) einer aufsetzenden Magic-Saeule (nur Saeulen-Modus; sonst nil
    /// → keine Magic-Landeanimation).
    case locked(before: Board, steps: [ClearStep], magicLanding: (col: Int, row: Int)?)
}

// MARK: - Gemeinsames Protokoll

/// Was die `GameScene` von einer Engine braucht — unabhaengig vom Modus. Wird von beiden Core-Engines
/// erfuellt (siehe Conformances unten). Die Eingabe-/Schwerkraft-Methoden sind `mutating`, weil die
/// Engines Wert-Typen (struct) sind; die Szene haelt sie in einem `var`.
protocol PlayEngine {
    var board: Board { get }
    var score: Int { get }
    var level: Int { get }
    var phase: Phase { get }

    /// Die Zellen des AKTIVEN (fallenden) Steins in BRETT-Koordinaten mit ihrer Sorte. Kann Zellen
    /// mit `row >= board.height` enthalten (Saeule schwebt von oben ein) — der Renderer blendet die
    /// aus, bis sie ins Feld rutschen.
    var activeCells: [(cell: Cell, gem: Gem)] { get }

    /// Vorschau auf den naechsten Stein fuers HUD.
    var preview: PreviewShape { get }

    mutating func moveLeft() -> Bool
    mutating func moveRight() -> Bool
    mutating func rotate() -> Bool
    func canFall() -> Bool

    /// Ein Schwerkraft-Schritt (fallen oder aufsetzen + Aufloesung berechnen).
    mutating func step() -> StepResult

    /// Wirft den naechsten Stein ein. Liefert `false`, wenn der Einwurf blockiert ist → Spiel vorbei.
    @discardableResult mutating func spawnNext() -> Bool
}

// MARK: - Conformance: Saeulen (Columns)

extension Engine: PlayEngine {
    /// Die drei Steine der Saeule, von unten nach oben (Index 0 = `current.row`).
    var activeCells: [(cell: Cell, gem: Gem)] {
        (0..<3).map { i in (Cell(col: current.col, row: current.row + i), current.gems[i]) }
    }

    var preview: PreviewShape { .columns(nextGems) }

    mutating func step() -> StepResult {
        switch gravityTick() {
        case .moved:
            return .moved
        case .locked(let r):
            // Magic-Saeule: ihre Landeposition fuer die Magic-Animation durchreichen; sonst nil.
            let magic = r.wasMagic ? (col: r.landed.col, row: r.landed.row) : nil
            return .locked(before: r.boardBefore, steps: r.steps, magicLanding: magic)
        }
    }
}

// MARK: - Conformance: Verschuettet (Vierlinge)

extension TetrominoEngine: PlayEngine {
    /// Die vier belegten Brett-Zellen des Vierlings; alle tragen die (kosmetische) Sorte der Form.
    var activeCells: [(cell: Cell, gem: Gem)] {
        let gem = current.type.gem
        return current.boardCells().map { (cell: $0, gem: gem) }
    }

    var preview: PreviewShape {
        // Die Spawn-Offsets der naechsten Form auf (0,0) normalisieren, damit der Renderer sie in
        // einer kleinen Box zentriert zeichnen kann.
        let offs = nextType.spawnOffsets
        let minC = offs.map(\.col).min() ?? 0
        let minR = offs.map(\.row).min() ?? 0
        let cells = offs.map { Cell(col: $0.col - minC, row: $0.row - minR) }
        return .tetromino(cells: cells, gem: nextType.gem)
    }

    mutating func step() -> StepResult {
        switch gravityTick() {
        case .moved:
            return .moved
        case .locked(let r):
            // Verschuettet kennt keine Magic-Steine → nie eine Magic-Landeanimation.
            return .locked(before: r.boardBefore, steps: r.steps, magicLanding: nil)
        }
    }
}
