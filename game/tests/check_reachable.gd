extends SceneTree

# CAN THE PLAYER STAND WHERE THIS OBJECT IS?
#
#   Godot --headless --path game --script res://tests/check_reachable.gd
#   Godot --headless --path game --script res://tests/check_reachable.gd -- Backrooms
#
# WHY THIS EXISTS (cross-level X43, ISSUES_SOLUTIONS Issue 90). All eight alcoves of the
# Backrooms' SPRAWL were sealed behind an unbroken perimeter wall for the life of the zone.
# Behind them: the zone's only note — the page that states its own tell — its phone, its
# one-way mirror, two mirage doors and five props, i.e. every authored object in 1600 m²
# except the pillars, the lights and the four glitch walls. Nothing went red, because:
#
#   * `check_wall_overlap.gd`  asks "do two surfaces COINCIDE"
#   * `check_note_mounting.gd` asks "is this prop ON A WALL"       (a sealed alcove's back
#                                                                   wall is still a wall)
#   * `check_doorways.gd`      asks "is a doorway SEALED"          — RoomBuilder levels only,
#                                                                   and an alcove has no
#                                                                   doorway to seal
#   * `walk_*` / `autoplay_*`  walk routes SOMEBODY THOUGHT TO WALK
#
# and NOTHING anywhere asked whether a player can get to a thing. So this does, for every
# level, by the only method that can answer it: a flood fill of the standable space with the
# level's OWN player capsule, seeded at the spawn, followed by the SHIPPING interact ray.
#
# ------------------------------------------------------------------ what it asserts
#
# For every Node3D in the scene with an `interact()` method (notes, doors, breakers, bottles,
# lockers, phones, cots, sconces, drawers, keys, triggers — the whole interactable surface):
#
#   REACHABLE      some reachable standing cell exists from which `player.ai_interact_target()`
#                  — the real `_update_interact_prompt()` path, including `can_interact()` —
#                  returns that prop.
#   INERT          no cell yields a prompt, but the RAW interact ray (identical parameters,
#                  `hit_from_inside = true`) does reach it from a reachable cell. That is a
#                  prop that is deliberately refusing right now: `LabLocker` before its note,
#                  a `HouseFridge` already used, a gate awaiting a key. It is REACHED, so it
#                  is not the bug this file exists for — and separating the two is what stops
#                  the guard crying wolf on half the props in the game.
#   UNREACHABLE    neither. The player cannot get to it. This is the finding.
#
# ------------------------------------------------------------------ how it can fail
#
# ⚠️ PROVED, every run, on the Backrooms: `_self_test_seal()` drops a wall across the mouth of
# the Sprawl alcove that holds `SprawlNote` — restoring, exactly, the state this file was
# written for — re-floods, and requires the note to go from REACHABLE to UNREACHABLE. If the
# fill or the ray stops measuring anything, the control stops going red and the run fails.
#
# ⚠️ AND THE SAMPLE SIZE IS PART OF THE ASSERTION. A scene that failed to build has 0 cells
# and 0 targets and would otherwise be a tidy green: `min_cells` / `min_targets` are per-scene
# and required.
#
# ------------------------------------------------------------------ the three honest caveats
#
# 1. SEEDS. Some regions are reached by a teleport, not by walking (the Backrooms' three
#    zones, THE NIGHTMARE's dungeon behind the cot). Each of those is a SEPARATE, documented
#    seed; the fill then still answers the question inside that region.
# 2. GATES. A prop behind something that opens is not unreachable. Rather than waive the prop,
#    this OPENS THE GATE — a named list per scene, each with a reason, whose size is asserted.
#    That asks the right question: with every puzzle solved, is everything reachable?
# 3. DORMANT PROPS ARE COUNTED, NOT PROBED. A body with `visible == false` or
#    `PROCESS_MODE_DISABLED` is not in the physics space, so there is nothing to measure —
#    THE NIGHTMARE's bed is hidden until 7/7 sconces burn. This file therefore says nothing
#    about whether such a prop is reachable once it appears; `walk_dungeon.gd` and
#    `check_interact_reach.gd` are what cover that one. If the DORMANT column ever grows,
#    that is a coverage gap, not a pass.

const Scenes := preload("res://tests/lib/scenes.gd")

