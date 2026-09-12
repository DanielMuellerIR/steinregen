// matching.ts
// Treffer-Erkennung und Nachrutschen — Portierung von `Sources/SteinregenCore/Matching.swift`.
// Bewusst freie, zustandslose Funktionen, genau wie im Swift-Kern.
//
// Drei Modi, drei Räum-Regeln: Linien in allen vier Richtungen (Säulen), verbundene Gruppen
// (Klumpen) und Linien ohne Diagonalen (Austreibung). Die Kaskaden-Schleife darüber ist für
// alle drei dieselbe.

import { Board, CellSet, cell, isMagic, type Cell, type ClearStep, type Gem } from "./models.ts";
import { Scoring } from "./rules.ts";

/**
 * Findet alle Zellen, die Teil eines Laufs von **mindestens 3 gleichfarbigen** Steinen sind —
 * in allen vier Orientierungen: waagerecht, senkrecht und beide Diagonalen.
 * Magic-Steine zählen nie als Treffer (sie liegen ohnehin nie im Brett).
 */
export function findMatches(board: Board): Cell[] {
  // Vier Richtungen: → (waagerecht), ↑ (senkrecht), ↗ und ↘ (Diagonalen).
  const directions: readonly (readonly [number, number])[] = [[1, 0], [0, 1], [1, 1], [1, -1]];
  const marked = new CellSet();

  for (let row = 0; row < board.height; row += 1) {
    for (let col = 0; col < board.width; col += 1) {
      const gem = board.get(col, row);
      if (gem === null || isMagic(gem)) continue;

      for (const [dx, dy] of directions) {
        // Nur am Anfang eines Laufs starten: die vorige Zelle in Gegenrichtung darf nicht
        // dieselbe Farbe haben (sonst zählten wir denselben Lauf mehrfach).
        const pc = col - dx;
        const pr = row - dy;
        if (board.inBounds(pc, pr) && board.get(pc, pr) === gem) continue;

        // Lauflänge in Vorwärtsrichtung zählen.
        let length = 0;
        let cc = col;
        let rr = row;
        while (board.inBounds(cc, rr) && board.get(cc, rr) === gem) {
          length += 1;
          cc += dx;
          rr += dy;
        }

        if (length >= 3) {
          cc = col;
          rr = row;
          for (let i = 0; i < length; i += 1) {
            marked.add(cell(cc, rr));
            cc += dx;
            rr += dy;
          }
        }
      }
    }
  }
  // Sortiert zurückgeben: Die Reihenfolge einer Menge ist nicht die des Bretts, und die
  // geräumten Zellen müssen bei gleichem Seed immer gleich aussehen.
  return marked.sorted();
}

/**
 * Findet alle Zellen, die zu einer GRUPPE aus mindestens `minSize` gleichfarbigen, direkt
 * verbundenen Steinen gehören (Flutfüllung über die vier Seiten-Nachbarn — Diagonalen
 * verbinden NICHT). Räum-Regel des „Blutklumpen“-Modus.
 */
export function findGroups(board: Board, minSize: number): Cell[] {
  const visited = new CellSet();
  const result: Cell[] = [];
  const neighbours: readonly (readonly [number, number])[] = [[1, 0], [-1, 0], [0, 1], [0, -1]];

  for (let row = 0; row < board.height; row += 1) {
    for (let col = 0; col < board.width; col += 1) {
      const start = cell(col, row);
      const gem = board.get(col, row);
      if (visited.has(start) || gem === null) continue;

      // Flutfüllung: alle mit `start` verbundenen Zellen derselben Farbe einsammeln.
      const group: Cell[] = [];
      const stack: Cell[] = [start];
      visited.add(start);
      for (let current = stack.pop(); current !== undefined; current = stack.pop()) {
        group.push(current);
        for (const [dx, dy] of neighbours) {
          const n = cell(current.col + dx, current.row + dy);
          if (
            board.inBounds(n.col, n.row) && !visited.has(n) && board.get(n.col, n.row) === gem
          ) {
            visited.add(n);
            stack.push(n);
          }
        }
      }
      if (group.length >= minSize) result.push(...group);
    }
  }
  return result;
}

