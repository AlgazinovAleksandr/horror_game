extends SceneTree

# MEASUREMENT ONLY — the distribution the House maze's difficulty band would have to be
# chosen from. It asserts nothing and changes nothing.
#
#   Godot --headless --path game --script res://tests/probe_maze_variance.gd
#   Godot --headless --path game --script res://tests/probe_maze_variance.gd -- 400
#   Godot --headless --path game --script res://tests/probe_maze_variance.gd -- 300 1 200 6
#                                                        seeds ^  N ^  bot px/s ^  ^ min detour
#   ⚠️ **N=0 is the CONTROL** — it reproduces the one-stage build exactly, through this same
#   instrumented path, and it is the only honest baseline to compare a redesign against.
#
# ⚠️ 2026-08-16: it now also reports TOUR (start -> every fragment -> mark, the length the
# two-stage objective actually asks for) and PANIC (the drip + proximity term integrated over
# a whole winning run — the redesign roughly triples time-on-board without touching
# MAZE_DRIP_RATE, so the cost to the player's LIFE changed even though no constant did).
#
# Backlog 02-house S1 Part 2 proposes a post-generation validate-and-reject loop (Cogmind's
# standard technique) to bound how much instances vary. ⚠️ The band's numbers are DIFFICULTY
# CONSTANTS and therefore the user's, so this probe exists to produce the numbers first. No
# constant may move before it has been run.
#
# Per seed it reports these, most of which already have code behind them:
#   * TOUR    — start -> every fragment -> mark: the length the objective actually asks for,
#               and the quantity `TOUR_BAND` validates against.
#   * PANIC   — the drip + proximity term integrated over a whole winning run, plus SNARE_PANIC
#               per snare sprung, out of PANIC_MAX 50.
#   * CAUGHT  — when the run died, how much of the objective was done, and WHICH pursuer did
#               it. ⚠️ This is the one that diagnosed the first build: "10/200 escaped" says
#               too hard, "median catch at 5.6 s with one fragment collected" says the tour
#               order is wrong, and those imply completely different fixes.
#   * ROUTE   — BFS corridor distance from the start cell to the mark (`_bfs_distances`)
#   * PATROL  — BFS distance from the patroller's start cell to the NEAREST cell on that
#               route (`_compute_route`). check_maze_chase.gd's own isolation table says the
#               patroller's mere PRESENCE, not its aggro, is where the variance lives.
#   * SNARE   — how many snares sit within one cell of the route. Should be 0 by
#               construction (`_place_snares` excludes route cells); measured, not assumed.
#   * WIN     — simulated seconds for a competent bot to reach the mark, using
#               check_maze_chase.gd's own `_step_player_toward_target` logic, with the real
#               hunter, patroller and snares ticking. -1 means it was caught.
#
# ⚠️ Nothing here opens a scene. It instantiates the script and steps its real functions, the
# same way check_maze_gen.gd and check_maze_chase.gd do.

const DT := 1.0 / 60.0
const SIM_TIMEOUT := 100.0
const AVOID_RADIUS := 70.0

var _ui: Node
var _runs := 200
var _frag_n := -1     # -1 = leave the shipped `fragment_count` alone
# ⚠️ SWEEPABLE (2026-08-16), and the reason matters. check_maze_chase.gd's bot has always run
# at 200 px/s while `PLAYER_MAX_SPEED` is 240 — i.e. the harness models a player at ~83 % of
# the top speed the game allows, which is roughly a player already at 28 % panic. Over a 10 s
# run that gap is worth a couple of metres. Over a 60-cell tour it is the whole margin against
# a MONSTER_SPEED of 172: 28 px/s of headroom instead of 68. A number measured at 200 is a
# real number about a mediocre player; it is not the ceiling, and after the two-stage redesign
# the difference between those two readings stopped being academic.
var _escape_speed := 200.0
var _detour := -1     # -1 = leave FRAGMENT_MIN_DETOUR alone

# Per-seed records, aligned by index, for the cross-tabs.
var _route_of: Array = []
var _patrol_of: Array = []
var _won_of: Array = []
var _time_of: Array = []

