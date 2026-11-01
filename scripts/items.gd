extends RefCounted
## Item database. Slots: weapon (atk), armor (def), charm (special bonuses).
## Add items here; a shop lists every item with price > 0 whose slot is in its stock (npc.gd `stock`).
## Armor `look` dresses the player (avatar.gd): parts = outfit glTF basenames (must be in player.tscn's
## wardrobe), tex = albedo swap (wardrobe_tex basename), tint / metal for plate, hood hides the hair.

const DB := {
	"wood_knuckles":  {"name": "Wooden Knuckles", "slot": "weapon", "price": 0,   "atk": 0,  "desc": "Better than bare fists. Barely."},
	"bronze_knuckles":{"name": "Bronze Knuckles", "slot": "weapon", "price": 60,  "atk": 4,  "desc": "+4 Strike damage"},
	"steel_gauntlets":{"name": "Steel Gauntlets", "slot": "weapon", "price": 180, "atk": 9,  "desc": "+9 Strike damage"},
	"dragon_claws":   {"name": "Dragon Claws",    "slot": "weapon", "price": 340, "atk": 14, "ember": 4, "desc": "+14 Strike, +4 Ember"},
	"cloth_tunic":    {"name": "Cloth Tunic",     "slot": "armor",  "price": 0,   "def": 0,  "desc": "Comfy. Not protective.",
		"look": {"parts": ["Male_Peasant"]}},
	"traveler_garb":  {"name": "Traveler's Garb", "slot": "armor",  "price": 45,  "def": 2,  "desc": "-2 damage taken",
		"look": {"parts": ["Male_Peasant"], "tex": "T_Peasant_2_BaseColor"}},
	"leather_vest":   {"name": "Leather Vest",    "slot": "armor",  "price": 80,  "def": 3,  "desc": "-3 damage taken",
		"look": {"parts": ["Male_Ranger_Body", "Male_Ranger_Arms", "Male_Ranger_Legs", "Male_Ranger_Feet_Boots"]}},
	"ranger_kit":     {"name": "Ranger Kit",      "slot": "armor",  "price": 150, "def": 5,  "speed": 0.05, "desc": "-5 damage, +5% speed",
		"look": {"parts": ["Male_Ranger"], "hood": true}},
	"shadow_cloak":   {"name": "Shadow Cloak",    "slot": "armor",  "price": 200, "def": 5,  "dodge_cd": 0.2, "desc": "-5 damage, faster dodge",
		"look": {"parts": ["Male_Ranger"], "tex": "T_Ranger_3_BaseColor", "tint": Color(0.55, 0.5, 0.6), "hood": true}},
	"iron_plate":     {"name": "Iron Plate",      "slot": "armor",  "price": 220, "def": 7,  "desc": "-7 damage taken",
		"look": {"parts": ["Male_Ranger_Body", "Male_Ranger_Arms", "Male_Ranger_Legs", "Male_Ranger_Feet_Boots", "Male_Ranger_Acc_Pauldron"],
			"tex": "T_Ranger_Plate_BaseColor", "tint": Color(0.72, 0.75, 0.8), "metal": 0.75}},
	"obsidian_plate": {"name": "Obsidian Plate",  "slot": "armor",  "price": 320, "def": 9,  "ember": 5, "desc": "-9 damage, +5 Ember",
		"look": {"parts": ["Male_Ranger_Body", "Male_Ranger_Arms", "Male_Ranger_Legs", "Male_Ranger_Feet_Boots", "Male_Ranger_Acc_Pauldron"],
			"tex": "T_Ranger_Plate_BaseColor", "tint": Color(0.42, 0.3, 0.55), "metal": 0.6}},
	"royal_plate":    {"name": "Royal Plate",     "slot": "armor",  "price": 450, "def": 12, "desc": "-12 damage taken. Shiny.",
		"look": {"parts": ["Male_Ranger_Body", "Male_Ranger_Arms", "Male_Ranger_Legs", "Male_Ranger_Feet_Boots", "Male_Ranger_Acc_Pauldron"],
			"tex": "T_Ranger_Plate_BaseColor", "tint": Color(1.0, 0.8, 0.4), "metal": 0.85}},
	"ember_charm":    {"name": "Ember Charm",     "slot": "charm",  "price": 120, "ember": 10, "desc": "+10 Ember damage"},
	"swift_charm":    {"name": "Swift Charm",     "slot": "charm",  "price": 100, "speed": 0.15, "dodge_cd": 0.25, "desc": "+15% move speed, faster dodge"},
	"guardian_charm": {"name": "Guardian Charm",  "slot": "charm",  "price": 160, "def": 3, "regen": 4.0, "desc": "-3 damage, faster regen"},
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


## stock: slots this shop sells (empty = everything); max_price: 0 = no limit.
static func shop_list(stock: Array = [], max_price := 0) -> Array:
	var ids := []
	for id in DB:
		if DB[id].price > 0 and (stock.is_empty() or DB[id].slot in stock) and (max_price == 0 or DB[id].price <= max_price):
			ids.append(id)
	return ids
