extends SceneTree

# Probe the area around the player spawn for blocking colliders. Casts rays
# forward (+z) and sideways at several heights and prints what each hits (name +
# parent + position). Run with a scene arg:
#   Godot --headless --path game --script res://tests/diagnose_entrance.gd -- res://scenes/level_2_1.tscn

var _scene := "res://scenes/level_2_1.tscn"
var _frame := 0
var _player: CharacterBody3D


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 1:
		_scene = a[0]
	change_scene_to_file(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 8:
		return false
	_player = current_scene.get_node_or_null("Player") as CharacterBody3D
	if not _player:
		print("no player")
		quit(1)
		return true
	var origin := _player.global_position
	print("=== spawn ", origin, " forward(-basis.z)=", -_player.global_transform.basis.z)
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state

	# Rays forward (+z) from the spawn at several heights.
	for h in [0.2, 0.6, 1.0, 1.6, 2.2]:
		var from := Vector3(origin.x, h, origin.z)
		var to := Vector3(origin.x, h, origin.z + 6.0)
		_probe("fwd h=%.1f" % h, space, from, to)
	# Rays at the doorway plane offsets to map width.
	for dx in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var from := Vector3(origin.x + dx, 1.0, origin.z)
		var to := Vector3(origin.x + dx, 1.0, origin.z + 6.0)
		_probe("fwd dx=%.1f" % dx, space, from, to)
	# Also probe straight down to confirm the floor is under the spawn.
	_probe("down", space, origin + Vector3(0, 1.0, 0), origin + Vector3(0, -1.0, 0))

	if _scene.contains("level_2"):
		_probe_house_kitchen(space)

	quit(0)
	return true


func _probe_house_kitchen(space: PhysicsDirectSpaceState3D) -> void:
	# Kitchen centre (5,6); cellar key at ~(7, 0.95, 7.6) on a stand.
	print("--- kitchen / key (kitchen center (5,6), key at (7,_,7.6)) ---")
	var key := Vector3(7, 0, 7.6)
	# Floor under the key?
	_probe("key floor", space, key + Vector3(0, 1.5, 0), key + Vector3(0, -1.0, 0))
	# Clearance around the key spot at head height (find surrounding walls).
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		_probe("key clr %v" % d, space, key + Vector3(0, 1.0, 0), key + Vector3(0, 1.0, 0) + d * 3.0)
	# Walk path: from the kitchen doorway (1.5,6) to the key, at body heights.
	for h in [0.3, 0.9, 1.5]:
		_probe("door->key h=%.1f" % h, space, Vector3(2.0, h, 6.0), Vector3(7.0, h, 7.6))
	# Kitchen centre clearance toward the south cellar opening / gate.
	_probe("kitchen->gate", space, Vector3(5.0, 1.0, 6.0), Vector3(5.0, 1.0, 1.0))
	# Is the kitchen floor continuous from doorway to key? sample a few floor points.
	for p in [Vector3(3, 0, 6), Vector3(5, 0, 6), Vector3(7, 0, 6), Vector3(7, 0, 8)]:
		_probe("floor@%v" % p, space, p + Vector3(0, 1.0, 0), p + Vector3(0, -1.0, 0))

	# --- cellar descent (open the gate first so we can test the path) ---
	print("--- cellar descent (ramp x=5; cellar centre (5,-6) floor y=-1.5) ---")
	var gate := current_scene.get_node_or_null("CellarGate") as CSGBox3D
	if gate:
		gate.position.y = 4.6
		gate.use_collision = false
	# Walk the ramp surface: down-probe along x=5 from z=3 to z=-2.4.
	for z in [3.0, 2.0, 1.0, 0.0, -1.0, -2.0]:
		_probe("ramp@z=%.0f" % z, space, Vector3(5, 1.5, z), Vector3(5, -2.5, z))
	# Cellar floor + enclosure.
	_probe("cellar floor", space, Vector3(5, 0.5, -6), Vector3(5, -2.5, -6))
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		_probe("cellar wall %v" % d, space, Vector3(5, -0.4, -6), Vector3(5, -0.4, -6) + d * 5.0)
	# Descent headroom: with the gate open, is the opening at z=3 clear?
	_probe("gate-open clr", space, Vector3(5, 1.5, 4.0), Vector3(5, 1.5, 1.5))


func _probe(label: String, space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [_player.get_rid()]
	var r := space.intersect_ray(q)
	if r.is_empty():
		print("  ", label, " -> clear")
		return
	var c: Object = r.collider
	var nm := "?"
	var parent := "?"
	if c is Node:
		nm = (c as Node).name
		var p := (c as Node).get_parent()
		parent = p.name if p else "<none>"
	var dist := from.distance_to(r.position)
	print("  ", label, " -> ", nm, " (parent ", parent, ") @ ", r.position, " dist=%.2f" % dist)
