# Putting Downtown Duel on itch.io

## Build the zip
```
godot --headless --path . --export-release "Web" export/web/index.html
python tools/make_itch_zip.py .
```
`tools/make_itch_zip.py` zips `export/web/` with `index.html` at the top level (what itch needs) into
`export/downtown-duel-web.zip`. Check the pack first (see CLAUDE.md → Testing → Web check).

Cover image, screenshots, tagline, tags and a longer description: `docs/itch/PAGE.md` (+ the images next to it).

## Upload settings (itch.io → Create new project)
| Field | Value |
|---|---|
| Kind of project | **HTML** |
| Uploads | the zip, tick **"This file will be played in the browser"** |
| Viewport dimensions | **1280 × 720** |
| Frame options | tick **Mobile friendly** (orientation: **Landscape**), **Automatically start on page load** off, **Fullscreen button** on |
| SharedArrayBuffer support | **off** (the build is single-threaded, it doesn't need it) |
| Visibility | **Restricted** (only people with the link / a password) is the easy way to share with friends first |

Restricted pages: Edit game → Visibility & access → Restricted → share the "secret URL", or set a password.

## Page text (paste and edit)
**Downtown Duel** — an open-world creature adventure in your browser.

Explore ten connected zones, from a city downtown and an overgrown ruin to a sci-fi bazaar and a mining quarry.
Befriend any creature with pets and treats (every one has a favourite flavour) and fight beside a party of three
companions with their own element moves. Take on crowned Alpha bosses, dig for ore in a hill of blocks, gear up
with armor you can see on your hero, and level up as you go. Progress saves in your browser.

**Controls (keyboard + mouse):** WASD move · mouse look (click to capture) · J / left click strike ·
K / right click ember · Space dodge · Tab lock on · F talk / shop · R use tool · T place block ·
1–5 party orders · C character menu · H all controls · F5 save.
**Phone / tablet (landscape):** left thumb moves, drag on the right to look, on-screen buttons for everything else, ? for the full list.

Made with Godot 4.7. Art: Quaternius (CC0) and Kenney (CC0).

## Known limits
- First load downloads ~86 MB (cached afterwards).
- Saves live in the browser (IndexedDB): another browser or a private window starts fresh.
