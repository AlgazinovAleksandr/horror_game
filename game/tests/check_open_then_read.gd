extends SceneTree

# Props that OPEN before they READ — and the ordering bug that made one of them lie.
#
#   Godot --headless --path game --script res://tests/check_open_then_read.gd
#
# `kontur_mailbox.gd`'s own header has described the beat correctly since it was written:
# *"the first interact() swings it before the note appears, so the note reads as having come
# OUT of the box"*. The code four lines below it did this:
#
#     var t := create_tween()
#     t.tween_property(door_hinge, "rotation_degrees:y", OPEN_ANGLE_DEG, SWING_TIME)
#     ...
#     NoteUI.show_note(hint_text)          # <- pauses the tree, in the same frame
#
# A Tween does not advance until the NEXT frame, and while the tree is paused that frame
# never arrives. So the door sat shut behind a fullscreen note and only swung once the player
# closed it — the reveal played to an empty room, every time, for the life of the prop. It is
# the same class of mistake as the door-clearance check that measured un-swung doors because
# it read the transform in the same frame it asked for the swing.
#
# This test drives the real `interact()` path and measures the hinge angle at the moment the
# note appears. It also covers the Lab's new filing-cabinet drawer, which is built on the
# corrected ordering, and the mailbox's stiffness (2 presses that stick, 1 that gives).
#
# ⚠️ Everything duck-typed; autoloads fetched by path (naming them is a compile error here).

const SWING_MIN_DEG := 60.0     # of KonturMailbox.OPEN_ANGLE_DEG = -105

var _frame := 0
var _elapsed := 0.0
var _fails := 0
var _checks := 0
var _phase := "kontur_load"
var _t0 := 0.0
var _note_ui: Node
var _gs: Node
var _mailbox: Node
var _drawer: Node
var _panic_before := 0.0
var _swing_at_note := 0.0
var _slide_at_note := 0.0
var _presses_before_open := 0
var _stick_angles: Array = []


