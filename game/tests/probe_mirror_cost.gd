extends SceneTree

# What moving `MirrorSurface.ACTIVE_DIST` costs, in metres of path with a second scene render.
#
#   Godot --headless --path game --script res://tests/probe_mirror_cost.gd
#
# A `probe_*`, kept because it documents the number quoted in `mirror_surface.gd`'s comment on
# ACTIVE_DIST and in backlogs/03-corridor.md §10. The gate is the ONLY thing standing between
# this level and two full scene renders per frame, so shrinking it is a saving and enlarging
# it is a cost — but nothing had ever measured which, or by how much.
#
# It walks the level's own `_path_point()` at 0.25 m and counts, at every candidate radius,
# how much of the walk has at least one mirror inside it and whether two are ever inside at
# once. No rendering, no player, no timing — this is geometry, so it is exact and headless.

const SCENE := "res://scenes/corridor.tscn"
const STEP := 0.25
const RADII := [14.0, 10.0, 8.0, 7.0, 5.0]

var _t := 0.0


func _initialize() -> void:
	change_scene_to_file(SCENE)


func _process(delta: float) -> bool:
	_t += delta
	if _t < 1.0:
		return false
	var scene: Node = current_scene
	var mirrors: Array = scene.get("_turn_mirrors")
	var total: float = float(scene.get("_total_len"))
	print("corridor length %.1f m, %d turn mirror(s)" % [total, mirrors.size()])
	print("  %-8s %-12s %-12s %s" % ["radius", "active m", "% of walk", "both at once"])
	var d := 0.0
	var samples := 0
	var active := {}
	var both := {}
	for r in RADII:
		active[r] = 0
		both[r] = 0
	while d <= total:
		var pt: Dictionary = scene.call("_path_point", d)
		var p: Vector3 = pt.pos
		for r in RADII:
			var n := 0
			for m in mirrors:
				var mp: Vector3 = m.pos
				if Vector2(p.x - mp.x, p.z - mp.z).length() <= float(r):
					n += 1
			if n > 0:
				active[r] += 1
			if n > 1:
				both[r] += 1
		samples += 1
		d += STEP
	for r in RADII:
		print("  %-8.1f %-12.2f %-12.1f %s" % [r, active[r] * STEP,
			100.0 * active[r] / float(samples), "YES" if both[r] > 0 else "no"])
	print("  (%d samples at %.2f m)" % [samples, STEP])
	quit(0)
	return true
