extends CanvasLayer
class_name MazeChaseUI

# The House map-and-chase minigame (new feature). A fresh maze (randomized DFS,
# never memorizable) is generated every time it's opened; the player drags their
# icon toward the target with the mouse while a monster icon hunts them. Reaching
# the target wins; the monster catching the player fails (house_map_prop.gd owns
# the fail consequence). Panic rises the whole time it's open — a flat drip plus a
# proximity term — via the same "a paused UI's own _process still calls
# player.add_panic() every frame" idiom note_ui.gd already uses for trap notes.
#
# Pause convention matches combination_lock.gd/note_ui.gd exactly: get_tree().paused
# = true while open, MOUSE_MODE_VISIBLE, reversed on close — this freezes the whole
# 3D game for free, no changes needed to player.gd or any creature script. Because
# this UI's own add_panic() call can itself push panic to PANIC_MAX and trigger a
# fatal Screamer.trigger() mid-minigame, the Issue-9 pause-race guard below is not
# optional — copied verbatim from the same lesson in note_ui.gd/combination_lock.gd.

signal won
signal caught

const TEX := "res://assets/textures/level_2_house/"

# ---------------------------------------------------------------- maze grid
const GRID_COLS := 10
const GRID_ROWS := 8
const CELL_SIZE := 96.0
const WALL_THICKNESS := 8.0
const PLAYFIELD_SIZE := Vector2(GRID_COLS * CELL_SIZE, GRID_ROWS * CELL_SIZE)  # 960x768

# ---------------------------------------------------------------- icons
const ICON_DISPLAY_SIZE := 64.0  # was 40 — playtest asked for bigger, more legible marks
const ICON_HALF_EXTENT := 14.0
const WIN_RADIUS := 28.0
const CATCH_RADIUS := 20.0

# ---------------------------------------------------------------- drag physics
# Both the ease rate AND the speed cap degrade together as panic rises — that
# combination is what sells "harder to steer under pressure," not just "slower."
const SPRING_K_BASE := 9.0
const SPRING_K_PANIC := 3.0
const PLAYER_MAX_SPEED := 240.0
const PLAYER_MIN_SPEED := 100.0

# ---------------------------------------------------------------- monster
# Still under the player's worst-case (panic-1.0) speed floor of 100, so a player who
# keeps moving can always outpace it — but it no longer wastes that speed walking into
# walls. See _tick_monster(): it follows the actual corridor route now.
#
# ⚠️ BACKLOG #14: "the monster in the maze is too stupid. It can basically kill the
# player only at the beginning." It was not a speed problem. It steered by a raw
# Euclidean beeline toward the player, and the maze is a randomized-DFS spanning tree —
# a PERFECT maze, no loops — where the corridor route between two cells is routinely
# 5-15x the straight-line distance. So the beeline pointed into a wall most of the
# time, the per-axis wall-slide sent it sideways down whatever dead end the tangent
# happened to face, and once the player left the starting neighbourhood it could never
# close again. The anti-stuck dodge never fired either: sliding along a wall still
# counts as "moving", so _stuck_timer reset on every sample.
#
# The fix is not more speed. _bfs_distances() — exact, and already written — was being
# used only at generation time to pick the target and the monster's spawn cell. Running
# it from the PLAYER's cell gives a perfect distance field over the whole maze, and
# stepping downhill through it is optimal pursuit for a fraction of a millisecond per
# recompute (80 cells).
# ⚠️ 88 -> 132 -> 172, both raises on the user's call across two playtests. For scale, the
# dragged icon runs at PLAYER_MAX_SPEED 240 with full nerve and degrades to PLAYER_MIN_SPEED
# 100 at high panic — so at 172 the monster is comfortably faster than a panicking player,
# which is the point: hesitating is what kills you.
#
# Measured each time with tests/check_maze_chase.gd (40 seeds), and the numbers are the reason
# it was safe to go this far:
#     88  — stationary player caught 40/40; moving player wins 37/40
#     132 — caught in 3.6 s; hunted down 9.4 s after stopping; still 37/40
#     172 — caught in 3.5 s; hunted down 5.2 s after stopping; still 37/40
# The escape rate has not moved at all; what changed is how quickly a mistake is punished.
# ⚠️ Do not raise it again without re-running that test. This minigame once killed 12 players
# in 40 for an unrelated reason.
#
# ⚠️ 37/40 WAS the line that said it is still a game; it is 26/40 now, and deliberately so.
# The 2026-08-15 pass braided the maze, added the patroller below and added snares, and the
# user chose to let the level get harder rather than hold the old rate. The isolation
# numbers behind that figure are in check_maze_chase.gd, next to the asserted floor. This
# speed was NOT touched as part of it.
const MONSTER_SPEED := 172.0
const MONSTER_START_DELAY := 3.0  # frozen this long after open() before it hunts

