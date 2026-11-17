extends Node3D
## Block mine: a hill of 1 m blocks (GridMap) generated from noise, so the same seed always gives the same hill.
##  - surface dirt, stone below, ores by depth under the surface (data/blocks.json: copper ... crystal)
##  - caves carved by 3D noise plus an entrance tunnel from the `entrance` side
##  - break blocks (pickaxe tier gates ores, hardness = hits), place stone / dirt back
##  - only the changes against the generated layout are saved (`diff`: "x,y,z" -> block id or "")
## Node origin = the hill's minimum corner on the ground; cells are 1 m.

const Data := preload("res://scripts/data.gd")

@export var mine_id := "quarry"
@export var size := Vector3i(24, 11, 24)
@export var seed_value := 7
@export var entrance := Vector3i(0, 0, -1)             ## side of the entrance tunnel (-z = north)
@export var tiles: Array[Texture2D] = []               ## block textures, in data/blocks.json order (minus "_doc")

var block_ids: Array = []                              ## GridMap item index -> block id
var diff := {}                                          ## "x,y,z" -> block id ("" = removed)
var grid: GridMap
var _damage := {}                                       # Vector3i -> hits taken so far
var _height := {}                                       # Vector2i -> surface height (cells)


func _ready() -> void:
	add_to_group("mine")
	for id in Data.table("blocks"):
		if not id.begins_with("_"):
			block_ids.append(id)
	grid = GridMap.new()
	grid.cell_size = Vector3.ONE
	grid.cell_center_x = true
	grid.cell_center_y = true
	grid.cell_center_z = true
	grid.mesh_library = _library()
	add_child(grid)
	generate()


func _library() -> MeshLibrary:
	var lib := MeshLibrary.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	for i in block_ids.size():
		var mat := StandardMaterial3D.new()
		if i < tiles.size() and tiles[i]:
			mat.albedo_texture = tiles[i]
		mat.uv1_triplanar = true                         # one tile per 1 m face, whatever the box UVs are
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		mat.roughness = 0.95
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		mesh.material = mat
		lib.create_item(i)
		lib.set_item_name(i, block_ids[i])
		lib.set_item_mesh(i, mesh)
		lib.set_item_shapes(i, [box, Transform3D.IDENTITY])
	return lib


# ------------------------------------------------------------------ generation

func generate() -> void:
	grid.clear()
	_damage.clear()
	var hn := FastNoiseLite.new()
	hn.seed = seed_value
	hn.frequency = 0.08
	var cave := FastNoiseLite.new()
	cave.seed = seed_value + 101
	cave.frequency = 0.14
	var c := Vector2(size.x - 1, size.z - 1) * 0.5
	for x in size.x:
		for z in size.z:
			# hill: noise heightmap with a soft fall-off to the edges
			var edge := 1.0 - clampf((Vector2(x, z) - c).length() / (c.length() * 0.95), 0.0, 1.0)
			var h := int(round((0.45 + 0.55 * (hn.get_noise_2d(x, z) * 0.5 + 0.5)) * size.y * smoothstep(0.0, 0.55, edge)))
			h = clampi(h, 0, size.y)
			_height[Vector2i(x, z)] = h
			for y in h:
				var depth := h - 1 - y
				if depth >= 2 and y >= 1 and cave.get_noise_3d(x, y, z) > 0.5:
					continue                              # cave pocket
				grid.set_cell_item(Vector3i(x, y, z), block_ids.find(_pick(x, y, z, depth)))
	_carve_entrance()
	for key in diff:
		_apply(key, diff[key])


## Which block sits at a cell `depth` blocks under the surface. Deterministic per seed + position.
func _pick(x: int, y: int, z: int, depth: int) -> String:
	if depth == 0:
		return "dirt"
	if depth == 1:
		return "gravel" if _roll(x, y, z, 0) < 0.3 else "dirt"
	var blocks := Data.table("blocks")
	var ores := block_ids.filter(func(b): return blocks[b].has("depth"))
	ores.reverse()                                       # rarest / deepest first
	for i in ores.size():
		var band: Array = blocks[ores[i]].depth
		if depth >= int(band[0]) and _roll(x, y, z, i + 1) < float(band[1]):
			return ores[i]
	return "stone"


func _roll(x: int, y: int, z: int, salt: int) -> float:
	return float(hash([seed_value, x, y, z, salt]) % 10000) / 10000.0


