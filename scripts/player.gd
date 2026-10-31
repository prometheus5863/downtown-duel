extends CharacterBody3D
## Arena player: movement, lock-on, two attacks, hit feedback.
##   WASD move · Tab lock-on · J strike (melee) · K ember (projectile) · RMB-drag orbit

const ProjectileScript := preload("res://scripts/projectile.gd")
const GRAVITY := 20.0

@export var speed := 6.0
@export var lock_range := 25.0          ## max distance for Tab lock-on
var target: Node3D                      ## current lock-on target (nearest enemy)
@export var mouse_sensitivity := 0.004  ## radians per pixel (captured mouse / drag)
@export var key_turn_speed := 2.2        ## rad/s for Q / E
@export var cam_height := 1.0           ## pivot height above player origin
@export var model_scene: PackedScene    ## animated character (Universal Animation Library)

@export_group("Strike (J)")
@export var strike_damage := 10
@export var strike_cooldown := 0.4
@export_group("Ember (K)")
@export var ember_damage := 15
@export var ember_cooldown := 1.0

@onready var cam_pivot: Node3D = $CamPivot
@onready var spring_arm: SpringArm3D = $CamPivot/SpringArm3D
@onready var camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var melee_hitbox: Area3D = $MeleeHitbox
@onready var swipe: MeshInstance3D = $MeleeHitbox/Swipe

var locked := false
var can_control := true                 ## turned off during the intro flyover
var touch_mode := false                 ## set by touch_controls.gd on phones/tablets
var cooldowns := {"strike": 0.0, "ember": 0.0}
var _shake := 0.0
var _anim: AnimationPlayer
var _act_t := 0.0                       # attack animation lock
var _jab := false


func _ready() -> void:
	# Camera must not inherit player rotation, otherwise turning the player
	# turns the camera that defines "forward" -> spiralling controls.
	cam_pivot.top_level = true
	cam_pivot.global_position = global_position + Vector3.UP * cam_height
	# Stop the spring arm from colliding with our own capsule.
	spring_arm.add_excluded_object(get_rid())
	swipe.visible = false
	add_to_group("player")
	if model_scene:
		$Body.visible = false
		$Nose.visible = false
		var m: Node3D = model_scene.instantiate()
		m.position.y = -1.0              # origin is capsule centre; feet at -1
		m.rotation.y = PI                # model faces +Z, we move along -Z
		add_child(m)
		_anim = _find_anim(m)


func _unhandled_input(event: InputEvent) -> void:
	if not can_control:
		return
	# Desktop: click to capture the mouse (mouse-look), Esc to release.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not touch_mode \
				and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_camera(-0.8)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_camera(0.8)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_camera(event.relative * mouse_sensitivity)


## Turn the camera. delta.x = yaw, delta.y = pitch (radians). Used by mouse and touch.
func rotate_camera(d: Vector2) -> void:
	if not locked:                       # while locked the camera tracks the target
		cam_pivot.rotate_y(-d.x)
	spring_arm.rotation.x = clampf(spring_arm.rotation.x - d.y, -1.2, 0.15)


func zoom_camera(amount: float) -> void:
	spring_arm.spring_length = clampf(spring_arm.spring_length + amount, 3.0, 12.0)


