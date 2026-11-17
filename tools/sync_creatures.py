"""Keeps data/creatures.json in step with the models in assets/monsters.
   - adds an entry for every glTF that has none (element / stats from SEED below, or neutral defaults)
   - refreshes the measured `height` (model bounds x scale) and `model` path
   - never overwrites hand-tuned fields of existing entries
   Run: python tools/sync_creatures.py ."""
import json, os, sys
P = sys.argv[1] if len(sys.argv) > 1 else "."
OUT = os.path.join(P, "data", "creatures.json")
MON = "assets/monsters"

# species: (species name, element, hp, atk, speed, scale)
SEED = {
    "Blob/Alien": ("Starblob", "shade", 100, 10, 2.2, 0.6), "Blob/Birb": ("Sparrowbit", "gale", 55, 7, 2.6, 0.5),
    "Blob/Cactoro": ("Cactoro", "verdant", 90, 9, 1.8, 0.55), "Blob/Cat": ("Whiskit", "shade", 65, 9, 2.6, 0.5),
    "Blob/Chicken": ("Cluckle", "gale", 45, 6, 2.4, 0.45), "Blob/Dog": ("Barkley", "stone", 75, 9, 2.6, 0.55),
    "Blob/Fish": ("Puddlefin", "tide", 60, 8, 2.2, 0.5), "Blob/GreenBlob": ("Gloop", "verdant", 80, 8, 2.0, 0.6),
    "Blob/GreenSpikyBlob": ("Spikeball", "verdant", 110, 11, 1.9, 0.6), "Blob/Mushnub": ("Mushnub", "verdant", 90, 8, 1.8, 0.5),
    "Blob/Mushnub_Evolved": ("Elder Mushnub", "verdant", 150, 12, 1.8, 0.55), "Blob/Ninja": ("Shadekin", "shade", 90, 12, 2.8, 0.6),
    "Blob/Orc": ("Grumblor", "stone", 140, 13, 2.0, 0.6), "Blob/Pigeon": ("Coo", "gale", 50, 6, 2.6, 0.6),
    "Blob/PinkBlob": ("Pinkle", "tide", 60, 7, 2.0, 0.6), "Blob/Wizard": ("Hexling", "ember", 115, 13, 2.0, 0.6),
    "Blob/Yeti": ("Snowball", "tide", 90, 10, 2.0, 0.55),
    "Big/Alien": ("Voidwalker", "shade", 150, 14, 2.2, 0.6), "Big/Birb": ("Galebeak", "gale", 85, 10, 2.6, 0.55),
    "Big/BlueDemon": ("Tidefiend", "tide", 160, 15, 2.2, 0.6), "Big/Bunny": ("Bunbun", "gale", 80, 9, 2.8, 0.5),
    "Big/Cactoro": ("Thornback", "verdant", 130, 12, 1.8, 0.6), "Big/Demon": ("Cinderhorn", "ember", 200, 17, 2.2, 0.65),
    "Big/Dino": ("Rockjaw", "stone", 170, 15, 2.2, 0.65), "Big/Fish": ("Rotorfin", "tide", 120, 12, 2.3, 0.6),
    "Big/Frog": ("Hopper", "tide", 110, 11, 2.4, 0.6), "Big/Monkroose": ("Monkroose", "stone", 130, 13, 2.6, 0.6),
    "Big/MushroomKing": ("Mushroom King", "verdant", 600, 22, 1.2, 1.0), "Big/Ninja": ("Nightblade", "shade", 220, 17, 2.8, 0.6),
    "Big/Orc": ("Boulderfist", "stone", 250, 18, 2.0, 0.6), "Big/Orc_Skull": ("Skullcrusher", "shade", 190, 16, 2.0, 0.62),
    "Big/Tribal": ("Embermask", "ember", 170, 15, 2.2, 0.65), "Big/Yeti": ("Frostmaw", "tide", 180, 15, 2.0, 0.65),
    "Flying/Alpaking": ("Alpaking", "gale", 90, 9, 2.2, 0.55), "Flying/Alpaking_Evolved": ("Alpaca Tycoon", "gale", 160, 14, 2.2, 0.6),
    "Flying/Armabee": ("Buzzbee", "stone", 90, 10, 2.6, 0.55), "Flying/Armabee_Evolved": ("Queen Armabee", "stone", 150, 14, 2.6, 0.6),
    "Flying/Demon": ("Imp", "ember", 110, 12, 2.6, 0.55), "Flying/Dragon": ("Emberwing", "ember", 140, 14, 2.4, 0.6),
    "Flying/Dragon_Evolved": ("Sky Wyrm", "ember", 520, 22, 1.6, 1.1), "Flying/Ghost": ("Wisp", "shade", 80, 10, 2.4, 0.55),
    "Flying/Ghost_Skull": ("Bone Wisp", "shade", 110, 12, 2.4, 0.55), "Flying/Glub": ("Glub", "tide", 90, 9, 2.2, 0.55),
    "Flying/Glub_Evolved": ("Glubzilla", "tide", 170, 15, 2.2, 0.65), "Flying/Goleling": ("Pebbling", "stone", 120, 11, 2.0, 0.6),
    "Flying/Goleling_Evolved": ("Scrap Golem", "stone", 200, 16, 2.0, 0.65), "Flying/Hywirl": ("Hywirl", "gale", 100, 11, 2.8, 0.55),
    "Flying/Pigeon": ("Skycoo", "gale", 70, 8, 2.8, 0.55), "Flying/Squidle": ("Squidle", "tide", 90, 10, 2.2, 0.55),
    "Flying/Tribal": ("Mask Imp", "ember", 100, 11, 2.6, 0.55),
}
MOVES = {"ember": ["cinder_bite", "fire_spit"], "tide": ["splash_tackle", "bubble_shot"], "verdant": ["vine_lash", "spore_burst"],
         "stone": ["rock_bash", "quake_stomp"], "gale": ["gust_dive", "wind_cutter"], "shade": ["shadow_claw", "night_pulse"]}


