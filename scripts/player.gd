extends CharacterBody3D
## Player: movement, camera, lock-on, two attacks, dodge roll (i-frames), HP, death/respawn.

const ProjectileScript := preload("res://scripts/projectile.gd")
const Items := preload("res://scripts/items.gd")
const Avatar := preload("res://scripts/avatar.gd")
const GRAVITY := 20.0

@export var speed := 6.0
@export var lock_range := 25.0          ## max distance for Tab lock-on
var target: Node3D                      ## current lock-on target (nearest enemy)
@export var mouse_sensitivity := 0.004  ## radians per pixel (captured mouse / drag)
@export var key_turn_speed := 2.2        ## rad/s for Q / E
@export var cam_height := 1.0           ## pivot height above player origin
@export var model_scene: PackedScene    ## animation rig (Universal Animation Library), dressed by avatar.gd
@export var wardrobe: Array[PackedScene] = []    ## head, hair and outfit glTFs that armor looks refer to
@export var wardrobe_tex: Array[Texture2D] = []  ## outfit texture variants that armor looks refer to
@export var hair_color := Color(0.28, 0.17, 0.1)

@export_group("Strike (J)")
@export var strike_damage := 10
@export var strike_cooldown := 0.4
@export_group("Ember (K)")
@export var ember_damage := 15
@export var ember_cooldown := 1.0
@export_group("Dodge (Space)")
@export var roll_time := 0.5
@export var roll_speed := 11.0
@export var dodge_cooldown := 0.7
@export var iframe_start := 0.04            ## i-frames from this many s into the roll...
@export var iframe_end := 0.42              ## ...until this many s
@export_group("Health")
@export var max_hp := 100
@export var regen_delay := 5.0              ## s without damage before regen
@export var regen_rate := 6.0               ## hp/s

signal hp_changed(hp: int, max_hp: int)
signal progress_changed                  ## level / xp / coins / gear / route counters changed
signal leveled_up(level: int)
signal interact_requested(node: Node)
signal hurt(amount: int)
signal dodged
signal died

@onready var cam_pivot: Node3D = $CamPivot
@onready var spring_arm: SpringArm3D = $CamPivot/SpringArm3D
@onready var camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var melee_hitbox: Area3D = $MeleeHitbox
@onready var swipe: MeshInstance3D = $MeleeHitbox/Swipe

var locked := false
var can_control := true                 ## turned off during the intro flyover
var touch_mode := false                 ## set by touch_controls.gd on phones/tablets
var cooldowns := {"strike": 0.0, "ember": 0.0, "dodge": 0.0}
var hp := 100.0
var alive := true
var spawn_point := Vector3.ZERO

# --- progression -------------------------------------------------------
var level := 1
var xp := 0
var coins := 0
var gear := Items.STARTER.duplicate()
var owned: Array = ["wood_knuckles", "cloth_tunic"]
var route := {"defeated": 0, "spared": 0, "friends": 0}
var followers: Array = []
const MAX_FOLLOWERS := 3
var talking := false                    ## dialogue / shop open
var _queued_attack := ""                # LMB/RMB while mouse-captured
var _roll_t := -1.0                     # time since roll start (-1 = not rolling)
var _roll_dir := Vector3.ZERO
var _knock_v := Vector3.ZERO
var _since_hurt := 99.0
var _shake := 0.0
var _anim: AnimationPlayer
var _act_t := 0.0                       # attack animation lock
var _jab := false
var _model: Node3D
var _parts := {}                        # wardrobe basename -> resource


func _ready() -> void:
	# Camera must not inherit player rotation, otherwise turning the player
	# turns the camera that defines "forward" -> spiralling controls.
	cam_pivot.top_level = true
	cam_pivot.global_position = global_position + Vector3.UP * cam_height
	# Stop the spring arm from colliding with our own capsule.
	spring_arm.add_excluded_object(get_rid())
	swipe.visible = false
	add_to_group("player")
	hp = max_hp
	spawn_point = global_position
	if model_scene:
		$Body.visible = false
		$Nose.visible = false
		var m: Node3D = model_scene.instantiate()
		m.position.y = -1.0              # origin is capsule centre; feet at -1
		m.rotation.y = PI                # model faces +Z, we move along -Z
		add_child(m)
		_anim = _find_anim(m)
		_model = m
		for r in wardrobe + wardrobe_tex:
			if r:
				_parts[r.resource_path.get_file().get_basename()] = r
		refresh_look()


