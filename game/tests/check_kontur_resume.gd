extends SceneTree

# KONTUR MUST COME BACK THE SAME LEVEL IT WAS, AND WITH THE DOORS IT ALREADY OPENED.
#
#   Godot --headless --path game --script res://tests/check_kontur_resume.gd
#
# WHY THIS EXISTS. Two defects, both in the same code path, both found on 2026-08-18
# (backlogs/05-kontur.md K-T6, cross-level X48):
#
#   1. `save_progress()` wrote "dark_x" and NOTHING EVER READ IT BACK, and the gate-1
#      colour was never saved at all. So walking out of KONTUR and back in re-rolled
#      the answers to gates 1 and 7 while restoring the ledger earned against the OLD
#      ones. `CLAUDE.md` states the rule this violates verbatim: "restoring the gate
#      ledger while re-rolling the answers would mark gates passed whose puzzles now
#      have different solutions."
#
#   2. Worse, and found while fixing (1): `_restore_progress()` restored the LEDGER and
#      `_ready()` rebuilt every physical SEAL from scratch. `AirlockSeal` is a solid
#      CSGBox3D across the Airlock->Escort doorway, and `_tick_airlock()` opens with
#      `if _gates["airlock"] ... return` — so on a resumed run nothing could ever remove
#      it again. A player who cleared gate 8, walked back for a note and returned was
#      WALLED IN. That is a soft-lock, in the level with the most saved state in the
#      game, reachable by using a door the game gives you.
#
# WHAT IT DRIVES, AND WHAT IT DOES NOT.
#   * Gate 1 is passed through the SHIPPING interact ray — `player.ai_interact()`, which
#     calls the same `_try_interact()` the E key calls, so `can_interact()`, the raycast
#     and the prompt all run. Never `door.interact()` directly (Issue 30).
#   * Gate 2 likewise: take the vinegar off the shelf by ray, then spray the barrier by
#     ray. Both are real props answering a real ray.
#   * Gate 8 calls `kontur.gd:_pass_airlock()` — the level's OWN success handler,
#     extracted from `_tick_airlock()` for exactly this reason. The catch itself polls
#     `Input.is_action_just_pressed`, which cannot be faked headless, so the alternative
#     was a test that re-implemented "free the seal" and then asserted its own code.
#   * Gate 5 emits `RosterLock.unlocked`, and that is the one signal-driven step here.
#     `combination_lock.gd` opens a paused 2D dial UI and there is no headless way to
#     type into it; the code the signal runs is the shipping lambda in `kontur.gd`.
#
# CONTROLS (both permanent, both run every time):
#   A. after asserting the Airlock doorway is CLEAR on the resumed run, a fresh solid
#      box is dropped into it and the SAME ray must report BLOCKED. A doorway probe that
#      cannot see a seal would pass this test on a level that was still walled shut.
#   B. the level is re-rolled at a second seed with NO snapshot, and must produce a
#      DIFFERENT `_dark_x` and a DIFFERENT gate-1 colour. Without that, "restored" is
#      indistinguishable from "there was only ever one answer".

const Scenes := preload("res://tests/lib/scenes.gd")

# Measured on this build: seed 5 -> _dark_x -3.0, black door WEST;
#                         seed 2 -> _dark_x  0.0, black door EAST.
# Both differ in both halves, which is what makes control B a real control. If either
# changes, the control fails loudly rather than degrading into a no-op.
const SEED_A := 5
const SEED_B := 2

const SETTLE := 1.6

var _fails := 0
var _phase := 0
var _t := 0.0
var _gs: Node

var _dark_x_a := 0.0
var _black_east_a := false
var _strikes_before := 0


