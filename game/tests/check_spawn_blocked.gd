extends SceneTree

# NOTHING INVISIBLE IS STANDING WHERE THE PLAYER SPAWNS — **in every level in the game**.
#
#   Godot --headless --path game --script res://tests/check_spawn_blocked.gd
#   Godot --headless --path game --script res://tests/check_spawn_blocked.gd -- KONTUR
#
# A player who spawns inside a collider is stuck before the level starts, and a camera inside
# a prop is why a screenshot comes back black. Both have happened here.
#
# ⚠️ IT ASSERTED NOTHING UNTIL 2026-08-17 (workstream H2). It printed what occupied six
# HAND-TYPED points in the House — points that had been copied out of a room layout that has
# since moved — and then returned without calling `quit()`, so it exited 0 whatever it found.
# It also used `intersect_shape`, which is the one query type that reports NOTHING when it
# lies wholly inside a CSG slab (Issue 40): the single case it existed to detect.
#
# Now: the point is the level's OWN `Player` spawn, on every scene in `tests/lib/scenes.gd`,
# tested with `intersect_point` and rays, and a control drops a box on the spawn every run.
#
# ⚠️ THE INTRO IS MEASURED AT THE END OF ITS WAKE-UP BEAT, not at t=0. `intro_room.gd` starts
# the player lying ON the gurney and tweens them off it; by this file's settle time they are
# standing on the floor and the spawn measures clear, which is the state that matters. (The
# mid-tween position is `check_reachable.gd`'s problem, and it documents it at `@intro_floor`.)

const Scenes := preload("res://tests/lib/scenes.gd")

const CAP_R := 0.38          # a hair under the player's 0.40 capsule
const HEIGHTS := [0.35, 1.0, 1.5]
const FLOOR_DROP := 2.5      # how far under the spawn we will accept finding a floor

const CONFIG := {
	"SCENE_KONTUR": {"seeds": [7, 3, 11]},
	"SCENE_DUNGEON": {"seeds": [1, 404]},
}

var _rows: Array = []
var _row := 0
var _t := 0.0
var _checks := 0
var _fails: Array[String] = []
var _summary: Array = []
var _only := ""
var _stage := "measure"
var _control: StaticBody3D = null
var _spawn := Vector3.ZERO


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
		print("SPAWN FAIL: no scene matched %s" % _only)
		quit(1)
		return
	_load_row()


func _load_row() -> void:
	_t = 0.0
	_stage = "measure"
	_control = null
	Scenes.pin_rng(int(_rows[_row]["seed"]))
	change_scene_to_file(String(_rows[_row]["path"]))


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _process(delta: float) -> bool:
	_t += delta
	var cfg: Dictionary = _rows[_row]
	if _stage == "measure":
		if _t < float(cfg["settle"]):
			return false
		_measure(cfg)
		if _control == null:
			return _advance()
		_stage = "control"
		_t = 0.0
		return false
	if _t < 0.4:
		return false
	_control_check(cfg)
	return _advance()


