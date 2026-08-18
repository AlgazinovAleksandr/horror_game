extends SceneTree

# The Lab's Records breaker cannot be thrown until the locker has ACTUALLY been shoved
# clear — all three bars, not one.
#
#   Godot --headless --path game --script res://tests/check_lab_breaker_gate.gd
#
# Playtest 2026-08-16, capture #3: *"Even though I did not pull the case till the end, I
# still could flip the breaker"*. The arithmetic backs it up, and this test measures it
# rather than trusting it: the locker spans x -9.50..-8.50 over a breaker collider spanning
# -9.40..-8.60, and LabLocker.SHOVE_DIST is 0.45 m per completed bar. One bar exposes
# 0.35 m of collider; two clear it completely, a whole bar before the gate is meant to open.
#
# The fix (user's call, option (c)) does not move the locker further or make the push
# harder — it makes the BREAKER inert while `blocked` is true, via the optional
# `can_interact()` that `player.gd:_update_interact_prompt()` already consults for LabLocker.
#
# ⚠️ Everything here is duck-typed. Naming a game class (`Breaker`, `LabLocker`) in a
# SceneTree script compiles that class BEFORE the autoloads exist, so GameState is undefined
# and the level under measurement fails to build — the trap walk_lab_wing.gd:147 documents.
#
# ⚠️ The win condition is never reached by emitting `flipped`. Every attempt goes through
# `player.ai_interact()`, so the real raycast, the real `can_interact()` consultation and the
# real `interact()` all run. A test that emitted the signal would pass on a build where the
# breaker was welded shut.

const BREAKER_POS := Vector3(-9.0, 1.1, 9.65)
# Three standing positions in Records' west half, all within INTERACT_RANGE (3.0 m) of the
# breaker and all with a clean line to the strip of panel a partial shove exposes.
const STANDS := [
	Vector3(-9.30, 0.1, 11.30),
	Vector3(-9.60, 0.1, 11.60),
	Vector3(-8.90, 0.1, 11.90),
]
const EYE_HEIGHT := 1.65      # Player/Camera3D's own transform in level_1.tscn
# Two aim points, because "can you hit it" depends on where you point. The panel CENTRE is
# the naive aim; the STRIP is the west edge of the breaker's collider (spans x -9.40..-8.60),
# which is the sliver a single 0.45 m shove uncovers and the only place a one-shove bypass
# could ever land. Both are driven at every shove count.
const AIMS := [
	[Vector3(-9.00, 1.1, 9.65), "panel centre"],
	[Vector3(-9.32, 1.1, 9.65), "exposed strip"],
]
const SHOVE_DIST := 0.14      # LabLocker.SHOVE_DIST — the intermediate lurch
const TOTAL_TRAVEL := 1.10    # LabLocker.TOTAL_TRAVEL — where the third bar leaves it

# --- VISIBLE AREA (2026-08-16) ------------------------------------------------------------
# The second half of the fix. `blocked` already made the breaker inert, and the playtester
# confirmed they could not throw it — and still filed it as broken, because they could SEE
# the panel at 2 of 3 shoves: *"I should not see it fully once I do all 3 out of 3"*. A prop
# in plain sight that refuses to answer E reads as a bug, not as a locked door.
#
# So this measures OCCLUSION, with rays, as a fraction of the panel's own front face that is
# reachable from a set of realistic eye positions. It is a stand-in for screen-space area
# that needs no display: each sample is one pixel of the panel, and the answer is the share
# of them the locker does not block.
const GRID_X := 13            # samples across the panel's width
const GRID_Y := 17            # ... and its height
# Where a player actually stands in Records. The first two are the front-on approach the
# third shove is meant to pay off; the rest are oblique, including the room's own doorway.
const VIEWS := [
	[Vector3(-9.00, 1.65, 11.40), "front, 1.8 m", true],
	[Vector3(-9.00, 1.65, 13.60), "front, 4.0 m", true],
	[Vector3(-8.20, 1.65, 11.20), "oblique from the east", false],
	[Vector3(-9.80, 1.65, 12.20), "oblique from the west", false],
	[Vector3(-6.40, 1.65, 12.50), "standing in the doorway", false],
	[Vector3(-9.00, 1.20, 10.90), "crouched, close", false],
]
# "Near zero" in the brief. One sample of 221 is 0.45 % of the panel — a grazing sliver at
# the very edge, not a visible object. Anything the eye could call a panel is far above this.
const HIDDEN_MAX_FRACTION := 0.01
const EXPOSED_MIN_FRACTION := 0.90

