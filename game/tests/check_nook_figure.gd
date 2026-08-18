extends SceneTree

# The BreakerNook figure stands somewhere real, and the player is turned to look at it.
#
#   Godot --headless --path game --script res://tests/check_nook_figure.gd
#
# Playtest 2026-08-16, capture #6: *"After I turn on the light switcher which is in the
# complete dark - sometimes I cannot see the creature which gives the jumpscare. We should
# guarantee the player will see this creature."*
#
# The old `_place_nook_figure()` fanned four headings off the camera and, if none of them had
# 1.8 m of ray clearance, fell through to `best_dir = -fwd, best_dist = 1.5` — a 1.5 m-wide
# billboard 1.5 m directly behind the player's head, at a spot NOTHING had checked. Two of
# the four headings (+/-90 degrees) are outside the camera's FOV by construction, so even the
# successful cases were often placed where nobody was looking. When it fired in the session,
# the player was 0.50 m from SouthHall's north wall.
#
# This measures both halves of the replacement:
#   1. CLEARANCE — every spot it returns is provably clear, checked here with an INDEPENDENT
#      ray fan rather than by calling the level's own _figure_fits() back at itself.
#      ⚠️ Rays, never intersect_shape (Issue 40).
#   2. FRAMING — how often the spot would have been on screen WITHOUT help (the old
#      lottery), versus after the scripted camera turn the beat now performs.
#
# ⚠️ Duck-typed throughout: naming a game class in a SceneTree script compiles it before the
# autoloads exist, and the level under measurement then fails to build.

const FIG_CLEAR := 0.80        # half the 1.5 m billboard, plus a margin
const FAN_RAYS := 12
const MIN_POSES := 40
const TURN_SAMPLES := 6
const TURN_SETTLE := 0.35      # seconds; turn_to_face()'s tween is 0.45 by default

var _frame := 0
var _elapsed := 0.0
var _fails := 0
var _checks := 0
var _scene: Node
var _player: CharacterBody3D
var _cam: Camera3D
var _phase := "grid"
var _poses: Array = []
var _turn_i := 0
var _turn_started := 0.0
var _turn_spot := Vector3.ZERO
var _turn_ok := 0
var _turn_done := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fails += 1
	print("  %s  %s%s" % ["PASS" if cond else "FAIL", label, ("   " + detail) if detail != "" else ""])


# An independently written clearance check — same principle as the level's, not the same
# code, and 12 rays where the level uses 16.
#
# ⚠️ The LINE OF SIGHT ray is the one that catches "inside a wall", and it is not optional.
# A ray that STARTS inside a CSG slab and travels outward crosses that slab's faces from
# BEHIND, and `ConcavePolygonShape3D.backface_collision` is false by default — so it reports
# nothing and an outward fan happily approves a figure buried in masonry. Measured here: an
# outward-only fan passed a spot a metre beyond SouthHall's north wall. The eye->chest
# segment has to cross the wall's near face from the front, which is why apparition.gd's
# `_fits()` is built on it too.
func _clear(spot: Vector3, eye: Vector3) -> bool:
	var space := _scene.get_viewport().world_3d.direct_space_state
	var chest := spot + Vector3(0, 1.35, 0)
	var ex := [_player.get_rid()]
	var los := PhysicsRayQueryParameters3D.create(eye, chest)
	los.exclude = ex
	if not space.intersect_ray(los).is_empty():
		return false
	for i in range(FAN_RAYS):
		var a := TAU * float(i) / float(FAN_RAYS)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var q := PhysicsRayQueryParameters3D.create(chest, chest + dir * FIG_CLEAR)
		q.exclude = ex
		if not space.intersect_ray(q).is_empty():
			return false
	# And the head-room, which is what catches a spot under a drop ceiling or inside a prop.
	var up := PhysicsRayQueryParameters3D.create(chest, spot + Vector3(0, 2.4, 0))
	up.exclude = ex
	return space.intersect_ray(up).is_empty()


func _visible_now(spot: Vector3) -> bool:
	return _cam.is_position_in_frustum(spot + Vector3(0, 1.2, 0))


func _build_poses() -> void:
	var spots: Array[Vector3] = []
	# BreakerNook (x -37..-31, z 5.7..9.7) — where the beat is designed to happen.
	for xi in range(5):
		for zi in range(3):
			spots.append(Vector3(-36.2 + float(xi) * 1.1, 0.1, 6.6 + float(zi) * 1.1))
	# SouthHall (x -31..-22.2, z 6.5..8.9) — where a player who walked out during the 5 s of
	# breathing actually is.
	for xi in range(6):
		spots.append(Vector3(-30.0 + float(xi) * 1.4, 0.1, 7.7))
	# SouthSpur (x -22.2..-19.8, z 6.5..10.5) — one room further out again.
	for zi in range(4):
		spots.append(Vector3(-21.0, 0.1, 7.0 + float(zi) * 1.0))
	for s in spots:
		for h in [0.0, 90.0, 180.0, 270.0]:
			_poses.append([s, deg_to_rad(h)])


