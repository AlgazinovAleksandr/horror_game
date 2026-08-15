extends Node3D

# Level 3 — The Corridor. A ~320 m zigzag hotel hallway, built procedurally
# from PATH_2D. The only test: walk it without panicking. Three zones:
#   A (0–90 m)    intact hotel — torches, paintings, the clock
#   B (90–230 m)  decay — blood, lights shatter, beartraps in the dark
#   C (230–320 m) nightmare — dead torches, the mirror, whispers, door 217

const W := 3.0   # corridor width
const H := 3.0   # corridor height
const T := 0.3   # wall thickness

# Corner points of the zigzag centerline (x, z). Segment lengths:
# 50 + 40 + 50 + 45 + 45 + 45 + 45 = 320 m.
const PATH_2D: Array[Vector2] = [
	Vector2(0, 0), Vector2(0, 50), Vector2(40, 50), Vector2(40, 100),
	Vector2(-5, 100), Vector2(-5, 145), Vector2(40, 145), Vector2(40, 190),
]

const TEX_DIR := "res://assets/textures/level_3_corridor/"

# Lit torches: [distance, side]. Zone A is generous, Zone B sparser.
# The three at 148–168 sit in the dark stretch and get shattered by the
# lights-out event before the player reaches them.
const TORCHES := [
	[8.0, 1.0], [20.0, -1.0], [32.0, 1.0], [44.0, -1.0], [56.0, 1.0],
	[68.0, -1.0], [80.0, 1.0],
	[100.0, 1.0], [120.0, -1.0], [134.0, 1.0],
	[148.0, -1.0], [158.0, 1.0], [168.0, -1.0],
	[176.0, 1.0], [196.0, -1.0], [214.0, 1.0],
]
const SHATTER_RANGE := Vector2(144.0, 172.0)  # torches extinguished by lights-out

const BEARTRAPS := [  # [distance, lateral offset]
	[150.0, 0.45], [155.0, -0.6], [162.0, 0.55], [168.0, 0.0], [245.0, -0.5],
]

# ⚠️ Difficulty fix: DARK_ZONES used to have a second entry, Vector2(240, 318),
# which sat entirely INSIDE the dread zone below. player.gd's _update_panic()
# treats dark-zone and dread-zone pressure as ADDITIVE (dark tax is +3/s on top
# of the unconditional +2/s dread pressure), so any stretch tagged as both was a
# guaranteed +5/s with the flashlight off — and the noclip ending (_ev_noclip_onset)
# FORCE-KILLS the flashlight for the final ~10 m with zero player agency to avoid
# it. A long level with beartrap QTEs earlier can also burn through the 240 s
# battery before reaching here, forcing the same double tax by attrition rather
# than choice. Either way it made the ending an unavoidable panic spike report
# read as "impossible." Dropped entirely — the dread zone's own pressure is
# already this stretch's difficulty signature; it doesn't need a second, stacking
# mechanic under it.
const DARK_ZONES := [Vector2(145.0, 172.0)]
# Shortened from 230 (90 m of flat/no-recovery pressure) to 260 (60 m) — gives
# the player real decay time after the silhouette/floor-crack events instead of
# carrying whatever panic they had straight into the endurance stretch.
const DREAD_ZONE := Vector2(260.0, 320.0)  # Zone C tail: weak decay + constant pressure

# The Manager: a survivable scare that strikes once while you walk — a flash, a
# scream, a panic spike to ride out. Distance-triggered (not wall-time) at a
# random mid-hall point, so it always fires regardless of walk/run speed.
const MANAGER_SCARE_PATH := "res://assets/textures/level_3_corridor/screamer_manager.png"
const MANAGER_PANIC := 25.0
const MANAGER_DIST := Vector2(80.0, 180.0)  # walked-distance window for the fire point

var _manager_fired: bool = false
var _furthest_reached: float = 0.0

# Turn mirrors: walk into the creature in the glass and it flashes back at you.
# [{pos, fired}] — proximity-tested in _process so each fires once.
const TURN_MIRROR_SCARE_PATH := "res://assets/textures/level_3_corridor/mirror_with_creature.png"
const TURN_MIRROR_SCARE_DIST := 2.0
const TURN_MIRROR_PANIC := 12.0

var _turn_mirrors: Array = []

const NOTE_TEXT := """Hotel Vesper — night audit.

The corridor between floors does not appear on the building plans. The staff do not walk it after dark.

You will.

Walk. Do not run. Do not stop for the things you hear behind you. The lights have been paid for where they still burn — rest beneath them.

One of the rooms on this floor is occupied. We are not permitted to say which, and we are not permitted to say when the guest will step out. It has happened before. It will happen once tonight.

Room 217 is waiting.

— The Management"""

var _segments: Array[Dictionary] = []
var _total_len: float = 0.0
var _torch_nodes: Array = []  # [distance, Torch3D]
var _wall_mat: StandardMaterial3D
var _floor_mat: StandardMaterial3D
var _ceil_mat: StandardMaterial3D

@onready var _player: CharacterBody3D = $Player


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameState.current_level = 3

	_build_segments()
	_make_materials()
	_build_geometry()
	_spawn_torches()
	_spawn_panels()
	_spawn_beartraps()
	_spawn_dark_zones()
	_spawn_dread_zone()
	_spawn_doors()
	_spawn_intro_note()
	_spawn_events()
	_spawn_noclip()
	_start_ambience()
	_black_background()
	Vignette.spawn(self, Color(0.9, 0.8, 0.65, 1.0), 1.2)
	RandomAmbient.register_player(_player)
	# ⚠️ The Corridor is the ONLY level that caps this, and it is opt-in for that reason —
	# see random_ambient.gd:set_once_per_type(). At ~300 m this is the longest walk in the
	# game, so a global 18-35 s metronome cycled the same three sounds many times over
	# ("too many repeating sounds… falling painting", 2026-08-15). One creak, one painting,
	# one half-scream, and then this autoload is quiet for the rest of the hall.
	RandomAmbient.set_once_per_type(true)
	_pick_silent_mirror()
	_spawn_apparition_director()
	# SCARY.md P2's stop-delayed echo. Two extra steps after the player halts: they stop,
	# and something behind them takes two more strides and stops too. Zero panic. This is
	# the first level other than the Backrooms to use the echo at all.
	_player.enable_footstep_echo(2)
	GameState.set_objective("Find room 217 — keep walking, do not run")
	_place_player()


# The shared Environment renders a procedural SKY behind the level. In a sealed corridor
# nobody ever sees it — until a mirror does. The reflection camera sits behind the glass
# with its near plane pushed out to the mirror plane, which necessarily clips the ceiling
# slab as well as the wall, and the sky poured through the gap as a bright blue band across
# the top of every mirror.
#
# `level_1.gd:_boost_ambient()` and the House already switch to a black background for
# exactly this class of leak ("so any geometry gap reads as darkness rather than blue
# sky"). The Corridor never needed it before because it had nothing that could see out.
# ⚠️ Ambient energy is deliberately NOT touched — this level's darkness is tuned.
func _black_background() -> void:
	var we: WorldEnvironment = get_node_or_null("Environment/WorldEnvironment")
	if not we or not we.environment:
		return
	var env: Environment = we.environment.duplicate()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	we.environment = env


# One of the three turn mirrors does not flash this run. See the note in _process.
func _pick_silent_mirror() -> void:
	if _turn_mirrors.size() < 2:
		return
	_turn_mirrors[randi() % _turn_mirrors.size()]["flashes"] = false


# The Corridor was the ONLY level with an ApparitionDirector-shaped hole — the Lab, the
# House, KONTUR and the Backrooms Flood all get the shared HOLD apparition and this level
# never did, despite having 140 m of Zone B to fill.
#
# ⚠️ Suppressed in two places, both for Issue-18 double-jeopardy reasons:
#   * 145-172 m, the dark zone with the four beartraps in it. A HOLD apparition kills you
#     for fleeing, and a player clamped at 45 % speed mashing E cannot demonstrate that they
#     are standing their ground. (`is_input_frozen()` now covers the beartrap QTE as well —
#     that was Phase 0's fourth fix — but keeping the whole stretch clear is the belt to its
#     braces, since the trap can also be stepped on a moment after the spawn.)
#   * past 260 m, the DreadZone, where decay is cancelled so every point is permanent, and
#     where the noclip force-kills the flashlight with no player agency at all.
func _spawn_apparition_director() -> void:
	if not RANDOM_APPARITIONS:
		return
	var director := ApparitionDirector.new()
	director.name = "ApparitionDirector"
	director.suppress = func() -> bool:
		var d := _furthest_reached
		if d >= DARK_ZONES[0].x - 5.0 and d <= DARK_ZONES[0].y + 5.0:
			return true
		return d >= DREAD_ZONE.x
	add_child(director)


