extends Area3D
class_name Beartrap

# Floor trap. Stepping in springs the jaws: loud snap, camera jolt, panic spike,
# 3 s limp. Never an instant fail — but brutal when panic is already high.
# Builds its own meshes so corridor.gd only has to place it.

const PANIC_HIT := 25.0
const SLOW_DURATION := 3.0
const JAW_OPEN_DEG := 75.0

var _sprung: bool = false
var _jaw_l: MeshInstance3D
var _jaw_r: MeshInstance3D
var _snap_player: AudioStreamPlayer3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_build_visuals()

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.32
	shape.height = 0.4
	col.shape = shape
	col.position.y = 0.2
	add_child(col)

	_snap_player = AudioStreamPlayer3D.new()
	var snap := GameState.load_audio("beartrap_snap")
	if snap:
		_snap_player.stream = snap
	_snap_player.unit_size = 6.0
	add_child(_snap_player)


func _build_visuals() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.18, 0.18, 0.2)
	metal.metallic = 0.9
	metal.roughness = 0.35
	# faint glint so an attentive player can spot the trap in the dark
	metal.emission_enabled = true
	metal.emission = Color(0.15, 0.17, 0.21)
	metal.emission_energy_multiplier = 0.12

	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.28
	base_mesh.bottom_radius = 0.28
	base_mesh.height = 0.03
	base.mesh = base_mesh
	base.position.y = 0.015
	base.set_surface_override_material(0, metal)
	add_child(base)

	_jaw_l = _build_jaw(metal, -1.0)
	_jaw_r = _build_jaw(metal, 1.0)


func _build_jaw(metal: StandardMaterial3D, side: float) -> MeshInstance3D:
	# Hinge pivot sits at the base edge; the jaw plate hangs off it.
	var jaw := MeshInstance3D.new()
	var plate := BoxMesh.new()
	plate.size = Vector3(0.5, 0.26, 0.02)
	jaw.mesh = plate
	jaw.set_surface_override_material(0, metal)
	jaw.position = Vector3(0, 0.13, 0)  # local: plate extends upward from hinge

	var hinge := Node3D.new()
	hinge.position = Vector3(0, 0.03, side * 0.24)
	hinge.rotation_degrees.x = side * JAW_OPEN_DEG
	hinge.add_child(jaw)
	add_child(hinge)
	return jaw


func _on_body_entered(body: Node3D) -> void:
	if _sprung or not body.has_method("add_panic"):
		return
	_sprung = true

	if _snap_player.stream:
		_snap_player.play()
	body.add_panic(PANIC_HIT)
	body.apply_slow(SLOW_DURATION)
	if body.has_method("jolt_camera"):
		body.jolt_camera(0.09, 0.5)

	for jaw_mesh in [_jaw_l, _jaw_r]:
		var hinge: Node3D = jaw_mesh.get_parent()
		var tween := create_tween()
		tween.tween_property(hinge, "rotation_degrees:x", 0.0, 0.07) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
