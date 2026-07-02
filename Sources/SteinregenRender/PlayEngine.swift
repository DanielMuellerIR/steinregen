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

import Foundation
import SteinregenCore

// MARK: - Spielmodus

/// Die waehlbaren Spielmodi. „Saeulen" = der klassische Columns-Modus (fallende Dreier-
/// Saeulen, ≥3 gleiche in Linie). „Verschuettet" = der Vierling-Modus (sieben Formen, volle Reihen
/// raeumen). „Klumpen" = der Steinpaar-Modus (fallende Zweier-Paare, Gruppen ab 4 verbundenen
/// gleichen Steinen raeumen). „Fuenfling" = die brutale Pentomino-Variante des Vierling-Modus
/// (achtzehn Fuenfer-Formen, gleiche Engine, gleiche Regeln). „Kapseln" = der Kapsel-Modus mit
/// Sieg-Bedingung (vorplatzierte Flueche tilgen, 4 in Reihe/Spalte). „Schnitter" = der
/// 2×2-Block-Modus mit wandernder Sense (gleichfarbige Quadrate bilden, die Sense erntet sie).
/// Bewusst markenfrei benannt.
public enum GameMode: Sendable, Equatable, Hashable, CaseIterable {
    case saeulen
    case verschuettet
    case klumpen
    case fuenfling
    case kapseln
    case schnitter

    /// Anzeigename im Menue/Dialog. (Die internen case-Namen `saeulen`/`verschuettet`/`klumpen`/
    /// `fuenfling`/`kapseln`/`schnitter` und die env-/UserDefaults-Schluessel bleiben aus
    /// Persistenz-/Naht-Gruenden unveraendert — nur diese Anzeige-Strings tragen die
    /// gewuenschten Anzeige-Namen.)
    public var title: String {
        switch self {
        case .saeulen:      return L10n.t("Steinschlag", "Rockfall")
        case .verschuettet: return L10n.t("Eingemauert", "Entombed")
        case .klumpen:      return L10n.t("Blutklumpen", "Blood Clots")
        case .fuenfling:    return L10n.t("Erdrückt", "Crushed")
        case .kapseln:      return L10n.t("Austreibung", "Exorcism")
        case .schnitter:    return L10n.t("Schnitter", "Reaper")
        }
    }

    /// Kurzbeschreibung (eine Zeile) fuer die Modus-Wahl.
    public var hint: String {
        switch self {
        case .saeulen:      return L10n.t("fallende Dreier-Säulen · 3 gleiche in Linie räumen",
                                          "falling triplet columns · clear 3 alike in a line")
        case .verschuettet: return L10n.t("fallende Vierlinge · volle Reihen räumen",
                                          "falling four-block pieces · clear full rows")
        case .klumpen:      return L10n.t("fallende Zweier-Paare · 4 verbundene gleiche räumen",
                                          "falling stone pairs · clear 4 connected alike")
        case .fuenfling:    return L10n.t("fallende Fünflinge · volle Reihen räumen · brutal",
                                          "falling five-block pieces · clear full rows · brutal")
        case .kapseln:      return L10n.t("Kapsel-Paare · 4 in Reihe · alle Flüche tilgen = Sieg",
                                          "capsule pairs · 4 in a row · purge all curses to win")
        case .schnitter:    return L10n.t("2×2-Blöcke · gleiche Quadrate bilden · die Sense erntet",
                                          "2×2 blocks · form matching squares · the scythe reaps")
        }
    }

    /// Standard-Brettmaße des Modus (Säulen und Klumpen 6×13, Verschüttet 10×18, Fünfling 12×20,
    /// Kapseln 8×16, Schnitter 12×12).
    public var defaultWidth: Int {
        switch self {
        case .saeulen, .klumpen: return Board.defaultWidth
        case .verschuettet:      return TetrominoEngine.defaultWidth
        case .fuenfling:         return TetrominoEngine.pentominoDefaultWidth
        case .kapseln:           return CapsuleEngine.defaultWidth
        case .schnitter:         return SquareEngine.defaultWidth
        }
    }
    public var defaultHeight: Int {
        switch self {
        case .saeulen, .klumpen: return Board.defaultHeight
        case .verschuettet:      return TetrominoEngine.defaultHeight
        case .fuenfling:         return TetrominoEngine.pentominoDefaultHeight
        case .kapseln:           return CapsuleEngine.defaultHeight
        case .schnitter:         return SquareEngine.defaultHeight
        }
    }

