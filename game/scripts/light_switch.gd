extends StaticBody3D
class_name LightSwitch

# A wall-mounted light switch for the Intro Room. interact() flips it once and
# emits `flipped` — the level owns the actual reveal sequence (audio, path-glow
# fade-out, ceiling lights, ambient tween), matching the project's existing
# division of labor (props emit, the owning level scene reacts). Self-building
# from primitives, same pattern as breaker.gd.
#
# Deliberately plays no audio itself, unlike breaker.gd's own interact() — the
# switch_clunk needs to land in step with intro_room.gd's broader reveal beat,
# not fire in isolation from the prop.

signal flipped

var _used: bool = false
var _led_mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build()


func _build() -> void:
	var plate := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.2, 0.04)
	plate.mesh = bm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.12, 0.12, 0.13)
	pm.metallic = 0.5
	pm.roughness = 0.6
	plate.set_surface_override_material(0, pm)
	add_child(plate)

	var led := MeshInstance3D.new()
	var qm := PlaneMesh.new()
	qm.size = Vector2(0.02, 0.03)
	led.mesh = qm
	led.rotation_degrees.x = -90.0
	led.position = Vector3(0, 0, 0.021)
	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color = Color(0.9, 0.7, 0.4)
	_led_mat.emission_enabled = true
	_led_mat.emission = Color(0.9, 0.65, 0.3)
	_led_mat.emission_energy_multiplier = 0.5
	led.set_surface_override_material(0, _led_mat)
	add_child(led)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.25, 0.35, 0.15)
	col.shape = shape
	add_child(col)


func interact() -> void:
	if _used:
		return
	_used = true
	var t := create_tween()
	t.tween_property(_led_mat, "emission_energy_multiplier", 2.0, 0.1)
	t.tween_property(_led_mat, "emission_energy_multiplier", 0.5, 0.2)
	flipped.emit()
