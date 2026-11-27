extends Camera3D
## Cinematic camera for conversations. When a menu opens it glides from the gameplay camera to a shot of the
## speaker (over the hero's shoulder for creatures, a portrait for shopkeepers), framed so the subject sits in
## the left part of the screen and the menu panel on the right doesn't cover it. close_up() pushes in on a
## creature (petting, treats); release() glides back and hands control back to the gameplay camera.

const GLIDE := 0.55

var player: Node3D
var _tween: Tween
var _subject: Node3D
var _active := false


func _ready() -> void:
	current = false
	fov = 55.0


func is_active() -> bool:
	return _active


## Glide to a framing of `subject`.
func focus(subject: Node3D) -> void:
	_subject = subject
	if not _active:
		global_transform = player.camera.global_transform
		fov = player.camera.fov
		current = true
		_active = true
	_glide(_shot(subject, false), 50.0)


## Push in on the subject (petting, a favourite treat).
func close_up() -> void:
	if _active and is_instance_valid(_subject):
		_glide(_shot(_subject, true), 42.0, 0.45)


## Back to the normal framing of the subject after a close-up.
func relax() -> void:
	if _active and is_instance_valid(_subject):
		_glide(_shot(_subject, false), 50.0, 0.5)


func release() -> void:
	if not _active:
		return
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_blend_to.bind(global_transform, fov), 0.0, 1.0, 0.4)
	_tween.tween_callback(func():
		_active = false
		current = false
		player.camera.current = true)


func _blend_to(w: float, from: Transform3D, from_fov: float) -> void:
	global_transform = from.interpolate_with(player.camera.global_transform, w)
	fov = lerpf(from_fov, player.camera.fov, w)


func _glide(to: Transform3D, to_fov: float, t := GLIDE) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "global_transform", to, t)
	_tween.tween_property(self, "fov", to_fov, t)


## Camera transform for a shot of `s`: over the hero's right shoulder (close-ups of creatures come in at their
## side). The look-at point is shifted to the right so the subject lands left of centre, clear of the menu panel.
func _shot(s: Node3D, close: bool) -> Transform3D:
	var h: float = float(s.get("height")) if s.get("height") != null else 1.8
	var head := s.global_position + Vector3.UP * h * 0.7
	var to_s := s.global_position - player.global_position
	to_s.y = 0.0
	if to_s.length() < 0.1:
		to_s = -player.global_transform.basis.z
	var fwd := to_s.normalized()                      # hero -> subject
	var right := fwd.cross(Vector3.UP).normalized()
	var size := clampf(h, 0.8, 4.0)
	var eye: Vector3
	if close and s.get("friend") != null:             # creatures: right up to it, slightly to the side
		eye = s.global_position - fwd * (1.0 + size * 0.9) + right * (0.4 + size * 0.3) + Vector3.UP * (size * 0.6 + 0.4)
	else:                                             # everyone else / normal framing: over the hero's right shoulder
		eye = player.global_position - fwd * 1.9 + right * 1.05 + Vector3.UP * (1.3 + size * 0.2)
	var aim := head + right * ((size * 0.2 + 0.2) if close else (size * 0.35 + 0.35))
	var t := Transform3D(Basis.IDENTITY, eye)
	return t.looking_at(aim, Vector3.UP)
