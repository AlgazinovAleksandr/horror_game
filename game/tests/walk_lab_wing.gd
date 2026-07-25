extends SceneTree

# Walk-test the Lab's dark breaker wing (rebuilt 2026-07-25 from a 4-room stub with
# one binary choice into a 10-room maze with three decision points).
#
#   Godot --headless --path game --script res://tests/walk_lab_wing.gd
#
# ⚠️ Why this drives a body instead of reading the ROOMS table: the project has been
# burned twice by tests that asserted intent rather than geometry. walk_backrooms.gd
# passed for weeks by calling `cleared.emit()` while the level was uncompletable, and
# a glitch wall's `is_real` flag was correct the whole time its trigger sat behind a
# wall. So the route here is covered by actually steering a CharacterBody3D through
# it under gravity, and "is this a dead end" is answered with raycasts against the
# built CSG, never with the DOORS array that produced it.
#
# Checks:
#   1. the full Records -> BreakerNook route is walkable end to end
#   2. the breaker's collider answers an interaction-range ray from standing height
#   3. all three dead ends really are dead (exactly one opening each)
#   4. no room in the wing has a lit lamp
#   5. both beacon layers exist, loop, and sit on the breaker
#   6. the flashlight-lock zone covers every waypoint of the route

const BREAKER_POS := Vector3(-36.85, 1.1, 7.7)

# Centre-line of the intended solution. The walker steers point to point; if any
# doorway on the route were sealed it would stall and the run would fail.
const ROUTE := [
	Vector2(-13.0, 12.5),   # through the Records doorway
	Vector2(-15.5, 12.5),   # DarkCorridor
	Vector2(-21.0, 12.5),   # Junction  <- decision 1 (west / north / south)
	Vector2(-21.0, 8.5),    # SouthSpur
	Vector2(-23.5, 7.7),    # into SouthHall
	Vector2(-30.0, 7.7),    # SouthHall west end  <- decision 3 (PumpRoom / on)
	Vector2(-34.0, 7.7),    # BreakerNook
]

# probe point, room bounds [x0,x1,z0,z1], and the ONE direction that should be open.
const DEAD_ENDS := [
	{ "name": "Plant",      "probe": Vector2(-32.5, 12.5), "b": [-35.0, -30.0, 10.5, 14.5], "open": "+x" },
	{ "name": "NorthVault", "probe": Vector2(-21.0, 22.0), "b": [-29.0, -20.0, 20.0, 24.0], "open": "-z" },
	{ "name": "PumpRoom",   "probe": Vector2(-25.0, 5.35), "b": [-27.0, -23.0, 4.2, 6.5],   "open": "+z" },
]

const WING_ROOMS := [
	"DarkCorridor", "Junction", "WestCorridor", "Plant", "NorthSpur",
	"NorthVault", "SouthSpur", "SouthHall", "PumpRoom", "BreakerNook",
]

var _frame := 0
var _scene: Node
var _player: CharacterBody3D
var _leg := 0
var _stalled := 0
var _last_pos := Vector3.ZERO
var _fail := 0
var _checks := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fail += 1
	print("  %s  %s%s" % ["PASS" if cond else "FAIL", label, ("   " + detail) if detail != "" else ""])


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 6:
		_scene = current_scene
		_player = _scene.get_node_or_null("Player") as CharacterBody3D
		if not _player:
			print("FAIL: no Player")
			quit(1)
			return true
		# Enter at the Records doorway, exactly where a player arrives from the room.
		_player.global_position = Vector3(-11.5, 0.2, 12.5)
		_last_pos = _player.global_position
		print("--- walking the wing ---")
	elif _frame > 8 and _leg < ROUTE.size():
		_drive()
	elif _frame > 8:
		_report()
		quit(1 if _fail > 0 else 0)
		return true
	return false


func _drive() -> void:
	var target: Vector2 = ROUTE[_leg]
	var here := _player.global_position
	var to := Vector3(target.x - here.x, 0.0, target.y - here.z)
	if to.length() < 0.8:
		_leg += 1
		_stalled = 0
		if _leg < ROUTE.size():
			print("  reached leg %d %v" % [_leg, here.snappedf(0.01)])
		return
	var dir := to.normalized()
	_player.velocity.x = dir.x * 4.0
	_player.velocity.z = dir.z * 4.0
	_player.velocity.y -= 1.5
	_player.move_and_slide()
	# A sealed doorway shows up as the body pressing into a wall and going nowhere.
	if _player.global_position.distance_to(_last_pos) < 0.004:
		_stalled += 1
		if _stalled > 180:
			print("  STALLED on leg %d at %v heading for %v"
				% [_leg, _player.global_position.snappedf(0.01), target])
			_leg = ROUTE.size()   # abandon the walk; _report() will mark it failed
	else:
		_stalled = 0
	_last_pos = _player.global_position


func _report() -> void:
	var here := _player.global_position
	var arrived := Vector2(here.x, here.z).distance_to(ROUTE[ROUTE.size() - 1]) < 1.5
	_ok("route Records -> BreakerNook is walkable", arrived, "ended at %v" % here.snappedf(0.01))

	_check_breaker_reachable()
	_check_dead_ends()
	_check_unlit()
	_check_beacon()
	_check_lock_zone()

	print("%d checks, %d failed" % [_checks, _fail])
	print("LAB-WING PASS" if _fail == 0 else "LAB-WING FAIL")


