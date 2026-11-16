extends RefCounted
## Save file I/O. One JSON document at user://save.json (IndexedDB on the web).
## Schema is described in docs/PLAN.md; bump VERSION and extend migrate() when it changes.

const SAVE_PATH := "user://save.json"
const VERSION := 1


static func blank() -> Dictionary:
	return {
		"version": VERSION, "saved_at": 0, "play_time": 0.0,
		"player": {}, "inventory": {}, "party": [], "storage": [],
		"world": {"chests": [], "befriended": [], "spared": [], "flags": {}, "sanctuaries": []},
	}


static func exists(path := SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


static func write(data: Dictionary, path := SAVE_PATH) -> bool:
	data["version"] = VERSION
	data["saved_at"] = int(Time.get_unix_time_from_system())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("save failed: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()                             # close = flush; needed for the browser to persist it
	return true


## Returns {} when there is no usable save (missing, unreadable or not a save document).
static func read(path := SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()                 # instance parse: a corrupt file must not log an engine error
	var err := json.parse(f.get_as_text())
	f.close()
	if err != OK or not (json.data is Dictionary) or not json.data.has("player"):
		return {}
	return migrate(json.data)


static func erase(path := SAVE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Brings an older save up to VERSION: fills in every key blank() has, so loaders never check for presence.
static func migrate(d: Dictionary) -> Dictionary:
	var out := blank()
	for k in d:
		out[k] = d[k]
	var w := blank().world as Dictionary
	for k in w:
		if not out.world.has(k):
			out.world[k] = w[k]
	out.version = VERSION
	return out


static func v3(a) -> Vector3:
	return Vector3(a[0], a[1], a[2]) if a is Array and a.size() == 3 else Vector3.ZERO


static func arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
