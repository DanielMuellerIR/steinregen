# Steinregen

A native macOS and iOS game in a raw black-metal style — two falling-block puzzle modes on one
deterministic engine. Written in Swift with SwiftUI and SpriteKit.

*(Deutsche Version: [README.de.md](README.de.md))*

<p align="center">
  <img src="assets/sc0_en.jpg" width="32%" alt="Start screen: pick a mode and starting speed">
  <img src="assets/sc1_en.jpg" width="32%" alt="Gameplay on a night background">
  <img src="assets/sc2_en.jpg" width="32%" alt="Settings: language, sound, music, board size, stone sets">
</p>

## Modes

- **Rockfall** (Columns-style) — falling columns of three stones. Line up **three or more of
  the same kind** horizontally, vertically, or diagonally to clear them; cleared stones make the
  ones above fall, which can set off chain reactions for bonus points.
- **Entombed** (block-stacking) — falling four-block pieces. Fill a whole row to clear it.
  Seven shapes, a deterministic 7-bag, simple wall kicks.

Both modes run on the same deterministic core and share the look, sound, music, and high-score
list. Pick the mode (and board size) on the start screen.

## Look

Pitch black, bone white, a single oxblood accent, film grain, a jagged hand-inked logo, and
AI-generated foggy-night backgrounds. The six stones are told apart by a white **sigil** (shape),
backed by a muted, desaturated color tint.

## Features

- **6 stones, marked by sigils** — inverted pentagram, inverted cross, Tiwaz rune, triquetra,
  skull, crescent. Told apart by shape, with a muted color tint as a secondary cue.
- **Selectable stone sets** — switch in Settings (with live preview) between six sets: the
  engraved "Sigils" and grimy "Doom" black-metal sets, three friendlier gem sets from the sibling
  project *Zaubersteine* ("Zaubersteine", "G20", "Jewels"), and a "FreeDoom" pixel-art set built
  from original Freedoom sprites. Adding one is a single renderer plus one registry entry.
- **Configurable board size** per mode, set in Settings.
- **Selectable starting speed** (levels 1–10), rising as you clear stones — or a constant
  "endless" tempo that keeps the starting speed.
- **Graveyard (high-score list)** — on death, enter a name (up to 16 chars); each grave
  shows the score and the level you died in. Persistent top 16, viewable from the menu.
