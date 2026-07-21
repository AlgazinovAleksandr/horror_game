extends SceneTree

# Dev tool: assert no two wall/floor/ceiling boxes in a RoomBuilder level occupy the
# same space. Coincident visible surfaces z-fight, and because abutting rooms can use
# different skins the fight shows up in game as one room's texture bleeding through
# another along a jagged contour — the "overlapping / merging textures" bug.
#
# Usage: Godot --headless --path game --script res://tests/check_wall_overlap.gd -- <scene>

var _scene := "res://scenes/level_1.tscn"
var _frame := 0

# What actually z-fights is a pair of COINCIDENT VISIBLE FACES, not volumetric
# overlap as such. Floor bridges are deliberately embedded in the room floors and
# sunk by RoomBuilder.BRIDGE_SINK (4 mm) precisely so their top faces are NOT
# coplanar — those must pass. So: flag a pair only when two parallel faces sit
# within COPLANAR of each other while overlapping substantially in the other axes.
const COPLANAR := 0.002   # face separation below this will fight for depth
# Ignore the 0.2 x 0.2 stubs where two perpendicular walls legitimately cross at a
# room corner — those coincide only over a tiny square, usually up at the ceiling
# line, and are not what the player sees. We want large coincident SURFACES.
const MIN_AREA := 0.35


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


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_scene = args[0]
	change_scene_to_file(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 20:
		return false
	var boxes: Array = []
	_collect(current_scene, boxes)
	print("WALL-OVERLAP scene=%s boxes=%d" % [_scene, boxes.size()])
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
					print("  ZFIGHT %s <-> %s  (%s)" % [boxes[i][0], boxes[j][0], why])
	bad += _check_wall_props(boxes)
	print("WALL-OVERLAP result: %d overlapping pair(s)" % bad)
	print("WALL-OVERLAP %s" % ("PASS" if bad == 0 else "FAIL"))
	return true


# Wall-mounted decals (posters, signs, whiteboards, mirrors, notes) are flat quads
# hung just off a wall. If one sits ON the wall face it z-fights and the wall
# texture slices through the artwork; if it sits behind the face it is swallowed.
# Report any such quad that is not clearly in front of every wall box it overlaps.
func _check_wall_props(boxes: Array) -> int:
	var quads: Array = []
	_collect_quads(current_scene, quads)
	var bad := 0
	for q in quads:
		var qpos: Vector3 = q[1]
		for b in boxes:
			var box: AABB = b[1]
			var grown := box.grow(MIN_CLEAR)
			if grown.has_point(qpos):
				bad += 1
				if bad <= 10:
					print("  WALLPROP %s at %s is within %.2f m of %s" % [
						q[0], qpos, MIN_CLEAR, b[0]])
				break
	print("WALL-OVERLAP wall props checked: %d" % quads.size())
	return bad


const MIN_CLEAR := 0.02


func _collect_quads(node: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is QuadMesh:
		var mi: MeshInstance3D = node
		out.append([mi.name, mi.global_position])
	for c in node.get_children():
		_collect_quads(c, out)


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
