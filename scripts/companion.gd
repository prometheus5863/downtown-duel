extends RefCounted
## Brain of a befriended creature (the node itself is still enemy.gd, which hands its tick over once `friend`).
##  - follows the player in formation, teleports back if left far behind
##  - picks a target from the party command (player.party_command):
##      attack = the player's lock-on target, else the nearest hostile creature
##      follow = assist: creatures that are fighting the player or the party
##      hold   = stay put, fight what comes close
##      heel   = come back and don't fight ("Return")
##      work   = harvest resource nodes near the player that match the creature's skills (data: "skills"),
##               still defending the player like "follow"; drops go to the player's inventory
##  - attacks like wild creatures do: wind-up -> move (lunge / shot / slam from data/moves.json) -> recover,
##    with its own attack tokens (at most MAX_ATTACKERS companions mid-attack)
##  - exhausted (0 HP): follows as a ghost and does nothing until revived

const Data := preload("res://scripts/data.gd")
const Projectile := preload("res://scripts/projectile.gd")

const MAX_ATTACKERS := 2
const ASSIST_RANGE := 12.0        ## follow: help against fights this close to the player
const ATTACK_RANGE := 16.0        ## attack: look this far from the player for something hostile
const HOLD_RANGE := 7.0
const LEASH := 24.0               ## never chase further than this from the player
const TELEPORT := 34.0
const ENGAGED := ["chase", "windup", "lunge", "recover"]

var host: CharacterBody3D
var player: Node3D
var target: Node3D
var hold_pos := Vector3.ZERO
var state := "follow"              ## follow | windup | lunge | recover
var _t := 0.0
var _move := {}
var _move_id := ""
var _cd := {}                      # move id -> seconds until ready
var _dir := Vector3.ZERO
var _retarget_t := 0.0
var _job: Node                     # resource field being worked
var _job_i := -1
var _job_t := 0.0
const WORK_RANGE := 16.0


func _init(h: CharacterBody3D, p: Node3D) -> void:
	host = h
	player = p
	hold_pos = h.global_position
	for id in Data.creature(h.species).get("moves", []):
		_cd[id] = 0.0


func on_command(cmd: String) -> void:
	if cmd == "hold":
		hold_pos = host.global_position
	if cmd == "heel" or cmd == "follow":
		target = null
	_retarget_t = 0.0


func tick(delta: float) -> void:
	for id in _cd:
		_cd[id] = maxf(_cd[id] - delta, 0.0)
	_t -= delta
	var to_p := player.global_position - host.global_position
	to_p.y = 0.0
	if to_p.length() > TELEPORT:
		host.global_position = _slot()
		target = null
		state = "follow"
	var move := Vector3.ZERO
	if host.exhausted:
		target = null
		state = "follow"
		move = _formation(delta)
	else:
		match state:
			"windup":
				if _valid(target):
					host._face(target.global_position - host.global_position, delta * 10.0)
				if _t <= 0.0:
					_execute()
			"lunge":
				move = _dir * 11.0
				if _t <= 0.0:
					_land()
			"recover":
				if _t <= 0.0:
					state = "follow"
			_:
				_retarget_t -= delta
				if _retarget_t <= 0.0 or not _valid(target):
					target = _pick_target()
					_retarget_t = 0.4
				if target:
					move = _engage(delta)
				elif player.party_command == "work":
					move = _work(delta)
				else:
					move = _idle_move(delta)
	host.velocity.x = move.x
	host.velocity.z = move.z
	host.move_and_slide()


# ------------------------------------------------------------------ targeting

func _valid(t) -> bool:
	return is_instance_valid(t) and t.get("alive") == true and not t.get("friend") and t.is_in_group("enemy") \
		and t.global_position.distance_to(player.global_position) < LEASH


func _pick_target() -> Node3D:
	var cmd: String = player.party_command
	if cmd == "heel":
		return null
	if cmd == "attack" and player.locked and _valid(player.target):
		return player.target
	var best: Node3D = null
	var best_d := INF
	for e in host.get_tree().get_nodes_in_group("enemy"):
		if not _valid(e) or e.is_dummy():
			continue
		var d_player: float = e.global_position.distance_to(player.global_position)
		var engaged: bool = e._state in ENGAGED
		var wanted := false
		match cmd:
			"attack":
				wanted = d_player < ATTACK_RANGE and (engaged or e.is_hostile())
			"hold":
				wanted = engaged and e.global_position.distance_to(hold_pos) < HOLD_RANGE
			_:
				wanted = engaged and d_player < ASSIST_RANGE
		var d: float = e.global_position.distance_to(host.global_position)
		if wanted and d < best_d:
			best_d = d
			best = e
	return best


# ------------------------------------------------------------------ fighting

func _engage(delta: float) -> Vector3:
	var to_t := target.global_position - host.global_position
	to_t.y = 0.0
	var dist := to_t.length()
	host._face(to_t, delta * 8.0)
	var id := _ready_move(dist)
	if id != "" and _attackers() < MAX_ATTACKERS:
		_move_id = id
		_move = Data.move(id)
		state = "windup"
		_t = 0.35
		host._play(host.IDLE)
		host.telegraph(0.35)
		return Vector3.ZERO
	var reach: float = host.attack_range
	if dist > reach and not (player.party_command == "hold" and host.global_position.distance_to(hold_pos) > HOLD_RANGE):
		host._play(host.WALK)
		return to_t.normalized() * host.move_speed * 2.2
	host._play(host.IDLE)
	return Vector3.ZERO


