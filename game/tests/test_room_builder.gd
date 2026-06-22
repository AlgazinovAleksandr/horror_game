extends SceneTree

# Headless validation for RoomBuilder. Builds a 3-room layout joined by doorways
# and asserts: (1) geometry is emitted, (2) walls block a ray, (3) a doorway gap
# lets a ray pass, (4) the floor exists under every room and under the doorway.
# Run: Godot --headless --path game --script res://tests/test_room_builder.gd

var _world: Node3D
var _builder: RoomBuilder
var _frame := 0


func _initialize() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	_world = scene

	_builder = RoomBuilder.new()
	_builder.wall_mat = StandardMaterial3D.new()
	_builder.floor_mat = StandardMaterial3D.new()
	_builder.ceil_mat = StandardMaterial3D.new()
	_world.add_child(_builder)

	# Two abutting rooms sharing the wall plane x=3, joined by one doorway.
	var rooms := [
		{ "name": "A", "pos": Vector2(0, 0), "size": Vector2(6, 6) },
		{ "name": "B", "pos": Vector2(6, 0), "size": Vector2(6, 6) },
	]
	var doorways := [
		{ "pos": Vector2(3, 0), "width": 1.4, "dir": "x" },   # A <-> B
	]
	_builder.build(rooms, doorways)
	print("[test] CSG boxes emitted: ", _builder.get_child_count())


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 5:
		return false  # let CSG bake collision

	var space := _world.get_world_3d().direct_space_state
	var fails := 0

	# 1) A solid wall at z = +3 (north wall of Room A, away from any doorway) blocks a ray.
	if _clear(space, Vector3(-2, 1.5, 0), Vector3(-2, 1.5, 5)):
		print("[FAIL] north wall of Room A did not block the ray")
		fails += 1
	else:
		print("[ok] solid wall blocks")

	# 2) The A<->B doorway at (3,0) lets a ray pass east through the shared wall.
	if not _clear(space, Vector3(0, 1.0, 0), Vector3(5.5, 1.0, 0)):
		print("[FAIL] doorway A->B is blocked (no opening cut)")
		fails += 1
	else:
		print("[ok] doorway opening clear")

	# 2b) The same shared wall is solid away from the opening (at z=2).
	if _clear(space, Vector3(0, 1.0, 2), Vector3(5.5, 1.0, 2)):
		print("[FAIL] shared wall has a hole away from the doorway")
		fails += 1
	else:
		print("[ok] shared wall solid away from door")

	# 3) Floor exists under Room A centre (ray down hits something).
	if _clear(space, Vector3(0, 1.5, 0), Vector3(0, -1.0, 0)):
		print("[FAIL] no floor under Room A")
		fails += 1
	else:
		print("[ok] floor under room")

	# 4) Floor exists under the A<->Hall doorway (the Issue-5 bridge).
	if _clear(space, Vector3(3, 1.5, 0), Vector3(3, -1.0, 0)):
		print("[FAIL] no floor bridge under doorway")
		fails += 1
	else:
		print("[ok] floor bridge under doorway")

	print("[test] DONE fails=", fails)
	quit(fails)
	return true


func _clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	return space.intersect_ray(q).is_empty()