# ---------------------------------------------------------------- panic
# Cut hard after playtest ("give me more time to pass the map minigame") —
# repeated deaths, on top of the head-start bug fixed above. Original values
# (0.9 / 260 / 5.0) were calibrated for a monster that started well away from
# the player; now that it spawns adjacent (per request), the average distance
# through a whole run is much smaller, so the same rates were far more punishing
# in practice than intended.
const MAZE_DRIP_RATE := 0.4
const PROXIMITY_RANGE := 160.0
const PROXIMITY_MAX_RATE := 2.5

var _ui_open: bool = false
var _focus_lost_clear: bool = false

var _cells: Array = []               # flat GRID_COLS*GRID_ROWS array of {n,e,s,w:bool}
var _wall_rects: Array[Rect2] = []
var _start_cell: Vector2i
var _target_cell: Vector2i

var _player_pos: Vector2
var _monster_pos: Vector2
var _target_pos: Vector2

var _monster_start_timer: float = 0.0

# Corridor-distance field from the player's current cell, and the cell it was built
# for. Rebuilt only when the player crosses into a new cell — see _pursuit_direction().
var _flow: Dictionary = {}
var _flow_origin: Vector2i = Vector2i(-1, -1)

var _root: Control
var _playfield: Control
var _wall_nodes: Array[ColorRect] = []
var _walls_container: Control
var _player_icon: Control
var _monster_icon: Control
var _patrol_icon: Control
var _target_icon: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 65  # above combination_lock's 60 and note_ui's 50
	_build_ui()


# ---------------------------------------------------------------- open/close

func open() -> void:
	_generate_maze()
	_reset_positions()
	_rebuild_wall_visuals()
	_rebuild_snare_visuals()
	_update_visual_positions()
	_start_chase_audio()
	_ui_open = true
	_focus_lost_clear = false
	_root.visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close() -> void:
	_ui_open = false
	_root.visible = false
	_stop_chase_audio()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# A screamer firing while we're open unpauses/reloads the scene out from under
# this UI — self-clear silently rather than trying to resume (Issue 9).
func _hide_after_external_unpause() -> void:
	_ui_open = false
	_root.visible = false
	# ⚠️ Stop the music HERE too, not only in _close(). This path is the one a screamer
	# takes, and a chase loop left running would play on over the reloaded scene.
	_stop_chase_audio()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focus_lost_clear = true


func _unhandled_input(event: InputEvent) -> void:
	if not _ui_open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


# ---------------------------------------------------------------- main loop

func _process(delta: float) -> void:
	if _ui_open and not get_tree().paused:
		_hide_after_external_unpause()
		return
	if not _ui_open:
		return

	var p := _player()
	var panic_ratio: float = p.get_panic_ratio() if p and p.has_method("get_panic_ratio") else 0.0

	var mouse_down: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _focus_lost_clear
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_focus_lost_clear = false  # a genuine release clears the focus-loss override
	if mouse_down:
		var cursor_local: Vector2 = get_viewport().get_mouse_position() - _playfield.global_position
		var k: float = lerpf(SPRING_K_BASE, SPRING_K_PANIC, panic_ratio)
		var ease_t: float = 1.0 - exp(-k * delta)
		var step: Vector2 = (cursor_local - _player_pos) * ease_t
		var max_step: float = lerpf(PLAYER_MAX_SPEED, PLAYER_MIN_SPEED, panic_ratio) * delta
		if step.length() > max_step and step.length() > 0.0:
			step = step.normalized() * max_step
		_player_pos = _resolve_wall_slide(_player_pos, _player_pos + step, ICON_HALF_EXTENT)

	# A snare holds you where you are. Movement above still ran, so the position is
	# rolled back — the drag keeps fighting and simply achieves nothing, which reads as
	# being caught on something rather than as the controls dying.
	if _snare_hold > 0.0:
		_snare_hold -= delta
		_player_pos = _snared_at

	var in_grace: bool = _monster_start_timer > 0.0
	if in_grace:
		_monster_start_timer -= delta
	else:
		_tick_monster(delta)
		_tick_patroller(delta)

	_check_snares(p)

	var dist_to_monster: float = _monster_pos.distance_to(_player_pos)
	dist_to_monster = minf(dist_to_monster, _patrol_pos.distance_to(_player_pos))

	# Playtest: moving the monster to spawn right next to the player (per your
	# request) meant the proximity term was already near its max from frame one
	# — the "head start" froze the monster's movement but panic climbed the whole
	# time anyway, defeating the point of a grace period. No panic at all (drip
	# OR proximity) while the monster is still frozen — a real head start now.
	if not in_grace:
		var proximity_rate := 0.0
		if dist_to_monster < PROXIMITY_RANGE:
			var ratio: float = 1.0 - dist_to_monster / PROXIMITY_RANGE
			proximity_rate = PROXIMITY_MAX_RATE * ratio * ratio
		if p and p.has_method("add_panic"):
			p.add_panic(delta * (MAZE_DRIP_RATE + proximity_rate))

	_update_visual_positions()

	if _player_pos.distance_to(_target_pos) <= WIN_RADIUS:
		_close()
		won.emit()
		return
	if dist_to_monster <= CATCH_RADIUS:
		_close()
		caught.emit()
		return


