extends SceneTree

# THE NIGHTMARE is physically completable: spawn -> all seven sconces -> the bed.
#
# This is the only test that can catch a SlamDoor collider spawning inside a jamb,
# or a chamber sealed by its own sconce. check_dungeon_gen.gd proves the LAYOUT is
# sound as data; this proves the GEOMETRY built from it can actually be walked, and
# that the real interact raycast can reach every objective.
#
# ⚠️ It never reaches the win condition by emitting a signal. walk_backrooms.gd
# passed for weeks on an uncompletable level by calling cleared.emit(); the sconces
# here are found by player.ai_interact_target(), i.e. through the shipping raycast,
# can_interact() and prompt path.
#
# Structure: cheap structural + ray checks across many seeds, then a real
# gravity-driven walk on a few. Walking every seed would be minutes of frames for
# information the ray pass already gives.
#
# Usage: Godot --headless --path game --script res://tests/walk_dungeon.gd

const RAY_SEEDS := [101, 202, 303, 404, 505, 606, 707, 808]
const WALK_SEEDS := [101, 404]
# Hard ceiling on the whole walk phase, so a pathological seed can never hang the
# suite the way an unbounded frame loop would.
# Sized from measurement, not intuition: a full route is ~100-120 waypoints and the
# body covers ~1.7 m per 60 IDLE frames at time_scale 1 (idle frames are uncapped in
# headless and run far ahead of the fixed 60 Hz physics tick that actually moves it).
const WALK_FRAME_CAP := 45000
# ⚠️ Generous on purpose. _process() is an IDLE frame and headless idle frames are
# uncapped, so they run far faster than the fixed 60 Hz physics tick that actually
# moves the body — measured at ~1.7 m of travel per 60 idle frames at time_scale 1.
# A budget sized from "frames" intuition rather than from that measurement times out
# mid-corridor and reports a traversable level as broken.
const FRAMES_PER_HOP := 700
const ARRIVE := 1.4
const AUTOPLAYER := preload("res://tests/autoplay/autoplayer.gd")

var _fails := 0
var _checks := 0
var _phase := 0          # index into the seed list being processed
var _mode := 0           # 0 = ray seeds, 1 = walk seeds
var _settle := 0
var _level: Node = null
var _gen = null
var _route: Array = []
var _leg := 0
var _hop_frames := 0
var _auto = null
var _walk_done := 0
var _stalls := 0
var _objectives := 0
var _total_frames := 0
var _capped := false
var _neutralised := 0
var _retry_leg := -1


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails += 1


func _initialize() -> void:
	Engine.time_scale = 6.0
	# ⚠️ The scene is NOT loaded here. _load_seed() has to reach the GameState
	# autoload, and an absolute node path from _initialize() errors with "Can't use
	# get_node() with absolute paths from outside the active scene tree" — the tree
	# is not running yet. First _process frame does it instead.


func _load_seed(s: int) -> void:
	_settle = 0
	_pending_seed = s
	# ⚠️ Pin the seed through the SHIPPING resume path rather than inventing a test
	# hook: dungeon.gd's _roll_seeds() reads the saved snapshot first, exactly so a
	# resumed level rebuilds the same dungeon. Passing only the two seeds leaves
	# every other key at its default (0 sconces, full candles, nothing taught), so
	# this is a fresh run of a KNOWN dungeon — and a red seed is reproducible.
	var gs := root.get_node_or_null("GameState")
	if gs:
		gs.call("save_level_progress", 7, {"layout_seed": s, "content_seed": s * 31 + 7})
	change_scene_to_file("res://scenes/dungeon.tscn")


var _pending_seed := 0
var _started := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_load_seed(RAY_SEEDS[0])
		return false
	_settle += 1
	if _settle < 14:
		return false
	if _level == null:
		_level = current_scene
		if _level == null or not _level.has_method("get_gen"):
			print("  FAIL dungeon.tscn did not load, or dungeon.gd failed to parse")
			_fails += 1
			return _report()
		_gen = _level.call("get_gen")
		# The scene rolls its own seed; force ours so the run is reproducible.
		if _gen == null:
			print("  FAIL level exposed no generator")
			_fails += 1
			return _report()
		if _mode == 0:
			_ray_pass(_pending_seed)
			return _next_seed()
		_begin_walk()
		return false

	if _mode == 1:
		return _tick_walk()
	return false


