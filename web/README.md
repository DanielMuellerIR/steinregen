# Steinregen Web — Portierung des Spielkerns nach TypeScript

Hier entsteht die Fassung des Spielkerns für eine mobile Webapp. Sie ist **kein Ersatz** für
`Sources/SteinregenCore`, sondern eine zweite Umsetzung derselben Regeln — geprüft gegen die
Vergleichsdaten in [`../golden/`](../golden/README.md), die der Swift-Kern erzeugt.

Der Grundsatz: **Die Swift-Fassung ist die Wahrheit.** Weicht diese Portierung ab, ist sie falsch,
nicht die Vorlage. Änderungen an den Spielregeln gehören zuerst in den Swift-Kern, danach werden
die Vergleichsdaten neu erzeugt und diese Portierung nachgezogen.

## Stand

| Baustein | Zustand |
|---|---|
| Zufallsgeneratoren (`src/core/prng.ts`) | fertig, gegen alle 10 Vektoren geprüft |
| Brett und Zellen (`src/core/models.ts`) | fertig, gegen rund 1100 aufgezeichnete Bretter geprüft |
| Treffer-Erkennung und Kaskade (`src/core/matching.ts`) | fertig, geprüft gegen jede Räum-Welle der drei Kaskaden-Modi (Steinschlag, Blutklumpen, Austreibung) |
| Punkte und Ziehung (`src/core/rules.ts`) | `points` und `draw` geprüft; `gemsPerLevel` ist bisher nur Gerüst für die Engines |
| die sechs Engines | offen |
| Darstellung, Bedienung, Ton | offen |

Was die Zeile zu `matching.ts` bewusst NICHT sagt: Die Reihen-Wellen von „Eingemauert"/„Erdrückt"
und die 19 Sensen-Ernten des „Schnitters" sind ungeprüft. Sie gehören zu Engines, die es hier noch
nicht gibt — `findLines` mit voller Reihe und das Ernten einer markierten Spaltensektion laufen
anders als eine Farb-Kaskade. Ausgezählt: 67 der 102 aufgezeichneten Wellen sind geprüft, die
übrigen 35 (16 Reihen-Wellen, 19 Ernten) nicht. Wer die Zeile als „alle Wellen geprüft" liest,
hält diese 35 fälschlich für abgesichert.

## Prüfen

```bash
npm install
npm test
npm run typecheck
```

Braucht Node 23.6 oder neuer: Node führt die TypeScript-Dateien direkt aus und entfernt die
Typangaben beim Laden. Deshalb gibt es hier kein Build-Werkzeug, und `tsconfig.json` dient allein
der Typprüfung (`noEmit`).

## Der Fallstrick, an dem diese Portierung hängt

JavaScript rechnet mit normalen Zahlen nur auf 53 Bit genau, die Generatoren brauchen aber volle
64 Bit. Deshalb `bigint` — und deshalb muss nach **jeder** Rechenoperation von Hand auf 64 Bit
zurechtgestutzt werden (`BigInt.asUintN(64, …)`). In Swift erledigen das die Operatoren `&+`, `&*`
und `<<` von selbst; BigInt dagegen lässt nichts überlaufen und rechnet unbegrenzt weiter. Fehlt
eine einzige dieser Beschneidungen, weicht schon der erste Wert ab.

Nachgemessen: Ein Aufruf kostet rund 100 ns. Ein Spielstein braucht ein bis vier Ziehungen — die
Geschwindigkeit von BigInt spielt für dieses Spiel also keine Rolle, und eine trickreichere
Umsetzung mit zwei 32-Bit-Hälften wäre unnötige Komplexität.

Ebenso wichtig: `below()` ist bewusst `next() % n` — dieselbe leicht schiefe Rechnung wie im
Swift-Kern. Sie darf **nicht** durch eine statistisch sauberere ersetzt werden, sonst zieht die
Webfassung andere Steinfarben als die Mac-App, und derselbe Seed ergäbe ein anderes Spiel.

## Der zweite Fallstrick: Wert gegen Verweis

In Swift ist `Board` ein Werttyp. `let vorher = board` legt dort eine **Kopie** an, und spätere
Änderungen am Original lassen `vorher` unberührt. In JavaScript zeigen nach derselben Zeile beide
Namen auf dasselbe Brett. Überall, wo der Swift-Kern sich auf dieses Kopieren verlässt — vor allem
beim Festhalten des Bretts je Räum-Welle —, steht hier ein ausdrückliches `clone()`.

Nachgeprüft, indem genau diese Kopie entfernt wurde: Drei Tests schlagen dann fehl, weil alle
Wellen einer Kaskade plötzlich denselben Endstand zeigen. In der fertigen Darstellung sähe man das
daran, dass sich beim Auflösen einer Kette nichts mehr bewegt.

Der zweite Unterschied derselben Art: Swift kann `Cell` in ein `Set` legen, weil Werte dort nach
Inhalt verglichen werden. JavaScript vergleicht Objekte nach Identität — `new Set([{col:1,row:2}])`
fände `{col:1,row:2}` nicht wieder. Dafür gibt es `CellSet`, das intern mit Zeichenketten arbeitet
und seine Zellen nur sortiert herausgibt.

## Was die Tests nicht abdecken

Die Abfrage auf den komplett leeren Generator-Zustand (`s0…s3 == 0`) lässt sich von außen nicht
auslösen, weil SplitMix64 für keinen Seed vier Nullen liefert. Nachgeprüft: Entfernt man sie,
bleibt die Testsuite grün. Sie steht im Code, weil der Swift-Kern sie ebenso enthält.

Die weiteren Lücken der Vergleichsdaten selbst stehen in
[`../golden/README.md`](../golden/README.md). In den aufgezeichneten Kapsel-Partien wird kein
einziger Fluch getilgt; der Fluch-Bonus und das Nachrutschen ohne den entfernten Fluch haben deshalb
einen eigenen Test mit gestelltem Brett in `test/matching.test.ts`. Nachgeprüft, indem der Bonus
versehentlich erst nach dem Nachrutschen verrechnet wurde: Genau dieser eine Test schlägt dann fehl,
alle anderen bleiben grün. Offen bleiben das gewonnene Kapsel-Spiel und der Magic Jewel (eine
Räumung plus ein verpuffender Aufsetzer in den Daten).

`applyMagic` hat eine offene Stelle, die keine Lücke der Daten ist, sondern der Portierung: Die
**Vorbedingung** des Magic Jewels — liegt unter der Aufsetzposition überhaupt ein Stein, und ist
er selbst kein Magic-Stein? — steht im Swift-Kern beim Aufrufer `Engine.lock()` und gehört
entsprechend in die Säulen-Engine. Ohne sie erzeugt ein verpuffender Magic-Stein hier eine Welle
mit null Zellen statt gar keiner.