    /// Erlaubte Spanne der einstellbaren Brettmaße (Säulen/Verschüttet bestätigt 2026-06-24;
    /// Klumpen nutzt dieselbe Spanne wie die Säulen — gleiche Brett-Geometrie. Fünfling braucht
    /// mehr Raum als die Vierlinge: die 18 Formen sind bis zu 5 Zellen breit. Kapseln liegen
    /// zwischen Säulen und Vierlingen — Paar-Geometrie, aber mehr Rangier-Raum noetig).
    public var widthRange: ClosedRange<Int> {
        switch self {
        case .saeulen, .klumpen: return 5...12
        case .verschuettet:      return 8...14
        case .fuenfling:         return 10...16
        case .kapseln:           return 6...12
        // Schnitter: das Genre-Original ist QUER (16×10) — die Spanne erlaubt es nachzustellen.
        case .schnitter:         return 8...16
        }
    }
    public var heightRange: ClosedRange<Int> {
        switch self {
        case .saeulen, .klumpen: return 10...24
        case .verschuettet:      return 14...24
        case .fuenfling:         return 16...26
        case .kapseln:           return 12...24
        case .schnitter:         return 8...16
        }
    }
}

// MARK: - Brettgroessen-Persistenz

/// Zentrale Stelle fuer die pro Modus eingestellten Brettmaße (UserDefaults). Sowohl der
/// Einstellungsdialog (schreibt) als auch der Spielstart (liest) gehen hierueber, damit die Schluessel
/// nicht auseinanderlaufen. Ungesetzt (UserDefaults liefert 0) ⇒ der Modus-Standard; gespeicherte
/// Werte werden zusaetzlich auf die erlaubte Spanne geklemmt (robust gegen alte/kaputte Werte).
@MainActor
public enum BoardConfig {
    public static let saeulenWidthKey      = "steinregen.dim.saeulen.w"
    public static let saeulenHeightKey     = "steinregen.dim.saeulen.h"
    public static let verschuettetWidthKey  = "steinregen.dim.verschuettet.w"
    public static let verschuettetHeightKey = "steinregen.dim.verschuettet.h"
    public static let klumpenWidthKey       = "steinregen.dim.klumpen.w"
    public static let klumpenHeightKey      = "steinregen.dim.klumpen.h"
    public static let fuenflingWidthKey     = "steinregen.dim.fuenfling.w"
    public static let fuenflingHeightKey    = "steinregen.dim.fuenfling.h"
    public static let kapselnWidthKey       = "steinregen.dim.kapseln.w"
    public static let kapselnHeightKey      = "steinregen.dim.kapseln.h"
    public static let schnitterWidthKey     = "steinregen.dim.schnitter.w"
    public static let schnitterHeightKey    = "steinregen.dim.schnitter.h"

    public static func widthKey(_ m: GameMode) -> String {
        switch m {
        case .saeulen:      return saeulenWidthKey
        case .verschuettet: return verschuettetWidthKey
        case .klumpen:      return klumpenWidthKey
        case .fuenfling:    return fuenflingWidthKey
        case .kapseln:      return kapselnWidthKey
        case .schnitter:    return schnitterWidthKey
        }
    }
    public static func heightKey(_ m: GameMode) -> String {
        switch m {
        case .saeulen:      return saeulenHeightKey
        case .verschuettet: return verschuettetHeightKey
        case .klumpen:      return klumpenHeightKey
        case .fuenfling:    return fuenflingHeightKey
        case .kapseln:      return kapselnHeightKey
        case .schnitter:    return schnitterHeightKey
        }
    }

    public static func width(_ m: GameMode) -> Int {
        clamp(UserDefaults.standard.integer(forKey: widthKey(m)), m.widthRange, m.defaultWidth)
    }
    public static func height(_ m: GameMode) -> Int {
        clamp(UserDefaults.standard.integer(forKey: heightKey(m)), m.heightRange, m.defaultHeight)
    }

