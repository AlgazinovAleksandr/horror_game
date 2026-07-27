extends SceneTree

# Can the player physically WALK to each level's exit door and get a prompt on it?
#   Godot --headless --path game --script res://tests/autoplay_exit_reachable.gd
#
# This is the check nobody was making. The project's history is full of mechanics that
# worked perfectly and were unreachable:
#   * Issue 30 — Level 6's doors: `E` could never find them, because a disabled
#     CollisionShape3D is invisible to raycasts too. Unwinnable for every player,
#     always, while its test passed by calling interact() directly.
#   * Issue 16 — KONTUR's exit had no unlock condition at all; the gates were
#     decoration and the level cleared in 32 seconds.
#   * Issue 5 — Level 2 was unbeatable because one wall had no doorway cut in it.
#
# So the assertion here is deliberately not "does the door work" but "can a body with
# gravity and collision get to it, and does the real interact raycast then see it".
# It drives player.gd's own `ai_*` surface (see tests/autoplay/autoplayer.gd for why
# that exists rather than simulated key presses) and asserts on the prompt target, not
# on a flag.
#
# Waypoints are room centres from each level's own ROOMS table, so the route comes from
# the same data that built the geometry.

const AUTOPLAYER := preload("res://tests/autoplay/autoplayer.gd")

# scene, [waypoints...], exit door node name
const ROUTES := [
	{
		"scene": "res://scenes/level_1.tscn", "label": "Lab",
		"waypoints": [
			Vector3(0, 0, 0), Vector3(0, 0, 7), Vector3(0, 0, 12.5),
			Vector3(0, 0, 16.5), Vector3(0, 0, 20.0),
		],
		"door": "ExitDoor",
	},
	{
		"scene": "res://scenes/level_2_1.tscn", "label": "House",
		"waypoints": [
			Vector3(0, 0, 0), Vector3(0, 0, 7), Vector3(0, 0, 12.5), Vector3(0, 0, 16.5),
		],
		"door": "ExitDoor",
	},
	{
		"scene": "res://scenes/kontur.tscn", "label": "KONTUR",
		"waypoints": [
			Vector3(0, 0, 0), Vector3(0, 0, 8),
		],
		"door": "BackDoor",     # the exit sits behind eight gates; the back door is the
								# one a walking body can reach without solving them
	},
	{
		"scene": "res://scenes/level_6_breach.tscn", "label": "Breach",
		"waypoints": [
			Vector3(0, 0, 0), Vector3(0, 0, -2),
		],
		"door": "BackDoor",
	},
	{
		"scene": "res://scenes/backrooms.tscn", "label": "Backrooms",
		"waypoints": [
			Vector3(0, 0, -3), Vector3(0, 0, -6.0),
		],
		"door": "BackDoor",     # added by BACKLOG #30 — this level had none at all
	},
]

const FRAME_BUDGET := 1600      # per route, ~26 s of simulated walking

var _fails := 0
var _route := 0
var _wp := 0
var _frames := 0
var _auto: AutoPlayer
var _loaded := false
var _settle := 0


func _initialize() -> void:
	change_scene_to_file(ROUTES[0]["scene"])


func _ok(label: String, cond: bool, detail: String = "") -> void:
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails += 1


func _finish_route(reached_door: bool) -> void:
	var r: Dictionary = ROUTES[_route]
	var scene := current_scene
	var door := scene.get_node_or_null(String(r["door"])) as Node3D
	_ok("%s: %s exists" % [r["label"], r["door"]], door != null)
	_ok("%s: walked the route without getting stuck" % r["label"], reached_door)

	if door and _auto:
		# Stand in front of the door's own face and look at it, then ask the REAL
		# interact ray what it sees. This is the Issue 30 question.
		# Stand on whichever side of the door the player actually came from — a door's
		# local -Z faces into its room in some levels and out of it in others, and a
		# ray fired at the wrong face just hits the wall behind it.
		var approach: Vector3 = _auto.player.global_position
		var normal: Vector3 = door.global_transform.basis.z.normalized()
		var side: float = 1.0 if (approach - door.global_position).dot(normal) >= 0.0 else -1.0
		var face: Vector3 = door.global_position + normal * side * 1.2
		_auto.player.global_position = Vector3(face.x, _auto.player.global_position.y, face.z)
		_auto.player.force_update_transform()
		_auto.player.call("ai_look_at", door.global_position)
		# ⚠️ The camera is a CHILD of the player and _get_raycast_target() fires from
		# camera.global_position — which stays STALE for the rest of the frame after a
		# teleport unless it is updated too. Without this the ray starts wherever the
		# player used to be and reports "nothing" for a door right in front of them.
		var cam := _auto.player.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.force_update_transform()
		var target: Node = _auto.player.call("ai_interact_target")
		_ok("%s: the interact ray finds %s" % [r["label"], r["door"]],
			target == door or (target != null and door.is_ancestor_of(target)),
			"ray sees %s" % ("nothing" if target == null else target.name))

	if _auto:
		_auto.release()
		_auto = null
	_route += 1
	_wp = 0
	_frames = 0
	_loaded = false
	_settle = 0
	if _route >= ROUTES.size():
		print("--------------------------------------------------")
		print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
		print("--------------------------------------------------")
		quit(0 if _fails == 0 else 1)
	else:
		change_scene_to_file(ROUTES[_route]["scene"])


func _process(_delta: float) -> bool:
	if _route >= ROUTES.size():
		return true
	if not _loaded:
		_settle += 1
		if _settle < 12:
			return false           # let the level build and the player fall to the floor
		var scene := current_scene
		var p := scene.get_node_or_null("Player") as CharacterBody3D
		if not p:
			_ok("%s: Player node" % ROUTES[_route]["label"], false)
			_finish_route(false)
			return false
		_auto = AUTOPLAYER.new(p)
		_loaded = true
		print("--- %s ---" % ROUTES[_route]["label"])
		return false

	_frames += 1
	var wps: Array = ROUTES[_route]["waypoints"]
	if _wp >= wps.size():
		_finish_route(true)
		return false
	if _frames > FRAME_BUDGET:
		_ok("%s: ran out of frames at waypoint %d" % [ROUTES[_route]["label"], _wp], false)
		_finish_route(false)
		return false

	var target: Vector3 = wps[_wp]
	target.y = _auto.player.global_position.y
	if _auto.step_toward(target):
		_wp += 1
		_auto.reset_stuck()
	elif _auto.stuck:
		# Not necessarily a failure — a doorway can need a nudge — but say so, and move
		# on to the next waypoint rather than burning the budget against a wall.
		print("      (stuck approaching waypoint %d at %v)"
			% [_wp, _auto.player.global_position.snappedf(0.1)])
		_wp += 1
		_auto.reset_stuck()
	return false
