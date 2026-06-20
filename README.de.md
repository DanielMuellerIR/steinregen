# Steinregen

Ein nativer macOS-Klon des Sega-Klassikers *Columns* (1990), geschrieben in Swift mit
SwiftUI und SpriteKit.

*(English version: [README.md](README.md))*

Es fallen Dreier-Säulen aus Edelsteinen; **drei oder mehr gleichfarbige** in einer Linie —
waagerecht, senkrecht oder diagonal — werden geräumt. Geräumte Steine lassen die darüber
liegenden nachrutschen, was Kettenreaktionen mit Bonuspunkten auslösen kann.

## Funktionen

- **6 Steinfarben** — Rubin, Topas, Smaragd, Diamant (türkis), Saphir, Amethyst.
- **Treffer in alle Richtungen** — horizontal, vertikal und beide Diagonalen.
- **Kettenreaktionen** — Kaskaden werden belohnt (Punkte = Steine × 10 × Kettenstufe).
- **Magic Jewel** — eine seltene, regenbogen-pulsierende Säule. Wo sie aufsetzt, räumt sie
  brettweit die Farbe der Zelle direkt darunter weg.
- **Wählbares Start-Tempo** (Stufen 0–9); das Tempo steigt mit der Zahl geräumter Steine.
- **Deterministisch, seed-getrieben** — gleicher Seed spielt exakt dieselbe Partie nach.

## Steuerung

| Taste | Aktion |
|-------|--------|
| ← → | Säule bewegen |
| ↑ | drehen (die drei Steine durchtauschen) |
| ↓ | schneller fallen (Softdrop) |
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

Baut `dist/Steinregen.app` (ad-hoc-signiert, mit einem aus den Stein-Grafiken erzeugten
Dock-Icon) plus ein weitergebbares `dist/Steinregen-<version>.zip`. Die `.app` im Finder
doppelklicken oder nach `/Programme` ziehen.

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

## Architektur

Drei Swift-Package-Manager-Module plus Tests:

- **`SteinregenCore`** — reine, deterministische Spiellogik (Brett, fallende Säule,
  Treffer-Erkennung, Kaskaden, Magic Jewel, Punkte). Kein globaler Zufall, keine Wanduhr;
  aller Zufall läuft über einen injizierten, seed-bestimmten PRNG.
- **`SteinregenRender`** — SpriteKit-Szene: Darstellung, Schwerkraft-/Animations-Loop,
  Stein-Texturen, Magic-Jewel-Animation.
- **`SteinregenApp`** — SwiftUI-Shell: Startbildschirm, Tastatursteuerung, Game-Over-Overlay.

Die Edelstein-Grafiken sowie mehrere wiederverwendete Bausteine (der deterministische PRNG,
der robuste Textur-Loader, das Drei-Modul-Layout) stammen aus dem Schwester-Projekt
*Zaubersteine*.

## Lizenz

MIT — siehe [LICENSE](LICENSE).

🤖 Gebaut mit [Claude Code](https://claude.com/claude-code).
