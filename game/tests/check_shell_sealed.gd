extends SceneTree

# YOU CANNOT SEE OUT OF ANY LEVEL IN THE GAME — floor under you, ceiling over you, and
# nothing but wall in every direction, from everywhere a player can stand.
#
#   Godot --headless --path game --script res://tests/check_shell_sealed.gd
#   Godot --headless --path game --script res://tests/check_shell_sealed.gd -- Flood
#
# WHY THIS EXISTS. On the 2026-08-17 verification replay the player stood in the Sprawl at
# local (-17.30, -12.20), photographed a gap in the wall opening onto the PROCEDURAL SKY —
# blue-grey horizon, a mirage door silhouetted against it — and wrote "What is that for?".
#
# The cause was one ternary: `backrooms_zone2.gd:_build_alcoves()` built the E and W alcoves'
# BACK walls with the side walls' dimensions, so each was a 3 m blade lying along the depth
# axis instead of a 3.4 m panel across it. All four E/W recesses were open to the world,
# 3.40 x 4.50 m each.
#
# ⚠️ IT SURVIVED A GUARD THAT HAD BEEN WRITTEN FOR THIS EXACT ZONE, THREE HOURS EARLIER.
# `check_sprawl_alcoves.gd` fires a "shell closed" ray outward from each recess CENTRE — and
# the blade sits exactly on that line. The ray hit it at 0.15 m and reported the wall present.
# A single centred ray cannot see a hole shaped like a doorway. `apparition.gd:_fits()` fans
# 16 rays and its comment says why; that lesson had simply never been applied here.
#
# WHAT THIS ASSERTS, with physics queries and nothing else:
#
#   1. PERIMETER SWEEP.  Along all four Sprawl walls, at 0.25 m laterally and six heights
#      from ankle to just under the 4.5 m ceiling, a ray fired outward from 1 m inside must
#      be stopped. 3816 rays. This is the sweep that would have caught the shipped bug at
#      any of ~400 sample points.
#   2. ALCOVE HEMISPHERES. From five points inside each of the eight recesses, every ray in
#      the outward hemisphere must be stopped (1320 rays). Catches a back corner, which a
#      lateral sweep down one wall cannot see.
#   3. INTERIOR SWEEP, ALL THREE ZONES. A 1.5 m floor grid over the whole level — found by
#      down-ray, so it only ever samples where the world actually has a floor, and filtered
#      to places a 0.4 m capsule could stand — then 18 horizontal rays at up to 4 heights
#      plus one straight up from each. ~61,000 rays over 883 points. Nothing may escape.
#   4. FLOOR AND CEILING. Every grid point has floor under it and ceiling over it.
#
# ⚠️ IT COVERS THE FLOOD TOO, and the Flood came out CLEAN. Every apparent opening there was
# a measurement artifact, and each one is documented at the constant that removed it — a
# sample buried in a wall slab, a 45° ray threading a room corner, an eye 0.6 m above a
# 2.6 m ceiling because it was standing on the 0.4 m DryPlatform. Read those before
# "fixing" anything this file reports: three quarters of a day's findings here were the
# test's own geometry, not the level's.
#
# ⚠️ A GLITCH WALL IS A HOLE ON PURPOSE — it is walk-through and has no collider, because
# walking into it IS the win condition. So a ray that hits nothing is forgiven only if it
# crosses the world AABB of a VISIBLE `GlitchWall` mesh: sealed to the eye, open to the body,
# which is exactly what that prop is. Everything else is a finding.
#
# ⚠️ PROOF IT CAN FAIL, kept permanently, and BOTH SWEEPS HAVE ONE. `_control_punch()` frees
# `AlcBackE1` — recreating the shipped bug precisely — and then:
#   * the perimeter sweep must go RED on the E side and report a gap of at least 3 m
#     (measured: 66 open rays, 3.25 m), having measured that same side CLEAN a moment
#     earlier with the wall still in place;
#   * the interior sweep's own logic, re-run over the patch of hall floor in front of that
#     alcove, must see it too (measured: 48 escaping rays from 46 standable samples).
# The second control exists because the first proves nothing about `_unstandable()` or the
# `head` clamp, and either of those could reject every sample and leave a tidy green zero.

# ------------------------------------------------------------------ coverage
#
# ⚠️ A SWEEP SINCE 2026-08-17 (workstream H1). The perimeter and alcove passes are about the
# Sprawl and stay that way; the INTERIOR pass — "from everywhere a player can stand, is every
# horizontal ray stopped, is there floor under them and ceiling over them" — is a question
# every level in the game has an answer to and only one had ever been asked. It now iterates
# `tests/lib/scenes.gd`, which is derived from `GameState`'s own `SCENE_*` constants.
#
# ⚠️ AND EVERY SCENE GETS A CONTROL, not just the Backrooms. `_control_punch()` frees a
# named Sprawl wall; on every other level `_generic_control()` picks a standable sample, finds
# the wall in front of it BY RAY, deletes that node and requires the sweep to see the hole. A
# sweep with no control is a sweep that can quietly stop measuring: `_unstandable()` rejecting
# every sample would leave "0 escaping rays" and a tidy green.

