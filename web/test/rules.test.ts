// rules.test.ts
// Prueft `draw` — die gemeinsame Zieh-Funktion aller Modi — gegen die Vergleichsdaten.
//
// Warum das noetig ist: `draw` verbraucht Werte aus dem Zufallsgenerator. Zieht sie eine Farbe
// zu viel, zu wenig oder in anderer Reihenfolge, verschiebt sich die GESAMTE weitere Steinfolge
// des Spiels — bei gleichem Seed kaeme ein anderes Spiel heraus. Die Funktion hatte bis hierher
// keinen einzigen Aufrufer und keinen Test, stand in web/README.md aber als „fertig".
//
// Der Ansatz: Die Engines des Swift-Kerns ziehen im Konstruktor als Allererstes den Startstein
// aus einem frisch gesaeten Generator. In den Vergleichsdaten steht dieser Stein als
// `initial.piece.gems` — also laesst er sich hier ohne portierte Engine nachrechnen.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { Gem, gemColors } from "../src/core/models.ts";
import { Xoshiro256StarStar } from "../src/core/prng.ts";
import { draw } from "../src/core/rules.ts";
import { golden } from "./golden.ts";

/// Welche Farbpalette und wie viele Steine ein Modus fuer seinen Startstein zieht — genau wie
/// die Konstruktoren im Swift-Kern (`Engine`, `PairEngine`, `SquareEngine`).
///
/// „Eingemauert"/„Erdrueckt" fehlen mit Absicht: Sie ziehen keine Farben, sondern Formen aus
/// einem Beutel. „Austreibung" fehlt, weil ihr Konstruktor VOR dem Startstein die Flueche setzt
/// und dabei schon Werte verbraucht — der erste Zug ist dort also nicht der erste Wert.
const FIRST_DRAW: Record<string, { count: number; palette: readonly Gem[] }> = {
  // Saeule: 3 aus allen 6 Farben (`Engine.drawColors`).
  saeulen: { count: 3, palette: gemColors },
  // Klumpen: 2 aus den ersten 4 Farben (`PairEngine.pairColors`).
  klumpen: { count: 2, palette: gemColors.slice(0, 4) },
  // Schnitter: 4 aus genau zwei Farben (`SquareEngine.blockColors` = Rubin, Diamant).
  schnitter: { count: 4, palette: [Gem.ruby, Gem.diamond] },
};

describe("draw() gegen die Vergleichsdaten", () => {
  it("zieht den Startstein jeder aufgezeichneten Partie richtig", () => {
    let geprueft = 0;
    for (const gameCase of golden().cases) {
      const regel = FIRST_DRAW[gameCase.mode];
      if (regel === undefined) continue;

      const rng = new Xoshiro256StarStar(BigInt(gameCase.seed));
      const gezogen = draw(regel.count, regel.palette, rng);
      assert.deepEqual(
        gezogen,
        gameCase.initial.piece?.gems,
        `${gameCase.id}: der erste gezogene Stein weicht ab`,
      );
      geprueft += 1;
    }
    // Ohne diese Schranke waere der Test still gruen, wenn `FIRST_DRAW` und die Modus-Namen
    // der Daten einmal auseinanderlaufen.
    assert.ok(geprueft >= 8, `zu wenige Partien geprueft: ${geprueft}`);
  });

  it("zieht auch die Vorschau richtig — also genau so viele Werte wie der Kern", () => {
    // Der zweite Zug desselben Generators ist die Vorschau (`nextGems`). Er trifft nur, wenn
    // der erste GENAU `count` Werte verbraucht hat: Ein Wert zu viel, und hier steht Unsinn.
    // „Steinschlag" fehlt hier, weil seine Vorschau vorher noch die Magic-Chance auswuerfelt.
    let geprueft = 0;
    for (const gameCase of golden().cases) {
      if (gameCase.mode !== "klumpen" && gameCase.mode !== "schnitter") continue;
      const regel = FIRST_DRAW[gameCase.mode];
      if (regel === undefined) continue;

      const rng = new Xoshiro256StarStar(BigInt(gameCase.seed));
      draw(regel.count, regel.palette, rng);
      const vorschau = draw(regel.count, regel.palette, rng);
      assert.deepEqual(
        vorschau,
        gameCase.initial.next,
        `${gameCase.id}: die Vorschau weicht ab`,
      );
      geprueft += 1;
    }
    assert.ok(geprueft >= 4, `zu wenige Partien geprueft: ${geprueft}`);
  });

  it("zieht nichts, wenn nichts zu ziehen ist", () => {
    const rng = new Xoshiro256StarStar(1n);
    assert.deepEqual(draw(0, gemColors, rng), []);
  });

  it("weist eine leere Palette zurueck, statt `undefined` durchzureichen", () => {
    // Zurueckgewiesen wird sie schon eine Ebene tiefer: `below(rng, 0)` laesst die Obergrenze 0
    // nicht durch. Die Meldung „leere Farbpalette" in `draw` ist deshalb nicht erreichbar — sie
    // steht dort nur, damit TypeScript den Zugriff `palette[i]` als sicher ansieht.
    const rng = new Xoshiro256StarStar(1n);
    assert.throws(() => draw(1, [], rng), /Obergrenze/);
  });
});
