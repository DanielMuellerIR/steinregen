# Changelog

All notable changes to Steinregen. Versions follow the `VERSION` file; the GitHub
release notes for each version are taken from the matching `## [version]` section below.

## [0.28.4]

Follow-up to the code review of 2026-08-20; no gameplay rule changed. The recorded games grew by
two cases and one changed case — the game itself behaves exactly as before, which the byte-for-byte
comparison of the 15 untouched cases confirms.

- Golden data now really cover **both** level rules. The comment claimed they did, but no
  row-clearing mode ever changed its level: the best case cleared 3 of the 10 rows a level needs.
  The new case `verschuettet-level` (5×20, starting at level 2) clears 10 rows and steps up to
  level 3, and because it is the only row case with a level other than 0 or 1 it also pins the
  factor `max(1, level)` in `linePoints` — 200 instead of 100 points per single row.
  `testRowModeLevelRuleIsCovered` keeps it that way.
- „Erdrückt" has its own end-of-game case. Its coverage rested on `fuenfling-a`, whose blocked
  spawn happened to fall on the 30th of 30 allowed pieces; one piece more survival time and the
  recording would have ended mid-fall again. `fuenfling-ende` (6×12) reaches the end after 11
  pieces.
- `kapseln-klein` now starts at level 5 instead of 1, so the **cap** in `curseCount`
  (`min(4 · level, (width · curseRows) / 2)`) actually binds: 18 curses instead of the 20 the level
  alone would ask for. At level 1 the case placed 4 curses — the same as on the large board, so the
  second branch of the formula was never exercised despite the comment promising it.
  `testCurseCountCapIsCovered` pins it.
- `steinregen-golden --out --check` used to write a 1.4 MB file literally named `--check` and
  report success while the requested comparison never ran — the same class of typo that was already
  closed for `--list` and `--help`, but in the only writing branch. Both `--out` and `--check` now
  reject a file argument starting with `--`.
- `tools/make-app.sh` removes a stale `dist/Steinregen-<version>.zip` whenever it skips the ZIP.
  This hung on `SKIP_SIGN=1`, which nothing in the repository sets; the real callers
  (`make-dmg.sh`, `make-notarized.sh`) use `SKIP_ZIP=1`, so on the path actually taken the outdated
  archive stayed put. The archive name is also taken from the single `ZIP` variable now instead of
  being reassembled from `VERSION`.
- `tools/make-dmg.sh` recognizes a leftover volume of its own across modes and versions. The check
  compared against the current run's RW name only, so after the split into `…-rw.dmg` and
  `…-test-rw.dmg` — or after a version bump — its own leftover was reported as a foreign disk
  image and the release run stopped with a wrong diagnosis. A plain empty directory under
  `/Volumes` no longer counts as a mount either.
- Same script: the `EXIT` trap is armed directly after `hdiutil attach`, not after parsing its
  output — that error branch used to leave a mounted volume behind, the very state the trap exists
  to prevent. And `hdiutil info` is captured into a variable before `awk` reads it, because `awk`'s
  `exit` on a hit closes the pipe and `pipefail` would abort the run with status 141 in exactly the
  case the check is for.
- The release gate binds `ditto "$APP" "$STAGED"` by text and by position. All four previous checks
  stayed green if that line was changed to write to `$DESTINATION`, which would overwrite a working
  installation before Gatekeeper ever evaluated it. Verified by making exactly that change: the
  gate now fails. The repeated order checks moved into one `require_order` helper.
- CI runs the TypeScript port. `npm ci`, `npm test` and `npm run typecheck` in `web/` ran nowhere
  automatically, although AGENTS.md lists them as mandatory.
- `draw` in the port is tested instead of merely being called "done": it is checked against the
  starting piece and preview of every recorded game of the three colour modes. It consumes PRNG
  values, so a single value too many shifts the whole piece sequence. Verified by drawing one extra
  value — exactly those tests fail.
- `npm test` runs `test/*.test.ts` instead of everything under `test/`. The helper modules
  `replay.ts` and `golden.ts` showed up in the report as test files with zero tests and loaded the
  1.4 MB data file twice more.
- `applyMagic` in the port no longer sorts what `cellsOf` already delivers in board order (Swift
  does not sort there either), and its documentation says what the function does: it takes the
  colour as an argument, never looks below the landing position, and has no fizzle branch. That
  precondition lives with the caller in Swift and is still unported — noted as such.
