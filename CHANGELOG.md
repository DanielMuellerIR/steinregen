# Changelog

All notable changes to Steinregen. Versions follow the `VERSION` file; the GitHub
release notes for each version are taken from the matching `## [version]` section below.

## [0.27.1]

- The "How to play" dialog now explains **all six game modes**, each in its own section,
  followed by mode-neutral controls and speed/end notes — no genre knowledge required.
  (Previously it only covered Rockfall.)

## [0.27.0]

- New sixth game mode **Reaper** (Lumines-style): 2×2 blocks of two stone kinds fall and
  rotate their colors; same-colored 2×2 squares are highlighted and harvested by a scythe —
  a sweep line that travels across the board and reaps marked sections as it passes their end.
  Block columns settle independently on lock; nothing clears on lock itself.
  Default board 12×12, configurable 8–16 × 8–16 (the genre's classic wide layout fits in).
- The mode picker is now a 3×2 grid of chips.

## [0.26.0]

- New fifth game mode **Exorcism** (falling-capsule style) — the first mode with a win
  condition: the board starts pre-seeded with **curses** (glowing ringed stones that stay
  pinned in place); clear runs of four in a row or column to purge them. Purge all curses
  and the game is **won** ("Exorcised"), with a bonus of 100 points per curse. Three colors,
  capsule pairs rotating around a pivot. The starting speed level also sets the number of
  curses (4 per level). Default board 8×16, configurable 6–12 × 12–24.

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
