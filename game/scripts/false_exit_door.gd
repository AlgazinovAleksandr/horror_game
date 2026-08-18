extends StaticBody3D
class_name FalseExitDoor

# ⭐ THE DOOR THAT SAYS 217 AND IS NOT ROOM 217 (2026-08-17).
#
# The user's brief, verbatim: *"inside the corridor level let's make a trap: the door on one
# of the corners or somewhere in the middle would look like a real exit door but opening it
# would result in an immediate jumpscare which will be loud and panic spike and the title
# written with red that It was an illusion. Because the level is not scary enough now."*
# And then, sharpening it: *"So it would look like the image I generated for the exit and it
# would have the correct number - the one the player thinks leads to the exit."*
#
# WHAT THE LIE IS. Not "a red door lied" — **the number lied**. This level's objective line
# is literally `Find room 217 — keep walking, do not run`, its entrance note ends *"Room 217
# is waiting"*, and 217 appears on no prop anywhere in the level (the real exit at d=320 wears
# `backrooms_tear_door.png`, which carries no number at all). So the first legible 217 in the
# game is this one, and it betrays the single instruction the level ever gives.
#
# ⚠️ DELIBERATELY NOT A `FakeDoor`. The level has three of those at 35/130/252 m — locked
# hotel doors that knock back from the other side for +8 on the first try. They are a texture
# of the place. This is a different promise and must not be read as one of them, which is why
# it is `door.png`'s leaf rather than `hotel_door_leaf.png`, why it stands in a blood-red
# frame, and why it is the only door in the level that opens when you press E.
#
# ⚠️ DELIBERATELY NOT `door.gd` either — `UnlockCondition` / `extra_lock` / `advances_level`
# is baggage for a door that is never an exit. Same reasoning `ajar_door.gd` and
# `slam_door.gd` recorded, and this is built on `ajar_door.gd`'s skeleton: hinge on the leaf's
# BACK FACE so swinging can only move wood into the corridor, art on `QuadMesh` faces rather
# than on the `BoxMesh` (Issue 24/31 — a textured box renders a magnified crop of its art).
#
# PROP EMITS, LEVEL DECIDES. `interact()` swings the leaf and emits `opened`; the flash, the
# panic and the scrawl all live in `corridor.gd`, the same split as `cellar_gate.gd`,
# `bottle_item.gd` and `choice_door.gd`. That is also what keeps the panic number in ONE
# place, at the level, where a difficulty constant belongs.
#
# ⚠️ ONE-SHOT. After it fires `can_interact()` returns false, so the prompt never comes back
# and E does literally nothing (`player.gd:_is_interactable()`'s opt-out — a prop that answers
# E forever with nothing reads as a bug). The leaf stays open on bare wallpaper afterwards:
# the room that is not there is the evidence, and it is worth more standing open.

signal opened

# ⚠️ SIZE DERIVED FROM THE ARTWORK, never chosen. `hotel_door_217.png` is 492 x 1136 = 0.4331,
# so a 2.1 m leaf is 0.909 m wide. `check_art_aspect.gd` sweeps this level and a hard-coded
# width is how a 1.29x squash got into the ordinary doors in the first place.
const HEIGHT := 2.1
const THICK := 0.10
# How far it swings. Wider than `AjarDoor.AJAR_MAX_DEG` 40 because this one is MEANT to be
# looked through — but the collider swings with it, so this is bounded by the corridor's
# walkable width and is asserted by `check_corridor_doors.gd`.
const OPEN_DEG := 62.0
const OPEN_TIME := 0.34

var _tex_path: String = ""
var _used: bool = false
var _width: float = 0.909


static func build(parent: Node, xform: Transform3D, tex_path: String) -> FalseExitDoor:
	var d := FalseExitDoor.new()
	d._tex_path = tex_path
	if tex_path != "" and ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path)
		d._width = HEIGHT * float(tex.get_width()) / float(tex.get_height())
	parent.add_child(d)
	d.global_transform = xform
	return d


func width() -> float:
	return _width


func _ready() -> void:
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.07, 0.06, 0.06)
	edge_mat.roughness = 0.85

	var mesh := MeshInstance3D.new()
	mesh.name = "Leaf"
	var box := BoxMesh.new()
	box.size = Vector3(_width, HEIGHT, THICK)
	mesh.mesh = box
	mesh.material_override = edge_mat
	# Hinge on the BACK FACE — see ajar_door.gd's ⚠️. Every part of the leaf lives at
	# local z >= 0, so it can never sweep backwards into the wall.
	mesh.position = Vector3(_width / 2.0, HEIGHT / 2.0, THICK / 2.0)
	add_child(mesh)

	var col := CollisionShape3D.new()
	col.name = "LeafCol"
	var shape := BoxShape3D.new()
	shape.size = Vector3(_width, HEIGHT, THICK)
	col.shape = shape
	col.position = mesh.position
	add_child(col)

	var face_mat := StandardMaterial3D.new()
	face_mat.roughness = 0.85
	if _tex_path != "" and ResourceLoader.exists(_tex_path):
		face_mat.albedo_texture = load(_tex_path)
	else:
		face_mat.albedo_color = Color(0.12, 0.10, 0.08)

	for z_sign in [1.0, -1.0]:
		var face := MeshInstance3D.new()
		face.name = "Face_%s" % ("front" if z_sign > 0.0 else "back")
		var qm := QuadMesh.new()
		qm.size = Vector2(_width, HEIGHT)
		face.mesh = qm
		face.material_override = face_mat
		face.position = Vector3(_width / 2.0, HEIGHT / 2.0,
			THICK / 2.0 + z_sign * (THICK / 2.0 + 0.004))
		if z_sign < 0.0:
			face.rotation.y = PI
		add_child(face)


# ⚠️ The opt-out, not merely a refusal. Once used there is no prompt and no target at all.
func can_interact() -> bool:
	return not _used


func interact() -> void:
	if _used:
		return
	_used = true
	# ⚠️ The signal FIRST, synchronously, and then the swing. The level fires the flash on it,
	# and the covering image is what the 0.34 s swing happens behind — so when the picture
	# drops the door is already standing open on blank wallpaper. Firing the swing first and
	# the scare after would be `house_fridge.gd`'s documented mistake inverted: there, a
	# fullscreen image landed ON TOP of the reveal it was announcing.
	opened.emit()
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation:y", rotation.y - deg_to_rad(OPEN_DEG), OPEN_TIME)


func is_used() -> bool:
	return _used


# The restore path for a back-door return: open, inert, no scare. `corridor.gd:save_progress()`
# records it, because a trap the player has already sprung must not be armed again — and
# because a door standing open is the level's only lasting record that it happened.
func set_used_instantly() -> void:
	if _used:
		return
	_used = true
	rotation.y -= deg_to_rad(OPEN_DEG)
