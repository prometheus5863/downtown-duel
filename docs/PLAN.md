# Build plan — Downtown Duel → open-world creature RPG

Spec: `docs/FABLE_BRIEF.md`. This file says *how* each milestone gets built: files, data schemas, tests, risks.
Progress and decisions are logged in `docs/PROGRESS.md`.

## Ground rules (from the brief, made concrete)
- **Engine:** Godot 4.7.2, GDScript, Compatibility renderer. No `class_name` globals; scripts are preloaded.
- **Data lives in `data/*.json`.** JSON (not GDScript consts) because the Python generators read the same files.
  Loaded through `scripts/data.gd` (cached `Data.creatures()`, `Data.moves()`, …). The Web preset's
  `include_filter` gains `data/*.json`.
- **World stays generated.** `tools/gen_world.py` (later split per region) writes `scenes/*.tscn`. City layouts,
  mine parameters and estate tiers are generator *inputs* under `data/`.
- **Tests:** `tests/test_*.gd` are headless SceneTree scripts that print `PASS <name>` / `FAIL <name>: why` and exit
  non-zero on failure. `python tools/run_tests.py` runs them all; it must be green before every commit.
- **Milestone gate:** all tests green → Web export loads → docs updated → commit.
- **Input:** new actions are registered at runtime by `scripts/input_setup.gd` (one table: action → keys), so
  `project.godot`'s fragile hand-edited InputEvent blocks are not touched. Every new action also gets a touch button.
- **Save compatibility:** `save.version` bumps when the schema changes; `save_game.gd` migrates old saves forward.

