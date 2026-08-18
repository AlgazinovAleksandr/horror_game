extends SceneTree

# THE GUEST — the House rearranging itself — plus the cellar child, the kitchen fridge and
# the kitchen drawer.
#
#   Godot --headless --path game --script res://tests/check_house_guest.gd
#
# The ladder:
#   1 map solved    -> the FALLING PAINTING goes face-down on the floor
#   2 key taken     -> (nothing changes in the house)
#   3 cellar opened -> arms the cellar sequence
#   4 note read     -> the music box has moved to the Hallway, still playing
#
# What is asserted, and why each one can break silently:
#   * the falling painting is in the CHILD'S ROOM (2026-08-16 — it was in the Bedroom, which
#     is off every route after the map is solved, so the beat played to an empty house), lands
#     flat, FACE UP, and moves along ITS OWN FORWARD — the old hard-coded `p.z + 0.55` was
#     correct only for a panel facing +z and would have slid this one sideways into the wall
#   * the cellar child DOES NOT APPEAR while the player cannot look: not while a note is open,
#     not while the tree is paused, and not while they are PINNED IN A BEARTRAP — which is
#     what actually happened in the 2026-08-16 session (a 15-point ESCAPE_INITIAL_PANIC spike
#     0.63 m from the trap, and the whole appearance inside the 7 s QTE)
#   * …and that it then DOES appear, IN THE VIEW CONE AND UNOCCLUDED. The old assertion was
#     `distance_to(player) < 5.0`, which a figure standing directly BEHIND the player passes —
#     i.e. the guard for the exact defect the user photographed could not see it
#   * the child is a `Watcher` — no ScaryObject ancestor and no collider — so the whole
#     rearrangement stays worth zero panic and the fridge remains the level's only new cost
#   * the fridge door swings OUT of its carcass (it swung in, and capture B1 contained no door
#     at all), and the revealed head clears both wire shelves (the lower one cut its chin off)
#   * the fridge charges on the REVEAL rather than the press, and goes completely inert after
#   * the drawer OPENS BEFORE its note pauses the tree, and slides out of the counter, not in
#
# ⚠️ NEVER write `bool(node.get("some_flag"))` here — see _flag() below.

const HALLWAY_SPOT := Vector3(0.0, 0.11, 7.4)
const NEAR := 0.35
const PAINTING_SLIDE := 0.55        # level_2.gd:_drop_painting()'s landing offset
const SEEN_DOT := 0.55              # Watcher.SEEN_DOT
const TIMEOUT := 90.0
# The cellar shell's INNER faces (level_2.gd:_build_cellar — centre (5,-6), 7x7, walls 0.2
# thick, the west one nudged 1 cm). A figure embedded in a wall lands outside these, or inside
# the margin; Watcher.FIT_RADIUS is 0.9, so a legitimately-placed one clears them by that.
const CELLAR_X := Vector2(1.59, 8.40)
const CELLAR_Z := Vector2(-9.40, -2.60)
const CELLAR_MARGIN := 0.85

var _t := 0.0
var _stage := 0
var _fails: Array[String] = []
var _checks := 0
var _scene: Node = null
var _player: CharacterBody3D = null
var _note_ui: Node = null
var _box: Node3D = null
var _painting: Node3D = null
var _painting_from := Vector3.ZERO
var _painting_fwd := Vector3.ZERO
var _fridge: Node = null
var _drawer: Node = null


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_2_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


# ⚠️ `Object.get()` returns null for a property that does not exist, and `bool(null)` THROWS.
# Thrown from inside `_process`, that aborts the frame before the stage counter advances, so
# the test re-runs the same stage forever: on 2026-07-29 this produced 21,265 assertion lines
# and a 28-minute hang on a test whose own timeout is 30 seconds, because a flag had been
# renamed out from under it. These helpers turn a missing property into `false`.
func _flag(name: String) -> bool:
	var v: Variant = _scene.get(name)
	return v != null and v == true


