extends Node
## Session state: loads the save on start, autosaves, and turns world state into / out of the save document.
## Lives in arena.tscn as the last node ("Game"), so everything it talks to is ready first.
## World objects are identified by their node path relative to the scene root (generator names are stable).

signal saved
signal loaded

const SaveGame := preload("res://scripts/save_game.gd")

## Tests point this somewhere else before instancing the scene, so they never touch the real save.
static var override_path := ""
## Tests set this to false to start from a clean world regardless of what is on disk.
static var load_on_start := true

@export var autosave_interval := 120.0

var play_time := 0.0
var flags := {}                         ## free-form world flags (quests, tutorial steps)
var sanctuaries: Array = []             ## discovered Sanctuary ids (M5)
var _player: Node
var _root: Node


func _ready() -> void:
	add_to_group("game")
	_root = get_parent()
	_player = _root.get_node_or_null("Player")
	var t := Timer.new()
	t.wait_time = autosave_interval
	t.autostart = true
	t.timeout.connect(save)
	add_child(t)
	if load_on_start and SaveGame.exists(path()):
		load_game.call_deferred()            # after the scene finishes building: loading spawns companions


func _process(delta: float) -> void:
	play_time += delta


func _notification(what: int) -> void:
	# Closing the window / hiding the browser tab: last chance to persist.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if is_inside_tree() and _player:
			save()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			save()
		elif event.keycode == KEY_F9 and SaveGame.exists(path()):
			get_tree().reload_current_scene()


func path() -> String:
	return override_path if override_path != "" else SaveGame.SAVE_PATH


# ------------------------------------------------------------------ save

func save() -> bool:
	if _player == null or not _player.alive:
		return false                      # never checkpoint a corpse
	var ok := SaveGame.write(collect(), path())
	if ok:
		saved.emit()
	return ok


func collect() -> Dictionary:
	var d := SaveGame.blank()
	d.play_time = play_time
	d.player = _player.to_save()
	d.party = _player.party_records()
	d.storage = _player.storage.duplicate(true)
	# Wild creatures that became companions (party or storage) must not reappear in the wild.
	for r in d.party + d.storage:
		if String(r.get("origin", "")) != "":
			d.world.befriended.append(r.origin)
	d.world.flags = flags
	d.world.sanctuaries = sanctuaries
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.get("opened") == true:
			d.world.chests.append(_id(n))
		elif n.get("spared") == true:
			d.world.spared.append(_id(n))
	return d


# ------------------------------------------------------------------ load

func load_game() -> bool:
	var d := SaveGame.read(path())
	if d.is_empty():
		return false
	apply(d)
	loaded.emit()
	return true


func apply(d: Dictionary) -> void:
	play_time = float(d.get("play_time", 0.0))
	flags = d.world.flags
	sanctuaries = d.world.sanctuaries
	_player.from_save(d.player)
	for id in d.world.chests:
		var c := _root.get_node_or_null(id)
		if c and c.has_method("set_opened"):
			c.set_opened()
	for id in d.world.spared:
		var e := _root.get_node_or_null(id)
		if e and e.has_method("set_spared"):
			e.set_spared()
	for id in d.world.befriended:
		var e := _root.get_node_or_null(id)
		if e:
			e.queue_free()                     # this one lives in the party / storage records now
	_player.load_companions(d.party, d.storage)
	# A returning player skips the intro flyover.
	var intro := _root.get_node_or_null("IntroCamera")
	if intro and intro.has_method("_finish"):
		var hud := _root.get_node_or_null("HUD")
		if hud:
			hud.hide_title()
		intro._finish()


func _id(n: Node) -> String:
	return String(_root.get_path_to(n))
