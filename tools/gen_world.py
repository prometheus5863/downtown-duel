"""Generates scenes/arena.tscn: a multi-zone world.
   Downtown (hub) · Training Grounds (N) · Oakvale Village (W) · Wild Grove (E) · Research Lab (S)
   Run:  python3 tools/gen_world.py <project_dir>
   Edit the zone sections below and re-run instead of hand-placing nodes."""
import sys, json, math, random, struct, os
P = sys.argv[1]
random.seed(7)

A = "assets/"
CITY = A + "city/Exports/glTF (Godot)/"
MED  = A + "medieval-village/Medieval Village MegaKit[Standard]/glTF/"
NAT  = A + "stylized-nature/glTF/"
FP   = A + "fantasy-props/Exports/glTF/"
SCI  = A + "modular-sci-fi/Modular SciFi MegaKit[Standard]/glTF/"
MON  = A + "monsters/"
UAL  = A + "animations/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb"

# ---------------------------------------------------------------- helpers
_bcache = {}
def bounds(rel):
    if rel in _bcache: return _bcache[rel]
    p = os.path.join(P, rel)
    if p.endswith(".glb"):
        b = open(p, "rb").read(); n = struct.unpack("<I", b[12:16])[0]; d = json.loads(b[20:20+n])
    else:
        d = json.load(open(p))
    mn = [1e9]*3; mx = [-1e9]*3; sc = {}
    for nd in d.get("nodes", []):
        if "mesh" in nd: sc[nd["mesh"]] = nd.get("scale", [1, 1, 1])
    for mi, m in enumerate(d.get("meshes", [])):
        s = sc.get(mi, [1, 1, 1])
        for pr in m["primitives"]:
            a = d["accessors"][pr["attributes"]["POSITION"]]
            for i in range(3):
                mn[i] = min(mn[i], a["min"][i]*s[i]); mx[i] = max(mx[i], a["max"][i]*s[i])
    _bcache[rel] = (mn, mx); return mn, mx

ext, subs, nodes = [], [], []
def ext_id(rel, typ="PackedScene"):
    for rid, r, t in ext:
        if r == rel: return rid
    rid = f"e{len(ext)}"; ext.append((rid, rel, typ)); return rid
def sub(sid, body):
    if sid not in [s for s, _ in subs]: subs.append((sid, body))
    return sid
f3 = lambda v: f"Vector3({v[0]:.3f}, {v[1]:.3f}, {v[2]:.3f})"
def rot2(x, z, yaw):   # rotate local xz by yaw (Godot Y rotation)
    return (x*math.cos(yaw) + z*math.sin(yaw), -x*math.sin(yaw) + z*math.cos(yaw))

_names = {}
def uname(base):
    _names[base] = _names.get(base, 0) + 1
    return f"{base}{_names[base]}"

def group(name, parent="."):
    nodes.append(f'[node name="{name}" type="Node3D" parent="{parent}"]\n')
    return name if parent == "." else f"{parent}/{name}"

def place(parent, rel, x, z, yaw=0.0, y=0.0, scale=1.0, collide=None, name=None):
    """collide: None | 'box' (model bounds) | (sx,sy,sz,cx,cy,cz) custom local box"""
    nm = name or uname(os.path.basename(rel).split(".")[0])
    s = f'[node name="{nm}" parent="{parent}" instance=ExtResource("{ext_id(rel)}")]\nposition = {f3((x, y, z))}\n'
    if yaw: s += f"rotation = Vector3(0, {yaw:.5f}, 0)\n"
    if scale != 1.0: s += f"scale = Vector3({scale}, {scale}, {scale})\n"
    nodes.append(s)
    if collide:
        if collide == "box":
            mn, mx = bounds(rel)
            size = [mx[i]-mn[i] for i in range(3)]; c = [(mn[i]+mx[i])/2 for i in range(3)]
        else:
            size, c = collide[:3], collide[3:]
        sid = sub("box_" + "_".join(f"{v:.2f}" for v in size).replace(".", "p").replace("-", "m"),
                  f'[sub_resource type="BoxShape3D" id="ID"]\nsize = {f3(size)}\n')
        nodes.append(f'[node name="Col" type="StaticBody3D" parent="{parent}/{nm}"]\n\n'
                     f'[node name="S" type="CollisionShape3D" parent="{parent}/{nm}/Col"]\nposition = {f3(c)}\nshape = SubResource("{sid}")\n')
    return f"{parent}/{nm}"

