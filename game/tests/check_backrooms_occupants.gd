extends SceneTree

# The Sprawl's Congregation and the Flood's unseen wader.
#
# The most important assertions here are NEGATIVE ones, because both features are defined by
# what they do not do:
#
#   * **The Congregation has no rules.** No ScaryObject ancestor (so no gaze panic), no
#     collider, no kill radius. If any of that crept in it would become a second
#     observation-dependent creature, which SCARY.md §8.3 bans outright — and it would
#     destabilise the Sprawl's tuned 12-panic mistake cost.
#   * **A figure never relocates while it can be seen**, and never while it is close enough
#     to be studied. Either would turn an anomaly into a visible teleport.
#   * **AND IT NEVER LANDS SOMEWHERE YOU CAN SEE.** ⚠️ This half was missing, in the code and
#     in this file, until 2026-08-17. `_process` gated the SOURCE and `_pick_spot()` asked
#     nothing at all about the player's view, so measured over a 90 s circuit of the Sprawl:
#     633 relocations, 20.0 m each, **65 of them landing inside the player's view cone with
#     line of sight** — one in ten a figure materialising on screen. That is a straight
#     violation of the contract CLAUDE.md cites as the reason the feature is legal, and the
#     assertion below ("a watched figure does not move") measured only the half that was
#     already right. `_congregation_audit()` is the missing half.
#   * **And a figure stays put long enough to be REMEMBERED.** One that has teleported five
#     times since you last looked cannot support "there was one by that pillar", which is the
#     entire product.
#   * **The wader is never rendered.** No mesh, no collider, no ScaryObject: SCARY.md P10's
#     entire point is a threat that cannot be caught clipping through a wall.
#   * **The wader stops when the player stops** — after a couple of strides, not instantly.
#   * **Standing still in the Sprawl is free.** Its tell is a SOUND you have to stop and
#     localise, and `enable_standstill_panic()` is armed level-wide, so the zone used to tax
#     the exact posture its own puzzle demands (Issue 18).
#
#   Godot --headless --path game --script res://tests/check_backrooms_occupants.gd

const SPRAWL_ORIGIN := Vector3(200, 0, 0)
const FLOOD_ORIGIN := Vector3(-200, 0, 0)

var _t := 0.0
var _stage := 0
var _stage_at := 0.0
var _fails: Array[String] = []
var _checks := 0
var _scene: Node = null
var _player: CharacterBody3D = null
var _cong: Node = null
var _wader: Node = null
var _watched: Node3D = null
var _watched_pos := Vector3.ZERO