- **Sound effects** (locally generated) — landing, clearing, rotating, level-up and game-over
  cues, with several random variants per event. In Settings you can pick a sound set —
  Steinregen (the project's own cues), Freedoom, or Silenced; **T** toggles in-game.
- **Music** (locally generated) — three instrumental atmospheric-black-metal tracks that play one
  after another in a loop, starting on a random track each game. On by default but only from the
  start of a level, not in the menu; toggled independently of the sound effects in Settings or
  with **M** in-game.
- **Backgrounds** — AI-generated foggy-night motifs (graveyard, dead winter forest, ruined
  cathedral, foggy moor, blood-red moon); a different one each game, never the same twice in a row.
- **Magic Jewel** — a rare, bright column pulsing through all six sigils. Where it lands it wipes
  every stone of the kind directly beneath it from the board.
- **Deterministic, seed-driven** — the same seed replays the exact same game.
- **Runs on macOS** (keyboard) **and iOS / iPad** (touch), sharing the same core and renderer.
- **English and German** — the interface follows your system language and can be switched in Settings.

## Controls

On iOS the game is played by touch (tap to rotate, swipe to move/drop, plus on-screen buttons).
On macOS, by keyboard:

| Key | Action |
|-----|--------|
| ← → · A D | move the piece |
| ↑ · W | rotate |
| ↓ · S | soft drop (faster fall) |
| Space | hard drop |
| T | toggle sound effects (off = "Silenced") |
| M | toggle music |
| Esc | back to main menu |

## Build & Run

Requires macOS 15+ and the Xcode toolchain.

```bash
swift build
swift run Steinregen
```

### Double-clickable app (with Dock icon)

```bash
bash tools/make-app.sh
```

Builds `dist/Steinregen.app` (ad-hoc signed, with a procedurally drawn Dock icon — an
inverted-pentagram sigil) plus a distributable `dist/Steinregen-<version>.zip`. Double-click the
`.app` in Finder, or drag it into `/Applications`. For a notarized, Gatekeeper-friendly build use
`bash tools/make-notarized.sh` (needs a Developer ID certificate and a notarytool keychain profile).

### iOS app

```bash
bash tools/make-ios-app.sh run
```

Generates an Xcode project from `project.yml` via xcodegen and builds + launches the app in the
iOS Simulator (needs full Xcode and `xcodegen`).

### Tests

`swift test` alone fails on systems with only the Command Line Tools (no XCTest). Use the
Xcode toolchain:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

### Headless / automation

The app honors environment variables so it can be driven without the menu (useful for automated
screenshots and smoke tests):

```bash
STEINREGEN_AUTOSTART=1 STEINREGEN_LEVEL=8 STEINREGEN_SEED=4242 swift run Steinregen
```

- `STEINREGEN_AUTOSTART=1` — start a game immediately
- `STEINREGEN_LEVEL=<1..10>` — starting speed
- `STEINREGEN_SEED=<UInt64>` — fixed seed (otherwise random)
- `STEINREGEN_SET=<id>` — stone set (`sigil` / `doom` / `zaubersteine` / `g20` / `juwelen` / `freedoom`)
- `STEINREGEN_MODE=<saeulen|verschuettet>` — mode (Rockfall / Entombed)
- `STEINREGEN_ENDLESS=1` — constant tempo
- `STEINREGEN_MUSIC=<0|1>` — force music off / on
- `STEINREGEN_SETTINGS=1` — open the settings dialog on launch
- `STEINREGEN_FRIEDHOF=1` — open the Graveyard (high-score list) on launch

## Architecture

Three Swift Package Manager modules plus tests:

- **`SteinregenCore`** — pure, deterministic game logic. Two engines (`Engine` for Rockfall,
  `TetrominoEngine` for Entombed), board, match detection, cascades, magic jewel, scoring. No
  global randomness and no wall-clock; all randomness flows through an injected, seeded PRNG.
- **`SteinregenRender`** — SpriteKit scene that drives both modes through one `PlayEngine`
  protocol: rendering, the gravity/animation loop, the procedurally drawn stone sets, the theme
  (palette/fonts/grain), sound effects, the music player, and the magic-jewel animation.
- **`SteinregenApp`** — SwiftUI shell for macOS and iOS: menus, settings, rules, the Graveyard, and
  game-over overlay. Keyboard input on macOS, touch on iOS.

Several reusable building blocks (the deterministic PRNG, the robust resource loader, the
three-module layout) and the three "pleasant" gem sets (Zaubersteine / G20 / Jewels) come from
the sibling project *Zaubersteine*.

## Trademarks

Steinregen is an independent project and is not affiliated with or endorsed by anyone. Its two
modes are inspired by classic falling-block puzzle games; *Columns* is a trademark of Sega, and
the names of other games in the genre are trademarks of their respective owners. Game rules are
not copyrightable, but those names are — Steinregen uses none of them as its own.

## License

MIT — see [LICENSE](LICENSE).

Title/HUD typeface: **Grenze Gotisch** by Omnibus-Type, licensed under the
[SIL Open Font License](Sources/SteinregenRender/Resources/GrenzeGotisch-OFL.txt).

The "FreeDoom" stone-set sprites come from the
[Freedoom](https://github.com/freedoom/freedoom) project (its own free assets, not the original
commercial Doom material), licensed under
[BSD-3-Clause](Sources/SteinregenRender/Resources/FREEDOOM-LICENSE.txt).

The sound effects were generated locally with an open audio model (Stable Audio 3); the three
music tracks with the open **ACE-Step** model; the foggy-night background images with the open
**Qwen-Image** model. All ship as part of this project. See
[THIRD-PARTY-ASSETS.md](THIRD-PARTY-ASSETS.md) for the full attribution and license overview.

🤖 Built with [Claude Code](https://claude.com/claude-code).
