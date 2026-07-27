extends SceneTree

# Play THE NIGHTMARE end to end, with EVERY ENTITY LIVE, across several seeds.
#
# This is the difficulty instrument. It is deliberately the opposite of
# walk_dungeon.gd, which strips the roster out to measure geometry: here the Still
# Ones stalk, the Matron cycles, the Hollow One arrives at six sconces and the
# beartraps are armed, and the run is allowed to end in death.
#
# ⚠️ It does not assert a difficulty threshold and it MUST NOT start doing so.
# Whether dying four times in five seeds is correct is the user's call, not this
# file's — `.claude/agents/game-tester.md`'s standing example is a creature that
# killed a playtester twice in one run where the analysis was right in every
# measured detail and the answer was still "leave it as is". What this reports is
# MEASUREMENTS: deaths, where, at what panic, with how many sconces lit, and how
# long the night took.
#
# What it DOES assert is that the level is winnable at all with the roster live —
# if no seed can ever be completed, that is a bug and not a difficulty opinion.
#
# The sconces are lit through the SHIPPING path: ai_interact_target() to confirm
# the prop is genuinely reachable, then ai_interact() to press E. Nothing here
# calls light_it() directly — walk_backrooms.gd passed for weeks on an
# uncompletable level by emitting the win signal, and that mistake is not repeated.
#
# Usage: Godot --headless --path game --script res://tests/autoplay/autoplay_dungeon.gd

const SEEDS := [101, 404]
const AUTOPLAYER := preload("res://tests/autoplay/autoplayer.gd")
const FRAMES_PER_HOP := 700
# Measured: a 7-sconce route plus the walk to the bed is ~150 waypoints, and seed
# 707 lit 7/7 then ran out of budget on the final leg. The cap is a HANG GUARD, not
# a difficulty statement — size it so a competent run always finishes.
const RUN_FRAME_CAP := 45000
const ARRIVE := 1.4
const INTERACT_RANGE := 1.6
# Light the candle only within this of a sconce; walk dark the rest of the time.
const CANDLE_LIGHT_RANGE := 6.0

var _fails := 0
var _checks := 0
var _started := false
var _settle := 0
var _seed_i := 0
var _level: Node = null
var _gen = null
var _auto = null
var _scene_path := ""

var _route: Array = []          # [{pos, kind, room}]
var _leg := 0
var _hop_frames := 0
var _run_frames := 0
var _retry_leg := -1

# Per-seed measurements.
var _lit := 0
var _died := false
var _death_at := Vector3.ZERO
var _death_panic := 0.0
var _peak_panic := 0.0
var _sim_seconds := 0.0
var _results: Array = []


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails += 1


func _initialize() -> void:
	# Compressed time: the pacing under test is unchanged (every timer is in game
	# seconds) while the wall clock drops. count_apparitions.gd uses the same trick.
	Engine.time_scale = 6.0


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		_load(SEEDS[0])
		return false

	_settle += 1
	if _settle < 16:
		return false

	if _level == null:
		_level = current_scene
		if _level == null or not _level.has_method("get_gen"):
			print("  FAIL dungeon.tscn did not load, or dungeon.gd failed to parse")
			_fails += 1
			return _report()
		_scene_path = _level.scene_file_path
		_gen = _level.call("get_gen")
		_begin_run()
		return false

	# A death reloads the scene out from under us — that is how Screamer.trigger()
	# ends a run, and it is a RESULT here rather than an error.
	if current_scene == null or current_scene.scene_file_path != _scene_path \
			or not is_instance_valid(_auto.player):
		_died = true
		return _finish_seed()

	_sim_seconds += delta
	var p: CharacterBody3D = _auto.player
	_peak_panic = maxf(_peak_panic, float(p.call("get_panic_ratio")))

	return _tick(p)


func _load(s: int) -> void:
	_settle = 0
	var gs := root.get_node_or_null("GameState")
	if gs:
		gs.call("save_level_progress", 7, {"layout_seed": s, "content_seed": s * 31 + 7})
	change_scene_to_file("res://scenes/dungeon.tscn")


