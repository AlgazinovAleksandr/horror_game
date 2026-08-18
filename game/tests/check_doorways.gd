extends SceneTree

# NOTHING SEALS A DOORWAY — **in every level in the game**.
#
#   Godot --headless --path game --script res://tests/check_doorways.gd
#   Godot --headless --path game --script res://tests/check_doorways.gd -- House
#
# Cast a ray straight THROUGH each doorway along its traversal axis, at two heights. The
# opening must be clear; a collider in it is the recurring "can't enter the room" bug — the
# Records warning sign sealed the Lab's third breaker room in Session 11, and `wall_point()`
# returns the wall CENTRE, which is exactly where a doorway is, so the mistake is one line
# away in every level script.
#
# ⚠️ THIS FILE ASSERTED NOTHING UNTIL 2026-08-17 (workstream H2). It printed "BLOCKED <name>"
# and then called `quit(0)` unconditionally: a doorway sealed by a prop produced a tidy PASS
# with the evidence printed inside it, in a suite whose only signals are the exit code and a
# grep. It also carried a HAND-COPIED COPY of `level_2.gd`'s DOORS table, so it described the
# House of whenever it was last edited, and it ran on the House alone — one level of nine, the
# same coverage failure `check_wall_overlap.gd` and `check_note_mounting.gd` each had.
#
# Now: the tables are read from each level's own script, the sweep is `tests/lib/scenes.gd`,
# a blocked doorway FAILS, the sample size is asserted, and a control seals a real doorway of
# the scene under test every run and requires it to be caught.
#
# ⚠️ A CLOSED DOOR IS NOT A BLOCKED DOORWAY. `door.gd`, `choice_door.gd`, `cellar_gate.gd`,
# `fungal_barrier.gd`, `slam_door.gd` and the Lab's morgue shutter all stand in a doorway on
# purpose — that is what a door is. Those are reported as GATED and counted; everything else
# is a finding.

const Scenes := preload("res://tests/lib/scenes.gd")

const HEIGHTS := [0.6, 1.6]        # a waist-high prop seals a doorway as surely as a sign
const THROUGH := 1.6               # how far either side of the plane the ray runs

# Scripts that are ALLOWED to stand in a doorway, because they are the door.
const GATE_SCRIPTS := [
	"door.gd", "choice_door.gd", "cellar_gate.gd", "fungal_barrier.gd", "slam_door.gd",
	"purge_chamber.gd", "ajar_door.gd", "glitch_wall.gd", "dungeon_cot.gd",
]
# ...and node names, for gates built as bare CSG by the level itself.
const GATE_NAMES := ["MorgueShutter", "RosterSeal", "AirlockSeal", "Shutter", "Seal"]

# ---------------------------------------------------------------- the per-scene rows
#
#   scripts     [[script path, origin], ...] to read DOORS out of, when the level's own
#               script is not the whole story (the Backrooms builds three zones at three
#               world origins, only one of which has a DOORS table)
#   min_doors   how many doorways this scene must yield — "0 doorways checked ... PASS"
#   no_doors    this level legitimately has no DOORS table, with the reason. Declaring it is
#               mandatory: a table that silently failed to load looks exactly the same.
#   filed       {label: why a blocked doorway here is not being fixed in this pass}
#   seeds       RNG seeds for a scene that builds itself from dice
const CONFIG := {
	"SCENE_INTRO": {"no_doors": "intro_room.gd builds one hand-placed ward, no room graph"},
	"SCENE_LEVEL_1": {"min_doors": 10},
	"SCENE_LEVEL_2": {"min_doors": 8},
	"SCENE_CORRIDOR": {"no_doors": "corridor.gd builds a 320 m path from PATH_2D"},
	"SCENE_BACKROOMS": {
		# Zone 1 is raw CSG and zone 2 is a pillar hall; only the Flood is a RoomBuilder graph.
		"scripts": [["res://scripts/backrooms_zone3.gd", "@zone3"]],
		"min_doors": 6,
	},
	"SCENE_KONTUR": {"min_doors": 10, "seeds": [7, 3]},
	"SCENE_LEVEL_6_BREACH": {"min_doors": 12},
	"SCENE_DUNGEON": {
		"no_doors": "dungeon_gen.gd generates the graph at runtime; no DOORS constant",
	},
	"SCENE_LEVEL_3": {"no_doors": "level_3.gd hand-builds the Void; no DOORS constant"},
}

