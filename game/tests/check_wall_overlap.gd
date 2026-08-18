extends SceneTree

# NO TWO VISIBLE SURFACES IN ONE PLANE — **IN EVERY LEVEL IN THE GAME**.
#
#   Godot --headless --path game --script res://tests/check_wall_overlap.gd
#   Godot --headless --path game --script res://tests/check_wall_overlap.gd -- Corridor
#   Godot --headless --path game --script res://tests/check_wall_overlap.gd -- res://scenes/x.tscn
#
# Coincident visible surfaces z-fight, and because abutting rooms can use different skins the
# fight shows up in game as one room's texture bleeding through another along a jagged
# contour — the "overlapping / merging textures" bug, this project's most common bug class
# (Issues 19/20/23/24/25/26).
#
# ⚠️ A SWEEP SINCE 2026-08-17 (workstream H1). It took a scene argument, `tools/run_tests.sh`
# has no per-test argument mechanism, and so for its entire life it ran on `level_1.tscn` and
# on whichever levels somebody had remembered to write a three-line wrapper for. The first
# run against the Corridor found 32 things; against the Backrooms, 10. It now iterates
# `tests/lib/scenes.gd`, which is DERIVED from `GameState`'s own `SCENE_*` constants, so a
# new level is enrolled by existing and the three wrappers are gone.
#
# The optional argument now filters that list by label (or takes a raw scene path for a
# one-off), which is what reproducing a single finding wants.

const Scenes := preload("res://tests/lib/scenes.gd")

var _scene := ""
var _frame := 0

# ⚠️ ALLOWLIST (added 2026-08-16, for the Corridor). A scene's CONFIG row may declare pairs of
# box names whose coincident faces are ACCEPTED, as `[["A", "B", "why"], ...]`.
#
# It exists because `corridor.gd:_build_geometry()` deliberately extends every segment's
# floor and ceiling footprint half a corridor-width past each interior corner so the corner
# square is covered by both segments. That is not a bug and it is not fixable without
# rebuilding the corner as its own box: the two slabs are the SAME MATERIAL INSTANCE, that
# material is `uv1_triplanar`, and triplanar UVs are a pure function of world position — so
# the two coincident faces sample the same texel, take the same normal and the same light,
# and resolve to the same colour whichever wins the depth test. The user has walked all six
# corners twice without reporting anything there.
#
# ⚠️ TWO GUARD RAILS, because an allowlist is how a check goes quietly blind:
#   1. A pair is only ever allowed if the two boxes carry the SAME material instance. If a
#      future skin pass gives one segment its own material the entry stops applying and the
#      pair goes red again — which is precisely when a coincident face becomes visible.
#   2. `_min_allow` asserts the allowlist's own size. If a change adds a 23rd coincident
#      pair, or removes one, the count moves and the test fails rather than swallowing it.
var _allow: Array = []
var _min_allow := 0

# ⚠️ EXTRA SAMPLING MODE (added 2026-08-17, cross-level X34). `_check_wall_props()` probes a
# flat prop's CENTRE POINT ONLY. That is exactly right for a 0.4 m decal and meaningless for
# a 60 x 60 m `PlaneMesh`: the Backrooms Flood's water sheet is 3600 m² tested at one point,
# and every large flat surface in the game (water sheets, floor decals, sky caps, glitch
# walls) is in the same blind spot.
#
# `_quad_grid` is the number of samples PER AXIS across each quad. ⚠️ DEFAULT 1 — one sample,
# at the centre, i.e. byte-identical to the behaviour every existing wrapper was green
# against. A scene's CONFIG row opts in; nothing else changes.
#
# ⚠️ It is proved to bite by `_self_test_quad_grid()`, which builds a plane whose CENTRE is
# in clear air and whose CORNER is inside a real wall of the scene under test, and requires
# grid 1 to miss it and the configured grid to catch it. That control only runs when the
# mode is on, because at grid 1 it would be asserting that the fix is absent.
var _quad_grid := 1

# Flat props whose finding is ACCEPTED, as {node name: reason}. Same discipline as `_allow`:
# each is REPORTED rather than hidden, and `_min_quad_ignored` asserts the list's own size,
# so an entry left behind after its prop was fixed cannot silently widen the rule.
var _quad_ignore: Dictionary = {}
var _min_quad_ignored := 0
# How many findings of each kind to print before truncating.
const MAX_REPORT := 40

