# Downtown Duel

A small open-world creature-battle demo in Godot 4.7 (Compatibility renderer → runs in the browser).
Five connected zones, 42 animated monsters with simple AI, real-time lock-on combat.

## Controls
**Desktop**
| Input | Action |
|---|---|
| Click | Grab mouse for mouse-look (Esc releases) |
| Mouse | Look around (yaw + pitch) |
| W A S D | Move (relative to camera) |
| LMB / J | Strike — melee, 10 dmg, 0.4 s cooldown (jab/cross combo) |
| RMB / K | Ember — projectile, 15 dmg, 1.0 s cooldown |
| Tab | Lock on to nearest monster (25 m) / release |
| Wheel | Zoom · Q / E turn camera |

**Phone / tablet** (landscape): left thumb = floating joystick, drag anywhere else = camera,
on-screen STRIKE / EMBER / LOCK buttons (true multi-touch). Shadows off + 75 % render scale on touch devices.

## World
| Zone | Where | What's there |
|---|---|---|
| Downtown | centre | City hub, 8 street monsters |
| Training Grounds | north | Fenced yard, 10 training dummies, sparring Orc & Ninja |
| Oakvale Village | west | Modular medieval houses, market, village critters |
| Wild Grove | east | Forest, 10 wild monsters, **Mushroom King boss** (600 HP) |
| Research Lab | south | Sci-fi lab, alien specimens, escaped monsters |

## Tech
- `tools/gen_world.py` — **procedural scene generator**. Builds `scenes/arena.tscn` from the asset packs:
  houses assembled from wall/roof modules, forest scattering, lab from floor/wall tiles,
  colliders computed from glTF mesh bounds. Edit the zone sections and re-run.
- `scripts/enemy.gd` — monster brain (idle → wander → notice player), hit/death animations
  resolved by clip name so any Quaternius monster works without per-model setup, respawn.
- `scripts/player.gd` — camera-relative movement, nearest-target lock-on, melee + projectile,
  hit-stop, screen shake, animated character (Universal Animation Library).
- `scripts/touch_controls.gd` — virtual joystick, camera drag, TouchScreenButtons, portrait warning, mobile graphics preset.
- `scripts/hud.gd` — target HP bar, cooldowns, zone banners. `scripts/intro_camera.gd` — Catmull-Rom flyover.
- Textures capped at 1024 px for the web build (≈62 MB game data).

## Roadmap
- [x] Movement, lock-on, two attacks, hit feedback
- [x] Multi-zone world, animated monsters with wander AI, animated player, boss
- [ ] Dodge roll (Space) with i-frames
- [ ] Monsters fight back (approach → wind-up → lunge), boss ground-slam
- [ ] Capture / party system, 2D overworld ↔ 3D battle transition

## Credits
All art CC0 by Quaternius: Downtown City, Medieval Village, Modular Sci-Fi, Stylized Nature,
Fantasy Props MegaKits, Ultimate Monsters, Universal Animation Library.
