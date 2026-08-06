# Vergleichsdaten des Spielkerns

`steinregen-golden.json` hält den exakten Ablauf mehrerer Partien fest — Zug für Zug, mit Brett,
Punktestand und jeder Räum-Welle. Die Datei ist der Prüfmaßstab für eine Portierung des Kerns in
eine andere Sprache (geplant: TypeScript für eine mobile Webapp): Die Portierung spielt dieselbe
Befehlsfolge ab und muss Feld für Feld dasselbe liefern.

Erzeugt wird sie aus dem Swift-Kern:

```bash
bash tools/make-golden.sh
```

Prüfen, ob die eingecheckte Datei noch zum Kern passt (Exit-Code 1 bei Abweichung):

```bash
bash tools/make-golden.sh --check
```

Derselbe Vergleich läuft als Test in `Tests/SteinregenGoldenTests/GoldenDataTests.swift` und
schlägt fehl, sobald sich am Kern etwas ändert. **Die Datei bei einem Fehlschlag niemals blind neu
erzeugen** — erst prüfen, ob die Änderung am Kern gewollt war, dann neu erzeugen und den
Unterschied im Diff durchsehen.

## Aufbau

```jsonc
{
  "format": "steinregen-golden/1",   // Formatversion; steigt bei unverträglichen Änderungen
  "prng": [ … ],                     // Rohsequenzen der Zufallsgeneratoren
  "cases": [ … ]                     // die aufgezeichneten Partien
}
```

Eine Programmversion steht bewusst **nicht** in der Datei: Sie stünde nach jedem Versionssprung
anders da und erzwänge einen Neuaufbau, obwohl sich am Spiel nichts geändert hat — und genau daran
gewöhnt man sich das routinemäßige Neuerzeugen an, das der Wächter unten verhindern soll. Welcher
Stand die Datei erzeugt hat, sagt `git log -- golden/steinregen-golden.json`.

Der Rahmen ist eingerückt, aber **jeder Spielzustand belegt genau eine Zeile**. So bleibt die Datei
bei rund 1,3 MB und `git diff` zeigt trotzdem genau die Züge, die sich geändert haben.

### `prng` — hier zuerst anfangen

Der wichtigste Einzeltest. JavaScript rechnet nur mit 53 Bit genau und braucht für die
64-Bit-Arithmetik des Generators `BigInt`. Stimmen diese Zahlen nicht, stimmt hinterher gar nichts.

```jsonc
{"generator":"Xoshiro256StarStar","seed":"1","values":["12966619160104079557", …]}
```

Alle 64-Bit-Zahlen stehen als **Dezimalzahl in einer Zeichenkette**, nie als JSON-Zahl — sonst
würde JavaScript sie beim Einlesen still verfälschen. Die Seeds decken auch die Randfälle ab:
`0` (der xoshiro-Zustand darf nie komplett null sein — diese Sonderbehandlung übersieht eine
Portierung leicht) und `18446744073709551615` (der größte 64-Bit-Wert).

### `cases` — die Partien

```jsonc
{
  "id": "saeulen-a",
  "mode": "saeulen",          // stabile Modus-Kennung, siehe AGENTS.md
  "seed": "1",                // Seed des Spiels, als Zeichenkette
  "startLevel": 0,
  "width": 6, "height": 13,
  "scriptSeed": "…",          // Seed des zweiten Generators, der die Züge erzeugt hat;
                              // nur zur Nachvollziehbarkeit — zum Nachspielen unnötig
  "initial": { … },           // Zustand vor dem ersten Befehl
  "commands": "LGGGG…",       // die abgespielte Befehlsfolge, ein Zeichen je Befehl
  "snapshots": [ … ],         // ein Zustand je Befehl, in derselben Reihenfolge
  "curseCountAtStart": 4      // nur „Austreibung"
}
```

### Befehle

