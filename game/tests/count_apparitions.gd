extends SceneTree

# How often does something actually materialise in front of the player in the Lab?
#
#   Godot --headless --path game --script res://tests/count_apparitions.gd
#
# Measures rather than argues: it watches the live scene tree for new Apparition
# instances and prints the real gap between them.
#
# History, because the numbers only mean something against it:
#   * A playtest reported seeing one "more often than each 45 seconds" while
#     DEBUG_APPAR_INTERVAL was exactly 45.0 — the loop was innocent; the SCRIPTED
#     corridor encounter stacks on top of it early in the level.
#   * BACKLOG #6 ("appears too often") replaced the bare 60 s countdown in three levels
#     with ApparitionDirector: a randomised MIN_GAP..MAX_GAP window, a LEVEL_GRACE at
#     the start, and suppression whenever an appearance would be unfair (frozen input,
#     an open note, high panic, right after a RandomAmbient scare).
#
# So the expected shape now is: nothing at all for the first LEVEL_GRACE seconds except
# the scripted corridor encounter, then gaps in the 90-180 s range — NOT a metronome.
# A run that shows evenly-spaced gaps means the director is not actually in the loop.

const RUN_SECONDS := 400.0

# ⚠️ Compressed time, not real time. RUN_SECONDS is GAME seconds: Engine.time_scale
# multiplies every _process delta, the director's included, so the pacing under test is
# unchanged while the run takes RUN_SECONDS / TIME_SCALE of wall clock. Without this a
# meaningful sample of a 90-180 s cycle costs seven minutes per run and nobody runs it.
const TIME_SCALE := 8.0

# This test used to only PRINT. It now asserts, because the thing it measures can fail
# to zero: the first version of ApparitionDirector required 30 s of quiet since the last
# RandomAmbient scare, while RandomAmbient fires every 18-35 s, so the condition was
# almost never satisfiable and the run produced NO apparitions at all. That is a deleted
# feature, and a purely informational test reported it as a tidy "0 in 400 s".
const MIN_EXPECTED := 2
const MIN_ACCEPTABLE_GAP := 60.0   # must be rarer than the 60 s metronome it replaced

var _elapsed := 0.0
var _scene: Node
var _seen := {}                  # instance id -> spawn time
var _last_appar := -1.0
var _gaps: Array[float] = []
var _ambient_events := 0
var _last_ambient_children := 0
var _fails := 0


func _fail(msg: String) -> void:
	_fails += 1
	print("  FAIL ", msg)


func _initialize() -> void:
	Engine.time_scale = TIME_SCALE
	change_scene_to_file("res://scenes/level_1.tscn")


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed < 0.6:
		return false
	if _scene == null:
		_scene = current_scene
		print("--- watching for %.0f s ---" % RUN_SECONDS)

	# An Apparition is the node carrying both of these signals; duck-typed, because
	# naming the class in a SceneTree script compiles it before the autoloads exist.
	#
	# ⚠️ Counts APPEARANCES (visible), not instantiations. Apparition nodes exist
	# dormant from level build — level_1.gd creates its scripted corridor encounter in
	# _ready() and leaves it invisible until a trigger volume arms it — so counting
	# nodes logged a phantom "apparition #1 at t=2.1 s" that the player never saw. And
	# appear() can now decline to materialise at all (no legible spot), which would
	# otherwise be counted as a sighting too.
	for n in _scene.get_children():
		if not (n.has_signal("rushed") and n.has_signal("survived")):
			continue
		if not (n is Node3D and (n as Node3D).visible):
			continue
		var id := n.get_instance_id()
		if _seen.has(id):
			continue
		_seen[id] = _elapsed
		if _last_appar >= 0.0:
			var gap := _elapsed - _last_appar
			_gaps.append(gap)
			print("  apparition #%d at t=%6.1f s   (+%.1f s since the last)"
				% [_seen.size(), _elapsed, gap])
		else:
			print("  apparition #1 at t=%6.1f s   (first)" % _elapsed)
		_last_appar = _elapsed

	if _elapsed >= RUN_SECONDS:
		_report()
		quit(0 if _fails == 0 else 1)
		return true
	return false


func _report() -> void:
	print("")
	print("apparitions spawned: %d in %.0f s" % [_seen.size(), _elapsed])
	if _gaps.is_empty():
		print("  (fewer than two — no gap to measure)")
	else:
		var lo := _gaps[0]
		var hi := _gaps[0]
		var sum := 0.0
		for g in _gaps:
			lo = minf(lo, g)
			hi = maxf(hi, g)
			sum += g
		print("  gaps: min %.1f s / mean %.1f s / max %.1f s" % [lo, sum / _gaps.size(), hi])
		if lo < MIN_ACCEPTABLE_GAP:
			_fail("shortest gap %.1f s is under %.0f s — no rarer than what it replaced"
				% [lo, MIN_ACCEPTABLE_GAP])
	if _seen.size() < MIN_EXPECTED:
		_fail("only %d apparition(s) in %.0f s — expected at least %d. A suppression rule "
			% [_seen.size(), _elapsed, MIN_EXPECTED]
			+ "is probably unsatisfiable; check ApparitionDirector._can_fire().")
	print("")
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	print("")
	print("NOTE: this counts SPAWNS, not sightings. appear() now ABORTS (queue_free, no")
	print("figure) when there is nowhere legible to stand, so a spawn here is very close")
	print("to a sighting — which was not true when a fixed distance could drop it in a wall.")
