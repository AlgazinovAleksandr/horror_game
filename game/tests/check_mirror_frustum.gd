extends SceneTree

# The turn mirrors are FRAMED ON THE GLASS: the reflection camera's near-plane window is the
# mirror quad itself, at every distance, from anywhere in the corridor.
#
#   Godot --headless --path game --script res://tests/check_mirror_frustum.gd
#
# WHY THIS EXISTS. `check_turn_mirror.gd`'s own header says a reflection cannot be ASSERTED,
# and stops at the wiring — shared world, layer 20, the proximity gate, one figure per
# mirror. All of that was correct while the picture was still wrong. The FRAMING can be
# asserted, and this is that half.
#
# The defect (capture C1, and C1b when the user re-flagged it unprompted a session later):
# the reflection camera was given the PLAYER's symmetric 75° perspective with `near` pushed
# out to the mirror plane. A symmetric near-plane window is `2*near*tan(fov/2)` tall, and the
# whole of it was stretched onto a 1.95 m quad — so the reflection was MINIFIED by
# window/quad, measured 1.93x at the player's own C1b position and 3.34x at C1's, and the
# factor moved with distance (0.79x at 1 m, 6.30x at 8 m) so the image zoomed as you walked.
#
# HOW IT MEASURES, and why this method rather than reading the constants back. The four
# corners of the glass are `unproject_position`-ed through the REAL camera into the REAL
# SubViewport, and must land on the four corners of that viewport. That goes through Godot's
# own projection matrix and the viewport's own size, so it cannot be satisfied by a test that
# reimplements the arithmetic under test. A mirror that is 1.00x at every distance is the
# only thing that passes it.
#
# ⚠️ It also asserts the NEAR PLANE is still at the mirror plane. That clip is what removes
# the wall the mirror hangs on from its own reflection; without it the glass renders the
# inside of the masonry with a strip of sky over the top, which is what the first screenshot
# of this feature showed. `set_frustum` makes it structural — the window plane IS the near
# plane — but "structural" is a claim, and this is the check.
#
# ⚠️ PROOF IT CAN FAIL, kept permanently rather than performed once by hand: the last stage
# puts the OLD symmetric projection back on the same camera at the same position and requires
# the corners to MISS. If that stage ever passes, this file has stopped measuring anything.

const EYE_DISTS := [1.0, 2.45, 4.25, 8.0]
const LATERAL := [0.0, 0.45, -0.6]
const CORNER_TOL_PX := 2.0
const NEAR_TOL := 0.002
const LEGACY_FOV := 75.0        # what the reflection camera used to inherit from the player

var _frame := 0
var _done := false
var _checks := 0
var _fails: Array[String] = []
var _samples := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/corridor.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _find(node: Node, out: Array) -> void:
	if String(node.name) == "MirrorSurface":
		out.append(node)
	for c in node.get_children():
		_find(c, out)


func _process(_delta: float) -> bool:
	_frame += 1
	if _done:
		return true
	if _frame < 12:
		return false
	_done = true

	var mirrors: Array = []
	_find(current_scene, mirrors)
	# ⚠️ Sample size, and it is read from the level's own table rather than from a literal:
	# the count went 3 -> 2 on 2026-08-16 (the user asked for the first corner and the last
	# one only) and a hard-coded 3 here would have been the only thing that noticed.
	# ⚠️ Via a Variant. A missing const returns null, and assigning null straight into a
	# typed Array is a runtime error that aborts _process before any assertion runs — which
	# in this project is a test that hangs or exits 0 rather than one that goes red.
	var table_v: Variant = current_scene.get_script().get("TURN_MIRRORS")
	var table: Array = table_v if table_v is Array else []
	_ok("the level declares its turn mirrors", table.size() >= 1, "%s" % str(table))
	_ok("every declared turn mirror is a MirrorSurface", mirrors.size() == table.size(),
		"found %d, declared %d" % [mirrors.size(), table.size()])
	if mirrors.is_empty():
		return _finish()

	for m in mirrors:
		_measure(m)

	_ok("enough eye positions were measured",
		_samples >= table.size() * EYE_DISTS.size() * LATERAL.size(),
		"%d measured" % _samples)

	_liveness(mirrors[0])
	_control(mirrors[0])
	return _finish()


