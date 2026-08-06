// replay.ts
// Hilfen, um die aufgezeichneten Partien durchzugehen. Zwei Dinge nimmt das den Tests ab:
//
// 1. Die Vergleichsdaten lassen Felder weg, die sich nicht geändert haben (`board`, `curses`,
//    `marked`). Wer einen einzelnen Zustand betrachtet, muss den zuletzt bekannten Stand also
//    mitführen — sonst fehlt ihm genau dort das Brett, wo es interessant wird.
// 2. Zellen stehen dort als Zahlenpaare und Bretter als Zeichenketten; hier werden sie in die
//    Typen der Portierung übersetzt.

import { Board, CellSet, cell, type Cell } from "../src/core/models.ts";
import { golden, type GoldenCase, type GoldenLock, type GoldenSnapshot, type GoldenStep } from "./golden.ts";

/// Ein Zustand samt der Felder, die in den Rohdaten weggelassen wurden.
export interface ResolvedSnapshot {
  readonly snapshot: GoldenSnapshot;
  /// Das Brett NACH diesem Befehl — immer gesetzt, auch wenn es sich nicht geändert hat.
  readonly board: string;
  /// Verbliebene Flüche („Austreibung“), sonst leer.
  readonly curses: CellSet;
  /// Markierte Zellen („Schnitter“), sonst leer.
  readonly marked: CellSet;
}

/// Wandelt `[Spalte, Reihe]`-Paare in Zellen.
export function toCells(raw: readonly number[][] | undefined): Cell[] {
  return (raw ?? []).map((pair) => {
    const [col, row] = pair;
    if (col === undefined || row === undefined) throw new Error(`kaputtes Zellenpaar: ${JSON.stringify(pair)}`);
    return cell(col, row);
  });
}

/// Geht eine Partie Befehl für Befehl durch und ergänzt dabei die weggelassenen Felder.
export function* walk(gameCase: GoldenCase): Generator<ResolvedSnapshot> {
  let board = gameCase.initial.board;
  if (board === undefined) throw new Error(`${gameCase.id}: Anfangszustand ohne Brett`);
  let curses = new CellSet(toCells(gameCase.initial.curses));
  let marked = new CellSet(toCells(gameCase.initial.marked));

  for (const snapshot of gameCase.snapshots) {
    if (snapshot.board !== undefined) board = snapshot.board;
    if (snapshot.curses !== undefined) curses = new CellSet(toCells(snapshot.curses));
    if (snapshot.marked !== undefined) marked = new CellSet(toCells(snapshot.marked));
    yield { snapshot, board, curses: curses.clone(), marked: marked.clone() };
  }
}

/// Ein aufgezeichnetes Aufsetzen samt dem Zustand, der dafür gilt.
export interface RecordedLock {
  readonly caseId: string;
  readonly mode: string;
  readonly lock: GoldenLock;
  /// Das Brett NACH dem kompletten Aufsetzen (inklusive Nachrutschen und aller Wellen).
  readonly boardAfter: string;
  /// Die Flüche, die BEIM Aufsetzen noch lagen (also der Stand davor).
  readonly cursesBefore: CellSet;
}

/// Alle Aufsetz-Vorgänge eines Modus, in Reihenfolge.
export function locksOf(mode: string): RecordedLock[] {
  const result: RecordedLock[] = [];
  for (const gameCase of golden().cases) {
    if (gameCase.mode !== mode) continue;
    // Der Fluch-Stand VOR dem Aufsetzen ist der des vorigen Zustands — im Zustand des
    // Aufsetzens selbst stehen bereits die getilgten Flüche.
    let cursesBefore = new CellSet(toCells(gameCase.initial.curses));
    for (const { snapshot, board, curses } of walk(gameCase)) {
      if (snapshot.lock !== undefined) {
        result.push({
          caseId: gameCase.id,
          mode: gameCase.mode,
          lock: snapshot.lock,
          boardAfter: board,
          cursesBefore,
        });
      }
      cursesBefore = curses;
    }
  }
  return result;
}

/// Alle Bretter, die irgendwo in den Vergleichsdaten vorkommen — für Rundlauf-Prüfungen.
export function allBoards(): string[] {
  const boards: string[] = [];
  for (const gameCase of golden().cases) {
    if (gameCase.initial.board !== undefined) boards.push(gameCase.initial.board);
    for (const snapshot of gameCase.snapshots) {
      if (snapshot.board !== undefined) boards.push(snapshot.board);
      if (snapshot.lock !== undefined) {
        boards.push(snapshot.lock.boardBefore);
        for (const step of snapshot.lock.steps) boards.push(step.boardAfter);
      }
      if (snapshot.harvest !== undefined) boards.push(snapshot.harvest.boardAfter);
    }
  }
  return boards;
}

/// Beschreibt eine Räum-Welle so, wie sie in den Vergleichsdaten steht — zum Vergleichen.
export function describeStep(step: GoldenStep): {
  cells: number[][];
  kind: string;
  color: string | null;
  chain: number;
  points: number;
  boardAfter: string;
} {
  return {
    cells: step.cells,
    kind: step.kind,
    color: step.color ?? null,
    chain: step.chain,
    points: step.points,
    boardAfter: step.boardAfter,
  };
}

/// Dasselbe für eine selbst berechnete Welle.
export function describeOwnStep(step: {
  cells: readonly Cell[];
  kind: string;
  color: string | null;
  chain: number;
  points: number;
  boardAfter: Board;
}): ReturnType<typeof describeStep> {
  return {
    cells: step.cells.map((c) => [c.col, c.row]),
    kind: step.kind,
    color: step.color,
    chain: step.chain,
    points: step.points,
    boardAfter: step.boardAfter.encode(),
  };
}