# What actually z-fights is a pair of COINCIDENT VISIBLE FACES, not volumetric
# overlap as such. Floor bridges are deliberately embedded in the room floors and
# sunk by RoomBuilder.BRIDGE_SINK (4 mm) precisely so their top faces are NOT
# coplanar — those must pass. So: flag a pair only when two parallel faces sit
# within COPLANAR of each other while overlapping substantially in the other axes.
const COPLANAR := 0.002   # face separation below this will fight for depth
# Ignore the 0.2 x 0.2 stubs where two perpendicular walls legitimately cross at a
# room corner — those coincide only over a tiny square, usually up at the ceiling
# line, and are not what the player sees. We want large coincident SURFACES.
const MIN_AREA := 0.35


func _faces_fight(a: AABB, b: AABB) -> String:
	var amin := a.position
	var amax := a.position + a.size
	var bmin := b.position
	var bmax := b.position + b.size
	var names := ["x", "y", "z"]
	for axis in range(3):
		var o1 := (axis + 1) % 3
		var o2 := (axis + 2) % 3
		var ov1: float = minf(amax[o1], bmax[o1]) - maxf(amin[o1], bmin[o1])
		var ov2: float = minf(amax[o2], bmax[o2]) - maxf(amin[o2], bmin[o2])
		if ov1 <= MIN_AREA or ov2 <= MIN_AREA:
			continue
		if absf(amax[axis] - bmax[axis]) < COPLANAR:
			return "+%s faces coincide" % names[axis]
		if absf(amin[axis] - bmin[axis]) < COPLANAR:
			return "-%s faces coincide" % names[axis]
	return ""


# ---------------------------------------------------------------- the per-scene rows
#
# ⚠️ A ROW IS AN OVERRIDE, NOT AN ENROLMENT. Every scene in `tests/lib/scenes.gd` is swept
# whether or not it appears here; a row exists only to say something the defaults cannot.
# That is the whole design: a level cannot be left out by being forgotten, only by being
# written down.
#
#   allow / min_allow            coincident CSG pairs that are accepted, and how many
#   quad_grid                    samples per axis across a flat prop (default 1 = its centre)
#   quad_ignore / min_quad_ignored   flat props whose finding is accepted, and how many
#   min_boxes / min_quads / min_solids   the SAMPLE SIZE this scene must produce
#   seeds                        RNG seeds to build a `random` scene at (see Scenes.pin_rng)
const CORRIDOR_CORNER := "corner square is covered by both segments; " \
	+ "same triplanar material instance"

