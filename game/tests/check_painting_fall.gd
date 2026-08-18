extends SceneTree

# The Corridor's falling painting lands ON A WALL, from anywhere in the level.
#
#   Godot --headless --path game --script res://tests/check_painting_fall.gd
#
# WHY THIS EXISTS. `_ev_painting_fall()` was the only visual prop in the game spawned at an
# unvalidated random world offset:
#
#     _player.global_position + Vector3(randf_range(-2, 2), 1.8, randf_range(-2, 2))
#
# The corridor is 3 m wide, so one of those two axes is always the LATERAL one and it was
# being drawn U(-2, 2) against walls at ±1.5 m. There was no raycast, no `wall_point()` and
# no clearance probe, and the 1.5 m quad was then yawed a random ±180°. This is Issue 77 —
# *"a scripted beat with a facing check and no line of sight: the painting that fell through
# a wall"* — recurring in a second level.
#
# HOW IT MEASURES. 200 player positions spread along the whole 320 m path, at random lateral
# offsets and random headings. For each, ask the level where the painting would go and then
# check all four corners of the picture with RAYCASTS against the built CSG — a ray from the
# corridor centreline to the corner must reach it unobstructed (the corner is inside the
# corridor) and a ray from just in front of the corner into the wall must hit (there is a
# wall behind it). Never against `PATH_2D`: the thing under test is the geometry, so the
# assertion has to interrogate the geometry.
#
# ⚠️ PROOF IT CAN FAIL, kept permanently: the same 200 positions are also run through a
# reimplementation of the OLD random-offset rule, and its failure rate is printed and
# asserted to be large. If that ever comes back clean, this file has stopped measuring.

const SAMPLES := 200
const CORNER_EPS := 0.02
const SETTLE := 12

var _frame := 0
var _done := false
var _checks := 0
var _fails: Array[String] = []
var _rng := RandomNumberGenerator.new()
var _scene: Node = null
var _player: CharacterBody3D = null
var _total := 0.0


func _initialize() -> void:
	change_scene_to_file("res://scenes/corridor.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _process(_delta: float) -> bool:
	_frame += 1
	if _done:
		return true
	if _frame < SETTLE:
		return false
	_done = true

	_rng.seed = 20260816
	_scene = current_scene
	_player = _scene.get_node_or_null("Player") as CharacterBody3D
	_total = float(_scene.get("_total_len"))
	_ok("player and path found", _player != null and _total > 300.0,
		"path length %.1f m" % _total)
	if _player == null:
		return _finish()

	var cam := _player.get_node("Camera3D") as Camera3D
	var bad_new := 0
	var bad_old := 0
	var skipped := 0
	var worst := ""

	for i in SAMPLES:
		var d: float = _rng.randf_range(3.0, _total - 3.0)
		var pt: Dictionary = _scene.call("_path_point", d)
		var lat: float = _rng.randf_range(-1.0, 1.0)
		_player.global_position = (pt.pos as Vector3) + (pt.side as Vector3) * lat \
			+ Vector3(0, 0.1, 0)
		cam.rotation.y = _rng.randf_range(-PI, PI)

		var xf: Transform3D = _scene.call("painting_fall_transform")
		if not bool(_scene.call("_has_backing", xf)):
			# The level withholds the picture rather than embedding it. That is the correct
			# outcome, not a pass to be glossed over — count it and assert it stays rare.
			skipped += 1
			continue
		var why := _corners_bad(xf)
		if why != "":
			bad_new += 1
			if worst == "":
				worst = "d=%.1f lat=%.2f: %s" % [d, lat, why]

		# ...and the rule this replaced, at the same position.
		var old_pos: Vector3 = _player.global_position + Vector3(
			_rng.randf_range(-2.0, 2.0), 1.8, _rng.randf_range(-2.0, 2.0))
		var old_xf := Transform3D(Basis(Vector3.UP, _rng.randf_range(-PI, PI)), old_pos)
		if _corners_bad(old_xf) != "":
			bad_old += 1

	_ok("every painting lands inside the corridor, on a wall",
		bad_new == 0, "%d of %d bad%s" % [bad_new, SAMPLES,
			("  first: " + worst) if worst != "" else ""])
	_ok("the level almost never has to withhold the picture", skipped <= SAMPLES / 10,
		"%d of %d skipped (no wall anywhere near)" % [skipped, SAMPLES])
	# ⚠️ THE CONTROL. The old rule must still fail loudly on this scene, or the check above
	# is measuring nothing.
	_ok("control: the old random-offset rule is REJECTED", bad_old > SAMPLES / 5,
		"%d of %d bad under the shipped-and-wrong rule" % [bad_old, SAMPLES])

	return _finish()


# "" when all four corners of the picture are inside the corridor AND have wall behind them.
func _corners_bad(xf: Transform3D) -> String:
	var size: Vector2 = _scene.get("PAINTING_SIZE")
	var space := _scene.get_viewport().world_3d.direct_space_state
	var n: Vector3 = xf.basis.z.normalized()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner: Vector3 = xf * Vector3(sx * (size.x / 2.0 - 0.02),
				sy * (size.y / 2.0 - 0.02), 0.0)
			# 1. Inside the corridor: the centreline at the corner's own path distance can
			#    see it. If a wall is in the way, the corner is on the far side of one.
			var d: float = float(_scene.call("_nearest_path_distance", corner))
			var pt: Dictionary = _scene.call("_path_point", d)
			var from: Vector3 = (pt.pos as Vector3) + Vector3(0, 1.5, 0)
			var q := PhysicsRayQueryParameters3D.create(from, corner)
			q.exclude = [_player.get_rid()]
			q.collide_with_areas = false
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var reach: float = from.distance_to(hit["position"])
				if reach < from.distance_to(corner) - CORNER_EPS:
					return "corner at %v is behind geometry (%.2f m of %.2f)" % [
						corner.round(), reach, from.distance_to(corner)]
			# 2. And there is a wall behind it.
			var probe := PhysicsRayQueryParameters3D.create(corner + n * 0.25,
				corner - n * 0.40)
			probe.exclude = [_player.get_rid()]
			probe.collide_with_areas = false
			if space.intersect_ray(probe).is_empty():
				return "corner at %v has no wall behind it" % [corner.round()]
	return ""


func _finish() -> bool:
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
	return true
