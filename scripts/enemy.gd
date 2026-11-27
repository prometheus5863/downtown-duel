extends CharacterBody3D
## Monster / training dummy.
##  - Optional animated model (Quaternius monsters): idle, walk, hit, death clips are
##    found by name so any monster in the packs works without per-model setup.
##  - Brain: idle -> wander -> notice player. Hostile monsters then chase -> wind-up (telegraphed "!")
##    -> lunge -> recover (punish window). Passive monsters only fight back once provoked (hit).
##    Leash: chase too far from home and they give up, walk back and heal. Boss: ground slam AoE.
##  - Takes damage: flash, knockback, damage number, hit/death animation, respawn. Damage is scaled by the
##    element wheel (data/elements.json); species, element and companion stats come from data/creatures.json.
##  - Fights whoever it is angry at (`_foe`): the player by default, or the companion that last hit it.
##  - Befriended (`friend`): becomes a party member. scripts/companion.gd takes over the brain, the creature
##    gets a save record, levels with the player, and at 0 HP is "exhausted" (a ghost) instead of dying.
## Origin sits on the floor; `height` sizes the collider and the aim point.

const Data := preload("res://scripts/data.gd")
const Companion := preload("res://scripts/companion.gd")

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
@export var level := 1                            ## wild level (set per zone by the generator); companions level up
@export var is_alpha := false                     ## region Alpha: big, crowned, phase 2 below half HP, Mythic treats only
@export var alpha_drop := ""                      ## data/materials.json id dropped when defeated or calmed

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
var species := ""              ## "Blob/GreenBlob" (key into data/creatures.json), from the model path
var element := ""
var record := {}               ## party / storage / save record once befriended (see docs/PLAN.md)
var brain: RefCounted          ## companion.gd, once befriended
var exhausted := false         ## companion at 0 HP: ghost until revived
var origin_id := ""            ## scene path of the wild creature this companion was (so it stays gone after loading)

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
var _foe: Node3D               # companion this creature is fighting instead of the player

# --- talking / pacifist route ---------------------------------------
var friend := false            ## befriended: follows the player, can't be targeted
var spared := false
var _snacked := false
var bond := 0                  ## 0-100. At JOIN_BOND it asks to join. Saved per creature (world.bond)
var lustre := false            ## rare shiny variant (1 in LUSTRE_ODDS, decided from the scene path so it's stable)
var _phase2 := false
var _petted := false           # petting counts once per conversation
const JOIN_BOND := 60
const LUSTRE_ODDS := 200
const BOND_PET := 8
const BOND_SPARE := 20
const LUSTRE_TINT := Color(1.0, 0.82, 0.35)
var _friend_tag: Label3D

const GREET_HOSTILE := ["%s growls and bares its teeth.", "%s eyes you hungrily.", "%s is not in the mood to chat.", "%s puffs itself up to look bigger."]
const GREET_CALM := ["%s tilts its head at you.", "%s wiggles happily.", "%s sniffs at your pockets.", "%s blinks slowly. That's a good sign."]
const PET_LINES := ["%s leans into your hand.", "%s makes a happy little noise.", "%s closes its eyes, content."]
var _alert: Label3D
var _ring: MeshInstance3D
var _tell: Tween


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
		species = Data.species_of(model_scene.resource_path)
		element = Data.creature(species).get("element", "")
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
	_roll_lustre()
	if is_alpha:
		_setup_alpha()
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


## Lustre is decided from a hash of the scene path: the same creature is Lustre on every load, and tests can
## force it with set_lustre().
func _roll_lustre() -> void:
	if friend or is_dummy() or not is_inside_tree() or get_tree().current_scene == null:
		return
	var key := String(get_tree().current_scene.get_path_to(self)) if get_tree().current_scene.is_ancestor_of(self) else String(name)
	if hash(key) % LUSTRE_ODDS == 0:
		set_lustre(true)


