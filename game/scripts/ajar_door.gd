extends StaticBody3D
class_name AjarDoor

# The Corridor's doors, given a body.
#
# Level 3 has six "decor" doors at 18/72/112/164/210/300 m that are flat, inert
# `QuadMesh`es stuck on the wallpaper (corridor.gd's `_spawn_quad` loop). They cannot
# open, because there is nothing there to open. This is that door as real geometry, so
# the level can give it the one rule a haunted hotel corridor has always wanted:
# **doors you have already walked past open behind you.**
#
# Deliberately NOT built on `door.gd`: that script's UnlockCondition / extra_lock /
# advances_level machinery is irrelevant baggage for a door that is never a level exit,
# exactly as `slam_door.gd` reasoned for Level 6. It IS built on `choice_door.gd`'s
# skeleton, which already solved the two things that matter here — the hinge sits at the
# node origin with the panel offset half a width along +x so rotating the body swings the
# door properly, and the art lives on `QuadMesh` faces rather than on the `BoxMesh`
# itself (Issue 24/31: a textured box renders a magnified CROP of its own art).
#
# There is no `interact()`. The player cannot open these — that is the point. If the
# player could open them, an ajar door would be evidence of nothing.
#
# ⚠️ The collider is a child of this body, so it swings with the panel. In a 3 m-wide
# corridor a 1.3 m panel at 40° protrudes ~0.84 m, which still leaves well over a
# player-width of clearance — but `AJAR_MAX_DEG` is the knob that guarantees it and the
# level's walk test is what proves it.

signal slammed

# ⚠️ WIDTH IS DERIVED FROM THE ARTWORK, not chosen (2026-08-16). `hotel_door_leaf.png` is
# 616 x 1334 = 0.4618, so a 2.1 m leaf is 0.970 m wide — a door-shaped door. It was 1.3 x 2.1
# (0.619) wearing `ordinary_hotel_door.png` (0.800), i.e. squashed 1.29x, and that source was
# a picture of a door PLUS its casing PLUS the wallpaper either side (Issue 35). The casing
# is real geometry now: `corridor.gd:_spawn_door_frame()`.
#
# ⚠️ If the crop changes, this changes with it or `check_art_aspect.gd` goes red.
const HEIGHT := 2.1
const WIDTH := 0.97
const THICK := 0.10
const AJAR_MAX_DEG := 40.0     # keep the swept panel out of the walkable corridor width
const SLAM_TIME := 0.12        # fast enough to read as violent

var _tex_path: String = ""
var _open_deg: float = 0.0


static func build(parent: Node, xform: Transform3D, tex_path: String) -> AjarDoor:
	var d := AjarDoor.new()
	d._tex_path = tex_path
	parent.add_child(d)
	d.global_transform = xform
	return d


func _ready() -> void:
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.08, 0.08, 0.09)
	edge_mat.roughness = 0.85

	# ⚠️ THE HINGE IS ON THE LEAF'S BACK FACE, not through its centre (2026-08-16). The panel
	# is pushed forward by THICK/2 so every part of it lives at local z >= 0, which means
	# swinging it can only move wood INTO the corridor and never backwards through the wall.
	# With the old centre hinge the rear corner swept `THICK * sin(40°)` = 6.4 cm behind the
	# hinge plane, which is why `corridor.gd` had to hold the whole door 14 cm off the wall
	# to make room — and 14 cm off the wall is what the player photographed.
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(WIDTH, HEIGHT, THICK)
	mesh.mesh = box
	mesh.material_override = edge_mat
	mesh.position = Vector3(WIDTH / 2.0, HEIGHT / 2.0, THICK / 2.0)
	add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(WIDTH, HEIGHT, THICK)
	col.shape = shape
	col.position = mesh.position
	add_child(col)

	var face_mat := StandardMaterial3D.new()
	face_mat.roughness = 0.85
	if _tex_path != "" and ResourceLoader.exists(_tex_path):
		face_mat.albedo_texture = load(_tex_path)
	else:
		face_mat.albedo_color = Color(0.12, 0.12, 0.13)

	# Art on both faces — an ajar door is seen from behind as often as from in front, and
	# a single-sided quad on the face the player never sees is Issue 28.
	for z_sign in [1.0, -1.0]:
		var face := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(WIDTH, HEIGHT)
		face.mesh = qm
		face.material_override = face_mat
		face.position = Vector3(WIDTH / 2.0, HEIGHT / 2.0,
			THICK / 2.0 + z_sign * (THICK / 2.0 + 0.004))
		if z_sign < 0.0:
			face.rotation.y = PI
		add_child(face)


func is_ajar() -> bool:
	return not is_zero_approx(_open_deg)


# Swing silently to `deg` (clamped). SILENCE IS THE MECHANIC: the door was never HEARD
# opening, so the player has no moment to attribute it to. A creak here would make this
# an event; without one it is a discrepancy.
func swing_ajar(deg: float, time: float = 1.4) -> void:
	_open_deg = clampf(absf(deg), 0.0, AJAR_MAX_DEG)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation:y", rotation.y - deg_to_rad(_open_deg), time)


# The one that is heard. The level owns the sound and the timing — this only reports it,
# the same prop-emits / level-decides split as `cellar_gate.gd` and `bottle_item.gd`.
func slam() -> void:
	if not is_ajar():
		return
	var target := rotation.y + deg_to_rad(_open_deg)
	_open_deg = 0.0
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "rotation:y", target, SLAM_TIME)
	slammed.emit()