var _rows: Array = []
var _row := 0
var _t := 0.0
var _checks := 0
var _fails: Array[String] = []
var _summary: Array = []
var _only := ""
var _player: CharacterBody3D = null
var _doors: Array = []
var _control_seal: CSGBox3D = null
var _control_door: Dictionary = {}
var _stage := "measure"


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
		print("DOORWAYS FAIL: no scene matched %s" % _only)
		quit(1)
		return
	_load_row()


func _load_row() -> void:
	var r: Dictionary = _rows[_row]
	_t = 0.0
	_stage = "measure"
	_control_seal = null
	_control_door = {}
	Scenes.pin_rng(int(r["seed"]))
	change_scene_to_file(String(r["path"]))


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _process(delta: float) -> bool:
	_t += delta
	var cfg: Dictionary = _rows[_row]
	# ⚠️ TIME, never a frame count (X42); CSG colliders are not registered during `_ready()`
	# (Issue 52), and a ray fired too early passes through everything.
	if _stage == "measure":
		if _t < float(cfg["settle"]):
			return false
		_measure(cfg)
		if _control_seal == null:
			return _advance()
		_stage = "control"
		_t = 0.0
		return false
	if _t < 0.4:                     # the new CSG box needs a frame to get a collider
		return false
	_control_check(cfg)
	return _advance()