func _player() -> CharacterBody3D:
	return get_tree().current_scene.get_node_or_null("Player") as CharacterBody3D


# ---------------------------------------------------------------- the patroller
#
# ⭐ The SECOND monster, and deliberately not a second copy of the first (2026-08-15).
#
# Two identical hunters would double the pressure without adding a decision. This one
# walks a circuit and only gives chase when you come near it, which is what makes ROUTE
# CHOICE matter — and route choice is the entire reason the maze is now braided. The
# hunter punishes standing still; the patroller punishes taking the obvious line.
#
# It is slower than the hunter on purpose: meeting it should be a mistake you can still
# walk out of, not a second unavoidable death.
const PATROL_SPEED := 86.0
const PATROL_AGGRO := 112.0     # px; inside this it drops the circuit and comes for you
const PATROL_CALM := 240.0      # px; outside this it gives up and resumes patrolling
const PATROL_MIN_START := 7     # cells of BFS distance from the player's start

var _patrol_pos := Vector2.ZERO
var _patrol_target := Vector2i.ZERO
var _patrol_chasing := false
var _patrol_flow: Dictionary = {}
var _patrol_flow_origin := Vector2i(-99, -99)


func _place_patroller(dist: Dictionary) -> void:
	# Somewhere genuinely elsewhere — a patroller that starts on top of the player is
	# just a second hunter with extra steps.
	var far: Array[Vector2i] = []
	for cell in dist.keys():
		if int(dist[cell]) >= PATROL_MIN_START and cell != _target_cell:
			far.append(cell)
	var start: Vector2i = far[randi() % far.size()] if not far.is_empty() else _target_cell
	_patrol_pos = _cell_center(start)
	_patrol_chasing = false
	_patrol_flow.clear()
	_patrol_flow_origin = Vector2i(-99, -99)
	_pick_patrol_target()


# ⚠️ The circuit avoids the player's likely route (2026-08-15). Measured across 40 seeds:
# a patroller wandering to uniformly-random cells dropped the escape rate from 34/40 to
# 25/40 on its own, BEFORE it ever gave chase — it was simply standing in the corridor the
# player had to walk. That is not a second threat, it is a roadblock, and it is the exact
# failure `_place_monster()` already guards against for the hunter.
#
# Off the artery, the patroller is something you MEET by choosing a greedy line or a wrong
# turn — which is the decision the braiding exists to offer.
func _pick_patrol_target() -> void:
	var options: Array[Vector2i] = []
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var c := Vector2i(col, row)
			if not _route_cells.has(c):
				options.append(c)
	if options.is_empty():
		_patrol_target = Vector2i(randi() % GRID_COLS, randi() % GRID_ROWS)
		return
	_patrol_target = options[randi() % options.size()]


func _tick_patroller(delta: float) -> void:
	var to_player: float = _patrol_pos.distance_to(_player_pos)
	# Hysteresis, or it flickers between states on the aggro boundary and jitters in place.
	if _patrol_chasing:
		if to_player > PATROL_CALM:
			_patrol_chasing = false
			_pick_patrol_target()
	elif to_player <= PATROL_AGGRO:
		_patrol_chasing = true

	var goal: Vector2i = _cell_at(_player_pos) if _patrol_chasing else _patrol_target
	if not _patrol_chasing and _cell_at(_patrol_pos) == _patrol_target:
		_pick_patrol_target()
		goal = _patrol_target

	# Same BFS-downhill steering the hunter uses — walking the ACTUAL corridors. A beeline
	# in a maze points into a wall most of the time (BACKLOG #14, measured).
	if goal != _patrol_flow_origin:
		_patrol_flow = _bfs_distances(goal)
		_patrol_flow_origin = goal
	var here: Vector2i = _cell_at(_patrol_pos)
	var best: Vector2i = here
	var best_d: int = int(_patrol_flow.get(here, 9999))
	for n in _open_neighbours(here):
		var nd: int = int(_patrol_flow.get(n, 9999))
		if nd < best_d:
			best_d = nd
			best = n
	var aim: Vector2 = _cell_center(best) if best != here else _player_pos
	var dir: Vector2 = (aim - _patrol_pos)
	if dir.length() < 0.01:
		return
	var speed: float = PATROL_SPEED * (1.05 if _patrol_chasing else 1.0)
	_patrol_pos = _resolve_wall_slide(
		_patrol_pos, _patrol_pos + dir.normalized() * speed * delta, ICON_HALF_EXTENT)