## The special (second move) when it is ready and the distance suits it, else the basic one in melee range.
func _ready_move(dist: float) -> String:
	var ids: Array = _cd.keys()
	for i in range(ids.size() - 1, -1, -1):
		var m := Data.move(ids[i])
		if _cd[ids[i]] > 0.0:
			continue
		match m.get("kind", "lunge"):
			"shot":
				if dist > 2.5 and dist <= float(m.range):
					return ids[i]
			"slam":
				if dist <= float(m.range) * 0.75:
					return ids[i]
			_:
				if dist <= host.attack_range + 0.4:
					return ids[i]
	return ""


func _execute() -> void:
	host.telegraph_end()
	if not _valid(target):
		state = "follow"
		return
	_cd[_move_id] = float(_move.get("cooldown", 1.6))
	var dmg := int(round(host.attack_damage * float(_move.get("power", 1.0))))
	var element: String = _move.get("element", host.element)
	host._play(host.ATTACK, false)
	match _move.get("kind", "lunge"):
		"shot":
			var dir: Vector3 = (target.aim_point() - host.aim_point()).normalized()
			var p: Area3D = Projectile.new()
			p.shooter = host
			p.direction = dir
			p.damage = dmg
			p.element = element
			host.get_parent().add_child(p)
			p.global_position = host.aim_point() + dir * (host.radius + 0.4)
			state = "recover"
			_t = 0.6
		"slam":
			var r := float(_move.get("range", 3.5))
			host.ring_fx(r, Data.element_color(element))
			for e in host.get_tree().get_nodes_in_group("enemy"):
				if e.get("alive") == true and not e.is_dummy() or e == target:
					var to: Vector3 = e.global_position - host.global_position
					if to.length() <= r and e.get("alive") == true:
						e.take_damage(dmg, to, host, element)
			state = "recover"
			_t = 0.8
		_:
			state = "lunge"
			_t = 0.16
			_dir = ((target.global_position - host.global_position) * Vector3(1, 0, 1)).normalized()


func _land() -> void:
	if _valid(target):
		var to := target.global_position - host.global_position
		to.y = 0.0
		if to.length() <= host.attack_range + target.radius + 0.6:
			var dmg := int(round(host.attack_damage * float(_move.get("power", 1.0))))
			target.take_damage(dmg, to, host, _move.get("element", host.element))
	state = "recover"
	_t = 0.6


func _attackers() -> int:
	var n := 0
	for c in player.party:
		if is_instance_valid(c) and c.brain and c.brain.state in ["windup", "lunge"]:
			n += 1
	return n


# ------------------------------------------------------------------ working

func skills() -> Array:
	return Data.creature(host.species).get("skills", [])


## Tool tier a working creature counts as: grows with level (Lv 1-3 = 1, 4-7 = 2, ... capped at 4).
func work_tier() -> int:
	return clampi(1 + host.level / 4, 1, 4)


func _find_job() -> void:
	_job = null
	_job_i = -1
	var best := WORK_RANGE
	for f in host.get_tree().get_nodes_in_group("resource_field"):
		if not (f.info.get("skill", "") in skills()) or not f.tool_ok(f.info.get("tool", "hand"), work_tier()):
			continue
		var i: int = f.nearest(player.global_position, WORK_RANGE)
		if i < 0:
			continue
		var d: float = f.world_pos(i).distance_to(host.global_position)
		if d < best:
			best = d
			_job = f
			_job_i = i


func _work(delta: float) -> Vector3:
	if _job == null or not is_instance_valid(_job) or not _job.available(_job_i) \
			or _job.world_pos(_job_i).distance_to(player.global_position) > WORK_RANGE:
		_find_job()
		if _job == null:
			return _formation(delta)
	var to: Vector3 = _job.world_pos(_job_i) - host.global_position
	to.y = 0.0
	host._face(to, delta * 8.0)
	if to.length() > host.radius + 1.3:
		host._play(host.WALK)
		return to.normalized() * host.move_speed * 2.0
	host._play(host.IDLE)
	_job_t -= delta
	if _job_t <= 0.0:
		_job_t = 1.0
		host._play(host.ATTACK, false)
		var r: Dictionary = _job.hit(_job_i, _job.info.get("tool", "hand"), work_tier())
		for item in r.drops:
			player.add_item(item, r.drops[item])
	return Vector3.ZERO


# ------------------------------------------------------------------ following

func _idle_move(delta: float) -> Vector3:
	if player.party_command == "hold":
		var back := hold_pos - host.global_position
		back.y = 0.0
		if back.length() > 1.0:
			host._face(back, delta * 6.0)
			host._play(host.WALK)
			return back.normalized() * host.move_speed * 1.5
		host._play(host.IDLE)
		return Vector3.ZERO
	return _formation(delta)


## Slot behind the player: left, right, then further back.
func _slot() -> Vector3:
	var idx: int = maxi(player.party.find(host), 0)
	var back: Vector3 = player.global_transform.basis.z * Vector3(1, 0, 1)
	if back.length() < 0.1:
		back = Vector3.BACK
	var angle: float = [-0.7, 0.7, 0.0][idx % 3]
	var p: Vector3 = player.global_position + back.normalized().rotated(Vector3.UP, angle) * (2.4 + 0.6 * idx)
	p.y = host.global_position.y
	return p


func _formation(delta: float) -> Vector3:
	var to := _slot() - host.global_position
	to.y = 0.0
	var d := to.length()
	if d > 0.9:
		host._face(to, delta * 8.0)
		host._play(host.WALK)
		return to.normalized() * clampf(d * 2.2, 2.0, 9.0)
	host._face(player.global_position - host.global_position, delta * 3.0)
	host._play(host.IDLE)
	return Vector3.ZERO
