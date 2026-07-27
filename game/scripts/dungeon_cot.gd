class_name DungeonCot
extends StaticBody3D

# The cot in the Antechamber, and the bed at the far end of the dungeon.
# One script, two ends of the same fiction (DUNGEON_NIGHTMARES.md §B3).
#
# ⚠️ interact(), NOT a trigger volume. The player CHOOSES to go under. That choice
# is what makes "You will be put down" land as consent rather than as a cutscene,
# and it is DN2's elevator minus the elevator.
#
# The level owns the consequence — this prop only reports that E was pressed, the
# same prop-emits / level-decides split as cellar_gate.gd and wall_sconce.gd.

signal used

const TEX := "res://assets/textures/level_9_dungeon/dn_cot.png"

@export var is_exit: bool = false   # the bed at the end, vs the cot at the start


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build()


func _build() -> void:
	var frame := MeshInstance3D.new()
	frame.name = "CotFrame"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.95, 0.42, 2.0)
	frame.mesh = bm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.13, 0.12, 0.11)
	fm.roughness = 0.95
	frame.set_surface_override_material(0, fm)
	frame.position = Vector3(0, 0.21, 0)
	add_child(frame)

	# ⚠️ Art on a QuadMesh laid flat, never on the box's top face: a textured box
	# renders a magnified CROP of its own texture (Issue 24). The source is
	# 1536x1024 landscape, so the quad is sized from that aspect rather than
	# squashed to the mesh's footprint (the kontur_lock_roster lesson, Issue 33).
	var top := MeshInstance3D.new()
	top.name = "CotSurface"
	var qm := QuadMesh.new()
	# ⚠️ Sized to the FRAME, not to the source's aspect. The art is a top-down photo
	# of a whole cot, so it has to sit exactly on the mattress footprint; deriving
	# the quad from the image aspect made it overhang the frame on both sides and
	# read as a floating white sheet.
	qm.size = Vector2(0.93, 1.98)
	top.mesh = qm
	var tm := StandardMaterial3D.new()
	if ResourceLoader.exists(TEX):
		var t: Texture2D = load(TEX)
		if t != null:
			tm.albedo_texture = t
	else:
		tm.albedo_color = Color(0.35, 0.32, 0.28)
	tm.roughness = 0.95
	# ⚠️ NO EMISSION, and the albedo tinted well down.
	# Measured: at emission 0.22 with the brazier 4 m away this rendered as a flat
	# white slab with no visible cot in it — Issue 21 exactly ("albedo must be dark;
	# a self-lit prop next to a point light blows out"), and Issue 27's rule that a
	# prop which has gained real art should stop wearing a findability glow. The
	# brazier already lights the Antechamber, and the cot is the only object in the
	# middle of the floor: it does not need help being found.
	tm.albedo_color = Color(0.42, 0.40, 0.37)
	top.set_surface_override_material(0, tm)
	top.position = Vector3(0, 0.43, 0)
	top.rotation = Vector3(-PI / 2.0, 0, 0)
	add_child(top)

	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.1, 0.7, 2.1)
	col.shape = sh
	col.position = Vector3(0, 0.35, 0)
	add_child(col)


func interact() -> void:
	used.emit()