func _advance() -> bool:
	_row += 1
	if _row < _rows.size():
		_load_row()
		return false
	print("")
	print("--- DOORWAY SWEEP: %d scene-run(s) ---" % _rows.size())
	for line in _summary:
		print("  " + line)
	print("%d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("DOORWAYS PASS")
		quit(0)
	else:
		for f in _fails:
			print("  FAIL: " + f)
		print("DOORWAYS FAIL")
		quit(1)
	return true


func _measure(cfg: Dictionary) -> void:
	print("")
	print("--- doorway clearance: %s (%s, seed %d) ---"
		% [cfg["label"], cfg["path"], int(cfg["seed"])])
	_player = current_scene.get_node_or_null("Player") as CharacterBody3D
	_ok("%s: player found" % cfg["label"], _player != null)
	if _player == null:
		return
	_doors = _load_doors(cfg)

	var no_doors: String = String(cfg.get("no_doors", ""))
	if no_doors != "":
		_ok("%s legitimately has no DOORS table" % cfg["label"], _doors.is_empty(), no_doors)
		_summary.append("%-10s seed %-4d not applicable — %s"
			% [cfg["label"], int(cfg["seed"]), no_doors])
		return

	_ok("%s: read a DOORS table" % cfg["label"],
		_doors.size() >= int(cfg.get("min_doors", 1)),
		"%d doorways, minimum %d" % [_doors.size(), int(cfg.get("min_doors", 1))])

	var blocked := 0
	var gated := 0
	var clear_door: Dictionary = {}
	for d in _doors:
		var hit := _through(d)
		if hit.is_empty():
			if clear_door.is_empty():
				clear_door = d
			continue
		var who: Node = hit["node"]
		if _is_gate(who):
			gated += 1
			print("  GATED %s  <- %s (a door, and doors close)" % [d["label"], who.name])
			continue
		blocked += 1
		var filed: Dictionary = cfg.get("filed", {})
		if filed.has(d["label"]):
			print("  FILED %s  <- %s  — %s" % [d["label"], who.name, filed[d["label"]]])
			continue
		_ok("%s: %s is walkable" % [cfg["label"], d["label"]], false,
			"BLOCKED by %s at %v, y=%.1f" % [who.name, hit["at"].snappedf(0.01), hit["y"]])
	_summary.append("%-10s seed %-4d %d doorways, %d gated, %d blocked"
		% [cfg["label"], int(cfg["seed"]), _doors.size(), gated, blocked])

	# ⚠️ THE CONTROL, derived from the scene under test: take a doorway this run just measured
	# CLEAR and drop a slab across it. The next frame must report it blocked. Without this,
	# a `_through()` that stopped hitting anything — a wrong collision mask, a ray fired too
	# early, an empty table — would report every doorway in the game as walkable, in silence.
	if not clear_door.is_empty():
		_control_door = clear_door
		var seal := CSGBox3D.new()
		seal.name = "DoorwaySealControl"
		seal.size = Vector3(1.2, 2.2, 1.2)
		seal.use_collision = true
		current_scene.add_child(seal)
		seal.global_position = Vector3(clear_door["x"], 1.1, clear_door["z"])
		_control_seal = seal
	else:
		_ok("%s CONTROL: a clear doorway exists to seal" % cfg["label"], false,
			"every doorway in the scene was already blocked or gated")


func _control_check(cfg: Dictionary) -> void:
	var hit := _through(_control_door)
	_ok("%s CONTROL: a slab dropped in a clear doorway IS caught" % cfg["label"],
		not hit.is_empty() and String((hit["node"] as Node).name) == "DoorwaySealControl",
		"%s -> %s" % [_control_door["label"],
			String((hit["node"] as Node).name) if not hit.is_empty() else "still clear"])
	if is_instance_valid(_control_seal):
		_control_seal.get_parent().remove_child(_control_seal)
		_control_seal.queue_free()


# The first collider in this doorway's aperture, at any of HEIGHTS, or {}.
func _through(d: Dictionary) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var dir: Vector3 = Vector3(0, 0, 1) if String(d["dir"]) == "z" else Vector3(1, 0, 0)
	for y in HEIGHTS:
		var c := Vector3(d["x"], y, d["z"])
		var q := PhysicsRayQueryParameters3D.create(c - dir * THROUGH, c + dir * THROUGH)
		q.exclude = [_player.get_rid()]
		q.collide_with_areas = false
		var r := space.intersect_ray(q)
		if r.is_empty():
			continue
		var n: Node = r["collider"] as Node
		if n == null:
			continue
		return {"node": n, "at": r["position"] as Vector3, "y": y}
	return {}


# ⚠️ By SCRIPT on the whole ancestor chain, never by node name: `door.gd` builds its leaf as
# an unnamed child body, and a name filter would let every closed door in the game read as a
# blocked doorway.
func _is_gate(n: Node) -> bool:
	var at: Node = n
	while at != null and at != current_scene:
		var s: Script = at.get_script()
		if s != null and GATE_SCRIPTS.has(String(s.resource_path).get_file()):
			return true
		for g in GATE_NAMES:
			if String(at.name).begins_with(g):
				return true
		at = at.get_parent()
	return false


# Doorways in WORLD space, read from the level's own DOORS constant(s).
func _load_doors(cfg: Dictionary) -> Array:
	var out: Array = []
	var tables: Array = [[_scene_script(), Vector3.ZERO]]
	for extra in cfg.get("scripts", []):
		tables.append([String(extra[0]), _origin_tag(String(extra[1]))])
	for t in tables:
		var path: String = String(t[0])
		if path == "":
			continue
		var gd: GDScript = load(path)
		if gd == null:
			continue
		# ⚠️ Object.get() reads PROPERTIES, not consts (Issue 54).
		var consts: Dictionary = gd.get_script_constant_map()
		var origin: Vector3 = t[1]
		for d in (consts.get("DOORS", []) as Array):
			var pos: Vector2 = d["pos"]
			out.append({
				"x": pos.x + origin.x, "z": pos.y + origin.z,
				"dir": String(d.get("dir", "z")),
				"label": "%s (%.1f, %.1f)" % [path.get_file(), pos.x, pos.y],
			})
	return out


func _scene_script() -> String:
	var s: Script = current_scene.get_script()
	return String(s.resource_path) if s != null else ""


func _origin_tag(tag: String) -> Vector3:
	if tag == "@zone3":
		var b: Dictionary = (load("res://scripts/backrooms.gd") as GDScript) \
			.get_script_constant_map()
		return b["ZONE3_ORIGIN"]
	return Vector3.ZERO
