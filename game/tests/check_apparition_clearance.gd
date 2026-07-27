extends SceneTree

# The apparition must never materialise inside the level geometry (BACKLOG #8:
# "sometimes the monster appears in the textures") — and it must still actually appear.
#   Godot --headless --path game --script res://tests/check_apparition_clearance.gd
#
# The old appear() cast ONE zero-width ray from eye height and then clamped:
#     dist = clampf(hit_distance - WALL_MARGIN, MIN_DIST, APPEAR_DIST)
# so a wall closer than MIN_DIST + WALL_MARGIN (2.1 m) was simply ignored — facing a
# wall 1.0 m away placed the figure at 1.6 m, a clear 0.6 m INSIDE it. And a 1.6 m wide
# billboard was being sited on the strength of a line with no width, so door jambs and
# pillars sliced it even when the centre line was clear.
#
# Two passes, because the obvious fix ("refuse to spawn unless it fits") trades one bug
# for a worse one — an apparition that quietly never appears:
#
#   WALL pass    — the player is shoved up against a wall and turned to FACE it, from
#                  many rooms and many headings. Adversarial. Aborting is fine here;
#                  spawning inside geometry is not.
#   CENTRE pass  — the player stands in the middle of a room, the ordinary case. Here
#                  an abort is a REGRESSION, so the abort rate is asserted.
#
# Assertions are physics queries against the built world, never object state: the old
# code's own numbers were perfectly self-consistent, they just described a point inside
# a wall.

# Taken from level_1.gd's ROOMS table — the tight corridors and small dead-end rooms of
# the dark wing are where this was worst.
# [room name, centre, size] straight out of level_1.gd's ROOMS table.
const SPOTS := [
	["Reception",     Vector3(0, 0.1, 0),        Vector2(6, 6)],
	["MainHall1",     Vector3(0, 0.1, 7),        Vector2(3, 8)],
	["Exam1",         Vector3(-4, 0.1, 7),       Vector2(5, 5)],
	["CrossHall",     Vector3(0, 0.1, 12.5),     Vector2(12, 3)],
	["Records",       Vector3(-9, 0.1, 12.5),    Vector2(6, 6)],
	["ExitVestibule", Vector3(0, 0.1, 20.5),     Vector2(4, 3)],
	["DarkCorridor",  Vector3(-15.5, 0.1, 12.5), Vector2(7, 2.2)],
	["Junction",      Vector3(-21, 0.1, 12.5),   Vector2(4, 4)],
	["Plant",         Vector3(-32.5, 0.1, 12.5), Vector2(5, 4)],
	["SouthSpur",     Vector3(-21, 0.1, 8.5),    Vector2(2.4, 4)],
	["BreakerNook",   Vector3(-34, 0.1, 7.7),    Vector2(6, 4)],
]

# A room can hold an apparition only if, from its centre, there is somewhere at least
# MIN_DIST away that still leaves the figure its own radius clear of the wall. Derived
# from apparition.gd's own constants and the room's size — NOT from what the run
# happened to produce, or the assertion would just ratify whatever the code does.
const APPAR_MIN_DIST := 1.6
const APPAR_FIT_RADIUS := 0.9
const WALL_HALF_THICK := 0.1
const HEADINGS := 8
const WALL_STANDOFF := 0.55   # how close to the wall the WALL pass shoves the player
# The quad's real rendered footprint: 1.6 x 2.4, thin. Modelled here as an oriented box
# in the billboard's own plane (perpendicular to the view direction) — deliberately a
# DIFFERENT shape from the conservative cylinder appear() reserves, so this checks the
# outcome rather than restating the implementation.
const FIG_SIZE := Vector3(1.6, 2.28, 0.25)
const FIG_LIFT := 0.06
# ⚠️ Asserted PER ROOM, not as a global rate. Some of these rooms are 2.2 m corridors,
# where only the two along-corridor headings can possibly hold a 1.6 m wide figure — a
# global abort rate there is a measure of the level's geometry, not of this code. The
# property that actually matters is "wherever the player is standing, there is SOME
# direction the apparition can use", so that the director's next attempt succeeds.
const MIN_SPAWNS_PER_ROOM := 3

var _frame := 0
var _fails := 0
var _checks := 0
var _aborts := 0
var _open_spawns := {}   # spot index -> how many of the HEADINGS produced a figure
var _scene: Node
var _player: CharacterBody3D
var _camera: Camera3D
var _appar_script: GDScript
var _trials: Array = []
var _ti := 0


func _initialize() -> void:
	_appar_script = load("res://scripts/apparition.gd")
	change_scene_to_file("res://scenes/level_1.tscn")


func _fail(msg: String) -> void:
	_fails += 1
	print("  FAIL ", msg)


# ⚠️ Without this the suite reports a cheerful "0 spawns checked … RESULT: PASS" when
# apparition.gd fails to COMPILE — every `_appar_script.new()` returns null, every
# trial short-circuits, and nothing is asserted. A green run on zero samples is the
# most dangerous result a test can give. (Hit for real while writing this file.)
func _assert_sampled() -> void:
	if _checks + _aborts < _trials.size():
		_fail("only %d/%d trials produced an apparition — did apparition.gd fail to load?"
			% [_checks + _aborts, _trials.size()])
	if _checks == 0:
		_fail("no apparition ever spawned — nothing was actually asserted")