# ---------------------------------------------------------------- progress snapshot
#
# The Corridor has no puzzle state — the level IS the walk. What it has instead is 320
# metres, and that is exactly what makes re-entry painful: coming BACK from the
# Backrooms used to drop the player at the corridor mouth with the whole hall to walk
# again before they could reach the noclip and go forward. So the only thing worth
# remembering is how far they got.
#
# ⚠️ Deliberately capped short of the noclip ONSET, not just the fall. Respawning inside
# either trigger would re-fire it the instant the level loaded — the blackout would kill
# the flashlight on arrival, or the fall would bounce the player straight back to the
# Backrooms they were trying to leave.
#
# ⚠️ THIS MOVES WITH `NOCLIP_ONSET_BEFORE_END`. It was 14.0 against a 10 m onset (cap at
# 306, clearing the onset box by 3 m); the 2026-08-15 pass moved the onset to 15 m out, so
# 14.0 would have put the player INSIDE it. 18.0 caps re-entry at 302: 2 m clear of the
# onset box (304-306) and ~11 m clear of the fall. `tests/check_noclip_fall.gd` asserts
# both gaps so the pair cannot drift apart again.
const RETURN_MARGIN := 18.0

# --- "the hotel wakes up behind you" (2026-07-28) --------------------------------------
# Measured dead stretches before this pass: 90-138 m had NOTHING in it (48 m, ~12 s of pure
# walking), and 288-310 m was 22 m of decals with the DreadZone's rates cancelling exactly,
# so panic could not even move. Zone C had no lit torch after 214 m and no calm zone at all.
#
# Everything here is panic-neutral except the apparition, which the user approved
# explicitly. The Manager's existing 25 is RE-HOMED rather than added to.
const DOOR_BEHIND_DIST := 10.0     # how far past a door before it may open
const DOOR_AJAR_MIN := 24.0        # degrees
const DOOR_AJAR_MAX := 38.0
const DOOR_SWING_TIME := 1.6       # slow, and silent — see AjarDoor.swing_ajar()
const DOOR_SLAM_LEAD := 22.0       # metres past the ajar door before it slams
const DOOR_VIEW_DOT := 0.35        # above this the player is looking at it; do not move it

# P4 The False Ceiling. A telegraph that usually means nothing, then one that does.
#
# ⚠️ WAS FIVE (104/126/150/178/206), and the user reported the result plainly: "there are
# too many repeating sounds… the trumpet musical instrument." `telegraph_groan` is a 3.2 s
# descending brass fall (tools/make_sfx_atmos.py:78-111) and hearing it five times in
# 100 m stops reading as dread and starts reading as a loop.
#
# Cut to TWO on the user's call (2026-08-15): one warning that leads nowhere, and one that
# delivers the Manager. That keeps the shape of the beat — you learn the sound means
# something is coming, you are wrong once, and then you are right — which is the whole
# point of P4, while the instrument is heard twice instead of five times.
const TELEGRAPH_AT: Array[float] = [126.0, 190.0]
const TELEGRAPH_PAYOFF_DELAY := 0.9

# The last stretch goes silent (P5's spatial cousin) instead of staying merely quiet.
const HUSH_AT := 296.0

# The Corridor's score rides its own bus so the hush cannot silence it. Nested under
# Master rather than Ambience — see _start_ambience().
const _MUSIC_BUS := "CorridorScore"

# Whether this level arms random apparitions. Same const-plus-director split as
# level_1/level_2/kontur: the level says WHETHER, ApparitionDirector owns WHEN.
const RANDOM_APPARITIONS := true

var _ajar_doors: Array[Dictionary] = []
var _slam_index: int = -1
var _slam_dist: float = -1.0
var _watcher_door: int = -1
var _telegraph_payoff: int = 0     # which of the five actually delivers, per run
var _telegraphs_fired: int = 0
var _hushed: bool = false


func save_progress() -> Dictionary:
	return {
		"furthest": _furthest_reached,
		"manager_fired": _manager_fired,
		# ⚠️ P4's payoff index must persist. Re-rolling it on a back-door return would let a
		# player who already learned which telegraph delivers meet a different one, which is
		# the opposite of the anti-habituation the whole mechanic exists for.
		"telegraph_payoff": _telegraph_payoff,
		"telegraphs_fired": _telegraphs_fired,
		# Which mirrors carry a flash is also drawn per run (see _spawn_turn_mirror).
		"mirror_flash": _turn_mirrors.map(func(m: Dictionary) -> bool: return bool(m.get("flashes", true))),
	}


func _place_player() -> void:
	if not _player:
		return
	if not GameState.entered_from_ahead:
		return                       # the .tscn already puts them at the mouth
	var data := GameState.get_level_progress(3)
	var dist: float = minf(float(data.get("furthest", 0.0)), _total_len - RETURN_MARGIN)
	if dist <= 1.0:
		return
	var pt := _path_point(dist)
	_player.global_position = pt.pos + Vector3(0, 0.1, 0)
	# Face back the way they came, toward the exit — they re-entered through it.
	_player.rotation.y = atan2(pt.dir.x, pt.dir.z)
	_manager_fired = bool(data.get("manager_fired", false))
	_telegraph_payoff = int(data.get("telegraph_payoff", _telegraph_payoff))
	_telegraphs_fired = int(data.get("telegraphs_fired", 0))
	var flags: Array = data.get("mirror_flash", [])
	for i in mini(flags.size(), _turn_mirrors.size()):
		_turn_mirrors[i]["flashes"] = bool(flags[i])


func _process(_delta: float) -> void:
	# Deferred to here because the clearance probes need a physics frame — see
	# _make_mirror_real(). One-shot; the array is cleared by the call.
	if not _mirror_figure_spots.is_empty():
		_spawn_mirror_figures()

	# Falling through the floor owns the rest of the frame — nothing below this point
	# (turn-mirror proximity, the hush, door slams) means anything once the level is over.
	if _noclip_fired:
		_tick_fall()
		return

	# Walk into a turn mirror and the creature in the glass flashes at you once.
	var pp := _player.global_position
	# Cheap high-water mark for the progress snapshot. Path distance is not recoverable
	# from a position (the hall zigzags and doubles back in x), so track it as we go.
	_furthest_reached = maxf(_furthest_reached, _nearest_path_distance(pp))
	for m in _turn_mirrors:
		if m.fired:
			continue
		var mp: Vector3 = m.pos
		if Vector2(pp.x - mp.x, pp.z - mp.z).length() <= TURN_MIRROR_SCARE_DIST:
			m.fired = true
			# ⚠️ Only SOME mirrors flash, drawn per run (_spawn_turn_mirror). The mirror sits
			# 1.45 m past each corner, so a normal turn ALWAYS trips it — three identical
			# 12-panic flashes at 90/230/275 m was textbook habituation by the third corner.
			# The panic is unchanged where it fires; one corner is now simply a corner.
			if not bool(m.get("flashes", true)):
				continue
			Screamer.flash_scare(TURN_MIRROR_SCARE_PATH, "glass_shatter", 0.6)
			_player.jolt_camera(0.07, 0.5)
			_player.add_panic(TURN_MIRROR_PANIC)

	_tick_doors()
	_tick_hush()