func _unhandled_input(event: InputEvent) -> void:
	if not can_control:
		return
	# Desktop: click to capture the mouse (mouse-look), Esc to release.
	if event is InputEventMouseButton and event.pressed:
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		if captured and event.button_index == MOUSE_BUTTON_LEFT:
			_queued_attack = "strike"
		elif captured and event.button_index == MOUSE_BUTTON_RIGHT:
			_queued_attack = "ember"
		elif event.button_index == MOUSE_BUTTON_LEFT and not touch_mode and not talking:
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
	var rolling := _roll_t >= 0.0
	if can_control and alive and not rolling:
		if Input.is_action_just_pressed("dodge") and cooldowns.dodge == 0.0:
			_start_roll()
			rolling = true
	if can_control and alive and not rolling:
		if Input.is_action_just_pressed("lock_on"):
			if locked:
				locked = false
			else:
				target = _nearest_enemy()
				locked = target != null
		if (Input.is_action_just_pressed("attack_strike") or _queued_attack == "strike") and cooldowns.strike == 0.0:
			_strike()
		if (Input.is_action_just_pressed("attack_ember") or _queued_attack == "ember") and cooldowns.ember == 0.0:
			_ember()
		if Input.is_action_just_pressed("interact"):
			var n := nearest_interactable()
			if n:
				interact_requested.emit(n)
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var turn := Input.get_axis("cam_left", "cam_right")
		if turn != 0.0:
			rotate_camera(Vector2(turn * key_turn_speed * delta, 0.0))

	_queued_attack = ""
	# --- Movement, relative to camera yaw ---
	var b := cam_pivot.global_transform.basis
	var dir := b.x * input.x + b.z * input.y
	dir.y = 0.0
	dir = dir.normalized()

	var spd := speed * (1.0 + Items.stat(gear, "speed"))
	velocity.x = dir.x * spd + _knock_v.x
	velocity.z = dir.z * spd + _knock_v.z
	_knock_v = _knock_v.move_toward(Vector3.ZERO, 30.0 * delta)
	if rolling:
		_roll_t += delta
		velocity.x = _roll_dir.x * roll_speed
		velocity.z = _roll_dir.z * roll_speed
		if _roll_t >= roll_time:
			_roll_t = -1.0
	_since_hurt += delta
	if alive and _since_hurt > regen_delay and hp < max_hp:
		hp = minf(hp + (regen_rate + Items.stat(gear, "regen")) * delta, max_hp)
		hp_changed.emit(int(hp), max_hp)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()

	_act_t = maxf(_act_t - delta, 0.0)
	if _act_t == 0.0 and alive and _roll_t < 0.0:
		_play("Jog_Fwd" if Vector2(velocity.x, velocity.z).length() > 0.1 else "Idle")

	# --- Facing: rolling -> roll dir, locked -> target, free -> movement ---
	if _roll_t >= 0.0:
		_face(_roll_dir)
	elif not alive:
		pass
	elif locked:
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
		if body != self and body.has_method("take_damage") and not body.get("friend"):
			body.take_damage(strike_power(), -global_transform.basis.z)
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
	p.damage = ember_power()
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

# ---------------------------------------------------------------- dodge / damage

func _start_roll() -> void:
	cooldowns.dodge = maxf(dodge_cooldown - Items.stat(gear, "dodge_cd"), 0.1) + roll_time
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var b := cam_pivot.global_transform.basis
	_roll_dir = (b.x * input.x + b.z * input.y) * Vector3(1, 0, 1)
	if _roll_dir.length() < 0.1:
		_roll_dir = -global_transform.basis.z * Vector3(1, 0, 1)   # no input: roll forward
	_roll_dir = _roll_dir.normalized()
	_roll_t = 0.0
	_act_t = 0.0
	if _anim and _anim.has_animation("Roll"):
		_play("Roll", false, _anim.get_animation("Roll").length / roll_time)


# ---------------------------------------------------------------- progression

func strike_power() -> int:
	return strike_damage + (level - 1) * 2 + int(Items.stat(gear, "atk"))


func ember_power() -> int:
	return ember_damage + (level - 1) * 2 + int(Items.stat(gear, "ember"))


func defense() -> int:
	return int(Items.stat(gear, "def"))


func xp_to_next() -> int:
	return 30 + level * 25