## Open blockers (owner action needed)
| Blocker | Why it matters | What to do |
|---|---|---|
| Godot **Web export templates 4.7.2** are not installed on the dev PC | the per-milestone "Web export loads" check cannot run | Godot → Editor → Manage Export Templates → Download and Install (or approve a download of `Godot_v4.7.2-stable_export_templates.tpz`, about 1 GB) |
| New asset packs (M2+, see the brief's table) | each is a download from quaternius.com / kaykit / kenney.nl | approve downloads when the milestone that needs them starts; otherwise URLs + target folders get listed in `docs/PROGRESS.md` |

Until the templates exist, each milestone records "web export: NOT VERIFIED" in `docs/PROGRESS.md`.

---

## M0 — Save / load
**Files**
- `scripts/save_game.gd` — static helpers: `write(path, dict)`, `read(path)`, `migrate(dict)`, `SAVE_PATH`, `VERSION`.
- `scripts/game.gd` — `Game` node in `arena.tscn` (generator adds it last). Collects state from the player and the
  world, applies it on load, autosaves every 120 s, on window close and on focus loss (browser tab hidden).
  `F5` quick-save, `F9` reload last save. Group `"game"` so other nodes find it.
- `scripts/player.gd` — `to_save()` / `from_save(d)`.
- `scripts/chest.gd` — `opened` persisted by node path. `scripts/hud.gd` — "Saved" toast.

**Schema v1** (`user://save.json`; IndexedDB on web)
```json
{ "version": 1, "saved_at": 1731700000, "play_time": 0.0,
  "player": { "level": 1, "xp": 0, "coins": 0, "max_hp": 100, "hp": 100, "pos": [0, 1.1, 0],
              "gear": {"weapon": "wood_knuckles", "armor": "cloth_tunic", "charm": ""},
              "owned": ["wood_knuckles", "cloth_tunic"], "route": {"defeated": 0, "spared": 0, "friends": 0},
              "spawn": [0, 1.1, 0] },
  "inventory": {},                    // M4: item id -> count
  "party": [], "storage": [],         // M1: creature records
  "world": { "chests": ["World/Ruins/Chest1"], "befriended": ["World/Village/Clucky1"],
             "spared": [], "flags": {}, "sanctuaries": [] } }
```
**Tests** `tests/test_save.gd`: change every saved field, open a chest, befriend a creature → save → fresh scene →
load → all equal; corrupt file → clean new game; version-0 dict migrates.
**Risks:** web persistence needs `user://` flush (close the file; save on focus loss). Node paths as world IDs
break if the generator renames nodes → generator names are deterministic (`uname`), and unknown paths are skipped.

## M1 — Party & companion combat
**Data**
- `data/elements.json` — `{ "order": ["ember","verdant","stone","gale","shade","tide"], "strong": 1.5, "weak": 0.67,
  "colors": {…} }`. Each element beats the next in `order` (wraps), and is weak attacking the previous one.
- `data/moves.json` — `id → { name, element, kind: "lunge"|"shot"|"slam", power, cooldown, range }` (2 per element).
- `data/creatures.json` — `species → { name, element, hp, atk, speed, moves: [id, id], model }` for all 50 models in
  `assets/monsters` (species id = `"Blob/GreenBlob"`). Companion stats = base × level scaling
  (`hp × (1 + 0.12 (lv−1))`, `atk × (1 + 0.10 (lv−1))`). Wild HP stays what the generator places (already tuned).
- **Creature record** (party / storage / save): `{ uid, species, name, level, xp, hp, origin, lustre }`.

**Files**
- `scripts/data.gd` — JSON loader + `element_mult(attack, defend)`.
- `scripts/enemy.gd` — gets `species`, `element`, `level`, a `_foe` (player *or* a companion) instead of
  player-only targeting, `take_damage(amount, dir, source, element)`, and hands its tick to the brain when befriended.
- `scripts/companion.gd` — brain (RefCounted) for befriended creatures: formation follow, target choice per command,
  wind-up → move (lunge / shot / slam) → recover, companion attack tokens (max 2 at once), leash to the player,
  exhausted "ghost" state at 0 HP.
- `scripts/creature_factory.gd` — builds a creature node from a record (withdrawn from storage, or on load).
- `scripts/player.gd` — `party` (max 3, replaces `followers`), `storage`, `befriend()`, `command_party()`,
  XP shared with the party. `scripts/input_setup.gd` — `cmd_attack/follow/hold/return` (1–4), `party_menu` (P).
- `scripts/ledger.gd` — Creature Ledger interactable (swap party ↔ storage, rest). Interim spot in Oakvale until M5.
- `scripts/hud.gd` + `scripts/party_panel.gd` — party cards (name, level, element badge, HP bar, state), command line.
- `scripts/touch_controls.gd` — 4 command buttons. `scripts/projectile.gd` — element, colour, friend-or-foe filter.
- `tools/gen_world.py` — `level` per zone, ledger, `Game` node.

**Tests** `tests/test_party.gd`: element wheel; befriend → party; 4th goes to storage; command attack kills a dummy
enemy without player input; an enemy hit by a companion retargets it; companion at 0 HP is exhausted and stops
attacking; rest revives; XP is shared; party/storage round-trip through save/load.
**Risks:** enemy brain is player-centric — retargeting touches every state; kept behind one `_current_foe()` helper.
Companions blocking the player in corridors → they stay on collision layer 2 (already ignored by the player).

## M2 — Treats, bond, Lustre, Alphas
**Data:** `data/treats.json` (`id → { name, tier: simple|hearty|royal|mythic, flavour, bond }`), creatures gain
`flavour`, `alpha_drop`; `data/alphas.json` (region → species, scale, phase-2 moves, drop).
**Files:** `enemy.gd` bond meter 0–100 replaces `_affection` (pet +8, treat +bond ×2 if favourite, spare +20, fought
beside +5); dialogue lists treats from the inventory; Alphas/bosses accept Mythic only; Lustre roll (1/200, hue
shift via material override, +10 % stats) decided at spawn from a seeded hash so it survives save/load; Alpha
flag: scale, crown tag, phase 2 below 50 % HP. Until M4 treats are bought/dropped; M4 makes them craftable.
**Tests:** bond maths, favourite ×2, hostile needs weakening, Alpha refuses non-Mythic, Lustre determinism, save.
**Risks:** balance of the treat chain — keep numbers in data and note tuning passes in PROGRESS.

## M3 — Gathering & block mining
**Data:** `data/resources.json` (node types: model, hp, tool, tier, drops, respawn), `data/tools.json` (tier, power),
`data/blocks.json` (block id → texture tile, hardness, tool tier, drop, depth band), `data/mines.json`
(per mine: origin, size, seed, noise params).
**Files:** `scripts/resource_field.gd` (MultiMesh + collider pool, deplete/respawn), `scripts/mine.gd` (GridMap
filled from noise at load; break/place; changed cells kept as a diff in the save), `tools/gen_blocks.py` (MeshLibrary
from Kenney Voxel tiles, or flat-colour fallback), `use_tool` action + touch button, creature `skills` and a
"Work" command.
**Tests:** node depletes/respawns; tool tier gates ore; mine layout is deterministic per seed; break/place diff
round-trips through the save; a Mining companion harvests with no player input.
**Risks:** GridMap performance on web (cap mine size at 48×24×48, one mine loaded at a time); MeshLibrary must be a
generated resource, not hand-made.

## M4 — Inventory & crafting
**Data:** `data/items.json` (absorbs `scripts/items.gd`), `data/recipes.json` (`id → { station, inputs, output }`).
**Files:** `scripts/inventory.gd`, `scripts/inventory_ui.gd` (grid, touch-sized cells), `scripts/station.gd`
(workbench / cooking pot / anvil), crafting panel in `menus.gd`.
**Tests:** stack add/remove, craft consumes inputs, missing input refuses, save round-trip, UI opens headless.
**Risks:** moving items from GDScript consts to JSON touches shops and looks — do it in one commit with tests first.

## M4.5 — The Estate
**Data:** `data/estate.json` (ordered tiers: cost, kit pieces, jobs unlocked). **Files:** `scripts/estate.gd`
(placed pieces toggled by tier, job assignment, output chest; production accrues on a timer and offline up to a cap),
generator places every tier's pieces hidden. **Tests:** upgrade consumes materials and reveals pieces; job output
accrues; save. **Risks:** scope — first 5 tiers only, as the brief says.

## M5 — Cities & Sanctuaries
**Data:** `data/cities/*.json` (plaza, districts, gates, roads, sanctuary spot, kit), `data/quests.json`.
**Files:** `tools/gen_city.py` rewritten as the data-driven city builder used by `gen_world.py`;
`scripts/sanctuary.gd` (heal, checkpoint, respawn non-boss enemies, fast travel, party swap, autosave — absorbs the
interim ledger), `scripts/contract_board.gd`, `scripts/npc_walker.gd`.
**Tests:** rest heals + sets spawn + respawns enemies; fast travel only to discovered Sanctuaries; a hunt contract
completes and pays; generated city has no building overlapping a road (generator self-check).
**Risks:** generator complexity — every city is validated by the overlap check at generation time.

## M6 — Souls-like depth
**Files:** `player.gd` stamina, sprint, heavy attack (hold), parry / perfect-dodge window with slow-mo counter;
`enemy.gd` poise + stagger, boss phases; coins dropped at a bloodstain on death (`scripts/bloodstain.gd`); revive
item for companions. **Tests:** stamina gates actions; parry window frames; poise break staggers; bloodstain
recover / lose-on-second-death; all through save. **Risks:** feel can't be unit-tested — a tuning pass with
recorded numbers per change goes in PROGRESS.

## M7 — Massive world
**Decision gate first:** Terrain3D on Compatibility + Web. If the web build fails, Terrain3D stays desktop-only
behind `Game.use_terrain3d`, and the web slice keeps the flat generated region.
**Files:** `tools/gen_region.py` (heightmap from stylised noise — and public SRTM shape for Bakulia — cells of 128 m
exported as `scenes/cells/x_z.tscn`), `scripts/world_streamer.gd` (threaded load/unload ring around the player),
MultiMesh foliage per cell, HLOD impostor meshes for cities, river planes + shader, `scripts/day_night.gd`, world map.
**Tests:** streamer loads/unloads the right cells along a scripted path; no cell above a node budget; frame-time
smoke test. **Risks:** the largest of the project — web memory (≤ 120 MB download), threaded loading on web
(single-threaded build → time-sliced fallback), Terrain3D web export being experimental.

## M8 — Polish & release
Main menu, settings, tutorial, credits (generated from the licence files), intro flyover across regions, Web slice +
Windows exports, itch.io page text. **Tests:** menu → new game → save → continue flow; settings persist.

## Order of risk (what could sink the plan)
1. M7 streaming + Terrain3D on web → prototype the web export of an empty Terrain3D scene *before* M7 work starts.
2. Web export unverified until the templates are installed.
3. Scope: M0–M8 is months of work for a team. Each milestone ships the smallest version that plays well; deferred
   pieces are listed per milestone in PROGRESS under "Deferred".