const CONFIG := {
	"SCENE_INTRO": {
		"min_boxes": 20, "min_quads": 8, "min_solids": 4,
		# ⚠️ IGNORED WITH THE MEASUREMENT, not filtered. Both are flat art laid on the TOP
		# FACE of a prop the player looks down on, which is the one place in this project
		# where a quad legitimately sits inside `MIN_CLEAR` of a box: the gurney's sheet art
		# is 5 mm proud of the mattress and the note's face 3.5 mm proud of the table. Neither
		# is coplanar and neither has ever shimmered — the fault this file exists for is two
		# surfaces IN one plane, and 3.5 mm at a 1.5 m viewing distance is not that.
		# `min_quad_ignored` asserts the size, so a THIRD flat prop landing inside a box
		# cannot hide behind these two.
		"quad_ignore": {
			"GurneyMattressArt_0_70": "sheet art 0.005 m proud of the mattress it lies on",
			"NoteFace": "the note's face 0.0035 m proud of the table it lies on",
		},
		"min_quad_ignored": 2,
	},
	"SCENE_LEVEL_1": {"min_boxes": 150, "min_quads": 10, "min_solids": 140},
	"SCENE_LEVEL_2": {"min_boxes": 110, "min_quads": 14, "min_solids": 40},
	"SCENE_CORRIDOR": {
		# ⚠️ WAIVED 2026-08-16. `corridor.gd:_build_geometry()` extends each segment's floor
		# and ceiling half a corridor-width past every interior corner (`lo = -W/2`,
		# `hi = len + W/2`) so the corner square has a floor and a ceiling at all. Consecutive
		# segments therefore share a ~3.3 x 3.3 m slab at exactly y = 0.0 and y = 3.0.
		#
		# Both slabs are the SAME `StandardMaterial3D` instance (`_floor_mat` / `_ceil_mat`)
		# and that material is `uv1_triplanar`, whose UVs are a pure function of world
		# position — so the two coincident faces sample the same texel, take the same normal
		# and the same light, and resolve to the same colour whichever wins the depth test.
		# This is the one case in the project where a coincident pair is genuinely invisible,
		# and it was checked against the player's own two traversals of all six corners.
		#
		# The alternative — cutting the corner square out of one segment and emitting it as
		# its own box — is geometry surgery on the level's load-bearing builder, for a defect
		# nobody can see. If a corner ever DOES shimmer, that is the fix; delete an entry here
		# first and watch it go red.
		"allow": "@corridor_corners", "min_allow": 12,
		"min_boxes": 28, "min_quads": 38, "min_solids": 120,
	},
	"SCENE_BACKROOMS": {
		# ⚠️ THE EXTRA SAMPLING MODE IS ON HERE (cross-level X34). This scene contains the
		# largest flat surface in the game — a 60 x 60 m water sheet — and the default probes
		# a flat prop at its CENTRE POINT ONLY, i.e. 3600 m² tested at one point. 5 x 5
		# samples across every flat prop instead, and `_self_test_quad_grid()` proves that
		# mode catches something grid 1 misses, on this scene, every run.
		"quad_grid": 5,
		# ⚠️ IGNORED, with the measurement. `backrooms_zone3.gd:_build_water()` lays one
		# 60 x 60 m translucent sheet at y = 0.12 over the whole flooded footprint, and
		# `_build_pressure()` raises a 3.4 x 3.4 m DryPlatform out of it whose AABB spans
		# y 0..0.44. The sheet therefore passes THROUGH the platform — which is the entire
		# point of a dry platform in a flood, and is not a z-fight: no face of either is
		# coplanar with a face of the other, the platform is opaque, and it occludes the sheet
		# from every angle a player can stand at.
		"quad_ignore": {
			"Floodwater": "the flood sheet passes through the DryPlatform standing in it — "
				+ "no coplanar faces, and the platform is opaque",
		},
		"min_quad_ignored": 1,
		"min_boxes": 170, "min_quads": 24, "min_solids": 160,
		# ⚠️ The arm assignment is re-rolled per round, so pin it and say so.
		"seeds": [1],
	},
	"SCENE_KONTUR": {
		# ⚠️ THREE SEEDS, and they are not decoration: `_dark_x` picks one of THREE spine
		# offsets and `_spawn_gate1_doors()` DELETES A FLOOR behind whichever antechamber drew
		# red, so the geometry under test is genuinely different per run. Measured before
		# being written down (tests/lib/scenes.gd's `pin_rng`): seed 7 -> `_dark_x` +3.0,
		# seed 3 -> -3.0, seed 11 -> 0.0 AND the gate-1 colours the other way round. That is
		# every spine offset and both colour assignments.
		"seeds": [7, 3, 11],
		# ⚠️ `min_quads` DROPPED 30 -> 27 ON 2026-08-18, and the drop is the point rather
		# than a relaxation: the eight redacted signs used to be a plate quad PLUS a
		# separate black quad for the censor bar, and the bar is now struck into the
		# generated artwork (`tools/make_kontur_signs.py`) — eight flat props that no
		# longer exist because they became paint. Measured across the three seeds: 28, 28,
		# 29 (the ±1 is the Perëkozhnik's disguise, which carries a label quad when it is
		# wearing a bottle and none when it is wearing a phone). The floor sits one under
		# the lowest observed count, not at it, for that reason.
		"min_boxes": 100, "min_quads": 27, "min_solids": 60,
	},
	"SCENE_LEVEL_6_BREACH": {"min_boxes": 90, "min_quads": 6, "min_solids": 25},
	"SCENE_DUNGEON": {
		# ⚠️ THE WHOLE LEVEL IS REGENERATED ON EVERY LOAD. Two pinned seeds, because one green
		# run says nothing at all about a level that is different every time — and because an
		# exact-count assertion against an unpinned generator is not an assertion.
		"seeds": [1, 404],
		"min_boxes": 150, "min_quads": 10, "min_solids": 90,
	},
	"SCENE_LEVEL_3": {
		# ⚠️ `min_quads` 0 IS A FINDING, NOT A SETTING. The Void contains no flat art props at
		# all, so the whole `_check_wall_props()` pass measures nothing here — its notes are
		# `BoxMesh` pages on tables. Recorded as a coverage gap in backlogs/08-void.md rather
		# than papered over; the solid pass and the CSG pass both have real samples.
		"min_boxes": 40, "min_quads": 0, "min_solids": 8,
	},
}

