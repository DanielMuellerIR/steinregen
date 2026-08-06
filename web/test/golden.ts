// golden.ts
// Laedt die Vergleichsdaten des Swift-Kerns (`golden/steinregen-golden.json`) und beschreibt
// ihren Aufbau als Typen. Die Datei ist der Pruefmassstab dieser Portierung; ihr Format ist in
// `golden/README.md` dokumentiert.
//
// Alle 64-Bit-Zahlen stehen dort als Zeichenkette, nie als JSON-Zahl — als Zahl gelesen wuerde
// JavaScript sie still verfaelschen (nur 53 Bit sind genau). Deshalb wandern sie hier ueber
// `BigInt(...)` und nicht ueber `Number(...)` weiter.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

/// Rohsequenz eines Zufallsgenerators.
export interface GoldenPRNG {
  generator: "SplitMix64" | "Xoshiro256StarStar";
  /// Seed als Dezimalzahl in einer Zeichenkette.
  seed: string;
  /// Die ersten Ausgaben, ebenfalls als Zeichenketten.
  values: string[];
}

/// Der aktive Spielstein. Welche Felder gesetzt sind, haengt von der Bauart ab.
export interface GoldenPiece {
  kind: "column" | "pair" | "tetromino" | "square";
  col: number;
  row: number;
  gems: string[];
  orientation?: "up" | "right" | "down" | "left";
  type?: string;
  offsets?: number[][];
}

/// Eine Raeum-Welle. `cells` sind Paare `[Spalte, Reihe]`.
export interface GoldenStep {
  cells: number[][];
  kind: "match" | "magic";
  color?: string;
  chain: number;
  points: number;
  boardAfter: string;
}

/// Was beim Aufsetzen eines Steins passiert ist.
export interface GoldenLock {
  landed: GoldenPiece;
  boardBefore: string;
  wasMagic?: boolean;
  steps: GoldenStep[];
}

/// Ein Spielzustand nach genau einem Befehl. Optionale Felder fehlen, wenn sie sich nicht
/// geaendert haben — siehe golden/README.md.
export interface GoldenSnapshot {
  i: number;
  cmd: string;
  ok?: boolean;
  /// Nur vorhanden, wenn sich das Brett geaendert hat.
  board?: string;
  piece?: GoldenPiece;
  score: number;
  level: number;
  phase: string;
  cleared: number;
  next?: string[];
  nextType?: string;
  lock?: GoldenLock;
  harvest?: GoldenStep;
  sweepCol?: number;
  /// Nur bei Aenderung: markierte Zellen („Schnitter“) bzw. verbliebene Flueche („Austreibung“).
  marked?: number[][];
  curses?: number[][];
}

/// Eine aufgezeichnete Partie.
export interface GoldenCase {
  id: string;
  mode: string;
  seed: string;
  startLevel: number;
  width: number;
  height: number;
  scriptSeed: string;
  commands: string;
  initial: GoldenSnapshot;
  snapshots: GoldenSnapshot[];
  curseCountAtStart?: number;
}

export interface GoldenDocument {
  format: string;
  prng: GoldenPRNG[];
  cases: GoldenCase[];
}

/// Pfad zur Datei — aus dem Ort DIESER Datei abgeleitet, damit die Tests unabhaengig vom
/// Arbeitsverzeichnis laufen (web/test/ → zwei Ebenen hoch zur Repo-Wurzel).
const goldenPath = fileURLToPath(new URL("../../golden/steinregen-golden.json", import.meta.url));

let cached: GoldenDocument | undefined;

/// Die Vergleichsdaten, beim ersten Zugriff geladen (die Datei ist ~1,3 MB gross).
export function golden(): GoldenDocument {
  if (cached === undefined) {
    const parsed = JSON.parse(readFileSync(goldenPath, "utf8")) as GoldenDocument;
    if (parsed.format !== "steinregen-golden/1") {
      throw new Error(
        `Unbekanntes Format der Vergleichsdaten: ${parsed.format}. ` +
          `Diese Portierung erwartet "steinregen-golden/1".`,
      );
    }
    cached = parsed;
  }
  return cached;
}
