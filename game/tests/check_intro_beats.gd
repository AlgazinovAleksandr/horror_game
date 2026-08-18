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
#   * the first switch press glimpses a tube that actually reaches an occupied bed
#   * the tube over the table stays dead, AND THE CANDLE IS LIT, so the note is lit by the
#     candle alone — ⚠️ this used to assert only the dead tube, i.e. only the absence half
#     of its own sentence, and the candle was in fact invisible and emitting nothing for the
#     entire life of the procedurally-rebuilt room (2026-08-16)
#   * one of the two covered beds is EMPTY once the lights are on
#   * the wheelchair turns from the line the player actually walks, with margin
#   * the breathing is gone once the lights are on
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
var _peak_panic := 0.0
var _wc: Node3D = null
var _wc_yaw := 0.0


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
		# One node per covered body: the form is built from parts under a single Node3D
		# (see intro_room.gd:_build_sheeted_form), so this counts BODIES, not boxes.
		if String(c.name).begins_with("SheetedForm_"):
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

		# --- NO jumpscare in this room ------------------------------------------------
		# The user cut the mid-fumble nightmare flash on the first playtest (2026-07-28).
		# Asserted as an absence so it cannot quietly come back: the cold open already
		# spends that image, and this is the one room with no fail state.
		_ok("there is NO jumpscare volume in the intro",
			_scene.get_node_or_null("FumbleJolt") == null)
		_advance(1)

	elif _stage == 1 and _t - _stage_at > 0.8:
		_ok("nothing has cost panic so far", is_zero_approx(_peak_panic),
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
		# ⚠️ REPLACES "and it is the FAR end of the ward" (2026-08-16). That assertion was
		# true and useless: the far tube is at z=-6 with omni_range 9, and both occupied
		# beds sat at z=+5..+6, eleven metres away — so the best beat in the room lit bare
		# floor and could not show a single covered body. What matters is not WHICH tube it
		# is, it is whether the flash reaches something worth seeing.
		var reach := 0.0
		var nearest_bed := 999.0
		for l in _ceiling_lights():
			if (l as OmniLight3D).light_energy > 0.05:
				reach = (l as OmniLight3D).omni_range
				for s in _sheets():
					nearest_bed = minf(nearest_bed,
						(s as Node3D).global_position.distance_to((l as OmniLight3D).global_position))
		_ok("and its light actually reaches an occupied bed", nearest_bed < reach,
			"nearest covered body is %.2f m from the lit tube (z=%.1f), range %.1f"
				% [nearest_bed, lit_z, reach])
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

		# --- the candle, i.e. the OTHER half of "lit by the candle alone" ----------------
		# ⚠️ `visible` is the assertion that matters. _darken_scene() hides this light for
		# the blind fumble; nothing restored it, so it tweened up to a perfectly good
		# energy on a hidden node — and a hidden Node3D light emits NOTHING. Measured
		# 2026-08-16: visible=false, energy=1.972. With the tube above the table
		# deliberately dead, the note the player is REQUIRED to read had no light on it.
		var candle: OmniLight3D = _scene.get("candle_light")
		_ok("the candle light exists", candle != null)
		if candle:
			_ok("the candle is VISIBLE after the reveal", candle.visible,
				"visible=%s" % candle.visible)
			_ok("…and is actually burning", candle.light_energy > 1.0,
				"energy %.3f" % candle.light_energy)
			# A light with no emitter is the other half of the same bug: this room had a
			# CandleLight and no candle at all, hanging 2.2 m above the table.
			var nearest_mesh := 999.0
			var who := "-"
			for c in _scene.get_children():
				if not (c is MeshInstance3D or c is CSGShape3D):
					continue
				var d: float = (c as Node3D).global_position.distance_to(candle.global_position)
				if d < nearest_mesh:
					nearest_mesh = d
					who = String(c.name)
			_ok("…and there is a real candle under it, not a bare light",
				nearest_mesh < 0.35, "nearest prop is %s at %.3f m" % [who, nearest_mesh])

		# --- one bed is empty afterwards (B2) --------------------------------------------
		# No sound, no panic, no camera move: only the count changes.
		_ok("one of the two covered beds is empty once the lights are on",
			_sheets().size() == 1, "%d covered bodies remain" % _sheets().size())

		# --- the wheelchair turns WHILE WATCHED (playtest 2026-07-28) -----------------
		# The inverse of MovedProp's rule, deliberately: the player must be close AND
		# looking, so the turn cannot be missed. Arm it, then stand in front of it.
		var wc := _scene.get_node_or_null("Wheelchair") as Node3D
		_ok("the wheelchair exists", wc != null)
		if wc:
			_wc = wc
			_wc_yaw = wc.rotation.y
			_scene.call("_arm_wheelchair")
			# Stand well back and look away: it must NOT turn yet.
			_player.global_position = wc.global_position + Vector3(0, 0.1, 8.0)
			var cam2 := _player.get_node("Camera3D") as Camera3D
			cam2.rotation.y = 0.0
			_advance(5)
			return false

		_finish()
		return true

	elif _stage == 5 and _t - _stage_at > 0.8:
		_ok("the wheelchair does not turn from across the room",
			is_equal_approx(_wc.rotation.y, _wc_yaw),
			"yaw %.3f" % _wc.rotation.y)

		# --- is the chair within reach of the route the player actually walks? ------------
		# The note is on the table at x=0 and the exit door is at x=0, so the walk from
		# reading the note to leaving runs along x=0. The chair's LATERAL offset from that
		# line is the closest the player ever gets to it without deliberately detouring.
		# ⚠️ Margin, not a knife-edge: the chair used to sit at x=3.0 against a limit of
		# 3.2, which is 0.2 m — and because the distance test was full-3D at the time, the
		# real allowance was 2.741 m of floor and the beat could not fire AT ALL.
		var limit: float = _scene.get_script().get("WHEELCHAIR_TURN_DIST")
		var lateral: float = absf(_wc.global_position.x)
		_ok("the wheelchair is within reach of the note-to-door line, with margin",
			lateral <= limit - 0.5,
			"lateral %.2f m vs limit %.2f (was 3.00)" % [lateral, limit])

		# --- and it fires at the full horizontal reach ------------------------------------
		# ⚠️ Deliberately probed at 3.0 m, NOT at the chair's own 2.4 m. 3.0 m is what the
		# old placement offered, and it is the distance that separates a horizontal test
		# from a 3D one: with the camera 1.65 m up, sqrt(3.0^2 + 1.65^2) = 3.42 > 3.2, so a
		# distance test that mixes in the vertical component fails this and only this.
		_player.global_position = _wc.global_position + Vector3(0, 0.1, 3.0)
		var cam3 := _player.get_node("Camera3D") as Camera3D
		cam3.look_at(_wc.global_position + Vector3(0, 0.5, 0), Vector3.UP)
		_advance(6)

	elif _stage == 6 and _t - _stage_at > 0.6:
		# --- the turn has a SOUND, and it is the purpose-made one ------------------------
		# ⚠️ Sampled at +0.6 s, not with the rotation at +1.8 s: the emitter fades out over
		# WHEELCHAIR_SFX_FADE_START + FADE_TIME (1.6 s) and frees itself, so a later check
		# would find nothing and could not tell "played and finished" from "never played".
		# ⚠️ The FILE is asserted, not just that something plays. `wheelchair_turn` never
		# existed and this beat fell back to `gurney_creak` for the life of the feature —
		# a fallback that works is exactly the kind of thing that hides a missing asset.
		var sfx := _scene.get_node_or_null("WheelchairTurnSfx") as AudioStreamPlayer3D
		_ok("the wheelchair turn plays a sound", sfx != null)
		if sfx:
			var src := "" if sfx.stream == null else sfx.stream.resource_path
			_ok("…and it is the purpose-made wheelchair sample, not the creak fallback",
				src.get_file().get_basename() == "wheelchair", "stream: %s" % src)
			_ok("…at the gain measured from the file, not a plausible number",
				is_equal_approx(sfx.volume_db, -7.6), "volume_db %.2f" % sfx.volume_db)
		_advance(7)

	elif _stage == 7 and _t - _stage_at > 1.4:
		_ok("it DOES turn at the full horizontal reach (3.0 m of floor, eye 1.65 m up)",
			absf(_wc.rotation.y - _wc_yaw) > deg_to_rad(25.0),
			"turned %.1f degrees" % rad_to_deg(_wc.rotation.y - _wc_yaw))
		_ok("…and the whole wheelchair beat still cost ZERO panic",
			is_zero_approx(_peak_panic), "peak %.4f" % _peak_panic)
		_finish()
		return true

	if _t > 25.0:
		print("RESULT: FAIL — timed out at stage %d" % _stage)
		quit(1)
		return true
	return false


func _finish() -> void:
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
