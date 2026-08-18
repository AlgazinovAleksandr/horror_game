extends StaticBody3D
class_name LabCabinet

# A Records filing cabinet, built from PARTS, whose drawers ALL open.
#
# Playtest 2026-08-16, capture #4, aimed at the two flat boxes that stood here before:
# *"These object look way too useless - shall we make them more bright? Or put another note
# which is another hint to the backrooms like sometimes it is useful to turn of the
# flashlight - especially if you feel something wants to hurt you without the reason"*.
#
# Both halves of that are answered here, and NEITHER of them is "brighter". They were two
# flat 0.7 x 1.3 x 0.6 boxes in a flat grey — Issue 35 exactly, the silhouette carries a
# prop and the art does not, so the fix is a plinth, a top overhang, four drawer faces
# standing proud of the frame, handles and label holders. No texture and no emission: the
# same answer Issue 35 got in `kontur_mailbox.gd` and `intro_room.gd:_build_wheelchair()`.
#
# The second half is the note. `GAME_MECHANICS_IDEAS` records that the Backrooms Flood's
# darkness tell — some seams are only visible with the torch OFF — is the one puzzle tell
# in the game with no cross-level hint at all, while KONTUR's eight gates have four. This
# is that hint, and it follows `kitchen_drawer.gd`'s rule: it states the RULE and never a
# place, because the Flood randomises nothing but the player's route and a location would
# delete the search rather than support it.
#
# ⚠️ SECOND REVISION (2026-08-16). The first build had ONE openable drawer on ONE of the two
# units, and it opened straight into the note. The playtester asked for the obvious better
# thing: *"Maybe we can do it in a way I could open all the boxes and only one would contain
# the note? Also I need to take it to start reading, now it reads automatically"*. So the
# cabinet no longer interacts at all — it is a carcass, and each of its four drawers is its
# own `LabCabinetDrawer` with its own interact volume. Eight drawers across the bank, one
# page, and the page has to be picked up.
#
# ⚠️ THIRD REVISION (2026-08-16). The drawers are a TOGGLE — E shuts an open one again. An
# open drawer stands 0.34 m into the room and shadows every slot beneath it, so a bank
# searched top-down used to blind itself: *"I cannot see what is under the top storages. I
# need to be able to close them by pressing the E button"*. Taken-state survives the cycle;
# see `lab_cabinet_drawer.gd`'s header table.
#
# ⚠️ FOURTH REVISION (2026-08-16, verification replay). An empty drawer no longer prints a
# flavour line — *"What for to write these messages? They are not needed, the player will see
# there is nothing in there"*. `EMPTY_LINES` is gone, and with it the drawers' `_searched`
# flag: suppressing a repeat of that line was the only thing it was ever read for.
#
# ⚠️ WHICH drawer holds it is chosen by the LEVEL, per run, and captured in
# `save_progress()`. Re-rolling it on a back-door return while restoring "already taken"
# would mark a search solved against an answer that had moved — KONTUR's `_dark_x` rule.

signal note_found                  # the page was taken and read

const SIZE := Vector3(0.7, 1.3, 0.6)       # unchanged from the boxes this replaces
const PLINTH_H := 0.06
const TOP_H := 0.04
const DRAWERS := 4
const DRAWER_PITCH := 0.28

const STEEL := Color(0.27, 0.29, 0.28)
const STEEL_LIGHT := Color(0.34, 0.36, 0.35)

var _drawers: Array[LabCabinetDrawer] = []
var _note_slot: int = -1
var _note_text: String = ""
var _note_taken: bool = false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build()


# ---------------------------------------------------------------- construction

func _build() -> void:
	var carcass_bottom := PLINTH_H
	var carcass_top := SIZE.y - TOP_H
	var carcass_h := carcass_top - carcass_bottom

	# Plinth — set back on all sides, so the cabinet reads as standing ON something
	# rather than as a box resting on the floor.
	_slab("Plinth", Vector3(SIZE.x - 0.08, PLINTH_H, SIZE.z - 0.08),
		Vector3(0, PLINTH_H / 2.0, 0), STEEL.darkened(0.35))

	# Carcass.
	_slab("Carcass", Vector3(SIZE.x, carcass_h, SIZE.z),
		Vector3(0, carcass_bottom + carcass_h / 2.0, 0), STEEL)

	# Top, overhanging on every side — the single cheapest edge that says "furniture".
	_slab("Top", Vector3(SIZE.x + 0.06, TOP_H, SIZE.z + 0.04),
		Vector3(0, carcass_top + TOP_H / 2.0, 0), STEEL_LIGHT)

	var front_z := SIZE.z / 2.0
	for i in range(DRAWERS):
		var d := LabCabinetDrawer.new()
		d.name = "Drawer%d" % i
		d.setup(i, front_z)
		d.position = Vector3(0, carcass_top - 0.09 - float(i) * DRAWER_PITCH, 0)
		d.note_taken.connect(_on_note_taken)
		add_child(d)
		_drawers.append(d)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# The BODY only. It must stop the player walking through the cabinet, and it must NOT
	# reach out past the drawer faces — the drawers are the interactive things, and a carcass
	# collider proud of them would swallow every ray aimed at a handle.
	shape.size = Vector3(SIZE.x, SIZE.y, SIZE.z)
	col.shape = shape
	col.position = Vector3(0, SIZE.y / 2.0, 0)
	add_child(col)


func _slab(slab_name: String, size: Vector3, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	m.name = slab_name
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.3
	mat.roughness = 0.75
	m.material_override = mat
	m.position = pos
	add_child(m)


# ---------------------------------------------------------------- the level's handles

# `slot < 0` (or an empty text) means this unit holds nothing. Safe to call twice: the level
# assigns a random slot when it builds the bank, and `_restore_progress()` may then move it.
func assign_note(text: String, slot: int) -> void:
	_note_text = text
	_note_slot = slot if text != "" else -1
	for i in range(_drawers.size()):
		_drawers[i].set_note(text if i == _note_slot else "")


func note_slot() -> int:
	return _note_slot


func is_note_taken() -> bool:
	return _note_taken


func mark_note_taken() -> void:
	_note_taken = true
	if _note_slot >= 0 and _note_slot < _drawers.size():
		_drawers[_note_slot].set_note("")


func drawer_count() -> int:
	return _drawers.size()


func get_drawer(i: int) -> LabCabinetDrawer:
	return _drawers[i] if i >= 0 and i < _drawers.size() else null


func open_slots() -> Array:
	var out: Array = []
	for d in _drawers:
		if d.is_open():
			out.append(d.index)
	return out


func open_slot_instantly(i: int) -> void:
	var d := get_drawer(i)
	if d:
		d.open_instantly()


func close_slot(i: int) -> void:
	var d := get_drawer(i)
	if d:
		d.close()


func _on_note_taken(_index: int) -> void:
	_note_taken = true
	note_found.emit()