const Scenes := preload("res://tests/lib/scenes.gd")

# ---------------------------------------------------------------- the per-scene rows
#
#   min_points     standable samples this scene must produce
#   backrooms      run the Sprawl-specific perimeter/alcove/glitch-wall passes
#   filed_escapes  known escaping rays that are NOT being fixed here, with the reason and the
#                  exact count. ⚠️ An exact count, not a ceiling: a fix moves it as loudly as
#                  a regression does.
#   filed_open     ...and the same for standable points with no ceiling over them.
const CONFIG := {
	"SCENE_INTRO": {"min_points": 40},
	"SCENE_LEVEL_1": {"min_points": 90},
	"SCENE_LEVEL_2": {
		# ⚠️ 60, and the House is the level that made the floor-level derivation necessary:
		# ground floor at 0, the cellar ramp at -0.8 and the cellar at -1.5, measured
		# 59 + 3 + 11 standable points. Three "zones" that are really three storeys.
		"min_points": 60,
	},
	"SCENE_CORRIDOR": {"min_points": 200},
	"SCENE_BACKROOMS": {"min_points": 300, "backrooms": true},
	"SCENE_KONTUR": {"min_points": 150, "seeds": [7]},
	"SCENE_LEVEL_6_BREACH": {"min_points": 150},
	"SCENE_DUNGEON": {"min_points": 200, "seeds": [1]},
	"SCENE_LEVEL_3": {
		# ⚠️ FILED, NOT FIXED, and the count is exact. THE VOID IS DELIBERATELY BROKEN
		# GEOMETRY — "corridors loop, geometry distorted, floating tiles", a floor opened
		# around a 1.6 m hole that is a fatal fall by design — so "you cannot see out of it"
		# is not obviously a requirement there the way it is everywhere else. What the sweep
		# measures is that 142 rays from 48 standable points leave the level entirely, i.e.
		# the Void has no shell. That is Level 8's own pass to rule on: it may be intended,
		# it may be why the level reads as unfinished, and it is not this pass's call.
		# backlogs/08-void.md.
		"min_points": 40, "filed_escapes": 142,
	},
}

const SCENE := "res://scenes/backrooms.tscn"

const PERIM_STEP := 0.25         # lateral spacing of the perimeter sweep
const PERIM_HEIGHTS := [0.3, 1.0, 1.7, 2.6, 3.6, 4.3]
const RAY_LEN := 90.0            # longer than any diagonal in any zone
const GRID_STEP := 1.5
const GRID_HEIGHTS := [0.4, 1.2, 2.0, 2.8]
# ⚠️ 18 BEARINGS WITH AN ANGULAR PHASE, NOT 16 ON THE COMPASS POINTS — same reasoning as
# PHASE_X, one dimension up. Every wall here is axis-aligned, so a fan of 16 contains 45°
# and 90° exactly, and a 45° ray can thread the corner where an alcove's back wall meets its
# side wall: a measure-zero seam that is not a hole and that nobody can see. Measured, it
# reported 199 "escapes" — 4 heights x ~50 grid points, all of them on ONE diagonal line,
# because a 1.5 m square grid puts fifty samples on the same 45° ray. 20° steps offset by
# 3.7° means no ray in this file is ever parallel to, or diagonal across, a wall.
const GRID_DIRS := 18
const ANGLE_PHASE := 0.0646        # ~3.7 degrees

# ⚠️ SAMPLE PHASE, AND IT IS NOT A FUDGE FACTOR. Every wall in this level sits at a round
# coordinate, so a grid on round coordinates puts samples EXACTLY ON WALL FACES — and
# `intersect_ray` ignores any shape whose origin is already inside it, so a ray fired from a
# point sitting in a wall plane sails 90 m and reports a hole that is not there. Measured on
# the first run: 1020 "escaping" rays, every one of them from a sample dead on a face
# (x = -13.00 is the W arm cap's inner face, to the centimetre). Offsetting by a couple of
# irregular centimetres removes the degeneracy without moving what is sampled.
const PHASE_X := 0.13
const PHASE_Z := 0.07
const PERIM_PHASE := 0.11
# ⚠️ ...and the same reasoning at the four corners of the hall: at u = ±HALF the sample is
# inside the perpendicular wall. A player cannot put an eye there either — their capsule is
# 0.4 m in radius — and the corner is covered by both sides' sweeps meeting short of it.
const PERIM_CORNER_MARGIN := 0.15
# A point closer than this to anything is not a place a player can stand (capsule radius 0.4),
# so it is not a place they can see out from. Skipping them also guarantees no ray in the
# interior sweep ever starts inside a collider.
const MIN_CLEARANCE := 0.45

var _t := 0.0
var _stage := 0
var _stage_at := 0.0
var _scene: Node = null
var _player: CharacterBody3D = null
var _b: Dictionary = {}
var _c2: Dictionary = {}
var _fails: Array[String] = []
var _checks := 0

var _glitch: Array[AABB] = []
var _perim_rays := 0
var _grid_rays := 0
var _grid_points := 0

