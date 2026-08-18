extends SceneTree

# EVERY FLUSH WALL PROP IS SEATED AGAINST ITS WALL — not merely clear of it. **All nine
# levels, in one run.**
#
#   Godot --headless --path game --script res://tests/check_prop_mounting.gd
#   Godot --headless --path game --script res://tests/check_prop_mounting.gd -- Corridor
#
# WHY THIS EXISTS. `check_wall_overlap.gd` asserts a MINIMUM clearance and has no maximum, so
# a prop that has drifted AWAY from its wall — or that never had one — passes every check it
# makes. That is cross-level item X1, and the Corridor is where it finally cost something:
# six `AjarDoor` leaves shipped **0.090 m** proud of the wallpaper with nothing behind them
# and the brass plate at **0.110 m**, and the player photographed them (*"some of the doors
# in the corridor are not linked to the walls — the same issue we had with the intro
# level"*). Every other flush prop in that level was at 0.020 m.
#
# It was worse than a missing maximum. `check_wall_overlap.gd:_collect_quads()` collected
# `QuadMesh` ONLY, and both offenders are `BoxMesh`, so they were invisible to the prop check
# in BOTH directions. That hole is closed there too (`_check_solid_props`), but a face-plane
# test can only ever catch a prop that is z-fighting; it cannot catch one that is floating.
# This file is the other half.
#
# HOW IT MEASURES. Per PROP, not per mesh: gather every mesh in the prop's subtree, find the
# one whose geometry reaches furthest BACK along the prop's own -Z, and fire a ray from that
# back plane into the wall. The minimum over the prop's meshes is its back-face gap. Doing it
# per mesh instead would fail every double-sided prop in the level on its FRONT face — an
# `AjarDoor`'s front art quad is legitimately 0.13 m off the wall because there is 0.10 m of
# door behind it.
#
# ⚠️ RAYS, never `intersect_shape` — Issue 40: a shape query against CSG reports NOTHING when
# it lies wholly inside the slab, i.e. it approves precisely the case being rejected.
#
# ⚠️ It asserts its own SAMPLE SIZE and carries a positive control DERIVED FROM THIS SCENE
# (X18): a prop this run has just certified as seated is cloned, floated out by the exact
# 0.09 m the doors shipped at, and must be rejected — and then pushed 0.09 m INTO the wall
# and rejected again, or "seated" would only ever mean "not floating". A control written
# against fixed coordinates is a vacuous pass the moment the level moves.
#
# ------------------------------------------------------------------ coverage
#
# ⚠️ A SWEEP SINCE 2026-08-17 (workstream H1), and `check_corridor_mounting.gd` before that —
# one level, because `tools/run_tests.sh` has no per-test argument mechanism and a wrapper is
# a thing to remember. It now iterates `tests/lib/scenes.gd`, derived from `GameState`'s own
# `SCENE_*` constants.
#
# ⚠️ AND THE FREE-STANDING RULE IS WHAT MAKES THAT SURVIVABLE. The Corridor is a hallway
# whose props are all wall panels, so there "nothing behind it" is a defect. Every other
# level has furniture: a bed, a gurney, a filing cabinet and a pedestal are all vertical
# prop faces with no wall behind them, and demanding one would report a hundred healthy
# objects. So a prop with nothing within `PROBE` behind it is classified FREE-STANDING and
# counted, not failed — except where a scene declares `require_wall`, which the Corridor
# does. A guard that cries wolf is a guard people learn to ignore, and that is precisely how
# the last three of these went quietly wrong.

const Scenes := preload("res://tests/lib/scenes.gd")

