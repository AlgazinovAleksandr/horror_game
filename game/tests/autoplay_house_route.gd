extends SceneTree

# Can an interactable in the House SEAL A ROUTE by being used?
#
#   Godot --headless --path game --script res://tests/autoplay_house_route.gd
#
# ⚠️ THIS CLASS HAD NO GUARD AT ALL, AND IT HAS NOW BITTEN THREE TIMES IN ONE WEEK:
#   * Lab Issue 65 / 67 — interact volumes given real depth blocked movement and prompts.
#   * House Issue 76 — `kitchen_drawer.gd` tweened `self`, so the CollisionShape3D travelled
#     with the visuals and an opened drawer put a 0.62 x 0.26 x 0.14 solid 34 cm out into the
#     Kitchen. Measured with the player's own capsule, the free lane across the room at
#     z = 7.40 went from ONE 5.10 m span to two spans of 1.30 m and 2.50 m. The playtester was
#     carrying the cellar key at the time: *"When I read this note it fell and blocked my way,
#     I cannot pass by."*
#
# `autoplay_exit_reachable.gd` walks to each level's exit with the world in its PRISTINE state,
# so it cannot see any of that. This file is its counterpart: it opens everything that opens
# and then asks the same question twice.
#
# Two independent assertions, because THEY CATCH DIFFERENT FAILURES and neither subsumes the
# other — verified by disabling the fix and watching which one goes red:
#
#   1. CONNECTIVITY — catches ISOLATION. A capsule-query flood fill of the ground floor from a
#      FIXED anchor (the spawn point), before and after using every openable prop. Every cell
#      that was reachable BEFORE and is still physically FREE after must still be reachable
#      AFTER. (Cells a prop now occupies are legitimately lost and are excluded; what may never
#      happen is that free floor becomes unreachable.) A physics query, never object state.
#      Plus a concrete companion: every room in the level's own ROOMS table still has reachable
#      floor in it.
#   2. THE WALK — catches NARROWING. The real player, driven through `player.ai_*` (never a
#      teleport), from the kitchen counter to the cellar gate and on to the exit lock, with
#      every prop already open and the painting already down, ending in the real interact
#      raycast on each door.
#
# ⚠️ MEASURED, and worth knowing before trusting either half on its own: restoring the Issue-76
# drawer reddens (2) HARD — the player jams at (3.65, 7.23) and never reaches the gate, which
# is the report verbatim — and leaves (1) completely green, because the drawer did not ISOLATE
# anything, it narrowed the one lane past the counter. Neither assertion subsumes the other and
# a build can be shipped-broken while one of them is happy.
#
# The props are opened through `player.ai_interact()`, i.e. the real ray + `can_interact()` +
# `interact()` chain, so this doubles as a reach test for both of them.

const AUTOPLAYER := preload("res://tests/autoplay/autoplayer.gd")

# Ground-floor flood-fill grid. The cellar is at y = -1.5 down a ramp and is deliberately out
# of scope: every prop under test is on this floor.
const STEP := 0.25
const X0 := -10.5
const X1 := 9.0
const Z0 := -3.5
const Z1 := 19.5
const CAP_R := 0.4          # level_2_1.tscn's player CapsuleShape3D
const CAP_H := 1.8
const CAP_Y := 0.95         # feet at 0.05

const MIN_CELLS := 600      # a flood fill that measures nothing must fail loudly
const FRAME_BUDGET := 900   # per leg

var _fails: Array[String] = []
var _checks := 0
var _t := 0.0
var _phase := "load"
var _t0 := 0.0
var _scene: Node = null
var _player: CharacterBody3D = null
var _auto: AutoPlayer = null
var _note_ui: Node = null
var _before: Dictionary = {}
var _leg: Array = []
var _wp := 0
var _frames := 0
var _painting_down_in_landing := true
var _anchor := Vector3.ZERO


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_2_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _find(node: Node, pred: Callable) -> Node:
	if pred.call(node):
		return node
	for c in node.get_children():
		var f := _find(c, pred)
		if f:
			return f
	return null


# ---------------------------------------------------------------- flood fill

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(int(round((p.x - X0) / STEP)), int(round((p.z - Z0) / STEP)))