def plane(parent, name, x, z, sx, sz, mat, y=0.0):
    mid = sub(f"pm_{sx}_{sz}_{mat}".replace(".", "p"),
              f'[sub_resource type="PlaneMesh" id="ID"]\nmaterial = SubResource("{mat}")\nsize = Vector2({sx}, {sz})\n')
    nodes.append(f'[node name="{name}" type="MeshInstance3D" parent="{parent}"]\nposition = {f3((x, y, z))}\nmesh = SubResource("{mid}")\n')

def sign(parent, text, x, z, y=7.0):
    nodes.append(f'[node name="{uname("Sign")}" type="Label3D" parent="{parent}"]\nposition = {f3((x, y, z))}\n'
                 f'billboard = 1\ntext = "{text}"\nfont_size = 160\noutline_size = 36\nmodulate = Color(1, 0.95, 0.8, 1)\n')

monsters = []
ZONE_HOSTILE = {"Downtown": True, "Village": False, "Training": False, "Grove": True, "Lab": True}
def monster(parent, name, x, z, model=None, scale=1.0, hp=80, height=None, radius=0.5,
            wander=6.0, speed=2.0, boss=False, color=(0.85, 0.2, 0.2), aggressive=None):
    if model and height is None:
        mn, mx = bounds(model); height = max(mx[1], 1.0) * scale
    if aggressive is None:
        aggressive = ZONE_HOSTILE.get(parent.split("/")[-1], True)
    monsters.append((parent, name, x, z, model, scale, hp, height or 2.0, radius, wander, speed, boss, color, aggressive))

def emit_monsters():
    out = ""
    for parent, nm, x, z, model, scale, hp, h, r, w, spd, boss, c, aggr in monsters:
        node = uname(nm.replace(" ", ""))
        out += f'[node name="{node}" type="CharacterBody3D" parent="{parent}"]\nposition = Vector3({x:.2f}, 0.05, {z:.2f})\n'
        out += f'script = ExtResource("{ext_id("scripts/enemy.gd", "Script")}")\ndisplay_name = "{nm}"\nmax_hp = {hp}\n'
        out += f'height = {h:.2f}\nradius = {r:.2f}\nwander_radius = {w}\nmove_speed = {spd}\n'
        if model: out += f'model_scene = ExtResource("{ext_id(model)}")\nmodel_scale = {scale}\n'
        else: out += f'color = Color({c[0]}, {c[1]}, {c[2]}, 1)\n'
        if boss: out += "is_boss = true\nrespawn_time = 8.0\nattack_damage = 22\nwindup_time = 1.1\nattack_cooldown = 2.4\n"
        else: out += f"attack_damage = {round(4 + hp / 25)}\n"
        if not aggr: out += "aggressive = false\n"
        out += f'\n[node name="Mesh" type="MeshInstance3D" parent="{parent}/{node}"]\nmesh = SubResource("capsule_mesh")\n'
        out += f'\n[node name="Collision" type="CollisionShape3D" parent="{parent}/{node}"]\n\n'
    return out

# ---------------------------------------------------------------- materials
def mat(mid, color, tex=None, uv=1):
    body = f'[sub_resource type="StandardMaterial3D" id="ID"]\nalbedo_color = Color({color[0]}, {color[1]}, {color[2]}, 1)\n'
    if tex: body += f'albedo_texture = ExtResource("{ext_id(tex, "Texture2D")}")\nuv1_scale = Vector3({uv}, {uv}, 1)\n'
    sub(mid, body)
mat("m_grass", (0.33, 0.47, 0.24))
mat("m_grove", (0.30, 0.46, 0.22))
mat("m_asphalt", (0.75, 0.75, 0.75), CITY + "T_Concrete_Asphalt_BaseColor.png", 30)
mat("m_road", (0.55, 0.45, 0.33))
mat("m_dirt", (0.62, 0.50, 0.36))
mat("m_cobble", (0.60, 0.57, 0.52))

W = group("World")
plane(W, "Grass", 0, 0, 340, 340, "m_grass", 0.0)