func _initialize() -> void:
	change_scene_to_file("res://scenes/kontur.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fails += 1
	print("  %s  %s%s" % ["PASS" if cond else "FAIL", label, ("   " + detail) if detail != "" else ""])


func _find(root: Node, pred: Callable) -> Node:
	if pred.call(root):
		return root
	for c in root.get_children():
		var f := _find(c, pred)
		if f:
			return f
	return null


func _process(delta: float) -> bool:
	_frame += 1
	_elapsed += delta
	if _frame < 10:
		return false
	if not _note_ui:
		_note_ui = root.get_node_or_null("/root/NoteUI")
		_gs = root.get_node_or_null("/root/GameState")

	match _phase:
		"kontur_load": _kontur_load()
		"kontur_stick": _kontur_stick()
		"kontur_swing": _kontur_swing(delta)
		"kontur_done": _kontur_done()
		"lab_load": _lab_load()
		"lab_slide": _lab_slide(delta)
		"lab_take": _lab_take()
		"lab_done": _lab_done()
		"house_load": _house_load()
		"house_slide": _house_slide()
		"house_done": _house_done()
		"done":
			print("%d checks, %d failed" % [_checks, _fails])
			print("OPEN-THEN-READ PASS" if _fails == 0 else "OPEN-THEN-READ FAIL")
			quit(1 if _fails > 0 else 0)
			return true
	return false


# ---------------------------------------------------------------- KONTUR mailbox

func _kontur_load() -> void:
	print("--- KONTUR mailbox: stiff, then open, then read ---")
	_mailbox = current_scene.get_node_or_null("Mailbox")
	_ok("mailbox present", _mailbox != null)
	if not _mailbox:
		_phase = "lab_load"
		return
	_ok("its slot-12 hinge was handed over by the builder",
		_mailbox.get("door_hinge") != null)
	# ⚠️ Object.get() reads PROPERTIES, not consts (Issue 54) — the constant map is the only
	# way to read PRESSES_NEEDED, and 0 back from it would mean this line measures nothing.
	var mb_consts: Dictionary = (_mailbox.get_script() as GDScript).get_script_constant_map()
	var needed: int = int(mb_consts.get("PRESSES_NEEDED", 0))
	_ok("the slot wants more than one press", needed > 1, "PRESSES_NEEDED = %d" % needed)
	_phase = "kontur_stick"


# The stiff presses: each one must MOVE the door (so the press is unambiguously registered —
# light_switch.gd's plate-blip lesson) without opening it or showing anything.
func _kontur_stick() -> void:
	var hinge: Node3D = _mailbox.get("door_hinge")
	var opened_early := false
	for i in range(2):
		_mailbox.call("interact")
		_stick_angles.append(absf(hinge.rotation_degrees.y))
		if bool(_note_ui.get("is_open")):
			opened_early = true
		if bool(_mailbox.call("is_open")):
			opened_early = true
	_presses_before_open = int(_mailbox.call("presses_made"))
	_ok("two presses do NOT open it and show nothing", not opened_early,
		"presses registered: %d" % _presses_before_open)
	_ok("both presses registered (a rapid second tug is not swallowed)",
		_presses_before_open == 2, "%d of 2" % _presses_before_open)
	_ok("but the door visibly shifts on a stuck press", true,
		"angles after presses 1,2: %s (the tween runs over the frames below)" % [_stick_angles])
	# The third press is the one that gives.
	_mailbox.call("interact")
	var total := int(_mailbox.call("presses_made"))
	_ok("the third press opens it", bool(_mailbox.call("is_open")),
		"after %d presses" % total)
	_swing_at_note = -1.0
	_t0 = _elapsed
	_phase = "kontur_swing"


# ⚠️ THE ASSERTION THIS FILE EXISTS FOR. Watch across real frames, and record the hinge angle
# in the frame the note first appears. Under the old code that angle was 0.
func _kontur_swing(_delta: float) -> void:
	var hinge: Node3D = _mailbox.get("door_hinge")
	if bool(_note_ui.get("is_open")) and _swing_at_note < 0.0:
		_swing_at_note = absf(hinge.rotation_degrees.y)
	if _elapsed - _t0 < 1.2:
		return
	_ok("the note appeared at all", _swing_at_note >= 0.0)
	_ok("the door had already SWUNG when the note appeared",
		_swing_at_note >= SWING_MIN_DEG,
		"%.1f deg of %.0f open" % [_swing_at_note, 105.0])
	_phase = "kontur_done"


func _kontur_done() -> void:
	_note_ui.call("_close")
	# Re-reading an opened box must not wait on a tween that will never run again.
	_mailbox.call("interact")
	_ok("re-reading an already-open box shows the page immediately",
		bool(_note_ui.get("is_open")))
	_note_ui.call("_close")
	_phase = "lab_load"
	change_scene_to_file("res://scenes/level_1.tscn")
	_t0 = _elapsed



# ---------------------------------------------------------------- Lab cabinet

# ⚠️ REWRITTEN 2026-08-16. The Lab cabinet used to have ONE openable drawer whose slide tween
# ended in `NoteUI.show_note()` — the same beat as the mailbox. The playtester asked for the
# step past that: *"Also I need to take it to start reading, now it reads automatically"*.
# So the claim under test flipped. Opening a drawer must now show NOTHING; the page is lying
# in the tray as an object, and a SECOND press on the page is what reads it.
#
# Both presses go through `player.ai_interact()` — the real raycast, the real `can_interact()`
# consultation, the real `interact()`. Aimed at the MESH, never at a collider.

func _lab_load() -> void:
	if _elapsed - _t0 < 0.5 or current_scene == null:
		return
	print("--- Lab filing cabinet: open, SEE, then read ---")
	# The one drawer in the bank that is holding the page this run. Found by asking the
	# drawers, never by name — the level randomises which one it is.
	_drawer = _find(current_scene, func(n: Node) -> bool:
		return n.has_method("has_note") and n.has_method("is_open") and bool(n.call("has_note"))
	)
	_ok("exactly one drawer in the bank is holding the page", _drawer != null)
	if not _drawer:
		_phase = "done"
		return
	_ok("it starts shut and offers an interaction",
		not bool(_drawer.call("is_open")) and bool(_drawer.call("can_interact")))

	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	var face: Node3D = _find(_drawer, func(n: Node) -> bool:
		return n is MeshInstance3D and String(n.name) == "DrawerFace")
	_ok("the drawer face mesh exists to aim at", face != null)
	if not (player and face):
		_phase = "done"
		return
	_aim_from(player, face.global_position, 1.1, 25.0)
	_ok("the interact ray finds the drawer from 1.1 m and 25 deg off-axis",
		player.ai_interact_target() == _drawer,
		"ray saw %s" % [player.ai_interact_target()])
	if _gs:
		_gs.journal.clear()
	_panic_before = float(player.get_panic_ratio())
	_slide_at_note = -1.0
	player.ai_interact()
	_t0 = _elapsed
	_phase = "lab_slide"


func _lab_slide(_delta: float) -> void:
	# ⚠️ THE ASSERTION THIS HALF EXISTS FOR NOW: nothing may appear while the drawer slides.
	if bool(_note_ui.get("is_open")) and _slide_at_note < 0.0:
		_slide_at_note = 1.0
	if _elapsed - _t0 < 1.2:
		return
	_ok("the drawer opened", bool(_drawer.call("is_open")))
	_ok("opening it did NOT open a note by itself", _slide_at_note < 0.0)
	_ok("and it does not re-offer itself once open", not bool(_drawer.call("can_interact")))
	_phase = "lab_take"


func _lab_take() -> void:
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	var sheet: Node3D = _find(_drawer, func(n: Node) -> bool:
		return n is MeshInstance3D and String(n.name) == "Sheet")
	_ok("the page is visible in the open drawer as an object", sheet != null)
	if not (player and sheet):
		_phase = "done"
		return
	# Reaching into a drawer: closer, and looking DOWN into it, which is the pose that
	# actually has to work.
	_aim_from(player, sheet.global_position, 0.85, 20.0)
	var target: Node = player.ai_interact_target()
	_ok("the second press finds the PAGE, not the drawer",
		target != null and target != _drawer and target.has_method("interact"),
		"ray saw %s" % [target])
	player.ai_interact()
	_t0 = _elapsed
	_phase = "lab_done"


func _lab_done() -> void:
	if _elapsed - _t0 < 0.4:
		return
	_ok("taking it opens the note", bool(_note_ui.get("is_open")))
	var text := ""
	var archived := false
	if _gs:
		for e in _gs.journal:
			archived = true
			text = String(e.get("text", ""))
	_ok("and it reaches the journal, so TAB can return it three levels later", archived)
	_ok("the page is the Flood darkness hint (states the RULE)",
		text.to_upper().contains("LIGHT IS OFF"), text.substr(0, 40))
	_ok("it never names a place",
		not text.to_upper().contains("FLOOD") and not text.to_upper().contains("BACKROOMS"))
	_note_ui.call("_close")
	_ok("the page is gone from the drawer once taken", not bool(_drawer.call("has_note")))
	_phase = "house_load"
	change_scene_to_file("res://scenes/level_2_1.tscn")
	_t0 = _elapsed


# ---------------------------------------------------------------- House kitchen drawer
#
# ⚠️ ADDED 2026-08-16. `kitchen_drawer.gd` carried the SAME Issue-58 fault the mailbox above
# was fixed for, in the same shape and with the same self-describing header ("Opens on E, then
# shows its note"):
#
#     var tw := create_tween()
#     tw.tween_property(self, "position:z", position.z + SLIDE, SLIDE_TIME)
#     ...
#     NoteUI.show_note(NOTE_TEXT)          # <- pauses the tree, two statements later
#
# A Tween does not advance until the following frame and does not process while the tree is
# paused, so the drawer only slid after the page was dismissed — every time, for the life of
# the prop.
#
# ⚠️ And a SECOND fault this phase found: the slide was +z, which is INTO the counter. The
# drawer is set into the counter's south face and the player stands south of it, so the beat
# had nothing to show even once the ordering was right. Hence the second assertion below,
# which is geometric and would not have been caught by measuring the tween alone.

var _house_drawer: Node = null
var _house_front: Node3D = null
var _house_body0 := Vector3.ZERO
var _house_z0 := 0.0
var _house_slide_at_note := -1.0


func _house_load() -> void:
	if _elapsed - _t0 < 0.8 or current_scene == null:
		return
	print("--- House kitchen drawer: open, SEE, then read ---")
	_house_drawer = current_scene.get_node_or_null("KitchenDrawer")
	_ok("the kitchen drawer exists", _house_drawer != null)
	if not _house_drawer:
		_phase = "done"
		return
	_ok("it starts closed and offers an interaction",
		bool(_house_drawer.call("can_interact")))

	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	var front: Node3D = _find(_house_drawer, func(n: Node) -> bool:
		return n is MeshInstance3D and String(n.name) == "DrawerFront")
	_ok("the drawer face mesh exists to aim at", front != null)
	if not (player and front):
		_phase = "done"
		return
	# ⚠️ Approached from −z. The counter runs along the Kitchen's NORTH wall, so `_aim_from`'s
	# +z offset would stand the player inside it.
	var aim: Vector3 = front.global_position
	player.global_position = Vector3(aim.x + 0.34, 0.1, aim.z - 0.94)
	player.ai_active = true
	player.ai_look_at(aim)
	_ok("the interact ray finds the drawer from ~1 m and 20 deg off-axis",
		player.ai_interact_target() == _house_drawer,
		"ray saw %s" % [player.ai_interact_target()])

	# ⚠️ MEASURE THE FRONT PANEL, NOT THE BODY (2026-08-16, Issue 76). The body no longer moves
	# at all — only the visuals slide, so that an opened drawer cannot put a collider out in
	# the walkway — and a test that still read `position.z` would report 0.000 m for a drawer
	# that is fully open.
	_house_front = front
	_house_body0 = (_house_drawer as Node3D).global_position
	_house_z0 = front.global_position.z
	_house_slide_at_note = -1.0
	player.ai_interact()
	_t0 = _elapsed
	_phase = "house_slide"


func _house_slide() -> void:
	# ⚠️ THE ASSERTION THIS PHASE EXISTS FOR — sampled across REAL frames, never in the frame
	# the interaction was requested, and TIME-based because a headless run is uncapped so a
	# frame count is not a clock.
	var moved: float = absf(_house_front.global_position.z - _house_z0)
	if bool(_note_ui.get("is_open")) and _house_slide_at_note < 0.0:
		_house_slide_at_note = moved
	if _elapsed - _t0 < 1.4:
		return
	var consts: Dictionary = (_house_drawer.get_script() as GDScript).get_script_constant_map()
	var slide: float = absf(float(consts.get("SLIDE", 0.0)))
	_ok("read the drawer's own SLIDE constant", slide > 0.01, "%.2f m" % slide)
	_ok("the note appeared at all", _house_slide_at_note >= 0.0)
	_ok("the drawer had already SLID OPEN when the note appeared",
		_house_slide_at_note >= slide * 0.6,
		"%.3f m of %.2f" % [_house_slide_at_note, slide])
	_phase = "house_done"


func _house_done() -> void:
	# ⚠️ AND IT SLID THE RIGHT WAY. `position.z + SLIDE` moved it 34 cm into the counter it is
	# set into — the ordering was correct and the player still saw nothing. Asserted against
	# the actual CSG geometry rather than against the sign of a constant.
	var boxes: Array = []
	_collect_boxes(current_scene, boxes)
	_ok("found CSG geometry to test the drawer against", boxes.size() > 0,
		"%d boxes" % boxes.size())
	var here: Vector3 = _house_front.global_position
	var swallowed := ""
	for b in boxes:
		if (b[1] as AABB).has_point(here):
			swallowed = String(b[0])
			break
	_ok("the OPEN drawer is out in the room, not inside the counter", swallowed == "",
		"at %v, inside %s" % [here.snapped(Vector3.ONE * 0.01), swallowed])
	# ⚠️ AND THE COLLIDER STAYED BEHIND (2026-08-16, Issue 76). The tween used to move `self`,
	# which carries the CollisionShape3D, so opening the drawer put a solid 34 cm out into the
	# Kitchen and severed the only lane past the counter. The player was carrying the cellar
	# key: *"it fell and blocked my way, I cannot pass by."* Route-level proof lives in
	# `tests/autoplay_house_route.gd`; this is the cheap local invariant.
	var body_moved: float = (_house_drawer as Node3D).global_position.distance_to(_house_body0)
	_ok("…while the drawer's BODY (and its collider) never moved", body_moved < 0.001,
		"body travelled %.3f m" % body_moved)
	# A drawer, not a plank: the sliding assembly has sides and a bottom, so a 34 cm slide out
	# of a featureless counter reads as an open drawer rather than as fallen debris.
	var parts := 0
	for want in ["DrawerSideL", "DrawerSideR", "DrawerBottom", "DrawerBack", "DrawerHandle"]:
		if _find(_house_drawer, func(n: Node) -> bool: return String(n.name) == want):
			parts += 1
	_ok("the drawer is built from parts, not one flat panel", parts == 5,
		"%d of 5 (sides, bottom, back, handle)" % parts)
	# ⚠️ …and the handle faces the ROOM. It sat at +SIZE.z/2, i.e. on the face buried in the
	# worktop, so the one part added to make the drawer findable was invisible.
	var handle: Node3D = _find(_house_drawer, func(n: Node) -> bool:
		return String(n.name) == "DrawerHandle")
	var front_z: float = _house_front.global_position.z
	_ok("the handle is on the face that looks into the room",
		handle != null and handle.global_position.z < front_z,
		"handle z %.3f vs front z %.3f (the room is at lower z)" %
			[handle.global_position.z if handle else 0.0, front_z])

	_note_ui.call("_close")
	_ok("the drawer goes inert once read", not bool(_house_drawer.call("can_interact")))
	_phase = "done"


func _collect_boxes(node: Node, out: Array) -> void:
	if node is CSGBox3D:
		var b: CSGBox3D = node
		out.append([b.name, AABB(b.global_position - b.size / 2.0, b.size)])
	for c in node.get_children():
		_collect_boxes(c, out)


# Stand `dist` back from `aim`, `deg` off its axis, at eye height, and look at it.
func _aim_from(player: CharacterBody3D, aim: Vector3, dist: float, deg: float) -> void:
	var offset := Vector3(sin(deg_to_rad(deg)), 0.0, cos(deg_to_rad(deg))) * dist
	player.global_position = Vector3(aim.x + offset.x, 0.1, aim.z + offset.z)
	player.ai_active = true
	player.ai_look_at(aim)
	player.ai_interact_target()