func set_lustre(on: bool) -> void:
	if on == lustre:
		return
	lustre = on
	if on:
		max_hp = int(round(max_hp * 1.1))
		hp = max_hp
		attack_damage = int(round(attack_damage * 1.1))
		display_name = display_name if display_name.begins_with("Lustre ") else "Lustre " + display_name
		_tint_meshes(LUSTRE_TINT)
		var star := Label3D.new()
		star.text = "✦"
		star.font_size = 90
		star.outline_size = 12
		star.modulate = LUSTRE_TINT
		star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		star.position.y = height + 0.35
		star.name = "LustreStar"
		add_child(star)


## Tinted surface overrides must be dropped before the meshes are freed, or the renderer logs
## "material is null" while tearing the scene down (same as avatar.gd).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for m in _meshes:
			if is_instance_valid(m):
				for i in m.get_surface_override_material_count():
					m.set_surface_override_material(i, null)


func _tint_meshes(col: Color) -> void:
	for m in _meshes:
		if m == get_node_or_null("Mesh"):
			continue
		for i in m.get_surface_override_material_count():
			var base := m.get_active_material(i)
			if base is StandardMaterial3D:
				var mat: StandardMaterial3D = base.duplicate()
				mat.albedo_color = mat.albedo_color * col
				mat.emission_enabled = true
				mat.emission = col * 0.25
				m.set_surface_override_material(i, mat)


func _setup_alpha() -> void:
	model_scale *= 1.0 if is_boss else 1.5
	height *= 1.0 if is_boss else 1.5
	radius *= 1.0 if is_boss else 1.4
	if model_scene and not is_boss:
		_visual.scale = _rest_scale()
		var shape: CapsuleShape3D = $Collision.shape
		shape.radius = radius
		shape.height = maxf(height, radius * 2.0)
		$Collision.position.y = shape.height * 0.5
		attack_range = radius + 1.4
	var crown := Label3D.new()
	crown.text = "♛"
	crown.font_size = 140
	crown.outline_size = 18
	crown.modulate = Color(1.0, 0.8, 0.2)
	crown.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	crown.position.y = height + 0.6
	add_child(crown)


## Below half HP an Alpha gets angry: faster tells, shorter cooldowns, harder hits.
func _enter_phase2() -> void:
	_phase2 = true
	windup_time *= 0.7
	attack_cooldown *= 0.6
	attack_damage = int(round(attack_damage * 1.25))
	move_speed *= 1.25
	_tint_meshes(Color(1.0, 0.55, 0.5))
	ring_fx(5.0, Color(1.0, 0.3, 0.2))
	_flash_alert(1.2)


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
	if friend:
		if brain:
			brain.tick(delta)
		return
	# "to_p" / "player_ok" below mean the current foe: the player, or a companion that drew this creature's anger.
	var foe := _current_foe()
	var to_p := Vector3.ZERO
	var dist := INF
	var player_ok: bool = foe != null
	if player_ok:
		to_p = foe.global_position - global_position
		to_p.y = 0.0
		dist = to_p.length()
	var hostile: bool = player_ok and wander_radius > 0.0 and (aggressive or _provoked)
	var from_home := Vector2(global_position.x - home.x, global_position.z - home.z).length()
	var engaged := _state in ["chase", "windup", "lunge", "recover"]

	var move := Vector3.ZERO
	if _state == "talk":
		# The player has no control while talking, so _current_foe() is null: face the player directly.
		if _player:
			_face(_player.global_position - global_position, delta * 6.0)
		if _busy_t <= 0.0:                          # don't cut off a petting reaction
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


## Who this creature fights right now: a companion that hit it (while that companion is up and close), else
## the player (while alive and in control). null = nobody to fight.
func _current_foe() -> Node3D:
	if is_instance_valid(_foe) and _foe.get("friend") and not _foe.get("exhausted") \
			and _foe.global_position.distance_to(global_position) < notice_range * 2.0:
		return _foe
	_foe = null
	if _player != null and _player.get("alive") != false and _player.get("can_control") != false:
		return _player
	return null


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
	telegraph(windup_time * 0.8)


## Squash-and-hold tell before an attack (also used by the companion brain).
func telegraph(t: float) -> void:
	_tell = create_tween()
	_tell.tween_property(_visual, "scale", _rest_scale() * Vector3(1.12, 0.85, 1.12), t)


