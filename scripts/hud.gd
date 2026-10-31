extends CanvasLayer
## HUD built in code: enemy HP bar, cooldowns, control hints, intro title.

@export var player: Node
@export var force_touch := false        ## show touch controls even without a touchscreen (testing)

const TouchControls := preload("res://scripts/touch_controls.gd")
var touch: CanvasLayer
var _hint: Label

var _bar: ProgressBar
var _cd_label: Label
var _title: Label
var _top: Control
var _name_l: Label
var _zone_l: Label
var _zone := ""

## name, centre (x, z), radius — keep in sync with tools/gen_world.py
const ZONES := [
	["Downtown", Vector2(0, 0), 56.0],
	["Oakvale Village", Vector2(-122, -18), 30.0],
	["Training Grounds", Vector2(-18, -116), 18.0],
	["Wild Grove", Vector2(124, 18), 32.0],
	["Research Lab", Vector2(18, 122), 16.0],
]


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Enemy HP (top centre) ---
	var top := VBoxContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -220
	top.offset_right = 220
	top.offset_top = 18
	root.add_child(top)
	_top = top
	_name_l = _label("", 20)
	_name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_name_l)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(440, 18)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.86, 0.22, 0.2)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", bg)
	top.add_child(_bar)

	# --- Cooldowns + hints (bottom left) ---
	var bottom := VBoxContainer.new()
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 20
	bottom.offset_top = -78
	bottom.offset_right = 700
	root.add_child(bottom)
	_cd_label = _label("", 22)
	bottom.add_child(_cd_label)
	_hint = _label("Click to look around (Esc frees mouse) · WASD move · LMB / J strike · RMB / K ember · Tab lock · Wheel zoom · Q/E turn", 15)
	bottom.add_child(_hint)

	# --- Phones / tablets ---
	if force_touch or DisplayServer.is_touchscreen_available() \
			or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		touch = TouchControls.new()
		touch.player = player
		add_child(touch)
		_hint.text = "Left thumb: move · Drag right side: camera · Buttons: strike / ember / lock"
		bottom.offset_left = 300                 # keep text clear of the joystick
		bottom.offset_top = -40

	# --- Zone banner (upper centre) ---
	_zone_l = _label("", 40)
	_zone_l.anchor_left = 0.0
	_zone_l.anchor_right = 1.0
	_zone_l.offset_top = 110
	_zone_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_l.modulate.a = 0.0
	root.add_child(_zone_l)

	# --- Intro title (centre) ---
	_title = _label("DOWNTOWN DUEL", 84)
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.modulate.a = 0.0
	root.add_child(_title)


func _process(delta: float) -> void:
	_check_zone()
	# Target panel follows whatever the player is locked on to.
	var t = player.target if player.locked else null
	_top.visible = t != null
	if t:
		_name_l.text = t.display_name.to_upper()
		_bar.max_value = t.max_hp
		_bar.value = move_toward(_bar.value, t.hp, t.max_hp * 4.0 * delta)
	var keys := touch == null
	_cd_label.text = ("[J] Strike  %s      [K] Ember  %s" if keys else "Strike  %s      Ember  %s") % [
		_cd_text(player.cooldowns.strike), _cd_text(player.cooldowns.ember)]


func _check_zone() -> void:
	if not player.can_control:
		return
	var p := Vector2(player.global_position.x, player.global_position.z)
	var z := ""
	for zone in ZONES:
		if p.distance_to(zone[1]) < zone[2]:
			z = zone[0]
	if z != "" and z != _zone:
		_zone_l.text = "— " + z.to_upper() + " —"
		var t := create_tween()
		t.tween_property(_zone_l, "modulate:a", 1.0, 0.4)
		t.tween_interval(1.8)
		t.tween_property(_zone_l, "modulate:a", 0.0, 0.8)
	if z != "":
		_zone = z


func show_title(duration: float) -> void:
	var t := create_tween()
	t.tween_property(_title, "modulate:a", 1.0, 0.8).set_delay(0.6)
	t.tween_interval(maxf(duration - 2.8, 0.5))
	t.tween_property(_title, "modulate:a", 0.0, 0.8)


func hide_title() -> void:
	create_tween().tween_property(_title, "modulate:a", 0.0, 0.25)


func _cd_text(t: float) -> String:
	return "READY" if t <= 0.0 else "%.1fs" % t


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", maxi(size / 6, 4))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