var _frame := 0
var _fails := 0
var _checks := 0
var _scene: Node
var _locker: Node3D
var _breaker: Node
var _player: CharacterBody3D
var _phase := "find"
var _start_x := 0.0
var _panel: CSGBox3D
var _samples_taken := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fails += 1
	print("  %s  %s%s" % ["PASS" if cond else "FAIL", label, ("   " + detail) if detail != "" else ""])


func _find(root: Node, pred: Callable) -> Node:
	if pred.call(root):
		return root
	for c in root.get_children():
		var f := _find(c, pred)
		if f:
			return f
	return null


# Does an interact ray from `eye`, aimed at the breaker, reach the breaker's collider?
# This is the *geometry* question, and after two shoves the honest answer is YES — the fix
# is not occlusion. Asserted so that a future change which quietly relies on the locker
# still covering the panel is caught.
func _ray_reaches_breaker(eye: Vector3, aim: Vector3) -> bool:
	var space := _scene.get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye, aim + Vector3(0, 0, -0.25))
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and hit["collider"] == _breaker


# What fraction of the breaker panel's own front face can be reached from `eye`? One ray per
# sample point; a sample counts as visible only if the ray's FIRST hit is the breaker.
#
# ⚠️ The rectangle sampled is the PANEL's, read off the node, never a typed-in box — so this
# keeps measuring the right thing if the prop is rebuilt. The breaker's collider is larger
# than the panel in both axes, so an unobstructed ray always terminates on the breaker.
func _panel_visible_fraction(eye: Vector3) -> float:
	var space := _scene.get_viewport().world_3d.direct_space_state
	var s: Vector3 = _panel.size
	var hits := 0
	var total := 0
	for iy in range(GRID_Y):
		for ix in range(GRID_X):
			var u: float = (float(ix) + 0.5) / float(GRID_X) - 0.5
			var v: float = (float(iy) + 0.5) / float(GRID_Y) - 0.5
			var p: Vector3 = _panel.global_transform * Vector3(s.x * u, s.y * v, s.z * 0.5)
			var q := PhysicsRayQueryParameters3D.create(eye, p)
			q.exclude = [_player.get_rid()]
			var hit := space.intersect_ray(q)
			total += 1
			if not hit.is_empty() and hit["collider"] == _breaker:
				hits += 1
	_samples_taken += total
	return float(hits) / float(maxi(1, total))


func _report_visibility(stage: String) -> Dictionary:
	var worst := 0.0
	var front := 1.0
	for entry in VIEWS:
		var f: float = _panel_visible_fraction(entry[0])
		worst = maxf(worst, f)
		if bool(entry[2]):
			front = minf(front, f)
		print("  ..  %s — %-24s panel visible %5.1f %%" % [stage, entry[1], f * 100.0])
	return { "worst": worst, "front": front }


# Drive the REAL interaction path from every eye position: stand there, look at the
# breaker, press E. Returns true if any of them threw it.
func _try_all_eyes(aim: Vector3) -> bool:
	for stand in STANDS:
		_player.global_position = stand
		_player.ai_active = true
		_player.ai_look_at(aim)
		# ⚠️ Refresh the prompt BEFORE pressing. `_try_interact()` acts on `_interact_target`,
		# which `_update_interact_prompt()` sets from `_physics_process` — so an ai_interact()
		# in the same frame as a teleport acts on the target from wherever the player was
		# standing LAST frame. That is not a quirk of the test: ai_interact_target() exists
		# precisely to run that refresh, and calling it is what makes this the real path.
		_player.ai_interact_target()
		_player.ai_interact()
		if bool(_breaker.call("is_flipped")):
			return true
	return false


func _prompt_offers_breaker(aim: Vector3) -> bool:
	for stand in STANDS:
		_player.global_position = stand
		_player.ai_active = true
		_player.ai_look_at(aim)
		if _player.ai_interact_target() == _breaker:
			return true
	return false


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 8:
		return false

	# ⚠️ Every stage is TWO frames: one to move the locker, one to measure. A StaticBody3D
	# teleported from _process does not reach the physics server until the next physics
	# tick, so a ray cast in the same frame answers against the PREVIOUS position. This is
	# not theoretical — the first version of this test measured one shove behind for its
	# whole life, and its headline "two shoves DO expose the panel" was really the one-shove
	# state. Nothing said so, because every number it printed was plausible.
	match _phase:
		"find": _do_find()
		"set0": _set_shoves(0, "zero")
		"zero": _do_shoves(0)
		"set1": _set_shoves(1, "one")
		"one": _do_shoves(1)
		"set2": _set_shoves(2, "two")
		"two": _do_shoves(2)
		"set3": _set_shoves(-1, "three")
		"three": _do_full_travel()
		"control": _do_control()
		"done":
			print("%d checks, %d failed" % [_checks, _fails])
			print("LAB-BREAKER-GATE PASS" if _fails == 0 else "LAB-BREAKER-GATE FAIL")
			quit(1 if _fails > 0 else 0)
			return true
	return false


