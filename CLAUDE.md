# Downtown Duel — project notes for Claude Code

Godot **4.7.2**, GDScript, **Compatibility renderer** (must stay exportable to Web).
Open-world creature-battle demo: 5 zones, 42 monsters, lock-on combat, desktop + touch controls.

## Layout
- `scenes/arena.tscn` — **GENERATED** by `tools/gen_world.py`. Do not hand-edit; change the generator and re-run:
  `python tools/gen_world.py .`
- `scenes/player.tscn` — player (CharacterBody3D, CamPivot → SpringArm3D → Camera3D, MeleeHitbox)
- `scripts/player.gd` — movement, camera (`rotate_camera`, `zoom_camera`), lock-on, attacks, hit-stop, anims
- `scripts/enemy.gd` — monster brain + damage. Origin on the floor; `height`/`radius` size the collider;
  animations found by clip name (IDLE/WALK/HIT/DEATH/REACT lists)
- `scripts/hud.gd` — HP bar, cooldowns, zone banners (ZONES must match gen_world.py), spawns touch controls
- `scripts/touch_controls.gd` — joystick / camera drag / TouchScreenButtons, mobile graphics preset
- `scripts/intro_camera.gd` — Catmull-Rom flyover; `scripts/projectile.gd` — Ember

## Conventions & gotchas
- Godot strips `_Loop` from glTF clip names on import (`Idle_Loop` → `Idle`).
- Quaternius models face +Z; the player moves along -Z (model rotated PI).
- Asset packs (all CC0, Quaternius) live in `assets/`. Only glTF is imported — FBX/OBJ/Blends folders carry `.gdignore`.
- glTFs reference textures by bare filename: textures must sit next to the .gltf (copied from each pack's Textures/).
- Texture imports capped at 1024 px (`process/size_limit`) to keep the web build ~62 MB.
- Web export preset "Web": scenes filter + `include_filter="scripts/*.gd"` (preloaded scripts aren't detected as deps).
- Input actions: move_*, lock_on, attack_strike (J/LMB), attack_ember (K/RMB), cam_left/right (Q/E).
- No `class_name` globals; scripts are preloaded.

## Next up
1. Dodge roll (Space) with i-frames — owner wants to write this himself; review, don't write.
2. Monsters fight back: approach → telegraphed wind-up → lunge; boss ground-slam AoE.
3. Capture/party system; 2D overworld ↔ 3D battle transition.

## Testing
Headless: `godot --headless --path . -s res://some_test.gd` (SceneTree script). Touch input needs a real window
(e.g. xvfb) — a 0×0 headless window scales event positions to garbage.
