extends CharacterBody3D
## Monster / training dummy.
##  - Optional animated model (Quaternius monsters): idle, walk, hit, death clips are
##    found by name so any monster in the packs works without per-model setup.
##  - Brain: idle -> wander -> notice player. Hostile monsters then chase -> wind-up (telegraphed "!")
##    -> lunge -> recover (punish window). Passive monsters only fight back once provoked (hit).
##    Leash: chase too far from home and they give up, walk back and heal. Boss: ground slam AoE.
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

@export_group("Combat")
@export var aggressive := true                    ## false = peaceful until hit
@export var attack_damage := 10
@export var attack_range := 0.0                   ## 0 = radius + 1.2
@export var windup_time := 0.6                    ## telegraph length (dodge window)
@export var attack_cooldown := 1.6
@export var leash := 20.0                         ## max chase distance from home

const GRAVITY := 20.0
const IDLE := ["Idle", "Flying_Idle", "Idle_Loop"]
const WALK := ["Walk", "Fast_Flying", "Run", "Walk_Loop"]
const HIT := ["HitRecieve", "HitReact", "Hit_Chest"]
const DEATH := ["Death", "Death01"]
const REACT := ["Yes", "Dance", "Wave"]
const ATTACK := ["Bite_Front", "Punch", "Headbutt", "Weapon", "Punch_Jab"]
const SLAM_RADIUS := 4.5
const MAX_ATTACKERS := 2      ## attack tokens: at most this many monsters attacking at once

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
var _provoked := false
var _atk_cd := 0.0
var _lunge_dir := Vector3.ZERO

# --- talking / pacifist route ---------------------------------------
var friend := false            ## befriended: follows the player, can't be targeted
var spared := false
var _snacked := false
var _affection := 0
var _friend_tag: Label3D

const GREET_HOSTILE := ["%s growls and bares its teeth.", "%s eyes you hungrily.", "%s is not in the mood to chat.", "%s puffs itself up to look bigger."]
const GREET_CALM := ["%s tilts its head at you.", "%s wiggles happily.", "%s sniffs at your pockets.", "%s blinks slowly. That's a good sign."]
const PET_LINES := ["%s leans into your hand.", "%s makes a happy little noise.", "%s closes its eyes, content."]
var _alert: Label3D
var _ring: MeshInstance3D


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("interactable")
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
	if attack_range <= 0.0:
		attack_range = radius + 1.2
	_alert = Label3D.new()
	_alert.text = "!"
	_alert.font_size = 160
	_alert.outline_size = 30
	_alert.modulate = Color(1.0, 0.25, 0.15)
	_alert.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert.no_depth_test = true
	_alert.position.y = height + 0.9
	_alert.visible = false
	add_child(_alert)
	if is_boss:
		var m := CylinderMesh.new()
		m.top_radius = SLAM_RADIUS
		m.bottom_radius = SLAM_RADIUS
		m.height = 0.02
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.15, 0.1, 0.35)
		m.material = mat
		_ring = MeshInstance3D.new()
		_ring.mesh = m
		_ring.position.y = 0.06
		_ring.visible = false
		add_child(_ring)


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
	_atk_cd = maxf(_atk_cd - delta, 0.0)
	_state_t -= delta

	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	var to_p := Vector3.ZERO
	var dist := INF
	var player_ok: bool = _player != null and _player.get("alive") != false and _player.get("can_control") != false
	if player_ok:
		to_p = _player.global_position - global_position
		to_p.y = 0.0
		dist = to_p.length()
	var hostile: bool = player_ok and wander_radius > 0.0 and (aggressive or _provoked)
	var from_home := Vector2(global_position.x - home.x, global_position.z - home.z).length()
	var engaged := _state in ["chase", "windup", "lunge", "recover"]

	var move := Vector3.ZERO
	if friend:
		_follow(delta, to_p, dist)
		return
	if _state == "talk":
		_face(to_p, delta * 6.0)
		_play(IDLE)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	match _state:
		"windup":
			_face(to_p, delta * 8.0)
			if is_boss and _ring:
				_ring.scale = Vector3.ONE * (1.0 - clampf(_state_t / windup_time, 0.0, 1.0) * 0.6)
			if _state_t <= 0.0:
				_strike_now()
		"lunge":
			move = _lunge_dir * 11.0
			if _state_t <= 0.0:
				_resolve_hit()
		"recover":
			if _state_t <= 0.0:
				_state = "chase"
		"return":
			var back := home - global_position
			back.y = 0.0
			if back.length() < 0.6:
				_state = "idle"
				_state_t = 2.0
				_provoked = false
				hp = max_hp
				health_changed.emit(hp, max_hp)
			else:
				move = back.normalized() * move_speed * 1.5
				_face(back, delta * 6.0)
				_play(WALK)
		_:
			if _busy_t > 0.0:
				pass
			elif hostile and from_home < leash and (dist < notice_range or (engaged and dist < notice_range * 1.8)):
				if _state != "chase":
					_state = "chase"
					_flash_alert(0.5)
				_face(to_p, delta * 8.0)
				var reach := SLAM_RADIUS * 0.7 if is_boss else attack_range
				if dist > reach:
					move = to_p.normalized() * move_speed * 1.7
					_play(WALK)
				elif _atk_cd <= 0.0 and (is_boss or _attackers() < MAX_ATTACKERS):
					_begin_windup()
				else:
					_play(IDLE)
			elif _state == "chase":
				_state = "return"                 # lost the player or hit the leash
			else:
				_idle_brain(delta, player_ok and dist < notice_range, to_p, delta)
				if _state == "walk":
					var to := _goal - global_position
					to.y = 0.0
					move = to.normalized() * move_speed if to.length() > 0.4 else Vector3.ZERO

	velocity.x = move.x
	velocity.z = move.z
	move_and_slide()


