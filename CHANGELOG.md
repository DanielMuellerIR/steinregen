# Changelog

All notable changes to Steinregen. Versions follow the `VERSION` file; the GitHub
release notes for each version are taken from the matching `## [version]` section below.

## [0.25.0]

- New fourth game mode **Crushed** (pentominoes): the brutal five-block variant of Entombed —
  all 18 one-sided pentomino shapes, full rows clear, five rows at once score 1200 × level.
  Default board 12×20, configurable 10–16 × 16–26.
- The mode picker is now a 2×2 grid of chips.

## [0.24.0]

- New third game mode **Blood Clots** (Puyo-style): pairs of stones fall and rotate around a
  pivot stone; groups of four or more connected same-colored stones clear, with chain reactions.
  Four colors, independently falling halves, simple wall kicks, no Magic Jewel.
- Board size configurable for the new mode as well (5–12 × 10–24, default 6×13).
- Fixed: the board-size card in Settings could show a stale mode when the dialog was opened
  through the automation seam.

## [0.23.9]

First public release.

- Two falling-block modes on one engine: **Rockfall** (Columns-style) and **Entombed** (Tetris-style).
- Six selectable stone sets (Sigils, Doom, Zaubersteine, G20, Jewels, FreeDoom) with live preview.
- Configurable board size per mode; selectable starting speed (1–10) or a constant "endless" tempo.
- Locally generated sound effects and three calm, atmospheric instrumental metal tracks.
- AI-generated foggy-night backgrounds, a different one each game.
- Graveyard high-score list; the Magic Jewel; seed-driven, reproducible games.
- Runs on macOS (keyboard) and iOS / iPad (touch); English and German UI with an in-app switch.
