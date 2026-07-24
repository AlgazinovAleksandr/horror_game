extends SceneTree

# Geometry/prop probe for Level 6 — THE BREACH.
#   Godot --headless --path game --script res://tests/check_level6_breach.gd
#
# 1. Doorway clearance @ y=1.6 for every DOORS entry in level_6_breach.gd — the
#    recurring "a prop silently seals the opening" bug class (check_doorways.gd's
#    pattern, reused here).
# 2. Prop counts: exactly 6 HidingSpot, 4 SlamDoor, 1 PurgeChamber.
# 3. A floor exists under the PurgeChamber's configured trap_bounds (catches a
#    future edit that resizes one but not the other).

const DOORS := [
	[0.0, 3.0, "z", "Entry<->Corridor1"],
	[0.0, 11.0, "z", "Corridor1<->Junction1"],
	[-4.0, 14.0, "x", "Junction1<->Records"],
	[0.0, 17.0, "z", "Junction1<->Atrium"],
	[4.0, 21.0, "x", "Atrium<->WardA"],
	[0.0, 27.0, "z", "Atrium<->Junction2"],
	[4.0, 30.0, "x", "WardA<->Junction2"],
	[-4.0, 30.0, "x", "Junction2<->ArchiveA"],
	[0.0, 33.0, "z", "Junction2<->WardB"],
	[-7.0, 34.0, "z", "ArchiveA<->ArchiveB"],
	[-4.0, 37.0, "x", "ArchiveB<->WardB"],
	[0.0, 41.0, "z", "WardB<->WardC"],
	[0.0, 49.0, "z", "WardC<->PurgeAnte"],
	[0.0, 55.0, "z", "PurgeAnte<->Incinerator"],
]

var _frame := 0
var _fails := 0
var _hiding_script: GDScript
var _slam_script: GDScript
var _purge_script: GDScript


func _initialize() -> void:
	# Referencing HidingSpot/SlamDoor/PurgeChamber by static type (`is SlamDoor`) here
	# would force Godot to eagerly compile those scripts before autoloads (GameState)
	# are registered — the "Identifier not found: GameState" trap test_apparition.gd
	# already documents for exactly this reason. Load as plain GDScript resources at
	# runtime instead and compare by script identity (same pattern as player.gd's
	# _find_scary_object).
	_hiding_script = load("res://scripts/hiding_spot.gd")
	_slam_script = load("res://scripts/slam_door.gd")
	_purge_script = load("res://scripts/purge_chamber.gd")
	change_scene_to_file("res://scenes/level_6_breach.tscn")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 8:
		return false

	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	if not player:
		print("FAIL: no Player node found")
		quit(1)
		return true
	var space := player.get_world_3d().direct_space_state

	print("--- doorway clearance @ y=1.6 (BLOCKED = a prop is in the opening) ---")
	for d in DOORS:
		var c := Vector3(d[0], 1.6, d[1])
		var dir: Vector3 = Vector3(0, 0, 1) if d[2] == "z" else Vector3(1, 0, 0)
		var from := c - dir * 1.6
		var to := c + dir * 1.6
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [player.get_rid()]
		# Layer 1 only — SlamDoor/PurgeChamber intentionally sit in 4 of these
		# doorways with an ALWAYS-enabled interact collider on the pass-through
		# layer (2), so E can reach them regardless of open/closed state (see
		# Issue "interact deadlock", 2026-07-24). This check exists to catch a
		# GENUINE physical obstruction, not the intended interactable.
		q.collision_mask = 1
		var r := space.intersect_ray(q)
		if r.is_empty():
			print("  OK      %s" % d[3])
		else:
			var n: Object = r.collider
			var nm: String = (n as Node).name if n is Node else "?"
			var hit: Vector3 = r.position
			print("  BLOCKED %s  <- %s @ %v" % [d[3], nm, hit.snappedf(0.01)])
			_fails += 1

	print("--- prop counts ---")
	var counts := _count_props(current_scene)
	_check("HidingSpot count == 6", counts["hiding"] == 6, "%d" % counts["hiding"])
	_check("SlamDoor count == 4", counts["slam"] == 4, "%d" % counts["slam"])
	_check("PurgeChamber count == 1", counts["purge"] == 1, "%d" % counts["purge"])

	print("--- floor present under the purge chamber's trap bounds ---")
	var probe_from := Vector3(0.0, 1.0, 58.5)
	var probe_to := Vector3(0.0, -1.0, 58.5)
	var q2 := PhysicsRayQueryParameters3D.create(probe_from, probe_to)
	q2.exclude = [player.get_rid()]
	var r2 := space.intersect_ray(q2)
	_check("Incinerator floor present", not r2.is_empty(), "")

	print("--------------------------------------------------")
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	print("--------------------------------------------------")
	quit(0 if _fails == 0 else 1)
	return true


func _check(label: String, cond: bool, detail: String) -> void:
	if cond:
		print("  OK   %s %s" % [label, detail])
	else:
		print("  FAIL %s %s" % [label, detail])
		_fails += 1


func _count_props(node: Node) -> Dictionary:
	var counts := {"hiding": 0, "slam": 0, "purge": 0}
	_walk_count(node, counts)
	return counts


func _walk_count(node: Node, counts: Dictionary) -> void:
	if node.get_script() == _hiding_script:
		counts["hiding"] += 1
	elif node.get_script() == _slam_script:
		counts["slam"] += 1
	elif node.get_script() == _purge_script:
		counts["purge"] += 1
	for child in node.get_children():
		_walk_count(child, counts)