# The bot's waypoint, recomputed only when the fragment count changes — see
# check_maze_chase.gd's `_bot_goal()`, of which this is the twin.
var _goal := Vector2.ZERO
var _goal_for := -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_runs = int(args[0])
	# ⚠️ `-- <runs> <N>` sweeps the fragment count. The choice between N=2 and N=3 was made
	# from this probe's own output rather than from taste, which is why `fragment_count` is a
	# var on the UI script at all.
	if args.size() >= 2:
		_frag_n = int(args[1])
	if args.size() >= 3:
		_escape_speed = float(args[2])
	if args.size() >= 4:
		_detour = int(args[3])
	var script: GDScript = load("res://scripts/maze_chase_ui.gd")
	_ui = script.new()
	# ⚠️ `>= 0`, not `> 0`: **N=0 is the control run** — it reproduces the shipped one-stage
	# build exactly (no fragments, the mark open from the first frame) through the same
	# instrumented code path, which is the only honest baseline to compare a redesign against.
	# A `> 0` here silently ignored `-- 200 0` and reprinted the previous N=3 figures.
	if _frag_n >= 0:
		_ui.set("fragment_count", _frag_n)
	if _detour >= 0:
		_ui.set("min_detour_override", _detour)


func _pct(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	var i: int = clampi(int(round(p * (sorted.size() - 1))), 0, sorted.size() - 1)
	return float(sorted[i])


func _report(label: String, values: Array) -> void:
	if values.is_empty():
		print("  %-8s (no samples)" % label)
		return
	var s := values.duplicate()
	s.sort()
	var sum := 0.0
	for v in s:
		sum += float(v)
	print("  %-8s n=%d  min %.1f  p10 %.1f  p25 %.1f  median %.1f  p75 %.1f  p90 %.1f  max %.1f  mean %.1f"
		% [label, s.size(), _pct(s, 0.0), _pct(s, 0.10), _pct(s, 0.25), _pct(s, 0.5),
			_pct(s, 0.75), _pct(s, 0.90), _pct(s, 1.0), sum / s.size()])


func _histogram(label: String, values: Array, bucket: float) -> void:
	var counts: Dictionary = {}
	for v in values:
		var b: int = int(floor(float(v) / bucket))
		counts[b] = int(counts.get(b, 0)) + 1
	var keys: Array = counts.keys()
	keys.sort()
	print("  %s (bucket %.0f):" % [label, bucket])
	for k in keys:
		var n: int = counts[k]
		print("    %5.0f-%-5.0f  %-4d %s" % [float(k) * bucket, float(k + 1) * bucket - 1, n,
			"#".repeat(mini(n, 60))])


func _process(_delta: float) -> bool:
	var grace: float = _ui.get_script().get("MONSTER_START_DELAY")
	var catch_radius: float = _ui.get_script().get("CATCH_RADIUS")
	# ⚠️ No WIN_RADIUS here any more: the win is decided by the UI's own `_is_won()`, which
	# also owns the "every fragment collected" half of the rule.

	var drip: float = float(_ui.get_script().get("MAZE_DRIP_RATE"))
	var prox_range: float = float(_ui.get_script().get("PROXIMITY_RANGE"))
	var prox_max: float = float(_ui.get_script().get("PROXIMITY_MAX_RATE"))
	var snare_panic: float = float(_ui.get_script().get("SNARE_PANIC"))

	var routes: Array = []
	var patrols: Array = []
	var snares_near: Array = []
	var win_times: Array = []
	var tours: Array = []
	var panics: Array = []
	var caught := 0
	# ⚠️ WHO caught you, and WHEN, and how much of the objective you had done. An aggregate
	# "2/40 escaped" says the build is too hard; it does not say which of the two pursuers, or
	# whether the run died at the first fragment or the last leg — and those imply completely
	# different fixes.
	var caught_by_hunter := 0
	var caught_by_patrol := 0
	var caught_times: Array = []
	var caught_progress: Array = []
	# Per-seed, aligned, for the cross-tabs at the bottom.
	_route_of.clear()
	_patrol_of.clear()
	_won_of.clear()
	_time_of.clear()

	for i in _runs:
		seed(9000 + i)
		_ui.call("_generate_maze")
		_ui.call("_reset_positions")
		_ui.set("_monster_start_timer", 0.0)
		_goal_for = -1

		var dist: Dictionary = _ui.call("_bfs_distances", _ui.get("_start_cell"))
		var route_len: int = int(dist.get(_ui.get("_target_cell"), -1))
		routes.append(route_len)
		tours.append(int(_ui.get("_tour_length")))

		# Patroller start -> nearest route cell, in corridor steps.
		var patrol_cell: Vector2i = _ui.call("_cell_at", _ui.get("_patrol_start"))
		var from_patrol: Dictionary = _ui.call("_bfs_distances", patrol_cell)
		var nearest := 1 << 20
		for c in (_ui.get("_route_cells") as Dictionary).keys():
			nearest = mini(nearest, int(from_patrol.get(c, 1 << 20)))
		patrols.append(nearest)

		# Snares within one cell of the route.
		var near := 0
		for s: Vector2 in (_ui.get("_snares") as Array):
			var sc: Vector2i = _ui.call("_cell_at", s)
			var d := 1 << 20
			var from_snare: Dictionary = _ui.call("_bfs_distances", sc)
			for c in (_ui.get("_route_cells") as Dictionary).keys():
				d = mini(d, int(from_snare.get(c, 1 << 20)))
			if d <= 1:
				near += 1
		snares_near.append(near)

		# Simulated time to win, with the whole roster live.
		#
		# ⚠️ PANIC IS INTEGRATED HERE TOO (2026-08-16). The two-stage objective roughly
		# triples how long the overlay stays open, and the panic drip is charged per second —
		# so the redesign changes the minigame's cost to the player's LIFE even though it did
		# not touch MAZE_DRIP_RATE or PROXIMITY_MAX_RATE. Dying inside the map is a screamer
		# and a level restart, which is much harsher than a catch, so the number belongs in
		# the report whether or not anything is done about it. Mirrors _process()'s formula
		# exactly, including the no-panic-during-the-head-start rule.
		var t := 0.0
		var won := false
		var lost := false
		var panic := 0.0
		var by_patrol := false
		var armed: int = (_ui.get("_fragments") as Array).size()
		var snares_before: int = (_ui.get("_snares") as Array).size()
		while t < SIM_TIMEOUT:
			_step_player_toward_target(DT)
			if t >= grace:
				_ui.call("_tick_monster", DT)
				_ui.call("_tick_patroller", DT)
				_ui.call("_check_snares", null)
			_ui.call("_check_fragments")
			var pp0: Vector2 = _ui.get("_player_pos")
			if t >= grace:
				var gap: float = minf(
					(_ui.get("_monster_pos") as Vector2).distance_to(pp0),
					(_ui.get("_patrol_pos") as Vector2).distance_to(pp0))
				var rate := drip
				if gap < prox_range:
					var ratio: float = 1.0 - gap / prox_range
					rate += prox_max * ratio * ratio
				panic += DT * rate
			t += DT
			var pp: Vector2 = _ui.get("_player_pos")
			var d_hunt: float = (_ui.get("_monster_pos") as Vector2).distance_to(pp)
			var d_patr: float = (_ui.get("_patrol_pos") as Vector2).distance_to(pp)
			if d_hunt <= catch_radius or d_patr <= catch_radius:
				lost = true
				by_patrol = d_patr <= catch_radius and d_hunt > catch_radius
				break
			if bool(_ui.call("_is_won")):
				won = true
				break
		panic += snare_panic * float(snares_before - (_ui.get("_snares") as Array).size())
		if won:
			panics.append(panic)
		_route_of.append(route_len)
		_patrol_of.append(nearest)
		_won_of.append(won)
		_time_of.append(t if won else 0.0)
		if won:
			win_times.append(t)
		elif lost:
			caught += 1
			caught_times.append(t)
			caught_progress.append(armed - (_ui.get("_fragments") as Array).size())
			if by_patrol:
				caught_by_patrol += 1
			else:
				caught_by_hunter += 1

	print("=== House maze variance, %d seeds, N=%d fragments (seed 9000+i) ==="
		% [_runs, int(_ui.get("fragment_count"))])
	_report("ROUTE", routes)
	_report("TOUR", tours)
	_report("PATROL", patrols)
	_report("SNARE<=1", snares_near)
	_report("WIN s", win_times)
	_report("PANIC", panics)
	print("  reached the mark %d/%d, caught %d, timed out %d   (bot speed %.0f px/s)"
		% [win_times.size(), _runs, caught, _runs - win_times.size() - caught, _escape_speed])
	_report("CAUGHT s", caught_times)
	_report("CAUGHT@", caught_progress)
	print("  caught by the HUNTER %d, by the PATROLLER %d" % [caught_by_hunter, caught_by_patrol])
	_histogram("TOUR distribution", tours, 5.0)
	_histogram("PATROL distribution", patrols, 1.0)
	_histogram("WIN-TIME distribution", win_times, 5.0)
	# ⚠️ The cross-tabs are the part a band would actually be chosen from: a distribution says
	# how much instances vary, and only these say whether the variation MATTERS.
	_crosstab("win rate by PATROL distance", _patrol_of, _won_of, _time_of,
		[0, 1, 3, 5, 7, 10, 999])
	_crosstab("win rate by ROUTE length", _route_of, _won_of, _time_of,
		[0, 20, 24, 28, 32, 38, 999])
	_crosstab("win rate by TOUR length", tours, _won_of, _time_of,
		[0, 42, 48, 54, 60, 66, 72, 9999])
	quit(0)
	return true


# Bucket by `keys`, and report how often the bot got out and how long it took.
func _crosstab(label: String, keys: Array, won: Array, times: Array, edges: Array) -> void:
	print("  %s:" % label)
	for e in range(edges.size() - 1):
		var lo: int = edges[e]
		var hi: int = edges[e + 1]
		var n := 0
		var w := 0
		var tsum := 0.0
		for i in keys.size():
			var k: int = int(keys[i])
			if k < lo or k >= hi:
				continue
			n += 1
			if bool(won[i]):
				w += 1
				tsum += float(times[i])
		if n == 0:
			continue
		print("    %-8s n=%-4d  reached the mark %3d/%-3d = %3.0f%%   mean win %.1f s"
			% ["%d-%d" % [lo, hi - 1] if hi < 999 else "%d+" % lo, n, w, n,
				100.0 * float(w) / float(n), (tsum / w) if w > 0 else 0.0])


# Where the bot is heading: the nearest live fragment by corridor distance, then the mark.
# Twin of check_maze_chase.gd's `_bot_goal()`, deliberately kept verbatim so the probe and
# the assertion measure the same player.
func _bot_goal() -> Vector2:
	var frags: Array = _ui.get("_fragments")
	if frags.is_empty():
		return _ui.get("_target_pos")
	if _goal_for != frags.size():
		_goal_for = frags.size()
		var pcell: Vector2i = _ui.call("_cell_at", _ui.get("_player_pos"))
		var field: Dictionary = _ui.call("_bfs_distances", pcell)
		var best: Vector2 = frags[0]
		var best_d: int = 1 << 30
		for f: Vector2 in frags:
			var d: int = int(field.get(_ui.call("_cell_at", f), 1 << 30))
			if d < best_d:
				best_d = d
				best = f
		_goal = best
	return _goal


# Verbatim from check_maze_chase.gd — a competent player who walks the corridor route and
# steps around a monster standing in it, rather than one teleporting through walls.
func _step_player_toward_target(dt: float) -> void:
	var pp: Vector2 = _ui.get("_player_pos")
	var tp: Vector2 = _bot_goal()
	var pcell: Vector2i = _ui.call("_cell_at", pp)
	var tcell: Vector2i = _ui.call("_cell_at", tp)
	var aim := tp
	if pcell != tcell:
		var field: Dictionary = _ui.call("_bfs_distances", tcell)
		var danger: Array[Vector2] = [_ui.get("_monster_pos"), _ui.get("_patrol_pos")]
		var best := pcell
		var best_d: int = field.get(pcell, 1 << 30)
		var fallback := pcell
		var fallback_d: int = best_d
		for n in _ui.call("_open_neighbours", pcell):
			if not field.has(n) or int(field[n]) >= best_d:
				if field.has(n) and int(field[n]) < fallback_d:
					fallback_d = int(field[n])
					fallback = n
				continue
			var centre: Vector2 = _ui.call("_cell_center", n)
			var blocked := false
			for d in danger:
				if centre.distance_to(d) < AVOID_RADIUS:
					blocked = true
					break
			if blocked:
				if int(field[n]) < fallback_d:
					fallback_d = int(field[n])
					fallback = n
				continue
			best_d = int(field[n])
			best = n
		if best == pcell:
			best = fallback
		if best != pcell:
			aim = _ui.call("_cell_center", best)
	var dir := (aim - pp)
	if dir.length() < 0.01:
		return
	var step: Vector2 = pp + dir.normalized() * _escape_speed * dt
	_ui.set("_player_pos", _ui.call("_resolve_wall_slide", pp, step,
		_ui.get_script().get("ICON_HALF_EXTENT")))