| Zeichen | Aufruf          | Bedeutung                                     |
|---------|-----------------|-----------------------------------------------|
| `L`     | `moveLeft()`    | eine Spalte nach links                        |
| `R`     | `moveRight()`   | eine Spalte nach rechts                       |
| `T`     | `rotate()`      | drehen                                        |
| `G`     | `gravityTick()` | ein Schritt Schwerkraft                       |
| `S`     | `spawnNext()`   | nächsten Stein einwerfen                      |
| `W`     | `sweepTick()`   | Sense eine Spalte weiter (nur „Schnitter")    |

### Zustand nach einem Befehl

```jsonc
{
  "i": 1,                     // laufende Nummer
  "cmd": "L",
  "ok": true,                 // Ergebnis von L/R/T/S — griff der Befehl?
  "board": "……/…r.",          // NUR vorhanden, wenn sich das Brett geändert hat
  "piece": { … },             // der aktive Stein
  "score": 0, "level": 0,
  "phase": "falling",         // falling | resolving | gameOver | won
  "cleared": 0,               // geräumte Steine bzw. Reihen (je nach Modus)
  "next": ["r","t","e"],      // Vorschau (Farben) …
  "nextType": "i",            // … bzw. Formname bei Vierling/Fünfling
  "lock": { … },              // nur wenn dieser Schritt den Stein einrasten ließ
  "harvest": { … },           // nur bei `W`, falls dabei geerntet wurde
  "sweepCol": 0,              // nur „Schnitter"
  "marked": [[0,0], …],       // nur „Schnitter", nur bei Änderung
  "curses": [[1,2], …]        // nur „Austreibung", nur bei Änderung
}
```

**Fehlt ein optionales Feld, gilt der vorige Stand unverändert weiter.** Das betrifft `board`,
`marked` und `curses` — sie stehen nur dann in der Zeile, wenn sie sich geändert haben. Ohne diese
Sparsamkeit wäre die Datei mehrfach so groß, denn ein Zug zur Seite ändert das Brett nie.

### Brett-Kodierung

Eine Zeichenkette: **oberste Reihe zuerst**, Reihen durch `/` getrennt, ein Zeichen je Zelle.

| Zeichen | Stein                  |
|---------|------------------------|
| `.`     | leere Zelle            |
| `r`     | Rubin (rot)            |
| `t`     | Topas (gold)           |
| `e`     | Smaragd (grün)         |
| `d`     | Diamant (türkis)       |
| `s`     | Saphir (blau)          |
| `a`     | Amethyst (violett)     |
| `m`     | Magic Jewel            |

Achtung beim Nachbauen: Die **Koordinaten** des Spiels beginnen unten links (`row` 0 ist die
unterste Reihe und wächst nach oben), die **Zeichenkette** beginnt dagegen oben — so liest sie sich
wie das Bild auf dem Schirm. Zellen stehen überall als `[Spalte, Reihe]` in Spielkoordinaten.

### Reihenfolge der Zellen

Hier lohnt ein genauer Blick, weil sie nicht überall dieselbe ist:

- `marked` und `curses` sind **immer sortiert** (erst Reihe, dann Spalte). Sie stammen aus Mengen,
  deren Speicher-Reihenfolge zufällig ist — ohne Sortierung sähe dieselbe Partie bei jedem Lauf
  anders aus.
- `cells` einer Räum-Welle steht dagegen **genau in der Reihenfolge, in der der Kern die Zellen
  einsammelt**, und wird hier bewusst nicht nachsortiert. Diese Reihenfolge ist sichtbar: Die
  Darstellung lässt die Steine in genau dieser Folge verschwinden. In den meisten Modi ist sie
  ohnehin die Brett-Reihenfolge, weil der Kern dort selbst sortiert (die Treffer stammen aus einer
  Menge). Nur im Modus „Blutklumpen" liefert die Flutfüllung die Zellen in ihrer eigenen Ordnung —
  eine Portierung muss sie also gleich durchlaufen, nicht bloß dieselbe Menge finden.

### Stein-Bauarten

| `kind`      | Modi                        | Felder                                      |
|-------------|-----------------------------|---------------------------------------------|
| `column`    | Steinschlag                 | `gems` (unten → oben)                       |
| `pair`      | Blutklumpen, Austreibung    | `gems` (Dreh-Stein, Satellit), `orientation`|
| `tetromino` | Eingemauert, Erdrückt       | `type`, `offsets` (Drehlage), `gems` (Deko) |
| `square`    | Schnitter                   | `gems` (unten-links, unten-rechts, oben-rechts, oben-links) |

## Wie die Züge entstanden sind

Ein zweiter Zufallsgenerator mit eigenem Seed steuert einen einfachen Spieler: Er dreht den Stein
null- bis dreimal und fährt dann die Spalte an, die er nach einer kleinen Bewertung für die beste
hält — gleiche Farben nebeneinander zählen mehr als eine flache Landung, im Kapsel-Modus zählt ein
gleichfarbiger Fluch nochmals mehr.

Diese Bewertung ist reine Aufzeichnungs-Mechanik und **kein Teil des Spiels**; sie muss nicht
portiert werden. Sie existiert, weil ein rein zufällig schiebender Spieler den Stapel hochtürmt und
verliert, bevor irgendetwas Interessantes passiert: Ein erster Versuch räumte in den Reihen-Modi
über 17 Aufsetzer hinweg keine einzige Reihe. Zum Nachspielen genügt in jedem Fall die fertige
Befehlsfolge in `commands`.

## Was diese Daten NICHT abdecken

Ehrlich benannt, damit die Portierung diese Punkte selbst prüft:

- **Der Sieg im Modus „Austreibung" (`phase: "won"`) kommt nicht vor.** Der einfache Spieler tilgt
  regelmäßig drei von vier Flüchen, aber nie den letzten; in 90 Probeläufen über verschiedene Seeds
  und Brettmaße gab es keinen Sieg. Die Regel selbst ist knapp — sind alle Flüche getilgt, wechselt
  die Phase auf `won` und es wird kein Stein mehr eingeworfen — aber sie braucht einen eigenen Test
  mit einem gestellten Brett.
- **Der Magic Jewel** kommt nur in `saeulen-b` vor (eine Räumung). Er erscheint im Schnitt bei
  jeder vierzigsten Säule; eine Portierung sollte ihn zusätzlich gezielt prüfen.
- **Lock Delay, Fallgeschwindigkeit und der Takt der Sense** stehen bewusst nicht hier: Sie sind
  Echtzeit-Verhalten der Darstellungsschicht, nicht des Kerns. Der Kern kennt nur den Schritt
  (`gravityTick`, `sweepTick`), nicht seine Dauer.
- **Sehr lange Partien.** Jeder Fall bricht nach 30 bis 60 aufgesetzten Steinen ab, damit die Datei
  handlich bleibt.
