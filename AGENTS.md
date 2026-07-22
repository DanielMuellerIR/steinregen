# Steinregen — Arbeitsregeln und Architektur

Steinregen ist ein nativer Swift-6-Puzzleklassiker für macOS und iOS. Ausgangspunkt ist Columns,
inzwischen teilen mehrere deterministische Fallblock-Modi denselben Core-/Render-Unterbau.
Black-Metal-Ästhetik, reproduzierbare Seeds, klare Modulgrenzen und stabile Steuerung sind
Produktinvarianten.

`CLAUDE.md` ist ein Symlink auf diese Datei. Änderungen an AGENTS gelten daher für beide Agenten;
keine zweite Regelkopie anlegen.

## Einstieg und Quellen

- `README.md` / `README.de.md`: öffentlicher Einstieg.
- `CHANGELOG.md`: Versions- und Implementierungshistorie.
- `THIRD-PARTY-ASSETS.md`: verbindliche Asset-/Lizenzbestandsaufnahme.
- `Package.swift`: Targets und Plattformen.
- `VERSION` und `Sources/SteinregenCore/Version.swift`: synchronisierte Version.
- `Sources/SteinregenCore`: reine deterministische Spiellogik.
- `Sources/SteinregenRender`: SpriteKit, Spielloop, Assets, Audio.
- `Sources/SteinregenApp`: SwiftUI-Shell, Persistenz und plattformspezifische Eingabe.
- Aktuelle Implementierung und Tests schlagen datierte Statusabsätze. Offene Ideen nicht aus alten
  Versionsnotizen ableiten.

## Arbeitsweise und Git

- Identifier Englisch; Kommentare und Doku Deutsch und anfängerfreundlich. Bestehende hilfreiche
  Kommentare bei Refactors erhalten und anpassen.
- Bestehende SwiftPM-/SwiftUI-/SpriteKit-Muster fortführen; keine Dependency oder Basisklassen-
  Hierarchie ohne belegten Nutzen.
- Nur beauftragte Pfade ändern. Fremdes WIP, Buildartefakte und lokale Signingdaten unangetastet.
- Git nach Fleet-Regeln: konkrete Pfade stagen, niemals `git add .`/`-A`. Ein abgeschlossenes,
  verifiziertes Implementierungs-Todo mit projekttypischem Version-Bump committen und zu kanonischer privater Fleet-Remote
  pushen. GitHub, Tags oder öffentliche Releases nur auf ausdrücklichen Auftrag.
- Reine AGENTS-/Doku-Reorganisation braucht keinen Produktversions-Bump und kein neues DMG.
- Destruktiver History-Rewrite, Force-Push, `--mirror`, `--all` oder pauschales `--tags` braucht
  ausdrückliche Freigabe.

## Harte Core-Invarianten

### Determinismus

`SteinregenCore` enthält keine globale Zufallsquelle, Systemzeit, Wanduhr, UI oder Dateizugriffe.

- Aller Zufall läuft über den injizierten `Xoshiro256StarStar`.
- Gleicher Seed und gleiche Eingabefolge erzeugen Zustand, Score, Clear-Schritte und Reihenfolge
  exakt reproduzierbar.
- Mengen aus Sets vor sichtbarer/serialisierter Ausgabe deterministisch sortieren.
- Falltempo, Animationszeit und Lock-Timer leben in Render/App, nicht im Core.
- Neue Mechanik bekommt einen Seed-/Replay-Test. Keine `randomElement()`-Abkürzung.
- Persistenz und UserDefaults gehören in App, nicht in die Engine.

### Engine-Verträge

`PlayEngine` enthält den modusneutralen Anzeige-/Zustandskern. `FallingPieceEngine` ergänzt das
Fallstein-Paradigma. Neue Modi implementieren nur passende Protokolle; einen Cursor-/Bandmodus
nicht künstlich in `FallingPieceEngine` pressen.

Aktive Modi und stabile interne IDs:

- `saeulen` → „Steinschlag“, klassische Dreiersäulen;
- `verschuettet` → „Eingemauert“, Vierlinge;
- `klumpen` → „Blutklumpen“, Steinpaare;
- `fuenfling` → „Erdrückt“, Pentominoes;
- `kapseln` → „Austreibung“, Kapseln/Flüche und Siegbedingung;
- `schnitter` → „Schnitter“, 2×2-Quadrate und Sense.

