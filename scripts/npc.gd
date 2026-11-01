extends Node3D
## Shopkeeper NPC: animation rig dressed by avatar.gd, name tag, opens the shop on interact.

const Avatar := preload("res://scripts/avatar.gd")

@export var display_name := "Merchant"
@export var model_scene: PackedScene          ## UAL rig
@export var parts: Array[PackedScene] = []    ## head, hair, outfit
@export var outfit_tex: Texture2D
@export var hair_color := Color(0.3, 0.2, 0.12)
@export var stock: Array[String] = []         ## item slots for sale (empty = everything)
@export var max_price := 0                    ## only items up to this price (0 = no limit)
@export var greeting := "Welcome! Gear for every kind of trainer."
@export var idle_clip := "Idle_Talking"


func _ready() -> void:
	add_to_group("interactable")
	if model_scene:
		var m: Node3D = model_scene.instantiate()
		add_child(m)
		if not parts.is_empty():
			Avatar.dress(m, {"parts": parts, "tex": outfit_tex, "hair": hair_color})
		for ap in m.find_children("*", "AnimationPlayer", true, false):
			var clip := idle_clip if ap.has_animation(idle_clip) else "Idle"
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
	pass   # menus.gd builds the shop UI from stock / greeting