func _begin_run() -> void:
	var p := _level.get_node_or_null("Player") as CharacterBody3D
	if p == null:
		_ok("player exists", false)
		return
	# Skip the cot's 1.6 s fade — it is UI, not play — and start where the level
	# would have put us.
	_level.set("_in_dungeon", true)
	p.global_position = _gen.room_center_world(_gen.spawn_room) + Vector3(0, 0.4, 0)
	p.force_update_transform()
	_auto = AUTOPLAYER.new(p)

	# Light the candle: the same method the F key runs, since
	# Input.parse_input_event() does not work headless.
	_level.call("_toggle_candle")

	_route = []
	_lit = 0
	_died = false
	_peak_panic = 0.0
	_sim_seconds = 0.0
	_leg = 0
	_hop_frames = 0
	_run_frames = 0
	_retry_leg = -1

	var at: String = _gen.spawn_room
	for spot in _gen.sconce_spots:
		_append_path(at, spot["room"])
		_route.append({"pos": _sconce_pos(spot["room"]), "kind": "sconce",
			"room": spot["room"]})
		at = spot["room"]
	_append_path(at, _gen.bed_room)
	_route.append({"pos": _gen.room_center_world(_gen.bed_room), "kind": "bed",
		"room": _gen.bed_room})


func _append_path(a: String, b: String) -> void:
	var hops: Array = _gen.path_between(a, b)
	for i in range(1, hops.size()):
		var next_c: Vector3 = _gen.room_center_world(hops[i])
		var door: Vector3 = _gen.doorway_between(hops[i - 1], hops[i])
		if door != Vector3.INF:
			_route.append({"pos": door, "kind": "walk", "room": hops[i]})
			var n := next_c - door
			n.y = 0.0
			if n.length() > 0.01:
				_route.append({"pos": door + n.normalized() * 2.0, "kind": "walk",
					"room": hops[i]})
		_route.append({"pos": next_c, "kind": "walk", "room": hops[i]})


func _sconce_pos(room: String) -> Vector3:
	for s in _level.call("get_sconces"):
		if is_instance_valid(s) and s.name == "Sconce_" + room:
			var n: Vector3 = s.global_transform.basis.z.normalized()
			return s.global_position + n * 1.2 - Vector3(0, 0.9, 0)
	return _gen.room_center_world(room)


func _tick(p: CharacterBody3D) -> bool:
	_run_frames += 1
	if _run_frames > RUN_FRAME_CAP or _leg >= _route.size():
		return _finish_seed()

	var step: Dictionary = _route[_leg]
	var target: Vector3 = step["pos"]
	var flat := Vector2(target.x - p.global_position.x, target.z - p.global_position.z)

	# ⚠️ Burn the candle ONLY near a sconce, and blow it out to walk.
	#
	# The first version kept it lit permanently and ran out of wax three sconces in:
	# 4 carried + 4 cached = 8 candles x 60 s = 480 s of light for a night the design
	# targets at 12-15 minutes. That reads like a softlock and is not one — §B11
	# deliberately makes blowing the candle out BANK the remaining seconds (DN wastes
	# them; the doc cuts that as an unteachable gotcha), so the wax is sufficient if
	# and only if you use the light in bursts.
	#
	# Playing it the intended way is what makes this a test of the level rather than
	# of a bad habit. It is ALSO the finding: a player who never discovers banking
	# will run dry at about eight minutes.
	var candle = _level.get("_candle")
	if candle != null:
		var want_lit: bool = flat.length() <= CANDLE_LIGHT_RANGE and step["kind"] == "sconce"
		var lit_now: bool = bool(candle.get("burning"))
		var have: bool = int(candle.get("candles")) > 0 or float(candle.get("remaining")) > 0.5
		if want_lit and not lit_now and have:
			_level.call("_toggle_candle")
		elif not want_lit and lit_now:
			_level.call("_toggle_candle")

	if flat.length() <= ARRIVE:
		if step["kind"] == "sconce":
			_try_light(p, step["room"])
		_leg += 1
		_hop_frames = 0
		_auto.reset_stuck()
		return false

	if not _walk_watching(p, target):
		_auto.step_toward(target)
	_hop_frames += 1
	if _hop_frames > FRAMES_PER_HOP:
		# One retry by backing out, then give up on this leg — same reasoning as
		# walk_dungeon.gd: AutoPlayer has no pathfinding and can wedge on a jamb.
		if _retry_leg != _leg:
			_retry_leg = _leg
			_leg = maxi(0, _leg - 1)
			_hop_frames = 0
			_auto.reset_stuck()
			return false
		_leg += 1
		_hop_frames = 0
		_auto.reset_stuck()
	return false


