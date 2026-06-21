# Steinregen

Ein nativer macOS-Klon des Sega-Klassikers *Columns* (1990), geschrieben in Swift mit
SwiftUI und SpriteKit.

*(English version: [README.md](README.md))*

Es fallen Dreier-Säulen aus Steinen; **drei oder mehr gleiche** in einer Linie —
waagerecht, senkrecht oder diagonal — werden geräumt. Geräumte Steine lassen die darüber
liegenden nachrutschen, was Kettenreaktionen mit Bonuspunkten auslösen kann.

Eine rohe **Black-Metal-Ästhetik**: pechschwarz, knochenweiß, ein einziger Ochsenblut-Akzent,
ziehender Nebel, Korn-Textur und ein zackiges Black-Metal-Logo. Die sechs Steine unterscheiden
sich über ein weißes **Sigil** (Form), dazu eine gedeckte, entsättigte Farb-Tönung.

## Funktionen

- **6 Steine mit Sigillen** — umgekehrtes Pentagramm, inverses Kreuz, Tiwaz-Rune, Triquetra,
  Schädel, Mondsichel. Unterscheidung über die Form, dazu eine gedeckte Farb-Tönung als Zusatzhinweis.
- **Wählbare Steine-Sets** — in den Einstellungen (mit Live-Vorschau) zwischen fünf Sets
  umschalten: den Black-Metal-Sets „Sigille" und „Doom" sowie drei freundlicheren Edelstein-Sets
  aus dem Schwester-Projekt *Zaubersteine* („Zaubersteine", „G20", „Juwelen"). Erweiterbar.
- **Treffer in alle Richtungen** — horizontal, vertikal und beide Diagonalen.
- **Kettenreaktionen** — Kaskaden werden belohnt (Punkte = Steine × 10 × Kettenstufe).
- **Magic Jewel** — eine seltene, helle Säule, die durch alle sechs Sigille pulsiert. Wo sie
  aufsetzt, räumt sie brettweit die Sorte der Zelle direkt darunter weg.
- **Wählbares Start-Tempo** (Stufen 0–9); das Tempo steigt mit der Zahl geräumter Steine.
- **Deterministisch, seed-getrieben** — gleicher Seed spielt exakt dieselbe Partie nach.

## Steuerung

| Taste | Aktion |
|-------|--------|
| ← → · A D | Säule bewegen |
| ↑ · W | drehen (die drei Steine durchtauschen) |
| ↓ · S | schneller fallen (Softdrop) |
| Leertaste | sofort fallen lassen |
| Esc | zurück ins Hauptmenü |

## Bauen & Starten

Voraussetzung: macOS 15+ und die Xcode-Toolchain.

```bash
swift build
swift run Steinregen
```

### Doppelklickbare App (mit Dock-Icon)

```bash
bash tools/make-app.sh
```

Baut `dist/Steinregen.app` (ad-hoc-signiert, mit einem prozedural erzeugten Dock-Icon —
umgekehrtes Pentagramm) plus ein weitergebbares `dist/Steinregen-<version>.zip`. Die `.app` im
Finder doppelklicken oder nach `/Programme` ziehen.

### Tests

`swift test` allein scheitert auf Systemen mit nur den Command Line Tools (kein XCTest).
Stattdessen die Xcode-Toolchain nutzen:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

### Headless / Automation

Die App wertet Umgebungsvariablen aus, damit sie ohne Menü gesteuert werden kann (für
automatische Screenshots und Smoke-Tests):

```bash
STEINREGEN_AUTOSTART=1 STEINREGEN_LEVEL=8 STEINREGEN_SEED=4242 swift run Steinregen
```

- `STEINREGEN_AUTOSTART=1` — startet sofort ein Spiel
- `STEINREGEN_LEVEL=<0..9>` — Start-Tempo
- `STEINREGEN_SEED=<UInt64>` — fester Seed (sonst zufällig)
- `STEINREGEN_SET=<id>` — Steine-Set (`sigil` / `doom` / `zaubersteine` / `g20` / `juwelen`)
- `STEINREGEN_SETTINGS=1` — öffnet beim Start den Einstellungsdialog

## Architektur

Drei Swift-Package-Manager-Module plus Tests:

- **`SteinregenCore`** — reine, deterministische Spiellogik (Brett, fallende Säule,
  Treffer-Erkennung, Kaskaden, Magic Jewel, Punkte). Kein globaler Zufall, keine Wanduhr;
  aller Zufall läuft über einen injizierten, seed-bestimmten PRNG.
- **`SteinregenRender`** — SpriteKit-Szene: Darstellung, Schwerkraft-/Animations-Loop,
  die prozedural gezeichneten Sigil-Steine, das Theme (Palette/Fonts/Korn), Magic-Jewel-Animation.
- **`SteinregenApp`** — SwiftUI-Shell: Startbildschirm, Tastatursteuerung, Game-Over-Overlay.

Mehrere wiederverwendete Bausteine (der deterministische PRNG, der robuste Ressourcen-Loader,
das Drei-Modul-Layout) sowie die drei freundlichen Edelstein-Sets (Zaubersteine / G20 / Juwelen)
stammen aus dem Schwester-Projekt *Zaubersteine*.

## Lizenz

MIT — siehe [LICENSE](LICENSE).

Titel-/HUD-Schrift: **Pirata One** von Rodrigo Fuenzalida & Nicolas Massi, lizenziert unter der
[SIL Open Font License](Sources/SteinregenRender/Resources/PirataOne-OFL.txt).

🤖 Gebaut mit [Claude Code](https://claude.com/claude-code).
