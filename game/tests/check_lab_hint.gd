extends SceneTree

# Verifies the LEVEL 4 HINT in the Lab: the whiteboard renders (not a black quad —
# the Issue-1 failure mode), the PA line is loadable, and — the important one — the
# Observation room is still ENTERABLE. Hanging a colliding wall panel on a room's
# only doorway wall silently seals it; that bug has bitten this project before.
#
#   Godot --path game --script res://tests/check_lab_hint.gd

const OUT := "/tmp/lab_hint_shots/"

var _frame := 0
var _scene: Node
var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	change_scene_to_file("res://scenes/level_1.tscn")


func _ok(label: String, cond: bool) -> void:
	_checks += 1
	print(("  PASS  " if cond else "  FAIL  ") + label)
	if not cond:
		_fails.append(label)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 10:
		_scene = current_scene
		_checks_run()
	elif _frame == 24:
		_shot("observation_whiteboard")
	elif _frame > 60:
		print("\n%d checks, %d failed" % [_checks, _fails.size()])
		for f in _fails:
			print("   ! ", f)
		quit(1 if _fails.size() > 0 else 0)
		return true
	return false


func _checks_run() -> void:
	print("\n--- lab hint ---")
	_ok("whiteboard texture imported",
		ResourceLoader.exists("res://assets/textures/level_1_lab/lab_whiteboard.png"))
	var gs: Node = root.get_node_or_null("/root/GameState")
	_ok("PA line loadable", gs != null and gs.load_audio("pa_trial4") != null)
	_ok("PA speaker in scene", _scene.get_node_or_null("PASpeaker") != null)

	# ── the spoken hint has to be RECOVERABLE ────────────────────────────────────────
	#
	# The PA line is the clearest statement of the Backrooms glitch-wall rule anywhere in
	# the game, and until 2026-08-16 it existed only as 13 seconds of caption fired once,
	# 1.4 s after the power came back, on top of the "Power restored" objective — and, in
	# the session that produced this item, under a second toast as well. It is not a Note,
	# so it never reached the journal either. Two recoveries now exist and both are checked:
	# a printed copy pinned beside the whiteboard, and an archive entry written the moment
	# the tannoy speaks.
	var pa_text: String = _scene.get_script().get_script_constant_map().get("PA_NOTE_TEXT", "")
	_ok("the level defines a printed PA transcript", pa_text != "")
	var note_script: GDScript = load("res://scripts/note.gd")
	var printed: Node3D = null
	var notes := 0
	for n in _scene.get_children():
		if n.get_script() == note_script:
			notes += 1
			if String(n.note_text) == pa_text:
				printed = n as Node3D
	_ok("found notes to search at all (%d)" % notes, notes >= 5)
	_ok("a printed copy of the PA line hangs in the level", printed != null)
	if printed:
		# Beside the whiteboard, not across the room from it: same wall, within 2.5 m.
		_ok("the printed copy is on Observation's north wall, beside the board",
			printed.global_position.z > 18.5 and absf(printed.global_position.x - 3.75) < 2.5)
	if gs:
		gs.journal.clear()
		_scene._announce_trial_four()
		var archived := false
		for e in gs.journal:
			if String(e.get("text", "")) == pa_text:
				archived = true
		_ok("speaking the PA line archives it for TAB", archived)
		# Reading the printed copy must not then produce a SECOND, identical entry.
		var before: int = gs.journal.size()
		gs.record_note(pa_text, 1)
		print("      journal: %d entries before, %d after re-recording" % [before, gs.journal.size()])
		_ok("the printed copy and the tannoy are one journal entry, not two",
			gs.journal.size() == before)

	# THE DOORWAY CHECK. Observation's only entrance is its WEST wall at (1.5, 17).
	# Sweep a player-sized capsule through that doorway; anything blocking it means
	# the whiteboard (or a lamp) has sealed the room.
	var space: PhysicsDirectSpaceState3D = _scene.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8

	# Probe from y=1.05 so the capsule sits clear of the floor slab (which every
	# point in the room legitimately overlaps) and only reports real obstructions.
	# Walk the doorway centreline from the hallway into the room. Probing off-centre
	# would just clip the door jambs, which are supposed to be solid.
	var blocked := 0
	for x in [0.9, 1.5, 2.1, 2.7]:
		for hit in _probe(space, shape, Vector3(x, 1.05, 17.0)):
			blocked += 1
			print("      doorway x=%.1f blocked by: %s" % [x, hit])
	_ok("Observation doorway passable (%d obstructions)" % blocked, blocked == 0)

	# Standable floor in the room, kept clear of the desk at x≈5.
	var inside := _probe(space, shape, Vector3(3.4, 1.05, 17.6))
	for hit in inside:
		print("      interior blocked by: %s" % hit)
	_ok("Observation interior is clear", inside.is_empty())