## Called by monsters when defeated / spared.
func reward(xp_gain: int, coin_gain: int, kind: String) -> void:
	if route.has(kind):
		route[kind] += 1
	coins += coin_gain
	xp += xp_gain
	var txt := "+%d XP" % xp_gain + ("   +%d coins" % coin_gain if coin_gain > 0 else "")
	_popup(txt, Color(0.6, 1.0, 0.5) if kind == "spared" else Color(1.0, 0.85, 0.3))
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		max_hp += 12
		hp = max_hp
		hp_changed.emit(int(hp), max_hp)
		leveled_up.emit(level)
	progress_changed.emit()


func route_name() -> String:
	if route.defeated == 0 and route.spared + route.friends > 0:
		return "Pacifist"
	if route.defeated >= 8 and route.spared + route.friends == 0:
		return "Hunter"
	return "Balanced"


func buy(id: String) -> String:
	var it := Items.get_item(id)
	if it.is_empty():
		return "Unknown item."
	if id in owned:
		equip(id)
		return "Equipped %s." % it.name
	if coins < it.price:
		return "Not enough coins (%d / %d)." % [coins, it.price]
	coins -= it.price
	owned.append(id)
	equip(id)
	return "Bought and equipped %s!" % it.name


func equip(id: String) -> void:
	var it := Items.get_item(id)
	if it.is_empty() or not (id in owned):
		return
	gear[it.slot] = id
	if it.slot == "armor":
		refresh_look()
	progress_changed.emit()


## Re-dress the character for the equipped armor.
func refresh_look() -> void:
	if _model == null:
		return
	var look: Dictionary = Items.get_item(gear.armor).get("look", {})
	var names := ["Superhero_Male_Head"]
	if not look.get("hood", false):
		names.append("Hair_SimpleParted")
	names.append_array(look.get("parts", ["Male_Peasant"]))
	var parts := []
	for n in names:
		if _parts.has(n):
			parts.append(_parts[n])
	Avatar.dress(_model, {"parts": parts, "tex": _parts.get(look.get("tex", "")), "tint": look.get("tint", Color.WHITE),
			"metal": look.get("metal", 0.0), "hair": hair_color})


func spend(amount: int) -> bool:
	if coins < amount:
		return false
	coins -= amount
	progress_changed.emit()
	return true


func add_follower(e: Node) -> bool:
	if followers.size() >= MAX_FOLLOWERS:
		return false
	followers.append(e)
	route.friends += 1
	progress_changed.emit()
	return true


func nearest_interactable(max_dist := 3.2) -> Node:
	var best: Node = null
	var best_d := max_dist
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.has_method("can_interact") and not n.can_interact():
			continue
		var d := global_position.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func is_invulnerable() -> bool:
	return _roll_t >= iframe_start and _roll_t <= iframe_end


## Returns true if the hit landed, false if dodged / ignored.
func take_damage(amount: int, from_dir: Vector3) -> bool:
	if not alive or not can_control:
		return false
	if is_invulnerable():
		dodged.emit()
		_popup("DODGE!", Color(0.4, 0.9, 1.0))
		return false
	amount = maxi(amount - int(Items.stat(gear, "def")), 1)
	hp = maxf(hp - amount, 0.0)
	_since_hurt = 0.0
	hp_changed.emit(int(hp), max_hp)
	hurt.emit(amount)
	_shake = maxf(_shake, 0.3)
	_knock_v = from_dir.normalized() * 7.0 * Vector3(1, 0, 1)
	if hp <= 0.0:
		_die()
	else:
		_act_t = _play("Hit_Chest", false, 1.4) * 0.6
	return true


func _die() -> void:
	alive = false
	locked = false
	_roll_t = -1.0
	died.emit()
	_play("Death01", false)
	await get_tree().create_timer(2.8).timeout
	global_position = spawn_point
	velocity = Vector3.ZERO
	_knock_v = Vector3.ZERO
	hp = max_hp
	alive = true
	_since_hurt = 99.0
	hp_changed.emit(int(hp), max_hp)
	_play("Idle")


func _popup(text: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.outline_size = 12
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	get_parent().add_child(l)
	l.global_position = global_position + Vector3(0, 1.6, 0)
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "position:y", l.position.y + 0.8, 0.5)
	t.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.15)
	t.chain().tween_callback(l.queue_free)


func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var best_d := lock_range
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.get("alive") == false or e.get("friend"):
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
