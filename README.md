# Steinregen

A native macOS clone of Sega's classic puzzle game *Columns* (1990), written in Swift with
SwiftUI and SpriteKit.

*(Deutsche Version: [README.de.md](README.de.md))*

Falling columns of three stones; line up **three or more of the same kind** horizontally,
vertically, or diagonally to clear them. Cleared stones make the ones above fall, which can set
off chain reactions for bonus points.

A raw **black-metal aesthetic**: pitch black, bone white, a single oxblood accent, drifting fog,
film grain, and a jagged black-metal logo. The six stones are told apart by a white **sigil**
(shape), backed by a muted, desaturated color tint.

## Features

- **6 stones, marked by sigils** — inverted pentagram, inverted cross, Tiwaz rune, triquetra,
  skull, crescent. Told apart by shape, with a muted color tint as a secondary cue.
- **Selectable stone sets** — switch in Settings (with live preview) between five sets: the
  engraved "Sigil" and grimy "Doom" black-metal sets, plus three friendlier gem sets adopted
  from the sibling project *Zaubersteine* ("Zaubersteine", "G20", "Juwelen"). Built to add more.
- **Friedhof (graveyard high-score list)** — on death, enter a name (up to 16 chars); each grave
  shows the score and the level you died in. Persistent top 16, viewable from the menu.
- **Sound effects** (from Freedoom, BSD-3) — landing, clearing, rotating, level-up and game-over
  cues. Toggle in Settings or with **T** in-game; the silent mode is called "mundtot".
- **Matches in all directions** — horizontal, vertical, and both diagonals.
- **Chain reactions** — cascading clears are rewarded (score = stones × 10 × chain step).
- **Magic Jewel** — a rare, bright column pulsing through all six sigils. Where it lands it wipes
  every stone of the kind directly beneath it from the board.
- **Selectable starting speed** (levels 1–10); speed increases as you clear stones.
- **Deterministic, seed-driven** stone sequence — the same seed replays the exact same game.

## Controls

| Key | Action |
|-----|--------|
| ← → · A D | move the column |
| ↑ · W | rotate (cycle the three stones) |
| ↓ · S | soft drop (faster fall) |
| Space | hard drop |
| T | toggle sound (off = "mundtot") |
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
`.app` in Finder, or drag it into `/Applications`.

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
- `STEINREGEN_SET=<id>` — stone set (`sigil` / `doom` / `zaubersteine` / `g20` / `juwelen`)
- `STEINREGEN_SETTINGS=1` — open the settings dialog on launch
- `STEINREGEN_FRIEDHOF=1` — open the Friedhof (high-score list) on launch

## Architecture

Three Swift Package Manager modules plus tests:

- **`SteinregenCore`** — pure, deterministic game logic (board, falling piece, match detection,
  cascades, magic jewel, scoring). No global randomness and no wall-clock; all randomness flows
  through an injected, seeded PRNG.
- **`SteinregenRender`** — SpriteKit scene: rendering, the gravity/animation loop, the
  procedurally drawn sigil stones, the theme (palette/fonts/grain), and the magic-jewel animation.
- **`SteinregenApp`** — SwiftUI shell: start screen, keyboard input, game-over overlay.

Several reusable building blocks (the deterministic PRNG, the robust resource loader, the
three-module layout) and the three "pleasant" gem sets (Zaubersteine / G20 / Juwelen) come
from the sibling project *Zaubersteine*.

## License

MIT — see [LICENSE](LICENSE).

Title/HUD typeface: **Pirata One** by Rodrigo Fuenzalida & Nicolas Massi, licensed under the
[SIL Open Font License](Sources/SteinregenRender/Resources/PirataOne-OFL.txt).

Sound effects from the [Freedoom](https://github.com/freedoom/freedoom) project (its own free
recordings, not the original commercial Doom sounds), licensed under
[BSD-3-Clause](Sources/SteinregenRender/Resources/FREEDOOM-LICENSE.txt).

🤖 Built with [Claude Code](https://claude.com/claude-code).
