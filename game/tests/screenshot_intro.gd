extends SceneTree

# Dev tool: the Intro Room's opening beat is a TIMED SEQUENCE (darkness -> sit-up
# tween -> switch -> reveal), not a set of static camera spots in an already-lit
# level, so this drives it as a time-based state machine rather than reusing
# screenshot_level.gd's teleport-to-spots list. Also runs a couple of
# physics-proof checks alongside the screenshots (never trust the flipped
# signal alone — see the game-testing skill).
#
# The walk to the switch is deliberately scare-free (the only screamer in the
# whole opening flow is main_menu.gd's cold-open on START) — this script just
# walks the player there and shoots the room, no jolt to wait for.
#
# Usage: Godot --path game --script res://tests/screenshot_intro.gd -- <out_dir>
# Needs a window (not --headless).

var _out := "/tmp/intro_shots/"
var _player: CharacterBody3D
var _room: Node3D

var _t := 0.0
var _state := "wait_ready"
var _walk_steps: Array = []
var _walk_i := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	change_scene_to_file("res://scenes/intro_room.tscn")


func _process(delta: float) -> bool:
	_t += delta

	if not _room:
		_room = current_scene
		if not _room:
			return false
	if not _player:
		_player = _room.get_node_or_null("Player") as CharacterBody3D
		if not _player:
			return false

	match _state:
		"wait_ready":
			if _t > 0.3:
				_capture("01_darkness")
				var door := _room.get_node_or_null("ExitDoor")
				if door and door.get("extra_lock") == true:
					print("CHECK door_locked_before_switch: PASS — extra_lock is true pre-switch")
				else:
					print("CHECK door_locked_before_switch: FAIL — door is walkable before the switch is flipped")
				_t = 0.0
				_state = "wait_wakeup"

		"wait_wakeup":
			# WAKEUP_TWEEN_TIME (1.8s) + a buffer for _on_wakeup_finished() to spawn
			# the path glow / light switch.
			var wakeup_time: float = _room.get("WAKEUP_TWEEN_TIME")
			if _t > wakeup_time + 0.5:
				_prepare_walk()
				_t = 0.0
				_state = "walking"

		"walking":
			if _walk_i < _walk_steps.size():
				if _t > 0.03:
					_t = 0.0
					_player.global_position = _walk_steps[_walk_i]
					_player.velocity = Vector3.ZERO
					_walk_i += 1
			else:
				_capture("02_approaching_switch")
				_t = 0.0
				_state = "flip_switch"

		"flip_switch":
			if _t > 0.2:
				var sw := _find_light_switch()
				if sw and sw.has_method("interact"):
					sw.interact()
				_capture("03_switch_flipped_transition")
				_t = 0.0
				_state = "wait_reveal"

		"wait_reveal":
			if _t > 1.6:
				_suppress_scares()
				_capture("04_room_revealed")
				_run_physics_checks()
				_teleport_table()
				_t = 0.0
				_state = "at_table"

		"at_table":
			if _t > 0.3:
				_capture("05_note_lit_table")
				_player.global_position = Vector3(0.0, 1.6, -6.5)
				_player.velocity = Vector3.ZERO
				_player.rotation.y = PI  # face +Z, back toward the gurneys/beds
				_player.camera.rotation.x = -0.15
				_t = 0.0
				_state = "overview"

		"overview":
			if _t > 0.3:
				_capture("06_room_overview")
				_player.global_position = Vector3(2.2, 1.5, 5.0)
				_player.velocity = Vector3.ZERO
				_player.rotation.y = -PI / 2.0  # face +X toward the new gurney+IV stand
				_player.camera.rotation.x = -0.15
				_t = 0.0
				_state = "closeup"

		"closeup":
			if _t > 0.3:
				_capture("07_gurney_closeup")
				# Body y=0.0 -> eye height ~1.65 (camera's local +1.65 offset from the
				# wake-up tween is still in effect) — the previous version of this shot
				# used body y=1.6, putting the camera near the ceiling and cropping the
				# low wheelchair cutout out of frame.
				_player.global_position = Vector3(2.2, 0.0, -1.5)
				_player.velocity = Vector3.ZERO
				_player.rotation.y = 0.3  # face toward the wheelchair, wall chart beyond it
				_player.camera.rotation.x = -0.25
				_t = 0.0
				_state = "wheelchair_chart"

		"wheelchair_chart":
			if _t > 0.3:
				_capture("08_wheelchair_and_chart")
				var chart_pos: Vector3 = _room.get("WALL_CHART_POS")
				_player.global_position = Vector3(chart_pos.x, 0.0, chart_pos.z + 1.4)
				_player.velocity = Vector3.ZERO
				_player.rotation.y = 0.0  # identity faces -Z, toward the chart
				_player.camera.rotation.x = -0.1
				_t = 0.0
				_state = "wallchart_closeup"

		"wallchart_closeup":
			if _t > 0.3:
				_capture("09_wallchart_closeup")
				var wc_pos: Vector3 = _room.get("WHEELCHAIR_POS")
				_player.global_position = Vector3(wc_pos.x + 1.4, 0.0, wc_pos.z)
				_player.velocity = Vector3.ZERO
				_player.rotation.y = PI / 2.0  # face -X, toward the wheelchair
				_player.camera.rotation.x = -0.1
				_t = 0.0
				_state = "wheelchair_closeup"

		"wheelchair_closeup":
			if _t > 0.3:
				_capture("10_wheelchair_closeup")
				var sw_pos: Vector3 = _room.get("SWITCH_POS")
				_player.global_position = Vector3(sw_pos.x + 1.3, 0.0, sw_pos.z)
				_player.velocity = Vector3.ZERO
				_player.rotation.y = PI / 2.0  # face -X, toward the switch on WallLeft
				_player.camera.rotation.x = -0.1
				_t = 0.0
				_state = "switch_closeup"

		"switch_closeup":
			if _t > 0.3:
				_capture("11_switch_closeup")
				return true

	return false


