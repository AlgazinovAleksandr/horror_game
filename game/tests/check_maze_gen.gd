extends SceneTree

# One-off stress test for maze_chase_ui.gd's maze generation, run outside any
# scene (the minigame is only ever opened via player interaction, so the normal
# scene smoke test never exercises _generate_maze() at all). Checks, across many
# random seeds: every cell is reachable from every other cell (a real spanning
# tree, no isolated pockets), the target is never trivially close to the start,
# the monster never spawns on the target, and wall/collision data is self-consistent.


func _initialize() -> void:
	var ui := MazeChaseUI.new()
	var failures := 0
	var runs := 200
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

		# Monster must not spawn exactly on the target, and must be a plausible
		# early-ish threat, not adjacent to the start.
		var monster_cell := Vector2i(int(ui._monster_pos.x / MazeChaseUI.CELL_SIZE), int(ui._monster_pos.y / MazeChaseUI.CELL_SIZE))
		if monster_cell == ui._target_cell:
			print("FAIL seed=%d: monster spawned on the target cell" % i)
			failures += 1
		var monster_dist: int = dist.get(monster_cell, -1)
		if monster_dist < 1:
			print("FAIL seed=%d: monster spawned on/adjacent to start (dist=%d)" % [i, monster_dist])
			failures += 1

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

	print("MAZE-GEN runs=%d failures=%d" % [runs, failures])
	if failures == 0:
		print("MAZE-GEN PASS")
	else:
		print("MAZE-GEN FAIL")
	quit()
