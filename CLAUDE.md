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
- Web export preset "Web": scenes filter + `include_filter="scripts/*.gd"` (preloaded scripts aren't detected as deps).
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

## Next up
1. Save/load (FileAccess user:// → IndexedDB on web).
2. Followers assist in combat; simple quests from villagers.
3. Separate: Merkur-targeted slot prototype + RTP simulation (casino studio lead).

## Testing
Headless: `godot --headless --path . -s res://some_test.gd` (SceneTree script). Touch input needs a real window
(e.g. xvfb) — a 0×0 headless window scales event positions to garbage.
