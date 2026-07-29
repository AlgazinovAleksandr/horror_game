extends StaticBody3D
class_name KitchenDrawer

# The House kitchen's counter drawer — the level's second cross-level hint.
#
# Playtest 2026-07-28: the kitchen furniture was *"completely useless… we need to either think
# how to use them, for example a useful note or a useful object can be hidden there, or a hint
# for other levels."* This is that, and it follows the game's oldest working pattern: KONTUR is
# built so that **its answers are not inside it** — all eight of its gates are hinted in levels
# 1 to 4 — and the House already carries one of them (the TV test card, Gate 2).
#
# This one is a second, independent source for **Gate 1, the two doors.** That gate's only
# other hint is a note hidden in the Lab morgue — a dark room with a `DarkZone`, a beartrap and
# two instant-fail trigger objects — and getting Gate 1 wrong does not merely cost a strike, it
# BANISHES the player back to the Backrooms. A single hint behind that much hazard is thin, and
# redundancy across two levels does not weaken KONTUR's design because the answer is still not
# inside KONTUR.
#
# ⚠️ The hint gives the RULE (black is the way out, red is not a door), never a position.
# `choice_door.gd` randomises which side is which per run precisely so the answer is the colour.
#
# Opens on E, then shows its note — the same open-then-read beat as `kontur_mailbox.gd`, so the
# page reads as having come out of the drawer rather than appearing from nowhere.

signal opened

const SIZE := Vector3(0.62, 0.16, 0.02)
const SLIDE := 0.34
const SLIDE_TIME := 0.45

const NOTE_TEXT := """He came back from that place and would not eat.

He kept saying the same thing over and over, until I wrote it down on the back of a bill just to make him stop.

"The black door is the way out. The red one is not a door."

I asked him what was behind the red one. He said nothing was behind it. He said that was the point, and then he went and sat in the cellar until it got dark."""

var _used: bool = false
var _front: MeshInstance3D = null


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build()


func _build() -> void:
	var wood := StandardMaterial3D.new()
	var tex := "res://assets/textures/level_2_house/house_drawer.png"
	if ResourceLoader.exists(tex):
		wood.albedo_texture = load(tex)
	else:
		wood.albedo_color = Color(0.36, 0.26, 0.18)
	wood.roughness = 0.85

	_front = MeshInstance3D.new()
	_front.name = "DrawerFront"
	var bm := BoxMesh.new()
	bm.size = SIZE
	_front.mesh = bm
	_front.material_override = wood
	add_child(_front)

	# A handle, because a flat panel on a flat counter is invisible — the same reason the
	# fridge needed one. Flat-tinted metal, never emissive (Issues 21/27/33).
	var handle := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.22, 0.022, 0.03)
	handle.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.55, 0.52, 0.45)
	hmat.metallic = 0.65
	hmat.roughness = 0.4
	handle.material_override = hmat
	handle.position = Vector3(0, 0, SIZE.z / 2.0 + 0.016)
	add_child(handle)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE.x, SIZE.y + 0.10, 0.14)
	col.shape = shape
	add_child(col)


# Inert once read, so it never advertises "Press E" for something that will not happen again —
# the opt-out `player.gd:_update_interact_prompt()` consults (see LabLocker, HouseFridge).
func can_interact() -> bool:
	return not _used


func interact() -> void:
	if _used:
		return
	_used = true

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:z", position.z + SLIDE, SLIDE_TIME)

	var s := GameState.load_audio("creak")
	if s:
		var p := AudioStreamPlayer3D.new()
		p.stream = s
		p.volume_db = -6.0
		p.unit_size = 4.0
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()

	# Archived like any other safe note, so TAB can re-read it at KONTUR's door two levels
	# later — which is the entire reason the journal exists.
	GameState.record_note(NOTE_TEXT, 2)
	NoteUI.show_note(NOTE_TEXT)
	opened.emit()