var _rows: Array = []           # [{key,label,path,settle,seed,cfg}]
var _row := 0
var _t := 0.0
var _stage := "load"
var _bad_total := 0
var _summary: Array = []
var _only := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1 and not String(args[0]).begins_with("--"):
		_only = args[0]
	# A raw path is still accepted, for reproducing one finding without touching the list.
	if _only.begins_with("res://"):
		_rows = [{"key": "ARG", "label": "arg", "path": _only, "settle": 1.6,
			"seed": 1, "cfg": {}}]
		_only = ""
	else:
		var problems: Array = Scenes.problems()
		for p in problems:
			print("  FAIL enrolment: %s" % p)
		_bad_total += problems.size()
		for s in Scenes.levels():
			if _only != "" and String(s["label"]).to_lower().find(_only.to_lower()) < 0:
				continue
			var cfg: Dictionary = CONFIG.get(s["key"], {})
			for sd in cfg.get("seeds", [1]):
				_rows.append({
					"key": s["key"], "label": String(s["label"]),
					"path": String(s["path"]), "settle": float(s["settle"]),
					"seed": int(sd), "cfg": cfg,
				})
	if _rows.is_empty():
		print("WALL-OVERLAP FAIL: no scene matched '%s'" % _only)
		quit(1)
		return
	_load_row()


func _load_row() -> void:
	var r: Dictionary = _rows[_row]
	_scene = String(r["path"])
	var cfg: Dictionary = r["cfg"]
	# Reset every per-scene knob, so one row's waivers cannot leak into the next.
	var allow: Variant = cfg.get("allow", [])
	_allow = _corridor_corners() if allow is String else (allow as Array)
	_min_allow = int(cfg.get("min_allow", 0))
	_quad_grid = int(cfg.get("quad_grid", 1))
	_quad_ignore = cfg.get("quad_ignore", {})
	_min_quad_ignored = int(cfg.get("min_quad_ignored", 0))
	_frame = 0
	_t = 0.0
	# ⚠️ Pin the dice BEFORE the scene builds. KONTUR, the Backrooms and THE NIGHTMARE all
	# choose geometry with `randi()` in `_ready()`.
	Scenes.pin_rng(int(r["seed"]))
	change_scene_to_file(_scene)


func _corridor_corners() -> Array:
	var out: Array = []
	for i in range(6):
		out.append(["Seg%dFloor" % i, "Seg%dFloor" % (i + 1), CORRIDOR_CORNER])
		out.append(["Seg%dCeiling" % i, "Seg%dCeiling" % (i + 1), CORRIDOR_CORNER])
	return out


func _process(delta: float) -> bool:
	_t += delta
	_frame += 1
	# ⚠️ TIME, not a frame count — headless runs uncapped, so a frame count measures the
	# machine (cross-level X42). CSG colliders are not registered during `_ready()` either
	# (Issue 52) and every level here builds itself there.
	if _t < float(_rows[_row]["settle"]):
		return false
	var bad := _measure_scene()
	_bad_total += bad
	_summary.append("%-10s seed %-4d %s (%d finding%s)"
		% [_rows[_row]["label"], _rows[_row]["seed"],
			"PASS" if bad == 0 else "FAIL", bad, "" if bad == 1 else "s"])
	_row += 1
	if _row < _rows.size():
		_load_row()
		return false
	print("")
	print("--- WALL-OVERLAP SWEEP: %d scene-run(s) ---" % _rows.size())
	for line in _summary:
		print("  " + line)
	print("WALL-OVERLAP %s (%d finding(s) in total)"
		% ["PASS" if _bad_total == 0 else "FAIL", _bad_total])
	quit(0 if _bad_total == 0 else 1)
	return true


var _last_boxes := 0
var _last_quads := 0
var _last_solids := 0


