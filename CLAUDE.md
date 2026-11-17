# Downtown Duel — project notes for Claude Code

Godot **4.7.2**, GDScript, **Compatibility renderer** (must stay exportable to Web).
Open-world creature-battle demo: 9 zones (ring road + spokes + alleys), 61 monsters, lock-on combat, desktop + touch controls.

## Layout
- `scenes/arena.tscn` — **GENERATED** by `tools/gen_world.py`. Do not hand-edit; change the generator and re-run:
  `python tools/gen_world.py .`
- `scenes/player.tscn` — player (CharacterBody3D, CamPivot → SpringArm3D → Camera3D, MeleeHitbox). `wardrobe` /
  `wardrobe_tex` list every head/hair/outfit glTF and texture that armor looks use (keeps them export deps).
- `scripts/player.gd` — movement, camera (`rotate_camera`, `zoom_camera`), lock-on, attacks, hit-stop, anims
- `scripts/enemy.gd` — monster brain + damage. Origin on the floor; `height`/`radius` size the collider;
  animations found by clip name (IDLE/WALK/HIT/DEATH/REACT lists)
- `scripts/hud.gd` — HP bar, cooldowns, zone banners (ZONES must match gen_world.py), spawns touch controls
- `scripts/touch_controls.gd` — joystick / camera drag / TouchScreenButtons, mobile graphics preset
- `scripts/intro_camera.gd` — Catmull-Rom flyover; `scripts/projectile.gd` — Ember
- `scripts/avatar.gd` — moves skinned parts (head, hair, outfit pieces) onto the UAL rig's Skeleton3D; restyles outfit
  materials (texture swap / tint / metal) and hair colour. Used by player.gd (`refresh_look`) and npc.gd.
- `scripts/chest.gd` (one-time loot, talk_* protocol), `scripts/minimap.gd` (reads the "road" group + HUD ZONES)

