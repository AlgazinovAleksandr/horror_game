extends SceneTree

# The figure in the turn mirrors stands OFF the axis, and that offset buys real motion.
#
#   Godot --headless --path game --script res://tests/check_mirror_figure.gd
#
# WHY. User report, 2026-08-16: *"It used to be in a way that the reflection in the mirror
# moves, now it is static. can we make it move again?"* The reflection was never frozen (see
# `check_mirror_frustum.gd:_liveness()`); what was frozen was the thing the player looks AT.
#
# The player walks the corridor's centreline, the mirror hangs on that axis, and the figure
# stood exactly on it — and **a point on a mirror's own normal is a fixed point of the
# projection under axial motion.** Measured across the whole 12 m -> 1 m approach, in pixels
# of the 551 px pane:
#
#     offset 0.00 m    275.5 px at every distance     0.0 px of travel — zero, exactly
#     offset 0.45 m    163.6 -> 253.4 px             89.7 px  (16.3 % of the pane)
#
# So the fix is geometric and this is the test of it. Two things are asserted, and the second
# is the one that matters:
#   1. every mirror actually GOT a figure, at an offset above the floor. `Watcher.spawn()`
#      returns null when a spot is refused, and the old loop swallowed that — a mirror with
#      an empty glass looked identical to one whose figure you had not spotted yet.
#   2. that offset produces measurable lateral travel in the RENDER, unprojected through the
#      real reflection camera into the real SubViewport — with an on-axis CONTROL that must
#      NOT move, or this file is measuring something other than the offset.

const MIN_TRAVEL_PX := 35.0     # at the 0.25 m floor the maths gives ~50 px; 0.00 m gives 0
const CONTROL_MAX_PX := 2.0
const EYE_FAR := 12.0
const EYE_NEAR := 1.0

var _frame := 0
var _done := false
var _checks := 0
var _fails: Array[String] = []
var _measured := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/corridor.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print("  %s  %s%s" % ["OK  " if cond else "FAIL", label, ("  " + detail) if detail else ""])
	if not cond:
		_fails.append(label)


func _collect(n: Node, mirrors: Array, figures: Array) -> void:
	if String(n.name) == "MirrorSurface" and n.has_node("SubViewport"):
		mirrors.append(n)
	elif String(n.name).begins_with("MirrorFigure"):
		figures.append(n)
	for c in n.get_children():
		_collect(c, mirrors, figures)


func _process(_dt: float) -> bool:
	_frame += 1
	if _done:
		return true
	# ⚠️ Not frame 1. The figures are spawned from the level's FIRST _process tick, because
	# CSG colliders are not registered with the physics server during _ready() and the
	# clearance probes would be querying an empty world (corridor.gd:_make_mirror_real).
	if _frame < 12:
		return false
	_done = true

	var scene := current_scene
	var cs: GDScript = scene.get_script()
	var declared_v: Variant = cs.get("TURN_MIRRORS")
	var declared: Array = declared_v if declared_v is Array else []
	var mirrors: Array = []
	var figures: Array = []
	_collect(scene, mirrors, figures)

	_ok("the level declares turn mirrors", declared.size() >= 1, str(declared))
	_ok("every mirror is built", mirrors.size() == declared.size(),
		"%d built / %d declared" % [mirrors.size(), declared.size()])
	# ⚠️ THE ONE THAT WOULD HAVE CAUGHT THE SILENT LOSS. A refused Watcher.spawn() used to be
	# a bare `continue`.
	_ok("every mirror got a figure", figures.size() == mirrors.size(),
		"%d figures / %d mirrors" % [figures.size(), mirrors.size()])

	# ---- the offsets the level settled on ------------------------------------------------
	var offs_v: Variant = scene.get("_mirror_figure_offsets")
	var offs: Array = offs_v if offs_v is Array else []
	var floor_m: float = float(cs.get("MIRROR_FIGURE_SIDE_MIN"))
	_ok("the level recorded an offset per mirror", offs.size() == mirrors.size(),
		"%s" % str(offs))
	for i in offs.size():
		# ⚠️ ABSOLUTE value: which SIDE a figure ends up on is chosen per mirror by what fits,
		# and both are equally good. What must never happen is a quiet return to 0.0.
		_ok("figure %d is off the axis" % i, absf(float(offs[i])) >= floor_m,
			"offset %+.2f m, floor %.2f" % [float(offs[i]), floor_m])

	if mirrors.is_empty() or figures.is_empty():
		return _finish()

	# ---- and that the offset is worth something in the RENDER ----------------------------
	for m in mirrors:
		_measure(m, figures)

	_ok("enough mirrors were measured", _measured == mirrors.size(),
		"%d of %d" % [_measured, mirrors.size()])
	return _finish()


