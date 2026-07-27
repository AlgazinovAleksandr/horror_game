extends SceneTree

# KONTUR's roster code must be findable, and only in the Backrooms Flood (BACKLOG #24).
#   Godot --headless --path game --script res://tests/check_flood_notes.gd
#
# Moving the answer out of the intro note and into two notes a level earlier is only
# safe if those notes are actually reachable. Three ways that could silently fail, all
# of which this project has hit before:
#
#   * hung on a wall that carries a DOORWAY, whose collider then seals the room
#     (the Records warning sign — CLAUDE.md's standing rule);
#   * buried IN the wall by too small a wall_point() inset (Issue 11 / Issue 26 — the
#     one-way mirror's figure was invisible for the project's entire life this way);
#   * the digits drifting out of sync with kontur.gd's ROSTER_CODE, so the notes
#     confidently state the wrong answer.
#
# Reachability is asserted with a raycast from inside the room, not by reading a
# position — Issue 14's lesson: a seam whose `is_real` flag was correct sat behind a
# wall and made the level uncompletable.

const ZONE3_ORIGIN := Vector3(-200, 0, 0)
# Room centres from backrooms_zone3.gd's ROOMS table, in zone-local space.
const ROOMS := {
	"WestRun": Vector3(-9, 0, 15),
	"EastRun": Vector3(9, 0, 15),
}

var _frame := 0
var _fails := 0
var _notes: Array[Node3D] = []


func _initialize() -> void:
	change_scene_to_file("res://scenes/backrooms.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails += 1


func _collect(node: Node, script: GDScript) -> void:
	if node.get_script() == script and node is Node3D:
		_notes.append(node as Node3D)
	for c in node.get_children():
		_collect(c, script)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 12:
		return false

	var note_script: GDScript = load("res://scripts/note.gd")
	var zone: Node = null
	for c in current_scene.get_children():
		if c.get_script() == load("res://scripts/backrooms_zone3.gd"):
			zone = c
	_ok("zone 3 (the Flood) is built", zone != null)
	if not zone:
		quit(1)
		return true
	_collect(zone, note_script)
	_ok("exactly 2 notes in the Flood", _notes.size() == 2, "found %d" % _notes.size())

	# --- the digits agree with the lock ---
	var kontur_src := FileAccess.get_file_as_string("res://scripts/kontur.gd")
	var code := ""
	for line in kontur_src.split("\n"):
		if line.begins_with("const ROSTER_CODE"):
			code = line.split('"')[1]
	_ok("read ROSTER_CODE from kontur.gd", code.length() >= 2, "'%s'" % code)
	var combined := ""
	for n in _notes:
		combined += String(n.get("note_text"))
	# Exact phrases, not "does this character appear anywhere" — the notes contain other
	# numbers ("sub-level 2"), so a loose contains() would happily pass on a code whose
	# digits were never actually written down.
	_ok("a note states FIRST digit is %s" % code[0],
		combined.contains("FIRST digit is %s" % code[0]))
	_ok("a note states SECOND digit is %s" % code[1],
		combined.contains("SECOND digit is %s" % code[1]))
	_ok("the notes name KONTUR, so the player can connect them to the gate",
		combined.contains("KONTUR"))

	# --- reachable: a ray from the room centre reaches the note, hitting nothing else
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	var space := player.get_world_3d().direct_space_state
	for n in _notes:
		var pos: Vector3 = n.global_position
		var room_name := ""
		var best := 1e9
		for key in ROOMS:
			var d: float = pos.distance_to(ZONE3_ORIGIN + ROOMS[key])
			if d < best:
				best = d
				room_name = key
		var from: Vector3 = ZONE3_ORIGIN + ROOMS[room_name] + Vector3(0, 1.4, 0)
		var q := PhysicsRayQueryParameters3D.create(from, pos)
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		var hit_node: Object = hit.get("collider") if not hit.is_empty() else null
		_ok("%s is visible from the room centre" % n.name,
			hit_node == n or hit.is_empty(),
			"ray hit %s" % ((hit_node as Node).name if hit_node is Node else "nothing"))

		# Proud of the wall, not sunk into it. Cast OUTWARD from the note, away from the
		# room centre: the wall must be there (so it is on a wall at all) and must be
		# far enough behind to not slice the page (Issue 26 — at inset 0.10 a prop sits
		# exactly on the wall face and z-fights). Measuring distance-from-centre instead
		# is what the first version of this check did, and it silently included the
		# note's 1.4 m HEIGHT in the total, making the number meaningless.
		var outward: Vector3 = pos - (ZONE3_ORIGIN + ROOMS[room_name])
		outward.y = 0.0
		outward = outward.normalized()
		var back := PhysicsRayQueryParameters3D.create(pos, pos + outward * 0.5)
		back.exclude = [player.get_rid(), n.get_rid()]
		back.collision_mask = 1
		var wall := space.intersect_ray(back)
		if wall.is_empty():
			_ok("%s is mounted on a wall" % n.name, false, "no wall within 0.5 m behind it")
		else:
			var gap: float = pos.distance_to(wall.position)
			_ok("%s stands clear of its wall" % n.name, gap > 0.03 and gap < 0.3,
				"%.3f m of clearance" % gap)

	print("--------------------------------------------------")
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	print("--------------------------------------------------")
	quit(0 if _fails == 0 else 1)
	return true