- Corrected comments that the data contradict: the capsule cases do not reach the win condition,
  the full-width row cases do clear the odd row (`verschuettet-schmal` is there for its double
  row), and seed 0 does not exercise the xoshiro null-state branch, because SplitMix64 never yields
  four zeros. `golden/README.md` gains the second, fizzling Magic Jewel and the note that `m` never
  appears in a board string.
- `GoldenSnapshot.piece` is no longer optional — all six modes always have a piece, in all 7168
  recorded states — and the recording player moved into its own `ScriptedPlayer` type, so `record`
  is left with recording and the field diff. The placeholder check throws its own error case
  instead of borrowing "JSON could not be read as UTF-8". `testEveryModeReachesTheEndOfAGame`
  continues past an empty case instead of aborting the whole test function on the first one.

## [0.28.3]

Follow-up to the code review of 2026-08-06; no gameplay rule changed.

- Golden data now cover the end of a game for every mode. `saeulen`, `klumpen`, and `schnitter`
  previously stopped mid-play because a recording ends after a fixed number of pieces, so no replay
  ever exercised their blocked-spawn/game-over path. Three short games on a narrow 4×8 board
  (`saeulen-ende`, `klumpen-ende`, `schnitter-ende`) now run all the way to `gameOver`, and a new
  test pins that minimum coverage. The existing cases are untouched — the new ones are appended, so
  the diff of the data file is purely additive.
- Honest gap instead of a test that only looked like it checked something: no recorded capsule game
  ever clears a curse, so the curse bonus and the settling afterwards were never exercised. The
  golden-driven test dropped that claim from its name, and a staged board now covers the bonus of
  100 points, the shrinking curse set, and the loose stone dropping all the way down. Verified by
  scoring the bonus after settling instead of before — exactly that one test fails.
- `steinregen-golden` rejects surplus arguments for `--list` and `--help`. `--list --check FILE`
  used to list the cases and report success without ever running the requested comparison.
- The PRNG test compares against fixed published reference numbers now (SplitMix64 from state 0,
  the first xoshiro256** value for seed 1) and pins the exact set of seeds. It previously only
  checked that the exported strings parse back into a 64-bit number, which cannot fail for values
  produced by `String(rng.next())`.
- `tools/make-dmg.sh` no longer force-ejects any volume named `Steinregen` before building. It
  unmounts only a leftover of its own run (same image file, compared by inode) and otherwise stops
  with a clear message, so a foreign disk image that is being written to stays mounted. Its own
  device is unmounted through a `trap`, so an aborted run no longer leaves a volume behind.
- Test runs of `tools/make-dmg.sh` (`--no-notarize`, `--no-finder-layout`) write
  `dist/Steinregen-<version>-test.dmg` instead of overwriting an already notarized release DMG of
  the same version.
- `tools/make-app.sh` removes a stale `dist/Steinregen-<version>.zip` when `SKIP_SIGN=1` skips the
  ZIP. The distributable name could otherwise keep an older archive that looked like the result of
  the unsigned run.
- The release gate checks that `install.sh` evaluates the staged copy with Gatekeeper *before* the
  swap, by line number, instead of merely finding the text somewhere in the file. Its lookup helper
  no longer aborts the whole script silently when a searched line is missing.
- Dead error case `GoldenError.mismatch` removed; `--check` writes its diagnosis to stderr directly.
- Documentation corrected where it contradicted the code: the port status lives in `web/README.md`
  alone, `ClearStep.cells` keeps the core's collection order (flood-fill order for "Blutklumpen")
  instead of always board order, and the golden data no longer claim to cover the capsule victory.

## [0.28.2]

- TypeScript port continues in `web/`: board, cells, match detection, settling, and the cascade
  loop. Checked against the recordings rather than invented examples — every board round-trips
  through encoding (about 900 of them), and every clear wave the Swift core produced in a real
  game is recalculated with its cells, chain level, points, and resulting board.
- Verified by reintroducing four typical porting mistakes, each caught by the suite: a missing
  board copy, dropped diagonals in `findMatches`, `findGroups` connecting across corners, and
  `settlePinned` letting stones slip past a curse.