/**
 * Findet alle Zellen, die Teil eines Laufs von mindestens `minRun` gleichfarbigen Steinen sind —
 * NUR waagerecht und senkrecht (KEINE Diagonalen). Räum-Regel des „Austreibung“-Modus.
 */
export function findLines(board: Board, minRun: number): Cell[] {
  const directions: readonly (readonly [number, number])[] = [[1, 0], [0, 1]];
  const marked = new CellSet();

  for (let row = 0; row < board.height; row += 1) {
    for (let col = 0; col < board.width; col += 1) {
      const gem = board.get(col, row);
      if (gem === null || isMagic(gem)) continue;

      for (const [dx, dy] of directions) {
        const pc = col - dx;
        const pr = row - dy;
        if (board.inBounds(pc, pr) && board.get(pc, pr) === gem) continue;

        let length = 0;
        let cc = col;
        let rr = row;
        while (board.inBounds(cc, rr) && board.get(cc, rr) === gem) {
          length += 1;
          cc += dx;
          rr += dy;
        }

        if (length >= minRun) {
          cc = col;
          rr = row;
          for (let i = 0; i < length; i += 1) {
            marked.add(cell(cc, rr));
            cc += dx;
            rr += dy;
          }
        }
      }
    }
  }
  return marked.sorted();
}

/**
 * Lässt in jeder Spalte alle Steine nach unten auf die freien Plätze nachrutschen. Es gibt kein
 * Überhängen — die Schwerkraft wirkt rein spaltenweise. **Ändert das übergebene Brett.**
 */
export function settle(board: Board): void {
  for (let col = 0; col < board.width; col += 1) {
    let writeRow = 0;
    for (let row = 0; row < board.height; row += 1) {
      const gem = board.get(col, row);
      if (gem !== null) {
        if (writeRow !== row) {
          board.set(col, writeRow, gem);
          board.set(col, row, null);
        }
        writeRow += 1;
      }
    }
  }
}

/**
 * Nachrutschen mit FESTGENAGELTEN Zellen („Austreibung“: die vorplatzierten Flüche kleben an
 * ihrem Platz und fallen NIE). Eine festgenagelte Zelle wirkt als Barriere: Steine oberhalb
 * rutschen nur bis AUF sie herab, nie an ihr vorbei. Mit leerem `pinned` identisch zu `settle`.
 * **Ändert das übergebene Brett.**
 */
export function settlePinned(board: Board, pinned: CellSet): void {
  if (pinned.isEmpty) {
    settle(board);
    return;
  }
  for (let col = 0; col < board.width; col += 1) {
    let writeRow = 0;
    for (let row = 0; row < board.height; row += 1) {
      if (pinned.has(cell(col, row))) {
        // Fester Stein: trennt den Stapel — alles Weitere landet OBERHALB von ihm.
        writeRow = row + 1;
        continue;
      }
      const gem = board.get(col, row);
      if (gem !== null) {
        if (writeRow !== row) {
          board.set(col, writeRow, gem);
          board.set(col, row, null);
        }
        writeRow += 1;
      }
    }
  }
}

/** Was `resolveCascade` außer den Wellen noch zurückgibt. */
export interface CascadeResult {
  readonly steps: ClearStep[];
  readonly score: number;
  readonly gemsCleared: number;
}

export interface CascadeOptions {
  /** Das Brett — wird **verändert** (in Swift ein `inout`-Parameter). */
  board: Board;
  /** Kettenstufe VOR der ersten Welle (Säulen: 1, wenn der Magic-Effekt schon geräumt hat). */
  startChain?: number;
  /** Liefert die zu räumenden Zellen: `findMatches`, `findGroups` oder `findLines`. */
  find: (board: Board) => Cell[];
  /** Lässt das Brett nach dem Räumen nachrutschen (Austreibung: fluch-bewusst). */
  settleBoard: (board: Board) => void;
  /**
   * Zusatzpunkte je Welle. Wird VOR dem Räumen aufgerufen und darf im Aufrufer Zustand
   * fortschreiben (z. B. getilgte Flüche austragen, die dann nicht mehr kleben).
   */
  bonus?: (cells: readonly Cell[]) => number;
  score: number;
  gemsCleared: number;
}