    private static func clamp(_ v: Int, _ range: ClosedRange<Int>, _ def: Int) -> Int {
        v == 0 ? def : Swift.min(Swift.max(v, range.lowerBound), range.upperBound)
    }
}

// MARK: - Vorschau-Form (HUD „als Naechstes")

/// Wie die Vorschau auf den naechsten Stein im HUD gezeichnet wird. Bewusst je Modus eine eigene
/// Variante, weil sich die Optik grundlegend unterscheidet (drei gestapelte Steine vs. eine kleine
/// Vierling-Form) — der Renderer waehlt anhand der Variante den passenden Zeichen-Pfad.
public enum PreviewShape: Sendable {
    /// Senkrecht gestapelte Steine, Index 0 = unten. Saeulen liefern drei, der Klumpen-Modus
    /// zwei (Pivot unten, Satellit oben) — der Renderer blendet ueberzaehlige Plaetze aus.
    case columns([Gem])
    /// Verschuettet: die naechste Vierling-Form als auf (0,0) normalisierte Zell-Offsets + Sorte
    /// (alle vier Zellen tragen dieselbe kosmetische Sorte).
    case tetromino(cells: [Cell], gem: Gem)
    /// Schnitter: ein kleines Zell-Raster mit INDIVIDUELLER Farbe je Zelle (der 2×2-Block
    /// besteht aus zwei Sorten — eine uniforme Form-Vorschau wie beim Vierling reicht nicht).
    case grid(cells: [(cell: Cell, gem: Gem)])
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

    /// true, wenn nach dem Aufsetzen die Steine noch spaltenweise nachrutschen koennen, BEVOR die
    /// erste Raeum-Welle laeuft (Klumpen: die beiden Haelften fallen unabhaengig). Die Szene
    /// animiert dann zuerst dieses Nachfallen. Saeulen setzen immer gestuetzt auf, Vierlinge
    /// duerfen ueberhaengen (kein Nachrutschen) — beide liefern den Default false.
    var postLockSettle: Bool { get }

    /// Zellen, die FEST im Brett kleben (Kapsel-Modus: die Flueche): Sie rutschen beim
    /// Nachrutschen nie nach unten und wirken als Barriere; der Renderer zeichnet sie markiert
    /// (Fluch-Ring) und laesst seine Nachrutsch-Animation an ihnen anhalten. Default: leer.
    var pinnedCells: Set<Cell> { get }

    /// HERVORGEHOBENE Zellen (Schnitter-Modus: Teile gleichfarbiger 2×2-Quadrate, die auf die
    /// Sense warten). Rein optisch — der Renderer legt einen hellen Schimmer darueber. Anders
    /// als `pinnedCells` aendern sie sich laufend und werden immer frisch gelesen. Default: leer.
    var highlightedCells: Set<Cell> { get }

    /// Aktuelle Spalte der Sense (Schnitter-Modus) — der Renderer zeichnet dort die Sweep-Linie
    /// und treibt `sweepTick()` im Takt. nil = dieser Modus hat keine Sense. Default: nil.
    var sweepColumn: Int? { get }

    /// Ein Sense-Schritt (Schnitter-Modus): bewegt die Sweep-Linie um eine Spalte und liefert
    /// ggf. die geerntete Raeum-Welle. Der TAKT lebt in der Szene (Echtzeit), der Schritt im
    /// Core (deterministisch). Default: tut nichts und liefert nil.
    mutating func sweepTick() -> ClearStep?
}

extension PlayEngine {
    var postLockSettle: Bool { false }
    var pinnedCells: Set<Cell> { [] }
    var highlightedCells: Set<Cell> { [] }
    var sweepColumn: Int? { nil }
    mutating func sweepTick() -> ClearStep? { nil }
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

// MARK: - Conformance: Kapseln (Austreibung)

extension CapsuleEngine: PlayEngine {
    /// Die beiden Brett-Zellen der Kapsel (Pivot + Satellit) mit ihrer Farbe — gleiche Geometrie
    /// wie im Klumpen-Modus (der Satellit kann beim Einschweben ueber dem Brett liegen).
    var activeCells: [(cell: Cell, gem: Gem)] { current.cells }