# ---------------------------------------------------------------- snares
#
# ⭐ Traps that HOLD you, never kill you (2026-08-15, user's choice).
#
# The danger is where being held leaves you, not the trap itself — the same logic the real
# beartrap uses (`beartrap.gd`: 15 panic and an escape, not a death). The maze already has
# one fail state; stacking a second on a minigame you can only retry by walking back across
# the House would be a lot of punishment for one wrong pixel.
#
# ⚠️ Placed OFF the start-to-target route. A snare on the only line is a tax every player
# pays; a snare beside it is a decision about how greedy a corner to cut. The braiding is
# what makes "beside it" exist at all.
const SNARE_COUNT := 5
const SNARE_RADIUS := 26.0
const SNARE_HOLD := 1.2
const SNARE_PANIC := 3.0

var _snares: Array[Vector2] = []
var _snare_hold: float = 0.0
var _snared_at := Vector2.ZERO
var _snare_nodes: Array[Control] = []
var _route_cells: Dictionary = {}   # cells on a shortest start->mark path


# Every cell on a shortest path from the start to the mark — the line the player is most
# likely to walk. Both the snares and the patroller's circuit are placed relative to it.
func _compute_route(dist: Dictionary) -> void:
	_route_cells.clear()
	var walk: Vector2i = _target_cell
	var guard := 0
	while walk != _start_cell and guard < GRID_COLS * GRID_ROWS:
		guard += 1
		_route_cells[walk] = true
		var here: int = int(dist.get(walk, 0))
		for n in _open_neighbours(walk):
			if int(dist.get(n, 9999)) == here - 1:
				walk = n
				break
	_route_cells[_start_cell] = true


func _place_snares(dist: Dictionary) -> void:
	_snares.clear()
	_snare_hold = 0.0
	var on_route: Dictionary = _route_cells

	var candidates: Array[Vector2i] = []
	for cell in dist.keys():
		if on_route.has(cell) or cell == _target_cell or cell == _start_cell:
			continue
		if int(dist[cell]) >= 2:
			candidates.append(cell)
	candidates.shuffle()
	for i in range(min(SNARE_COUNT, candidates.size())):
		_snares.append(_cell_center(candidates[i]))


func _check_snares(p: Node) -> void:
	if _snare_hold > 0.0:
		return
	for s in _snares:
		if s.distance_to(_player_pos) <= SNARE_RADIUS:
			_snares.erase(s)          # one-shot: a snare you already sprang is spent
			_snare_hold = SNARE_HOLD
			_snared_at = _player_pos
			if p and p.has_method("add_panic"):
				p.add_panic(SNARE_PANIC)
			_rebuild_snare_visuals()
			return


# ---------------------------------------------------------------- monster AI

func _tick_monster(delta: float) -> void:
	var dir := _pursuit_direction()
	if dir.length() > 0.01:
		var candidate: Vector2 = _monster_pos + dir * MONSTER_SPEED * delta
		# Kept as a safety net only. With corridor following the monster should never
		# be driving into a wall, but a diagonal cut across a junction can still clip a
		# corner, and sliding is nicer there than stopping dead.
		_monster_pos = _resolve_wall_slide(_monster_pos, candidate, ICON_HALF_EXTENT)


# Steer along the maze's actual corridors instead of straight at the player.
#
# Recomputes the BFS distance field from the PLAYER's cell whenever the player changes
# cell (not every frame — 80 cells is cheap, but there is no reason to burn it), then
# walks downhill: of the neighbours reachable from the monster's own cell, head for the
# one strictly closer to the player. Aim at that cell's CENTRE, which keeps the icon off
# the walls through corners without any special-casing.
#
# In the player's own cell, fall back to the beeline — that is the one place where
# straight-line and corridor distance agree, and it is what makes the final approach
# feel like a lunge rather than a grid step.
func _pursuit_direction() -> Vector2:
	var monster_cell := _cell_at(_monster_pos)
	var player_cell := _cell_at(_player_pos)
	if monster_cell == player_cell:
		return (_player_pos - _monster_pos).normalized()

	if player_cell != _flow_origin or _flow.is_empty():
		_flow_origin = player_cell
		_flow = _bfs_distances(player_cell)

	if not _flow.has(monster_cell):
		# Off the grid (shouldn't happen) — beeline rather than freeze.
		return (_player_pos - _monster_pos).normalized()

	var best_cell := monster_cell
	var best_dist: int = _flow[monster_cell]
	for step in _open_neighbours(monster_cell):
		if _flow.has(step) and int(_flow[step]) < best_dist:
			best_dist = int(_flow[step])
			best_cell = step
	if best_cell == monster_cell:
		return (_player_pos - _monster_pos).normalized()
	return (_cell_center(best_cell) - _monster_pos).normalized()


func _cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(pos.x / CELL_SIZE), 0, GRID_COLS - 1),
		clampi(int(pos.y / CELL_SIZE), 0, GRID_ROWS - 1))


