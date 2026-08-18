extends SceneTree

# EVERY NOTE AND EVERY WALL PANEL IN THE GAME IS ACTUALLY ON A WALL — or resting on
# something. **All nine levels, in one run.**
#
#   Godot --headless --path game --script res://tests/check_note_mounting.gd
#   Godot --headless --path game --script res://tests/check_note_mounting.gd -- House
#
# Two faults, both photographed by the 2026-08-16 playtest, both invisible to every existing
# guard:
#
#   * capture #7 — the TRIAL 7 note hung IN THE MORGUE'S DOORWAY. `wall_point("Morgue",
#     (-1,0))` returns the west wall's CENTRE, and the morgue's only door is at exactly that
#     centre. There was no wall behind the page. It did not seal the room only because
#     note.gd sits on collision_layer 2 — the Records warning sign, on layer 1, sealed a room
#     outright doing the same thing in Session 11.
#   * the Reception briefing note was hand-typed at (2.4, 1.4, -2.6) while the wall's inner
#     face is at x = 2.90 — the first note in the game after the intro, floating half a metre
#     out in the room.
#
# ⚠️ `check_wall_overlap.gd` cannot see either of these. It asserts a MINIMUM clearance
# (things must not z-fight) and has no maximum, so a prop that has drifted AWAY from its wall
# — or has no wall at all — passes every one of its checks. That is cross-level item X1, and
# this is its note-shaped half.
#
# The test: from each prop, fire a ray BACKWARDS along its own facing normal. It must hit
# solid geometry within MAX_BACKING — or, for a page standing on a table, there must be
# something holding it up within SUPPORT_DROP. And the prop must not sit inside a doorway's
# aperture, read from the level script's own DOORS table.
#
# ⚠️ Rays, never `intersect_shape` — Issue 40: a shape query against CSG reports NOTHING when
# it lies wholly inside the slab, i.e. it approves precisely the case being rejected.
#
# ⚠️ SEPARATION (added 2026-08-16, verification replay). Fixing the doorway note created the
# next defect: it was re-hung 1.6 m from the note already on the morgue's south wall, and the
# playtester photographed both pages in one frame — *"These two notes at the morgue are at the
# same place. Let's at least put them into different parts of the room"*, with two NOTE READ
# events 1.7 s apart in the log. So mounting a note correctly is only half the requirement;
# any two notes in the SAME ROOM must also be far apart AND not on the same wall plane.
# Distance alone is the weaker of the two — 2.5 m along one wall is still one glance — so both
# are asserted. This is a general trap: every level in this game hangs notes with wall_point(),
# and wall_point() plus a lateral offset is the obvious way to place the second one.
#
# ------------------------------------------------------------------ coverage
#
# ⚠️ A SWEEP SINCE 2026-08-17 (workstream H1). This was hard-coded to the Lab, then given two
# hand-written wrappers, and `tools/run_tests.sh` has no per-test argument mechanism — so the
# guard written for exactly this class of fault ran on THREE levels out of nine, and the
# House's third note was found floating 1.40 m off a wall BY HAND, in a playtest, with this
# file green. It now iterates `tests/lib/scenes.gd`, which is derived from `GameState`'s own
# `SCENE_*` constants: a new level is enrolled by existing.

const Scenes := preload("res://tests/lib/scenes.gd")

