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
│   ├── SteinregenRender/     (SpriteKit-Szene, Spielloop, Theme = Palette/Fonts/Korn/Nebel,
│   │                          Steine-Sets: StoneSets-Registry + SigilStones + DoomStones
│   │                          + ZaubersteineStones (svg/procedural/png), GemTextures =
│   │                          set-bewusste Textur-Fabrik, SoundFX = Soundeffekte, Magic-Animation)
│   └── SteinregenApp/        (SwiftUI-Shell: Startbildschirm, Einstellungen, Friedhof =
│                              Bestenliste/Persistenz, Steuerung, Game-Over)
└── Tests/
    └── SteinregenCoreTests/  (Determinismus, Treffer h/v/diagonal, Kaskade, Magic, Game-Over)
```

---

## 3. Technik

- **Sprache**: Swift 6
- **Plattform**: macOS 15+ (Core plattformneutral gehalten; iOS-Port als späterer Schritt denkbar)
- **UI**: SwiftUI · **Engine**: SpriteKit (via `SpriteView`) · **Build**: Swift Package Manager
- **Look (ab v0.2.0)**: Black-Metal-Ästhetik — rabenschwarz, knochenweiß, ein Ochsenblut-Akzent,
  räudiges Korn, **animierter Nebel** im Hintergrund (zwei gegenläufig driftende Wolken-Schichten,
  `GemTextures.fog()`). Die Steine werden **prozedural** gezeichnet, alle alten Edelstein-PNGs
  werden NICHT mehr ins Spiel geladen.
- **Steine-Sets (wählbar, erweiterbar)**: Jedes Set ist ein `StoneSet` (id + Name + Zeichen-Funktion)
  in der `StoneSets`-Registry. Aktuell fünf:
  - **„Sigille"** (`SigilStones`) — fein geritzte Zeichen, gedeckte Tönung (Black Metal).
  - **„Doom"** (`DoomStones`) — vollflächig gefüllt, kräftige Farben, Grunge/Blut/Kratzer.
  - **„Zaubersteine" / „G20" / „Juwelen"** (`ZaubersteineStones`) — komplett aus dem Schwester-Projekt
    *Zaubersteine* übernommen (svg = glänzende SVG-Steine, procedural = flache Tasten-Steine,
    png = Foto-Kristalle). Die freundliche Alternative zur Finsternis. 6 von dort 11 Farben gemappt
    (ruby/topaz/emerald/sapphire/amethyst + turquoise→`diamond`-Slot).
  - Auswahl im Einstellungsdialog (mit Live-Vorschau), persistiert via UserDefaults
    (`StoneSets.selectedID`), beim Spielstart in `GemTextures.activeSetID` übernommen.
    **Standard-Set: Doom** (steht im Dialog ganz oben).
  - **Neues Set hinzufügen**: einen Renderer schreiben (Datei wie `DoomStones.swift` kopieren) und
    EINEN Eintrag in `StoneSets.all` ergänzen — Spiel, Dialog und Vorschau ziehen automatisch nach.
- **Assets**: Die 6 Edelstein-PNGs (256×256, aus *Zaubersteine*) dienen dem App-Icon-Build
  (`tools/make-icon.sh`) UND dem „Juwelen"-Set (umgefärbte Foto-Kristalle). Dazu sechs
  `svg_*.png` (512×512) für das „Zaubersteine"-Set. Beide stammen aus dem Schwester-Projekt.
  `logo.png` = Start-Logo (weiß auf transparent, aus einem KI-generierten Schriftzug auf die
  Buchstaben getrimmt + Schwarz transparent gemacht); ersetzt im Startbildschirm den Pirata-One-
  Schriftzug (`Theme.logoImage()`, Fallback auf Text). Pirata One bleibt für Untertitel/HUD/Game-Over.
- **Soundeffekte**: 9 FreeDoom-WAVs (`ds*.wav`, BSD-3-Clause) + `FREEDOOM-LICENSE.txt` im Bundle,
  abgespielt über `SoundFX`. Zuordnung: Drehen `dstink`, Aufsetzen zyklisch
  `dsgetpow→dsoof→dsswtchn`, Auflösen `dspstop`, Game-Over zufällig `dspdiehi/dspldeth/dsdorcls`,
  Level `dswpnup`. Ton-Aus = „mundtot" (UserDefaults `steinregen.mundtot`, Taste **T**, Einstellungen).
  Kandidaten zum Probehören: `tools/get-sound-candidates.sh` + `tools/audition-sounds.sh`
  (laden nach `assets/sound-candidates/`, git-ignoriert).
  Zusätzlich im Bundle: **Pirata One** (Blackletter-Titel/HUD-Schrift) als `PirataOne-Regular.ttf`
  + `PirataOne-OFL.txt` (SIL Open Font License — muss mitgeliefert werden), zur Laufzeit über
  `Theme.registerFonts()` registriert. Die wiederverwendeten Bausteine (deterministischer PRNG,
  robuster Bundle-Loader ohne `Bundle.module`, das 3-Modul-Layout) stammen aus *Zaubersteine*.

### Build & Test

- Build: `swift build`
- **Tests**: `swift test` allein scheitert (CommandLineTools ohne XCTest). Xcode-Toolchain nutzen:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test`
- **Version**: Datei `VERSION` + Konstante `steinregenVersion` (Core) synchron halten; pro
  abgeschlossener Aufgabe committen + bumpen.
