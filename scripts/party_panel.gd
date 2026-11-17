extends VBoxContainer
## HUD party cards: element badge, name, level, HP bar and state for each active companion, plus the current
## party command and its keys. Rebuilt when the party changes; bars update every frame.

const Data := preload("res://scripts/data.gd")
const COMMAND_LABEL := {"attack": "Attack", "follow": "Follow", "hold": "Hold", "heel": "Return"}

var player: Node
var touch := false
var _rows: Array = []                 # [companion, ProgressBar, Label]
var _cmd: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	player.party_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_rows.clear()
	_cmd = null
	if player.party.is_empty():
		return
	for c in player.party:
		if not is_instance_valid(c):
			continue
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		var badge := Label.new()                  # element badge: coloured tile with the element's initial
		badge.text = Data.element_name(c.element).left(1)
		badge.custom_minimum_size = Vector2(26, 26)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 16)
		badge.add_theme_color_override("font_color", Color(0.08, 0.08, 0.1))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Data.element_color(c.element)
		sb.set_corner_radius_all(6)
		badge.add_theme_stylebox_override("normal", sb)
		badge.tooltip_text = Data.element_name(c.element)
		row.add_child(badge)
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_theme_constant_override("separation", 1)
		var name_l := _label(15)
		col.add_child(name_l)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(170, 9)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.35, 0.8, 0.95)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.55)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", bg)
		col.add_child(bar)
		row.add_child(col)
		add_child(row)
		_rows.append([c, bar, name_l])
	_cmd = _label(14)
	add_child(_cmd)
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	for r in _rows:
		var c = r[0]
		if not is_instance_valid(c):
			continue
		r[1].max_value = c.max_hp
		r[1].value = c.hp
		r[2].text = "%s  Lv %d%s" % [c.display_name, c.level, "  · exhausted" if c.exhausted else ""]
		r[2].modulate = Color(0.65, 0.65, 0.7) if c.exhausted else Color.WHITE
	if _cmd:
		var keys := "" if touch else "    1 Attack · 2 Follow · 3 Hold · 4 Return"
		_cmd.text = "Party: %s%s" % [COMMAND_LABEL.get(player.party_command, "Follow").to_upper(), keys]


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
