// prng.test.ts
// Prueft die portierten Zufallsgeneratoren gegen die Rohsequenzen aus den Vergleichsdaten des
// Swift-Kerns. Das ist der Grundtest der ganzen Portierung: Stimmen diese Zahlen nicht, ist
// jede weitere Regel wertlos, weil das Spiel schon andere Steine ausgibt.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { SplitMix64, Xoshiro256StarStar, below, type RandomNumberGenerator } from "../src/core/prng.ts";
import { golden, type GoldenPRNG } from "./golden.ts";

/// Baut den Generator, den ein Vergleichsvektor beschreibt.
function makeGenerator(vector: GoldenPRNG): RandomNumberGenerator {
  const seed = BigInt(vector.seed);
  return vector.generator === "SplitMix64" ? new SplitMix64(seed) : new Xoshiro256StarStar(seed);
}

describe("Zufallsgeneratoren gegen die Vergleichsdaten", () => {
  const vectors = golden().prng;

  it("die Vergleichsdaten enthalten ueberhaupt Vektoren", () => {
    assert.ok(vectors.length > 0, "keine PRNG-Vektoren in den Vergleichsdaten");
    // Beide Generatoren muessen vorkommen, sonst prueft der Rest nur die halbe Wahrheit.
    const generators = new Set(vectors.map((v) => v.generator));
    assert.deepEqual([...generators].sort(), ["SplitMix64", "Xoshiro256StarStar"]);
  });

  for (const vector of vectors) {
    it(`${vector.generator} mit Seed ${vector.seed}`, () => {
      const rng = makeGenerator(vector);
      vector.values.forEach((expected, index) => {
        const actual = rng.next();
        assert.equal(
          actual.toString(),
          expected,
          `${vector.generator}/Seed ${vector.seed}: Wert Nr. ${index + 1} weicht ab`,
        );
      });
    });
  }
});

describe("Randfaelle der Generatoren", () => {
  it("Seed 0 ist ein brauchbarer Seed", () => {
    // ACHTUNG, damit sich niemand in falscher Sicherheit wiegt: Dieser Test sichert NICHT die
    // Abfrage auf den komplett leeren Zustand im Konstruktor ab. Sie ist von aussen gar nicht
    // erreichbar, weil SplitMix64 fuer keinen Seed vier Nullen liefert — nachgeprueft, indem
    // die Abfrage entfernt wurde: Alle Tests blieben gruen. Sie steht im Code, weil der
    // Swift-Kern sie ebenso hat und ein anderer Seeding-Weg sie braeuchte.
    // Geprueft wird hier nur, dass Seed 0 (der Randfall der Zahlenreihe) eine brauchbare
    // Folge ergibt; die exakten Werte deckt der Vergleich gegen die Golden-Daten oben ab.
    const rng = new Xoshiro256StarStar(0n);
    const values = Array.from({ length: 8 }, () => rng.next());
    assert.ok(
      values.some((v) => v !== 0n),
      "Seed 0 ergab eine reine Nullfolge",
    );
  });

  it("alle Werte bleiben innerhalb von 64 Bit", () => {
    // Der eigentliche Fallstrick der Portierung: BigInt laesst nichts ueberlaufen. Fehlt auch
    // nur eine Beschneidung auf 64 Bit, wachsen die Zahlen unbegrenzt — hier wuerde das sofort
    // auffallen, waehrend der Vergleich oben nur die ersten 16 Werte abdeckt.
    const limit = 1n << 64n;
    for (const seed of [0n, 1n, 42n, 18446744073709551615n]) {
      const rng = new Xoshiro256StarStar(seed);
      for (let i = 0; i < 500; i += 1) {
        const value = rng.next();
        assert.ok(value >= 0n && value < limit, `Seed ${seed}: Wert ${value} liegt ausserhalb 64 Bit`);
      }
    }
  });

  it("derselbe Seed ergibt zweimal dieselbe Folge", () => {
    const a = Array.from({ length: 32 }, ((rng) => () => rng.next())(new Xoshiro256StarStar(7n)));
    const b = Array.from({ length: 32 }, ((rng) => () => rng.next())(new Xoshiro256StarStar(7n)));
    assert.deepEqual(a, b);
  });

  it("verschiedene Seeds ergeben verschiedene Folgen", () => {
    const a = new Xoshiro256StarStar(1n).next();
    const b = new Xoshiro256StarStar(2n).next();
    assert.notEqual(a, b);
  });
});

describe("below() — die Ziehung im Bereich 0 … n−1", () => {
  it("entspricht genau `rng.next() % n` aus dem Swift-Kern", () => {
    // Nachgerechnet, statt nur auf den Wertebereich zu pruefen: `below` muss buchstabengetreu
    // dieselbe Rechnung sein, sonst zieht die Webfassung andere Steinfarben als der Mac.
    const expectedSource = new Xoshiro256StarStar(99n);
    const actualSource = new Xoshiro256StarStar(99n);
    for (const bound of [2, 3, 4, 6, 18, 40]) {
      for (let i = 0; i < 50; i += 1) {
        const expected = Number(expectedSource.next() % BigInt(bound));
        assert.equal(below(actualSource, bound), expected);
      }
    }
  });

  it("bleibt im Bereich", () => {
    const rng = new Xoshiro256StarStar(5n);
    for (let i = 0; i < 200; i += 1) {
      const value = below(rng, 6);
      assert.ok(Number.isInteger(value) && value >= 0 && value < 6, `ausserhalb: ${value}`);
    }
  });

  it("weist eine unbrauchbare Obergrenze zurueck", () => {
    const rng = new Xoshiro256StarStar(1n);
    assert.throws(() => below(rng, 0), RangeError);
    assert.throws(() => below(rng, -3), RangeError);
    assert.throws(() => below(rng, 2.5), RangeError);
  });
});
