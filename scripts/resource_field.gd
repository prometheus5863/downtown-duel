extends Node3D
## A field of harvestable nodes of one kind (data/resources.json): trees, rocks, ore veins, bushes, herbs.
## Drawn with one MultiMesh per model part (cheap even with many nodes), one StaticBody per node when the kind
## has a collider. A node takes `hits` (fewer with a better tool), then disappears and respawns after `respawn` s.
## The generator places the fields (positions in `points`, yaw in `yaws`).

const Data := preload("res://scripts/data.gd")

@export var kind := "rock"
@export var model_scene: PackedScene
@export var points: PackedVector3Array = []
@export var yaws: PackedFloat32Array = []

var info := {}
var _hp: PackedInt32Array = []
var _back_at: PackedFloat32Array = []        # 0 = standing, else time (s) it respawns
var _mms: Array[MultiMeshInstance3D] = []
var _parts: Array[Transform3D] = []           # each MultiMesh's mesh transform inside the model
var _bodies: Array[StaticBody3D] = []
var _clock := 0.0


func _ready() -> void:
	add_to_group("resource_field")
	info = Data.table("resources").get(kind, {})
	_hp.resize(points.size())
	_back_at.resize(points.size())
	for i in points.size():
		_hp[i] = int(info.get("hits", 1))
	if model_scene:
		var m: Node3D = model_scene.instantiate()
		add_child(m)                              # in the tree only long enough to read global transforms
		var tint := Color(info.tint) if info.has("tint") else Color.WHITE
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			if tint != Color.WHITE:
				mesh = _tinted(mesh, tint)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = points.size()
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.visibility_range_end = 140.0
			add_child(mmi)
			_mms.append(mmi)
			_parts.append(m.global_transform.affine_inverse() * (mi as Node3D).global_transform)
		remove_child(m)
		m.free()
	var box = info.get("collider")
	for i in points.size():
		_show(i, true)
		if box is Array:
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(box[0], box[1], box[2])
			cs.shape = shape
			cs.position.y = box[1] * 0.5
			body.add_child(cs)
			body.position = points[i]
			body.set_meta("field_index", i)
			add_child(body)
			_bodies.append(body)


func _process(delta: float) -> void:
	_clock += delta
	for i in _back_at.size():
		if _back_at[i] > 0.0 and _clock >= _back_at[i]:
			_back_at[i] = 0.0
			_hp[i] = int(info.get("hits", 1))
			_show(i, true)


func available(i: int) -> bool:
	return i >= 0 and i < points.size() and _back_at[i] == 0.0


func world_pos(i: int) -> Vector3:
	return to_global(points[i])


## Index of the nearest standing node within max_dist of `pos` (-1 if none).
func nearest(pos: Vector3, max_dist: float) -> int:
	var best := -1
	var best_d := max_dist
	for i in points.size():
		if not available(i):
			continue
		var d := world_pos(i).distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best


## Can a tool of this kind / tier work this field? hand-tool kinds accept anything (even bare hands).
func tool_ok(tool_kind: String, tool_tier: int) -> bool:
	var need: String = info.get("tool", "hand")
	if need == "hand":
		return true
	return tool_kind == need and tool_tier >= int(info.get("tier", 0))


## One hit on node i. Returns {done: bool, drops: {item: n}, msg}. Drops are only given when it breaks.
func hit(i: int, tool_kind: String, tool_tier: int) -> Dictionary:
	if not available(i):
		return {"done": false, "drops": {}, "msg": ""}
	if not tool_ok(tool_kind, tool_tier):
		var need: String = info.get("tool", "hand")
		return {"done": false, "drops": {}, "msg": "Needs a %s (tier %d)" % ["pickaxe" if need == "pick" else "axe", int(info.get("tier", 0))]}
	var dmg := 1 + maxi(tool_tier - int(info.get("tier", 0)), 0)      # better tools take fewer hits
	_hp[i] = maxi(_hp[i] - dmg, 0)
	_wobble(i)
	if _hp[i] > 0:
		return {"done": false, "drops": {}, "msg": ""}
	_back_at[i] = _clock + float(info.get("respawn", 90))
	_show(i, false)
	var drops := {}
	for item in info.get("drops", {}):
		var r: Array = info.drops[item]
		drops[item] = randi_range(int(r[0]), int(r[1]))
	return {"done": true, "drops": drops, "msg": ""}


func _show(i: int, on: bool) -> void:
	var base := Transform3D(Basis(Vector3.UP, yaws[i] if i < yaws.size() else 0.0), points[i])
	if not on:
		base = base.scaled_local(Vector3.ONE * 0.001)
	for k in _mms.size():
		_mms[k].multimesh.set_instance_transform(i, base * _parts[k])
	if i < _bodies.size():
		_bodies[i].process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		_bodies[i].collision_layer = 1 if on else 0


## Quick shake so a hit reads even without particles.
func _wobble(i: int) -> void:
	var base := Transform3D(Basis(Vector3.UP, yaws[i] if i < yaws.size() else 0.0), points[i])
	for k in _mms.size():
		_mms[k].multimesh.set_instance_transform(i, base.rotated_local(Vector3.FORWARD, 0.08) * _parts[k])
	get_tree().create_timer(0.08).timeout.connect(func():
		if available(i) or _hp[i] > 0:
			_show(i, true))


static func _tinted(mesh: Mesh, tint: Color) -> Mesh:
	var m: Mesh = mesh.duplicate()
	for s in m.get_surface_count():
		var mat := m.surface_get_material(s)
		if mat is StandardMaterial3D:
			var t: StandardMaterial3D = mat.duplicate()
			t.albedo_color = t.albedo_color * tint
			m.surface_set_material(s, t)
	return m
