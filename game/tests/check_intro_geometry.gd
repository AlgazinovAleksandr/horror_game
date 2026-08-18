extends SceneTree

# The Intro Room's wall-mounted geometry — that things mounted on a wall are actually ON it.
#
# WHY THIS EXISTS. The 2026-08-16 playtest photographed the exit door and said "the door is
# not connected to the wall". It was measured at **0.275 m clear of WallBack's inner face**,
# full height, full width, with open air behind it that rays passed straight through — and
# that also dragged the game's FINAL beat with it, because _corrupt_room()'s planks derive
# from EXIT_DOOR_POS and so hung 0.485 m in front of blank concrete.
#
# ⚠️ `check_wall_overlap.gd` passed this scene, 27 boxes, 0 problems, the whole time. It
# asserts a MINIMUM clearance (a quad must be ≥2 cm off any CSG box) and there is no
# MAXIMUM, so a prop that has drifted away from its wall is invisible to it. This test is
# the other direction, and the two together are what "the prop is on the wall" means.
#
# ⚠️ Assertions are PHYSICS QUERIES wherever a physics query can answer, per the project's
# verification rules — a node's transform said the door was fine for the life of the bug.
#
#   Godot --headless --path game --script res://tests/check_intro_geometry.gd

const SETTLE := 2.6       # geometry is built in _ready(); the switch waits on the 1.8 s tween
const MAX_BITE := 0.06    # how far a wall prop's back face may sit INSIDE its wall
const MIN_BITE := 0.001   # …and it must bite at all: 0 is coplanar, which z-fights

var _t := 0.0
var _stage := 0
var _fails: Array[String] = []
var _checks := 0
var _scene: Node = null
var _gs: Node = null