# ⭐ THE REFLECTION IS LIVE — the half `check_turn_mirror.gd` could not reach.
#
# User report, 2026-08-16: *"It used to be ... the reflection in the mirror moves, now it is
# static."* The first hypothesis was that the frustum work had left the SubViewport frozen —
# a viewport stuck at UPDATE_ONCE/UPDATE_DISABLED renders one frame and then shows that
# frame forever, which looks EXACTLY like a working mirror in a screenshot and exactly like
# the report in motion. It had not; this is the assertion that keeps it that way.
#
# Three things, all driven by really moving the player rather than by reading a flag back:
#   1. beyond ACTIVE_DIST the viewport is DISABLED (the gate is real);
#   2. inside it, the viewport is ALWAYS (the render is live, every frame);
#   3. moving the eye MOVES the projection, and not moving it does not — the second half is
#      the control, without which "the numbers differ" proves nothing.
func _liveness(m: Node3D) -> void:
	print("  -- liveness: is the glass actually rendering, and does it respond --")
	var quad: MeshInstance3D = m.get_parent() as MeshInstance3D
	var vp: SubViewport = m.get_node("SubViewport") as SubViewport
	var cam: Camera3D = m.get_node("SubViewport/Camera3D") as Camera3D
	var player := current_scene.get_node_or_null("Player") as Node3D
	_ok("liveness: the player is findable", player != null)
	if player == null:
		return
	# MirrorSurface finds the player through the "player" GROUP, not by path.
	_ok("liveness: the player is in the \"player\" group", player.is_in_group("player"))

	var n: Vector3 = quad.global_transform.basis.z.normalized()
	var away: Vector3 = quad.global_position + n * (float(m.get_script().get("ACTIVE_DIST")) + 8.0)
	var near_pos: Vector3 = quad.global_position + n * 2.45

	player.global_position = Vector3(away.x, 0.0, away.z)
	m.call("_process", 0.016)
	_ok("liveness: beyond ACTIVE_DIST the viewport is idle",
		vp.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"mode %d" % vp.render_target_update_mode)

	player.global_position = Vector3(near_pos.x, 0.0, near_pos.z)
	m.call("_process", 0.016)
	_ok("liveness: inside ACTIVE_DIST it renders EVERY frame",
		vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"mode %d" % vp.render_target_update_mode)

	# Does the picture respond to the player moving? Measure the projection of a fixed world
	# point, not the camera transform — the transform could move while the frustum offset
	# cancels it out.
	#
	# ⚠️ THE PROBE POINT IS OFF THE AXIS ON PURPOSE, and the reason is worth keeping. A point
	# on the mirror's own normal is a FIXED POINT of the projection under axial motion: walk
	# straight at the glass and it only rescales, it does not move. Measured with an on-axis
	# probe, walking 0.5 m shifted it by **0.73 px**; the same walk shifts a probe 1.0 m to
	# the side by **14.7 px**. So an on-axis probe would have been a test that reports "the
	# reflection is frozen" on a perfectly live mirror.
	var probe: Vector3 = quad.global_position + n * 7.0 \
		+ quad.global_transform.basis.x.normalized() * 1.0 + Vector3(0, 0.2, 0)
	var eye_a: Vector3 = quad.global_position + n * 2.45 + Vector3(0, 0.15, 0)
	var eye_b: Vector3 = eye_a + n * 0.50                       # half a step back
	var eye_c: Vector3 = eye_a + quad.global_transform.basis.x.normalized() * 0.50

	m.call("_aim", eye_a)
	var p_a: Vector2 = cam.unproject_position(probe)
	m.call("_aim", eye_a)
	var p_a2: Vector2 = cam.unproject_position(probe)
	m.call("_aim", eye_b)
	var p_b: Vector2 = cam.unproject_position(probe)
	m.call("_aim", eye_c)
	var p_c: Vector2 = cam.unproject_position(probe)

	# The control FIRST: aiming twice from the same eye must give the same pixel, or the
	# two assertions below are measuring noise.
	_ok("liveness control: the same eye gives the same picture",
		p_a.distance_to(p_a2) < 0.01, "%.4f px apart" % p_a.distance_to(p_a2))
	_ok("liveness: walking 0.5 m moves the reflection",
		p_a.distance_to(p_b) > 4.0, "%.1f px" % p_a.distance_to(p_b))
	_ok("liveness: strafing 0.5 m moves the reflection",
		p_a.distance_to(p_c) > 4.0, "%.1f px" % p_a.distance_to(p_c))

	# ⚠️ AND THE THING THAT IS *MEANT* TO BE STILL. A mirror is a fixed window: turning your
	# head cannot change what it reflects, and `player.gd:_rotate_camera()` yaws the player
	# about its own Y axis with the camera sitting ON that axis, so the eye does not move at
	# all. This is asserted, not merely commented, because it is the exact behaviour the user
	# reported as "static" and the next person to read that report will be tempted to feed
	# the camera's heading back in — which is what caused capture C1's 3.34x minification.
	player.global_position = Vector3(near_pos.x, 0.0, near_pos.z)
	var cam_node := player.get_node_or_null("Camera3D") as Camera3D
	if cam_node != null:
		var before: Vector3 = cam_node.global_position
		player.rotate_y(deg_to_rad(35.0))
		var after: Vector3 = cam_node.global_position
		player.rotate_y(deg_to_rad(-35.0))
		_ok("liveness: 35 deg of yaw does not move the eye (so the glass must not move)",
			before.distance_to(after) < 0.001, "%.5f m" % before.distance_to(after))