func _idle_brain(delta: float, near: bool, to_p: Vector3, _d: float) -> void:
	if near and wander_radius > 0.0:
		_face(to_p, delta * 6.0)               # peaceful: just watch the player
		if not _noticed:
			_noticed = true
			_busy_t = _play(REACT, false)
		else:
			_play(IDLE)
		return
	_noticed = false
	if wander_radius <= 0.0:
		return
	if _state == "idle" or _state == "":
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
			_face(to, delta * 5.0)
			_play(WALK)


# ------------------------------------------------------------------ attacks

func _begin_windup() -> void:
	_state = "windup"
	_state_t = windup_time
	_alert.visible = true
	if _ring:
		_ring.visible = true
	_play(IDLE)
	# telegraph: quick squash so the tell reads even on static models
	var t := create_tween()
	t.tween_property(_visual, "scale", _visual.scale * Vector3(1.12, 0.85, 1.12), windup_time * 0.8)


func _strike_now() -> void:
	_alert.visible = false
	_visual.scale = Vector3.ONE * (model_scale if model_scene else 1.0)
	_play(ATTACK, false)
	if is_boss:
		_state = "lunge"                       # slam lands immediately
		_state_t = 0.0
		_lunge_dir = Vector3.ZERO
	else:
		_state = "lunge"
		_state_t = 0.16
		_lunge_dir = (_player.global_position - global_position) * Vector3(1, 0, 1)
		_lunge_dir = _lunge_dir.normalized()


func _resolve_hit() -> void:
	if _ring:
		_ring.visible = false
		_ring.scale = Vector3.ONE
	var to := _player.global_position - global_position
	to.y = 0.0
	var reach := SLAM_RADIUS if is_boss else attack_range + 0.6
	if to.length() <= reach and _player.has_method("take_damage"):
		_player.take_damage(attack_damage, to.normalized())
	_state = "recover"
	_state_t = 1.1 if is_boss else 0.8         # punish window
	_atk_cd = attack_cooldown


func _attackers() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e._state == "windup" or e._state == "lunge":
			n += 1
	return n


func _flash_alert(t: float) -> void:
	_alert.visible = true
	await get_tree().create_timer(t).timeout
	if _state != "windup":
		_alert.visible = false


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
	_provoked = true
	if _player:
		_face(_player.global_position - global_position, 1.0)
	if _state == "windup" and not is_boss:          # stagger: hits interrupt small monsters
		_state = "recover"
		_state_t = 0.5
		_alert.visible = false
		_visual.scale = Vector3.ONE * (model_scale if model_scene else 1.0)
		_atk_cd = attack_cooldown * 0.5
	elif _state in ["idle", "walk", "return", ""]:
		_state = "chase"
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
	if _player and _player.has_method("reward"):
		if wander_radius <= 0.0:
			_player.reward(4, 1, "training")
		else:
			_player.reward(max_hp / 2, max_hp / 8 + randi() % 5, "defeated")
	_alert.visible = false
	if _ring:
		_ring.visible = false
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
	_provoked = false
	_visual.scale = Vector3.ONE * (model_scale if model_scene else 1.0)
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


# ------------------------------------------------------------------ talking

func can_interact() -> bool:
	return alive and not friend and _state not in ["windup", "lunge"]


func is_dummy() -> bool:
	return wander_radius <= 0.0


