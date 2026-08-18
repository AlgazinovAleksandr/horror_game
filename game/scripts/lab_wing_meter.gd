extends CanvasLayer
class_name LabWingMeter

# ⚠️ DELIBERATE (2026-08-16) — a signal-strength readout for the Lab's dark wing, added on
# the user's explicit call, over a written anti-pattern, after they were shown both
# ISSUES_SOLUTIONS Issue 34 and GAME_MECHANICS_IDEAS §5.2(2) — which name a HUD readout of
# proximity-to-a-solution as a thing this project does not build. Their reason, from the
# playtest: *"Finding your way through sounds only in the complete dark is hard for the
# unexperienced user. Let's make the visual noise indicator also - like a continuous scale.
# The noise would get noisier the closer we are to the flip breaker."*
#
# The decision is made. Do not relitigate it in code, in a comment, or in the backlog.
#
# What IS worth writing down is why this widget is not the one that was deleted. The old
# `panic_hud.set_breaker_proximity()` bar was driven by STRAIGHT-LINE DISTANCE, and that is
# half of why it went: from inside a dead end it read a warm ~0.43 while being nowhere near
# the breaker in walking terms. It did not merely solve the maze, it solved it WRONG, and a
# player who trusted it walked into a wall.
#
# This one is driven by PATH DISTANCE through the actual room graph — Dijkstra over the
# wing's doorways, the same "route, not beeline" correction `maze_chase_ui.gd` had to make
# when its monster steered by a Euclidean vector in a maze where the corridor route is
# routinely 5-15x the straight line. A dead end 3 m from the breaker through a wall now
# reads COLD, because in walking terms it is cold. The meter can be trusted, which is a
# thing the old one could not claim.
#
# It is deliberately NOT a distance number and NOT a direction. It says "warmer/colder along
# the route you could actually walk"; the two-layer beacon (level_1.gd:_spawn_dark_beacon)
# still owns BEARING, which is the half of the problem a scalar cannot answer.

const WIDTH := 320.0
const HEIGHT := 16.0
const BOTTOM_MARGIN := 58.0

const COLD := Color(0.28, 0.34, 0.40, 1.0)
const HOT := Color(0.95, 0.76, 0.33, 1.0)
const LABEL := "PANEL HUM"

# How fast the displayed value chases the real one. Smoothing only — the underlying
# measurement is exact, and a bar that snaps between rooms reads as broken.
const EASE_RATE := 4.0
# A live level meter twitches more when there is more signal to twitch on. Purely cosmetic.
const JITTER_BASE := 0.012
const JITTER_GAIN := 0.055

var _rooms: Dictionary = {}          # name -> {min: Vector2, max: Vector2}
var _doors: Array[Vector2] = []      # doorway centres, in the order they were accepted
var _doors_of: Dictionary = {}       # room name -> Array[int] of doorway indices
var _door_cost: Array[float] = []    # shortest path distance from doorway i to the target
var _target: Vector3 = Vector3.ZERO
var _target_room: String = ""
var _max_path: float = 1.0

var _player: Node3D = null
var _active: bool = false
var _shown: float = 0.0              # the eased, displayed value
var _bar: ColorRect = null
var _bg: ColorRect = null
var _label: Label = null
var _root: Control = null


# `rooms` / `doors` are level_1.gd's ROOMS / DOORS tables verbatim; `room_names` is the
# subset the meter is allowed to route through (the ten wing rooms). `target` is the
# breaker. Everything below is derived — there is no hand-typed geometry in this file.
func setup(rooms: Array, doors: Array, room_names: Array, target: Vector3,
		target_room: String) -> void:
	_target = target
	_target_room = target_room
	for r in rooms:
		var name := String(r["name"])
		if not room_names.has(name):
			continue
		var pos: Vector2 = r["pos"]
		var half: Vector2 = r["size"] * 0.5
		_rooms[name] = { "min": pos - half, "max": pos + half }
		_doors_of[name] = []

	for d in doors:
		var p: Vector2 = d["pos"]
		var touching: Array[String] = []
		for name in _rooms:
			if _touches(name, p):
				touching.append(name)
		if touching.is_empty():
			continue
		var idx := _doors.size()
		_doors.append(p)
		for name in touching:
			_doors_of[name].append(idx)

	_solve()
	_build_ui()


# A doorway belongs to a room when it sits on that room's boundary: inside the rectangle
# grown by half a wall thickness, which is what "abutting rooms share a wall plane" means
# numerically.
const EDGE_TOL := 0.25

func _touches(room_name: String, p: Vector2) -> bool:
	var lo: Vector2 = _rooms[room_name]["min"]
	var hi: Vector2 = _rooms[room_name]["max"]
	return p.x >= lo.x - EDGE_TOL and p.x <= hi.x + EDGE_TOL \
		and p.y >= lo.y - EDGE_TOL and p.y <= hi.y + EDGE_TOL