# Neighbouring cells this one is NOT walled off from. Mirrors the wall bookkeeping in
# _bfs_distances(), so the monster can only use openings the player can also use.
func _open_neighbours(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c: Dictionary = _cells[_idx(cell)]
	if not c["n"]:
		out.append(cell + Vector2i(0, -1))
	if not c["s"]:
		out.append(cell + Vector2i(0, 1))
	if not c["e"]:
		out.append(cell + Vector2i(1, 0))
	if not c["w"]:
		out.append(cell + Vector2i(-1, 0))
	return out


# ---------------------------------------------------------------- collision

func _resolve_wall_slide(from: Vector2, to: Vector2, half_extent: float) -> Vector2:
	var pos := from
	var try_x := Vector2(to.x, pos.y)
	if not _rect_hits_wall(try_x, half_extent):
		pos.x = to.x
	var try_y := Vector2(pos.x, to.y)
	if not _rect_hits_wall(try_y, half_extent):
		pos.y = to.y
	return pos


func _rect_hits_wall(center: Vector2, half_extent: float) -> bool:
	var r := Rect2(center - Vector2(half_extent, half_extent), Vector2(half_extent, half_extent) * 2.0)
	for wr in _wall_rects:
		if r.intersects(wr):
			return true
	return false


# ---------------------------------------------------------------- maze generation

func _idx(cell: Vector2i) -> int:
	return cell.y * GRID_COLS + cell.x


func _generate_maze() -> void:
	_cells.clear()
	for i in range(GRID_COLS * GRID_ROWS):
		_cells.append({"n": true, "e": true, "s": true, "w": true, "visited": false})

	var stack: Array[Vector2i] = []
	var origin := Vector2i(0, 0)
	_cells[_idx(origin)]["visited"] = true
	stack.append(origin)
	while not stack.is_empty():
		var cur: Vector2i = stack[-1]
		var neighbors := _unvisited_neighbors(cur)
		if neighbors.is_empty():
			stack.pop_back()
			continue
		var next: Vector2i = neighbors[randi() % neighbors.size()]
		_remove_wall(cur, next)
		_cells[_idx(next)]["visited"] = true
		stack.append(next)

	_braid()

	_start_cell = Vector2i(0, GRID_ROWS / 2)
	var dist := _bfs_distances(_start_cell)

	_target_cell = _start_cell
	var max_d := -1
	for cell in dist.keys():
		if dist[cell] > max_d:
			max_d = dist[cell]
			_target_cell = cell

	_wall_rects.clear()
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var cell: Dictionary = _cells[_idx(Vector2i(col, row))]
			var cx: float = col * CELL_SIZE
			var cy: float = row * CELL_SIZE
			if cell["n"]:
				_wall_rects.append(Rect2(cx - WALL_THICKNESS / 2.0, cy - WALL_THICKNESS / 2.0,
					CELL_SIZE + WALL_THICKNESS, WALL_THICKNESS))
			if cell["w"]:
				_wall_rects.append(Rect2(cx - WALL_THICKNESS / 2.0, cy - WALL_THICKNESS / 2.0,
					WALL_THICKNESS, CELL_SIZE + WALL_THICKNESS))
			if row == GRID_ROWS - 1 and cell["s"]:
				_wall_rects.append(Rect2(cx - WALL_THICKNESS / 2.0, cy + CELL_SIZE - WALL_THICKNESS / 2.0,
					CELL_SIZE + WALL_THICKNESS, WALL_THICKNESS))
			if col == GRID_COLS - 1 and cell["e"]:
				_wall_rects.append(Rect2(cx + CELL_SIZE - WALL_THICKNESS / 2.0, cy - WALL_THICKNESS / 2.0,
					WALL_THICKNESS, CELL_SIZE + WALL_THICKNESS))

	_place_monster(dist)
	_compute_route(dist)
	_place_patroller(dist)
	_place_snares(dist)


# ⭐ BRAID THE MAZE — knock extra walls out so it has LOOPS (2026-08-15).
#
# User report: "make more space so that you can actually bypass the monster when it is
# running towards you." In a randomized-DFS maze there is exactly ONE route between any two
# cells, so a monster coming down a corridor at you cannot be passed — not because it is
# fast, but because the topology forbids it. Widening corridors or enlarging the grid does
# not fix that; only cycles do.
#
# ⚠️ This project has already paid to learn it once. `dungeon_gen.gd` adds `ceil(0.25 * K)`
# extra edges to its spanning tree with the note: "The extra edges are NOT optional. A
# spanning tree is a perfect maze, and in one a corridor-following pursuer is unbeatable.
# `maze_chase_ui.gd` already cost this project 12 instant deaths in 40 to learn that." That
# was about monster PLACEMENT; this is the same lesson applied to the maze itself.
#
# Dead ends are the target: removing a wall from a dead end is what turns a trap into a
# through-route, which is exactly the space the player was asking for.
const BRAID_FRACTION := 0.55   # share of dead ends opened into loops

func _braid() -> void:
	var dead_ends: Array[Vector2i] = []
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var c := Vector2i(col, row)
			if _open_neighbours(c).size() <= 1:
				dead_ends.append(c)
	dead_ends.shuffle()
	var quota := int(ceil(dead_ends.size() * BRAID_FRACTION))
	for i in range(min(quota, dead_ends.size())):
		var cell: Vector2i = dead_ends[i]
		# Candidate walls that lead to a real neighbour and are still closed.
		var options: Array[Vector2i] = []
		var open_now: Array[Vector2i] = _open_neighbours(cell)
		for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var n: Vector2i = cell + d
			if n.x < 0 or n.y < 0 or n.x >= GRID_COLS or n.y >= GRID_ROWS:
				continue
			if not open_now.has(n):
				options.append(n)
		if options.is_empty():
			continue
		_remove_wall(cell, options[randi() % options.size()])


func _unvisited_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var n: Vector2i = cell + d
		if n.x >= 0 and n.x < GRID_COLS and n.y >= 0 and n.y < GRID_ROWS:
			if not _cells[_idx(n)]["visited"]:
				result.append(n)
	return result


func _remove_wall(a: Vector2i, b: Vector2i) -> void:
	var d := b - a
	if d == Vector2i(0, -1):
		_cells[_idx(a)]["n"] = false
		_cells[_idx(b)]["s"] = false
	elif d == Vector2i(0, 1):
		_cells[_idx(a)]["s"] = false
		_cells[_idx(b)]["n"] = false
	elif d == Vector2i(1, 0):
		_cells[_idx(a)]["e"] = false
		_cells[_idx(b)]["w"] = false
	elif d == Vector2i(-1, 0):
		_cells[_idx(a)]["w"] = false
		_cells[_idx(b)]["e"] = false


func _bfs_distances(start: Vector2i) -> Dictionary:
	var dist := {start: 0}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var cd: int = dist[cur]
		var cell: Dictionary = _cells[_idx(cur)]
		var moves: Array[Vector2i] = []
		if not cell["n"]:
			moves.append(Vector2i(0, -1))
		if not cell["s"]:
			moves.append(Vector2i(0, 1))
		if not cell["e"]:
			moves.append(Vector2i(1, 0))
		if not cell["w"]:
			moves.append(Vector2i(-1, 0))
		for d in moves:
			var n: Vector2i = cur + d
			if not dist.has(n):
				dist[n] = cd + 1
				queue.append(n)
	return dist


# Playtest redesign: the monster now starts right next to the player (not
# roaming elsewhere in the maze) and holds still for MONSTER_START_DELAY before
# it begins hunting — "catches you if you get stuck," not "avoid its territory."
# Prefer a cell exactly 1 step from start; widen the search if the maze's
# branching happens to leave none (rare but possible in a small maze).
func _place_monster(dist: Dictionary) -> void:
	# ⚠️ Never on the FIRST STEP of the route to the target, if that can be avoided.
	# The maze is a spanning tree, so there is exactly ONE route from start to target
	# and exactly one neighbour of the start cell that lies on it. Parking the monster
	# there turns a 1.6-cell-wide corridor into a roadblock the player cannot go round
	# — and it went unnoticed for as long as the monster jammed itself on walls and
	# drifted off harmlessly. With corridor following (BACKLOG #14) it stands its
	# ground, and a measured 12 of 40 seeds became a walk-straight-into-it death.
	# Adjacency is the point of this placement; sitting in the doorway is not.
	var to_target := _bfs_distances(_target_cell)
	var start_to_target: int = int(to_target.get(_start_cell, 1 << 30))

	var off_path: Array[Vector2i] = []
	var on_path: Array[Vector2i] = []
	for cell in dist.keys():
		if cell == _target_cell or dist[cell] != 1:
			continue
		if int(to_target.get(cell, 1 << 30)) < start_to_target:
			on_path.append(cell)
		else:
			off_path.append(cell)

	var candidates := off_path
	if candidates.is_empty():
		candidates = on_path          # start is a dead end — nowhere else to stand
	if candidates.is_empty():
		for cell in dist.keys():
			if cell != _target_cell and dist[cell] >= 1 and dist[cell] <= 2:
				candidates.append(cell)
	var monster_cell: Vector2i = candidates[randi() % candidates.size()] if not candidates.is_empty() else _start_cell
	_monster_pos = _cell_center(monster_cell)


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL_SIZE + CELL_SIZE / 2.0, cell.y * CELL_SIZE + CELL_SIZE / 2.0)


