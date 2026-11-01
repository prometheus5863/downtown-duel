extends CanvasLayer
## Dialogue + shop panel. Works with mouse, touch (emulated mouse) and number keys (1-9, Esc/F to leave).
## Monsters implement talk_begin() / talk_choose(option) / talk_end(result)  (see enemy.gd).
## Shopkeepers implement open_shop().

const Items := preload("res://scripts/items.gd")

var player: Node
var is_open := false

var _panel: PanelContainer
var _title: Label
var _text: Label
var _opts: VBoxContainer
var _talker: Node
var _mode := ""
var _pending_end := ""
var _buttons: Array = []


func _ready() -> void:
	layer = 8
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.1, 0.92)
	sb.border_color = Color(1, 0.85, 0.4, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -400
	_panel.offset_right = 400
	_panel.offset_bottom = -24
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	_title = _lbl(30, Color(1, 0.85, 0.4))
	v.add_child(_title)
	_text = _lbl(22, Color(0.95, 0.95, 0.95))
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 760
	v.add_child(_text)
	_opts = VBoxContainer.new()
	_opts.add_theme_constant_override("separation", 6)
	v.add_child(_opts)
	_panel.visible = false


# ------------------------------------------------------------------ open / close

func open_for(node: Node) -> void:
	if is_open or not is_instance_valid(node):
		return
	_talker = node
	if node.has_method("talk_begin"):
		_mode = "talk"
		_set_open(true)
		_show(node.talk_begin())
	elif node.has_method("open_shop"):
		_mode = "shop"
		_set_open(true)
		_show_shop(node.get("greeting") if node.get("greeting") else "Welcome!")


func close() -> void:
	if not is_open:
		return
	if _mode == "talk" and is_instance_valid(_talker):
		_talker.talk_end(_pending_end if _pending_end != "" else "leave")
	_pending_end = ""
	_set_open(false)


func _set_open(on: bool) -> void:
	is_open = on
	_panel.visible = on
	player.talking = on
	player.can_control = not on
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if not is_open or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE or event.keycode == KEY_F:
		get_viewport().set_input_as_handled()
		close()
	elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var i: int = event.keycode - KEY_1
		if i < _buttons.size():
			get_viewport().set_input_as_handled()
			_buttons[i].pressed.emit()


# ------------------------------------------------------------------ dialogue

func _show(d: Dictionary) -> void:
	_title.text = d.title
	_text.text = d.text
	_clear()
	if d.end != "":
		_pending_end = d.end
		_add("OK", close)
	elif d.options.is_empty():
		_add("OK", close)
	else:
		for o in d.options:
			_add(o, _choose.bind(o))


func _choose(option: String) -> void:
	if option == "Leave":
		_pending_end = "leave"
		close()
		return
	_show(_talker.talk_choose(option))


# ------------------------------------------------------------------ shop

func _show_shop(status: String) -> void:
	_title.text = _talker.display_name if is_instance_valid(_talker) else "Shop"
	_text.text = "%s\nCoins: %d    ·    Strike %d    Ember %d    Defense %d" % [
		status, player.coins, player.strike_power(), player.ember_power(), player.defense()]
	_clear()
	var stock: Array = _talker.get("stock") if is_instance_valid(_talker) and _talker.get("stock") != null else []
	var cap: int = _talker.get("max_price") if is_instance_valid(_talker) and _talker.get("max_price") != null else 0
	for id in Items.shop_list(stock, cap):
		var it: Dictionary = Items.get_item(id)
		var tag := ""
		if player.gear.get(it.slot, "") == id:
			tag = "EQUIPPED"
		elif id in player.owned:
			tag = "owned · equip"
		else:
			tag = "%d coins" % it.price
		_add("%s  —  %s   [%s]" % [it.name, it.desc, tag], _buy.bind(id))
	_add("Leave", close)


func _buy(id: String) -> void:
	_show_shop(player.buy(id))


# ------------------------------------------------------------------ widgets

func _add(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = "%d.  %s" % [_buttons.size() + 1, text]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 46
	b.add_theme_font_size_override("font_size", 20)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	_opts.add_child(b)
	_buttons.append(b)


func _clear() -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()


func _lbl(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l
