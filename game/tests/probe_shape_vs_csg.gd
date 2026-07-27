extends SceneTree

# Throwaway probe: does intersect_shape() report an overlap against the CSG walls for
# a Cylinder as reliably as for a Box? apparition.gd:_fits() passed at a point clearly
# inside the Plant room's north wall, which the test's own Box query then flagged.
#   Godot --headless --path game --script res://tests/probe_shape_vs_csg.gd

const INSIDE_WALL := Vector3(-31.0, 0.0, 14.4)   # Plant north wall face is z=14.4

var _frame := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_1.tscn")


func _try(name_: String, shape: Shape3D, pos: Vector3, space: PhysicsDirectSpaceState3D) -> void:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, pos + Vector3(0, 1.2, 0))
	q.collision_mask = 1
	var hits := space.intersect_shape(q, 8)
	var names: Array[String] = []
	for h in hits:
		var c: Object = h.get("collider")
		if c is Node:
			names.append((c as Node).name)
	print("  %-10s -> %d hits  %s" % [name_, hits.size(), ", ".join(names)])


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 12:
		return false
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	var space := player.get_world_3d().direct_space_state

	var cyl := CylinderShape3D.new()
	cyl.radius = 0.8
	cyl.height = 2.28
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 2.28, 1.6)
	var sph := SphereShape3D.new()
	sph.radius = 0.8

	print("--- at %v (0.8 m inside the Plant north wall) ---" % INSIDE_WALL)
	_try("cylinder", cyl, INSIDE_WALL, space)
	_try("box", box, INSIDE_WALL, space)
	_try("sphere", sph, INSIDE_WALL, space)

	var deep := Vector3(-31.0, 0.0, 14.5)   # dead centre of the wall slab
	print("--- at %v (centre of the wall slab) ---" % deep)
	_try("cylinder", cyl, deep, space)
	_try("box", box, deep, space)
	_try("sphere", sph, deep, space)

	var open := Vector3(-32.5, 0.0, 12.5)   # middle of the Plant room
	print("--- at %v (open floor) ---" % open)
	_try("cylinder", cyl, open, space)
	_try("box", box, open, space)

	# Reproduce the exact failing trial and re-query where the figure actually landed.
	print("--- reproducing: player (-32.5,0.1,12.5) facing 45° ---")
	player.set_physics_process(false)
	player.global_position = Vector3(-32.5, 0.1, 12.5)
	player.rotation.y = deg_to_rad(45.0) + PI
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.rotation.x = 0.0
		cam.force_update_transform()
	player.force_update_transform()
	var appar: Node3D = load("res://scripts/apparition.gd").new()
	current_scene.add_child(appar)
	appar.call("appear")
	if not is_instance_valid(appar) or appar.is_queued_for_deletion():
		print("  aborted (no legible spot)")
	else:
		var p: Vector3 = appar.global_position
		print("  figure landed at %v" % p)
		_try("cylinder@figure", cyl, p, space)
		_try("box@figure", box, p, space)

	quit(0)
	return true