const PROBE := 0.80        # how far behind a prop we look for a wall at all
const DEFAULT_MIN_GAP := 0.005    # below this it is z-fighting the wall
# ⚠️ 0.15 m by default, 0.045 in the Corridor, and the difference is a real convention split.
# `corridor.gd:WALL_INSET` is 0.03; the `RoomBuilder` levels hang props with
# `wall_point(..., inset)` whose inset is measured from the room's NOMINAL boundary while the
# wall's inner face is T/2 = 0.10 m in from that — so the house style of 0.16 leaves 0.06 m
# and the "something hangs behind it" style of 0.22 leaves 0.12 m. Both are correct and both
# would read as floating against the Corridor's number.
const DEFAULT_MAX_GAP := 0.15
# ⚠️ AND A PROP DEEPER THAN THIS ALONG ITS OWN FACING IS FURNITURE, NOT A WALL PANEL — the
# single most important false-positive filter in this file. A flush wall prop is thin: the
# Corridor's `AjarDoor` leaf is 0.10 m, its brass plate less. A filing cabinet, a steel
# locker, a hiding cabinet, a map stand and a fridge are all vertical faces standing NEAR a
# wall, and measured without this they reported as "floating" at 0.18-0.48 m: 12 healthy
# objects across four levels, in the first run. They are not floating, they are furniture,
# and furniture legitimately stands off the wall. `check_wall_overlap.gd:_check_solid_props`
# is what covers them, by face plane.
#
# ⚠️ It is also what keeps a ZONE CONTAINER out: `ZoneSprawl` and `ZoneFlood` are Node3Ds
# with meshes under them, and their "depth" is 40 m.
const MAX_PROP_DEPTH := 0.35
# ⚠️ ...AND A THIN PROP WITH A WALL FURTHER THAN THIS BEHIND IT IS NOT MOUNTED ON IT EITHER.
# `PROBE` is 0.80 m, and in a house every wall has something standing near it: the House's TV
# is a 0.08 m panel 0.46 m out from the living-room wall, and its bathroom map lies on a stool
# 0.28 m from the tiles. Both reported as "floating", and both are simply objects in a room.
# The defect this file exists for is a prop that LOOKS attached and is not — a door leaf
# 0.09 m proud of its wallpaper — so the floating band runs from the seating maximum to here,
# and anything beyond is free-standing. ⚠️ The Corridor overrides this to the full PROBE,
# because there every prop IS a wall panel and "nothing behind it" is already a failure there.
const DEFAULT_NEAR_WALL := 0.25

# ---------------------------------------------------------------- the per-scene rows
#
#   min_gap / max_gap   the seating band for this scene's mounting convention
#   require_wall        a prop with no wall behind it FAILS rather than being counted as
#                       free-standing (the Corridor, whose props are all wall panels)
#   min_props           how many props must be measured — "0 measured ... PASS" has shipped
#   min_free            ...and how many are expected to be free-standing furniture, so that
#                       branch cannot silently become where every prop goes
#   filed               {node name or prefix: why this finding is not being fixed here}
#   min_filed           and how many surfaces those entries must still account for
#   skip_scripts / skip_prefix / skip_exact   additions to the global skip lists
#   seeds               RNG seeds for a scene that builds itself from dice
const CONFIG := {
	"SCENE_INTRO": {
		"min_props": 3, "min_free": 1,
		# ⚠️ FILED, NOT FIXED — the Intro is a verified, closed level. `check_intro_geometry.gd`
		# already owns this room's mounting numbers and passes; the entries below are props
		# this broader sweep sees that the narrower guard does not enumerate.
		"filed": {},
	},
	"SCENE_LEVEL_1": {"min_props": 10, "min_free": 2, "filed": {}},
	"SCENE_LEVEL_2": {"min_props": 10, "min_free": 4, "filed": {}},
	"SCENE_CORRIDOR": {
		# The Corridor's own convention, and its own guard's numbers, unchanged.
		"min_gap": 0.005, "max_gap": 0.045, "require_wall": true, "near_wall": 0.80,
		# ⚠️ 28, not 30 (2026-08-16). It was set AT the measured count of 31 minus a hair,
		# which meant the first legitimate prop removal — the 230 m turn mirror, on the user's
		# request — put a correct level one prop from a red test. The floor exists to catch a
		# scene that builds NOTHING, so it sits a couple below the real count.
		"min_props": 28, "min_free": 0, "filed": {},
	},
	"SCENE_BACKROOMS": {"min_props": 6, "min_free": 2, "filed": {}},
	"SCENE_KONTUR": {"min_props": 12, "min_free": 3, "filed": {}, "seeds": [7]},
	"SCENE_LEVEL_6_BREACH": {
		# ⚠️ Three panels and eleven pieces of furniture: the Breach is a level of lockers,
		# cabinets and desks, and its only flush wall props are its signs.
		"min_props": 3, "min_free": 0, "filed": {},
	},
	"SCENE_DUNGEON": {"min_props": 6, "min_free": 1, "filed": {}, "seeds": [1]},
	"SCENE_LEVEL_3": {
		# ⚠️ min_props 0 IS A FINDING, NOT A SETTING, and it is filed in backlogs/08-void.md:
		# The Void has NO flush wall props at all. Its eight notes stand on tables, its
		# creatures are excluded as creatures, and its geometry is CSG. This guard therefore
		# says nothing about that level, which is a coverage gap rather than a clean bill.
		"min_props": 0, "min_free": 0, "filed": {},
	},
}

