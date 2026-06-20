# Steinregen — Agent-Regeln und Architektur

Dieses Repository enthält **Steinregen**, einen nativen macOS-Klon des Sega-Klassikers
*Columns* (1990), geschrieben in Swift. Geometrie/Logik sind deterministisch (seed-getrieben).

---

## 1. Wichtige Regeln für AI-Agenten

1. **Git**: `git add`/`commit`/`push`/`reset` nur auf ausdrückliche Anweisung. Nie Wildcard-Adden
   (`git add .`/`-A`) — Pfade einzeln stagen.
2. **Deterministische Engine**: Die Kernlogik liegt im Modul `SteinregenCore`. **Kein** globaler
   Zufall, **keine** Systemzeit/Wanduhr in `SteinregenCore`. Aller Zufall (Farbfolge der Säulen,
   Auftauchen des Magic Jewels) läuft über den injizierten PRNG (`Xoshiro256StarStar`). Gleicher
   Seed + gleiche Eingaben ⇒ exakt gleicher Spielverlauf. Zeitmessung/Fallgeschwindigkeit lebt
   ausschließlich in der Render-/App-Schicht.
3. **Kommentare**: Deutsch, ausführlich (anfängerfreundlich). Identifier Englisch.

---

## 2. Verzeichnisstruktur

```
steinregen/                   (SwiftPM-Workspace)
├── Package.swift
├── AGENTS.md                 (diese Datei)
├── CLAUDE.md                 (Symlink auf AGENTS.md)
├── LICENSE                   (MIT)
├── README.md                 (englisch)
├── README.de.md              (deutsch)
├── VERSION                   (synchron zu `steinregenVersion` in Core halten)
├── Sources/
│   ├── SteinregenCore/       (reine, deterministische Spiellogik + PRNG + Modelle)
│   ├── SteinregenRender/     (SpriteKit-Szene, Spielloop, PNG-Texturen, Magic-Jewel-Animation)
│   └── SteinregenApp/        (SwiftUI-Shell: Startbildschirm, Steuerung, Game-Over)
└── Tests/
    └── SteinregenCoreTests/  (Determinismus, Treffer h/v/diagonal, Kaskade, Magic, Game-Over)
```

---

## 3. Technik

- **Sprache**: Swift 6
- **Plattform**: macOS 15+ (Core plattformneutral gehalten; iOS-Port als späterer Schritt denkbar)
- **UI**: SwiftUI · **Engine**: SpriteKit (via `SpriteView`) · **Build**: Swift Package Manager
- **Assets**: 6 Edelstein-PNGs (256×256) — übernommen aus dem Schwester-Projekt *Zaubersteine*.
  Auch die wiederverwendeten Bausteine (deterministischer PRNG, robuster Bundle-/Textur-Loader
  ohne `Bundle.module`, das 3-Modul-Layout) stammen von dort.

### Build & Test

- Build: `swift build`
- **Tests**: `swift test` allein scheitert (CommandLineTools ohne XCTest). Xcode-Toolchain nutzen:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test`
- **Version**: Datei `VERSION` + Konstante `steinregenVersion` (Core) synchron halten; pro
  abgeschlossener Aufgabe committen + bumpen.

### Automations-/Headless-Naht

Die App liest beim Start Umgebungsvariablen (für automatische Screenshots / Smoke-Tests):

- `STEINREGEN_AUTOSTART=1` — startet sofort ein Spiel (überspringt das Menü)
- `STEINREGEN_LEVEL=<0..9>` — Start-Tempostufe
- `STEINREGEN_SEED=<UInt64>` — fester Seed (sonst zufällig)

Fenster-gezielter Screenshot ohne Fokus-Klau: Window-ID per CoreGraphics holen, dann
`screencapture -x -o -l <id>` (kein Fenster-nach-vorn nötig).

---

## 4. Spielkonzept

Faithful *Columns*: kein Bejeweled, sondern fallende Dreier-Säulen.

- **Spielfeld 6 Spalten × 13 Reihen.** Es fällt eine vertikale Säule aus 3 Steinen.
- **6 Farben** (Rainbow + Türkis): `ruby` (rot), `topaz` (gold), `emerald` (grün),
  `diamond` (türkis), `sapphire` (blau), `amethyst` (violett).
- **Treffer**: ≥ 3 gleichfarbige Steine in einer Linie — **horizontal, vertikal oder diagonal**
  (beide Diagonalen) — werden geräumt. Anschließendes Nachrutschen kann **Ketten/Kaskaden** auslösen
  (stark belohnt: Punkte = geräumte Steine × 10 × Kettenstufe).
- **Magic Jewel** (selten, ~1 von 40 Säulen, deterministisch aus dem Seed): eine durch alle
  Farben pulsierende Säule. Beim Aufsetzen räumt sie **brettweit die Farbe der Zelle direkt
  darunter** weg (verpufft, wenn sie auf leerem Boden landet). Magic-Steine landen nie dauerhaft
  im Brett. — Bewusst klassisch-getreu umgesetzt.
- **Level/Tempo**: Start-Tempostufe wählbar (0–9). Das Level steigt mit der Zahl geräumter Steine
  (je 30 Steine +1); die Fallgeschwindigkeit nimmt mit dem Level zu (Mapping in `GameScene`).
- **Game Over**: Einwurf-Spalte (Mitte) oben blockiert.

### Steuerung

- **← →** Säule horizontal bewegen
- **↑** Säule drehen (Farben zyklisch durchtauschen)
- **↓** schneller fallen (Softdrop, gehalten)
- **Leertaste** sofort fallen lassen (Hard-Drop)
- **Esc** zurück ins Hauptmenü

---

## 5. Status (Stand 2026-06-21, v0.1.0)

Erste spielbare Version: Arcade-Endlosmodus mit wählbarer Start-Tempostufe, Highscore-Anzeige
im Sieg-/Game-Over-Overlay, Vorschau auf die nächste Säule, Magic Jewel, deterministische,
seed-getriebene Säulenfolge. Core vollständig unit-getestet.

**Naheliegende nächste Schritte (Ideen, nicht beauftragt):** persistenter Highscore (UserDefaults),
Seed-Anzeige/-Eingabe wie in Zaubersteine (Crockford-Base32), Sound (`AVFoundation`), Pause,
App-Bundle + Notarisierung, optionaler iOS-Port.
