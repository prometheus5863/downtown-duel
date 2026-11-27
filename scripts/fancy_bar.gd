extends Control
## Styled bar used everywhere (HP, target, party, bond, XP): rounded dark frame, glossy two-tone fill,
## a "damage trail" that shows what was just lost and drains after a beat, a low-value pulse, and optional text.
## Set `value` / `max_value` like a ProgressBar; the fill eases to it on its own.

@export var max_value := 100.0
@export var value := 100.0
@export var fill_color := Color(0.35, 0.9, 0.45)
@export var low_color := Color(1.0, 0.3, 0.25)        ## the fill blends towards this below `low_at`
@export var low_at := 0.3
@export var trail_color := Color(1.0, 0.85, 0.55, 0.85)
@export var show_text := false
@export var text_prefix := ""
@export var font_size := 13
@export var ticks := 0                                ## divider lines (e.g. 4 = quarters)

var _shown := -1.0                                     # eased fill value
var _trail := -1.0                                     # damage trail value
var _trail_hold := 0.0
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(200, 12)


## Jump straight to a value without animating (first show).
func snap(v: float, mx := -1.0) -> void:
	if mx > 0.0:
		max_value = mx
	value = v
	_shown = v
	_trail = v
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _shown < 0.0:
		_shown = value
		_trail = value
	var before := Vector2(_shown, _trail)
	if value < _shown:                                   # damage: fill drops fast, trail waits then drains
		if _trail < _shown:
			_trail = _shown
		_shown = move_toward(_shown, value, max_value * 3.0 * delta)
		_trail_hold = 0.45
	else:                                                # heal: fill eases up, no trail
		_shown = move_toward(_shown, value, max_value * 1.2 * delta)
	_trail_hold -= delta
	if _trail_hold <= 0.0:
		_trail = move_toward(_trail, _shown, max_value * 0.9 * delta)
	_trail = maxf(_trail, _shown)
	var low := max_value > 0.0 and value / max_value <= low_at and value > 0.0
	if before != Vector2(_shown, _trail) or low:
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var rad := int(minf(size.y * 0.5, 8.0))
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.02, 0.03, 0.05, 0.78)
	frame.border_color = Color(1, 1, 1, 0.16)
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(rad)
	frame.shadow_color = Color(0, 0, 0, 0.35)
	frame.shadow_size = 4
	draw_style_box(frame, r)
	var inner := r.grow(-2.0)
	var mx := maxf(max_value, 0.001)
	var ratio := clampf(_shown / mx, 0.0, 1.0)
	var trail := clampf(_trail / mx, 0.0, 1.0)
	var irad := maxi(rad - 2, 1)
	if trail > ratio + 0.002:
		_pill(Rect2(inner.position, Vector2(inner.size.x * trail, inner.size.y)), trail_color, irad)
	if ratio > 0.0:
		var col := fill_color
		var frac := clampf(value / mx, 0.0, 1.0)
		if frac <= low_at:
			var pulse := 0.5 + 0.5 * sin(_t * 7.0)
			col = fill_color.lerp(low_color, 0.65 + 0.35 * pulse)
		var fr := Rect2(inner.position, Vector2(maxf(inner.size.x * ratio, irad * 2.0), inner.size.y))
		_pill(fr, col.darkened(0.12), irad)
		# gloss: lighter upper half
		_pill(Rect2(fr.position, Vector2(fr.size.x, fr.size.y * 0.48)), col.lightened(0.35) * Color(1, 1, 1, 0.55), irad)
		# bright cap at the end of the fill
		if ratio < 0.995 and fr.size.x > 4.0:
			draw_rect(Rect2(fr.end.x - 2.0, fr.position.y + 1.0, 2.0, fr.size.y - 2.0), col.lightened(0.6) * Color(1, 1, 1, 0.9))
	for i in range(1, ticks):
		var x := inner.position.x + inner.size.x * float(i) / ticks
		draw_line(Vector2(x, inner.position.y + 1), Vector2(x, inner.end.y - 1), Color(0, 0, 0, 0.35), 1.0)
	if show_text and size.y >= 12.0:
		var font := get_theme_default_font()
		var txt := "%s%d / %d" % [text_prefix, int(round(value)), int(round(max_value))]
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var pos := Vector2((size.x - w) * 0.5, size.y * 0.5 + font_size * 0.36)
		draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.85))
		draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.95))


func _pill(rect: Rect2, col: Color, rad: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(mini(rad, int(rect.size.y * 0.5)))
	draw_style_box(sb, rect)
