# Progress log

Newest first. Each milestone: what's done, how it was verified, decisions, deferred work, known issues.
Plan: `docs/PLAN.md`. Spec: `docs/FABLE_BRIEF.md`.

## Status
| Milestone | State |
|---|---|
| M0 Save / load | **done** |
| M1 Party & companion combat | **done** |
| M2 Treats, bond, Lustre, Alphas | **done** |
| M3 Gathering & block mining | **done** |
| Presentation pass (between M3 and M4) | **done** |
| M4 Inventory & crafting | next |
| M4.5 – M8 | not started |

## Standing issues
- **Web build is 86 MB zipped** (149 MB `index.pck` + 39 MB wasm unzipped) after M2. Budget is 120 MB download.
  The character/outfit and district assets added most of it; M3+ assets must be budgeted (see PLAN risks).
- Asset packs added so far: Kenney Voxel Pack (CC0, block tiles; `assets/voxel/`). The rest of the brief's list is
  fetched when the milestone that needs it starts.

## Web export checks
| Date | Build | Result |
|---|---|---|
| 2026-11-17 | M3 | Export OK, pack 149 MB (zip about 86 MB). `tools/check_pack.gd` run against the exported pack: world loads, 65 creatures, 8 resource fields, mine generated, player model present (**PACK OK**). In Chromium the loading screen clears and the main loop runs with no game errors (only "zero-size framebuffer" WebGL warnings because the browser pane was hidden, so frames weren't visible). A "0.2 MB pack" seen once was a measuring mistake (the export command was piped through `head`, which returned before Godot finished writing). |
| 2026-11-17 | M0 + M1 + M2 (`eeb024a`) | Export OK with no errors (Godot 4.7.2 templates installed from the official release). In Chromium (browser pane, served from `export/web` on localhost) the engine boots: WebGL 2 / Compatibility, single-threaded, no console errors. The exported `index.pck` also runs 600 frames headless in desktop Godot with zero errors, so every scene, script and `data/*.json` is in the pack. **Not seen:** in-browser gameplay frames (the pane was hidden, so the page didn't render). |

---

## Presentation pass (2026-11-27)
Asked for by the owner: make conversations, shops, level-ups and the character screen feel polished.
**Done**
- **Talk camera** (`scripts/talk_cam.gd`): opening a conversation, shop or the Ledger glides the camera to an
  over-the-shoulder shot of the speaker, framed left of centre so the menu doesn't cover them; the HUD (stats line,
  minimap, party cards, zone banner) and the speaker's floating name tag hide meanwhile. Closing glides back.
- **Petting / treats:** the camera pushes in on the creature, which turns to you, plays its happy animation,
  squashes and bounces and floats hearts (more for bigger bond gains); a favourite treat adds a gold sparkle
  burst; a creature joining gets the biggest version.
- **Menu redesign** (`scripts/menus.gd` + shared `scripts/ui_style.gd`): right-side glass panel with an accent
  colour per context (element colour for creatures, gold for shops, teal for the Ledger), header with icon tile,
  name and chips (element, level, Alpha, Lustre, calm / hostile), a bond bar instead of text hearts, typewriter
  text, styled buttons with key chips. Dialogue and Ledger panels hug their content; shops use the full height.
- **Shops:** a detail card for the selected item: a turning 3D preview of you wearing an armor
  (`scripts/preview_3d.gd`), the tool icon or treat glyph, description, what changes if you equip it (green ▲ /
  red ▼), price and Buy / Equip, plus "you need N more coins". Hover or 1-9 selects, Enter / Space / clicking the
  selected row again buys.
- **Level-up:** a gold ring and rising sparkles on the hero, a light flash and a short camera punch-in, and a
  "LEVEL UP" card that pops in with the XP gained and what went up.
- **Character menu** (C, or the ME button on phones; pauses the game): the hero on a turntable you can drag,
  level / XP / route / coins, and tabs: Gear (stat cards + every owned item per slot, click to equip, the preview
  updates), Party (companion cards with their own 3D model, HP and XP bars, moves, work skills, favourite flavour),
  Bag (inventory grid with tool / ore icons from the Kenney Voxel Pack, counts).

**Verified:** `tests/test_polish.gd`: 23 checks (camera takes over and looks at the speaker, petting floats
hearts and pushes the camera in, camera hands back on close, shop detail card + armor preview + defense delta +
buy from the card, level-up card and light, character menu pause / tabs / equip / bag tiles). All earlier tests
still pass. Screenshots of every screen checked in a real 1280×720 window.

**Fixed along the way:** creatures in a conversation never turned to face you (the player has no control while
talking, so their "who am I fighting" check returned nobody); they now always face you.

**Web check:** export OK, pack 149.5 MB; `tools/check_pack.gd` on the exported pack: **PACK OK** (65 creatures,
8 resource fields).

**Known issues / next**
- The menu font is still Godot's default; a CC0 display font would lift it further.
- Touch: the character menu closes with its on-screen Close button (touch buttons are paused with the game).

---

## M3 — Gathering & block mining (2026-11-17)
**Done**
- **Pebble Hill Quarry** (new zone between Oakvale and the Old Quarter, road from the west spoke): a 24×11×24 hill
  of 1 m blocks in a `GridMap` (`scripts/mine.gd`), generated from noise per seed: dirt on top, stone below,
  ores by depth under the surface (copper ≥ 2, iron ≥ 4, silver ≥ 5, gold ≥ 6, crystal ≥ 7), noise caves and a
  3×3 entrance tunnel. Break blocks (**R**, hold to keep mining, hits = hardness, better picks hit harder) and
  place stone / dirt back (**T**). Only the changes are saved (`world.mines`).
- **Resource nodes** (`scripts/resource_field.gd`, `data/resources.json`): trees, rocks, copper / iron veins,
  berry bushes, herbs, mushrooms. One MultiMesh per model part, a collider per node, deplete after a few hits,
  respawn on a timer. Fields around the quarry, east of Oakvale, between Downtown and the Grove, in the Grove and
  the Ivy Ruins.
- **Tools** (`data/tools.json`): wood → stone → copper → iron → crystal pickaxes and wood / stone / iron axes. A new
  game starts with wooden ones; shops sell the rest (Oakvale: stone, Old Quarter armorer: copper / iron, Neon
  Bazaar: up to crystal) until crafting (M4). Tool tier gates ores and veins.
- **Companion Work order (5 / WRK):** creatures with a matching skill (`skills` in creatures.json: mining,
  lumber, gathering, by element) harvest nodes near you, still defending you, and drops go to your inventory.
- HUD: crosshair + "[R] Mine Stone · [T] place block (n)" when aiming at a mine block, "[R] Chop Tree" etc. near
  nodes. Touch: TOOL / PLACE buttons appear when there's something to use them on, WRK in the party row.
- Block textures: Kenney Voxel Pack (CC0), triplanar so each face shows one tile.

**Verified:** `tests/test_gather.gd`: 39 checks (assets exist, layout deterministic, ores only at their depth,
entrance open, tier gating, hardness, player tool ray breaks the aimed block, place rules, node deplete / respawn /
tool kind and tier, gathering by hand, tool shop, a working companion harvests rock, mine diff + tools survive
save / load). All 152 checks pass. Screenshots: the quarry from the road, the tunnel with the aim prompt.

**Decisions**
- The mine is a **hill above ground**, not a pit: the world floor is one flat collider, so digging *into* a hill
  gives the same depth-based ores without cutting holes in it. Depth = blocks under the hill's surface.
- The block MeshLibrary is built at runtime from `data/blocks.json` + textures listed on the Mine node (keeps them
  export dependencies), instead of a generated `.tres`.
- Resource node depletion isn't saved (they respawn in a minute or two anyway); mine edits are.
- Tools are sold for now; M4 makes them craftable from ores and wood.

**Deferred**
- Only one mine so far; more mines / quarries come with the region pass (M7). Placed blocks are limited to the
  mine's bounds.
- Creatures don't mine blocks in the GridMap, only overworld nodes.

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