# ---------------------------------------------------------------- the per-scene rows
#
# ⚠️ A ROW IS AN OVERRIDE, NOT AN ENROLMENT — every scene in the list is swept whether or not
# it appears here.
#
#   extra_rooms    rooms the level builds outside its own ROOMS table (the House's cellar)
#   zones          "@backrooms": several room graphs at several world origins
#   no_room_table  this level HAS no ROOMS/DOORS constants, with the reason. ⚠️ Declaring it
#                  is mandatory: without a row, a level whose table simply failed to load
#                  would silently lose the doorway and separation passes, which is a vacuous
#                  pass wearing a green hat.
#   min_props / min_notes / min_pairs / min_resting   the SAMPLE SIZE this scene must produce
#   seeds          RNG seeds for a scene that builds itself from dice
const CONFIG := {
	"SCENE_INTRO": {
		"no_room_table": "intro_room.gd builds one hand-placed ward, not a room graph",
		# ⚠️ min_resting 0 even though the Intro's note is on a table: it lies FLAT, so its
		# thin axis is vertical and `_backing()` already measures DOWNWARD into the table and
		# passes on the wall rule. Only a page standing UPRIGHT on furniture (the Void's
		# eight) reaches the resting branch at all.
		"min_props": 1, "min_notes": 1, "min_pairs": 0, "min_resting": 0,
	},
	"SCENE_LEVEL_1": {"min_props": 8, "min_notes": 4, "min_pairs": 1},
	"SCENE_LEVEL_2": {
		# level_2.gd: CELLAR_CENTER (5, -6), CELLAR_SIZE 7 x 7. ⚠️ THE CELLAR IS NOT IN
		# `ROOMS` — `_build_cellar()` builds it by hand 1.5 m below the ground floor, so
		# without this every cellar note reads as "not inside a room of the level". That is
		# exactly where the fault was (the third digit note, 1.40 m out in mid-air, playtest
		# capture A4).
		"extra_rooms": [{"name": "Cellar", "pos": Vector2(5, -6), "size": Vector2(7, 7)}],
		# ⚠️ THE HOUSE HAS NO SAME-ROOM NOTE PAIRS. One note per room, on purpose, so the
		# separation pass finds zero pairs here and the synthetic control in `_self_test()`
		# is what keeps that rule from going vacuous on this scene.
		"min_props": 8, "min_notes": 5, "min_pairs": 0,
	},
	"SCENE_CORRIDOR": {
		"no_room_table": "corridor.gd builds a 320 m path from PATH_2D, not a room graph",
		"min_props": 8, "min_notes": 2, "min_pairs": 0, "min_resting": 0,
	},
	"SCENE_BACKROOMS": {
		# ⚠️ THE ROOM TABLES ARE DERIVED, NEVER TYPED (X18). Zone 1 is raw CSG with no ROOMS
		# constant at all and zone 2's alcoves are generated in a loop, so both are rebuilt
		# from the same constants the level builds them from. A literal here would be a
		# control that stops describing the scene the moment an arm length changes.
		"zones": "@backrooms",
		"min_props": 5, "min_notes": 4, "min_pairs": 0,
	},
	"SCENE_KONTUR": {
		# ⚠️ WAS 0/0, AND THAT WAS A FINDING (K-T5), NOT A SETTING. KONTUR's readable
		# surfaces are its eight REDACTED SIGNS (`Label3D` over a quad, no `ScaryObject`)
		# and text delivered by `NoteUI.show_note()` from props — a mailbox, a pedestal —
		# so the population this guard collects was EMPTY on the level with the most wall
		# text in the game.
		#
		# ⚠️ RESOLVED 2026-08-18 BY CONTENT, NOT BY WIDENING THE COLLECTOR. The Archive
		# gained a real `note.gd` inventory ledger (kontur.gd:_spawn_recovery_archive),
		# which is a page the level wanted anyway; the signs are still measured by
		# `check_prop_mounting.gd`, which is the guard whose subject they are. Widening
		# this collector to swallow `Label3D`-over-quad plates would have made every
		# redacted sign in the level a "note" for the separation pass, and the eight signs
		# are deliberately one per gate room — several of them within 2.5 m of nothing at
		# all, because they are the only thing on their wall.
		#
		# ⚠️ 2 SINCE 2026-08-18: the Landing's briefing notice (`NoticeBriefing`) is the
		# second real `note.gd` page in the level. It is a wall plate AND a note — the art
		# states the level's design rule from the walking line, the body archives the full
		# memo to the journal — so it is exactly this collector's subject.
		"min_props": 2, "min_notes": 2, "min_pairs": 0,
		"seeds": [7, 11],
	},
	"SCENE_LEVEL_6_BREACH": {"min_props": 1, "min_notes": 1, "min_pairs": 0},
	"SCENE_DUNGEON": {
		"no_room_table": "dungeon_gen.gd generates the room graph at runtime from a seed; "
			+ "there is no ROOMS constant to read",
		# ⚠️ The count varies with the seed — 2 Weeping Frames on one dungeon, 3 on another —
		# so the floor is what any dungeon must have, not what one dungeon had.
		"min_props": 2, "min_notes": 0, "min_pairs": 0,
		"seeds": [1, 404],
	},
	"SCENE_LEVEL_3": {
		"no_room_table": "level_3.gd hand-builds the Void's broken rooms; no ROOMS constant",
		# ⚠️ ALL EIGHT VOID NOTES STAND ON TABLES (`_spawn_note_tables()` puts a 1.2 m box
		# under each and the page sits on its top face). They are RESTING, not floating, and
		# the classification below is what tells the two apart.
		"min_props": 8, "min_notes": 8, "min_pairs": 0, "min_resting": 8,
	},
}

