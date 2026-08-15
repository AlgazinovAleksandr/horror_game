extends SceneTree

# Does a level's audio duck follow the player into the NEXT level?
#
#   Godot --headless --path game --script res://tests/check_bus_leak.gd
#
# User report, 2026-08-15: "the music in the backrooms disappeared after I got there from
# the corridor. But when I started the backrooms scene from scratch, the music was there."
#
# That is a global-state bug wearing a level-specific costume. `AudioServer` buses are
# process-global: `change_scene_to_file()` frees the scene and leaves every bus volume
# exactly where the last level left it, `AudioBuses.ensure()` early-returns on an existing
# bus without touching its volume, and every per-level bed bus is routed INTO `Ambience`.
# So `corridor.gd:_tick_hush()` — which tweens `Ambience` to -40 dB at 296 m and had no
# restore of any kind — silenced not just the Backrooms but every level for the rest of
# the session. Loading the Backrooms directly worked because nothing had hushed it yet.
#
# ⚠️ No existing test could see this. Every audio test loads ONE scene and asserts within
# it; the fault only exists in the seam BETWEEN two scenes. That is the whole point of this
# file, and the reason it drives a real level transition rather than poking the mixer.

const HUSH_MARGIN := 6.0    # seconds to let the hush tween (3 s) finish

var _t := 0.0
var _stage := 0
var _fails: Array[String] = []
var _checks := 0
var _gs: Node


func _initialize() -> void:
	change_scene_to_file("res://scenes/corridor.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print("  %s  %s%s" % ["OK  " if cond else "FAIL", label, ("  " + detail) if detail else ""])
	if not cond:
		_fails.append(label)


func _db(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	return 999.0 if i == -1 else AudioServer.get_bus_volume_db(i)


func _process(delta: float) -> bool:
	_t += delta
	match _stage:
		0:
			if _t < 1.0:
				return false
			# ⚠️ Through the node, never the bare identifier — `GameState` as a name is a
			# compile error in a SceneTree script (check_journal.gd:21).
			_gs = root.get_node_or_null("/root/GameState")
			_ok("GameState autoload present", _gs != null)
			if _gs == null:
				return _report()
			_ok("Ambience starts at 0 dB", absf(_db("Ambience")) < 0.01,
				"%.1f dB" % _db("Ambience"))

			# Walk the corridor past HUSH_AT so the level ducks the bus for real, using its
			# own high-water mark rather than reaching into the tween.
			var scene := current_scene
			var hush_at: float = float(scene.get_script().get("HUSH_AT"))
			scene.set("_furthest_reached", hush_at + 1.0)
			_stage = 1
			_t = 0.0

		1:
			if _t < HUSH_MARGIN:
				return false
			# The hush is the level doing its job — this must be ducked right now.
			_ok("the corridor's hush ducks Ambience", _db("Ambience") < -20.0,
				"%.1f dB" % _db("Ambience"))
			# Now leave, the way the noclip does.
			_gs.call("advance_level")
			_stage = 2
			_t = 0.0

		2:
			if _t < 2.0:
				return false
			# ⭐ THE ASSERTION. Whatever the Corridor did to the mixer must not have
			# followed us here.
			_ok("we arrived in the Backrooms", int(_gs.get("current_level")) == 4,
				"level %d" % int(_gs.get("current_level")))
			_ok("Ambience is restored on arrival", absf(_db("Ambience")) < 0.01,
				"%.1f dB" % _db("Ambience"))
			_ok("the Backrooms bed bus is not ducked either", absf(_db("Backrooms")) < 0.01,
				"%.1f dB" % _db("Backrooms"))

			# And the audible consequence, not just the mixer state: the music must be
			# playing AND its whole bus chain must be at unity.
			var scene := current_scene
			var music: AudioStreamPlayer = scene.get_node_or_null("MusicPlayer")
			_ok("the Backrooms music exists", music != null)
			if music != null:
				_ok("it is playing", music.playing)
				var chain: float = music.volume_db + _db(music.bus) + _db("Ambience") \
					+ _db("Master")
				# -4 is the score's own level; anything below about -12 means something in
				# the chain is still ducked.
				_ok("and nothing in its bus chain is ducked", chain > -12.0,
					"%.1f dB through the chain" % chain)
			return _report()
	return false


func _report() -> bool:
	print("  %d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL — ", ", ".join(_fails))
		quit(1)
	return true