- **Doppelklickbare App**: `bash tools/make-app.sh` baut `dist/Steinregen.app` (mit Dock-Icon,
  ad-hoc-signiert) + `dist/Steinregen-<version>.zip`. Das Icon (`tools/AppIcon.icns`) wird bei
  Bedarf von `tools/make-icon.sh` **prozedural** erzeugt (Composer: `tools/icon-compose.swift`,
  Motiv: umgekehrtes Pentagramm im Kreis, satanisch). `dist/` und `tools/AppIcon.icns` sind
  git-ignoriert (reproduzierbar).

### Automations-/Headless-Naht

Die App liest beim Start Umgebungsvariablen (für automatische Screenshots / Smoke-Tests):

- `STEINREGEN_AUTOSTART=1` — startet sofort ein Spiel (überspringt das Menü)
- `STEINREGEN_LEVEL=<0..9>` — Start-Tempostufe
- `STEINREGEN_SEED=<UInt64>` — fester Seed (sonst zufällig)
- `STEINREGEN_SET=<id>` — Steine-Set (`sigil`/`doom`/`zaubersteine`/`g20`/`juwelen`)
- `STEINREGEN_SETTINGS=1` — öffnet beim Start direkt den Einstellungsdialog
- `STEINREGEN_FRIEDHOF=1` — öffnet beim Start direkt den Friedhof (Bestenliste)

Fenster-gezielter Screenshot ohne Fokus-Klau: Window-ID per CoreGraphics holen, dann
`screencapture -x -o -l <id>` (kein Fenster-nach-vorn nötig).

---

## 4. Spielkonzept

Faithful *Columns*: kein Bejeweled, sondern fallende Dreier-Säulen.

- **Spielfeld 6 Spalten × 13 Reihen.** Es fällt eine vertikale Säule aus 3 Steinen.
- **6 Steine**, unterschieden über ihr weißes **Sigil** (Form), nicht über Farbe — nahezu
  monochrom: `ruby` (umgekehrtes Pentagramm), `sapphire` (inverses Kreuz), `emerald` (Tiwaz-Rune),
  `topaz` (Triquetra), `diamond` (Schädel), `amethyst` (Mondsichel). Jeder Stein hat zusätzlich
  eine gedeckte, entsättigte Farb-Tönung als Zusatzhinweis. (Die internen Namen/Zieh-Reihenfolge
  stammen noch aus der Edelstein-Version.)
- **Treffer**: ≥ 3 gleiche Steine in einer Linie — **horizontal, vertikal oder diagonal**
  (beide Diagonalen) — werden geräumt. Anschließendes Nachrutschen kann **Ketten/Kaskaden** auslösen
  (stark belohnt: Punkte = geräumte Steine × 10 × Kettenstufe).
- **Magic Jewel** (selten, ~1 von 40 Säulen, deterministisch aus dem Seed): eine helle, durch alle
  sechs Sigille pulsierende Säule. Beim Aufsetzen räumt sie **brettweit die Sorte (Stein-Typ) der
  Zelle direkt darunter** weg (verpufft, wenn sie auf leerem Boden landet). Magic-Steine landen nie
  dauerhaft im Brett. — Bewusst klassisch-getreu umgesetzt.