# ⚠️ CREATURES ARE NOT WALL PROPS. `creature_shapechanger.gd` builds the exact
# `ScaryObject -> StaticBody3D -> QuadMesh` chain this file collects, so KONTUR's Perëkozhnik
# — a billboard mimic standing in the middle of a passage, by design — was reported as a
# panel with 1.90 m of air behind it, which is a description of a creature rather than a
# defect. Excluded by SCRIPT on the whole ancestor chain, never by node name: every one of
# these builds its body as an anonymous `@StaticBody3D@NN`.
const CREATURE_SCRIPTS := [
	"creature_shapechanger.gd", "creature_stalker.gd", "creature_smiler.gd",
	"creature_static.gd", "creature_object12.gd", "creature_hollow.gd",
	"kneeling_man.gd", "dn_child.gd", "apparition.gd", "watcher.gd",
	"congregation.gd", "unseen_wader.gd",
]

# Two notes in one room must be at least this far apart...
const MIN_NOTE_SEPARATION := 2.5
# ...and must not share a wall: near-parallel facings whose positions differ by less than this
# along that facing are the same plane, however far apart they are sideways.
const SAME_PLANE_DOT := 0.95
const SAME_PLANE_DEPTH := 0.5
# A wall prop is mounted if there is solid geometry this close behind it. Wall face + inset
# (0.16) + the prop's own half-depth is ~0.1 m; 0.35 m is generous and still catches "in a
# doorway" (nothing behind for metres) and "floating in the room" (0.5 m).
const MAX_BACKING := 0.35
# ⚠️ ...AND A PAGE STANDING ON A TABLE IS NOT A WALL PROP (added 2026-08-17). Eight of the
# Void's notes, the Intro's, the Corridor's framing note and the Backrooms' entry clue all
# stand on furniture in the middle of a room, and "nothing behind it" is a true and useless
# statement about every one of them. They are accepted only if something holds them UP within
# SUPPORT_DROP of their own origin — which the House's 1.40 m mid-air cellar note, the fault
# that motivated the whole file, still fails by a metre. Their count is asserted per scene
# (`min_resting`), so this cannot quietly become the branch every failing prop escapes down.
const SUPPORT_DROP := 0.40
const DOORWAY_PLANE_TOL := 0.5    # how close to a doorway's plane counts as "on" it
const DOORWAY_EDGE_PAD := 0.2     # and how far past its edge still counts as in the aperture

var _scene := ""
var _level_script := ""
var _extra_rooms: Array = []
var _origin := Vector3.ZERO
var _zones: Array = []
var _min_props := 8
var _min_notes := 4
var _min_pairs := 1
var _min_resting := 0

var _rows: Array = []
var _row := 0
var _t := 0.0
var _fails := 0
var _checks := 0
var _doors: Array = []
var _rooms: Array = []
var _summary: Array = []
var _only := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1 and not String(args[0]).begins_with("--"):
		_only = args[0]
	var problems: Array = Scenes.problems()
	for p in problems:
		print("  FAIL enrolment: %s" % p)
		_fails += 1
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
		print("NOTE-MOUNTING FAIL: no scene matched '%s'" % _only)
		quit(1)
		return
	_load_row()


func _load_row() -> void:
	var r: Dictionary = _rows[_row]
	var cfg: Dictionary = r["cfg"]
	_scene = String(r["path"])
	_extra_rooms = cfg.get("extra_rooms", [])
	_zones = _backrooms_zones() if cfg.get("zones", "") == "@backrooms" else []
	_min_props = int(cfg.get("min_props", 1))
	_min_notes = int(cfg.get("min_notes", 1))
	_min_pairs = int(cfg.get("min_pairs", 0))
	_min_resting = int(cfg.get("min_resting", 0))
	_t = 0.0
	Scenes.pin_rng(int(r["seed"]))
	change_scene_to_file(_scene)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fails += 1
	print("  %s  %s%s" % ["PASS" if cond else "FAIL", label, ("   " + detail) if detail != "" else ""])


func _walk(n: Node, out: Array) -> void:
	out.append(n)
	for c in n.get_children():
		_walk(c, out)