# Classes that legitimately stand PROUD of the wall, excluded by what they are rather than by
# where they ended up:
#   Torch3D        a bracket projects ~0.15 m by design — that is what a bracket is
#   AjarFrame_/    the door architrave and the turn-mirror frames, bars deliberately
#   FakeFrame_/    standing FRAME_PROUD off the wall so the panel inside them reads as
#   MirrorFrame_/  recessed. ⚠️ Their back face is sunk WALL_INSET + FRAME_SINK, i.e. 1 cm
#   FalseExitFrame INSIDE the wall slab — so the probe ray starts inside CSG, whose backfaces
#                  do not collide (Issue 59), and reports "nothing behind it". That is the
#                  measurement being wrong, not the prop
#   MirrorFigure   a Watcher standing in the corridor, not a wall prop at all
# and things that are not wall-mounted in the first place:
#   IntroNote      lies on a table on the centreline
#   NoteTable      is the table
#   BackDoor/Exit  built by door.gd in the end caps, on a different convention
const SKIP_EXACT := ["IntroNote", "NoteTable", "ExitDoor", "BackDoor"]
const SKIP_PREFIX := ["AjarFrame_", "FakeFrame_", "MirrorFrame_", "MirrorFigure",
	"FalseExitFrame"]
# ⚠️ Excluded by SCRIPT FILE, not by `is Beartrap` and not by node name.
#   * not by name — `Torch3D.new()` is never named, so Godot calls all sixteen of them
#     "@Node3D@NN" and any name filter misses every one;
#   * not by class identifier — naming `Beartrap` in a `--script` SceneTree tool forces
#     `beartrap.gd` to compile before the autoloads exist, and it references `GameState` at
#     class scope, so the whole dependency chain fails to compile. Measured (X29/Issue 82):
#     it took `Beartrap.new()` down inside the LEVEL, so the scene under test was built
#     without its beartraps while the test itself still passed.
# The creatures are here for the same reason they are excluded from `check_note_mounting.gd`:
# a billboard mimic standing in the middle of a room is a creature, not a floating prop.
const SKIP_SCRIPTS := [
	"torch_3d.gd", "beartrap.gd", "watcher.gd", "door.gd",
	"creature_stalker.gd", "creature_smiler.gd", "creature_shapechanger.gd",
	"creature_object12.gd", "creature_hollow.gd", "creature_static.gd",
	"apparition.gd", "dn_child.gd", "kneeling_man.gd", "congregation.gd",
	"unseen_wader.gd", "key_item.gd", "bottle_item.gd",
]

var _rows: Array = []
var _row := 0
var _t := 0.0
var _checks := 0
var _fails: Array[String] = []
var _summary: Array = []
var _only := ""