func _free(space: PhysicsDirectSpaceState3D, q: PhysicsShapeQueryParameters3D,
		c: Vector2i) -> bool:
	q.transform = Transform3D(Basis(),
		Vector3(X0 + c.x * STEP, CAP_Y, Z0 + c.y * STEP))
	return space.intersect_shape(q, 1).is_empty()


# Returns { free: {Vector2i: true}, reach: {Vector2i: true} }.
#
# ⚠️ `from` is a FIXED anchor (the spawn point), never the player's live position: if the
# fill started where they happen to be standing, a prop that walls them into one half of a
# room would move the seed into that half and the comparison would report nothing wrong.
# ⚠️ And the player's own body is EXCLUDED, or they show up as a moving 0.8 m obstacle and
# invent "lost" cells wherever they were standing when the sample was taken.
func _flood(from: Vector3) -> Dictionary:
	var space := _scene.get_viewport().find_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = CAP_R
	shape.height = CAP_H
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	if _player:
		q.exclude = [_player.get_rid()]
	var nx := int((X1 - X0) / STEP)
	var nz := int((Z1 - Z0) / STEP)
	var free := {}
	for ix in range(nx + 1):
		for iz in range(nz + 1):
			var c := Vector2i(ix, iz)
			if _free(space, q, c):
				free[c] = true
	# BFS from the anchor cell, nudged to the nearest free one (the spawn point does not
	# necessarily land on a grid intersection).
	var start := _cell(from)
	if not free.has(start):
		var best := Vector2i(-1, -1)
		var bd := 1e9
		for c in free:
			var d: float = Vector2(c - start).length()
			if d < bd:
				bd = d
				best = c
		start = best
	var reach := {}
	if free.has(start):
		var queue: Array[Vector2i] = [start]
		reach[start] = true
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if free.has(n) and not reach.has(n):
					reach[n] = true
					queue.append(n)
	return {"free": free, "reach": reach}


# ---------------------------------------------------------------- driving

func _begin_leg(points: Array) -> void:
	_leg = points
	_wp = 0
	_frames = 0
	_auto.reset_stuck()


# Returns true when the leg is done; sets `stuck` handling itself.
func _drive_leg(label: String) -> bool:
	_frames += 1
	if _wp >= _leg.size():
		return true
	if _frames > FRAME_BUDGET:
		_ok("%s: ran out of frames at waypoint %d" % [label, _wp], false,
			"at %v" % _player.global_position.snappedf(0.01))
		return true
	var target: Vector3 = _leg[_wp]
	target.y = _player.global_position.y
	if _auto.step_toward(target):
		_wp += 1
		_auto.reset_stuck()
	elif _auto.stuck:
		_ok("%s: STUCK on the way to waypoint %d %v" % [label, _wp, _leg[_wp]], false,
			"at %v" % _player.global_position.snappedf(0.01))
		_wp += 1
		_auto.reset_stuck()
	return false


func _use(target_name: String, mesh_name: String, stand_from: Vector3) -> void:
	var prop := _scene.get_node_or_null(target_name)
	_ok("%s exists" % target_name, prop != null)
	if not prop:
		return
	var mesh: Node3D = _find(prop, func(n: Node) -> bool:
		return n is MeshInstance3D and String(n.name) == mesh_name)
	_ok("%s: the %s mesh exists to aim at" % [target_name, mesh_name], mesh != null)
	if not mesh:
		return
	# ⚠️ Aim at the MESH, never at the collider — aiming at the collider is what let an
	# earlier reach test pass against props a player could not hit (check_interact_reach.gd).
	_player.ai_look_at(mesh.global_position)
	var cam := _player.get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.force_update_transform()
	var hit: Node = _player.ai_interact_target()
	_ok("%s: the real interact ray finds it from %.2f m" %
			[target_name, _player.global_position.distance_to(mesh.global_position)],
		hit == prop or (hit != null and prop.is_ancestor_of(hit)),
		"ray saw %s (stood %v)" % [hit, stand_from.snappedf(0.01)])
	_player.ai_interact()


