extends SceneTree

# The Lab's Records locker (the note-gated, TAB-mashed cover over breaker 2) and the
# BreakerNook payoff scare.
#
#   Godot --headless --path game --script res://tests/check_lab_locker.gd
#
# ⚠️ Everything here is duck-typed. Naming a game class (`LabLocker`, `Breaker`) in a
# SceneTree script compiles that class BEFORE the autoloads exist, so GameState is
# undefined and the level this test is measuring fails to build — the same trap
# screenshot_maze_ui.gd:47 and walk_lab_wing.gd:147 both document.
#
# ⚠️ And the occlusion checks are RAYCASTS against the built geometry, not distance
# arithmetic against the ROOMS table that produced it. "The breaker is behind the
# locker" is only true if a ray actually stops at the locker.
#
# Checks:
#   1. the locker exists and stands between the room and the Records breaker
#   2. the gate holds: interacting before the note is read moves nothing
#   3. reading the Observation maintenance note unlocks it
#   4. mashing the real `push_effort` action drives the bar and slides it aside
#   5. the breaker is reachable afterwards and was not reachable before
#   6. REGRESSION: _restore_power() leaves every NO_LAMP_ROOMS lamp dark
#   7. flipping the nook breaker kills the beacons and starts the breathing

const BREAKER_POS := Vector3(-9.0, 1.1, 9.65)     # Records breaker, wall_point-derived
const EYE := Vector3(-9.0, 1.1, 11.5)             # standing in Records, looking at it
const NOOK_BREAKER_POS := Vector3(-36.85, 1.1, 7.7)

# The ten rooms of the dark wing — the narrow exception that _light_the_wing() turns on
# after the scare resolves. Kept in sync with level_1.gd's WING_ROOMS.
const WING_ROOMS := [
	"DarkCorridor", "Junction", "WestCorridor", "Plant",
	"NorthSpur", "NorthVault", "SouthSpur", "SouthHall", "PumpRoom", "BreakerNook",
]

# Every room _spawn_lights() deliberately gives a 0-energy lamp. Kept in sync with
# level_1.gd's NO_LAMP_ROOMS — this is WING_ROOMS plus the Morgue, which stays dark
# under every circumstance.
const DARK_ROOMS := [
	"Morgue",
	"DarkCorridor", "Junction", "WestCorridor", "Plant",
	"NorthSpur", "NorthVault", "SouthSpur", "SouthHall", "PumpRoom", "BreakerNook",
]

var _frame := 0
var _scene: Node
var _locker: Node3D
var _start_pos := Vector3.ZERO
var _mash_frames := 0
var _settle_started := 0.0
var _elapsed := 0.0
var _scare_started := 0.0
var _fail := 0
var _checks := 0
var _phase := "find"


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fail += 1
	print("  %s  %s%s" % ["PASS" if cond else "FAIL", label, ("   " + detail) if detail != "" else ""])


# What does a ray from the room to the breaker hit first?
#
# The player is excluded, exactly as player.gd:_get_raycast_target() excludes `self`.
# Without that this check fails for the right reason and the wrong one: starting the
# push tweens the player onto the brace mark directly in front of the locker, which
# is on this line of sight.
func _ray_target() -> Node:
	var space := _scene.get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(EYE, BREAKER_POS + Vector3(0, 0, -0.2))
	var player := _scene.get_node_or_null("Player") as CharacterBody3D
	if player:
		q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	return hit.get("collider") if not hit.is_empty() else null


func _find(root: Node, pred: Callable) -> Node:
	if pred.call(root):
		return root
	for c in root.get_children():
		var f := _find(c, pred)
		if f:
			return f
	return null


func _find_all(root: Node, pred: Callable, out: Array) -> Array:
	if pred.call(root):
		out.append(root)
	for c in root.get_children():
		_find_all(c, pred, out)
	return out


func _process(delta: float) -> bool:
	_frame += 1
	_elapsed += delta
	if _frame < 6:
		return false

	match _phase:
		"find": _do_find()
		"gate": _do_gate()
		"unlock": _do_unlock()
		"mash": _do_mash()
		"settle": _do_settle()
		"lights": _do_lights()
		"nook": _do_nook()
		"aftermath": _do_aftermath()
		"done":
			print("%d checks, %d failed" % [_checks, _fail])
			print("LAB-LOCKER PASS" if _fail == 0 else "LAB-LOCKER FAIL")
			quit(1 if _fail > 0 else 0)
			return true
	return false