func _measure(m: Node3D, figures: Array) -> void:
	var quad: MeshInstance3D = m.get_parent() as MeshInstance3D
	var cam: Camera3D = m.get_node("SubViewport/Camera3D") as Camera3D
	var n: Vector3 = quad.global_transform.basis.z.normalized()

	# The figure belonging to THIS mirror: the nearest one down its own normal.
	var best: Node3D = null
	var best_d := INF
	for f in figures:
		var d: float = (f as Node3D).global_position.distance_to(quad.global_position)
		if d < best_d:
			best_d = d
			best = f
	if best == null:
		return
	var label := String(quad.get_parent().get_parent().name)

	# Chest height on the figure; the exact height is irrelevant, only that it is fixed.
	var target: Vector3 = best.global_position + Vector3(0, 0.9, 0)
	# The CONTROL: the figure's own position projected back ONTO the mirror's axis — same
	# distance down the corridor, same height, zero lateral offset. It is the placement this
	# change replaced, measured side by side with the one that replaced it.
	var along: float = (best.global_position - quad.global_position).dot(n)
	var on_axis: Vector3 = quad.global_position + n * along
	on_axis.y = target.y

	var far_eye: Vector3 = quad.global_position + n * EYE_FAR + Vector3(0, 0.15, 0)
	var near_eye: Vector3 = quad.global_position + n * EYE_NEAR + Vector3(0, 0.15, 0)

	m.call("_aim", far_eye)
	var fig_far: Vector2 = cam.unproject_position(target)
	var axis_far: Vector2 = cam.unproject_position(on_axis)
	m.call("_aim", near_eye)
	var fig_near: Vector2 = cam.unproject_position(target)
	var axis_near: Vector2 = cam.unproject_position(on_axis)

	var travel: float = absf(fig_near.x - fig_far.x)
	var control: float = absf(axis_near.x - axis_far.x)

	# The control FIRST. If an on-axis point also travels, the number below is not the offset.
	_ok("%s: control — an ON-AXIS point does not move across the glass" % label,
		control <= CONTROL_MAX_PX, "%.2f px over a %.0f m approach" % [control, EYE_FAR - EYE_NEAR])
	_ok("%s: the figure DOES move across the glass" % label, travel >= MIN_TRAVEL_PX,
		"%.1f px over a %.0f m approach (floor %.0f)" % [travel, EYE_FAR - EYE_NEAR, MIN_TRAVEL_PX])

	# It must still be a legal spot: real rays, out to Watcher's own fan radius.
	var radius: float = float(load("res://scripts/watcher.gd").get("FIT_RADIUS"))
	var space := quad.get_world_3d().direct_space_state
	var clear := true
	for i in 16:
		var a := TAU * float(i) / 16.0
		var from: Vector3 = best.global_position + Vector3(0, 1.2, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(sin(a), 0, cos(a)) * radius)
		q.collision_mask = 1
		if not space.intersect_ray(q).is_empty():
			clear = false
	_ok("%s: the figure still has %.2f m of elbow room" % [label, radius], clear)
	_measured += 1


func _finish() -> bool:
	print("  %d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL — ", ", ".join(_fails))
		quit(1)
	return true
