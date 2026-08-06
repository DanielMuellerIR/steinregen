// rules.ts
// Modusübergreifende Spielregel-Bausteine — Portierung von `Sources/SteinregenCore/Rules.swift`.

import { below, type RandomNumberGenerator } from "./prng.ts";
import type { Gem } from "./models.ts";

/** Punktwertung und Level-Takt, geteilt von Säulen, Klumpen, Austreibung und Schnitter. */
export const Scoring = {
  /** So viele geräumte Steine heben das Level um eins. */
  gemsPerLevel: 30,

  /**
   * Punkte einer Räum-Welle: je Stein 10 Punkte, multipliziert mit der Kettenstufe
   * (Kettenreaktionen werden also stark belohnt).
   */
  points(cleared: number, chain: number): number {
    return cleared * 10 * chain;
  },
} as const;

/**
 * Zieht `count` Steinfarben aus `palette` — deterministisch aus dem übergebenen Generator.
 * Gemeinsamer Baustein der Zieh-Funktionen aller Modi (Säule 3 aus 6, Klumpen 2 aus 4,
 * Kapsel 2 aus 3, Block 4 aus 2). Magic kommt hier nie vor.
 *
 * Die Reihenfolge der Ziehungen ist Teil des Determinismus-Vertrags: Die Farben werden von
 * links nach rechts nacheinander gezogen, genau wie in Swift.
 */
export function draw(count: number, palette: readonly Gem[], rng: RandomNumberGenerator): Gem[] {
  const result: Gem[] = [];
  for (let i = 0; i < count; i += 1) {
    const gem = palette[below(rng, palette.length)];
    if (gem === undefined) throw new Error("leere Farbpalette");
    result.push(gem);
  }
  return result;
}
