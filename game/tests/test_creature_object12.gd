extends SceneTree

# Headless behavior test for Object 12's state machine (creature_object12.gd).
# Proves, in order, via SIGNALS ONLY (never private state, matching
# test_apparition.gd's convention):
#   1. Dormant until activate() — stays PATROL, does not move.
#   2. PATROL -> CHASE on detecting the (visible, non-hidden) stub player.
#   3. CHASE -> SEARCH when the player leaves detection range.
#   4. SEARCH -> PATROL after SEARCH_TIME with no re-detection.
#   5. CHASE -> STAGGERED from sustained apply_light_damage(), `staggered` fires.
#   6. STAGGERED -> SEARCH (not CHASE) after a randomised STAGGER_MIN..STAGGER_MAX,
#      and light applied OUTSIDE a chase neither staggers nor drains the shield.
#   7. is_hidden() == true suppresses detection entirely — no CHASE transition.
#   8. Contact within CONTACT_DIST during CHASE fires `contact_fatal`.
#
# Engine.time_scale is raised so real waits (SEARCH_TIME=8s, the 5-7s stagger)
# don't cost that many real seconds — every timer in the creature is delta-based,
# so this doesn't change correctness.
#
# Run: Godot --headless --path game --script res://tests/test_creature_object12.gd

class StubPlayer extends CharacterBody3D:
	var hidden := false
	func is_hidden() -> bool: return hidden
	# creature_object12.gd resolves the player via the "player" group (the same
	# lookup player.gd itself registers into — Issue 12), not a relative node path.
	func _ready() -> void: add_to_group("player")


var _CREATURE_SCRIPT: GDScript

var _world: Node3D
var _player: StubPlayer
var _cam: Camera3D
var _creature: Node3D

var _setup_done := false
var _phase := 0
var _t := 0.0

var _last_old_state: int = -1
var _last_new_state: int = -1
var _staggered_fired := false
var _contact_fired := false
var _stagger_duration := -1.0    # what the `staggered` signal announced
var _stagger_started_at := -1.0
var _stagger_measured := -1.0    # what it actually lasted, in game seconds
# ⚠️ A clock of its own. `_t` is the PHASE timer and _advance() resets it to 0, so
# timing anything that spans a phase boundary against `_t` silently measures only the
# tail — the stagger begins in phase 4 and ends in phase 5, and reading `_t` reported
# 3.44 s for a 6.12 s stagger and flagged correct code as broken.
var _clock := 0.0

var _results: Dictionary = {}
var _start_ms: int = 0
const HARD_TIMEOUT_MS := 90000


func _initialize() -> void:
	_start_ms = Time.get_ticks_msec()
	Engine.time_scale = 25.0
	# creature_object12.gd calls Screamer.trigger() internally, so a top-level
	# preload() here would hit the same "Identifier not found: Screamer" trap
	# test_apparition.gd documents — load it at runtime instead, after autoloads
	# are registered.
	_CREATURE_SCRIPT = load("res://scripts/creature_object12.gd")


func _setup() -> void:
	_world = Node3D.new()
	root.add_child(_world)

	_player = StubPlayer.new()
	_player.name = "Player"
	_cam = Camera3D.new()
	_cam.name = "Camera3D"
	_cam.position = Vector3(0, 1.65, 0)   # match player.gd's real eye height
	_player.add_child(_cam)
	_world.add_child(_player)
	_player.global_position = Vector3(0, 0, 20)   # far away, out of DETECT_RANGE (10)

	_creature = _CREATURE_SCRIPT.new()
	_creature.position = Vector3.ZERO
	_world.add_child(_creature)
	# Real waypoints (never empty in production use) matter here: with none, PATROL
	# never rotates the creature, so whatever facing a prior SEARCH scan happened to
	# leave it at is permanent — re-detection in a later phase becomes a coin flip
	# on random facing instead of a deterministic assertion. A small loop keeps it
	# sweeping, closer to how level_6_breach.gd actually drives it.
	_creature.set_waypoints(PackedVector3Array([
		Vector3(3, 0, 0), Vector3(0, 0, 3), Vector3(-3, 0, 0), Vector3(0, 0, -3),
	]))
	_creature.state_changed.connect(_on_state_changed)
	_creature.staggered.connect(func(d):
		_staggered_fired = true
		_stagger_duration = d
		_stagger_started_at = _clock
	)
	_creature.recovered.connect(func():
		if _stagger_started_at >= 0.0:
			_stagger_measured = _clock - _stagger_started_at
	)
	_creature.contact_fatal.connect(func(): _contact_fired = true)

	_phase = 0
	_t = 0.0


func _on_state_changed(old: int, new: int) -> void:
	_last_old_state = old
	_last_new_state = new


