# Downtown Duel

A small open-world creature-battle demo in Godot 4.7 (Compatibility renderer → runs in the browser).
Nine connected zones on a looping road network, 61 animated monsters with simple AI, real-time lock-on combat,
a dressed-up hero whose armor changes how they look.

## Controls
**Desktop**
| Input | Action |
|---|---|
| Click | Grab mouse for mouse-look (Esc releases) |
| Mouse | Look around (yaw + pitch) |
| W A S D | Move (relative to camera) |
| Space | Dodge roll (i-frames 0.04–0.42 s, 0.7 s cooldown) |
| LMB / J | Strike — melee, 10 dmg, 0.4 s cooldown (jab/cross combo) |
| RMB / K | Ember — projectile, 15 dmg, 1.0 s cooldown |
| Tab | Lock on to nearest monster (25 m) / release |
| F | Talk to a monster / shop / open a chest (1–9 pick options, Esc leave) |
| Wheel | Zoom · Q / E turn camera |

**Phone / tablet** (landscape): left thumb = floating joystick, drag anywhere else = camera,
on-screen STRIKE / EMBER / DODGE / LOCK buttons, TALK appears near monsters/NPCs (true multi-touch). Shadows off + 75 % render scale on touch devices.

## World
| Zone | Where | What's there |
|---|---|---|
| Downtown | centre | City hub, 8 street monsters |
| Training Grounds | north | Fenced yard, 10 training dummies, sparring Orc & Ninja |
| Oakvale Village | west | Modular medieval houses, market, village critters |
| Wild Grove | east | Forest, 10 wild monsters, **Mushroom King boss** (600 HP) |
| Research Lab | south | Sci-fi lab, alien specimens, escaped monsters |
| Ivy Ruins | north-west | City blocks swallowed by forest: ivy-covered brick walls, dead trees, 5 hostile monsters |
| Neon Bazaar | north-east | Sci-fi market plaza between city towers, **Gadgeteer Vex** (weapons + charms), peaceful critters |
| Old Quarter | south-west | Medieval houses on modern asphalt streets, **Armorer Brenna** (all armor) |
| Skyport | south-east | Landing pads in the wilds, **Sky Wyrm boss** (520 HP) |

The map is **non-linear**: spokes from Downtown, a ring road that runs through every zone (Training, Lab and the
Grove got extra gates for it) and diagonal alleys from Downtown's corners to each district — every zone has 2–4 ways in.
A corner **minimap** shows roads, zones (names appear once visited), monsters and you. **7 treasure chests** hide around
the map (coins, XP and gear; gear is equipped if it beats what you wear).

## RPG systems
- **Levels & XP** — from defeating *or* sparing monsters; each level +12 max HP, +2 Strike/Ember.
- **Coins** — dropped only when you defeat monsters (sparing pays XP, not money — routes have a cost).
- **Gear** — weapon (+Strike), armor (flat damage reduction), charm (Ember / speed / dodge / regen).
  **8 armors that change your look**: Cloth Tunic → Traveler's Garb → Leather Vest → Ranger Kit (hood) → Shadow Cloak →
  Iron / Obsidian / Royal Plate. Three shops: Oakvale (starter gear ≤ 160 coins), Neon Bazaar (weapons + charms), Old Quarter (armor).
- **Talking to monsters (F)** — peaceful monsters: pet / snack → they ask to join and **follow you** (max 3).
  Hostile monsters: *Fight*, *Calm it down* (works below 50 % HP, or after a snack; boss below 30 %), *Snack (10 coins)*.
  Failing to calm one makes it attack immediately.
- **Route** — HUD tracks defeated / spared / friends → **Pacifist**, **Balanced** or **Hunter**.

## Tech
- `tools/gen_world.py` — **procedural scene generator**. Builds `scenes/arena.tscn` from the asset packs:
  houses assembled from wall/roof modules, forest scattering, lab from floor/wall tiles,
  colliders computed from glTF mesh bounds. Edit the zone sections and re-run.
- `scripts/enemy.gd` — monster brain: idle → wander → chase → telegraphed wind-up ("!") → lunge → recover (punish window);
  passive monsters fight back only when provoked; leash + heal on return; max 2 simultaneous attackers (attack tokens);
  boss ground-slam with AoE ring. Hit/death animations
  resolved by clip name so any Quaternius monster works without per-model setup, respawn.
- `scripts/player.gd` — camera-relative movement, nearest-target lock-on, melee + projectile,
  hit-stop, screen shake. The hero is a Universal Base Character head + hair wearing Modular Character Outfits
  pieces, all skinned onto the Universal Animation Library rig (`scripts/avatar.gd`); armor `look`s in items.gd pick the parts,
  texture variant, tint and metalness. `tools/cut_head.py` cuts the head out of the base body so outfits don't clip.
- `scripts/items.gd` — item database (add gear here). `scripts/menus.gd` — dialogue + shop panel. `scripts/npc.gd` — dressed shopkeepers
  (per-shop stock / price cap). `scripts/chest.gd` — treasure chests. `scripts/minimap.gd` — corner map.
- `scripts/touch_controls.gd` — virtual joystick, camera drag, TouchScreenButtons, portrait warning, mobile graphics preset.
- `scripts/hud.gd` — target HP bar, cooldowns, zone banners. `scripts/intro_camera.gd` — Catmull-Rom flyover.
- Textures capped at 1024 px for the web build (≈62 MB game data).

## Roadmap
- [x] Movement, lock-on, two attacks, hit feedback
- [x] Multi-zone world, animated monsters with wander AI, animated player, boss
- [x] Dodge roll with i-frames, player HP / regen / death & respawn
- [x] Monsters fight back (chase → wind-up → lunge), attack tokens, leash, boss ground-slam
- [x] XP & levels, gear, coins & shop
- [x] Talk-to-monster dialogue with pacifist routes (spare / befriend / followers)
- [x] Dressed hero + visible armor tiers, hybrid districts, non-linear road network, minimap, chests
- [ ] Save game (browser storage), quests, followers that fight alongside you
- [ ] Capture / party system, 2D overworld ↔ 3D battle transition

## Credits
All art CC0 by Quaternius: Downtown City, Medieval Village, Modular Sci-Fi, Stylized Nature,
Fantasy Props MegaKits, Ultimate Monsters, Universal Animation Library, Universal Base Characters,
Modular Character Outfits – Fantasy.
