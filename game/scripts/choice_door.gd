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
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.85
	if texture_path != "" and ResourceLoader.exists(texture_path):
		mat.albedo_texture = load(texture_path)
	else:
		mat.albedo_color = Color(0.12, 0.12, 0.13)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(WIDTH, HEIGHT, THICK)
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = Vector3(WIDTH / 2.0, HEIGHT / 2.0, 0.0)
	add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(WIDTH, HEIGHT, THICK)
	col.shape = shape
	col.position = mesh.position
	add_child(col)


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