- **Level/Tempo**: Start-Tempostufe wählbar (0–9). Das Level steigt mit der Zahl geräumter Steine
  (je 30 Steine +1); die Fallgeschwindigkeit nimmt mit dem Level zu (Mapping in `GameScene`).
- **Game Over**: Einwurf-Spalte (Mitte) oben blockiert.

### Steuerung

- **← →** oder **A D** — Säule horizontal bewegen
- **↑** oder **W** — Säule drehen (Steine zyklisch durchtauschen)
- **↓** oder **S** — schneller fallen (Softdrop, gehalten)
- **Leertaste** sofort fallen lassen (Hard-Drop)
- **T** Ton ein/aus (Aus-Modus heißt „mundtot"); **M** ist für späteres Musik-Ein/Aus reserviert
  (Musik gibt es noch nicht)
- **Esc** zurück ins Hauptmenü

Tastatur läuft über einen lokalen `NSEvent`-Monitor (in `GameplayView`), bewusst **fokus-unabhängig**
— sonst war die Steuerung nach Spielstart die ersten Sekunden tot (SwiftUI-Fokus kam zu spät).

---

## 5. Status (Stand 2026-06-21, v0.6.0)

Spielbarer Arcade-Endlosmodus mit wählbarer Start-Tempostufe, Highscore-Anzeige im
Sieg-/Game-Over-Overlay, Vorschau auf die nächste Säule, Magic Jewel, deterministische,
seed-getriebene Säulenfolge. Core vollständig unit-getestet. Doppelklickbares App-Bundle mit
Dock-Icon (`tools/make-app.sh`).

**v0.2.0 — Black-Metal-Redesign:** kompletter Look-Overhaul (schwarz/knochenweiß/Ochsenblut,
prozedurale Steine statt Edelstein-PNGs, animierter Nebel-Hintergrund, Blackletter-Schrift Pirata
One, räudiges Korn, grim-Texte „verreckt"/„Tod macht Fliegen aus uns allen"). Satanisches App-Icon
(umgekehrtes Pentagramm). **Wählbare, erweiterbare Steine-Sets** mit Einstellungsdialog +
Live-Vorschau. Erzwingt Dark-Mode. Spiellogik unverändert.

**v0.3.0 — drei weitere Steine-Sets** aus dem Schwester-Projekt *Zaubersteine* übernommen
(„Zaubersteine"/„G20"/„Juwelen", `ZaubersteineStones`) — die optisch angenehme Alternative
zur Black-Metal-Optik. Außerdem: **neues Start-Logo** (`logo.png`) ersetzt den Schriftzug.
Standard-Set jetzt **Doom**.

**v0.4.0 — Steuerung & Layout:** Tastatur fokus-unabhängig via `NSEvent`-Monitor (behebt
„Eingabe die ersten Sekunden tot"); zusätzlich **W/A/S/D** alternativ zu den Pfeiltasten.
Spielfeld nahezu **randlos** (kleineres Padding, Fenster-Default im Brett-Format, alles größer).

**v0.5.0 — Friedhof (Bestenliste):** persistente Top-16-Liste (`Friedhof.swift`, UserDefaults,
JSON). Name bis 16 Zeichen beim Game-Over (wenn der Score reicht), zweizeilige Grabstein-Einträge
(Rang · Name · Score / rot „verreckt in Level X" + Sterbedatum). Erreichbar im Game-Over-Overlay
und über den Menü-Button „Friedhof".

**v0.6.0 — Soundeffekte (FreeDoom, BSD-3):** Drehen/Aufsetzen (zyklisch)/Auflösen/Game-Over
(zufällig)/Level via `SoundFX`. In den Einstellungen an/aus (Aus = „mundtot"), im Spiel Taste **T**.
**Vorgemerkt:** Musik (Taste **M**) — gibt es noch nicht, kommt später.

**Naheliegende nächste Schritte (Ideen, nicht beauftragt):** persistenter Highscore (UserDefaults),
Seed-Anzeige/-Eingabe wie in Zaubersteine (Crockford-Base32), Sound (`AVFoundation`), Pause,
Developer-ID-Signatur + Notarisierung (für Weitergabe ohne Gatekeeper-Warnung), optionaler iOS-Port.
