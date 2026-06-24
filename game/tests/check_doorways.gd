extends SceneTree

# Cast a ray at head height (y=1.6) straight THROUGH each House doorway along its
# traversal axis. The opening should be clear — if a ray hits a collider inside it,
# a prop/decal is blocking the doorway (the recurring "can't enter the room" bug).
#   Godot --headless --path game --script res://tests/check_doorways.gd

# [x, z, dir("x"|"z"), label]  — mirrors level_2.gd DOORS (room-to-room openings).
const DOORS := [
	[0.0, 3.0, "z", "Entry<->Hallway"],
	[-1.5, 6.0, "x", "Hallway<->LivingRoom"],
	[1.5, 6.0, "x", "Hallway<->Kitchen"],
	[0.0, 11.0, "z", "Hallway<->Landing"],
	[-4.0, 12.5, "x", "Landing<->Bedroom"],
	[4.0, 12.5, "x", "Landing<->Bathroom"],
	[0.0, 14.0, "z", "Landing<->ChildRoom"],
	[5.0, 3.0, "z", "Kitchen<->Cellar"],
]

var _frame := 0
var _player: CharacterBody3D


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_2_1.tscn")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 8:
		return false
	_player = current_scene.get_node_or_null("Player") as CharacterBody3D
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	print("--- doorway clearance @ y=1.6 (BLOCKED = a prop is in the opening) ---")
	for d in DOORS:
		var c := Vector3(d[0], 1.6, d[1])
		var dir: Vector3 = Vector3(0, 0, 1) if d[2] == "z" else Vector3(1, 0, 0)
		var from := c - dir * 1.6
		var to := c + dir * 1.6
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [_player.get_rid()]
		var r := space.intersect_ray(q)
		if r.is_empty():
			print("  OK      %s" % d[3])
		else:
			var n: Object = r.collider
			var nm: String = (n as Node).name if n is Node else "?"
			var hit: Vector3 = r.position
			print("  BLOCKED %s  <- %s @ %v" % [d[3], nm, hit.snappedf(0.01)])
	quit(0)
	return true