func _ray_finds(door_name: String) -> void:
	var door := _scene.get_node_or_null(door_name) as Node3D
	_ok("%s exists" % door_name, door != null)
	if not door:
		return
	_player.ai_look_at(door.global_position)
	var cam := _player.get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.force_update_transform()
	var hit: Node = _player.ai_interact_target()
	_ok("the walk ends with the interact ray on %s" % door_name,
		hit == door or (hit != null and door.is_ancestor_of(hit)),
		"from %v, ray saw %s" % [_player.global_position.snappedf(0.01), hit])


# ---------------------------------------------------------------- the run

func _process(delta: float) -> bool:
	_t += delta
	match _phase:
		"load":
			if _t < 1.0:
				return false
			_scene = current_scene
			_player = _scene.get_node_or_null("Player") as CharacterBody3D
			_note_ui = root.get_node_or_null("/root/NoteUI")
			_ok("player found", _player != null)
			_ok("NoteUI autoload present", _note_ui != null)
			if not _player:
				return _bail()
			_auto = AUTOPLAYER.new(_player)
			_anchor = _player.global_position
			print("--- flood fill BEFORE ---")
			_before = _flood(_anchor)
			_ok("the ground floor flood fill measured something",
				int(_before["reach"].size()) >= MIN_CELLS,
				"%d of %d free cells reachable" % [_before["reach"].size(),
					_before["free"].size()])
			# Arm the painting the way the game does (map solved), then let the real
			# `_tick_painting()` decide when it falls.
			_scene.call("_advance_guest", 1)
			_begin_leg([
				Vector3(0, 0, 1.0), Vector3(0, 0, 5.0), Vector3(2.4, 0, 6.0),
				Vector3(2.4, 0, 7.4), Vector3(4.0, 0, 7.45),
			])
			_phase = "to_drawer"
		"to_drawer":
			if _drive_leg("Hallway -> kitchen counter"):
				_auto.stop()
				print("--- open the drawer ---")
				_use("KitchenDrawer", "DrawerFront", _player.global_position)
				_t0 = _t
				_phase = "drawer_open"
		"drawer_open":
			if _t - _t0 < 1.4:
				return false
			var dr := _scene.get_node_or_null("KitchenDrawer")
			_ok("the drawer opened", dr != null and not bool(dr.call("can_interact")))
			if _note_ui and bool(_note_ui.get("is_open")):
				_note_ui.call("_close")
			_begin_leg([
				Vector3(5.5, 0, 7.45), Vector3(6.7, 0, 7.45), Vector3(6.7, 0, 6.95),
			])
			_phase = "to_fridge"
		"to_fridge":
			if _drive_leg("counter -> fridge"):
				_auto.stop()
				print("--- open the fridge ---")
				_use("Fridge", "FridgeDoor", _player.global_position)
				_t0 = _t
				_phase = "fridge_open"
		"fridge_open":
			if _t - _t0 < 1.4:
				return false
			print("--- flood fill AFTER (drawer + fridge open) ---")
			_compare()
			_begin_leg([
				Vector3(6.7, 0, 5.2), Vector3(5.6, 0, 4.4), Vector3(5.0, 0, 4.0),
			])
			_phase = "to_gate"
		"to_gate":
			if _drive_leg("fridge -> cellar gate"):
				_auto.stop()
				print("--- the R1 route: kitchen counter -> cellar gate ---")
				var gate := _scene.get_node_or_null("CellarGate") as Node3D
				var gd := 999.0
				if gate:
					var a: Vector3 = _player.global_position
					var b: Vector3 = gate.global_position
					gd = Vector2(a.x - b.x, a.z - b.z).length()
				_ok("the walk reached the cellar gate", gd <= 2.0,
					"%.2f m from it, at %v" % [gd, _player.global_position.snappedf(0.01)])
				_ray_finds("CellarGate")
				_begin_leg([
					Vector3(5.0, 0, 5.0), Vector3(2.4, 0, 4.6), Vector3(2.4, 0, 6.0),
					Vector3(0.6, 0, 6.0), Vector3(0, 0, 9.0), Vector3(0, 0, 12.6),
				])
				_phase = "to_landing"
		"to_landing":
			if _drive_leg("cellar gate -> Landing"):
				_auto.stop()
				# ⚠️ The painting hangs on the ChildRoom's NORTH wall and is armed. From the
				# Landing it is out of range AND behind a wall, so it must still be up.
				_painting_down_in_landing = bool(_scene.get("_painting_fallen"))
				_ok("the painting has NOT fallen while the player is still in the Landing",
					not _painting_down_in_landing,
					"armed at the start of the walk; %v" % _player.global_position.snappedf(0.01))
				_begin_leg([Vector3(0, 0, 15.2), Vector3(-0.7, 0, 17.9)])
				_phase = "to_lock"
		"to_lock":
			if _drive_leg("Landing -> the exit lock"):
				_auto.stop()
				_ok("…and it HAS fallen by the time the player is at the lock",
					bool(_scene.get("_painting_fallen")),
					"at %v" % _player.global_position.snappedf(0.01))
				_t0 = _t
				_phase = "settle"
		"settle":
			if _t - _t0 < 0.9:      # let the 0.45 s fall tween finish
				return false
			print("--- the exit lock, with the painting on the floor ---")
			_ray_finds("ExitDoor")
			print("--- flood fill AFTER (everything used, painting down) ---")
			_compare()
			return _bail()
	return false


