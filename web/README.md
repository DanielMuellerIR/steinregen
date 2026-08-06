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
| Brett, Treffer-Erkennung, Nachrutschen | offen |
| die sechs Engines | offen |
| Darstellung, Bedienung, Ton | offen |

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

## Was die Tests nicht abdecken

Die Abfrage auf den komplett leeren Generator-Zustand (`s0…s3 == 0`) lässt sich von außen nicht
auslösen, weil SplitMix64 für keinen Seed vier Nullen liefert. Nachgeprüft: Entfernt man sie,
bleibt die Testsuite grün. Sie steht im Code, weil der Swift-Kern sie ebenso enthält.

Die weiteren Lücken der Vergleichsdaten selbst — kein gewonnenes Kapsel-Spiel, Magic Jewel nur
einmal — stehen in [`../golden/README.md`](../golden/README.md) und brauchen hier später eigene
Tests mit gestelltem Brett.