- Golden data made stricter: `ClearStep.cells` is now exported in the order the core collects the
  cells instead of being sorted first. That order is visible — the display removes stones in
  exactly that sequence. Only the "Blutklumpen" mode is affected, where the flood fill has its own
  order; every other mode already sorts inside the core. `curses` and `marked` stay sorted, since
  those really are sets. Documented in `golden/README.md`.
- Two Swift-to-JavaScript pitfalls documented where they bite, in code and in `web/README.md`:
  `Board` is a value type in Swift and needs an explicit `clone()` here, and `Cell` cannot go into
  a plain `Set` because JavaScript compares objects by identity.

## [0.28.1]

- First building block of the TypeScript port in `web/`: both random number generators
  (`SplitMix64`, `Xoshiro256StarStar`) reproduce all ten reference sequences from the golden data
  bit for bit. Everything else in the core depends on this — a different sequence means different
  stones, hits, and scores.
- 64-bit arithmetic uses `bigint` with an explicit `BigInt.asUintN(64, …)` after every operation,
  because BigInt never overflows on its own the way Swift's `&+`, `&*`, and `<<` do. Verified by
  reintroducing two typical porting mistakes — a missing truncation and a swapped shift width —
  both of which the tests catch.
- `below()` deliberately keeps Swift's slightly biased `next() % n`. Replacing it with a
  statistically cleaner draw would yield different stone colours for the same seed.
- Measured rather than assumed: one draw costs about 100 ns, so BigInt is irrelevant to this
  game's performance and a 32-bit-halves implementation would be needless complexity.
- Honest gap, documented in code and in `web/README.md`: the all-zero state guard cannot be
  triggered from outside, since SplitMix64 never yields four zeros. Removing it leaves the suite
  green; no test covers it.
- No build tooling: Node 23.6+ runs the TypeScript sources directly, `tsconfig.json` only type-checks.

## [0.28.0]

- Golden data for the game core: `golden/steinregen-golden.json` records complete games for all six
  modes move by move — board, score, and every clear wave — plus the raw output of both random
  number generators. It is the reference a port of the core in another language (planned:
  TypeScript for a mobile web app) has to reproduce field by field. Format and known gaps are
  documented in `golden/README.md`.
- New `steinregen-golden` tool (library `SteinregenGolden` plus a thin CLI target) with
  `--out`/`--check`/`--list` and meaningful exit codes, driven by `tools/make-golden.sh`. It depends
  on the core alone, so it builds without the Xcode toolchain.
- `SteinregenGoldenTests` ties the checked-in data to the current core: any core change makes the
  test fail and names the first differing line, so the data can never drift unnoticed. Verified by
  temporarily altering both the data file and a scoring rule.
- Recording uses a simple placement heuristic rather than random moves. A purely random player
  towered up and lost before anything interesting happened — it cleared no row at all in the
  row-clearing modes. The heuristic is recording machinery, not part of the game.

## [0.27.15]

- Memory: the backdrop cache now retains only the currently selected decoded image; switching
  repeatedly across several motifs is covered by a retention regression test.
- CI security: checkout fetches the complete Git history and a SHA-pinned gitleaks action runs
  Gitleaks 8.30.1 as a mandatory gate. All action/tag pins were verified against their official
  upstream repositories.
- Publish safety: the Git remote and `GITHUB_REPO` must resolve to the same canonical GitHub
  repository. After the single release tag is pushed, its remote commit must equal `HEAD`, and a
  new release requires `gh release create --verify-tag`; fake git/gh tests cover mismatches and
  ordering without touching GitHub. A guarded `SKIP_SIGN=1` path permits local app-bundle build
  verification without invoking codesign or producing a distribution ZIP.

## [0.27.14]

- CI maintenance: pinned `actions/checkout` v7.0.0 (Node 24) to its verified commit SHA and remove
  an unrelated untrusted Homebrew tap from the ephemeral runner before installing xcodegen. This
  eliminates both remaining workflow annotations without changing the application.

## [0.27.13]

- CI compatibility: applied the same explicit teardown-storage isolation used by
  `BoardConfigTests` to `FriedhofTests`. GitHub's macOS 15 runner invokes XCTest setup and teardown
  outside the Main Actor; only the two private, serial test-instance backups opt out of isolation.

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
