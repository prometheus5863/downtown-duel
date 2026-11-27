extends CanvasLayer
## HUD built in code: enemy HP bar, cooldowns, control hints, intro title.

@export var player: Node
@export var force_touch := false        ## show touch controls even without a touchscreen (testing)

const TouchControls := preload("res://scripts/touch_controls.gd")
const Menus := preload("res://scripts/menus.gd")
var menus: CanvasLayer
var _info: Label
var _bottom: Control
var _prompt: Label
var touch: CanvasLayer
var _hint: Label

var _bar: Control                      # fancy_bar.gd (target HP)
var _cd_label: Label
var _title: Label
var _top: Control
var _name_l: Label
var _zone_l: Label
var _hp_bar: Control                   # fancy_bar.gd (player HP)
var _pills: HBoxContainer
var controls: CanvasLayer               ## controls_menu.gd (H / ?)
var _welcome_t := -1.0
var _hurt_flash: ColorRect
var _banner: Label
var _title_tween: Tween
var _zone := ""
var _lvl_card: Control
var _cinema_hide: Array = []
var _cross: Label
var _tool_t := 0.0
var _tool_target := {}

## name, centre (x, z), radius — keep in sync with tools/gen_world.py
const ZONES := [
	["Downtown", Vector2(0, 0), 56.0],
	["Oakvale Village", Vector2(-122, -18), 30.0],
	["Training Grounds", Vector2(-18, -116), 18.0],
	["Wild Grove", Vector2(124, 18), 32.0],
	["Research Lab", Vector2(18, 122), 16.0],
	["Ivy Ruins", Vector2(-92, -92), 26.0],
	["Neon Bazaar", Vector2(92, -90), 26.0],
	["Old Quarter", Vector2(-90, 92), 26.0],
	["Skyport", Vector2(94, 94), 26.0],
	["Pebble Hill Quarry", Vector2(-82, 25), 18.0],
]
const Minimap := preload("res://scripts/minimap.gd")
const PartyPanel := preload("res://scripts/party_panel.gd")
const Data := preload("res://scripts/data.gd")
const CharacterMenu := preload("res://scripts/character_menu.gd")
const FancyBar := preload("res://scripts/fancy_bar.gd")
const AbilityPill := preload("res://scripts/ability_pill.gd")
const ControlsMenu := preload("res://scripts/controls_menu.gd")
var character_menu: CanvasLayer


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
	_bar = FancyBar.new()
	_bar.custom_minimum_size = Vector2(440, 20)
	_bar.fill_color = Color(0.92, 0.3, 0.22)
	_bar.low_color = Color(1.0, 0.6, 0.2)
	_bar.trail_color = Color(1.0, 0.95, 0.75, 0.9)
	_bar.show_text = true
	_bar.ticks = 4
	top.add_child(_bar)

	# --- Cooldowns + hints (bottom left) ---
	var bottom := VBoxContainer.new()
	_bottom = bottom
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 20
	bottom.offset_top = -78
	bottom.offset_right = 700
	root.add_child(bottom)
	_hp_bar = FancyBar.new()
	_hp_bar.custom_minimum_size = Vector2(340, 22)
	_hp_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_hp_bar.show_text = true
	_hp_bar.text_prefix = "HP  "
	_hp_bar.font_size = 14
	_hp_bar.snap(player.max_hp, player.max_hp)
	bottom.add_child(_hp_bar)
	bottom.offset_top = -78
	bottom.add_theme_constant_override("separation", 8)
	# cooldown pills: fill while recharging, glow when ready
	_pills = HBoxContainer.new()
	_pills.add_theme_constant_override("separation", 8)
	_pills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_pills)
	for a in [["Strike", "J", "strike", Color(1.0, 0.82, 0.38)], ["Ember", "K", "ember", Color(1.0, 0.55, 0.25)],
			["Dodge", "␣", "dodge", Color(0.45, 1.0, 0.75)]]:
		var pill: Control = AbilityPill.new()
		pill.title = a[0]
		pill.key = a[1]
		pill.color = a[3]
		var cd: String = a[2]
		pill.read_cooldown = func(): return float(player.cooldowns[cd])
		_pills.add_child(pill)
	_cd_label = _label("", 1)                 # kept for compatibility; the pills replace the text
	_cd_label.visible = false
	bottom.add_child(_cd_label)

	_hurt_flash = ColorRect.new()
	_hurt_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt_flash.color = Color(0.9, 0.05, 0.05, 0.0)
	_hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hurt_flash)
	_banner = _label("", 64)
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	root.add_child(_banner)
	player.hp_changed.connect(func(hp, mx): _hp_bar.max_value = mx; _hp_bar.value = float(hp))
	player.hurt.connect(_on_hurt)
	player.died.connect(func(): _show_banner("DEFEATED", Color(1, 0.35, 0.3), 2.4))
	# (the always-on controls hint line is gone: H / ? opens the controls screen, and new games get a welcome card)
	_hint = _label("", 1)
	_hint.visible = false
	bottom.add_child(_hint)

	# --- Phones / tablets ---
	if force_touch or DisplayServer.is_touchscreen_available() \
			or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		touch = TouchControls.new()
		touch.player = player
		add_child(touch)
		bottom.offset_left = 300                 # keep clear of the joystick
		bottom.offset_top = -86
		for pill in _pills.get_children():
			pill.key = ""                        # no keyboard on phones
			pill.custom_minimum_size.x = 112

	# --- Progress line (top left) + interaction prompt ---
	_info = _label("", 18)
	_info.offset_left = 16
	_info.offset_top = 12
	root.add_child(_info)
	_cinema_hide.append(_info)
	var pp: VBoxContainer = PartyPanel.new()
	pp.player = player
	pp.touch = touch != null
	pp.offset_left = 16
	pp.offset_top = 70
	root.add_child(pp)
	_cinema_hide.append(pp)
	var mm: Control = Minimap.new()
	mm.player = player
	mm.zones = ZONES
	mm.anchor_left = 1.0
	mm.anchor_right = 1.0
	mm.offset_left = -196
	mm.offset_right = -16
	mm.offset_top = 12
	mm.offset_bottom = 192
	root.add_child(mm)
	_cinema_hide.append(mm)
	_cross = _label("+", 30)
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.offset_left = -9
	_cross.offset_top = -22
	_cross.visible = false
	root.add_child(_cross)
	var game := get_tree().get_first_node_in_group("game")
	if game == null:                         # Game is the last node in the scene: not ready yet
		game = get_parent().get_node_or_null("Game")
	if game:
		var toast := _label("Game saved", 18)
		toast.anchor_left = 1.0
		toast.anchor_right = 1.0
		toast.offset_left = -196
		toast.offset_top = 196
		toast.modulate = Color(0.7, 1.0, 0.75, 0.0)
		root.add_child(toast)
		game.saved.connect(func():
			var tw := create_tween()
			tw.tween_property(toast, "modulate:a", 1.0, 0.2)
			tw.tween_interval(1.4)
			tw.tween_property(toast, "modulate:a", 0.0, 0.6))
	controls = ControlsMenu.new()
	controls.player = player
	controls.touch = touch != null
	add_child(controls)
	character_menu = CharacterMenu.new()
	character_menu.player = player
	add_child(character_menu)
	_prompt = _label("", 26)
	_prompt.anchor_left = 0.0
	_prompt.anchor_right = 1.0
	_prompt.anchor_top = 0.62
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_prompt)
	menus = Menus.new()
	menus.player = player
	add_child(menus)
	player.interact_requested.connect(menus.open_for)
	player.leveled_up.connect(_level_up)

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
	var r: Dictionary = player.route
	var treats := 0
	for id in player.inventory:
		if Data.table("treats").has(id):
			treats += player.inventory[id]
	_info.text = "Lv %d   XP %d / %d   Coins %d   Treats %d\nRoute: %s   (defeated %d · spared %d · friends %d)" % [
		player.level, player.xp, player.xp_to_next(), player.coins, treats,
		player.route_name(), r.defeated, r.spared, r.friends]
	_bottom.visible = not menus.is_open
	for c in _cinema_hide:                       # conversations are framed like cut-scenes: no HUD clutter
		c.visible = not menus.is_open
	if _zone_l:
		_zone_l.visible = not menus.is_open
	var near: Node = null if menus.is_open or not player.can_control else player.nearest_interactable()
	if near == null:
		_prompt.text = ""
		_tool_t -= delta
		if _tool_t <= 0.0 and not menus.is_open and player.can_control:
			_tool_t = 0.15                        # ray + field scan at ~7 Hz is plenty for a prompt
			_tool_target = player.tool_target()
		var tt := _tool_target if player.can_control and not menus.is_open else {}
		_cross.visible = tt.get("type", "") == "block"
		if not tt.is_empty():
			var key := "TOOL" if touch else "[R]"
			if tt.type == "block":
				var placeable: int = player.item_count("stone") + player.item_count("dirt")
				_prompt.text = "%s Mine %s" % [key, tt.label] + ("   ·   %s place block (%d)" % ["PLACE" if touch else "[T]", placeable] if placeable > 0 else "")
			else:
				var need: String = tt.field.info.get("tool", "hand")
				_prompt.text = "%s %s %s" % [key, {"pick": "Mine", "axe": "Chop"}.get(need, "Gather"), tt.label]
	else:
		var key := "TALK" if touch else "[F]"
		_cross.visible = false
		var verb := "Shop at" if near.has_method("open_shop") else "Open" if near.get("opened") != null \
			else "Use" if near.has_method("open_ledger") else "Talk to"
		_prompt.text = "%s  %s %s" % [key, verb, near.display_name]
	# Target panel follows whatever the player is locked on to.
	var t = player.target if player.locked else null
	_top.visible = t != null
	if t:
		if not _bar.has_meta("target") or t != _bar.get_meta("target"):   # new target: no trail from the last one
			_bar.set_meta("target", t)
			_bar.snap(t.hp, t.max_hp)
		_name_l.text = t.display_name.to_upper()
		_bar.max_value = t.max_hp
		_bar.value = t.hp
	# first time the player gets control on a new game: welcome card pointing at the controls screen
	if player.can_control and _welcome_t < 0.0:
		_welcome_t = 1.5
	elif _welcome_t > 0.0:
		_welcome_t -= delta
		if _welcome_t <= 0.0:
			_welcome_t = 0.0
			controls.show_welcome()


