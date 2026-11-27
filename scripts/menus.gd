extends CanvasLayer
## Dialogue, shop and Creature Ledger panel, with a cinematic camera (talk_cam.gd) that frames whoever you talk to.
## Works with mouse, touch (emulated mouse) and keys: 1-9 pick an option (in shops: select an item),
## Enter / Space buys the selected item, Esc / F leaves.
## Monsters implement talk_begin() / talk_choose(option) / talk_end(result)  (see enemy.gd).
## Shopkeepers implement open_shop(). The Creature Ledger implements open_ledger() (party <-> storage, rest).

const Items := preload("res://scripts/items.gd")
const Data := preload("res://scripts/data.gd")
const UI := preload("res://scripts/ui_style.gd")
const Preview := preload("res://scripts/preview_3d.gd")
const TalkCam := preload("res://scripts/talk_cam.gd")

var player: Node
var is_open := false
var cam: Camera3D                      ## talk_cam.gd, lives in the 3D world next to the player

var _root: Control
var _panel: PanelContainer
var _portrait: PanelContainer
var _portrait_slot: Control
var _title: Label
var _chips: HBoxContainer
var _bond_row: HBoxContainer
var _bond_bar: ProgressBar
var _bond_l: Label
var _text: Label
var _detail: VBoxContainer             # shop: selected item card
var _list_scroll: ScrollContainer
var _opts: VBoxContainer
var _talker: Node
var _mode := ""
var _pending_end := ""
var _buttons: Array = []
var _accent := UI.GOLD
var _shop_rows: Array = []             # [kind, id] per shop row button, same order as _buttons
var _selected := -1
var _preview: SubViewportContainer
var _relax_t: SceneTreeTimer
var _hidden_tags: Array = []


func _ready() -> void:
	layer = 8
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = UI.panel(_accent)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -560
	_panel.offset_right = -24
	_panel.offset_top = 24
	_panel.offset_bottom = -24
	_root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	_portrait_slot = Control.new()
	_portrait_slot.custom_minimum_size = Vector2(78, 78)
	head.add_child(_portrait_slot)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 6)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	_title = UI.label("", 30, UI.GOLD)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(_title)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 6)
	hv.add_child(_chips)

	_bond_row = HBoxContainer.new()
	_bond_row.add_theme_constant_override("separation", 10)
	_bond_row.add_child(UI.label("Bond", 17, UI.DIM))
	_bond_bar = UI.bar(0, 100, Color(1.0, 0.45, 0.65), 300, 12)
	_bond_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bond_row.add_child(_bond_bar)
	_bond_l = UI.label("", 17, Color(1.0, 0.7, 0.8))
	_bond_row.add_child(_bond_l)
	v.add_child(_bond_row)

	_text = UI.label("", 21)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_text)

	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 8)
	v.add_child(_detail)

	_list_scroll = ScrollContainer.new()
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_list_scroll)
	_opts = VBoxContainer.new()
	_opts.add_theme_constant_override("separation", 7)
	_opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_opts)
	_panel.visible = false

	cam = TalkCam.new()
	cam.player = player
	player.get_parent().add_child.call_deferred(cam)


# ------------------------------------------------------------------ open / close

func open_for(node: Node) -> void:
	if is_open or not is_instance_valid(node):
		return
	_talker = node
	_hidden_tags.clear()
	for c in node.get_children():                  # the speaker's floating name tag would loom over the shot
		if c is Label3D and c.visible:
			c.visible = false
			_hidden_tags.append(c)
	if node is Node3D:
		var to: Vector3 = (node as Node3D).global_position - player.global_position
		player._face(to)
		if cam.is_inside_tree():
			cam.focus(node)
	if node.has_method("talk_begin"):
		_mode = "talk"
		_set_open(true)
		_show(node.talk_begin())
	elif node.has_method("open_ledger"):
		_mode = "ledger"
		_set_open(true)
		_show_ledger("Your companions rest here. Swap who travels with you (party of %d)." % player.MAX_PARTY)
	elif node.has_method("open_shop"):
		_mode = "shop"
		_selected = -1
		_set_open(true)
		_show_shop(node.get("greeting") if node.get("greeting") else "Welcome!")