# Build `_rooms` / `_doors` in WORLD space. Default: the one table in the LOADED SCENE's own
# script, offset by `_origin` (ZERO for every level built at the origin).
#
# ⚠️ THE LEVEL SCRIPT IS READ OFF THE SCENE, not typed into a table here. It used to be a
# second hand-maintained string per wrapper, i.e. a second thing to get wrong when a level
# was added; `current_scene.get_script()` cannot disagree with the scene under test.
#
# ⚠️ THE ROOM TABLES ARE NOT WORLD-SPACE, AND THIS FILE USED TO ASSUME THEY WERE
# (cross-level X32, fixed 2026-08-17). `_room_of()` and `_in_doorway()` compare a WORLD
# position against the level script's LOCAL `ROOMS`/`DOORS` table. Every level built at the
# origin got away with it; the Backrooms builds three zones in ONE SCENE at 0, +200 x and
# -200 x, so all four of its notes reported "not inside a room of the level".
#
# ⚠️ `check_wall_overlap.gd` is immune to this and says nothing about it: everything in that
# file is `global_position` / `global_transform`. The two sibling guards differed, and only
# one of them documented it. Now both do.
func _load_tables() -> void:
	_rooms = []
	_doors = []
	_level_script = ""
	var zones := _zones
	if zones.is_empty():
		var script: GDScript = current_scene.get_script() as GDScript
		var consts: Dictionary = {}
		if script != null:
			_level_script = script.resource_path
			# ⚠️ Object.get() reads PROPERTIES, not consts (Issue 54). The constant map is the
			# only way to reach DOORS, and an empty one means this test is measuring nothing.
			consts = script.get_script_constant_map()
		zones = [{
			"origin": _origin,
			"rooms": (consts.get("ROOMS", []) as Array) + _extra_rooms,
			"doors": consts.get("DOORS", []),
		}]
	for z in zones:
		var o: Vector3 = z.get("origin", Vector3.ZERO)
		var flat := Vector2(o.x, o.z)
		for r in (z.get("rooms", []) as Array):
			_rooms.append({
				"name": r["name"],
				"pos": (r["pos"] as Vector2) + flat,
				"size": r["size"],
			})
		for d in (z.get("doors", []) as Array):
			var e: Dictionary = (d as Dictionary).duplicate()
			e["pos"] = (d["pos"] as Vector2) + flat
			_doors.append(e)


# A prop's front — the direction its face points, in world space.
#
# ⚠️ DERIVED FROM THE PROP'S OWN MESH since 2026-08-17, not assumed to be +Z. Notes are
# BoxMesh bodies whose thin axis carries the paper; a note HUNG ON A WALL is thin in Z, and
# a note LYING ON A TABLE is thin in Y. This file assumed the first, so every table note in
# the game reported "NOTHING behind it" — correctly, and uselessly: there is nothing behind
# it, there is something UNDER it. The Backrooms' entry-arm clue note is one, and it is the
# first thing the player reads in that level.
#
# Every prop that passed this check before is thin in Z, so the returned axis is the same
# `basis.z` it always was; the fallback keeps that literally true for anything with no mesh.
func _front(n: Node3D) -> Vector3:
	var mi := _mesh_of(n)
	if mi == null:
		return n.global_transform.basis.z.normalized()
	var ext := _mesh_extents(mi.mesh)
	if ext == Vector3.ZERO:
		return n.global_transform.basis.z.normalized()
	var thin := 0
	for ax in 3:
		if ext[ax] < ext[thin]:
			thin = ax
	# ⚠️ Named columns, not `basis[thin]`. Godot 4's Basis exposes x/y/z as COLUMNS while its
	# C++ operator[] returns ROWS, and the two are only the same for a symmetric basis — a
	# yawed note would have come back with the wrong axis and the difference is invisible in
	# a scene built at the origin.
	var b := mi.global_transform.basis
	if thin == 0:
		return b.x.normalized()
	if thin == 1:
		return b.y.normalized()
	return b.z.normalized()


func _mesh_of(n: Node3D) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		if c is MeshInstance3D and _mesh_extents((c as MeshInstance3D).mesh) != Vector3.ZERO:
			return c as MeshInstance3D
	return null


# Local-space extents of the primitive meshes this project builds props from. Anything else
# returns ZERO and the caller falls back to +Z.
func _mesh_extents(m: Mesh) -> Vector3:
	if m is BoxMesh:
		return (m as BoxMesh).size
	if m is QuadMesh:
		var q: Vector2 = (m as QuadMesh).size
		return Vector3(q.x, q.y, 0.0)
	if m is PlaneMesh:
		var p: Vector2 = (m as PlaneMesh).size
		return Vector3(p.x, p.y, 0.0)
	return Vector3.ZERO