func _advance() -> bool:
	_row += 1
	if _row < _rows.size():
		_load_row()
		return false
	print("")
	print("--- SPAWN SWEEP: %d scene-run(s) ---" % _rows.size())
	for line in _summary:
		print("  " + line)
	print("%d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("SPAWN PASS")
		quit(0)
	else:
		for f in _fails:
			print("  FAIL: " + f)
		print("SPAWN FAIL")
		quit(1)
	return true


# What is in the way at the spawn, as a list of collider names. Empty is clear.
#
# ⚠️ `intersect_point` plus rays, NEVER `intersect_shape` — Issue 40, and it is the whole
# reason the old version of this file could not have found the bug it was written for: a
# shape query against CSG returns nothing when the query volume is wholly inside the slab.
func _blockers(player: CharacterBody3D) -> Array:
	var space := current_scene.get_viewport().world_3d.direct_space_state
	var names: Array = []
	for y in HEIGHTS:
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = _spawn + Vector3(0, y, 0)
		pq.collide_with_areas = false
		pq.exclude = [player.get_rid()]
		for hit in space.intersect_point(pq, 8):
			var n: Node = hit.get("collider") as Node
			if n != null and not names.has(String(n.name)):
				names.append(String(n.name))
		# ...and a short fan, which catches a wall face the point query sits just outside of.
		var eye: Vector3 = _spawn + Vector3(0, y, 0)
		for i in range(8):
			var a := TAU * float(i) / 8.0 + 0.0646
			var q := PhysicsRayQueryParameters3D.create(
				eye, eye + Vector3(cos(a), 0, sin(a)) * CAP_R)
			q.exclude = [player.get_rid()]
			q.collide_with_areas = false
			var r := space.intersect_ray(q)
			if r.is_empty():
				continue
			var rn: Node = r["collider"] as Node
			if rn != null and not names.has(String(rn.name)):
				names.append(String(rn.name))
	return names


func _measure(cfg: Dictionary) -> void:
	print("")
	print("--- spawn: %s (%s, seed %d) ---" % [cfg["label"], cfg["path"], int(cfg["seed"])])
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	_ok("%s: player found" % cfg["label"], player != null)
	if player == null:
		return
	_spawn = player.global_position
	var blockers := _blockers(player)
	var on_furniture: String = String(cfg.get("on_furniture", ""))
	if on_furniture != "":
		# ⚠️ Asserted, not waived: the exception claims the spawn IS inside something, so if
		# that ever stops being true the row is stale and has to go.
		_ok("%s: the documented on-furniture spawn is still on it" % cfg["label"],
			not blockers.is_empty(), "%s — %s" % [str(blockers), on_furniture])
	else:
		_ok("%s: the spawn point is clear" % cfg["label"], blockers.is_empty(),
			"at %v, blocked by %s" % [_spawn.snappedf(0.01), str(blockers)])

	# There must also be a floor under it — a spawn in mid-air is the Issue-5 void fall.
	var space := current_scene.get_viewport().world_3d.direct_space_state
	var down := PhysicsRayQueryParameters3D.create(
		_spawn + Vector3(0, 0.4, 0), _spawn - Vector3(0, FLOOR_DROP, 0))
	down.exclude = [player.get_rid()]
	var fh := space.intersect_ray(down)
	_ok("%s: there is floor under the spawn" % cfg["label"], not fh.is_empty(),
		"nothing within %.1f m below %v" % [FLOOR_DROP, _spawn.snappedf(0.01)]
			if fh.is_empty() else "%.2f m below"
				% (_spawn.y - float(fh["position"].y)))
	_summary.append("%-10s seed %-4d spawn %v, %d blocker(s)"
		% [cfg["label"], int(cfg["seed"]), _spawn.snappedf(0.1), blockers.size()])

	# ⚠️ THE CONTROL, on the scene under test, every run: drop a solid box on the spawn and
	# require the same probe to see it. A probe that had stopped detecting anything — the
	# `intersect_shape`-against-CSG trap this file used to be built on — would otherwise
	# report every spawn in the game as clear, forever.
	# ⚠️ A `StaticBody3D` + `BoxShape3D`, NOT a `CSGBox3D` — cross-level X45, measured again
	# here. A CSG box created at RUNTIME answers `intersect_ray` and is invisible to
	# `intersect_shape` AND to `intersect_point`, so the first version of this control was
	# undetectable by the very probe it exists to prove: nine scenes reported "the control was
	# not detected" on a probe that works. Build a control from the simplest primitive there
	# is, and assert its halves separately.
	var body := StaticBody3D.new()
	body.name = "SpawnBlockerControl"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 2.0, 1.0)
	col.shape = shape
	body.add_child(col)
	current_scene.add_child(body)
	body.global_position = _spawn + Vector3(0, 1.0, 0)
	_control = body


func _control_check(cfg: Dictionary) -> void:
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	var blockers: Array = _blockers(player) if player != null else []
	_ok("%s CONTROL: a box dropped on the spawn IS detected" % cfg["label"],
		blockers.has("SpawnBlockerControl"), str(blockers))
	if is_instance_valid(_control):
		_control.get_parent().remove_child(_control)
		_control.queue_free()
