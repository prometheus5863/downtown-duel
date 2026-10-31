extends Node3D
## Shopkeeper NPC: animated mannequin with a tint, name tag, opens the shop on interact.

@export var display_name := "Merchant"
@export var model_scene: PackedScene
@export var tint := Color(0.35, 0.6, 0.35)


func _ready() -> void:
	add_to_group("interactable")
	if model_scene:
		var m: Node3D = model_scene.instantiate()
		add_child(m)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = mat
		for ap in m.find_children("*", "AnimationPlayer", true, false):
			var clip := "Idle_Talking" if ap.has_animation("Idle_Talking") else "Idle"
			if ap.has_animation(clip):
				ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				ap.play(clip)
	var tag := Label3D.new()
	tag.text = display_name
	tag.font_size = 56
	tag.outline_size = 12
	tag.modulate = Color(1, 0.9, 0.5)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 2.3
	add_child(tag)


func can_interact() -> bool:
	return true


func open_shop() -> void:
	pass   # menus.gd builds the shop UI