# Metres of air behind the prop before something solid. INF when nothing is there at all.
#
# ⚠️ REWRITTEN 2026-08-16, for two faults that between them made this the least trustworthy
# function in the file. Both were found by pointing it at the House.
#
# 1. THE START POINT WAS A COIN FLIP. It fired from `from - back * 0.05` — 5 cm in front of
#    the prop — and a wall panel's own collider is typically 0.1 m deep, so that landed
#    EXACTLY on its own near face. With `hit_from_inside` false, a ray starting on a surface
#    is numerically ambiguous: the same panel measured 0.03 m in one run and INF in the next,
#    from arithmetic that differed only in float rounding. Now it starts AT the prop and
#    excludes the prop's own body, which is unambiguous in both directions.
# 2. IT ASSUMED +Z FACES THE ROOM. `LivingMirror` faces its local −Z (the House hangs two of
#    them at `rotation.y = 0` and `PI` accordingly), so the ray was fired INTO the wall and
#    out the other side, and two perfectly mounted mirrors read as "NOTHING behind it".
#    It now tries both directions and takes the nearer hit.
#
# ⚠️ Bidirectional is weaker in principle and adequate in practice: every fault this file was
# written for — a note in a doorway, a page 0.5 m off a wall, the House's third note 1.40 m
# out in mid-air — has nothing within MAX_BACKING on EITHER side, so all three still fail.
func _backing(n: Node3D) -> float:
	var front := _front(n)
	return minf(_ray_len(n, -front), _ray_len(n, front))


# Metres of air UNDER the prop before something holds it up. INF when nothing does.
func _support(n: Node3D) -> float:
	return _ray_len(n, Vector3.DOWN)


func _ray_len(n: Node3D, dir: Vector3) -> float:
	var from: Vector3 = n.global_position
	var space := current_scene.get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 2.0)
	var excluded: Array[RID] = []
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	if player:
		excluded.append(player.get_rid())
	if n is CollisionObject3D:
		excluded.append((n as CollisionObject3D).get_rid())
	q.exclude = excluded
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return INF
	return from.distance_to(hit["position"])


# Is this position inside a doorway's opening, per the level's own DOORS table?
func _in_doorway(pos: Vector3) -> String:
	for d in _doors:
		var dpos: Vector2 = d["pos"]
		var w: float = d.get("width", 1.4)
		var dir: String = d.get("dir", "z")
		if dir == "x":
			if absf(pos.x - dpos.x) < DOORWAY_PLANE_TOL \
					and absf(pos.z - dpos.y) < w / 2.0 + DOORWAY_EDGE_PAD:
				return "x-doorway at (%.1f, %.1f)" % [dpos.x, dpos.y]
		else:
			if absf(pos.z - dpos.y) < DOORWAY_PLANE_TOL \
					and absf(pos.x - dpos.x) < w / 2.0 + DOORWAY_EDGE_PAD:
				return "z-doorway at (%.1f, %.1f)" % [dpos.x, dpos.y]
	return ""


# Which room of the level's own ROOMS table this position falls in, "" if none.
func _room_of(pos: Vector3) -> String:
	for r in _rooms:
		var c: Vector2 = r["pos"]
		var half: Vector2 = (r["size"] as Vector2) * 0.5
		# Generous by half a wall thickness, because a wall prop sits just inside the face and
		# a room's nominal boundary is 0.1 m outside it.
		if absf(pos.x - c.x) <= half.x + 0.15 and absf(pos.z - c.y) <= half.y + 0.15:
			return String(r["name"])
	return ""


# Do these two wall props hang on the same wall? Near-parallel facings AND no meaningful
# depth between them along that facing. Two notes 3 m apart on one wall are still one wall.
func _same_plane(a: Node3D, b: Node3D) -> bool:
	var na := _front(a)
	var nb := _front(b)
	if absf(na.dot(nb)) < SAME_PLANE_DOT:
		return false
	return absf((a.global_position - b.global_position).dot(na)) < SAME_PLANE_DEPTH


# ⚠️ Any ancestor carrying a creature script disqualifies the whole subtree. See
# CREATURE_SCRIPTS.
func _is_creature(n: Node) -> bool:
	var at: Node = n
	while at != null and at != current_scene:
		var s: Script = at.get_script()
		if s != null and CREATURE_SCRIPTS.has(String(s.resource_path).get_file()):
			return true
		at = at.get_parent()
	return false


func _process(delta: float) -> bool:
	_t += delta
	# ⚠️ TIME, not a frame count — headless runs uncapped (X42). CSG colliders are not
	# registered during _ready() (Issue 52) either, so a query fired too early comes back
	# empty and the whole level reports "nothing is mounted" for the wrong reason.
	if _t < float(_rows[_row]["settle"]):
		return false

	var before := _fails
	_measure_scene()
	_summary.append("%-10s seed %-4d %s (%d failing check%s)"
		% [_rows[_row]["label"], _rows[_row]["seed"],
			"PASS" if _fails == before else "FAIL", _fails - before,
			"" if _fails - before == 1 else "s"])
	_row += 1
	if _row < _rows.size():
		_load_row()
		return false

	print("")
	print("--- NOTE-MOUNTING SWEEP: %d scene-run(s) ---" % _rows.size())
	for line in _summary:
		print("  " + line)
	print("%d checks, %d failed" % [_checks, _fails])
	print("NOTE-MOUNTING PASS" if _fails == 0 else "NOTE-MOUNTING FAIL")
	quit(1 if _fails > 0 else 0)
	return true


