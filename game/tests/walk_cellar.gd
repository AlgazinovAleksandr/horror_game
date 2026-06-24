extends SceneTree

# Walk-test the House cellar descent. Opens the gate, drops the player at the kitchen
# doorway, drives it forward (-z) down the ramp under gravity for a few seconds, and
# reports whether it actually reaches the cellar floor. Also prints up+down headroom
# at points along the ramp so we can see any pinch.
#   Godot --headless --path game --script res://tests/walk_cellar.gd

var _frame := 0
var _player: CharacterBody3D
var _scene: Node
var _min_clear := 999.0
var _min_clear_z := 0.0


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_2_1.tscn")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 6:
		_scene = current_scene
		_player = _scene.get_node_or_null("Player") as CharacterBody3D
		# Force the gate open.
		var gate := _scene.get_node_or_null("CellarGate") as CSGBox3D
		if gate:
			gate.position.y = 5.0
			gate.use_collision = false
		_headroom_scan()
		# Start DOWN in the cellar and climb the ramp back UP toward the kitchen.
		if _player:
			_player.global_position = Vector3(5, -1.3, -4.0)
			_player.rotation.y = PI  # forward = +z (up the ramp)
			print("start ", _player.global_position)
	elif _frame > 8 and _frame < 400:
		# Drive forward (+z) every physics frame.
		if _player:
			_player.velocity.x = 0.0
			_player.velocity.z = 3.0
			_player.velocity.y -= 1.2
			_player.move_and_slide()
			if _frame % 20 == 0:
				print("  t=%d pos=%v" % [_frame, _player.global_position.snappedf(0.01)])
	elif _frame == 400:
		print("final ", _player.global_position.snappedf(0.01))
		var reached: bool = _player.global_position.z > 2.0 and _player.global_position.y > -0.3
		print("CLIMBED OUT: ", reached)
		print("min headroom %.2f at z=%.1f" % [_min_clear, _min_clear_z])
		quit(0)
		return true
	return false


func _headroom_scan() -> void:
	var space := _player.get_world_3d().direct_space_state
	print("--- headroom (floor y .. ceiling y = clearance) along x=5 ---")
	for z in [3.0, 2.5, 2.0, 1.0, 0.0, -1.0, -2.0, -2.5]:
		var floor_y := _cast(space, Vector3(5, 2.5, z), Vector3(5, -3.0, z))
		var ceil_y := _cast(space, Vector3(5, 0.3, z), Vector3(5, 4.0, z))
		if is_nan(floor_y) or is_nan(ceil_y):
			print("  z=%.1f  floor=%s ceil=%s" % [z, str(floor_y), str(ceil_y)])
			continue
		var clear := ceil_y - floor_y
		if clear < _min_clear:
			_min_clear = clear
			_min_clear_z = z
		print("  z=%.1f  floor=%.2f ceil=%.2f  clearance=%.2f" % [z, floor_y, ceil_y, clear])


func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [_player.get_rid()]
	var r := space.intersect_ray(q)
	if r.is_empty():
		return NAN
	return r.position.y