func _flag_on(obj: Object, name: String) -> bool:
	var v: Variant = obj.get(name)
	return v != null and v == true


func _has_ancestor_scary(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if p.get_script() and String(p.get_script().get_global_name()) == "ScaryObject":
			return true
		p = p.get_parent()
	return false


func _find_class(node: Node, cls: String) -> Node:
	if node.get_script() and String(node.get_script().get_global_name()) == cls:
		return node
	for c in node.get_children():
		var r := _find_class(c, cls)
		if r:
			return r
	return null


func _count_class(node: Node, cls: String) -> int:
	var n := 0
	if node.get_script() and String(node.get_script().get_global_name()) == cls:
		n += 1
	for c in node.get_children():
		n += _count_class(c, cls)
	return n


func _named(node: Node, want: String) -> Node3D:
	if node is Node3D and String(node.name) == want:
		return node
	for c in node.get_children():
		var r := _named(c, want)
		if r:
			return r
	return null


func _world_aabb(mi: MeshInstance3D) -> AABB:
	return mi.global_transform * mi.get_aabb()


# Face the player at `at` from `dist` metres away, at the given floor height.
func _stand(from: Vector3, look_at: Vector3) -> void:
	_player.global_position = from
	var cam := _player.get_node_or_null("Camera3D") as Camera3D
	var to := look_at - (from + Vector3(0, 1.2, 0))
	to.y = 0.0
	if to.length() > 0.01:
		_player.rotation.y = atan2(-to.x, -to.z)
	if cam:
		cam.rotation.x = 0.0


# Re-arm the cellar sequence so a second and third case can be run in one scene.
func _rearm_child() -> void:
	var child := _scene.get_node_or_null("GuestChild")
	if child:
		child.free()
	_scene.set("_guest_child_done", false)
	_scene.set("_child_node", null)
	_scene.set("_child_postponed", 0.0)


# Is the child both in the player's horizontal view cone AND unoccluded?
func _child_report(child: Node3D) -> Dictionary:
	var cam := _player.get_node_or_null("Camera3D") as Camera3D
	var eye: Vector3 = cam.global_position if cam else _player.global_position
	var to: Vector3 = child.global_position - eye
	var flat := Vector3(to.x, 0.0, to.z)
	var fwd: Vector3 = -(cam.global_basis.z if cam else _player.global_basis.z)
	fwd.y = 0.0
	var dot := 0.0
	if flat.length() > 0.01 and fwd.length() > 0.01:
		dot = fwd.normalized().dot(flat.normalized())
	var seen := false
	if child.has_method("is_visible_to_player"):
		seen = bool(child.call("is_visible_to_player"))
	# ⚠️ An INDEPENDENT "not inside a wall" test, deliberately not the LOS ray — the spawn
	# already used that one, so re-running it would be circular. A figure standing in the room
	# has CELLAR_MARGIN of floor around it in both axes; one embedded in the shell does not.
	var p: Vector3 = child.global_position
	var clear: bool = p.x > CELLAR_X.x + CELLAR_MARGIN and p.x < CELLAR_X.y - CELLAR_MARGIN \
		and p.z > CELLAR_Z.x + CELLAR_MARGIN and p.z < CELLAR_Z.y - CELLAR_MARGIN
	return {"dot": dot, "dist": to.length(), "seen": seen, "clear": clear, "at": p}


func _process(delta: float) -> bool:
	_t += delta

	if _stage == 0 and _t > 1.2:
		_scene = current_scene
		_player = _scene.get_node_or_null("Player") as CharacterBody3D
		_note_ui = root.get_node_or_null("/root/NoteUI")
		_box = _scene.get_node_or_null("MusicBox") as Node3D
		_painting = _scene.get("_bedroom_painting") as Node3D
		_ok("player found", _player != null)
		_ok("NoteUI autoload present", _note_ui != null)
		_ok("the music box exists as a real object", _box != null,
			"it used to be a bare looping sound with no body at all")
		_ok("the falling-painting handle exists", _painting != null)
		_ok("the Landing mirror exists", _scene.get_node_or_null("LandingMirror") != null)
		_ok("the fridge exists", _scene.get_node_or_null("Fridge") != null)
		_ok("the kitchen drawer exists", _scene.get_node_or_null("KitchenDrawer") != null)
		if not (_player and _box and _painting and _note_ui):
			quit(1)
			return true

		_ok("the music box's loop is a CHILD of the body",
			_box.get_node_or_null("MusicBoxAudio") != null,
			"so moving the box moves the sound")
		_ok("the kitchen chairs are built from parts, not one box",
			_scene.get_node_or_null("KitchenChair") != null
				and _scene.get_node_or_null("KitchenTable") != null)
		_ok("no figure anywhere before its stage", _count_class(_scene, "Watcher") == 0,
			"the cellar corner Watcher was removed 2026-07-29 — only the child remains")

		# ⚠️ Capture BOTH the position and the facing BEFORE the drop. After it, the panel has
		# been pitched flat, so its basis.z points at the ceiling and cannot be used to check
		# which way it slid.
		_painting_from = _painting.position
		_painting_fwd = _painting.global_transform.basis.z
		_painting_fwd.y = 0.0
		_painting_fwd = _painting_fwd.normalized()
		_ok("it starts on a wall in the CHILD'S ROOM, not the Bedroom",
			absf(_painting_from.x) < 2.6 and _painting_from.z > 14.0 and _painting_from.z < 19.0,
			"at %s" % str(_painting_from.snapped(Vector3.ONE * 0.01)))
		# ⚠️ AND ON THE WALL THE LOCK IS ON (2026-08-16: *"let it be next to the door so once you
		# approach the lock it falls"*). The right ROOM was not enough — for one session it hung
		# on the east wall, so approaching the lock did not stage the beat.
		var door := _scene.get_node_or_null("ExitDoor") as Node3D
		_ok("the exit door exists to measure against", door != null)
		if door:
			_ok("…on the NORTH wall, the same wall as the exit door",
				_painting_from.z > door.global_position.z - 0.4
					and _painting_from.z < door.global_position.z + 0.4,
				"painting z %.2f vs door z %.2f" % [_painting_from.z, door.global_position.z])
			var gap: float = absf(_painting_from.x - door.global_position.x)
			# 1.25 m door + 0.8 m panel, so their half-widths sum to 1.025: anything above that
			# is clear wall between them, and 3 m would be the far corner rather than "beside".
			_ok("…BESIDE the door, not on it and not across the room",
				gap > 1.03 and gap < 3.0, "%.2f m between their centres" % gap)
			_ok("…and its facing is INTO the room, not into the wall",
				_painting_fwd.z < -0.9, "forward %s" % str(_painting_fwd.snapped(Vector3.ONE * 0.01)))
		# ⚠️ NOT ON A DOORWAY. `wall_point()` returns the wall CENTRE, which is exactly where a
		# RoomBuilder doorway sits, and a collider there silently seals the room.
		var doors: Array = _scene.get_script().get_script_constant_map().get("DOORS", [])
		_ok("read the level's own DOORS table", doors.size() >= 8, "%d doorways" % doors.size())
		var on_doorway := ""
		for d in doors:
			var dp: Vector2 = d["pos"]
			var w: float = float(d["width"]) * 0.5 + 0.4
			if String(d["dir"]) == "z" and absf(_painting_from.z - dp.y) < 0.35 \
					and absf(_painting_from.x - dp.x) < w:
				on_doorway = "z-doorway at %s" % str(dp)
			elif String(d["dir"]) == "x" and absf(_painting_from.x - dp.x) < 0.35 \
					and absf(_painting_from.z - dp.y) < w:
				on_doorway = "x-doorway at %s" % str(dp)
		_ok("…and it is not hung across a doorway", on_doorway == "", on_doorway)

		# ⚠️ ARM IT, DO NOT DROP IT. The three cases below drive the level's REAL
		# `_tick_painting()`, because "the milestone fired" and "the player watched it fall"
		# are different claims and the shipped build only ever proved the first: the replay
		# log has the painting hitting the floor 1.5 s after the key was taken, in a room the
		# player did not enter for another ~130 s, through the Landing's south wall.
		_scene.call("_advance_guest", 1)
		_ok("stage 1 ARMS the painting rather than dropping it",
			_flag("_painting_armed") and not _flag("_painting_fallen"))
		print("  -- the painting falls only when it can actually be SEEN --")
		# (a) In the Landing: the right heading, but out of range and behind a wall.
		_stand(Vector3(0.85, 0.1, 13.0), Vector3(0.85, 1.5, 19.0))
		_stage = 90
		_t = 0.0

	elif _stage == 90 and _t > 0.4:
		_ok("it does NOT fall while the player is in the Landing", not _flag("_painting_fallen"),
			"one room short, through a wall")
		# (b) The LOS case, isolated: 0.9 m away, facing it dead on, with the north wall in
		# between. Distance and facing both pass here; only the ray can refuse.
		_stand(Vector3(0.85, 0.1, 19.75), Vector3(0.85, 1.5, 14.0))
		_stage = 91
		_t = 0.0

	elif _stage == 91 and _t > 0.4:
		var cam := _player.get_node_or_null("Camera3D") as Camera3D
		var eye: Vector3 = cam.global_position if cam else _player.global_position
		var d: float = Vector2(eye.x - _painting_from.x, eye.z - _painting_from.z).length()
		_ok("the LOS case is genuinely in range and facing it (or it proves nothing)",
			d < 4.5, "%.2f m of PAINTING_TRIGGER_DIST 4.5" % d)
		_ok("…and it still does NOT fall, because a wall is in the way",
			not _flag("_painting_fallen"))
		# (c) At the lock. This is the beat.
		_stand(Vector3(-0.7, 0.1, 17.6), Vector3(0.85, 1.5, 18.84))
		_stage = 92
		_t = 0.0

	elif _stage == 92 and _t > 0.4:
		_ok("it DOES fall when the player walks up to the exit lock",
			_flag("_painting_fallen"), "at %v" % _player.global_position.snappedf(0.01))
		_stage = 1
		_t = 0.0

	elif _stage == 1 and _t > 0.6:
		# --- stage 1: the painting goes down ------------------------------------------------
		var pp: Vector3 = _painting.position
		_ok("stage 1 lays the painting on the floor",
			pp.y > -0.1 and pp.y < 0.3, "y = %.2f" % pp.y)
		# ⚠️ Position, not just height. An earlier version asserted only `y < 0.3`, and a
		# painting teleported through the floor to the world ORIGIN passes that.
		_ok("…and it is inside the child's room, not through the floor",
			absf(pp.x) < 2.5 and pp.z > 14.0 and pp.z < 19.0,
			"at %s" % str(pp.snapped(Vector3.ONE * 0.01)))
		# ⚠️ AND IT SLID ALONG ITS OWN FORWARD. The offset was hard-coded `p.z + 0.55`; on this
		# wall (y_rot = -PI/2) that is sideways, and the picture would have finished half
		# inside the plaster.
		var slid: Vector3 = pp - _painting_from
		slid.y = 0.0
		var along := 0.0
		if slid.length() > 0.001:
			along = _painting_fwd.dot(slid.normalized())
		_ok("…and it slid OUT INTO THE ROOM, along its own forward",
			along > 0.94 and absf(slid.length() - PAINTING_SLIDE) < 0.05,
			"%.2f m at dot %.3f to facing %s" % [slid.length(), along,
				str(_painting_fwd.snapped(Vector3.ONE * 0.01))])
		# ⚠️ FLAT, not merely low. MovedProp only rotated YAW until 2026-07-28, so it dropped
		# to floor height and stayed UPRIGHT — a picture hung on a very low wall.
		_ok("…and it is lying FLAT, not standing upright on the floor",
			absf(rad_to_deg(_painting.rotation.x)) > 60.0,
			"pitch %.1f degrees" % rad_to_deg(_painting.rotation.x))
		# ⚠️ And FACE-UP. A QuadMesh faces its own +Z; a +90° pitch turns that toward the floor
		# and backface culling makes it vanish (Issue 28) — which is exactly what shipped once.
		var facing: Vector3 = _painting.global_transform.basis.z
		_ok("…and FACE-UP, not face-down into the floor", facing.y > 0.5,
			"quad normal y = %.2f" % facing.y)

		# --- THE CELLAR SEQUENCE, case (i): a note is open ----------------------------------
		print("  -- cellar sequence: it must not fire while a note is open --")
		_ok("the lights are on before the sequence", not _flag("_child_dark"))
		_stand(Vector3(5.0, -1.4, -5.0), Vector3(5.0, -1.4, -8.0))   # in the cellar, facing S
		_note_ui.call("show_note", "the player is reading", 0.0)
		_scene.call("_begin_cellar_blackout")
		_ok("entering the cellar kills every light", _flag("_child_dark"))
		_ok("…and takes the torch", not _player.is_flashlight_on())
		# ⚠️ The cellar is a DarkZone. Forcing the torch off there would charge +3/s for a
		# scripted event the player cannot avoid (Issue 18), so the tax must be suspended.
		_ok("…and suspends the dark-zone tax while it does so",
			_flag_on(_player, "_smiler_active"))
		_ok("nothing has appeared yet", _count_class(_scene, "Watcher") == 0)
		_stage = 2
		_t = 0.0

	elif _stage == 2 and _t > 6.4:      # CHILD_APPEAR_DELAY is 5.5
		# THE ASSERTION THIS BLOCK EXISTS FOR: the delay has elapsed, and it has NOT appeared.
		_ok("the child does NOT appear while a note is open",
			_scene.get_node_or_null("GuestChild") == null,
			"SceneTreeTimer defaults to process_always, so it fires through a tree pause")
		_ok("…and the sequence has not ended either — the dark is still holding",
			_flag("_child_dark"))
		_note_ui.call("_close")
		_stage = 3
		_t = 0.0

	elif _stage == 3 and _t > 1.0:      # CHILD_RETRY is 0.25
		var child := _scene.get_node_or_null("GuestChild") as Node3D
		_ok("…and it appears as soon as the note is closed", child != null,
			"a guard that postpones forever is worse than the bug it replaces")
		if child:
			var r := _child_report(child)
			# ⚠️ NOT `distance < 5.0`. A figure directly BEHIND the player at 3.2 m passes a
			# distance test, which is precisely the failure the user photographed.
			_ok("it is IN THE VIEW CONE", float(r["dot"]) >= SEEN_DOT,
				"facing dot %.2f (needs >= %.2f), %.1f m away" % [r["dot"], SEEN_DOT, r["dist"]])
			_ok("…and UNOCCLUDED — not inside or behind a wall", bool(r["seen"]),
				"Watcher.is_visible_to_player() raycasts the eye->figure segment")
			_ok("…and standing in the room with floor round it, not in the shell",
				bool(r["clear"]), "at %s" % str((r["at"] as Vector3).snapped(Vector3.ONE * 0.01)))
			# The two properties that keep it free.
			_ok("the figure feeds NO gaze panic (no ScaryObject ancestor)",
				not _has_ancestor_scary(child))
			_ok("the figure has no collider",
				_find_class(child, "CollisionShape3D") == null
					and child.get_node_or_null("CollisionShape3D") == null)
		var lit := 0
		for e in (_scene.get("_lights") as Array):
			if (e[0] as OmniLight3D).light_energy > 0.001:
				lit += 1
		_ok("…measured: no lamp is still burning", lit == 0, "%d lit" % lit)
		_stage = 4
		_t = 0.0

	elif _stage == 4 and _t > 3.6:      # CHILD_HOLD is 3.0
		_ok("the lights come back afterwards", not _flag("_child_dark"))
		_ok("…and the torch is handed back", _player.is_flashlight_on())
		_ok("…and the dark-zone tax is un-suspended",
			not _flag_on(_player, "_smiler_active"))
		_ok("…and the figure is gone", _scene.get_node_or_null("GuestChild") == null)
		_ok("the whole sequence cost zero panic",
			_player.get_panic_ratio() < 0.05, "panic %.4f" % _player.get_panic_ratio())

		# --- case (ii): PINNED IN A BEARTRAP ------------------------------------------------
		#
		# ⚠️ THE CASE THE USER ACTUALLY HIT, and the one that matters most now: the cellar
		# beartrap is 1.6 m past the blackout trigger on the only heading in, and the user's
		# decision on 2026-08-16 is that it STAYS there. So this collision will keep happening
		# and the postponement is the only thing preventing it.
		#
		# The pin goes through the REAL `player.begin_qte()` — the same call `beartrap.gd`
		# makes from `_start_escape()` — and `is_input_frozen()` is what the level consults.
		print("  -- cellar sequence: it must not fire while PINNED IN A BEARTRAP --")
		_rearm_child()
		_stand(Vector3(5.0, -1.4, -5.0), Vector3(5.0, -1.4, -8.0))
		_player.begin_qte()
		_ok("begin_qte() reads as 'cannot act freely'", _player.is_input_frozen())
		_scene.set("_child_dark", true)
		_scene.call("_cellar_child_appear")
		_ok("the child does not appear on the spot while pinned",
			_scene.get_node_or_null("GuestChild") == null)
		_stage = 5
		_t = 0.0

	elif _stage == 5 and _t > 1.0:
		_ok("…and it is still holding off a second later, not merely delayed one frame",
			_scene.get_node_or_null("GuestChild") == null)
		_player.end_qte()
		_stage = 6
		_t = 0.0

	elif _stage == 6 and _t > 1.0:
		var child2 := _scene.get_node_or_null("GuestChild") as Node3D
		_ok("…and it appears the moment the trap lets go", child2 != null,
			"postponed, never skipped")
		if child2:
			var r2 := _child_report(child2)
			_ok("…in the view cone", float(r2["dot"]) >= SEEN_DOT,
				"dot %.2f, %.1f m" % [r2["dot"], r2["dist"]])
			_ok("…and unoccluded", bool(r2["seen"]))
			_ok("…and clear of the shell", bool(r2["clear"]),
				"at %s" % str((r2["at"] as Vector3).snapped(Vector3.ONE * 0.01)))

		# --- case (iii): standing nose-to-the-wall ------------------------------------------
		#
		# ⚠️ `Watcher.spawn(..., require_los)` was passed FALSE here, which watcher.gd restricts
		# to congregation.gd — the LOS ray is the ONLY probe that catches "inside a wall"
		# (Issue 40/59), so the ladder below it was dead code and a player facing a wall got a
		# figure buried in it. Either it is in front and visible, or there is none. Never both.
		print("  -- cellar sequence: facing a wall from 0.7 m --")
		_rearm_child()
		# Cellar south wall inner face is z = -9.40; stand just off it, looking at it.
		_stand(Vector3(5.0, -1.4, -8.7), Vector3(5.0, -1.4, -12.0))
		_scene.set("_child_dark", true)
		_scene.call("_cellar_child_appear")
		_stage = 7
		_t = 0.0

	elif _stage == 7 and _t > 1.0:
		var child3 := _scene.get_node_or_null("GuestChild") as Node3D
		if child3 == null:
			_ok("facing a wall: no figure at all, rather than one inside the wall", true,
				"a skipped Watcher costs nothing; an embedded one is BACKLOG #8")
		else:
			var r3 := _child_report(child3)
			# ⚠️ The strong half of the claim, and the one A5 is really about: whatever it does,
			# it must never be INSIDE geometry. With require_los=false the three candidates
			# beyond the wall were all accepted, because the remaining probes all originate
			# inside the slab and report clear against a concave CSG trimesh (Issue 40/59).
			_ok("facing a wall: the figure is never buried in it", bool(r3["clear"]),
				"at %s, %.1f m from the player" % [
					str((r3["at"] as Vector3).snapped(Vector3.ONE * 0.01)), r3["dist"]])
			# ⚠️ "IN FRONT" IS DELIBERATELY NOT ASSERTED HERE, and the number is printed instead.
			# Watcher's billboard is 1.6 m wide and `_fits()` wants FIT_RADIUS (0.9 m) of
			# clearance all round, so standing 0.7 m from a wall there is NO candidate inside the
			# view cone that fits — measured: all three ladder distances land beyond the wall and
			# are correctly refused. `_cellar_child_appear()`'s room-centre fallback then places
			# it on open floor BEHIND the player rather than eating the beat entirely, which is
			# the pre-existing design ("It must NOT be allowed to fail silently the way the
			# Hallway version did"). Recorded in backlogs/02-house.md §5 for a later decision.
			print("      (informational) facing-a-wall fallback: dot %.2f, in view cone = %s"
				% [r3["dot"], r3["seen"]])
		_scene.call("_end_cellar_blackout")
		# Out of the cellar for the fridge phase — its DreadZone cancels decay exactly, which
		# would pin the measured panic at its charged value instead of letting it settle.
		_stand(Vector3(5.0, 0.1, 6.0), Vector3(8.0, 0.1, 6.0))

		# --- stage 4 of the ladder: the music box -------------------------------------------
		_scene.call("_force_guest_stages", 4)
		_stage = 8
		_t = 0.0

	elif _stage == 8 and _t > 0.6:
		_ok("stage 4 puts the music box in the Hallway",
			_box.global_position.distance_to(HALLWAY_SPOT) < NEAR,
			"at %s" % str(_box.global_position.snapped(Vector3.ONE * 0.01)))
		var audio := _box.get_node_or_null("MusicBoxAudio") as AudioStreamPlayer3D
		_ok("and it is still playing when it gets there", audio != null and audio.playing)

		var snap: Dictionary = _scene.call("save_progress")
		_ok("save_progress records the Guest stage",
			int(snap.get("guest_stage", -1)) == 4, "guest_stage = %s" % snap.get("guest_stage"))

		# --- the fridge -----------------------------------------------------------------------
		_fridge = _scene.get_node_or_null("Fridge")
		if not _fridge:
			_finish()
			return true
		_ok("the thing inside is hidden until it is opened",
			not bool((_fridge.get_node("FridgeThing") as Node3D).visible))
		_player.set("_panic", 0.0)
		_fridge.call("interact")
		_ok("the fridge reports itself open", bool(_fridge.call("is_open")))
		_ok("and it goes completely inert — no stale 'Press E'",
			bool(_fridge.call("can_interact")) == false)
		_stage = 9
		_t = 0.0

	elif _stage == 9 and _t > 1.1:      # DOOR_DELAY 0.28 + DOOR_OPEN_TIME 0.55, plus slack
		# ⚠️ A WINDOW, not an exact figure. The panic lands with the REVEAL (REVEAL_DELAY 0.62)
		# rather than on the press, and PANIC_DECAY_RATE is 3.5/s, so an exact 10.00 is
		# unobtainable once time has passed.
		var after: float = _player.get_panic_ratio() * 50.0
		_ok("the reveal costs about 10 panic", after > 6.0 and after < 10.5, "%.2f" % after)
		_ok("the thing inside is now visible",
			bool((_fridge.get_node("FridgeThing") as Node3D).visible))

		_check_fridge_geometry()

		var before2: float = _player.get_panic_ratio() * 50.0
		_fridge.call("interact")
		var after2: float = _player.get_panic_ratio() * 50.0
		_ok("a second press charges nothing — it is one-shot",
			absf(after2 - before2) < 0.01, "%.2f -> %.2f" % [before2, after2])

		var snap2: Dictionary = _scene.call("save_progress")
		_ok("save_progress records the open fridge", bool(snap2.get("fridge_open", false)))

		# --- the drawer's cross-level hint ----------------------------------------------------
		_drawer = _scene.get_node_or_null("KitchenDrawer")
		if _drawer:
			_drawer.call("interact")
		_stage = 10
		_t = 0.0

	elif _stage == 10 and _t > 1.0:     # SLIDE_TIME is 0.45, then the note
		if _drawer:
			var gs := root.get_node_or_null("/root/GameState")
			var archived := false
			for e in (gs.get("journal") as Array):
				if String(e["text"]).to_lower().contains("black door"):
					archived = true
			_ok("the drawer's KONTUR hint is archived to the journal", archived,
				"so TAB can re-read it two levels later")
			_ok("the drawer goes inert once read",
				bool(_drawer.call("can_interact")) == false)
		_finish()
		return true

	if _t > TIMEOUT:
		print("RESULT: FAIL — timed out at stage %d" % _stage)
		quit(1)
		return true
	return false


# A1 + A2 — the two things capture B1 photographed.
func _check_fridge_geometry() -> void:
	print("  -- the fridge door and the head --")
	var fridge3d := _fridge as Node3D
	var consts: Dictionary = (_fridge.get_script() as GDScript).get_script_constant_map()
	# ⚠️ Object.get() reads PROPERTIES, not consts (Issue 54).
	var size: Vector3 = consts.get("SIZE", Vector3.ZERO)
	_ok("read the fridge's own SIZE constant", size.length() > 0.1, "%s" % size)
	if size.length() < 0.1:
		return

	var door := _named(_fridge, "FridgeDoor") as MeshInstance3D
	_ok("the door panel exists", door != null)
	if door:
		# ⚠️ IN THE FRIDGE'S OWN FRAME. The hinge was on the −X edge and interact() tweens to
		# +105°, so the free edge travelled toward local −Z — BACKWARDS THROUGH THE SHELL,
		# ending at local (−0.49, y, −0.007), i.e. behind the front face at +SIZE.z/2. That is
		# why the capture contains no door and no handle: they were inside the box.
		var local: Vector3 = fridge3d.global_transform.affine_inverse() * door.global_position
		_ok("the OPEN door is clear of the carcass, in front of its own face",
			local.z > size.z / 2.0,
			"door centre at local z = %.3f, front face at %.3f" % [local.z, size.z / 2.0])
		var handle := _named(_fridge, "FridgeHandle") as MeshInstance3D
		if handle:
			var hl: Vector3 = fridge3d.global_transform.affine_inverse() * handle.global_position
			_ok("…and so is the handle", hl.z > size.z / 2.0, "local z = %.3f" % hl.z)

	# A2 — the wire shelf drew straight across the bottom of the face.
	var face := _named(_fridge, "FridgeFace") as MeshInstance3D
	_ok("the revealed face exists", face != null)
	if face:
		var fab := _world_aabb(face)
		var shelves := 0
		for i in 2:
			var sh := _named(_fridge, "FridgeShelf%d" % i) as MeshInstance3D
			if not sh:
				continue
			shelves += 1
			var sab := _world_aabb(sh)
			_ok("the head clears wire shelf %d" % i, not fab.intersects(sab),
				"face y %.3f..%.3f vs shelf y %.3f..%.3f" % [
					fab.position.y, fab.end.y, sab.position.y, sab.end.y])
		# ⚠️ Assert the sample size. "0 shelves checked … PASS" has happened in this repo.
		_ok("both shelves were actually measured", shelves == 2, "%d found" % shelves)


func _finish() -> void:
	print("")
	print("%d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		for f in _fails:
			print("  FAIL: " + f)
		print("RESULT: FAIL")
		quit(1)
