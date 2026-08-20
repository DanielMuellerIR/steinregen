// Golden.swift
// Erzeugt die „Vergleichsdaten" (englisch oft „golden data") des Spielkerns: eine feste JSON-Datei,
// die den EXAKTEN Ablauf mehrerer Partien festhaelt — Zug fuer Zug, mit Brett, Punkten und jeder
// Raeum-Welle. Sie ist der Pruefmassstab fuer die geplante TypeScript-Portierung: Die Web-Fassung
// spielt dieselbe Befehlsfolge ab und muss Feld fuer Feld dasselbe liefern.
//
// Warum eine Bibliothek plus ein duennes Kommandozeilen-Ziel (`SteinregenGoldenCLI`)? Zwei Gruende:
//   1. Die Daten sollen als Datei im Repo liegen, damit ein fremdes Projekt (die Webapp) sie
//      lesen kann, ohne Swift zu bauen.
//   2. Ein Werkzeug mit stdout und Exit-Code laesst sich in jede Automation haengen.
// Weil die Logik hier in einer Bibliothek liegt, kann der Regressionstest
// (Tests/SteinregenGoldenTests/GoldenDataTests.swift) genau dieselbe Funktion aufrufen, statt ein
// fertig gebautes Programm auf der Platte suchen zu muessen.
//
// Determinismus-Vertrag (siehe AGENTS.md): Dieses Ziel benutzt Foundation nur zum Schreiben von
// JSON. Alle Spielentscheidungen stammen aus dem seed-bestimmten PRNG des Kerns; es gibt hier
// keine Wanduhr, keinen Systemzufall und keine von der Laufzeit abhaengige Reihenfolge.

import Foundation
import SteinregenCore

// MARK: - Kodierung einzelner Spielwerte
//
// Alle Werte werden so verschriftlicht, dass eine andere Programmiersprache sie ohne
// Interpretationsspielraum nachbilden kann. Besonders wichtig: 64-Bit-Zahlen wandern als
// Zeichenkette ins JSON, weil JavaScript nur 53 Bit genau rechnet und groessere Zahlen
// beim Einlesen still verfaelschen wuerde.

/// Ein-Zeichen-Kuerzel je Steinsorte. `.` steht fuer eine leere Zelle.
func code(_ gem: Gem) -> String {
    switch gem {
    case .ruby:     return "r"
    case .topaz:    return "t"
    case .emerald:  return "e"
    case .diamond:  return "d"
    case .sapphire: return "s"
    case .amethyst: return "a"
    case .magic:    return "m"
    }
}

/// Das Brett als eine Zeichenkette: oberste Reihe zuerst, Reihen durch `/` getrennt.
/// Beispiel fuer ein 3×2-Brett mit einem Rubin unten links: `".../r.."`.
/// Oben-zuerst ist bewusst gewaehlt — so liest sich die Kette wie das Bild auf dem Schirm,
/// obwohl die Koordinaten im Spiel unten links beginnen.
func encode(_ board: Board) -> String {
    var rows: [String] = []
    for row in stride(from: board.height - 1, through: 0, by: -1) {
        var line = ""
        for col in 0..<board.width {
            line += board[col, row].map(code) ?? "."
        }
        rows.append(line)
    }
    return rows.joined(separator: "/")
}

/// Eine Zelle als Zahlenpaar `[Spalte, Reihe]`.
func encode(_ cell: Cell) -> [Int] { [cell.col, cell.row] }

/// Mehrere Zellen — IMMER sortiert (erst Reihe, dann Spalte). Kommen die Zellen aus einem
/// `Set`, ist ihre Reihenfolge im Speicher zufaellig; ohne Sortierung waeren die Daten
/// zwischen zwei Laeufen verschieden und als Pruefmassstab wertlos.
func encode(_ cells: some Sequence<Cell>) -> [[Int]] { cells.sorted().map(encode) }

/// Die Spielphase als sprechendes Wort.
func encode(_ phase: Phase) -> String {
    switch phase {
    case .falling:   return "falling"
    case .resolving: return "resolving"
    case .gameOver:  return "gameOver"
    case .won:       return "won"
    }
}

/// Die Art einer Raeum-Welle.
func encode(_ kind: ClearKind) -> String {
    switch kind {
    case .match: return "match"
    case .magic: return "magic"
    }
}

/// Der Name einer Vierling-/Fuenfling-Form. Bewusst als ausgeschriebener `switch` und nicht
/// ueber `String(describing:)`: Der Name gehoert zum verabredeten Datenformat und darf sich
/// nicht aendern, nur weil die Swift-Laufzeit ihre Spiegelung (Reflection) umbaut.
func encode(_ type: TetrominoType) -> String {
    switch type {
    case .i:   return "i"
    case .o:   return "o"
    case .t:   return "t"
    case .l:   return "l"
    case .j:   return "j"
    case .s:   return "s"
    case .z:   return "z"
    case .f5:  return "f5"
    case .f5M: return "f5M"
    case .i5:  return "i5"
    case .l5:  return "l5"
    case .l5M: return "l5M"
    case .n5:  return "n5"
    case .n5M: return "n5M"
    case .p5:  return "p5"
    case .p5M: return "p5M"
    case .t5:  return "t5"
    case .u5:  return "u5"
    case .v5:  return "v5"
    case .w5:  return "w5"
    case .x5:  return "x5"
    case .y5:  return "y5"
    case .y5M: return "y5M"
    case .z5:  return "z5"
    case .z5M: return "z5M"
    }
}

/// Die Lage des Satelliten neben dem Dreh-Stein.
func encode(_ orientation: PairOrientation) -> String {
    switch orientation {
    case .up:    return "up"
    case .right: return "right"
    case .down:  return "down"
    case .left:  return "left"
    }
}

// MARK: - Ausgabe-Modelle
//
// Diese Typen beschreiben das JSON-Format. Optionale Felder fehlen in der Ausgabe komplett,
// wenn sie leer sind (so macht es Swifts eingebaute Kodierung) — das haelt die Dateien klein
// und die Bedeutung eindeutig: „Feld nicht da" heisst „gilt hier nicht bzw. unveraendert".

/// Der aktive Spielstein, in einer Form, die alle sechs Modi abdeckt.
struct GoldenPiece: Encodable, Equatable {
    /// Bauart: `column`, `pair`, `tetromino` oder `square`.
    let kind: String
    let col: Int
    let row: Int
    /// Farben des Steins in der modus-eigenen Reihenfolge (Saeule unten→oben, Paar Pivot→Satellit,
    /// Block unten-links→unten-rechts→oben-rechts→oben-links, Vierling: die eine Deko-Farbe).
    let gems: [String]
    /// Nur Paar/Kapsel: Lage des Satelliten.
    var orientation: String? = nil
    /// Nur Vierling/Fuenfling: Formname.
    var type: String? = nil
    /// Nur Vierling/Fuenfling: belegte Zellen relativ zur Dreh-Box, in der aktuellen Drehlage.
    var offsets: [[Int]]? = nil
}

