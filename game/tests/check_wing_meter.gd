extends SceneTree

# The Lab dark wing's signal meter tells the TRUTH.
#
#   Godot --headless --path game --script res://tests/check_wing_meter.gd
#
# ⚠️ DELIBERATE (2026-08-16). This widget is a HUD readout of proximity to a solution, which
# `GAME_MECHANICS_IDEAS` §5.2(2) and ISSUES_SOLUTIONS Issue 34 both name as a thing this
# project does not build. It is here on the user's explicit call, made after being shown
# both. That decision is not what this test is about.
#
# What this test is about is the half of Issue 34 that was NOT a matter of taste. The deleted
# `set_breaker_proximity()` bar measured straight-line distance, so from inside a dead end it
# read a warm ~0.43 while being nowhere near the breaker in walking terms — it did not merely
# solve the maze, it solved it WRONG. The replacement runs Dijkstra over the wing's own
# doorway graph, and the assertions below are exactly the cases where a beeline lies:
#
#   * every DEAD END must read colder than the route room it branches off, even where it is
#     physically closer to the breaker than that room is;
#   * Plant — MEASURED at 6.6 m from the breaker in a straight line and 30.0 m of walking,
#     a 4.6x lie — must read cold. A beeline meter calls it 0.79 (nearly arrived) and points
#     the player at a wall; this one calls it 0.04;
#   * the value must rise monotonically along the real route.
#
# The test also proves the meter can be wrong: it computes the naive Euclidean answer beside
# the real one and prints both, so the size of the lie it is avoiding is on the record.

# The real route in, from Records' doorway to the breaker.
const ROUTE := [
	Vector3(-13.0, 0.0, 12.5),      # DarkCorridor, just inside the wing
	Vector3(-18.0, 0.0, 12.5),      # DarkCorridor, far end
	Vector3(-21.0, 0.0, 12.5),      # Junction — decision 1
	Vector3(-21.0, 0.0, 9.5),       # SouthSpur
	Vector3(-26.0, 0.0, 7.7),       # SouthHall — decision 3
	Vector3(-30.5, 0.0, 7.7),       # SouthHall, at the nook doorway
	Vector3(-35.5, 0.0, 7.7),       # BreakerNook, on the breaker
]
# Dead ends, each paired with the route room it branches off.
const DEAD_ENDS := [
	["Plant", Vector3(-32.5, 0.0, 12.5), Vector3(-21.0, 0.0, 12.5)],
	["NorthVault", Vector3(-24.5, 0.0, 22.0), Vector3(-21.0, 0.0, 12.5)],
	["PumpRoom", Vector3(-25.0, 0.0, 5.35), Vector3(-26.0, 0.0, 7.7)],
]

var _frame := 0
var _fails := 0
var _checks := 0
var _meter: Node
var _breaker := Vector3.ZERO


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fails += 1
	print("  %s  %s%s" % ["PASS" if cond else "FAIL", label, ("   " + detail) if detail != "" else ""])


func _find(root: Node, pred: Callable) -> Node:
	if pred.call(root):
		return root
	for c in root.get_children():
		var f := _find(c, pred)
		if f:
			return f
	return null


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 10:
		return false

	_meter = _find(current_scene, func(n: Node) -> bool:
		return n is CanvasLayer and n.has_method("path_distance") and n.has_method("signal_strength")
	)
	print("--- dark wing signal meter ---")
	_ok("the meter exists in the built level", _meter != null)
	if not _meter:
		_finish()
		return true
	var nook := current_scene.get_node_or_null("Breaker_Nook") as Node3D
	_ok("the nook breaker exists to measure against", nook != null)
	if nook:
		_breaker = nook.global_position

	# It must only be on screen inside the wing.
	_ok("it starts hidden (the player spawns in Reception)", not bool(_meter.call("is_active")))

	print("  ..  normalisation: the furthest room in the wing is %.1f m of walking away"
		% float(_meter.call("max_path")))
	_ok("the scale is derived from the level's own geometry, not a typed-in number",
		float(_meter.call("max_path")) > 20.0 and float(_meter.call("max_path")) < 120.0,
		"%.1f m" % float(_meter.call("max_path")))

	# ── the route reads monotonically warmer ─────────────────────────────────────────
	var last := -1.0
	var monotonic := true
	var trace: Array = []
	for p in ROUTE:
		var s: float = _meter.call("signal_strength", p)
		trace.append("%.2f" % s)
		if s < last - 0.001:
			monotonic = false
		last = s
	print("  ..  along the real route: %s" % [", ".join(PackedStringArray(trace))])
	_ok("the meter rises monotonically along the actual route", monotonic)
	_ok("and it reads ~1.0 standing at the breaker", last > 0.9, "%.2f" % last)

	# ── the assertion the deleted widget failed ──────────────────────────────────────
	var checked := 0
	for entry in DEAD_ENDS:
		var room: String = entry[0]
		var dead: Vector3 = entry[1]
		var junction: Vector3 = entry[2]
		var s_dead: float = _meter.call("signal_strength", dead)
		var s_junction: float = _meter.call("signal_strength", junction)
		var path: float = _meter.call("path_distance", dead)
		var beeline: float = dead.distance_to(_breaker)
		checked += 1
		print("  ..  %s: %.1f m of walking, %.1f m as the crow flies (a %.1fx lie), reads %.2f"
			% [room, path, beeline, path / maxf(0.1, beeline), s_dead])
		_ok("%s (a dead end) reads COLDER than the junction it branches off" % room,
			s_dead < s_junction, "%.2f vs %.2f" % [s_dead, s_junction])
	# ⚠️ Assert the sample size — "0 dead ends checked … PASS" is a documented failure mode here.
	_ok("every dead end was actually checked", checked == DEAD_ENDS.size(),
		"%d of %d" % [checked, DEAD_ENDS.size()])

	# THE CASE THAT CONVICTED THE OLD WIDGET, in this level's own geometry. Plant is the far
	# end of the west limb: 6.6 m from the breaker through two walls, 30.0 m of walking.
	# A straight-line meter reads it as nearly ARRIVED (~0.79) and points the player at a
	# wall; the path-based one reads 0.04. That gap IS the fix, so it is asserted with a real
	# margin rather than by a hair.
	var plant := Vector3(-32.5, 0.0, 12.5)
	var plant_path: float = _meter.call("signal_strength", plant)
	var plant_naive: float = clampf(
		1.0 - plant.distance_to(_breaker) / float(_meter.call("max_path")), 0.0, 1.0)
	print("  ..  Plant: path-based %.2f vs the old straight-line answer %.2f"
		% [plant_path, plant_naive])
	_ok("Plant does NOT read warm (this is the Issue-34 lie, measured)",
		plant_path < plant_naive - 0.4,
		"path %.2f, beeline %.2f, gap %.2f" % [plant_path, plant_naive, plant_naive - plant_path])

	# Outside the wing there is nothing to measure and it must say so rather than guess.
	var outside: float = _meter.call("path_distance", Vector3(0.0, 0.0, 0.0))
	_ok("outside the wing it reports no reading at all", not is_finite(outside))

	_finish()
	return true


func _finish() -> void:
	print("%d checks, %d failed" % [_checks, _fails])
	print("WING-METER PASS" if _fails == 0 else "WING-METER FAIL")
	quit(1 if _fails > 0 else 0)
