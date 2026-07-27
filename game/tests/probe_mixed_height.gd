extends SceneTree

# Probe: does RoomBuilder emit COINCIDENT wall slabs when two abutting rooms have
# different per-room heights?
#
# Why this exists: DUNGEON_NIGHTMARES.md §B6 step 6 wants h=3.2 chambers abutting
# h=2.6 corridors. RoomBuilder's wall dedup keys its covered-interval map on
# "axis|plane|HEIGHT" (room_builder.gd:228), and NO shipped level uses the per-room
# "h" key at all — every level is uniform. So the mixed-height case is untested, and
# the key strongly suggests both rooms emit a slab on their shared plane.
#
# Reasoning about it is not evidence. This builds the two-room fixture and measures.
#
# Usage: Godot --headless --path game --script res://tests/probe_mixed_height.gd

const COPLANAR := 0.002
const MIN_AREA := 0.35

var _frame := 0
var _builder: Node3D = null


func _initialize() -> void:
	# Loaded at runtime, never named as a class_name: naming RoomBuilder here forces
	# it to compile before the autoloads exist.
	var rb_script: GDScript = load("res://scripts/room_builder.gd")
	_builder = rb_script.new()
	root.add_child(_builder)

	# Two rooms that ABUT on the plane z = 4 — the exact chamber/corridor case.
	# Chamber spans z 0..4 at h 3.2; corridor spans z 4..12 at h 2.6.
	var rooms := [
		{ "name": "Chamber",  "pos": Vector2(0, 2),  "size": Vector2(8, 4), "h": 3.2 },
		{ "name": "Corridor", "pos": Vector2(0, 8),  "size": Vector2(3, 8), "h": 2.6 },
	]
	var doors := [
		{ "pos": Vector2(0, 4), "width": 2.2, "dir": "z" },
	]
	_builder.call("build", rooms, doors)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 10:
		return false

	var boxes: Array = []
	_collect(_builder, boxes)
	print("MIXED-HEIGHT boxes=%d" % boxes.size())

	var bad := 0
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			var o: Vector3 = _overlap(boxes[i][1], boxes[j][1])
			if o.x <= 0.0 or o.y <= 0.0 or o.z <= 0.0:
				continue
			var why: String = _faces_fight(boxes[i][1], boxes[j][1])
			if why != "":
				bad += 1
				if bad <= 12:
					print("  ZFIGHT %s %s <-> %s %s  (%s)" % [
						boxes[i][0], _fmt(boxes[i][1]),
						boxes[j][0], _fmt(boxes[j][1]), why])

	# The specific thing under test: how many wall slabs sit on the shared plane z=4?
	var on_plane := 0
	for b in boxes:
		var box: AABB = b[1]
		var center_z: float = box.position.z + box.size.z * 0.5
		if absf(center_z - 4.0) < 0.15 and box.size.z < 0.5 and box.size.y > 1.0:
			on_plane += 1
			print("  SHARED-PLANE slab %s %s" % [b[0], _fmt(box)])

	print("MIXED-HEIGHT slabs on the shared plane z=4: %d (1 = deduped, 2 = both emitted)" % on_plane)
	print("MIXED-HEIGHT result: %d coincident-face pair(s)" % bad)
	print("MIXED-HEIGHT %s" % ("NO CONFLICT" if bad == 0 and on_plane <= 1 else "CONFLICT CONFIRMED"))
	quit(0)
	return true


func _fmt(a: AABB) -> String:
	return "[%.2f,%.2f,%.2f size %.2f,%.2f,%.2f]" % [
		a.position.x, a.position.y, a.position.z, a.size.x, a.size.y, a.size.z]


func _faces_fight(a: AABB, b: AABB) -> String:
	var amin := a.position
	var amax := a.position + a.size
	var bmin := b.position
	var bmax := b.position + b.size
	var names := ["x", "y", "z"]
	for axis in range(3):
		var o1 := (axis + 1) % 3
		var o2 := (axis + 2) % 3
		var ov1: float = minf(amax[o1], bmax[o1]) - maxf(amin[o1], bmin[o1])
		var ov2: float = minf(amax[o2], bmax[o2]) - maxf(amin[o2], bmin[o2])
		if ov1 <= MIN_AREA or ov2 <= MIN_AREA:
			continue
		if absf(amax[axis] - bmax[axis]) < COPLANAR:
			return "+%s faces coincide" % names[axis]
		if absf(amin[axis] - bmin[axis]) < COPLANAR:
			return "-%s faces coincide" % names[axis]
	return ""


func _collect(node: Node, out: Array) -> void:
	if node is CSGBox3D:
		var b: CSGBox3D = node
		out.append([b.name, AABB(b.global_position - b.size / 2.0, b.size)])
	for c in node.get_children():
		_collect(c, out)


func _overlap(a: AABB, b: AABB) -> Vector3:
	var amin := a.position
	var amax := a.position + a.size
	var bmin := b.position
	var bmax := b.position + b.size
	return Vector3(
		minf(amax.x, bmax.x) - maxf(amin.x, bmin.x),
		minf(amax.y, bmax.y) - maxf(amin.y, bmin.y),
		minf(amax.z, bmax.z) - maxf(amin.z, bmin.z))