func _physics_process(delta: float) -> void:
	for k in cooldowns:
		cooldowns[k] = maxf(cooldowns[k] - delta, 0.0)

	# Drop lock if the target died / was removed.
	if locked and not _target_alive():
		locked = false

	var input := Vector2.ZERO
	if can_control:
		if Input.is_action_just_pressed("lock_on"):
			if locked:
				locked = false
			else:
				target = _nearest_enemy()
				locked = target != null
		if Input.is_action_just_pressed("attack_strike") and cooldowns.strike == 0.0:
			_strike()
		if Input.is_action_just_pressed("attack_ember") and cooldowns.ember == 0.0:
			_ember()
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var turn := Input.get_axis("cam_left", "cam_right")
		if turn != 0.0:
			rotate_camera(Vector2(turn * key_turn_speed * delta, 0.0))

	# --- Movement, relative to camera yaw ---
	var b := cam_pivot.global_transform.basis
	var dir := b.x * input.x + b.z * input.y
	dir.y = 0.0
	dir = dir.normalized()

	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()

	_act_t = maxf(_act_t - delta, 0.0)
	if _act_t == 0.0:
		_play("Jog_Fwd" if Vector2(velocity.x, velocity.z).length() > 0.1 else "Idle")

	# --- Facing: locked -> face target, free -> face movement ---
	if locked:
		_face(target.global_position - global_position)
	elif dir.length() > 0.0:
		_face(dir)

	# --- Camera follow; when locked, swing to keep target in frame ---
	cam_pivot.global_position = global_position + Vector3.UP * cam_height
	if locked:
		var aim := target.global_position
		aim.y = cam_pivot.global_position.y
		if cam_pivot.global_position.distance_to(aim) > 0.01:
			cam_pivot.look_at(aim, Vector3.UP)


func _process(delta: float) -> void:
	# Screen shake decays every frame (uses real time so hit-stop doesn't freeze it).
	camera.h_offset = randf_range(-1.0, 1.0) * _shake
	camera.v_offset = randf_range(-1.0, 1.0) * _shake
	_shake = move_toward(_shake, 0.0, 1.5 * delta / maxf(Engine.time_scale, 0.05))


# ---------------------------------------------------------------- attacks

func _strike() -> void:
	cooldowns.strike = strike_cooldown
	_jab = not _jab
	_act_t = _play("Punch_Jab" if _jab else "Punch_Cross", false, 1.6) * 0.6
	_flash_swipe()
	for body in melee_hitbox.get_overlapping_bodies():
		if body != self and body.has_method("take_damage"):
			body.take_damage(strike_damage, -global_transform.basis.z)
			_on_hit(0.25, 0.07)


func _ember() -> void:
	cooldowns.ember = ember_cooldown
	_act_t = _play("Spell_Simple_Shoot", false, 1.5) * 0.5
	var dir := -global_transform.basis.z
	if locked:
		var aim: Vector3 = target.aim_point() if target.has_method("aim_point") else target.global_position
		dir = (aim - global_position).normalized()
	var p: Area3D = ProjectileScript.new()
	p.shooter = self
	p.direction = dir
	p.damage = ember_damage
	get_parent().add_child(p)
	p.global_position = global_position + dir * 0.9
	p.hit.connect(_on_hit.bind(0.15, 0.04))


func _on_hit(shake: float, stop_time: float) -> void:
	_shake = maxf(_shake, shake)
	# Hit-stop: nearly freeze time for a few frames so the impact "lands".
	Engine.time_scale = 0.05
	await get_tree().create_timer(stop_time, true, false, true).timeout
	Engine.time_scale = 1.0


func _flash_swipe() -> void:
	swipe.visible = true
	await get_tree().create_timer(0.08).timeout
	swipe.visible = false


# ---------------------------------------------------------------- helpers

func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var best_d := lock_range
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.get("alive") == false:
			continue
		var d := global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _target_alive() -> bool:
	return is_instance_valid(target) and target.get("alive") != false


func _play(anim_name: String, loop := true, speed := 1.0) -> float:
	if _anim == null or not _anim.has_animation(anim_name):
		return 0.0
	var a := _anim.get_animation(anim_name)
	if loop:
		if _anim.current_animation == anim_name:
			return a.length
		a.loop_mode = Animation.LOOP_LINEAR
	else:
		a.loop_mode = Animation.LOOP_NONE
	_anim.play(anim_name, 0.12, speed)
	if not loop:
		_anim.seek(0.0, true)
	return a.length / speed


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r:
			return r
	return null


func _face(v: Vector3) -> void:
	v.y = 0.0
	if v.length() > 0.01:
		look_at(global_position + v, Vector3.UP)
