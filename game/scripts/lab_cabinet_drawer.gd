extends StaticBody3D
class_name LabCabinetDrawer

# ONE drawer of a Records filing cabinet, and the reason the bank is a SEARCH.
#
# Playtest 2026-08-16, second replay, standing at the cabinets: *"Maybe we can do it in a
# way I could open all the boxes and only one would contain the note? Also I need to take it
# to start reading, now it reads automatically"*.
#
# Both halves are here:
#
#   1. EVERY drawer opens. Exactly one of the eight in the bank holds the hint (the level
#      picks which, per run — see level_1.gd:_spawn_room_props). Opening an empty one shows
#      you it is empty and costs nothing: no panic, no penalty, no fail state, no gate.
#      Nothing in the level is behind this; it is a reward for looking, so the only price
#      of looking in the wrong place is the looking.
#      ⚠️ AND IT SAYS NOTHING (2026-08-16, verification replay). An empty drawer used to
#      print a line of flavour ("Duplicates of duplicates."). J-capture in Records: *"What
#      for to write these messages? They are not needed, the player will see there is
#      nothing in there"*. The drawer sliding out with folders and no page IS the message;
#      a caption on top of it is the game narrating something already on screen. Do not
#      re-add it — and note that removing it took `_searched` with it, because suppressing
#      a repeat of that line was the only thing the flag was ever read for.
#   2. Opening is NOT reading. The drawer slides, the paper is lying in it as an OBJECT, and
#      a second, separate E takes it. That is `kontur_mailbox.gd`'s open-then-read beat taken
#      one step further — there the note still arrived on its own, here you have to pick it
#      up.
#   3. E CLOSES IT AGAIN. See below.
#
# ⚠️ ONE effortless press to open. KONTUR's mailbox slot is the stiff one (PRESSES_NEEDED),
# and the user asked explicitly for the Lab cabinet to stay a single press. Do not "unify"
# these two: the mailbox is a gate on a level's hint, this is furniture in a room nothing
# forces you to enter. ⚠️ Closing is one effortless press too, for the same reason.
#
# ⚠️ THE DRAWER IS A TOGGLE (2026-08-16, third replay). J-capture in Records: *"There is a
# bug - I cannot see what is under the top storages. I need to be able to close them by
# pressing the E button"*, photographed with two drawers hanging out over the four below
# them. A drawer sticks 0.34 m into the room, and a standing player aims DOWN at the lower
# slots — so an open drawer both HIDES and SHADOWS everything under it, and a bank searched
# top-down blinds itself. That is Issue 65 again in a different coat: there the shadow came
# from an over-deep collider, here it comes from a drawer that had no way back in.
#
# ⚠️ WHICH THING ANSWERS THE RAY IS THE WHOLE DESIGN, and it is decided by `_refresh_layer()`
# rather than by aim. A single ray cannot reliably choose between a drawer face and a page
# lying 0.10 m behind and below it inside a 0.26 m slot — measured on the pose a standing
# player actually uses, a ray descending toward the page crosses the face's own volume first.
# So the two targets take turns:
#
#     shut                        -> the DRAWER answers   (E opens it)
#     open, page still inside     -> the PAGE answers     (E takes it; the drawer is inert)
#     open, empty or page taken   -> the DRAWER answers   (E closes it)
#
# The one consequence worth stating plainly: the drawer holding the page cannot be shut until
# the page is out of it. That costs a press the player wanted to make anyway, and it is the
# reason the page can never be shadowed by the drawer that contains it.
#
# ⚠️ CLOSING RESETS NOTHING: a page you have taken does not come back, and the level's
# snapshot records which drawers were left open. There is no longer any *searched* state to
# keep — with the flavour line gone, nothing in the game behaves differently for a drawer you
# have already looked in, so the flag and its snapshot key were removed rather than left as a
# field nobody reads.
#
# ⚠️ Layer 2 / mask 0, `note.gd`'s convention: raycast-hittable but NOT solid. A drawer that
# slides 0.34 m into the room on a layer-1 collider is a moving wall that can shove or trap
# the player, for no gain — the carcass behind it is what stops you walking through the
# cabinet.
#
# ⚠️ The note paper's own body is a nested class at the bottom of this file rather than a
# fourth script: it exists only inside a drawer, is built only by this file, and player.gd
# duck-types `interact()`/`can_interact()` off the collider it hits, so it needs no
# class_name to work.

signal opened(index: int)
signal closed(index: int)
signal note_taken(index: int)

const FACE := Vector3(0.62, 0.26, 0.03)
const PROUD := 0.005              # how far the face stands off the carcass front
const SLIDE := 0.34
const SLIDE_TIME := 0.55
# Shutting it is the same runners in the other direction: the same sample, pitched down and
# eased IN so it accelerates home instead of coasting out. A separate asset would need an
# --import pass to say something this says already.
const CLOSE_TIME := 0.45
const OPEN_PITCH := Vector2(0.94, 1.06)
const CLOSE_PITCH := Vector2(0.80, 0.88)

