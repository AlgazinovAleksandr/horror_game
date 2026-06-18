extends StaticBody3D
class_name MirageDoor

# A blood-red door identical to the back doors of earlier levels — the player's
# instinct says "a way out." Open it and it swings onto blank yellow wallpaper,
# mocking the hope of retreat and spiking panic. Builds its own mesh; backrooms.gd
# only places + orients it flush on a wall, facing inward.

const PANIC := 10.0
const SIZE := Vector2(1.0, 2.1)

var _opened: bool = false
var _creak: AudioStreamPlayer3D
var _hinge: Node3D


func _ready() -> void:
	# hinge at the left edge so the door swings into the corridor
	_hinge = Node3D.new()
	_hinge.position = Vector3(-SIZE.x / 2.0, 0, 0)
	add_child(_hinge)

	var door := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(SIZE.x, SIZE.y, 0.08)
	door.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.01, 0.01)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.02, 0.02)
	mat.emission_energy_multiplier = 1.5
	door.set_surface_override_material(0, mat)
	door.position = Vector3(SIZE.x / 2.0, SIZE.y / 2.0, 0)
	_hinge.add_child(door)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE.x, SIZE.y, 0.12)
	col.shape = shape
	col.position = Vector3(0, SIZE.y / 2.0, 0)
	add_child(col)

	_creak = AudioStreamPlayer3D.new()
	var s := GameState.load_audio("creak")
	if s:
		_creak.stream = s
	_creak.unit_size = 5.0
	add_child(_creak)


func interact() -> void:
	if _opened:
		return
	_opened = true
	if _creak.stream:
		_creak.play()
	# swing open onto the blank wall behind
	var tween := create_tween()
	tween.tween_property(_hinge, "rotation:y", deg_to_rad(105.0), 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var player := get_parent().get_node_or_null("Player")
	if player and player.has_method("add_panic"):
		player.add_panic(PANIC)
