extends Node3D
class_name Torch3D

# Wall-mounted 3D torch built from primitives: bracket + cup + emissive flame +
# flickering warm OmniLight + CalmZone (panic sanctuary). corridor.gd places it
# flush against a wall, facing into the corridor (local +Z = into the room).

@export var lit: bool = true
@export var calm_radius: float = 3.0

var _light: OmniLight3D
var _flame: MeshInstance3D
var _phase: float = 0.0

const _CALM_ZONE := preload("res://scripts/calm_zone.gd")


func _ready() -> void:
	_phase = randf() * 100.0
	_build()


func _build() -> void:
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = Color(0.25, 0.17, 0.08)
	bronze.metallic = 0.7
	bronze.roughness = 0.5

	var bracket := MeshInstance3D.new()
	var bracket_mesh := BoxMesh.new()
	bracket_mesh.size = Vector3(0.06, 0.3, 0.06)
	bracket.mesh = bracket_mesh
	bracket.set_surface_override_material(0, bronze)
	add_child(bracket)

	var cup := MeshInstance3D.new()
	var cup_mesh := CylinderMesh.new()
	cup_mesh.top_radius = 0.07
	cup_mesh.bottom_radius = 0.03
	cup_mesh.height = 0.16
	cup.mesh = cup_mesh
	cup.position = Vector3(0, 0.18, 0.08)
	cup.set_surface_override_material(0, bronze)
	add_child(cup)

	if not lit:
		return

	_flame = MeshInstance3D.new()
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.05
	flame_mesh.height = 0.16
	_flame.mesh = flame_mesh
	_flame.position = Vector3(0, 0.32, 0.08)
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.55, 0.15)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.55, 0.15)
	flame_mat.emission_energy_multiplier = 3.0
	_flame.set_surface_override_material(0, flame_mat)
	add_child(_flame)

	_light = OmniLight3D.new()
	_light.position = Vector3(0, 0.35, 0.12)
	_light.light_color = Color(1.0, 0.62, 0.3)
	_light.light_energy = 1.3
	_light.omni_range = 6.5
	_light.omni_attenuation = 1.4
	add_child(_light)

	var zone: Area3D = _CALM_ZONE.new()
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = calm_radius
	col.shape = sphere
	zone.add_child(col)
	add_child(zone)


func extinguish() -> void:
	# Lights-out event: kill flame, fade the light, drop the sanctuary.
	lit = false
	set_process(false)
	if _flame:
		_flame.visible = false
	if _light:
		var tween := create_tween()
		tween.tween_property(_light, "light_energy", 0.0, 0.35)
	for child in get_children():
		if child is CalmZone:
			child.queue_free()


func _process(delta: float) -> void:
	if not _light:
		return
	_phase += delta
	_light.light_energy = 1.3 + sin(_phase * 9.7) * 0.18 + sin(_phase * 23.1) * 0.09
	if _flame:
		var s := 1.0 + sin(_phase * 14.3) * 0.12
		_flame.scale = Vector3(s, 1.0 + sin(_phase * 11.1) * 0.18, s)