# ⚠️ 0.125 m, NOT the 0.25 that `autoplay_house_route.gd` uses, and the difference is the
# difference between a guard and a nuisance. Measured on the Backrooms hub: the lane from the
# hub into the E arm was 1.01 m wide between `ArrowColE` and `ArmNWallR`, against an 0.80 m
# capsule — a 0.21 m band of legal standing positions. At 0.25 m the 4-connected grid could
# not thread it and reported both of zone 1's arm mirage doors as unreachable, which was
# FALSE: the arm is walked in every playtest. Any interval of length >= STEP is guaranteed to
# contain a grid line, so 0.125 resolves a 0.21 m band by construction.
#
# ⚠️ THAT LANE IS NOW 2.02-2.38 m (2026-08-17, backlog 04 R2) — the player judged the old
# hub unwalkable in a J-capture and it turned out this file had measured the same fault a
# round earlier and reported it as a false positive rather than as a finding. Keep 0.125
# anyway. The number is not tuned to that one lane; it is the resolution at which a grid
# stops lying about a gap, and the lesson is the reason it is written down: when the fill
# says "unreachable" and a human says "I walk through there", the honest next step is to
# MEASURE the gap, not to loosen the grid until the complaint goes away.
const STEP := 0.125
const STEP_UP := 0.35       # CharacterBody3D cannot step up; only ramps climb
# ⚠️ 1.0 m, and REACHABILITY IS NOT THE SAME AS RETURN: a walking player steps off a ledge
# this high without thinking, so the space below it IS reachable even though they may not be
# able to climb back. At 0.6 the Intro failed outright — `intro_room.gd:_play_wakeup_beat()`
# puts the player ON THE GURNEY at y = 0.60, so the fill was trapped on the mattress by
# exactly the drop the game opens with.
const FALL_MAX := 1.00
const EYE_FALLBACK := 1.6
const MAX_CELLS := 700000   # runaway guard; a fill that hits this FAILS rather than truncates
const REACH_FRACTION := 0.9 # stand at 90 % of INTERACT_RANGE, like check_interact_reach.gd
const MIN_STAND := 0.45     # never test from inside the prop
const MAX_PROBES := 20      # candidate standing cells per prop

# ⚠️ THE FILL CAPSULE IS 2 cm NARROWER THAN THE PLAYER'S, and it has to be. A grid of
# STATIC capsule placements is a strictly harsher test than a `move_and_slide` body, which
# is pushed out of a shallow overlap and keeps walking. Measured, on the House cellar ramp:
# at z = 1.625 the capsule's lower hemisphere clips the ramp slab's top-end corner by **6 mm**
# — one grid line, right across the ramp's full width — and a 4-connected fill cannot step
# over it, so the whole cellar (and the level's third code digit) reported as unreachable on
# a ramp `walk_cellar.gd` drives down and back up every run. 2 cm is far under the thinnest
# wall in the game (0.20 m), so it cannot thread anything real.
const CAP_SHRINK := 0.02

# Scripts whose instances are removed before anything is measured. Teleporting a player
# around a level with fatal creatures in it is Issue 89 — a harness that photographs its own
# death and keeps going. This one also verifies the scene did not reload (see `_measure`).
const DISARM := [
	"creature_stalker.gd", "creature_smiler.gd", "creature_shapechanger.gd",
	"creature_object12.gd", "creature_hollow.gd", "creature_static.gd",
	"apparition.gd", "beartrap.gd", "dn_child.gd", "kneeling_man.gd",
	"weeping_frame.gd",
]