/// Eine einzelne Raeum-Welle (eine Kettenstufe).
struct GoldenStep: Encodable, Equatable {
    let cells: [[Int]]
    let kind: String
    /// Nur bei der Magic-Jewel-Raeumung: die getroffene Farbe.
    var color: String? = nil
    let chain: Int
    let points: Int
    let boardAfter: String
}

/// Was beim Aufsetzen eines Steins passiert ist.
struct GoldenLock: Encodable, Equatable {
    let landed: GoldenPiece
    /// Brett direkt nach dem Einschreiben, aber VOR dem Nachrutschen und Raeumen.
    let boardBefore: String
    /// Nur im Saeulen-Modus aussagekraeftig: War der aufgesetzte Stein ein Magic Jewel?
    var wasMagic: Bool? = nil
    let steps: [GoldenStep]
}

/// Ein Zustand nach genau einem Befehl.
struct GoldenSnapshot: Encodable, Equatable {
    /// Laufende Nummer, beginnend bei 1.
    let i: Int
    /// Der ausgefuehrte Befehl (siehe `GoldenCommand`).
    let cmd: String
    /// Ergebnis der Bewegungsbefehle `L`/`R`/`T` bzw. von `S` (Einwurf gelungen?).
    var ok: Bool? = nil
    /// Das Brett — nur vorhanden, wenn es sich gegenueber dem vorigen Schritt GEAENDERT hat.
    /// Fehlt das Feld, gilt der vorige Stand unveraendert weiter.
    var board: String? = nil
    /// Der aktive Stein. NICHT optional: Alle sechs Modi haben in jedem aufgezeichneten Zustand
    /// einen — auch im letzten, in dem der Einwurf bereits blockiert ist. Als Optional getarnt
    /// taeuschte das Feld einen Grenzfall vor, den eine Portierung nachbauen muesste, obwohl er
    /// nicht vorkommt. Kaeme spaeter ein Modus ohne fallenden Stein dazu (Cursor/Band), gehoert
    /// die Optionalitaet zurueck — dann aendern sich diese Daten ohnehin.
    let piece: GoldenPiece
    let score: Int
    let level: Int
    let phase: String
    /// Zaehler des Modus: geraeumte Steine bzw. (bei Vierling/Fuenfling) geraeumte Reihen.
    let cleared: Int
    /// Vorschau auf den naechsten Stein: Farben bzw. Formname.
    var next: [String]? = nil
    var nextType: String? = nil
    /// Nur beim Aufsetzen (`G`, der den Stein einrasten liess).
    var lock: GoldenLock? = nil
    /// Nur beim Sensen-Schritt `W`, falls dabei geerntet wurde.
    var harvest: GoldenStep? = nil
    /// Nur „Schnitter": aktuelle Spalte der Sense.
    var sweepCol: Int? = nil
    /// Nur „Schnitter": markierte Zellen — nur vorhanden, wenn sich die Menge geaendert hat.
    var marked: [[Int]]? = nil
    /// Nur „Austreibung": verbliebene Flueche — nur vorhanden, wenn sich die Menge geaendert hat.
    var curses: [[Int]]? = nil
}

/// Ein kompletter Testfall: eine Partie von vorne bis zum Abbruch.
struct GoldenCase: Encodable, Equatable {
    let id: String
    /// Die stabile Modus-Kennung aus AGENTS.md (`saeulen`, `verschuettet`, …).
    let mode: String
    /// Seed als Zeichenkette, weil er 64 Bit breit sein darf.
    let seed: String
    let startLevel: Int
    let width: Int
    let height: Int
    /// Seed des zweiten PRNG, der die Spielzuege erzeugt hat. Nur zur Nachvollziehbarkeit —
    /// zum Nachspielen genuegt die fertige Befehlsfolge in `commands`.
    let scriptSeed: String
    /// Der Anfangszustand vor dem ersten Befehl.
    let initial: GoldenSnapshot
    /// Die abgespielte Befehlsfolge als eine Zeichenkette, ein Zeichen je Befehl.
    let commands: String
    /// Ein Zustand je Befehl, in derselben Reihenfolge.
    let snapshots: [GoldenSnapshot]
    /// Nur „Austreibung": Zahl der Flueche zu Partiebeginn.
    var curseCountAtStart: Int? = nil
}

/// Rohsequenz eines Zufallsgenerators — der wichtigste Einzeltest fuer die Portierung:
/// JavaScript kennt keine 64-Bit-Ganzzahlen und muss `BigInt` benutzen. Stimmen diese
/// Zahlen nicht, stimmt hinterher gar nichts.
struct GoldenPRNG: Encodable, Equatable {
    let generator: String
    let seed: String
    /// Die ersten Ausgaben, jeweils als Dezimalzahl in einer Zeichenkette.
    let values: [String]
}

// MARK: - Befehle
//
// Eine Partie wird als Folge einzelner Buchstaben festgehalten. Die Web-Fassung liest die
// Kette und ruft dieselben Funktionen auf — mehr braucht es zum Nachspielen nicht.

enum GoldenCommand: Character {
    case left    = "L"   // moveLeft()
    case right   = "R"   // moveRight()
    case turn    = "T"   // rotate()
    case gravity = "G"   // gravityTick() — ein Schritt Schwerkraft
    case spawn   = "S"   // spawnNext()  — naechsten Stein einwerfen
    case sweep   = "W"   // sweepTick()  — nur „Schnitter": Sense eine Spalte weiter
}

// MARK: - Gemeinsame Sicht auf die fuenf Engines
//
// Die Engines im Kern haben absichtlich je eigene Typen (eine Saeule ist kein Kapselpaar).
// Fuer den Export genuegt eine schmale gemeinsame Sicht. Sie liegt bewusst HIER und nicht im
// Kern: Der Kern soll modusneutral bleiben und nichts ueber dieses Dateiformat wissen.
// (Die Render-Schicht hat aus demselben Grund ihr eigenes `PlayEngine`-Protokoll.)

/// Was ein Schwerkraft-Schritt ergeben hat.
enum GoldenTick {
    case moved
    case locked(GoldenLock)
}

protocol GoldenEngine {
    mutating func goldenLeft() -> Bool
    mutating func goldenRight() -> Bool
    mutating func goldenTurn() -> Bool
    mutating func goldenGravity() -> GoldenTick
    mutating func goldenSpawn() -> Bool
    /// Nur der „Schnitter" bewegt eine Sense; alle anderen Modi liefern hier `nil`.
    mutating func goldenSweep() -> GoldenStep?

    var goldenBoard: Board { get }
    var goldenPiece: GoldenPiece { get }
    var goldenScore: Int { get }
    var goldenLevel: Int { get }
    var goldenPhase: Phase { get }
    /// Geraeumte Steine bzw. Reihen — je nachdem, was den Level des Modus treibt.
    var goldenCleared: Int { get }
    var goldenNext: [String]? { get }
    var goldenNextType: String? { get }
    var goldenSweepCol: Int? { get }
    var goldenMarked: [[Int]]? { get }
    var goldenCurses: [[Int]]? { get }
}

