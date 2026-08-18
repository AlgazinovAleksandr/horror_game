extends SceneTree

# THE HOUSE'S LIVING-ROOM WINDOW EXISTS, IS VISIBLE, AND FACES INTO THE ROOM.
#
#   Godot --headless --path game --script res://tests/check_window.gd
#
# The window is the frame for a survivable 25-panic scare (`_spawn_window()`: press up against
# the glass and the forest answers). Its quads are rotated PI to face the room and inset 0.25
# to sit proud of the wall — get either wrong and the player sees the back of a one-sided quad,
# i.e. nothing at all, and the scare has no object.
#
# ⚠️ IT ASSERTED NOTHING UNTIL 2026-08-17 (workstream H2). It walked the nodes within 2 m of a
# hand-typed point, printed their transforms and materials, and returned without calling
# `quit()` — so it exited 0 whether the window was there, backwards, or absent, while
# `tools/run_tests.sh` listed it as "the House window exists and faces the room". A printer is
# a fine tool; it is not a guard, and the runner could not tell the difference.

const TARGET := Vector3(-5.0, 1.6, 8.75)     # the living room's north wall, level_2.gd
const RADIUS := 2.5
const MIN_PARTS := 2                         # glass + forest, at least

var _t := 0.0
var _checks := 0
var _fails: Array[String] = []
var _stage := "measure"
var _control: MeshInstance3D = null


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_2_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _process(delta: float) -> bool:
	_t += delta
	if _stage == "measure":
		if _t < 1.4:
			return false
		_measure()
		_stage = "control"
		_t = 0.0
		return false
	_control_check()
	print("")
	print("%d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("WINDOW PASS")
		quit(0)
	else:
		for f in _fails:
			print("  FAIL: " + f)
		print("WINDOW FAIL")
		quit(1)
	return true


# Every flat mesh at the window, as [node, facing].
func _parts() -> Array:
	var out: Array = []
	for n in _all(current_scene, []):
		if not (n is MeshInstance3D):
			continue
		var mi: MeshInstance3D = n
		if mi.global_position.distance_to(TARGET) > RADIUS:
			continue
		if not (mi.mesh is QuadMesh or mi.mesh is PlaneMesh):
			continue
		out.append([mi, mi.global_transform.basis.z.normalized()])
	return out


func _all(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children():
		_all(c, out)
	return out


func _measure() -> void:
	print("--- the House living-room window ---")
	var parts := _parts()
	# ⚠️ Sample size first: "0 window parts checked ... PASS" is the failure this file spent
	# its whole life in.
	_ok("the window is built at all", parts.size() >= MIN_PARTS,
		"%d flat mesh(es) within %.1f m of %v" % [parts.size(), RADIUS, TARGET])
	# The room is at -z from the wall (living room centre ~ z 6), so a quad facing the room
	# has a facing with a negative z component.
	var into_room := 0
	for p in parts:
		var mi: MeshInstance3D = p[0]
		var f: Vector3 = p[1]
		_ok("%s is visible" % mi.name, mi.is_visible_in_tree())
		if f.z < -0.5:
			into_room += 1
	_ok("the window's faces point INTO the living room", into_room >= MIN_PARTS,
		"%d of %d faces have -z facing" % [into_room, parts.size()])

	# ⚠️ THE CONTROL, derived from the scene: turn one window face around and require the
	# same measurement to reject it. Without it, a facing test that had started reading the
	# wrong basis column — Godot's Basis exposes COLUMNS in GDScript and ROWS in C++, and this
	# project has been bitten by exactly that — would approve a window facing the garden.
	if not parts.is_empty():
		_control = parts[0][0]
		_control.rotate_y(PI)


func _control_check() -> void:
	if _control == null:
		_ok("control: a window face exists to turn around", false)
		return
	var f: Vector3 = _control.global_transform.basis.z.normalized()
	_ok("CONTROL: a window face turned to face the wall is REJECTED", f.z >= -0.5,
		"facing z = %.2f after a 180 turn" % f.z)
	_control.rotate_y(PI)