# THE ANCHOR: doors you have already walked past open behind you.
#
# ⚠️ SILENTLY, and that is the mechanic. A creak at the moment of opening would give the
# player something to attribute it to and make this an event; without one it is a
# discrepancy, and it works RETROACTIVELY — one door standing ajar makes every door already
# passed a question. (Condemned's mannequins, via SCARY.md P6.)
#
# ⚠️ Also gated on not being looked at. The door must never move in view: a prop visibly
# swinging on its own is a different, cheaper effect, and this level has no supernatural
# register to spend yet at 90 m.
func _tick_doors() -> void:
	var here := _furthest_reached
	for d in _ajar_doors:
		var node: AjarDoor = d.node
		if not is_instance_valid(node):
			continue
		if not bool(d.opened):
			if here < float(d.dist) + DOOR_BEHIND_DIST:
				continue
			if _looking_at(node.global_position):
				continue
			d.opened = true
			node.swing_ajar(randf_range(DOOR_AJAR_MIN, DOOR_AJAR_MAX), DOOR_SWING_TIME)
			# One door in Zone B has someone standing in it. No rules, no panic, no sound,
			# gone when you look again — and BEHIND the player, per the "never scare from
			# the front" placement clause (GAME_MECHANICS_IDEAS N1).
			if int(d.dist) == _watcher_door:
				var pt := _path_point(float(d.dist))
				Watcher.spawn(self, (pt.pos as Vector3) + (pt.side as Vector3) * 1.1,
					"res://assets/textures/shared/watcher_figure.png", 4.0)
		elif _slam_index >= 0 and int(d.dist) == _slam_index and here >= _slam_dist:
			# The one that is HEARD. By now the player has probably already noticed doors
			# standing open, so the slam lands as confirmation rather than as a jump.
			_slam_index = -1
			_play_at("door_slam", node.global_position + Vector3(0, 1.0, 0), 0.0)
			node.slam()


func _looking_at(target: Vector3) -> bool:
	var cam := _player.get_node_or_null("Camera3D") as Camera3D
	if not cam:
		return false
	var to_it := target - cam.global_position
	to_it.y = 0.0
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	if to_it.length() < 0.05 or fwd.length() < 0.05:
		return true      # degenerate: assume visible and leave the door alone
	return fwd.normalized().dot(to_it.normalized()) > DOOR_VIEW_DOT


# The last 22 m before the noclip were mechanically frozen and content-free. They get the
# one thing this level has never had: silence. The whisper loop and the ambient bed die, and
# the player's own footsteps — on the un-duckable Body bus — are all that is left for the
# walk into the drop.
func _tick_hush() -> void:
	if _hushed or _furthest_reached < HUSH_AT:
		return
	_hushed = true
	var idx := AudioServer.get_bus_index(AudioBuses.AMBIENCE)
	if idx == -1:
		return
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: AudioServer.set_bus_volume_db(idx, v),
		AudioServer.get_bus_volume_db(idx), -40.0, 3.0)


# ⚠️ THE HUSH MUST NOT OUTLIVE THE LEVEL. Audio buses are global and survive a scene
# change, and this level ducks `Ambience` by 40 dB roughly 20 m before it ends — so for the
# life of the project every level after the Corridor played with its ambience 40 dB down.
# It surfaced as "the music in the Backrooms disappeared after I got there from the
# corridor, but starting the Backrooms from scratch it was there" (2026-08-15).
#
# `GameState.start_current_level()` now resets every bus on every load, which is the real
# guarantee; this is the level cleaning up after itself so it is not the thing relying on
# it. Both, deliberately — the same belt-and-braces `silence_zone.gd` uses.
func _exit_tree() -> void:
	var idx := AudioServer.get_bus_index(AudioBuses.AMBIENCE)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, 0.0)


# P4 — the telegraph that usually means nothing, plus N3's announced-but-unbounded window.
#
# Four of the five fire and are followed by NOTHING AT ALL. The fifth, drawn per run, is
# followed 0.9 s later by the Manager's EXISTING flash_scare — so a 25-panic startle becomes
# a ~100 m dread structure at zero additional panic cost. A non-event cannot be unfair,
# which makes this the cheapest legal scare in the whole document.
func _telegraph(index: int) -> void:
	_telegraphs_fired += 1
	_play_at("telegraph_groan", _player.global_position + Vector3(0, 1.6, 0), -4.0)
	HoldBreath.dip(get_tree(), 1.2)
	if index != _telegraph_payoff:
		return                     # …and nothing happens. Four times out of five.
	get_tree().create_timer(TELEGRAPH_PAYOFF_DELAY).timeout.connect(_ev_manager)


# ---------------------------------------------------------------- path helpers

func _build_segments() -> void:
	var d := 0.0
	for i in range(PATH_2D.size() - 1):
		var p0 := PATH_2D[i]
		var p1 := PATH_2D[i + 1]
		var seg_len := p0.distance_to(p1)
		_segments.append({
			"p0": p0, "dir": (p1 - p0) / seg_len, "len": seg_len, "start_d": d,
		})
		d += seg_len
	_total_len = d


# Point on the centerline at walked distance `dist`.
# Returns pos (floor level), dir (walk direction) and side (lateral unit vector).
# Approximate path distance of a world position, by walking the segment table. Good
# enough for a respawn marker; it is never used for anything the player can see.
func _nearest_path_distance(pos: Vector3) -> float:
	var here := Vector2(pos.x, pos.z)
	var best_d := 0.0
	var best_sq := INF
	for seg in _segments:
		var p0: Vector2 = seg.p0
		var dir: Vector2 = seg.dir
		var seg_len: float = seg.len
		var t: float = clampf((here - p0).dot(dir), 0.0, seg_len)
		var closest: Vector2 = p0 + dir * t
		var d_sq: float = closest.distance_squared_to(here)
		if d_sq < best_sq:
			best_sq = d_sq
			best_d = float(seg.start_d) + t
	return best_d


func _path_point(dist: float) -> Dictionary:
	for i in range(_segments.size()):
		var seg: Dictionary = _segments[i]
		if dist <= seg.start_d + seg.len or i == _segments.size() - 1:
			var t: float = clampf(dist - seg.start_d, 0.0, seg.len)
			var p: Vector2 = seg.p0 + seg.dir * t
			var dir3 := Vector3(seg.dir.x, 0, seg.dir.y)
			return {
				"pos": Vector3(p.x, 0, p.y),
				"dir": dir3,
				"side": Vector3(dir3.z, 0, -dir3.x),
			}
	return {}


# ---------------------------------------------------------------- geometry

func _make_materials() -> void:
	# Negative y: triplanar V grows upward in world space, which renders the
	# texture upside-down on walls — flip so the wainscot sits at the floor.
	_wall_mat = _make_mat(TEX_DIR + "wall.png", Vector3(1.0 / 3.6, -1.0 / 3.0, 1.0 / 3.6), Color(0.25, 0.2, 0.14))
	_floor_mat = _make_mat(TEX_DIR + "carpet.png", Vector3(0.5, 0.5, 0.5), Color(0.16, 0.12, 0.05))
	_ceil_mat = _make_mat("", Vector3.ONE, Color(0.10, 0.085, 0.07))