# ---------------------------------------------------------------------------- the scenes
#
# ⚠️ THE SCENE LIST IS DERIVED, NOT TYPED (2026-08-17, workstream H1). The rows below are
# keyed by `GameState`'s own `SCENE_*` constant and merged onto `tests/lib/scenes.gd`, which
# reads those constants out of `game_state.gd`. A level added to the game is swept here
# whether or not anybody remembers this file; a `SCENE_*` constant that is neither classified
# as a level nor excluded by name fails the run. This file already covered all nine scenes —
# it is the only guard that did — but it covered them by a hand-typed list of paths, which is
# the same thing `check_wall_overlap.gd` had before it lost six levels for a year.
#
# `seeds`  : Vector3 world positions, or a tag resolved by `_resolve_seed()`.
# `gates`  : { node name: why it is opened before the fill }.
# `ignore` : { prop name: why an UNREACHABLE verdict on it is accepted }.
const CONFIG := {
	"SCENE_INTRO": {
		# ⚠️ NOT `@player`. `intro_room.gd:_play_wakeup_beat()` starts the player LYING ON
		# THE GURNEY at y = GURNEY_TOP_Y, so a fill seeded there is trapped on the mattress —
		# stepping off means the capsule clipping the frame, which a grid of standing
		# positions cannot represent and a walking player does without noticing. Seed the
		# floor beside the gurney instead, derived from the level's own constant.
		"seeds": ["@intro_floor"], "gates": {}, "ignore": {},
		"min_cells": 6000, "min_targets": 2,
	},
	"SCENE_LEVEL_1": {
		"seeds": ["@player"],
		# The morgue shutter drops when the third breaker is thrown; the locker is SHOVED
		# aside to expose the breaker behind it. Both are solved states of a real puzzle.
		"gates": {
			"MorgueShutter": "drops when power is restored (3/3 breakers)",
			"RecordsLocker": "is shoved 1.3 m aside by the player to expose the Records breaker",
		},
		"ignore": {}, "min_cells": 10000, "min_targets": 8,
	},
	"SCENE_LEVEL_2": {
		"seeds": ["@player"],
		"gates": {
			"CellarGate": "opens with the cellar key, which is the level's own quest",
		},
		"ignore": {}, "min_cells": 7000, "min_targets": 8,
	},
	"SCENE_CORRIDOR": {
		"seeds": ["@player"], "gates": {}, "ignore": {},
		"min_cells": 25000, "min_targets": 5,
	},
	"SCENE_BACKROOMS": {
		# ⚠️ THREE SEEDS, because the three zones are connected by a glitch-wall TELEPORT and
		# by nothing else. A single fill from the Lobby spawn would report the Sprawl and the
		# Flood as unreachable, which is true of walking and false of the game.
		"seeds": ["@player", "@zone2", "@zone3"],
		"gates": {}, "ignore": {},
		"min_cells": 70000, "min_targets": 6,
		"control": "SprawlNote",
	},
	"SCENE_KONTUR": {
		"seeds": ["@player"],
		"gates": {
			"RosterSeal": "the welded personnel gate opens on the roster code (Gate 5)",
			"FungalBarrier": "the fungal mass dissolves when sprayed with vinegar (Gate 2)",
			"ChoiceDoor_": "both vestibule doors swing open on E (Gate 1); which is black "
				+ "is randomised per run, so the prefix opens the pair",
			"AirlockSeal": "the airlock opens once the catch minigame is passed (Gate 8)",
		},
		# ⚠️ 9 since 2026-08-18 — the Landing's briefing notice is an interactable too, and
		# a statement the player cannot walk up to is a statement they cannot re-read.
		"ignore": {}, "min_cells": 18000, "min_targets": 9,
	},
	"SCENE_LEVEL_6_BREACH": {
		"seeds": ["@player"], "gates": {}, "ignore": {},
		"min_cells": 18000, "min_targets": 8,
	},
	"SCENE_DUNGEON": {
		# The Antechamber and the dungeon are joined by the cot, i.e. by a sleep transition.
		# ⚠️ The dungeon is regenerated on every load; pin it with `-- --dungeon-seed N` when
		# reproducing a finding.
		"seeds": ["@player", "@dungeon"],
		"gates": {}, "ignore": {}, "min_cells": 25000, "min_targets": 8,
	},
	"SCENE_LEVEL_3": {
		"seeds": ["@player"], "gates": {},
		# ⚠️ REPORTED, NOT HIDDEN — and NOT FIXED, because the Void is not this pass's level.
		# Both notes sit in a pocket around x 8.5..9.0, z -1.0..0.5 that the fill cannot enter
		# from the spawn: the nearest REACHABLE standing cell is 4.79 m and 3.25 m away
		# respectively, while the fill covers 77 m² spanning the level's full extent and finds
		# the other eight interactables including `NoteVoid3` at (9, 9) and the `TwistNote`.
		# The level is still winnable (the twist note is the win condition and is reachable);
		# what is lost is one safe digit note and one trap note. Filed as cross-level X44 —
		# and note that `autoplay_exit_reachable.gd` has no Void route either, so this is the
		# first time anything walked it.
		"ignore": {
			"NoteVoid2": "unreachable pocket — cross-level X44, belongs to Level 8's own pass",
			"TrapVoid1": "same pocket, same finding — X44",
		},
		"min_cells": 3000, "min_targets": 6,
	},
}

var _scenes: Array = []
var _only := ""
var _stage := "load"
var _i := 0
var _t := 0.0
var _fails: Array[String] = []
var _checks := 0
var _rows: Array = []
var _scene_id := 0
var _control_before := false