SKILLS = {"stone": ["mining"], "verdant": ["lumber", "gathering"], "gale": ["gathering"], "ember": ["mining"],
          "tide": ["gathering"], "shade": ["lumber"]}
FLAVOUR = {"ember": "spicy", "tide": "savory", "verdant": "bitter", "stone": "savory", "gale": "sweet", "shade": "sour"}


def model_height(path):
    d = json.load(open(path))
    sc = {nd["mesh"]: nd.get("scale", [1, 1, 1]) for nd in d.get("nodes", []) if "mesh" in nd}
    top = 0.0
    for mi, m in enumerate(d.get("meshes", [])):
        for pr in m["primitives"]:
            top = max(top, d["accessors"][pr["attributes"]["POSITION"]]["max"][1] * sc.get(mi, [1, 1, 1])[1])
    return max(top, 1.0)


data = json.load(open(OUT)) if os.path.exists(OUT) else {}
added = 0
for group in ("Blob", "Big", "Flying"):
    folder = os.path.join(P, MON, group, "glTF")
    for f in sorted(os.listdir(folder)):
        if not f.endswith(".gltf"):
            continue
        sp = f"{group}/{f[:-5]}"
        name, element, hp, atk, speed, scale = SEED.get(sp, (f[:-5], "stone", 100, 10, 2.2, 0.6))
        e = data.get(sp)
        if e is None:
            e = data[sp] = {"name": name, "element": element, "hp": hp, "atk": atk, "speed": speed, "scale": scale,
                            "radius": round(0.5 * scale / 0.6, 2), "moves": MOVES[element],
                            "flavour": FLAVOUR[element], "skills": SKILLS[element]}
            added += 1
        e["model"] = f"{MON}/{group}/glTF/{f}"
        e["height"] = round(model_height(os.path.join(folder, f)) * e["scale"], 2)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
json.dump(data, open(OUT, "w", newline="\n"), indent=1)
print(f"ok: {len(data)} species ({added} added)")
