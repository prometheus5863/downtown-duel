extends Node3D
## Creature Ledger: swap companions between the party and storage, and rest (heal + revive the party).
## Interim stand-alone version; M5 folds it into the Sanctuary. menus.gd builds the UI (open_ledger marker).

@export var display_name := "Creature Ledger"
@export var model_scene: PackedScene


func _ready() -> void:
	add_to_group("interactable")
	if model_scene:
		add_child(model_scene.instantiate())
	var tag := Label3D.new()
	tag.text = display_name
	tag.font_size = 48
	tag.outline_size = 10
	tag.modulate = Color(0.5, 1.0, 0.9)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 2.1
	add_child(tag)


func can_interact() -> bool:
	return true


func open_ledger() -> void:
	pass   # menus.gd builds the ledger UI