# per-scene, filled by _measure()
var _cells: Dictionary = {}        # Vector3i -> Vector3 (world FEET position)
var _buckets: Dictionary = {}      # Vector2i -> Array[Vector3i]
var _cap_r := 0.4
var _cap_h := 1.8
var _eye := EYE_FALLBACK
var _reach := 2.7


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if not a.begins_with("--"):
			_only = a
	# ⚠️ Enrolment first: a scene constant nobody classified is a level nobody swept.
	for p in Scenes.problems():
		print("  FAIL enrolment: %s" % p)
		_fails.append("enrolment: " + String(p))
	for row in Scenes.levels():
		if _only != "" and String(row["label"]).to_lower().find(_only.to_lower()) < 0:
			continue
		# ⚠️ Defaults, so a level with no row here is still swept — from its own player spawn,
		# with the weakest possible sample floors. A new level cannot be silently skipped; the
		# most that can happen is that its floors are loose until somebody tightens them.
		var cfg: Dictionary = (CONFIG.get(row["key"], {}) as Dictionary).duplicate(true)
		cfg["label"] = String(row["label"])
		cfg["path"] = String(row["path"])
		if not cfg.has("seeds"):
			cfg["seeds"] = ["@player"]
		if not cfg.has("gates"):
			cfg["gates"] = {}
		if not cfg.has("ignore"):
			cfg["ignore"] = {}
		if not cfg.has("min_cells"):
			cfg["min_cells"] = 1000
		if not cfg.has("min_targets"):
			cfg["min_targets"] = 1
		_scenes.append(cfg)
	if _scenes.is_empty():
		print("REACHABLE FAIL: no scene matched %s" % _only)
		quit(1)
		return
	change_scene_to_file(_scenes[0]["path"])


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


# ------------------------------------------------------------------ driving

func _process(delta: float) -> bool:
	_t += delta
	match _stage:
		"load":
			# ⚠️ CSG colliders are not registered during `_ready()` (Issue 52), and the
			# procedural levels build everything there. Settle before any query.
			if _t < 1.4:
				return false
			_open_gates(_scenes[_i])
			_t = 0.0
			_stage = "gated"
		"gated":
			# A gate opened by disabling a CSG collider also needs a frame to take effect.
			if _t < 0.5:
				return false
			_measure(_scenes[_i])
			_t = 0.0
			if _scenes[_i].has("control"):
				_seal_control(_scenes[_i])
				_stage = "control"
			else:
				_stage = "next"
		"control":
			if _t < 0.6:
				return false
			_measure_control(_scenes[_i])
			_t = 0.0
			_stage = "next"
		"next":
			_i += 1
			if _i >= _scenes.size():
				return _report()
			_t = 0.0
			_stage = "load"
			change_scene_to_file(_scenes[_i]["path"])
	return false


# ------------------------------------------------------------------ setup helpers

func _walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children():
		_walk(c, out)
	return out


func _script_file(n: Node) -> String:
	var s: Script = n.get_script()
	if s == null:
		return ""
	return String(s.resource_path).get_file()


func _disarm(scene: Node) -> int:
	var killed := 0
	for n in _walk(scene, []):
		if DISARM.has(_script_file(n)):
			n.queue_free()
			killed += 1
	return killed


func _find_named(scene: Node, wanted: String) -> Array:
	var out: Array = []
	for n in _walk(scene, []):
		if String(n.name).begins_with(wanted):
			out.append(n)
	return out


# Turn a gate's collision off wherever it lives — a CollisionShape3D, a CSG box, or both.
#
# ⚠️ AND PUT IT BACK BEFORE PROBING (`_close_gates`). Several gates are interactables in their
# own right — `RecordsLocker`, `CellarGate`, both KONTUR `ChoiceDoor_`s, `FungalBarrier` — so
# leaving them open deletes the very collider the interact ray is aiming at, and the first
# run of this file reported five perfectly healthy props as unreachable for that reason. A
# gate is opened to answer "can the player get to the space BEHIND it" and for nothing else;
# props in that space are probed from cells inside it, so the restored gate never occludes
# them.
var _gated: Array = []

func _open_gates(cfg: Dictionary) -> void:
	var scene := current_scene
	if scene == null:
		return
	_gated = []
	var gates: Dictionary = cfg["gates"]
	for gname in gates:
		for node in _find_named(scene, String(gname)):
			# ⚠️ PREFER THE GAME'S OWN RESTORE PATH. `LabLocker` already has
			# `move_aside_instantly()` — the method `_restore_progress()` uses when the player
			# walks back into the Lab having already shoved it — so the guard slides the
			# locker exactly as the game does instead of deleting its collider. That matters
			# because the locker is BOTH a gate and a probe target, and it also occludes the
			# breaker behind it: nothing else reproduces the solved state correctly.
			if node.has_method("move_aside_instantly"):
				node.call("move_aside_instantly")
				continue
			for n in _walk(node, []):
				if n is CollisionShape3D and not (n as CollisionShape3D).disabled:
					(n as CollisionShape3D).disabled = true
					_gated.append(n)
				elif n is CSGShape3D and (n as CSGShape3D).use_collision:
					(n as CSGShape3D).use_collision = false
					_gated.append(n)
	if not gates.is_empty():
		print("      gates opened for the fill: %d collider(s) across %d documented gate(s)"
			% [_gated.size(), gates.size()])