// Vorgaben, damit jede Engine nur beschreiben muss, was sie wirklich kann.
extension GoldenEngine {
    mutating func goldenSweep() -> GoldenStep? { nil }
    var goldenNext: [String]? { nil }
    var goldenNextType: String? { nil }
    var goldenSweepCol: Int? { nil }
    var goldenMarked: [[Int]]? { nil }
    var goldenCurses: [[Int]]? { nil }
}

/// Wandelt eine Raeum-Welle des Kerns in die Ausgabeform.
func encode(_ step: ClearStep) -> GoldenStep {
    // Bewusst OHNE Sortierung: `ClearStep.cells` ist bereits eine Liste, keine Menge — ihre
    // Reihenfolge steht also fest und ist sichtbar, weil die Darstellung die Steine in genau
    // dieser Folge verschwinden laesst. Wer hier sortierte, verstiesse gegen den Zweck der
    // Datei: Eine Portierung, die ihre Treffer in anderer Reihenfolge einsammelt, fiele nicht
    // mehr auf. (Die Modi, die aus einer Menge schoepfen, sortieren bereits im Kern selbst;
    // `curses` und `marked` unten sind echte Mengen und werden hier weiterhin sortiert.)
    GoldenStep(cells: step.cells.map(encode),
               kind: encode(step.kind),
               color: step.color.map(code),
               chain: step.chain,
               points: step.points,
               boardAfter: encode(step.boardAfter))
}

// — Saeulen („Steinschlag") —

extension Piece {
    var golden: GoldenPiece {
        GoldenPiece(kind: "column", col: col, row: row, gems: gems.map(code))
    }
}

extension Engine: GoldenEngine {
    mutating func goldenLeft() -> Bool { moveLeft() }
    mutating func goldenRight() -> Bool { moveRight() }
    mutating func goldenTurn() -> Bool { rotate() }
    mutating func goldenSpawn() -> Bool { spawnNext() }

    mutating func goldenGravity() -> GoldenTick {
        switch gravityTick() {
        case .moved:
            return .moved
        case .locked(let r):
            return .locked(GoldenLock(landed: r.landed.golden,
                                      boardBefore: encode(r.boardBefore),
                                      wasMagic: r.wasMagic,
                                      steps: r.steps.map(encode)))
        }
    }

    var goldenBoard: Board { board }
    var goldenPiece: GoldenPiece { current.golden }
    var goldenScore: Int { score }
    var goldenLevel: Int { level }
    var goldenPhase: Phase { phase }
    var goldenCleared: Int { gemsCleared }
    var goldenNext: [String]? { nextGems.map(code) }
}

// — Vierlinge/Fuenflinge („Eingemauert" / „Erdrueckt") —

extension Tetromino {
    var golden: GoldenPiece {
        GoldenPiece(kind: "tetromino", col: col, row: row,
                    gems: [code(type.gem)],
                    type: encode(type),
                    offsets: offsets.map { [$0.col, $0.row] })
    }
}

extension TetrominoEngine: GoldenEngine {
    mutating func goldenLeft() -> Bool { moveLeft() }
    mutating func goldenRight() -> Bool { moveRight() }
    mutating func goldenTurn() -> Bool { rotate() }
    mutating func goldenSpawn() -> Bool { spawnNext() }

    mutating func goldenGravity() -> GoldenTick {
        switch gravityTick() {
        case .moved:
            return .moved
        case .locked(let r):
            return .locked(GoldenLock(landed: r.landed.golden,
                                      boardBefore: encode(r.boardBefore),
                                      steps: r.steps.map(encode)))
        }
    }

    var goldenBoard: Board { board }
    var goldenPiece: GoldenPiece { current.golden }
    var goldenScore: Int { score }
    var goldenLevel: Int { level }
    var goldenPhase: Phase { phase }
    var goldenCleared: Int { linesCleared }
    var goldenNextType: String? { encode(nextType) }
}

// — Steinpaare („Blutklumpen") und Kapseln („Austreibung") —

extension PairPiece {
    func golden(kind: String) -> GoldenPiece {
        GoldenPiece(kind: kind, col: col, row: row, gems: gems.map(code),
                    orientation: encode(orientation))
    }
}

extension PairEngine: GoldenEngine {
    mutating func goldenLeft() -> Bool { moveLeft() }
    mutating func goldenRight() -> Bool { moveRight() }
    mutating func goldenTurn() -> Bool { rotate() }
    mutating func goldenSpawn() -> Bool { spawnNext() }

    mutating func goldenGravity() -> GoldenTick {
        switch gravityTick() {
        case .moved:
            return .moved
        case .locked(let r):
            return .locked(GoldenLock(landed: r.landed.golden(kind: "pair"),
                                      boardBefore: encode(r.boardBefore),
                                      steps: r.steps.map(encode)))
        }
    }

    var goldenBoard: Board { board }
    var goldenPiece: GoldenPiece { current.golden(kind: "pair") }
    var goldenScore: Int { score }
    var goldenLevel: Int { level }
    var goldenPhase: Phase { phase }
    var goldenCleared: Int { gemsCleared }
    var goldenNext: [String]? { nextGems.map(code) }
}

extension CapsuleEngine: GoldenEngine {
    mutating func goldenLeft() -> Bool { moveLeft() }
    mutating func goldenRight() -> Bool { moveRight() }
    mutating func goldenTurn() -> Bool { rotate() }
    mutating func goldenSpawn() -> Bool { spawnNext() }

    mutating func goldenGravity() -> GoldenTick {
        switch gravityTick() {
        case .moved:
            return .moved
        case .locked(let r):
            return .locked(GoldenLock(landed: r.landed.golden(kind: "pair"),
                                      boardBefore: encode(r.boardBefore),
                                      steps: r.steps.map(encode)))
        }
    }

    var goldenBoard: Board { board }
    var goldenPiece: GoldenPiece { current.golden(kind: "pair") }
    var goldenScore: Int { score }
    var goldenLevel: Int { level }
    var goldenPhase: Phase { phase }
    var goldenCleared: Int { gemsCleared }
    var goldenNext: [String]? { nextGems.map(code) }
    var goldenCurses: [[Int]]? { encode(curses) }
}

// — 2×2-Bloecke („Schnitter") —

extension SquarePiece {
    var golden: GoldenPiece {
        GoldenPiece(kind: "square", col: col, row: row, gems: gems.map(code))
    }
}

extension SquareEngine: GoldenEngine {
    mutating func goldenLeft() -> Bool { moveLeft() }
    mutating func goldenRight() -> Bool { moveRight() }
    mutating func goldenTurn() -> Bool { rotate() }
    mutating func goldenSpawn() -> Bool { spawnNext() }

    mutating func goldenGravity() -> GoldenTick {
        switch gravityTick() {
        case .moved:
            return .moved
        case .locked(let r):
            return .locked(GoldenLock(landed: r.landed.golden,
                                      boardBefore: encode(r.boardBefore),
                                      steps: []))
        }
    }

    mutating func goldenSweep() -> GoldenStep? { sweepTick().map(encode) }