# per-scene
var _min_gap := DEFAULT_MIN_GAP
var _max_gap := DEFAULT_MAX_GAP
var _require_wall := false
var _near_wall := DEFAULT_NEAR_WALL
var _filed: Dictionary = {}
var _measured := 0
var _free := 0
var _furniture := 0
var _filed_seen := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1 and not String(args[0]).begins_with("--"):
		_only = args[0]
	for p in Scenes.problems():
		print("  FAIL enrolment: %s" % p)
		_fails.append("enrolment: " + String(p))
	for s in Scenes.levels():
		if _only != "" and String(s["label"]).to_lower().find(_only.to_lower()) < 0:
			continue
		var cfg: Dictionary = CONFIG.get(s["key"], {})
		for sd in cfg.get("seeds", [1]):
			_rows.append({
				"label": String(s["label"]), "path": String(s["path"]),
				"settle": float(s["settle"]), "seed": int(sd), "cfg": cfg,
			})
	if _rows.is_empty():
		print("PROP-MOUNTING FAIL: no scene matched '%s'" % _only)
		quit(1)
		return
	_load_row()


func _load_row() -> void:
	var r: Dictionary = _rows[_row]
	var cfg: Dictionary = r["cfg"]
	_min_gap = float(cfg.get("min_gap", DEFAULT_MIN_GAP))
	_max_gap = float(cfg.get("max_gap", DEFAULT_MAX_GAP))
	_require_wall = bool(cfg.get("require_wall", false))
	_near_wall = float(cfg.get("near_wall", DEFAULT_NEAR_WALL))
	_filed = cfg.get("filed", {})
	_measured = 0
	_free = 0
	_furniture = 0
	_filed_seen = 0
	_t = 0.0
	Scenes.pin_rng(int(r["seed"]))
	change_scene_to_file(String(r["path"]))


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _process(delta: float) -> bool:
	_t += delta
	# ⚠️ TIME, never a frame count (X42); CSG colliders are not registered during _ready()
	# (Issue 52), so a ray fired too early reports every prop as unbacked.
	if _t < float(_rows[_row]["settle"]):
		return false

	var before := _fails.size()
	var cfg: Dictionary = _rows[_row]["cfg"]
	print("")
	print("--- wall-prop mounting: %s (%s, seed %d) ---"
		% [_rows[_row]["label"], _rows[_row]["path"], int(_rows[_row]["seed"])])

	var props: Array = []
	_gather(current_scene, props)

	var seated: Array = []
	for entry in props:
		var node: Node3D = entry[0]
		var gap: float = _back_gap(node, entry[1], entry[2])
		if not is_finite(gap) or gap > _near_wall:
			# Nothing behind it, or a wall too far behind to be what it is mounted on.
			if not _require_wall:
				_free += 1
				continue
		_measured += 1
		var ok: bool = gap >= _min_gap and gap <= _max_gap
		if ok:
			seated.append([entry[0], entry[1], entry[2], gap])
			continue
		var why := _filed_reason(String(node.name))
		if why != "":
			_filed_seen += 1
			print("  FILED %s at %s  — %s"
				% [node.name, ("%.3f m behind it" % gap) if is_finite(gap) else "no wall", why])
			continue
		_ok("%s is seated against its wall" % _label_of(node), false,
			("%.3f m behind it (band %.3f..%.3f)" % [gap, _min_gap, _max_gap]) if is_finite(gap)
				else "NOTHING within %.2f m behind it" % PROBE)

	# ⚠️ "0 props checked ... PASS" has shipped in this repo more than once.
	_ok("enough wall props were actually measured",
		_measured >= int(cfg.get("min_props", 1)),
		"%d measured, minimum %d" % [_measured, int(cfg.get("min_props", 1))])
	# ⚠️ ...and the free-standing branch is asserted too, or a level whose every prop drifted
	# into open air would report a tidy zero.
	_ok("the free-standing count is what this scene should have",
		_free >= int(cfg.get("min_free", 0)),
		"%d free-standing, minimum %d" % [_free, int(cfg.get("min_free", 0))])
	if not _filed.is_empty():
		_ok("every filed finding is still present", _filed_seen >= _filed.size(),
			"%d seen, %d entries" % [_filed_seen, _filed.size()])

	_self_test(seated)

	_summary.append("%-10s seed %-4d %s (%d panels, %d free, %d furniture, %d filed, %d failing)"
		% [_rows[_row]["label"], _rows[_row]["seed"],
			"PASS" if _fails.size() == before else "FAIL",
			_measured, _free, _furniture, _filed_seen, _fails.size() - before])
	_row += 1
	if _row < _rows.size():
		_load_row()
		return false

	print("")
	print("--- PROP-MOUNTING SWEEP: %d scene-run(s) ---" % _rows.size())
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


