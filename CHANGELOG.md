# Changelog

All notable changes to Steinregen. Versions follow the `VERSION` file; the GitHub
release notes for each version are taken from the matching `## [version]` section below.

## [0.27.7]

- Tests: closed the highest-value coverage gaps in the previously untested config/
  persistence helpers — board-size clamping (`BoardConfig`), language resolution
  (`L10n.lang`), `GameMode` metadata consistency (defaults within ranges), and the
  persistent high-score list (`Friedhof`: sorting, cap, JSON round-trip). +13 tests
  (117 total); adds a `SteinregenAppTests` target for the app layer.

## [0.27.6]

- Internal: the 1580-line `SteinregenApp.swift` is split along its existing view
  boundaries into eight focused files (StartView, SettingsView, GameplayView,
  GameOverOverlay, FriedhofView, RulesSheet, TouchControls) plus a `SharedUI` file
  holding the reused helpers (`themeCard`, `StepperArrow`, `DoneButton`, the color and
  dialog-frame helpers). Pure move + de-duplication; the UI is pixel-identical.

## [0.27.5]

- Internal: shared engine building blocks extracted — scoring/level pacing now live in a
  mode-neutral `Scoring` namespace (previously hidden as statics on the Columns engine),
  and the color draw, collision check (`Board.fits`), and cascade loop that Blood Clots /
  Exorcism / Reaper had each duplicated verbatim are now single shared functions.
  No behavior change; determinism tests confirm identical runs.

## [0.27.4]

- Internal: the mode-neutral `PlayEngine` protocol is split into a display core
  (board, score, phase, visual seams) and a `FallingPieceEngine` sub-protocol carrying
  the falling-piece verbs (move/rotate/step/spawn). No behavior change — this prepares
  future modes that have no falling piece (catch-paddle or cursor-swap styles).

## [0.27.3]

- Determinism polish: match results (`findMatches`, `findLines`, Reaper harvests) now
  return their cells in a fixed board order (row, then column) instead of Swift's
  process-random set order. Game state was always deterministic; now the *order* of
  cleared cells (and thus clear animations and future replays) is too.

## [0.27.2]

- Music tracks are now discovered automatically: drop another gaplessly numbered
  `musik-N.mp3` into the bundle and it joins the playlist — no code change needed
  (previously the track list was hard-coded).

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
