extends SceneTree
## Presentation layer: talk camera framing / close-up / hand-back, petting reaction, shop detail card with
## armor preview and stat deltas, level-up celebration, character menu (pause, tabs, equip from the menu).

const Harness := preload("res://tests/harness.gd")


func _init() -> void:
	var t := Harness.new(self, 240.0)
	await process_frame
	var arena: Node = await t.world()
	var p: Node = arena.get_node("Player")
	var hud: Node = arena.get_node("HUD")
	var menus: Node = hud.menus
	await t.frames(2)
	t.ok(menus.cam.is_inside_tree(), "talk camera is in the world")

	# ---- talking: camera frames the creature, close-up on petting, hands back on close ----
	var cat: Node = t.find_enemy("Whiskers")
	p.global_position = cat.global_position + Vector3(0, 1.05, 3.0)
	await t.frames(3)
	menus.open_for(cat)
	await t.frames(40)
	t.ok(menus.cam.current and menus.cam.is_active(), "talk camera takes over when a conversation opens")
	var to_cat: Vector3 = cat.global_position - menus.cam.global_position
	t.ok((-menus.cam.global_basis.z).dot(to_cat.normalized()) > 0.85, "it looks at the creature")
	t.ok(menus._bond_row.visible, "creature dialogue shows the bond bar")
	t.ok(menus._chips.get_child_count() >= 2, "header shows element and level chips")
	var hearts_before: int = cat.get_children().filter(func(c): return c is Label3D and c.text == "♥").size()
	menus._choose("Pet it")
	await t.frames(2)
	var hearts: int = cat.get_children().filter(func(c): return c is Label3D and c.text == "♥").size()
	t.ok(hearts > hearts_before, "petting floats hearts over the creature")
	await t.frames(40)
	t.ok(menus.cam.fov < 46.0, "petting pushes the camera in", str(menus.cam.fov))
	t.ok(not String(menus._text.text).contains("Bond  ♥"), "bond line is shown as the bar, not as text")
	menus.close()
	await t.frames(40)
	t.ok(p.camera.current and not menus.cam.is_active(), "closing hands the camera back to gameplay")

	# ---- shop: detail card, armor preview, stat deltas, buy with the selected item ----
	var brenna: Node = arena.get_node("World/Quarter/Brenna")
	p.global_position = brenna.global_position + Vector3(-2, 1.05, 0)
	p.coins = 1000
	await t.frames(3)
	menus.open_for(brenna)
	await t.frames(5)
	t.ok(menus._detail.get_child_count() > 0, "shop opens with the first item's detail card")
	var plate := -1
	for i in menus._shop_rows.size():
		if menus._shop_rows[i][1] == "iron_plate":
			plate = i
	menus._select(plate)
	await t.frames(5)
	t.ok(menus._preview != null and menus._preview.is_inside_tree(), "armor shows a 3D preview of you wearing it")
	var card_text := _texts(menus._detail)
	t.ok(card_text.contains("Defense") and card_text.contains("▲7"), "detail card shows the defense gain", card_text)
	menus._buy_selected()
	await t.frames(3)
	t.ok("iron_plate" in p.owned and p.gear.armor == "iron_plate", "Buy on the detail card buys and equips it")
	t.eq(menus._selected, plate, "the same item stays selected after buying")
	menus.close()
	await t.frames(20)

	# ---- level up ----
	p.reward(p.xp_to_next() + 1, 0, "")
	await t.frames(2)
	t.ok(is_instance_valid(hud._lvl_card), "level up shows the level-up card")
	t.ok(p.get_children().any(func(c): return c is OmniLight3D), "and a light burst on the hero")
	await t.frames(30)

	# ---- character menu ----
	var cm: Node = hud.character_menu
	cm.open()
	await t.frames(3)
	t.ok(cm.is_open and paused, "character menu opens and pauses the game")
	t.ok(cm._body.get_child_count() > 3, "gear tab lists stats and slots")
	var owned_armor: int = p.owned.filter(func(id): return preload("res://scripts/items.gd").get_item(id).get("slot") == "armor").size()
	t.ok(owned_armor >= 2, "test owns at least two armors")
	cm._equip("cloth_tunic")
	await t.frames(2)
	t.eq(p.gear.armor, "cloth_tunic", "equipping from the character menu works")
	cm.show_tab("bag")
	await t.frames(2)
	var grid: Node = cm._body.get_child(0)
	t.eq(grid.get_child_count(), p.inventory.size(), "bag tab shows one tile per item")
	cm.show_tab("party")
	await t.frames(2)
	t.ok(cm._body.get_child_count() >= 1, "party tab builds")
	cm.close()
	await t.frames(2)
	t.ok(not paused, "closing the character menu unpauses")

	# ---- phones: UI scale from the real screen size ----
	var TC := preload("res://scripts/touch_controls.gd")
	t.ok(absf(TC.ui_scale_for(390.0, 1.0) - 1.477) < 0.01, "iPhone landscape (390 CSS px tall) gets ~1.5x UI")
	t.ok(absf(TC.ui_scale_for(1170.0, 3.0) - 1.477) < 0.01, "same phone reported in device pixels (x3) gets the same")
	t.eq(TC.ui_scale_for(768.0, 1.0), 1.0, "tablets stay at 1x")
	t.eq(TC.ui_scale_for(1080.0, 1.0), 1.0, "desktop stays at 1x")
	t.eq(TC.ui_scale_for(200.0, 1.0), 1.8, "scale is capped")

	await t.drop(arena)
	t.finish()


func _texts(n: Node) -> String:
	var out := ""
	for c in n.find_children("*", "Label", true, false):
		out += c.text + " | "
	for c in n.find_children("*", "Button", true, false):
		out += c.text + " | "
	return out
