extends Node3D
## Treasure chest: opens once for coins + XP, and optionally a piece of gear (equipped on the spot).
## Uses the dialogue panel through the talk_* protocol (see menus.gd).

const Items := preload("res://scripts/items.gd")

@export var display_name := "treasure chest"
@export var coins := 30
@export var xp := 10
@export var item := ""                 ## items.gd id, optional
@export var model_scene: PackedScene

var opened := false
var _model: Node3D


func _ready() -> void:
	add_to_group("interactable")
	if model_scene:
		_model = model_scene.instantiate()
		add_child(_model)


func can_interact() -> bool:
	return not opened


func talk_begin() -> Dictionary:
	opened = true
	var p := get_tree().get_first_node_in_group("player")
	var text := "You found %d coins" % coins
	if item != "" and p and not (item in p.owned):
		var it := Items.get_item(item)
		p.owned.append(item)
		text += " and %s (%s)" % [it.name, it.desc]
		if _better(it, Items.get_item(p.gear.get(it.slot, ""))):
			p.equip(item)
			text += " — equipped!"
		else:
			text += ". Equip it at any shop that sells %s." % ("armor" if it.slot == "armor" else it.slot + "s")
	else:
		text += "!"
	if p:
		p.reward(xp, coins, "")
	return {"title": "Treasure chest", "text": text, "options": [], "end": "leave"}


## Upgrade check by price (prices track item power in items.gd).
func _better(new_item: Dictionary, current: Dictionary) -> bool:
	return current.is_empty() or int(new_item.get("price", 0)) > int(current.get("price", 0))


func talk_choose(_option: String) -> Dictionary:
	return {}


func talk_end(_result: String) -> void:
	if _model:
		var t := create_tween()
		t.tween_property(_model, "scale", Vector3(0.01, 0.01, 0.01), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_callback(_model.queue_free)
