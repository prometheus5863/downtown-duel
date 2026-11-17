extends SceneTree
## M2: treats, bond, favourite flavour, hostile creatures need calming, Alphas (Mythic only, phase 2, drops),
## Lustre variants, treat shops and the save round trip of inventory + bond.

const Harness := preload("res://tests/harness.gd")
const Game := preload("res://scripts/game.gd")
const Data := preload("res://scripts/data.gd")


func _init() -> void:
	var t := Harness.new(self, 300.0)
	await process_frame

	# ---- data ----
	var treats := Data.table("treats")
	var tiers := {}
	for id in treats:
		tiers[treats[id].tier] = true
	t.eq(tiers.keys().size(), 4, "four treat tiers exist")
	var no_flavour := []
	for sp in Data.creatures():
		if Data.creature(sp).get("flavour", "") == "":
			no_flavour.append(sp)
	t.eq(no_flavour, [], "every species has a favourite flavour")

	var arena: Node = await t.world()
	var p: Node = arena.get_node("Player")
	t.eq(p.item_count("berry_bite"), 3, "new game starts with a few treats")

	# ---- calm creature: pet + treats raise bond, favourite counts double ----
	var cat: Node = t.find_enemy("Whiskers")             # Blob/Cat: favourite savory
	t.eq(cat.favourite_flavour(), "savory", "flavour comes from data")
	var d: Dictionary = cat.talk_begin()
	t.ok("Pet it" in d.options, "calm creature offers petting")
	t.ok(d.options.any(func(o): return o.begins_with("Give Berry Bite")), "treats you carry are offered")
	cat.talk_choose("Pet it")
	t.eq(cat.bond, 8, "petting adds bond")
	cat.talk_choose("Pet it")
	t.eq(cat.bond, 8, "petting counts once per conversation")
	d = cat.talk_choose("Give Berry Bite (3)")
	t.eq(cat.bond, 20, "simple non-favourite treat adds its bond")
	t.eq(p.item_count("berry_bite"), 2, "a given treat is used up")
	d = cat.talk_choose("Give Salt Cracker (2)")
	t.eq(cat.bond, 44, "favourite flavour doubles the bond")
	t.ok(not ("Join me!" in d.options), "doesn't ask to join below the threshold")
	p.add_item("mushroom_pie", 1)                        # hearty savory: 22 x2
	d = cat.talk_choose("Give Mushroom Pie (1)")
	t.ok(cat.bond >= cat.JOIN_BOND and "Join me!" in d.options, "asks to join once bond reaches the threshold")
	cat.talk_end("leave")

	# ---- hostile creature: must be calmed or weakened, treat calms it ----
	var gloop: Node = t.find_enemy("Gloop")
	d = gloop.talk_begin()
	t.ok("Fight!" in d.options and not ("Pet it" in d.options), "hostile creature can't be petted")
	d = gloop.talk_choose("Try to calm it down")
	t.eq(d.end, "fight", "full-HP hostile creature refuses to calm down")
	gloop.talk_end("leave")
	gloop.talk_begin()
	gloop.talk_choose("Give Berry Bite (2)")
	t.ok(gloop.bond > 0, "a treat to a hostile creature adds bond")
	d = gloop.talk_choose("Try to calm it down")
	t.eq(d.end, "spared", "a treat lets you calm a hostile creature")
	gloop.talk_end("spared")
	t.ok(gloop.bond >= 20 + 12, "sparing adds bond on top")
	t.eq(gloop.is_hostile(), false, "calmed creature is no longer hostile")

	# ---- Alphas ----
	var alpha: Node = t.find_enemy("ALPHA SKULLCRUSHER")
	t.ok(alpha != null and alpha.is_alpha, "Alpha is placed from data/alphas.json")
	t.ok(t.find_enemy("MUSHROOM KING").is_alpha and t.find_enemy("SKY WYRM").is_alpha, "existing bosses are their zone's Alpha")
	var alphas: Array = get_nodes_in_group("enemy").filter(func(e): return e.is_alpha)
	t.eq(alphas.size(), 4, "four Alphas in the world")
	t.eq(alpha.treat_bond("royal_jelly"), 0, "Alpha refuses non-Mythic treats")
	t.ok(alpha.treat_bond("mythic_morsel") >= 60, "Alpha accepts a Mythic treat")
	var base_wind: float = alpha.windup_time
	alpha.take_damage(alpha.max_hp / 2 + 5, Vector3.FORWARD, p, "")
	t.ok(alpha._phase2 and alpha.windup_time < base_wind, "Alpha enters phase 2 below half HP")
	var spores: int = p.item_count("bone_totem")
	alpha.take_damage(99999, Vector3.FORWARD, p, "")
	await t.frames(2)
	t.eq(p.item_count("bone_totem"), spores + 1, "defeated Alpha drops its material")
	t.eq(p.item_count("mythic_morsel"), 1, "and (until crafting) a Mythic Morsel")

	# befriend another Alpha with the Mythic treat
	var king: Node = t.find_enemy("ALPHA VOIDWALKER")
	king.hp = int(king.max_hp * 0.25)
	king.talk_begin()
	d = king.talk_choose("Give Royal Jelly (1)")       # not owned -> just checks no crash
	d = king.talk_choose("Give Mythic Morsel (1)")
	t.ok(king.bond >= 60, "Mythic treat bonds an Alpha")
	d = king.talk_choose("Try to calm it down")
	t.eq(d.end, "spared", "weakened + treated Alpha calms down")
	king.talk_end("spared")
	t.eq(p.item_count("void_crystal"), 1, "calming an Alpha also gives its drop")
	d = king.talk_begin()
	d = king.talk_choose("Pet it")
	t.ok("Join me!" in d.options, "bonded Alpha asks to join")
	d = king.talk_choose("Join me!")
	king.talk_end(d.end)
	t.ok(king in p.party and king.is_alpha, "an Alpha can join the party")

	# ---- Lustre ----
	var bun: Node = t.find_enemy("Bunbun")
	var hp0: int = bun.max_hp
	bun.set_lustre(true)
	t.eq(bun.max_hp, int(round(hp0 * 1.1)), "Lustre gives +10% HP")
	t.ok(bun.display_name.begins_with("Lustre "), "Lustre is named")
	var n_lustre: int = get_nodes_in_group("enemy").filter(func(e): return e.lustre and e != bun).size()
	t.ok(n_lustre <= 3, "Lustre is rare (%d naturally in the world)" % n_lustre)
	bun.bond = 70
	bun.talk_begin()
	d = bun.talk_choose("Join me!")
	bun.talk_end(d.end)
	t.ok(p.storage.size() + p.party.size() >= 2, "Lustre creature befriended")

	# ---- shop sells treats ----
	var tobin: Node = arena.get_node("World/Village/Tobin")
	t.ok("treat" in tobin.stock, "Oakvale merchant sells treats")
	var hud: Node = arena.get_node("HUD")
	p.coins = 100
	hud.menus.open_for(tobin)
	await t.frames(2)
	var labels: Array = hud.menus._buttons.map(func(b): return b.text)
	t.ok(labels.any(func(l): return "Honey Cake" in l), "hearty treats are in the Oakvale shop", str(labels))
	t.ok(not labels.any(func(l): return "Royal Jelly" in l), "royal treats are not (price cap)")
	hud.menus._buy_treat("honey_cake")
	t.eq(p.item_count("honey_cake"), 1, "buying a treat puts it in the inventory")
	t.eq(p.coins, 75, "and costs its price")
	hud.menus.close()

	# ---- save round trip: inventory + bond ----
	var cat_id := String(arena.get_path_to(cat))
	var cat_bond: int = cat.bond
	var inv: Dictionary = p.inventory.duplicate()
	arena.get_node("Game").save()
	await t.drop(arena)
	Game.load_on_start = true
	arena = await t.world()
	await t.frames(3)
	p = arena.get_node("Player")
	t.eq(p.inventory, inv, "inventory restored")
	t.eq(arena.get_node(cat_id).bond, cat_bond, "a wild creature's bond is restored")
	t.ok(p.party.any(func(c): return c.is_alpha), "the Alpha companion is restored as an Alpha")
	await t.drop(arena)
	Game.load_on_start = false

	t.finish()