var _rows: Array = []
var _row := 0
var _cfg: Dictionary = {}
var _summary: Array = []
var _only := ""
var _samples: Array[Vector3] = []      # standable feet positions, for the generic control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if not a.begins_with("--"):
			_only = a
	for p in Scenes.problems():
		print("  FAIL enrolment: %s" % p)
		_fails.append("enrolment: " + String(p))
	for row in Scenes.levels():
		if _only != "" and String(row["label"]).to_lower().find(_only.to_lower()) < 0:
			continue
		var cfg: Dictionary = (CONFIG.get(row["key"], {}) as Dictionary).duplicate(true)
		cfg["label"] = String(row["label"])
		cfg["path"] = String(row["path"])
		cfg["settle"] = float(row["settle"])
		for sd in cfg.get("seeds", [1]):
			var one := cfg.duplicate(true)
			one["seed"] = int(sd)
			_rows.append(one)
	if _rows.is_empty():
		print("SHELL-SEALED FAIL: no scene matched %s" % _only)
		quit(1)
		return
	_load_row()


func _load_row() -> void:
	_cfg = _rows[_row]
	_glitch = []
	_samples = []
	_grid_points = 0
	_grid_rays = 0
	_perim_rays = 0
	_t = 0.0
	_stage = 0
	_stage_at = 0.0
	Scenes.pin_rng(int(_cfg["seed"]))
	change_scene_to_file(String(_cfg["path"]))


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _process(delta: float) -> bool:
	_t += delta
	var backrooms: bool = bool(_cfg.get("backrooms", false))
	match _stage:
		0:
			# ⚠️ TIME, never a frame count (X42). CSG colliders are not registered during
			# `_ready()` (Issue 52) either, and every ray in this file comes back empty
			# without real frames first — which would report the entire level as a hole.
			if _t < maxf(1.5, float(_cfg["settle"])):
				return false
			_scene = current_scene
			_player = _scene.get_node_or_null("Player") as CharacterBody3D
			print("")
			print("--- shell: %s (%s, seed %d) ---"
				% [_cfg["label"], _cfg["path"], int(_cfg["seed"])])
			_ok("%s: player found" % _cfg["label"], _player != null)
			if _player == null:
				_row += 1
				if _row >= _rows.size():
					return _report()
				_load_row()
				return false
			if backrooms:
				_b = (load("res://scripts/backrooms.gd") as GDScript) \
					.get_script_constant_map()
				_c2 = (load("res://scripts/backrooms_zone2.gd") as GDScript) \
					.get_script_constant_map()
				_ok("read both constant maps", _b.size() > 10 and _c2.size() > 10,
					"%d / %d" % [_b.size(), _c2.size()])
				_collect_glitch()
				_perimeter()
				_alcove_hemispheres()
			else:
				_collect_glitch_generic()
			_interior()
			_stage = 1
			_stage_at = _t
		1:
			if backrooms:
				_control_punch()
			else:
				_generic_punch()
			_stage = 2
			_stage_at = _t
		2:
			# The freed CSG box needs a frame before its collider is really gone.
			if _t - _stage_at < 0.5:
				return false
			if backrooms:
				_control_check()
			else:
				_generic_control_check()
			_row += 1
			if _row >= _rows.size():
				return _report()
			_load_row()
			return false
	if _t > 180.0:
		print("RESULT: FAIL — timed out on %s at stage %d" % [_cfg["label"], _stage])
		quit(1)
		return true
	return false


# ---------------------------------------------------------------- helpers

func _space() -> PhysicsDirectSpaceState3D:
	return _scene.get_viewport().find_world_3d().direct_space_state


