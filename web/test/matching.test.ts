// matching.test.ts
// Prüft Treffer-Erkennung, Nachrutschen und Kaskade gegen die aufgezeichneten Partien.
//
// Das ist der eigentliche Wert der Vergleichsdaten: Statt sich Beispiele auszudenken, wird jede
// Räum-Welle nachgerechnet, die der Swift-Kern in einer echten Partie erzeugt hat — mit ihren
// Zellen, ihrer Kettenstufe, ihren Punkten und dem Brett danach.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { Board, CellSet, Gem, cell, isGem } from "../src/core/models.ts";
import {
  applyMagic,
  findGroups,
  findLines,
  findMatches,
  resolveCascade,
  settle,
  settlePinned,
} from "../src/core/matching.ts";
import { describeOwnStep, describeStep, locksOf } from "./replay.ts";

describe("Nachrutschen gegen die Vergleichsdaten", () => {
  it("„Schnitter“: nach dem Aufsetzen zerfallen die Spalten unabhängig", () => {
    // Der Schnitter räumt beim Aufsetzen nie — der Zustand nach dem Aufsetzen ist also genau
    // das nachgerutschte Brett. Damit prüft das hier `settle` ganz für sich allein.
    const locks = locksOf("schnitter");
    assert.ok(locks.length > 20, `zu wenige Aufsetzer geprüft: ${locks.length}`);
    for (const { caseId, lock, boardAfter } of locks) {
      const board = Board.decode(lock.boardBefore);
      settle(board);
      assert.equal(board.encode(), boardAfter, `${caseId}: Nachrutschen weicht ab`);
    }
  });

  it("„Blutklumpen“: ohne Treffer bleibt nur das Nachrutschen übrig", () => {
    const locks = locksOf("klumpen").filter((l) => l.lock.steps.length === 0);
    assert.ok(locks.length > 20, `zu wenige treffer-freie Aufsetzer: ${locks.length}`);
    for (const { caseId, lock, boardAfter } of locks) {
      const board = Board.decode(lock.boardBefore);
      settle(board);
      assert.equal(board.encode(), boardAfter, `${caseId}: Nachrutschen weicht ab`);
    }
  });

  it("„Austreibung“: die Flüche kleben an ihrem Platz", () => {
    // Hier zeigt sich, ob `settlePinned` stimmt: Steine rutschen nur bis AUF einen Fluch,
    // nie an ihm vorbei, und der Fluch selbst bewegt sich nie.
    const locks = locksOf("kapseln").filter((l) => l.lock.steps.length === 0);
    assert.ok(locks.length > 20, `zu wenige treffer-freie Aufsetzer: ${locks.length}`);
    for (const { caseId, lock, boardAfter, cursesBefore } of locks) {
      const board = Board.decode(lock.boardBefore);
      settlePinned(board, cursesBefore);
      assert.equal(board.encode(), boardAfter, `${caseId}: fluch-bewusstes Nachrutschen weicht ab`);
    }
  });
});