/**
 * Löst die Treffer-Kaskade vollständig auf: solange `find` Treffer liefert, werden sie geräumt,
 * das Brett rutscht nach, Punkte und Zähler steigen, und je Welle entsteht ein `ClearStep`.
 * Geteilt von Säulen, Klumpen und Austreibung.
 *
 * Anders als in Swift kommen die fortgeschriebenen Zähler zurück, statt über `inout` gesetzt zu
 * werden — das gibt es in JavaScript nicht. Das Brett dagegen wird wie dort direkt verändert.
 */
export function resolveCascade(options: CascadeOptions): CascadeResult {
  const { board, find, settleBoard, bonus } = options;
  const steps: ClearStep[] = [];
  let chain = options.startChain ?? 0;
  let score = options.score;
  let gemsCleared = options.gemsCleared;

  for (;;) {
    const matches = find(board);
    if (matches.length === 0) break;
    chain += 1;
    const extra = bonus?.(matches) ?? 0;
    for (const c of matches) board.set(c.col, c.row, null);
    settleBoard(board);
    const points = Scoring.points(matches.length, chain) + extra;
    score += points;
    gemsCleared += matches.length;
    steps.push({
      cells: matches,
      kind: "match",
      color: null,
      chain,
      points,
      // Kopie: Ohne sie zeigten alle Wellen am Ende auf dasselbe, zuletzt geänderte Brett.
      boardAfter: board.clone(),
    });
  }
  return { steps, score, gemsCleared };
}

/**
 * Der Magic-Jewel-Effekt: räumt brettweit alle Steine der Farbe `target`.
 *
 * **Die Farbe kommt von aussen — diese Funktion sieht nicht unter die Aufsetzposition.** Im
 * Swift-Kern steht die Vorbedingung beim Aufrufer (`Engine.lock()`): Nur wenn unter dem
 * untersten Magic-Stein überhaupt eine Zelle liegt und die keine Magic-Zelle ist, wird geräumt;
 * sonst verpufft der Stein ganz ohne Welle. Diese Vorbedingung ist hier **noch nicht portiert**
 * — sie gehört in die Säulen-Engine. Wer sie weglässt und `applyMagic` blind für eine Farbe
 * aufruft, die im Brett gar nicht liegt, erzeugt eine Phantom-Welle mit null Zellen und null
 * Punkten. Die Vergleichsdaten enthalten genau so einen verpuffenden Magic-Aufsetzer
 * (`saeulen-ende`, i=20): dort steht `steps: []`, eben KEINE leere Welle.
 *
 * Steht hier und nicht in der Säulen-Engine, weil er dieselben Bausteine benutzt wie die
 * Kaskade. **Ändert das übergebene Brett.**
 */
export function applyMagic(
  board: Board,
  target: Gem,
  score: number,
  gemsCleared: number,
): { step: ClearStep; score: number; gemsCleared: number } | null {
  // Kein Nachsortieren: `cellsOf` läuft schon Reihe für Reihe, Spalte für Spalte — also genau
  // in Brett-Reihenfolge. Der Swift-Gegenpart sortiert hier ebenfalls nicht. Ein `sortCells`
  // davor wäre heute folgenlos, würde aber eine künftige Reihenfolge-Änderung in `cellsOf`
  // verdecken; die Zusicherung gehört dorthin, wo die Reihenfolge entsteht.
  const cells = board.cellsOf(target);
  // Eine Farbe, die auf dem Brett nicht vorkommt, lässt den Magic-Stein wie im
  // Swift-Kern ohne Räumwelle verpuffen. Eine leere Welle wäre ein Phantomschritt.
  if (cells.length === 0) return null;
  for (const c of cells) board.set(c.col, c.row, null);
  settle(board);
  const points = Scoring.points(cells.length, 1);
  return {
    step: {
      cells,
      kind: "magic",
      color: target,
      chain: 1,
      points,
      boardAfter: board.clone(),
    },
    score: score + points,
    gemsCleared: gemsCleared + cells.length,
  };
}
