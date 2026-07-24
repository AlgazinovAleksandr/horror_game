extends StaticBody3D
class_name ChoiceDoor

# KONTUR Gate 1 — one of the two doors in the vestibule. Both doors LOOK the same
# kind of thing and both swing open on interact; only `is_correct` decides what is
# behind them and whether the level scores a strike. The level (kontur.gd) owns the
# consequence — this node just reports the choice once.
#
# The node sits at the HINGE; the panel mesh and its collider are offset half a
# width along +x, so rotating this body swings the door properly.

signal chosen(correct: bool)

const WIDTH := 1.4
const HEIGHT := 2.2
const THICK := 0.12
const OPEN_ANGLE := deg_to_rad(95.0)
const OPEN_TIME := 0.7

@export var is_correct: bool = false
@export var texture_path: String = ""

var _used: bool = false


func _ready() -> void:
	_build()


func _build() -> void:
	# Issue 24 (ISSUES_SOLUTIONS.md): a BoxMesh does not map a full texture per
	# face, so putting `texture_path` directly on the box (the old approach)
	# rendered a magnified crop — no window, no hinge detail. The box stays a
	# plain dark edge/depth; the art lives on QuadMesh faces front and back,
	# same pattern as door.gd:build_visual().
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.08, 0.08, 0.09)
	edge_mat.roughness = 0.85

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(WIDTH, HEIGHT, THICK)
	mesh.mesh = box
	mesh.material_override = edge_mat
	mesh.position = Vector3(WIDTH / 2.0, HEIGHT / 2.0, 0.0)
	add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(WIDTH, HEIGHT, THICK)
	col.shape = shape
	col.position = mesh.position
	add_child(col)

	var face_mat := StandardMaterial3D.new()
	face_mat.roughness = 0.85
	if texture_path != "" and ResourceLoader.exists(texture_path):
		face_mat.albedo_texture = load(texture_path)
	else:
		face_mat.albedo_color = Color(0.12, 0.12, 0.13)

	for z_sign in [1.0, -1.0]:
		var face := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(WIDTH, HEIGHT)
		face.mesh = qm
		face.material_override = face_mat
		face.position = Vector3(WIDTH / 2.0, HEIGHT / 2.0,
			z_sign * (THICK / 2.0 + 0.004))
		if z_sign < 0.0:
			face.rotation.y = PI
		add_child(face)


func interact() -> void:
	if _used:
		return
	_used = true
	chosen.emit(is_correct)
	_swing()


func _swing() -> void:
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation:y", rotation.y - OPEN_ANGLE, OPEN_TIME)