func _reset_positions() -> void:
	_player_pos = _cell_center(_start_cell)
	_target_pos = _cell_center(_target_cell)
	_monster_start_timer = MONSTER_START_DELAY
	_flow.clear()
	_flow_origin = Vector2i(-1, -1)
	_snare_hold = 0.0


# ---------------------------------------------------------------- UI construction

# Skeleton avoids Issue 4 (PRESET_CENTER anchors a node's top-left corner to
# screen centre, not the node's own centre): Control full-rect -> ColorRect
# backdrop + CenterContainer full-rect siblings -> fixed-size playfield as the
# CenterContainer's child. Anything that MOVES (icons) is positioned via raw
# .position on the playfield, never anchors.
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.75)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_playfield = Control.new()
	_playfield.custom_minimum_size = PLAYFIELD_SIZE
	_playfield.size = PLAYFIELD_SIZE
	_playfield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_playfield)

	var bg_path := TEX + "house_map_maze_bg.png"
	if ResourceLoader.exists(bg_path):
		var bg := TextureRect.new()
		bg.texture = load(bg_path)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.size = PLAYFIELD_SIZE
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_playfield.add_child(bg)
	else:
		var bg_fallback := ColorRect.new()
		bg_fallback.color = Color(0.78, 0.7, 0.55)
		bg_fallback.size = PLAYFIELD_SIZE
		bg_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_playfield.add_child(bg_fallback)

	# Own container for the wall rects, added ONCE here — _rebuild_wall_visuals()
	# only ever adds/removes children INSIDE this container, never directly to
	# _playfield. Control nodes paint in child order (later = on top); walls used
	# to be rebuilt (and re-added) on every open(), landing AFTER the icons below
	# and painting over them every single attempt — the confirmed cause of the
	# target being completely invisible in playtest.
	_walls_container = Control.new()
	_walls_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_playfield.add_child(_walls_container)

	# ⚠️ The caption goes on _root, NOT on `center`. A CenterContainer centres EVERY
	# child independently and overwrites its anchors/offsets/position during layout,
	# so a Label added here used to have both its PRESET_CENTER_TOP and its
	# position.y = -48 silently discarded — it landed stacked dead-centre ON the
	# parchment, over the maze (playtest capture #3). _root is a plain Control, so
	# presets survive. Anchored off the vertical centre by half the playfield so it
	# sits just above the map at any viewport size.
	var caption := Label.new()
	caption.text = "Drag to the mark. Don't get caught."
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	_outline(caption, 6)
	caption.anchor_left = 0.0
	caption.anchor_right = 1.0
	caption.anchor_top = 0.5
	caption.anchor_bottom = 0.5
	caption.offset_left = 0.0
	caption.offset_right = 0.0
	caption.offset_top = -PLAYFIELD_SIZE.y / 2.0 - 46.0
	caption.offset_bottom = -PLAYFIELD_SIZE.y / 2.0 - 12.0
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(caption)

	_target_icon = _make_icon(TEX + "house_map_target_icon.png", Color(1.0, 0.85, 0.25))
	_player_icon = _make_icon(TEX + "house_map_player_icon.png", Color(0.45, 0.85, 1.0))
	_monster_icon = _make_icon(TEX + "house_map_monster_icon.png", Color(1.0, 0.25, 0.18))
	# The patroller wears the same art in a different colour — it must read as "another one
	# of those", not as a new species, because the thing the player has to learn is its
	# BEHAVIOUR. Amber against the hunter's red.
	_patrol_icon = _make_icon(TEX + "house_map_monster_icon.png", Color(1.0, 0.60, 0.12))