func _all(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children():
		_all(c, out)
	return out


# Every walk-through-but-visible surface in the level, as a world AABB grown a little so a
# ray grazing its plane still counts.
#
# ⚠️ THIS IS AN EXEMPTION LIST, so it carries the same discipline `check_wall_overlap.gd`
# puts on `_allow`: the COUNT is asserted. Eight, and they are not interchangeable —
#   zone 1  THE LOBBY   1  the utility room's exit, a bare MeshInstance3D named "GlitchWall"
#   zone 2  THE SPRAWL  4  `GlitchWall` instances, one per side, one of them real
#   zone 3  THE FLOOD   3  `GlitchWall` instances, one real seam + two decoys
# If a ninth appears, or one stops being visible, this fails rather than quietly widening
# the set of directions in which the level is allowed to have no wall.
const EXPECTED_GLITCH := 8
# ⚠️ ...and three of the eight are ALLOWED to be invisible right now: the Flood's tell is
# that its real seam shows only with the flashlight OFF and its two decoys only with it ON,
# so exactly one of those states is hidden at any moment. They still seal the view, because
# a Flood seam hangs on a RoomBuilder room's real north wall rather than replacing it. The
# other five ARE the wall they stand in, so they must be visible.
const MAY_BE_HIDDEN := ["FloodSeam", "DecoyCistern", "DecoyBasin"]

func _collect_glitch() -> void:
	var hidden: Array[String] = []
	var found := 0
	for n in _all(_scene, []):
		if not (n is Node3D):
			continue
		# Both spellings: the Sprawl and the Flood build `GlitchWall` nodes; zone 1's exit
		# is a plain MeshInstance3D that predates the class.
		if not (n is GlitchWall or String(n.name).begins_with("GlitchWall")):
			continue
		if n is MeshInstance3D and n.get_parent() is GlitchWall:
			continue                       # already covered by its owner
		var g := n as Node3D
		found += 1
		if not g.is_visible_in_tree() and not MAY_BE_HIDDEN.has(String(g.name)):
			hidden.append(String(g.name))
		var box := AABB()
		var first := true
		for m in _all(g, []):
			if not (m is MeshInstance3D):
				continue
			var mi := m as MeshInstance3D
			if mi.mesh == null:
				continue
			var wa := mi.global_transform * mi.get_aabb()
			box = wa if first else box.merge(wa)
			first = false
		if first:
			continue
		_glitch.append(box.grow(0.35))
	_ok("every walk-through surface was found", found == EXPECTED_GLITCH,
		"%d found, expected exactly %d" % [found, EXPECTED_GLITCH])
	_ok("...and the five that ARE a wall are visible", hidden.is_empty(),
		"hidden: %s" % str(hidden))
	_ok("...and every one yielded a mesh volume to exempt",
		_glitch.size() == found, "%d volumes for %d nodes" % [_glitch.size(), found])


# The same collection WITHOUT the Backrooms' count assertions, for every other level. Most
# have none at all; the point is that if one ever grows a walk-through surface, the sweep
# forgives a ray through it rather than reporting a hole that is a feature.
func _collect_glitch_generic() -> void:
	var found := 0
	for n in _all(_scene, []):
		if not (n is Node3D):
			continue
		if not (n is GlitchWall or String(n.name).begins_with("GlitchWall")):
			continue
		if n is MeshInstance3D and n.get_parent() is GlitchWall:
			continue
		var g := n as Node3D
		found += 1
		var box := AABB()
		var first := true
		for m in _all(g, []):
			if not (m is MeshInstance3D):
				continue
			var mi := m as MeshInstance3D
			if mi.mesh == null:
				continue
			var wa := mi.global_transform * mi.get_aabb()
			box = wa if first else box.merge(wa)
			first = false
		if not first:
			_glitch.append(box.grow(0.35))
	if found > 0:
		print("  NOTE  %d walk-through surface(s) exempted in %s" % [found, _cfg["label"]])


# True when the segment from->to is stopped by geometry, or crosses a visible glitch wall.
func _stopped(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = [_player.get_rid()]
	if not _space().intersect_ray(q).is_empty():
		return true
	var dir := (to - from)
	for box in _glitch:
		var hit: Variant = box.intersects_ray(from, dir)
		if hit != null:
			return true
	return false


# Eight short rays at chest height: is there anything within MIN_CLEARANCE?
#
# ⚠️ RAYS, NOT `intersect_shape`. A shape query against CSG reports NOTHING when the query
# shape's origin is inside the box (Issue 40, and measured again on the hub pilasters while
# diagnosing backlog 04 R2), which would silently approve exactly the samples this is meant
# to reject.
#
# ⚠️⚠️ A POINT QUERY FIRST, AND IT IS THE HALF THAT MATTERS. A grid sample can land INSIDE a
# 0.2 m wall slab, and a ray fired from in there reports NOTHING in every direction — it
# exits through a back face, which is culled. So a sample buried in a wall reads as a sample
# in a room with no walls at all, and the test declares a hole in the wall it is standing in.
# Measured: 128 phantom "escapes" in the Flood, all from one sample at z = 17.07, inside a
# wall box spanning z 16.90..17.10.
#
# ⚠️ AND `hit_from_inside = true` DOES NOT FIX IT HERE, which is worth writing down because
# it is the obvious fix and it was tried (tests/probe_inside_ray.gd, deleted): CSG geometry
# collides as a ConcavePolygonShape3D, and that flag only means anything for a CONVEX shape.
# Measured on this exact point: `hit_from_inside` true and false both return NOTHING in all
# three directions tried, while `intersect_point` at the same position returns 1 collider.
# This is Issue 40's family — a query type that silently answers "clear" for the one case you
# are asking about — and `intersect_point` is the member of it that works.
func _unstandable(feet: Vector3) -> bool:
	for y in [0.3, 1.2]:
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = feet + Vector3(0, y, 0)
		pq.collide_with_bodies = true
		pq.collide_with_areas = false
		pq.exclude = [_player.get_rid()]
		if not _space().intersect_point(pq, 4).is_empty():
			return true
	var eye := feet + Vector3(0, 1.2, 0)
	for i in range(8):
		var a := TAU * float(i) / 8.0 + ANGLE_PHASE
		var dir := Vector3(cos(a), 0, sin(a))
		var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * MIN_CLEARANCE)
		q.collision_mask = 1
		q.exclude = [_player.get_rid()]
		if not _space().intersect_ray(q).is_empty():
			return true
	return false


func _sprawl_origin() -> Vector3:
	var z2 := _scene.get_node_or_null("ZoneSprawl") as Node3D
	return z2.global_position if z2 else _b["ZONE2_ORIGIN"]


# ---------------------------------------------------------------- 1 perimeter sweep

func _perimeter(only_side: String = "", quiet: bool = false) -> Dictionary:
	var org := _sprawl_origin()
	var half: float = _c2["HALF"]
	var open_by_side := {}
	var worst := 0.0
	for s in _c2["SIDES"]:
		if only_side != "" and String(s) != only_side:
			continue
		var axis: Vector3 = _c2["SIDE_AXIS"][s]
		var lat := Vector3(axis.z, 0, axis.x)
		var run := 0.0
		var side_open := 0
		var u := -half + PERIM_CORNER_MARGIN + PERIM_PHASE
		while u <= half - PERIM_CORNER_MARGIN:
			var hole := false
			for y in PERIM_HEIGHTS:
				var from: Vector3 = org + axis * (half - 1.0) + lat * u + Vector3(0, y, 0)
				_perim_rays += 1
				if not _stopped(from, from + axis * RAY_LEN):
					hole = true
					side_open += 1
			if hole:
				run += PERIM_STEP
				worst = maxf(worst, run)
			else:
				run = 0.0
			u += PERIM_STEP
		if side_open > 0:
			open_by_side[String(s)] = side_open
		u += PERIM_STEP
	if not quiet:
		_ok("the Sprawl perimeter stops every outward ray", open_by_side.is_empty(),
			"open rays by side: %s (widest continuous gap %.2f m)" % [str(open_by_side), worst])
		# ⚠️ Sample size is part of the assertion. 4 sides x 161 laterals x 6 heights.
		_ok("the perimeter sweep measured a meaningful sample", _perim_rays >= 3800,
			"%d rays" % _perim_rays)
	return {"open": open_by_side, "widest": worst}


# ---------------------------------------------------------------- 2 alcove hemispheres

func _alcove_hemispheres() -> void:
	var org := _sprawl_origin()
	var half: float = _c2["HALF"]
	var d: float = _c2["ALCOVE_D"]
	var w: float = _c2["ALCOVE_W"]
	var at: float = _c2["ALCOVE_AT"]
	var bad: Array[String] = []
	var fired := 0
	var probed := 0
	for s in _c2["SIDES"]:
		var axis: Vector3 = _c2["SIDE_AXIS"][s]
		var lat := Vector3(axis.z, 0, axis.x)
		for k in [-1, 1]:
			var centre: Vector3 = org + axis * (half + d / 2.0) + lat * (float(k) * at)
			for spot in [Vector3.ZERO, lat * (w / 2.0 - 0.55), lat * -(w / 2.0 - 0.55),
					axis * (d / 2.0 - 0.55), axis * -(d / 2.0 - 0.55)]:
				probed += 1
				for y in [0.4, 1.6, 3.2]:
					var from: Vector3 = centre + spot + Vector3(0, y, 0)
					for i in range(24):
						var a := TAU * float(i) / 24.0 + ANGLE_PHASE
						var dir := (lat * cos(a) + axis * sin(a)).normalized()
						# Only the OUTWARD hemisphere — the mouth is meant to be open.
						if dir.dot(axis) <= 0.15:
							continue
						fired += 1
						if not _stopped(from, from + dir * RAY_LEN):
							bad.append("Alc%s%+d %.1f m up, bearing %d°"
								% [s, k, y, int(rad_to_deg(a))])
	_ok("every alcove is closed in the whole outward hemisphere", bad.is_empty(),
		"%d escaping ray(s): %s" % [bad.size(), ", ".join(bad.slice(0, 6))])
	_ok("the hemisphere sweep measured a meaningful sample",
		probed == 40 and fired >= 800, "%d spots, %d rays" % [probed, fired])


# ---------------------------------------------------------------- 3 interior sweep

# Zone bounding boxes in world space, generous enough to cover each zone's outbuildings.
func _zone_boxes() -> Array:
	if not bool(_cfg.get("backrooms", false)):
		return _derived_boxes()
	var o2: Vector3 = _sprawl_origin()
	var o3: Vector3 = _b["ZONE3_ORIGIN"]
	var half2: float = _c2["HALF"]
	var reach: float = half2 + float(_c2["ALCOVE_D"]) + 1.0
	return [
		["Lobby", Vector3(-16, 0, -10), Vector3(16, 0, 26)],
		["Sprawl", o2 - Vector3(reach, 0, reach), o2 + Vector3(reach, 0, reach)],
		["Flood", o3 - Vector3(34, 0, 34), o3 + Vector3(34, 0, 34)],
	]


# THE BOUNDS, DERIVED FROM THE LEVEL'S OWN GEOMETRY. Every `CSGBox3D` in the scene, merged,
# then flattened to a floor-level box. ⚠️ Derived rather than typed for the same reason the
# scene list is: a hand-written extent is a number that stops describing the level the moment
# the level moves, and the sweep would then report a clean pass over the half it still covers.
func _derived_boxes() -> Array:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var n := 0
	for node in _all(_scene, []):
		if not (node is CSGBox3D):
			continue
		var b: CSGBox3D = node
		var a := AABB(b.global_position - b.size / 2.0, b.size)
		lo = Vector3(minf(lo.x, a.position.x), minf(lo.y, a.position.y), minf(lo.z, a.position.z))
		var e := a.position + a.size
		hi = Vector3(maxf(hi.x, e.x), maxf(hi.y, e.y), maxf(hi.z, e.z))
		n += 1
	if n == 0:
		return []
	# ⚠️ ONE BOX PER FLOOR LEVEL, not one per level. The House's cellar floor is 1.5 m below
	# its ground floor, and a single box anchored at the LOWEST geometry in the scene made the
	# down-ray's `abs(hit.y - col.y) > 1.6` filter throw away every ground-floor sample:
	# measured, 13 standable points in an eight-room house. A guard that samples 13 points and
	# says PASS is the vacuous green this whole pass exists to remove.
	var out: Array = []
	for y in _floor_levels():
		out.append(["%s y=%.1f" % [_cfg["label"], y],
			Vector3(lo.x, y, lo.z), Vector3(hi.x, y, hi.z)])
	if out.is_empty():
		out.append([String(_cfg["label"]), Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z)])
	return out


