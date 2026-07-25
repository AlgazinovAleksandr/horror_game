extends SceneTree

# How often does something actually materialise in front of the player in the Lab?
#
#   Godot --headless --path game --script res://tests/count_apparitions.gd
#
# Playtest 2026-07-26: "during this trial I saw apparition more often than each 45
# seconds." DEBUG_APPAR_INTERVAL is 45.0 and was not changed, so either the code does
# something other than what it reads like, or something ELSE is producing the same
# impression. This measures rather than argues: it watches the live scene tree for new
# Apparition instances and prints the real gap between them.
#
# It also counts RandomAmbient's events, because that autoload fires a positional
# scream/creak/crash within 4 m of the player every 5-10 s and is a strong candidate for
# what a player would describe as "it appeared next to me again".

const RUN_SECONDS := 155.0

var _elapsed := 0.0
var _scene: Node
var _seen := {}                  # instance id -> spawn time
var _last_appar := -1.0
var _gaps: Array[float] = []
var _ambient_events := 0
var _last_ambient_children := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_1.tscn")


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed < 0.6:
		return false
	if _scene == null:
		_scene = current_scene
		print("--- watching for %.0f s (DEBUG_APPAR_INTERVAL is what it is) ---" % RUN_SECONDS)

	# An Apparition is the node carrying both of these signals; duck-typed, because
	# naming the class in a SceneTree script compiles it before the autoloads exist.
	for n in _scene.get_children():
		if not (n.has_signal("rushed") and n.has_signal("survived")):
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
		quit(0)
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
	print("")
	print("NOTE: this counts SPAWNS. It cannot count how many the player actually saw —")
	print("before APPEAR_DIST was cut to 4 m many spawned inside walls and were invisible,")
	print("so an unchanged spawn rate can still feel like a large increase in frequency.")