# The project's universal legibility trick, same as ScreenText._outline(): this is
# the ONLY overlay text in the game that had neither an outline, a shadow, nor a
# dark panel behind it — over cream parchment that reads as no text at all.
func _outline(lbl: Label, size: int) -> void:
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", size)


# A flat rounded disc. Godot has no circle primitive for Control nodes, but a Panel
# with a StyleBoxFlat whose corner radius is half its size is one.
func _disc(diameter: float, color: Color) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size = Vector2(diameter, diameter)
	p.position = Vector2(ICON_DISPLAY_SIZE - diameter, ICON_DISPLAY_SIZE - diameter) / 2.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	var r := int(diameter / 2.0)
	sb.corner_radius_top_left = r
	sb.corner_radius_top_right = r
	sb.corner_radius_bottom_left = r
	sb.corner_radius_bottom_right = r
	p.add_theme_stylebox_override("panel", sb)
	return p


# Three layers, because the source art alone cannot carry this. Each icon PNG is a
# 1024x1024 canvas whose visible ink fills only ~30-40% of it, so at ICON_DISPLAY_SIZE
# the actual mark is ~28 px of mid-brown (#6b4a2a-#8a5c30) sitting on cream parchment,
# beside wall rects of Color(0.32,0.22,0.12) — same hue family as both. Tinting via
# `modulate` cannot fix it either: modulate MULTIPLIES, and no multiplier turns brown
# into saturated blue. So the colour comes from a solid disc underneath and the art
# rides on top as dark detail:
#   1. dark halo   — separates the marker from the parchment
#   2. bright disc — the identity colour, sized to ICON_HALF_EXTENT so the marker is
#                    honest about its own hitbox (the 64 px art visually engulfs the
#                    player long before CATCH_RADIUS fires)
#   3. the ink     — modulated near-black so it reads as line work over the disc
func _make_icon(tex_path: String, marker_color: Color) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(ICON_DISPLAY_SIZE, ICON_DISPLAY_SIZE)

	holder.add_child(_disc(ICON_HALF_EXTENT * 2.0 + 8.0, Color(0.04, 0.03, 0.02, 0.9)))
	holder.add_child(_disc(ICON_HALF_EXTENT * 2.0, marker_color))

	if ResourceLoader.exists(tex_path):
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size = Vector2(ICON_DISPLAY_SIZE, ICON_DISPLAY_SIZE)
		icon.texture = load(tex_path)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.modulate = Color(0.16, 0.11, 0.06)
		holder.add_child(icon)

	_playfield.add_child(holder)
	return holder