# The distinct heights at which this level has a FLOOR — a wide, thin, horizontal CSG box
# with real headroom over it. ⚠️ The headroom test is what keeps CEILINGS out: a ceiling slab
# is the same shape as a floor slab and has nothing above it, and sampling on top of one
# would put the grid outside the building, where of course every ray escapes.
func _floor_levels() -> Array:
	var seen: Dictionary = {}
	for node in _all(_scene, []):
		if not (node is CSGBox3D):
			continue
		var b: CSGBox3D = node
		if b.size.y > 0.6 or b.size.x * b.size.z < 4.0:
			continue
		var top: float = b.global_position.y + b.size.y / 2.0
		var c := Vector3(b.global_position.x, top + 0.15, b.global_position.z)
		var q := PhysicsRayQueryParameters3D.create(c, c + Vector3(0, 12.0, 0))
		q.collision_mask = 1
		var up := _space().intersect_ray(q)
		if up.is_empty():
			continue                        # open sky above: this is a ceiling, not a floor
		if float(up["position"].y) - top < 1.9:
			continue                        # not enough headroom to stand
		seen[snappedf(top, 0.1)] = true
	var out: Array = seen.keys()
	out.sort()
	return out


# The floor AT THIS LEVEL under a column, or {} when there is none.
#
# ⚠️ IT MARCHES DOWN THROUGH SURFACES rather than taking the first hit, and the difference is
# 142 phantom findings. A single down-ray finds whatever is highest — in the House that is the
# SLOPED CELLAR CEILING, and 23 samples landed on TOP of it at y = 1.1-1.4, outside the
# building, where naturally there is no ceiling over them and every horizontal ray escapes.
# Taking the first hit and rejecting it (rather than looking past it) then lost 60 % of the
# level instead. So: step past each surface and keep looking, and accept the first one within
# a stride of the floor level being sampled. The Backrooms is unchanged by this — its first
# hit already IS the floor (measured: 880 standable points, same as before).
const FLOOR_BAND := 0.6