func _close_gates() -> void:
	for n in _gated:
		if not is_instance_valid(n):
			continue
		if n is CollisionShape3D:
			(n as CollisionShape3D).disabled = false
		elif n is CSGShape3D:
			(n as CSGShape3D).use_collision = true
	_gated = []


func _resolve_seed(scene: Node, tag: Variant) -> Vector3:
	if tag is Vector3:
		return tag
	var s := String(tag)
	match s:
		"@player":
			var p := scene.get_node_or_null("Player") as Node3D
			return p.global_position if p else Vector3.ZERO
		"@zone2":
			var z := scene.get_node_or_null("ZoneSprawl")
			return z.get("spawn_point") if z else Vector3.ZERO
		"@zone3":
			var z3 := scene.get_node_or_null("ZoneFlood")
			return z3.get("spawn_point") if z3 else Vector3.ZERO
		"@intro_floor":
			var c: Dictionary = (load("res://scripts/intro_room.gd") as GDScript) \
				.get_script_constant_map()
			var g: Vector3 = c.get("GURNEY_POS", Vector3.ZERO)
			return g + Vector3(0, 0.2, -2.5)   # the open floor at the foot of the gurney
		"@dungeon":
			if scene.has_method("get_gen"):
				var gen: Object = scene.call("get_gen")
				if gen and gen.get("spawn_room") != null:
					return gen.call("room_center_world", gen.get("spawn_room"))
			return Vector3.ZERO
	return Vector3.ZERO


# ------------------------------------------------------------------ the flood fill

var _skip: Array = []      # the player's own RID — see _flood()

func _floor_at(space: PhysicsDirectSpaceState3D, x: float, z: float,
		from_y: float, to_y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, to_y, z))
	q.collision_mask = 1
	# ⚠️ The player is a solid body on layer 1 standing in the middle of the fill. Without
	# this, columns within a capsule radius of wherever they happen to be report the TOP OF
	# THE PLAYER as their floor, and the seed's own neighbourhood comes back unwalkable.
	q.exclude = _skip
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	return float(hit["position"].y)


func _key(p: Vector3) -> Vector3i:
	return Vector3i(int(round(p.x / STEP)), int(round(p.z / STEP)), int(round(p.y / 0.25)))


func _bucket(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / 3.0)), int(floor(p.z / 3.0)))


func _free(space: PhysicsDirectSpaceState3D, q: PhysicsShapeQueryParameters3D,
		feet: Vector3) -> bool:
	q.transform = Transform3D(Basis(), feet + Vector3(0, _cap_h / 2.0 + 0.05, 0))
	return space.intersect_shape(q, 1).is_empty()


# Lazy BFS over standing positions. Only cells CONNECTED to a seed are ever queried, which is
# what makes a 320 m corridor and a 460 m-wide three-zone scene affordable.
func _flood(scene: Node, seeds: Array) -> void:
	_cells = {}
	_buckets = {}
	var space := scene.get_viewport().find_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = _cap_r - CAP_SHRINK
	shape.height = _cap_h - 2.0 * CAP_SHRINK
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	var player := scene.get_node_or_null("Player") as CollisionObject3D
	_skip = [player.get_rid()] if player else []
	q.exclude = _skip

	var queue: Array[Vector3] = []
	for s in seeds:
		var sx: float = round(s.x / STEP) * STEP
		var sz: float = round(s.z / STEP) * STEP
		var y := _floor_at(space, sx, sz, s.y + 1.2, s.y - 4.0)
		if is_nan(y):
			continue
		var feet := Vector3(sx, y + 0.02, sz)
		if not _free(space, q, feet):
			continue
		var k := _key(feet)
		if _cells.has(k):
			continue
		_cells[k] = feet
		queue.append(feet)

	var dirs := [Vector3(STEP, 0, 0), Vector3(-STEP, 0, 0),
		Vector3(0, 0, STEP), Vector3(0, 0, -STEP)]
	while not queue.is_empty():
		if _cells.size() > MAX_CELLS:
			break
		var c: Vector3 = queue.pop_back()
		for d in dirs:
			var nx: float = c.x + d.x
			var nz: float = c.z + d.z
			var ny := _floor_at(space, nx, nz, c.y + STEP_UP, c.y - FALL_MAX)
			if is_nan(ny):
				continue
			var feet2 := Vector3(nx, ny + 0.02, nz)
			var k2 := _key(feet2)
			if _cells.has(k2):
				continue
			if not _free(space, q, feet2):
				continue
			_cells[k2] = feet2
			queue.append(feet2)

	for k in _cells:
		var b := _bucket(_cells[k])
		if not _buckets.has(b):
			_buckets[b] = []
		_buckets[b].append(_cells[k])


# ------------------------------------------------------------------ the props