Env-/UserDefaults-IDs nicht an Anzeigenamen angleichen; gespeicherte Einstellungen und
Automationsläufe hängen daran.

Geteilte Regeln liegen in `Rules.swift`, `Board.fits(cells:)` und `Matching.resolveCascade`.
Keine neue Basisklasse nur zur Boilerplate-Reduktion. Modusspezifischer Zustand und kleine
`shift`-/`gravityTick`-Methoden dürfen getrennt bleiben.

### Steinschlag-Regeln

- Brett 6×13, vertikale Säule aus drei Steinen; ≥3 gleiche horizontal, vertikal oder diagonal.
- Nachrutschen kann Kaskaden bilden; Score basiert auf geräumten Steinen und Kettenstufe.
- Magic Jewel ist seed-gesteuert und räumt brettweit den Typ direkt unter seiner Aufsetzposition.
- Game Over, wenn die Einwurfspalte oben blockiert.
- Lock Delay ist eine bewusste Produktentscheidung: ab erster Bodenberührung läuft ein fester
  Echtzeittimer. Drehen/Schieben setzt ihn nicht zurück. Nach Ablauf wird nur eingerastet, wenn
  `canFall == false`; mit Luft fällt der Stein weiter. Hard Drop nutzt den kürzeren Delay.
  Kein Move-Reset und keine „tiefste Reihe“-Ausnahme ohne ausdrückliche Produktentscheidung.
- Lock-Delay-Änderungen brauchen `SteinregenRenderTests/LockDelayTests.swift`.

### Schnitter-Regeln

Gleichfarbige 2×2-Flächen werden beim Aufsetzen markiert, nicht sofort entfernt. Der Core bewegt
die Sense tick-basiert über `sweepTick()`; Echtzeitdauer bleibt in der Szene. Verlassen der rechten
Kante einer zusammenhängenden markierten Spaltensektion erntet die ganze Sektion. Danach
Nachfallen und Neumarkierung, aber keine sofortige Kaskadenernte. Diese Trennung Core-Tick versus
Render-Zeit nicht vermischen.

## Render, UI und Assets

### Modulgrenzen

- `SteinregenCore`: Modelle, Board, PRNG, Engines, reine Regeln.
- `SteinregenRender`: `GameScene`, SpriteKit, `PlayEngine`-Darstellung, Theme, StoneSets,
  SoundFX, MusicPlayer.
- `SteinregenApp`: SwiftUI-Menüs, Persistenz, Fenster, Tastatur/Touch und Lebenszyklus.
- Gemeinsame UI/Renderpfade plattformneutral halten; AppKit/UIKit nur in klaren
  `#if os(...)`-Grenzen.

Desktop ist macOS 15+ Apple Silicon; iOS 17+, iPhone/iPad Hochformat. Die abgenommene iPhone-/
iPad-Optik nicht ungefragt „verbessern“. Layout-, Logo- und Buttonmaße nur bei Auftrag ändern und
auf passendem Gerät/Simulator prüfen.

Der lokale NSEvent-Monitor ist bewusst fokusunabhängig. Änderungen an Keyboard-/Fensterfokus
müssen echte Steuerung direkt nach Spielstart testen.

### StoneSets und Ressourcen

`StoneSets.all` ist die Registry. Ein neues Set besteht aus Renderer plus Registry-Eintrag; Menü
und Vorschau leiten sich daraus ab. Bestehende IDs und UserDefaults nicht ändern.

- Assets nur lazy laden, wenn pro Partie nur eines gebraucht wird.
- Ressourcenbundle über die bestehende robuste Bundle-Suche laden; Tests müssen Ressourcen finden.
- Soundeffekte und Musik haben getrennte Schalter und Lebenszyklen. Musik läuft nur im Spiel.
- Neue `musik-N.mp3` lückenlos nummerieren; Discovery/Shuffle bleibt getestet.
- Grenze-Gotisch-Lizenz, FreeDoom BSD-3-Credits und übrige Einträge aus
  `THIRD-PARTY-ASSETS.md` erhalten.
- Öffentliche Marken-Disclaimer nicht entfernen. Vor breiter/kommerzieller Distribution nahe
  Genre-Klone gesondert rechtlich prüfen.
- Signing-/Notary-Credentials bleiben im Schlüsselbund/Umgebung und nie im Repo oder Terminaltext.

## Automation und Smoke-Tests

Die App unterstützt env-gegatete Zustände, ohne normales Laufzeitverhalten zu ändern:

- `STEINREGEN_AUTOSTART=1`, `STEINREGEN_LEVEL` und `STEINREGEN_SEED`;
- `STEINREGEN_SET` und `STEINREGEN_MODE` mit den stabilen IDs oben;
- `STEINREGEN_ENDLESS=1`, `STEINREGEN_MUSIC=0|1`, `STEINREGEN_LANG=de|en`;
- `STEINREGEN_SETTINGS=1`, `STEINREGEN_FRIEDHOF=1`, `STEINREGEN_RULES=1`.

Für Simulatorlaunch die Variablen als `SIMCTL_CHILD_<NAME>` durchreichen. Screenshots über
Fenster-ID bzw. `simctl io` erzeugen, ohne Fokus anderer Arbeit unnötig zu übernehmen.

Neue UI-Zustände nach Möglichkeit env-gegatet reproduzierbar machen. Testhooks dürfen nie
Spielstand verändern oder im normalen Startpfad aktiv sein.

## Build, Tests und Versionierung

Standard:

```bash
swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

`swift test` mit bloßen CommandLineTools reicht wegen XCTest/SpriteKit nicht. Nach einem
Implementierungs-Todo eine startbare App bauen:

```bash
bash tools/make-app.sh
```

Das erzeugt ad-hoc-signiert `dist/Steinregen.app` und ZIP. Notarisierung/DMG nur bei
Distribution oder ausdrücklichem Wunsch:

- `tools/make-notarized.sh`: Developer-ID, Notary, Stapling, ZIP;
- `tools/make-dmg.sh`: DMG; `--publish` ist eine externe Veröffentlichung und nie automatisch;
- `tools/make-ios-app.sh`: XcodeGen-Projekt und Simulatorbuild; mit `run` installieren/starten.

`VERSION` und `steinregenVersion` immer gemeinsam ändern. Produktänderungen erhöhen die Version;
reine README-/Regelpflege kann ohne Bump bleiben.

## Testmatrix

- Core-Regel/Engine: vollständige Swift-Tests, Seed-Replay, Reihenfolge und Randfälle.
- Lock/Fall/Scene: RenderTests mit Xcode-Toolchain; Soft-/Hard-Drop und Luft-nach-Timer.
- Persistenz/Friedhof: UserDefaults isolieren und nach Test restaurieren.
- Ressourcen/Theme/Musik: Discovery, Lücken, Bundle-Pfad und Lazy Load.
- Modus/Registry: Defaultmaße innerhalb Spanne, stabile IDs, nichtleere Texte.
- macOS-UI: startbare Bundle-App, Menü/Steuerung/Fokus und gezielter Screenshot.
- iOS: XcodeGen-/Simulatorbuild und relevante Hochformatansicht; abgenommene Optik schützen.
- Release: Lizenzbestand, Signatur/Notary nur bei echtem Releaseauftrag.

## Öffentliche Veröffentlichung

Der aktuelle Inhaltsscan war secret-frei, aber ältere erreichbare Commits können eine frühere
Developer-ID/Team-ID enthalten. Eine Bereinigung wäre destruktiver History-Rewrite und ist keine
Nebenaufgabe. Bis zur Entscheidung bei einem öffentlichen Push nur den ausdrücklich freigegebenen
`main`-Stand senden; keine lokalen Archivtags oder sonstigen Refs veröffentlichen.

Versionschronik, lange Featureberichte, erledigte Todos und weitere Modusideen gehören in
CHANGELOG/Backlog, nicht zurück in diese Daueranweisung.

Die frühere Regel- und Featurechronik liegt unverändert unter
[`docs/archive/agent-context-legacy-2026-07-14.md`](docs/archive/agent-context-legacy-2026-07-14.md)
und ist keine aktive Anweisung.

## Verzeichnisstruktur

- [`README.md`](README.md) / [`README.de.md`](README.de.md): Projektüberblick.
- [`SECURITY.md`](SECURITY.md): Sicherheits- und Melderegeln.
- [`THIRD-PARTY-ASSETS.md`](THIRD-PARTY-ASSETS.md): Assetlizenzen.
- [`CHANGELOG.md`](CHANGELOG.md): veröffentlichte Änderungen.
- [`BACKLOG.md`](BACKLOG.md): verifizierte offene Arbeit.
- [`docs/archive/agent-context-legacy-2026-07-14.md`](docs/archive/agent-context-legacy-2026-07-14.md): frühere Chronik.
