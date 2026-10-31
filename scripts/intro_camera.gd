extends Camera3D
## Intro flyover: swoops over the rooftops along a smooth spline and lands
## exactly on the gameplay camera, then hands control to the player.
## Any key skips it.

@export var player: Node
@export var hud: Node
@export var duration := 9.0

## Spline waypoints. The last one equals the gameplay camera's start position.
@export var points: PackedVector3Array = [
	Vector3(170, 95, 150), Vector3(60, 70, 150), Vector3(-90, 55, 60), Vector3(-30, 24, 30),
	Vector3(0, 7, 11), Vector3(0, 4.06, 5.64)]

var s := 0.0                                  ## spline progress 0..1 (tweened)
var look_target := Vector3(0, 0, -6)          ## tweened toward the player
var _done := false


func _ready() -> void:
	player.can_control = false
	current = true
	global_position = points[0]
	var t := create_tween().set_parallel()
	t.tween_property(self, "s", 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "look_target", Vector3(0, 2, 0), duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(_finish)
	if hud:
		hud.show_title(duration)


func _process(_delta: float) -> void:
	if _done:
		return
	global_position = _sample(s)
	if global_position.distance_to(look_target) > 0.01:
		look_at(look_target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventScreenTouch or event is InputEventMouseButton) and event.pressed:
		if hud:
			hud.hide_title()
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	player.camera.current = true
	player.can_control = true
	queue_free()


## Catmull-Rom through all points.
func _sample(t: float) -> Vector3:
	var n := points.size() - 1
	var f := clampf(t, 0.0, 1.0) * n
	var i := mini(int(f), n - 1)
	var u := f - i
	var p0 := points[maxi(i - 1, 0)]
	var p1 := points[i]
	var p2 := points[i + 1]
	var p3 := points[mini(i + 2, n)]
	return p1.cubic_interpolate(p2, p0, p3, u)
