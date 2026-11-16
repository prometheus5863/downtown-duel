# Progress log

Newest first. Each milestone: what's done, how it was verified, decisions, deferred work, known issues.
Plan: `docs/PLAN.md`. Spec: `docs/FABLE_BRIEF.md`.

## Status
| Milestone | State |
|---|---|
| M0 Save / load | **done** |
| M1 Party & companion combat | next |
| M2 – M8 | not started |

## Standing issues
- **Web export is NOT VERIFIED.** The Godot 4.7.2 Web export templates are not installed on the dev PC, so
  `--export-release "Web"` cannot run. Install them (Editor → Manage Export Templates) and re-run the export for
  every milestone below marked "web: not verified".
- No new asset packs have been downloaded yet (none needed before M2/M3).

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
