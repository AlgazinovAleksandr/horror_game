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
# ⚠️ DERIVED FROM THE ARTWORK, not chosen (2026-08-18, K-T1). `door_black_leaf.png` and
# `door_red_leaf.png` are the two generated doors CROPPED to the leaf — the originals
# carried the concrete wall and reveal around them, so a 1.4 x 2.2 mesh squashed them
# **1.571x** (Issue 35 / X24, and this is the prop gate 1 asks the player to read).
# The two crops land at 0.7380 and 0.7589; WIDTH is fixed by the 1.4 m doorway, so
# HEIGHT = WIDTH / mean(0.7380, 0.7589) = 1.87, which leaves each leaf within 1.4 % of
# its own artwork — comfortably inside `check_art_aspect.gd`'s 10 % band.
#
# ⚠️ BOTH DOORS MUST BE THE SAME SIZE. Sizing each from its own texture would make the
# SHAPE a second tell alongside the colour, and gate 1's answer is the colour alone.
# `_build()` warns if a texture's aspect drifts more than 8 % from this constant.
const LEAF_ASPECT := 0.7485
const HEIGHT := WIDTH / LEAF_ASPECT     # 1.870
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
		var tex: Texture2D = load(texture_path)
		face_mat.albedo_texture = tex
		var a: float = float(tex.get_width()) / float(tex.get_height())
		if absf(a / LEAF_ASPECT - 1.0) > 0.08:
			push_warning("ChoiceDoor: %s is aspect %.4f against LEAF_ASPECT %.4f — "
				% [texture_path.get_file(), a, LEAF_ASPECT]
				+ "re-derive HEIGHT or the leaf is stretched again")
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


# The RESTORE path, for a level resumed through the back door with gate 1 already
# passed. No tween, no signal, no sound: the player opened this door on an earlier
# visit and the level is only catching its own geometry up (kontur.gd's
# _reopen_passed_gates). Deliberately marks _used, so a second interact() cannot
# re-emit `chosen` on a gate that cannot be re-taken.
func open_instantly() -> void:
	if _used:
		return
	_used = true
	rotation.y -= OPEN_ANGLE
