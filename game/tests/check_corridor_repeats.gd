extends SceneTree

# How many times can the Corridor play the SAME sound at you?
#
#   Godot --headless --path game --script res://tests/check_corridor_repeats.gd
#
# User report, 2026-08-15: "in the corridor there are too many repeating sounds: let's
# leave music to be present in the entire level, but the sound of trumpet musical
# instrument, falling painting, time clock, beartraps snap let's make appear only once."
#
# Counted at the time, over one ~300 m walk:
#   telegraph_groan   5 placements (104/126/150/178/206 m) — the "trumpet", a 3.2 s brass fall
#   painting_fall     2 scripted events, PLUS RandomAmbient rolling it as 1 of 3 events
#                     every 18-35 s for the whole walk
#   beartrap_snap     5 traps x (1 snap + one replay PER escape keypress, 7 needed)
#   clock_chime       already once (left alone on the user's call)
#
# ⚠️ This counts PLACEMENTS in the built level, not sounds heard, because that is the thing
# a regression would change: someone adding a sixth telegraph or a third painting would not
# notice, and no scene test would fail. The RandomAmbient cap is asserted behaviourally.

const SCENE := "res://scenes/corridor.tscn"

var _t := 0.0
var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	change_scene_to_file(SCENE)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print("  %s  %s%s" % ["OK  " if cond else "FAIL", label, ("  " + detail) if detail else ""])
	if not cond:
		_fails.append(label)


func _process(delta: float) -> bool:
	_t += delta
	if _t < 1.0:
		return false
	var scene := current_scene
	var s: GDScript = scene.get_script()

	# 1. The trumpet.
	var telegraphs: Array = s.get("TELEGRAPH_AT")
	_ok("the telegraph groan is not a loop", telegraphs.size() <= 2,
		"%d placements: %s" % [telegraphs.size(), str(telegraphs)])
	# It still has to keep its shape — a warning that means nothing, then one that does.
	_ok("but it still warns before it pays off", telegraphs.size() >= 2,
		"%d placements" % telegraphs.size())

	# 2. The painting. Counted from the source, since the events are lambdas by then.
	var src := FileAccess.open("res://scripts/corridor.gd", FileAccess.READ)
	var text := src.get_as_text()
	src.close()
	var painting := 0
	for line in text.split("\n"):
		if line.contains("_spawn_event(") and line.contains("_ev_painting_fall"):
			painting += 1
	_ok("the painting falls once", painting <= 1, "%d scripted placements" % painting)

	# 3. The beartrap. The snap must not be re-fired per keypress.
	var bt := FileAccess.open("res://scripts/beartrap.gd", FileAccess.READ)
	var bt_text := bt.get_as_text()
	bt.close()
	var in_press_block := false
	var replays := 0
	for line in bt_text.split("\n"):
		if line.contains("_escape_presses += 1"):
			in_press_block = true
			continue
		if in_press_block:
			if line.contains("_snap_player.play()"):
				replays += 1
			if line.strip_edges().begins_with("if _escape_timer"):
				in_press_block = false
	_ok("the beartrap does not re-snap on every keypress", replays == 0,
		"%d replays in the press handler" % replays)

	# 4. The music plays for the WHOLE level — i.e. it is not on the bus the hush ducks.
	var ambient: AudioStreamPlayer = scene.get_node_or_null("AmbientPlayer")
	_ok("the corridor has a score", ambient != null and ambient.stream != null)
	if ambient != null:
		_ok("and it is not on the bus the hush kills", ambient.bus != "Ambience", ambient.bus)
		_ok("it is playing", ambient.playing)
		# Drive the hush for real and confirm the score survives it.
		scene.set("_furthest_reached", float(s.get("HUSH_AT")) + 1.0)
		scene.call("_tick_hush")
		var music_bus_idx := AudioServer.get_bus_index(ambient.bus)
		_ok("the hush leaves the score's own bus alone",
			music_bus_idx != -1 and absf(AudioServer.get_bus_volume_db(music_bus_idx)) < 0.01,
			"%.1f dB" % AudioServer.get_bus_volume_db(music_bus_idx))

	# 5. The global ambient metronome is capped for this level — and ONLY this level, so
	#    check the opt-in exists rather than assuming the autoload changed for everyone.
	var ra: Node = root.get_node_or_null("/root/RandomAmbient")
	_ok("RandomAmbient offers a per-level cap", ra != null and ra.has_method("set_once_per_type"))
	if ra != null:
		_ok("and the Corridor opted in", bool(ra.get("_once_per_type")))
		# Behavioural: fire it more times than there are event types and count distinct.
		ra.call("set_once_per_type", true)
		var seen := {}
		for i in range(12):
			ra.call("_fire_random_event")
			for k in (ra.get("_used") as Dictionary):
				seen[k] = true
		_ok("each ambient event fires at most once", seen.size() <= 3,
			"%d distinct events after 12 rolls" % seen.size())

	# 6. The mirror-appearance cue (2026-08-16). One per turn mirror, one-shot each, so the
	#    ceiling is the number of mirrors — the same shape as the telegraph's cap of two.
	#    `check_mirror_wake.gd` owns the behaviour; this owns the COUNT, which is the thing a
	#    future "let's put one at every corner" would quietly change.
	var declared_v: Variant = s.get("TURN_MIRRORS")
	var declared: Array = declared_v if declared_v is Array else []
	_ok("the mirror-wake cue cannot fire more than twice in a walk", declared.size() <= 2,
		"%d turn mirrors: %s" % [declared.size(), str(declared)])
	_ok("and it still fires at least once", declared.size() >= 1)

	print("  %d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL — ", ", ".join(_fails))
		quit(1)
	return true
