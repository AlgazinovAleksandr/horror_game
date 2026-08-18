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
#
# ⚠️ Only the VISUALS slide. The collider stays flush with the counter face for the life of the
# prop — see the ⚠️ block on `interact()` and Issue 76.

signal opened

const SIZE := Vector3(0.62, 0.16, 0.02)
# ⚠️ NEGATIVE, i.e. toward −z (found 2026-08-16 while fixing the Issue-58 ordering below).
# It was +0.34. The drawer is set into the counter's SOUTH face — `level_2.gd` places it at
# `kc.z + 2.4 - 0.36` = 8.04 and the counter box spans z 8.05..8.75 — and the player stands
# south of it, so a positive slide drove the panel 34 cm straight INTO the carcass and out of
# sight. The "open, then read" beat this file is named for had nothing to show either way.
# `tests/check_open_then_read.gd` now asserts the opened drawer is outside every CSG box.
const SLIDE := -0.34
const SLIDE_TIME := 0.45

# Drawer-box depth: how far the sides/bottom/back run back into the counter.
const BOX_DEPTH := 0.30


const NOTE_TEXT := """He came back from that place and would not eat.

He kept saying the same thing over and over, until I wrote it down on the back of a bill just to make him stop.

"The black door is the way out. The red one is not a door."

I asked him what was behind the red one. He said nothing was behind it. He said that was the point, and then he went and sat in the cellar until it got dark."""

