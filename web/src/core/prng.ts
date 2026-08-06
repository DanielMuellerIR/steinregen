// prng.ts
// Die deterministischen Zufallsgeneratoren des Spiels — Portierung von
// `Sources/SteinregenCore/PRNG.swift`.
//
// Warum das der erste portierte Baustein ist: Der ganze Determinismus des Spiels haengt an
// diesen beiden Funktionen. Gleicher Seed muss exakt dieselbe Zahlenfolge liefern wie in Swift,
// sonst faellt jede weitere Regel auseinander — andere Steinfarben, andere Treffer, andere
// Punkte. Geprueft wird das gegen `golden/steinregen-golden.json` (siehe test/prng.test.ts).
//
// Der Fallstrick in JavaScript: Die normale Zahl (`number`) rechnet nur mit 53 Bit genau, die
// Generatoren brauchen aber volle 64 Bit. Deshalb `bigint`. BigInt rechnet beliebig genau und
// laesst nichts ueberlaufen — in Swift verwerfen `&+`, `&*` und `<<` die oberen Bits von selbst.
// Genau das muss hier von Hand passieren, sonst wachsen die Zahlen unbegrenzt weiter und die
// Folge stimmt schon ab dem zweiten Wert nicht mehr. Dafuer steht `u64()` unten, das nach JEDER
// Rechnung auf 64 Bit zurechtstutzt.

/// Schneidet einen Wert auf 64 Bit ohne Vorzeichen zurecht — das Gegenstueck zum stillen
/// Ueberlauf von `&+`/`&*`/`<<` in Swift.
const u64 = (value: bigint): bigint => BigInt.asUintN(64, value);

/// Rotiert `x` um `k` Stellen nach links (die oben herausfallenden Bits kommen unten wieder
/// herein). Entspricht `rotl` in PRNG.swift.
function rotl(x: bigint, k: bigint): bigint {
  return u64((x << k) | (x >> (64n - k)));
}

/// Gemeinsame Schnittstelle beider Generatoren: eine Quelle von 64-Bit-Zufallszahlen.
export interface RandomNumberGenerator {
  /// Die naechste Zahl im Bereich 0 … 2^64−1.
  next(): bigint;
}

/**
 * 64-Bit-Zustands-Generator (SplitMix64). Einfach und schnell; dient auch dazu, den groesseren
 * xoshiro-Generator mit einem Seed zu „verteilen“.
 */
export class SplitMix64 implements RandomNumberGenerator {
  #state: bigint;

  constructor(seed: bigint) {
    this.#state = u64(seed);
  }

  next(): bigint {
    this.#state = u64(this.#state + 0x9e3779b97f4a7c15n);
    let z = this.#state;
    z = u64((z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n);
    z = u64((z ^ (z >> 27n)) * 0x94d049bb133111ebn);
    return z ^ (z >> 31n);
  }
}

/**
 * 256-Bit-Zustands-Generator (xoshiro256** 1.0). Das ist der eigentliche Spiel-Generator — er
 * bestimmt die Farbfolge der fallenden Steine, das Auftauchen des Magic Jewels und die
 * Fluch-Vorbefuellung im Kapsel-Modus.
 */
export class Xoshiro256StarStar implements RandomNumberGenerator {
  #s0: bigint;
  #s1: bigint;
  #s2: bigint;
  #s3: bigint;

  constructor(seed: bigint) {
    // Seed ueber SplitMix64 auf 256 Bit Zustand „aufblasen“.
    const sm = new SplitMix64(seed);
    this.#s0 = sm.next();
    this.#s1 = sm.next();
    this.#s2 = sm.next();
    this.#s3 = sm.next();

    // Der Zustand darf nicht komplett 0 sein — sonst liefert der Generator fuer immer nur
    // Nullen. Dieser Zweig ist ueber den Konstruktor NICHT erreichbar: SplitMix64 gibt fuer
    // keinen Seed viermal hintereinander 0 zurueck. Er steht hier, weil PRNG.swift ihn ebenso
    // enthaelt und weil ein anderer Weg, den Zustand zu setzen, ihn braeuchte. Kein Test kann
    // ihn ausloesen — entfernt man ihn, bleibt die Testsuite gruen.
    if (this.#s0 === 0n && this.#s1 === 0n && this.#s2 === 0n && this.#s3 === 0n) {
      this.#s0 = 1n;
    }
  }

  next(): bigint {
    const result = u64(rotl(u64(this.#s1 * 5n), 7n) * 9n);
    const t = u64(this.#s1 << 17n);

    this.#s2 ^= this.#s0;
    this.#s3 ^= this.#s1;
    this.#s1 ^= this.#s2;
    this.#s0 ^= this.#s3;

    this.#s2 ^= t;
    this.#s3 = rotl(this.#s3, 45n);

    return result;
  }
}

/**
 * Eine Zahl aus `0 … bound−1`.
 *
 * Das ist genau die Rechnung, die der Swift-Kern ueberall benutzt (`rng.next() % UInt64(n)`),
 * und sie muss buchstabengetreu dieselbe bleiben. Sie ist statistisch leicht schief — die
 * niedrigen Reste kommen minimal haeufiger vor —, aber das ist hier gleichgueltig und darf auf
 * keinen Fall „verbessert“ werden: Jede andere Rechnung ergaebe eine andere Steinfolge und
 * damit ein anderes Spiel als die Mac-Fassung.
 */
export function below(rng: RandomNumberGenerator, bound: number): number {
  if (!Number.isInteger(bound) || bound <= 0) {
    throw new RangeError(`Obergrenze muss eine positive ganze Zahl sein, war: ${bound}`);
  }
  return Number(rng.next() % BigInt(bound));
}
