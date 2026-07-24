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
# Deliberately well under the player's worst-case (panic-1.0) speed floor of 100,
# so a player who plays cleanly can always outpace it.
const MONSTER_SPEED := 78.0
const STUCK_SAMPLE_INTERVAL := 0.3
const STUCK_MOVE_THRESHOLD := 6.0
const STUCK_TRIGGER_TIME := 1.2
const DODGE_TIME := 0.4
const DODGE_ANGLE_DEG := 70.0
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

var _stuck_timer: float = 0.0
var _stuck_check_timer: float = 0.0
var _stuck_check_pos: Vector2
var _dodge_time_left: float = 0.0
var _monster_start_timer: float = 0.0
var _dodge_sign: float = 1.0

var _root: Control
var _playfield: Control
var _wall_nodes: Array[ColorRect] = []
var _walls_container: Control
var _player_icon: TextureRect
var _monster_icon: TextureRect
var _target_icon: TextureRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 65  # above combination_lock's 60 and note_ui's 50
	_build_ui()


# ---------------------------------------------------------------- open/close

func open() -> void:
	_generate_maze()
	_reset_positions()
	_rebuild_wall_visuals()
	_update_visual_positions()
	_ui_open = true
	_focus_lost_clear = false
	_root.visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close() -> void:
	_ui_open = false
	_root.visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# A screamer firing while we're open unpauses/reloads the scene out from under
# this UI — self-clear silently rather than trying to resume (Issue 9).
func _hide_after_external_unpause() -> void:
	_ui_open = false
	_root.visible = false
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

	var in_grace: bool = _monster_start_timer > 0.0
	if in_grace:
		_monster_start_timer -= delta
	else:
		_tick_monster(delta)

	var dist_to_monster: float = _monster_pos.distance_to(_player_pos)

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


# ---------------------------------------------------------------- monster AI

func _tick_monster(delta: float) -> void:
	_stuck_check_timer += delta
	if _stuck_check_timer >= STUCK_SAMPLE_INTERVAL:
		if _monster_pos.distance_to(_stuck_check_pos) < STUCK_MOVE_THRESHOLD:
			_stuck_timer += _stuck_check_timer
		else:
			_stuck_timer = 0.0
		_stuck_check_pos = _monster_pos
		_stuck_check_timer = 0.0

	var dir: Vector2
	if _dodge_time_left > 0.0:
		_dodge_time_left -= delta
		dir = (_player_pos - _monster_pos).normalized().rotated(deg_to_rad(_dodge_sign * DODGE_ANGLE_DEG))
	else:
		dir = (_player_pos - _monster_pos).normalized()
		if _stuck_timer > STUCK_TRIGGER_TIME:
			_dodge_time_left = DODGE_TIME
			_dodge_sign = 1.0 if randf() < 0.5 else -1.0
			_stuck_timer = 0.0

	if dir.length() > 0.01:
		var candidate: Vector2 = _monster_pos + dir * MONSTER_SPEED * delta
		_monster_pos = _resolve_wall_slide(_monster_pos, candidate, ICON_HALF_EXTENT)


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
	var candidates: Array[Vector2i] = []
	for cell in dist.keys():
		if cell != _target_cell and dist[cell] == 1:
			candidates.append(cell)
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
	_stuck_timer = 0.0
	_stuck_check_timer = 0.0
	_stuck_check_pos = _monster_pos
	_dodge_time_left = 0.0
	_monster_start_timer = MONSTER_START_DELAY


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

	var caption := Label.new()
	caption.text = "Drag to the mark. Don't get caught."
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	caption.position.y = -48.0
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(caption)

	_target_icon = _make_icon(TEX + "house_map_target_icon.png", Color(0.9, 0.85, 0.3))
	_player_icon = _make_icon(TEX + "house_map_player_icon.png", Color(0.5, 0.85, 1.0))
	_monster_icon = _make_icon(TEX + "house_map_monster_icon.png", Color(0.85, 0.2, 0.2))


func _make_icon(tex_path: String, fallback_color: Color) -> TextureRect:
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size = Vector2(ICON_DISPLAY_SIZE, ICON_DISPLAY_SIZE)
	if ResourceLoader.exists(tex_path):
		icon.texture = load(tex_path)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
	else:
		var fallback := ColorRect.new()
		fallback.color = fallback_color
		fallback.size = Vector2(ICON_DISPLAY_SIZE, ICON_DISPLAY_SIZE)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_child(fallback)
	_playfield.add_child(icon)
	return icon


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
	_target_icon.position = _target_pos - half