var _used: bool = false
var _front: MeshInstance3D = null
# ⚠️ EVERYTHING VISIBLE HANGS OFF THIS, AND ONLY THIS MOVES (2026-08-16 — see the ⚠️ block on
# `interact()`). The `CollisionShape3D` is a direct child of the body and never leaves the
# counter face, so an opened drawer cannot narrow a walkway.
var _slider: Node3D = null


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

	_slider = Node3D.new()
	_slider.name = "DrawerSlide"
	add_child(_slider)

	_front = MeshInstance3D.new()
	_front.name = "DrawerFront"
	var bm := BoxMesh.new()
	bm.size = SIZE
	_front.mesh = bm
	_front.material_override = wood
	_slider.add_child(_front)

	# ⚠️ A DRAWER, NOT A PANEL (2026-08-16, replay capture 001: *"When I read this note it fell
	# and blocked my way"*). This used to be a single 2 cm-thick board with nothing behind it,
	# so sliding it 34 cm out of a featureless counter produced a pale plank hanging in mid-air
	# — which is exactly what the user photographed and read as fallen debris. A drawer is
	# legible because it has SIDES and a BOTTOM you can see into; Issue 35 in furniture form,
	# the same note the chairs, the table and the key stool each earned in turn.
	#
	# The box runs BACK into the counter (+z), so while shut it is entirely inside the carcass
	# and invisible; it only becomes a shape once the front has slid out.
	var carcass := StandardMaterial3D.new()
	carcass.albedo_color = Color(0.22, 0.16, 0.11)
	carcass.roughness = 0.9
	var mid := SIZE.z / 2.0 + BOX_DEPTH / 2.0
	var parts := [
		# name, size, local position
		["DrawerSideL", Vector3(0.02, SIZE.y, BOX_DEPTH), Vector3(-SIZE.x / 2.0 + 0.01, 0.0, mid)],
		["DrawerSideR", Vector3(0.02, SIZE.y, BOX_DEPTH), Vector3(SIZE.x / 2.0 - 0.01, 0.0, mid)],
		["DrawerBottom", Vector3(SIZE.x, 0.02, BOX_DEPTH), Vector3(0.0, -SIZE.y / 2.0 + 0.01, mid)],
		["DrawerBack", Vector3(SIZE.x, SIZE.y, 0.02),
			Vector3(0.0, 0.0, SIZE.z / 2.0 + BOX_DEPTH - 0.01)],
	]
	for p in parts:
		var m := MeshInstance3D.new()
		m.name = String(p[0])
		var box := BoxMesh.new()
		box.size = p[1]
		m.mesh = box
		m.material_override = carcass
		m.position = p[2]
		_slider.add_child(m)

	# A handle, because a flat panel on a flat counter is invisible — the same reason the
	# fridge needed one. Flat-tinted metal, never emissive (Issues 21/27/33).
	#
	# ⚠️ On the −z face. It was at `+SIZE.z/2`, i.e. on the side that faces INTO the counter
	# (the counter box starts at z 8.05 and the panel's front face is at 8.03), so the one part
	# added to make the drawer findable was buried in the worktop. Same sign error as the slide.
	var handle := MeshInstance3D.new()
	handle.name = "DrawerHandle"
	var hm := BoxMesh.new()
	hm.size = Vector3(0.22, 0.022, 0.03)
	handle.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.55, 0.52, 0.45)
	hmat.metallic = 0.65
	hmat.roughness = 0.4
	handle.material_override = hmat
	handle.position = Vector3(0, 0, -(SIZE.z / 2.0 + 0.016))
	_slider.add_child(handle)

	var col := CollisionShape3D.new()
	col.name = "DrawerCollision"
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

	var s := GameState.load_audio("creak")
	if s:
		var p := AudioStreamPlayer3D.new()
		p.stream = s
		p.volume_db = -6.0
		p.unit_size = 4.0
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()

	# ⚠️ THE DRAWER USED TO OPEN AFTER THE NOTE CLOSED (fixed 2026-08-16 — Issue 58, the same
	# fault `kontur_mailbox.gd` carried and the one `tests/check_open_then_read.gd` exists for).
	#
	# It read:
	#     var tw := create_tween()
	#     tw.tween_property(self, "position:z", position.z + SLIDE, SLIDE_TIME)
	#     ...
	#     NoteUI.show_note(NOTE_TEXT)          # <- pauses the tree, two statements later
	#
	# A Tween does not advance until the NEXT frame, and while the tree is paused that frame
	# never arrives — so the drawer sat shut behind a fullscreen page and only slid open once
	# the player dismissed it. Measured on the identical construction in the mailbox: the hinge
	# read 0.0° of 105 at the moment the note appeared. The header three paragraphs up has
	# claimed "opens on E, then shows its note" since the day this file was written.
	#
	# The note is now fired from the slide's `finished`: open, then see, then read.
	#
	# ⚠️ THE VISUALS SLIDE; THE COLLIDER DOES NOT (2026-08-16 — Issue 76, reported on the
	# verification replay as *"When I read this note it fell and blocked my way, I cannot pass
	# by"*). This used to tween `self`, which carries the CollisionShape3D with it, so an open
	# drawer put a 0.62 x 0.26 x 0.14 solid 34 cm out into the room. Measured with the player's
	# own capsule: the free lane across the Kitchen at z = 7.40 went from ONE 5.10 m span to two
	# spans of 1.30 m and 2.50 m — the drawer severed the only connection between the west
	# strip and the rest of the north kitchen. An interactable must never be able to close a
	# route, so nothing that opens in this level moves a collider any more; `tests/
	# autoplay_house_route.gd` flood-fills the floor before and after and asserts it.
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_slider, "position:z", _slider.position.z + SLIDE, SLIDE_TIME)
	tw.finished.connect(_reveal)
	opened.emit()


# How far the visible drawer has slid out of the counter, in metres. The body itself never
# moves, so a test must ask for this rather than reading `position.z`.
func slide_offset() -> float:
	return absf(_slider.position.z) if _slider else 0.0


func _reveal() -> void:
	# Archived like any other safe note, so TAB can re-read it at KONTUR's door two levels
	# later — which is the entire reason the journal exists.
	GameState.record_note(NOTE_TEXT, 2)
	NoteUI.show_note(NOTE_TEXT)
