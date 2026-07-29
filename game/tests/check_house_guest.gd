extends SceneTree

# THE GUEST — the House rearranging itself — plus the kitchen fridge and drawer.
#
# Rewritten 2026-07-28 after playtest. The Guest used to relocate a kitchen chair twice; the
# chair rendered as a flat-shaded cube and the user replaced both of those stages with a
# single appearance of a child figure. The ladder is now:
#
#   1 map solved    -> the bedroom painting is face-down on the floor
#   2 key taken     -> (nothing changes in the house)
#   3 cellar opened -> THE CHILD is standing in the Hallway, once, with a sound
#   4 note read     -> the music box has moved to the Hallway, still playing
#
# What is asserted, and why each one can break silently:
#   * the child is a `Watcher` — **no ScaryObject ancestor and no collider** — so the whole
#     rearrangement stays worth zero panic and the fridge remains the level's only new cost
#   * it appears exactly ONCE, however many times the stage is re-applied
#   * the music box's audio is a CHILD of the body, which is the only reason the sound moves
#     with it in stage 4
#   * the fridge hides its occupant until the door opens, charges on the REVEAL rather than
#     the press, and goes completely inert afterwards
#   * the drawer carries the KONTUR Gate 1 hint and archives it to the journal
#
#   Godot --headless --path game --script res://tests/check_house_guest.gd

const HALLWAY_SPOT := Vector3(0.0, 0.11, 7.4)
const CHILD_SPOT := Vector3(0.0, 0.0, 10.0)
const NEAR := 0.35

var _t := 0.0
var _stage := 0
var _fails: Array[String] = []
var _checks := 0
var _scene: Node = null
var _player: CharacterBody3D = null
var _box: Node3D = null
var _painting: Node3D = null
var _fridge: Node = null


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_2_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


# ⚠️ NEVER write `bool(node.get("some_flag"))` in a test.
#
# `Object.get()` returns null for a property that does not exist, and `bool(null)` is not a
# valid GDScript constructor — it throws. Thrown from inside `_process`, that aborts the
# frame BEFORE the stage counter advances, so the test re-runs the same stage forever: on
# 2026-07-29 this produced a run that emitted 21,265 assertion lines and hung for 28 minutes
# on a test whose own timeout is 30 seconds, because a flag had been renamed out from under
# it. These helpers turn a missing property into `false` instead of an exception.
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


