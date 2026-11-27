extends CanvasLayer
## Character menu (C, or ME on phones). Pauses the game. Left: the hero on a turntable (drag to spin), level and XP.
## Right, three tabs: Gear (stats + every owned item per slot, click to equip, the preview follows),
## Party (companion cards with their own 3D model, HP, XP, skills) and Bag (inventory grid with counts).

const UI := preload("res://scripts/ui_style.gd")
const Data := preload("res://scripts/data.gd")
const Items := preload("res://scripts/items.gd")
const Preview := preload("res://scripts/preview_3d.gd")

var player: Node
var is_open := false
var tab := "gear"

var _root: Control
var _hero: SubViewportContainer
var _level_l: Label
var _xp_bar: ProgressBar
var _xp_l: Label
var _coins_l: Label
var _tabs := {}
var _body: VBoxContainer


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	# --- left: hero ---
	var left := UI.panel(UI.GOLD)
	left.anchor_bottom = 1.0
	left.offset_left = 24
	left.offset_top = 24
	left.offset_right = 404
	left.offset_bottom = -24
	_root.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	left.add_child(lv)
	lv.add_child(UI.label("HERO", 30, UI.GOLD))
	_level_l = UI.label("", 20)
	lv.add_child(_level_l)
	_xp_bar = UI.bar(0, 1, UI.GOLD, 330, 12)
	lv.add_child(_xp_bar)
	_xp_l = UI.label("", 15, UI.DIM)
	lv.add_child(_xp_l)
	_hero = Preview.new()
	_hero.player = player
	_hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero.custom_minimum_size = Vector2(330, 300)
	_hero.spin_speed = 0.35
	lv.add_child(_hero)
	lv.add_child(UI.label("drag to turn", 13, UI.DIM))
	_coins_l = UI.label("", 18, UI.GOLD)
	lv.add_child(_coins_l)

	# --- right: tabs ---
	var right := UI.panel(UI.GOLD)
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = 424
	right.offset_top = 24
	right.offset_right = -24
	right.offset_bottom = -24
	_root.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 12)
	right.add_child(rv)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	rv.add_child(bar)
	for t in [["gear", "Gear", "1"], ["party", "Party", "2"], ["bag", "Bag", "3"]]:
		var b := UI.button(t[1], UI.GOLD, t[2], 19)
		b.custom_minimum_size = Vector2(150, 46)
		b.pressed.connect(show_tab.bind(t[0]))
		bar.add_child(b)
		_tabs[t[0]] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var x := UI.button("Close", UI.DIM, "C", 18)
	x.custom_minimum_size = Vector2(130, 46)
	x.pressed.connect(close)
	bar.add_child(x)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	scroll.add_child(_body)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("character_menu") or (is_open and event is InputEventKey and event.pressed
			and event.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		if is_open:
			close()
		else:
			open()
	elif is_open and event is InputEventKey and event.pressed and not event.echo:
		var tabs := {KEY_1: "gear", KEY_2: "party", KEY_3: "bag"}
		if tabs.has(event.keycode):
			show_tab(tabs[event.keycode])


func open() -> void:
	if is_open or not player.can_control or player.talking or not player.alive:
		return
	is_open = true
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_hero()
	show_tab(tab)
	_root.modulate.a = 0.0
	_root.create_tween().tween_property(_root, "modulate:a", 1.0, 0.18)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	_hero.clear()
	get_tree().paused = false


func _refresh_hero() -> void:
	_hero.show_look()
	_level_l.text = "Level %d   ·   %s route" % [player.level, player.route_name()]
	_xp_bar.max_value = player.xp_to_next()
	_xp_bar.value = player.xp
	_xp_l.text = "XP %d / %d" % [player.xp, player.xp_to_next()]
	_coins_l.text = "%d coins" % player.coins


func show_tab(t: String) -> void:
	tab = t
	for k in _tabs:
		_tabs[k].add_theme_stylebox_override("normal", UI.card_box(UI.GOLD, k == t))
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	match t:
		"gear":
			_gear_tab()
		"party":
			_party_tab()
		"bag":
			_bag_tab()


# ------------------------------------------------------------------ gear

func _gear_tab() -> void:
	var s: Dictionary = player.stats_with({})
	var stats := GridContainer.new()
	stats.columns = 3
	stats.add_theme_constant_override("h_separation", 12)
	stats.add_theme_constant_override("v_separation", 12)
	_body.add_child(stats)
	for row in [["Health", "%d / %d" % [int(player.hp), player.max_hp], UI.GOOD], ["Strike", str(s.strike), UI.GOLD],
			["Ember", str(s.ember), Color(1.0, 0.55, 0.25)], ["Defense", str(s.defense), Color(0.6, 0.8, 1.0)],
			["Speed", "+%d%%" % int(s.speed * 100), UI.TEAL], ["Dodge", "%.2f s" % maxf(player.dodge_cooldown - Items.stat(player.gear, "dodge_cd"), 0.1), UI.TEAL]]:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UI.card_box(row[2]))
		card.custom_minimum_size = Vector2(180, 0)
		var v := VBoxContainer.new()
		v.add_child(UI.label(row[0], 14, UI.DIM))
		v.add_child(UI.label(row[1], 26, row[2]))
		card.add_child(v)
		stats.add_child(card)
	for slot in ["weapon", "armor", "charm"]:
		_body.add_child(UI.label(slot.capitalize(), 20, UI.GOLD))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 10)
		_body.add_child(flow)
		var any := false
		for id in player.owned:
			var it := Items.get_item(id)
			if it.get("slot", "") != slot:
				continue
			any = true
			var on: bool = player.gear.get(slot, "") == id
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(220, 74)
			b.text = "%s\n%s" % [it.name, it.desc]
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 15)
			for st in ["normal", "hover", "pressed"]:
				b.add_theme_stylebox_override(st, UI.card_box(UI.GOOD if on else UI.GOLD, on or st != "normal"))
			b.tooltip_text = "Equipped" if on else "Click to equip"
			b.pressed.connect(_equip.bind(id))
			flow.add_child(b)
		if not any:
			flow.add_child(UI.label("Nothing yet — shops and chests have them.", 15, UI.DIM))


