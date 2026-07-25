extends SceneTree

# Can you get OUT of the Lab's dark wing from its deepest dead end?
#
#   Godot --headless --path game --script res://tests/walk_wing_escape.gd
#
# walk_lab_wing.gd proves the route IN is walkable and that the three dead ends are
# dead. It never tests the way back. Playtest 2026-07-26 ended with the player circling
# NorthVault for 90 s and reporting "I think I got stuck in the dark room", so this
# drives the exact position the log last recorded them at, all the way back to Records.
#
# It answers a specific question — is this GEOMETRY or is it NAVIGATION? A stall means a
# real trap; a clean walk means the player was lost, which is a different fix entirely.

const START := Vector3(-28.4, 0.2, 22.7)   # last logged position of the stuck session

# Out of NorthVault, down the north spur, through the junction and home.
const ROUTE := [
	Vector2(-21.0, 22.0),   # NorthVault, lined up with its only doorway
	Vector2(-21.0, 19.0),   # through into NorthSpur
	Vector2(-21.0, 15.5),   # down the spur
	Vector2(-21.0, 12.5),   # Junction
	Vector2(-16.0, 12.5),   # DarkCorridor
	Vector2(-11.5, 12.5),   # out into Records — clear of the wing
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
		_player.global_position = START
		_last_pos = START
		print("--- escaping the wing from %v ---" % START)
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
	if _player.global_position.distance_to(_last_pos) < 0.004:
		_stalled += 1
		if _stalled > 180:
			print("  STALLED on leg %d at %v heading for %v"
				% [_leg, _player.global_position.snappedf(0.01), target])
			_leg = ROUTE.size()
	else:
		_stalled = 0
	_last_pos = _player.global_position


func _report() -> void:
	var here := _player.global_position
	_ok("walked out of the wing under gravity", _leg >= ROUTE.size() and _stalled <= 180,
		"ended at %v" % here.snappedf(0.01))
	# The walker stops within 0.8 m of a waypoint, so the final x lands anywhere in
	# [-12.3, -11.5]. Assert against the Records DOORWAY (x = -12) plus that tolerance,
	# not against the doorway itself.
	_ok("finished at the Records doorway", here.x > -12.4,
		"x = %.2f (doorway at -12.0, walker tolerance 0.8)" % here.x)
	print("%d checks, %d failed" % [_checks, _fail])
	print("WING-ESCAPE PASS" if _fail == 0 else "WING-ESCAPE FAIL")
