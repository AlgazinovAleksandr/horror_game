extends SceneTree

# Structural + walk test for the three-zone Backrooms.
#
# A clean scene load proves nothing here: every zone is built procedurally and the
# failure modes are silent (a wall with no trigger, a real seam that can never be
# promoted, a player who falls through an alcove floor). This drives the actual
# progression and asserts on it.
#
#   Godot --headless --path game --script res://tests/walk_backrooms.gd

var _frame := 0
var _scene: Node
var _player: CharacterBody3D
var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/backrooms.tscn")


func _ok(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS  ", label)
	else:
		print("  FAIL  ", label)
		_fails.append(label)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 8:
		_scene = current_scene
		_player = _scene.get_node_or_null("Player") as CharacterBody3D
		_structure()
	elif _frame == 20:
		_zone2_logic()
	elif _frame == 32:
		_zone3_logic()
	elif _frame == 44:
		_gravity_probe()
	elif _frame == 56:
		_progression()
	elif _frame == 70:
		_solid_walls_block()
	elif _frame == 78:
		_seams_reachable()
	elif _frame == 90:
		_flood_survivable_setup()
	elif _frame == 96:
		_flood_baseline()
	elif _frame == 156:
		_flood_measure()
	elif _frame > 200:
		print("\n%d checks, %d failed" % [_checks, _fails.size()])
		for f in _fails:
			print("   ! ", f)
		quit(1 if _fails.size() > 0 else 0)
		return true
	return false


func _structure() -> void:
	print("\n--- structure ---")
	_ok("player exists", _player != null)
	_ok("player joined 'player' group", _player and _player.is_in_group("player"))

	var z2 := _scene.get_node_or_null("ZoneSprawl")
	var z3 := _scene.get_node_or_null("ZoneFlood")
	_ok("zone 2 built", z2 != null)
	_ok("zone 3 built", z3 != null)

	# The audio bus everything routes through — SilenceZone is a no-op without it.
	_ok("Backrooms audio bus exists", AudioServer.get_bus_index("Backrooms") != -1)

	if z2:
		var walls := 0
		for c in z2.get_children():
			if c is GlitchWall:
				walls += 1
		_ok("zone 2 has 4 glitch walls (got %d)" % walls, walls == 4)
		_ok("zone 2 has a silence pocket",
			z2.get_node_or_null("SilencePocket") != null)
		_ok("zone 2 spawn is inside the hall",
			absf(z2.spawn_point.x - 200.0) < 25.0)

	if z3:
		var seam := z3.get_node_or_null("FloodSeam")
		_ok("zone 3 real seam exists", seam != null)
		_ok("zone 3 seam is flagged real", seam != null and seam.is_real)
		var decoys := 0
		for c in z3.get_children():
			if c is GlitchWall and not c.is_real:
				decoys += 1
		_ok("zone 3 has 2 decoy seams (got %d)" % decoys, decoys == 2)


func _zone2_logic() -> void:
	print("\n--- zone 2: exactly one real wall, always solvable ---")
	var z2 = _scene.get_node_or_null("ZoneSprawl")
	if not z2:
		return

	# Exactly one wall may be real at a time, across many re-randomisations.
	var bad_counts := 0
	for i in range(40):
		z2._randomise_real_wall()
		var real := 0
		for c in z2.get_children():
			if c is GlitchWall and c.is_real:
				real += 1
		if real != 1:
			bad_counts += 1
	_ok("exactly one real wall over 40 rerolls", bad_counts == 0)

	# Out every wall, then reroll: the zone must rescue itself rather than soft-lock.
	for c in z2.get_children():
		if c is GlitchWall:
			c.go_solid()
	z2._randomise_real_wall()
	var reachable := 0
	for c in z2.get_children():
		if c is GlitchWall and c.is_real and not c.is_solid():
			reachable += 1
	_ok("all-walls-outed still leaves a reachable exit", reachable == 1)


func _zone3_logic() -> void:
	print("\n--- zone 3: seam visibility inverts with the flashlight ---")
	var z3 = _scene.get_node_or_null("ZoneFlood")
	if not z3 or not _player:
		return
	var seam: GlitchWall = z3.get_node_or_null("FloodSeam")
	if not seam:
		return

	# Drive the zone's own per-frame logic with the light forced each way.
	_player.global_position = z3.spawn_point
	var flash: SpotLight3D = _player.get_node_or_null("Camera3D/Flashlight")

	if flash:
		flash.visible = true
		z3._process(0.016)
		var real_hidden_when_lit := not seam.visible
		flash.visible = false
		z3._process(0.016)
		var real_shown_when_dark := seam.visible
		_ok("real seam hidden with flashlight ON", real_hidden_when_lit)
		_ok("real seam visible with flashlight OFF", real_shown_when_dark)

		# And the decoys must do the exact opposite, or the inversion isn't a rule.
		var decoy_ok := true
		for c in z3.get_children():
			if c is GlitchWall and not c.is_real and c.visible:
				decoy_ok = false
		_ok("decoys hidden while real seam shows", decoy_ok)


func _progression() -> void:
	# The whole point of the rework: zone 1 must hand off to zone 2, zone 2 to
	# zone 3, and only zone 3 may advance the level. Drive the real signal paths.
	print("\n--- progression ---")
	var z2 = _scene.get_node_or_null("ZoneSprawl")
	var z3 = _scene.get_node_or_null("ZoneFlood")
	if not z2 or not z3 or not _player:
		return

	# Autoload globals aren't bound as identifiers inside a bare SceneTree script,
	# so reach the singleton by path.
	var gs: Node = root.get_node_or_null("/root/GameState")
	if not gs:
		_ok("GameState autoload reachable", false)
		return

	# Zone 1 cleared -> should land in the Sprawl, NOT advance the level.
	var lvl_before: int = gs.current_level
	_scene._counter = 2
	_scene._on_exit_reached(_player)
	_ok("zone 1 exit moves player into the Sprawl",
		_player.global_position.distance_to(z2.spawn_point) < 1.0)
	_ok("zone 1 exit does NOT advance the level",
		gs.current_level == lvl_before)

	# A wrong wall in the Sprawl: costs panic and sends you back to its spawn.
	var panic_before: float = _player.get_panic_ratio()
	_player.global_position = z2.spawn_point + Vector3(5, 0, 5)
	_scene._on_zone_mistake(2)
	_ok("wrong wall returns player to the Sprawl spawn",
		_player.global_position.distance_to(z2.spawn_point) < 1.0)
	_ok("wrong wall costs panic", _player.get_panic_ratio() > panic_before)

	# Real wall in the Sprawl -> the Flood.
	z2.cleared.emit()
	_ok("Sprawl exit moves player into the Flood",
		_player.global_position.distance_to(z3.spawn_point) < 1.0)
	_ok("Sprawl exit does NOT advance the level",
		gs.current_level == lvl_before)


func _solid_walls_block() -> void:
	# REGRESSION (playtest 2026-07-20): go_solid() used to drop the trigger without
	# adding a collider, leaving a 7 m hole in the perimeter with no floor behind
	# it. The player walked through an "outed" wall and fell out of the world.
	# Flag checks can't see this — only a physical query can.
	print("\n--- outed walls are physically solid ---")
	var z2 = _scene.get_node_or_null("ZoneSprawl")
	if not z2:
		return

	var space: PhysicsDirectSpaceState3D = _scene.get_world_3d().direct_space_state
	var walls: Array = []
	for c in z2.get_children():
		if c is GlitchWall:
			walls.append(c)

	for w in walls:
		w.go_solid()
	await process_frame

	var leaks := 0
	for w in walls:
		# Ray from the hall centre outward through the wall. A solid wall must stop it.
		var outward: Vector3 = (w.global_position - z2.global_position)
		outward.y = 0.0
		outward = outward.normalized()
		var from: Vector3 = z2.global_position + Vector3(0, 1.5, 0) + outward * 5.0
		var to: Vector3 = z2.global_position + Vector3(0, 1.5, 0) + outward * 26.0
		var q := PhysicsRayQueryParameters3D.create(from, to)
		if space.intersect_ray(q).is_empty():
			leaks += 1
			print("      LEAK through %s" % w.name)
	_ok("no walk-through gaps once every wall is outed (%d leaks)" % leaks, leaks == 0)

	# And the out-of-world catcher must recover a player who gets past anyway.
	_player.global_position = z2.global_position + Vector3(0, -20.0, 22.0)
	_scene._zone = 2
	_scene._catch_out_of_world()
	_ok("out-of-world catcher returns the player",
		_player.global_position.distance_to(z2.spawn_point) < 1.0)

	for w in walls:
		w.revive()


func _seams_reachable() -> void:
	# REGRESSION (2026-07-21): the Flood's seams were yawed PI "to face the room",
	# which swung their walk-into triggers to the far side of the wall they were
	# mounted on. Every seam rendered correctly and none could be touched — the zone
	# was unwinnable, and the only reachable trigger left in it was a decoy.
	#
	# The existing progression test missed this entirely because it fires `cleared`
	# and `_on_seam_touched()` directly. Wiring was never the problem; geometry was.
	# So ask the physics server, not the object.
	print("\n--- Flood seams are physically reachable ---")
	var z3 = _scene.get_node_or_null("ZoneFlood")
	if not z3:
		return
	var space: PhysicsDirectSpaceState3D = _scene.get_world_3d().direct_space_state
	var unreachable: Array[String] = []
	var seams := 0
	for seam in z3.get_children():
		if not (seam is GlitchWall):
			continue
		seams += 1
		var area: Area3D = seam.get_node_or_null("GlitchTrigger")
		if not area:
			unreachable.append("%s (no trigger)" % seam.name)
			continue
		# Walk in toward the trigger from 2 m further out on the trigger's own side.
		var toward: Vector3 = area.global_position - seam.global_position
		var from: Vector3 = area.global_position + toward.normalized() * 2.0
		from.y = seam.global_position.y
		var q := PhysicsRayQueryParameters3D.create(from, area.global_position)
		if not space.intersect_ray(q).is_empty():
			unreachable.append(seam.name)
	_ok("all 3 Flood seams found (got %d)" % seams, seams == 3)
	_ok("no Flood seam is walled off from the player (%s)"
		% ("none" if unreachable.is_empty() else ", ".join(unreachable)),
		unreachable.is_empty())

	# And the real one must not be the decoy's neighbour on a doorway: a decoy
	# straddling a doorway scores a mistake for merely using the corridor.
	var basin: Vector3 = z3._builder.room_center("Basin")
	var on_doorway := false
	for d in z3._decoys:
		if absf(d.global_position.z - (z3.global_position.z + basin.z + 3.85)) < 0.1 \
				and absf(d.position.x - basin.x) < 1.9:
			on_doorway = true
	_ok("no decoy straddles the Throat doorway", not on_doorway)


var _flood_t0 := 0.0
var _flood_p0 := 0.0

func _flood_survivable_setup() -> void:
	# SURVIVABILITY (playtest 2026-07-20): the Flood's puzzle needs the flashlight
	# OFF, but a blanket DarkZone charged +3/s for exactly that AND suppressed decay
	# (player.gd's panic chain is if/elif). Net +5/s with no way down killed the
	# player in ~1 s, three runs in a row, with the mechanic never attempted.
	# Assert the intended play style is actually survivable long enough to solve.
	print("\n--- the Flood is survivable while solving it ---")
	var z3 = _scene.get_node_or_null("ZoneFlood")
	if not z3 or not _player:
		return
	_ok("Flood has no blanket DarkZone (it would tax the solution)",
		z3.get_node_or_null("FloodDark") == null)
	_player.global_position = z3.spawn_point + Vector3(0, 0, 6.0)
	var flash: SpotLight3D = _player.get_node_or_null("Camera3D/Flashlight")
	if flash:
		flash.visible = false          # the posture the puzzle demands


func _flood_baseline() -> void:
	if not _player:
		return
	_player.set_panic_ratio(0.25)      # what _enter_zone now caps arrivals at
	_flood_p0 = _player.get_panic_ratio()
	_flood_t0 = Time.get_ticks_msec() / 1000.0


func _flood_measure() -> void:
	if not _player:
		return
	var dt: float = maxf(0.001, Time.get_ticks_msec() / 1000.0 - _flood_t0)
	var dp: float = _player.get_panic_ratio() - _flood_p0
	var rate: float = (dp * 50.0) / dt          # panic points per second
	var survival: float = 999.0
	if rate > 0.01:
		survival = ((1.0 - _flood_p0) * 50.0) / rate
	print("      light-off in the Flood: %+.2f panic/s -> ~%.0f s of search time"
		% [rate, survival])
	# 25 s is the floor for "you can cross the wing and check the Sump".
	_ok("searching in the dark gives >90 s of search time and is not frozen (got %.0f s)" % survival,
		survival > 90.0 and rate > 0.05)


func _gravity_probe() -> void:
	# The classic procedural-geometry failure: a floor that isn't there. Drop the
	# player at several points in each new zone and confirm something catches them.
	print("\n--- floor coverage (drop probes) ---")
	var z2 = _scene.get_node_or_null("ZoneSprawl")
	var z3 = _scene.get_node_or_null("ZoneFlood")
	var probes: Array = []
	if z2:
		for p in [Vector3(0, 0, 0), Vector3(14, 0, 14), Vector3(-14, 0, -14),
				Vector3(0, 0, 18), Vector3(18, 0, 0)]:
			probes.append(["sprawl %v" % p, Vector3(200, 0, 0) + p])
	if z3:
		for p in [Vector3(0, 0, 0), Vector3(0, 0, 15), Vector3(-9, 0, 21),
				Vector3(9, 0, 21), Vector3(0, 0, 23)]:
			probes.append(["flood %v" % p, Vector3(-200, 0, 0) + p])

	var space: PhysicsDirectSpaceState3D = _scene.get_world_3d().direct_space_state
	for pr in probes:
		var from: Vector3 = pr[1] + Vector3(0, 2.0, 0)
		var to: Vector3 = pr[1] + Vector3(0, -3.0, 0)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		var hit: Dictionary = space.intersect_ray(q)
		_ok("floor under %s" % pr[0], not hit.is_empty())
