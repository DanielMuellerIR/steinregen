# Steinregen

A native macOS clone of Sega's classic puzzle game *Columns* (1990), written in Swift with
SwiftUI and SpriteKit.

*(Deutsche Version: [README.de.md](README.de.md))*

Falling columns of three gems; line up **three or more of the same color** horizontally,
vertically, or diagonally to clear them. Cleared gems make the ones above fall, which can set
off chain reactions for bonus points.

## Features

- **6 gem colors** — ruby, topaz, emerald, diamond, sapphire, amethyst.
- **Matches in all directions** — horizontal, vertical, and both diagonals.
- **Chain reactions** — cascading clears are rewarded (score = gems × 10 × chain step).
- **Magic Jewel** — a rare, rainbow-pulsing column. Where it lands it wipes every gem of the
  color directly beneath it from the board.
- **Selectable starting speed** (levels 0–9); speed increases as you clear gems.
- **Deterministic, seed-driven** gem sequence — the same seed replays the exact same game.

## Controls

| Key | Action |
|-----|--------|
| ← → | move the column |
| ↑ | rotate (cycle the three gems) |
| ↓ | soft drop (faster fall) |
| Space | hard drop |
| Esc | back to main menu |

## Build & Run

Requires macOS 15+ and the Xcode toolchain.

```bash
swift build
swift run Steinregen
```

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
- `STEINREGEN_LEVEL=<0..9>` — starting speed
- `STEINREGEN_SEED=<UInt64>` — fixed seed (otherwise random)

## Architecture

Three Swift Package Manager modules plus tests:

- **`SteinregenCore`** — pure, deterministic game logic (board, falling piece, match detection,
  cascades, magic jewel, scoring). No global randomness and no wall-clock; all randomness flows
  through an injected, seeded PRNG.
- **`SteinregenRender`** — SpriteKit scene: rendering, the gravity/animation loop, gem textures,
  the magic-jewel animation.
- **`SteinregenApp`** — SwiftUI shell: start screen, keyboard input, game-over overlay.

The gem artwork and several reusable building blocks (the deterministic PRNG, the robust texture
loader, the three-module layout) come from the sibling project *Zaubersteine*.

## License

MIT — see [LICENSE](LICENSE).

🤖 Built with [Claude Code](https://claude.com/claude-code).
