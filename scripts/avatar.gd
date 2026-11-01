extends RefCounted
## Dresses a Universal Animation Library rig (UAL1_Standard.glb instance) with skinned parts:
## Universal Base Character head + hair and Modular Character Outfits pieces. They all share the
## UAL skeleton (same 65 bone names), so each part's MeshInstance3D is moved onto the rig's Skeleton3D.
##   look = {parts: Array[PackedScene], tex: Texture2D (outfit albedo swap, optional),
##           tint: Color (outfit tint), metal: float (0..1 metallic for plate armor), hair: Color}

const DRESSED := "_dressed"


static func skeleton_of(model: Node) -> Skeleton3D:
	var s := model.find_children("*", "Skeleton3D", true, false)
	return s[0] if s.size() > 0 else null


## Removes previously added parts and hides the grey mannequin.
static func undress(model: Node) -> void:
	var skel := skeleton_of(model)
	if skel == null:
		return
	for c in skel.get_children():
		if c.has_meta(DRESSED):
			skel.remove_child(c)
			c.queue_free()
		elif c is MeshInstance3D:
			c.visible = false


static func dress(model: Node, look: Dictionary) -> void:
	var skel := skeleton_of(model)
	if skel == null:
		return
	undress(model)
	var tex: Texture2D = look.get("tex")
	var tint: Color = look.get("tint", Color.WHITE)
	var metal: float = look.get("metal", 0.0)
	var hair: Color = look.get("hair", Color(0.35, 0.22, 0.13))
	for scene in look.get("parts", []):
		if scene == null:
			continue
		var src: Node = scene.instantiate()
		for mi in src.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mi
			m.get_parent().remove_child(m)
			m.owner = null
			m.transform = Transform3D.IDENTITY
			skel.add_child(m)
			m.skeleton = NodePath("..")
			m.set_meta(DRESSED, true)
			_restyle(m, tex, tint, metal, hair)
		src.free()


## Outfit materials (MI_Peasant / MI_Ranger) get the texture swap, tint and metal; hair + eyebrows
## (greyscale MI_Hair_* textures, meant to be coloured) get the hair colour; skin and eyes untouched.
static func _restyle(m: MeshInstance3D, tex: Texture2D, tint: Color, metal: float, hair: Color) -> void:
	for i in m.get_surface_override_material_count():
		var base := m.get_active_material(i)
		if not (base is StandardMaterial3D):
			continue
		if base.resource_name.begins_with("MI_Hair"):
			var hm: StandardMaterial3D = base.duplicate()
			hm.albedo_color = hair
			m.set_surface_override_material(i, hm)
			continue
		if not _is_outfit(base) or (tex == null and tint == Color.WHITE and metal == 0.0):
			continue
		var mat: StandardMaterial3D = base.duplicate()
		if tex:
			mat.albedo_texture = tex
		mat.albedo_color = tint
		if metal > 0.0:
			mat.metallic = metal
			mat.metallic_texture = null
			mat.roughness = 0.35
		m.set_surface_override_material(i, mat)


static func _is_outfit(mat: Material) -> bool:
	var n := mat.resource_name
	return n.contains("Peasant") or n.contains("Ranger")