const STEEL := Color(0.27, 0.29, 0.28)
const STEEL_LIGHT := Color(0.34, 0.36, 0.35)
const HANDLE := Color(0.50, 0.48, 0.43)
const FOLDER := Color(0.21, 0.19, 0.16)
# ⚠️ The loose sheet is the one pale thing in the whole bank, and that is its entire job:
# in a dark room, a drawer with something in it has to be distinguishable from a drawer
# with nothing in it at a glance. Still NO emission (Issues 21/27/33) — the Records accent
# lamp lights it, it does not light itself.
const PAPER := Color(0.70, 0.68, 0.60)

var index: int = 0

var _open: bool = false
var _sliding: bool = false
var _front_z: float = 0.3
var _base_z: float = 0.0
var _paper: Node3D = null
var _creak: AudioStreamPlayer3D = null


func setup(idx: int, front_z: float) -> void:
	index = idx
	_front_z = front_z


func _ready() -> void:
	# See the header: hittable, never solid.
	collision_mask = 0
	# ⚠️ The shut position is READ, not assumed to be 0 — LabCabinet sets it before add_child,
	# and the close tween has to have somewhere exact to return to. Deriving the target from
	# `position.z - SLIDE` instead would accumulate error across a toggle cycle.
	_base_z = position.z
	_refresh_layer()
	_build()
	_build_audio()


# ---------------------------------------------------------------- construction

func _build() -> void:
	# The face, handle and card holder are IDENTICAL on every drawer, live or empty — which
	# is what stops the one holding the note from advertising itself before it is opened.
	var face := MeshInstance3D.new()
	face.name = "DrawerFace"
	var fm := BoxMesh.new()
	fm.size = FACE
	face.mesh = fm
	face.material_override = _flat(STEEL_LIGHT, 0.35, 0.6)
	face.position = Vector3(0, 0, _front_z + FACE.z / 2.0 + PROUD)
	add_child(face)

	var handle := MeshInstance3D.new()
	handle.name = "DrawerHandle"
	var hm := BoxMesh.new()
	hm.size = Vector3(0.26, 0.024, 0.032)
	handle.mesh = hm
	handle.material_override = _flat(HANDLE, 0.65, 0.4)
	handle.position = Vector3(0, 0.05, _front_z + FACE.z + PROUD + 0.014)
	add_child(handle)

	# The card holder — a pale rectangle at eye-scan height is what makes a bank of
	# drawers read as RECORDS rather than as lockers.
	# ⚠️ Knocked down from 0.62 after photographing it: a pale plate is the brightest albedo
	# on the prop and Records carries an accent lamp, so at 0.62 the card holders read as
	# little lights rather than as paper.
	var label := MeshInstance3D.new()
	label.name = "DrawerLabel"
	var lm := BoxMesh.new()
	lm.size = Vector3(0.16, 0.045, 0.008)
	label.mesh = lm
	label.material_override = _flat(Color(0.48, 0.46, 0.41), 0.0, 0.9)
	label.position = Vector3(0, -0.06, _front_z + FACE.z + PROUD + 0.004)
	add_child(label)

	_build_tray()

	# The interact volume: a thin slab standing just proud of the carcass, so the ray meets
	# the DRAWER before the cabinet body behind it. Full width and full slot pitch, so an
	# approach from 25 deg off-axis still lands (check_interact_reach's rule).
	#
	# ⚠️ DEPTH IS 0.08, NOT 0.20, and that is the whole difference between a bank of four
	# drawers and a bank of one. A volume 0.20 deep protrudes 0.18 m into the room, and a
	# player standing up aims DOWN at the lower drawers — measured, every ray at the bottom
	# three slots was intercepted by the drawer ABOVE the one being aimed at, and 6 of 8
	# drawers in the bank were unreachable. The first version of this file shipped that; the
	# reach check caught it. Keep the front face inside ~5 cm of the drawer face.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.68, 0.26, 0.08)
	col.shape = shape
	col.position = Vector3(0, 0, _front_z + 0.02)
	add_child(col)