func _initialize() -> void:
	Scenes.pin_rng(SEED_A)
	change_scene_to_file("res://scenes/kontur.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails += 1


func _process(delta: float) -> bool:
	_t += delta
	if _t < SETTLE:
		return false
	_t = 0.0

	if _gs == null:
		_gs = root.get_node_or_null("GameState")
		if _gs == null:
			print("FAIL: no GameState")
			quit(1)
			return true
		_gs.set("level_progress", {})

	match _phase:
		0: _phase_build()
		1: _phase_after_return()
		2: _phase_control_b()
		3: _phase_control_b_check()
	return false


# ---------------------------------------------------------------- phase 0

func _phase_build() -> void:
	var k := current_scene
	print("--- KONTUR built at seed %d ---" % SEED_A)
	_ok("the level exposes save_progress()", k.has_method("save_progress"))
	_dark_x_a = float(k.get("_dark_x"))
	_black_east_a = bool(k.get("_gate1_black_east"))
	print("  dark_x=%.1f  black door %s" % [_dark_x_a, "EAST" if _black_east_a else "WEST"])
	_ok("the snapshot records dark_x",
		(k.call("save_progress") as Dictionary).has("dark_x"))
	_ok("the snapshot records the gate-1 colour",
		(k.call("save_progress") as Dictionary).has("gate1_black_east"),
		"<- this key did not exist before 2026-08-18")

	var p := k.get_node_or_null("Player") as CharacterBody3D
	if p == null:
		_ok("Player present", false)
		_finish()
		return
	p.set("ai_active", true)
	_strikes_before = int(k.get("_strikes"))

	# ---- gate 1, through the real interact ray -----------------------------------
	var gate_x: float = 2.0 if _black_east_a else -2.0
	p.global_position = Vector3(gate_x, 0.1, 8.4)
	p.velocity = Vector3.ZERO
	p.call("ai_look_at", Vector3(gate_x, 1.1, 10.0))
	var target: Node = p.call("ai_interact_target")
	_ok("the black door answers the interact ray",
		target != null and String(target.name).begins_with("ChoiceDoor_Black"),
		"target=%s" % (target.name if target else "<none>"))
	p.call("ai_interact")
	_ok("gate 1 is passed", bool((k.get("_gates") as Dictionary)["doors"]))

	# ---- gate 2, through the real interact ray ------------------------------------
	p.global_position = Vector3(2.4, 0.1, 23.5)
	p.velocity = Vector3.ZERO
	p.call("ai_look_at", Vector3(3.4, 1.1, 23.5))
	var bottle: Node = p.call("ai_interact_target")
	_ok("the vinegar bottle answers the interact ray",
		bottle != null and String(bottle.name) == "Bottle_vinegar",
		"target=%s" % (bottle.name if bottle else "<none>"))
	p.call("ai_interact")
	p.global_position = Vector3(0.0, 0.1, 25.6)
	p.velocity = Vector3.ZERO
	p.call("ai_look_at", Vector3(0.0, 1.5, 27.0))
	var barrier: Node = p.call("ai_interact_target")
	_ok("the fungal barrier answers the interact ray",
		barrier != null and String(barrier.name) == "FungalBarrier",
		"target=%s" % (barrier.name if barrier else "<none>"))
	p.call("ai_interact")
	_ok("gate 2 is passed", bool((k.get("_gates") as Dictionary)["shelf"]))
	_ok("and it cost no strike", int(k.get("_strikes")) == _strikes_before,
		"strikes=%d" % int(k.get("_strikes")))

	# ---- gates 5 and 8 -------------------------------------------------------------
	var lock := k.get_node_or_null("RosterLock")
	if lock:
		lock.emit_signal("unlocked")
	_ok("gate 5 is passed", bool((k.get("_gates") as Dictionary)["roster"]))
	k.call("_pass_airlock")
	_ok("gate 8 is passed", bool((k.get("_gates") as Dictionary)["airlock"]))
	# ⚠️ `queue_free()` is deferred to the end of the frame, so the seal is STILL A CHILD
	# on the frame the gate is passed (the same deferral kontur.gd's `_clear_old_scene()`
	# documents). Ask whether it is condemned, not whether it is absent.
	var seal := k.get_node_or_null("AirlockSeal")
	_ok("the AirlockSeal is condemned on the FIRST pass",
		seal == null or seal.is_queued_for_deletion())

	# Leave forward and come straight back, the real way. A different seed is pinned
	# first, so a level that re-rolled would demonstrably land somewhere else.
	print("--- advance to the Breach, then walk back in ---")
	_gs.call("advance_level")
	Scenes.pin_rng(SEED_B)
	_gs.call("go_back")
	_phase = 1


# ---------------------------------------------------------------- phase 1

func _phase_after_return() -> void:
	var k := current_scene
	_ok("back in KONTUR", int(_gs.get("current_level")) == 5)
	_ok("entered_from_ahead is true", _gs.get("entered_from_ahead") == true)

	var dark_x := float(k.get("_dark_x"))
	var black_east := bool(k.get("_gate1_black_east"))
	_ok("dark_x survived the round trip", is_equal_approx(dark_x, _dark_x_a),
		"was %.1f, now %.1f" % [_dark_x_a, dark_x])
	_ok("the gate-1 colour survived the round trip", black_east == _black_east_a,
		"was %s, now %s" % [_black_east_a, black_east])

	# The randomisation is not a number in a variable — it is where the level IS.
	var real_seam := _find_prefixed(k, "DarkSeam_real")
	_ok("the REAL dark seam is at the restored offset",
		real_seam != null and absf(real_seam.global_position.x - _dark_x_a) < 0.01,
		"seam x=%.2f" % (real_seam.global_position.x if real_seam else -999.0))
	var exit_door := k.get_node_or_null("ExitDoor") as Node3D
	_ok("the exit door is on the restored spine",
		exit_door != null and absf(exit_door.global_position.x - _dark_x_a) < 0.01,
		"door x=%.2f" % (exit_door.global_position.x if exit_door else -999.0))
	var hole_x: float = -2.0 if _black_east_a else 2.0
	_ok("the hole in the floor is still under the RED antechamber",
		_floor_missing(k, hole_x, 12.0) and _floor_present(k, -hole_x, 12.0),
		"probed x=%.1f (red) and x=%.1f (black)" % [hole_x, -hole_x])

	# The ledger came back.
	var gates: Dictionary = k.get("_gates")
	for key in ["doors", "shelf", "roster", "airlock"]:
		_ok("gate '%s' is still passed" % key, bool(gates[key]))

	# ...and so did the world it describes. This is the soft-lock half.
	# ⚠️ Probed at the LIVE `_dark_x`, not at the remembered one, and paired with a node
	# check. With the fix disabled the spine moves, so a ray fired at the remembered
	# offset finds open air and reports "clear" for entirely the wrong reason — measured.
	# A probe that can pass on a broken build is a probe that measures nothing.
	_ok("the AirlockSeal is not rebuilt", k.get_node_or_null("AirlockSeal") == null,
		"<- it used to come back solid with no way to remove it: a soft-lock")
	_ok("the Airlock doorway is CLEAR again", _doorway_clear(k, dark_x, 66.0))
	_ok("the RosterSeal is gone", k.get_node_or_null("RosterSeal") == null)
	_ok("the fungal barrier is gone or dissolving",
		_barrier_open(k.get_node_or_null("FungalBarrier")))
	var blk := _find_prefixed(k, "ChoiceDoor_Black")
	_ok("the black door is standing open",
		blk != null and absf(blk.rotation.y) > deg_to_rad(80.0),
		"rotation.y=%.1f deg" % (rad_to_deg(blk.rotation.y) if blk else 0.0))

	# CONTROL A — prove the doorway probe can still see a seal.
	var plug := CSGBox3D.new()
	plug.name = "ControlPlug"
	plug.size = Vector3(1.8, 3.0, 0.3)
	plug.position = Vector3(_dark_x_a, 1.5, 66.0)
	plug.use_collision = true
	k.add_child(plug)
	_phase = 2


# ---------------------------------------------------------------- phase 2

func _phase_control_b() -> void:
	var k := current_scene
	print("--- controls ---")
	_ok("CONTROL A: a fresh plug in the Airlock doorway reads BLOCKED",
		not _doorway_clear(k, _dark_x_a, 66.0),
		"<- if this passes while the plug is there, the probe measures nothing")
	var plug := k.get_node_or_null("ControlPlug")
	if plug:
		k.remove_child(plug)
		plug.queue_free()

	# CONTROL B — with no snapshot at all, a different seed must roll a different level.
	_gs.set("level_progress", {})
	_gs.set("entered_from_ahead", false)
	Scenes.pin_rng(SEED_B)
	_gs.set("current_level", 5)
	_gs.call("start_current_level")
	_phase = 3


func _phase_control_b_check() -> void:
	var k := current_scene
	var dx := float(k.get("_dark_x"))
	var be := bool(k.get("_gate1_black_east"))
	_ok("CONTROL B: an unsaved run at seed %d rolls a DIFFERENT dark_x" % SEED_B,
		not is_equal_approx(dx, _dark_x_a), "seed %d -> %.1f, seed %d -> %.1f"
			% [SEED_A, _dark_x_a, SEED_B, dx])
	_ok("CONTROL B: ...and a DIFFERENT gate-1 colour", be != _black_east_a,
		"seed %d -> %s, seed %d -> %s" % [SEED_A, _black_east_a, SEED_B, be])
	_finish()


func _finish() -> void:
	print("--------------------------------------------------")
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	print("--------------------------------------------------")
	quit(0 if _fails == 0 else 1)


# ---------------------------------------------------------------- probes

func _space() -> PhysicsDirectSpaceState3D:
	var p := current_scene.get_node_or_null("Player") as CharacterBody3D
	if p == null:
		return null
	return p.get_world_3d().direct_space_state


# A ray straight through the doorway plane at head height, the same probe
# check_kontur.gd uses. Physics, never a node lookup — a seal that is `visible = false`
# but still solid is exactly the failure a node lookup cannot see.
func _doorway_clear(k: Node, x: float, z: float) -> bool:
	var space := _space()
	if space == null:
		return false
	var p := k.get_node_or_null("Player") as CharacterBody3D
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, 1.6, z - 1.8), Vector3(x, 1.6, z + 1.8))
	q.exclude = [p.get_rid()]
	return space.intersect_ray(q).is_empty()


func _floor_present(k: Node, x: float, z: float) -> bool:
	var space := _space()
	if space == null:
		return false
	var p := k.get_node_or_null("Player") as CharacterBody3D
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 1.0, z), Vector3(x, -1.5, z))
	q.exclude = [p.get_rid()]
	return not space.intersect_ray(q).is_empty()


func _floor_missing(k: Node, x: float, z: float) -> bool:
	return not _floor_present(k, x, z)


func _barrier_open(b: Node) -> bool:
	if b == null:
		return true
	return bool(b.get("_open"))


func _find_prefixed(root_node: Node, prefix: String) -> Node3D:
	for child in root_node.get_children():
		if String(child.name).begins_with(prefix) and child is Node3D:
			return child as Node3D
	return null
