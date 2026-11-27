extends CanvasLayer
## Controls / tutorial screen (H, or ? on phones). Pauses the game. Shows the controls for the device you're on,
## grouped (Move & camera · Combat · Creatures & party · World), plus a few tips. On a new game a small welcome
## card points at it once (Game flag "seen_controls"), instead of a hint line that's always on screen.

const UI := preload("res://scripts/ui_style.gd")

var player: Node
var touch := false
var is_open := false

var _root: Control
var _welcome: PanelContainer

const KEYS := [
	["Move & camera", [["W A S D", "Move"], ["Mouse", "Look around (click to capture, Esc frees it)"], ["Q / E", "Turn the camera"],
		["Wheel", "Zoom"], ["Tab", "Lock on to the nearest creature"]]],
	["Combat", [["J / Left click", "Strike"], ["K / Right click", "Ember (ranged)"], ["Space", "Dodge roll (dodge through attacks)"]]],
	["Creatures & party", [["F", "Talk, pet, give treats, shop"], ["1  2  3  4  5", "Party: Attack · Follow · Hold · Return · Work"]]],
	["World & menus", [["R", "Use tool: mine, chop, gather (hold)"], ["T", "Place a block in a mine"], ["C", "Character: gear, party, bag"],
		["H", "This screen"], ["F5 / F9", "Save now / load last save"]]],
]
const TOUCH := [
	["Move & camera", [["Left thumb", "Move (the joystick appears where you touch)"], ["Drag on the right", "Look around"],
		["LOCK", "Lock on to the nearest creature"]]],
	["Combat", [["STRIKE", "Melee attack"], ["EMBER", "Ranged attack"], ["DODGE", "Dodge roll (dodge through attacks)"]]],
	["Creatures & party", [["TALK", "Talk, pet, give treats, shop (appears when something is near)"],
		["ATK FLW HLD RET WRK", "Party orders (appear once you have companions)"]]],
	["World & menus", [["TOOL / PLACE", "Mine, chop, gather / place a block"], ["ME", "Character: gear, party, bag"], ["?", "This screen"]]],
]
const TIPS := [
	"Befriend creatures with pets and treats; each has a favourite flavour that counts double.",
	"Hostile creatures must be weakened or calmed with a treat before they'll listen.",
	"Watch for the red \"!\" — that's a creature winding up an attack. Dodge it, then punish.",
	"Rest at the Creature Ledger in Oakvale to heal and revive your party.",
]


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("help") or (is_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		if is_open:
			close()
		else:
			open()


func open() -> void:
	if is_open or player.talking or not player.alive:
		return
	if get_tree().paused:                       # another pause menu (character menu) is up
		return
	_hide_welcome()
	_mark_seen()
	is_open = true
	_build()
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.modulate.a = 0.0
	_root.create_tween().tween_property(_root, "modulate:a", 1.0, 0.18)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	get_tree().paused = false


func _build() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var panel := UI.panel(UI.TEAL)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40
	panel.offset_top = 24
	panel.offset_right = -40
	panel.offset_bottom = -24
	_root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(UI.label("CONTROLS", 30, UI.TEAL))
	head.add_child(UI.chip("touch" if touch else "keyboard + mouse", UI.DIM))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var x := UI.button("Close", UI.DIM, "?" if touch else "H", 18)
	x.custom_minimum_size = Vector2(130, 44)
	x.pressed.connect(close)
	head.add_child(x)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	var flow := GridContainer.new()                  # two columns that share the width
	flow.columns = 2
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	body.add_child(flow)
	for group in (TOUCH if touch else KEYS):
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UI.card_box(UI.TEAL))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)
		cv.add_child(UI.label(group[0], 19, UI.GOLD))
		for row in group[1]:
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 12)
			var k := UI.chip(row[0], UI.TEAL, 15)
			k.custom_minimum_size.x = 150
			k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(k)
			var d := UI.label(row[1], 16)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(d)
			cv.add_child(h)
		flow.add_child(card)
	body.add_child(UI.label("Tips", 19, UI.GOLD))
	for tip in TIPS:
		var l := UI.label("•  " + tip, 16, UI.DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(l)


# ------------------------------------------------------------------ first-run welcome card

## Shown once on a new game (after the intro), fades out by itself after a while.
func show_welcome() -> void:
	if _seen() or _welcome:
		return
	_welcome = UI.panel(UI.TEAL)
	_welcome.anchor_left = 0.5
	_welcome.anchor_right = 0.5
	if touch:                                     # phones: under the target bar, clear of the thumbs
		_welcome.offset_left = -290
		_welcome.offset_right = 290
		_welcome.offset_top = 86
	else:                                         # desktop: above the HP bar
		_welcome.anchor_top = 1.0
		_welcome.anchor_bottom = 1.0
		_welcome.offset_left = -330
		_welcome.offset_right = 330
		_welcome.offset_top = -250
		_welcome.offset_bottom = -120
	_welcome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_welcome.add_child(v)
	v.add_child(UI.label("Welcome to Downtown Duel!", 22, UI.TEAL))
	var lines := ["Left thumb moves, drag on the right to look.", "TALK to creatures to pet them and give treats.",
		"Tap  ?  any time to see every control."] if touch else \
		["WASD to move, click to look around.  J strike · K ember · Space dodge.",
		"F to talk to creatures: pet them and give treats to make friends.", "Press  H  any time to see every control."]
	for l in lines:
		v.add_child(UI.label(l, 17))
	add_child(_welcome)
	_welcome.modulate.a = 0.0
	var t := _welcome.create_tween()
	t.tween_property(_welcome, "modulate:a", 1.0, 0.4)
	t.tween_interval(12.0)
	t.tween_property(_welcome, "modulate:a", 0.0, 0.8)
	t.tween_callback(_hide_welcome)
	_mark_seen()


func _hide_welcome() -> void:
	if _welcome:
		_welcome.queue_free()
		_welcome = null


func _game() -> Node:
	return get_tree().get_first_node_in_group("game")


func _seen() -> bool:
	var g := _game()
	return g != null and g.flags.get("seen_controls", false)


func _mark_seen() -> void:
	var g := _game()
	if g:
		g.flags["seen_controls"] = true
