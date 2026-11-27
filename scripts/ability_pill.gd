extends Control
## Cooldown pill for the HUD: key chip + ability name, the pill fills up as the ability recharges and glows
## when it's ready. `cooldown` is read every frame from a callable; the full length is learned from the jump
## when the ability is used.

@export var title := "Strike"
@export var key := "J"
@export var color := Color(1.0, 0.82, 0.38)
var read_cooldown: Callable                          ## () -> float seconds remaining

var _full := 0.0
var _left := 0.0
var _t := 0.0
var _flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(132, 34)


func _process(delta: float) -> void:
	_t += delta
	var left: float = read_cooldown.call() if read_cooldown.is_valid() else 0.0
	if left > _left + 0.05:                              # just used: remember how long a full recharge is
		_full = left
	if _left > 0.0 and left <= 0.0:
		_flash = 1.0                                     # ready again
	_left = left
	_flash = maxf(_flash - delta * 2.5, 0.0)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var rad := int(size.y * 0.5)
	var ready := _left <= 0.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.04, 0.06, 0.78)
	bg.border_color = Color(color.r, color.g, color.b, 0.85 if ready else 0.25)
	bg.set_border_width_all(2 if ready else 1)
	bg.set_corner_radius_all(rad)
	if ready:
		bg.shadow_color = Color(color.r, color.g, color.b, 0.25 + 0.35 * _flash)
		bg.shadow_size = int(4 + 8 * _flash)
	draw_style_box(bg, r)
	if not ready and _full > 0.0:
		var p := clampf(1.0 - _left / _full, 0.0, 1.0)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(color.r, color.g, color.b, 0.28)
		fill.set_corner_radius_all(rad - 2)
		draw_style_box(fill, Rect2(Vector2(2, 2), Vector2(maxf((size.x - 4) * p, rad), size.y - 4)))
	elif ready:
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(color.r, color.g, color.b, 0.16 + 0.1 * sin(_t * 2.5) + 0.3 * _flash)
		glow.set_corner_radius_all(rad - 2)
		draw_style_box(glow, r.grow(-2))
	var font := get_theme_default_font()
	var tx := 14.0
	if key != "":                                        # key chip (desktop only)
		tx = _key_chip(font, ready) + 8.0
	var label := title if ready else "%.1fs" % _left
	var col := Color(1, 1, 1, 0.95) if ready else Color(1, 1, 1, 0.6)
	draw_string_outline(font, Vector2(tx, size.y * 0.5 + 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 3, Color(0, 0, 0, 0.7))
	draw_string(font, Vector2(tx, size.y * 0.5 + 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)


## Draws the round key chip; returns its right edge.
func _key_chip(font: Font, ready: bool) -> float:
	var chip := Rect2(Vector2(5, 5), Vector2(size.y - 10, size.y - 10))
	var cb := StyleBoxFlat.new()
	cb.bg_color = Color(color.r, color.g, color.b, 0.9 if ready else 0.35)
	cb.set_corner_radius_all(int(chip.size.y * 0.5))
	draw_style_box(cb, chip)
	var kw := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, Vector2(chip.position.x + (chip.size.x - kw) * 0.5, chip.position.y + chip.size.y * 0.5 + 5),
		key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.05, 0.05, 0.08) if ready else Color(1, 1, 1, 0.8))
	return chip.end.x