func _measure_scene() -> int:
	var boxes: Array = []
	_collect(current_scene, boxes)
	var quads: Array = []
	_collect_quads(current_scene, quads)
	var solids: Array = []
	_collect_solids(current_scene, solids)
	_last_boxes = boxes.size()
	_last_quads = quads.size()
	_last_solids = solids.size()
	print("")
	print("--- %s (%s, seed %d) ---"
		% [_rows[_row]["label"], _scene, int(_rows[_row]["seed"])])
	print("WALL-OVERLAP scene=%s boxes=%d" % [_scene, boxes.size()])
	var bad := 0
	var allowed_seen := 0
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			var o: Vector3 = _overlap(boxes[i][1], boxes[j][1])
			if o.x <= 0.0 or o.y <= 0.0 or o.z <= 0.0:
				continue
			var why: String = _faces_fight(boxes[i][1], boxes[j][1])
			if why == "":
				continue
			var why_allowed := _allowed(boxes[i], boxes[j])
			if why_allowed != "":
				allowed_seen += 1
				print("  ALLOWED %s <-> %s  (%s; %s)" % [
					boxes[i][0], boxes[j][0], why, why_allowed])
				continue
			bad += 1
			if bad <= MAX_REPORT:
				print("  ZFIGHT %s <-> %s  (%s)" % [boxes[i][0], boxes[j][0], why])
	# ⚠️ The allowlist must match EXACTLY what the scene produces. Too few and something
	# has been swallowed by a stale entry; too many and a new coincident pair has appeared
	# and is being waved through by a rule written for a different one.
	if allowed_seen != _min_allow:
		print("  FAIL allowlist size: %d coincident pair(s) were waived, expected exactly %d"
			% [allowed_seen, _min_allow])
		bad += 1
	elif _min_allow > 0:
		print("WALL-OVERLAP %d documented coincident pair(s) waived, as expected" % allowed_seen)
	bad += _check_wall_props(boxes)
	if _quad_grid > 1:
		# A quiet re-run gives the control a baseline measured the same way it measures.
		bad += _self_test_quad_grid(boxes, _check_wall_props(boxes, true))
	var solid_bad := _check_solid_props(boxes)
	bad += solid_bad
	bad += _self_test_solid(boxes, solid_bad)
	# ⚠️ SAMPLE SIZE IS PART OF THE ASSERTION, PER PASS. This file used to assert only that
	# the scene produced SOME CSG boxes — so a level whose flat props all failed to spawn, or
	# whose prop names had changed, measured nothing in `_check_wall_props()` and still
	# printed a tidy PASS. Every pass now has a floor, taken a little under the measured
	# count so a legitimate prop removal does not turn a healthy level red.
	var cfg: Dictionary = _rows[_row]["cfg"]
	bad += _floor("CSG boxes", _last_boxes, int(cfg.get("min_boxes", 20)))
	bad += _floor("flat props", _last_quads, int(cfg.get("min_quads", 1)))
	bad += _floor("solid props", _last_solids, int(cfg.get("min_solids", 1)))
	print("WALL-OVERLAP result: %d finding(s)   [%d boxes, %d flat props, %d solid props]"
		% [bad, _last_boxes, _last_quads, _last_solids])
	print("WALL-OVERLAP %s" % ("PASS" if bad == 0 else "FAIL"))
	return bad


# Assert a pass measured something. Returns 1 (a failure) when it did not.
func _floor(what: String, got: int, want: int) -> int:
	if got >= want:
		return 0
	print("  FAIL sample size: %d %s measured, expected at least %d — did %s fail to build?"
		% [got, what, want, _scene])
	return 1