# ================================================================ DOWNTOWN (hub)
D = group("Downtown", W)
plane(D, "Asphalt", 0, 0, 116, 116, "m_asphalt", 0.02)
CELL = 36
btypes = ["Building_Large_2", "Building_Medium_2_001", "Building_Small_1", "Building_Medium_2_001",
          "Building_Large_2", "Building_Small_1", "Building_Small_1", "Building_Large_2"]
k = 0
for cx in (-1, 0, 1):
    for cz in (-1, 0, 1):
        if cx == 0 and cz == 0: continue
        rel = CITY + btypes[k] + ".gltf"; k += 1
        face_x = (cz == 0) or (cx * cz < 0)
        yaw = (-math.pi/2 if cx > 0 else math.pi/2) if face_x else (math.pi if cz > 0 else 0.0)
        mn, mx = bounds(rel); ox, oz = rot2((mn[0]+mx[0])/2, (mn[2]+mx[2])/2, yaw)
        place(D, rel, cx*CELL - ox, cz*CELL - oz, yaw, collide="box")
for x, z in [(11,11),(-11,11),(11,-11),(-11,-11),(25,25),(-25,-25),(25,-25),(-25,25)]:
    place(D, CITY + "Prop_Planter_Single.gltf", x, z)
for x in range(-8, 9, 4):
    for (bx, bz) in [(x, -13), (x, 13), (13, x), (-13, x)]:
        place(D, CITY + "Prop_Bollard.gltf", bx, bz)
for x, z in [(4,4),(-18,10),(18,-10),(10,-30),(-10,30),(40,0),(-40,0)]:
    place(D, CITY + "Prop_ManholeCover.gltf", x, z, y=0.02)
B = MON + "Blob/glTF/"
for (x, z), nm, mdl, hp in [((0,-9),"Gloop",B+"GreenBlob.gltf",80), ((18,4),"Spikeball",B+"GreenSpikyBlob.gltf",110),
                            ((-18,-4),"Shadow Ninja",B+"Ninja.gltf",90), ((4,18),"Street Wizard",B+"Wizard.gltf",120),
                            ((-4,-18),"Pinkle",B+"PinkBlob.gltf",60), ((18,30),"Alley Orc",B+"Orc.gltf",140),
                            ((-30,18),"Coo",B+"Pigeon.gltf",50), ((30,-18),"Space Blob",B+"Alien.gltf",100)]:
    monster(D, nm, x, z, mdl, 0.6, hp, wander=7)
# (hub has no floating sign; the HUD zone banner names it)

# roads from the city's street exits to each zone
R = group("Roads", W)
plane(R, "RoadW", -86, -18, 64, 8, "m_road", 0.015)
plane(R, "RoadE", 86, 18, 64, 8, "m_road", 0.015)
plane(R, "RoadN", -18, -84, 8, 60, "m_road", 0.015)
plane(R, "RoadS", 18, 84, 8, 60, "m_road", 0.015)

# ================================================================ OAKVALE VILLAGE (west)
VX, VZ = -122, -18
V = group("Village", W)
plane(V, "Square", VX, VZ, 30, 30, "m_cobble", 0.02)
sign(V, "OAKVALE VILLAGE", VX + 12, VZ, 8)