# ⚠️ A prop built in code and never named is `@StaticBody3D@554`, and that number MOVES with
# the build order — it is useless in a report and worse in a waiver key. Always print the
# parent chain and the world position with it.
func _label_of(n: Node3D) -> String:
	var parent := n.get_parent()
	var pname := String(parent.name) if parent else "-"
	return "%s (under %s) at %v" % [n.name, pname, n.global_position.snappedf(0.01)]


func _filed_reason(name: String) -> String:
	for key in _filed:
		if name == key or name.begins_with(String(key)):
			return String(_filed[key])
	return ""


# ⚠️ Descend through `ScaryObject` and through bare containers. `ScaryObject` extends Node,
# not Node3D — that is the documented transform-chain gotcha the whole gaze system is built
# on — so every cursed panel and every turn mirror is `ScaryObject -> StaticBody3D`.
# Iterating the level's Node3D children alone silently skipped eight props in the Corridor,
# including the three the user complained about, and would have reported a comfortable pass.
#
# A node with meshes IS the prop and its subtree is not descended into; a node without them
# is a container and is. A skipped node takes its whole subtree with it.
func _gather(node: Node, out: Array) -> void:
	for child in node.get_children():
		var sf := _script_file(child)
		if _skipped(String(child.name)) or SKIP_SCRIPTS.has(sf):
			continue
		if child is CSGShape3D or child is Area3D or child is AudioStreamPlayer3D:
			continue
		if child is Light3D or child is Camera3D or child is CharacterBody3D:
			continue
		if not (child is Node3D):
			_gather(child, out)         # ScaryObject and other plain-Node wrappers
			continue
		var meshes: Array = []
		_collect_meshes(child, meshes)
		if meshes.is_empty():
			_gather(child, out)
			continue
		# Only props hung on a wall PLANE: their own +Z is the outward normal, so a prop
		# whose +Z points up or down is a floor/ceiling decal and out of scope here.
		var n: Vector3 = (child as Node3D).global_transform.basis.z.normalized()
		if absf(n.y) > 0.3:
			continue
		if _depth_along(meshes, n) > MAX_PROP_DEPTH:
			_furniture += 1
			continue
		out.append([child, meshes, n])


# How deep the prop is along its own facing normal, in metres.
func _depth_along(meshes: Array, n: Vector3) -> float:
	var lo := INF
	var hi := -INF
	for mi in meshes:
		var m: MeshInstance3D = mi
		var aabb: AABB = m.get_aabb()
		var xf: Transform3D = m.global_transform
		for c in 8:
			var d: float = (xf * aabb.get_endpoint(c)).dot(n)
			lo = minf(lo, d)
			hi = maxf(hi, d)
	return hi - lo


func _script_file(n: Node) -> String:
	var s: Script = n.get_script()
	if s == null:
		return ""
	return s.resource_path.get_file()


func _skipped(n: String) -> bool:
	if SKIP_EXACT.has(n):
		return true
	for p in SKIP_PREFIX:
		if n.begins_with(p):
			return true
	return false


func _collect_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh is QuadMesh or mi.mesh is BoxMesh or mi.mesh is PlaneMesh:
			out.append(mi)
	for c in node.get_children():
		_collect_meshes(c, out)


# Metres of air between the prop's back face and the wall behind it. INF when there is no
# wall there at all — which is the "hung in a doorway" / "floating in the room" case in a
# level of wall panels, and ordinary furniture anywhere else. The caller decides which.
func _back_gap(root: Node3D, meshes: Array, n: Vector3) -> float:
	var best := INF
	var excluded: Array[RID] = []
	_collect_rids(root, excluded)
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	if player:
		excluded.append(player.get_rid())
	var space := current_scene.get_viewport().world_3d.direct_space_state

	for mi in meshes:
		var m: MeshInstance3D = mi
		var aabb: AABB = m.get_aabb()
		var xf: Transform3D = m.global_transform
		var back_depth := INF
		var centre := Vector3.ZERO
		for c in 8:
			var p: Vector3 = xf * aabb.get_endpoint(c)
			back_depth = minf(back_depth, p.dot(n))
			centre += p
		centre /= 8.0
		# The point on this mesh's BACK plane, at the mesh's own lateral centre.
		var from: Vector3 = centre + n * (back_depth - centre.dot(n)) + n * 0.002
		var q := PhysicsRayQueryParameters3D.create(from, from - n * PROBE)
		q.exclude = excluded
		q.collide_with_areas = false
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		best = minf(best, from.distance_to(hit["position"]) - 0.002)
	return best