func _initialize() -> void:
	change_scene_to_file("res://scenes/intro_room.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _process(delta: float) -> bool:
	_t += delta
	if _stage == 0 and _t > SETTLE:
		_scene = current_scene
		_gs = get_root().get_node_or_null("/root/GameState")
		print("--- the opening room ---")
		_check_door()
		_check_casing()
		_check_switch()
		# Rebuild as the twist ending and re-run the same measurement on the planks.
		if _gs:
			_gs.is_ending = true
			change_scene_to_file("res://scenes/intro_room.tscn")
		_t = 0.0
		_stage = 1
		return false

	if _stage == 1 and _t > SETTLE:
		_scene = current_scene
		print("--- the corrupted room (same scene, GameState.is_ending) ---")
		_check_planks()
		if _gs:
			_gs.is_ending = false
		_finish()
		return true

	if _t > 30.0:
		print("RESULT: FAIL — timed out at stage %d" % _stage)
		quit(1)
		return true
	return false


# ---------------------------------------------------------------- helpers

func _wall_face_z() -> float:
	# Derived from the built node, never from the script's constants — a test that reads the
	# same constant the code does proves only that arithmetic is deterministic.
	var wall := _scene.get_node_or_null("WallBack") as CSGBox3D
	if not wall:
		return NAN
	return wall.global_position.z + wall.size.z / 2.0


func _box_span_z(mi: MeshInstance3D) -> Vector2:
	var bm: BoxMesh = mi.mesh
	var c: float = mi.global_position.z
	return Vector2(c - bm.size.z / 2.0, c + bm.size.z / 2.0)


func _space():
	return (_scene.get_node("Player") as Node3D).get_world_3d().direct_space_state


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.hit_from_inside = true
	return _space().intersect_ray(q)


# ---------------------------------------------------------------- the door

func _check_door() -> void:
	var wall_z := _wall_face_z()
	var door := _scene.get_node_or_null("ExitDoor") as Node3D
	_ok("WallBack found", not is_nan(wall_z), "inner face z = %.4f" % wall_z)
	_ok("ExitDoor found", door != null)
	if not door or is_nan(wall_z):
		return

	var slab := door.get_node_or_null("DoorSlab") as MeshInstance3D
	_ok("the door has a slab", slab != null)
	if not slab:
		return
	var span := _box_span_z(slab)
	var bite := wall_z - span.x            # >0 means the back face is inside the wall
	_ok("the door leaf is SET INTO WallBack, not floating in front of it",
		bite >= MIN_BITE and bite <= MAX_BITE,
		"back face %.4f, wall face %.4f, bite %+.4f m (was -0.2750 = a 27.5 cm gap)"
			% [span.x, wall_z, bite])

	# The real assertion: fire rays ACROSS the door, at heights spanning its full extent, in
	# the strip between the wall face and the leaf's front face. Before the fix this strip
	# was open air at every height (measured: clear at y = 0.30 / 1.10 / 2.00 / 2.30); now
	# every one of them must land on the door itself.
	var probe_z: float = (wall_z + span.y) / 2.0
	var hits := 0
	var heights := [0.30, 1.10, 2.00]
	for y in heights:
		var r := _ray(Vector3(-4.0, y, probe_z), Vector3(4.0, y, probe_z))
		var who: String = str(r.get("collider").name) if r else "NOTHING"
		if r and r.get("collider") == door:
			hits += 1
		else:
			print("       ray y=%.2f z=%.3f hit %s" % [y, probe_z, who])
	_ok("no air slot behind the leaf — rays across it hit the door at every height",
		hits == heights.size(), "%d/%d at z=%.3f" % [hits, heights.size(), probe_z])
	_ok("…and the probe really was in the gap region", probe_z > wall_z and probe_z < span.y,
		"%.4f is between %.4f and %.4f" % [probe_z, wall_z, span.y])


func _check_casing() -> void:
	var wall_z := _wall_face_z()
	var jamb_l := _scene.get_node_or_null("DoorJambL") as MeshInstance3D
	var jamb_r := _scene.get_node_or_null("DoorJambR") as MeshInstance3D
	var lintel := _scene.get_node_or_null("DoorLintel") as MeshInstance3D
	_ok("the doorway has a casing (two jambs + a lintel)",
		jamb_l != null and jamb_r != null and lintel != null)
	if not (jamb_l and jamb_r and lintel):
		return

	var door := _scene.get_node_or_null("ExitDoor") as Node3D
	var art := door.get_node_or_null("DoorMesh") as MeshInstance3D if door else null
	var casing_front := _box_span_z(jamb_l).y
	_ok("the casing bites into the wall too", wall_z - _box_span_z(jamb_l).x >= MIN_BITE,
		"jamb back %.4f vs wall %.4f" % [_box_span_z(jamb_l).x, wall_z])
	if art:
		_ok("the leaf sits RECESSED inside the casing",
			casing_front > art.global_position.z + 0.02,
			"casing front %.4f vs door art %.4f (%.3f m of reveal)"
				% [casing_front, art.global_position.z, casing_front - art.global_position.z])

	# ⚠️ The casing must have NO COLLIDER. A collider on the only doorway wall is this
	# project's documented way of silently sealing a room. Physics, not node inspection:
	# aim at the jamb's centre from inside the room and the first thing hit must be the wall
	# BEHIND it, which can only happen if the jamb is not solid.
	for jamb in [jamb_l, jamb_r]:
		var x: float = (jamb as Node3D).global_position.x
		var r := _ray(Vector3(x, 1.10, -6.0), Vector3(x, 1.10, wall_z - 0.10))
		var who: String = str(r.get("collider").name) if r else "NOTHING"
		_ok("%s is visual only — nothing solid was added to the doorway wall" % jamb.name,
			who == "WallBack", "ray at x=%.2f hit %s" % [x, who])


func _check_switch() -> void:
	var wall := _scene.get_node_or_null("WallLeft") as CSGBox3D
	var sw := _scene.get_node_or_null("LightSwitch") as Node3D
	_ok("WallLeft found", wall != null)
	# The switch is spawned by _on_wakeup_finished(), i.e. after the 1.8 s tween. At SETTLE
	# it does not exist yet — assert the mounting from its CONSTANT instead of skipping,
	# because "not there yet" must not read as a pass.
	if not wall:
		return
	var face_x: float = wall.global_position.x + wall.size.x / 2.0
	if sw:
		var backing := sw.get_child(0) as MeshInstance3D
		var bm: BoxMesh = backing.mesh
		var back_x: float = sw.global_position.x - bm.size.z / 2.0
		var bite := back_x - face_x
		_ok("the switch plate is mounted ON WallLeft",
			bite <= -MIN_BITE and bite >= -MAX_BITE,
			"plate back %.4f, wall face %.4f, bite %+.4f m (was +0.0600 = a 6 cm gap)"
				% [back_x, face_x, -bite])
	else:
		var script_pos: Vector3 = _scene.get_script().get("SWITCH_POS")
		var back_x2: float = script_pos.x - 0.02
		_ok("the switch plate is mounted ON WallLeft (from SWITCH_POS — not spawned yet)",
			back_x2 < face_x and face_x - back_x2 <= MAX_BITE,
			"plate back %.4f, wall face %.4f" % [back_x2, face_x])


func _check_planks() -> void:
	var wall_z := _wall_face_z()
	_ok("the exit door is gone in the ending", _scene.get_node_or_null("ExitDoor") == null)
	_ok("but the casing survives — planks need a doorway to be nailed across",
		_scene.get_node_or_null("DoorJambL") != null
			and _scene.get_node_or_null("DoorLintel") != null)

	var jamb := _scene.get_node_or_null("DoorJambL") as MeshInstance3D
	var casing_front: float = _box_span_z(jamb).y if jamb else wall_z + 0.22
	var planks := 0
	var worst := -99.0
	for c in _scene.get_children():
		if not (c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh):
			continue
		var bm: BoxMesh = (c as MeshInstance3D).mesh
		if bm.size.x < 1.5:
			continue
		planks += 1
		var z: float = (c as Node3D).global_position.z
		worst = maxf(worst, z)
		_ok("plank %d is boarded across the doorway, not floating in the room" % planks,
			z > wall_z and z < casing_front + 0.02,
			"z=%.4f, wall face %.4f, casing front %.4f (was -8.3650 = 0.485 m out)"
				% [z, wall_z, casing_front])
	_ok("three planks were checked", planks == 3, "found %d" % planks)


func _finish() -> void:
	print("")
	print("%d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		for f in _fails:
			print("  FAIL: " + f)
		print("RESULT: FAIL")
		quit(1)