func _do_find() -> void:
	_scene = current_scene
	_player = _scene.get_node_or_null("Player") as CharacterBody3D
	_breaker = _scene.get_node_or_null("Breaker_Records")
	_locker = _find(_scene, func(n: Node) -> bool:
		return n is Node3D and n.has_signal("moved") and n.has_method("is_pushing")
	) as Node3D
	print("--- records breaker gate ---")
	_ok("player present", _player != null)
	_ok("Breaker_Records present", _breaker != null)
	_ok("locker present", _locker != null)
	if not (_player and _breaker and _locker):
		_phase = "done"
		return
	_ok("the breaker starts BLOCKED", bool(_breaker.get("blocked")))
	_ok("blocked: can_interact() is false", not bool(_breaker.call("can_interact")))
	_start_x = _locker.global_position.x
	_panel = null
	for c in _breaker.get_children():
		if c is CSGBox3D:
			_panel = c
			break
	_ok("the breaker's panel mesh was found to sample", _panel != null)
	if not _panel:
		_phase = "done"
		return
	_phase = "set0"


# Move it, and let the physics server catch up before anything is asked of it. `n < 0`
# means the full TOTAL_TRAVEL of the third bar.
func _set_shoves(n: int, next_phase: String) -> void:
	_locker.global_position.x = _start_x + (TOTAL_TRAVEL if n < 0 else SHOVE_DIST * float(n))
	_phase = next_phase


# Reproduce exactly what one / two completed bars leave behind: the locker moved
# SHOVE_DIST per bar, with the gate NOT satisfied (LabLocker.moved never fires, so the
# level never calls unblock()).
func _do_shoves(n: int) -> void:
	var vis := _report_visibility("%d/3 shoves" % n)
	_ok("after %d shove(s) the panel is effectively invisible" % n,
		float(vis["worst"]) <= HIDDEN_MAX_FRACTION,
		"worst view %.1f %% of the panel (limit %.1f %%)"
			% [float(vis["worst"]) * 100.0, HIDDEN_MAX_FRACTION * 100.0])
	if n == 0:
		_phase = "set1"
		return
	var total_exposed := 0
	for entry in AIMS:
		var aim: Vector3 = entry[0]
		var exposed := 0
		for stand in STANDS:
			if _ray_reaches_breaker(stand + Vector3(0, EYE_HEIGHT, 0), aim):
				exposed += 1
		total_exposed += exposed
		print("  ..  after %d of 3 shoves, aiming at the %s: the panel answers a ray from %d/%d positions"
			% [n, entry[1], exposed, STANDS.size()])
		_ok("after %d shove(s), %s: no 'Press E' target" % [n, entry[1]],
			not _prompt_offers_breaker(aim))
		_ok("after %d shove(s), %s: pressing E does not throw it" % [n, entry[1]],
			not _try_all_eyes(aim), "is_flipped=%s" % [_breaker.call("is_flipped")])
	_ok("after %d shove(s), no interact ray reaches the panel either" % n, total_exposed == 0,
		"%d ray hits across %d aims" % [total_exposed, AIMS.size()])
	_phase = "set2" if n == 1 else "set3"


# The third bar. `_slide()` carries the locker the REST of TOTAL_TRAVEL in one long shove,
# and this is the payoff the player asked for: at 3/3 the panel is not merely usable, it is
# fully in sight. Asserted from the front-on views, which is where they will be standing.
func _do_full_travel() -> void:
	var vis := _report_visibility("3/3 (the slide)")
	_ok("after the third shove the panel is fully exposed",
		float(vis["front"]) >= EXPOSED_MIN_FRACTION,
		"worst front-on view %.1f %% of the panel (want >= %.0f %%)"
			% [float(vis["front"]) * 100.0, EXPOSED_MIN_FRACTION * 100.0])
	_ok("sampled a real number of rays", _samples_taken > 2000,
		"%d rays cast" % _samples_taken)
	_phase = "control"


# POSITIVE CONTROL — proof this test can fail. With `blocked` cleared (which is exactly what
# LabLocker.moved -> unblock() does) the identical drive DOES throw the breaker. So the
# checks above are measuring the flag and not something incidental: revert the fix, and the
# three "pressing E does not throw it" lines go red here rather than passing vacuously.
func _do_control() -> void:
	# Belt and braces: even fully exposed, the flag is still what decides.
	_breaker.set("blocked", false)
	_ok("control: unblocked -> can_interact() is true", bool(_breaker.call("can_interact")))
	_ok("control: unblocked -> the same E press DOES throw it", _try_all_eyes(AIMS[0][0]),
		"if this fails, the checks above proved nothing")
	_phase = "done"
