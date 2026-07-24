extends SceneTree

# End-to-end completability proof for Level 6 — THE BREACH. Places the player
# safely inside the Incinerator and the creature in PurgeAnte, lets it detect and
# chase via its REAL state machine (no shortcuts), and seals the Purge Chamber the
# instant the creature's body physically enters the trap AABB (checked every frame,
# not assumed) — the same "physics-confirmed, not speculative" discipline the
# project's own tests use elsewhere. Never calls creature_trapped directly.
#
# ⚠️ The seal itself is driven through player._try_interact() — the SAME raycast-
# based path a real E-press uses — NOT a direct purge.interact() call. An earlier
# version of this test called interact() directly and passed cleanly while the
# actual game was unwinnable: both door scripts' only collision shape started
# disabled (Godot raycasts never hit a disabled shape), so a real player could
# never get an interact prompt on either door at all. Driving the real raycast
# path is what would have caught that immediately.
#   Godot --headless --path game --script res://tests/walk_level6_breach.gd

const STATE_CHASE := 2   # CreatureObject12.State enum order: PATROL/INVESTIGATE/CHASE/SEARCH/STAGGERED

var _level: Node
var _player: CharacterBody3D
var _creature: Node
var _purge: Node
var _phase := 0
var _t := 0.0
var _start_ms := 0
const HARD_TIMEOUT_MS := 45000


func _initialize() -> void:
	# ⚠️ Deliberately NOT accelerated (unlike test_creature_object12.gd). This test
	# measures a REACTION-TIME margin (creature closing a gap vs. the interact ray
	# resolving) — time_scale compresses both sides together, but real player input
	# still happens at real wall-clock speed, so an accelerated run understates the
	# real window and produced a false "instant death" here during development.
	_start_ms = Time.get_ticks_msec()
	change_scene_to_file("res://scenes/level_6_breach.tscn")


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _start_ms > HARD_TIMEOUT_MS:
		print("RESULT: FAIL (hard timeout at phase %d)" % _phase)
		return true

	if not _level:
		if not current_scene:
			return false   # change_scene_to_file() request hasn't resolved yet
		_level = current_scene
		_player = _level.get_node_or_null("Player")
		return false

	_t += _delta_or_frame()

	match _phase:
		0:
			_creature = _level.get("_creature")
			_purge = _level.get("_purge_chamber")
			if not _creature or not _purge:
				return false
			_player.global_position = Vector3(0, 0.1, 58.0)
			_player.rotation.y = PI
			var body = _creature.get("_body")
			if body:
				body.global_position = Vector3(0, 0, 52.0)
				body.rotation.y = 0.0
			_creature.call("activate")
			print("phase0: player @ z=58 (Incinerator), creature @ z=52 (PurgeAnte), activated")
			_phase = 1
			_t = 0.0

		1:
			var state = _creature.call("get_state")
			if state == STATE_CHASE:
				print("phase1: creature entered CHASE at t=%.2f" % _t)
				_phase = 2
				_t = 0.0
			elif _t > 10.0:
				print("RESULT: FAIL (creature never entered CHASE — state=%d)" % state)
				return true

		2:
			var pos: Vector3 = _creature.call("get_creature_position")
			var bounds: AABB = _purge.get("trap_bounds")
			if bounds.has_point(pos):
				print("phase2: creature entered trap bounds at t=%.2f, pos=%v — sidestepping to seal it" % [_t, pos])
				# Models a player who sprinted past and stepped to the SIDE rather
				# than turning around dead-center on top of the creature (that first
				# attempt put the player only 1.2m from a creature already AT the
				# doorway — real contact, real death, before the raycast even ran).
				# x=1.8 is ~1.8m from the creature's likely central position (safely
				# outside CONTACT_DIST=1.0) while still within INTERACT_RANGE (2.5)
				# of the door.
				# z=55.0, matching the door's own z — its collider is only 0.15m thick
				# in Z (centered at z=55), so a ray at z=55.5 (0.5m off) can NEVER
				# geometrically hit it no matter the x range or facing: this was the
				# real bug in the last two failed runs, not a rotation error.
				_player.global_position = Vector3(1.8, 0.1, 55.0)
				# player.gd's raycast forward is (-sin(y), 0, -cos(y)) for rotation.y=y
				# (verified against check_purge_interact.gd's passing rotation.y=PI
				# case, which must face +z) — PI/2 here faces -x, toward the door.
				_player.rotation.y = PI / 2.0
				_phase = 25
				_t = 0.0
			elif _t > 20.0:
				print("RESULT: FAIL (creature never reached the trap bounds — last pos=%v)" % pos)
				return true

		25:
			# Give _physics_process a couple of frames to resolve _interact_target via
			# the real raycast before "pressing E" through the same _try_interact()
			# player.gd's own input handler calls.
			var target = _player.get("_interact_target")
			if target != null and target.has_method("interact"):
				print("phase2b: interact target resolved to %s at t=%.2f — pressing E" % [target.name, _t])
				_player.call("_try_interact")
				_phase = 3
				_t = 0.0
			elif _t > 3.0:
				print("RESULT: FAIL (player's own interact raycast never resolved to the purge chamber — target=%s)" % [target])
				return true

		3:
			var defeated = _level.get("_creature_defeated")
			if defeated:
				print("RESULT: PASS — creature_defeated=true, win sequence confirmed end-to-end")
				return true
			elif _t > 6.0:
				print("RESULT: FAIL (sealed the door but creature_defeated never became true)")
				return true

	return false


var _last_ms := 0
func _delta_or_frame() -> float:
	var now := Time.get_ticks_msec()
	if _last_ms == 0:
		_last_ms = now
		return 0.0
	var d := (now - _last_ms) / 1000.0
	_last_ms = now
	return d