func _make_mat(tex_path: String, uv_scale: Vector3, fallback: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.92
	if tex_path != "" and ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
		# Triplanar = 1 texture unit per (1/scale) world metres, independent of
		# CSG face size. Wall y-scale 1/3 fits exactly one wainscot row per 3 m.
		mat.uv1_triplanar = true
		mat.uv1_scale = uv_scale
	else:
		mat.albedo_color = fallback
	return mat


func _build_geometry() -> void:
	for i in range(_segments.size()):
		var seg: Dictionary = _segments[i]
		var n: Vector2 = Vector2(seg.dir.y, -seg.dir.x)  # side normal (2D)
		# Footprint extends half a width past interior corners so overlapping
		# floor/ceiling boxes cover the corner squares.
		var lo := 0.0 if i == 0 else -W / 2.0
		var hi: float = seg.len if i == _segments.size() - 1 else seg.len + W / 2.0

		_corridor_box("Seg%dFloor" % i, seg, lo, hi, 0.0, W + 2.0 * T, -T / 2.0, T, _floor_mat)
		_corridor_box("Seg%dCeiling" % i, seg, lo, hi, 0.0, W + 2.0 * T, H + T / 2.0, T, _ceil_mat)

		for side in [1.0, -1.0]:
			var wa := lo
			var wb := hi
			# Leave a corridor-wide opening where the adjacent segment attaches.
			if i > 0 and (-_segments[i - 1].dir as Vector2).distance_to(n * side) < 0.01:
				wa = lo + W
			if i < _segments.size() - 1 and (_segments[i + 1].dir as Vector2).distance_to(n * side) < 0.01:
				wb = hi - W
			if wb - wa > 0.01:
				var wall_name := "Seg%dWall%s" % [i, "A" if side > 0 else "B"]
				_corridor_box(wall_name, seg, wa, wb, side * (W + T) / 2.0, T, H / 2.0, H + 2.0 * T, _wall_mat)

		if i == 0:
			_corridor_box("StartCapWall", seg, lo - T, lo, 0.0, W + 2.0 * T, H / 2.0, H + 2.0 * T, _wall_mat)
		if i == _segments.size() - 1:
			_corridor_box("EndCapWall", seg, hi, hi + T, 0.0, W + 2.0 * T, H / 2.0, H + 2.0 * T, _wall_mat)


# Axis-aligned CSG box spanning [a, b] along the segment direction,
# `lateral` metres off the centerline, `width` across, `height` tall.
func _corridor_box(box_name: String, seg: Dictionary, a: float, b: float,
		lateral: float, width: float, y_center: float, height: float, mat: Material) -> void:
	var n: Vector2 = Vector2(seg.dir.y, -seg.dir.x)
	var mid2: Vector2 = seg.p0 + (seg.dir as Vector2) * ((a + b) / 2.0) + n * lateral
	var box := CSGBox3D.new()
	box.name = box_name
	box.use_collision = true
	if absf(seg.dir.x) > 0.5:
		box.size = Vector3(b - a, height, width)
	else:
		box.size = Vector3(width, height, b - a)
	box.position = Vector3(mid2.x, y_center, mid2.y)
	if mat:
		box.material = mat
	add_child(box)


# ---------------------------------------------------------------- props

func _spawn_torches() -> void:
	for entry in TORCHES:
		var dist: float = entry[0]
		var side: float = entry[1]
		var pt := _path_point(dist)
		var torch := Torch3D.new()
		torch.position = pt.pos + (pt.side as Vector3) * side * (W / 2.0 - 0.12) + Vector3(0, 1.9, 0)
		var inward: Vector3 = -(pt.side as Vector3) * side
		torch.rotation.y = atan2(inward.x, inward.z)
		add_child(torch)
		_torch_nodes.append([dist, torch])


func _spawn_panels() -> void:
	# Plain decor panels: [dist, side, w, h, texture, y_center]
	var decor := [
		[60.0, 1.0, 1.5, 1.2, "painting.png", 1.8],
		[180.0, -1.0, 1.5, 1.2, "painting.png", 1.8],
		[110.0, 1.0, 2.4, 1.8, "blood_corridor.png", 1.4],
		[150.0, -1.0, 2.4, 1.8, "blood_corridor.png", 1.4],
		[200.0, 1.0, 2.4, 1.8, "blood_corridor.png", 1.4],
		[246.0, -1.0, 2.4, 1.8, "blood_corridor.png", 1.4],
		[282.0, 1.0, 2.4, 1.8, "blood_corridor.png", 1.4],
		[308.0, -1.0, 2.4, 1.8, "blood_corridor.png", 1.4],
		[240.0, 1.0, 2.0, 3.0, "torch.png", 1.5],   # dead torches — Zone C
		[262.0, -1.0, 2.0, 3.0, "torch.png", 1.5],
		[300.0, 1.0, 2.0, 3.0, "torch.png", 1.5],
		[255.0, -1.0, 1.8, 1.2, "carpet.png", 1.6],  # wall-hung carpet
		# KONTUR HINT 3/4 — the answer to KONTUR's Gate 3 (the offering). Reads as
		# hotel signage here; only later does it mean anything. Full-height panel
		# because the art carries its own wallpaper+wainscot background, like the
		# clock/mirror/torch panels. See kontur.gd.
		[172.0, -1.0, 2.0, 3.0, "kontur_plate.png", 1.5],
	]
	for p in decor:
		_spawn_quad(_panel_transform(p[0], p[1], p[5]), Vector2(p[2], p[3]), TEX_DIR + p[4])

	# Floor crack decals (static decor; the live crack event spawns its own)
	for crack in [[258.0, 0.4], [296.0, -0.5]]:
		var pt := _path_point(crack[0])
		var quad := _spawn_quad(Transform3D(), Vector2(1.6, 1.2), TEX_DIR + "floor_crack.png")
		if quad:
			quad.position = pt.pos + (pt.side as Vector3) * crack[1] + Vector3(0, 0.012, 0)
			quad.rotation_degrees.x = -90.0

	# Cursed panels (gaze fills panic): [dist, side, w, h, texture, y_center, intensity]
	# The plain mirror.png stays a full-height side-wall panel — now one on each
	# wall in Zone C so the player is flanked by their own reflection.
	var cursed := [
		[25.0, -1.0, 1.5, 1.2, "painting.png", 1.8, 0.8],
		[48.0, 1.0, 2.0, 3.0, "clock.png", 1.5, 1.0],
		[268.0, 1.0, 1.5, 1.2, "painting.png", 1.8, 1.2],
		[285.0, -1.0, 2.0, 3.0, "mirror.png", 1.5, 2.5],
		[288.0, 1.0, 2.0, 3.0, "mirror.png", 1.5, 2.0],
	]
	for p in cursed:
		_spawn_cursed_panel(p[0], p[1], Vector2(p[2], p[3]), TEX_DIR + p[4], p[5], p[6])

	# The creature in the glass: an ornate mirror set on the wall the player walks
	# straight at when reaching a turn — miss the turn and you walk into it.
	for tm in [[90.0, 1.5], [230.0, 2.0], [275.0, 2.2]]:
		_spawn_turn_mirror(tm[0], tm[1])

	# Locked hotel room doors that knock back, plus plain decor doors for atmosphere.
	for fd in [[35.0, -1.0], [130.0, 1.0], [252.0, 1.0]]:
		_spawn_fake_door(fd[0], fd[1])
	# ⚠️ These six were flat, inert `QuadMesh`es glued to the wallpaper — pure decor, with
	# no way to open because there was nothing there to open. They are real hinged doors
	# now, which gives the level the one rule a haunted hotel corridor has always wanted:
	# doors you have already walked past open behind you. See _tick_doors().
	for dd in [[18.0, 1.0], [72.0, -1.0], [112.0, 1.0], [164.0, -1.0], [210.0, 1.0], [300.0, -1.0]]:
		# 0.14 of depth inset clears the wall (see _panel_transform), and the hinge is
		# shifted half a width along the wall so the door stays centred where the old flat
		# decal was — AjarDoor's panel extends from its origin along local +x.
		var xf := _panel_transform(dd[0], dd[1], 0.0, 0.14) \
			.translated_local(Vector3(-AjarDoor.WIDTH / 2.0, 0.0, 0.0))
		var d := AjarDoor.build(self, xf, TEX_DIR + "ordinary_hotel_door.png")
		d.name = "AjarDoor_%d" % int(dd[0])
		_ajar_doors.append({ "node": d, "dist": float(dd[0]), "opened": false })


# Transform flush against the wall at `dist` on `side`, quad facing inward.
#
# `depth_inset` is how far the origin sits IN from the wall's inner face. 0.02 is right for
# a zero-thickness decal quad, but anything with real depth needs more: an AjarDoor's art
# quads sit 0.054 off its own centre, so at 0.02 they would end up 3 cm INSIDE the wall and
# trip check_wall_overlap.gd's "every QuadMesh is at least 2 cm clear of every CSG box".
func _panel_transform(dist: float, side: float, y_center: float,
		depth_inset: float = 0.02) -> Transform3D:
	var pt := _path_point(dist)
	var inward: Vector3 = -(pt.side as Vector3) * side
	var pos: Vector3 = pt.pos + (pt.side as Vector3) * side * (W / 2.0 - depth_inset) \
		+ Vector3(0, y_center, 0)
	return Transform3D(Basis(Vector3.UP, atan2(inward.x, inward.z)), pos)


func _spawn_quad(xform: Transform3D, size: Vector2, tex_path: String) -> MeshInstance3D:
	if not ResourceLoader.exists(tex_path):
		return null
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(tex_path)
	mat.roughness = 0.9
	quad.set_surface_override_material(0, mat)
	quad.transform = xform
	add_child(quad)
	return quad


func _spawn_cursed_panel(dist: float, side: float, size: Vector2, tex_path: String,
		y_center: float, intensity: float) -> void:
	_make_cursed_panel_at(_panel_transform(dist, side, y_center), size, tex_path, intensity)


# A turn mirror sits flush on the wall directly ahead at a corner (the wall you
# face if you fail to turn), so you approach the creature in the glass head-on.
func _spawn_turn_mirror(corner_dist: float, intensity: float) -> void:
	var pt := _path_point(corner_dist)
	var dir_in: Vector3 = pt.dir  # at a corner distance, _path_point returns the incoming segment
	var pos: Vector3 = pt.pos + dir_in * (W / 2.0 - 0.05) + Vector3(0, 1.5, 0)
	var face := -dir_in
	var xform := Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)), pos)
	var quad := _make_cursed_panel_at(xform, Vector2(1.4, 1.95), TURN_MIRROR_SCARE_PATH, intensity)
	_make_mirror_real(quad, pt, face)
	# `flashes` is decided in _pick_silent_mirror() once all three exist — one corner per run
	# is a corner and nothing else. The GAZE panel is untouched either way, so a player who
	# stops and stares at the silent mirror still pays for it.
	_turn_mirrors.append({ "pos": pos, "fired": false, "flashes": true })