func _compare() -> void:
	var after := _flood(_anchor)
	var lost: Array = []
	for c in _before["reach"]:
		if after["free"].has(c) and not after["reach"].has(c):
			lost.append(c)
	_ok("the flood fill still measures something",
		int(after["reach"].size()) >= MIN_CELLS,
		"%d of %d free cells reachable" % [after["reach"].size(), after["free"].size()])
	var sample := ""
	if not lost.is_empty():
		var c: Vector2i = lost[0]
		sample = " e.g. (%.2f, %.2f)" % [X0 + c.x * STEP, Z0 + c.y * STEP]
	_ok("NO free floor was cut off by using a prop", lost.is_empty(),
		"%d cells reachable before are now unreachable%s" % [lost.size(), sample])
	# ⚠️ A SECOND, CONCRETE assertion beside the cell arithmetic. "No cell was lost" is true of
	# a build where the flood fill silently measured the wrong thing; "the Kitchen and the
	# child's room are still reachable from the front door" is not. Room centres come from the
	# level's own ROOMS table, so this cannot drift away from the geometry that produced it.
	var rooms: Array = _scene.get_script().get_script_constant_map().get("ROOMS", [])
	_ok("read the level's own ROOMS table", rooms.size() >= 8, "%d rooms" % rooms.size())
	# ⚠️ NOT the room CENTRE — the Kitchen's is under the dining table, so a centre test reports
	# a furnished room as sealed. The question is whether ANY free floor in the room can still
	# be reached, and how much of it.
	var unreachable: Array[String] = []
	var thin: Array[String] = []
	for r in rooms:
		var pos: Vector2 = r["pos"]
		var half: Vector2 = r["size"] * 0.5
		var lo := _cell(Vector3(pos.x - half.x, 0.0, pos.y - half.y))
		var hi := _cell(Vector3(pos.x + half.x, 0.0, pos.y + half.y))
		var free_here := 0
		var reach_here := 0
		for ix in range(lo.x, hi.x + 1):
			for iz in range(lo.y, hi.y + 1):
				var c := Vector2i(ix, iz)
				if after["free"].has(c):
					free_here += 1
					if after["reach"].has(c):
						reach_here += 1
		if free_here < 4:
			thin.append("%s(%d free)" % [String(r["name"]), free_here])
		elif reach_here == 0:
			unreachable.append(String(r["name"]))
	# A room with almost no free floor would make the line above vacuously true.
	_ok("every room has floor to measure", thin.is_empty(), "too few free cells: %s" % str(thin))
	_ok("every room is still reachable from the entrance", unreachable.is_empty(),
		"cut off: %s" % str(unreachable))


func _bail() -> bool:
	if _auto:
		_auto.release()
	print("--------------------------------------------------")
	print("%d checks, %d failed" % [_checks, _fails.size()])
	for f in _fails:
		print("   FAILED: " + f)
	print("HOUSE-ROUTE " + ("PASS" if _fails.is_empty() else "FAIL"))
	quit(0 if _fails.is_empty() else 1)
	return true
