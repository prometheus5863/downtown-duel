"""Downscales PNGs in the given asset folders to <= 1024 px. The project caps texture imports at 1024
   (process/size_limit) anyway, so the game looks the same and the repo stays small.
   Needs Pillow.   Run: python tools/shrink_textures.py . assets/characters assets/outfits"""
import os, sys
from PIL import Image
P, dirs = sys.argv[1], sys.argv[2:]
MAX = 1024
for d in dirs:
    for f in sorted(os.listdir(os.path.join(P, d))):
        if not f.lower().endswith(".png"):
            continue
        p = os.path.join(P, d, f)
        im = Image.open(p)
        if max(im.size) <= MAX:
            continue
        before = os.path.getsize(p)
        im.thumbnail((MAX, MAX), Image.LANCZOS)
        im.save(p, optimize=True)
        print(f"{d}/{f}: {before // 1024} KB -> {os.path.getsize(p) // 1024} KB")
