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
├── project.yml               (xcodegen-Spec der iOS-App; .xcodeproj wird daraus erzeugt, git-ignoriert)
├── Sources/
│   ├── SteinregenCore/       (reine, deterministische Spiellogik + PRNG + Modelle — plattformneutral)
│   ├── SteinregenRender/     (SpriteKit-Szene, Spielloop, Theme = Palette/Fonts/Korn/Nebel,
│   │                          Steine-Sets: StoneSets-Registry + SigilStones + DoomStones
│   │                          + ZaubersteineStones (svg/procedural/png), GemTextures =
│   │                          set-bewusste Textur-Fabrik, SoundFX = Soundeffekte, Magic-Animation
│   │                          — cross-platform: nur SKColor, keine AppKit/UIKit-Typen)
│   └── SteinregenApp/        (SwiftUI-Shell für macOS UND iOS: Startbildschirm, Einstellungen,
│                              Spielregeln, Friedhof, Game-Over; Steuerung per `#if os(...)` —
│                              macOS = Tastatur (NSEvent), iOS = Touch (Gesten + Knopfleiste))
└── Tests/
    └── SteinregenCoreTests/  (Determinismus, Treffer h/v/diagonal, Kaskade, Magic, Game-Over)
```

---

## 3. Technik

- **Sprache**: Swift 6
- **Plattform**: macOS 15+ (Desktop) UND **iOS 17+** (iPhone, ab v0.10.0). `SteinregenCore` +
  `SteinregenRender` sind plattformneutral und werden geteilt; nur die App-Schicht trennt per
  `#if os(...)` (macOS = Tastatur/NSEvent + Fenster, iOS = Touch + Vollbild).
- **UI**: SwiftUI · **Engine**: SpriteKit (via `SpriteView`) · **Build**: Swift Package Manager
- **Look (ab v0.2.0)**: Black-Metal-Ästhetik — rabenschwarz, knochenweiß, ein Ochsenblut-Akzent,
  räudiges Korn, **animierter Nebel** im Hintergrund (zwei gegenläufig driftende Wolken-Schichten,
  `GemTextures.fog()`). Die Steine werden **prozedural** gezeichnet, alle alten Edelstein-PNGs
  werden NICHT mehr ins Spiel geladen.
- **Steine-Sets (wählbar, erweiterbar)**: Jedes Set ist ein `StoneSet` (id + Name + Zeichen-Funktion)
  in der `StoneSets`-Registry. Aktuell sechs:
  - **„Sigille"** (`SigilStones`) — fein geritzte Zeichen, gedeckte Tönung (Black Metal).
  - **„Doom"** (`DoomStones`) — vollflächig gefüllt, kräftige Farben, Grunge/Blut/Kratzer.
  - **„Zaubersteine" / „G20" / „Juwelen"** (`ZaubersteineStones`) — komplett aus dem Schwester-Projekt
    *Zaubersteine* übernommen (svg = glänzende SVG-Steine, procedural = flache Tasten-Steine,
    png = Foto-Kristalle). Die freundliche Alternative zur Finsternis. 6 von dort 11 Farben gemappt
    (ruby/topaz/emerald/sapphire/amethyst + turquoise→`diamond`-Slot).
  - **„FreeDoom"** (`FreeDoomStones`) — sechs originale FreeDoom-Pixel-Sprites (BSD-3-Clause), zur
    Laufzeit BRUTAL ins Tile gequetscht (Bounding-Box-Crop + Cover + Oben-Anker + Nearest-Neighbor)
    auf dunklem Tile: rotes Gibs, Flamme, Marine, Cyberdemon, God-Gesicht, Pain-Fratze. Kuratiert
    mit `tools/freedoom-contact.swift`.
  - Auswahl im Einstellungsdialog (mit Live-Vorschau), persistiert via UserDefaults
    (`StoneSets.selectedID`), beim Spielstart in `GemTextures.activeSetID` übernommen.
    **Standard-Set: Doom** (steht im Dialog ganz oben).
  - **Neues Set hinzufügen**: einen Renderer schreiben (Datei wie `DoomStones.swift` kopieren) und
    EINEN Eintrag in `StoneSets.all` ergänzen — Spiel, Dialog und Vorschau ziehen automatisch nach.
