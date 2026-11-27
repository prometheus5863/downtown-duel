extends SubViewportContainer
## Little 3D stage for menus: its own world with a soft light, a turntable and a camera. Shows either the
## hero wearing a given armor (`show_look`) or any model scene (`show_model`). Drag to spin it; otherwise it
## turns slowly by itself. Processes while the game is paused (the character menu pauses).

const Avatar := preload("res://scripts/avatar.gd")

var player: Node
var spin_speed := 0.5
var _vp: SubViewport
var _turn: Node3D
var _cam: Camera3D
var _drag := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.66)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.5, 0.6, 0)
	key.light_energy = 1.2
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(-0.3, PI + 0.4, 0)
	rim.light_color = Color(0.6, 0.8, 1.0)
	rim.light_energy = 0.7
	_vp.add_child(rim)
	_turn = Node3D.new()
	_vp.add_child(_turn)
	_cam = Camera3D.new()
	_cam.fov = 32
	_vp.add_child(_cam)
	_frame(1.8)


func _process(delta: float) -> void:
	if not _drag:
		_turn.rotation.y += spin_speed * delta


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
	elif event is InputEventMouseMotion and _drag:
		_turn.rotation.y += event.relative.x * 0.012


func clear() -> void:
	for c in _turn.get_children():
		_turn.remove_child(c)
		c.queue_free()


## The hero wearing the armor `armor_id` (or what they wear now when "").
func show_look(armor_id := "") -> void:
	clear()
	if player == null or player.model_scene == null:
		return
	var m: Node3D = player.model_scene.instantiate()
	_turn.add_child(m)
	Avatar.dress(m, player.look_for(armor_id if armor_id != "" else player.gear.armor))
	_loop(m, ["Idle"])
	_frame(1.85)


## Any model (a creature) scaled to fit a `height` m tall frame.
func show_model(scene: PackedScene, height := 1.5, idle: Array = ["Idle", "Flying_Idle"]) -> void:
	clear()
	if scene == null:
		return
	var m: Node3D = scene.instantiate()
	_turn.add_child(m)
	_loop(m, idle)
	_frame(maxf(height, 0.6) * 1.35)


func _frame(h: float) -> void:
	# Camera far enough back that something h m tall fills ~85 % of the view height.
	var dist := (h * 0.6) / tan(deg_to_rad(_cam.fov * 0.5))
	_cam.position = Vector3(0, h * 0.55, dist)
	_cam.look_at(Vector3(0, h * 0.5, 0), Vector3.UP)


func _loop(m: Node, names: Array) -> void:
	for ap in m.find_children("*", "AnimationPlayer", true, false):
		for n in names:
			if ap.has_animation(n):
				ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
				ap.play(n)
				ap.process_mode = Node.PROCESS_MODE_ALWAYS
				return
