extends SceneTree
## M1: element wheel, befriending into party / storage, companion combat, exhaustion, rest, shared XP,
## party commands, ledger swaps and the save round trip of party + storage.

const Harness := preload("res://tests/harness.gd")
const Game := preload("res://scripts/game.gd")
const Data := preload("res://scripts/data.gd")


func _init() -> void:
	var t := Harness.new(self, 300.0)
	await process_frame

	# ---- data ----
	t.eq(Data.creatures().size(), 50, "every monster model has a creature entry")
	var bad := []
	for sp in Data.creatures():
		var c: Dictionary = Data.creatures()[sp]
		if not ResourceLoader.exists("res://" + c.model) or c.moves.size() != 2 or Data.element_name(c.element) == "Neutral":
			bad.append(sp)
		for m in c.moves:
			if Data.move(m).is_empty():
				bad.append(sp + ":" + m)
	t.eq(bad, [], "creature entries have a model, an element and 2 known moves")
	t.eq(Data.element_mult("ember", "verdant"), 1.5, "ember beats verdant")
	t.eq(Data.element_mult("verdant", "ember"), 0.67, "verdant is weak against ember")
	t.eq(Data.element_mult("tide", "ember"), 1.5, "tide beats ember (wheel wraps)")
	t.eq(Data.element_mult("ember", "stone"), 1.0, "non-adjacent elements are neutral")
	t.eq(Data.element_mult("", "tide"), 1.0, "no element is neutral")
	t.eq(Data.species_of("res://assets/monsters/Blob/glTF/GreenBlob.gltf"), "Blob/GreenBlob", "species from model path")

	# ---- befriending ----
	var arena: Node = await t.world()
	var p: Node = arena.get_node("Player")
	p.global_position = Vector3(-122, 1.1, -18)               # Oakvale: peaceful critters
	await t.frames(5)
	var names := ["Clucky", "Bok", "Whiskers", "Barkley"]
	var ids := []
	for n in names:
		var e: Node = t.find_enemy(n)
		ids.append(String(arena.get_path_to(e)))
		e.talk_begin()
		e.talk_end("friend")
	await t.frames(2)
	t.eq(p.party.size(), 3, "first three befriended creatures join the party")
	t.eq(p.storage.size(), 1, "the fourth waits in storage")
	t.eq(p.storage[0].get("name"), "Barkley", "storage holds the fourth creature's record")
	t.ok(p.party.all(func(c): return c.friend and not c.is_in_group("enemy")), "party members are friends, not enemies")
	t.eq(p.route.friends, 4, "route counts every befriended creature")
	var clucky: Node = p.party[0]
	t.eq(clucky.element, "gale", "companion element comes from data")
	t.ok(clucky.brain != null, "companion has a brain")

	# ---- follow ----
	p.global_position += Vector3(8, 0, 0)
	await t.frames(120)
	t.ok(clucky.global_position.distance_to(p.global_position) < 5.0, "companions follow the player",
		str(clucky.global_position.distance_to(p.global_position)))

	# ---- attack command: companions kill a target without player input ----
	var target: Node = t.find_enemy("Mushnub")
	target.max_hp = 60
	target.hp = 60
	target.global_position = p.global_position + Vector3(0, -1.05, -5)
	target.home = target.global_position
	p.target = target
	p.locked = true
	p.command_party("attack")
	var gave_xp: int = clucky.record.get("xp", 0)
	var lvl: int = clucky.level
	for i in 60 * 15:
		if not target.alive:
			break
		await physics_frame
	t.eq(target.alive, false, "companions defeat the locked target on their own")
	t.ok(clucky.level > lvl or int(clucky.record.get("xp", 0)) > gave_xp, "XP is shared with companions")
	p.locked = false

	# ---- wild creature retargets the companion that hits it ----
	var brute: Node = t.find_enemy("Elder Mushnub")
	brute.global_position = p.global_position + Vector3(4, -1.05, 0)
	brute.home = brute.global_position
	brute.take_damage(5, Vector3.RIGHT, clucky, "gale")
	var retargeted := false
	for i in 20:
		if brute._current_foe() == clucky:
			retargeted = true
		await physics_frame
	t.ok(retargeted or brute._foe == clucky, "a creature hit by a companion turns on it")
	brute._foe = null
	brute.talk_end("spared")

	# ---- exhaustion and rest ----
	clucky.take_damage(9999, Vector3.FORWARD, brute, "")
	t.eq(clucky.exhausted, true, "companion at 0 HP is exhausted, not dead")
	t.eq(clucky.alive, true, "exhausted companion stays in the party")
	var spot: Node = t.find_enemy("Bunbun")
	p.target = spot
	p.locked = true
	p.command_party("attack")
	await t.frames(30)
	t.eq(clucky.brain.state, "follow", "exhausted companion does not attack")
	p.locked = false
	p.command_party("follow")
	p.hp = 10.0
	p.rest()
	t.eq(clucky.exhausted, false, "rest revives exhausted companions")
	t.eq(clucky.hp, clucky.max_hp, "rest heals companions to full")
	t.eq(int(p.hp), p.max_hp, "rest heals the player")

	# ---- hold / return ----
	p.command_party("hold")
	var held: Vector3 = clucky.global_position
	p.global_position += Vector3(-10, 0, 0)
	await t.frames(90)
	t.ok(clucky.global_position.distance_to(held) < 2.0, "hold keeps companions in place")
	p.command_party("heel")
	await t.frames(150)
	t.ok(clucky.global_position.distance_to(p.global_position) < 5.0, "return brings them back")

	# ---- element damage on creatures ----
	var plant: Node = t.find_enemy("Gloop")           # verdant
	var before: int = plant.hp
	plant.take_damage(10, Vector3.FORWARD, p, "ember")
	t.eq(before - plant.hp, 15, "ember hits verdant for 1.5x")
	plant.talk_end("spared")

	# ---- ledger swaps ----
	var barkley_rec: Dictionary = p.storage[0]
	t.ok(p.deposit(1), "deposit a party member")
	t.eq(p.party.size(), 2, "party shrinks on deposit")
	t.eq(p.storage.size(), 2, "storage grows on deposit")
	t.ok(p.withdraw(0), "withdraw from storage")
	await t.frames(3)
	t.eq(p.party.size(), 3, "party is full again")
	t.eq(p.party[2].display_name, String(barkley_rec.name), "withdrawn companion is spawned from its record")
	t.eq(p.party[2].level, int(barkley_rec.level), "withdrawn companion keeps its level")
	t.eq(p.withdraw(0), false, "can't withdraw into a full party")

	# ---- save round trip ----
	var party_names: Array = p.party.map(func(c): return c.display_name)
	var party_levels: Array = p.party.map(func(c): return c.level)
	var stored_names: Array = p.storage.map(func(r): return r.name)
	clucky.hp = 7
	var game: Node = arena.get_node("Game")
	t.ok(game.save(), "save with a party")
	await t.drop(arena)
	Game.load_on_start = true
	arena = await t.world()
	await t.frames(3)
	p = arena.get_node("Player")
	t.eq(p.party.map(func(c): return c.display_name), party_names, "party restored in order")
	t.eq(p.party.map(func(c): return c.level), party_levels, "companion levels restored")
	t.eq(p.storage.map(func(r): return r.name), stored_names, "storage restored")
	t.eq(p.party[0].hp, 7, "companion HP restored")
	t.eq(p.party_command, "heel", "party command restored")
	var gone := 0
	for id in ids:
		var n := arena.get_node_or_null(id)
		if n == null or n.is_queued_for_deletion():
			gone += 1
	t.eq(gone, 4, "befriended wild creatures (party and storage) don't respawn in the wild")
	t.ok(p.party.all(func(c): return c.friend and c.brain != null), "loaded companions have brains")
	await t.drop(arena)
	Game.load_on_start = false

	t.finish()