func _process(delta: float) -> bool:
	if not _setup_done:
		_setup_done = true
		_setup()
		return false

	if Time.get_ticks_msec() - _start_ms > HARD_TIMEOUT_MS:
		print("HARD TIMEOUT — stuck in phase %d (state=%d)" % [_phase, _creature.get_state()])
		_results["hard_timeout_hit_phase_%d" % _phase] = false
		return _finish()

	_t += delta
	_clock += delta

	match _phase:
		0:
			# Dormant: not activated yet. Stub sits far away regardless; assert no
			# movement and no state change after a short settle.
			if _t > 0.3:
				_results["dormant_no_move"] = _creature.get_creature_position().distance_to(Vector3.ZERO) < 0.01
				_results["dormant_state_patrol"] = _creature.get_state() == _CREATURE_SCRIPT.State.PATROL
				_creature.activate()
				_player.global_position = Vector3(0, 0, 2)   # inside DETECT_RANGE, in FOV
				_advance(1)

		1:
			# PATROL -> CHASE on detection.
			if _last_new_state == _CREATURE_SCRIPT.State.CHASE:
				_results["patrol_to_chase"] = true
				_player.global_position = Vector3(0, 0, 50)   # well outside DETECT_RANGE
				_advance(2)
			elif _t > 3.0:
				_results["patrol_to_chase"] = false
				_advance(2)

		2:
			# CHASE -> SEARCH once the player is out of range past LOS_LOSS_GRACE.
			if _last_new_state == _CREATURE_SCRIPT.State.SEARCH:
				_results["chase_to_search"] = true
				_advance(3)
			elif _t > 2.0:
				_results["chase_to_search"] = false
				_advance(3)

		3:
			# SEARCH -> PATROL after SEARCH_TIME with nothing re-detected. While that
			# runs, hose it with light the whole time: outside CHASE this must have NO
			# effect at all. Before BACKLOG #26 the shield drained in every state while
			# the stagger could only fire from CHASE/INVESTIGATE, so a player lighting
			# up a creature that had not locked on emptied the pool for nothing and
			# read the result as "the blind lasted no time".
			_creature.apply_light_damage(delta)
			if _last_new_state == _CREATURE_SCRIPT.State.PATROL:
				_results["search_to_patrol"] = true
				_results["light_outside_chase_does_not_stagger"] = not _staggered_fired
				_results["light_outside_chase_does_not_drain"] = \
					_creature.get_shield_ratio() > 0.99
				_player.global_position = Vector3(0, 0, 2)   # back in view -> re-CHASE
				_advance(4)
			elif _t > 10.0:
				_results["search_to_patrol"] = false
				_advance(4)

		4:
			# Re-trigger CHASE, then drain the shield via apply_light_damage(). Keep a
			# safe gap from the creature throughout — apply_light_damage() is called
			# directly here (this test exercises the creature's OWN shield bookkeeping,
			# not the level's geometric light-cone gate), so proximity isn't needed for
			# the drain itself, and letting CHASE actually catch the stub would fire a
			# REAL contact_fatal + Screamer.trigger(), which reloads a whole real scene
			# (intro_room.tscn) inside this test's SceneTree — reserve that for phase 7.
			if _last_new_state == _CREATURE_SCRIPT.State.CHASE:
				var cpos: Vector3 = _creature.get_creature_position()
				if _player.global_position.distance_to(cpos) < 3.0:
					_player.global_position = cpos + Vector3(0, 0, 8.0)
				_creature.apply_light_damage(delta)
				if _last_new_state == _CREATURE_SCRIPT.State.STAGGERED:
					_results["chase_to_staggered"] = true
					_results["staggered_signal_fired"] = _staggered_fired
					_advance(5)
			elif _t > 10.0:
				_results["chase_to_staggered"] = false
				_results["staggered_signal_fired"] = false
				_advance(5)

		5:
			# STAGGERED -> SEARCH (not CHASE) after STAGGER_DURATION.
			if _last_new_state == _CREATURE_SCRIPT.State.SEARCH and \
					_last_old_state == _CREATURE_SCRIPT.State.STAGGERED:
				_results["staggered_to_search"] = true
				var lo: float = _CREATURE_SCRIPT.STAGGER_MIN
				var hi: float = _CREATURE_SCRIPT.STAGGER_MAX
				_results["stagger_announced_in_range"] = \
					_stagger_duration >= lo and _stagger_duration <= hi
				# 0.5 s of slack: the recovery is detected on a frame boundary.
				_results["stagger_lasted_as_announced"] = \
					absf(_stagger_measured - _stagger_duration) < 0.5
				print("   stagger announced %.2f s, measured %.2f s (allowed %.0f-%.0f)"
					% [_stagger_duration, _stagger_measured, lo, hi])
				_advance(6)
			elif _t > 30.0:
				_results["staggered_to_search"] = false
				_advance(6)

		6:
			# Hidden suppresses detection entirely — stay clear of CHASE.
			_player.hidden = true
			_player.global_position = Vector3(0, 0, 2)   # in FOV/range, but hidden
			if _t > 3.0:
				_results["hidden_suppresses_detection"] = _creature.get_state() != _CREATURE_SCRIPT.State.CHASE
				_player.hidden = false
				_advance(7)

		7:
			# Contact within CONTACT_DIST during CHASE -> contact_fatal. Nudge it
			# toward the player once via notify_noise() rather than relying purely on
			# the patrol loop's facing lining up by chance within the timeout window.
			if _t < 0.01:
				_creature.notify_noise(Vector3(0, 0, 2), 20.0)
			if _creature.get_state() != _CREATURE_SCRIPT.State.CHASE:
				_player.global_position = Vector3(0, 0, 2)
			else:
				_player.global_position = _creature.get_creature_position()
			if _contact_fired:
				_results["contact_fatal_fires"] = true
				return _finish()
			elif _t > 60.0:
				_results["contact_fatal_fires"] = false
				return _finish()

	return false


func _advance(phase: int) -> void:
	print("PHASE %d -> %d @ %.1fs wall" % [_phase, phase, (Time.get_ticks_msec() - _start_ms) / 1000.0])
	_phase = phase
	_t = 0.0
	_last_old_state = -1
	_last_new_state = -1


func _finish() -> bool:
	print("--------------------------------------------------")
	var all_ok := true
	for key in _results:
		var ok: bool = _results[key]
		all_ok = all_ok and ok
		print("  %-32s %s" % [key, "PASS" if ok else "FAIL"])
	print("RESULT: ", "ALL PASS" if all_ok else "FAILURE")
	print("--------------------------------------------------")
	quit(0 if all_ok else 1)
	return true