func _collect_targets(scene: Node) -> Array:
	var out: Array = []
	for n in _walk(scene, []):
		if n is Node3D and n.has_method("interact"):
			out.append(n)
	return out


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return n
	for c in n.get_children():
		var f := _first_mesh(c)
		if f != null:
			return f
	return null


# ⚠️ AIM AT WHAT THE PLAYER CAN SEE, which is the mesh, never at the collider — aiming at a
# collider is what let an earlier reach test pass against props nobody could hit
# (check_interact_reach.gd's header).
func _art_centre(prop: Node3D) -> Vector3:
	var hinge: Variant = prop.get("_hinge")
	if hinge is Node3D:
		var hm := _first_mesh(hinge)
		if hm != null:
			return hm.global_transform * hm.get_aabb().get_center()
	var m := _first_mesh(prop)
	if m != null:
		return m.global_transform * m.get_aabb().get_center()
	return prop.global_position


# Distance from the prop to the closest standing cell anywhere in the fill. Only ever used
# to describe a failure, so a full scan is affordable.
func _nearest_cell(aim: Vector3) -> float:
	var best := INF
	for k in _cells:
		var feet: Vector3 = _cells[k]
		var d := Vector2(feet.x - aim.x, feet.z - aim.z).length()
		if d < best:
			best = d
	return best


func _candidates(aim: Vector3) -> Array:
	var out: Array = []
	var b := _bucket(aim)
	for bx in range(b.x - 1, b.x + 2):
		for bz in range(b.y - 1, b.y + 2):
			var key := Vector2i(bx, bz)
			if not _buckets.has(key):
				continue
			for feet in _buckets[key]:
				var d := Vector2(feet.x - aim.x, feet.z - aim.z).length()
				if d < MIN_STAND or d > _reach:
					continue
				out.append([absf(d - 1.4), feet])
	out.sort_custom(func(a, c): return a[0] < c[0])
	var picked: Array = []
	for e in out:
		picked.append(e[1])
		if picked.size() >= MAX_PROBES:
			break
	return picked


# Returns "prompt" / "ray" / "" — see the header's REACHABLE / INERT / UNREACHABLE.
func _verdict(player: Node3D, prop: Node3D, aim: Vector3) -> String:
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	var best := ""
	for feet in _candidates(aim):
		player.global_position = Vector3(feet.x, feet.y, feet.z)
		player.force_update_transform()
		player.call("ai_look_at", aim)
		if cam:
			cam.force_update_transform()
		var target: Node = player.call("ai_interact_target")
		if target != null and (target == prop or prop.is_ancestor_of(target)):
			return "prompt"
		# The same ray the prompt uses, minus `can_interact()`: distinguishes "the player
		# cannot get to it" from "the prop is deliberately refusing right now".
		if cam:
			var space := player.get_world_3d().direct_space_state
			var origin: Vector3 = cam.global_position
			var q := PhysicsRayQueryParameters3D.create(origin,
				origin - cam.global_transform.basis.z * _reach / REACH_FRACTION)
			q.exclude = [(player as CollisionObject3D).get_rid()]
			q.hit_from_inside = true
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var col: Node = hit["collider"]
				if col == prop or prop.is_ancestor_of(col):
					best = "ray"
	return best


# ------------------------------------------------------------------ measuring

