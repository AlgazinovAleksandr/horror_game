extends SceneTree

# The child's music box: winding it plays the RECORDING, ducks the room-tone bed under it,
# and — the part that matters — puts the bed BACK afterwards.
#
#   Godot --headless --path game --script res://tests/check_music_box.gd
#
# ⚠️ Why the "afterwards" half is not optional. This project has a documented case of exactly
# this shape: `corridor.gd:_tick_hush()` pulled the Ambience bus to −40 dB at 296 m and never
# restored it, which silenced every level entered after the Corridor for the rest of the
# session (Issue 50, `check_bus_leak.gd`). A one-shot before/during probe structurally cannot
# see a duck that never comes back — it has to watch past the wind-down.
#
# ⚠️ Assert `_tune_audio` is there FIRST. `music_box.gd` deliberately falls back to a
# one-stream behaviour when the recording is missing, and a test that did not check would
# quietly measure the fallback and report a tidy pass on a box that plays nothing new.
#
# ⚠️ PLAY_TIME is 22 s. It is burned by calling the node's own `_process()` with a big delta
# rather than by waiting, so this costs ~4 s instead of ~26 — but the WIND-DOWN is waited out
# in REAL time, because it is a Tween and a Tween only advances on real frames.

const DB_TOL := 1.2
const TIMEOUT := 30.0

var _t := 0.0
var _stage := 0
var _checks := 0
var _fails: Array[String] = []
var _box: Node = null
var _bed: AudioStreamPlayer3D = null
var _tune: AudioStreamPlayer3D = null
var _loud := 0.0
var _idle := 0.0
var _duck := 0.0
var _play_time := 0.0


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_2_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _find(node: Node, cls: String) -> Node:
	if node.get_script() and String(node.get_script().get_global_name()) == cls:
		return node
	for c in node.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null


func _process(delta: float) -> bool:
	_t += delta

	if _stage == 0 and _t > 1.2:
		_box = _find(current_scene, "MusicBoxProp")
		_ok("the windable music box exists", _box != null)
		if not _box:
			_finish()
			return true
		_bed = _box.get("_audio")
		_tune = _box.get("_tune_audio")
		# ⚠️ THE GUARD THAT KEEPS THIS TEST FROM MEASURING NOTHING.
		_ok("the wind RECORDING is wired, not just the room-tone bed", _tune != null,
			"music_box.gd falls back to one stream when it is missing")
		_ok("the room-tone bed is wired", _bed != null)
		if not (_tune and _bed):
			_finish()
			return true
		# ⚠️ Both must be CHILDREN of the box body — that is the only reason THE GUEST's last
		# stage works, because the sound travels with the object when the house moves it.
		# `level_2.gd` parents the box body, both streams and this script's node to the same
		# CSGBox3D — which is why MovedProp carrying the body carries the sound with it.
		_ok("both streams hang off the same box body as the crank, so the sound moves with it",
			_bed.get_parent() == _box.get_parent() and _tune.get_parent() == _box.get_parent(),
			"bed under %s, tune under %s, crank under %s" % [
				_bed.get_parent().name, _tune.get_parent().name, _box.get_parent().name])

		var consts: Dictionary = (_box.get_script() as GDScript).get_script_constant_map()
		_loud = float(consts.get("LOUD_DB", 999.0))
		_idle = float(consts.get("IDLE_DB", 999.0))
		_duck = float(consts.get("BED_DUCK_DB", 999.0))
		_play_time = float(consts.get("PLAY_TIME", 0.0))
		_ok("read the script's own gain constants",
			_loud < 900.0 and _idle < 900.0 and _duck < 900.0 and _play_time > 1.0,
			"loud %.1f / idle %.1f / duck %.1f / %.0f s" % [_loud, _idle, _duck, _play_time])

		_ok("the bed starts at its idle level", absf(_bed.volume_db - _idle) < DB_TOL,
			"%.1f dB" % _bed.volume_db)
		_ok("the recording is silent and not playing before a wind",
			not _tune.playing, "volume %.1f dB" % _tune.volume_db)

		_box.call("interact")
		_stage = 1
		_t = 0.0

	elif _stage == 1 and _t > 0.7:      # the two gain tweens are 0.35 s
		_ok("winding it starts the recording", _tune.playing)
		_ok("…at the loud level", absf(_tune.volume_db - _loud) < DB_TOL,
			"%.1f dB, want %.1f" % [_tune.volume_db, _loud])
		# ⚠️ DUCKED, never stopped — the room must not go silent between the two streams.
		_ok("…and the room-tone bed ducks UNDER it rather than stopping",
			absf(_bed.volume_db - _duck) < DB_TOL and _bed.playing,
			"%.1f dB, want %.1f, playing=%s" % [_bed.volume_db, _duck, _bed.playing])

		# Burn PLAY_TIME by hand. `_process` is the node's own, so the wind-down it triggers is
		# the shipping path; only the waiting is skipped.
		_box.call("_process", _play_time + 1.0)
		_ok("the tune is marked as finished", _box.get("_playing_loud") == false)
		_stage = 2
		_t = 0.0

	elif _stage == 2 and _t > 2.9:      # the wind-down tweens are 2.5 s, in REAL time
		# ⚠️ THE ASSERTION THIS FILE EXISTS FOR.
		_ok("the bed comes BACK to its idle level", absf(_bed.volume_db - _idle) < DB_TOL,
			"%.1f dB, want %.1f — a duck with no restore is Issue 50" % [_bed.volume_db, _idle])
		_ok("…and the recording has stopped", not _tune.playing,
			"volume %.1f dB" % _tune.volume_db)

		# And it is re-windable — no resource, no fail state, no one-shot.
		_box.call("interact")
		_stage = 3
		_t = 0.0

	elif _stage == 3 and _t > 0.7:
		_ok("it can be wound again", _tune.playing
			and absf(_tune.volume_db - _loud) < DB_TOL,
			"%.1f dB" % _tune.volume_db)
		_finish()
		return true

	if _t > TIMEOUT:
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
