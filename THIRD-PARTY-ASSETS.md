# Third-Party Assets & Attribution

Steinregen's own source code is MIT-licensed (see [LICENSE](LICENSE)). This file documents the
origin and license of every bundled asset that is **not** original Steinregen code, so the rights
situation is auditable before any (re)distribution.

## Fonts

- **Grenze Gotisch** (`GrenzeGotisch-Regular.ttf`, `GrenzeGotisch-Bold.ttf`) — by Omnibus-Type.
  SIL Open Font License 1.1. License text:
  `Sources/SteinregenRender/Resources/GrenzeGotisch-OFL.txt` (bundled).
  Commercial use allowed; the font may not be sold on its own. ✅

## Sound effects & the "FreeDoom" stone set

- **Freedoom sound effects** (`ds*.m4a`) and the **"FreeDoom" stone-set sprites** (`fd_*.png`,
  cropped/scaled at runtime from original Freedoom sprites) — from the
  [Freedoom](https://github.com/freedoom/freedoom) project. BSD-3-Clause. License text:
  `Sources/SteinregenRender/Resources/FREEDOOM-LICENSE.txt` (bundled). These are Freedoom's own
  free assets, not the original commercial Doom material. Commercial use allowed with
  attribution. ✅

## Gem sets (from the sibling project *Zaubersteine*)

- **Gem stone images** (`ruby.png`, `sapphire.png`, `emerald.png`, `topaz.png`, `amethyst.png`,
  `diamond.png`) and **SVG-rendered stones** (`svg_*.png`) — original artwork created by the author
  in Affinity Designer for the sibling project *Zaubersteine* (MIT). Own work. ✅

## Background images

- **`hintergrund.png`, `hintergrund-2.png` … `hintergrund-5.png`** — five foggy-night motifs
  (graveyard, dead winter forest, ruined gothic cathedral, foggy moor, blood-red moon) generated
  locally with the open **Qwen-Image** model. The game picks one at random per game. Qwen-Image
  permits commercial use. ✅

## Logo

- **`logo.png`** — derived from a logotype produced with a locally-run **FLUX.1 [dev]** image
  model. ⚠️ FLUX.1 [dev] is licensed for **non-commercial** use by Black Forest Labs. Fine for
  non-commercial distribution; the output-rights situation must be verified (or the logo replaced)
  before any commercial release. See the open items below.

## Music

- **`musik-1.mp3`, `musik-2.mp3`, `musik-3.mp3`** — three calm, atmospheric instrumental metal
  tracks generated locally with the open **ACE-Step** model. ACE-Step permits commercial use. ✅
- **`musik-4.mp3` … `musik-13.mp3`** — ten selected instrumental metal tracks generated with
  MiniMax Music 2.6. Their applicable MiniMax service terms must be verified before a commercial
  redistribution; they are therefore not marked license-clean here. ⚠️

## App icon

- Procedurally generated at build time (`tools/icon-compose.swift`). Own code, MIT. ✅

## Game design

- Steinregen has six modes, each inspired by a classic falling-block genre: **Rockfall** (a clone
  of the gameplay of Sega's *Columns*, 1990), **Entombed** (a falling-tetromino,
  fill-and-clear-rows mode in the long tradition of that genre), **Blood Clots** (a
  connected-groups pair mode in the *Puyo Puyo* tradition), **Crushed** (Entombed with
  pentominoes), **Exorcism** (a clear-the-pre-seeded-board mode in the *Dr. Mario* tradition), and
  **Reaper** (a timeline-sweep mode in the *Lumines* tradition). Game mechanics and rules are not
  copyrightable. All referenced game names are trademarks of their respective owners; Steinregen
  uses none of those names for itself and is not affiliated with or endorsed by anyone. The code
  deliberately uses generic terms ("Tetromino", "Pair", "Capsule", "Square").

## In-game text

- The game-over epitaph is Steinregen's own line since v0.23.0 ("Am Ende fällt jeder Stein" /
  "In the end, every stone falls"); the earlier Bethlehem quote has been removed. ✅

---

## Before a COMMERCIAL release — open items

Steinregen is currently intended for **non-commercial** release only; the items below are **not**
blockers for that. They must be resolved before any commercial distribution:

1. **logo.png** — FLUX.1 [dev] outputs are under a non-commercial license. Verify the exact
   output-rights terms with Black Forest Labs, obtain a commercial license, or replace the logo
   with a fully owned asset.
2. **Bethlehem epitaph** — ✅ resolved in v0.23.0: the quoted line was replaced with an original
   epitaph ("Am Ende fällt jeder Stein" / "In the end, every stone falls").
3. **Sega/Columns trademark** — keep the "independent clone, not affiliated with Sega" disclaimer
   prominent (already stated above and in the README).
4. **Tetromino mode (Entombed)** — the falling-block genre's market leader is aggressively
   enforced: the name is a registered trademark, and courts have found that closely reproducing the
   original's specific *expression* (playfield proportions, the seven standard pieces, the
   next-piece display, the 100/300/500/800 line-clear scoring) can infringe **copyright** even
   under a different name. Non-issue for a non-commercial hobby release; before any paid
   distribution, differentiate the mode visibly or take legal advice. Never use the trademarked
   name in the app, store text, or marketing.
5. **FreeDoom & Grenze Gotisch attribution** — already license-clean; for a polished commercial
   build, surface the attributions in an in-app "About" screen as well.