func _do_find() -> void:
	_scene = current_scene
	_locker = _find(_scene, func(n: Node) -> bool:
		return n is Node3D and n.has_method("interact") and n.has_signal("moved") \
			and n.has_method("is_pushing")
	) as Node3D
	print("--- lab locker ---")
	_ok("locker exists in the built level", _locker != null)
	if not _locker:
		_phase = "done"
		return
	_start_pos = _locker.global_position
	_ok("locker occludes the breaker", _ray_target() == _locker,
		"ray hit %s" % [_ray_target()])
	_ok("push_effort action is bound",
		InputMap.has_action("push_effort") and InputMap.action_get_events("push_effort").size() > 0)
	_phase = "gate"


func _do_gate() -> void:
	# Locked: the locker must be COMPLETELY inert — player.gd asks can_interact()
	# before it will even show "Press E" or set its interact target, so a false here
	# is what makes E do literally nothing.
	_ok("locked: can_interact() is false (no prompt, no target)", not _locker.can_interact())
	_locker.interact()
	_ok("locked: interact() does not open the push", not _locker.is_pushing())
	_ok("locked: locker has not moved", _locker.global_position.is_equal_approx(_start_pos))
	_phase = "unlock"


func _do_unlock() -> void:
	# The gate is the Observation maintenance note. Drive the real signal path rather
	# than setting `unlocked` directly, so a broken connect() fails this test.
	var note := _find(_scene, func(n: Node) -> bool:
		return n.has_signal("read") and "note_text" in n \
			and String(n.note_text).begins_with("MAINTENANCE")
	)
	_ok("maintenance note exists", note != null)
	if note:
		# interact() would also open NoteUI and pause the tree; the signal is the part
		# under test, so emit it directly.
		note.read.emit()
	_ok("reading the note unlocks the locker", note != null and _locker.unlocked)
	_ok("unlocked: can_interact() is true (prompt returns)", _locker.can_interact())
	if not _locker.unlocked:
		_phase = "done"
		return
	_locker.interact()
	_ok("unlocked: interact() opens the push", _locker.is_pushing())
	_phase = "mash"


func _do_mash() -> void:
	if not _locker.is_pushing():
		# Either it slid (good) or it aborted (bad) — _do_settle sorts that out.
		Input.action_release("push_effort")
		_phase = "settle"
		return
	_mash_frames += 1
	if _mash_frames > 900:
		_ok("mashing push_effort fills the bar", false, "still pushing after 900 frames")
		Input.action_release("push_effort")
		_phase = "done"
		return
	# Alternate press/release so is_action_just_pressed() fires each cycle.
	if _mash_frames % 2 == 1:
		Input.action_press("push_effort")
	else:
		Input.action_release("push_effort")


func _do_settle() -> void:
	# Let the 1.1 s slide tween finish. Time-based for the same reason _do_aftermath is.
	if _settle_started == 0.0:
		_settle_started = _elapsed
	if _elapsed - _settle_started < 1.6:
		return
	var travelled: float = _locker.global_position.distance_to(_start_pos)
	# ⚠️ The travel is FRONT-LOADED onto the last bar since 2026-08-16 (two 0.14 m lurches
	# that keep the panel covered, then one 0.82 m slide that reveals it), so the old
	# "3 x SHOVE_DIST" arithmetic no longer describes it. What still has to be true is the
	# TOTAL — anything much under LabLocker.TOTAL_TRAVEL means the staging short-circuited
	# and one bar cleared the whole thing. Where the panel is visible at each intermediate
	# stage is measured with rays in check_lab_breaker_gate.gd, not here.
	_ok("three shoves slid the locker fully aside", travelled >= 1.05,
		"travelled %.2f m (LabLocker.TOTAL_TRAVEL = 1.10)" % travelled)
	_ok("breaker is reachable once the locker has moved",
		_ray_target() != null and _ray_target().has_signal("flipped"),
		"ray hit %s" % [_ray_target()])
	_phase = "lights"