# Build a gaze-panic panel (StaticBody + textured quad + collision + ScaryObject)
# at an arbitrary transform.
func _make_cursed_panel_at(xform: Transform3D, size: Vector2, tex_path: String,
		intensity: float) -> MeshInstance3D:
	# The ScaryObject must be an ANCESTOR of the collider — player.gd's gaze check
	# walks UP from the ray-hit StaticBody. Previously it was a child of the body,
	# so no cursed panel (paintings, clock, mirrors) ever fed gaze panic.
	# ScaryObject is a plain Node (no transform) and breaks the spatial chain, so
	# the world transform lives on the StaticBody3D itself (parent non-spatial ->
	# the body's local transform IS its global transform).
	var scary := ScaryObject.new()
	scary.scare_intensity = intensity
	add_child(scary)

	var body := StaticBody3D.new()
	body.transform = xform
	scary.add_child(body)

	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
	else:
		mat.albedo_color = Color(0.1, 0.08, 0.06)
	mat.roughness = 0.9
	quad.set_surface_override_material(0, mat)
	body.add_child(quad)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y, 0.1)
	col.shape = shape
	body.add_child(col)
	return quad


# ⭐ Turn a painted mirror into a REFLECTING one, and put something in it that is not in
# the corridor (2026-08-15).
#
# The old turn mirror was `mirror_with_creature.png` on a flat quad — the user's report was
# "it does not really look like a mirror," and it wasn't: nothing in this project reflected
# anything (no ReflectionProbe, no SSR, no SubViewport). See mirror_surface.gd.
#
# The creature is now a real `Watcher` standing in the corridor on MIRROR_ONLY_LAYER: the
# player's camera drops that layer (player.gd:_ready), the reflection camera keeps it. So
# the glass shows a figure over your shoulder, you turn round, and the corridor is empty —
# which is a far better beat than a painted figure, and it costs no panic and has no rules
# (watcher.gd), so it cannot kill anyone by surprise.
#
# ⚠️ Everything else about the turn mirror is untouched: the ScaryObject gaze intensity, the
# 2 m one-shot `flash_scare`, and `_pick_silent_mirror()`'s anti-habituation roll. Those are
# playtest-derived and were not part of this change.
const MIRROR_FIGURE_DIST := 7.0    # metres in front of the glass, i.e. behind the player
# ⚠️ ON THE CENTRELINE. An earlier 0.55 m offset looked better on paper — the figure would
# not sit directly behind your own head — but `Watcher.spawn()` rejected two of the three
# placements: the billboard is 1.6 m wide, so at 0.55 off-centre its edge came within
# 0.15 m of the wall of a 3 m corridor and the clearance fan refused it. Only one figure
# spawned, silently, because a refused spawn returns null rather than complaining. There is
# no player body to hide behind anyway (first person, no mesh), so centred is both safer
# and the better shot: the figure stands dead centre in the glass.
const MIRROR_FIGURE_SIDE := 0.0
const TURN_MIRROR_FIGURE_PATH := "res://assets/textures/shared/watcher_figure.png"

var _mirror_figure_spots: Array[Vector3] = []

func _make_mirror_real(quad: MeshInstance3D, pt: Dictionary, face: Vector3) -> void:
	if quad == null:
		return
	MirrorSurface.attach(quad)

	# The figure stands down the corridor the mirror looks along — the stretch the player
	# has just walked. `face` points from the glass back into that corridor.
	var side_vec: Vector3 = Vector3(face.z, 0, -face.x)
	var fig_pos: Vector3 = quad.global_position + face * MIRROR_FIGURE_DIST \
		+ side_vec * MIRROR_FIGURE_SIDE
	fig_pos.y = 0.0
	# ⚠️ QUEUED, not spawned here. `Watcher.spawn()` clearance-probes with raycasts, and
	# during `_ready()` the CSG colliders this level has just built are not yet registered
	# with the physics server — so the probe is querying an empty world and its answers are
	# meaningless. Measured: called inline, one of three figures survived; called from the
	# first _process tick, all three do, and the same call from a test probe at t=1 s always
	# worked, which is what pointed at timing rather than at placement.
	_mirror_figure_spots.append(fig_pos)


# Runs once, on the first frame, when physics knows about the level.
func _spawn_mirror_figures() -> void:
	for fig_pos in _mirror_figure_spots:
		# ⚠️ `require_los = false` because the player is 90+ m away round two corners, so an
		# LOS check would refuse every one of these. The clearance fan and head-room probes
		# still run, and the position comes off the corridor centreline, so it cannot land
		# inside geometry — the case require_los normally guards.
		var w := Watcher.spawn(self, fig_pos, TURN_MIRROR_FIGURE_PATH, 0.0, false)
		if w == null:
			continue
		# ⚠️ PERSISTENT, or it deletes itself. A default Watcher is an apparition: it expires
		# at MAX_LIFETIME and rolls to vanish whenever the player looks away and back. These
		# are fixtures — the thing in the glass has to be there every time you pass the
		# corner, and the look-away roll is meaningless for a figure the player's camera
		# cannot see at all.
		w.persistent = true
		# ⚠️ Named distinctly. Watcher.spawn() calls every one of them "Watcher", and Godot
		# silently renames the collisions — which made a test counting them by name report
		# one figure where three existed. The name also says what this one IS: not a roaming
		# Watcher, a fixture that lives in a mirror.
		w.name = "MirrorFigure%d" % _mirror_figure_spots.find(fig_pos)
		# Render it ONLY into mirrors. Watcher builds its own billboard quad, so walk its
		# meshes rather than assuming a shape.
		_set_mirror_only(w)
	_mirror_figure_spots.clear()


func _set_mirror_only(n: Node) -> void:
	if n is VisualInstance3D:
		n.layers = 1 << (MirrorSurface.MIRROR_ONLY_LAYER - 1)
	for c in n.get_children():
		_set_mirror_only(c)


func _spawn_fake_door(dist: float, side: float) -> void:
	var body := FakeDoor.new()
	body.transform = _panel_transform(dist, side, 1.05)
	add_child(body)

	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.4, 2.1)
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	var door_tex := TEX_DIR + "ordinary_hotel_door.png"
	if ResourceLoader.exists(door_tex):
		mat.albedo_texture = load(door_tex)
	else:
		mat.albedo_color = Color(0.15, 0.1, 0.06)
	mat.roughness = 0.9
	quad.set_surface_override_material(0, mat)
	body.add_child(quad)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.4, 2.1, 0.1)
	col.shape = shape
	body.add_child(col)


func _spawn_beartraps() -> void:
	for entry in BEARTRAPS:
		var pt := _path_point(entry[0])
		var trap := Beartrap.new()
		trap.position = pt.pos + (pt.side as Vector3) * entry[1]
		add_child(trap)


func _spawn_dark_zones() -> void:
	for zone_range in DARK_ZONES:
		_spawn_zone_boxes(zone_range, func() -> Area3D: return DarkZone.new())


func _spawn_dread_zone() -> void:
	_spawn_zone_boxes(DREAD_ZONE, func() -> Area3D: return DreadZone.new())