    var goldenBoard: Board { board }
    var goldenPiece: GoldenPiece { current.golden }
    var goldenScore: Int { score }
    var goldenLevel: Int { level }
    var goldenPhase: Phase { phase }
    var goldenCleared: Int { gemsCleared }
    var goldenNext: [String]? { nextGems.map(code) }
    var goldenSweepCol: Int? { sweepCol }
    var goldenMarked: [[Int]]? { encode(marked) }
}

// MARK: - Eine Partie aufzeichnen

/// Wie der aufgezeichnete „Spieler" seine Zielspalte waehlt.
///
/// Warum ueberhaupt eine Strategie? Ein rein zufaellig schiebender Spieler tuermt den Stapel
/// schnell hoch und verliert, BEVOR interessante Dinge passieren: Ein erster Versuch raeumte in
/// den Reihen-Modi in 12–17 Aufsetzern keine einzige Reihe. Damit waeren genau die Regeln
/// ungeprueft geblieben, um die es geht (volle Reihen, Ketten, Fluch-Tilgung). Die Strategie
/// bleibt bewusst simpel und schaut nur auf das oeffentlich lesbare Brett — sie soll das Spiel
/// am Laufen halten, nicht gut spielen.
enum PlayStrategy {
    /// Zielt auf die Spalte mit dem niedrigsten Stapel. Haelt das Brett flach, wodurch in den
    /// Reihen-Modi Reihen voll werden und in den Farb-Modi gleiche Steine zusammenfinden.
    case lowest
    /// Zielt auf die Spalte, in der noch ein Fluch liegt („Austreibung"). Das haelt das Spiel
    /// dort in Gang, wo es hingehoert — den Sieg erreicht der einfache Spieler damit aber NICHT:
    /// In keiner aufgezeichneten Kapsel-Partie wird ein Fluch getilgt (siehe `specs`).
    /// Ohne verbliebene Flueche wie `lowest`.
    case curses
}

/// Beschreibung eines Testfalls.
struct CaseSpec {
    let id: String
    let mode: String
    let seed: UInt64
    var startLevel: Int = 0
    var width: Int? = nil
    var height: Int? = nil
    /// Hoechstzahl aufgesetzter Steine — danach bricht die Aufzeichnung ab, auch wenn die
    /// Partie noch laeuft. Haelt die Datei in vernuenftiger Groesse.
    var pieces: Int = 30
    var strategy: PlayStrategy = .lowest
}

/// Hoehe eines Stapels in einer Spalte: die Reihe oberhalb des obersten belegten Feldes
/// (0 = Spalte leer). Reine Rechnung auf dem oeffentlich lesbaren Brett.
func columnHeight(_ board: Board, _ col: Int) -> Int {
    for row in stride(from: board.height - 1, through: 0, by: -1) where board[col, row] != nil {
        return row + 1
    }
    return 0
}

/// Die belegten Zellen eines Steins RELATIV zu seiner Position, jeweils mit ihrer Farbe.
/// Damit laesst sich vorausrechnen, wo der Stein landen wuerde und welche Farbe dort haengen
/// bleibt. Die Reihenfolge entspricht genau `piece.gems`.
func relativeCells(_ piece: GoldenPiece) -> [(dc: Int, dr: Int, gem: String)] {
    /// Farbe an Position `i` der Stein-Farbliste; ein Vierling traegt ueberall dieselbe.
    func gem(_ i: Int) -> String {
        piece.gems.indices.contains(i) ? piece.gems[i] : (piece.gems.first ?? ".")
    }
    switch piece.kind {
    case "column":
        // Dreier-Saeule: gems[0] unten, gems[2] oben.
        return [(0, 0, gem(0)), (0, 1, gem(1)), (0, 2, gem(2))]
    case "square":
        // 2×2-Block — Reihenfolge wie `SquarePiece.gems`:
        // unten-links, unten-rechts, oben-rechts, oben-links.
        return [(0, 0, gem(0)), (1, 0, gem(1)), (1, 1, gem(2)), (0, 1, gem(3))]
    case "pair":
        // Paar/Kapsel: Dreh-Stein (gems[0]) plus Satellit (gems[1]) in der aktuellen Lage.
        switch piece.orientation {
        case "right": return [(0, 0, gem(0)), (1, 0, gem(1))]
        case "down":  return [(0, 0, gem(0)), (0, -1, gem(1))]
        case "left":  return [(0, 0, gem(0)), (-1, 0, gem(1))]
        default:      return [(0, 0, gem(0)), (0, 1, gem(1))]
        }
    case "tetromino":
        // Alle Zellen eines Vierlings/Fuenflings tragen dieselbe Deko-Farbe.
        return (piece.offsets ?? []).map { (dc: $0[0], dr: $0[1], gem: gem(0)) }
    default:
        return [(0, 0, gem(0))]
    }
}

/// Bewertung einer moeglichen Zielspalte: Wie hoch laege die Oberkante, und wie viele Zellen
/// kaemen neben eine gleichfarbige zu liegen? `nil`, wenn der Stein dort nicht ins Brett passt.
///
/// Die Rechnung nimmt an, dass jede Spalte fuer sich bis auf ihren Stapel faellt — genau so
/// wirkt die Schwerkraft im Spiel. Fuer die Kapseln ist es eine Naeherung (festsitzende Flueche
/// koennen einen Stein hoeher aufhalten); fuer eine Zielwahl genuegt das.
///
/// Die Farb-Nachbarschaft ist der Grund, warum ueberhaupt geraeumt wird: Ein Spieler, der nur
/// flach stapelt, bildet nie vier gleiche in einer Linie — ein erster Versuch gewann in 72
/// aufgezeichneten Kapsel-Partien kein einziges Mal. Wer gleiche Farben aneinanderlegt,
/// erzeugt Treffer, haelt das Brett dadurch niedrig und spielt laenger.
func landingScore(_ board: Board, _ piece: GoldenPiece, col: Int,
                  curses: Set<Cell>) -> (top: Int, matches: Int, curseMatches: Int)? {
    let cells = relativeCells(piece)
    var landRow = Int.min
    for (dc, dr, _) in cells {
        let c = col + dc
        guard c >= 0, c < board.width else { return nil }
        // Diese Zelle muss mindestens auf dem Stapel ihrer Spalte zu liegen kommen.
        landRow = max(landRow, columnHeight(board, c) - dr)
    }
    guard landRow != Int.min, let highest = cells.map(\.dr).max() else { return nil }
    let top = landRow + highest
    guard top < board.height else { return nil }   // wuerde oben herausragen

    // Gleichfarbige Nachbarn zaehlen (nur schon liegende Steine, nicht die eigenen Zellen).
    // Ein gleichfarbiger FLUCH wird getrennt gezaehlt: Ihn zu umlagern ist der einzige Weg
    // zum Sieg, waehrend jeder andere Farbtreffer nur Punkte bringt.
    var matches = 0
    var curseMatches = 0
    for (dc, dr, gem) in cells {
        let c = col + dc, r = landRow + dr
        for (nc, nr) in [(c - 1, r), (c + 1, r), (c, r - 1)] {
            guard board.inBounds(col: nc, row: nr), let other = board[nc, nr] else { continue }
            guard code(other) == gem else { continue }
            if curses.contains(Cell(col: nc, row: nr)) { curseMatches += 1 } else { matches += 1 }
        }
    }
    return (top, matches, curseMatches)
}