func _process(delta: float) -> bool:
	_frame += 1
	_elapsed += delta
	# ⚠️ CSG colliders are not registered during _ready() (Issue 52).
	if _frame < 10:
		return false

	match _phase:
		"grid": _do_grid()
		"turn": _do_turn(delta)
		"done":
			print("%d checks, %d failed" % [_checks, _fails])
			print("NOOK-FIGURE PASS" if _fails == 0 else "NOOK-FIGURE FAIL")
			quit(1 if _fails > 0 else 0)
			return true
	return false


func _do_grid() -> void:
	_scene = current_scene
	_player = _scene.get_node_or_null("Player") as CharacterBody3D
	_cam = _player.get_node_or_null("Camera3D") as Camera3D if _player else null
	print("--- nook figure placement ---")
	_ok("player + camera present", _player != null and _cam != null)
	_ok("the beat can aim the camera (player.turn_to_face exists)",
		_player != null and _player.has_method("turn_to_face"))
	if not (_player and _cam):
		_phase = "done"
		return
	_player.ai_active = true
	_build_poses()

	var placed := 0
	var skipped := 0
	var bad := 0
	var visible_before := 0
	var first_bad := ""
	for pose in _poses:
		_player.global_position = pose[0]
		_player.rotation.y = pose[1]
		_cam.rotation.x = 0.0
		var spot: Vector3 = _scene._place_nook_figure(_player)
		if not spot.is_finite():
			skipped += 1
			continue
		placed += 1
		if not _clear(spot, _cam.global_position):
			bad += 1
			if first_bad == "":
				first_bad = "player %v -> figure %v" % [pose[0], spot]
		if _visible_now(spot):
			visible_before += 1

	# ⚠️ Assert the sample size. A run that measured nothing and printed PASS is a documented
	# failure mode in this repo, not a hypothetical one.
	_ok("sampled enough poses", _poses.size() >= MIN_POSES, "%d poses" % _poses.size())
	_ok("a figure was actually placed in most of them", placed >= _poses.size() / 2,
		"%d placed, %d skipped" % [placed, skipped])
	_ok("EVERY placed figure is clear by an independent ray fan", bad == 0,
		"%d bad of %d placed%s" % [bad, placed, ("   e.g. " + first_bad) if first_bad != "" else ""])
	# Not an assertion — the number the fix exists for. This is the fraction that would have
	# been on screen with no help at all, i.e. the old lottery.
	print("  ..  without the camera turn, %d of %d placements (%.0f%%) were already in frustum"
		% [visible_before, placed, 100.0 * float(visible_before) / maxf(1.0, float(placed))])
	# POSITIVE CONTROL — proof the clearance check above can go red, kept permanently rather
	# than performed once by hand. The first spot is where the OLD code's unvalidated
	# fallback put the figure on the run that produced capture #6: the player was at
	# (-24.20, 8.40), half a metre from SouthHall's north wall (z = 8.9), and "1.5 m directly
	# behind" with their back to it lands the billboard inside that wall. The second is an
	# ordinary open floor spot, so a _clear() that simply always said "no" would fail too.
	_ok("control: a spot through SouthHall's north wall is REJECTED",
		not _clear(Vector3(-24.2, 0.0, 9.9), Vector3(-24.2, 1.75, 8.4)))
	_ok("control: an open spot in the middle of BreakerNook is ACCEPTED",
		_clear(Vector3(-34.0, 0.0, 7.7), Vector3(-32.0, 1.75, 7.7)))
	_phase = "turn"
	_turn_started = _elapsed


# And now the other half: after turn_to_face(), is it on screen? Driven as a real tween over
# real frames — a turn asserted in the same frame it was requested measures nothing (the
# swing-door lesson: a Tween does not advance until the next frame).
func _do_turn(_delta: float) -> void:
	if _turn_i >= TURN_SAMPLES:
		# Sample size asserted separately from the result, so "0 turns measured … PASS"
		# cannot happen: a sample whose pose produced no figure is skipped, not counted.
		_ok("enough turn samples produced a figure to measure",
			_turn_done >= TURN_SAMPLES - 2, "%d of %d samples" % [_turn_done, TURN_SAMPLES])
		_ok("after the scripted turn, the figure is in frustum every time",
			_turn_done > 0 and _turn_ok == _turn_done,
			"%d/%d" % [_turn_ok, _turn_done])
		_phase = "done"
		return

	# Space the samples across the grid rather than taking six neighbours.
	var idx: int = int(float(_turn_i) / float(TURN_SAMPLES) * float(_poses.size()))
	var pose: Array = _poses[idx]
	if _turn_spot == Vector3.ZERO:
		_player.global_position = pose[0]
		_player.rotation.y = pose[1]
		_cam.rotation.x = 0.0
		var spot: Vector3 = _scene._place_nook_figure(_player)
		if not spot.is_finite():
			_turn_i += 1                     # nothing to look at here; not a failure
			return
		_turn_spot = spot
		_turn_started = _elapsed
		# Deliberately looking AWAY first, so the turn has work to do.
		_player.rotation.y = pose[1] + PI
		_player.turn_to_face(spot + Vector3(0, 1.35, 0), 0.2)
		return

	if _elapsed - _turn_started < TURN_SETTLE:
		return
	_turn_done += 1
	if _visible_now(_turn_spot):
		_turn_ok += 1
	else:
		print("  ..  NOT in frustum after the turn: player %v -> figure %v"
			% [_player.global_position, _turn_spot])
	_turn_spot = Vector3.ZERO
	_turn_i += 1
