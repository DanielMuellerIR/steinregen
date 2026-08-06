// board.test.ts
// Prüft das Brett gegen die Vergleichsdaten — und gegen den Fallstrick, der bei einer
// Portierung von Swift nach JavaScript am ehesten zuschlägt: das Kopierverhalten.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { Board, CellSet, Gem, cell, sortCells } from "../src/core/models.ts";
import { allBoards } from "./replay.ts";

describe("Brett-Kodierung gegen die Vergleichsdaten", () => {
  it("jedes aufgezeichnete Brett übersteht Einlesen und Ausgeben unverändert", () => {
    const boards = allBoards();
    // Wenn hier nichts ankommt, prüft der Test nichts — das wäre der stille Ausfall. Die
    // Schranke liegt bewusst deutlich unter dem Ist-Stand (rund 900), damit sie nicht bei
    // jeder kleinen Änderung an den Vergleichsdaten anschlägt.
    assert.ok(boards.length > 500, `zu wenige Bretter geprüft: ${boards.length}`);
    for (const text of boards) {
      assert.equal(Board.decode(text).encode(), text);
    }
  });

  it("liest die Reihenfolge richtig: die erste Zeile ist OBEN", () => {
    // Der Klassiker beim Nachbauen: Die Zeichenkette beginnt oben, die Koordinaten unten.
    // Wer das verwechselt, dreht jedes Brett auf den Kopf, ohne dass ein Rundlauf es merkt.
    const board = Board.decode("r./..");
    assert.equal(board.get(0, 1), Gem.ruby, "der Rubin gehört in die OBERE Reihe (row 1)");
    assert.equal(board.get(0, 0), null);
  });

  it("weist kaputte Zeichenketten zurück", () => {
    assert.throws(() => Board.decode("rr/r"), /Ungleich lange Reihen/);
    assert.throws(() => Board.decode("rx"), /Unbekanntes Stein-Zeichen/);
    assert.throws(() => Board.decode(""), /Leere Brett-Zeichenkette/);
  });
});

describe("Brett-Grundlagen", () => {
  it("eine Kopie ist unabhängig vom Original", () => {
    // In Swift ist `Board` ein Werttyp: `let kopie = board` kopiert. In JavaScript zeigen beide
    // Namen auf dasselbe Objekt. Überall, wo der Swift-Kern sich auf das Kopieren verlässt,
    // steht in der Portierung `clone()` — dieser Test hält fest, dass das auch wirkt.
    const original = Board.decode("../r.");
    const copy = original.clone();
    copy.set(1, 1, Gem.topaz);
    assert.equal(original.get(1, 1), null, "das Original wurde mitverändert");
    assert.equal(copy.get(0, 0), Gem.ruby, "die Kopie hat den Inhalt nicht übernommen");
  });

  it("kennt seine Grenzen", () => {
    const board = new Board(3, 2);
    assert.ok(board.inBounds(0, 0) && board.inBounds(2, 1));
    assert.ok(!board.inBounds(-1, 0) && !board.inBounds(3, 0) && !board.inBounds(0, 2));
  });

  it("zählt belegte Zellen und findet Farben", () => {
    const board = Board.decode("r.t/rr.");
    assert.equal(board.filledCount, 4);
    assert.deepEqual(board.cellsOf(Gem.ruby), [cell(0, 0), cell(1, 0), cell(0, 1)]);
    assert.deepEqual(board.cellsOf(Gem.topaz), [cell(2, 1)]);
  });

  it("fits: oberhalb des Bretts ist frei, unterhalb und seitlich nicht", () => {
    // Die Steine schweben von oben ein — deshalb gelten Reihen über dem Brett als frei.
    const board = Board.decode("../r.");
    assert.ok(board.fits([{ cell: cell(1, 0) }]), "freie Zelle");
    assert.ok(!board.fits([{ cell: cell(0, 0) }]), "belegte Zelle");
    assert.ok(board.fits([{ cell: cell(0, 5) }]), "oberhalb des Bretts gilt als frei");
    assert.ok(!board.fits([{ cell: cell(0, -1) }]), "unter dem Boden");
    assert.ok(!board.fits([{ cell: cell(2, 0) }]), "rechts daneben");
  });
});

describe("Zellen-Menge", () => {
  it("vergleicht nach Inhalt, nicht nach Identität", () => {
    // Genau hierfür gibt es die Klasse: `new Set([{col:1,row:2}]).has({col:1,row:2})` wäre
    // in JavaScript `false`, weil zwei gleich aussehende Objekte verschieden sind.
    const set = new CellSet([cell(1, 2)]);
    assert.ok(set.has(cell(1, 2)), "dieselbe Zelle wurde nicht wiedergefunden");
    assert.ok(!set.has(cell(2, 1)), "vertauschte Koordinaten gelten als dieselbe Zelle");
  });

  it("gibt ihre Zellen in Brett-Reihenfolge heraus", () => {
    // Erst Reihe, dann Spalte — davon hängt ab, dass geräumte Zellen immer gleich aussehen.
    const set = new CellSet([cell(2, 3), cell(0, 0), cell(1, 3), cell(5, 0)]);
    assert.deepEqual(set.sorted(), [cell(0, 0), cell(5, 0), cell(1, 3), cell(2, 3)]);
  });

  it("bildet Schnittmengen und zieht ab", () => {
    const set = new CellSet([cell(0, 0), cell(1, 1), cell(2, 2)]);
    assert.deepEqual(set.intersection([cell(1, 1), cell(9, 9)]), [cell(1, 1)]);
    set.subtract([cell(0, 0), cell(2, 2)]);
    assert.deepEqual(set.sorted(), [cell(1, 1)]);
  });

  it("die Kopie ist unabhängig", () => {
    const set = new CellSet([cell(0, 0)]);
    const copy = set.clone();
    copy.add(cell(1, 1));
    assert.equal(set.size, 1);
    assert.equal(copy.size, 2);
  });

  it("sortCells liefert eine neue Liste und lässt die Eingabe in Ruhe", () => {
    const input = [cell(2, 0), cell(0, 0)];
    const sorted = sortCells(input);
    assert.deepEqual(sorted, [cell(0, 0), cell(2, 0)]);
    assert.deepEqual(input, [cell(2, 0), cell(0, 0)], "die Eingabe wurde umsortiert");
  });
});