# Largest distance from the room centre at which the figure still clears every wall.
func _room_reach(size: Vector2) -> float:
	var hx: float = size.x * 0.5 - WALL_HALF_THICK - APPAR_FIT_RADIUS
	var hz: float = size.y * 0.5 - WALL_HALF_THICK - APPAR_FIT_RADIUS
	return Vector2(maxf(hx, 0.0), maxf(hz, 0.0)).length()


func _assert_still_appears() -> void:
	print("--- standing in the open: headings that produced a figure ---")
	for i in SPOTS.size():
		var room_name: String = SPOTS[i][0]
		var size: Vector2 = SPOTS[i][2]
		var reach := _room_reach(size)
		var roomy := reach >= APPAR_MIN_DIST
		var n: int = _open_spawns.get(i, 0)
		var label := "%-14s %d/%d  (reach %.2f m, needs %.2f)" % [
			room_name, n, HEADINGS, reach, APPAR_MIN_DIST]
		if roomy and n < MIN_SPAWNS_PER_ROOM:
			_fail(label + " — big enough to hold a figure, but it hardly ever appears")
		elif roomy:
			print("  OK   " + label)
		else:
			print("  --   " + label + "  [too small for a 1.6 m figure — exempt]")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 12:
		return false
	if _scene == null:
		_scene = current_scene
		_player = _scene.get_node_or_null("Player") as CharacterBody3D
		if not _player:
			print("FAIL: no Player")
			quit(1)
			return true
		_camera = _player.get_node_or_null("Camera3D") as Camera3D
		# The player is a physics body; freezing it stops gravity/depenetration undoing
		# a teleport between the placement frame and the spawn frame.
		_player.set_physics_process(false)
		for i in SPOTS.size():
			for h in range(HEADINGS):
				var yaw := TAU * float(h) / float(HEADINGS)
				_trials.append([SPOTS[i][1], yaw, true, i])    # WALL pass
				_trials.append([SPOTS[i][1], yaw, false, i])   # CENTRE pass
		print("--- %d placements (half shoved against a wall, half in the open) ---"
			% _trials.size())
		return false

	if _ti >= _trials.size():
		_assert_sampled()
		_assert_still_appears()
		print("--------------------------------------------------")
		print("%d spawns checked, %d aborted (no legible spot), %d failed"
			% [_checks, _aborts, _fails])
		print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
		print("--------------------------------------------------")
		quit(0 if _fails == 0 else 1)
		return true

	_run_trial(_trials[_ti])
	_ti += 1
	return false


func _run_trial(trial: Array) -> void:
	var origin: Vector3 = trial[0]
	var yaw: float = trial[1]
	var against_wall: bool = trial[2]
	var spot_index: int = trial[3]
	var dir := Vector3(sin(yaw), 0.0, cos(yaw))
	var space := _player.get_world_3d().direct_space_state

	var stand := origin
	if against_wall:
		# Find the wall this heading runs into and stand just short of it, facing it —
		# the exact geometry the old clamp mishandled.
		var eye := origin + Vector3(0, 1.2, 0)
		var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * 12.0)
		q.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			stand = origin + dir * maxf(eye.distance_to(hit.position) - WALL_STANDOFF, 0.0)

	_player.global_position = stand
	_player.rotation.y = yaw + PI    # player forward is -Z, so face +dir
	if _camera:
		_camera.rotation.x = 0.0
	_player.force_update_transform()
	if _camera:
		_camera.force_update_transform()

	var appar: Node3D = _appar_script.new()
	_scene.add_child(appar)
	appar.call("appear")

	if not is_instance_valid(appar) or appar.is_queued_for_deletion():
		_aborts += 1   # legitimately refused to spawn — see the header
		return

	_checks += 1
	if not against_wall:
		_open_spawns[spot_index] = int(_open_spawns.get(spot_index, 0)) + 1
	var pos: Vector3 = appar.global_position
	var label := "%s at %v facing %.0f° -> figure %v" % [
		"wall" if against_wall else "open", stand.snappedf(0.1), rad_to_deg(yaw),
		pos.snappedf(0.1)]

	# THE assertion: the quad, oriented as it will actually be drawn (facing the
	# player), must not intersect solid world geometry.
	var view := pos - _player.global_position
	view.y = 0.0
	var billboard_yaw := atan2(view.x, view.z) if view.length() > 0.01 else yaw
	var box := BoxShape3D.new()
	box.size = FIG_SIZE
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = box
	sq.transform = Transform3D(Basis(Vector3.UP, billboard_yaw),
		pos + Vector3(0, FIG_LIFT + FIG_SIZE.y * 0.5, 0))
	sq.exclude = [_player.get_rid()]
	sq.collision_mask = 1     # solid world only, not layer-2 interactables
	var solid: Array[String] = []
	for o in space.intersect_shape(sq, 8):
		var c: Object = o.get("collider")
		if c is Node and c != appar:
			solid.append((c as Node).name)
	if not solid.is_empty():
		_fail("figure intersects %s — %s" % [", ".join(solid), label])

	# And it must actually be visible from the player: nothing solid in between.
	var q2 := PhysicsRayQueryParameters3D.create(
		_player.global_position + Vector3(0, 1.2, 0), pos + Vector3(0, 1.2, 0))
	q2.exclude = [_player.get_rid()]
	q2.collision_mask = 1
	var block := space.intersect_ray(q2)
	if not block.is_empty():
		var bn: Object = block.get("collider")
		_fail("wall %s between player and figure — %s"
			% [(bn as Node).name if bn is Node else "?", label])

	appar.queue_free()