/// Der aufgezeichnete „Spieler" — bewusst als eigener Typ neben der Aufzeichnung.
///
/// Warum getrennt? `record` vereinte frueher drei Aufgaben auf rund 170 Zeilen: die Aufzeichnung,
/// den Feld-Diff (welche Felder haben sich geaendert?) und diese Zugwahl. Die Zugwahl ist aber
/// ausdruecklich KEIN Teil des Spiels (siehe `golden/README.md`) — nur ein Mittel, damit die
/// Partie lange genug laeuft. Getrennt laesst sie sich lesen und aendern, ohne die Aufzeichnung
/// anzufassen, und die Vergleichsdaten bleiben dabei nachweislich unveraendert.
struct ScriptedPlayer {
    let strategy: PlayStrategy

    /// Waehlt die Zielspalte fuer den naechsten Stein.
    ///
    /// `script` ist der zweite, vom Spiel unabhaengige Generator — er entscheidet nur zwischen
    /// gleich guten Spalten und wird dabei weitergedreht. Deshalb `inout`: Die gezogene Zahl
    /// darf nicht zweimal dieselbe sein.
    func targetColumn(board: Board, piece: GoldenPiece, curses: [[Int]]?,
                      script: inout Xoshiro256StarStar) -> Int {
        // „Austreibung": Solange Flueche liegen, eine Fluch-Spalte anfahren — dort passiert das
        // Modus-Eigene. Unter den Fluch-Spalten die mit dem niedrigsten Stapel, sonst schuettet
        // der Spieler immer dieselbe Spalte zu und verliert frueh. Ist auch die niedrigste davon
        // schon gefaehrlich hoch, geht Ueberleben vor.
        if strategy == .curses, let curses, !curses.isEmpty {
            let cols = Set(curses.map { $0[0] }).sorted()   // sortiert = reproduzierbar
            if let best = cols.min(by: { columnHeight(board, $0) < columnHeight(board, $1) }),
               columnHeight(board, best) * 3 < board.height * 2 {
                return best
            }
        }
        // Sonst: jede Spalte bewerten und die beste nehmen. Gleiche Farben nebeneinander
        // wiegen schwerer als eine flache Landung — nur so entstehen ueberhaupt Treffer;
        // die Landehoehe entscheidet dann unter den farblich gleich guten Plaetzen.
        // Unter mehreren gleich guten Spalten waehlt der Skript-Generator, sonst landete
        // alles immer ganz links.
        //
        // Die Fluch-Zellen als Menge, damit die Bewertung sie erkennt (leer in allen Modi
        // ausser „Austreibung").
        let curseCells = Set((curses ?? []).map { Cell(col: $0[0], row: $0[1]) })
        var bestValue = Int.min
        var candidates: [Int] = []
        for col in 0..<board.width {
            guard let (top, matches, curseMatches) =
                    landingScore(board, piece, col: col, curses: curseCells) else { continue }
            let value = curseMatches * 12 + matches * 4 - top
            if value > bestValue { bestValue = value; candidates = [col] }
            else if value == bestValue { candidates.append(col) }
        }
        guard !candidates.isEmpty else { return board.width / 2 }
        return candidates[Int(script.next() % UInt64(candidates.count))]
    }
}

public enum GoldenData {

    /// Alle aufgezeichneten Partien. Zusammen decken sie jeden Modus, beide Level-Regeln
    /// (Steine bzw. Reihen), das Ernten der Sense und je Modus mindestens ein Spielende ab.
    ///
    /// NICHT abgedeckt ist der Kapsel-Sieg (`phase: "won"`): Der einfache Spieler tilgt in den
    /// aufgezeichneten Partien keinen einzigen Fluch. Diese Luecke steht ausdruecklich in
    /// `golden/README.md` und braucht einen eigenen Test mit gestelltem Brett — sie hier als
    /// abgedeckt zu bezeichnen, waere eine falsche Sicherheit.
    ///
    /// „Beide Level-Regeln" ist woertlich gemeint und war frueher zu grosszuegig formuliert:
    /// Die Reihen-Regel (`TetrominoEngine.linesPerLevel`, Stufe je 10 geraeumte Reihen) steigt
    /// nur in `verschuettet-level` wirklich an — die uebrigen Reihen-Faelle raeumen dafuer zu
    /// wenige Reihen. Dieser eine Fall traegt also die Reihen-Level-Regel und zugleich den
    /// Faktor `max(1, level)` aus `linePoints`; faellt er weg, sind beide ungeprueft.
    static let specs: [CaseSpec] = [
        CaseSpec(id: "saeulen-a",      mode: "saeulen",      seed: 1),
        CaseSpec(id: "saeulen-b",      mode: "saeulen",      seed: 20260806, startLevel: 3),
        CaseSpec(id: "verschuettet-a", mode: "verschuettet", seed: 1),
        CaseSpec(id: "verschuettet-b", mode: "verschuettet", seed: 20260806, startLevel: 2),
        // Schmales Brett: Auf voller Breite raeumt der einfache Spieler kaum Reihen (`-a` und
        // `fuenfling-a` je genau eine), und MEHRFACHREIHEN kommen dort ueberhaupt nicht vor.
        // Genau die braucht es aber, um die Punktetabelle nach Reihenzahl zu pruefen: Dieser
        // Fall ist der einzige mit einer Doppelreihe (300 Punkte). Freie Brettmaße sind ein
        // regulaerer Spielzustand — die App bietet sie als Einstellung an.
        CaseSpec(id: "verschuettet-schmal", mode: "verschuettet", seed: 7,
                 width: 5, height: 10, pieces: 40),
        CaseSpec(id: "klumpen-a",      mode: "klumpen",      seed: 1),
        CaseSpec(id: "klumpen-b",      mode: "klumpen",      seed: 20260806),
        CaseSpec(id: "fuenfling-a",    mode: "fuenfling",    seed: 1),
        // Die Kapsel-Faelle zielen auf die Fluch-Spalten — dort passiert das Modus-Eigene.
        // Den SIEG erreichen sie nicht: kein einziger Fluch wird getilgt (siehe oben).
        CaseSpec(id: "kapseln-a",      mode: "kapseln",      seed: 1, startLevel: 1,
                 pieces: 60, strategy: .curses),
        CaseSpec(id: "kapseln-b",      mode: "kapseln",      seed: 20260806, startLevel: 3,
                 pieces: 60, strategy: .curses),
        // Kleines Brett mit hoher Stufe: prueft den DECKEL der Fluch-Vorbefuellung. `curseCount`
        // ist `min(4 * level, (Breite * curseRows) / 2)`; auf 6×10 sind das Reihen 0…5 und damit
        // hoechstens 18 Flueche. Stufe 5 wuerde 20 verlangen — der zweite Zweig bindet also, und
        // `curseCountAtStart` steht auf 18. Bei Stufe 1 (frueherer Stand) gewann immer der erste
        // Zweig mit 4, genau wie auf dem grossen Brett: Der Deckel war dann ungeprueft.
        CaseSpec(id: "kapseln-klein",  mode: "kapseln",      seed: 3, startLevel: 5,
                 width: 6, height: 10, pieces: 40, strategy: .curses),
        CaseSpec(id: "schnitter-a",    mode: "schnitter",    seed: 1),
        CaseSpec(id: "schnitter-b",    mode: "schnitter",    seed: 20260806),
        // Kurze Partien BIS ZUM SPIELENDE. Auf den vollen Brettern oben bricht die Aufzeichnung
        // nach `pieces` Steinen ab, waehrend das Spiel noch laeuft — der blockierte Einwurf und
        // damit der modusspezifische Spawn-/Game-over-Pfad kaeme dann in keinem Replay vor.
        // Ein enges Brett (4×8) fuellt sich schnell genug, dass diese drei Modi ihr Ende wirklich
        // erreichen. Sie stehen bewusst am Ende der Liste: So bleiben die Bloecke der
        // bestehenden Faelle in der JSON-Datei unveraendert und der Diff zeigt nur Neues.
        CaseSpec(id: "saeulen-ende",   mode: "saeulen",      seed: 11,
                 width: 4, height: 8, pieces: 40),
        CaseSpec(id: "klumpen-ende",   mode: "klumpen",      seed: 11,
                 width: 4, height: 8, pieces: 40),
        CaseSpec(id: "schnitter-ende", mode: "schnitter",    seed: 11,
                 width: 4, height: 8, pieces: 40),
        // „Erdrueckt" braucht ein eigenes Spielende. Vorher trug `fuenfling-a` es allein — und
        // zwar zufaellig: Dort faellt der blockierte Einwurf auf den 30. von 30 erlaubten
        // Steinen. Ein Stein mehr Ueberlebenszeit, und die Aufzeichnung endete wieder mitten im
        // Fallen. Dieser Fall auf engem Brett erreicht das Ende nach 11 Steinen und raeumt
        // nebenbei drei Reihen.
        CaseSpec(id: "fuenfling-ende", mode: "fuenfling",    seed: 17,
                 width: 6, height: 12, pieces: 40),
        // Der einzige Fall, in dem die REIHEN-Level-Regel wirklich zuschlaegt: Nach 10 geraeumten
        // Reihen steigt die Stufe (`linesPerLevel = 10`), hier von 2 auf 3. Zugleich der einzige
        // Reihen-Fall mit einer Stufe ungleich 0 oder 1 — damit steht auch der Faktor
        // `max(1, level)` aus `linePoints` in den Daten (200 statt 100 Punkte je Einzelreihe).
        // Das schmale, hohe Brett und die grosse Steinzahl sind noetig, weil der einfache
        // Spieler auf voller Breite nie so weit kommt.
        CaseSpec(id: "verschuettet-level", mode: "verschuettet", seed: 106, startLevel: 2,
                 width: 5, height: 20, pieces: 300),
    ]

