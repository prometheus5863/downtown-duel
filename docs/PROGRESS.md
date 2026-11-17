# Progress log

Newest first. Each milestone: what's done, how it was verified, decisions, deferred work, known issues.
Plan: `docs/PLAN.md`. Spec: `docs/FABLE_BRIEF.md`.

## Status
| Milestone | State |
|---|---|
| M0 Save / load | **done** |
| M1 Party & companion combat | **done** |
| M2 Treats, bond, Lustre, Alphas | next |
| M3 – M8 | not started |

## Standing issues
- **Web export is NOT VERIFIED.** The Godot 4.7.2 Web export templates are not installed on the dev PC, so
  `--export-release "Web"` cannot run. Install them (Editor → Manage Export Templates) and re-run the export for
  every milestone below marked "web: not verified".
- No new asset packs have been downloaded yet (none needed before M2/M3).

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
Web: not verified (no templates).

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
state, corrupt file → clean new game with no engine error, v0 → v1 migration). Web: not verified (see above).

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