func telegraph_end() -> void:
	if _tell:
		_tell.kill()
	_visual.scale = _rest_scale()


func _rest_scale() -> Vector3:
	return Vector3.ONE * (model_scale if model_scene else 1.0)


## Expanding flat ring for area attacks.
func ring_fx(r: float, col: Color) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = 0.02
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(col.r, col.g, col.b, 0.45)
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position.y = 0.07
	mi.scale = Vector3(0.2, 1, 0.2)
	add_child(mi)
	var t := mi.create_tween().set_parallel()
	t.tween_property(mi, "scale", Vector3.ONE, 0.25)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	t.chain().tween_callback(mi.queue_free)


func _strike_now() -> void:
	_alert.visible = false
	telegraph_end()
	_play(ATTACK, false)
	var foe := _current_foe()
	if is_boss or foe == null:
		_state = "lunge"                       # slam lands immediately
		_state_t = 0.0
		_lunge_dir = Vector3.ZERO
	else:
		_state = "lunge"
		_state_t = 0.16
		_lunge_dir = (foe.global_position - global_position) * Vector3(1, 0, 1)
		_lunge_dir = _lunge_dir.normalized()


func _resolve_hit() -> void:
	if _ring:
		_ring.visible = false
		_ring.scale = Vector3.ONE
	var reach := SLAM_RADIUS if is_boss else attack_range + 0.6
	# Bosses slam everyone in the ring; others hit the one they lunged at.
	var victims: Array = []
	if is_boss and _player:
		victims = [_player] + _player.party
	elif _current_foe():
		victims = [_current_foe()]
	for v in victims:
		if not is_instance_valid(v) or v.get("exhausted"):
			continue
		var to: Vector3 = v.global_position - global_position
		to.y = 0.0
		if to.length() <= reach and v.has_method("take_damage"):
			v.take_damage(attack_damage, to.normalized(), self, element)
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

## source = who dealt it (player, companion or wild creature); attack_element scales it by the element wheel.
func take_damage(amount: int, from_dir: Vector3, source: Node = null, attack_element := "") -> void:
	if not alive or exhausted:
		return
	var mult := Data.element_mult(attack_element, element)
	amount = maxi(int(round(amount * mult)), 1)
	hp = maxi(hp - amount, 0)
	health_changed.emit(hp, max_hp)
	_flash()
	_knock(from_dir)
	_popup(amount, Color(1.0, 0.45, 0.2) if mult > 1.0 else Color(0.7, 0.7, 0.75) if mult < 1.0 else Color(1.0, 0.9, 0.2), mult)
	if friend:
		if hp == 0:
			_exhaust()
		return
	if is_alpha and not _phase2 and hp > 0 and hp <= max_hp / 2:
		_enter_phase2()
	_provoked = true
	# Anger follows the hits: a companion that lands one usually pulls it off the player, and the reverse.
	if source != null and source.get("friend"):
		if _foe == null or randf() < 0.7:
			_foe = source
	elif source != null and source == _player and randf() < 0.5:
		_foe = null
	var facing: Node3D = source if source is Node3D else _player
	if facing:
		_face(facing.global_position - global_position, 1.0)
	if _state == "windup" and not is_boss:          # stagger: hits interrupt small monsters
		_state = "recover"
		_state_t = 0.5
		_alert.visible = false
		telegraph_end()
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


func _popup(amount: int, col := Color(1.0, 0.9, 0.2), mult := 1.0) -> void:
	var l := Label3D.new()
	l.text = str(amount) + ("!" if mult > 1.0 else "")
	l.font_size = 88 if mult > 1.0 else 72
	l.outline_size = 14
	l.modulate = col
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
		_give_alpha_drop()
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
	_foe = null
	_snacked = false
	if _phase2:                                  # respawns calm and in phase 1
		_phase2 = false
		windup_time /= 0.7
		attack_cooldown /= 0.6
		attack_damage = int(round(attack_damage / 1.25))
		move_speed /= 1.25
		_tint_meshes(LUSTRE_TINT if lustre else Color.WHITE)
	_visual.scale = _rest_scale()
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


