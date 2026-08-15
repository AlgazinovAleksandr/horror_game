extends SceneTree

# The Corridor's ending is three constants that must stay in formation:
#
#   NOCLIP_ONSET_BEFORE_END   where the torches die and the flashlight is force-killed
#   NOCLIP_FALL_BEFORE_DOOR   how far short of room 217 the floor gives way
#   RETURN_MARGIN             how far back a player returning from the Backrooms lands
#
#   Godot --headless --path game --script res://tests/check_noclip_fall.gd
#
# Why this exists. They were tuned independently and nothing connected them. Moving the
# fall 5 m earlier (2026-08-15) pushed the blackout's useful run-up from ~7 m down to ~4,
# and moving the blackout to compensate put it PAST the re-entry cap — which would have
# respawned a player walking back from the Backrooms inside the blackout trigger, killing
# their flashlight on arrival, or inside the fall, bouncing them straight back to the
# level they had just left. Both are silent: the level loads, looks correct, and does the
# wrong thing one frame later.
#
# So this asserts the RELATIONSHIPS, not the numbers. Retuning any one of the three is
# fine; retuning one without the others is what this catches.

const SCENE := "res://scenes/corridor.tscn"
const MIN_DARK_RUNUP := 6.0    # metres of blind walking the beat needs to read at all
const MIN_RESPAWN_GAP := 1.5   # metres of clearance from the nearest trigger box face

var _t := 0.0
var _fails: Array[String] = []
var _checks := 0
var _stage := 0
var _player: CharacterBody3D
var _fall_y0: float = 0.0


func _initialize() -> void:
	change_scene_to_file(SCENE)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print("  %s  %s%s" % ["OK  " if cond else "FAIL", label, ("  " + detail) if detail else ""])
	if not cond:
		_fails.append(label)