func _measure_scene() -> void:
	var cfg: Dictionary = _rows[_row]["cfg"]
	_load_tables()
	print("")
	print("--- note & panel mounting: %s (%s, seed %d) ---"
		% [_rows[_row]["label"], _scene, int(_rows[_row]["seed"])])
	var no_tables: String = String(cfg.get("no_room_table", ""))
	if no_tables != "":
		# ⚠️ Declared, printed, and its truth asserted: if this level ever GAINS a room table
		# the row is stale and the coverage it waives has quietly come back.
		_ok("%s legitimately has no room table" % _rows[_row]["label"],
			_rooms.is_empty() and _doors.is_empty(), no_tables)
		print("  NOTE  doorway and same-room separation are NOT checked here — %s" % no_tables)
	else:
		_ok("read the level's DOORS table", _doors.size() > 0, "%d doorways" % _doors.size())
		_ok("read the level's ROOMS table", _rooms.size() > 0, "%d rooms" % _rooms.size())

	var nodes: Array = []
	_walk(current_scene, nodes)
	var note_script: GDScript = load("res://scripts/note.gd")

	var props: Array = []      # [node, label]
	var notes: Array = []      # [node, label] — notes only, for the separation pass
	for n in nodes:
		if not (n is Node3D):
			continue
		if _is_creature(n):
			continue
		if n.get_script() == note_script:
			var title: String = String(n.note_text).split("\n")[0]
			props.append([n, "note: " + title.substr(0, 38)])
			notes.append([n, title.substr(0, 28)])
		elif n is StaticBody3D and n.get_parent() is ScaryObject:
			var has_quad := false
			for c in n.get_children():
				if c is MeshInstance3D and c.mesh is QuadMesh:
					has_quad = true
			if has_quad:
				props.append([n, "panel at %v" % [n.global_position.round()]])

	# ⚠️ Assert the sample size. "0 props checked ... PASS" has happened in this repo.
	_ok("found wall props to check", props.size() >= _min_props, "%d props" % props.size())
	_ok("found notes to check", notes.size() >= _min_notes, "%d notes" % notes.size())

	var resting := 0
	var rest_anchor: Node3D = null
	for entry in props:
		var n: Node3D = entry[0]
		var label: String = entry[1]
		var backing := _backing(n)
		if backing > MAX_BACKING:
			# Not on a wall — is it standing on something?
			var under := _support(n)
			if under <= SUPPORT_DROP:
				resting += 1
				if rest_anchor == null:
					rest_anchor = n
				print("  REST  %s stands on something %.2f m below it" % [label, under])
				continue
		_ok("%s — has a wall behind it" % label, backing <= MAX_BACKING,
			"%.2f m of air" % backing if is_finite(backing) else "NOTHING behind it")
		if no_tables == "":
			var door := _in_doorway(n.global_position)
			_ok("%s — is not in a doorway" % label, door == "", door)
	# ⚠️ And the size of the escape hatch. A scene where EVERY prop took the resting branch
	# would otherwise report zero failures having asserted nothing about mounting at all.
	_ok("the expected number of props are resting on furniture rather than hung",
		resting >= _min_resting, "%d resting, minimum %d" % [resting, _min_resting])

	if no_tables == "":
		_separation(notes)
	_self_test(props, rest_anchor)


# No two notes in one room may be within arm's reach of each other, or share a wall.
func _separation(notes: Array) -> void:
	print("  -- separation: two notes in one room --")
	# Group by room, using the level's own ROOMS table rather than by node parent (every prop
	# in this level is a direct child of the level root).
	var by_room: Dictionary = {}
	for entry in notes:
		var n: Node3D = entry[0]
		var room := _room_of(n.global_position)
		if room == "":
			_ok("note '%s' is inside a room of the level" % entry[1], false,
				"at %v" % [n.global_position.round()])
			continue
		if not by_room.has(room):
			by_room[room] = []
		by_room[room].append(entry)

	var pairs := 0
	for room in by_room.keys():
		var group: Array = by_room[room]
		for i in range(group.size()):
			for j in range(i + 1, group.size()):
				pairs += 1
				var a: Node3D = group[i][0]
				var b: Node3D = group[j][0]
				var d := a.global_position.distance_to(b.global_position)
				var same := _same_plane(a, b)
				_ok("%s: '%s' and '%s' are %.2f m apart" % [room, group[i][1], group[j][1], d],
					d >= MIN_NOTE_SEPARATION, "minimum is %.2f m" % MIN_NOTE_SEPARATION)
				_ok("%s: '%s' and '%s' are on different walls"
					% [room, group[i][1], group[j][1]], not same,
					"same wall plane" if same else "")
	# ⚠️ Assert the sample size. A room-lookup that silently returned "" for everything would
	# leave zero pairs and report a tidy pass — this repo has shipped that exact green before.
	# Levels with one note per room legitimately have none, and set min_pairs = 0; the
	# synthetic control in _self_test() is what keeps the rule honest for them.
	_ok("checked the expected number of same-room note pairs", pairs >= _min_pairs,
		"%d pairs, minimum %d" % [pairs, _min_pairs])