# Wall-mounted decals (posters, signs, whiteboards, mirrors, notes) are flat quads
# hung just off a wall. If one sits ON the wall face it z-fights and the wall
# texture slices through the artwork; if it sits behind the face it is swallowed.
# Report any such quad that is not clearly in front of every wall box it overlaps.
func _check_wall_props(boxes: Array, quiet: bool = false) -> int:
	var quads: Array = []
	_collect_quads(current_scene, quads)
	var bad := 0
	var ignored := 0
	var samples := 0
	for q in quads:
		var points: Array[Vector3] = _quad_samples(q)
		samples += points.size()
		var hit_box := ""
		var hit_at := Vector3.ZERO
		for qpos in points:
			for b in boxes:
				var box: AABB = b[1]
				var grown := box.grow(MIN_CLEAR)
				if grown.has_point(qpos):
					hit_box = b[0]
					hit_at = qpos
					break
			if hit_box != "":
				break
		if hit_box == "":
			continue
		if _quad_ignore.has(q[0]):
			ignored += 1
			if not quiet:
				print("  IGNORED %s at %s within %.2f m of %s  — %s"
					% [q[0], hit_at, MIN_CLEAR, hit_box, _quad_ignore[q[0]]])
			continue
		bad += 1
		if bad <= MAX_REPORT and not quiet:
			print("  WALLPROP %s at %s is within %.2f m of %s" % [
				q[0], hit_at, MIN_CLEAR, hit_box])
	if not quiet:
		print("WALL-OVERLAP wall props checked: %d (%d sample points)"
			% [quads.size(), samples])
		# ⚠️ The ignore list must match EXACTLY what the scene produces, for the same reason
		# `_min_allow` does. Too few and a stale entry is swallowing something; too many and
		# a new fault is being waved through by a rule written for a different prop.
		if ignored != _min_quad_ignored:
			print("  FAIL flat-prop ignore list: %d waived, expected exactly %d"
				% [ignored, _min_quad_ignored])
			bad += 1
		elif _min_quad_ignored > 0:
			print("WALL-OVERLAP %d documented flat prop(s) waived, as expected" % ignored)
	return bad


# World-space sample points across a flat prop's surface. `_quad_grid` per axis; at 1 this
# returns exactly [centre], which is what this file did before the mode existed.
#
# ⚠️ THE OUTERMOST 5 % OF EACH AXIS IS NOT SAMPLED, and it has to be. A full-height wall
# surface legitimately reaches the floor and the ceiling — the Backrooms' five glitch walls
# span 0 to H exactly — so a sample at the literal edge is inside the floor slab's
# MIN_CLEAR skin by construction and every one of them would report. That is a prop TOUCHING
# a surface at its own boundary, which is not the bug this file exists for; the bug is two
# surfaces OVERLAPPING, and an overlap always shows up in the interior samples too.
const QUAD_EDGE_INSET := 0.05

