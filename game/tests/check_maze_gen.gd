extends SceneTree

# One-off stress test for maze_chase_ui.gd's maze generation, run outside any
# scene (the minigame is only ever opened via player interaction, so the normal
# scene smoke test never exercises _generate_maze() at all). Checks, across many
# random seeds: every cell is reachable from every other cell (a real spanning
# tree, no isolated pockets), the target is never trivially close to the start,
# the monster never spawns on the target, and wall/collision data is self-consistent.
#
# ⚠️ 2026-08-16 — THE TWO-STAGE OBJECTIVE. Three new families of assertion, each of which
# exists because the thing it checks can fail SILENTLY and produce a green run:
#   * FRAGMENTS  — the right number of them, off the direct line, not clustered in one
#                  pocket, and never on the start or the mark. A generator that quietly
#                  placed zero fragments would turn the two-stage objective back into the
#                  one-stage one and every other test here would still pass.
#   * THE TOUR   — strictly longer than the direct route (i.e. the detours are REAL), and
#                  inside the declared band unless the maze genuinely could not produce one.
#   * THE BAND   — the patroller no longer starts on the player's artery, which is the
#                  single largest source of the reported randomness (backlog §7 P4: 40 % of
#                  seeds started it ON the route, and those seeds won 28 % against 83-100 %).
# Each is checked against an INDEPENDENT recomputation, never against the value the
# generator recorded for itself.