func _floor_hit(col: Vector3) -> Dictionary:
	var y: float = col.y + 2.5
	for _i in range(8):
		var down := PhysicsRayQueryParameters3D.create(
			Vector3(col.x, y, col.z), Vector3(col.x, col.y - 1.0, col.z))
		down.collision_mask = 1
		down.exclude = [_player.get_rid()]
		var hit := _space().intersect_ray(down)
		if hit.is_empty():
			return {}
		var hy: float = float(hit["position"].y)
		if absf(hy - col.y) <= FLOOR_BAND:
			return hit
		if hy <= col.y - 1.0:
			return {}
		y = hy - 0.05
	return {}


func _interior() -> void:
	var escaped: Array[String] = []
	var no_ceiling: Array[String] = []
	var per_zone := {}
	for zb in _zone_boxes():
		var label: String = zb[0]
		var lo: Vector3 = zb[1]
		var hi: Vector3 = zb[2]
		var here := 0
		var x := lo.x + PHASE_X
		while x <= hi.x:
			var z := lo.z + PHASE_Z
			while z <= hi.z:
				var col := Vector3(x, lo.y, z)
				# Is there floor here at all? Only sample where the world has one — outside
				# the shell there is nothing, so no false interior points.
				var fh := _floor_hit(col)
				if fh.is_empty():
					z += GRID_STEP
					continue
				var feet := Vector3(x, float(fh["position"].y), z)
				# ⚠️ Only sample where a player could actually stand. A point inside or
				# flush against a wall is both unreachable and undiagnosable (see PHASE_X).
				if _unstandable(feet):
					z += GRID_STEP
					continue
				here += 1
				_grid_points += 1
				_samples.append(feet)
				# ceiling — and how high it is, which the fan below needs
				_grid_rays += 1
				var upq := PhysicsRayQueryParameters3D.create(
					feet + Vector3(0, 0.3, 0), feet + Vector3(0, 12.0, 0))
				upq.collision_mask = 1
				upq.exclude = [_player.get_rid()]
				var up := _space().intersect_ray(upq)
				if up.is_empty():
					no_ceiling.append("%s %v" % [label, feet.snappedf(0.1)])
				# ⚠️ NEVER FIRE FROM ABOVE THE CEILING. The Flood's rooms are 2.6 m high and
				# its DryPlatform stands 0.4 m proud of the floor, so the 2.8 m eye height in
				# GRID_HEIGHTS put the ray 3.2 m up — through the ceiling, in the void above
				# the building, where of course nothing stops it. Measured: 20 phantom
				# escapes, all of them at 2.8 m and all of them on that platform. A player's
				# eye is 1.65 m; the tall samples exist to catch a hole up near the ceiling,
				# not to leave the building.
				var head: float = 99.0 if up.is_empty() \
					else float(up["position"].y) - feet.y - 0.2
				for y in GRID_HEIGHTS:
					if y > head:
						continue
					var from: Vector3 = feet + Vector3(0, y, 0)
					for i in range(GRID_DIRS):
						var a := TAU * float(i) / float(GRID_DIRS) + ANGLE_PHASE
						var dir := Vector3(cos(a), 0, sin(a))
						_grid_rays += 1
						if not _stopped(from, from + dir * RAY_LEN):
							escaped.append("%s %v %.1f m up, bearing %d°"
								% [label, feet.snappedf(0.1), y, int(rad_to_deg(a))])
				z += GRID_STEP
			x += GRID_STEP
		per_zone[label] = here
	var filed_esc := int(_cfg.get("filed_escapes", 0))
	var filed_open := int(_cfg.get("filed_open", 0))
	_ok("%s: no horizontal ray escapes the level from anywhere a player can stand"
		% _cfg["label"], escaped.size() == filed_esc, "%d escaping ray(s)%s: %s"
			% [escaped.size(), (" (filed: %d)" % filed_esc) if filed_esc > 0 else "",
				", ".join(escaped.slice(0, 8))])
	_ok("%s: every standable point has a ceiling over it" % _cfg["label"],
		no_ceiling.size() == filed_open, "%d without%s: %s"
			% [no_ceiling.size(), (" (filed: %d)" % filed_open) if filed_open > 0 else "",
				", ".join(no_ceiling.slice(0, 8))])
	# ⚠️ Sample size, per zone AND per scene. A grid that finds no floor is a test that
	# measured the level not at all, and it would still print a tidy PASS.
	# ⚠️ The per-zone floor is 40 for the Backrooms' three hand-named zones and 1 everywhere
	# else, because everywhere else the "zones" are FLOOR LEVELS this file derived itself: the
	# House's ramp is a legitimate level with three standable points on it, and a floor of 40
	# would be asserting something about the derivation rather than about the level. The
	# scene-wide `min_points` below is the number that means something there.
	var per_zone_floor: int = 40 if bool(_cfg.get("backrooms", false)) else 1
	var thin: Array[String] = []
	for k in per_zone:
		if int(per_zone[k]) < per_zone_floor:
			thin.append("%s=%d" % [k, int(per_zone[k])])
	_ok("%s: every zone was really sampled" % _cfg["label"], thin.is_empty(),
		"%s (total %d points, %d rays)" % [str(per_zone), _grid_points, _grid_rays])
	_ok("%s: enough standable points" % _cfg["label"],
		_grid_points >= int(_cfg.get("min_points", 40)),
		"%d points, minimum %d" % [_grid_points, int(_cfg.get("min_points", 40))])
	_summary.append("%-10s seed %-4d %d points, %d escaping, %d without ceiling"
		% [_cfg["label"], int(_cfg["seed"]), _grid_points, escaped.size(), no_ceiling.size()])