func is_engaged() -> bool:
	return _state in ["chase", "windup", "lunge", "recover"]


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
	_petted = false
	var extra := "\nFavourite flavour: %s" % favourite_flavour() if bond > 0 else ""
	if is_hostile():
		return _say(GREET_HOSTILE.pick_random() % display_name + extra, _hostile_options())
	return _say(GREET_CALM.pick_random() % display_name + "\n" + _bond_text() + extra, _calm_options())


func talk_choose(option: String) -> Dictionary:
	var n := display_name
	if option.begins_with("Give "):
		return _give_treat(_treat_from_option(option))
	match option:
		"Fight!":
			return _say("You raise your fists.", [], "fight")
		"Try to calm it down":
			var threshold := 0.3 if (is_boss or is_alpha) else 0.5
			if _snacked:
				threshold = 0.5 if (is_boss or is_alpha) else 1.01
			if float(hp) / max_hp <= threshold:
				return _say("%s calms down and lowers its guard. You spared it!" % n, [], "spared")
			return _say("%s won't listen!  (Weaken it first, or offer a treat.)" % n, [], "fight")
		"Pet it":
			if not _petted:
				_petted = true
				bond = mini(bond + BOND_PET, 100)
			return _after_bond(PET_LINES.pick_random() % n)
		"Join me!":
			if is_boss and not is_alpha:
				return _say("%s is far too grand to follow anyone... but it bows to you." % n, [], "leave")
			if _player.party.size() >= _player.MAX_PARTY:
				return _say("%s wants to come along! Your party is full, so it will wait for you at the Creature Ledger." % n, [], "friend")
			return _say("%s joined your party! It fights beside you:  1 Attack · 2 Follow · 3 Hold · 4 Return." % n, [], "friend")
	return _say("", [], "leave")


func talk_end(result: String) -> void:
	_petted = false
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
			bond = mini(bond + BOND_SPARE, 100)
			if _player:
				_player.reward(int(max_hp * 0.4), 0, "spared")
				_give_alpha_drop()
		"friend":
			if _player:
				_player.befriend(self)
		_:
			if _state == "talk":
				_state = "idle"
				_state_t = 2.0


## Loading a save: this creature was spared earlier.
func set_spared() -> void:
	spared = true
	aggressive = false
	_provoked = false


## Alpha treasure (and, until crafting arrives in M4, one Mythic Morsel so the next Alpha can be befriended).
func _give_alpha_drop() -> void:
	if alpha_drop == "" or _player == null or not _player.has_method("add_item"):
		return
	_player.add_item(alpha_drop, 1)
	_player.add_item("mythic_morsel", 1)


# ------------------------------------------------------------------ treats & bond

## Bond a treat gives this creature: 0 if refused (Alphas want Mythic), x2 for its favourite flavour.
func treat_bond(treat_id: String) -> int:
	var t: Dictionary = Data.table("treats").get(treat_id, {})
	if t.is_empty():
		return 0
	if (is_alpha or is_boss) and t.tier != "mythic":
		return 0
	var b := int(t.bond)
	if t.flavour == favourite_flavour():
		b *= 2
	return b


func favourite_flavour() -> String:
	return Data.creature(species).get("flavour", "")


func _give_treat(treat_id: String) -> Dictionary:
	var n := display_name
	var t: Dictionary = Data.table("treats").get(treat_id, {})
	if t.is_empty() or _player.item_count(treat_id) <= 0:
		return _say("You don't have that treat.", _hostile_options() if is_hostile() else _calm_options())
	var gain := treat_bond(treat_id)
	if gain == 0:
		return _say("%s sniffs the %s and turns away. Only a Mythic treat will do for an Alpha." % [n, t.name],
			_hostile_options() if is_hostile() else _calm_options())
	_player.remove_item(treat_id, 1)
	bond = mini(bond + gain, 100)
	var fav := " It's its favourite!" if t.flavour == favourite_flavour() else ""
	if is_hostile():
		_snacked = true
		return _say("%s snatches the %s and chews suspiciously... it seems calmer.%s" % [n, t.name, fav], _hostile_options())
	return _after_bond("%s gobbles the %s!%s" % [n, t.name, fav])