func _do_lights() -> void:
	# REGRESSION (ISSUES_SOLUTIONS Issue 36): _restore_power() used to raise EVERY
	# lamp's base energy, including the eleven rooms spawned dark — floodlighting the
	# Morgue and the whole navigate-by-ear wing.
	_scene._restore_power()
	var lit: Array = []
	for room in DARK_ROOMS:
		var lamp := _scene.get_node_or_null("Lamp_" + room) as OmniLight3D
		if lamp == null:
			lit.append(room + "(missing)")
		elif lamp.light_energy > 0.01:
			lit.append("%s=%.2f" % [room, lamp.light_energy])
	_ok("restoring power leaves every dark room dark", lit.is_empty(),
		"lit: %s" % [lit])
	_phase = "nook"


func _do_nook() -> void:
	var breakers: Array = _find_all(_scene, func(n: Node) -> bool:
		return n is Node3D and n.has_signal("flipped") and n.has_method("interact")
	, [])
	var nook: Node3D = null
	for b in breakers:
		if b.global_position.distance_to(NOOK_BREAKER_POS) < 0.5:
			nook = b
	_ok("nook breaker found", nook != null)
	if not nook:
		_phase = "done"
		return

	var beacons_before: Array = _find_all(_scene, func(n: Node) -> bool:
		return n is AudioStreamPlayer3D and String(n.name).begins_with("Beacon_")
	, [])
	_ok("both beacon layers running before the flip", beacons_before.size() == 2,
		"%d found" % beacons_before.size())

	# Lock the flashlight first, the way the wing's Area3D does on entry — otherwise
	# the "usable again" check below passes vacuously, since the test player is
	# teleported straight to Records and never walks into the wing.
	var pl := _scene.get_node_or_null("Player") as CharacterBody3D
	if pl and pl.has_method("lock_flashlight"):
		pl.lock_flashlight()
	_ok("flashlight locked on entering the wing", pl != null and pl._flashlight_locked)

	nook.interact()

	var beacons_after: Array = _find_all(_scene, func(n: Node) -> bool:
		return n is AudioStreamPlayer3D and String(n.name).begins_with("Beacon_") \
			and not n.is_queued_for_deletion()
	, [])
	_ok("flipping the nook breaker kills the beacons", beacons_after.is_empty(),
		"%d still live" % beacons_after.size())
	_ok("breathing starts behind the player",
		_scene.get_node_or_null("NookBreath") != null)
	_scare_started = _elapsed
	_phase = "aftermath"


# The whole scare runs on SceneTree timers: 5 s to the reveal, then ~2.2 s of beats
# before _nook_cleanup() lights the wing. Wait it out rather than calling the private
# helper, so the timer chain itself is under test.
#
# ⚠️ Waits on ELAPSED TIME, not on a frame count. Headless runs uncapped, so a frame
# budget that looks generous ("500 frames") can be a fraction of a second of the
# SceneTreeTimer time this is waiting for — which is exactly how this check first
# failed, reporting the wing dark when the scare simply had not finished yet.
func _do_aftermath() -> void:
	if _elapsed - _scare_started < 8.0:
		return
	var dark: Array = []
	for room in WING_ROOMS:
		var lamp := _scene.get_node_or_null("Lamp_" + room) as OmniLight3D
		if lamp == null or lamp.light_energy <= 0.01:
			dark.append(room)
	_ok("the wing lights up after the scare", dark.is_empty(), "still dark: %s" % [dark])

	# The Morgue is in NO_LAMP_ROOMS too and must NOT be caught by that exception —
	# its DarkZone, beartrap and don't-look triggers all assume a black room.
	var morgue := _scene.get_node_or_null("Lamp_Morgue") as OmniLight3D
	_ok("the Morgue stays dark", morgue != null and morgue.light_energy <= 0.01,
		"energy %.2f" % (morgue.light_energy if morgue else -1.0))

	# And the flashlight lock is released for good — the zone is gone, so walking back
	# in cannot re-lock it.
	var player := _scene.get_node_or_null("Player") as CharacterBody3D
	_ok("flashlight is usable again", player != null and not player._flashlight_locked)
	_phase = "done"
