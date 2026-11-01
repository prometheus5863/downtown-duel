"""Lists every asset file the game actually uses (scenes -> models -> .bin/textures -> .import),
   plus pack licenses. Used to keep the git repo small.  Run: python tools/used_assets.py ."""
import json, os, re, struct, sys
P = sys.argv[1] if len(sys.argv) > 1 else "."
used = set()
for scn in ("scenes/arena.tscn", "scenes/player.tscn"):
    for m in re.finditer(r'path="res://(assets/[^"]+)"', open(os.path.join(P, scn)).read()):
        used.add(m.group(1))
for rel in list(used):
    d = os.path.dirname(rel)
    if rel.endswith(".gltf"):
        g = json.load(open(os.path.join(P, rel)))
        for key in ("buffers", "images"):
            for b in g.get(key, []):
                if b.get("uri") and not b["uri"].startswith("data:"):
                    used.add(f"{d}/{b['uri']}")
for rel in list(used):
    if os.path.exists(os.path.join(P, rel + ".import")):
        used.add(rel + ".import")
for root, _, files in os.walk(os.path.join(P, "assets")):
    for f in files:
        if f.lower().startswith("license") and f.endswith(".txt") and ".gdignore" not in files:
            used.add(os.path.relpath(os.path.join(root, f), P).replace(os.sep, "/"))
missing = [u for u in used if not os.path.exists(os.path.join(P, u))]
for u in sorted(used): print(u)
print(f"# {len(used)} files, {sum(os.path.getsize(os.path.join(P,u)) for u in used if u not in missing)//2**20} MB, missing={missing}", file=sys.stderr)
