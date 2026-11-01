"""Greyscale copy of the Ranger outfit texture; avatar.gd tints it into steel / gold / obsidian plate.
   Needs Pillow.   Run: python tools/make_armor_tex.py ."""
import os, sys
from PIL import Image, ImageEnhance, ImageOps
D = os.path.join(sys.argv[1] if len(sys.argv) > 1 else ".", "assets/outfits")
im = Image.open(os.path.join(D, "T_Ranger_BaseColor.png")).convert("RGB")
g = ImageOps.grayscale(im)
g = ImageEnhance.Contrast(g).enhance(1.25)
g = ImageEnhance.Brightness(g).enhance(1.5)
g.convert("RGB").save(os.path.join(D, "T_Ranger_Plate_BaseColor.png"))
print("ok")
