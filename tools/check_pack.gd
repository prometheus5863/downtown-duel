extends SceneTree
## Smoke test for an exported pack (catches files missing from the export):
##   godot --headless --main-pack export/web/index.pck -s <abs path>/tools/check_pack.gd
## Loads the world from the pack, steps it, and checks that the data tables and key assets came along.
## Lives in tools/ (not exported); run it with an absolute path.


func _init() -> void:
	await process_frame
	var fails := []
	for t in ["creatures", "moves", "elements", "treats", "alphas", "materials", "blocks", "tools", "resources"]:
		if not FileAccess.file_exists("res://data/%s.json" % t):
			fails.append("data/%s.json missing" % t)
	var scene: PackedScene = load("res://scenes/arena.tscn")
	if scene == null:
		fails.append("arena.tscn missing")
	else:
		var arena := scene.instantiate()
		root.add_child(arena)
		for i in 120:
			await physics_frame
		var monsters := get_nodes_in_group("enemy").size()
		if monsters < 50:
			fails.append("only %d creatures" % monsters)
		if get_nodes_in_group("mine").is_empty() or get_first_node_in_group("mine").grid.get_used_cells().size() < 500:
			fails.append("mine missing or empty")
		if get_nodes_in_group("resource_field").size() < 5:
			fails.append("resource fields missing")
		var p := arena.get_node_or_null("Player")
		if p == null or p.get("_model") == null:
			fails.append("player model missing")
		print("pack: %d creatures, %d resource fields" % [monsters, get_nodes_in_group("resource_field").size()])
	if fails.is_empty():
		print("PACK OK")
	else:
		print("PACK FAIL: ", ", ".join(fails))
	quit(0 if fails.is_empty() else 1)