func _rebuild_wall_visuals() -> void:
	for w in _wall_nodes:
		if is_instance_valid(w):
			w.queue_free()
	_wall_nodes.clear()
	for wr in _wall_rects:
		var rect := ColorRect.new()
		rect.color = Color(0.32, 0.22, 0.12, 0.85)
		rect.position = wr.position
		rect.size = wr.size
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_walls_container.add_child(rect)
		_wall_nodes.append(rect)


func _update_visual_positions() -> void:
	var half := Vector2(ICON_DISPLAY_SIZE, ICON_DISPLAY_SIZE) / 2.0
	_player_icon.position = _player_pos - half
	_monster_icon.position = _monster_pos - half
	_patrol_icon.position = _patrol_pos - half
	_target_icon.position = _target_pos - half


# Snares are drawn UNDER the icons, as small dark discs. They must be visible — a trap the
# player cannot see is not a decision, it is a dice roll (SCARY.md §8.11: never punish a
# scare the player could not have seen coming).
func _rebuild_snare_visuals() -> void:
	for n in _snare_nodes:
		n.queue_free()
	_snare_nodes.clear()
	for s in _snares:
		var disc := _disc(SNARE_RADIUS * 1.6, Color(0.12, 0.05, 0.03, 0.85))
		disc.position = s - Vector2(SNARE_RADIUS * 0.8, SNARE_RADIUS * 0.8)
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# ⚠️ Into the WALLS container, which is added once in _build_ui(). Adding to the
		# playfield instead would place them after the icons in the draw order and paint
		# over them — the confirmed cause of the target being invisible in a past playtest.
		_walls_container.add_child(disc)
		_snare_nodes.append(disc)


# ---------------------------------------------------------------- chase audio
#
# ⚠️ A plain AudioStreamPlayer (not 3D): this is a 2D overlay, there is nothing to pan
# around. Parented to this CanvasLayer so it inherits PROCESS_MODE_ALWAYS and keeps
# playing while the tree is paused — which it is, the whole time the map is open.
#
# ⚠️ Bus left unset, i.e. Master, matching `combination_lock.gd`'s buzz — the only other
# paused-UI sound in the game. A chase cue must not be duckable by a SilenceZone or a
# HoldBreath dip firing somewhere else.
#
# ⚠️ Looped in CODE. Every .wav.import in this project is loop_mode=0, so the stream never
# repeats itself; `finished -> play` is the house idiom. `tools/make_loop.py` trimmed the
# supplied file's fade-out and crossfaded the seam so the repeat is inaudible.
# ⚠️ Loaded BY PATH, not through `GameState.load_audio()`. `check_maze_gen.gd` instantiates
# this class by its class_name, which compiles this file before the autoloads are
# registered — so a bare `GameState` here is a COMPILE error that takes the test down with
# it, and the test then spins instead of failing. Same hazard `screenshot_maze_ui.gd`
# documents for naming game classes in a SceneTree script. The texture constants above are
# hardcoded for the same reason, so this matches the file's own convention.
const CHASE_PATH := "res://assets/audio/level_2_house/chase.wav"
const CHASE_VOLUME_DB := -6.0

var _chase_audio: AudioStreamPlayer


func _start_chase_audio() -> void:
	if _chase_audio == null:
		if not ResourceLoader.exists(CHASE_PATH):
			return
		var stream: AudioStream = load(CHASE_PATH)
		if stream == null:
			return
		_chase_audio = AudioStreamPlayer.new()
		_chase_audio.name = "ChaseAudio"
		_chase_audio.stream = stream
		_chase_audio.volume_db = CHASE_VOLUME_DB
		add_child(_chase_audio)
		_chase_audio.finished.connect(_chase_audio.play)
	_chase_audio.play()


func _stop_chase_audio() -> void:
	if _chase_audio and _chase_audio.playing:
		_chase_audio.stop()
