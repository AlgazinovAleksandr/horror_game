extends SceneTree

# The House map minigame's monster must be able to catch you — and you must still be
# able to win (BACKLOG #14).
#   Godot --headless --path game --script res://tests/check_maze_chase.gd
#
# The bug: it steered by a raw Euclidean beeline through a PERFECT maze (randomized-DFS
# spanning tree, no loops), where the corridor route between two cells is routinely
# 5-15x the straight line. So it drove into walls, the per-axis wall-slide carried it
# sideways down dead ends, and once the player had left the starting neighbourhood it
# could never close again — exactly the reported "it can basically kill the player only
# at the beginning."
#
# Nothing here opens the real UI or touches a scene. It instantiates MazeChaseUI's
# script, generates real mazes, and steps the real _tick_monster() by hand — the same
# way check_maze_gen.gd exercises generation, because the minigame is only ever reached
# through a prop's interact() and no scene smoke test ever runs a single frame of it.
#
# Three passes. The first two are deliberately opposed, because "smarter" has an obvious
# wrong answer; the third is the one that actually discriminates:
#   CATCH   — a player who stands still AT THE START is caught.
#   ESCAPE  — a player who walks the corridor route to the target still wins. If this
#             fails the monster is unbeatable, a worse bug than the one being fixed.
#   PURSUE  — a player who runs to the far end of the maze and THEN stops is still
#             hunted down. This is the reported bug in one sentence: "it can basically
#             kill the player only at the beginning."
#
# ⚠️ CATCH and ESCAPE both PASS against the old beeline AI, verified by putting it back.
# They had to be written before that was obvious: the monster spawns one cell from the
# player, and over 96 px a beeline and a corridor route are the same thing, so neither
# pass touches pathfinding at all. Only PURSUE separates them (beeline: 0/40).

const TRIALS := 40
const DT := 1.0 / 60.0
const CATCH_TIMEOUT := 30.0     # seconds of simulated chase before we call it inert
# Generous: crossing a 10x8 maze corner to corner along the corridors is ~30 cells
# = ~2900 px, which at MONSTER_SPEED takes ~33 s. Anything under this is navigation
# working; a monster that never arrives is jammed.
const HUNT_TIMEOUT := 60.0
const ESCAPE_SPEED := 200.0     # under PLAYER_MAX_SPEED (240) — an unhurried player

var _ui: Node
var _fails := 0
var _catch_times: Array[float] = []
var _escapes := 0
var _caught_while_fleeing := 0


func _initialize() -> void:
	var script: GDScript = load("res://scripts/maze_chase_ui.gd")
	_ui = script.new()


func _fail(msg: String) -> void:
	_fails += 1
	print("  FAIL ", msg)


func _fresh(seed_value: int) -> void:
	seed(seed_value)
	_ui.call("_generate_maze")
	_ui.call("_reset_positions")
	# The caller gates ticking on MONSTER_START_DELAY itself (see `grace`), so clear the
	# UI's own counter — otherwise the delay would be applied twice.
	_ui.set("_monster_start_timer", 0.0)