# PROOF THIS CHECK CAN FAIL, kept permanently rather than performed once by hand, and RUN ON
# EVERY SCENE IN THE SWEEP.
#
# ⚠️ SCENE-INDEPENDENT since 2026-08-16. It used to re-create the Lab's two shipped faults at
# their real former coordinates — (6.16, 1.4, 12.50) and (2.4, 1.4, -2.6) — which is a
# perfectly good control on the Lab and a VACUOUS PASS anywhere else: point this file at
# another level and those two points are in open space, so "REJECTED" is true for the wrong
# reason and proves nothing about the scene actually under test (cross-level X18).
#
# The controls are derived from the scene's own data:
#   * take a prop this run just certified as mounted, and float a probe 1 m off the same wall
#     along the same facing — the checker must reject it, on BOTH the wall rule and the
#     support rule, or the resting branch is an escape hatch rather than a classification;
#   * take the level's own first doorway and require _in_doorway() to name it.
# Both go red if _backing() ever starts returning 0, or if the DOORS table stops being read.
func _self_test(props: Array, rest_anchor: Node3D = null) -> void:
	print("  -- positive control: derived from this scene --")
	var anchor: Node3D = null
	for entry in props:
		var n: Node3D = entry[0]
		if _backing(n) <= MAX_BACKING:
			anchor = n
			break
	# ⚠️ A scene with no wall-mounted prop at all cannot supply this control, and saying so is
	# better than inventing one: KONTUR's collected population is empty (see CONFIG).
	if anchor == null:
		print("  NOTE  no wall-mounted prop in this scene to derive a float control from")
	else:
		# ⚠️ The probe is measured along the ANCHOR'S OWN front, not along a bare Node3D's +Z.
		# Once `_front()` started deriving the axis from the prop's mesh, an anchor that is a
		# table note (thin in Y) would have been floated upward and then measured sideways —
		# the control would still have said REJECTED, for entirely the wrong reason.
		var front := _front(anchor)
		var floated := anchor.global_position + front * 1.0
		var probe := _probe_at(floated, front)
		_ok("control: the SAME prop floated 1 m off its wall is REJECTED",
			probe.x > MAX_BACKING,
			"%.2f m of air" % probe.x if is_finite(probe.x) else "nothing behind it")
		_ok("control: ...and it is not rescued by the resting rule either",
			probe.y > SUPPORT_DROP,
			"%.2f m below it" % probe.y if is_finite(probe.y) else "nothing below it")

	# ⚠️ AND THE RESTING BRANCH NEEDS ITS OWN CONTROL, or a scene where every prop takes it —
	# the Void, all eight notes — has proved nothing at all. Lift a copy of a prop this run
	# just classified as RESTING 1.2 m into the air above its own table: it must fail the
	# support rule AND the wall rule, i.e. be reported. Without this, a `_support()` that
	# always returned 0 would turn the whole Void green and read as a tidy pass.
	if rest_anchor != null:
		var lifted := _probe_at(rest_anchor.global_position + Vector3(0, 1.2, 0),
			_front(rest_anchor))
		_ok("control: a RESTING prop lifted 1.2 m off its table is REJECTED",
			lifted.x > MAX_BACKING and lifted.y > SUPPORT_DROP,
			"%.2f m behind, %.2f m below" % [lifted.x, lifted.y])

	if not _doors.is_empty():
		var door_entry: Dictionary = _doors[0]
		var dp: Vector2 = door_entry["pos"]
		var at := Vector3(dp.x, 1.4, dp.y)
		_ok("control: the level's own first doorway is named as a doorway",
			_in_doorway(at) != "", "%s at %v" % [_in_doorway(at), at])

	# And the pair the separation rule was written for: both morgue pages on the south wall,
	# 1.6 m apart, exactly as they shipped between the first and second fixes. Both halves of
	# the rule must reject it — that is what stops a future "just nudge it along the wall".
	var a := Node3D.new()
	var b := Node3D.new()
	current_scene.add_child(a)
	current_scene.add_child(b)
	a.global_position = Vector3(9.5, 1.4, 9.63)
	b.global_position = Vector3(11.1, 1.4, 9.66)
	var d := a.global_position.distance_to(b.global_position)
	_ok("control: the old morgue pair (1.6 m along one wall) is too CLOSE",
		d < MIN_NOTE_SEPARATION, "%.2f m apart" % d)
	_ok("control: and it is called out as the SAME WALL", _same_plane(a, b))
	a.queue_free()
	b.queue_free()


