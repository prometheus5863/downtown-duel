extends CharacterBody3D
## Monster / training dummy.
##  - Optional animated model (Quaternius monsters): idle, walk, hit, death clips are
##    found by name so any monster in the packs works without per-model setup.
##  - Simple brain: idle -> wander around home -> notice player (face + react).
##  - Takes damage: flash, knockback, damage number, hit/death animation, respawn.
## Origin sits on the floor; `height` sizes the collider and the aim point.

signal health_changed(hp: int, max_hp: int)
signal died

@export var display_name := "Training Dummy"
@export var color := Color(0.85, 0.2, 0.2)       ## capsule colour when no model
@export var max_hp := 100
@export var respawn_time := 4.0
@export var model_scene: PackedScene
@export var model_scale := 1.0
@export var height := 2.0                         ## collider height (m)
@export var radius := 0.5                         ## collider radius (m)
@export var wander_radius := 6.0                  ## 0 = stays put (training dummies)
@export var move_speed := 2.0
@export var notice_range := 9.0
@export var is_boss := false

const GRAVITY := 20.0
const IDLE := ["Idle", "Flying_Idle", "Idle_Loop"]
const WALK := ["Walk", "Fast_Flying", "Run", "Walk_Loop"]
const HIT := ["HitRecieve", "HitReact", "Hit_Chest"]
const DEATH := ["Death", "Death01"]
const REACT := ["Yes", "Bite_Front", "Punch", "Headbutt", "Dance"]

var hp := 0
var alive := true
var home := Vector3.ZERO

var _visual: Node3D
var _anim: AnimationPlayer
var _meshes: Array[MeshInstance3D] = []
var _base_mat := StandardMaterial3D.new()
var _flash_mat := StandardMaterial3D.new()
var _state := "idle"
var _state_t := 0.0
var _goal := Vector3.ZERO
var _busy_t := 0.0          # hit/react animation lock
var _noticed := false
var _player: Node3D


func _ready() -> void:
	add_to_group("enemy")
	hp = max_hp
	home = global_position
	_flash_mat.albedo_color = Color.WHITE
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color.WHITE

	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(height, radius * 2.0)
	$Collision.shape = shape
	$Collision.position.y = shape.height * 0.5

	if model_scene:
		$Mesh.visible = false
		_visual = model_scene.instantiate()
		_visual.scale = Vector3.ONE * model_scale
		add_child(_visual)
		_collect(_visual)
		_play(IDLE)
	else:
		_visual = $Mesh
		_visual.position.y = height * 0.5
		_base_mat.albedo_color = color
		$Mesh.material_override = _base_mat
		_meshes = [$Mesh]
	_visual.rotation.y = randf() * TAU
	_state_t = randf_range(1.0, 4.0)


func aim_point() -> Vector3:
	return global_position + Vector3.UP * height * 0.55


# ------------------------------------------------------------------ brain

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	_busy_t = maxf(_busy_t - delta, 0.0)
	_state_t -= delta

	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	var near := _player != null and global_position.distance_to(_player.global_position) < notice_range

	var move := Vector3.ZERO
	if _busy_t > 0.0:
		pass
	elif near and wander_radius > 0.0:
		# Notice the player: turn to face, little reaction the first time.
		_face(_player.global_position - global_position, delta * 6.0)
		if not _noticed:
			_noticed = true
			_busy_t = _play(REACT, false)
		else:
			_play(IDLE)
	else:
		_noticed = _noticed and near
		if wander_radius <= 0.0:
			pass
		elif _state == "idle":
			_play(IDLE)
			if _state_t <= 0.0:
				var a := randf() * TAU
				_goal = home + Vector3(cos(a), 0, sin(a)) * randf_range(1.0, wander_radius)
				_state = "walk"
				_state_t = 6.0
		elif _state == "walk":
			var to := _goal - global_position
			to.y = 0.0
			if to.length() < 0.4 or _state_t <= 0.0:
				_state = "idle"
				_state_t = randf_range(2.0, 5.0)
			else:
				move = to.normalized() * move_speed
				_face(to, delta * 5.0)
				_play(WALK)

	velocity.x = move.x
	velocity.z = move.z
	move_and_slide()


func _face(dir: Vector3, weight: float) -> void:
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var target_yaw := atan2(dir.x, dir.z)       # models face +Z
	_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, clampf(weight, 0.0, 1.0))


# ------------------------------------------------------------------ combat

func take_damage(amount: int, from_dir: Vector3) -> void:
	if not alive:
		return
	hp = maxi(hp - amount, 0)
	health_changed.emit(hp, max_hp)
	_flash()
	_knock(from_dir)
	_popup(amount)
	if _player:
		_face(_player.global_position - global_position, 1.0)
	if hp == 0:
		_die()
	else:
		_busy_t = maxf(_play(HIT, false), 0.25)
		if _anim == null:
			_wobble()


func _flash() -> void:
	for m in _meshes:
		m.material_override = _flash_mat
	await get_tree().create_timer(0.08, true, false, true).timeout
	for m in _meshes:
		m.material_override = _base_mat if m == $Mesh else null


func _knock(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var home_pos := _visual.position
	var t := create_tween()
	t.tween_property(_visual, "position", home_pos + dir.normalized() * 0.35, 0.05)
	t.tween_property(_visual, "position", home_pos, 0.15)


func _wobble() -> void:
	var t := create_tween()
	t.tween_property(_visual, "rotation:x", -0.25, 0.06)
	t.tween_property(_visual, "rotation:x", 0.12, 0.12)
	t.tween_property(_visual, "rotation:x", 0.0, 0.15)


func _popup(amount: int) -> void:
	var l := Label3D.new()
	l.text = str(amount)
	l.font_size = 72
	l.outline_size = 14
	l.modulate = Color(1.0, 0.9, 0.2)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	get_parent().add_child(l)
	l.global_position = global_position + Vector3(randf_range(-0.3, 0.3), height + 0.4, 0.0)
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "position:y", l.position.y + 1.0, 0.6)
	t.tween_property(l, "modulate:a", 0.0, 0.6)
	t.chain().tween_callback(l.queue_free)


func _die() -> void:
	alive = false
	died.emit()
	$Collision.set_deferred("disabled", true)
	var dur := _play(DEATH, false)
	await get_tree().create_timer(maxf(dur, 0.2) + 0.6).timeout
	visible = false
	await get_tree().create_timer(respawn_time).timeout
	global_position = home
	hp = max_hp
	alive = true
	visible = true
	_state = "idle"
	_state_t = 1.0
	_play(IDLE)
	$Collision.set_deferred("disabled", false)
	health_changed.emit(hp, max_hp)


# ------------------------------------------------------------------ animation

## Plays the first clip in `names` this model has. Returns its length (0 if none).
func _play(names: Array, loop := true) -> float:
	if _anim == null:
		return 0.0
	for n in names:
		if _anim.has_animation(n):
			if _anim.current_animation != n or not loop:
				var a := _anim.get_animation(n)
				a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
				_anim.play(n, 0.15)
			return _anim.get_animation(n).length
	return 0.0


func _collect(n: Node) -> void:
	if n is MeshInstance3D:
		_meshes.append(n)
	if n is AnimationPlayer and _anim == null:
		_anim = n
	for c in n.get_children():
		_collect(c)