func _process(delta: float) -> bool:
	_t += delta

	if _stage == 0 and _t > 1.2:
		_scene = current_scene
		_player = _scene.get_node_or_null("Player") as CharacterBody3D
		_box = _scene.get_node_or_null("MusicBox") as Node3D
		_painting = _scene.get("_bedroom_painting") as Node3D
		_ok("player found", _player != null)
		_ok("the music box exists as a real object", _box != null,
			"it used to be a bare looping sound with no body at all")
		_ok("the bedroom painting handle exists", _painting != null)
		_ok("the Landing mirror exists", _scene.get_node_or_null("LandingMirror") != null)
		_ok("the fridge exists", _scene.get_node_or_null("Fridge") != null)
		_ok("the kitchen drawer exists", _scene.get_node_or_null("KitchenDrawer") != null)
		if not (_player and _box and _painting):
			quit(1)
			return true

		_ok("the music box's loop is a CHILD of the body",
			_box.get_node_or_null("MusicBoxAudio") != null,
			"so moving the box moves the sound")
		# A chair with a back, not a cube — the playtest complaint.
		_ok("the kitchen chairs are built from parts, not one box",
			_scene.get_node_or_null("KitchenChair") != null
				and _scene.get_node_or_null("KitchenTable") != null)
		_ok("no figure anywhere before its stage", _count_class(_scene, "Watcher") == 0,
			"the cellar corner Watcher was removed 2026-07-29 — only the child remains")

		# --- stage 1: the painting goes down ------------------------------------------
		_scene.call("_force_guest_stages", 1)
		_stage = 1
		_t = 0.0

	elif _stage == 1 and _t > 0.5:
		# ⚠️ Position, not just height. The first version asserted only `y < 0.3`, and a
		# painting that had been teleported through the floor to the world origin passed it —
		# which is exactly what was happening. Assert it is on the floor AND still in the
		# Bedroom (centre x = -7, south wall z ≈ 9.6).
		var pp: Vector3 = _painting.position
		_ok("stage 1 lays the bedroom painting on the floor",
			pp.y > -0.1 and pp.y < 0.3, "y = %.2f" % pp.y)
		_ok("…and it is still IN the bedroom, not through the floor",
			absf(pp.x - (-7.0)) < 1.5 and pp.z > 9.0 and pp.z < 11.5,
			"at %s" % str(pp.snapped(Vector3.ONE * 0.01)))
		# ⚠️ FLAT, not merely low. MovedProp only rotated YAW until 2026-07-28, so the
		# painting dropped to floor height and stayed UPRIGHT — it read as a picture hung on
		# a very low wall, which is exactly what playtest reported. Laying it down is a PITCH.
		_ok("…and it is lying FLAT, not standing upright on the floor",
			absf(rad_to_deg(_painting.rotation.x)) > 60.0,
			"pitch %.1f degrees" % rad_to_deg(_painting.rotation.x))
		# ⚠️ And FACE-UP. A QuadMesh faces its own +Z; a +90° pitch turns that toward the
		# floor and backface culling makes the painting vanish (Issue 28) — which is exactly
		# what shipped. The picture must end up pointing at the ceiling, i.e. the rotated
		# +Z has a positive y component.
		var facing: Vector3 = _painting.global_transform.basis.z
		_ok("…and FACE-UP, not face-down into the floor", facing.y > 0.5,
			"quad normal y = %.2f" % facing.y)

		# --- THE CELLAR SEQUENCE ---------------------------------------------------------
		# Beat 1: the lights and the torch die the moment the player reaches the bottom of
		# the ramp. The figure does NOT appear yet — that gap is the whole point.
		_ok("the lights are on before the sequence", not _flag("_child_dark"))
		_player.global_position = Vector3(5.0, -1.4, -5.0)   # in the cellar
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

	elif _stage == 2 and _t > 6.2:      # CHILD_APPEAR_DELAY is 5.5
		# ⚠️ By NAME, not by class count. The cellar also contains the corner Watcher added in
		# the atmosphere pass, so counting Watchers here found two and told us nothing.
		var child := _scene.get_node_or_null("GuestChild") as Node3D
		_ok("the child appears after the delay", child != null)
		if child:
			_ok("it stands in front of the player",
				(child as Node3D).global_position.distance_to(_player.global_position) < 5.0,
				"%.1f m away" % (child as Node3D).global_position.distance_to(
					_player.global_position))
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
		_stage = 3
		_t = 0.0

	elif _stage == 3 and _t > 3.6:      # CHILD_HOLD is 3.0
		_ok("the lights come back afterwards", not _flag("_child_dark"))
		_ok("…and the torch is handed back", _player.is_flashlight_on())
		_ok("…and the dark-zone tax is un-suspended",
			not _flag_on(_player, "_smiler_active"))
		_ok("…and the figure is gone", _scene.get_node_or_null("GuestChild") == null)
		_ok("the whole sequence cost zero panic",
			_player.get_panic_ratio() < 0.05, "panic %.4f" % _player.get_panic_ratio())

		# --- stage 4 of the ladder: the music box ---------------------------------------
		_scene.call("_force_guest_stages", 4)
		_stage = 4
		_t = 0.0

	elif _stage == 4 and _t > 0.5:
		_ok("stage 4 puts the music box in the Hallway",
			_box.global_position.distance_to(HALLWAY_SPOT) < NEAR,
			"at %s" % str(_box.global_position.snapped(Vector3.ONE * 0.01)))
		var audio := _box.get_node_or_null("MusicBoxAudio") as AudioStreamPlayer3D
		_ok("and it is still playing when it gets there", audio != null and audio.playing)

		var snap: Dictionary = _scene.call("save_progress")
		_ok("save_progress records the Guest stage",
			int(snap.get("guest_stage", -1)) == 4, "guest_stage = %s" % snap.get("guest_stage"))

		# --- the fridge -------------------------------------------------------------------
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
		_stage = 5
		_t = 0.0

	elif _stage == 5 and _t > 0.8:
		# ⚠️ A WINDOW, not an exact figure. The panic now lands with the REVEAL
		# (REVEAL_DELAY 0.3 s) rather than on the press, and PANIC_DECAY_RATE is 3.5/s, so an
		# exact 10.00 is unobtainable once time has passed. Still tight enough to catch a
		# missing charge or a double charge.
		var after: float = _player.get_panic_ratio() * 50.0
		_ok("the reveal costs about 10 panic", after > 6.5 and after < 10.5, "%.2f" % after)
		_ok("the thing inside is now visible",
			bool((_fridge.get_node("FridgeThing") as Node3D).visible))

		var before2: float = _player.get_panic_ratio() * 50.0
		_fridge.call("interact")
		var after2: float = _player.get_panic_ratio() * 50.0
		_ok("a second press charges nothing — it is one-shot",
			absf(after2 - before2) < 0.01, "%.2f -> %.2f" % [before2, after2])

		var snap2: Dictionary = _scene.call("save_progress")
		_ok("save_progress records the open fridge", bool(snap2.get("fridge_open", false)))

		# --- the drawer's cross-level hint -------------------------------------------------
		var drawer := _scene.get_node_or_null("KitchenDrawer")
		if drawer:
			drawer.call("interact")
			var gs := root.get_node_or_null("/root/GameState")
			var archived := false
			for e in (gs.get("journal") as Array):
				if String(e["text"]).to_lower().contains("black door"):
					archived = true
			_ok("the drawer's KONTUR hint is archived to the journal", archived,
				"so TAB can re-read it two levels later")
			_ok("the drawer goes inert once read",
				bool(drawer.call("can_interact")) == false)
		_finish()
		return true

	if _t > 30.0:
		print("RESULT: FAIL — timed out at stage %d" % _stage)
		quit(1)
		return true
	return false


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