describe("Treffer-Kaskade gegen die Vergleichsdaten", () => {
  it("„Steinschlag“: Linien in allen vier Richtungen", () => {
    // Säulen rutschen vor der Suche nicht nach — die Kaskade beginnt direkt auf `boardBefore`.
    // Die Magic-Aufsetzer bleiben außen vor, die prüft der nächste Abschnitt.
    const locks = locksOf("saeulen").filter((l) => l.lock.wasMagic !== true);
    assert.ok(locks.length > 40, `zu wenige Aufsetzer geprüft: ${locks.length}`);
    let wavesChecked = 0;

    for (const { caseId, lock, boardAfter } of locks) {
      const board = Board.decode(lock.boardBefore);
      const result = resolveCascade({
        board,
        find: findMatches,
        settleBoard: settle,
        score: 0,
        gemsCleared: 0,
      });
      assert.deepEqual(
        result.steps.map(describeOwnStep),
        lock.steps.map(describeStep),
        `${caseId}: Räum-Wellen weichen ab`,
      );
      assert.equal(board.encode(), boardAfter, `${caseId}: Brett nach der Kaskade weicht ab`);
      wavesChecked += result.steps.length;
    }
    // Ohne echte Wellen prüfte der Vergleich nur leere Listen gegen leere Listen.
    assert.ok(wavesChecked >= 20, `zu wenige echte Räum-Wellen: ${wavesChecked}`);
  });

  it("„Blutklumpen“: verbundene Gruppen ab vier Steinen", () => {
    const locks = locksOf("klumpen").filter((l) => l.lock.steps.length > 0);
    assert.ok(locks.length > 5, `zu wenige Aufsetzer mit Treffern: ${locks.length}`);

    for (const { caseId, lock, boardAfter } of locks) {
      // Anders als bei den Säulen rutscht hier ZUERST nach (die beiden Hälften fallen
      // unabhängig), erst danach wird gesucht.
      const board = Board.decode(lock.boardBefore);
      settle(board);
      const result = resolveCascade({
        board,
        find: (b) => findGroups(b, 4),
        settleBoard: settle,
        score: 0,
        gemsCleared: 0,
      });
      assert.deepEqual(
        result.steps.map(describeOwnStep),
        lock.steps.map(describeStep),
        `${caseId}: Räum-Wellen weichen ab`,
      );
      assert.equal(board.encode(), boardAfter, `${caseId}: Brett nach der Kaskade weicht ab`);
    }
  });

  it("„Austreibung“: Vierer-Läufe ohne Diagonalen", () => {
    // Achtung, hier wird der Fluch-Bonus NICHT geprüft: In den aufgezeichneten Kapsel-Partien
    // liegt kein Treffer je auf einem Fluch (kein einziger Zustand ändert `curses`), der
    // `bonus`-Hook weiter unten liefert also durchweg 0. Diesen Fall deckt der gestellte Test
    // „ein getilgter Fluch bringt Bonus …“ im letzten Abschnitt ab.
    const locks = locksOf("kapseln").filter((l) => l.lock.steps.length > 0);
    assert.ok(locks.length > 3, `zu wenige Aufsetzer mit Treffern: ${locks.length}`);

    for (const { caseId, lock, boardAfter, cursesBefore } of locks) {
      const board = Board.decode(lock.boardBefore);
      const remaining = cursesBefore.clone();
      settlePinned(board, remaining);
      const result = resolveCascade({
        board,
        find: (b) => findLines(b, 4),
        settleBoard: (b) => settlePinned(b, remaining),
        // Getilgte Flüche werden VOR dem Nachrutschen ausgetragen — sie kleben dann nicht mehr.
        bonus: (cells) => {
          const cleared = remaining.intersection(cells);
          remaining.subtract(cleared);
          return cleared.length * 100;
        },
        score: 0,
        gemsCleared: 0,
      });
      assert.deepEqual(
        result.steps.map(describeOwnStep),
        lock.steps.map(describeStep),
        `${caseId}: Räum-Wellen weichen ab`,
      );
      assert.equal(board.encode(), boardAfter, `${caseId}: Brett nach der Kaskade weicht ab`);
    }
  });

  it("Magic Jewel räumt brettweit eine Farbe", () => {
    const locks = locksOf("saeulen").filter((l) => l.lock.wasMagic === true && l.lock.steps.length > 0);
    // In den Vergleichsdaten kommt genau ein solcher Aufsetzer vor (siehe golden/README.md) —
    // die Prüfung ist deshalb dünn und ersetzt keinen gezielten Test.
    assert.ok(locks.length >= 1, "kein Magic-Aufsetzer in den Vergleichsdaten");

    for (const { caseId, lock, boardAfter } of locks) {
      const board = Board.decode(lock.boardBefore);
      const first = lock.steps[0];
      assert.ok(first !== undefined && first.kind === "magic", `${caseId}: erste Welle ist keine Magic-Welle`);
      const color = first.color;
      assert.ok(color !== undefined && isGem(color), `${caseId}: Magic-Welle ohne Farbe`);

      const magic = applyMagic(board, color, 0, 0);
      assert.deepEqual(describeOwnStep(magic.step), describeStep(first), `${caseId}: Magic-Welle weicht ab`);

      // Danach läuft die normale Kaskade weiter — mit der Kettenstufe, die der Magic-Effekt
      // schon verbraucht hat.
      const rest = resolveCascade({
        board,
        startChain: 1,
        find: findMatches,
        settleBoard: settle,
        score: magic.score,
        gemsCleared: magic.gemsCleared,
      });
      assert.deepEqual(
        rest.steps.map(describeOwnStep),
        lock.steps.slice(1).map(describeStep),
        `${caseId}: Wellen nach dem Magic-Effekt weichen ab`,
      );
      assert.equal(board.encode(), boardAfter, `${caseId}: Brett nach dem Magic-Aufsetzer weicht ab`);
    }
  });
});