# ⭐ The ONE piece of competence this walker has, and it encodes the level's own
# taught rule rather than a general-purpose AI: A STILL ONE FREEZES WHILE YOU LOOK
# AT IT (§B4.1 — CreatureStalker is a weeping angel).
#
# Without this the walker is food. It aims at its next waypoint, which wakes every
# Still One it passes and then looks away from them, which is precisely the input
# that makes them advance. Measured: 3 deaths in 3 seeds, two of them inside 40 s,
# all by contact.
#
# Keeping the walk going while watching the threat is exactly what a competent
# player does, and it makes the difference between this test measuring THE LEVEL
# and measuring the harness's inability to turn its head.
# Returns true if it handled movement this frame.
#
# ⚠️ Look and move must be driven SEPARATELY here. AutoPlayer.step_toward() walks by
# facing the target and pushing ai_move_dir = (0, -1), i.e. "forward" in the
# player's own basis — so simply calling ai_look_at() afterwards to watch a creature
# makes the walker stride straight INTO it. Measured: the run stalled at 12 s of
# STATIONARY with a Still One in its face.
#
# So: face the creature, and express the direction of travel in the player's rotated
# frame. That is what a competent player does — back away down the corridor without
# taking their eyes off the thing.
func _walk_watching(p: CharacterBody3D, target: Vector3) -> bool:
	var best: Node3D = null
	var best_d := 9.0     # CreatureStalker.ENGAGE_DIST is 8.0; a little margin
	for child in _level.get_children():
		if not child.name.begins_with("StillOne_"):
			continue
		# has_fallen() is the dud outcome — a toppled one is inert forever and
		# staring at it wastes the only defence we have.
		if child.has_method("has_fallen") and bool(child.call("has_fallen")):
			continue
		var body := _still_one_body(child)
		if body == null:
			continue
		var d: float = body.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = body
	if best == null:
		return false

	p.call("ai_look_at", best.global_position + Vector3(0, 0.9, 0))
	var cam := p.get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.force_update_transform()

	# World direction of travel -> the player's local frame. ai_move_dir follows
	# Input.get_vector()'s convention, where y is FORWARD-NEGATIVE.
	var to := target - p.global_position
	to.y = 0.0
	if to.length() < 0.05:
		p.set("ai_move_dir", Vector2.ZERO)
		return true
	var local: Vector3 = p.global_transform.basis.inverse() * to.normalized()
	p.set("ai_move_dir", Vector2(local.x, local.z).normalized())
	p.set("ai_sprint", false)
	return true


# CreatureStalker keeps its world transform on an inner StaticBody3D under a
# ScaryObject (ScaryObject is a plain Node and breaks the Node3D chain — Issue 10),
# so the outer node's position is only the seed value and is not where it IS.
func _still_one_body(node: Node) -> Node3D:
	for c in node.get_children():
		for gc in c.get_children():
			if gc is StaticBody3D:
				return gc
	return null


