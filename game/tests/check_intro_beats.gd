extends SceneTree

# The Intro Room's dread beats — and, above all, that it is still UNLOSEABLE.
#
# This room shipped with literally zero scares: no panic source, no RandomAmbient, no
# ApparitionDirector, no objective line — 60-120 s of nothing. "The ward is occupied"
# (2026-07-28) fills it with dread only, and the hard constraint agreed with the user is
# that **nothing here may ever raise panic**. That is what this test defends: it samples
# panic at every beat, including through the jolt, and fails if it moves at all.
#
# It also pins the beats themselves, because each one is a thing a future edit could
# silently delete without breaking anything else:
#   * two occupied gurneys, and NOT the one the player spawns on
#   * the first switch press glimpses the far end of the ward, and does not throw it
#   * the tube over the table stays dead, so the note is lit by the candle alone
#   * the breathing at the far wall is gone once the lights are on
#
# ⚠️ TIME-based, not frame-based. Headless runs uncapped so a frame count is not a clock;
# check_audio_buses.gd reported a false failure that way before it was fixed.
#
#   Godot --headless --path game --script res://tests/check_intro_beats.gd

const WAKE_WAIT := 3.0        # WAKEUP_TWEEN_TIME is 1.8 s, then the switch is spawned
const GLIMPSE_SAMPLE := 0.22  # inside the stuck press's 0.06 up + 0.4 hold
const REVEAL_WAIT := 1.4      # _flicker_on is 0.6 s; the breath fade is 0.5 s

var _t := 0.0
var _stage := 0
var _stage_at := 0.0
var _fails: Array[String] = []
var _checks := 0
var _scene: Node = null
var _player: CharacterBody3D = null
var _switch: Node = null
var _jolt_count := 0
var _peak_panic := 0.0


func _initialize() -> void:
	change_scene_to_file("res://scenes/intro_room.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _ceiling_lights() -> Array:
	var out: Array = []
	for c in _scene.get_children():
		# begins_with, not ==: the tubes are CeilingLight_0/1/2 (unique names, Issue 17).
		if c is OmniLight3D and String(c.name).begins_with("CeilingLight"):
			out.append(c)
	return out


func _sheets() -> Array:
	var out: Array = []
	for c in _scene.get_children():
		# The mound only, not the head box — "GurneySheet_" excludes "GurneySheetHead_".
		if String(c.name).begins_with("GurneySheet_"):
			out.append(c)
	return out


func _advance(next: int) -> void:
	_stage = next
	_stage_at = _t


func _process(delta: float) -> bool:
	_t += delta
	if _player:
		_peak_panic = maxf(_peak_panic, _player.get_panic_ratio())

	if _stage == 0:
		_scene = current_scene
		if _t < WAKE_WAIT:
			return false
		_player = _scene.get_node_or_null("Player") as CharacterBody3D
		_switch = _scene.get_node_or_null("LightSwitch")
		_ok("player found", _player != null)
		_ok("light switch spawned after the wake-up", _switch != null)
		if not (_player and _switch):
			quit(1)
			return true

		# --- the occupied ward -------------------------------------------------------
		var sheets := _sheets()
		_ok("two gurneys are occupied", sheets.size() == 2, "found %d" % sheets.size())
		# ⚠️ The player spawns lying on GURNEY_POS. A solid form on THAT bed would push
		# them out of the world, which is the class of bug check_spawn_blocked.gd exists
		# for — so assert the sheets keep well clear of it.
		var spawn_xz := Vector2(0.0, 7.0)   # intro_room.gd GURNEY_POS
		var nearest := 999.0
		for s in sheets:
			var p: Vector3 = (s as Node3D).position
			nearest = minf(nearest, Vector2(p.x, p.z).distance_to(spawn_xz))
		_ok("no sheeted form on the player's own gurney", nearest > 2.0,
			"nearest is %.2f m away" % nearest)

		_ok("the breathing at the far wall is playing",
			_scene.get_node_or_null("FarBreath") != null)
		var lights := _ceiling_lights()
		_ok("three ceiling tubes exist", lights.size() == 3, "found %d" % lights.size())
		var all_dark := true
		for l in lights:
			if (l as OmniLight3D).light_energy > 0.001:
				all_dark = false
		_ok("every tube is dark before the switch", all_dark)

		# --- the mid-fumble jolt (INTRO.md's specced-but-never-built beat) ------------
		var jolt := _scene.get_node_or_null("FumbleJolt") as Area3D
		_ok("the fumble jolt volume exists", jolt != null)
		if jolt:
			jolt.fired.connect(func() -> void: _jolt_count += 1)
			# Teleport into it rather than walking — Area3D detects on the physics step.
			_player.global_position = jolt.global_position + Vector3(0, -0.6, 0)
		_advance(1)

	elif _stage == 1 and _t - _stage_at > 0.8:
		_ok("the jolt fired exactly once", _jolt_count == 1, "fired %d" % _jolt_count)
		_ok("and it cost NO panic", is_zero_approx(_peak_panic),
			"peak %.3f" % _peak_panic)

		# --- the switch sticks --------------------------------------------------------
		_switch.call("interact")
		_advance(2)

	elif _stage == 2 and _t - _stage_at > GLIMPSE_SAMPLE:
		# One tube — the far one, furthest from the gurney — is briefly alight.
		var lit := 0
		var lit_z := 0.0
		for l in _ceiling_lights():
			if (l as OmniLight3D).light_energy > 0.05:
				lit += 1
				lit_z = (l as OmniLight3D).position.z
		_ok("the stuck press glimpses exactly one tube", lit == 1, "%d lit" % lit)
		# GURNEY_POS.z is +7, so the far end is negative z.
		_ok("and it is the FAR end of the ward", lit < 1 or lit_z < 0.0,
			"z = %.1f" % lit_z)
		_advance(3)

	elif _stage == 3 and _t - _stage_at > 0.9:
		# The glimpse must go away again — a stuck press that left the room dimly lit
		# would rob the real reveal of its contrast.
		var still_lit := 0
		for l in _ceiling_lights():
			if (l as OmniLight3D).light_energy > 0.001:
				still_lit += 1
		_ok("the glimpse fades back to full dark", still_lit == 0,
			"%d still lit" % still_lit)

		# --- the real reveal ----------------------------------------------------------
		_switch.call("interact")
		_advance(4)

	elif _stage == 4 and _t - _stage_at > REVEAL_WAIT:
		var dead := 0
		var alive := 0
		for l in _ceiling_lights():
			if (l as OmniLight3D).light_energy > 0.1:
				alive += 1
			else:
				dead += 1
		_ok("the reveal lights the ward", alive == 2, "%d alive" % alive)
		_ok("but the tube over the table stays dead", dead == 1, "%d dead" % dead)
		_ok("the breathing is gone once the lights are on",
			_scene.get_node_or_null("FarBreath") == null)

		# The whole point of the room.
		_ok("panic NEVER rose — the intro is still unloseable",
			is_zero_approx(_peak_panic), "peak %.4f of PANIC_MAX" % _peak_panic)

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
		return true

	if _t > 25.0:
		print("RESULT: FAIL — timed out at stage %d" % _stage)
		quit(1)
		return true
	return false