# An OPEN-FRONTED tray (floor + two sides + back, no lid, no front), so a pulled-out drawer
# reads as a container with something in it instead of as a panel floating away from a hole
# — Issue 46's lesson, one level over.
func _build_tray() -> void:
	var inner_w := FACE.x - 0.04
	var depth := 0.5
	var tray_y := -FACE.y / 2.0 + 0.02
	var tray_z := _front_z - depth / 2.0
	var tray_mat := STEEL.darkened(0.2)
	_slab("TrayFloor", Vector3(inner_w, 0.015, depth), Vector3(0, tray_y, tray_z), tray_mat)
	_slab("TrayL", Vector3(0.015, FACE.y - 0.05, depth),
		Vector3(-inner_w / 2.0, 0, tray_z), tray_mat)
	_slab("TrayR", Vector3(0.015, FACE.y - 0.05, depth),
		Vector3(inner_w / 2.0, 0, tray_z), tray_mat)
	_slab("TrayBack", Vector3(inner_w, FACE.y - 0.05, 0.015),
		Vector3(0, 0, tray_z - depth / 2.0), tray_mat)

	# Two leaning folders in EVERY drawer — an empty drawer is not a bare tin box, it is a
	# drawer with the wrong paperwork in it. Dull manila, so the loose sheet in the one that
	# matters is unmistakably brighter.
	for i in range(2):
		var folder := MeshInstance3D.new()
		folder.name = "Folder%d" % i
		var bm := BoxMesh.new()
		bm.size = Vector3(inner_w - 0.06, FACE.y - 0.09, 0.02)
		folder.mesh = bm
		folder.material_override = _flat(FOLDER, 0.0, 0.95)
		folder.position = Vector3(0, 0.01, tray_z + 0.10 - float(i) * 0.09)
		folder.rotation.x = deg_to_rad(-6.0 - float(i) * 3.0)
		add_child(folder)


func _slab(slab_name: String, size: Vector3, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	m.name = slab_name
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.material_override = _flat(color, 0.3, 0.75)
	m.position = pos
	add_child(m)


func _flat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


func _build_audio() -> void:
	_creak = AudioStreamPlayer3D.new()
	_creak.name = "DrawerCreak"
	var s := GameState.load_audio("metal_creak")
	if s:
		_creak.stream = s
	_creak.unit_size = 5.0
	_creak.volume_db = -2.0
	_creak.max_db = 3.0
	add_child(_creak)


# ---------------------------------------------------------------- the note inside

# Put (or remove) the hint page in this drawer. Called by LabCabinet, which is told by the
# level — the placement is randomised per run and captured in save_progress(), the same rule
# KONTUR's `_dark_x` follows: never restore "already found" against a re-rolled answer.
func set_note(text: String) -> void:
	if is_instance_valid(_paper):
		_paper.queue_free()
		_paper = null
	if text == "":
		# An open drawer that has just had its page removed takes the ray back, so E shuts it.
		_refresh_layer()
		return
	var p := NotePaper.new()
	p.name = "HintPage"
	p.text = text
	p.drawer = self
	# ⚠️ Lying NEARLY FLAT and at the FRONT of the tray, not standing up among the folders.
	# Photographed at 52 deg it was edge-on to anyone looking down into an open drawer and
	# read as a bright line; the whole job of this object is to be recognisable as a page at
	# a glance, from the pose a standing player actually looks into a drawer from.
	p.position = Vector3(0.0, 0.02, _front_z - 0.08)
	add_child(p)
	_paper = p
	# ⚠️ ITS COLLIDER IS OFF UNTIL THE DRAWER OPENS, and that is not belt-and-braces, it is
	# load-bearing. The page's grab volume is deliberately generous and it sits INSIDE a shut
	# drawer, so it can be the nearest thing on the interact ray — and because the page's own
	# can_interact() is false while the drawer is shut, player.gd then nulls the target
	# entirely rather than falling through to the drawer behind it. Measured: the ONE drawer
	# holding the page could not be opened, intermittently, depending on which slot the run
	# had put it in. `can_interact()` alone cannot fix this; the collider has to be absent.
	p.set_active(_open)
	_refresh_layer()


func has_note() -> bool:
	return is_instance_valid(_paper)


# ---------------------------------------------------------------- interaction

# ⚠️ The single source of truth for WHICH of the two nested props answers the interact ray.
# See the header's table. Called from every state change rather than being written inline at
# each one, because the failure mode when the drawer and the page are both hittable is not a
# visible bug — it is a press that silently goes to the wrong object (Issue 66).
func _refresh_layer() -> void:
	var mine := not _sliding and not (_open and has_note())
	collision_layer = 2 if mine else 0


func can_interact() -> bool:
	if _sliding:
		return false
	if not _open:
		return true
	# Open: closable only once the page is out of it. While the page is still lying there it
	# is the thing E is for, and it is what the ray reaches (see _refresh_layer).
	return not has_note()


func is_open() -> bool:
	return _open


func interact() -> void:
	if not can_interact():
		return
	if _open:
		close()
	else:
		_open_drawer()


func _open_drawer() -> void:
	_open = true
	_sliding = true
	_refresh_layer()
	_play_creak(OPEN_PITCH)
	var t := create_tween()
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "position:z", _base_z + SLIDE, SLIDE_TIME)
	# Connected, never awaited (Issue 6).
	t.finished.connect(_on_open_finished)