    /// Erzeugt die Engine eines Falls. Fehlen Breite/Hoehe, gilt das Standardmass des Modus.
    static func makeEngine(_ spec: CaseSpec) -> GoldenEngine {
        switch spec.mode {
        case "saeulen":
            return Engine(seed: spec.seed, startLevel: spec.startLevel,
                          width: spec.width ?? Board.defaultWidth,
                          height: spec.height ?? Board.defaultHeight)
        case "verschuettet":
            return TetrominoEngine(seed: spec.seed, startLevel: spec.startLevel,
                                   width: spec.width ?? TetrominoEngine.defaultWidth,
                                   height: spec.height ?? TetrominoEngine.defaultHeight,
                                   types: TetrominoType.tetrominoes)
        case "fuenfling":
            return TetrominoEngine(seed: spec.seed, startLevel: spec.startLevel,
                                   width: spec.width ?? TetrominoEngine.pentominoDefaultWidth,
                                   height: spec.height ?? TetrominoEngine.pentominoDefaultHeight,
                                   types: TetrominoType.pentominoes)
        case "klumpen":
            return PairEngine(seed: spec.seed, startLevel: spec.startLevel,
                              width: spec.width ?? Board.defaultWidth,
                              height: spec.height ?? Board.defaultHeight)
        case "kapseln":
            return CapsuleEngine(seed: spec.seed, startLevel: spec.startLevel,
                                 width: spec.width ?? CapsuleEngine.defaultWidth,
                                 height: spec.height ?? CapsuleEngine.defaultHeight)
        case "schnitter":
            return SquareEngine(seed: spec.seed, startLevel: spec.startLevel,
                                width: spec.width ?? SquareEngine.defaultWidth,
                                height: spec.height ?? SquareEngine.defaultHeight)
        default:
            fatalError("unbekannter Modus: \(spec.mode)")
        }
    }