func _measure(cfg: Dictionary) -> void:
	var label := String(cfg["label"])
	print("--- %s ---" % label)
	var scene := current_scene
	_scene_id = scene.get_instance_id()
	var player := scene.get_node_or_null("Player") as Node3D
	_ok("%s: player exists" % label, player != null)
	if player == null:
		_rows.append([label, 0, 0, 0, 0])
		return
	print("      disarmed %d fatal entit(ies)" % _disarm(scene))
	# ⚠️ Stop the player TICKING. Nothing here is a playthrough: with `_physics_process` off
	# there is no gravity, no gaze clock and no panic, so parking the camera on a
	# `trigger_object` for a frame cannot fire a screamer and invalidate every later probe.
	player.set_physics_process(false)
	player.set_process(false)
	player.set("ai_active", true)

	var caps := _capsule_of(player)
	_cap_r = caps.x
	_cap_h = caps.y
	var cam := player.get_node_or_null("Camera3D") as Node3D
	_eye = cam.position.y if cam else EYE_FALLBACK
	var ir: Variant = player.get_script().get("INTERACT_RANGE")
	_reach = (float(ir) if ir != null else 3.0) * REACH_FRACTION

	var seeds: Array = []
	for tag in cfg["seeds"]:
		var s := _resolve_seed(scene, tag)
		if s != Vector3.ZERO or String(tag) == "@player":
			seeds.append(s)
	_ok("%s: every documented seed resolved" % label, seeds.size() == cfg["seeds"].size(),
		"%d of %d" % [seeds.size(), cfg["seeds"].size()])

	var t0 := Time.get_ticks_msec()
	_flood(scene, seeds)
	var ms := Time.get_ticks_msec() - t0
	# ⚠️ The EXTENT is printed as well as the count, because a fill that stalls in a pocket and
	# a fill that covers the level both produce a number, and only the extent says which.
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for k in _cells:
		var f: Vector3 = _cells[k]
		lo = Vector3(minf(lo.x, f.x), minf(lo.y, f.y), minf(lo.z, f.z))
		hi = Vector3(maxf(hi.x, f.x), maxf(hi.y, f.y), maxf(hi.z, f.z))
	_ok("%s: the flood fill measured something" % label,
		_cells.size() >= int(cfg["min_cells"]) and _cells.size() < MAX_CELLS,
		"%d standing cells (%.1f m²) in %d ms, extent %v..%v (capsule r=%.2f h=%.2f, eye %.2f)"
			% [_cells.size(), _cells.size() * STEP * STEP, ms, lo.snappedf(0.1),
				hi.snappedf(0.1), _cap_r, _cap_h, _eye])

	# The fill is done; every gate goes back exactly as it was before anything is probed.
	_close_gates()
	var targets := _collect_targets(scene)
	_ok("%s: found interactables to probe" % label,
		targets.size() >= int(cfg["min_targets"]), "%d props" % targets.size())

	var ignore: Dictionary = cfg["ignore"]
	var reachable := 0
	var inert := 0
	var dormant := 0
	var contained := 0
	var bad: Array = []
	var waived := 0
	var verdicts: Dictionary = {}
	for p in targets:
		# ⚠️ NOT IN THE WORLD YET. `dungeon.gd:_build_bed()` hides `TheBed` and sets
		# `PROCESS_MODE_DISABLED` until 7/7 sconces burn, which takes its body out of the
		# physics space entirely — so the fill walks through it and the ray passes through
		# it. That is the feature working, not a sealed room. Read from the NODE'S OWN
		# STATE, never from a name list, so this cannot go stale.
		if not p.is_visible_in_tree() or not p.can_process():
			dormant += 1
			verdicts[p] = "dormant"
			continue
		var aim := _art_centre(p)
		var v := _verdict(player, p, aim)
		verdicts[p] = v
		match v:
			"prompt": reachable += 1
			"ray": inert += 1
			_:
				# ⚠️ INSIDE SOMETHING THAT OPENS. The Lab's `HintPage` lives inside
				# `RecordsCabinet0/Drawer0`; the drawer is the interactable and the page is
				# reached by opening it. If any ANCESTOR is itself an interactable that this
				# run found reachable, the content is reachable too — a structural rule, not
				# a per-prop waiver.
				var host := _reachable_host(p, verdicts)
				if host != "":
					contained += 1
					print("      CONTAINED %s — reached by opening %s" % [p.name, host])
				elif ignore.has(String(p.name)):
					waived += 1
					print("      IGNORED %s — %s" % [p.name, ignore[String(p.name)]])
				else:
					# Report HOW it is unreachable: no standing cell in range at all is a
					# sealed room; cells in range but no ray is an aiming/collider fault.
					bad.append("%s @%v [%d cells in range, nearest %.2f m]"
						% [p.name, aim.snappedf(0.1), _candidates(aim).size(),
							_nearest_cell(aim)])
	_ok("%s: every interactable can be reached" % label, bad.is_empty(),
		"%d unreachable: %s" % [bad.size(), ", ".join(bad.slice(0, 12))])
	_ok("%s: the ignore list is exactly the size it claims" % label,
		waived == ignore.size(), "%d waived of %d listed" % [waived, ignore.size()])
	# Issue 89: a harness that dies mid-run keeps producing plausible output.
	_ok("%s: the scene did not reload while probing" % label,
		current_scene != null and current_scene.get_instance_id() == _scene_id)
	_rows.append([label, targets.size(), reachable, inert, contained, dormant, waived,
		bad.size()])
	print("      %s: %d reachable, %d inert, %d contained, %d dormant, %d UNREACHABLE, %d waived"
		% [label, reachable, inert, contained, dormant, bad.size(), waived])


# The nearest ancestor that is itself an interactable this run classified as reachable
# (or inert — a drawer that has already been opened still contained its page).
func _reachable_host(p: Node, verdicts: Dictionary) -> String:
	var n: Node = p.get_parent()
	while n != null and n != current_scene:
		if verdicts.has(n) and String(verdicts[n]) in ["prompt", "ray"]:
			return String(n.get_parent().name) + "/" + String(n.name)
		n = n.get_parent()
	return ""