    /// Vorschau als Zweier-Stapel (Pivot unten, Satellit oben) ueber den Saeulen-Zeichenpfad.
    var preview: PreviewShape { .columns(nextGems) }

    /// Nach dem Aufsetzen koennen die Haelften (fluch-bewusst) nachrutschen → die Szene animiert
    /// zuerst dieses Nachfallen, dann die Raeum-Wellen.
    var postLockSettle: Bool { true }

    /// Die noch nicht getilgten Flueche: kleben fest, werden markiert gezeichnet.
    var pinnedCells: Set<Cell> { curses }

    mutating func step() -> StepResult {
        switch gravityTick() {
        case .moved:
            return .moved
        case .locked(let r):
            // Kapseln kennen keine Magic-Steine → nie eine Magic-Landeanimation.
            return .locked(before: r.boardBefore, steps: r.steps, magicLanding: nil)
        }
    }
}

// MARK: - Conformance: Schnitter (2×2-Bloecke + Sense)

extension SquareEngine: PlayEngine {
    /// Die vier Brett-Zellen des Blocks mit ihrer Farbe. Die obere Block-Reihe kann beim
    /// Einschweben ueber dem Brett liegen (row >= height) — der Renderer blendet sie aus.
    var activeCells: [(cell: Cell, gem: Gem)] { current.cells }

    /// Vorschau als kleines 2×2-Raster mit individueller Farbe je Zelle
    /// (`nextGems`-Reihenfolge: [unten-links, unten-rechts, oben-rechts, oben-links]).
    var preview: PreviewShape {
        .grid(cells: [(Cell(col: 0, row: 0), nextGems[0]),
                      (Cell(col: 1, row: 0), nextGems[1]),
                      (Cell(col: 1, row: 1), nextGems[2]),
                      (Cell(col: 0, row: 1), nextGems[3])])
    }

    /// Nach dem Aufsetzen zerfallen die beiden Blockspalten unabhaengig → die Szene animiert
    /// zuerst dieses Nachfallen (Raeum-Wellen gibt es beim Aufsetzen nie).
    var postLockSettle: Bool { true }

    /// Die auf die Sense wartenden Quadrat-Zellen — heller Schimmer im Renderer.
    var highlightedCells: Set<Cell> { marked }

    /// Sense-Position + -Schritt: `sweepTick()` kommt bereits aus dem Core und erfuellt die
    /// Protokoll-Anforderung direkt; hier ist nur die Spalte zu veroeffentlichen.
    var sweepColumn: Int? { sweepCol }

    mutating func step() -> StepResult {
        switch gravityTick() {
        case .moved:
            return .moved
        case .locked(let r):
            // Beim Aufsetzen wird nie geraeumt (steps leer) — das Ernten macht die Sense.
            return .locked(before: r.boardBefore, steps: [], magicLanding: nil)
        }
    }
}

// MARK: - Conformance: Klumpen (Steinpaare)

extension PairEngine: PlayEngine {
    /// Die beiden Brett-Zellen des Paars (Pivot + Satellit) mit ihrer Farbe. Der Satellit kann
    /// beim Einschweben ueber dem Brett liegen (row >= height) — der Renderer blendet ihn aus.
    var activeCells: [(cell: Cell, gem: Gem)] { current.cells }

    /// Vorschau als Zweier-Stapel (Pivot unten, Satellit oben) ueber den Saeulen-Zeichenpfad.
    var preview: PreviewShape { .columns(nextGems) }

    /// Nach dem Aufsetzen koennen die Haelften unabhaengig nachrutschen → die Szene animiert
    /// zuerst dieses Nachfallen, dann die Raeum-Wellen.
    var postLockSettle: Bool { true }

    mutating func step() -> StepResult {
        switch gravityTick() {
        case .moved:
            return .moved
        case .locked(let r):
            // Klumpen kennt keine Magic-Steine → nie eine Magic-Landeanimation.
            return .locked(before: r.boardBefore, steps: r.steps, magicLanding: nil)
        }
    }
}
