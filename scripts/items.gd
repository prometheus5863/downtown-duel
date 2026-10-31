extends RefCounted
## Item database. Slots: weapon (atk), armor (def), charm (special bonuses).
## Add items here; the shop lists everything with price > 0.

const DB := {
	"wood_knuckles":  {"name": "Wooden Knuckles", "slot": "weapon", "price": 0,   "atk": 0,  "desc": "Better than bare fists. Barely."},
	"bronze_knuckles":{"name": "Bronze Knuckles", "slot": "weapon", "price": 60,  "atk": 4,  "desc": "+4 Strike damage"},
	"steel_gauntlets":{"name": "Steel Gauntlets", "slot": "weapon", "price": 180, "atk": 9,  "desc": "+9 Strike damage"},
	"cloth_tunic":    {"name": "Cloth Tunic",     "slot": "armor",  "price": 0,   "def": 0,  "desc": "Comfy. Not protective."},
	"leather_vest":   {"name": "Leather Vest",    "slot": "armor",  "price": 80,  "def": 3,  "desc": "-3 damage taken per hit"},
	"iron_plate":     {"name": "Iron Plate",      "slot": "armor",  "price": 220, "def": 7,  "desc": "-7 damage taken per hit"},
	"ember_charm":    {"name": "Ember Charm",     "slot": "charm",  "price": 120, "ember": 10, "desc": "+10 Ember damage"},
	"swift_charm":    {"name": "Swift Charm",     "slot": "charm",  "price": 100, "speed": 0.15, "dodge_cd": 0.25, "desc": "+15% move speed, faster dodge"},
}
const STARTER := {"weapon": "wood_knuckles", "armor": "cloth_tunic", "charm": ""}


static func get_item(id: String) -> Dictionary:
	return DB.get(id, {})


static func stat(gear: Dictionary, key: String) -> float:
	var total := 0.0
	for slot in gear:
		var it: Dictionary = DB.get(gear[slot], {})
		total += float(it.get(key, 0.0))
	return total


static func shop_list() -> Array:
	var ids := []
	for id in DB:
		if DB[id].price > 0:
			ids.append(id)
	return ids