func is_hostile() -> bool:
	return (aggressive or _provoked) and not spared


## Dialogue protocol used by menus.gd: each call returns
##   {title, text, options: [String], end: "" | "fight" | "leave" | "spared" | "friend"}
func talk_begin() -> Dictionary:
	if is_dummy():
		return _say("It's a training dummy. It does not talk back.", [], "leave")
	_state = "talk"
	_alert.visible = false
	if is_hostile():
		return _say(GREET_HOSTILE.pick_random() % display_name, _hostile_options())
	return _say(GREET_CALM.pick_random() % display_name, _calm_options())


func talk_choose(option: String) -> Dictionary:
	var n := display_name
	match option:
		"Fight!":
			return _say("You raise your fists.", [], "fight")
		"Try to calm it down":
			var threshold := 0.3 if is_boss else 0.5
			if _snacked and not is_boss:
				threshold = 1.01
			elif _snacked:
				threshold = 0.5
			if float(hp) / max_hp <= threshold:
				return _say("%s calms down and lowers its guard. You spared it!" % n, [], "spared")
			return _say("%s won't listen!  (Weaken it first, or offer a snack.)" % n, [], "fight")
		"Offer a snack (10 coins)", "Offer a snack (5 coins)":
			var cost := 10 if option.contains("10") else 5
			if not _player.spend(cost):
				return _say("You don't have enough coins.", _hostile_options() if is_hostile() else _calm_options())
			if is_hostile():
				_snacked = true
				return _say("%s snatches the snack and chews suspiciously... it seems calmer." % n, _hostile_options())
			_affection += 2
			return _after_affection("%s gobbles the snack!" % n)
		"Pet it":
			_affection += 1
			return _after_affection(PET_LINES.pick_random() % n)
		"Join me!":
			if is_boss:
				return _say("%s is far too grand to follow anyone... but it bows to you." % n, [], "leave")
			if not _player.add_follower(self):
				return _say("Your party is full (%d / %d)." % [_player.followers.size(), _player.MAX_FOLLOWERS], [], "leave")
			return _say("%s joined you! Friends follow you around." % n, [], "friend")
	return _say("", [], "leave")


func talk_end(result: String) -> void:
	match result:
		"fight":
			_provoked = true
			_state = "chase"
			_atk_cd = 0.0
		"spared":
			spared = true
			aggressive = false
			_provoked = false
			_state = "idle"
			_state_t = 2.0
			if _player:
				_player.reward(int(max_hp * 0.4), 0, "spared")
		"friend":
			_become_friend()
		_:
			if _state == "talk":
				_state = "idle"
				_state_t = 2.0


func _hostile_options() -> Array:
	var o := ["Fight!", "Try to calm it down"]
	if not _snacked:
		o.append("Offer a snack (10 coins)")
	return o


func _calm_options() -> Array:
	return ["Pet it", "Offer a snack (5 coins)", "Leave"]


func _after_affection(line: String) -> Dictionary:
	if _affection >= 3:
		return _say(line + "\n%s seems to really like you. Ask it to join you?" % display_name, ["Join me!", "Leave"])
	return _say(line, _calm_options())


func _say(text: String, options: Array, end := "") -> Dictionary:
	return {"title": display_name, "text": text, "options": options, "end": end}


func _become_friend() -> void:
	friend = true
	spared = true
	aggressive = false
	remove_from_group("enemy")
	collision_layer = 2            # player, projectiles and melee ignore friends
	_friend_tag = Label3D.new()
	_friend_tag.text = "friend"
	_friend_tag.font_size = 48
	_friend_tag.outline_size = 10
	_friend_tag.modulate = Color(0.5, 1.0, 0.6)
	_friend_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_friend_tag.position.y = height + 0.5
	add_child(_friend_tag)


func _follow(delta: float, to_p: Vector3, dist: float) -> void:
	var idx: int = maxi(_player.followers.find(self), 0) if _player else 0
	var keep := 2.6 + idx * 1.4
	var move := Vector3.ZERO
	if dist > 30.0:
		global_position = _player.global_position - to_p.normalized() * keep
	elif dist > keep:
		move = to_p.normalized() * clampf(dist * 1.5, 2.0, 7.0)
		_face(to_p, delta * 8.0)
		_play(WALK)
	else:
		_face(to_p, delta * 3.0)
		_play(IDLE)
	velocity.x = move.x
	velocity.z = move.z
	move_and_slide()


func _collect(n: Node) -> void:
	if n is MeshInstance3D:
		_meshes.append(n)
	if n is AnimationPlayer and _anim == null:
		_anim = n
	for c in n.get_children():
		_collect(c)
