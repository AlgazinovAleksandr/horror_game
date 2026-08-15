extends SceneTree

# Caught in a beartrap, are you actually STUCK?
#
#   Godot --headless --path game --script res://tests/check_beartrap_hold.gd
#
# User report, 2026-08-15: "when the player is stuck in the beartrap, the player still can
# move. It should not be that way — when you are stuck you are actually stuck until you
# escape."
#
# They were exactly right, and the code had it written down as intentional. `beartrap.gd`
# only ever called `apply_slow()` — SLOW_MULTIPLIER 0.45 — so "trapped" was a speed
# penalty. You could walk out of a closed trap, sprint even (0.45 x 1.6), while the UI
# read "TRAPPED — PRESS [E] TO ESCAPE", and `_escape_fail()` would still land its 40 panic
# on you from the far side of the level. Two ⚠️ DELIBERATE comments defended it.
#
# What this asserts, and why each one:
#   * movement is genuinely zero while caught — the report itself
#   * LOOK still works — the user chose tense over blinding, so a regression that freezes
#     the camera too would be just as wrong as the original bug
#   * the pin lifts on BOTH exits, success and timeout — a QTE that leaks its lock leaves
#     the player unable to move for the rest of the level, which is unrecoverable
#
# ⚠️ Drives the trap through `_on_body_entered`, the real trigger, rather than calling the
# escape internals — the same reason autoplayer.gd exists.

var _t := 0.0
var _stage := 0
var _fails: Array[String] = []
var _checks := 0
var _player: CharacterBody3D
var _trap: Node3D
var _scene: Node
var _caught_at: Vector3
var _speed_at_snap: float = 0.0


func _initialize() -> void:
	change_scene_to_file("res://scenes/corridor.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print("  %s  %s%s" % ["OK  " if cond else "FAIL", label, ("  " + detail) if detail else ""])
	if not cond:
		_fails.append(label)


func _process(delta: float) -> bool:
	_t += delta
	match _stage:
		0:
			if _t < 1.0:
				return false
			_scene = current_scene
			_player = _scene.get_node_or_null("Player") as CharacterBody3D
			_trap = _find_trap(_scene)
			_ok("the player exists", _player != null)
			_ok("the Corridor has a beartrap", _trap != null)
			if _player == null or _trap == null:
				return _report()
			# ⚠️ WALK IN. DO NOT TELEPORT. The previous version of this test dropped the
			# player onto the trap and then called `_on_body_entered` by hand — which meant
			# their velocity was ZERO at the moment of the snap, and the bug is entirely
			# about velocity that survives the snap. It passed against a build where a
			# walking player slid straight out of a closed trap.
			#
			# Stand back down the corridor's own centreline, face the trap, and let the
			# Area3D's real `body_entered` fire.
			var d: float = _scene.call("_nearest_path_distance", _trap.global_position)
			var back: Dictionary = _scene.call("_path_point", maxf(1.0, d - 2.5))
			_player.global_position = back["pos"] + Vector3(0, 0.1, 0)
			_player.force_update_transform()
			_player.set("ai_active", true)
			_player.call("ai_look_at", _trap.global_position)
			_player.set("ai_move_dir", Vector2(0, -1))
			_player.set("ai_sprint", true)
			_stage = 1
			_t = 0.0

		1:
			# Keep walking until the trap springs on its own.
			if not bool(_trap.get("_sprung")):
				if _t > 6.0:
					_ok("the player reached the trap by walking", false, "never sprang")
					return _report()
				_speed_at_snap = Vector2(_player.velocity.x, _player.velocity.z).length()
				return false
			_ok("the player reached the trap by walking", true)
			# The whole point: they were MOVING when it closed.
			_ok("and they were moving when it closed", _speed_at_snap > 1.0,
				"%.2f m/s the frame before" % _speed_at_snap)
			_ok("the trap sprang", bool(_trap.get("_sprung")))
			_ok("the escape QTE is running", bool(_trap.get("_escaping")))
			_ok("the player is marked busy", bool(_player.call("is_input_frozen")))
			_caught_at = _player.global_position
			# Still holding the key down, still sprinting, still trying to walk out.
			_stage = 2
			_t = 0.0

		2:
			if _t < 1.5:
				return false
			var moved: float = _player.global_position.distance_to(_caught_at)
			# A hair of settling under gravity is fine; a step is not. Unpinned and
			# sprinting, 1.5 s would carry the player ~9.6 m.
			_ok("a trapped player cannot walk away", moved < 0.25, "moved %.2f m in 1.5 s" % moved)

			# Look must still work, or the fix has overshot into freeze_input().
			var before: float = _player.rotation.y
			var ev := InputEventMouseMotion.new()
			ev.relative = Vector2(120, 0)
			_player.call("_unhandled_input", ev)
			_ok("but they can still turn to look", absf(_player.rotation.y - before) > 0.01,
				"yaw moved %.3f rad" % absf(_player.rotation.y - before))

			# Escaping releases the pin.
			_trap.call("_escape_success")
			_stage = 3
			_t = 0.0

		3:
			if _t < 0.1:
				return false
			_ok("escaping releases the pin", not bool(_player.call("is_input_frozen")))
			# ⚠️ Measure the "can move again" half from a KNOWN-OPEN spot, not from the
			# trap. The traps sit in the corridor's dark stretch, where the zigzag means
			# the spawn facing can point straight into a wall — the first version of this
			# test read 0.03 m and blamed the pin when the player was simply walking into
			# masonry. The corridor's own spawn faces +z down a 50 m straight.
			_player.global_position = Vector3(0, 0.1, 2.0)
			_player.rotation.y = 0.0
			_player.force_update_transform()
			_stage = 4
			_t = 0.0
			_caught_at = _player.global_position

		4:
			if _t < 0.8:
				return false
			var moved_after: float = _player.global_position.distance_to(_caught_at)
			_ok("and then they can move again", moved_after > 0.5,
				"moved %.2f m in 0.8 s" % moved_after)

			# ⚠️ The other exit. A timeout must release the pin too, and it must do so even
			# though it also fires 40 panic — if the ordering ever leaves _qte_active set,
			# the player is frozen for the rest of the level with no way to clear it.
			var trap2 := _find_trap(current_scene, _trap)
			if trap2 != null:
				_player.global_position = trap2.global_position + Vector3(0, 0.1, 0)
				trap2.call("_on_body_entered", _player)
				trap2.call("_escape_fail")
				_ok("a TIMEOUT also releases the pin", not bool(_player.call("is_input_frozen")))
			else:
				_ok("a second trap exists to test the timeout path", false)
			return _report()
	return false


func _find_trap(n: Node, skip: Node = null) -> Node3D:
	# Duck-typed: a class_name in a SceneTree script compiles before the autoloads exist.
	if n != skip and n is Node3D and n.has_method("_on_body_entered") \
			and n.get("_escaping") != null:
		return n
	for c in n.get_children():
		var f := _find_trap(c, skip)
		if f != null:
			return f
	return null


func _report() -> bool:
	print("  %d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL — ", ", ".join(_fails))
		quit(1)
	return true
