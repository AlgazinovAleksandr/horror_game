extends SceneTree

# Structural test for KONTUR after the depth pass.
#
# Written against the two rules this project learned expensively:
#
#   * ASSERT WITH PHYSICS QUERIES, NOT OBJECT STATE. The Backrooms Flood shipped
#     unwinnable because a seam's `is_real` flag was correct the whole time its
#     trigger sat behind a wall (Issue 14).
#   * NEVER REACH THE WIN CONDITION BY EMITTING THE SIGNAL. walk_backrooms.gd passed
#     for weeks on a level that could not be completed, because it called
#     `cleared.emit()` instead of walking into anything.
#
#   Godot --headless --path game --script res://tests/walk_kontur.gd

var _frame := 0
var _scene: Node
var _player: CharacterBody3D
var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/kontur.tscn")


func _ok(label: String, cond: bool) -> void:
	_checks += 1
	print(("  PASS  " if cond else "  FAIL  ") + label)
	if not cond:
		_fails.append(label)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 8:
		_scene = current_scene
		_player = _scene.get_node_or_null("Player") as CharacterBody3D
		_structure()
	elif _frame == 16:
		_the_void_is_real()
	elif _frame == 24:
		_floor_coverage()
	elif _frame == 32:
		_exit_locks()
	elif _frame == 40:
		_dark_room_inverts()
	elif _frame == 48:
		_signs_not_buried()
	elif _frame == 56:
		_banishment()
	elif _frame == 62:
		_escort_grace()
	elif _frame > 70:
		print("\n%d checks, %d failed" % [_checks, _fails.size()])
		for f in _fails:
			print("   ! ", f)
		quit(1 if _fails.size() > 0 else 0)
		return true
	return false


func _space() -> PhysicsDirectSpaceState3D:
	return _scene.get_world_3d().direct_space_state


# Is there floor under this point? The single most useful question in a procedural level.
func _has_floor(x: float, z: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, 2.0, z), Vector3(x, -3.0, z))
	return not _space().intersect_ray(q).is_empty()


func _structure() -> void:
	print("\n--- structure ---")
	_ok("player exists", _player != null)
	_ok("player is in the 'player' group", _player and _player.is_in_group("player"))
	_ok("exit door built", _scene.get_node_or_null("ExitDoor") != null)
	_ok("roster lock built", _scene.get_node_or_null("RosterLock") != null)
	_ok("switchboard phone built", _scene.get_node_or_null("SwitchboardPhone") != null)
	_ok("airlock zone built", _scene.get_node_or_null("AirlockZone") != null)
	_ok("escort gate built", _scene.get_node_or_null("EscortGate") != null)
	# Eight gates, all starting unpassed.
	_ok("ledger has 8 gates (got %d)" % _scene._gates.size(), _scene._gates.size() == 8)


func _the_void_is_real() -> void:
	# THE POINT OF THE WHOLE CHANGE. The wrong door must open onto nothing. Flags
	# can't show this — only a downward ray can.
	print("\n--- the wrong door is a hole ---")
	var red := _scene.get_node_or_null("ChoiceDoor_Red")
	var black := _scene.get_node_or_null("ChoiceDoor_Black")
	if not red or not black:
		_ok("both choice doors exist", false)
		return

	# The hinge sits half a panel width left of the doorway centre.
	var red_x: float = red.position.x + ChoiceDoor.WIDTH / 2.0
	var black_x: float = black.position.x + ChoiceDoor.WIDTH / 2.0

	# Two paces past the red doorway there must be NO floor...
	_ok("no floor 2 m past the red door", not _has_floor(red_x, 12.0))
	_ok("no floor 2.5 m past the red door", not _has_floor(red_x, 12.5))
	# ...but the entry lip is kept, so you step onto something before it gives way.
	_ok("the red doorway itself still has a lip", _has_floor(red_x, 10.2))
	# ...and the black door must be walkable all the way through to the Passage.
	_ok("floor past the black door", _has_floor(black_x, 12.0))
	_ok("floor through the black antechamber", _has_floor(black_x, 13.0))
	_ok("floor on into the Passage", _has_floor(black_x, 14.5))