func _quad_samples(q: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var centre: Vector3 = q[1]
	if _quad_grid <= 1 or q.size() < 4:
		out.append(centre)
		return out
	var t: Transform3D = q[2]
	var size: Vector2 = q[3]
	var span := 1.0 - 2.0 * QUAD_EDGE_INSET
	for i in range(_quad_grid):
		for j in range(_quad_grid):
			var u := (float(i) / float(_quad_grid - 1) - 0.5) * size.x * span
			var v := (float(j) / float(_quad_grid - 1) - 0.5) * size.y * span
			out.append(t * Vector3(u, v, 0.0))
	return out


# PROOF THE EXTRA SAMPLING MODE CAN FAIL, derived from the scene under test and kept
# permanently. Builds a plane whose CENTRE sits in clear air and whose corner is buried in a
# real wall of this scene, then requires:
#   * grid 1 (the old behaviour) to MISS it — otherwise the control is not testing the mode;
#   * the configured grid to CATCH it.
# Returns 1 (a failure) if either half does not hold.
func _self_test_quad_grid(boxes: Array, baseline: int) -> int:
	if _quad_grid <= 1:
		return 0
	# A TALL wall, so its thin axis is horizontal and the probe can be aimed at its face.
	var wall: AABB = AABB()
	var found := false
	for b in boxes:
		var a: AABB = b[1]
		if a.size.y > 2.0 and (a.size.x > 2.0 or a.size.z > 2.0):
			wall = a
			found = true
			break
	if not found:
		print("  FAIL quad-grid self-test: no tall wall to derive a control from")
		return 1
	var thin := 0 if wall.size.x < wall.size.z else 2
	var centre := wall.position + wall.size / 2.0

	# A 4 m plane aimed edge-on AT the wall, with its centre CTRL_OUT in open air. Its near
	# end therefore reaches 0.8 m INSIDE the wall while its centre — the only point the old
	# behaviour ever looked at — is in the middle of a room.
	#
	# ⚠️ 1.2 m out, not 3: the corridors in this game are 3 m wide, and a control that stands
	# 3 m off one wall is standing INSIDE the opposite one.
	const CTRL_LEN := 4.0
	const CTRL_OUT := 1.2
	var probe := MeshInstance3D.new()
	probe.name = "QuadGridControlProbe"
	var pm := QuadMesh.new()
	pm.size = Vector2(CTRL_LEN, 0.4)
	probe.mesh = pm
	current_scene.add_child(probe)
	if thin == 2:
		probe.rotation.y = PI / 2.0   # local X runs along world Z

	# Which side of the wall is open air depends on the scene, so try both and accept the
	# side that behaves. If NEITHER does, the control fails loudly rather than passing.
	var result := 1
	for sign in [1.0, -1.0]:
		var pos := centre
		var off: float = sign * (wall.size[thin] / 2.0 + CTRL_OUT)
		if thin == 0:
			pos.x += off
		else:
			pos.z += off
		probe.global_position = pos

		var old_grid := _quad_grid
		_quad_grid = 1
		var at_one := _check_wall_props(boxes, true)
		_quad_grid = old_grid
		var at_grid := _check_wall_props(boxes, true)
		if at_one == baseline and at_grid == baseline + 1:
			print("WALL-OVERLAP quad-grid self-test: a plane whose CENTRE is clear and whose "
				+ "END is buried is MISSED at grid 1 (%d) and CAUGHT at grid %d (%d)"
				% [at_one, _quad_grid, at_grid])
			result = 0
			break
		print("  quad-grid control on side %+.0f: grid1 %d, grid%d %d (baseline %d)"
			% [sign, at_one, _quad_grid, at_grid, baseline])
	probe.queue_free()
	if result != 0:
		print("  FAIL quad-grid self-test: neither side of the control wall behaved")
	return result


const MIN_CLEAR := 0.02


# ⚠️ `QuadMesh` ONLY, until 2026-08-16 — and that is why six floating doors sailed through.
#
# Every prop in this game that is built from a `BoxMesh` (the Corridor's `AjarDoor` leaves
# and its brass plate, the House's furniture, `intro_room.gd`'s wheelchair) was invisible to
# this check, in BOTH directions: it could neither be caught z-fighting a wall nor caught
# floating 9 cm off one. `PlaneMesh` is included for the same reason — `intro_room.gd` uses
# it for flat art where the rest of the project uses `QuadMesh`.
func _collect_quads(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		# [name, world centre, world transform, surface size] — the last two are what
		# `_quad_samples()` needs; nothing reads them at _quad_grid == 1.
		if mi.mesh is QuadMesh:
			out.append([mi.name, mi.global_position, mi.global_transform,
				(mi.mesh as QuadMesh).size])
		elif mi.mesh is PlaneMesh:
			# ⚠️ A PlaneMesh lies in its own XZ plane, not XY like a QuadMesh — unless its
			# `orientation` says otherwise (FACE_Z is what GlitchWall uses). Hand
			# `_quad_samples()` a transform in which local XY is always the surface.
			var p := mi.mesh as PlaneMesh
			var t := mi.global_transform
			if p.orientation == PlaneMesh.FACE_Y:
				t = t * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO)
			elif p.orientation == PlaneMesh.FACE_X:
				t = t * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3.ZERO)
			out.append([mi.name, mi.global_position, t, p.size])
	for c in node.get_children():
		_collect_quads(c, out)


# Solid props (BoxMesh) that share a VISIBLE FACE PLANE with a wall/floor/ceiling slab.
# Same rule as the CSG-vs-CSG pass above and the same bug class; a box prop's centre is a
# useless probe (a fixture mounted flush to a ceiling legitimately has its centre inside
# half its own thickness of it, and a closed drawer legitimately lives inside its counter),
# so this compares FACES, exactly as `_faces_fight` does for the level's own geometry.
func _check_solid_props(boxes: Array) -> int:
	var solids: Array = []
	_collect_solids(current_scene, solids)
	var bad := 0
	for s in solids:
		for b in boxes:
			var o: Vector3 = _overlap(s[1], b[1])
			if o.x <= 0.0 or o.y <= 0.0 or o.z <= 0.0:
				continue
			var why: String = _faces_fight(s[1], b[1])
			if why != "":
				bad += 1
				if bad <= MAX_REPORT:
					print("  SOLIDPROP %s <-> %s  (%s)" % [s[0], b[0], why])
				break
	print("WALL-OVERLAP solid props checked: %d" % solids.size())
	return bad