# ── Ray pass: every doorway is traversable, every sconce is on a solid wall ──────
func _ray_pass(s: int) -> void:
	var space := _level.get_viewport().world_3d.direct_space_state
	var sealed := 0
	var blocked_doors := 0

	# Every doorway must have clear air across it at eye height. This is what
	# catches a SlamDoor's blocker left enabled, or a prop dropped in a jamb.
	# ⚠️ collision_mask = 1 only: SlamDoor deliberately keeps an always-enabled
	# interact collider on layer 2 so E can reach it in either state, and reading
	# that as an obstruction would fail every door in the level.
	for d in _gen.doorways:
		var p: Vector2 = d["pos"]
		var n: Vector3 = Vector3(1, 0, 0) if d["dir"] == "x" else Vector3(0, 0, 1)
		var mid := Vector3(p.x, 1.6, p.y)
		var q := PhysicsRayQueryParameters3D.create(mid - n * 1.7, mid + n * 1.7)
		q.collision_mask = 1
		if not space.intersect_ray(q).is_empty():
			blocked_doors += 1

	# Every sconce must sit on a wall that is NOT a doorway, and must be reachable
	# from inside its own chamber. wall_point() returns the wall CENTRE, which is
	# exactly where a doorway sits — a collider there silently seals the room.
	for spot in _gen.sconce_spots:
		var nm: String = spot["room"]
		if not _gen.free_sides(nm).has(spot["side"]):
			sealed += 1

	_ok("seed %d: no doorway is blocked at eye height" % s,
		blocked_doors == 0, "%d blocked of %d" % [blocked_doors, _gen.doorways.size()])
	_ok("seed %d: no sconce sits on a doorway wall" % s, sealed == 0)
	_ok("seed %d: seven sconces exist in the built scene" % s,
		_level.call("get_sconces").size() == 7,
		"%d built" % _level.call("get_sconces").size())


# ── Walk pass: drive the real player body through the whole objective route ─────
func _begin_walk() -> void:
	var p := _level.get_node_or_null("Player") as CharacterBody3D
	if p == null:
		_ok("player exists", false)
		return
	# The level starts in the Antechamber and the cot transition is a 1.6 s fade,
	# which is UI, not geometry — teleport into the dungeon and test the walk.
	p.global_position = _gen.room_center_world(_gen.spawn_room) + Vector3(0, 0.4, 0)
	p.force_update_transform()
	_neutralise_entities()
	_auto = AUTOPLAYER.new(p)

	# ⚠️ The route is room-by-room WITH THE DOORWAY between each pair inserted.
	# AutoPlayer.step_toward steers in a straight line — it has no pathfinding — and
	# a straight line from one room centre to the next generally runs into a wall,
	# because the doorway is rarely on that line (the sightline pass deliberately
	# moves doorways OFF centre). Aiming at each opening in turn is what makes this
	# a test of whether the level is traversable rather than a test of whether the
	# rooms happen to be collinear.
	_route = []
	var objectives: Array = []
	for s in _gen.sconce_spots:
		objectives.append(s["room"])
	objectives.append(_gen.bed_room)

	var at: String = _gen.spawn_room
	for target in objectives:
		var hops: Array = _gen.path_between(at, target)
		for i in range(1, hops.size()):
			var next_c: Vector3 = _gen.room_center_world(hops[i])
			var door: Vector3 = _gen.doorway_between(hops[i - 1], hops[i])
			if door != Vector3.INF:
				_route.append(door)
				# ⚠️ A COMMIT point 2 m past the opening. ARRIVE is 1.4 m and cannot
				# go below AutoPlayer's own 0.9 m stop distance, so "arrived at the
				# doorway" can still mean standing on the near side of the wall —
				# and the next leg then aims diagonally at a room centre through
				# solid masonry and stalls. Stepping through first is what makes the
				# straight-line steering viable in a room graph.
				var n := next_c - door
				n.y = 0.0
				if n.length() > 0.01:
					_route.append(door + n.normalized() * 2.0)
			_route.append(next_c)
		at = target
	_objectives = objectives.size()
	_leg = 0
	_hop_frames = 0
	_stalls = 0
	_total_frames = 0


# ⚠️ Remove everything that can move, slow or kill the walker before measuring the
# GEOMETRY. This is walk_cellar.gd's precedent, which force-opens the cellar gate
# and disables its colliders for the same reason.
#
# It is not a way of making the test easier — it is what makes it MEAN anything.
# Left in place, a Still One stalks the walker and lunges on contact, and a lunge
# calls Screamer.trigger(), which reloads the scene out from under the test; and a
# beartrap halves the walker's speed for the rest of the route. Both are random per
# run (is_dud is a randf() roll), so the same pinned seed produced 105/105 on one
# run and 85/117 on the next — a test whose result depends on a coin flip cannot
# tell anyone whether the level is traversable.
#
# Entity BEHAVIOUR is covered where it belongs: check_dungeon_entities.gd for the
# §B10 placement rules, test_creature_object12.gd for the Matron's state machine.
func _neutralise_entities() -> void:
	var removed := 0
	for child in _level.get_children():
		var n: String = child.name
		if n.begins_with("StillOne_") or n.begins_with("Trap_") \
				or n == "TheChild" or n == "TheMatron" or n == "TheHollowOne" \
				or n == "TheKneelingMan":
			_level.remove_child(child)
			child.queue_free()
			removed += 1
	_neutralised = removed