func _probe(space: PhysicsDirectSpaceState3D, shape: Shape3D, at: Vector3) -> Array:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), at)
	var names: Array = []
	for r in space.intersect_shape(q, 8):
		var c = r.get("collider")
		if c:
			names.append(str(c.name))
	return names


func _shot(shot_name: String) -> void:
	# Find the board by its texture rather than assuming where it ended up, then
	# stand 2 m in front of it facing its normal.
	var board := _find_board(_scene)
	if not board:
		_ok("whiteboard mesh present in scene", false)
		return
	_ok("whiteboard mesh present in scene", true)
	print("      board at %v" % board.global_position)

	# Stand at the Observation room's centre and look at the board. Deriving the
	# camera side from the panel's own basis puts it through the wall — the quad's
	# front faces into the room, not away from it.
	var room_centre := Vector3(4.0, 0.0, 17.0)
	var to_board: Vector3 = board.global_position - room_centre
	to_board.y = 0.0

	var player: CharacterBody3D = _scene.get_node("Player")
	player.global_position = room_centre
	player.rotation.y = atan2(-to_board.x, -to_board.z)

	# Light it — the room is nearly black, and an unlit albedo panel photographs as
	# nothing, which is indistinguishable from the texture having failed to import.
	var lamp := OmniLight3D.new()
	lamp.light_energy = 4.0
	lamp.omni_range = 7.0
	lamp.position = board.global_position - to_board.normalized() * 1.5 + Vector3(0, 0.4, 0)
	_scene.add_child(lamp)

	# THE BURIAL CHECK. wall_point() measures from the room's nominal boundary, not
	# the wall's inner face, so a panel with too small an inset ends up *inside* the
	# wall and renders as nothing — indistinguishable from a broken texture, and
	# silent. Assert the panel is the first thing you hit looking at it.
	var space2: PhysicsDirectSpaceState3D = _scene.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(
		room_centre + Vector3(0, 1.7, 0),
		board.global_position + to_board.normalized() * 0.5)
	# Exclude the panel's OWN collider — _make_cursed_panel gives it a 0.1 m-deep
	# box, which the ray would otherwise report as "the wall".
	var own_body: Node = board.get_parent()
	if own_body is CollisionObject3D:
		rq.exclude = [(own_body as CollisionObject3D).get_rid()]
	var rh: Dictionary = space2.intersect_ray(rq)
	var wall_z: float = (rh["position"] as Vector3).z if rh.has("position") else 999.0
	print("      board z=%.3f, wall inner face z=%.3f" % [board.global_position.z, wall_z])
	_ok("whiteboard sits proud of the wall (not buried)",
		board.global_position.z < wall_z)

	await process_frame
	await process_frame
	# ⚠️ `--headless` HAS NO RENDER TARGET, so `get_texture()` returns null here and this
	# "screenshot" has never once been written when the suite runs it. It threw
	# `Cannot call method 'save_png' on a null value` every time and nobody saw it, because a
	# GDScript runtime error aborts the call and leaves the exit code alone (Issue 78). The
	# shot is a debugging convenience, not an assertion, so the fix is to say so out loud
	# rather than to pretend: run this file WITHOUT `--headless` if you want the image.
	var tex := root.get_viewport().get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		print("shot: %s SKIPPED (no render target — run this without --headless)" % shot_name)
		return
	img.save_png(OUT + shot_name + ".png")
	print("shot: ", shot_name)


func _find_board(n: Node) -> MeshInstance3D:
	# ⚠️ Guard the surface count first. A MeshInstance3D that dresses itself with
	# `material_override` (the new LabCabinet parts, and most flat-tinted props) has ZERO
	# surface override slots, and asking for slot 0 spams an engine error per node per frame.
	if n is MeshInstance3D and (n as MeshInstance3D).get_surface_override_material_count() > 0:
		var mat := (n as MeshInstance3D).get_surface_override_material(0)
		if mat is StandardMaterial3D and mat.albedo_texture:
			if mat.albedo_texture.resource_path.contains("lab_whiteboard"):
				return n
	for c in n.get_children():
		var found := _find_board(c)
		if found:
			return found
	return null