func _collect_rids(node: Node, out: Array[RID]) -> void:
	if node is CollisionObject3D:
		out.append((node as CollisionObject3D).get_rid())
	for c in node.get_children():
		_collect_rids(c, out)


# PROOF THIS CHECK CAN FAIL, derived from the scene rather than from remembered coordinates,
# and RE-RUN ON EVERY SCENE IN THE SWEEP.
#
# Take a prop this run certified as seated, clone its mesh into a bare Node3D on the same
# wall with the same facing, and push it out by 0.09 m — the exact distance the six
# `AjarDoor` leaves shipped at. The measurement must reject it. If `_back_gap` ever starts
# returning 0, or the ray stops hitting the CSG, this goes red before anything else does.
func _self_test(seated: Array) -> void:
	print("  -- positive control: derived from this scene --")
	if seated.is_empty():
		# ⚠️ A scene with no flush wall panel cannot supply this control, and saying so beats
		# inventing one. The `min_props` assertion above is what makes that visible: it is a
		# coverage finding, recorded per scene, not a silent skip.
		print("  NOTE  no seated wall panel in this scene to derive a control from")
		return
	var entry: Array = seated[0]
	var src: MeshInstance3D = entry[1][0]
	var n: Vector3 = entry[2]

	var probe := Node3D.new()
	current_scene.add_child(probe)
	probe.global_transform = (entry[0] as Node3D).global_transform
	var clone := MeshInstance3D.new()
	clone.mesh = src.mesh
	current_scene.add_child(clone)
	clone.global_transform = src.global_transform
	# ⚠️ Pushed out by one MAX_GAP plus the shipped 0.09 m, so the control is a rejection in
	# every scene's band rather than only in the Corridor's tight one.
	clone.global_position += n * (_max_gap + 0.09)

	var gap := _back_gap(probe, [clone], n)
	_ok("control: the same prop floated %.2f m off its wall is REJECTED" % (_max_gap + 0.09),
		gap > _max_gap, "%.3f m behind it" % gap if is_finite(gap) else "nothing behind it")

	# And the other direction: buried in the wallpaper must fail too, or "seated" would only
	# ever mean "not floating".
	#
	# ⚠️ Pushed in by ITS OWN GAP plus a centimetre, not by the same big number the float
	# control uses. A 0.24 m shove puts the clone straight THROUGH a 0.20 m wall and out the
	# far side, where the next surface is a whole room away — measured 0.220 m in the Intro,
	# i.e. the control reported the buried prop as comfortably seated. This lands its back
	# plane 0.01 m inside the wall face, which is the defect being described.
	var seated_gap: float = float(entry[3])
	clone.global_position = src.global_transform.origin - n * (seated_gap + 0.01)
	var buried := _back_gap(probe, [clone], n)
	# ⚠️ The assertion is "NOT seated", not "reads as less than min_gap". A ray fired from
	# INSIDE a CSG slab is not stopped by it (Issue 40's family: back faces are culled and
	# concave shapes have no inside), so a buried prop measures whatever is on the far side of
	# the wall — 0.420 m in the Intro, i.e. a plausible number that happens to describe the
	# next room. What matters is that the value cannot land in the seating band.
	_ok("control: and the same prop pushed INTO the wall is REJECTED",
		not (is_finite(buried) and buried >= _min_gap and buried <= _max_gap),
		"%.3f m behind it" % buried if is_finite(buried) else "nothing behind it")

	clone.queue_free()
	probe.queue_free()