# Dijkstra over doorways. Two doorways are adjacent when they sit on the same room, at the
# straight-line cost between them — legal because every room here is a convex rectangle, so
# the straight line between two of its doorways is a walkable path.
func _solve() -> void:
	var n := _doors.size()
	_door_cost.resize(n)
	for i in range(n):
		_door_cost[i] = INF
	# Seed: doorways of the room the breaker is in.
	for i in _doors_of.get(_target_room, []):
		_door_cost[i] = _doors[i].distance_to(Vector2(_target.x, _target.z))

	var settled := {}
	while settled.size() < n:
		var best := -1
		var best_cost := INF
		for i in range(n):
			if not settled.has(i) and _door_cost[i] < best_cost:
				best = i
				best_cost = _door_cost[i]
		if best < 0:
			break                      # the rest are unreachable
		settled[best] = true
		for room_name in _doors_of:
			var list: Array = _doors_of[room_name]
			if not list.has(best):
				continue
			for j in list:
				if j == best:
					continue
				var alt: float = best_cost + _doors[best].distance_to(_doors[j])
				if alt < _door_cost[j]:
					_door_cost[j] = alt

	# Normalise against the FURTHEST room in the wing, measured the same way — so the scale
	# is derived from the level's own geometry rather than from a number somebody liked.
	_max_path = 1.0
	for room_name in _rooms:
		var lo: Vector2 = _rooms[room_name]["min"]
		var hi: Vector2 = _rooms[room_name]["max"]
		var mid: Vector2 = (lo + hi) * 0.5
		var d := path_distance(Vector3(mid.x, 0.0, mid.y))
		if is_finite(d):
			_max_path = maxf(_max_path, d)


# Metres of walking from `pos` to the breaker, through doorways. INF when `pos` is outside
# the wing entirely. Public: tests assert this directly rather than reading pixels.
func path_distance(pos: Vector3) -> float:
	var p := Vector2(pos.x, pos.z)
	var room := _room_at(p)
	if room == "":
		return INF
	if room == _target_room:
		return p.distance_to(Vector2(_target.x, _target.z))
	var best := INF
	for i in _doors_of.get(room, []):
		if not is_finite(_door_cost[i]):
			continue
		best = minf(best, p.distance_to(_doors[i]) + _door_cost[i])
	return best


# 0 = as far from the breaker as this wing gets, 1 = standing on it.
func signal_strength(pos: Vector3) -> float:
	var d := path_distance(pos)
	if not is_finite(d):
		return 0.0
	return clampf(1.0 - d / _max_path, 0.0, 1.0)


func max_path() -> float:
	return _max_path


func _room_at(p: Vector2) -> String:
	for name in _rooms:
		if _touches(name, p):
			return name
	return ""


# ---------------------------------------------------------------- display

func set_active(active: bool) -> void:
	_active = active
	if _root:
		_root.visible = active


func is_active() -> bool:
	return _active


func set_player(p: Node3D) -> void:
	_player = p


func shown_value() -> float:
	return _shown


func _build_ui() -> void:
	layer = 5      # under NoteUI (50) and the Screamer (100), over the world
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	_bg = ColorRect.new()
	_bg.color = Color(0.05, 0.05, 0.06, 0.72)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bg.offset_left = -WIDTH / 2.0
	_bg.offset_right = WIDTH / 2.0
	_bg.offset_top = -BOTTOM_MARGIN - HEIGHT
	_bg.offset_bottom = -BOTTOM_MARGIN
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bg)

	# Driven by `anchor_right`, never by `size` — beartrap.gd / lab_locker.gd's convention,
	# because a ColorRect's size fights its parent's layout and its anchor does not.
	_bar = ColorRect.new()
	_bar.color = COLD
	_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar.anchor_right = 0.0
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_bar)

	_label = Label.new()
	_label.text = LABEL
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.72, 0.74, 0.72))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 5)
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_label.offset_left = -WIDTH / 2.0
	_label.offset_right = WIDTH / 2.0
	_label.offset_top = -BOTTOM_MARGIN - HEIGHT - 24.0
	_label.offset_bottom = -BOTTOM_MARGIN - HEIGHT - 2.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_label)


func tick(delta: float) -> void:
	if not _active or not _bar or not is_instance_valid(_player):
		return
	var target := signal_strength(_player.global_position)
	_shown = lerpf(_shown, target, clampf(EASE_RATE * delta, 0.0, 1.0))
	var jitter := randf_range(-1.0, 1.0) * (JITTER_BASE + JITTER_GAIN * _shown)
	_bar.anchor_right = clampf(_shown + jitter, 0.0, 1.0)
	_bar.color = COLD.lerp(HOT, _shown)
	_label.modulate.a = 0.55 + 0.45 * _shown
