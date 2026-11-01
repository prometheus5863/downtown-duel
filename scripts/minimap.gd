extends Control
## Corner minimap: roads, zone discs (named, visited ones brighter), live monsters, the player arrow.
## Map is north-up; world -Z is up. Roads come from the "road" group (gen_world.py tags the road meshes).

const WORLD := 150.0                    ## half-size of the walkable square

var player: Node3D
var zones: Array = []                    ## HUD.ZONES rows: [name, Vector2 centre, radius]
var _visited := {}
var _roads: Array = []                   # [Vector2 a, Vector2 b, width]
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r in get_tree().get_nodes_in_group("road"):
		var b: Basis = r.global_transform.basis
		var half: float = r.get_meta("length", 0.0) * 0.5
		var along := Vector2(b.z.x, b.z.z).normalized()
		var c := Vector2(r.global_position.x, r.global_position.z)
		_roads.append([c - along * half, c + along * half, r.get_meta("width", 6.0)])


func _process(delta: float) -> void:
	_t += delta
	if _t > 0.1:                         # 10 Hz is plenty
		_t = 0.0
		if player:
			var p := Vector2(player.global_position.x, player.global_position.z)
			for z in zones:
				if p.distance_to(z[1]) < z[2]:
					_visited[z[0]] = true
		queue_redraw()


func _to_map(w: Vector2) -> Vector2:
	return (w / WORLD * 0.5 + Vector2(0.5, 0.5)) * size


func _draw() -> void:
	var s := size.x / (WORLD * 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.08, 0.07, 0.72))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.85, 0.4, 0.6), false, 2.0)
	for r in _roads:
		draw_line(_to_map(r[0]), _to_map(r[1]), Color(0.75, 0.65, 0.5, 0.75), maxf(r[2] * s, 2.0))
	var font := get_theme_default_font()
	for z in zones:
		var seen: bool = _visited.has(z[0])
		draw_circle(_to_map(z[1]), z[2] * s, Color(0.4, 0.75, 0.45, 0.45 if seen else 0.18))
	for z in zones:
		var nm: String = z[0] if _visited.has(z[0]) else "?"
		var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 10).x
		draw_string_outline(font, _to_map(z[1]) + Vector2(-w / 2, 4), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0, 0, 0, 0.9))
		draw_string(font, _to_map(z[1]) + Vector2(-w / 2, 4), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.95, 0.8))
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.get("alive") == false:
			continue
		var ep := _to_map(Vector2(e.global_position.x, e.global_position.z))
		draw_circle(ep, 3.5 if e.get("is_boss") else 1.6, Color(1, 0.3, 0.25, 0.9))
	if player:
		var pp := _to_map(Vector2(player.global_position.x, player.global_position.z))
		var f: Vector3 = -player.global_transform.basis.z
		var fwd := Vector2(f.x, f.z).normalized()
		var side := Vector2(-fwd.y, fwd.x)
		draw_colored_polygon(PackedVector2Array([pp + fwd * 7, pp - fwd * 4 + side * 4, pp - fwd * 4 - side * 4]), Color(0.4, 0.85, 1.0))
