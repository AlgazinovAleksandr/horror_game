extends SceneTree

# WHAT DOES SEARCHING THE FLOOD ACTUALLY COST? — a measurement instrument, not a guard.
#
#   Godot --headless --path game --script res://tests/probe_flood_search.gd
#
# ⚠️ DELIBERATELY NOT IN `tools/run_tests.sh`. It takes ~2 minutes of wall clock and it
# measures a DIFFICULTY QUESTION, which is the user's call and not a regression. It exists
# because THE DROWNED (2026-08-17) adds six optional detours to a zone whose panic economy is
# a flat drip with no decay, and "how much of the bar does a completionist spend" is the one
# number nobody could answer by reading the constants.
#
# It drives the REAL player through `player.gd`'s `ai_*` surface — gravity, collision,
# `move_and_slide`, the wade slow, the interact RAYCAST and the panic system are all the
# shipping path. Two runs, back to back, from the same entry state:
#
#   A  BEELINE     spawn -> Descent -> Basin -> WestRun -> the Sump seam. What the level cost
#                  before this feature existed, and what it still costs a player who ignores it.
#   B  FULL SEARCH the same destination, detouring through all six objects and searching each.
#
# ⚠️ THE TWO APPARITIONS ARE DISARMED. They are pre-existing content on this route (Throat and
# Sump), their rule is "hold still ~4 s", and an automated walker that keeps walking reads as
# FLEEING and dies. Add ~4-5 s of standing still per encounter to run B's figure; both are
# zero-panic if obeyed. The Cistern beartrap is not on either route.
#
# ⚠️ READING IS FREE and is not in these numbers. `NoteUI` pauses the tree, so the zone's
# `_process` — and therefore `DREAD_DRIP` — does not tick behind a page. The probe closes each
# page on the frame it opens; a human reading six short pages adds wall clock and zero panic.

const SCENE := "res://scenes/backrooms.tscn"
const ORIGIN := Vector3(-200, 0, 0)
const EYE := 0.1

# zone-local (x, z). "go" walks there; "search" presses E on the named object.
# ⚠️ EVERY ROUTE STEERS AROUND THE `DryPlatform`. It is a 3.4 x 3.4 m slab standing 0.44 m
# proud of the Basin floor (x -1.7..1.7, z 13.3..16.7) and `move_and_slide` cannot step up
# 0.44 m — a walker aimed straight through the middle of the Basin stops dead against it. It
# is also the zone's only `CalmZone`, so a route that clips it RECOVERS panic; both routes
# below pass near it, which is realistic and is called out in the report.
const ROUTE_BEELINE := [
	[0, 4], [0, 10], [0, 12.3], [-3, 13], [-4.5, 15], [-6.5, 15], [-9, 15],
	[-10, 18], [-10, 22.5],
]
# ⚠️ A "go" waypoint is a STANDING SPOT BESIDE the object, never the object's own position:
# these are solid bodies, so a waypoint inside one can never be arrived at and the leg times
# out. That is how the first version of this probe spent 127 s failing to reach three things
# that a human reaches in two steps.
const ROUTE_SEARCH := [
	[-0.55, 0.3], "Drowned_Landing",
	[0, 4], [0.7, 7.0], "Drowned_Descent",
	[0, 10], [0, 12.3], [2.5, 12.8], [3.4, 15.2], "Drowned_Basin",
	[5, 15], [7, 15], [8.2, 15.0], "Drowned_EastRun",
	[7, 15], [3, 12.6], [-2.6, 12.6], [-2.6, 17.5], [0, 18], [0, 20],
	[-0.3, 24.6], "Drowned_Throat",
	[0, 20], [0, 18], [-2.6, 17.5], [-4.5, 15], [-7, 15], [-8.0, 15.1], "Drowned_WestRun",
	[-9, 15], [-10, 18], [-10, 22.5],
]

var _t := 0.0
var _phase := 0
var _scene: Node
var _player: CharacterBody3D
var _zone: Node
var _auto: AutoPlayer
var _route: Array = []
var _leg := 0
var _run_start := 0.0
var _panic_at_start := 0.0
var _walked := 0.0
var _last_pos := Vector3.ZERO
var _report_lines: Array[String] = []
var _leg_at := 0.0
var _calm_s := 0.0
var _wet_s := 0.0



const LEG_TIMEOUT := 20.0


func _initialize() -> void:
	change_scene_to_file(SCENE)


func _process(delta: float) -> bool:
	_t += delta
	if _phase > 0 and (not is_instance_valid(_scene) or not is_instance_valid(_player)):
		print("ABORTED — the level reloaded (a death) at t=%.1f s" % _t)
		quit(1)
		return true

	match _phase:
		0:
			if _t < 1.0:
				return false
			_setup()
		1, 3:
			_drive(delta)
		2:
			# Reset for run B: back to the entry state, panic capped exactly as the level
			# caps it on arrival, and the wing untouched.
			_scene.call("_enter_zone", 3)
			_begin("B  FULL SEARCH  (all six objects)", ROUTE_SEARCH, 3)
		4:
			return _finish()

	if _t > 300.0:
		print("ABORTED — timed out")
		quit(1)
		return true
	return false


func _setup() -> void:
	_scene = current_scene
	_player = _scene.get_node_or_null("Player") as CharacterBody3D
	_zone = _scene.get_node_or_null("ZoneFlood")
	if _player == null or _zone == null:
		print("ABORTED — no Player / ZoneFlood")
		quit(1)
		return
	var appar: GDScript = load("res://scripts/apparition.gd")
	for n in _all(_zone, []):
		if n.get_script() == appar or String(n.name).ends_with("Event"):
			n.queue_free()
	_auto = AutoPlayer.new(_player)
	_scene.call("_enter_zone", 3)
	_begin("A  BEELINE  (no searching — the pre-2026-08-17 cost)", ROUTE_BEELINE, 1)