    /// Zeichnet eine Partie auf.
    ///
    /// Die Spielzuege stammen aus einem ZWEITEN Zufallsgenerator mit eigenem Seed. So haengen
    /// die Zuege nicht mit der Farbfolge zusammen (sonst „wuesste" der Spieler unbewusst, was
    /// kommt), und die Aufzeichnung bleibt trotzdem reproduzierbar. Die fertige Befehlsfolge
    /// steht am Ende im Feld `commands` — zum Nachspielen braucht die Web-Fassung diesen
    /// zweiten Generator also gar nicht.
    static func record(_ spec: CaseSpec) -> GoldenCase {
        var engine = makeEngine(spec)
        // Der zweite Generator bekommt einen erkennbar anderen Seed als das Spiel selbst.
        let scriptSeed = spec.seed ^ 0x5E1D_0000_0000_0001
        var script = Xoshiro256StarStar(seed: scriptSeed)

        var commands: [Character] = []
        var snapshots: [GoldenSnapshot] = []
        // Der zuletzt geschriebene Brett-Stand. Das Brett steht nur dann erneut in der Ausgabe,
        // wenn es sich wirklich geaendert hat (Zug nach links aendert das Brett nie).
        var lastBoard = encode(engine.goldenBoard)
        var lastMarked = engine.goldenMarked
        var lastCurses = engine.goldenCurses

        let initial = GoldenSnapshot(i: 0, cmd: "-",
                                     board: lastBoard,
                                     piece: engine.goldenPiece,
                                     score: engine.goldenScore,
                                     level: engine.goldenLevel,
                                     phase: encode(engine.goldenPhase),
                                     cleared: engine.goldenCleared,
                                     next: engine.goldenNext,
                                     nextType: engine.goldenNextType,
                                     sweepCol: engine.goldenSweepCol,
                                     marked: lastMarked,
                                     curses: lastCurses)

        /// Fuehrt einen Befehl aus, haengt den entstandenen Zustand an und meldet, ob der
        /// Befehl gegriffen hat (bei Bewegungen: `false`, wenn Wand oder Stein im Weg war).
        @discardableResult
        func run(_ cmd: GoldenCommand) -> Bool {
            var ok: Bool? = nil
            var lock: GoldenLock? = nil
            var harvest: GoldenStep? = nil

            switch cmd {
            case .left:    ok = engine.goldenLeft()
            case .right:   ok = engine.goldenRight()
            case .turn:    ok = engine.goldenTurn()
            case .spawn:   ok = engine.goldenSpawn()
            case .sweep:   harvest = engine.goldenSweep()
            case .gravity:
                if case .locked(let l) = engine.goldenGravity() { lock = l }
            }

            commands.append(cmd.rawValue)

            let board = encode(engine.goldenBoard)
            let boardChanged = board != lastBoard
            if boardChanged { lastBoard = board }

            let marked = engine.goldenMarked
            let markedChanged = marked != lastMarked
            if markedChanged { lastMarked = marked }

            let curses = engine.goldenCurses
            let cursesChanged = curses != lastCurses
            if cursesChanged { lastCurses = curses }

            snapshots.append(GoldenSnapshot(
                i: snapshots.count + 1,
                cmd: String(cmd.rawValue),
                ok: ok,
                board: boardChanged ? board : nil,
                piece: engine.goldenPiece,
                score: engine.goldenScore,
                level: engine.goldenLevel,
                phase: encode(engine.goldenPhase),
                cleared: engine.goldenCleared,
                next: engine.goldenNext,
                nextType: engine.goldenNextType,
                lock: lock,
                harvest: harvest,
                sweepCol: engine.goldenSweepCol,
                marked: markedChanged ? marked : nil,
                curses: cursesChanged ? curses : nil))

            return ok ?? true
        }

        let player = ScriptedPlayer(strategy: spec.strategy)

        // Im „Schnitter" muss die Sense mitlaufen, sonst wird nie geerntet. Ein Sensen-Schritt
        // je Schwerkraft-Schritt ist grob das Verhaeltnis, das die Szene in Echtzeit erzeugt.
        let sweeps = spec.mode == "schnitter"

        for _ in 0..<spec.pieces {
            guard engine.goldenPhase == .falling else { break }

            // Zug des „Spielers": erst bis zu drei Drehungen aus dem Skript-Generator, damit
            // auch die Drehlagen vorkommen.
            let turns = Int(script.next() % 4)
            for _ in 0..<turns {
                run(.turn)
                if sweeps { run(.sweep) }
            }

            // Dann die Zielspalte anfahren. Die Schleife endet, sobald das Ziel erreicht ist
            // ODER ein Zug nicht mehr greift (Wand/Stein) — sie kann also nicht haengen bleiben.
            let target = player.targetColumn(board: engine.goldenBoard,
                                             piece: engine.goldenPiece,
                                             curses: engine.goldenCurses,
                                             script: &script)
            var sideways = 0
            while sideways < engine.goldenBoard.width {
                let piece = engine.goldenPiece
                guard piece.col != target else { break }
                let moved = run(piece.col < target ? .right : .left)
                if sweeps { run(.sweep) }
                if !moved { break }
                sideways += 1
            }

            // Fallen lassen, bis der Stein einrastet. Die Obergrenze ist ein Sicherheitsnetz
            // gegen Endlosschleifen — erreicht wird sie im Normalfall nie.
            var guardCount = 0
            while engine.goldenPhase == .falling && guardCount < 64 {
                run(.gravity)
                if sweeps { run(.sweep) }
                guardCount += 1
            }

            guard engine.goldenPhase == .resolving else { break }
            run(.spawn)
            if sweeps { run(.sweep) }
        }

        var result = GoldenCase(id: spec.id,
                                mode: spec.mode,
                                seed: String(spec.seed),
                                startLevel: spec.startLevel,
                                width: engine.goldenBoard.width,
                                height: engine.goldenBoard.height,
                                scriptSeed: String(scriptSeed),
                                initial: initial,
                                commands: String(commands),
                                snapshots: snapshots)
        if let capsule = engine as? CapsuleEngine {
            result.curseCountAtStart = capsule.curseCountAtStart
        }
        return result
    }

    /// Die Rohsequenzen beider Zufallsgeneratoren.
    static func prngVectors() -> [GoldenPRNG] {
        // 0 ist bewusst dabei — aber NICHT, weil es die Null-Zustands-Abfrage im
        // xoshiro-Konstruktor ausloeste: SplitMix64 liefert ab Zustand 0 die Werte
        // 16294208416658607535, 7960286522194355700, … und damit nie vier Nullen. Dieser Zweig
        // ist von aussen unerreichbar (nachgeprueft in `web/README.md`). Seed 0 steht hier als
        // Randfall von SplitMix64 selbst; der groesste 64-Bit-Wert deckt das andere Ende ab.
        let seeds: [UInt64] = [0, 1, 42, 20260806, 18446744073709551615]
        var out: [GoldenPRNG] = []
        for seed in seeds {
            var sm = SplitMix64(seed: seed)
            out.append(GoldenPRNG(generator: "SplitMix64", seed: String(seed),
                                  values: (0..<16).map { _ in String(sm.next()) }))
            var xo = Xoshiro256StarStar(seed: seed)
            out.append(GoldenPRNG(generator: "Xoshiro256StarStar", seed: String(seed),
                                  values: (0..<16).map { _ in String(xo.next()) }))
        }
        return out
    }

    /// Der Kodierer fuer die Zeilen — EINMAL konfiguriert, nicht je Zeile neu.
    ///
    /// `sortedKeys` ist hier keine Kosmetik, sondern Pflicht: Ohne feste Schluesselreihenfolge
    /// saehe dieselbe Ausgabe bei jedem Lauf anders aus, und ein Vergleich Zeile fuer Zeile
    /// waere unmoeglich. `withoutEscapingSlashes` haelt die Brett-Zeichenketten lesbar
    /// (`..r/.tt` statt `..r\/.tt`).
    ///
    /// Genau weil diese zwei Einstellungen ueber die Vergleichbarkeit entscheiden, stehen sie an
    /// einer Stelle und nicht in einer Schleife, die pro Lauf mehrere tausend Mal durchlaeuft.
    private static let lineEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    /// Kodiert einen Wert als JSON in EINER Zeile.
    static func line(_ value: some Encodable) throws -> String {
        guard let text = String(data: try lineEncoder.encode(value), encoding: .utf8) else {
            throw GoldenError.encoding
        }
        return text
    }

