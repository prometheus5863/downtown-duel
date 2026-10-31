extends CanvasLayer
## On-screen controls for phones/tablets (multi-touch):
##   left 40% of screen  -> floating joystick (move)
##   rest of screen      -> drag to turn the camera
##   buttons             -> Strike / Ember / Lock (TouchScreenButton = true multi-touch)
## Also: portrait warning overlay and lighter graphics for mobile GPUs.

var player: Node

const JOY_R := 110.0
const KNOB_R := 46.0
const CAM_SENS := 0.007

var _joy_id := -1
var _joy_origin := Vector2.ZERO
var _cam_id := -1
var _cam_last := Vector2.ZERO
var _joy_base: Sprite2D
var _joy_knob: Sprite2D
var _buttons: Array = []           # [TouchScreenButton, radius, anchor_fn]
var _portrait: Control


func _ready() -> void:
	layer = 5
	player.touch_mode = true
	_joy_base = _sprite(JOY_R, Color(1, 1, 1, 0.16))
	_joy_knob = _sprite(KNOB_R, Color(1, 1, 1, 0.5))
	_add_button("attack_strike", "STRIKE", 72, Color(1.0, 0.85, 0.3), func(s): return Vector2(s.x - 140, s.y - 150))
	_add_button("attack_ember", "EMBER", 58, Color(1.0, 0.5, 0.15), func(s): return Vector2(s.x - 300, s.y - 105))
	_add_button("dodge", "DODGE", 54, Color(0.4, 1.0, 0.7), func(s): return Vector2(s.x - 270, s.y - 250))
	_add_button("lock_on", "LOCK", 46, Color(0.5, 0.8, 1.0), func(s): return Vector2(s.x - 115, s.y - 315))
	_add_button("interact", "TALK", 50, Color(0.6, 1.0, 0.6), func(s): return Vector2(s.x - 260, s.y - 390))

	_portrait = ColorRect.new()
	_portrait.color = Color(0, 0, 0, 0.85)
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	var msg := Label.new()
	msg.text = "Rotate your phone to landscape to play"
	msg.add_theme_font_size_override("font_size", 44)
	msg.set_anchors_preset(Control.PRESET_FULL_RECT)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	_portrait.add_child(msg)
	add_child(_portrait)

	get_viewport().size_changed.connect(_layout)
	_layout()
	_lighten_graphics()


func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	for b in _buttons:
		var c: Vector2 = b[2].call(s)
		b[0].position = c - Vector2(b[1], b[1])
		b[0].set_meta("center", c)
	_reset_joystick()
	_portrait.visible = s.y > s.x


func _process(_delta: float) -> void:
	# Menus open: hide pads so taps reach the dialogue buttons. TALK only when something is near.
	var menu_open: bool = player.talking
	for b in _buttons:
		if b[0].action == "interact":
			b[0].visible = not menu_open and player.can_control and player.nearest_interactable() != null
		else:
			b[0].visible = not menu_open
	_joy_base.visible = not menu_open
	_joy_knob.visible = not menu_open


func _input(event: InputEvent) -> void:
	if player.talking:
		if _joy_id != -1:
			_joy_id = -1
			_set_move(Vector2.ZERO)
		_cam_id = -1
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _hits_button(event.position):
				return                                   # TouchScreenButton handles it
			var s := get_viewport().get_visible_rect().size
			if event.position.x < s.x * 0.4 and _joy_id == -1:
				_joy_id = event.index
				_joy_origin = event.position
				_joy_base.position = _joy_origin
				_joy_knob.position = _joy_origin
			elif _cam_id == -1:
				_cam_id = event.index
				_cam_last = event.position
		else:
			if event.index == _joy_id:
				_joy_id = -1
				_set_move(Vector2.ZERO)
				_reset_joystick()
			elif event.index == _cam_id:
				_cam_id = -1
	elif event is InputEventScreenDrag:
		if event.index == _joy_id:
			var v: Vector2 = (event.position - _joy_origin).limit_length(JOY_R)
			_joy_knob.position = _joy_origin + v
			_set_move(v / JOY_R)
		elif event.index == _cam_id:
			player.rotate_camera((event.position - _cam_last) * CAM_SENS)
			_cam_last = event.position


func _set_move(v: Vector2) -> void:
	_axis("move_right", "move_left", v.x)
	_axis("move_back", "move_forward", v.y)


func _axis(pos_action: String, neg_action: String, value: float) -> void:
	if value > 0.05:
		Input.action_press(pos_action, value)
		Input.action_release(neg_action)
	elif value < -0.05:
		Input.action_press(neg_action, -value)
		Input.action_release(pos_action)
	else:
		Input.action_release(pos_action)
		Input.action_release(neg_action)


func _hits_button(p: Vector2) -> bool:
	for b in _buttons:
		if not b[0].visible:
			continue
		if p.distance_to(b[0].get_meta("center")) <= b[1] * 1.1:
			return true
	return false


func _reset_joystick() -> void:
	var s := get_viewport().get_visible_rect().size
	_joy_base.position = Vector2(170, s.y - 160)
	_joy_knob.position = _joy_base.position


func _add_button(action: String, text: String, r: float, col: Color, anchor: Callable) -> void:
	var b := TouchScreenButton.new()
	b.texture_normal = _circle(int(r), Color(col.r, col.g, col.b, 0.35))
	b.texture_pressed = _circle(int(r), Color(col.r, col.g, col.b, 0.75))
	var shape := CircleShape2D.new()
	shape.radius = r
	b.shape = shape
	b.shape_centered = true
	b.action = action
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(r * 0.34))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.size = Vector2(r * 2, r * 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(l)
	add_child(b)
	_buttons.append([b, r, anchor])


func _sprite(r: float, col: Color) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _circle(int(r), col)
	add_child(s)
	return s


func _circle(r: int, col: Color) -> ImageTexture:
	var img := Image.create(r * 2, r * 2, false, Image.FORMAT_RGBA8)
	for y in r * 2:
		for x in r * 2:
			var d := Vector2(x - r + 0.5, y - r + 0.5).length()
			var a := clampf(r - d, 0.0, 1.0)
			var rim := 1.0 if d > r - 4.0 else 0.6       # brighter rim
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * a * rim))
	return ImageTexture.create_from_image(img)


func _lighten_graphics() -> void:
	# Phones: no real-time shadows, render 3D at 75% resolution.
	var sun := get_tree().root.find_child("Sun", true, false)
	if sun:
		sun.shadow_enabled = false
	get_viewport().scaling_3d_scale = 0.75