# PROOF THE SOLID-PROP CHECK CAN FAIL, derived from the scene and kept permanently.
#
# The `BoxMesh` pass was added on 2026-08-16 after six floating doors, a brass plate and the
# House's whole furniture set turned out to be invisible to this file. A check that has never
# been seen to fire is a check nobody should trust — so: build one `BoxMesh` sharing a face
# plane with a real wall of THIS scene, re-run the pass, and require the count to go up by
# exactly one. Returns 1 (a failure) if it does not.
func _self_test_solid(boxes: Array, baseline: int) -> int:
	# ⚠️ Pick the box's THIN axis to straddle, and be generous in the other two. The first
	# version of this control hard-coded +x and a 0.5 m cube, which on a FLOOR slab overlaps
	# only its 0.2 m thickness in y — under MIN_AREA — so the pair was skipped and the
	# control reported "not caught" on two perfectly healthy scenes.
	var wall: AABB = AABB()
	var found := false
	for b in boxes:
		var a: AABB = b[1]
		var big := 0
		for ax in 3:
			if a.size[ax] > 1.2:
				big += 1
		if big >= 2:
			wall = a
			found = true
			break
	if not found:
		print("  FAIL self-test: no wall-sized box to derive a control from")
		return 1

	var thin := 0
	for ax in 3:
		if wall.size[ax] < wall.size[thin]:
			thin = ax
	var size := Vector3(0.8, 0.8, 0.8)
	size[thin] = minf(0.4, wall.size[thin] * 0.8)

	var probe := MeshInstance3D.new()
	probe.name = "ZFightControlProbe"
	var bm := BoxMesh.new()
	bm.size = size
	probe.mesh = bm
	current_scene.add_child(probe)
	# Share the wall's far face along its own normal, overlapping well past MIN_AREA in the
	# two axes the wall is large in.
	var pos := wall.position + wall.size / 2.0
	pos[thin] = wall.position[thin] + wall.size[thin] - size[thin] / 2.0
	probe.global_position = pos

	var after := _check_solid_props(boxes)
	probe.queue_free()
	if after == baseline + 1:
		print("WALL-OVERLAP self-test: a coplanar BoxMesh IS caught (%d -> %d)"
			% [baseline, after])
		return 0
	print("  FAIL self-test: a coplanar BoxMesh was NOT caught (%d -> %d)" % [baseline, after])
	return 1


func _collect_solids(node: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is BoxMesh:
		var mi: MeshInstance3D = node
		var aabb := mi.get_aabb()
		var t := mi.global_transform
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for c in 8:
			var p: Vector3 = t * aabb.get_endpoint(c)
			lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
		out.append([mi.name, AABB(lo, hi - lo)])
	for c in node.get_children():
		_collect_solids(c, out)


func _collect(node: Node, out: Array) -> void:
	if node is CSGBox3D:
		var b: CSGBox3D = node
		out.append([b.name, AABB(b.global_position - b.size / 2.0, b.size), b.material])
	for c in node.get_children():
		_collect(c, out)


# "" when this coincident pair is NOT covered by the subclass's allowlist. Order-insensitive,
# and refuses any entry whose two boxes no longer share one material instance.
func _allowed(a: Array, b: Array) -> String:
	for entry in _allow:
		var n0: String = entry[0]
		var n1: String = entry[1]
		if not ((a[0] == n0 and b[0] == n1) or (a[0] == n1 and b[0] == n0)):
			continue
		if a.size() < 3 or b.size() < 3 or a[2] != b[2] or a[2] == null:
			print("  FAIL allowlisted pair %s <-> %s no longer shares one material" % [n0, n1])
			return ""
		return String(entry[2])
	return ""


func _overlap(a: AABB, b: AABB) -> Vector3:
	var amin := a.position
	var amax := a.position + a.size
	var bmin := b.position
	var bmax := b.position + b.size
	return Vector3(
		minf(amax.x, bmax.x) - maxf(amin.x, bmin.x),
		minf(amax.y, bmax.y) - maxf(amin.y, bmin.y),
		minf(amax.z, bmax.z) - maxf(amin.z, bmin.z))