def house(cx, cz, w, d, yaw, style):
    """Modular medieval house: wall ring (door front-centre, windows), corner posts, tiled roof."""
    g = group(uname("House"), V)
    wall = {"plaster": ("Wall_Plaster_Straight", "Wall_Plaster_Door_Round", "Wall_Plaster_Window_Wide_Round"),
            "brick":   ("Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Door_Round", "Wall_UnevenBrick_Window_Wide_Round")}[style]
    segs = []  # (lx, lz, lyaw, kind)
    nx, nz = w // 2, d // 2
    for i in range(nx):
        lx = -w/2 + 1 + 2*i
        segs.append((lx,  d/2, 0.0, 1 if i == nx//2 else 2 if i % 2 == 0 else 0))
        segs.append((lx, -d/2, math.pi, 2 if i % 2 else 0))
    for j in range(nz):
        lz = -d/2 + 1 + 2*j
        segs.append((-w/2, lz, -math.pi/2, 2 if j % 2 else 0))
        segs.append(( w/2, lz,  math.pi/2, 2 if j % 2 == 0 else 0))
    for lx, lz, ly, kind in segs:
        ox, oz = rot2(lx, lz, yaw)
        place(g, MED + wall[kind] + ".gltf", cx + ox, cz + oz, yaw + ly)
    for sx in (-1, 1):
        for sz in (-1, 1):
            ox, oz = rot2(sx*w/2, sz*d/2, yaw)
            place(g, MED + "Corner_Exterior_Wood.gltf", cx + ox, cz + oz, yaw)
    place(g, MED + f"Roof_RoundTiles_{w}x{d}.gltf", cx, cz, yaw, y=3.0)
    ox, oz = rot2(w/2 - 1.2, -d/2 + 1.5, yaw)
    place(g, MED + "Prop_Chimney.gltf", cx + ox, cz + oz, yaw, y=4.6)
    # one collider for the whole house
    hb = sub(f"hbox_{w}_{d}", '[sub_resource type="BoxShape3D" id="ID"]\nsize = Vector3(%s, 3.2, %s)\n' % (w + 0.4, d + 0.4))
    nodes.append(f'[node name="Col" type="StaticBody3D" parent="{g}"]\nposition = Vector3({cx:.2f}, 1.6, {cz:.2f})\nrotation = Vector3(0, {yaw:.5f}, 0)\n\n'
                 f'[node name="S" type="CollisionShape3D" parent="{g}/Col"]\nshape = SubResource("{hb}")\n')

house(VX - 8, VZ - 19, 6, 6, 0.0, "plaster")
house(VX + 8, VZ - 20, 6, 8, 0.0, "brick")
house(VX - 8, VZ + 20, 8, 8, math.pi, "brick")
house(VX + 9, VZ + 19, 6, 6, math.pi, "plaster")
house(VX - 21, VZ - 4, 6, 8, math.pi/2, "plaster")
house(VX - 21, VZ + 8, 6, 6, math.pi/2, "brick")
# market + clutter
for i, (dx, dz) in enumerate([(-6, -6), (-6, 0), (-6, 6)]):
    place(V, FP + "Stall_Empty.gltf", VX + dx, VZ + dz, math.pi/2, collide="box")
    place(V, FP + ["FarmCrate_Apple", "FarmCrate_Carrot", "Barrel_Apples"][i] + ".gltf", VX + dx + 1.6, VZ + dz + 0.8)
for dx, dz, m in [(4,-9,"Barrel"),(5,-9.6,"Barrel"),(4.5,9,"Crate_Wooden"),(6,9.5,"Crate_Wooden"),(2,-11,"Bench"),(2,11,"Bench")]:
    place(V, FP + m + ".gltf", VX + dx, VZ + dz, random.random()*0.4)
place(V, MED + "Prop_Wagon.gltf", VX + 7, VZ + 3, 0.3, collide="box")
# shopkeeper behind the middle stall
npc_cap = sub("npc_cap", '[sub_resource type="CapsuleShape3D" id="ID"]\nradius = 0.4\nheight = 1.8\n')
npc_script = ext_id("scripts/npc.gd", "Script")
npc_model = ext_id(UAL)
nodes.append('[node name="Merchant" type="Node3D" parent="%s"]\nposition = Vector3(%.2f, 0.03, %.2f)\n'
             'rotation = Vector3(0, %.5f, 0)\nscript = ExtResource("%s")\ndisplay_name = "Merchant"\nmodel_scene = ExtResource("%s")\n'
             % (V, VX - 7.6, VZ, math.pi / 2, npc_script, npc_model))
nodes.append('[node name="Col" type="StaticBody3D" parent="%s/Merchant"]\n\n[node name="S" type="CollisionShape3D" parent="%s/Merchant/Col"]\n'
             'position = Vector3(0, 0.9, 0)\nshape = SubResource("%s")\n' % (V, V, npc_cap))
for i in range(6):
    place(V, MED + "Prop_WoodenFence_Single.gltf", VX - 14 + 2.06*i, VZ + 12.5)
BG = MON + "Big/glTF/"
for (dx, dz), nm, mdl, sc, hp in [((0,-4),"Clucky",B+"Chicken.gltf",0.45,40), ((2,5),"Bok",B+"Chicken.gltf",0.45,40),
                                  ((-3,8),"Whiskers",B+"Cat.gltf",0.5,60), ((9,-4),"Barkley",B+"Dog.gltf",0.55,70),
                                  ((-10,-8),"Mushnub",B+"Mushnub.gltf",0.5,90), ((10,10),"Bunbun",BG+"Bunny.gltf",0.5,80),
                                  ((-12,4),"Elder Mushnub",B+"Mushnub_Evolved.gltf",0.55,150)]:
    monster(V, nm, VX + dx, VZ + dz, mdl, sc, hp, wander=8)

# ================================================================ TRAINING GROUNDS (north)
TX, TZ = -18, -116
T = group("Training", W)
plane(T, "Yard", TX, TZ, 28, 28, "m_dirt", 0.02)
sign(T, "TRAINING GROUNDS", TX, TZ + 15, 8)
n = 13
for i in range(n):        # fence ring, gap on the south side for the road
    a = -13 + 2.06*i + 1.03
    place(T, MED + "Prop_WoodenFence_Single.gltf", TX + a, TZ - 13.5, collide=(2.06, 1.0, 0.3, 0, 0.5, 0))
    place(T, MED + "Prop_WoodenFence_Single.gltf", TX - 13.5, TZ + a, math.pi/2, collide=(2.06, 1.0, 0.3, 0, 0.5, 0))
    place(T, MED + "Prop_WoodenFence_Single.gltf", TX + 13.5, TZ + a, math.pi/2, collide=(2.06, 1.0, 0.3, 0, 0.5, 0))
    if abs(a) > 4:
        place(T, MED + "Prop_WoodenFence_Single.gltf", TX + a, TZ + 13.5, collide=(2.06, 1.0, 0.3, 0, 0.5, 0))
for row, dz in enumerate((-7, -2)):
    for col, dx in enumerate((-8, -4, 0, 4, 8)):
        monster(T, "Training Dummy", TX + dx, TZ + dz, FP + "Dummy.gltf", 1.0, 120, height=1.9, radius=0.4, wander=0)
for dx, dz, m, yaw in [(-11,-11,"WeaponStand",0.6),(11,-11,"WeaponStand",-0.6),(-11,4,"Barrel",0),(-10.2,4.6,"Barrel",0),
                       (11,4,"Anvil",0.3),(10,6,"Workbench",-1.57),(-11,8,"Bench",1.57),(6,-11,"Crate_Wooden",0.2)]:
    place(T, FP + m + ".gltf", TX + dx, TZ + dz, yaw, collide="box")
monster(T, "Sparring Orc", TX + 5, TZ + 6, BG + "Orc.gltf", 0.6, 250, wander=4)
monster(T, "Ninja Sensei", TX - 5, TZ + 6, BG + "Ninja.gltf", 0.6, 220, wander=4)

# ================================================================ WILD GROVE (east)
GX, GZ = 124, 18
G = group("Grove", W)
plane(G, "Meadow", GX, GZ, 64, 64, "m_grove", 0.01)
sign(G, "WILD GROVE", GX - 20, GZ, 9)
def scatter(models, count, rmin, rmax, scale=(0.8, 1.3), collide=None, avoid_road=True):
    placed = 0; tries = 0
    while placed < count and tries < count * 20:
        tries += 1
        a = random.random()*math.tau; r = random.uniform(rmin, rmax)
        x, z = GX + math.cos(a)*r, GZ + math.sin(a)*r
        if avoid_road and x < GX - 6 and abs(z - GZ) < 6: continue   # keep the entrance path clear
        place(G, NAT + random.choice(models) + ".gltf", x, z, random.random()*math.tau,
              scale=round(random.uniform(*scale), 2), collide=collide)
        placed += 1
scatter(["CommonTree_1","CommonTree_2","CommonTree_3","CommonTree_4","Pine_1","Pine_2","Pine_3","TwistedTree_1","TwistedTree_2"],
        30, 14, 31, collide=(0.8, 4, 0.8, 0, 2, 0))
scatter(["Rock_Medium_1","Rock_Medium_2","Rock_Medium_3"], 10, 9, 28, collide=(2.0, 1.6, 2.0, 0, 0.8, 0))
scatter(["Bush_Common","Bush_Common_Flowers","Fern_1","Plant_1_Big","Plant_7_Big"], 22, 6, 29)
scatter(["Grass_Common_Tall","Grass_Wispy_Tall","Grass_Common_Short","Clover_1"], 40, 3, 29)
scatter(["Flower_3_Group","Flower_4_Group","Mushroom_Common","Mushroom_Laetiporus"], 22, 4, 26)
FL = MON + "Flying/glTF/"
for (dx, dz), nm, mdl, sc, hp in [((-6,-8),"Emberwing",FL+"Dragon.gltf",0.6,140), ((7,-10),"Buzzbee",FL+"Armabee.gltf",0.55,90),
                                  ((10,6),"Pebbling",FL+"Goleling.gltf",0.6,120), ((-8,10),"Wisp",FL+"Ghost.gltf",0.55,80),
                                  ((0,14),"Squidle",FL+"Squidle.gltf",0.55,90), ((14,-2),"Hywirl",FL+"Hywirl.gltf",0.55,100),
                                  ((-12,-2),"Yeti",BG+"Yeti.gltf",0.65,180), ((4,-16),"Dino",BG+"Dino.gltf",0.65,170),
                                  ((-4,16),"Hopper",BG+"Frog.gltf",0.6,110), ((15,12),"Cactoro",BG+"Cactoro.gltf",0.6,130)]:
    monster(G, nm, GX + dx, GZ + dz, mdl, sc, hp, wander=7, speed=2.2)
monster(G, "MUSHROOM KING", GX + 2, GZ, BG + "MushroomKing.gltf", 1.0, 600, radius=1.0, wander=3, speed=1.2, boss=True)

# ================================================================ RESEARCH LAB (south)
LX, LZ = 18, 122
L = group("Lab", W)
sign(L, "RESEARCH LAB", LX, LZ - 12, 9)
NXT, NZT = 5, 4
WALLS = ["WallAstra_Straight", "WallAstra_Straight_Window", "WallBand_Straight", "WallAstra_Straight_Divided"]
for i in range(NXT):
    for j in range(NZT):
        x = LX + (i - (NXT-1)/2) * 4; z = LZ + (j - (NZT-1)/2) * 4
        place(L, SCI + "Platforms/" + ("Platform_Metal" if (i + j) % 2 else "Platform_DarkPlates") + ".gltf", x, z, y=0.03)
        edges = []
        if i == 0: edges.append(0.0)
        if i == NXT-1: edges.append(math.pi)
        if j == 0 and i != NXT//2: edges.append(-math.pi/2)    # entrance gap, north side
        if j == NZT-1: edges.append(math.pi/2)
        for e in edges:
            place(L, SCI + "Walls/" + WALLS[(i*3 + j + int(e*2)) % len(WALLS)] + ".gltf", x, z, e,
                  collide=(1.2, 3.0, 4.0, -2.17, 1.5, 0))
for dx, dz, m, yaw in [(-6,5.6,"Prop_Computer",math.pi),(-3,5.6,"Prop_Computer",math.pi),(6,5.6,"Prop_Computer",math.pi),
                       (-7.5,-3,"Prop_Crate3",0.3),(-7.4,-1.4,"Prop_Crate4",0),(7.3,-4,"Prop_Barrel_Large",0),
                       (7.3,1,"Prop_Chest",-1.57),(0,0,"Prop_Light_Floor",0),(-4,-5,"Prop_Light_Floor",0),(4,-5,"Prop_Light_Floor",0)]:
    place(L, SCI + "Props/" + m + ".gltf", LX + dx, LZ + dz, yaw, y=0.03, collide="box")
for dx, m in [(-4.5,"Alien_Cyclop"),(0,"Alien_Oculichrysalis"),(4.5,"Alien_Scolitex")]:   # specimens on display
    place(L, SCI + "Aliens/" + m + ".gltf", LX + dx, LZ + 3, math.pi, y=1.15)
for (dx, dz), nm, mdl, sc, hp in [((-4,-2),"Specimen X-1",BG+"Alien.gltf",0.6,150), ((4,-1),"Specimen X-2",B+"Alien.gltf",0.6,100),
                                  ((0,-12),"Lab Escapee",BG+"BlueDemon.gltf",0.6,160), ((6,-14),"Glub",FL+"Glub.gltf",0.55,90)]:
    monster(L, nm, LX + dx, LZ + dz, mdl, sc, hp, wander=3 if abs(dz) < 6 else 6)

# ================================================================ world edge
E = group("Edge", W)
for i in range(70):   # pine ring hides the end of the world
    a = i / 70 * math.tau + random.uniform(-0.03, 0.03); r = random.uniform(150, 162)
    place(E, NAT + random.choice(["Pine_1","Pine_2","Pine_3","Pine_4","Pine_5"]) + ".gltf",
          math.cos(a)*r, math.sin(a)*r, random.random()*math.tau, scale=round(random.uniform(1.4, 2.2), 2))
BW = 150
for nm, (x, z, sx, sz) in {"N":(0,-BW,2*BW,1),"S":(0,BW,2*BW,1),"E":(BW,0,1,2*BW),"W":(-BW,0,1,2*BW)}.items():
    sid = sub(f"wall_{sx}_{sz}", f'[sub_resource type="BoxShape3D" id="ID"]\nsize = Vector3({sx}, 6, {sz})\n')
    nodes.append(f'[node name="Wall{nm}" type="StaticBody3D" parent="{E}"]\nposition = Vector3({x}, 3, {z})\n\n'
                 f'[node name="S" type="CollisionShape3D" parent="{E}/Wall{nm}"]\nshape = SubResource("{sid}")\n')

# ---------------------------------------------------------------- write scene
mon_nodes = emit_monsters()
ext_id("scenes/player.tscn"); ext_id("scripts/hud.gd", "Script"); ext_id("scripts/intro_camera.gd", "Script")
sub("capsule_mesh", '[sub_resource type="CapsuleMesh" id="ID"]\n')
sub("floor_shape", '[sub_resource type="BoxShape3D" id="ID"]\nsize = Vector3(340, 1, 340)\n')
hdr = "\n".join(f'[ext_resource type="{t}" path="res://{r}" id="{rid}"]' for rid, r, t in ext)
subtxt = "\n".join(b.replace('id="ID"', f'id="{sid}"') for sid, b in subs)
scene = f'''[gd_scene load_steps={len(ext)+len(subs)+4} format=3]

{hdr}

{subtxt}
[sub_resource type="ProceduralSkyMaterial" id="sky_mat"]
sky_horizon_color = Color(0.72, 0.70, 0.66, 1)
ground_horizon_color = Color(0.72, 0.70, 0.66, 1)

[sub_resource type="Sky" id="sky"]
sky_material = SubResource("sky_mat")

[sub_resource type="Environment" id="env"]
background_mode = 2
sky = SubResource("sky")
ambient_light_source = 3
tonemap_mode = 2
fog_enabled = true
fog_light_color = Color(0.74, 0.74, 0.72, 1)
fog_density = 0.0012

[node name="Arena" type="Node3D"]

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("env")

[node name="Sun" type="DirectionalLight3D" parent="."]
rotation = Vector3(-0.75, 0.6, 0)
light_color = Color(1, 0.93, 0.82, 1)
shadow_enabled = true
directional_shadow_max_distance = 90.0

[node name="Floor" type="StaticBody3D" parent="."]

[node name="S" type="CollisionShape3D" parent="Floor"]
position = Vector3(0, -0.5, 0)
shape = SubResource("floor_shape")

{chr(10).join(nodes)}
{mon_nodes}[node name="Player" parent="." instance=ExtResource("{ext_id("scenes/player.tscn")}")]
position = Vector3(0, 1.1, 0)

[node name="HUD" type="CanvasLayer" parent="." node_paths=PackedStringArray("player")]
script = ExtResource("{ext_id("scripts/hud.gd", "Script")}")
player = NodePath("../Player")

[node name="IntroCamera" type="Camera3D" parent="." node_paths=PackedStringArray("player", "hud")]
script = ExtResource("{ext_id("scripts/intro_camera.gd", "Script")}")
player = NodePath("../Player")
hud = NodePath("../HUD")
'''
open(os.path.join(P, "scenes/arena.tscn"), "w").write(scene)
print(f"ok: {len(nodes)} world nodes, {len(monsters)} monsters, {len(ext)} resources, {len(subs)} sub-resources")