func _on_hurt(amount: int) -> void:
	_hurt_flash.color.a = clampf(0.12 + amount * 0.012, 0.15, 0.4)
	create_tween().tween_property(_hurt_flash, "color:a", 0.0, 0.35)


## Level-up card: "LEVEL UP" pops in with a gold glow, then a line per stat that went up.
func _level_up(lv: int) -> void:
	if _lvl_card:
		_lvl_card.queue_free()
	var card := VBoxContainer.new()
	_lvl_card = card
	card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	card.offset_left = -260
	card.offset_right = 260
	card.offset_top = 200
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", 4)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.get_parent().add_child(card)
	var big := _label("LEVEL UP", 64)
	big.add_theme_color_override("font_color", Color(1.0, 0.86, 0.4))
	big.add_theme_color_override("font_outline_color", Color(0.45, 0.25, 0.0, 0.95))
	big.add_theme_constant_override("outline_size", 14)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(big)
	var sub := _label("Level %d" % lv, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(sub)
	var lines := ["+%d XP" % player.last_xp_gain, "Max HP  %d  →  %d" % [player.max_hp - 12, player.max_hp],
		"Strike +2     Ember +2", "Fully healed"]
	var rows := []
	for l in lines:
		var r := _label(l, 20)
		r.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8))
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		r.modulate.a = 0.0
		card.add_child(r)
		rows.append(r)
	big.pivot_offset = Vector2(260, 40)
	big.scale = Vector2(0.4, 0.4)
	card.modulate.a = 0.0
	var t := card.create_tween()
	t.tween_property(card, "modulate:a", 1.0, 0.15)
	t.parallel().tween_property(big, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in rows.size():
		t.tween_property(rows[i], "modulate:a", 1.0, 0.25).set_delay(0.05)
	t.tween_interval(1.8)
	t.tween_property(card, "modulate:a", 0.0, 0.6)
	t.tween_callback(card.queue_free)


func _show_banner(text: String, col: Color, hold: float) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", col)
	var t := create_tween()
	t.tween_property(_banner, "modulate:a", 1.0, 0.3)
	t.tween_interval(hold)
	t.tween_property(_banner, "modulate:a", 0.0, 0.5)


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
	_title_tween = t
	t.tween_property(_title, "modulate:a", 1.0, 0.8).set_delay(0.6)
	t.tween_interval(maxf(duration - 2.8, 0.5))
	t.tween_property(_title, "modulate:a", 0.0, 0.8)


func hide_title() -> void:
	if _title_tween:
		_title_tween.kill()
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
