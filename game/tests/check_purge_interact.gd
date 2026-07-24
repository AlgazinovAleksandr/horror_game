extends SceneTree

# Isolated, safe check: does the player's REAL interact raycast (the E-key path,
# not a direct interact() call) actually find the Purge Chamber and the interior
# SlamDoors at all? No creature activity involved — this answers exactly one
# question, cleanly, without any risk of a contact death confounding the result.
#   Godot --headless --path game --script res://tests/check_purge_interact.gd

var _level: Node
var _player: CharacterBody3D
var _purge: Node
var _slam_doors: Array = []
var _phase := 0
var _t := 0.0
var _fails := 0
var _results: Dictionary = {}


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_6_breach.tscn")


func _process(delta: float) -> bool:
	if not _level:
		if not current_scene:
			return false
		_level = current_scene
		_player = _level.get_node_or_null("Player")
		return false

	_t += delta

	match _phase:
		0:
			_purge = _level.get("_purge_chamber")
			var doors: Array = _level.get("_slam_doors")
			if not _purge or doors == null:
				return false
			_slam_doors = doors
			# Face the Purge Chamber from PurgeAnte, well within INTERACT_RANGE (2.5),
			# no creature anywhere near — purely testing the raycast + prompt path.
			_player.global_position = Vector3(0, 0.1, 53.5)
			_player.rotation.y = PI
			_phase = 1
			_t = 0.0

		1:
			if _t < 0.15:
				return false   # let a couple of physics frames resolve _interact_target
			var target = _player.get("_interact_target")
			_results["purge_chamber_targetable"] = target != null and target.has_method("interact")
			if target != null and target.has_method("interact"):
				_player.call("_try_interact")
				print("check: purge chamber interact() fired via real E-press path")
			_phase = 2
			_t = 0.0

		2:
			# interact() should have slammed the door shut (visually + the block
			# collider enabling) even though the creature isn't inside — confirm the
			# call actually went through by checking _used flipped true.
			_results["purge_chamber_used_after_press"] = _purge.get("_used") == true
			_phase = 3
			_t = 0.0
			# Now check a SlamDoor the same way.
			if _slam_doors.size() > 0:
				var door = _slam_doors[0]
				var dpos: Vector3 = door.global_position
				_player.global_position = dpos + Vector3(0, 0.1, 0.3)
				_player.rotation.y = 0.0
				_phase = 4
			else:
				_results["slam_door_exists"] = false
				_phase = 9

		4:
			if _t < 0.15:
				return false
			var door = _slam_doors[0]
			var target = _player.get("_interact_target")
			_results["slam_door_targetable"] = target != null and target.has_method("interact")
			if target != null and target.has_method("interact"):
				_player.call("_try_interact")
				print("check: slam door interact() fired via real E-press path")
			_phase = 5
			_t = 0.0

		5:
			var door = _slam_doors[0]
			_results["slam_door_closed_after_press"] = door.get("_closed") == true
			_phase = 9

		9:
			return _finish()

	return false


func _finish() -> bool:
	print("--------------------------------------------------")
	var all_ok := true
	for key in _results:
		var ok: bool = _results[key]
		all_ok = all_ok and ok
		print("  %-32s %s" % [key, "PASS" if ok else "FAIL"])
	print("RESULT: ", "ALL PASS" if all_ok else "FAILURE")
	print("--------------------------------------------------")
	quit(0 if all_ok else 1)
	return true