## Conventions & gotchas
- Godot strips `_Loop` from glTF clip names on import (`Idle_Loop` → `Idle`).
- Quaternius models face +Z; the player moves along -Z (model rotated PI).
- Asset packs (all CC0, Quaternius) live in `assets/`. Only glTF is imported — FBX/OBJ/Blends folders carry `.gdignore`.
- glTFs reference textures by bare filename: textures must sit next to the .gltf (copied from each pack's Textures/).
- Characters: `assets/characters` (Universal Base Characters, Superhero bodies) + `assets/outfits` (Modular Character
  Outfits – Fantasy, Standard = Peasant + Ranger only, cut for the *Regular* body). All share the UAL 65-bone skeleton.
  Outfits replace the body, so only `*_Head.gltf` (made by `tools/cut_head.py` from `*_FullBody.gltf`) is worn.
  The FullBody .gltf files are git-ignored: re-running cut_head.py needs the pack zip extracted into assets/characters.
  Hair/eyebrow textures are greyscale — avatar.gd tints MI_Hair_* materials. `T_Ranger_Plate_BaseColor.png` is
  generated (`tools/make_armor_tex.py`); `tools/shrink_textures.py` downscales source PNGs to 1024 px.
- Asset whitelist: `.gitignore` lists only used assets — regenerate from `python tools/used_assets.py .` after world changes.
- Texture imports capped at 1024 px (`process/size_limit`) to keep the web build ~62 MB.
- Web export preset "Web": scenes filter + `include_filter="scripts/*.gd, data/*.json"` (preloaded scripts and
  JSON read at runtime aren't detected as deps).
- Input actions: move_*, lock_on, attack_strike (J/LMB), attack_ember (K/RMB), dodge (Space), interact (F), cam_left/right (Q/E).
- HUD `ZONES` must match the zone centres in gen_world.py (incl. the 4 diagonal districts).
- No `class_name` globals; scripts are preloaded.

## Combat model
- Player: `hp`, `take_damage(amount, dir) -> bool` (false when dodged / i-frames), signals hp_changed/hurt/dodged/died.
- Enemy states: idle, walk, chase, windup, lunge, recover, return. `aggressive=false` → only fights once `_provoked`.
  MAX_ATTACKERS = 2 attack tokens (boss exempt). Zone temperament set in gen_world.py `ZONE_HOSTILE`.

## RPG layer
- Player progression lives on player.gd: level/xp/coins/gear/owned/route/followers; `reward(xp, coins, kind)`,
  `buy(id)`, `equip(id)`, `spend(n)`, `add_follower(e)`, stat getters strike_power()/ember_power()/defense().
- Items: scripts/items.gd `DB` (slot weapon/armor/charm; keys atk/def/ember/speed/dodge_cd).
- Dialogue protocol (enemy.gd → menus.gd): talk_begin() / talk_choose(option) / talk_end(result) returning
  {title, text, options, end}. Results: fight | spared | friend | leave. Anything in group "interactable" with
  can_interact(); NPCs implement open_shop().
- Friends: `friend=true`, removed from "enemy" group, collision_layer=2 (projectiles/melee/player ignore them).
- Mouse attacks are handled in code only while the mouse is captured (input map has keys only) so GUI clicks and
  touch→mouse emulation never trigger attacks. `pointing/emulate_mouse_from_touch=true` (needed for menu buttons on phones).
- project.godot input entries are hand-edited sometimes: InputEvent objects contain nested parens (Vector2(...)) — never
  strip them with a naive regex.

## Roadmap
The game is being grown into an open-world creature RPG: spec `docs/FABLE_BRIEF.md`, per-milestone plan
`docs/PLAN.md`, status + decisions `docs/PROGRESS.md` (update it every milestone). M0 (save/load), M1 (party) and M2 (treats/bond/Alphas) are done.
Separate, unrelated: Merkur-targeted slot prototype + RTP simulation (casino studio lead).

## Creatures & party (M1)
- Data: `data/creatures.json` (species id = `"Blob/GreenBlob"`, from the model path), `data/moves.json`,
  `data/elements.json`, loaded via `scripts/data.gd`. New monster models → `python tools/sync_creatures.py .`
- `enemy.gd` is every creature. `take_damage(amount, dir, source, element)` (element wheel applied there).
  `_current_foe()` = companion it's angry at, else the player. Befriended: `adopt(player, record, origin)` →
  `friend`, `brain` = `companion.gd`, `record` = save record; `exhausted` at 0 HP instead of dying.
- Player: `party` (nodes, max 3), `storage` (records), `party_command`, `befriend/deposit/withdraw/rest`.
  `scripts/creature_factory.gd` spawns a companion from a record. `scripts/ledger.gd` + menus.gd = storage UI.
- Projectiles never hit the player or friends (`body.is_in_group("player")` / `friend`).
- Runtime-added input actions: `scripts/input_setup.gd` (cmd_attack/follow/hold/return = 1-4).

## Treats, bond, Alphas (M2)
- `data/treats.json` (tier, flavour, bond, price), `data/alphas.json` (zone → species, name, drop, optional pos/hp;
  the generator places them and asserts all are placed), `data/materials.json`. Species `flavour` in creatures.json.
- enemy.gd: `bond` (0-100, JOIN_BOND 60), `treat_bond(id)`, `is_alpha` / `alpha_drop` / `_phase2`, `lustre`
  (`set_lustre`, hash of scene path % 200). Tinted materials are cleared in NOTIFICATION_PREDELETE (else the
  renderer logs "material is null" at teardown — same trap as avatar.gd).
- Player `inventory` (id → int; JSON loads floats, Game.apply casts back), `add_item/remove_item/item_count`.
- Shops sell treats when their `stock` includes "treat".

## Save / load
- `scripts/save_game.gd` (file I/O, `VERSION`, `migrate()`), `scripts/game.gd` (`Game` node, last in arena.tscn, group
  "game"): `collect()` / `apply()` turn world state into the save dict. World objects are keyed by node path relative
  to the scene root, so generator node names must stay stable.
- Anything new that must persist: add it to `SaveGame.blank()`, `Game.collect()`, `Game.apply()` and `tests/test_save.gd`.

## Testing
`python tools/run_tests.py` runs every `tests/test_*.gd` headless (PASS/FAIL lines; any engine `ERROR:` fails the run).
Tests use `tests/harness.gd` (`world()`, `ok()`, `eq()`) and a redirected save path. Run them before every commit.
Single test: `godot --headless --path . -s res://tests/test_save.gd` (SceneTree script).
Web check per milestone: `godot --headless --path . --export-release "Web" export/web/index.html`, then
(a) run the pack: `godot --headless --main-pack export/web/index.pck --quit-after 600` (must print no errors — catches
files missing from the export), and (b) serve it with the `web-build` config in `.claude/launch.json` (port 8060)
and load it in a browser. Log the result in docs/PROGRESS.md "Web export checks". Touch input needs a real window
(e.g. xvfb) — a 0×0 headless window scales event positions to garbage.