func _initialize() -> void:
	change_scene_to_file("res://scenes/backrooms.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _find(node: Node, cls: String) -> Node:
	if node.get_class() == cls or (node.get_script() and \
			String(node.get_script().get_global_name()) == cls):
		return node
	for c in node.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null


func _has_ancestor_scary(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if p.get_script() and String(p.get_script().get_global_name()) == "ScaryObject":
			return true
		p = p.get_parent()
	return false


func _advance(next: int) -> void:
	_stage = next
	_stage_at = _t


func _process(delta: float) -> bool:
	_t += delta

	if _stage == 0 and _t > 1.2:
		_scene = current_scene
		_player = _scene.get_node_or_null("Player") as CharacterBody3D
		_ok("player found", _player != null)
		if not _player:
			quit(1)
			return true
		# Both later zones are built at _ready(); jump straight into the Sprawl.
		_scene.call("_enter_zone", 2)
		_advance(1)

	elif _stage == 1 and _t - _stage_at > 0.6:
		_cong = _find(_scene, "Congregation")
		_ok("the Congregation exists in the Sprawl", _cong != null)
		if not _cong:
			_finish()
			return true
		var n: int = int(_cong.call("figure_count"))
		_ok("it starts with a field of figures", n >= 5, "%d figures" % n)

		# --- the negative assertions --------------------------------------------------
		var bad_scary := 0
		var bad_collider := 0
		for f in _cong.get_children():
			if not (f is Node3D):
				continue
			if _has_ancestor_scary(f):
				bad_scary += 1
			if _find(f, "CollisionShape3D") != null:
				bad_collider += 1
		_ok("no figure feeds gaze panic (no ScaryObject ancestor)", bad_scary == 0,
			"%d offenders" % bad_scary)
		_ok("no figure has a collider", bad_collider == 0, "%d offenders" % bad_collider)
		_figure_is_a_silhouette()

		# Standing still in the Sprawl must be free.
		_ok("standstill panic is suspended in the Sprawl",
			bool(_player.get("_standstill_suspended")))

		# A mistake adds one more of them, at no panic.
		var before_n: int = int(_cong.call("figure_count"))
		var before_p: float = _player.get_panic_ratio()
		_cong.call("add_one")
		_ok("a mistake can add another figure",
			int(_cong.call("figure_count")) == before_n + 1,
			"%d -> %d" % [before_n, int(_cong.call("figure_count"))])
		_ok("and adding one costs no panic",
			is_equal_approx(_player.get_panic_ratio(), before_p))

		# --- it must not move while watched ------------------------------------------
		# Stand right next to a figure and look at it.
		for f in _cong.get_children():
			if f is Node3D:
				_watched = f
				break
		if _watched:
			_player.global_position = _watched.global_position + Vector3(0, 0.1, -3.0)
			var cam := _player.get_node("Camera3D") as Camera3D
			cam.look_at(_watched.global_position + Vector3(0, 1.2, 0), Vector3.UP)
			_watched_pos = _watched.global_position
		_advance(2)

	elif _stage == 2 and _t - _stage_at > 1.2:
		if _watched and is_instance_valid(_watched):
			_ok("a watched figure does not move",
				_watched.global_position.distance_to(_watched_pos) < 0.01)
			# Still close, but now looking away: the distance guard alone must hold it.
			var cam := _player.get_node("Camera3D") as Camera3D
			cam.rotation.y += PI
		_advance(3)

	elif _stage == 3 and _t - _stage_at > 1.2:
		if _watched and is_instance_valid(_watched):
			_ok("nor does one standing right next to you, even unwatched",
				_watched.global_position.distance_to(_watched_pos) < 0.01,
				"RELOCATE_MIN_DIST is what stops a figure popping at arm's length")
		_audit_begin()
		_advance(10)

	elif _stage == 10:
		_audit_sample()
		if _t - _stage_at > AUDIT_TIME:
			_audit_report()
			# --- the Flood ------------------------------------------------------------
			_scene.call("_enter_zone", 3)
			_advance(4)

	elif _stage == 4 and _t - _stage_at > 0.8:
		_ok("standstill panic is restored outside the Sprawl",
			not bool(_player.get("_standstill_suspended")))
		_wader = _find(_scene, "UnseenWader")
		_ok("the unseen wader exists in the Flood", _wader != null)
		if not _wader:
			_finish()
			return true
		# It is NEVER rendered, and can never be touched.
		_ok("the wader has no mesh", _find(_wader, "MeshInstance3D") == null)
		_ok("the wader has no collider", _find(_wader, "CollisionShape3D") == null)
		_ok("the wader feeds no gaze panic", not _has_ancestor_scary(_wader))
		_ok("it keeps its distance",
			(_wader as Node3D).global_position.distance_to(_player.global_position) >= 11.0,
			"%.1f m away" % (_wader as Node3D).global_position.distance_to(_player.global_position))

		# Start it, then stop the player and watch it take a couple more strides.
		_wader.call("set_player_wading", true)
		_advance(5)

	elif _stage == 5 and _t - _stage_at > 0.5:
		_ok("it is audible while you wade", bool(_wader.get("_halted")) == false)
		_wader.call("set_player_wading", false)
		_advance(6)

	elif _stage == 6 and _t - _stage_at > 0.3:
		# Immediately after the player halts it must STILL be going — that gap is the beat.
		_ok("it does not stop the instant you do", bool(_wader.get("_halted")) == false,
			"two more strides first")
		_advance(7)

	elif _stage == 7 and _t - _stage_at > 2.4:
		_ok("but it does stop, a moment later", bool(_wader.get("_halted")) == true)
		_ok("and none of it cost any panic", _player.get_panic_ratio() < 0.30,
			"panic %.2f — the Flood's own 0.3/s drip is the only source here"
			% _player.get_panic_ratio())
		_finish()
		return true

	if _t > 40.0 + AUDIT_TIME:
		print("RESULT: FAIL — timed out at stage %d" % _stage)
		quit(1)
		return true
	return false


# --------------------------------------------------- it is a SILHOUETTE, not a cutout
#
# `watcher.gd`'s header states the design: "this reads because it is a dark shape OCCLUDING a
# lit surface". Measured in the Sprawl on 2026-08-17, that was FALSE — the figure was a
# LIGHTER patch than the floor it stood on:
#
#   figure at 2 m ......... 43.7 lum      figure at 25 m ....... 42.4 lum   (no falloff:
#   Sprawl floor .......... 29.5 - 36.3          the material is UNSHADED, so albedo is the
#   Sprawl ceiling ........ 28.8                 final colour at every distance)
#
# Because it is unshaded, the rendered value is exactly `source pixel x albedo_color`, so it
# can be asserted headlessly without a frame. The bar is the DARKEST ground measured, 28.8 —
# under it, the figure is an occluder everywhere in the room.
const GROUND_LUM := 28.8
# Fallback if the imported texture cannot be decoded headlessly: Pillow, over the opaque
# pixels of watcher_figure.png, 2026-08-17. Which path was used is always printed, so this
# can never quietly become the only thing being measured.
const FIGURE_SOURCE_MEAN := 43.6


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _figure_is_a_silhouette() -> void:
	var quad: MeshInstance3D = null
	for f in _cong.get_children():
		quad = _find(f, "MeshInstance3D") as MeshInstance3D
		if quad != null:
			break
	_ok("a Congregation figure has a quad to measure", quad != null)
	if quad == null:
		return
	var mat := quad.get_surface_override_material(0) as StandardMaterial3D
	_ok("...with an unshaded material (albedo IS the rendered colour)",
		mat != null and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
	if mat == null:
		return
	_ok("...and no emission, ever (Issues 21/27/33)", not mat.emission_enabled)

	var source := FIGURE_SOURCE_MEAN
	var how := "documented Pillow measurement"
	if mat.albedo_texture != null:
		var img: Image = mat.albedo_texture.get_image()
		if img != null and img.is_compressed():
			if img.decompress() != OK:
				img = null
		if img != null:
			var acc := 0.0
			var n := 0
			var step: int = maxi(1, img.get_width() / 64)
			for y in range(0, img.get_height(), step):
				for x in range(0, img.get_width(), step):
					var px := img.get_pixel(x, y)
					if px.a < 0.8:
						continue
					acc += _lum(px) * 255.0
					n += 1
			if n > 0:
				source = acc / float(n)
				how = "%d opaque pixels sampled from the imported texture" % n
	var effective: float = source * _lum(mat.albedo_color)
	print("      figure source mean %.1f lum (%s) x tint %.3f -> %.1f rendered"
		% [source, how, _lum(mat.albedo_color), effective])
	_ok("the figure is DARKER than the darkest ground behind it",
		effective < GROUND_LUM,
		"%.1f rendered vs floor/ceiling %.1f — untinted it was 43.6" % [effective, GROUND_LUM])


# ---------------------------------------------------------------- the relocation audit
#
# Walk the player a circuit of the Sprawl and watch every figure. What is asserted:
#
#   1. ZERO relocations land where the player can see them. Computed HERE, independently of
#      `Congregation.would_be_seen()` — re-running the implementation and agreeing with it
#      proves nothing.
#   2. The sample was not empty. ⚠️ A run that produced 0 relocations must FAIL, not pass:
#      "0 spawns checked ... PASS" has shipped in this repo more than once.
#   3. The visibility predicate can say YES. Without this control, (1) is satisfied by any
#      test whose `_sees()` is broken and always false.
#   4. No figure moves twice inside the settle window.
#
# ⚠️ Radius 11.5 m, not the hall's full 20: `backrooms_zone2.gd:_build_pressure()` puts
# beartraps at (-15, 8), (13, -11) and (4, 16), and 15 panic plus a 7 s escape QTE plus its
# 40 panic timeout would end the run and take the scene with it. This circuit stays >= 4.5 m
# from all three.
const AUDIT_TIME := 30.0
const AUDIT_RADIUS := 11.5
const AUDIT_OMEGA := 0.55        # rad per second of simulated time
const AUDIT_MIN_MOVES := 3
# congregation.gd:SETTLE_MIN, with a poll-interval's slack.
const AUDIT_SETTLE_MIN := 8.0 - 0.25

var _audit_last: Dictionary = {}    # figure -> last known position
var _audit_moved_at: Dictionary = {}
var _audit_moves := 0
var _audit_in_view := 0
var _audit_worst_gap := INF
var _audit_settle_pairs := 0
var _audit_prev_pos := Vector3.ZERO
var _audit_prev_fwd := Vector3.FORWARD
var _audit_have_prev := false
var _audit_control_front := false
var _audit_control_behind := true


func _sprawl_centre() -> Vector3:
	return SPRAWL_ORIGIN


func _cam() -> Camera3D:
	return _player.get_node_or_null("Camera3D") as Camera3D


# The same rule Watcher._is_seen() applies, re-derived from its documented constants
# (SEEN_DOT 0.55, figure centre at half of SIZE.y) rather than called through the object.
func _sees(pos: Vector3) -> bool:
	var cam := _cam()
	if cam == null:
		return false
	return _sees_from(cam.global_position, -cam.global_basis.z, pos)


# The same rule, from an EXPLICIT pose. ⚠️ This exists because of backlog 04 D13/D19: this
# audit failed about one run in twelve, always as "1 of N relocations landed in view", and it
# was the harness rather than the feature.
#
# `_audit_sample()` used to MOVE THE PLAYER and then judge, so a destination the Congregation
# legitimately approved from pose P was scored from pose P' one frame later — and the walk is
# a continuous circuit, so P' is never quite P. Judging from an explicit pose lets the audit
# require the destination to be visible from BOTH the pose in effect when the move was seen
# AND the one before it.
#
# ⚠️ It is a CONJUNCTION rather than a one-frame rewind on purpose: whether the level's node
# `_process` runs before or after a `SceneTree` script's `_process` is an engine detail this
# test should not depend on, and either way the true decision pose is one of those two. A
# genuine violation — a figure that lands in front of a player walking a slow circle — is
# visible from both; the artefact is visible from only one. Nothing else about the assertion
# is relaxed: the count that must be zero is still zero.
func _sees_from(cam_pos: Vector3, forward: Vector3, pos: Vector3) -> bool:
	var centre: Vector3 = pos + Vector3(0, 1.2, 0)
	var fwd := forward
	fwd.y = 0.0
	var flat := centre - cam_pos
	flat.y = 0.0
	if fwd.length() < 0.01 or flat.length() < 0.01:
		return false
	if fwd.normalized().dot(flat.normalized()) < 0.55:
		return false
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(cam_pos, centre)
	q.exclude = [_player.get_rid()]
	q.collision_mask = 1
	return space.intersect_ray(q).is_empty()


func _audit_begin() -> void:
	_audit_last.clear()
	_audit_moved_at.clear()
	_audit_moves = 0
	_audit_in_view = 0
	_audit_worst_gap = INF
	_audit_walk(0.0)
	for f in _cong.get_children():
		if f is Node3D:
			_audit_last[f] = (f as Node3D).global_position
			# ⚠️ NOT `_t`. The settle clock started when the figure was BUILT, several seconds
			# before this audit, so a figure that legitimately becomes eligible 4 s in would
			# report a 4 s gap and fail a rule it had actually obeyed. Only gaps between two
			# moves BOTH observed inside the audit window are measured.
			_audit_moved_at[f] = -1.0e9
	# Controls 3: a point 6 m dead ahead in open air must read as SEEN, and the same point
	# behind the player must not.
	var cam := _cam()
	var ahead := -cam.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var foot := _player.global_position
	_audit_control_front = _sees(foot + ahead * 6.0)
	_audit_control_behind = _sees(foot - ahead * 6.0)


func _audit_walk(phase: float) -> void:
	var c := _sprawl_centre()
	var a := phase * AUDIT_OMEGA
	var here := c + Vector3(sin(a) * AUDIT_RADIUS, 0.1, cos(a) * AUDIT_RADIUS)
	_player.global_position = here
	_player.velocity = Vector3.ZERO
	# Look along the direction of travel, which is what a player crossing the hall does.
	var tangent := Vector3(cos(a), 0.0, -sin(a))
	_player.rotation.y = atan2(-tangent.x, -tangent.z)
	var cam := _cam()
	if cam:
		cam.rotation.x = 0.0


# ⚠️ JUDGE FIRST, WALK LAST (backlog 04 D19). The order used to be the other way round, which
# is the whole of the intermittent failure — see `_sees_from()`.
func _audit_sample() -> void:
	var cam := _cam()
	var pose_pos: Vector3 = cam.global_position if cam else Vector3.ZERO
	var pose_fwd: Vector3 = -cam.global_basis.z if cam else Vector3.FORWARD
	for f in _cong.get_children():
		if not (f is Node3D):
			continue
		var node: Node3D = f
		var now: Vector3 = node.global_position
		if not _audit_last.has(node):
			_audit_last[node] = now
			_audit_moved_at[node] = -1.0e9
			continue
		if now.distance_to(_audit_last[node]) < 0.01:
			continue
		_audit_moves += 1
		var seen_now: bool = _sees_from(pose_pos, pose_fwd, now)
		var seen_before: bool = (not _audit_have_prev) \
			or _sees_from(_audit_prev_pos, _audit_prev_fwd, now)
		if seen_now and seen_before:
			_audit_in_view += 1
			print("      IN VIEW: a figure landed at %v, %.1f m from the player"
				% [now, now.distance_to(_player.global_position)])
		var prev: float = float(_audit_moved_at[node])
		if prev > 0.0:
			_audit_worst_gap = minf(_audit_worst_gap, _t - prev)
			_audit_settle_pairs += 1
		_audit_last[node] = now
		_audit_moved_at[node] = _t
	_audit_prev_pos = pose_pos
	_audit_prev_fwd = pose_fwd
	_audit_have_prev = true
	_audit_walk(_t - _stage_at)


func _audit_report() -> void:
	print("  -- relocation audit: %.0f s circuit of the Sprawl, %d relocations --"
		% [AUDIT_TIME, _audit_moves])
	_ok("the visibility probe can say YES (control)", _audit_control_front,
		"a point 6 m dead ahead must read as visible, or 'none in view' is vacuous")
	_ok("...and NO for something behind you (control)", not _audit_control_behind)
	_ok("relocations actually happened", _audit_moves >= AUDIT_MIN_MOVES,
		"%d in %.0f s, minimum %d" % [_audit_moves, AUDIT_TIME, AUDIT_MIN_MOVES])
	_ok("NO relocation landed in the player's view", _audit_in_view == 0,
		"%d of %d landed on screen" % [_audit_in_view, _audit_moves])
	# Only measurable when some figure moved TWICE inside the window. Reported either way, so
	# "the settle rule was never exercised" is visible rather than silently absent.
	if _audit_settle_pairs > 0:
		_ok("no figure moved twice inside the settle window",
			_audit_worst_gap >= AUDIT_SETTLE_MIN,
			"shortest gap %.1f s over %d consecutive-move pair(s), minimum %.1f"
			% [_audit_worst_gap, _audit_settle_pairs, AUDIT_SETTLE_MIN])
	else:
		print("      settle interval: not exercised — no figure moved twice in %.0f s"
			% AUDIT_TIME)
	# The whole feature is still free.
	_ok("and the audit cost no panic beyond the zone's own dread",
		_player.get_panic_ratio() < 0.40, "panic %.2f" % _player.get_panic_ratio())


func _finish() -> void:
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
