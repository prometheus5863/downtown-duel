"""Makes head-only versions of the Universal Base Characters so outfits (cut for the 'Regular' body)
   can be worn without the Superhero body poking through.
   Keeps body triangles whose vertices are mostly skinned to the neck/head bones; eyes + eyebrows stay.
   Writes <name>_Head.gltf + <name>_Head.bin next to the source.   Run: python tools/cut_head.py ."""
import json, os, struct, sys
P = sys.argv[1] if len(sys.argv) > 1 else "."
D = os.path.join(P, "assets/characters")
CT = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
KEEP = 0.5          # min weight on head bones for a vertex to count as "head"


def read(d, buf, ai):
    a = d["accessors"][ai]; bv = d["bufferViews"][a["bufferView"]]
    fmt, size = CT[a["componentType"]]; n = NC[a["type"]]
    stride = bv.get("byteStride", size * n); off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    return [struct.unpack_from("<" + fmt * n, buf, off + i * stride) for i in range(a["count"])]


for src in ("Superhero_Male_FullBody", "Superhero_Female_FullBody"):
    d = json.load(open(os.path.join(D, src + ".gltf")))
    buf = open(os.path.join(D, d["buffers"][0]["uri"]), "rb").read()
    joints = d["skins"][0]["joints"]
    # head set = neck_01 + Head + every descendant of Head
    names = {j: d["nodes"][j]["name"] for j in joints}
    head = {i for i, j in enumerate(joints) if names[j] in ("neck_01", "Head")}
    stack = [j for j in joints if names[j] == "Head"]
    while stack:
        n = stack.pop()
        for c in d["nodes"][n].get("children", []):
            if c in joints:
                head.add(joints.index(c)); stack.append(c)
    extra = bytearray()
    body_mesh = max(range(len(d["meshes"])), key=lambda m: d["accessors"][d["meshes"][m]["primitives"][0]["attributes"]["POSITION"]]["count"])
    for pr in d["meshes"][body_mesh]["primitives"]:
        J = read(d, buf, pr["attributes"]["JOINTS_0"]); W = read(d, buf, pr["attributes"]["WEIGHTS_0"])
        if d["accessors"][pr["attributes"]["WEIGHTS_0"]]["componentType"] != 5126:
            W = [tuple(x / 255.0 for x in w) for w in W]
        is_head = [sum(w for j, w in zip(js, ws) if j in head) >= KEEP for js, ws in zip(J, W)]
        idx = [i[0] for i in read(d, buf, pr["indices"])]
        tris = [idx[k:k + 3] for k in range(0, len(idx), 3) if all(is_head[v] for v in idx[k:k + 3])]
        flat = [v for t in tris for v in t]
        while len(extra) % 4: extra.append(0)
        off = len(extra); extra += struct.pack("<%dI" % len(flat), *flat)
        d["bufferViews"].append({"buffer": 1, "byteOffset": off, "byteLength": len(flat) * 4, "target": 34963})
        d["accessors"].append({"bufferView": len(d["bufferViews"]) - 1, "componentType": 5125, "count": len(flat), "type": "SCALAR"})
        pr["indices"] = len(d["accessors"]) - 1
        print(f"{src}: kept {len(tris)} / {len(idx)//3} body triangles")
    out = src.replace("_FullBody", "_Head")
    d["buffers"].append({"uri": out + ".bin", "byteLength": len(extra)})
    open(os.path.join(D, out + ".bin"), "wb").write(extra)
    json.dump(d, open(os.path.join(D, out + ".gltf"), "w"))