# ---------------------------------------------------------------- the control

# ---------------------------------------------------------------- the generic control
#
# PROOF THE INTERIOR SWEEP CAN FAIL, ON EVERY LEVEL, derived from the scene under test.
#
# Take a point this run certified as standable, find the wall in front of it BY RAY, delete
# that node, and require the sweep's own logic to see daylight from the same point. Nothing
# here is a remembered coordinate — a control built from literals is a no-op the moment a
# level moves, and this project has shipped that too (X18).
#
# ⚠️ It tries several samples and several bearings, because deleting one wall of a room whose
# neighbour has its own wall behind it proves nothing: the ray is stopped either way. If NO
# sample yields a hole, that is reported as a failure rather than swallowed.
var _punched_name := ""
var _punch_from := Vector3.ZERO
var _punch_dir := Vector3.ZERO

func _generic_punch() -> void:
	_punched_name = ""
	if _samples.is_empty():
		return
	var step: int = maxi(1, _samples.size() / 24)
	var i := 0
	while i < _samples.size():
		var feet: Vector3 = _samples[i]
		var eye: Vector3 = feet + Vector3(0, 1.2, 0)
		for k in range(GRID_DIRS):
			var a := TAU * float(k) / float(GRID_DIRS) + ANGLE_PHASE
			var dir := Vector3(cos(a), 0, sin(a))
			var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * 6.0)
			q.collision_mask = 1
			q.exclude = [_player.get_rid()]
			var hit := _space().intersect_ray(q)
			if hit.is_empty():
				continue
			var col: Object = hit.get("collider")
			var node: Node = col as Node
			while node != null and not (node is CSGBox3D) and node != _scene:
				node = node.get_parent()
			if node == null or node == _scene or not (node is CSGBox3D):
				continue
			# ⚠️ Not a floor or a ceiling: this control is about seeing OUT.
			var box: CSGBox3D = node
			if box.size.y < 0.5:
				continue
			# ⚠️ AND IT HAS TO BE AN OUTSIDE WALL. Deleting an interior partition proves
			# nothing: the ray simply crosses the next room and is stopped by ITS far wall,
			# and the control reports "the sweep did not see the hole" on a perfectly working
			# sweep. Measured in the Lab, first attempt. So: step past the wall and check that
			# the world really does end there before choosing it.
			var beyond: Vector3 = Vector3(hit["position"]) + dir * 0.6
			if _stopped(beyond, beyond + dir * RAY_LEN):
				continue
			# ⚠️ REMEMBER THE NAME, NOT THE NODE. A freed Object compares EQUAL TO NULL in
			# GDScript, so `_punched != null` on the node we have just deleted is false — the
			# control reported "found no wall to delete" immediately after deleting one, and
			# looked exactly like a control that could not fire. This is Issue 45's family:
			# the wrong kind of nil check, silently.
			_punched_name = String(node.name)
			_punch_from = eye
			_punch_dir = dir
			node.get_parent().remove_child(node)
			node.queue_free()
			return
		i += step
	# fall through with _punched == null; the check below fails loudly