func _tick_walk() -> bool:
	if _auto == null or _leg >= _route.size():
		return _finish_walk()
	_total_frames += 1
	if _total_frames > WALK_FRAME_CAP:
		_capped = true
		return _finish_walk()

	var target: Vector3 = _route[_leg]
	var p: CharacterBody3D = _auto.player
	var flat := Vector2(target.x - p.global_position.x, target.z - p.global_position.z)

	if flat.length() <= ARRIVE:
		_leg += 1
		_hop_frames = 0
		_auto.reset_stuck()
		return false

	_auto.step_toward(target)
	_hop_frames += 1
	if _hop_frames > FRAMES_PER_HOP:
		# ⚠️ ONE RETRY, by backing up to the previous waypoint first.
		# AutoPlayer steers in a straight line with no pathfinding, so it can wedge
		# itself on a door jamb or an inside corner and push into it forever. Backing
		# out and re-approaching clears that, and it is the difference between a test
		# that reports the LEVEL as broken and one that reports its own steering as
		# imperfect: measured, the same pinned seed stalled 2 legs on one run and 0
		# on the next with nothing about the level changed.
		# A leg that fails twice is a real finding and is counted as a stall.
		if _retry_leg != _leg:
			_retry_leg = _leg
			_leg = maxi(0, _leg - 1)
			_hop_frames = 0
			_auto.reset_stuck()
			return false
		_stalls += 1
		_leg += 1
		_hop_frames = 0
		_auto.reset_stuck()
	return false


func _finish_walk() -> bool:
	# Every waypoint is a doorway or a room centre on the BFS route through the
	# whole objective chain, so "walked the route" means the level is traversable
	# from the spawn to all seven sconces to the bed under gravity.
	# ⚠️ The cap is a HANG GUARD, not a result. The first version failed the seed
	# whenever the cap was reached even if every waypoint had already been walked,
	# which reported a completed 117/117 route as broken. What is being asserted is
	# "the route was completed with no leg timing out"; the cap only matters when it
	# stopped us short.
	var completed: bool = _leg >= _route.size()
	var reached: int = _leg - _stalls
	_ok("seed %d: walked %d/%d waypoints (%d objectives) under gravity" % [
		_pending_seed, reached, _route.size(), _objectives],
		_stalls == 0 and completed,
		("stopped at the frame cap; " if (_capped and not completed) else "")
		+ "%d legs timed out, %d entities removed first" % [_stalls, _neutralised])

	# The real interact path: teleport to each sconce's face and assert the shipping
	# raycast finds it. This is the Issue-30 question — is it REACHABLE — which
	# nothing was asking until autoplay_exit_reachable.gd started asking it.
	var found := 0
	var sconces: Array = _level.call("get_sconces")
	var p: CharacterBody3D = _auto.player
	var cam := p.get_node_or_null("Camera3D") as Camera3D
	for s in sconces:
		if not is_instance_valid(s):
			continue
		var normal: Vector3 = s.global_transform.basis.z.normalized()
		p.global_position = s.global_position + normal * 1.1 - Vector3(0, 0.9, 0)
		p.force_update_transform()
		p.call("ai_look_at", s.global_position)
		if cam:
			# ⚠️ The camera is a CHILD of the player and its global transform stays
			# stale for the rest of the frame after a teleport — without this the
			# ray reports "nothing" for a prop directly in front of it.
			cam.force_update_transform()
		var t: Node = p.call("ai_interact_target")
		if t == s or (t != null and s.is_ancestor_of(t)):
			found += 1
	_ok("seed %d: the interact ray finds %d/%d sconces" % [_pending_seed, found, sconces.size()],
		found == sconces.size())

	if _auto:
		_auto.release()
		_auto = null
	_walk_done += 1
	return _next_seed()


func _next_seed() -> bool:
	_level = null
	_gen = null
	if _mode == 0:
		var i: int = RAY_SEEDS.find(_pending_seed)
		if i + 1 < RAY_SEEDS.size():
			_load_seed(RAY_SEEDS[i + 1])
			return false
		_mode = 1
		_load_seed(WALK_SEEDS[0])
		return false
	var j: int = WALK_SEEDS.find(_pending_seed)
	if j + 1 < WALK_SEEDS.size():
		_load_seed(WALK_SEEDS[j + 1])
		return false
	return _report()


func _report() -> bool:
	# ⚠️ Sample-size assertion: a dungeon.gd that fails to parse makes every probe
	# short-circuit, and without this the run would report a tidy PASS having
	# asserted nothing at all.
	if _checks < RAY_SEEDS.size() * 3:
		print("  FAIL only %d checks ran — did dungeon.gd fail to load?" % _checks)
		_fails += 1
	print("  %d checks, %d failed" % [_checks, _fails])
	print("--------------------------------------------------")
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	print("--------------------------------------------------")
	quit(0 if _fails == 0 else 1)
	return true