func _prepare_walk() -> void:
	var gurney: Vector3 = _room.get("GURNEY_POS")
	var switch_pos: Vector3 = _room.get("SWITCH_POS")
	var top_y: float = _room.get("GURNEY_TOP_Y")
	var g0 := Vector2(gurney.x, gurney.z)
	var g1 := Vector2(switch_pos.x, switch_pos.z)
	_walk_steps.clear()
	# Several waypoints toward the switch, not one teleport — matches how a real
	# walk crosses the room, and gives the screenshot a mid-walk vantage point.
	var n := 14
	for i in range(1, n + 1):
		var progress: float = float(i) / float(n) * 0.75  # up to 75% of the way
		var xz := g0.lerp(g1, progress)
		_walk_steps.append(Vector3(xz.x, top_y, xz.y))
	_walk_i = 0


func _teleport_table() -> void:
	var table_pos: Vector3 = _room.get("TABLE_POS")
	_player.global_position = table_pos + Vector3(0, 0.1, 1.6)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = 0.0
	# The table/note sit well below eye height at this range — the level pitch
	# left over from the wake-up tween looks straight over them at the door
	# beyond, not down at the note. Pitch down to actually frame the table.
	_player.camera.rotation.x = -0.6


func _find_light_switch() -> Node:
	for child in _room.get_children():
		if child is LightSwitch:
			return child
	return null


# Same reasoning as screenshot_level.gd: teleporting the camera around during a
# capture run risks a scare firing over the very geometry we came to shoot.
func _suppress_scares() -> void:
	paused = false
	var screamer := root.get_node_or_null("Screamer")
	if screamer:
		screamer.visible = false
		screamer.set("_is_triggering", false)
		screamer.set("_is_flashing", false)
	if _player:
		_player.process_mode = Node.PROCESS_MODE_INHERIT
		if "_panic" in _player:
			_player.set("_panic", 0.0)


func _capture(shot_name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out + shot_name + ".png")
	print("shot: ", shot_name, " @ ", _player.global_position if _player else "no player")


# ---------------------------------------------------------------- physics-proof checks

func _run_physics_checks() -> void:
	_check_switch_reachable()
	_check_path_clear()
	_check_door_unlocked()


func _check_door_unlocked() -> void:
	var door := _room.get_node_or_null("ExitDoor")
	if door and door.get("extra_lock") == false:
		print("CHECK door_unlocked_after_switch: PASS — extra_lock cleared after the switch flip")
	else:
		print("CHECK door_unlocked_after_switch: FAIL — door is still locked after the switch was flipped")


func _check_switch_reachable() -> void:
	var switch_pos: Vector3 = _room.get("SWITCH_POS")
	var sw := _find_light_switch()
	if not sw:
		print("CHECK switch_reachable: FAIL — no LightSwitch node found in the scene")
		return
	var space_state := _player.get_world_3d().direct_space_state
	var origin := switch_pos + Vector3(1.5, 0.0, 0.0)  # 1.5m into the room, facing the wall
	var query := PhysicsRayQueryParameters3D.create(origin, switch_pos)
	var result := space_state.intersect_ray(query)
	if result and result.collider == sw:
		print("CHECK switch_reachable: PASS — raycast from %v hits the LightSwitch" % origin)
	elif result:
		print("CHECK switch_reachable: FAIL — raycast hit %s instead of the switch" % result.collider.name)
	else:
		print("CHECK switch_reachable: FAIL — raycast hit nothing")


func _check_path_clear() -> void:
	var gurney: Vector3 = _room.get("GURNEY_POS")
	var switch_pos: Vector3 = _room.get("SWITCH_POS")
	var top_y: float = _room.get("GURNEY_TOP_Y")
	var g0 := Vector2(gurney.x, gurney.z)
	var g1 := Vector2(switch_pos.x, switch_pos.z)
	var space_state := _player.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.35
	var blocked := 0
	for i in range(1, 10):
		var progress := float(i) / 10.0
		var xz := g0.lerp(g1, progress)
		var pos := Vector3(xz.x, top_y + 0.7, xz.y)  # mid-capsule height along the walk
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = shape
		params.transform = Transform3D(Basis(), pos)
		params.exclude = [_player]
		var hits := space_state.intersect_shape(params, 4)
		if hits.size() > 0:
			blocked += 1
			print("CHECK path_clear: blocked at %v by %s" % [pos, hits[0].collider.name])
	if blocked == 0:
		print("CHECK path_clear: PASS — no blockers along the gurney->switch walk")
	else:
		print("CHECK path_clear: FAIL — %d/9 sample points blocked" % blocked)