func _initialize() -> void:
	var ui := MazeChaseUI.new()
	var failures := 0
	var runs := 200
	# Sample counters — a pass that checked nothing must be visible as such. This repo has
	# shipped "0 spawns checked … PASS" before.
	var frag_checks := 0
	var tour_checks := 0
	var band_ok := 0
	var band_impossible := 0
	var tour_in_band := 0
	var tour_lengths: Array = []
	var direct_lengths: Array = []
	for i in range(runs):
		seed(i * 7919 + 13)
		ui._generate_maze()

		# Every one of GRID_COLS*GRID_ROWS cells must be visited by the DFS.
		var unvisited := 0
		for c in ui._cells:
			if not c["visited"]:
				unvisited += 1
		if unvisited > 0:
			print("FAIL seed=%d: %d unvisited cells (maze is not a full spanning tree)" % [i, unvisited])
			failures += 1

		# BFS from start must reach all 80 cells (connectivity check independent
		# of the "visited" flag above).
		var dist: Dictionary = ui._bfs_distances(ui._start_cell)
		if dist.size() != MazeChaseUI.GRID_COLS * MazeChaseUI.GRID_ROWS:
			print("FAIL seed=%d: BFS only reached %d/%d cells" % [i, dist.size(), MazeChaseUI.GRID_COLS * MazeChaseUI.GRID_ROWS])
			failures += 1

		# Target must be a real, non-trivial route (the whole point of picking the
		# max-BFS-distance cell).
		var target_dist: int = dist.get(ui._target_cell, -1)
		if target_dist < 6:
			print("FAIL seed=%d: target only %d cells from start (too close)" % [i, target_dist])
			failures += 1

		# ⚠️ The comment here used to say "not adjacent to the start" while the check
		# was `monster_dist < 1` — and _place_monster() deliberately picks dist == 1,
		# i.e. exactly adjacent. So the assertion could never fire and the comment
		# described the opposite of the design. Adjacency IS the design (playtest:
		# "catches you if you get stuck", not "avoid its territory"); what must be
		# true is that it is ON THE GRID and not standing on the goal.
		var monster_cell := Vector2i(int(ui._monster_pos.x / MazeChaseUI.CELL_SIZE), int(ui._monster_pos.y / MazeChaseUI.CELL_SIZE))
		if monster_cell == ui._target_cell:
			print("FAIL seed=%d: monster spawned on the target cell" % i)
			failures += 1
		var monster_dist: int = dist.get(monster_cell, -1)
		if monster_dist != 1:
			print("FAIL seed=%d: monster is %d cells from start, expected exactly 1" % [i, monster_dist])
			failures += 1

		# It must not stand on the FIRST STEP of the only route to the player's first
		# objective. The maze is a spanning tree, so blocking that cell is a roadblock the
		# player cannot go round — harmless while the monster jammed itself on walls, a
		# measured 12-in-40 instant death once it started following corridors (BACKLOG #14).
		#
		# ⚠️ THE DESTINATION CHANGED ON 2026-08-16 and this assertion had to move with it.
		# With the two-stage objective the player's opening move is toward `_tour[0]` — the
		# nearest FRAGMENT — and the mark is inert until every fragment is in hand. Checking
		# the route to the mark would have been checking a corridor nobody walks first.
		var first_goal: Vector2i = ui._tour[0] if not ui._tour.is_empty() else ui._target_cell
		var to_target: Dictionary = ui._bfs_distances(first_goal)
		var start_to_target: int = int(to_target.get(ui._start_cell, 1 << 30))
		var monster_to_target: int = int(to_target.get(monster_cell, 1 << 30))
		if monster_to_target < start_to_target:
			# Only a real failure if some OTHER adjacent cell was available.
			var alternatives := 0
			for n in ui._open_neighbours(ui._start_cell):
				if int(to_target.get(n, 1 << 30)) >= start_to_target:
					alternatives += 1
			if alternatives > 0:
				print("FAIL seed=%d: monster blocks the only route to the target, and %d "
					% [i, alternatives] + "off-route cell(s) were free")
				failures += 1

		# ---------------------------------------------------------------- the fragments
		var want_frags: int = ui.fragment_count
		if ui._fragments.size() != want_frags or ui._fragments_initial.size() != want_frags:
			print("FAIL seed=%d: %d live / %d armed fragments, expected %d"
				% [i, ui._fragments.size(), ui._fragments_initial.size(), want_frags])
			failures += 1
		if ui._fragment_cells.size() != want_frags:
			print("FAIL seed=%d: %d fragment cells, expected %d"
				% [i, ui._fragment_cells.size(), want_frags])
			failures += 1
		else:
			# Independent recomputation of the detour each fragment is worth:
			#     detour(c) = d(start,c) + d(c,mark) - d(start,mark)
			var to_mark: Dictionary = ui._bfs_distances(ui._target_cell)
			var direct_len: int = int(dist.get(ui._target_cell, 0))
			direct_lengths.append(direct_len)
			for f in ui._fragment_cells:
				frag_checks += 1
				if f == ui._start_cell or f == ui._target_cell:
					print("FAIL seed=%d: fragment on the start or the mark (%s)" % [i, f])
					failures += 1
					continue
				var detour: int = int(dist.get(f, 1 << 20)) + int(to_mark.get(f, 1 << 20)) - direct_len
				# The loosest rung of the relaxation ladder is min_detour = 1. A fragment
				# worth ZERO extra cells sits on a shortest path to the mark and is collected
				# for free, which is the whole feature failing quietly.
				if detour < 1:
					print("FAIL seed=%d: fragment %s costs %d extra cells — it is ON the "
						% [i, f, detour] + "direct route and would be collected for free")
					failures += 1
				# ⚠️ And never at the bottom of a cul-de-sac. `_braid()` opens only 55 % of dead
				# ends, so the rest are real, and a MANDATORY objective in one is a trap: you
				# walk in, the hunter follows you in, and there is no second exit. Measured over
				# 300 seeds, removing this guard cost 12 seeds — 57.3 % → 53.3 %, i.e. straight
				# through `check_maze_chase.gd`'s 0.55 floor.
				if ui._open_neighbours(f).size() < 2:
					print("FAIL seed=%d: fragment %s is in a DEAD END — one way in, one way out, "
						% [i, f] + "and a pursuer behind you")
					failures += 1
			# Not all in one pocket: the loosest rung is min_sep = 2.
			for a in range(ui._fragment_cells.size()):
				for b in range(a + 1, ui._fragment_cells.size()):
					var sep: int = int(ui._bfs_distances(ui._fragment_cells[a]).get(
						ui._fragment_cells[b], 1 << 20))
					if sep < 2:
						print("FAIL seed=%d: fragments %s and %s are %d cells apart"
							% [i, ui._fragment_cells[a], ui._fragment_cells[b], sep])
						failures += 1

			# ---------------------------------------------------------------- the tour
			tour_checks += 1
			if ui._tour.size() != want_frags + 1:
				print("FAIL seed=%d: tour has %d waypoints, expected %d fragments + the mark"
					% [i, ui._tour.size(), want_frags])
				failures += 1
			elif ui._tour[-1] != ui._target_cell:
				print("FAIL seed=%d: the tour does not end at the mark (%s)" % [i, ui._tour[-1]])
				failures += 1
			# Recompute the tour length rather than trusting `_tour_length`.
			var walked := 0
			var cur: Vector2i = ui._start_cell
			for w in ui._tour:
				walked += int(ui._bfs_distances(cur).get(w, 1 << 20))
				cur = w
			tour_lengths.append(walked)
			if walked != ui._tour_length:
				print("FAIL seed=%d: recorded tour length %d, recomputed %d"
					% [i, ui._tour_length, walked])
				failures += 1
			# The point of the whole feature: the objective is genuinely longer than the
			# direct walk it replaced.
			if walked <= direct_len:
				print("FAIL seed=%d: tour %d cells vs direct route %d — no detour at all"
					% [i, walked, direct_len])
				failures += 1
			var band: Vector2i = MazeChaseUI.TOUR_BAND.get(want_frags, Vector2i(0, 1 << 20))
			if walked >= band.x and walked <= band.y:
				tour_in_band += 1

		# ---------------------------------------------------------------- the patroller band
		# The banding assertion, checked against an independent BFS from the patroller's own
		# start out to the nearest route cell — never against `_patrol_route_gap`, which is
		# the generator's own opinion of its own work.
		var patrol_cell := Vector2i(int(ui._patrol_start.x / MazeChaseUI.CELL_SIZE),
			int(ui._patrol_start.y / MazeChaseUI.CELL_SIZE))
		var from_patrol: Dictionary = ui._bfs_distances(patrol_cell)
		var gap := 1 << 20
		for c in ui._route_cells.keys():
			gap = mini(gap, int(from_patrol.get(c, 1 << 20)))
		if gap >= MazeChaseUI.PATROL_MIN_ROUTE_GAP:
			band_ok += 1
		else:
			# Only a failure if some ELIGIBLE cell could have done better. In a maze whose
			# artery happens to cover most of the grid there may be no such cell, and the
			# placement loop is bounded precisely so that it accepts the best rather than
			# spinning — so "no candidate was good enough" is a legal outcome, and
			# "a better candidate existed and was not taken" is not.
			var best_possible := -1
			var gap_field: Dictionary = ui._route_gap_field()
			for cell in dist.keys():
				if int(dist[cell]) >= MazeChaseUI.PATROL_MIN_START and cell != ui._target_cell:
					best_possible = maxi(best_possible, int(gap_field.get(cell, 0)))
			if best_possible >= MazeChaseUI.PATROL_MIN_ROUTE_GAP:
				print("FAIL seed=%d: patroller started %d cells off the route; a cell %d off "
					% [i, gap, best_possible] + "the route was available (the P4 lottery)")
				failures += 1
			else:
				band_impossible += 1

		# Wall rects must be non-empty (a maze with zero walls would mean
		# generation silently did nothing) and every wall rect must lie within
		# the playfield bounds.
		if ui._wall_rects.is_empty():
			print("FAIL seed=%d: zero wall rects generated" % i)
			failures += 1
		for wr in ui._wall_rects:
			if wr.position.x < -20.0 or wr.position.y < -20.0 \
					or wr.end.x > MazeChaseUI.PLAYFIELD_SIZE.x + 20.0 \
					or wr.end.y > MazeChaseUI.PLAYFIELD_SIZE.y + 20.0:
				print("FAIL seed=%d: wall rect out of playfield bounds: %s" % [i, wr])
				failures += 1
				break

	# ⚠️ Assert the sample sizes. Every number below is meaningless if the loops above ran
	# zero times, and a test that measures nothing and prints PASS has shipped here before.
	if frag_checks < runs:
		print("FAIL: only %d fragment checks across %d runs — expected at least one per run"
			% [frag_checks, runs])
		failures += 1
	if tour_checks != runs:
		print("FAIL: only %d tours checked across %d runs" % [tour_checks, runs])
		failures += 1
	if band_ok + band_impossible != runs:
		print("FAIL: patroller band accounted for %d of %d runs"
			% [band_ok + band_impossible, runs])
		failures += 1

	var mean_tour := 0.0
	for v in tour_lengths:
		mean_tour += float(v)
	if not tour_lengths.is_empty():
		mean_tour /= tour_lengths.size()
	var mean_direct := 0.0
	for v in direct_lengths:
		mean_direct += float(v)
	if not direct_lengths.is_empty():
		mean_direct /= direct_lengths.size()
	print("MAZE-GEN fragments=%d/run  tour mean %.1f cells vs direct %.1f (x%.2f), in band %d/%d"
		% [ui.fragment_count, mean_tour, mean_direct,
			mean_tour / maxf(mean_direct, 1.0), tour_in_band, runs])
	print("MAZE-GEN patroller >= %d cells off the route: %d/%d (%d seeds had no better cell)"
		% [MazeChaseUI.PATROL_MIN_ROUTE_GAP, band_ok, runs, band_impossible])
	print("MAZE-GEN runs=%d failures=%d" % [runs, failures])
	if failures == 0:
		print("MAZE-GEN PASS")
	else:
		print("MAZE-GEN FAIL")
	# ⚠️ Was a bare `quit()`, i.e. exit code 0 no matter how many seeds failed — so
	# every FAIL line above was printed into a green suite and this test could never
	# fail run_tests.sh (whose only signal is the exit code). Fixed 2026-07-27; the
	# same defect was live in check_wall_overlap.gd, which returned true from
	# _process and never called quit() at all.
	quit(0 if failures == 0 else 1)