# The other half of the toggle. Safe to call with the page still inside — the page's collider
# goes back down as the drawer starts moving, which is the Issue-66 direction of the same
# guard that turns it on. The player cannot reach this path with a page in the drawer
# (can_interact() refuses), but the restore path and the level can.
func close() -> void:
	if not _open or _sliding:
		return
	_open = false
	_sliding = true
	# ⚠️ FIRST, and not at the end of the tween: the page is travelling back inside the
	# carcass from this frame on, and a grab volume left live while it goes is exactly the
	# collider that made a shut drawer unopenable (Issue 66).
	if is_instance_valid(_paper):
		_paper.set_active(false)
	_refresh_layer()
	_play_creak(CLOSE_PITCH)
	var t := create_tween()
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(self, "position:z", _base_z, CLOSE_TIME)
	t.finished.connect(_on_close_finished)


func _on_open_finished() -> void:
	if not is_inside_tree():
		return
	_sliding = false
	# An opened drawer holding the page stops answering the ray, so the page — which is
	# BEHIND this collider from every angle a player looks in from — becomes the target.
	# Once it is empty the drawer takes the ray back, and E shuts it again.
	_refresh_layer()
	if is_instance_valid(_paper):
		_paper.set_active(true)
	# ⚠️ An empty drawer says NOTHING — no toast, no caption, no panic, no journal entry.
	# See the header: the player can see it is empty. `check_lab_cabinet.gd` counts the
	# on-screen labels across an open and asserts the count does not move.
	opened.emit(index)


func _on_close_finished() -> void:
	if not is_inside_tree():
		return
	_sliding = false
	position.z = _base_z
	_refresh_layer()
	closed.emit(index)


func open_instantly() -> void:
	if _open:
		return
	_open = true
	position.z = _base_z + SLIDE
	_refresh_layer()
	if is_instance_valid(_paper):
		_paper.set_active(true)


func close_instantly() -> void:
	if not _open:
		return
	_open = false
	_sliding = false
	position.z = _base_z
	if is_instance_valid(_paper):
		_paper.set_active(false)
	_refresh_layer()


func _on_note_taken() -> void:
	# ⚠️ Cleared HERE, not left to the page's own queue_free(): is_instance_valid() stays true
	# for a queued node until the end of the frame, so has_note() — and therefore both
	# can_interact() and _refresh_layer() — would still believe the page was in the drawer for
	# the rest of this frame, and E would do nothing on the press right after taking it.
	_paper = null
	_refresh_layer()
	note_taken.emit(index)


func _play_creak(pitch: Vector2) -> void:
	if not _creak or not _creak.stream:
		return
	_creak.pitch_scale = randf_range(pitch.x, pitch.y)
	_creak.play()


# ---------------------------------------------------------------- the page itself

# The second press. A page you can see lying in an open drawer, that you have to pick up.
class NotePaper extends StaticBody3D:
	var text: String = ""
	var drawer: Node = null
	var _taken: bool = false
	var _active: bool = false
	var _col: CollisionShape3D = null

	# Hittable only while the drawer that holds it is open.
	func set_active(on: bool) -> void:
		_active = on
		if _col:
			_col.disabled = not on

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var sheet := MeshInstance3D.new()
		sheet.name = "Sheet"
		var bm := BoxMesh.new()
		bm.size = Vector3(0.46, 0.006, 0.28)
		sheet.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = LabCabinetDrawer.PAPER
		mat.roughness = 0.95
		sheet.material_override = mat
		# A slight tilt only — enough that it does not look printed onto the tray floor.
		sheet.rotation.x = deg_to_rad(-16.0)
		add_child(sheet)

		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		# Generous on purpose — this is an invisible, non-solid grab volume, and the player
		# is reaching into a 0.26 m drawer slot from above at an angle. ⚠️ Shallow enough in Z
		# that it stays behind the DRAWER's own volume even when shut, so a shut drawer is
		# never shadowed by the page inside it; the disabled flag below is the real guard, and
		# this is the geometry agreeing with it.
		shape.size = Vector3(0.52, 0.20, 0.22)
		col.shape = shape
		_col = col
		add_child(col)
		set_active(_active)

	# Unreachable until the drawer has actually opened — belt and braces on top of the
	# geometry, so a stray ray through the carcass can never read a page in a shut drawer.
	func can_interact() -> bool:
		return not _taken and drawer != null and bool(drawer.call("is_open"))

	func interact() -> void:
		if not can_interact():
			return
		_taken = true
		# Archived like any other safe note, so TAB can return it three levels later at the
		# Flood's seam wall — which is the entire reason the journal exists.
		GameState.record_note(text, 1)
		NoteUI.show_note(text)
		if drawer:
			drawer.call("_on_note_taken")
		# It is in your hands now, not in the drawer.
		queue_free()