# (backing, support) at a bare point, in metres.
func _probe_at(pos: Vector3, front: Vector3) -> Vector2:
	var n := Node3D.new()
	current_scene.add_child(n)
	n.global_position = pos
	var back: float = minf(_ray_len(n, -front), _ray_len(n, front))
	var under := _ray_len(n, Vector3.DOWN)
	n.queue_free()
	return Vector2(back, under)


# ---------------------------------------------------------------- the Backrooms' three zones
#
# ⚠️ DERIVED, NEVER TYPED (X18). Zone 1 is raw CSG with no ROOMS constant at all and zone 2's
# alcoves are generated in a loop, so both are rebuilt here from the same constants the level
# builds them from. A literal would be a control that stops describing the scene the moment an
# arm length or an alcove depth changes.
func _consts(path: String) -> Dictionary:
	return (load(path) as GDScript).get_script_constant_map()


func _backrooms_zones() -> Array:
	var b := _consts("res://scripts/backrooms.gd")
	var z2 := _consts("res://scripts/backrooms_zone2.gd")
	var z3 := _consts("res://scripts/backrooms_zone3.gd")

	# ---- zone 1, THE LOBBY: hub + entry arm + three choice arms + the utility room.
	var half: float = b["HALF"]
	var w: float = b["W"]
	var arms: Dictionary = b["CHOICE_ARMS"]
	var util_d: float = b["UTIL_DEPTH"]
	var util_w: float = b["UTIL_WIDTH"]
	var entry_lo := -7.0            # backrooms.gd:_build_entry_arm()'s `lo`
	# ⚠️ The entry arm spans the hub's SOUTH EDGE (-half) out to `lo` — it does not start at
	# the hub centre. This model mirrored the builder's old `(entry_lo - half) / 2` centring,
	# which put the whole arm 1.5 m south of the truth; both were corrected 2026-08-17
	# (backlog 04 R2). If the builder moves again, this has to move with it.
	var rooms1: Array = [
		{ "name": "Hub", "pos": Vector2(0, 0), "size": Vector2(w, w) },
		{ "name": "Entry", "pos": Vector2(0, (-half + entry_lo) / 2.0),
			"size": Vector2(w, -half - entry_lo) },
	]
	for id in arms:
		var axis: Vector3 = arms[id]["axis"]
		var length: float = arms[id]["len"]
		var mid: float = half + length / 2.0
		var along := absf(axis.x) > 0.5
		rooms1.append({
			"name": "Arm" + String(id),
			"pos": Vector2(axis.x * mid, axis.z * mid),
			"size": Vector2(length, w) if along else Vector2(w, length),
		})
	var util_z: float = half + float(arms["N"]["len"]) + util_d / 2.0
	rooms1.append({ "name": "Utility", "pos": Vector2(0, util_z),
		"size": Vector2(util_w, util_d) })

	# ---- zone 2, THE SPRAWL: the hall plus its eight alcoves.
	var size2: float = z2["SIZE"]
	var half2: float = z2["HALF"]
	var alc_d: float = z2["ALCOVE_D"]
	var alc_w: float = z2["ALCOVE_W"]
	var sides: Array = z2["SIDES"]
	var side_axis: Dictionary = z2["SIDE_AXIS"]
	var rooms2: Array = [
		{ "name": "SprawlHall", "pos": Vector2(0, 0), "size": Vector2(size2, size2) },
	]
	for s in sides:
		var axis: Vector3 = side_axis[s]
		var is_x := absf(axis.x) > 0.5
		for k in [-1, 1]:
			var centre: Vector3 = axis * (half2 + alc_d / 2.0) \
				+ Vector3(axis.z, 0, axis.x) * (k * 11.0)
			rooms2.append({
				"name": "Alc%s%d" % [s, k],
				"pos": Vector2(centre.x, centre.z),
				"size": Vector2(alc_d, alc_w) if is_x else Vector2(alc_w, alc_d),
			})

	return [
		{ "origin": Vector3.ZERO, "rooms": rooms1, "doors": [] },
		{ "origin": b["ZONE2_ORIGIN"], "rooms": rooms2, "doors": [] },
		{ "origin": b["ZONE3_ORIGIN"], "rooms": z3["ROOMS"], "doors": z3["DOORS"] },
	]