# Cover [range.x, range.y] of the path with axis-aligned Area3D boxes, one per
# segment slice. `make_zone` constructs the zone node type.
func _spawn_zone_boxes(zone_range: Vector2, make_zone: Callable) -> void:
	for seg in _segments:
		var a: float = maxf(zone_range.x, seg.start_d)
		var b: float = minf(zone_range.y, seg.start_d + seg.len)
		if b - a < 0.5:
			continue
		var zone: Area3D = make_zone.call()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(W, H, b - a)
		col.shape = shape
		zone.add_child(col)
		var mid2: Vector2 = seg.p0 + (seg.dir as Vector2) * ((a + b) / 2.0 - seg.start_d)
		zone.position = Vector3(mid2.x, H / 2.0, mid2.y)
		zone.rotation.y = atan2(seg.dir.x, seg.dir.y)
		add_child(zone)


# ---------------------------------------------------------------- doors & note

const _DOOR_SCRIPT := preload("res://scripts/door.gd")
const _NOTE_SCRIPT := preload("res://scripts/note.gd")


func _spawn_doors() -> void:
	# Exit: room 217 at the far end. Reaching it IS the win — unlock NONE.
	var end_pt := _path_point(_total_len)
	var exit_door: StaticBody3D = _make_door_body("ExitDoor")
	# Room 217 is a lie — you never walk through it. The noclip floor trigger in
	# front of it drops you into the Backrooms instead (see _spawn_noclip).
	exit_door.advances_level = false
	exit_door.position = end_pt.pos + Vector3(end_pt.dir.x, 0, end_pt.dir.z) * -0.08
	var exit_inward: Vector3 = -(end_pt.dir as Vector3)
	exit_door.rotation.y = atan2(exit_inward.x, exit_inward.z)
	_dress_exit_door(exit_door)

	# Back door at the start, returns to The House (blood-red per convention).
	var start_pt := _path_point(0.0)
	var back_door: StaticBody3D = _make_door_body("BackDoor")
	back_door.advances_level = false
	back_door.goes_back = true
	back_door.position = start_pt.pos + Vector3(start_pt.dir.x, 0, start_pt.dir.z) * 0.08
	back_door.rotation.y = atan2(start_pt.dir.x, start_pt.dir.z)
	_dress_back_door(back_door)


func _make_door_body(door_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = door_name
	body.set_script(_DOOR_SCRIPT)
	add_child(body)
	var col := CollisionShape3D.new()
	col.name = door_name + "Col"
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.6, 2.8, 0.2)
	col.shape = shape
	col.position.y = 1.4
	body.add_child(col)
	return body


func _dress_exit_door(body: StaticBody3D) -> void:
	var quad := MeshInstance3D.new()
	quad.name = "DoorMesh"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 3.0)
	quad.mesh = mesh
	# ⚠️ Sized from the ARTWORK's aspect, not chosen: `backrooms_tear_door.png` is
	# 774x1458 (1:1.884), so a 3.0 m tall panel is 1.593 wide. The old `door.png` was
	# 2:3 and the quad was 2.0x3.0 to match it; keeping 2.0 here would stretch the new
	# door 26% wide (SCARY.md §7.1(4)). 1.593 also happens to match the collider width
	# (1.6, see _make_door_body), which the old art did not.
	var tex_path := TEX_DIR + "backrooms_tear_door.png"
	var has_art: bool = ResourceLoader.exists(tex_path)
	if has_art:
		mesh.size = Vector2(1.593, 3.0)
	# ⚠️ UNSHADED, not emissive — and this door is the one place in the game where that is
	# the right answer. Measured, in this order:
	#
	#   emission 0.35-red @ 0.6, no emission_texture .. a flat red slab, art invisible.
	#     This was the reported bug: a red wash painted OVER the picture.
	#   door_material() — 0.6-red @ 0.08 WITH the texture .. the art, but uniformly red,
	#     because unlike the Lab's pale steel or the House's timber this artwork is
	#     already near-black, so a red tint is all that survives.
	#   white tint @ 0.42, then @ 0.14 ............... a flat LIGHT-GREY slab, and dropping
	#     the energy barely moved it; at 0.0 the door went black (sampled 16,12,12). The
	#     emission was reading as its flat colour rather than modulating the texture.
	#
	# The artwork measures 22/255 mean luma, so there is no emission tint that both lights
	# it and preserves it. Unshaded sidesteps the whole argument: the quad renders the art
	# exactly as authored — a black door with a red-lit tear already glowing inside it —
	# and is self-lit by definition, so it stays findable after the blackout force-kills
	# the flashlight. That is the only thing the blood-red door convention is really for.
	# `mirror_surface.gd` uses the same shading mode for the same reason.
	var mat: StandardMaterial3D
	if has_art:
		mat = StandardMaterial3D.new()
		mat.albedo_texture = load(tex_path)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		mat = _DOOR_SCRIPT.door_material("")
	quad.set_surface_override_material(0, mat)
	quad.position.y = 1.5
	body.add_child(quad)


func _dress_back_door(body: StaticBody3D) -> void:
	var door_mesh := MeshInstance3D.new()
	door_mesh.name = "DoorMesh"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 2.2, 0.15)
	door_mesh.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.01, 0.01)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.02, 0.02)
	mat.emission_energy_multiplier = 1.5
	door_mesh.set_surface_override_material(0, mat)
	door_mesh.position.y = 1.1
	body.add_child(door_mesh)


func _spawn_intro_note() -> void:
	var pt := _path_point(4.0)
	var table_pos: Vector3 = pt.pos + (pt.side as Vector3) * (W / 2.0 - 0.45)

	var table := CSGBox3D.new()
	table.name = "NoteTable"
	table.size = Vector3(0.5, 1.2, 0.4)
	table.use_collision = true
	table.position = table_pos + Vector3(0, 0.6, 0)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.16, 0.10, 0.05)
	wood.roughness = 0.8
	table.material = wood
	add_child(table)

	var note := StaticBody3D.new()
	note.name = "IntroNote"
	note.set_script(_NOTE_SCRIPT)
	note.note_text = NOTE_TEXT
	note.position = table_pos + Vector3(0, 1.25, 0)
	add_child(note)

	var note_mesh := MeshInstance3D.new()
	note_mesh.mesh = BoxMesh.new()
	(note_mesh.mesh as BoxMesh).size = Vector3(0.21, 0.01, 0.297)
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.05, 0.05, 0.04)
	paper.emission_enabled = true
	paper.emission = Color(0.55, 0.50, 0.35)
	paper.emission_energy_multiplier = 0.6
	note_mesh.set_surface_override_material(0, paper)
	note.add_child(note_mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.35, 0.12, 0.45)
	col.shape = shape
	note.add_child(col)

	_spawn_nightmare_plate()


# NIGHTMARE HINT 3/3 — and DUNGEON_NIGHTMARES.md §B2 calls it "the single most
# important hint in the game".
#
# THE NIGHTMARE's flagship tell is that the ambient bed and the music CUT OUT when a
# primary entity spawns. That is a mechanic made of an ABSENCE, and an absence
# cannot teach itself: a player who has never been told that the music is a signal
# hears silence and assumes the audio broke. The level does have a one-shot in-level
# scrawl for it, but a hint planted four levels earlier — in a place the player has
# already walked, that means nothing at the time — is the KONTUR pattern and by far
# the better version.
#
# Deliberately a NOTE rather than one of the wall-panel decals: notes are archived
# in the TAB journal, and a hint the player has to still remember four levels later
# needs to be re-readable. It is also why it is not in Zone C's near-black stretch.
func _spawn_nightmare_plate() -> void:
	const D := 250.0
	var pt := _path_point(D)
	var pos: Vector3 = pt.pos + (pt.side as Vector3) * (W / 2.0 - 0.12) + Vector3(0, 1.55, 0)

	var plate := StaticBody3D.new()
	plate.name = "LowerFloorsPlate"
	plate.set_script(_NOTE_SCRIPT)
	plate.note_text = "HOTEL VESPER — NOTICE TO NIGHT STAFF\n\n" \
		+ "WE STOPPED PLAYING MUSIC ON THE LOWER FLOORS.\n\n" \
		+ "The subjects complained they couldn't hear it stop.\n\n" \
		+ "Anyone working below the third landing is reminded that the absence of " \
		+ "the score is not a fault of the system. Do not report it. Do not go " \
		+ "looking for the fault. Stand still and listen to what is left."
	plate.position = pos
	plate.rotation.y = atan2((pt.side as Vector3).x, (pt.side as Vector3).z)
	add_child(plate)

	# A brass-ish wall plate. Faint emission only — enough to be findable in a
	# corridor lit at ~0.45, and well under 1.0 so it cannot clamp to flat white
	# (Issue 21). The BODY carries it because this prop has no separate art quad.
	var mesh := MeshInstance3D.new()
	mesh.name = "PlateMesh"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.46, 0.30, 0.02)
	mesh.mesh = bm
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.20, 0.17, 0.09)
	brass.metallic = 0.5
	brass.roughness = 0.55
	brass.emission_enabled = true
	brass.emission = Color(0.55, 0.46, 0.24)
	brass.emission_energy_multiplier = 0.3
	mesh.set_surface_override_material(0, brass)
	plate.add_child(mesh)

	var pcol := CollisionShape3D.new()
	var pshape := BoxShape3D.new()
	pshape.size = Vector3(0.5, 0.36, 0.14)
	pcol.shape = pshape
	plate.add_child(pcol)