func _floor_coverage() -> void:
	# Drop probes per room. The randomised tail (Airlock/Escort/Terminus) moves with
	# _dark_x, so probe where it actually is rather than where it usually is.
	print("\n--- floor coverage ---")
	var dx: float = _scene._dark_x
	var probes := [
		["Landing", 0.0, 0.0], ["Vestibule", 0.0, 7.0], ["Passage", 0.0, 16.5],
		["Kitchen", 0.0, 23.5], ["Records", 0.0, 31.0], ["Archive", 0.0, 39.5],
		["Switchboard", 0.0, 47.5], ["Blackout", 0.0, 55.5],
		["Airlock", dx, 63.0], ["EscortMid", dx, 79.0], ["Terminus", dx, 95.0],
		["Blackout->Airlock seam", dx, 60.0], ["Escort->Terminus seam", dx, 92.0],
	]
	for p in probes:
		_ok("floor in %s" % p[0], _has_floor(p[1], p[2]))


func _exit_locks() -> void:
	# The bug this whole pass exists to fix: the exit had no unlock condition, so the
	# level was completable having failed or skipped every gate.
	print("\n--- the exit actually locks ---")
	var door = _scene.get_node_or_null("ExitDoor")
	if not door:
		return
	_ok("exit is locked while gates are outstanding", door.extra_lock)
	_ok("locked message names the shortfall", door.locked_message.contains("/"))

	# Pass every gate the way the level does, then re-check. Note this drives
	# _pass_gate (the real bookkeeping), not the door's flag directly.
	for k in _scene._gates.keys():
		_scene._pass_gate(k)
	_ok("exit unlocks once all 8 gates pass", not door.extra_lock)

	# And a forfeit must re-seal it, permanently and legibly.
	_scene._forfeit("TEST")
	_ok("forfeit re-locks the exit", door.extra_lock)
	_ok("forfeit says WHY (not just 'LOCKED')", door.locked_message.contains("VOID"))

	# Reset for the remaining checks.
	_scene._forfeited = false
	for k in _scene._gates.keys():
		_scene._gates[k] = false
	_scene._refresh_exit()


func _dark_room_inverts() -> void:
	print("\n--- gate 7: seams invert with the flashlight ---")
	var flash: SpotLight3D = _player.get_node_or_null("Camera3D/Flashlight")
	if not flash or _scene._dark_seams.is_empty():
		_ok("dark seams + flashlight present", false)
		return

	flash.visible = true
	_scene._update_dark_seams()
	var real_hidden := true
	var decoy_shown := true
	for e in _scene._dark_seams:
		if e[1] and e[0].visible:
			real_hidden = false
		if not e[1] and not e[0].visible:
			decoy_shown = false
	_ok("real seam hidden with the light ON", real_hidden)
	_ok("decoys visible with the light ON", decoy_shown)

	flash.visible = false
	_scene._update_dark_seams()
	var real_shown := false
	var decoy_hidden := true
	for e in _scene._dark_seams:
		if e[1] and e[0].visible:
			real_shown = true
		if not e[1] and e[0].visible:
			decoy_hidden = false
	_ok("real seam visible with the light OFF", real_shown)
	_ok("decoys hidden with the light OFF", decoy_hidden)

	# REGRESSION (playtest 2026-07-21, and the Backrooms Flood before it): a room whose
	# answer is "flashlight off" must not also be a DarkZone. DarkZone charges +3/s for
	# the light being off AND suppresses decay (player.gd's if/elif chain), which on top
	# of this level's DreadZone is +5/s with no way down — 45% of the bar in 4 seconds.
	var taxed := false
	for c in _scene.get_children():
		if c is DarkZone and absf(c.position.z - 55.5) < 6.0:
			taxed = true
	_ok("the dark room does not tax the flashlight being off", not taxed)

	# The real seam must actually be a way through, and the decoys must not be.
	var dx: float = _scene._dark_x
	_ok("the real seam has floor beyond it", _has_floor(dx, 61.0))
	for x in [-3.0, 0.0, 3.0]:
		if absf(x - dx) < 0.01:
			continue
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(x, 1.5, 58.0), Vector3(x, 1.5, 61.0))
		_ok("decoy at x=%d is solid wall" % int(x), not _space().intersect_ray(q).is_empty())