func _generic_control_check() -> void:
	_ok("%s CONTROL: found a wall to delete in front of a standable point" % _cfg["label"],
		_punched_name != "", _punched_name)
	if _punched_name == "":
		return
	var seen := not _stopped(_punch_from, _punch_from + _punch_dir * RAY_LEN)
	_ok("%s CONTROL: with that wall gone, the sweep sees out from the same point"
		% _cfg["label"], seen,
		"deleted %s, looking from %v" % [_punched_name, _punch_from.snappedf(0.1)])


var _control_baseline: Dictionary = {}

func _control_punch() -> void:
	# Recreate the shipped bug exactly: remove one E-side alcove's back wall.
	_control_baseline = _perimeter("E", true)
	var z2 := _scene.get_node_or_null("ZoneSprawl") as Node3D
	var wall := z2.get_node_or_null("AlcBackE1") if z2 else null
	_ok("the control has a wall to remove", wall != null)
	if wall:
		wall.get_parent().remove_child(wall)
		wall.queue_free()


func _control_check() -> void:
	var after := _perimeter("E", true)
	var open: Dictionary = after["open"]
	_ok("CONTROL: with AlcBackE1 removed, the sweep goes RED on the E side",
		open.has("E") and int(open["E"]) > 0, "%s" % str(open))
	_ok("CONTROL: ...and reports a gap at least 3 m wide",
		float(after["widest"]) >= 3.0, "%.2f m" % float(after["widest"]))
	# And the baseline taken a moment earlier, on the same side with the wall still in place,
	# has to have been clean — or the control proves nothing about the sweep.
	_ok("CONTROL: the same side measured clean before the wall was removed",
		(_control_baseline["open"] as Dictionary).is_empty(),
		"%s" % str(_control_baseline["open"]))

	# ⚠️ THE INTERIOR SWEEP NEEDS ITS OWN CONTROL. The perimeter control above proves
	# `_stopped()` and the ray machinery; it proves nothing about `_unstandable()` and the
	# `head` clamp, either of which could reject EVERY sample and leave a tidy green "0
	# escaping rays". So: re-run the interior sweep's own logic over a small patch of floor
	# in front of the alcove whose back wall has just been removed, and require it to see it.
	var org := _sprawl_origin()
	var axis: Vector3 = _c2["SIDE_AXIS"]["E"]
	var lat := Vector3(axis.z, 0, axis.x)
	var mouth: Vector3 = org + axis * (float(_c2["HALF"]) - 3.0) \
		+ lat * float(_c2["ALCOVE_AT"])
	var seen := 0
	var sampled := 0
	for iu in range(7):
		for iv in range(7):
			var feet := mouth + lat * ((float(iu) - 3.0) * 0.6 + 0.07) \
				+ axis * ((float(iv) - 3.0) * 0.6 - 0.13)
			feet.y = org.y
			if _unstandable(feet):
				continue
			sampled += 1
			for i in range(GRID_DIRS):
				var a := TAU * float(i) / float(GRID_DIRS) + ANGLE_PHASE
				var from: Vector3 = feet + Vector3(0, 1.6, 0)
				if not _stopped(from, from + Vector3(cos(a), 0, sin(a)) * RAY_LEN):
					seen += 1
	_ok("CONTROL: the interior sweep sees the same hole from the hall floor", seen > 0,
		"%d escaping ray(s) from %d standable sample(s)" % [seen, sampled])
	_ok("CONTROL: ...and it had somewhere to stand while looking", sampled >= 10,
		"%d samples" % sampled)


func _report() -> bool:
	print("")
	print("--- SHELL SWEEP: %d scene-run(s) ---" % _rows.size())
	for line in _summary:
		print("  " + line)
	print("%d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		for f in _fails:
			print("  FAIL: " + f)
		print("RESULT: FAIL")
		quit(1)
	return true
