extends RefCounted
## Shared look for every menu: dark glass panels with an accent colour, rounded buttons with a key chip,
## stat rows with green / red deltas. Pure helpers (no state), so menus stay consistent.

const BG := Color(0.055, 0.065, 0.085, 0.9)
const BG_SOFT := Color(1, 1, 1, 0.045)
const TEXT := Color(0.94, 0.94, 0.96)
const DIM := Color(0.66, 0.68, 0.74)
const GOLD := Color(1.0, 0.82, 0.38)
const GOOD := Color(0.45, 0.95, 0.55)
const BAD := Color(1.0, 0.45, 0.4)
const TEAL := Color(0.35, 0.95, 0.85)


static func panel_box(accent: Color, radius := 18, alpha := 0.9) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(BG.r, BG.g, BG.b, alpha)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	sb.set_border_width_all(2)
	sb.border_width_top = 4
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(20)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 18
	return sb


static func card_box(accent: Color, selected := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r, accent.g, accent.b, 0.16) if selected else BG_SOFT
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.9 if selected else 0.18)
	sb.set_border_width_all(2 if selected else 1)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(12)
	return sb


static func panel(accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_box(accent))
	return p


static func label(text: String, size: int, col := TEXT, outline := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline:
		l.add_theme_constant_override("outline_size", maxi(size / 6, 4))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Menu button: left accent stripe, number chip, hover / pressed states.
static func button(text: String, accent: Color, key := "", size := 20) -> Button:
	var b := Button.new()
	b.text = ("  %s   %s" % [key, text]) if key != "" else "  " + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 50
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", DIM)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(12)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.border_width_left = 5
		match state:
			"normal":
				sb.bg_color = BG_SOFT
				sb.border_color = Color(accent.r, accent.g, accent.b, 0.45)
			"hover":
				sb.bg_color = Color(accent.r, accent.g, accent.b, 0.2)
				sb.border_color = accent
			"pressed":
				sb.bg_color = Color(accent.r, accent.g, accent.b, 0.35)
				sb.border_color = accent
			"disabled":
				sb.bg_color = Color(1, 1, 1, 0.02)
				sb.border_color = Color(1, 1, 1, 0.1)
		b.add_theme_stylebox_override(state, sb)
	return b


## Small rounded tag ("320 coins", "EQUIPPED", "Gale").
static func chip(text: String, col: Color, size := 15) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.22)
	sb.border_color = Color(col.r, col.g, col.b, 0.75)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(label(text, size, col.lightened(0.35)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## "Strike   12  →  16  ▲4" style row. new_value == old_value hides the arrow part.
static func stat_row(name: String, old_value: float, new_value: float, fmt := "%d") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var n := label(name, 17, DIM)
	n.custom_minimum_size.x = 110
	h.add_child(n)
	h.add_child(label(fmt % old_value, 17))
	if not is_equal_approx(old_value, new_value):
		var up := new_value > old_value
		h.add_child(label("→", 17, DIM))
		h.add_child(label(fmt % new_value, 17, GOOD if up else BAD))
		h.add_child(label(("▲" if up else "▼") + (fmt % absf(new_value - old_value)), 15, GOOD if up else BAD))
	return h


## Styled bar (fancy_bar.gd): glossy fill, damage trail. `value` / `max_value` like a ProgressBar.
static func bar(value: float, max_value: float, col: Color, width := 200.0, height := 10.0) -> Control:
	var b: Control = preload("res://scripts/fancy_bar.gd").new()
	b.fill_color = col
	b.low_at = 0.0                                    # no low-value pulse for bond / XP style bars
	b.custom_minimum_size = Vector2(width, height)
	b.snap(value, maxf(max_value, 1.0))
	return b


## Square tile showing an icon texture, or a big glyph on a coloured background when there is no icon.
static func icon_tile(tex: Texture2D, glyph: String, col: Color, side := 120.0) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.18)
	sb.border_color = Color(col.r, col.g, col.b, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(side, side)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		r.custom_minimum_size = Vector2(side * 0.7, side * 0.7)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(r)
	else:
		var l := label(glyph, int(side * 0.45), col.lightened(0.4))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(l)
	return p


## Fade + slide a control in from `offset` pixels away (inside a container, which owns its position: fade only).
static func slide_in(c: Control, offset := Vector2(60, 0), t := 0.28) -> void:
	c.modulate.a = 0.0
	if c.get_parent() is Container:
		c.create_tween().tween_property(c, "modulate:a", 1.0, t)
		return
	var target := c.position
	c.position = target + offset
	var tw := c.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, t)
	tw.tween_property(c, "position", target, t)
