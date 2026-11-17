extends SceneTree
## M3: resource nodes (deplete / respawn / tool gating), block mine (deterministic layout, ores by depth,
## tier gating, break / place, player tool ray), companion Work order, tool shops, save of mine changes.

const Harness := preload("res://tests/harness.gd")
const Game := preload("res://scripts/game.gd")
const Data := preload("res://scripts/data.gd")


func _init() -> void:
	var t := Harness.new(self, 300.0)
	await process_frame

	# ---- data ----
	var missing := []
	for id in Data.table("blocks"):
		if not id.begins_with("_") and not ResourceLoader.exists("res://assets/voxel/tiles/%s.png" % Data.table("blocks")[id].tile):
			missing.append(id)
	for id in Data.table("resources"):
		if not id.begins_with("_") and not ResourceLoader.exists("res://" + Data.table("resources")[id].model):
			missing.append(id)
	t.eq(missing, [], "every block tile and resource model exists")

	var arena: Node = await t.world()
	var p: Node = arena.get_node("Player")
	var mine: Node = get_first_node_in_group("mine")
	t.ok(mine != null, "the quarry mine is in the world")
	t.eq(p.best_tool("pick").tier, 1, "new game starts with a wooden pickaxe")
	t.eq(p.best_tool("axe").tier, 1, "and a wooden axe")

	# ---- mine layout ----
	var census: Dictionary = mine.census()
	t.ok(census.get("stone", 0) > 300 and census.get("dirt", 0) > 50, "hill is mostly stone under dirt", str(census))
	t.ok(census.get("copper", 0) > 0 and census.get("iron", 0) > 0, "ores are generated", str(census))
	var bad_depth := 0
	for cell in mine.grid.get_used_cells():
		var b: String = mine.block_at(cell)
		var band = Data.table("blocks")[b].get("depth")
		if band and mine._height[Vector2i(cell.x, cell.z)] - 1 - cell.y < int(band[0]):
			bad_depth += 1
	t.eq(bad_depth, 0, "every ore sits at least its minimum depth under the surface")
	var before: Dictionary = census
	mine.generate()
	t.eq(mine.census(), before, "same seed gives the same hill")
	t.eq(mine.block_at(Vector3i(12, 0, 0)), "", "entrance tunnel is open")

	# ---- tier gating + hardness ----
	var copper := Vector3i(-1, -1, -1)
	for cell in mine.grid.get_used_cells():
		if mine.block_at(cell) == "copper":
			copper = cell
			break
	var r: Dictionary = mine.hit(copper, 1)
	t.ok(not r.broke and r.msg.contains("needs"), "copper needs a better pickaxe than wood")
	var hits := 0
	while mine.block_at(copper) == "copper" and hits < 10:
		r = mine.hit(copper, 2)
		hits += 1
	t.eq(hits, 4, "copper takes its hardness in hits with a stone pickaxe")
	t.eq(r.drop, "copper_ore", "copper drops copper ore")
	t.ok(mine.diff.has("%d,%d,%d" % [copper.x, copper.y, copper.z]), "broken block is recorded in the diff")

	# ---- player tool ray: walk to the tunnel mouth, aim at the wall, mine it ----
	var mouth: Vector3 = mine.cell_center(Vector3i(12, 0, 0))
	p.global_position = Vector3(mouth.x, 1.05, mouth.z - 3.0)
	p.velocity = Vector3.ZERO
	p.cam_pivot.rotation = Vector3(0, PI, 0)                  # look +z, into the hill
	p.spring_arm.rotation.x = 0.0
	p.spring_arm.spring_length = 0.3
	await t.frames(8)
	p.global_position = Vector3(mouth.x - 1.6, 1.05, mouth.z - 1.0)   # beside the tunnel: facing solid wall
	await t.frames(8)
	var tt: Dictionary = p.tool_target()
	t.eq(tt.get("type", ""), "block", "aiming at the hill targets a block")
	var dirt_before: int = p.item_count("dirt") + p.item_count("stone")
	var target_cell: Vector3i = tt.get("cell", Vector3i.ZERO)
	for i in 30:
		p._tool_cd = 0.0
		p.use_tool()
		if mine.block_at(target_cell) == "":
			break
	t.eq(mine.block_at(target_cell), "", "use_tool breaks the targeted block")
	t.ok(p.item_count("dirt") + p.item_count("stone") > dirt_before, "the block's drop goes to the inventory")

	# ---- place ----
	p.inventory["stone"] = 3
	var empty := Vector3i(12, 2, 0)
	t.eq(mine.place(empty, "stone"), true, "stone can be placed in an empty cell")
	t.eq(mine.block_at(empty), "stone", "placed block is there")
	t.eq(mine.place(empty, "stone"), false, "can't place into a filled cell")
	t.eq(mine.place(Vector3i(12, 0, 1), "copper"), false, "ores can't be placed")
	var under: Vector3i = mine.world_to_cell(p.global_position)
	t.eq(mine.place(under, "stone"), false, "can't place a block inside the player")

	# ---- resource nodes ----
	var trees: Node = null
	var rocks: Node = null
	for f in get_nodes_in_group("resource_field"):
		if f.kind == "tree" and trees == null:
			trees = f
		if f.kind == "rock" and f.get_parent().name == "Quarry":
			rocks = f
	t.ok(trees != null and rocks != null, "tree and rock fields exist")
	t.eq(rocks.tool_ok("axe", 4), false, "rocks need a pickaxe, not an axe")
	t.eq(trees.tool_ok("axe", 1), true, "a wooden axe chops trees")
	var wood: int = p.item_count("wood")
	var res := {}
	for i in 4:
		res = trees.hit(0, "axe", 1)
	t.ok(res.done and res.drops.get("wood", 0) >= 2, "four hits with a wooden axe fell a tree", str(res))
	t.eq(trees.available(0), false, "felled tree is gone")
	trees._process(float(trees.info.respawn) + 1.0)
	t.eq(trees.available(0), true, "it grows back after its respawn time")
	trees.hit(0, "axe", 3)
	res = trees.hit(0, "axe", 3)
	t.ok(res.done, "a better axe takes fewer hits")
	var veins: Node = null
	for f in get_nodes_in_group("resource_field"):
		if f.kind == "copper_vein":
			veins = f
	t.eq(veins.hit(0, "pick", 1).msg != "", true, "copper veins refuse a wooden pickaxe")

	# player gathers berries by hand
	var bushes: Node = null
	for f in get_nodes_in_group("resource_field"):
		if f.kind == "berry_bush":
			bushes = f
	p.spring_arm.spring_length = 6.0
	p.spring_arm.rotation.x = -0.35
	p.global_position = bushes.world_pos(0) + Vector3(0, 1.05, 1.0)
	p.look_at(bushes.world_pos(0) + Vector3(0, 1.05, 0), Vector3.UP)
	await t.frames(4)
	var berries: int = p.item_count("berries")
	tt = p.tool_target()
	t.eq(tt.get("type", ""), "node", "standing at a bush targets it")
	p._tool_cd = 0.0
	p.use_tool()
	t.ok(p.item_count("berries") > berries, "gathering by hand gives berries")

	# ---- shops sell tools ----
	t.ok("tool" in arena.get_node("World/Village/Tobin").stock, "Oakvale sells tools")
	var hud: Node = arena.get_node("HUD")
	p.coins = 500
	hud.menus.open_for(arena.get_node("World/Quarter/Brenna"))
	await t.frames(2)
	hud.menus._buy_tool("iron_pick")
	t.eq(p.best_tool("pick").tier, 4, "bought iron pickaxe becomes the best pick")
	hud.menus.close()

	# ---- companion Work ----
	var golem: Node = t.find_enemy("Pebbling")                 # stone: mining skill
	for c in [golem]:
		c.talk_begin()
		c.talk_end("friend")
	t.ok("mining" in golem.brain.skills(), "stone creatures can mine")
	p.global_position = rocks.world_pos(0) + Vector3(3, 1.05, 0)
	golem.global_position = p.global_position + Vector3(0, -1.0, 2)
	var stone: int = p.item_count("stone")
	p.command_party("work")
	for i in 60 * 20:
		if p.item_count("stone") > stone:
			break
		await physics_frame
	t.ok(p.item_count("stone") > stone, "a working companion harvests rock for you")
	p.command_party("follow")

	# ---- save: mine changes persist ----
	var mine_diff: Dictionary = mine.diff.duplicate()
	var inv_tools: int = p.item_count("iron_pick")
	arena.get_node("Game").save()
	await t.drop(arena)
	Game.load_on_start = true
	arena = await t.world()
	await t.frames(3)
	mine = get_first_node_in_group("mine")
	p = arena.get_node("Player")
	t.eq(mine.diff, mine_diff, "mine diff restored")
	t.eq(mine.block_at(copper), "", "broken block stays broken after loading")
	t.eq(mine.block_at(empty), "stone", "placed block is still there after loading")
	t.eq(inv_tools, p.item_count("iron_pick"), "tools are kept in the inventory")
	await t.drop(arena)
	Game.load_on_start = false
	t.finish()