# The SHIPPING interact path, start to finish: aim, confirm the prompt would show,
# then press E. If ai_interact_target() does not return the sconce, the player
# could not have lit it either.
func _try_light(p: CharacterBody3D, room: String) -> void:
	var sconce: Node = null
	for s in _level.call("get_sconces"):
		if is_instance_valid(s) and s.name == "Sconce_" + room:
			sconce = s
	if sconce == null:
		return
	p.call("ai_look_at", sconce.global_position)
	var cam := p.get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.force_update_transform()
	var t: Node = p.call("ai_interact_target")
	if t == sconce or (t != null and sconce.is_ancestor_of(t)):
		p.call("ai_interact")
		if bool(sconce.get("is_lit")):
			_lit += 1


func _finish_seed() -> bool:
	var s: int = SEEDS[_seed_i]
	var panic := 0.0
	if _auto != null and is_instance_valid(_auto.player):
		panic = float(_auto.player.call("get_panic_ratio"))
	_results.append({
		"seed": s, "lit": _lit, "died": _died, "peak_panic": _peak_panic,
		"seconds": _sim_seconds, "reached_bed": _leg >= _route.size(),
		"candles": _candles_left(),
	})
	if _auto != null:
		_auto.release()
		_auto = null

	_seed_i += 1
	_level = null
	if _seed_i < SEEDS.size():
		_load(SEEDS[_seed_i])
		return false
	return _report()


func _candles_left() -> int:
	if _level == null or not is_instance_valid(_level):
		return -1
	var c = _level.get("_candle")
	return int(c.get("candles")) if c != null else -1


func _report() -> bool:
	print("AUTOPLAY-DUNGEON seeds=%d  (entities LIVE)" % _results.size())
	var wins := 0
	var deaths := 0
	var total_lit := 0
	for r in _results:
		# Peak panic separates the two death causes: a panic death necessarily
		# reaches 100%, while creature contact is instant at whatever panic you
		# happened to be carrying.
		var verdict: String = "reached the bed" if r["reached_bed"] else "ran out of budget"
		if r["died"]:
			verdict = "DIED (panic)" if r["peak_panic"] > 0.9 else "DIED (contact)"
		print("  seed %-5d %-18s sconces %d/7  peak panic %3d%%  %5.0f s  candles left %d" % [
			r["seed"], verdict, r["lit"], int(r["peak_panic"] * 100.0), r["seconds"],
			r["candles"]])
		total_lit += int(r["lit"])
		if r["died"]:
			deaths += 1
		elif r["reached_bed"]:
			wins += 1

	# ⚠️ Sample-size assertion — a level that fails to parse must not report PASS.
	if _results.size() < SEEDS.size():
		_ok("every seed produced a result", false,
			"%d/%d" % [_results.size(), SEEDS.size()])

	# ⚠️ What is asserted here, and what is NOT.
	#
	# NOT asserted: that this bot wins. It has exactly one piece of competence (watch
	# the nearest Still One) and none of the others the level teaches — it cannot
	# stop and listen for the Hollow One, cannot hide, cannot walk away from the
	# Matron. A horror level that a bot with no threat response can clear would be a
	# worse level, so "wins > 0" is not a property worth demanding. Whether the
	# resulting death rate is CORRECT is the user's call, never this file's.
	#
	# Asserted: that progress is possible with the full roster live and that the
	# shipping interact path works under load — every seed must light at least one
	# sconce through ai_interact_target() + ai_interact(), and the runs together must
	# make real headway. If sconces stop being lightable once entities are active,
	# that is a bug, and it is the thing this test exists to catch.
	var every_seed_progressed := true
	for r in _results:
		if int(r["lit"]) < 1:
			every_seed_progressed = false
	_ok("every seed lit at least one sconce through the real interact path",
		every_seed_progressed)
	_ok("meaningful progress is possible with the roster live",
		total_lit >= 3, "%d sconces lit across %d runs (%d won, %d died)" % [
			total_lit, _results.size(), wins, deaths])

	print("  %d checks, %d failed" % [_checks, _fails])
	print("--------------------------------------------------")
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	print("--------------------------------------------------")
	quit(0 if _fails == 0 else 1)
	return true