func _process(delta: float) -> bool:
	_t += delta
	if _stage == 1:
		return _tick_fall_check()
	if _t < 1.0:
		return false
	var scene := current_scene
	if scene == null:
		print("FAIL: no scene")
		quit(1)
		return true

	var s: GDScript = scene.get_script()
	var total: float = float(scene.get("_total_len"))
	var fall: float = float(scene.call("noclip_fall_distance"))
	var depth: float = float(s.get("NOCLIP_TRIGGER_DEPTH"))
	var onset: float = total - float(s.get("NOCLIP_ONSET_BEFORE_END"))
	var margin: float = float(s.get("RETURN_MARGIN"))
	var respawn: float = total - margin
	var door_d: float = total - 0.08

	_ok("the corridor is its documented length", absf(total - 320.0) < 0.01, "%.1f m" % total)

	# 1. The fall lands where the user asked: its NEAR face 5 m from the door.
	var near_face: float = fall - depth / 2.0
	var gap_to_door: float = door_d - near_face
	_ok("the floor gives way ~5 m short of the door",
		absf(gap_to_door - float(s.get("NOCLIP_FALL_BEFORE_DOOR"))) < 0.01,
		"%.2f m from the door plane" % gap_to_door)

	# 2. And the player genuinely cannot reach the door: even the far face of the trigger
	#    is short of it, so there is no way to walk past the volume and touch room 217.
	_ok("room 217 stays unreachable", fall + depth / 2.0 < door_d,
		"trigger ends at %.2f, door at %.2f" % [fall + depth / 2.0, door_d])

	# 3. The blackout precedes the fall by enough to be a beat rather than a flicker.
	var runup: float = near_face - onset
	_ok("the blackout leads the fall by a real distance", runup >= MIN_DARK_RUNUP,
		"%.1f m of blind walking (min %.1f)" % [runup, MIN_DARK_RUNUP])
	_ok("the blackout comes first", onset < near_face)

	# 4. ⚠️ The one that actually bit: re-entry must clear BOTH trigger boxes. _spawn_event
	#    builds a 2.0-deep box, so the onset's near face is 1.0 back from its centre.
	_ok("re-entry lands clear of the blackout", onset - 1.0 - respawn >= MIN_RESPAWN_GAP,
		"respawn %.1f, blackout box starts %.1f" % [respawn, onset - 1.0])
	_ok("re-entry lands clear of the fall", near_face - respawn >= MIN_RESPAWN_GAP,
		"respawn %.1f, fall box starts %.1f" % [respawn, near_face])
	_ok("re-entry is still deep in the level", respawn > total * 0.85,
		"%.1f m of %.1f" % [respawn, total])

	# 5. The exit door wears the new art, at the artwork's own aspect.
	var door: Node = scene.get_node_or_null("ExitDoor")
	_ok("the exit door exists", door != null)
	if door != null:
		var quad: MeshInstance3D = door.get_node_or_null("DoorMesh")
		_ok("it has a door mesh", quad != null)
		if quad != null:
			var mat: StandardMaterial3D = quad.get_surface_override_material(0)
			var tex_name := ""
			if mat and mat.albedo_texture:
				tex_name = mat.albedo_texture.resource_path.get_file()
			_ok("it wears the torn-door art", tex_name == "backrooms_tear_door.png", tex_name)
			# ⚠️ THE ASSERTIONS THAT WERE MISSING. The line above passed while the door
			# rendered as a flat red panel, because a texture being ASSIGNED says nothing
			# about it being VISIBLE.
			#
			# Two separate requirements, and the door has to meet both:
			#
			#  (a) SELF-LIT. The blackout force-kills the flashlight 10 m before this door
			#      and every torch is out, so a surface that relies on scene lighting is a
			#      black rectangle. Unshaded satisfies this; so does real emission.
			#  (b) NOT WASHED. A flat, UNTEXTURED emission is a coloured sheet painted over
			#      the picture — that is exactly what shipped (0.35 red at energy 0.6) and
			#      what the user reported as "the door still looks just red".
			if mat != null:
				var unshaded: bool = mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
				var lit_emission: bool = mat.emission_enabled \
					and mat.emission_texture != null and mat.emission_energy_multiplier > 0.0
				_ok("the door lights itself in the blackout", unshaded or lit_emission,
					"unshaded=%s emissive=%s" % [unshaded, lit_emission])
				var flat_wash: bool = mat.emission_enabled and mat.emission_texture == null \
					and mat.emission_energy_multiplier > 0.05
				_ok("and nothing is washed flat over the art", not flat_wash,
					"untextured emission at %.2f" % mat.emission_energy_multiplier)
			if mat and mat.albedo_texture:
				var t: Texture2D = mat.albedo_texture
				var art := float(t.get_height()) / float(t.get_width())
				var qm: QuadMesh = quad.mesh
				var quad_aspect: float = qm.size.y / qm.size.x
				# A texture squashed onto a mismatched quad is SCARY.md §7.1(4).
				_ok("the quad matches the artwork's aspect", absf(art - quad_aspect) < 0.05,
					"art 1:%.3f vs quad 1:%.3f" % [art, quad_aspect])

	# ⭐ AND IT IS A REAL FALL. Everything above is geometry; this is the only check that
	# asks what the PLAYER experiences. The first version of this ending faded to black and
	# waited two seconds with the player standing still — every distance assertion above
	# passed against it, because not one of them asked whether anything moved.
	_player = scene.get_node_or_null("Player") as CharacterBody3D
	_ok("the player exists", _player != null)
	if _player == null:
		return _report()
	# Stand on the fall trigger and let the level's own event fire.
	var pt: Dictionary = scene.call("_path_point", scene.call("noclip_fall_distance"))
	_player.global_position = pt["pos"] + Vector3(0, 0.1, 0)
	_player.force_update_transform()
	scene.set("_noclip_armed", true)     # the blackout normally arms this 10 m earlier
	scene.call("_ev_noclip_fall")
	_fall_y0 = _player.global_position.y
	_stage = 1
	_t = 0.0
	return false


func _tick_fall_check() -> bool:
	if not is_instance_valid(_player) or current_scene == null:
		# advance_level() already fired — that only happens well below the floor.
		_ok("the fall carries the player through the floor", true, "level advanced")
		return _report()
	var dropped: float = _fall_y0 - _player.global_position.y
	if _t < 1.2:
		return false
	# 1.2 s of real gravity is ~7 m; anything under a metre means they are still standing.
	_ok("the fall carries the player through the floor", dropped > 1.0,
		"dropped %.2f m in %.1f s" % [dropped, _t])
	_ok("and they are below the corridor floor", _player.global_position.y < -0.5,
		"y = %.2f" % _player.global_position.y)
	return _report()




func _report() -> bool:
	print("  %d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL — ", ", ".join(_fails))
		quit(1)
	return true