func close() -> void:
	if not is_open:
		return
	if _mode == "talk" and is_instance_valid(_talker):
		_talker.talk_end(_pending_end if _pending_end != "" else "leave")
	_pending_end = ""
	for c in _hidden_tags:
		if is_instance_valid(c):
			c.visible = true
	_hidden_tags.clear()
	if cam.is_inside_tree():
		cam.release()
	_set_open(false)


func _set_open(on: bool) -> void:
	is_open = on
	_panel.visible = on
	player.talking = on
	player.can_control = not on
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		UI.slide_in(_panel, Vector2(80, 0))


func _input(event: InputEvent) -> void:
	if not is_open or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE or event.keycode == KEY_F:
		get_viewport().set_input_as_handled()
		close()
	elif _mode == "shop" and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE or event.keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		_buy_selected()
	elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var i: int = event.keycode - KEY_1
		if i < _buttons.size():
			get_viewport().set_input_as_handled()
			_buttons[i].pressed.emit()


# ------------------------------------------------------------------ header

func _header(title: String, accent: Color, glyph: String, chips: Array, tex: Texture2D = null) -> void:
	_accent = accent
	_fit(_mode == "shop")
	_panel.add_theme_stylebox_override("panel", UI.panel_box(accent))
	_title.text = title
	_title.add_theme_color_override("font_color", accent.lightened(0.25))
	if _portrait:
		_portrait.queue_free()
	_portrait = UI.icon_tile(tex, glyph, accent, 78)
	_portrait_slot.add_child(_portrait)
	for c in _chips.get_children():
		c.queue_free()
	for ch in chips:
		_chips.add_child(UI.chip(ch[0], ch[1]))


func _say(text: String) -> void:
	_text.text = text
	_text.visible_ratio = 0.0
	var t := _text.create_tween()
	t.tween_property(_text, "visible_ratio", 1.0, clampf(text.length() / 90.0, 0.15, 0.7))


## Full-height panel (shops) or one that hugs its content from the top (dialogue, ledger).
func _fit(full: bool) -> void:
	_panel.anchor_bottom = 1.0 if full else 0.0
	_panel.offset_bottom = -24 if full else 24
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL if full else Control.SIZE_FILL
	_list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if full else ScrollContainer.SCROLL_MODE_DISABLED
	_panel.reset_size.call_deferred()


# ------------------------------------------------------------------ dialogue

func _show(d: Dictionary) -> void:
	_clear_detail()
	var t := _talker
	if t and t.get("species") != null and t.get("element") != null:
		var col := Data.element_color(t.element)
		var chips := [[Data.element_name(t.element), col], ["Lv %d" % int(t.level), UI.DIM]]
		if t.get("is_alpha"):
			chips.append(["♛ Alpha", UI.GOLD])
		if t.get("lustre"):
			chips.append(["✦ Lustre", Color(1.0, 0.82, 0.35)])
		if t.has_method("is_hostile") and not t.is_dummy():
			chips.append(["hostile", UI.BAD] if t.is_hostile() else ["calm", UI.GOOD])
		_header(d.title, col, Data.element_name(t.element).left(1), chips)
		_bond_row.visible = not t.is_dummy()
		_set_bond(int(t.bond))
	else:
		_header(d.title, UI.GOLD, "?", [])
		_bond_row.visible = false
	# the bond line is drawn as a bar, so drop it from the text
	var lines := Array(String(d.text).split("\n")).filter(func(l): return not l.begins_with("Bond "))
	_say("\n".join(lines))
	_clear()
	if d.end != "":
		_pending_end = d.end
		_add("OK", close)
	elif d.options.is_empty():
		_add("OK", close)
	else:
		for o in d.options:
			_add(o, _choose.bind(o))