func _begin(label: String, route: Array, next: int) -> void:
	print("")
	print("=== RUN %s" % label)
	_player.global_position = _zone.get("spawn_point")
	_player.velocity = Vector3.ZERO
	# Both runs start from the SAME realistic entry state: `backrooms.gd:ZONE_ENTRY_PANIC_CAP`
	# is 25 % of PANIC_MAX, i.e. the worst the level lets you arrive at.
	_player.call("set_panic_ratio", 0.25)
	_route = route
	_leg = 0
	_walked = 0.0
	_calm_s = 0.0
	_wet_s = 0.0
	_last_pos = _player.global_position
	_run_start = _t
	_leg_at = _t
	_panic_at_start = float(_player.call("get_panic_ratio")) * 50.0
	_phase = next


func _drive(_delta: float) -> void:
	# Dismiss any page the moment it opens: reading is free and this probe measures walking.
	var ui := root.get_node_or_null("/root/NoteUI")
	if ui != null and bool(ui.get("is_open")):
		ui.call("_close")

	_walked += Vector2(_player.global_position.x - _last_pos.x,
		_player.global_position.z - _last_pos.z).length()
	_last_pos = _player.global_position
	var loc := Vector2(_player.global_position.x - ORIGIN.x, _player.global_position.z)
	# ⚠️ ASK THE PLAYER, do not re-derive the box. `CalmZone` fires on `body_entered`, i.e. on
	# the CAPSULE overlapping the Area3D — so the effective region is the 4.5 m box grown by
	# the capsule's 0.40 m radius, and a probe that tests the player's ORIGIN against the
	# nominal box under-reports by roughly a third. This reads `player.gd`'s own counter, the
	# same number `_update_panic()` acts on.
	if int(_player.get("_calm_zones")) > 0:
		_calm_s += _delta
	if loc.y > -4.0 and loc.y < 30.0 and absf(loc.x) < 20.0:
		_wet_s += _delta

	if _leg >= _route.size():
		_end_run()
		return
	var step = _route[_leg]
	if step is String:
		var item := _named(String(step))
		if item == null:
			print("  !! %s not found" % step)
			_leg += 1
			_leg_at = _t
			return
		# ⚠️ REFRESH THE PROMPT BEFORE PRESSING E. `_try_interact()` acts on `_interact_target`,
		# which `_update_interact_prompt()` sets — and that runs in the player's own `_process`,
		# i.e. with LAST frame's heading. Turning and pressing in the same frame presses at
		# whatever the walker was looking at while it was still walking, which is nothing.
		# `ai_interact_target()` is the shipping refresh; this is not a shortcut past it.
		_player.call("ai_look_at", item.global_position + Vector3(0, 0.45, 0))
		var cam := _player.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.force_update_transform()
		_player.call("ai_interact_target")
		_player.call("ai_interact")
		var done: bool = bool(item.get("is_searched"))
		print("  searched %-18s at t+%5.1f s   panic %5.1f / 50   %s"
			% [step, _t - _run_start, float(_player.call("get_panic_ratio")) * 50.0,
			"OK" if done else "NO PROMPT — the walker could not reach it"])
		_leg += 1
		_leg_at = _t
		return

	var target := ORIGIN + Vector3(float(step[0]), EYE, float(step[1]))
	if _auto.step_toward(target):
		_leg += 1
		_leg_at = _t
		return
	# ⚠️ TIME, NOT FRAMES. `AutoPlayer.stuck` counts frames in which the body moved less than
	# 5 cm, which at the ~145 fps a headless run reaches is EVERY frame at walking pace — it
	# reads `true` for the whole of a perfectly healthy walk. Measured, and filed. This probe
	# uses its own wall-clock leg timeout instead and never consults that flag.
	if _t - _leg_at > LEG_TIMEOUT:
		print("  !! leg %d (%.1f, %.1f) timed out after %.0f s — skipping"
			% [_leg, float(step[0]), float(step[1]), LEG_TIMEOUT])
		_leg += 1
		_leg_at = _t


func _end_run() -> void:
	var secs := _t - _run_start
	var panic := float(_player.call("get_panic_ratio")) * 50.0
	var line := ("  -> %5.1f s   %5.1f m walked   panic %.1f -> %.1f of 50  (%+.1f, %+.0f%% of "
		+ "the bar)\n     %.1f s wading, of which %.1f s (%.0f%%) inside the Basin CalmZone") \
		% [secs, _walked, _panic_at_start, panic, panic - _panic_at_start,
		(panic - _panic_at_start) / 50.0 * 100.0, _wet_s, _calm_s,
		(_calm_s / maxf(0.1, _wet_s)) * 100.0]
	print(line)
	_report_lines.append(line)
	_phase += 1


func _finish() -> bool:
	_auto.release()
	print("")
	print("--------------------------------------------------")
	print("THE FLOOD — measured cost of a search")
	for l in _report_lines:
		print(l)
	print("  reference: DREAD_DRIP is 0.3/s while wading, the DreadZone cancels decay")
	print("             exactly, the entry cap is 25% of PANIC_MAX (12.5), and the Basin's")
	print("             DryPlatform CalmZone nets about -2.7/s standing in it.")
	print("  worst case: a search route that never touched the anchor would cost")
	print("             %.1f s x 0.3 = +%.1f of the 37.5 points left after the entry cap."
		% [_wet_s, _wet_s * 0.3])
	print("--------------------------------------------------")
	quit(0)
	return true


func _all(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children():
		_all(c, out)
	return out


func _named(nm: String) -> Node3D:
	for n in _all(_zone, []):
		if String(n.name) == nm and n is Node3D:
			return n as Node3D
	return null
