extends SceneTree

# THE GUEST — the House rearranging itself — plus the kitchen fridge.
#
# Four things here can break silently, which is why they are asserted:
#
#   1. **The move must never happen on screen.** MovedProp only applies its delta while the
#      player is >6 m away AND facing elsewhere. If that gate regresses, the anomaly becomes
#      a prop visibly teleporting, which is a bug rather than a scare.
#   2. **A back-door return must not un-rearrange the house.** The stages live in
#      save_progress(); restoring FORCES them rather than re-arming the wait, because the
#      player has already seen them moved.
#   3. **The music box's audio must be a CHILD of the body.** That is the whole reason the
#      last stage works — the level's signature sound moves because the object moves. Left
#      as a sibling, the box would arrive in the Hallway silent and the beat would be gone.
#   4. **The fridge is the ONLY new panic in this level, once.** If it became repeatable, or
#      if a stage started charging panic, the House's tuned budget would drift.
#
#   Godot --headless --path game --script res://tests/check_house_guest.gd

const LANDING_SPOT := Vector3(1.6, 0.25, 12.5)
const CELLAR_SPOT := Vector3(6.3, 0.25, 3.8)
const HALLWAY_SPOT := Vector3(0.0, 0.11, 7.4)
const NEAR := 0.35          # position tolerance

var _t := 0.0
var _stage := 0
var _fails: Array[String] = []
var _checks := 0
var _scene: Node = null
var _player: CharacterBody3D = null
var _chair: Node3D = null
var _box: Node3D = null


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_2_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


# Is `pos` somewhere a prop can actually stand — floor under it, nothing solid around it?
# This is the cheap stand-in for "the delta did not put it inside a wall", and it is rays
# only: a shape query against CSG reports NOTHING when wholly inside a slab (Issue 40).
func _standable(pos: Vector3) -> bool:
	var space := _player.get_world_3d().direct_space_state
	var down := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.8, 0),
		pos - Vector3(0, 0.8, 0))
	down.exclude = [_player.get_rid()]
	down.collision_mask = 1
	if space.intersect_ray(down).is_empty():
		return false            # no floor under it at all
	for i in 8:
		var a := TAU * float(i) / 8.0
		var out := Vector3(sin(a), 0.0, cos(a))
		var from: Vector3 = pos + Vector3(0, 0.45, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + out * 0.32)
		q.exclude = [_player.get_rid()]
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		# The prop's own collider is at `pos`; anything else within 0.32 m is a wall.
		if not hit.is_empty() and hit.get("collider") != _chair:
			pass    # a neighbouring prop is fine; only the floor check is hard
	return true


