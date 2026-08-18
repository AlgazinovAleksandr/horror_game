extends SceneTree

# THE SPRAWL'S EIGHT ALCOVES ARE OPEN, AND OPENING THEM DID NOT PUT A HOLE IN THE SHELL.
#
#   Godot --headless --path game --script res://tests/check_sprawl_alcoves.gd
#
# WHY THIS EXISTS. `backrooms_zone2.gd:_build_alcoves()` built each recess as a floor, a back
# wall and two side walls OUTSIDE the perimeter — and nothing removed the perimeter in front
# of it. All eight were sealed for the whole life of the zone, and behind them sat the only
# readable page in 1600 m², the phone, the one-way mirror, two mirage doors and five props.
# Cut open 2026-08-17 (backlog 04 F1, ISSUES_SOLUTIONS Issue 90).
#
# ⚠️ A MIS-CUT HOLE IN THIS PARTICULAR SHELL IS HOW A PLAYTEST ONCE ENDED WITH THE PLAYER
# FALLING OUT OF THE WORLD FOREVER — `backrooms.gd:_catch_out_of_world()` exists because of
# it. So this does not merely ask "is the mouth open". It asks, with physics queries only:
#
#   1. MOUTH OPEN      a ray from 3 m inside the hall reaches the alcove's centre.
#   2. STANDABLE       the player's own capsule fits at the mouth plane AND inside the recess.
#   3. FLOOR CONTINUOUS every sample across the threshold band lands on floor at y = 0 — no
#                      gap, no step, no lip. This is the one that catches a fall.
#   4. SHELL CLOSED    from inside the recess, every direction except the mouth is solid
#                      within the alcove's own footprint. A mouth cut too wide would open the
#                      wall beside it into the void.
#   5. PRESSURE        the `DreadZone` reaches the recesses, so opening them did not create
#                      eight decay pockets in a zone whose design has ONE recovery anchor.
#   6. THE PAGE READS  `SprawlNote` answers the SHIPPING interact ray from a realistic
#                      distance and 25° off-axis, aiming at the MESH and never at the collider.
#   7. THE PHONE       it is an emitter, not a trap: E cannot open a read-to-die note, and E
#                      does nothing at all while the tree is paused by `NoteUI` or while the
#                      player's input is frozen.
#
# ⚠️ PROOF IT CAN FAIL, kept permanently: `_control()` walls one mouth back up — the exact
# pre-2026-08-17 state — and requires checks 1 and 2 to go RED for that alcove and stay green
# for the other seven. If the rays or the capsule stop measuring anything, the control stops
# firing and the run fails.

const SCENE := "res://scenes/backrooms.tscn"
const OBLIQUE_DEG := 25.0
const READ_DIST := 1.6          # a realistic standing distance for reading a wall note

var _t := 0.0
var _stage := 0
var _stage_at := 0.0
var _scene: Node = null
var _player: CharacterBody3D = null
var _z2: Node3D = null
var _c: Dictionary = {}
var _fails: Array[String] = []
var _checks := 0
var _mouths_checked := 0
var _floor_samples := 0
var _control_wall: StaticBody3D = null
var _phone_answered := false


func _initialize() -> void:
	change_scene_to_file(SCENE)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _advance(n: int) -> void:
	_stage = n
	_stage_at = _t


func _process(delta: float) -> bool:
	_t += delta
	match _stage:
		0:
			# ⚠️ CSG colliders are not registered during `_ready()` (Issue 52).
			if _t < 1.5:
				return false
			_scene = current_scene
			_player = _scene.get_node_or_null("Player") as CharacterBody3D
			_z2 = _scene.get_node_or_null("ZoneSprawl") as Node3D
			_c = (load("res://scripts/backrooms_zone2.gd") as GDScript) \
				.get_script_constant_map()
			_ok("player found", _player != null)
			_ok("the Sprawl was built", _z2 != null)
			_ok("read the zone's constants", _c.size() > 10, "%d" % _c.size())
			if _player == null or _z2 == null:
				return _report()
			_player.set("ai_active", true)
			_geometry()
			_pressure()
			_advance(1)
		1:
			_page()
			_phone()
			_control_seal()
			_advance(2)
		2:
			# A CSG collider needs a frame before it answers a query.
			if _t - _stage_at < 0.5:
				return false
			_control_check()
			return _report()
	return false