func _capsule_of(player: Node3D) -> Vector2:
	for n in _walk(player, []):
		if n is CollisionShape3D and (n as CollisionShape3D).shape is CapsuleShape3D:
			var c := (n as CollisionShape3D).shape as CapsuleShape3D
			return Vector2(c.radius, c.height)
	return Vector2(0.4, 1.8)


# ------------------------------------------------------------------ the control
#
# ⚠️ PROOF THIS FILE CAN FAIL, kept permanently and derived from the scene under test rather
# than typed. It walls the named prop's alcove mouth back up — which is EXACTLY the state
# every one of the Sprawl's eight alcoves was in until 2026-08-17 — and requires the verdict
# to flip from reachable to unreachable. A fill or a ray that has stopped measuring anything
# leaves the control green, so the control is what makes the green above mean something.

var _control_wall: CSGBox3D = null

func _seal_control(cfg: Dictionary) -> void:
	var scene := current_scene
	var name_wanted := String(cfg["control"])
	var prop: Node3D = null
	for n in _walk(scene, []):
		if String(n.name) == name_wanted and n is Node3D:
			prop = n
			break
	# ⚠️ BOTH HALVES, or the control is vacuous: on 2026-08-17, before the perimeter was cut,
	# `SprawlNote` was ALREADY unreachable and "sealing it makes it unreachable" was green
	# while measuring nothing at all. The control must first prove the prop is reachable.
	_control_before = prop != null and _verdict(
		scene.get_node_or_null("Player") as Node3D, prop, _art_centre(prop)) != ""
	_ok("%s: the control prop %s is reachable BEFORE it is sealed"
		% [String(cfg["label"]), name_wanted], _control_before)
	if prop == null or not _control_before:
		return
	# ⚠️ "Out of the alcove" is derived from the FILL, not from the prop's own basis. The first
	# version used `-prop.global_transform.basis.z` and sealed the wall BEHIND the note: a
	# `note.gd` body carries its paper on +Z, so its -Z points into the plaster, and the
	# control cheerfully reported the note still reachable through a slab in the wrong place.
	var centroid := Vector3.ZERO
	var cands := _candidates(_art_centre(prop))
	for c in cands:
		centroid += c
	if cands.is_empty():
		return
	centroid /= float(cands.size())
	var out: Vector3 = centroid - prop.global_position
	out.y = 0.0
	if out.length() < 0.01:
		return
	out = out.normalized()
	_control_wall = CSGBox3D.new()
	_control_wall.name = "ReachControlSeal"
	_control_wall.size = Vector3(6.0, 6.0, 0.4)   # wider and taller than the mouth it seals
	_control_wall.use_collision = true
	scene.add_child(_control_wall)
	var pos: Vector3 = prop.global_position + out * 1.3 + Vector3(0, 1.5, 0)
	_control_wall.global_position = pos
	# A CSGBox3D is thin along its LOCAL Z; `look_at` points local -Z at the target, so
	# looking back at the prop puts the thin axis along `out`, i.e. across the mouth.
	_control_wall.look_at(pos - out, Vector3.UP)


func _measure_control(cfg: Dictionary) -> void:
	var label := String(cfg["label"])
	var name_wanted := String(cfg["control"])
	if not _control_before:
		return
	var scene := current_scene
	var player := scene.get_node_or_null("Player") as Node3D
	var prop: Node3D = null
	for n in _walk(scene, []):
		if String(n.name) == name_wanted and n is Node3D:
			prop = n
			break
	if player == null or prop == null:
		_ok("%s: control could be measured" % label, false)
		return
	var seeds: Array = []
	for tag in cfg["seeds"]:
		seeds.append(_resolve_seed(scene, tag))
	_flood(scene, seeds)
	var v := _verdict(player, prop, _art_centre(prop))
	_ok("%s: SEALING %s's mouth makes it UNREACHABLE (the pre-2026-08-17 Sprawl, restored)"
		% [label, name_wanted], v == "", "verdict after sealing: '%s'" % v)
	if is_instance_valid(_control_wall):
		_control_wall.queue_free()


# ------------------------------------------------------------------ report

func _report() -> bool:
	print("")
	print("REACHABILITY SWEEP")
	print("%-11s %7s %10s %6s %10s %8s %7s %12s" % ["LEVEL", "TARGETS", "REACHABLE",
		"INERT", "CONTAINED", "DORMANT", "WAIVED", "UNREACHABLE"])
	print("-------------------------------------------------------------------------------")
	for r in _rows:
		print("%-11s %7d %10d %6d %10d %8d %7d %12d"
			% [r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7]])
	print("-------------------------------------------------------------------------------")
	print("  %d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL — " + ", ".join(_fails))
		quit(1)
	return true