# ---------------------------------------------------------------- events

func _spawn_events() -> void:
	_spawn_event(6.0, _ev_entry_slam)
	_spawn_event(46.0, _ev_clock_chime)
	_spawn_event(72.0, _ev_painting_fall)
	_spawn_event(138.0, _ev_lights_out)
	_spawn_event(188.0, _ev_whisper_oneshot)
	# ⚠️ The SECOND scripted painting fall was removed 2026-08-15. Between this level's two
	# placements and `RandomAmbient` rolling `painting_fall` as one of its three events every
	# 18-35 s, the same crash was landing many times in one walk. One scripted fall, and the
	# ambient roll is now capped (see `_ready`'s RandomAmbient.set_once_per_type call).
	_spawn_event(205.0, _ev_silhouette)
	_spawn_event(235.0, _ev_whisper_loop)
	_spawn_event(250.0, _ev_floor_crack)

	# ⚠️ The Manager no longer gets a `_spawn_event` of its own. It used to drop at
	# randf_range(80, 180) and fire COLD — a hard cut to a fullscreen image, which is F1's
	# diagnosis exactly. It is now the payoff of ONE of five identical telegraphs
	# (see _telegraph), so the same 25 panic buys ~100 m of dread instead of 0.85 s of
	# startle. MANAGER_DIST is retained only as the window TELEGRAPH_AT sits inside.
	_telegraph_payoff = randi() % TELEGRAPH_AT.size()
	for i in TELEGRAPH_AT.size():
		_spawn_event(TELEGRAPH_AT[i], _telegraph.bind(i))

	# Which door slams, and which one has someone standing in it. Both drawn from the
	# Zone-B doors only (90-230 m), the stretch this pass exists to fill.
	var zone_b: Array[int] = []
	for d in _ajar_doors:
		var dist: float = float(d.dist)
		if dist >= 90.0 and dist <= 230.0:
			zone_b.append(int(dist))
	if not zone_b.is_empty():
		_slam_index = zone_b.pick_random()
		_slam_dist = float(_slam_index) + DOOR_SLAM_LEAD
		_watcher_door = zone_b.pick_random()


# ---------------------------------------------------------------- the noclip

# The player never reaches room 217. The corridor plunges black and the flashlight dies,
# and then the floor gives way SHORT of the door — they can see it, torn open and lit
# from inside, and never get to touch it. Replaces the old clean door advance.
#
# ⚠️ The fall used to be AT the door (trigger centred at d = 318.5, i.e. its leading face
# 2.75 m out). The user's call 2026-08-15 was to drop the player ~5 m short, so the door
# stays a thing seen rather than a thing reached.
const NOCLIP_FALL_BEFORE_DOOR := 5.0   # metres from the door plane to the trigger's near face
const NOCLIP_TRIGGER_DEPTH := 2.5
# The blackout moved with it. At the old d = 310 onset a 5 m-earlier fall left barely 4 m
# of dark walking; at 15 m out the run-up is ~9 m again, which is what the beat is for.
const NOCLIP_ONSET_BEFORE_END := 15.0

var _noclip_armed: bool = false
var _noclip_fired: bool = false

func _spawn_noclip() -> void:
	_spawn_event(_total_len - NOCLIP_ONSET_BEFORE_END, _ev_noclip_onset)
	# Floor trigger, placed so its NEAR face — the one the player walks into — sits
	# NOCLIP_FALL_BEFORE_DOOR from the door. The door body itself is at _total_len - 0.08.
	var door_d: float = _total_len - 0.08
	# ⚠️ PLUS half the depth. The near face is at centre - depth/2, so to put that face
	# 5 m from the door the centre goes 5 m out and then half a box back TOWARD it.
	# Subtracting instead (the obvious-looking arithmetic) placed the fall 7.5 m out —
	# caught by check_noclip_fall.gd before the level was ever launched.
	var centre_d: float = door_d - NOCLIP_FALL_BEFORE_DOOR + NOCLIP_TRIGGER_DEPTH / 2.0
	var pt := _path_point(centre_d)
	var area := CorridorEvent.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(W, H, NOCLIP_TRIGGER_DEPTH)
	col.shape = shape
	area.add_child(col)
	area.position = pt.pos + Vector3(0, H / 2.0, 0)
	area.rotation.y = atan2(pt.dir.x, pt.dir.z)
	area.fired.connect(_ev_noclip_fall)
	add_child(area)


func _ev_noclip_onset() -> void:
	# Pitch black: every torch dies and the flashlight is force-killed (F now
	# only clicks). The last stretch before the floor goes is walked blind.
	_noclip_armed = true
	for entry in _torch_nodes:
		entry[1].extinguish()
	if _player.has_method("kill_flashlight"):
		_player.kill_flashlight()
	_play_at("creak", _path_point(_total_len - 6.0).pos + Vector3(0, 1.5, 0), 2.0)


# Where the floor gives way, in path distance. Exposed so tests can assert the gap to the
# door and to the re-entry cap without re-deriving the arithmetic (which is how the two
# constants drifted apart in the first place).
func noclip_fall_distance() -> float:
	return (_total_len - 0.08) - NOCLIP_FALL_BEFORE_DOOR + NOCLIP_TRIGGER_DEPTH / 2.0


# ⭐ THE FLOOR GIVES WAY AND YOU ACTUALLY FALL (2026-08-15, user's call).
#
# ⚠️ This used to fade to black and wait two seconds, which is not a fall — the player
# stood still while the screen dimmed. Reported as "there is still no such thing as the
# visual like you are falling; I want like you just walk and fall through the floor."
#
# The player is a CharacterBody3D, so zeroing its `collision_mask` means nothing holds it
# up any more: `player.gd:_apply_gravity()` already runs every frame and `is_on_floor()`
# goes false, so it accelerates downward through the floor under real gravity. The camera
# falls with it and the corridor rushes up past the view.
#
# ⚠️ Done this way rather than by cutting a hole. The corridor floor is ONE CSGBox3D per
# 45 m segment (`_build_geometry`), so there is no local piece to delete the way
# `kontur.gd:_open_the_void()` deletes a room's floor — it would need a CSG subtraction and
# a collision rebuild, for a hole nobody can see: the blackout killed every light 10 m ago.
# What the player is owed here is the SENSATION, and that is entirely in the falling.
const FALL_FADE_AT := -3.0     # metres below the floor before the screen starts to go
const FALL_ADVANCE_AT := -9.0  # and where the Backrooms takes over

# ⭐ THE FALL IS NOW SHOWN, NOT SIMULATED (user's call): the cutscene covers the screen the
# instant the floor gives way, so what the player sees is entirely the video — the shaft, the
# watchers leaning over the hole, the walls turning Backrooms-yellow — and the Backrooms loads
# when it ends rather than at a depth.
#
# ⚠️ The physics fall below is UNCHANGED and still runs, invisibly, behind the video. Two
# reasons, both load-bearing:
#   1. `tests/check_noclip_fall.gd` asserts the player actually drops >1 m in 1.2 s. That guard
#      exists because this ending shipped twice as a fade with the player standing still.
#   2. `CutscenePlayer.play()` returns null headless and if the file is missing, and then the
#      old depth-driven fade/advance in `_tick_fall()` is what completes the level.
# So the video is a presentation layer over the fall, never a replacement for it.
const FALL_VIDEO := "res://assets/video/fall_scene.ogv"

