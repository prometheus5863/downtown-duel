extends SceneTree
## M0: save / load round trip, corrupt save, migration.

const Harness := preload("res://tests/harness.gd")
const Game := preload("res://scripts/game.gd")
const SaveGame := preload("res://scripts/save_game.gd")


func _init() -> void:
	var t := Harness.new(self)
	await process_frame

	# ---- change everything that is saved ----
	var arena: Node = await t.world()
	var p: Node = arena.get_node("Player")
	var game: Node = arena.get_node("Game")
	p.coins = 321
	p.level = 4
	p.xp = 17
	p.max_hp = 136
	p.hp = 90.0
	p.owned.append("iron_plate")
	p.equip("iron_plate")
	p.route.spared = 2
	p.global_position = Vector3(-80, 1.1, -80)
	p.spawn_point = Vector3(-80, 1.1, -80)
	game.flags["tutorial_done"] = true

	var chest: Node = null
	for n in get_nodes_in_group("interactable"):
		if n.get("opened") == false:
			chest = n
			break
	var chest_id := String(arena.get_path_to(chest))
	chest.talk_begin()
	var coins_after_chest: int = p.coins

	var pal: Node = t.find_enemy("Clucky")
	var pal_id := String(arena.get_path_to(pal))
	pal.talk_begin()
	pal.talk_end("friend")
	var pal_name: String = pal.display_name
	var calm: Node = t.find_enemy("Whiskers")
	var calm_id := String(arena.get_path_to(calm))
	calm.talk_begin()
	calm.talk_end("spared")
	var xp_before_save: int = p.xp
	var level_before_save: int = p.level

	t.ok(game.save(), "save() writes the file")
	t.ok(SaveGame.exists(Harness.TEST_SAVE), "save file exists")
	await t.drop(arena)

	# ---- fresh world, load ----
	Game.load_on_start = true
	arena = await t.world()
	p = arena.get_node("Player")
	game = arena.get_node("Game")
	t.eq(p.coins, coins_after_chest, "coins restored")
	t.eq(p.level, level_before_save, "level restored")
	t.eq(p.xp, xp_before_save, "xp restored")
	t.eq(p.max_hp, 136, "max hp restored")
	t.ok(absf(p.hp - 90.0) < 3.0, "hp restored", str(p.hp))
	t.eq(p.gear.armor, "iron_plate", "equipped armor restored")
	t.ok("iron_plate" in p.owned, "owned gear restored")
	t.eq(p.route.spared, 3, "route counters restored")
	t.ok(p.global_position.distance_to(Vector3(-80, 1.1, -80)) < 1.5, "position restored", str(p.global_position))
	t.eq(game.flags.get("tutorial_done"), true, "world flags restored")
	t.eq(arena.get_node(chest_id).opened, true, "opened chest stays opened")
	t.eq(arena.get_node(chest_id).can_interact(), false, "opened chest can't be looted twice")
	t.ok(arena.get_node_or_null(pal_id) == null or arena.get_node(pal_id).is_queued_for_deletion(),
		"befriended wild creature does not respawn in the wild")
	t.eq(p.party.size(), 1, "companion is back in the party")
	t.ok(p.party.size() == 1 and p.party[0].display_name == pal_name and p.party[0].friend, "it is the same companion")
	t.eq(arena.get_node(calm_id).spared, true, "spared creature stays spared")
	t.eq(arena.get_node(calm_id).is_hostile(), false, "spared creature is not hostile")
	t.ok(arena.get_node_or_null("IntroCamera") == null or arena.get_node("IntroCamera").is_queued_for_deletion(),
		"intro is skipped when a save exists")
	t.eq(p.can_control, true, "player has control after load")
	await t.drop(arena)

	# ---- corrupt save -> clean new game, no crash ----
	var f := FileAccess.open(Harness.TEST_SAVE, FileAccess.WRITE)
	f.store_string("{{{ not json")
	f.close()
	t.eq(SaveGame.read(Harness.TEST_SAVE), {}, "corrupt save reads as empty")
	arena = await t.world()
	t.eq(arena.get_node("Player").coins, 0, "corrupt save starts a clean game")
	await t.drop(arena)

	# ---- migration fills in missing keys ----
	var old := SaveGame.migrate({"version": 0, "player": {"coins": 5}, "world": {"chests": ["x"]}})
	t.eq(old.version, SaveGame.VERSION, "migrate bumps the version")
	t.ok(old.world.has("sanctuaries") and old.has("party") and old.world.chests == ["x"], "migrate fills missing keys, keeps data")

	t.finish()