- **Assets**: Die 6 Edelstein-PNGs (256×256, aus *Zaubersteine*) dienen dem App-Icon-Build
  (`tools/make-icon.sh`) UND dem „Juwelen"-Set (umgefärbte Foto-Kristalle). Dazu sechs
  `svg_*.png` (512×512) für das „Zaubersteine"-Set. Beide stammen aus dem Schwester-Projekt.
  `logo.png` = Start-Logo (weiß auf transparent, aus einem KI-generierten Schriftzug auf die
  Buchstaben getrimmt + Schwarz transparent gemacht); zeigt im Startbildschirm das Black-Metal-Logo
  als **Bild** (`Theme.logoImage()`, Fallback auf Text in der UI-Schrift). Das Logo-Bild bleibt
  bewusst unangetastet — alle übrigen Texte laufen in der gotischen UI-Schrift (siehe unten).
- **Soundeffekte**: 9 FreeDoom-WAVs (`ds*.wav`, BSD-3-Clause) + `FREEDOOM-LICENSE.txt` im Bundle,
  abgespielt über `SoundFX`. Zuordnung: Drehen `dstink`, Aufsetzen zyklisch
  `dsgetpow→dsoof→dsswtchn`, Auflösen `dspstop`, Game-Over zufällig `dspdiehi/dspldeth/dsdorcls`,
  Level `dswpnup`. Ton-Aus = „mundtot" (UserDefaults `steinregen.mundtot`, Taste **T**, Einstellungen).
  Kandidaten zum Probehören: `tools/get-sound-candidates.sh` + `tools/audition-sounds.sh`
  (laden nach `assets/sound-candidates/`, git-ignoriert).
  Zusätzlich im Bundle: **Grenze Gotisch** (gotische Titel-/UI-/HUD-Schrift, modernes gut lesbares
  Blackletter — ab v0.8.0 statt Pirata One) als `GrenzeGotisch-Regular.ttf` + `GrenzeGotisch-Bold.ttf`
  + `GrenzeGotisch-OFL.txt` (SIL Open Font License — muss mitgeliefert werden), zur Laufzeit über
  `Theme.registerFonts()` registriert (`Theme.blackletterFamily`/`blackletterPostScript`/`blackletterBoldPostScript`;
  der Name „blackletter" bleibt, passt aber weiter — Grenze Gotisch IST ein Blackletter). Einzige
  Ausnahme: die Tasten-/Pfeil-Spalte der Steuerungs-Legende bleibt System-Mono (Grenze hat keine
  Pfeil-Glyphen ←↑→↓). Die wiederverwendeten Bausteine (deterministischer PRNG,
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
- **iOS-App (iPhone)**: SwiftPM kann kein iOS-App-Bundle erzeugen → `bash tools/make-ios-app.sh`
  erzeugt per **xcodegen** aus `project.yml` ein Xcode-Projekt (`Steinregen.xcodeproj`, git-ignoriert)
  und baut die App fürs iOS-Simulator-SDK. `bash tools/make-ios-app.sh run` installiert + startet sie
  zusätzlich headless im Simulator (`STEINREGEN_SIM` wählt das Gerät, Default „iPhone 17");
  Screenshot ohne Fokus-Klau: `xcrun simctl io <udid> screenshot out.png`. Voraussetzung: volles
  Xcode (nicht nur CommandLineTools) + `xcodegen` (`brew install xcodegen`). Die env-Vars unten
  (`STEINREGEN_*`) gelten auch auf iOS — beim `simctl launch` als `SIMCTL_CHILD_<VAR>` voranstellen.

### Automations-/Headless-Naht

Die App liest beim Start Umgebungsvariablen (für automatische Screenshots / Smoke-Tests):

- `STEINREGEN_AUTOSTART=1` — startet sofort ein Spiel (überspringt das Menü)
- `STEINREGEN_LEVEL=<1..10>` — Start-Tempostufe
- `STEINREGEN_SEED=<UInt64>` — fester Seed (sonst zufällig)
- `STEINREGEN_SET=<id>` — Steine-Set (`sigil`/`doom`/`zaubersteine`/`g20`/`juwelen`/`freedoom`)
- `STEINREGEN_SETTINGS=1` — öffnet beim Start direkt den Einstellungsdialog
- `STEINREGEN_FRIEDHOF=1` — öffnet beim Start direkt den Friedhof (Bestenliste)

Fenster-gezielter Screenshot ohne Fokus-Klau: Window-ID per CoreGraphics holen, dann
`screencapture -x -o -l <id>` (kein Fenster-nach-vorn nötig).

---

## 4. Spielkonzept

Faithful *Columns*: kein Bejeweled, sondern fallende Dreier-Säulen.

- **Spielfeld 6 Spalten × 13 Reihen.** Es fällt eine vertikale Säule aus 3 Steinen. Die Säule
  **schwebt von oben ein** (ab v0.8.0, abweichend vom Original): Einwurf-Reihe `spawnRow = height-1`,
  d. h. anfangs steht nur der unterste Stein in der obersten Brettreihe, die zwei oberen Segmente
  liegen noch über dem Brett (unsichtbar) und tauchen beim Fallen Reihe für Reihe auf.
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
- **Level/Tempo**: Start-Tempostufe wählbar (1–10, 1-basiert). Das Level steigt mit der Zahl geräumter Steine
  (je 30 Steine +1); die Fallgeschwindigkeit nimmt mit dem Level zu (Mapping in `GameScene`).
- **Game Over**: Einwurf-Spalte (Mitte) oben blockiert.
- **Lock-Delay** (Sega-Style): nach dem Aufsetzen ein kurzes Korrektur-Fenster (`lockDelay`, aktuell
  0,42 s in `GameScene`), in dem die Säule noch geschoben/gedreht werden kann; bekommt sie dabei
  wieder Luft, fällt sie normal weiter. **Jede gelungene Korrektur frischt das Fenster auf**
  (Move-Reset: `lockDelayAccumulator = 0` in `inputLeft/Right/Rotate`). **Hard-Drop** (Leertaste)
  fixiert nicht sofort, sondern öffnet das **halbe Fenster** (`hardDropLockDelay`, 0,21 s) für eine
  Last-Minute-Korrektur. Core-Abfrage: `Engine.canFall()`.

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

## 5. Status (Stand 2026-06-22, v0.10.2)

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

**v0.6.1 — Bugfixes:** Fenster auf festes Seitenverhältnis gesperrt (`WindowConfigurator`,
`NSWindow.contentAspectRatio`) + Szene-Größe beim Start an den View angeglichen → keine verzerrten
Steine mehr. Level ist jetzt **1-basiert** (Start-Tempo 1–10, kein „Level 0" mehr; `fallInterval`
rechnet mit `level-1`).

**v0.7.0 — Lock-Delay + Game-Over-Optik:** kurzes Korrektur-Fenster (0,3 s) nach dem Aufsetzen
(`Engine.canFall()` + `lockDelay`). Game-Over-Overlay deutlich lesbarer: größere/kontrastreichere
Schrift, echte Tafel mit Ochsenblut-Rahmen statt mattem Material.

**v0.7.1 — Lock-Delay-Feel + „Verreckt":** Korrektur-Fenster auf **0,42 s** verlängert (0,3 s war
real kaum zu treffen) und **Move-Reset** ergänzt — jede Korrektur (Schieben/Drehen) frischt das
Fenster auf, statt dass es ab dem ersten Aufsetzen unaufhaltsam abläuft. **Hard-Drop** (Leertaste)
fixiert nicht mehr sofort, sondern öffnet ein **halbes Fenster** (0,21 s, `hardDropLockDelay`).
Außerdem: „verreckt" → **„Verreckt"** (großes V) in Game-Over-Banner/-Overlay + Grabstein-Zeile.

**v0.8.0 — Säule schwebt von oben ein:** statt alle drei Segmente sofort oben am Schacht zu zeigen,
wird die Säule eine Reihe tiefer eingeworfen (`spawnRow = height-1`). Anfangs ist nur der unterste
Stein sichtbar (oberste Brettreihe); die zwei oberen Segmente liegen über dem Brett (im Core als
freie Zellen behandelt, vom Renderer ausgeblendet) und gleiten beim Fallen Reihe für Reihe herein.
Bewusste Abweichung vom Original (dort erscheint die Säule komplett). Game-Over-Abfrage greift
dadurch erst, wenn die oberste Brettreihe der Einwurf-Spalte belegt ist; Core-Tests unverändert grün.
Außerdem Sprach-/Text-Politur: das Bethlehem-Zitat „Tod macht Fliegen aus uns allen" wandert vom
Startbildschirm in den Game-Over-Screen (Grabspruch unter dem Punktestand, Overlay etwas breiter);
HUD-Label „als nächstes" → „als Nächstes" (Duden-korrekte Nominalisierung).
**Schrift komplett auf `Grenze Gotisch`** (modernes, gut lesbares Blackletter; Pirata One war als
Großbuchstabe schwer zu entziffern — F sah aus wie f). Ersetzt sowohl das alte Pirata One ALS AUCH
den schmucklosen System-Font (San Francisco) in der gesamten UI — HUD, Menü, Einstellungen, Friedhof,
Game-Over, Buttons; Regular + fetter Schnitt (`blackletterBoldPostScript`) für Titel/Score. Pirata-
One-Assets entfernt. Logo-**Bild** bleibt unangetastet. Einzige Ausnahme: die Tasten-/Pfeil-Spalte
der Steuerungs-Legende bleibt System-Mono (Grenze hat keine Pfeil-Glyphen).
**Layout-Umbau (ebenfalls v0.8.0):** Fenster breiter (670×900), Spielbrett **mittig** mit zwei
Seiten-Panels — links Punkte/Level, rechts „als Nächstes" mit **senkrechter** Vorschau (vorher
waagerecht). Neue hellere Blutrot-Farbe `Theme.blood` (RGB 0.82/0.20/0.17) für **lesbaren** roten
Text auf Dunkel (Game-Over, Grabstein); das dunklere `oxblood` bleibt für Rahmen/Striche/Tints.
Durchgehend etwas größere Schriften.

**v0.8.0 — Feinschliff (Review-Runde):**
- **Erfolgs-Feedback** im Spiel: bei Kettenreaktionen blendet groß werdend „2× / 3× / 4× …" ein
  (Rot ab Kette 3), große Einzel-Räumungen zeigen „N!"; der Magic-Stein blendet beim Aufsetzen
  einen dezenten Erklärtext ein (`showCombo` + Magic-Info in `GameScene`).
- **Neuer Menüpunkt „Spielregeln"** (`RulesSheet`) — erklärt Ziel/Treffer/Ketten/Steuerung/
  Magic-Stein/Tempo (es gibt genau EINEN Spezialstein).
- **Eigener Auto-Repeat** fürs horizontale Bewegen (in der Szene: `startMove`/`stopMove` + `moveDir`
  im `update`, DAS 0,17 s / ARR 0,05 s) — unabhängig von der OS-Tastenwiederholung, deterministisch.
- **Tastaturbedienung der Menüs**: im Startbildschirm wählen ← → das Start-Tempo (eigene
  ◀ Level N ▶-Steuerung statt System-Stepper, kein Fokusrahmen); im Game-Over steuern ↑↓/←→ die
  drei Knöpfe, Return löst aus, die Auswahl zeigt ein Ochsenblut-Hintergrund (kein Fokusrahmen).
  Beides über fokus-unabhängige `NSEvent`-Monitore (wie im Spiel).
- **Schrift-Untergrenze 18 pt** programmweit (alle vorher ≤16 pt angehoben); Logo (feste Höhe, damit
  es nicht mehr von Nachbar-Elementen gequetscht wird) und Menü-Buttons größer.
- **Highscore-Liste vereinfacht**: einzeilig (`Rang. Name … Punktzahl`), ohne Karte/Rahmen/grauen
  Hintergrund direkt auf Schwarz, „Verreckt in Level …" + Sterbedatum aus der Anzeige entfernt
  (bleiben persistiert). Das Game-Over-Overlay zeigt bis zu 8 Einträge OHNE Scrollbar
  (`FriedhofView.scroll`-Schalter; das eigene Friedhof-Fenster bleibt scrollbar). Name weiterhin
  bis 16 Zeichen, in der Zeile bei Bedarf mit „…" gekürzt.

**v0.9.0 — Steine-Set „FreeDoom":** sechstes, bild-basiertes Set aus originalen FreeDoom-Grafiken
(BSD-3-Clause): rotes Gibs (`col5`), Flamme (`fcan`), Marine (`play`), Cyberdemon (`cybr`),
God-Gesicht (`stfgod`, aus `graphics/`), Pain-Elemental-Fratze (`pain`). Die Sprites sind winzig
(Doom-Auflösung) und werden zur Laufzeit BRUTAL ins Tile gequetscht: auf die sichtbaren Pixel
zugeschnitten (Bounding-Box), füllend (cover), mit Oben-Anker (unten anschneiden → Köpfe/Gesichter
bleiben) + Pro-Stein-Feinjustage (zoom/ybias), harte Pixelkanten (Nearest-Neighbor) auf dunklem Tile
(`FreeDoomStones`). Lizenz verifiziert + in `FREEDOOM-LICENSE.txt` dokumentiert (deckt Sounds UND
Grafiken; kommerziell ok, Attribution nötig). Kuratierung über `tools/freedoom-contact.swift`
(Kontaktbögen roh/gequetscht/farbsortiert mit Empfehlungs-Markierung). Die fd_*.png sind unveränderte
Originale (nur umbenannt), der Zuschnitt passiert im Renderer.

**v0.10.0 — iOS-App (iPhone):** zweite App mit identischem Funktionsumfang auf demselben Code.
`SteinregenCore` + `SteinregenRender` sind unverändert geteilt (waren bereits plattformneutral: nur
`SKColor`, keine AppKit/UIKit-Typen). Die App-Schicht `SteinregenApp.swift` ist jetzt plattform-
conditional (`#if os(macOS)` / `#if os(iOS)`) — **macOS bleibt byte-identisch** (NSEvent-Tastatur,
NSWindow-Seitenverhältnis), iOS bekommt **Touch-Steuerung**: Gesten über dem Brett (Tippen = drehen,
links/rechts wischen = ein Schritt, runter wischen = Hard-Drop) plus eine dezente Knopfleiste unten
(◀ ▶ halten = Auto-Repeat via `startMove`/`stopMove`, Drehen, Softdrop halten, Hard-Drop) und einen
Menü-Knopf oben links; die Dialoge laufen über `dialogFrame` bildschirmfüllend statt im festen
Sheet-Maß. Das Brett rendert dank `scaleMode = .resizeFill` + adaptivem `layout()` unverzerrt
(quadratische Kacheln, zentriert). Build/Run: `tools/make-ios-app.sh` (xcodegen → Xcode-Projekt →
Simulator). Im iPhone-17-Simulator verifiziert: Menü, Gameplay (Brett + Touch-Leiste), Einstellungen
sowie die **gesamte Touch-Steuerung** per `idb` (headless Touch-Injektion): Bewegen ◀▶ inkl.
Halten/Auto-Repeat, Rotieren (Knopf + Brett-Tippen), Hard-Drop (Knopf + Wisch nach unten),
Wisch-Bewegen. Hinweis: ein 0-ms-Synthetik-Tap löst SwiftUIs `Button`/`onTapGesture` nicht aus
(`DragGesture`-Knöpfe schon) — ein echter Finger mit ~100 ms greift, reines Test-Artefakt, kein
App-Bug. **Noch offen:** iOS-App-Icon (Asset-Catalog fehlt → blankes Icon); Gerätesignatur; iPad-Layout.

**v0.10.1 — iOS-Politur:** Im Spiel füllt das Steinregen-Logo den freien Raum über dem Brett
(zwischen Menü-Knopf und Schacht) — rein dekorativ (`allowsHitTesting(false)`, Tippen dreht dort
weiter), nur iOS (`TouchControlsOverlay`). macOS unverändert.

**v0.10.2 — iOS-Touch-Layout:** Logo deutlich größer (nutzt den oberen Freiraum voll, ohne in den
Schacht zu ragen — Menü-Knopf liegt jetzt auf eigener `topLeading`-Ebene). Steuerleiste über die
volle Breite verteilt (◀ ganz links, ▶ ganz rechts, ↻/▼/⤓ gleichmäßig dazwischen) und Knöpfe größer
(54→64 pt). Nur iOS; macOS unverändert. Im iPhone-17-Simulator verifiziert (inkl. ✕ → Menü).

**Beauftragte TODOs (Stand 2026-06-22):**
- **iOS-App (iPhone):** ✅ Grundgerüst + Touch-Steuerung erledigt und im Simulator verifiziert
  (v0.10.0, siehe oben); teilt Core+Render mit macOS. **Rest:** iOS-App-Icon, Gerätesignatur,
  ggf. iPad-Layout + Test auf echtem Gerät.
- **Weitere Steine-Sets generieren** — ✅ erledigt für FreeDoom (Set „FreeDoom", v0.9.0; Lizenz
  verifiziert + dokumentiert). Weitere Sets jederzeit möglich (Renderer + ein `StoneSets.all`-Eintrag).
- **Zweites Sound-Set:** mit den (noch in Arbeit befindlichen) SFX-Generierungs-Werkzeugen ein
  eigenes Soundeffekt-Set erzeugen — Werkzeug wird ca. ab 2026-06-22 verfügbar sein.
- **Veröffentlichbarkeit prüfen** — ✅ auditiert (Stand 2026-06-22), Bestandsaufnahme in
  [THIRD-PARTY-ASSETS.md](THIRD-PARTY-ASSETS.md). **Non-kommerziell ist sauber** (eigener Code MIT;
  FreeDoom-WAVs **und** -Grafiken BSD-3, Grenze Gotisch OFL, Edelstein-Assets Eigenwerk, Logo aus
  lokalem FLUX.1 [dev]). README-Doku-Bugs gefixt (Pirata One → Grenze Gotisch, FreeDoom-Grafiken in
  der Attribution, „six sets", `freedoom`-ID). **Offene Blocker NUR für eine spätere kommerzielle
  Verbreitung** (kein Hindernis für non-kommerziell): (1) `logo.png` aus FLUX.1 [dev] = nicht-
  kommerzielle Lizenz → Output-Rechte prüfen oder Logo ersetzen; (2) Bethlehem-Zitat „Tod macht
  Fliegen aus uns allen" (Album-/Songtitel 1994) ersetzen/freigeben; (3) Sega/Columns-Trademark-
  Disclaimer prominent halten. Details + Checkliste in THIRD-PARTY-ASSETS.md.
- **Git-History bereinigen vor Erstveröffentlichung** — History auf persönliche/private Daten
  durchsuchen, dann gezielt entfernen (history-rewrite) oder vor dem ersten Public-Push squashen.

**Naheliegende nächste Schritte (Ideen, nicht beauftragt):** persistenter Highscore (UserDefaults),
Seed-Anzeige/-Eingabe wie in Zaubersteine (Crockford-Base32), Sound (`AVFoundation`), Pause,
Developer-ID-Signatur + Notarisierung (für Weitergabe ohne Gatekeeper-Warnung).
