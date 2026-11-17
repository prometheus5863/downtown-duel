extends RefCounted
## Game data tables from data/*.json (creatures, moves, elements, ...), parsed once and cached.
## The Python generators read the same files, so stats live in exactly one place.

static var _cache := {}


static func table(name: String) -> Dictionary:
	if not _cache.has(name):
		var f := FileAccess.open("res://data/%s.json" % name, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text()) if f else null
		if not (parsed is Dictionary):
			push_error("data/%s.json is missing or not a JSON object" % name)
			parsed = {}
		_cache[name] = parsed
	return _cache[name]


static func creatures() -> Dictionary:
	return table("creatures")


static func creature(species: String) -> Dictionary:
	return creatures().get(species, {})


static func move(id: String) -> Dictionary:
	return table("moves").get(id, {})


## "res://assets/monsters/Blob/glTF/GreenBlob.gltf" -> "Blob/GreenBlob" ("" when it isn't a monster model).
static func species_of(model_path: String) -> String:
	var i := model_path.find("assets/monsters/")
	if i < 0:
		return ""
	return model_path.substr(i + 16).replace("/glTF/", "/").get_basename()


# ------------------------------------------------------------------ elements

## Damage multiplier of an `attack` element hitting a `defend` element. Each element beats the next one in
## elements.order (wrapping) and is weak against the one before it. "" (no element) is always neutral.
static func element_mult(attack: String, defend: String) -> float:
	var e := table("elements")
	var order: Array = e.get("order", [])
	var a := order.find(attack)
	var d := order.find(defend)
	if a < 0 or d < 0:
		return 1.0
	if (a + 1) % order.size() == d:
		return float(e.strong)
	if (d + 1) % order.size() == a:
		return float(e.weak)
	return 1.0


static func element_color(element: String) -> Color:
	var hex: String = table("elements").get("colors", {}).get(element, "")
	return Color(hex) if hex != "" else Color(0.85, 0.85, 0.85)


static func element_name(element: String) -> String:
	return table("elements").get("names", {}).get(element, "Neutral")


# ------------------------------------------------------------------ companion stats

static func xp_to_next(level: int) -> int:
	return 30 + level * 25


static func companion_hp(species: String, level: int) -> int:
	return int(round(float(creature(species).get("hp", 80)) * (1.0 + 0.12 * (level - 1))))


static func companion_atk(species: String, level: int) -> int:
	return int(round(float(creature(species).get("atk", 8)) * (1.0 + 0.10 * (level - 1))))