describe("Treffer-Regeln im Einzelnen", () => {
  it("findMatches zählt auch Diagonalen, findLines nicht", () => {
    // Dasselbe Brett, zwei Regeln: Die Diagonale ist für die Säulen ein Treffer,
    // für die Austreibung nicht.
    const board = Board.decode("..r/.r./r..");
    assert.deepEqual(findMatches(board), [cell(0, 0), cell(1, 1), cell(2, 2)]);
    assert.deepEqual(findLines(board, 3), []);
  });

  it("findMatches braucht mindestens drei", () => {
    assert.deepEqual(findMatches(Board.decode("rr.")), []);
    assert.deepEqual(findMatches(Board.decode("rrr")), [cell(0, 0), cell(1, 0), cell(2, 0)]);
  });

  it("findMatches ignoriert Magic-Steine", () => {
    // Magic-Steine liegen nie im Brett; falls doch, dürfen sie keinen Treffer bilden.
    const board = new Board(3, 1);
    board.set(0, 0, Gem.magic);
    board.set(1, 0, Gem.magic);
    board.set(2, 0, Gem.magic);
    assert.deepEqual(findMatches(board), []);
  });

  it("findGroups verbindet nur über die Seiten, nicht über Ecken", () => {
    // Vier gleiche Steine über Eck sind KEINE Gruppe …
    assert.deepEqual(findGroups(Board.decode(".r/r."), 2).length, 0);
    // … zwei nebeneinander schon.
    assert.deepEqual(findGroups(Board.decode("../rr"), 2).length, 2);
  });

  it("findLines beachtet die geforderte Lauflänge", () => {
    const board = Board.decode("rrr.");
    assert.deepEqual(findLines(board, 3).length, 3);
    assert.deepEqual(findLines(board, 4).length, 0);
  });

  it("settle lässt nichts überhängen", () => {
    const board = Board.decode("rt/../.e");
    settle(board);
    assert.equal(board.encode(), "../.t/re");
  });

  it("settlePinned hält Steine oberhalb eines Fluchs zurück", () => {
    // Ein Fluch (t) auf Reihe 1, darüber eine Lücke und ein loser Stein (r) ganz oben.
    // Ohne die Festnagelung fiele r bis auf den Boden; so kommt er nur bis AUF den Fluch.
    const board = Board.decode("r/./t/.");
    const pinned = new CellSet([cell(0, 1)]);
    settlePinned(board, pinned);
    assert.equal(board.encode(), "./r/t/.", "der Fluch (t) muss stehen bleiben, r darf nur bis auf ihn");

    // Gegenprobe ohne Festnagelung: Dann fällt r bis ganz nach unten auf den Fluch-Stein.
    const loose = Board.decode("r/./t/.");
    settle(loose);
    assert.equal(loose.encode(), "././r/t");
  });

  it("eine leere Menge festgenagelter Zellen verhält sich wie normales Nachrutschen", () => {
    const a = Board.decode("r/./t");
    const b = a.clone();
    settle(a);
    settlePinned(b, new CellSet());
    assert.equal(a.encode(), b.encode());
  });

  it("jede Welle hält ihr eigenes Brett fest", () => {
    // Ohne Kopie in `resolveCascade` zeigten am Ende alle Wellen auf denselben Endstand —
    // ein Fehler, den man in der Darstellung sofort sähe (nichts würde sich bewegen).
    const board = Board.decode("t../r../rrt/rtt");
    const result = resolveCascade({
      board,
      find: findMatches,
      settleBoard: settle,
      score: 0,
      gemsCleared: 0,
    });
    assert.ok(result.steps.length >= 2, `Kaskade zu kurz für diesen Test: ${result.steps.length}`);
    const boards = result.steps.map((s) => s.boardAfter.encode());
    assert.equal(new Set(boards).size, boards.length, "die Wellen teilen sich ein Brett");
  });

  it("„Austreibung“: ein getilgter Fluch bringt Bonus und nagelt danach nichts mehr fest", () => {
    // Gestelltes Brett, weil die Vergleichsdaten diesen Fall nicht enthalten: In allen
    // aufgezeichneten Kapsel-Partien wird kein einziger Fluch geräumt. Angelehnt an den
    // Swift-Test `CapsuleEngineTests.testRunOfFourClearsOnLockWithCurseBonus`, aber mit dem
    // losen Stein bewusst in der FLUCH-Spalte: Dort steht bei ihm nichts, deshalb fällt sein
    // Stein mit und ohne die Reihenfolge „Bonus vor dem Nachrutschen" gleich weit — die
    // Eigenschaft prüft er also gar nicht. Der Swift-Kern hat dafür inzwischen einen eigenen
    // Test (`testClearedCurseNoLongerPinsTheStoneAbove`), dieser hier ist sein Gegenstück.
    //   Reihe 0: vier Rubine; der linke (0,0) ist der Fluch, den der Vierer-Lauf tilgt.
    //   (0,2):   ein loser Topas. Er muss nach dem Räumen bis auf den Boden durchfallen —
    //            bliebe der getilgte Fluch festgenagelt, käme er nur bis (0,1).
    const board = Board.decode("t..../...../rrrr.");
    const remaining = new CellSet([cell(0, 0)]);

    // Wie im Kern: erst fluch-bewusst nachrutschen, dann die Kaskade auflösen.
    settlePinned(board, remaining);
    assert.equal(board.encode(), "...../t..../rrrr.", "der Topas bleibt auf dem Fluch liegen");

    const result = resolveCascade({
      board,
      find: (b) => findLines(b, 4),
      settleBoard: (b) => settlePinned(b, remaining),
      bonus: (cells) => {
        const cleared = remaining.intersection(cells);
        remaining.subtract(cleared);
        return cleared.length * 100;
      },
      score: 0,
      gemsCleared: 0,
    });

    assert.equal(result.steps.length, 1, "genau eine Räum-Welle");
    const step = result.steps[0];
    assert.ok(step !== undefined);
    assert.deepEqual(step.cells, [cell(0, 0), cell(1, 0), cell(2, 0), cell(3, 0)]);
    // 4 Steine × 10 × Kettenstufe 1 + ein getilgter Fluch × 100 Bonus = 140 — wie im Swift-Kern.
    assert.equal(step.points, 140);
    assert.equal(result.score, 140);
    assert.equal(result.gemsCleared, 4);
    assert.ok(remaining.isEmpty, "der geräumte Fluch ist aus der Fluch-Menge ausgetragen");
    // Und erst dadurch fällt der Topas ganz durch: Der Fluch klebt nicht mehr an (0,0).
    assert.equal(board.encode(), "...../...../t....");
    assert.equal(step.boardAfter.encode(), board.encode());
  });

  it("Punkte steigen mit der Kettenstufe", () => {
    // 10 Punkte je Stein, multipliziert mit der Kettenstufe.
    const board = Board.decode("t../r../rrt/rtt");
    const result = resolveCascade({
      board,
      find: findMatches,
      settleBoard: settle,
      score: 0,
      gemsCleared: 0,
    });
    result.steps.forEach((step) => {
      assert.equal(step.points, step.cells.length * 10 * step.chain);
    });
    assert.equal(result.score, result.steps.reduce((n, s) => n + s.points, 0));
  });
});