func _treat_from_option(option: String) -> String:
	for id in Data.table("treats"):
		if option.begins_with("Give %s" % Data.table("treats")[id].name):
			return id
	return ""


## "Give <treat> (<count>)" options for the treats you carry: best tier first, at most 4.
func _treat_options() -> Array:
	var out := []
	if _player == null or not _player.has_method("item_count"):
		return out
	var ids: Array = Data.table("treats").keys()
	ids.reverse()                                 # treats.json lists simple -> mythic
	for id in ids:
		var c: int = _player.item_count(id)
		if c > 0 and out.size() < 4:
			out.append("Give %s (%d)" % [Data.table("treats")[id].name, c])
	return out


func _hostile_options() -> Array:
	var o := ["Fight!", "Try to calm it down"]
	if not _snacked:
		o.append_array(_treat_options())
	return o


func _calm_options() -> Array:
	var o := ["Pet it"] if not _petted else []
	o.append_array(_treat_options())
	o.append("Leave")
	return o


## Petting / treat feedback while the camera is in close: happy animation, a squash-and-bounce, hearts that
## float up (more for bigger bond gains) and, for a favourite, a gold sparkle burst.
func react_affection(gained: int, favourite := false) -> void:
	_busy_t = maxf(_play(REACT, false), 0.6)
	var rest := _rest_scale()
	var t := create_tween()
	t.tween_property(_visual, "scale", rest * Vector3(1.15, 0.82, 1.15), 0.12).set_trans(Tween.TRANS_SINE)
	t.tween_property(_visual, "scale", rest * Vector3(0.92, 1.14, 0.92), 0.14).set_trans(Tween.TRANS_SINE)
	t.tween_property(_visual, "scale", rest, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in clampi(2 + gained / 6, 2, 9):
		var h := Label3D.new()
		h.text = "♥"
		h.font_size = randi_range(36, 58)
		h.outline_size = 10
		h.modulate = Color(1.0, randf_range(0.35, 0.6), randf_range(0.55, 0.75))
		h.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		h.no_depth_test = true
		add_child(h)
		h.position = Vector3(randf_range(-0.5, 0.5) * radius * 2.0, height * 0.8, randf_range(-0.3, 0.3))
		var ht := h.create_tween().set_parallel()
		var delay := i * 0.09
		h.modulate.a = 0.0
		ht.tween_property(h, "modulate:a", 1.0, 0.15).set_delay(delay)
		ht.tween_property(h, "position:y", height * 1.05 + 0.25 + randf() * 0.3, 1.2).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		ht.tween_property(h, "position:x", h.position.x + randf_range(-0.4, 0.4), 1.2).set_delay(delay)
		ht.tween_property(h, "modulate:a", 0.0, 0.4).set_delay(delay + 0.85)
		ht.chain().tween_callback(h.queue_free)
	if favourite:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.amount = 28
		p.lifetime = 0.9
		p.explosiveness = 0.9
		p.direction = Vector3.UP
		p.spread = 80.0
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 4.5
		p.gravity = Vector3(0, -3, 0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.2
		var m := SphereMesh.new()
		m.radius = 0.05
		m.height = 0.1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.85, 0.35)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.75, 0.2)
		mat.emission_energy_multiplier = 2.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material = mat
		p.mesh = m
		add_child(p)
		p.position.y = height * 0.7
		p.emitting = true
		get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func _bond_text() -> String:
	var full := int(round(bond / 10.0))
	return "Bond  " + "♥".repeat(mini(full, 10)) + "♡".repeat(maxi(10 - full, 0)) + "  %d / 100" % bond


func _after_bond(line: String) -> Dictionary:
	if bond >= JOIN_BOND:
		return _say(line + "\n%s\n%s seems to really like you. Ask it to join you?" % [_bond_text(), display_name], ["Join me!", "Leave"])
	return _say(line + "\n" + _bond_text(), _calm_options())


func _say(text: String, options: Array, end := "") -> Dictionary:
	return {"title": display_name, "text": text, "options": options, "end": end}


# ------------------------------------------------------------------ companion