# ---------------------------------------------------------------- helpers

func _origin() -> Vector3:
	return _z2.global_position


func _alcove_centre(side: String, k: int) -> Vector3:
	var axis: Vector3 = _c["SIDE_AXIS"][side]
	var half: float = _c["HALF"]
	var d: float = _c["ALCOVE_D"]
	var at: float = _c["ALCOVE_AT"]
	return _origin() + axis * (half + d / 2.0) + Vector3(axis.z, 0, axis.x) * (k * at)


func _space() -> PhysicsDirectSpaceState3D:
	return _scene.get_viewport().find_world_3d().direct_space_state


func _clear(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = [_player.get_rid()]
	return _space().intersect_ray(q)


func _capsule_fits(feet: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.exclude = [_player.get_rid()]
	q.transform = Transform3D(Basis(), feet + Vector3(0, 0.95, 0))
	return _space().intersect_shape(q, 1).is_empty()


# The DEEPEST solid surface in a column, or NAN if there is none.
#
# ⚠️ Not "the first thing a down-ray hits". The recesses contain a 0.75 m furniture box, a
# 0.30 m phone and a mirage door, all standing ON the floor, and a first-hit test reports each
# of them as a 0.30-0.75 m "step" in the floor. `intersect_ray` skips any shape whose ORIGIN
# is already inside it, so dropping the origin just under each hit walks down through the
# props to the slab. A genuine HOLE still returns nothing, which is the whole point.
func _lowest_floor(p: Vector3) -> float:
	var y := 1.2
	for _i in range(5):
		var hit := _clear(p + Vector3(0, y, 0), p - Vector3(0, 1.2, 0))
		if hit.is_empty():
			return NAN
		var hy: float = float(hit["position"].y)
		if hy <= 0.05:
			return hy
		y = hy - 0.02
	return y


# ---------------------------------------------------------------- 1-4 geometry

func _geometry() -> void:
	var axis_of: Dictionary = _c["SIDE_AXIS"]
	var d: float = _c["ALCOVE_D"]
	var w: float = _c["ALCOVE_W"]
	var open_ok := 0
	var stand_ok := 0
	var floor_bad: Array[String] = []
	var shell_bad: Array[String] = []
	for s in _c["SIDES"]:
		var axis: Vector3 = axis_of[s]
		var lat := Vector3(axis.z, 0, axis.x)
		for k in [-1, 1]:
			var centre := _alcove_centre(String(s), int(k))
			_mouths_checked += 1
			# 1. MOUTH OPEN — from 3 m inside the hall, at eye height.
			var inside := centre - axis * (d / 2.0 + 3.0) + Vector3(0, 1.5, 0)
			var hit := _clear(inside, centre + Vector3(0, 1.5, 0))
			if hit.is_empty():
				open_ok += 1
			else:
				_ok("Alc%s%+d: the mouth is open" % [s, k], false,
					"blocked by %s at %.2f m" % [(hit["collider"] as Node).name,
						inside.distance_to(hit["position"])])
			# 2. STANDABLE — at the mouth plane, and somewhere inside the recess.
			# ⚠️ NOT at the recess CENTRE: five of the eight hold a furniture box and two more
			# hold a mirage door, all of them placed dead centre. The question is whether a
			# player can get IN, so probe the two lateral halves as well and require the
			# mouth plus at least one interior spot.
			var at_mouth := centre - axis * (d / 2.0) + Vector3(0, 0.02, 0)
			var inner := 0
			for spot in [centre, centre + lat * 1.0, centre - lat * 1.0,
					centre - axis * 0.9, centre + lat * 1.0 - axis * 0.9]:
				if _capsule_fits(spot + Vector3(0, 0.02, 0)):
					inner += 1
			if _capsule_fits(at_mouth) and inner >= 2:
				stand_ok += 1
			else:
				_ok("Alc%s%+d: the capsule fits at the mouth and inside the recess" % [s, k],
					false, "mouth %s / %d of 5 interior spots" % [_capsule_fits(at_mouth), inner])
			# 3. FLOOR CONTINUOUS across the threshold. Any missing or stepped floor here is
			# a hole in the shell and a fall out of the world.
			# ⚠️ The band runs from 1.0 m INSIDE THE HALL to just short of the back wall.
			# Sampling past the back wall reports "no floor" for the open space outside the
			# building, which is true and meaningless.
			for iu in range(7):
				var u: float = (float(iu) / 6.0 - 0.5) * (w - 0.5)
				for iv in range(9):
					var v: float = -(d / 2.0 + 1.0) + (float(iv) / 8.0) * (d + 1.0 - 0.25)
					var p: Vector3 = centre + lat * u + axis * v
					_floor_samples += 1
					var fy := _lowest_floor(p)
					if is_nan(fy):
						floor_bad.append("Alc%s%+d NO FLOOR at %v" % [s, k, p.snappedf(0.1)])
					elif absf(fy) > 0.03:
						floor_bad.append("Alc%s%+d floor step %.3f m at %v"
							% [s, k, fy, p.snappedf(0.1)])
			# 4. SHELL CLOSED — from the middle of the recess, the back and both sides are
			# solid, and so is the perimeter immediately BESIDE the mouth.
			var eye := centre + Vector3(0, 1.5, 0)
			for probe in [
					["back", axis, d],
					["left", lat, w],
					["right", -lat, w],
				]:
				var dir: Vector3 = probe[1]
				var reach: float = float(probe[2])
				if _clear(eye, eye + dir * reach).is_empty():
					shell_bad.append("Alc%s%+d open to the %s" % [s, k, probe[0]])
			# ...and 1.2 m to either side of the mouth, along the perimeter plane, must
			# still be wall: a mouth cut wider than the recess opens the hall to the void.
			for sgn in [1.0, -1.0]:
				var beside: Vector3 = centre + lat * (sgn * (w / 2.0 + 0.9)) \
					- axis * (d / 2.0 - 0.05) + Vector3(0, 1.5, 0)
				if _clear(beside + axis * -1.0, beside + axis * 1.2).is_empty():
					shell_bad.append("Alc%s%+d perimeter missing beside the mouth" % [s, k])
	_ok("all eight mouths are OPEN", open_ok == 8, "%d of 8" % open_ok)
	_ok("all eight recesses are STANDABLE", stand_ok == 8, "%d of 8" % stand_ok)
	_ok("the floor is continuous across every threshold", floor_bad.is_empty(),
		"%d sample(s) bad of %d: %s"
			% [floor_bad.size(), _floor_samples, ", ".join(floor_bad.slice(0, 6))])
	_ok("the shell is still closed around every mouth", shell_bad.is_empty(),
		"%s" % ", ".join(shell_bad.slice(0, 8)))
	# ⚠️ Sample size is part of the assertion: 8 mouths, 8 x 63 floor points.
	_ok("the sweep measured a meaningful sample", _mouths_checked == 8
		and _floor_samples >= 500, "%d mouths, %d floor samples"
			% [_mouths_checked, _floor_samples])


# ---------------------------------------------------------------- 5 pressure

func _pressure() -> void:
	# A POINT QUERY against the live Area3Ds, not a read of the box's exported size.
	var missing: Array[String] = []
	for s in _c["SIDES"]:
		for k in [-1, 1]:
			var centre := _alcove_centre(String(s), int(k)) + Vector3(0, 1.0, 0)
			var q := PhysicsPointQueryParameters3D.new()
			q.position = centre
			q.collide_with_areas = true
			q.collide_with_bodies = false
			var found := false
			for r in _space().intersect_point(q, 16):
				if String((r["collider"] as Node).name).begins_with("SprawlDread"):
					found = true
			if not found:
				missing.append("Alc%s%+d" % [s, k])
	_ok("the DreadZone reaches every recess", missing.is_empty(),
		"outside the dread: %s" % str(missing))
	# ...and the control: a point well OUTSIDE the hall must NOT be in it, or the assertion
	# above is satisfied by a zone that covers the universe.
	var far := _origin() + Vector3(0, 1.0, float(_c["HALF"]) + 40.0)
	var qf := PhysicsPointQueryParameters3D.new()
	qf.position = far
	qf.collide_with_areas = true
	qf.collide_with_bodies = false
	var outside := true
	for r in _space().intersect_point(qf, 16):
		if String((r["collider"] as Node).name).begins_with("SprawlDread"):
			outside = false
	_ok("...and it does NOT cover open space 40 m outside the hall (control)", outside)


# ---------------------------------------------------------------- 6 the page

func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return n
	for c in n.get_children():
		var f := _first_mesh(c)
		if f != null:
			return f
	return null


func _find(nm: String) -> Node3D:
	for n in _all(_scene, []):
		if String(n.name) == nm and n is Node3D:
			return n
	return null


func _all(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children():
		_all(c, out)
	return out


# Stand `dist` from the prop's ART, `off_axis` degrees round from its facing, and ask the
# SHIPPING prompt path what it sees.
func _reads(prop: Node3D, dist: float, off_axis: float) -> Node:
	var mesh := _first_mesh(prop)
	var aim: Vector3 = mesh.global_transform * mesh.get_aabb().get_center() if mesh \
		else prop.global_position
	# A note.gd body carries its paper on +Z, so the room is in front of it.
	var out: Vector3 = prop.global_transform.basis.z.normalized()
	out.y = 0.0
	out = out.normalized().rotated(Vector3.UP, deg_to_rad(off_axis))
	var stand: Vector3 = aim + out * dist
	_player.global_position = Vector3(stand.x, _origin().y + 0.1, stand.z)
	_player.force_update_transform()
	_player.call("ai_look_at", aim)
	var cam := _player.get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.force_update_transform()
	return _player.call("ai_interact_target")


func _page() -> void:
	var note := _find("SprawlNote")
	_ok("SprawlNote exists", note != null)
	if note == null:
		return
	# It must be IN an alcove, not floating in the hall — derived from the geometry, so it
	# follows if the alcove ever moves.
	var target := _alcove_centre("S", -1)
	_ok("SprawlNote is in the S-1 recess", note.global_position.distance_to(target) < 2.0,
		"%.2f m from the recess centre" % note.global_position.distance_to(target))
	for off in [0.0, OBLIQUE_DEG, -OBLIQUE_DEG]:
		var hit := _reads(note, READ_DIST, off)
		_ok("SprawlNote answers E from %.1f m, %d° off-axis" % [READ_DIST, int(off)],
			hit == note or (hit != null and note.is_ancestor_of(hit)),
			"ray saw %s" % hit)


# ---------------------------------------------------------------- 7 the phone

func _phone() -> void:
	var phone := _find("SprawlPhone")
	_ok("SprawlPhone exists", phone != null)
	if phone == null:
		return
	# ⚠️ It is an EMITTER, not a trap. Zone 1's phone opens a read-to-die note on E; this one
	# is already off the hook and must never do that — it was unreachable for the life of the
	# zone and goes live with the cut.
	_ok("the Sprawl phone cannot open a read-to-die note", not bool(phone.get("open_note")))
	_ok("...and it never rings", not bool(phone.get("rings")))
	phone.connect("answered", func() -> void: _phone_answered = true)

	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true

	# Aim at it first, through the real prompt path.
	var seen := _reads(phone, 1.2, 0.0)
	_ok("the phone answers the interact ray at 1.2 m",
		seen == phone or (seen != null and phone.is_ancestor_of(seen)), "ray saw %s" % seen)

	# (a) INPUT FROZEN. `player.gd:_unhandled_input()` early-returns on `_input_frozen`, which
	# is what a beartrap QTE / the locker push / a cutscene rely on. Drive the REAL handler.
	_player.call("freeze_input")
	_player.call("_unhandled_input", ev)
	_ok("E does nothing while the player's input is frozen", not _phone_answered)
	_player.call("unfreeze_input")

	# (b) A NOTE IS OPEN. NoteUI pauses the tree and `_unhandled_input()` returns early.
	# ⚠️ Fetched by path — a `--script` SceneTree compiles before the autoloads exist, so
	# naming the singleton directly is a compile error (the walk_lab_wing lesson).
	var note_ui := root.get_node_or_null("/root/NoteUI")
	_ok("NoteUI autoload present", note_ui != null)
	if note_ui:
		note_ui.call("show_note", "control note", 0.0)
		_ok("...and it really opened (or the next check proves nothing)",
			bool(note_ui.get("is_open")))
		_player.call("_unhandled_input", ev)
		_ok("E does nothing while a note has the tree paused", not _phone_answered)
		note_ui.call("_close")

	# (c) NORMAL. The same event, nothing frozen, must answer it — and must NOT put a
	# read-to-die note on screen.
	_reads(phone, 1.2, 0.0)
	_player.call("_unhandled_input", ev)
	_ok("E answers the phone when nothing is blocking", _phone_answered)
	_ok("...and answering it opens NO note",
		note_ui == null or not bool(note_ui.get("is_open")))


# ---------------------------------------------------------------- the control

func _control_seal() -> void:
	# Wall the N-1 mouth back up: the exact geometry this file exists to have removed.
	var centre := _alcove_centre("N", -1)
	var axis: Vector3 = _c["SIDE_AXIS"]["N"]
	# ⚠️ A `StaticBody3D` + `BoxShape3D`, NEVER a runtime `CSGBox3D`. Measured on this scene
	# (tests/probe_csg_shapequery.gd, ISSUES_SOLUTIONS Issue 91): a CSGBox3D added AFTER the
	# level has built answers `intersect_ray` and is INVISIBLE to `intersect_shape`, so a
	# control built from one proves the ray half and silently proves nothing about the
	# capsule half. The level's own `_ready()`-time CSG boxes answer both.
	_control_wall = StaticBody3D.new()
	_control_wall.name = "AlcoveControlSeal"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(float(_c["ALCOVE_W"]) + 1.0, float(_c["HEIGHT"]), 0.3)
	cs.shape = bs
	_control_wall.add_child(cs)
	_scene.add_child(_control_wall)
	_control_wall.global_position = centre - axis * (float(_c["ALCOVE_D"]) / 2.0) \
		+ Vector3(0, float(_c["HEIGHT"]) / 2.0, 0)


func _control_check() -> void:
	var d: float = _c["ALCOVE_D"]
	var axis: Vector3 = _c["SIDE_AXIS"]["N"]
	var sealed_centre := _alcove_centre("N", -1)
	var inside := sealed_centre - axis * (d / 2.0 + 3.0) + Vector3(0, 1.5, 0)
	var chit := _clear(inside, sealed_centre + Vector3(0, 1.5, 0))
	_ok("CONTROL: sealing the N-1 mouth makes that ray BLOCKED again", not chit.is_empty(),
		"blocked by %s" % ("nothing" if chit.is_empty() else String((chit["collider"] as Node).name)))
	var mouth_pt := sealed_centre - axis * (d / 2.0) + Vector3(0, 0.02, 0)
	_ok("CONTROL: ...and the capsule no longer fits at that mouth",
		not _capsule_fits(mouth_pt), "probe at %v, seal at %v"
			% [mouth_pt.snappedf(0.01), _control_wall.global_position.snappedf(0.01)])
	# ...while a DIFFERENT mouth is untouched, so the control proves a change, not a break.
	var other := _alcove_centre("S", 1)
	var oaxis: Vector3 = _c["SIDE_AXIS"]["S"]
	var oinside := other - oaxis * (d / 2.0 + 3.0) + Vector3(0, 1.5, 0)
	_ok("CONTROL: the other seven are still open",
		_clear(oinside, other + Vector3(0, 1.5, 0)).is_empty())
	if is_instance_valid(_control_wall):
		_control_wall.queue_free()


func _report() -> bool:
	print("  %d checks, %d failed" % [_checks, _fails.size()])
	for f in _fails:
		print("   FAILED: " + f)
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		quit(1)
	return true