func _measure(m: Node3D) -> void:
	var quad: MeshInstance3D = m.get_parent() as MeshInstance3D
	var cam: Camera3D = m.get_node("SubViewport/Camera3D") as Camera3D
	var vp: SubViewport = m.get_node("SubViewport") as SubViewport
	var size: Vector2 = (quad.mesh as QuadMesh).size
	var name := String(quad.get_parent().get_parent().name) + "@" \
		+ str(quad.global_position.round())

	# The viewport must have the glass's aspect, or the reflection is stretched by exactly
	# the ratio between them — a further 7 % on top of the framing error, at 512x768.
	var vp_aspect: float = float(vp.size.x) / float(vp.size.y)
	var quad_aspect: float = size.x / size.y
	_ok("%s: the SubViewport has the glass's aspect" % name,
		absf(vp_aspect / quad_aspect - 1.0) < 0.01,
		"viewport %.4f vs quad %.4f" % [vp_aspect, quad_aspect])

	var n: Vector3 = quad.global_transform.basis.z.normalized()
	var right: Vector3 = quad.global_transform.basis.x.normalized()

	for d in EYE_DISTS:
		for lat in LATERAL:
			var eye: Vector3 = quad.global_position + n * d + right * lat + Vector3(0, 0.2, 0)
			m.call("_aim", eye)
			_samples += 1

			# 1. The near plane is the mirror plane.
			_ok("%s: near plane is the glass at %.2f m" % [name, d],
				absf(cam.near - d) < NEAR_TOL, "near %.4f vs %.4f" % [cam.near, d])

			# 2. The glass exactly fills the render, at 1.00x.
			var corners := [
				quad.global_transform * Vector3(-size.x / 2.0, -size.y / 2.0, 0),
				quad.global_transform * Vector3(size.x / 2.0, -size.y / 2.0, 0),
				quad.global_transform * Vector3(-size.x / 2.0, size.y / 2.0, 0),
				quad.global_transform * Vector3(size.x / 2.0, size.y / 2.0, 0),
			]
			var worst := _corner_error(cam, vp, corners)
			_ok("%s: the glass fills the render at %.2f m, lat %.2f" % [name, d, lat],
				worst <= CORNER_TOL_PX, "worst corner off by %.2f px" % worst)


# Distance in pixels from each projected quad corner to the nearest viewport corner, worst
# case. Orientation-agnostic on purpose: which corner goes where depends on the camera's
# handedness, and that is the material's UV flip to worry about, not the frustum's.
func _corner_error(cam: Camera3D, vp: SubViewport, corners: Array) -> float:
	var vw := float(vp.size.x)
	var vh := float(vp.size.y)
	var targets := [Vector2(0, 0), Vector2(vw, 0), Vector2(0, vh), Vector2(vw, vh)]
	var worst := 0.0
	for c in corners:
		var p: Vector2 = cam.unproject_position(c)
		var best := INF
		for t in targets:
			best = minf(best, p.distance_to(t))
		worst = maxf(worst, best)
	return worst


# PROOF THE ASSERTION BITES. Put the shipped-and-wrong projection back — the player's
# symmetric 75° perspective with near at the mirror plane — and require the corners to MISS
# by a mile. The printed minification is the same number §1 of the backlog measured by hand.
func _control(m: Node3D) -> void:
	print("  -- positive control: the projection this replaced --")
	var quad: MeshInstance3D = m.get_parent() as MeshInstance3D
	var cam: Camera3D = m.get_node("SubViewport/Camera3D") as Camera3D
	var vp: SubViewport = m.get_node("SubViewport") as SubViewport
	var size: Vector2 = (quad.mesh as QuadMesh).size
	var n: Vector3 = quad.global_transform.basis.z.normalized()

	for d in [2.45, 4.25]:
		var eye: Vector3 = quad.global_position + n * d
		m.call("_aim", eye)
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = LEGACY_FOV
		cam.near = d
		var corners := [
			quad.global_transform * Vector3(-size.x / 2.0, -size.y / 2.0, 0),
			quad.global_transform * Vector3(size.x / 2.0, -size.y / 2.0, 0),
			quad.global_transform * Vector3(-size.x / 2.0, size.y / 2.0, 0),
			quad.global_transform * Vector3(size.x / 2.0, size.y / 2.0, 0),
		]
		var worst := _corner_error(cam, vp, corners)
		var window_h: float = 2.0 * d * tan(deg_to_rad(LEGACY_FOV) / 2.0)
		_ok("control: the old symmetric projection at %.2f m is REJECTED" % d,
			worst > CORNER_TOL_PX,
			"corners off by %.1f px; window %.2f m vs glass %.2f m = %.2fx minification"
				% [worst, window_h, size.y, window_h / size.y])


func _finish() -> bool:
	print("")
	print("%d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		for f in _fails:
			print("  FAIL: " + f)
		print("RESULT: FAIL")
		quit(1)
	return true