var _fall_cutscene: bool = false

func _ev_noclip_fall() -> void:
	if not _noclip_armed or _noclip_fired:
		return
	_noclip_fired = true

	_player.collision_mask = 0
	# No steering on the way down; you are falling, not flying.
	if _player.has_method("freeze_input"):
		_player.freeze_input()

	var cutscene := CutscenePlayer.play(self, FALL_VIDEO)
	if cutscene != null:
		_fall_cutscene = true
		cutscene.finished.connect(_on_fall_cutscene_finished)
	else:
		# Fallback path: no video, so the break has to be sold in-engine as it always was.
		# Keep the jolt and the creak — they are the sound of it breaking. With the cutscene
		# they are dropped, because the clip carries its own floor-collapse audio and the
		# camera shake is behind an opaque overlay where nobody can see it.
		_player.jolt_camera(0.12, 0.5)
		_play_at("creak", _player.global_position, 3.0)

	set_process(true)   # _process drives the rest — see _tick_fall()


func _on_fall_cutscene_finished() -> void:
	if not _noclip_fired:
		return
	_noclip_armed = false      # belt and braces against a second entry
	GameState.advance_level()  # -> The Backrooms


var _fall_fading: bool = false

# Driven from _process while the player is falling. Deliberately not an `await` chain: the
# distance fallen is what advances the level, so a slow frame or a long drop cannot desync
# the fade from the transition the way a fixed 2 s timer did.
func _tick_fall() -> void:
	if not _noclip_fired or _player == null or not is_instance_valid(_player):
		return
	# The cutscene owns the fade (it is opaque) and the transition (it advances on `finished`).
	# The body below is the no-video fallback only.
	if _fall_cutscene:
		return
	var y: float = _player.global_position.y
	if not _fall_fading and y <= FALL_FADE_AT:
		_fall_fading = true
		var layer := CanvasLayer.new()
		layer.layer = 80
		add_child(layer)
		var fade := ColorRect.new()
		fade.color = Color(0, 0, 0, 0)
		fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.add_child(fade)
		var tween := create_tween()
		tween.tween_property(fade, "color:a", 1.0, 0.8)
	if y <= FALL_ADVANCE_AT:
		_noclip_armed = false      # belt and braces against a second entry
		GameState.advance_level()  # -> The Backrooms


func _spawn_event(dist: float, callback: Callable) -> void:
	var pt := _path_point(dist)
	var ev := CorridorEvent.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(W, H, 2.0)
	col.shape = shape
	ev.add_child(col)
	ev.position = pt.pos + Vector3(0, H / 2.0, 0)
	ev.rotation.y = atan2(pt.dir.x, pt.dir.z)
	ev.fired.connect(callback)
	add_child(ev)


func _play_at(base_name: String, pos: Vector3, volume_db: float = 0.0) -> void:
	var stream := GameState.load_audio(base_name)
	if not stream:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.unit_size = 8.0
	p.max_db = 6.0
	add_child(p)
	p.position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _ev_manager() -> void:
	# Survivable: a flash, a scream, a panic spike — only fatal if you were
	# already near the edge. Guarded so it never double-fires.
	if _manager_fired:
		return
	_manager_fired = true
	Screamer.flash_scare(MANAGER_SCARE_PATH, "screamer_manager", 0.85)
	_player.jolt_camera(0.09, 0.6)
	_player.add_panic(MANAGER_PANIC)


func _ev_entry_slam() -> void:
	# The way back slams shut behind you.
	_play_at("door_slam", _path_point(0.5).pos + Vector3(0, 1.2, 0), 2.0)
	_player.add_panic(10.0)


func _ev_clock_chime() -> void:
	_play_at("clock_chime", _panel_transform(48.0, 1.0, 1.5).origin, 1.0)
	_player.add_panic(10.0)


func _ev_lights_out() -> void:
	_play_at("glass_shatter", _path_point(150.0).pos + Vector3(0, 2.4, 0), 3.0)
	for entry in _torch_nodes:
		if entry[0] >= SHATTER_RANGE.x and entry[0] <= SHATTER_RANGE.y:
			entry[1].extinguish()


func _ev_whisper_oneshot() -> void:
	_play_at("whispers", _path_point(200.0).pos + Vector3(0, 1.5, 0), -6.0)


func _ev_silhouette() -> void:
	# Something crosses the junction ahead, far down the hall.
	var pt := _path_point(228.5)
	var fig := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.75
	fig.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.03)
	mat.emission_enabled = true
	mat.emission = Color(0.06, 0.05, 0.07)
	mat.emission_energy_multiplier = 0.4
	fig.set_surface_override_material(0, mat)
	add_child(fig)
	var side3: Vector3 = pt.side
	fig.position = pt.pos + side3 * 1.2 + Vector3(0, 0.9, 0)
	var tween := create_tween()
	tween.tween_property(fig, "position", pt.pos - side3 * 1.2 + Vector3(0, 0.9, 0), 0.7)
	tween.tween_callback(fig.queue_free)
	_play_at("jumpscare", pt.pos + Vector3(0, 1.2, 0), -14.0)
	_player.add_panic(20.0)


func _ev_whisper_loop() -> void:
	# Constant low whispers for the rest of the walk (Zone C).
	var stream := GameState.load_audio("whispers")
	if not stream:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = -10.0
	p.unit_size = 14.0
	p.max_db = -4.0
	add_child(p)
	p.position = _path_point(290.0).pos + Vector3(0, 1.5, 0)
	p.finished.connect(p.play)
	p.play()


func _ev_floor_crack() -> void:
	# The floor splits under your feet.
	_play_at("creak", _player.global_position, 4.0)
	_player.jolt_camera(0.06, 0.45)
	_player.add_panic(10.0)
	if ResourceLoader.exists(TEX_DIR + "floor_crack.png"):
		var quad := _spawn_quad(Transform3D(), Vector2(1.8, 1.4), TEX_DIR + "floor_crack.png")
		if quad:
			quad.position = Vector3(_player.global_position.x, 0.012, _player.global_position.z)
			quad.rotation_degrees.x = -90.0

func _ev_painting_fall() -> void:
	# Картина срывается со стены перед игроком.
	var pt := _path_point(_player.global_position.length())
	var painting_pos := _player.global_position + Vector3(randf_range(-2.0, 2.0), 1.8, randf_range(-2.0, 2.0))

	# Звук падения
	_play_at("painting_fall", painting_pos, 1.5)
	_player.add_panic(8.0)

	# Визуал: квад-картина падает вниз
	var quad := _spawn_quad(Transform3D(), Vector2(1.5, 1.2), TEX_DIR + "painting.png")
	if quad:
		quad.position = painting_pos
		quad.rotation.y = randf_range(-PI, PI)
		var tween := create_tween()
		tween.tween_property(quad, "rotation:z", PI / 2.0, 0.35).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(quad, "position:y", 0.05, 0.4).set_ease(Tween.EASE_IN)
		tween.tween_callback(quad.queue_free)

# ---------------------------------------------------------------- ambience

func _start_ambience() -> void:
	var ambient: AudioStreamPlayer = get_node_or_null("AmbientPlayer")
	if not ambient:
		return
	# ⚠️ NOT on the duckable `Ambience` bus (2026-08-15, user's call: "let's leave music to
	# be present in the entire level"). `_tick_hush()` pulls `Ambience` down by 40 dB for
	# the last 25 m, which used to take this bed with it and leave the walk to the fall in
	# total silence. On its own bus the hush still silences the WORLD — the whispers loop
	# and RandomAmbient's one-shots, which is the beat the hush exists for — while the
	# score plays through to the floor giving way. Same reasoning as `kontur.gd` keeping
	# `kontur_music` off the ducked path.
	# ⚠️ Ensure BEFORE assigning. Godot resolves a bus by name at assignment time and falls
	# back to Master silently if it does not exist yet — which would look like it worked
	# and leave the score un-bussed. (`check_audio_buses.gd` documents the same trap.)
	AudioBuses.ensure_music_bus(_MUSIC_BUS)
	ambient.bus = _MUSIC_BUS
	var s := GameState.load_audio("ghost_house")
	if s:
		ambient.stream = s
	if ambient.stream:
		ambient.volume_db = -6.0
		ambient.finished.connect(ambient.play)
		ambient.play()
