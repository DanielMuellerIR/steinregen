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
│   ├── SteinregenCore/       (reine, deterministische Spiellogik + PRNG + Modelle — plattformneutral;
│   │                          DREI Engines: Engine = Säulen/Columns, TetrominoEngine = Verschüttet,
│   │                          PairEngine = Klumpen/Steinpaare)
│   ├── SteinregenRender/     (SpriteKit-Szene, Spielloop, Theme = Palette/Fonts/Korn/Nebel,
│   │                          PlayEngine = modusneutrales Protokoll über alle Engines (GameScene
│   │                          treibt Säulen + Verschüttet + Klumpen mit einem Code-Pfad),
│   │                          Steine-Sets: StoneSets-Registry + SigilStones + DoomStones
│   │                          + ZaubersteineStones (svg/procedural/png), GemTextures =
│   │                          set-bewusste Textur-Fabrik, SoundFX = Soundeffekte, MusicPlayer =
│   │                          Hintergrundmusik (getrennt schaltbar), L10n = Lokalisierung de/en,
│   │                          Magic-Animation
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
- **Plattform**: macOS 15+ (Desktop) UND **iOS 17+** (iPhone ab v0.10.0, iPad ab v0.11.0 — beide nur
  Hochformat). `SteinregenCore` + `SteinregenRender` sind plattformneutral und werden geteilt; nur die
  App-Schicht trennt per `#if os(...)` (macOS = Tastatur/NSEvent + Fenster, iOS = Touch + Vollbild).
  Innerhalb iOS unterscheidet `UIDevice.userInterfaceIdiom == .pad` das Touch-Layout (iPhone vs. iPad).
- **UI**: SwiftUI · **Engine**: SpriteKit (via `SpriteView`) · **Build**: Swift Package Manager
- **Look (ab v0.2.0)**: Black-Metal-Ästhetik — rabenschwarz, knochenweiß, ein Ochsenblut-Akzent,
  räudiges Korn. **Hintergrundbilder (ab v0.20.0, Pool ab v0.21.0)**: KI-generierte Nebel-bei-Nacht-
  Motive (`hintergrund.png` plus `hintergrund-2.png` … `hintergrund-5.png`, Qwen-Image, kommerziell
  unbedenklich) liegen formatfüllend (Cover) ganz hinten hinter dem Brett. `Theme.backdropImages()`
  lädt ALLE vorhandenen `hintergrund*.png` (eine weitere `hintergrund-N.png` ins Bundle legen genügt),
  `GameScene` wählt pro Partie zufällig eines (`backdropIndex`, in `start()` gesetzt, über Resizes
  stabil) und `GameScene.buildBackdrop()` zeichnet es. **Ersetzt** den früheren prozeduralen, animiert
  driftenden Nebel (`GemTextures.fog()` entfernt). Die Steine werden **prozedural** gezeichnet, alle
  alten Edelstein-PNGs werden NICHT mehr ins Spiel geladen.
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
- **Musik (ab v0.21.0)**: drei instrumentale Stücke (Downfall-of-Gaia-Stil, lokal mit ACE-Step
  erzeugt, kommerziell unbedenklich) als `musik-1.mp3`/`musik-2.mp3`/`musik-3.mp3` im Bundle,
  abgespielt über `MusicPlayer` (eigene Datei, `AVAudioPlayer` + Delegate). Laufen NACHEINANDER in
  Schleife, pro Partie zufälliger Einstieg. **Getrennt von den Soundeffekten**: eigener Schalter
  (UserDefaults `steinregen.musik.aus`, Taste **M**, Einstellungs-Karte „Musik"), **standardmäßig
  AN**, spielt aber **nur im laufenden Spiel** (nicht im Menü) — die App-Schicht ruft
  `MusicPlayer.shared.gameStarted()` beim Levelbeginn (`startGame`) und `gameEnded()` bei der
  Rückkehr ins Menü (`goToMenu`). Reine Render-/Präsentationsschicht, kein Core-Bezug.
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
  git-ignoriert (reproduzierbar). `make-app.sh` kennt zwei optionale env-Schalter (Default
  unverändert): `SIGN_ID` (echte Signatur mit Hardened Runtime statt ad-hoc) und `SKIP_ZIP=1`.
- **Notarisierte App (Weitergabe ohne Gatekeeper-Warnung)**: `bash tools/make-notarized.sh` baut die
  App, signiert sie mit **Developer ID + Hardened Runtime**, reicht sie bei Apple zur **Notarisierung**
  ein (`notarytool submit --wait`), heftet das Ticket an (`stapler staple`) und packt
  `dist/Steinregen-<version>-notarized.zip`. Nutzt intern `make-app.sh` (kein Code-Duplikat).
  Voraussetzungen **pro Mac** (Schlüsselbund wird nicht gesynct): Developer-ID-Application-Zertifikat
  in der Login-Keychain + notarytool-Keychain-Profil. Identität/Profil per env überschreibbar
  (`SIGN_ID`, `NOTARY_PROFILE`, Default-Profil `steinregen-notary`). Das notarytool-Keychain-Profil
  einmalig anlegen mit `xcrun notarytool store-credentials` (Apple-ID + Team-ID + App-spezifisches Passwort).
- **Notarisiertes DMG / Release**: `bash tools/make-dmg.sh` baut die Developer-ID-signierte App in
  ein DMG mit Hintergrundbild (`assets/dmg-background.png`, erzeugt von
  `tools/generate-dmg-background.swift`) + Applications-Shortcut, signiert/notarisiert/stapelt es →
  `dist/Steinregen-<version>.dmg`. `--no-notarize` baut ein unsigniertes Test-DMG (Layout-Check ohne
  Zertifikat). `--publish` setzt Tag `v<version>` und legt das GitHub-Release mit dem DMG an (Notes
  aus `CHANGELOG.md`). **Konvention: Ein Release/DMG entsteht nur bei `VERSION`-Bump — reine
  README-/Doku-/Mini-Änderungen ohne Bump erzeugen kein neues DMG.** Notar-Profil-Default
  `steinregen-notary` (per `NOTARY_PROFILE` überschreibbar).
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
- `STEINREGEN_MODE=<modus>` — Spielmodus (`saeulen` = Columns, im Menü „Steinschlag"; `verschuettet`
  = Vierlinge, im Menü „Eingemauert"; `klumpen` = Steinpaare, im Menü „Blutklumpen"; Default
  `saeulen`). Die env-/UserDefaults-IDs bleiben bewusst `saeulen`/`verschuettet`/`klumpen` — nur die
  Anzeige-Namen heißen Steinschlag/Eingemauert/Blutklumpen.
- `STEINREGEN_ENDLESS=1` — konstantes Tempo (Fallgeschwindigkeit bleibt auf der Start-Tempostufe)
- `STEINREGEN_MUSIC=<0|1>` — Musik aus (`0`) bzw. erzwungen an (`1`); ohne die Variable gilt der
  persistierte Default (an). Praktisch für stille Screenshot-/Smoke-Test-Läufe.
- `STEINREGEN_LANG=<de|en>` — erzwingt die Sprache (sonst System-Sprache bzw. gespeicherte Wahl).
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
- **Lock-Delay** (einfache, feste Regel — Stand v0.23.14): Sobald der Stein zum ersten Mal nicht
  mehr fallen kann (Berührung), startet `settleTimer` in `GameScene`. Er läuft in Echtzeit und wird
  von **nichts** zurückgesetzt — Drehen/Schieben ändern ihn nicht. Nach `lockDelay` (0,6 s) rastet
  der Stein ein, bzw. nach `hardDropLockDelay` (0,21 s), wenn er per **Hard-Drop** (Leertaste)
  gesetzt wurde. **Drehen bremst das Fallen nicht** (Schwerkraft läuft im `update` unabhängig weiter).
  Fixiert wird **nur, wenn der Stein wirklich aufliegt** (`canFall == false`): hat er bei Ablauf noch
  Luft (z. B. zur Seite neben einen Stein gezogen), fällt er **normal weiter** und rastet erst am
  echten Aufsetzpunkt ein — **kein Instant-Slam nach unten**.
  **Bewusst KEIN Move-Reset, keine „neue tiefste Reihe"-Ausnahme, keine Obergrenze** — der Zeitpunkt
  steht ab der ersten Berührung fest (sonst ließe sich das Einrasten durch Dauer-Rotieren beliebig
  hinauszögern; Wunsch Daniel 2026-07-01). Core-Abfrage: `Engine.canFall()`. Headless-Tests:
  `Tests/SteinregenRenderTests/LockDelayTests.swift`.

### Steuerung

- **← →** oder **A D** — Säule horizontal bewegen
- **↑** oder **W** — Säule drehen (Steine zyklisch durchtauschen)
- **↓** oder **S** — schneller fallen (Softdrop, gehalten)
- **Leertaste** sofort fallen lassen (Hard-Drop)
- **T** Soundeffekte ein/aus (Aus-Modus heißt „mundtot"); **M** Musik ein/aus (getrennt von den
  Soundeffekten — ab v0.21.0)
- **Esc** zurück ins Hauptmenü

Tastatur läuft über einen lokalen `NSEvent`-Monitor (in `GameplayView`), bewusst **fokus-unabhängig**
— sonst war die Steuerung nach Spielstart die ersten Sekunden tot (SwiftUI-Fokus kam zu spät).

---

## 5. Status (Stand 2026-07-02, v0.24.0)

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
**Musik** (Taste **M**) folgte in v0.21.0 (siehe unten).

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
App-Bug. **Test auf echtem Gerät:** ✅ erledigt (2026-06-22) — läuft auf zwei echten iPhones.

**v0.10.1 — iOS-Politur:** Im Spiel füllt das Steinregen-Logo den freien Raum über dem Brett
(zwischen Menü-Knopf und Schacht) — rein dekorativ (`allowsHitTesting(false)`, Tippen dreht dort
weiter), nur iOS (`TouchControlsOverlay`). macOS unverändert.

**v0.10.2 — iOS-Touch-Layout:** Logo deutlich größer (nutzt den oberen Freiraum voll, ohne in den
Schacht zu ragen — Menü-Knopf liegt jetzt auf eigener `topLeading`-Ebene). Steuerleiste über die
volle Breite verteilt (◀ ganz links, ▶ ganz rechts, ↻/▼/⤓ gleichmäßig dazwischen) und Knöpfe größer
(54→64 pt). Nur iOS; macOS unverändert. Im iPhone-17-Simulator verifiziert (inkl. ✕ → Menü).

**v0.10.2/.3 — iOS-Signing + App-Icon:** Automatisches Geräte-Signing (`CODE_SIGN_STYLE=Automatic`,
`DEVELOPMENT_TEAM` aus der Umgebung — `make-ios-app.sh` leitet die Team-ID aus dem lokalen
Apple-Development-Zertifikat ab, nichts Kontoidentifizierendes im Repo; **Team-ID = OU des Zerts,
NICHT die Klammer im CN** — die ist die Member-/Zert-ID und ergibt ein falsches Team). **iOS-App-Icon** (umgekehrtes
Pentagramm, full-bleed/deckend) über denselben Composer wie macOS: `tools/icon-compose.swift … ios`
erzeugt `iOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` (git-ignoriert, von
`make-ios-app.sh` reproduzierbar; Asset-Catalog-Metadaten im Repo). Auf dem Simulator-Home-Screen
verifiziert.

**v0.11.0 — iPad-Support:** `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad, beide Hochformat). Das
Touch-Layout passt sich per `UIDevice.userInterfaceIdiom == .pad` an: auf iPad wird das Brett
vertikal eingerückt (Platz für Logo oben / Steuerleiste unten), das Logo ist größer, und die fünf
Knöpfe bilden eine **zentrierte Gruppe** mit festen Abständen (statt der vollen Breite wie auf dem
iPhone — sonst stünden sie unerreichbar an den Rändern). Wichtig gelernt: Im `ZStack(.topLeading)`
muss die Inhalts-`VStack` `maxWidth: .infinity` haben, sonst schrumpft sie auf ihr breitestes Kind und
rutscht nach links (fiel auf iPhone nicht auf, weil die Spacer-Leiste die VStack ohnehin füllt). Auf
iPad-Air-11-Simulator verifiziert; iPhone-Layout unverändert. **v0.11.1:** Einzug oben/unten
vergrößert (240/188 pt), damit das Brett spürbar kleiner ist und Logo bzw. Steuerleiste klar
freistehen (vorher saßen sie direkt an der Brett-Kante) — auf iPad weiterhin gut spielbar groß. **v0.11.2:**
Logo auf iPad spürbar vergrößert — im Menü (`StartView`, 660×320 statt 480×210) und im Spiel
(620×210 statt 540×150, Brett-Einzug oben entsprechend auf 290).

**v0.12.0 — eigene, lokal erzeugte Soundeffekte:** die bisherigen FreeDoom-WAVs durch **selbst
generierte Klänge** ersetzt (lokal mit dem offenen Audio-Modell *Stable Audio 3* erzeugt). Im
Bundle liegen jetzt kleine Mono-`.m4a`-Dateien (AAC): je ein Effekt für Drehen (`drehen.m4a`),
Auflösen (`aufloesen.m4a`), Aufsetzen (`aufsetzen-1.m4a`, kurz, scharfer Attack, führende Stille
getrimmt → kein hörbares Delay) und Level (`level.m4a`) sowie ein **Zufalls-Pool aus sieben**
Game-Over-Klängen (`gameover-1.m4a` … `gameover-7.m4a`). `SoundFX` wählt Lade- bzw.
Game-Over-Klang zufällig, aber **ohne direkte Wiederholung**; der Loader lädt jetzt `.m4a` statt
`.wav`. Die neun ungenutzten FreeDoom-`.wav` entfernt (kleineres Bundle). README (de/en) und
`FREEDOOM-LICENSE.txt` entsprechend korrigiert: die Sounds stammen **nicht mehr aus FreeDoom**
(die FreeDoom-Lizenz bleibt nur noch für das Sprite-Set „FreeDoom"). Spiellogik unverändert.

**v0.13.0 — wählbares Klang-Set in den Einstellungen:** Ton-Schalter und Klang-Auswahl zu **einer**
Karte zusammengefasst — drei Optionen **Steinregen** (die eigenen Klänge aus v0.12.0), **Freedoom**
und **Mundtot** (stumm), gesetzt in der Theme-Schrift (kein System-Picker, kein Stilbruch). Bedienbar
per Maus **und** Tastatur (Fokus + ← → wählt, Leertaste bestätigt). `SoundFX` kennt damit zwei
Klang-Sets (eigene / freedoom) und merkt sich die Wahl (persistiert). Die FreeDoom-Klänge wurden aus
der Git-Historie **zurückgeholt** und als kleine Mono-AAC (`.m4a`, 2–22 KB) wieder eingebunden, sodass
beide Sets verfügbar sind. Außerdem Einstellungs-Politur: die Steine-Liste ist jetzt per ↑ ↓
navigierbar, die Steine-Karten zeigen nur noch Name/Vorschau/Marker (ohne Beschreibung), und das
Steine-Set „FreeDoom" rückt auf Platz 2.

**v0.14.0 — frei konfigurierbare Brettgröße (Core):** die Brettmaße sind jetzt Instanz-Werte
(`Board.width`/`height`) statt feste Konstanten — `Engine(seed:startLevel:width:height:)`, Default
weiterhin 6×13. Matching/Settle/Spawn rechnen über die echten Maße. Vorbereitung für den zweiten
Modus und frei einstellbare Bretter. Spiellogik bei 6×13 unverändert, Core-Tests grün.

**v0.15.0 — zweite Engine „Verschüttet" (Core):** eigene, parallele Spiel-Engine für den
Vierling-Modus (`TetrominoEngine` + `Tetromino`): sieben klassische Formen, CW-Drehung in der N×N-Box,
deterministischer 7-bag (jede Form einmal pro Beutel, seed-gemischt), volle Reihen räumen + Blöcke
nachrutschen (keine Kette), Punkte 100/300/500/800 × Level, Game-Over, einfache Wall-Kicks. Default
10×18, einstellbar. Die Columns-Engine bleibt **völlig unberührt** — beide teilen nur `Board`/`Gem`/
`Phase`/`ClearStep`/PRNG. +13 Core-Tests. Bewusst markenfrei („Tetromino" = geometrischer Gattungs-
begriff).

**v0.16.0 — Render treibt BEIDE Modi (Phase 3):** neues schmales Protokoll **`PlayEngine`**
(in der Render-Schicht) mit retroaktiver Conformance für `Engine` UND `TetrominoEngine`; `GameScene`
spricht nur noch dieses Protokoll und treibt damit Säulen **und** Verschüttet mit EINEM Code-Pfad.
Modusneutrale Typen: `StepResult` (`.moved`/`.locked(before:steps:magicLanding:)`), `activeCells`
(aktive Stein-Zellen in Brett-Koordinaten, inkl. der über dem Brett schwebenden Säulen-Segmente, die
der Renderer ausblendet) und `PreviewShape` (`.columns`/`.tetromino`). **Variable Brettmaße im
Renderer:** Layout, Raster, Brett-Render und Nachrutsch-Animation laufen über `engine.board.width/height`
statt feste Konstanten; `gemNodes`/`pieceNodes` sind dynamisch dimensioniert. Die HUD-Vorschau hat
zwei Pfade — Säulen (drei gestapelte Steine, **pixelgleich** zu vorher) und Verschüttet (die nächste
Form als Mini-Shape). Modus vorerst nur über die Test-Naht `STEINREGEN_MODE=saeulen|verschuettet`
wählbar (UI-Modus-Wahl folgt). Säulen 6×13 per Vorher/Nachher-Screenshot als **optisch unverändert**
verifiziert (nur das ohnehin zufällige Korn-Overlay flackert), Verschüttet headless gesichtet.
Die beiden Modi heißen **Säulen** (bestehender Columns-Modus) und **Verschüttet** (neuer Vierling-Modus).

**v0.16.1 — Mipmaps für die glatten Steine-Sets:** `GemTextures.makeTexture` aktiviert für die
gemalten/foto-artigen Sets `usesMipmaps` → sauberes (statt flimmerndes) Verkleinern auf kleinen
Kacheln großer Bretter (Verschüttet 10×18, frei eingestellte Maße). Das pixelige Set **FreeDoom
bleibt ohne Mipmaps** (harte Retro-Kanten bleiben erhalten). Säulen 6×13 dadurch optisch unverändert
(große Kacheln → kein sichtbarer Effekt), per Screenshot bestätigt.

**v0.17.0 — Modus-Wahl im Startbildschirm (Phase 4, Teil 1):** der Spielmodus ist jetzt direkt im
Menü wählbar — zwei Chips **Säulen** / **Verschüttet** (gewählter in Ochsenblut), mit einzeiligem
Hinweis, im Stil des Tempo-Wählers (Theme-Schrift, kein System-Control). Bedienbar per Maus/Touch
**und** auf macOS per **↑ ↓** (← → bleiben fürs Tempo; fokus-unabhängiger `NSEvent`-Monitor).
`startGame` reicht den Modus an `GameScene.start(mode:)` durch. Die Steuerungs-Legende ist
modus-abhängig („Säule" vs. „Vierling" bewegen/drehen). **iOS-Layout:** der Startbildschirm liegt
auf iOS jetzt in einer zentrierenden `ScrollView` (`minHeight = Bildschirmhöhe`) — der zusätzliche
Modus-Block kann das iPhone-Menü höher als den Schirm machen; so bleibt alles erreichbar und
**alle bestehenden Element-Maße unverändert** (zentriert wo Platz reicht = iPad, scrollbar sonst =
iPhone). Die Modus-Chips sind breiten-adaptiv (macOS exakt 190 pt wie zuvor, schmales iPhone:
schrumpfen mit), der Hinweistext bricht um statt rechts abzuschneiden. Auf macOS, iPhone- und
iPad-Simulator verifiziert (Menü beide Modi + Verschüttet-Spiel auf iOS headless gesichtet).
Noch offen in Phase 4: Dimensions-Einstellungen + Endlos-Toggle.

**v0.18.0 — einstellbare Brettgröße je Modus (Phase 4, Teil 2):** im Einstellungsdialog eine neue
Karte „Brettgröße — <Modus>" mit zwei Steppern (Breite/Höhe, ◀ N ▶), begrenzt auf die je Modus
erlaubte Spanne. **Bestätigte Grenzen (Stand 2026-06-24):** Säulen Breite 5–12 / Höhe 10–24
(Default 6×13), Verschüttet Breite 8–14 / Höhe 14–24 (Default 10×18). Persistenz zentral über
`BoardConfig` (Render): dieselben UserDefaults-Schlüssel, die der Einstellungsdialog schreibt und
`startGame` beim Spielstart liest (ungesetzt ⇒ Modus-Standard, gespeicherte Werte auf die Spanne
geklemmt). Der Dialog zeigt die Maße des aktuell gewählten Modus (im Menü gewählt, durchgereicht).
Wirkt ab der nächsten Partie. Variables Brett rendert dank Phase 3 sauber — mit Säulen 11×20
headless gegengeprüft (mehr Spalten/Reihen, Einwurf mittig), iOS-Dialog im Simulator bestätigt.
Die Modus-Grenzen liegen als `GameMode.widthRange`/`heightRange`/`defaultWidth`/`defaultHeight`.
**Damit ist Phase 4 fast komplett — offen bleibt nur der Endlos-Toggle (= Phase 2).**

**v0.19.0 — Endlos / konstantes Tempo (Phase 4 abgeschlossen, = Phase 2):** im Startbildschirm unter
dem Start-Tempo ein Umschalter „steigt mit Level" / „konstant" (Kapseln, gewählte in Ochsenblut,
persistiert). Bei „konstant" hält `GameScene` die Fallgeschwindigkeit auf der **Start-Tempostufe**
fest (statt mit dem Level zu beschleunigen) — Punkte/Level zählen weiter normal. Greift für **beide**
Modi (`fallInterval(speedLevel)` mit `speedLevel = constantTempo ? startTempoLevel : engine.level`).
Durchgereicht über `GameScene.start(…, endless:)`, Test-Naht `STEINREGEN_ENDLESS=1`. **Layout:** der
Startbildschirm liegt jetzt auf **beiden** Plattformen in der zentrierenden ScrollView (die zusätzliche
Tempo-Verlauf-Zeile ließ auch das macOS-Fenster knapp überlaufen → Logo wurde oben angeschnitten);
zentriert wo der Platz reicht, scrollbar sonst, alle Element-Maße unverändert. macOS-Menü per
Screenshot bestätigt. **Phase 4 (UI) ist damit komplett: Modus-Wahl + Brettgröße + Endlos.**

**v0.19.1 — Modus-Namen umbenannt:** die beiden Spielmodi heißen im Menü/Dialog jetzt
**Steinschlag** (vormals „Säulen", der Columns-Modus) und **Eingemauert** (vormals „Verschüttet",
der Vierling-Modus). Reine Anzeige-Änderung in `GameMode.title` — die internen case-Namen
(`saeulen`/`verschuettet`), die `STEINREGEN_MODE`-Naht und die UserDefaults-Schlüssel bleiben
unverändert (Persistenz/Headless-Naht). macOS-Menü per Screenshot bestätigt.

**v0.20.0 — Hintergrundbild statt prozeduralem Nebel:** der früher prozedural erzeugte, animiert
driftende Nebel (wirkte unpassend) ist durch ein **statisches
KI-Hintergrundbild** ersetzt — ein Nebel-bei-Nacht-Friedhof (Mond, schmiedeeisernes Kreuz,
Grabsteine, Ochsenblut-Schimmer), passend zur Black-Metal-Ästhetik. Lokal auf dem M5 mit
**Qwen-Image** generiert (hohe Qualität **und** kommerziell unbedenklich — anders als FLUX, das wie
schon `logo.png` einen Non-Commercial-Blocker hinzufügen würde) über die Number-One-Bildgen-Pipeline,
ausgewählt aus 10 Kandidaten (5 Prompts × 2 Seeds). Liegt als `Resources/hintergrund.png` (896×1280)
im Bundle, wird über `Theme.backdropImage()` geladen und in `GameScene.buildBackdrop()` formatfüllend
(Cover, zentriert) ganz nach hinten gelegt — funktioniert auf macOS-Fenster wie iOS-Hochformat (Ränder
werden beschnitten). Der verwaiste `GemTextures.fog()` + `fogCache` sind entfernt. macOS per
Screenshot bestätigt (Brett/HUD bleiben klar lesbar). Nur das Gameplay; der SwiftUI-Startbildschirm
ist unberührt.

**v0.21.0 — Hintergrund-Pool + Musik (Phase 5):**
- **Mehrere Hintergrundbilder statt nur einem:** die vier weiteren Qwen-Image-Favoriten aus Number
  One (toter Winterwald, Kathedralenruine, Nebelmoor + zackige Berge, blutroter Mond) liegen neben
  dem ursprünglichen Friedhof (`hintergrund-2.png` … `hintergrund-5.png`, alle 896×1280, kommerziell
  unbedenklich). `Theme.backdropImage()` → **`Theme.backdropImages()`** lädt jetzt ALLE vorhandenen
  `hintergrund*.png` (Reihenfolge: erst `hintergrund`, dann `-2`, `-3`, …; eine weitere `-N` ins
  Bundle legen genügt). `GameScene` wählt **pro Partie zufällig** eines (`backdropIndex`, in
  `start()` gesetzt → stabil über Resizes, kein Wechsel beim Fenster-Ziehen). macOS per Screenshots
  über mehrere Läufe bestätigt (Friedhof/Moor/Kathedrale/Winterwald gesehen), iOS-Hochformat (Cover)
  ebenfalls.
- **Hintergrundmusik (neu, getrennt von den Soundeffekten):** drei instrumentale Stücke im
  Downfall-of-Gaia-Stil (lokal mit **ACE-Step** erzeugt, kommerziell unbedenklich; die drei
  Favoriten aus Projekt *Musica* in Number One) als `musik-1/2/3.mp3`. Neue Datei
  **`MusicPlayer.swift`** (`AVAudioPlayer` + Delegate, `@MainActor`, Singleton `shared`): die Stücke
  laufen **nacheinander in Schleife**, pro Partie mit **zufälligem Einstieg**. **Standardmäßig AN**,
  aber **erst ab Levelbeginn** (nicht im Menü): `startGame` ruft `gameStarted()`, der Weg zurück ins
  Menü (`goToMenu`) ruft `gameEnded()` (stoppt). **Eigener Schalter** (UserDefaults
  `steinregen.musik.aus`, getrennt von `steinregen.mundtot`): Taste **M** im Spiel + eigene Karte
  „Musik" (An/Aus) in den Einstellungen. Headless-Naht `STEINREGEN_MUSIC=<0|1>`. Verifiziert:
  macOS-Build + Lauf ohne Crash, alle drei mp3 via `AVAudioPlayer` ladbar (120/240/240 s, Stereo);
  iOS-Build + Simulator-Screenshots (Einstellungs-Karte „Musik" passt aufs iPhone, Gameplay-
  Hintergrund im Hochformat). Reine Render-/App-Schicht, Core unberührt, 32 Core-Tests grün.

**v0.22.0 — Level-Sound ersetzt + Hintergrund wechselt garantiert pro Partie:**
- **Neuer Level-Geschafft-Klang:** der alte `level.m4a` (klang schwach) ist durch einen
  **dunklen Ritual-Gong** ersetzt — lokal mit **Stable Audio 3** (sfxgen) erzeugt, aus
  5 Konzepten × 2 Varianten (Glocke/Sarg/Gong/Handglocke/Röhrenglocke) in Number One per ⭐
  ausgewählt. Gewählt wegen voller, durchsetzungsfähiger Klangfarbe, die **neben der Musik**
  durchkommt. **Reiner Asset-Tausch:** `Resources/level.m4a` (mono AAC, 3 s) ausgetauscht, das
  SoundFX-Mapping (`eigene` → `levelUp: "level"`) bleibt unverändert.
- **Hintergrund garantiert neu pro Partie:** `GameScene.start()` wählt jetzt nie direkt dasselbe
  Bild wie in der Vorpartie (`lastBackdropIndex`, no-immediate-repeat wie beim SoundFX-Pool) — bei
  jedem Spielstart erscheint ein sichtbar **neues** Motiv, **ohne App-Neustart**. (v0.21.0 wählte
  bereits pro Partie zufällig, konnte aber dasselbe zweimal hintereinander erwischen.)

**v0.23.0 — Englische Lokalisierung (Deutsch/Englisch):** die gesamte Oberfläche ist jetzt
zweisprachig. Neuer, bewusst leichtgewichtiger Helfer **`L10n`** (in `SteinregenRender`): beide
Sprachfassungen stehen direkt am Aufrufort — `L10n.t("deutsch", "english")` — **ohne** SwiftPM-
`.lproj`/`.xcstrings`-Maschinerie (die mit dem eigenen Bundle-Loader zickt und für macOS- UND
iOS-Projekt getrennt einzurichten wäre). Sprache: Default = **System-Sprache** (`Locale`), fest
umstellbar über eine neue Karte „Sprache/Language" in den Einstellungen (persistiert in
`steinregen.sprache`); alle Top-Level-Views beobachten den Schlüssel via `@AppStorage`, der
Wechsel greift sofort. Übersetzt sind HUD, Menü, **Modus-Namen** (Steinschlag → „Rockfall",
Eingemauert → „Entombed"), Einstellungen, Spielregeln, Friedhof, Game-Over und die Flash-Hinweise;
**tontreu** (z. B. „Verreckt" → „Perished", „mundtot" → „silenced"). Der frühere Bethlehem-
Grabspruch ist durch einen **eigenen** ersetzt („Am Ende fällt jeder Stein" / „In the end, every
stone falls") — erledigt damit zugleich den Commercial-Blocker. **iOS-Fix nebenbei:** der
Einstellungsdialog ist auf iOS jetzt voll scrollbar (die zusätzliche Sprach-Karte ließ den Inhalt
über die iPhone-Höhe laufen → Titel war oben abgeschnitten); macOS unverändert (feste Dialoghöhe,
nur die Steine-Liste scrollt). Headless-Naht `STEINREGEN_LANG=de|en`. Auf macOS (Menü/Settings/
Spiel in beiden Sprachen) und iOS-Simulator (Settings beide Sprachen) per Screenshot verifiziert.

**v0.24.0 — dritter Modus „Blutklumpen" (Puyo-Stil):** neue, eigene Core-Engine **`PairEngine`**
(+ `Pair.swift`-Typen), parallel zu den beiden bestehenden — es fällt ein **Zweier-Paar** (Pivot +
Satellit, dreht in vier Lagen um den Pivot, einfacher Kick: Pivot weicht um den Gegen-Versatz aus,
kein 180-Flip). **Nur vier Farben** (`PairEngine.pairColors`, klassisch spielbar — mit sechs kämen
Vierergruppen kaum zustande), kein Magic-Stein. Nach dem Aufsetzen fallen die beiden Hälften
**unabhängig** (`settle` wiederverwendet); geräumt werden Gruppen ab **4 verbundenen** gleichen
Steinen (neues `findGroups` in `Matching.swift`, Flood-Fill über Seiten-Nachbarn — Diagonalen
verbinden nicht), Kaskaden/Punkte/Level wie im Säulen-Modus (`Engine.points`, 30 Steine je Level).
Brett 6×13 (Spanne wie Säulen 5–12/10–24, eigene UserDefaults-Schlüssel `steinregen.dim.klumpen.*`).
Render: `PairEngine`-Conformance zu `PlayEngine`; neue Protokoll-Eigenschaft **`postLockSettle`**
(Default false) — bei true animiert `GameScene.animateLock` zuerst das Nachfallen der getrennten
Hälften (`compactColumnsAnimated`), dann die Räum-Wellen; die HUD-Vorschau nutzt den Säulen-Pfad
mit zwei Steinen (überzählige Knoten ausgeblendet). App: dritter Modus-Chip (Reihe jetzt max. 598 pt),
Brettgrößen-Karte, Naht `STEINREGEN_MODE=klumpen`. **Nebenbei gefixt:** der Einstellungsdialog
bekommt den Modus jetzt als **Binding** — das `.sheet`-Inhalts-Closure konnte einen veralteten
View-Stand einfangen (Karte zeigte bei der env-Naht `STEINREGEN_MODE` + `STEINREGEN_SETTINGS` den
alten Modus). Tests: 17 neue Core-Tests (`PairEngineTests`: Flood-Fill, Kicks, unabhängige Hälften,
Kette, Determinismus, Vier-Farben) + 2 headless Szene-Tests (`PairModeSceneTests`; Harness-Grenze
dokumentiert: SKActions laufen headless nicht → Engine-Score-Diagnose `testEngineScore`). Verifiziert
auf macOS (Menü 3 Chips, Gameplay, Räumung mit Punkten via Seed 12, Game-Over, Settings-Karte) und
iOS-Simulator (Menü englisch „Blood Clots", Klumpen-Gameplay mit Touch-Leiste).

**Design-Entscheidung (Stand 2026-06-22): iOS-/iPad-Optik ist abgenommen** — Layout, Größen,
Logo- und Button-Maße auf iPhone UND iPad sind so gewollt und **nicht ohne ausdrücklichen Auftrag
zu ändern** (keine ungefragten „Verbesserungen"). Am echten iPhone + iPad-Simulator bestätigt.

**Beauftragte TODOs (Stand 2026-06-22):**
- **iOS-App (iPhone + iPad):** ✅ Grundgerüst + Touch-Steuerung, App-Icon, automatisches
  Geräte-Signing und iPad-Layout erledigt (v0.10.0–v0.11.0, siehe oben); teilt Core+Render mit macOS.
  Im iPhone- und iPad-Simulator verifiziert; **auf zwei echten iPhones getestet (2026-06-22) — läuft.**
  Hinweis: Geräte-Signing kann periodisch eine Apple-PLA-Zustimmung verlangen (developer.apple.com →
  Agreement akzeptieren), dann in Xcode „Try Again" — kein Code-Problem. **Damit iOS vollständig.**
- **Weitere Steine-Sets generieren** — ✅ erledigt für FreeDoom (Set „FreeDoom", v0.9.0; Lizenz
  verifiziert + dokumentiert). Weitere Sets jederzeit möglich (Renderer + ein `StoneSets.all`-Eintrag).
- **Zaubersteine-Set-Assets aktualisieren** (für später, noch offen) — das Set
  „Zaubersteine"/„G20"/„Juwelen" zeigte weiße Säume an den Stein-Kanten. Im Schwester-Projekt
  `~/git/zaubersteine` wurde das korrigiert; die aktualisierten Bilddateien von dort neu nach
  `Sources/SteinregenRender/Resources/` holen und ersetzen — betrifft die Edelstein-PNGs
  (`ruby/sapphire/emerald/topaz/amethyst/diamond.png`) und die SVG-Steine (`svg_*.png`). Reiner
  Asset-Tausch (bessere Kantenqualität), keine Code-Änderung.
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
Seed-Anzeige/-Eingabe wie in Zaubersteine (Crockford-Base32), Sound (`AVFoundation`), Pause.
(Developer-ID-Signatur + Notarisierung ist ab v0.20.0 als `tools/make-notarized.sh` verfügbar —
siehe Build & Test.)