func _set_bond(b: int) -> void:
	var tw := _bond_bar.create_tween()
	tw.tween_property(_bond_bar, "value", float(b), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_bond_l.text = "%d / 100" % b


func _choose(option: String) -> void:
	if option == "Leave":
		_pending_end = "leave"
		close()
		return
	var bond_before: int = int(_talker.get("bond")) if _talker.get("bond") != null else 0
	var d: Dictionary = _talker.talk_choose(option)
	var gained: int = (int(_talker.bond) - bond_before) if _talker.get("bond") != null else 0
	# Pets and treats: push the camera in and let the creature react, then ease back out.
	if (option == "Pet it" or option.begins_with("Give ")) and _talker.has_method("react_affection"):
		_talker.react_affection(gained, option.begins_with("Give ") and String(d.text).contains("favourite"))
		_close_up_for(1.6)
	if d.end == "friend" and _talker.has_method("react_affection"):
		_talker.react_affection(30, true)
		_close_up_for(2.2)
	_show(d)


func _close_up_for(t: float) -> void:
	if not cam.is_inside_tree():
		return
	cam.close_up()
	_relax_t = get_tree().create_timer(t)
	var me := _relax_t
	_relax_t.timeout.connect(func():
		if me == _relax_t and is_open:
			cam.relax())


# ------------------------------------------------------------------ shop

func _show_shop(status: String) -> void:
	var stock: Array = _talker.get("stock") if is_instance_valid(_talker) and _talker.get("stock") != null else []
	var cap: int = _talker.get("max_price") if is_instance_valid(_talker) and _talker.get("max_price") != null else 0
	_header(_talker.display_name if is_instance_valid(_talker) else "Shop", UI.GOLD, "⚖",
		[["%d coins" % player.coins, UI.GOLD], ["shop", UI.DIM]])
	_bond_row.visible = false
	_say(status)
	_clear()
	_shop_rows.clear()
	for id in Data.table("treats"):
		var tr: Dictionary = Data.table("treats")[id]
		if "treat" in stock and int(tr.price) > 0 and (cap == 0 or int(tr.price) <= cap):
			_add_row(tr.name, "%d" % tr.price, ["treat", id], "have %d" % player.item_count(id))
	for id in Data.rows("tools"):
		var tl: Dictionary = Data.rows("tools")[id]
		if "tool" in stock and int(tl.price) > 0 and (cap == 0 or int(tl.price) <= cap):
			_add_row(tl.name, "owned" if player.item_count(id) > 0 else "%d" % tl.price, ["tool", id])
	for id in Items.shop_list(stock, cap):
		var it: Dictionary = Items.get_item(id)
		var tag := "EQUIPPED" if player.gear.get(it.slot, "") == id else "owned" if id in player.owned else "%d" % it.price
		_add_row(it.name, tag, ["gear", id])
	_add("Leave", close)
	if _shop_rows.is_empty():
		_clear_detail()
	else:
		_select(clampi(_selected, 0, _shop_rows.size() - 1))


func _add_row(name: String, tag: String, row: Array, note := "") -> void:
	var i := _buttons.size()
	var b := UI.button(name + ("   ·   " + note if note != "" else ""), UI.GOLD, str(i + 1) if i < 9 else "", 18)
	b.custom_minimum_size.y = 44
	var c := UI.chip(tag + (" coins" if tag.is_valid_int() else ""), UI.GOLD if tag.is_valid_int() else UI.TEAL, 14)
	b.add_child(c)
	c.anchor_top = 0.5
	c.anchor_bottom = 0.5
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.offset_left = -110
	c.offset_right = -10
	c.offset_top = -13
	c.offset_bottom = 13
	b.pressed.connect(_on_row.bind(i))
	b.mouse_entered.connect(func(): _select(i))
	_opts.add_child(b)
	_buttons.append(b)
	_shop_rows.append(row)


func _on_row(i: int) -> void:
	if i == _selected:
		_buy_selected()                       # second tap / click on the selected row buys it
	else:
		_select(i)


func _select(i: int) -> void:
	if i < 0 or i >= _shop_rows.size() or i == _selected and _detail.get_child_count() > 0:
		return
	_selected = i
	for k in _shop_rows.size():
		_buttons[k].add_theme_stylebox_override("normal", UI.card_box(UI.GOLD, k == i))
	_build_detail(_shop_rows[i])


func _clear_detail() -> void:
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	_preview = null


## Detail card for the selected shop item: preview, description, stat changes if you equip it, price, Buy.
func _build_detail(row: Array) -> void:
	_clear_detail()
	var kind: String = row[0]
	var id: String = row[1]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.card_box(UI.GOLD, true))
	_detail.add_child(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	card.add_child(h)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name := ""
	var desc := ""
	var price := 0
	var owned := false
	match kind:
		"gear":
			var it := Items.get_item(id)
			name = it.name
			desc = it.desc
			price = int(it.price)
			owned = id in player.owned
			if it.slot == "armor":
				_preview = Preview.new()
				_preview.player = player
				_preview.custom_minimum_size = Vector2(150, 190)
				h.add_child(_preview)
				_preview.show_look.call_deferred(id)
			else:
				h.add_child(UI.icon_tile(null, "⚔" if it.slot == "weapon" else "✦", UI.GOLD, 120))
			var now: Dictionary = player.stats_with({})
			var then: Dictionary = player.stats_with({it.slot: id})
			info.add_child(UI.label(it.slot.capitalize() + "  ·  if you equip it:", 15, UI.DIM))
			for k in [["Strike", "strike"], ["Ember", "ember"], ["Defense", "defense"]]:
				if now[k[1]] != then[k[1]] or k[1] == {"weapon": "strike", "armor": "defense", "charm": "ember"}[it.slot]:
					info.add_child(UI.stat_row(k[0], now[k[1]], then[k[1]]))
			if now.speed != then.speed:
				info.add_child(UI.stat_row("Speed", now.speed * 100, then.speed * 100, "%d%%"))
		"tool":
			var tl: Dictionary = Data.rows("tools")[id]
			name = tl.name
			price = int(tl.price)
			owned = player.item_count(id) > 0
			desc = "Tier %d %s. %s" % [tl.tier, "pickaxe" if tl.kind == "pick" else "axe",
				"Breaks ores up to tier %d." % tl.tier if tl.kind == "pick" else "Fells trees faster."]
			h.add_child(UI.icon_tile(player.icon_for(tl.get("icon", "")), "⛏", UI.GOLD, 120))
			info.add_child(UI.stat_row("Tool tier", player.best_tool(tl.kind).tier, maxi(player.best_tool(tl.kind).tier, int(tl.tier))))
		"treat":
			var tr: Dictionary = Data.table("treats")[id]
			name = tr.name
			desc = tr.desc
			price = int(tr.price)
			var fcol: Color = {"sweet": Color(1.0, 0.55, 0.75), "spicy": Color(1.0, 0.45, 0.25), "savory": Color(0.95, 0.75, 0.4),
				"sour": Color(0.7, 1.0, 0.4), "bitter": Color(0.55, 0.8, 0.55)}.get(tr.flavour, UI.GOLD)
			h.add_child(UI.icon_tile(null, "♥", fcol, 120))
			info.add_child(UI.label("%s  ·  %s" % [String(tr.tier).capitalize() + " treat", String(tr.flavour).capitalize()], 16, fcol))
			info.add_child(UI.label("+%d bond  (×2 for creatures who love %s)" % [tr.bond, tr.flavour], 16, UI.TEXT))
			info.add_child(UI.label("You have %d" % player.item_count(id), 15, UI.DIM))
	h.add_child(info)
	var title := UI.label(name, 24, UI.GOLD)
	info.add_child(title)
	info.move_child(title, 0)
	var d := UI.label(desc, 16, UI.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(d)
	info.move_child(d, 1)
	var buy_text := ""
	if kind == "gear" and player.gear.get(Items.get_item(id).slot, "") == id:
		buy_text = "Equipped"
	elif kind == "gear" and owned:
		buy_text = "Equip"
	elif kind == "tool" and owned:
		buy_text = "Owned"
	else:
		buy_text = "Buy  ·  %d coins" % price
	var b := UI.button(buy_text, UI.GOOD if player.coins >= price or owned else UI.BAD, "⏎", 19)
	b.disabled = buy_text in ["Equipped", "Owned"]
	b.pressed.connect(_buy_selected)
	info.add_child(b)
	if not owned and player.coins < price:
		info.add_child(UI.label("You need %d more coins" % (price - player.coins), 15, UI.BAD))
	UI.slide_in(card, Vector2(0, 14), 0.2)


func _buy_selected() -> void:
	if _selected < 0 or _selected >= _shop_rows.size():
		return
	var row: Array = _shop_rows[_selected]
	match row[0]:
		"gear":
			_buy(row[1])
		"tool":
			_buy_tool(row[1])
		"treat":
			_buy_treat(row[1])


func _buy_tool(id: String) -> void:
	var tl: Dictionary = Data.table("tools")[id]
	if player.item_count(id) > 0:
		_refresh_shop("You already have a %s." % tl.name)
	elif player.spend(int(tl.price)):
		player.add_item(id, 1)
		_refresh_shop("Bought a %s." % tl.name)
	else:
		_refresh_shop("Not enough coins (%d / %d)." % [player.coins, tl.price])


func _buy_treat(id: String) -> void:
	var tr: Dictionary = Data.table("treats")[id]
	if player.spend(int(tr.price)):
		player.add_item(id, 1)
		_refresh_shop("Bought a %s." % tr.name)
	else:
		_refresh_shop("Not enough coins (%d / %d)." % [player.coins, tr.price])


func _buy(id: String) -> void:
	_refresh_shop(player.buy(id))


## Rebuild the shop after a purchase, keeping the same item selected.
func _refresh_shop(status: String) -> void:
	var keep := _selected
	_selected = -1
	_show_shop(status)
	if keep >= 0 and keep < _shop_rows.size():
		_select(keep)


# ------------------------------------------------------------------ creature ledger

func _show_ledger(status: String) -> void:
	_clear_detail()
	_header("Creature Ledger", UI.TEAL, "✎", [["Party %d / %d" % [player.party.size(), player.MAX_PARTY], UI.TEAL],
		["Storage %d" % player.storage.size(), UI.DIM]])
	_bond_row.visible = false
	_say(status)
	_clear()
	_add("Rest  —  heal everyone, revive exhausted companions", _ledger_rest)
	for i in player.party.size():
		var c: Node = player.party[i]
		_add("Store  %s  ·  Lv %d %s  ·  HP %d / %d" % [c.display_name, c.level, Data.element_name(c.element), c.hp, c.max_hp],
			_ledger_store.bind(i))
	if player.party.size() < player.MAX_PARTY:
		for i in mini(player.storage.size(), 8 - _buttons.size()):
			var r: Dictionary = player.storage[i]
			var sp := Data.creature(r.get("species", ""))
			_add("Take  %s  ·  Lv %d %s" % [r.get("name", "?"), int(r.get("level", 1)), Data.element_name(sp.get("element", ""))],
				_ledger_take.bind(i))
	_add("Leave", close)


func _ledger_rest() -> void:
	player.rest()
	var game := get_tree().get_first_node_in_group("game")
	if game:
		game.save()
	_show_ledger("You feel rested. Everyone is back on their feet.")


func _ledger_store(i: int) -> void:
	var n: String = player.party[i].display_name
	player.deposit(i)
	_show_ledger("%s will wait here for you." % n)


func _ledger_take(i: int) -> void:
	var n: String = player.storage[i].get("name", "?")
	_show_ledger("%s joins your party." % n if player.withdraw(i) else "Your party is full.")


# ------------------------------------------------------------------ widgets

func _add(text: String, cb: Callable) -> void:
	var i := _buttons.size()
	var b := UI.button(text, UI.DIM if text in ["Leave", "OK"] else _accent, str(i + 1) if i < 9 else "")
	b.pressed.connect(cb)
	_opts.add_child(b)
	_buttons.append(b)
	UI.slide_in(b, Vector2(30, 0), 0.18 + 0.04 * i)


func _clear() -> void:
	for b in _buttons:
		_opts.remove_child(b)
		b.queue_free()
	_buttons.clear()