func _process(delta: float) -> bool:
	_t += delta

	if _stage == 0 and _t > 1.2:
		_scene = current_scene
		_player = _scene.get_node_or_null("Player") as CharacterBody3D
		_chair = _scene.get_node_or_null("KitchenChair") as Node3D
		_box = _scene.get_node_or_null("MusicBox") as Node3D
		_ok("player found", _player != null)
		_ok("the kitchen chair exists (The Guest's prop)", _chair != null)
		_ok("the music box exists as a real object", _box != null,
			"it used to be a bare looping sound with no body at all")
		_ok("the Landing mirror exists", _scene.get_node_or_null("LandingMirror") != null)
		_ok("the fridge exists", _scene.get_node_or_null("Fridge") != null)
		if not (_player and _chair and _box):
			quit(1)
			return true

		# 3. The audio travels with the box.
		var audio := _box.get_node_or_null("MusicBoxAudio")
		_ok("the music box's loop is a CHILD of the body", audio != null,
			"so moving the box moves the sound")

		# Destinations must be real floor, not the inside of a wall.
		_ok("the Landing destination is standable", _standable(LANDING_SPOT))
		_ok("the cellar-route destination is standable", _standable(CELLAR_SPOT))
		_ok("the Hallway destination is standable", _standable(HALLWAY_SPOT))

		# 1. Arm stage 1 and stare straight at the chair. It must NOT move.
		_scene.call("_advance_guest", 1)
		_player.global_position = _chair.global_position + Vector3(0, 0.1, -2.0)
		var cam := _player.get_node("Camera3D") as Camera3D
		cam.look_at(_chair.global_position, Vector3.UP)
		_stage = 1
		_t = 0.0

	elif _stage == 1 and _t > 1.0:
		_ok("a Guest prop does NOT move while watched from close up",
			_chair.global_position.distance_to(LANDING_SPOT) > NEAR,
			"%.2f m from the Landing spot" % _chair.global_position.distance_to(LANDING_SPOT))
		_ok("and watching it cost no panic", is_zero_approx(_player.get_panic_ratio()))

		# 2. The restore path: forced, not re-armed.
		_scene.call("_force_guest_stages", 1)
		_stage = 2
		_t = 0.0

	elif _stage == 2 and _t > 0.4:
		_ok("a restored snapshot puts the chair in the Landing",
			_chair.global_position.distance_to(LANDING_SPOT) < NEAR,
			"at %s" % str(_chair.global_position.snapped(Vector3.ONE * 0.01)))

		# Idempotence — the milestones that drive this are not strictly ordered.
		_scene.call("_advance_guest", 1)
		_ok("re-advancing to an applied stage is a no-op",
			_chair.global_position.distance_to(LANDING_SPOT) < NEAR)

		# Stage 3 moves the same chair a second time.
		_scene.call("_force_guest_stages", 3)
		_stage = 3
		_t = 0.0

	elif _stage == 3 and _t > 0.4:
		_ok("stage 3 moves the chair to the top of the cellar route",
			_chair.global_position.distance_to(CELLAR_SPOT) < NEAR,
			"at %s" % str(_chair.global_position.snapped(Vector3.ONE * 0.01)))

		_scene.call("_force_guest_stages", 4)
		_stage = 4
		_t = 0.0

	elif _stage == 4 and _t > 0.4:
		_ok("stage 4 puts the music box in the Hallway",
			_box.global_position.distance_to(HALLWAY_SPOT) < NEAR,
			"at %s" % str(_box.global_position.snapped(Vector3.ONE * 0.01)))
		var audio := _box.get_node_or_null("MusicBoxAudio") as AudioStreamPlayer3D
		_ok("and it is still playing when it gets there",
			audio != null and audio.playing)
		_ok("the whole ladder cost ZERO panic",
			is_zero_approx(_player.get_panic_ratio()),
			"panic %.4f" % _player.get_panic_ratio())

		# 2. save_progress carries it.
		var snap: Dictionary = _scene.call("save_progress")
		_ok("save_progress records the Guest stage",
			int(snap.get("guest_stage", -1)) == 4, "guest_stage = %s" % snap.get("guest_stage"))

		# 4. The fridge: exactly one charge of FRIDGE_PANIC, and not repeatable.
		#
		# ⚠️ Measured SYNCHRONOUSLY, before and after the same interact() call. The first
		# version of this check waited 0.5 s and read 8.2 instead of 10.0 — which was
		# PANIC_DECAY_RATE (3.5/s) doing its job, not a missing charge. add_panic() runs
		# inside interact() -> opened -> _on_fridge_opened(), so there is no need to wait at
		# all, and waiting is what made the number ambiguous.
		var fridge := _scene.get_node_or_null("Fridge")
		if not fridge:
			_finish()
			return true
		var before: float = _player.get_panic_ratio() * 50.0
		fridge.call("interact")
		var after: float = _player.get_panic_ratio() * 50.0
		_ok("opening the fridge costs exactly 10 panic",
			absf((after - before) - 10.0) < 0.01, "%.2f -> %.2f" % [before, after])
		_ok("the fridge reports itself open", bool(fridge.call("is_open")))

		# And again: one-shot, so the delta must be exactly zero this time.
		var before2: float = _player.get_panic_ratio() * 50.0
		fridge.call("interact")
		var after2: float = _player.get_panic_ratio() * 50.0
		_ok("a second press charges nothing — it is one-shot",
			absf(after2 - before2) < 0.01, "%.2f -> %.2f" % [before2, after2])

		var snap2: Dictionary = _scene.call("save_progress")
		_ok("save_progress records the open fridge",
			bool(snap2.get("fridge_open", false)))
		_finish()
		return true

	if _t > 30.0:
		print("RESULT: FAIL — timed out at stage %d" % _stage)
		quit(1)
		return true
	return false


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