func _process(_delta: float) -> bool:
	print("--- %d mazes: does a STATIONARY player get caught? ---" % TRIALS)
	var catch_radius: float = _ui.get_script().get("CATCH_RADIUS")
	# ⚠️ Honour MONSTER_START_DELAY. The monster spawns one cell from the player, and in
	# a spanning tree the route to the target very often runs through that exact cell —
	# so without the head start the player walks straight into it and "escape" measures
	# the grace period's absence, not the AI. _tick_monster() knows nothing about the
	# delay (the UI's own _process() gates it), so the test has to.
	var grace: float = _ui.get_script().get("MONSTER_START_DELAY")
	for i in TRIALS:
		_fresh(9000 + i)
		var t := 0.0
		var caught := false
		while t < CATCH_TIMEOUT:
			if t >= grace:
				_ui.call("_tick_monster", DT)
			t += DT
			var mp: Vector2 = _ui.get("_monster_pos")
			var pp: Vector2 = _ui.get("_player_pos")
			if mp.distance_to(pp) <= catch_radius:
				caught = true
				break
		if caught:
			_catch_times.append(t)
		else:
			_fail("maze seed %d: stood still for %.0f s and was never caught"
				% [9000 + i, CATCH_TIMEOUT])

	if not _catch_times.is_empty():
		var lo := _catch_times[0]
		var hi := _catch_times[0]
		var sum := 0.0
		for v in _catch_times:
			lo = minf(lo, v)
			hi = maxf(hi, v)
			sum += v
		print("  caught %d/%d — time to catch: min %.1f s / mean %.1f s / max %.1f s"
			% [_catch_times.size(), TRIALS, lo, sum / _catch_times.size(), hi])

	print("--- %d mazes: can a player who KEEPS MOVING still win? ---" % TRIALS)
	for i in TRIALS:
		_fresh(9000 + i)
		var t := 0.0
		var won := false
		var caught := false
		while t < CATCH_TIMEOUT:
			_step_player_toward_target(DT)
			if t >= grace:
				_ui.call("_tick_monster", DT)
			t += DT
			var mp: Vector2 = _ui.get("_monster_pos")
			var pp: Vector2 = _ui.get("_player_pos")
			var tp: Vector2 = _ui.get("_target_pos")
			if mp.distance_to(pp) <= catch_radius:
				caught = true
				break
			if pp.distance_to(tp) <= float(_ui.get_script().get("WIN_RADIUS")):
				won = true
				break
		if won:
			_escapes += 1
		elif caught:
			_caught_while_fleeing += 1
	print("  reached the mark %d/%d (caught in flight %d)"
		% [_escapes, TRIALS, _caught_while_fleeing])
	if _escapes < int(TRIALS * 0.75):
		_fail("only %d/%d escapes — the monster is now effectively unbeatable"
			% [_escapes, TRIALS])

	print("--- %d mazes: player runs to the far end, THEN stops. Hunted down? ---" % TRIALS)
	var hunted := 0
	var hunt_times: Array[float] = []
	for i in TRIALS:
		_fresh(9000 + i)
		var t := 0.0
		# Phase 1: run for the target, monster held for its usual head start.
		while t < 12.0:
			_step_player_toward_target(DT)
			if t >= grace:
				_ui.call("_tick_monster", DT)
			t += DT
			var pp0: Vector2 = _ui.get("_player_pos")
			var tp0: Vector2 = _ui.get("_target_pos")
			if pp0.distance_to(tp0) <= float(_ui.get_script().get("WIN_RADIUS")):
				break
		# Phase 2: freeze. From here the ONLY question is whether it can navigate.
		var start_gap: float = (_ui.get("_monster_pos") as Vector2).distance_to(
			_ui.get("_player_pos") as Vector2)
		var t2 := 0.0
		var got := false
		while t2 < HUNT_TIMEOUT:
			_ui.call("_tick_monster", DT)
			t2 += DT
			if (_ui.get("_monster_pos") as Vector2).distance_to(
					_ui.get("_player_pos") as Vector2) <= catch_radius:
				got = true
				break
		if got:
			hunted += 1
			hunt_times.append(t2)
		elif hunted + (TRIALS - i - 1) < int(TRIALS * 0.9):
			pass   # reported in aggregate below
		if not got and hunt_times.size() < 3:
			print("    seed %d: gave up after %.0f s, still %.0f px away (started %.0f px)"
				% [9000 + i, HUNT_TIMEOUT,
					(_ui.get("_monster_pos") as Vector2).distance_to(
						_ui.get("_player_pos") as Vector2), start_gap])
	var mean_hunt := 0.0
	for v in hunt_times:
		mean_hunt += v
	if not hunt_times.is_empty():
		mean_hunt /= hunt_times.size()
	print("  hunted down %d/%d (mean %.1f s after the player stopped)"
		% [hunted, TRIALS, mean_hunt])
	if hunted < int(TRIALS * 0.9):
		_fail("only %d/%d — the monster cannot reach a player who moved away. This is "
			% [hunted, TRIALS] + "the reported bug: it only kills you at the start.")

	print("--------------------------------------------------")
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	print("--------------------------------------------------")
	quit(0 if _fails == 0 else 1)
	return true


# Drive the player along the SAME corridor route the monster uses, so "escape" means a
# competent player, not one teleporting through walls.
func _step_player_toward_target(dt: float) -> void:
	var pp: Vector2 = _ui.get("_player_pos")
	var tp: Vector2 = _ui.get("_target_pos")
	var pcell: Vector2i = _ui.call("_cell_at", pp)
	var tcell: Vector2i = _ui.call("_cell_at", tp)
	var aim := tp
	if pcell != tcell:
		var field: Dictionary = _ui.call("_bfs_distances", tcell)
		var best := pcell
		var best_d: int = field.get(pcell, 1 << 30)
		for n in _ui.call("_open_neighbours", pcell):
			if field.has(n) and int(field[n]) < best_d:
				best_d = int(field[n])
				best = n
		if best != pcell:
			aim = _ui.call("_cell_center", best)
	var dir := (aim - pp)
	if dir.length() < 0.01:
		return
	var step: Vector2 = pp + dir.normalized() * ESCAPE_SPEED * dt
	_ui.set("_player_pos", _ui.call("_resolve_wall_slide", pp, step,
		_ui.get_script().get("ICON_HALF_EXTENT")))