func _equip(id: String) -> void:
	player.equip(id)
	_refresh_hero()
	show_tab("gear")


# ------------------------------------------------------------------ party

func _party_tab() -> void:
	if player.party.is_empty():
		_body.add_child(UI.label("No companions yet. Befriend creatures with pets and treats (F to talk).", 18, UI.DIM))
	for c in player.party:
		if not is_instance_valid(c):
			continue
		var col := Data.element_color(c.element)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UI.card_box(col, true))
		_body.add_child(card)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		card.add_child(h)
		var pv := Preview.new()
		pv.custom_minimum_size = Vector2(150, 150)
		h.add_child(pv)
		var sp := Data.creature(c.species)            # the preview shows the model unscaled: frame its native height
		pv.show_model.call_deferred(c.model_scene, float(sp.get("height", 1.4)) / maxf(float(sp.get("scale", 0.6)), 0.01))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		top.add_child(UI.label(c.display_name, 24, col.lightened(0.3)))
		top.add_child(UI.chip(Data.element_name(c.element), col))
		top.add_child(UI.chip("Lv %d" % c.level, UI.DIM))
		if c.is_alpha:
			top.add_child(UI.chip("♛ Alpha", UI.GOLD))
		if c.exhausted:
			top.add_child(UI.chip("exhausted", UI.BAD))
		v.add_child(top)
		var hp := HBoxContainer.new()
		hp.add_theme_constant_override("separation", 8)
		hp.add_child(UI.label("HP", 15, UI.DIM))
		hp.add_child(UI.bar(c.hp, c.max_hp, UI.GOOD, 260, 10))
		hp.add_child(UI.label("%d / %d" % [c.hp, c.max_hp], 15))
		v.add_child(hp)
		var xp := HBoxContainer.new()
		xp.add_theme_constant_override("separation", 8)
		xp.add_child(UI.label("XP", 15, UI.DIM))
		xp.add_child(UI.bar(int(c.record.get("xp", 0)), Data.xp_to_next(c.level), UI.GOLD, 260, 8))
		v.add_child(xp)
		var moves: Array = Data.creature(c.species).get("moves", []).map(func(m): return Data.move(m).get("name", m))
		v.add_child(UI.label("Moves: %s   ·   Attack %d" % [", ".join(moves), c.attack_damage], 15, UI.TEXT))
		var skills: Array = Data.creature(c.species).get("skills", [])
		v.add_child(UI.label("Work: %s   ·   loves %s treats" % [", ".join(skills), c.favourite_flavour()], 15, UI.DIM))
	if player.storage.size() > 0:
		_body.add_child(UI.label("%d more waiting at the Creature Ledger." % player.storage.size(), 16, UI.DIM))


# ------------------------------------------------------------------ bag

func _bag_tab() -> void:
	if player.inventory.is_empty():
		_body.add_child(UI.label("Your bag is empty.", 18, UI.DIM))
		return
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	var order := []
	for table in ["tools", "treats", "materials"]:
		for id in player.inventory:
			if Data.rows(table).has(id):
				order.append([table, id])
	for e in order:
		var id: String = e[1]
		var tex: Texture2D = null
		var glyph := "◆"
		var col := UI.TEAL
		match e[0]:
			"tools":
				tex = player.icon_for(Data.rows("tools")[id].get("icon", ""))
				col = UI.GOLD
			"treats":
				glyph = "♥"
				col = Color(1.0, 0.55, 0.7)
			_:
				var ore := {"iron_ore": "ore_iron", "silver_ore": "ore_silver", "gold_ore": "ore_gold", "crystal": "ore_diamond",
					"berries": "apple", "herbs": "seed", "mushroom": "seed", "wood": "", "stone": ""}
				tex = player.icon_for(ore.get(id, ""))
				glyph = {"wood": "▤", "stone": "■", "dirt": "■"}.get(id, "◆")
		var cell := VBoxContainer.new()
		cell.custom_minimum_size = Vector2(120, 0)
		cell.add_theme_constant_override("separation", 4)
		var tile := UI.icon_tile(tex, glyph, col, 96)
		cell.add_child(tile)
		var n := UI.label(player.item_name(id), 14)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.custom_minimum_size.x = 110
		cell.add_child(n)
		cell.add_child(UI.label("× %d" % player.item_count(id), 16, col.lightened(0.3)))
		grid.add_child(cell)
