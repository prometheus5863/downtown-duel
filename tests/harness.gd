extends RefCounted
## Tiny assertion helper for headless SceneTree tests. Prints PASS / FAIL lines; tools/run_tests.py greps them.

const Game := preload("res://scripts/game.gd")
const SaveGame := preload("res://scripts/save_game.gd")
const TEST_SAVE := "user://test_save.json"

var failed := 0
var passed := 0
var tree: SceneTree


func _init(t: SceneTree, timeout := 240.0) -> void:
	tree = t
	# Watchdog: a script error stops the test coroutine, which would otherwise leave Godot running forever.
	t.create_timer(timeout, true, false, true).timeout.connect(func():
		print("FAIL watchdog: test did not finish within %d s (script error above?)" % timeout)
		t.quit(1))
	Game.override_path = TEST_SAVE          # never touch the real save
	Game.load_on_start = false
	SaveGame.erase(TEST_SAVE)


func ok(cond: bool, name: String, detail := "") -> void:
	if cond:
		passed += 1
		print("PASS ", name)
	else:
		failed += 1
		print("FAIL ", name, ("  -> " + detail) if detail != "" else "")


func eq(got, want, name: String) -> void:
	ok(got == want, name, "got %s, want %s" % [got, want])


## Fresh world with the intro skipped. Returns the Arena root.
func world() -> Node:
	var arena: Node = load("res://scenes/arena.tscn").instantiate()
	tree.root.add_child(arena)
	for i in 3:
		await tree.process_frame
	var intro := arena.get_node_or_null("IntroCamera")
	if intro:
		arena.get_node("HUD").hide_title()
		intro._finish()
	for i in 5:
		await tree.physics_frame
	return arena


func drop(arena: Node) -> void:
	arena.queue_free()
	for i in 3:
		await tree.process_frame


func frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


func find_enemy(display_name: String) -> Node:
	for e in tree.get_nodes_in_group("enemy"):
		if e.display_name == display_name:
			return e
	return null


func finish() -> void:
	SaveGame.erase(TEST_SAVE)
	print("%s: %d passed, %d failed" % ["OK" if failed == 0 else "FAILED", passed, failed])
	tree.quit(1 if failed > 0 else 0)