    /// Der JSON-Text des Dokuments.
    ///
    /// Das Format ist ein Mittelweg: Der Rahmen steht eingerueckt und lesbar da, aber JEDER
    /// Spielzustand belegt genau EINE Zeile. Vollstaendig eingerueckt waere die Datei rund
    /// dreimal so gross und im Diff unbrauchbar; komplett in einer Zeile waere sie zwar klein,
    /// aber eine Aenderung liesse sich nirgends mehr verorten. So zeigt `git diff` genau die
    /// Zuege, die sich geaendert haben.
    public static func json() throws -> String {
        // Die Listen werden leer kodiert und danach durch die zeilenweisen Bloecke ersetzt.
        // Dadurch gibt es die Feldnamen nur EINMAL — naemlich in den `Encodable`-Typen oben —
        // und dieser Schreiber kann nicht davon abweichen.
        // Bewusst OHNE Programmversion: Die stuende nach jedem Versions-Bump anders da und
        // erzwaenge einen Neuaufbau der ganzen Datei, obwohl sich am Spiel nichts geaendert hat.
        // Genau daran gewoehnt man sich das routinemaessige Neuerzeugen an — und damit waere der
        // Waechter wertlos. Welcher Stand die Datei erzeugt hat, sagt `git log` zu dieser Datei.
        var out = "{\n"
        out += "  \"format\": \"steinregen-golden/1\",\n"

        let vectors = try prngVectors().map { "    " + (try line($0)) }
        out += "  \"prng\": [\n" + vectors.joined(separator: ",\n") + "\n  ],\n"

        var blocks: [String] = []
        for spec in specs {
            let recorded = record(spec)
            // Den Fall mit LEERER Zustandsliste kodieren und die Liste danach einsetzen.
            var head = try line(GoldenCase(id: recorded.id, mode: recorded.mode,
                                           seed: recorded.seed, startLevel: recorded.startLevel,
                                           width: recorded.width, height: recorded.height,
                                           scriptSeed: recorded.scriptSeed,
                                           initial: recorded.initial,
                                           commands: recorded.commands,
                                           snapshots: [],
                                           curseCountAtStart: recorded.curseCountAtStart))
            let rows = try recorded.snapshots.map { "        " + (try line($0)) }
            guard head.contains("\"snapshots\":[]") else { throw GoldenError.placeholderMissing }
            head = head.replacingOccurrences(
                of: "\"snapshots\":[]",
                with: "\"snapshots\":[\n" + rows.joined(separator: ",\n") + "\n      ]")
            blocks.append("    " + head)
        }
        out += "  \"cases\": [\n" + blocks.joined(separator: ",\n") + "\n  ]\n"
        out += "}\n"
        return out
    }
}

/// Fehler beim Erzeugen der Vergleichsdaten.
///
/// Eine Abweichung beim Vergleich (`--check`) steht bewusst NICHT hier: Sie ist kein Fehler des
/// Erzeugens, sondern das Ergebnis des Werkzeugs — `--check` schreibt sie mit vollstaendiger
/// Anleitung direkt nach stderr und liefert Exit-Code 1.
enum GoldenError: Error, CustomStringConvertible {
    case encoding
    /// Der Platzhalter `"snapshots":[]`, in den die zeilenweisen Bloecke eingesetzt werden,
    /// stand nicht im kodierten Fall. Eigener Fall, weil die Ursache eine ganz andere ist als
    /// bei `.encoding`: Da hat jemand das Encodable-Modell umbenannt.
    case placeholderMissing

    var description: String {
        switch self {
        case .encoding:
            return "JSON liess sich nicht als UTF-8 lesen"
        case .placeholderMissing:
            return "Platzhalter \"snapshots\":[] fehlt — wurde das Feld in GoldenCase umbenannt?"
        }
    }
}

// MARK: - Kommandozeile
//
// Die Auswertung der Argumente liegt bewusst hier in der Bibliothek und nicht im ausfuehrbaren
// Ziel: So bleibt dort nur eine einzige Zeile, und das Verhalten des Werkzeugs ist testbar.

/// Kurze Hilfe.
let usage = """
steinregen-golden — erzeugt die Vergleichsdaten des Spielkerns

  steinregen-golden                 JSON nach stdout
  steinregen-golden --out DATEI     JSON in eine Datei schreiben
  steinregen-golden --check DATEI   erzeugen und mit der Datei vergleichen
  steinregen-golden --list          die aufgezeichneten Faelle auflisten

Exit-Code 0 = in Ordnung, 1 = Abweichung oder Fehler.
"""

/// Fuehrt das Werkzeug aus und liefert den Exit-Code (0 = in Ordnung, 1 = Abweichung/Fehler).
public func goldenMain(_ arguments: [String] = Array(CommandLine.arguments.dropFirst())) -> Int32 {
    let args = arguments

    /// Das Dateiargument von `--out`/`--check` herausziehen — oder `nil`, wenn es fehlt, zu viele
    /// sind oder es gar keine Datei ist.
    ///
    /// Die Pruefung auf fuehrendes `--` ist der eigentliche Punkt: `steinregen-golden --out --check`
    /// hat frueher eine 1,4-MB-Datei namens `--check` angelegt und Exit-Code 0 gemeldet. Der
    /// verlangte Vergleich fand nie statt — genau die Fehlerklasse, gegen die `--list` und
    /// `--help` bereits abgesichert waren, nur im einzigen SCHREIBENDEN Zweig.
    func fileArgument(_ option: String) -> String? {
        guard args.count == 2 else {
            FileHandle.standardError.write(Data("\(option) braucht genau eine Datei\n".utf8))
            return nil
        }
        guard !args[1].hasPrefix("--") else {
            FileHandle.standardError.write(
                Data("\(option): »\(args[1])« ist ein Dateiname, keine Option\n".utf8))
            return nil
        }
        return args[1]
    }

    do {
        switch args.first {
        case nil:
            print(try GoldenData.json(), terminator: "")

        case "--list":
            // Ueberzaehlige Argumente sind fast immer ein Tippfehler oder ein falsch
            // zusammengesetzter Automationsaufruf. Frueher lief `--list --check DATEI` durch,
            // listete nur auf und meldete mit Exit-Code 0 Erfolg — der verlangte Vergleich
            // fand nie statt.
            guard args.count == 1 else {
                FileHandle.standardError.write(Data("--list nimmt keine weiteren Argumente\n".utf8))
                return 1
            }
            for spec in GoldenData.specs {
                print("\(spec.id)\t\(spec.mode)\tseed=\(spec.seed)\tlevel=\(spec.startLevel)")
            }

        case "--out":
            guard let path = fileArgument("--out") else { return 1 }
            try GoldenData.json().write(toFile: path, atomically: true, encoding: .utf8)
            print("geschrieben: \(path)")

        case "--check":
            guard let path = fileArgument("--check") else { return 1 }
            let expected = try String(contentsOfFile: path, encoding: .utf8)
            let actual = try GoldenData.json()
            if expected != actual {
                FileHandle.standardError.write(Data("""
                Vergleichsdaten weichen ab: \(path)
                Der Spielkern hat sich geaendert. Wenn das gewollt ist, neu erzeugen:
                  bash tools/make-golden.sh
                und den Unterschied im Diff PRUEFEN, bevor er eingecheckt wird.

                """.utf8))
                return 1
            }
            print("Vergleichsdaten stimmen: \(path)")

        case "--help", "-h":
            guard args.count == 1 else {
                FileHandle.standardError.write(Data("\(args[0]) nimmt keine weiteren Argumente\n".utf8))
                return 1
            }
            print(usage)

        default:
            FileHandle.standardError.write(Data("unbekannte Option: \(args[0])\n\n\(usage)\n".utf8))
            return 1
        }
    } catch {
        FileHandle.standardError.write(Data("Fehler: \(error)\n".utf8))
        return 1
    }
    return 0
}
