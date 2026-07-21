extends SceneTree

# Dev tool: report what solid geometry occupies a set of world points, so a player
# who gets stuck (or a screenshot that comes back black because the camera is inside
# a prop) can be traced to the actual collider.
# Usage: Godot --headless --path game --script res://tests/check_spawn_blocked.gd -- <scene>

var _scene := "res://scenes/level_2_1.tscn"
var _frame := 0

const POINTS := [
	Vector3(0, 1.6, 12.5), Vector3(-7, 1.6, 12.5),
	Vector3(6.5, 1.6, 12.5), Vector3(0, 1.6, 16.5),
	Vector3(-5, 1.6, 6.0), Vector3(5, 1.6, 6.0),
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_scene = args[0]
	change_scene_to_file(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 25:
		return false
	var space := current_scene.get_viewport().world_3d.direct_space_state
	print("SPAWN-PROBE %s" % _scene)
	for p in POINTS:
		var shape := SphereShape3D.new()
		shape.radius = 0.35
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis(), p)
		q.collide_with_areas = false
		var hits: Array = space.intersect_shape(q, 8)
		var names: Array = []
		for h in hits:
			var c = h.get("collider")
			if c:
				names.append("%s(%s)" % [c.name, c.get_class()])
		print("  %s -> %s" % [p, "CLEAR" if names.is_empty() else ", ".join(names)])
	return true
