extends RefCounted
## Builds a creature node (enemy.gd) from a party / storage record: used when loading a save and when a
## companion is taken out of storage. The species' model, size and stats come from data/creatures.json.

const Enemy := preload("res://scripts/enemy.gd")
const Data := preload("res://scripts/data.gd")


static func spawn_companion(record: Dictionary, player: Node3D, pos: Vector3) -> CharacterBody3D:
	var c := Data.creature(record.get("species", ""))
	if c.is_empty():
		push_warning("unknown species in record: %s" % record.get("species", "?"))
		return null
	var e := CharacterBody3D.new()
	e.set_script(Enemy)
	e.name = "Companion_%s" % record.get("uid", "x")
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = CapsuleMesh.new()
	e.add_child(mesh)
	var col := CollisionShape3D.new()
	col.name = "Collision"
	e.add_child(col)
	e.display_name = record.get("name", c.name)
	e.model_scene = load("res://" + c.model)
	e.model_scale = float(c.get("scale", 0.6))
	e.height = float(c.get("height", 1.5))
	e.radius = float(c.get("radius", 0.5))
	e.aggressive = false
	player.get_parent().add_child(e)
	e.global_position = pos
	e.adopt(player, record)
	return e
