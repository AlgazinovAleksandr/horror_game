extends SceneTree

# DIAGNOSTIC, not a guard: how much authored content is in each of KONTUR's 13 rooms, and
# how far apart the eight gates are. It is the evidence behind the hypotheses section of
# `backlogs/05-kontur.md`, which is why it is kept rather than deleted.
#
#   Godot --headless --path game --script res://tests/probe_kontur_density.gd
#
# ⚠️ IT UNDERCOUNTS COMPOSITE PROPS. Every direct child of the scene root counts as ONE,
# so the containment cell (about forty meshes) and a recovery rack (about twenty) each
# score 1 while a floor hazard band scores one per chevron. Read it as "how many separate
# THINGS are in this room", never as a measure of geometry.

const Scenes := preload("res://tests/lib/scenes.gd")
var _t := 0.0
func _initialize() -> void:
	Scenes.pin_rng(11)
	change_scene_to_file("res://scenes/kontur.tscn")
func _process(d: float) -> bool:
	_t += d
	if _t < 1.6: return false
	var sc := current_scene
	var rooms: Array = sc.get("ROOMS")
	var tail: Array = sc.call("_tail_rooms")
	var all := rooms + tail
	# count "authored" nodes per room: direct children of the scene root that are Node3D
	# and are not the builder / player / env / lights
	var skip := ["RoomBuilder", "Player", "Environment", "AmbientPlayer", "HUDCanvas"]
	var per := {}
	var areas := {}
	for r in all:
		per[r["name"]] = 0
		areas[r["name"]] = float(r["size"].x) * float(r["size"].y)
	var total := 0
	for c in sc.get_children():
		if not (c is Node3D): continue
		var n := String(c.name)
		if skip.has(n) or n.begins_with("Lamp_") or c is OmniLight3D or c is DreadZone or c is DarkZone: continue
		if c.get_script() == null and (c is CSGBox3D): pass
		var z: float = (c as Node3D).global_position.z
		for r in all:
			var lo: float = float(r["pos"].y) - float(r["size"].y) / 2.0
			var hi: float = float(r["pos"].y) + float(r["size"].y) / 2.0
			if z >= lo and z <= hi:
				per[r["name"]] = int(per[r["name"]]) + 1
				total += 1
				break
	print("--- authored nodes per room (seed 11) ---")
	for r in all:
		var nm: String = r["name"]
		print("  %-12s  z %6.1f..%-6.1f  %5.0f m2   %3d nodes   %.2f /m2" % [
			nm, float(r["pos"].y) - float(r["size"].y)/2.0, float(r["pos"].y) + float(r["size"].y)/2.0,
			areas[nm], per[nm], float(per[nm]) / float(areas[nm])])
	print("  total %d" % total)
	# interactables
	var inter := 0
	var stack: Array = [sc]
	while stack:
		var x = stack.pop_back()
		for ch in x.get_children():
			stack.append(ch)
			if ch.has_method("interact"): inter += 1
	print("  interactables: %d" % inter)
	# gate-to-gate walking distance along the spine
	var gates := [["gate1 doors", 10.0], ["gate2 barrier", 27.0], ["gate5 roster", 35.0],
		["gate3 pedestal", 39.0], ["gate6 phone", 47.5], ["gate7 seams", 59.9],
		["gate8 airlock", 65.8], ["gate4 terminus", 93.0]]
	print("--- gate-to-gate spans ---")
	var prev := -3.0
	var prev_n := "spawn"
	for g in gates:
		print("  %-16s -> %-16s %5.1f m" % [prev_n, g[0], float(g[1]) - prev])
		prev = float(g[1]); prev_n = String(g[0])
	quit(0)
	return true