# The breaker has to answer a ray from where a player would actually stand, at eye
# height — not merely exist at the right coordinates.
func _check_breaker_reachable() -> void:
	var space := _player.get_world_3d().direct_space_state
	var eye := Vector3(BREAKER_POS.x + 1.8, 1.6, BREAKER_POS.z)
	# Aim PAST the panel, not at its centre: the collider is only 0.3 m deep and
	# rotated flat against the wall, so a ray terminating on the nominal wall_point
	# stops a few cm short of the near face and reports a clean miss.
	var q := PhysicsRayQueryParameters3D.create(eye, BREAKER_POS + Vector3(-0.4, 0.0, 0.0))
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)
	var body: Node = hit.get("collider") if not hit.is_empty() else null
	# ⚠️ Duck-typed on the `flipped` signal rather than written as `body is Breaker`.
	# Naming a game class here makes GDScript compile breaker.gd while this SceneTree
	# script is still parsing, which is BEFORE the autoloads exist — breaker.gd then
	# fails on `GameState`, `Breaker.new()` raises "Nonexistent function 'new'", and
	# level_1.gd's whole _spawn_power_quest() aborts. The test would then be reporting
	# on a level it had itself broken.
	var is_breaker := body != null and (body.has_signal("flipped")
		or (body.get_parent() != null and body.get_parent().has_signal("flipped")))
	_ok("breaker answers an interaction ray", is_breaker,
		"hit %s" % (body.name if body else "nothing"))


func _check_dead_ends() -> void:
	var space := _player.get_world_3d().direct_space_state
	for d in DEAD_ENDS:
		var p: Vector2 = d["probe"]
		var b: Array = d["b"]
		var from := Vector3(p.x, 1.2, p.y)
		var opens: Array = []
		# Aim 0.6 m PAST the nominal boundary: a solid wall stops the ray, a doorway
		# lets it through. Per-direction lengths, so a wide room can't read as open
		# just because a fixed-length ray fell short of its far wall.
		var probes := {
			"-x": Vector3(b[0] - 0.6, 1.2, p.y),
			"+x": Vector3(b[1] + 0.6, 1.2, p.y),
			"-z": Vector3(p.x, 1.2, b[2] - 0.6),
			"+z": Vector3(p.x, 1.2, b[3] + 0.6),
		}
		for k in probes:
			var q := PhysicsRayQueryParameters3D.create(from, probes[k])
			q.exclude = [_player.get_rid()]
			if space.intersect_ray(q).is_empty():
				opens.append(k)
		_ok("%s is a dead end" % d["name"],
			opens.size() == 1 and opens[0] == d["open"],
			"open: %s (expected %s)" % [str(opens), d["open"]])


func _check_unlit() -> void:
	var lit: Array = []
	for r in WING_ROOMS:
		var lamp := _scene.get_node_or_null("Lamp_" + r) as OmniLight3D
		if lamp and lamp.light_energy > 0.0:
			lit.append("%s=%.2f" % [r, lamp.light_energy])
	_ok("no lit lamp anywhere in the wing", lit.is_empty(), str(lit))


func _check_beacon() -> void:
	for base in ["breaker_hum", "breaker_buzz"]:
		var n := _scene.get_node_or_null("Beacon_" + base) as AudioStreamPlayer3D
		var at_breaker := n != null and n.position.distance_to(BREAKER_POS) < 0.01
		# finished->play is what makes a loop_mode=0 .wav behave as a loop.
		var loops := n != null and n.finished.is_connected(n.play)
		_ok("beacon layer %s present, positioned and looping" % base,
			n != null and at_breaker and loops,
			"" if n else "missing")


# One Area3D, not one per room — adjacent zones fire body_exited before body_entered
# and would strobe the flashlight lock at every doorway.
func _check_lock_zone() -> void:
	var zone: Area3D = null
	var shape: BoxShape3D = null
	for c in _scene.get_children():
		if not (c is Area3D):
			continue
		for gc in c.get_children():
			if not (gc is CollisionShape3D):
				continue
			var sh := (gc as CollisionShape3D).shape
			if sh is BoxShape3D and (sh as BoxShape3D).size.x > 20.0:
				zone = c
				shape = sh as BoxShape3D
				break
		if zone:
			break
	if not zone:
		_ok("flashlight-lock zone found", false)
		return
	var lo := zone.position - shape.size / 2.0
	var hi := zone.position + shape.size / 2.0
	var outside: Array = []
	for wp in ROUTE:
		if wp.x < lo.x or wp.x > hi.x or wp.y < lo.z or wp.y > hi.z:
			outside.append(wp)
	for d in DEAD_ENDS:
		var p: Vector2 = d["probe"]
		if p.x < lo.x or p.x > hi.x or p.y < lo.z or p.y > hi.z:
			outside.append(p)
	_ok("lock zone covers the whole wing", outside.is_empty(), "outside: %s" % str(outside))
