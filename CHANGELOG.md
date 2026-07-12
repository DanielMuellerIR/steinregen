# Changelog

All notable changes to Steinregen. Versions follow the `VERSION` file; the GitHub
release notes for each version are taken from the matching `## [version]` section below.

## [0.27.12]

- CI compatibility: made the `BoardConfigTests` teardown storage explicitly nonisolated because
  XCTest invokes `tearDown()` outside the Main Actor on GitHub's macOS 15 runner. The storage is
  private to one serial test instance; production code and deterministic game logic are unchanged.

## [0.27.11]

- Publication readiness: refreshed all six smoothed Zaubersteine assets from the sibling project,
  removing the remaining white edge halos.
- Privacy and portability: notarization scripts no longer contain a personal Developer ID or Team
  ID. They discover a Developer-ID Application certificate from the local keychain, allow an
  explicit `SIGN_ID` override, and keep `NOTARY_PROFILE` as the only required local input.
- Documentation: corrected the English and German feature descriptions, added the offline privacy
  guarantee, clarified the trademark language, and updated asset provenance against current
  primary license sources. FLUX.1 [dev] output rights are no longer misreported as a blanket
  non-commercial restriction. The supported desktop scope is now explicit: macOS 15+ on Apple
  Silicon; Intel builds are intentionally out of scope.
- Release safeguards: added `tools/check-release-readiness.sh` and wired it into CI to verify
  version consistency, required documents and licenses, local Markdown links, the 1280×640 social
  preview, the contiguous 13-track music pool, shell syntax, private strings, and (when installed)
  the complete Git history with gitleaks.
- CI supply chain: pinned `actions/checkout` v4.3.1 to its verified full commit SHA instead of a
  moving major-version tag. CI now also builds the iOS Simulator app, covering platform-specific
  Swift code instead of testing only the shared/macOS compilation path.
- Security policy: documented the supported version, private-reporting path, offline data scope,
  and the rule never to disclose sensitive vulnerability details in a public issue.
- Binary licensing: macOS ZIP/DMG and iOS app bundles now carry Steinregen's MIT notice and the
  full asset inventory alongside the already bundled Freedoom BSD and Grenze Gotisch OFL texts.
  The bundled Freedoom notice now correctly covers the `ds*.m4a` sound set restored in v0.13.0,
  instead of retaining the obsolete v0.12.0 claim that no Freedoom sounds ship.
- Test hygiene: removed four ineffective assignments to a weak `GameScene.model` reference, so the
  complete 118-test build is warning-free.
- Build reliability: fixed two unbraced shell variables directly followed by Unicode punctuation;
  UTF-8 Bash otherwise interpreted the punctuation as part of `VERSION`/`SIGN_ID` and aborted the
  iOS or signed macOS build under `set -u`.
- Publish safety: `make-dmg.sh --publish` now validates repository syntax, GitHub authentication,
  a clean `main`, the matching changelog/tag, and an identical remote `main` before building. It
  pushes only the single release tag, never the repository's archived tags.
- DMG reliability: the Finder layout now reads back and retries its window bounds, avoiding the
  intermittent macOS 26 behavior where a single assignment leaves the wrong window size.
- Social preview: visually reviewed the project-native composition and verified that
  `tools/make-social-preview.swift` reproduces `assets/social-preview.png` pixel-for-pixel.

## [0.27.10]

- Release documentation: corrected the unpublished GitHub-release links and documented the
  bundled music accurately — three tracks are local ACE-Step XL Turbo outputs, ten are from
  MiniMax Music 2.6, all at 128 kbit/s stereo.
- Notarization: the release scripts now require an explicit `NOTARY_PROFILE` instead of assuming
  a machine-specific profile name.

## [0.27.9]

- Music: added ten selected instrumental metal tracks to the bundle (13 in total). Playback
  now uses a fresh random, non-repeating order: every track plays once before the next shuffled
  run begins, and the first new track cannot repeat the previous one.
- Mobile bundle: the ten added tracks are encoded as 128 kbit/s stereo MP3, matching the existing
  music instead of their original 256 kbit/s encoding.

## [0.27.8]

- Memory: the backdrop images are now loaded lazily. Previously `Theme.backdropImages()`
  decoded and permanently cached all five night backgrounds, though only one is drawn per
  game (tens of MB decoded on iOS). Split into `backdropCount()` (file probe, no decode)
  and `backdropImage(_:)` (loads and caches only the chosen index).

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
