extends Area3D
## Ember projectile. Builds its own mesh/collider so it needs no .tscn.

signal hit

var shooter: Node
var direction := Vector3.FORWARD
var damage := 15
var speed := 18.0
var life := 1.5
var _done := false


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.0)
	mat.emission_energy_multiplier = 3.0
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	sphere.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	add_child(mi)

	var shape := SphereShape3D.new()
	shape.radius = 0.3
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)

	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.5, 0.1)
	glow.omni_range = 3.0
	add_child(glow)

	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	life -= delta
	if life <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if _done or body == shooter:
		return
	_done = true
	if body.has_method("take_damage"):
		body.take_damage(damage, direction)
		hit.emit()
	queue_free()