func _signs_not_buried() -> void:
	# ISSUES_SOLUTIONS Issue 11: wall_point() measures from the room's NOMINAL
	# boundary, and walls are 0.2 m thick centred on it — so an inset under ~0.11
	# leaves the panel inside the wall, invisible, and nobody notices for a session.
	print("\n--- signs are proud of their walls ---")
	var buried := 0
	var total := 0
	for c in _sign_roots():
		total += 1
		# Cast from inside the room toward the sign; nothing may intervene.
		# The plate is a QuadMesh (faces +z locally) and the root is yawed to aim it
		# into the room, so the room side is +basis.z. Casting from -basis.z starts
		# OUTSIDE the wall and reports every sign as buried.
		var from: Vector3 = c.global_position + c.global_transform.basis.z * 1.2
		var q := PhysicsRayQueryParameters3D.create(from, c.global_position)
		if not _space().intersect_ray(q).is_empty():
			buried += 1
			print("      buried: %s at %v" % [c.name, c.global_position])
	# ⚠️ EXACTLY the eight `_make_sign()` calls. `>= 7` was a floor a stray prop could
	# satisfy — and did: the count read 9 while one of them was a shelf ornament.
	_ok("found the redacted signs (%d)" % total, total == 8)
	_ok("no sign is buried inside its wall (%d buried)" % buried, buried == 0)


# ⚠️ IDENTIFIED BY THEIR ARTWORK, not by a `Label3D` child (2026-08-18). The eight signs
# were engine text over a blank plate until this pass and are now generated printed
# documents (`tools/make_kontur_signs.py`) with the rule and the censor bar STRUCK INTO
# THE IMAGE — so there is no `Label3D` to find, and a collector that looked for one went
# from finding a shelf ornament to finding nothing at all. The texture path is the
# structural fact: it cannot be renamed by a sibling collision (Issue 17) and it is the
# thing that makes the prop a sign.
func _sign_roots() -> Array:
	var out: Array = []
	for c in _scene.get_children():
		if not (c is Node3D):
			continue
		for gc in c.get_children():
			if not (gc is MeshInstance3D and (gc as MeshInstance3D).mesh is QuadMesh):
				continue
			var mat := (gc as MeshInstance3D).get_surface_override_material(0)
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture:
				var path: String = (mat as StandardMaterial3D).albedo_texture.resource_path
				if path.get_file().begins_with("kontur_sign_"):
					out.append(c)
					break
	return out


func _escort_grace() -> void:
	# REGRESSION (playtest 2026-07-21): the player forfeited the entire run 1.5 m into
	# a 26 m corridor, 3 s after entering — before the first temptation stage and
	# before reaching the sign that states the rule. The first look must now WARN.
	print("\n--- gate 4: the first look is free ---")
	var gate = _scene.get_node_or_null("EscortGate")
	if not gate or not _player:
		_ok("escort gate present", false)
		return

	var cam: Camera3D = _player.get_node_or_null("Camera3D")
	if not cam:
		_ok("player camera present", false)
		return

	var broke := [false]
	var warned := [false]
	gate.broken.connect(func() -> void: broke[0] = true)
	gate.warned.connect(func() -> void: warned[0] = true)

	# Stand just inside the corridor mouth and turn right around — the exact thing
	# the lights-out event provokes.
	var entry_z: float = gate.span_start_z + 1.5
	_player.global_position = Vector3(_scene._dark_x, 0.1, entry_z)
	gate._player = _player
	gate._camera = cam
	gate._active = true
	gate._cooldown = 0.0
	cam.global_rotation = Vector3(0, 0, 0)     # facing -z, i.e. straight back
	gate._process(0.016)
	_ok("looking back at the corridor mouth WARNS", warned[0])
	_ok("looking back at the corridor mouth does NOT forfeit", not broke[0])

	# Now walk well past the arming point and do it again: this one must bite.
	warned[0] = false
	broke[0] = false
	var deep_z: float = gate.span_start_z + (gate.span_end_z - gate.span_start_z) * 0.5
	_player.global_position = Vector3(_scene._dark_x, 0.1, deep_z)
	gate._cooldown = 0.0
	gate._process(0.016)
	_ok("looking back deep in the corridor DOES forfeit", broke[0])

	# And the rule must be readable BEFORE the corridor, not inside it.
	var sign_in_airlock := false
	for c in _sign_roots():
		if not String(c.name).contains("escort"):
			continue
		# The Airlock spans z 60..66; the corridor starts at 66.
		sign_in_airlock = c.global_position.z < gate.span_start_z
	_ok("the escort rule is posted before the corridor, not inside it", sign_in_airlock)


func _banishment() -> void:
	# Assert what _banish() SETS, without letting it actually change scene — the flag
	# has to survive reset_level_state(), which is the whole trick.
	print("\n--- banishment state ---")
	var gs: Node = root.get_node_or_null("/root/GameState")
	if not gs:
		_ok("GameState reachable", false)
		return
	gs.kontur_banished = true
	gs.reset_level_state()
	_ok("kontur_banished survives reset_level_state()", gs.kontur_banished)
	gs.kontur_banished = false
