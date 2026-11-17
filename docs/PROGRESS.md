# Progress log

Newest first. Each milestone: what's done, how it was verified, decisions, deferred work, known issues.
Plan: `docs/PLAN.md`. Spec: `docs/FABLE_BRIEF.md`.

## Status
| Milestone | State |
|---|---|
| M0 Save / load | **done** |
| M1 Party & companion combat | **done** |
| M2 Treats, bond, Lustre, Alphas | **done** |
| M3 Gathering & block mining | next |
| M4 – M8 | not started |

## Standing issues
- **Web build is 86 MB zipped** (149 MB `index.pck` + 39 MB wasm unzipped) after M2. Budget is 120 MB download.
  The character/outfit and district assets added most of it; M3+ assets must be budgeted (see PLAN risks).
- No new asset packs have been downloaded yet (none needed before M3).

## Web export checks
| Date | Build | Result |
|---|---|---|
| 2026-11-17 | M0 + M1 + M2 (`eeb024a`) | Export OK with no errors (Godot 4.7.2 templates installed from the official release). In Chromium (browser pane, served from `export/web` on localhost) the engine boots: WebGL 2 / Compatibility, single-threaded, no console errors. The exported `index.pck` also runs 600 frames headless in desktop Godot with zero errors, so every scene, script and `data/*.json` is in the pack. **Not seen:** in-browser gameplay frames (the pane was hidden, so the page didn't render). |

---

## M2 — Treats, bond, Lustre, Alphas (2026-11-17)
**Done**
- **Treats** (`data/treats.json`): 14 treats in 4 tiers (Simple → Hearty → Royal → Mythic) and 5 flavours (sweet,
  spicy, savory, sour, bitter). Every species has a favourite flavour in `data/creatures.json` (×2 bond).
- **Inventory** (`player.inventory`, item id → count; saved). New games start with 5 Simple treats. The Oakvale
  merchant sells Simple + Hearty treats, Gadgeteer Vex in the Neon Bazaar sells Royal ones too.
- **Bond meter 0–100** replaces the old 3-step affection: petting +8 (once per conversation), treats +bond
  (×2 favourite), sparing +20. At 60 the creature asks to join. Dialogue shows a heart bar and, after the first
  bond, the creature's favourite flavour. Bond is saved per wild creature. The coin "snack" is gone; treats calm
  hostile creatures instead.
- **Alphas** (`data/alphas.json`): one per wild zone — Mushroom King (Grove), Sky Wyrm (Skyport), Alpha
  Skullcrusher (Ivy Ruins, new) and Alpha Voidwalker (Lab, new). Crown icon, 1.5× size, level +4, phase 2 below
  half HP (faster tells, shorter cooldowns, harder hits), accept only Mythic treats, and drop a material
  (`data/materials.json`) when defeated or calmed. Alphas can now join the party and keep their crown.
- **Lustre variants:** 1 in 200 creatures, picked from a hash of the scene path so it's stable across loads;
  gold tint, ✦ marker, +10 % HP and attack, "Lustre" name; stays Lustre as a companion.

**Verified:** `tests/test_bond.gd` — 44 checks (data, bond maths, favourite ×2, petting once, hostile needs calming,
treat calms, Alpha refuses non-Mythic, phase 2, drops, Alpha befriending, Lustre stats, treat shop + price cap,
save of inventory, bond and Alpha companion). All 113 checks across the 3 test files pass. Screenshots checked:
treat dialogue with bond bar, crowned Alpha and a Lustre creature in the Ivy Ruins.

**Decisions**
- **Interim Mythic source:** until crafting (M4), defeating or calming an Alpha also gives one Mythic Morsel, so the
  Alpha chain works today: beat one Alpha → befriend the next. M4 replaces this with a recipe that uses Alpha
  materials.
- "Fighting beside it" as a bond source is deferred: wild creatures don't fight alongside you yet.

**Known issues**
- The Lustre tint is subtle on dark models; the ✦ marker is what makes it readable.
- The Ivy Ruins' new Alpha sits close to the plaza walls; fine in play but worth a look in the M5 layout pass.

---

## M1 — Party & companion combat (2026-11-17)
**Done**
- **Data:** `data/creatures.json` (all 50 monster models: name, element, HP, attack, speed, size, 2 moves),
  `data/moves.json` (12 moves: lunge / shot / slam, 2 per element), `data/elements.json` (6 elements on a wheel:
  ember → verdant → stone → gale → shade → tide → ember; 1.5× / 0.67×). `scripts/data.gd` loads them;
  `tools/sync_creatures.py` adds entries for new models and re-measures heights without touching tuned stats.
- **Party:** befriended creatures become companions (party of 3, unlimited storage). A 4th goes straight to
  storage. `player.party`, `player.storage`, `befriend()`, `deposit()`, `withdraw()`, `rest()`.
- **Companion AI** (`scripts/companion.gd`, driving the same enemy.gd node): formation follow, teleport when left
  far behind, wind-up → lunge / shot / slam → recover with each species' two moves and cooldowns, companion
  attack tokens (max 2 at once). Commands **1 Attack · 2 Follow · 3 Hold · 4 Return** (touch: ATK/FLW/HLD/RET
  buttons that appear once you have companions).
- **Wild creatures fight companions too:** a creature hit by a companion usually turns on it; bosses slam
  everyone in the ring. Damage everywhere goes through the element wheel (critical hits show "!" in orange).
- **Companions level up** with XP shared from every reward; stats scale with level from `data/creatures.json`.
- **Exhausted:** a companion at 0 HP turns into a ghost that follows but can't fight, until you rest.
- **Creature Ledger** (book stand by the Oakvale gate): rest (heal + revive + autosave), store and take companions.
- **HUD:** party cards with element badge, name, level, HP bar and state, plus the current command.
- **Save:** party and storage records (`uid, species, name, level, xp, hp, origin, lustre`) and the party command.
  Wild creatures that were befriended stay gone from the world after loading.
- Wild creatures get a level per zone (Oakvale 1 … Skyport 6, bosses +4), which a befriended companion keeps.

**Verified:** `tests/test_party.gd` — 44 checks: data integrity of all 50 species, element wheel, party/storage
overflow, follow, companions killing a locked target with no player input, shared XP, retargeting, exhaustion
and rest, hold / return, ledger swaps, save round trip of party + storage + HP + command. `tests/test_save.gd`
still passes (25). Rendered check in a real window: companions fighting the Grove Yeti, party HUD, ledger menu.
Web: see "Web export checks".

**Decisions**
- Companions reuse `enemy.gd` (model, animation, damage, death) with the brain swapped to `companion.gd`, rather
  than a parallel scene: one creature implementation, and any monster model works as a companion.
- Data is JSON, not GDScript consts, so the Python generators read the same numbers.
- The Ledger lives in Oakvale until Sanctuaries exist (M5), which will absorb it.
- New input actions are added at runtime by `scripts/input_setup.gd` instead of editing `project.godot`.
- The harness now has a watchdog: a script error fails a test in seconds instead of hanging the runner.

**Deferred**
- A radial / D-pad command wheel for gamepads (keys and touch buttons cover desktop and phone today).
- Companion portraits (element badges stand in until the portrait art pass).
- Wild-creature levels only set companion stats; wild HP is still the hand-tuned value from the generator.

---

## M0 — Save / load (2026-11-16)
**Done**
- `scripts/save_game.gd`: JSON save at `user://save.json` (IndexedDB on web), schema v1 with `migrate()`.
- `scripts/game.gd`: `Game` node (added by the generator as the last node of `arena.tscn`). Loads on start, autosaves
  every 2 minutes, on window close and when the window / browser tab loses focus. `F5` saves, `F9` reloads the save.
- Saved: player level, XP, coins, max HP, HP, position, respawn point, gear, owned items, route counters;
  opened chests, spared creatures, befriended creatures (by generator node path); world flags; discovered
  Sanctuaries (empty until M5). Inventory / party / storage keys exist in the schema and fill in at M1 and M4.
- A returning player skips the intro flyover. HUD shows a "Game saved" toast.
- Test tooling: `tests/harness.gd`, `python tools/run_tests.py` (fails on any `FAIL` line or engine error).

**Verified:** `tests/test_save.gd` — 24 checks pass headless (round trip of every field, chest / friend / spared
state, corrupt file → clean new game with no engine error, v0 → v1 migration). Web: see "Web export checks".

**Decisions**
- World objects are keyed by node path relative to the scene root. The generator's names are deterministic, and
  unknown paths in a save are skipped rather than failing the load.
- Tests redirect the save path (`Game.override_path`) so they never touch the player's real save.
- Autosave does not run while the player is dead (no checkpointing a corpse).

**Fixed along the way:** re-dressing the hero (`avatar.gd`) freed parts that still held override materials, which
logged an engine error per armor change; overrides are now cleared first.

**Deferred**
- "Autosave on resting at a Sanctuary" lands with Sanctuaries in M5 (`Game.save()` is the hook).
- A New Game / erase-save button comes with the main menu in M8; until then delete `user://save.json`
  (`%APPDATA%\Godot\app_userdata\Arena Proto\save.json`).
