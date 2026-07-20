extends SceneTree

# KONTUR geometry probe. Two checks, both guarding recurring bug classes in this
# project:
#   1. Every doorway along the spine is CLEAR at head height (Session-11 "a prop on
#      the doorway wall silently seals the room").
#   2. There is solid floor under the whole walking line (Issue 5 void-fall).
#
#   Godot --headless --path game --script res://tests/check_kontur.gd

# [x, z, dir, label] — mirrors kontur.gd DOORS.
const DOORS := [
	[0.0, 4.0, "z", "Landing<->Vestibule"],
	[-2.0, 10.0, "z", "Vestibule<->Passage (west door)"],
	[2.0, 10.0, "z", "Vestibule<->Passage (east door)"],
	[0.0, 20.0, "z", "Passage<->Kitchen"],
	[0.0, 27.0, "z", "Kitchen<->Archive (BARRIER expected)"],
	[0.0, 36.0, "z", "Archive<->Airlock"],
	[0.0, 41.0, "z", "Airlock<->Escort"],
	[0.0, 67.0, "z", "Escort<->Terminus"],
]

const FLOOR_Z_MIN := -3.5
const FLOOR_Z_MAX := 72.5
const FLOOR_STEP := 1.0

var _frame := 0
var _fails := 0
var _stage := 0
var _settle := 0.0


func _initialize() -> void:
	change_scene_to_file("res://scenes/kontur.tscn")


func _process(delta: float) -> bool:
	# Stage 1: the door swing (0.7 s) and barrier dissolve (1.6 s) are tweens, so
	# give them real time to finish before re-probing.
	if _stage == 1:
		_settle += delta
		if _settle < 2.6:
			return false
		_recheck()
		return true

	_frame += 1
	if _frame < 10:
		return false

	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	if not player:
		print("FAIL: no Player in kontur.tscn")
		quit(1)
		return true
	var space := player.get_world_3d().direct_space_state

	print("--- doorway clearance @ y=1.6 (gates still shut) ---")
	for d in DOORS:
		var nm := _probe(space, player, d)
		if nm == "":
			print("  OK        %s" % d[3])
		else:
			# A shut gate is SUPPOSED to seal its doorway; anything else is the
			# "prop blocks the room" bug.
			var is_gate: bool = nm == "FungalBarrier" or nm.begins_with("ChoiceDoor_")
			print("  %s %s  <- %s" % ["GATE(ok)  " if is_gate else "BLOCKED   ", d[3], nm])
			if not is_gate:
				_fails += 1

	print("--- floor coverage along the spine (x=0) ---")
	var z := FLOOR_Z_MIN
	var holes: Array = []
	while z <= FLOOR_Z_MAX:
		var q2 := PhysicsRayQueryParameters3D.create(Vector3(0, 1.0, z), Vector3(0, -1.5, z))
		q2.exclude = [player.get_rid()]
		if space.intersect_ray(q2).is_empty():
			holes.append(z)
		z += FLOOR_STEP
	if holes.is_empty():
		print("  OK      solid floor from z=%.1f to z=%.1f" % [FLOOR_Z_MIN, FLOOR_Z_MAX])
	else:
		print("  HOLES   at z = %s" % str(holes))
		_fails += 1

	# Audio wiring: load_audio() silently returns null for a missing base name, so a
	# typo or a missing AUDIO_SUBDIRS entry is invisible in-game. Assert it here.
	print("--- audio ---")
	var ambient := current_scene.get_node_or_null("AmbientPlayer") as AudioStreamPlayer
	if ambient and ambient.stream:
		print("  OK        ambient bed loaded")
	else:
		print("  FAIL      AmbientPlayer has no stream")
		_fails += 1
	# Autoloads are not registered at compile time inside a SceneTree script, so
	# reach load_audio() (a static func) through the script resource instead.
	var gs: GDScript = load("res://scripts/game_state.gd")
	for base in ["ambient_kontur", "breathing_behind", "door_seal", "acid_hiss",
			"pedestal_alarm", "kontur_flash", "screamer_kontur"]:
		if gs.load_audio(base):
			print("  OK        %s" % base)
		else:
			print("  FAIL      %s did not resolve" % base)
			_fails += 1

	# The win path: open the correct door and dissolve the barrier, then re-probe.
	# This is what proves the level is actually completable, not just well-formed.
	print("--- win path: opening the black door + dissolving the barrier ---")
	var black := _find_by_prefix(current_scene, "ChoiceDoor_Black")
	var barrier := current_scene.get_node_or_null("FungalBarrier")
	if black:
		black.interact()
	else:
		print("  FAIL    no ChoiceDoor_Black in the scene")
		_fails += 1
	if barrier:
		barrier.dissolve()
	else:
		print("  FAIL    no FungalBarrier in the scene")
		_fails += 1
	_stage = 1
	return false


func _recheck() -> void:
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	var space := player.get_world_3d().direct_space_state
	for d in [DOORS[1], DOORS[2], DOORS[4]]:
		var nm := _probe(space, player, d)
		# The red door may legitimately still be shut; only the black door and the
		# dissolved barrier must now be clear.
		var must_be_clear: bool = not d[3].begins_with("Vestibule<->Passage (east")
		if nm == "":
			print("  OK        %s now clear" % d[3])
		elif nm.begins_with("ChoiceDoor_Red"):
			print("  OK        %s still shut (red door — correct)" % d[3])
		else:
			print("  BLOCKED   %s  <- %s" % [d[3], nm])
			if must_be_clear:
				_fails += 1

	print("--- result: %s ---" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


func _probe(space: PhysicsDirectSpaceState3D, player: CharacterBody3D, d: Array) -> String:
	var c := Vector3(d[0], 1.6, d[1])
	var dir: Vector3 = Vector3(0, 0, 1) if d[2] == "z" else Vector3(1, 0, 0)
	var q := PhysicsRayQueryParameters3D.create(c - dir * 1.8, c + dir * 1.8)
	q.exclude = [player.get_rid()]
	var r := space.intersect_ray(q)
	if r.is_empty():
		return ""
	return (r.collider as Node).name if r.collider is Node else "?"


func _find_by_prefix(root: Node, prefix: String) -> Node:
	for child in root.get_children():
		if child.name.begins_with(prefix):
			return child
	return null