## Turns this creature into a party member of `p`. `rec` is its saved record; empty = just befriended in the
## wild, and `origin` is then its scene path (so the wild one stays gone after loading).
func adopt(p: Node, rec: Dictionary = {}, origin := "") -> void:
	_player = p
	friend = true
	spared = true
	aggressive = false
	_provoked = false
	_foe = null
	_state = "idle"
	_alert.visible = false
	telegraph_end()
	remove_from_group("enemy")
	remove_from_group("interactable")
	collision_layer = 2            # player, projectiles and melee ignore friends
	if rec.is_empty():
		rec = {"uid": "%08x%04x" % [randi(), randi() % 65536], "species": species, "name": display_name,
			"level": level, "xp": 0, "hp": -1, "origin": origin, "lustre": lustre, "alpha": is_alpha}
	record = rec
	origin_id = String(rec.get("origin", ""))
	display_name = String(rec.get("name", display_name))
	level = int(rec.get("level", 1))
	_apply_level()
	if bool(rec.get("lustre", false)) and not lustre:
		set_lustre(true)
	elif lustre:
		max_hp = int(round(max_hp * 1.1))
		attack_damage = int(round(attack_damage * 1.1))
	if bool(rec.get("alpha", false)):
		max_hp = int(round(max_hp * 1.5))
		attack_damage = int(round(attack_damage * 1.3))
	hp = max_hp if int(rec.get("hp", -1)) < 0 else clampi(int(rec.hp), 0, max_hp)
	wander_radius = maxf(wander_radius, 1.0)      # a befriended dummy still counts as a creature
	move_speed = float(Data.creature(species).get("speed", move_speed))
	brain = Companion.new(self, p)
	if _friend_tag == null:
		_friend_tag = Label3D.new()
		_friend_tag.font_size = 44
		_friend_tag.outline_size = 10
		_friend_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_friend_tag.position.y = height + 0.45
		add_child(_friend_tag)
	_refresh_tag()
	health_changed.emit(hp, max_hp)
	if hp == 0:
		_exhaust()


## Record for the save file / storage, with the current HP.
func make_record() -> Dictionary:
	record["hp"] = hp
	record["level"] = level
	record["name"] = display_name
	return record.duplicate()


func _apply_level() -> void:
	max_hp = Data.companion_hp(species, level)
	attack_damage = Data.companion_atk(species, level)


## XP is shared with the player (player.reward). Returns true when the companion levelled up.
func gain_xp(amount: int) -> bool:
	if not friend:
		return false
	record["xp"] = int(record.get("xp", 0)) + amount
	var up := false
	while record.xp >= Data.xp_to_next(level):
		record.xp -= Data.xp_to_next(level)
		level += 1
		up = true
	if up:
		var missing := max_hp - hp
		_apply_level()
		hp = max_hp if not exhausted else 0
		if not exhausted and missing > 0:
			hp = max_hp                             # level up = full heal, like the player
		record["level"] = level
		_refresh_tag()
		health_changed.emit(hp, max_hp)
	return up


func _exhaust() -> void:
	exhausted = true
	hp = 0
	_alert.visible = false
	telegraph_end()
	for m in _meshes:
		m.transparency = 0.65                     # ghost
	_refresh_tag()
	health_changed.emit(hp, max_hp)


## Sanctuary rest / revive item: back on its feet with `fraction` of max HP.
func revive(fraction := 1.0) -> void:
	exhausted = false
	hp = maxi(int(max_hp * fraction), 1)
	for m in _meshes:
		m.transparency = 0.0
	_refresh_tag()
	health_changed.emit(hp, max_hp)


func heal_full() -> void:
	if exhausted:
		revive()
	else:
		hp = max_hp
		health_changed.emit(hp, max_hp)


func _refresh_tag() -> void:
	if _friend_tag:
		_friend_tag.text = "%s  Lv %d%s" % [display_name, level, "  (exhausted)" if exhausted else ""]
		_friend_tag.modulate = Color(0.6, 0.6, 0.65) if exhausted else Data.element_color(element).lightened(0.3)


func _collect(n: Node) -> void:
	if n is MeshInstance3D:
		_meshes.append(n)
	if n is AnimationPlayer and _anim == null:
		_anim = n
	for c in n.get_children():
		_collect(c)