## 3-wide, 3-high tunnel from the entrance side to the middle at ground level (room for the third-person camera).
func _carve_entrance() -> void:
	var mid := Vector3i(size.x / 2, 0, size.z / 2)
	var steps := (size.x if entrance.x != 0 else size.z) / 2
	for s in steps + 1:                                  # centre -> edge
		var p := mid + entrance * s
		for w in range(-1, 2):
			for y in 3:
				var side := Vector3i(w, 0, 0) if entrance.x == 0 else Vector3i(0, 0, w)
				grid.set_cell_item(p + side + Vector3i(0, y, 0), GridMap.INVALID_CELL_ITEM)


# ------------------------------------------------------------------ queries

func block_at(cell: Vector3i) -> String:
	var i := grid.get_cell_item(cell)
	return "" if i == GridMap.INVALID_CELL_ITEM else block_ids[i]


func in_bounds(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.z >= 0 and cell.x < size.x and cell.y < size.y + 4 and cell.z < size.z


func world_to_cell(p: Vector3) -> Vector3i:
	return grid.local_to_map(grid.to_local(p))


func cell_center(cell: Vector3i) -> Vector3:
	return grid.to_global(grid.map_to_local(cell))


## Count of each block in the mine (tests / debugging).
func census() -> Dictionary:
	var out := {}
	for cell in grid.get_used_cells():
		var b := block_at(cell)
		out[b] = int(out.get(b, 0)) + 1
	return out


# ------------------------------------------------------------------ edits

## One pickaxe hit. Returns {broke, drop, msg}.
func hit(cell: Vector3i, tool_tier: int) -> Dictionary:
	var id := block_at(cell)
	if id == "":
		return {"broke": false, "drop": "", "msg": ""}
	var b: Dictionary = Data.table("blocks")[id]
	if tool_tier < int(b.tier):
		return {"broke": false, "drop": "", "msg": "%s needs a better pickaxe (tier %d)" % [b.name, int(b.tier)]}
	var dmg := 1 + (tool_tier - int(b.tier))
	_damage[cell] = int(_damage.get(cell, 0)) + dmg
	_fx(cell, Color(0.8, 0.75, 0.7), 4)
	if _damage[cell] < int(b.hardness):
		return {"broke": false, "drop": "", "msg": "%s  %d / %d" % [b.name, _damage[cell], int(b.hardness)]}
	_set_block(cell, "")
	_fx(cell, Color(0.9, 0.85, 0.8), 12)
	return {"broke": true, "drop": b.drop, "msg": ""}


## Place a block into an empty cell. Refuses cells that would trap a body (the player or a creature).
func place(cell: Vector3i, id: String) -> bool:
	if not in_bounds(cell) or block_at(cell) != "" or not Data.table("blocks").get(id, {}).get("place", false):
		return false
	var c := cell_center(cell)
	for body in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("enemy"):
		var p: Vector3 = body.global_position
		if absf(p.x - c.x) < 0.9 and absf(p.z - c.z) < 0.9 and c.y > p.y - 1.2 and c.y < p.y + 1.2:
			return false
	_set_block(cell, id)
	return true


func _set_block(cell: Vector3i, id: String) -> void:
	grid.set_cell_item(cell, GridMap.INVALID_CELL_ITEM if id == "" else block_ids.find(id))
	_damage.erase(cell)
	diff["%d,%d,%d" % [cell.x, cell.y, cell.z]] = id


func _apply(key: String, id: String) -> void:
	var p := key.split(",")
	var cell := Vector3i(int(p[0]), int(p[1]), int(p[2]))
	grid.set_cell_item(cell, GridMap.INVALID_CELL_ITEM if id == "" else block_ids.find(id))


## Loading a save: replay the saved changes on top of the freshly generated hill.
func apply_diff(d: Dictionary) -> void:
	diff = d.duplicate()
	for key in diff:
		_apply(key, String(diff[key]))


## Little burst of cubes where a block was hit / broken.
func _fx(cell: Vector3i, col: Color, n: int) -> void:
	if not is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = n
	p.lifetime = 0.5
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -12, 0)
	var m := BoxMesh.new()
	m.size = Vector3.ONE * 0.12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	m.material = mat
	p.mesh = m
	add_child(p)
	p.global_position = cell_center(cell)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)
