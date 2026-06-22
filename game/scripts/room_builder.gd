extends Node3D
class_name RoomBuilder

# Procedural room-graph geometry builder.
#
# Give it a list of ROOMS (axis-aligned rectangular cells on the floor plane) and
# DOORWAYS (openings cut into the walls). It emits CSG floor/ceiling/wall boxes,
# auto-bridges the floor under every doorway — so the Issue-5 floor-gap / void-fall
# class of bug cannot recur — and cuts the doorway openings into the walls. It
# applies its own materials as it builds, so the level script does NOT need an
# _apply_textures() scan pass for this geometry.
#
# Rooms may overlap or abut freely. Like corridor.gd, coplanar box faces are
# accepted (the game is dark; seam z-fighting is invisible at these scales).
# Full-height shared interior walls are de-duped by plane+span so a shared divider
# is only built once; doorway openings are subtracted from EVERY wall on the same
# plane, so a passage between two abutting rooms opens regardless of build order.
#
# Data formats (plain Dictionaries):
#   room    = { "name": String, "pos": Vector2(x,z), "size": Vector2(w,d), "h": float? }
#   doorway = { "pos": Vector2(x,z), "width": float, "dir": "x"|"z", "h": float? }
#       dir is the axis you WALK THROUGH the opening. dir "z" sits in a wall that
#       runs along X (constant z); dir "x" sits in a wall that runs along Z.

const DEFAULT_H := 3.0
const T := 0.2            # wall / floor / ceiling thickness
const BRIDGE_PAD := 1.3   # half-length a floor bridge extends past the doorway centre
const PLANE_TOL := 0.4    # a doorway lies "on" a wall if its fixed coord is within this
const SEG_MIN := 0.05     # ignore wall sub-segments thinner than this

var wall_mat: Material
var floor_mat: Material
var ceil_mat: Material
var wall_height: float = DEFAULT_H

var _rooms: Dictionary = {}        # name -> { pos, size, h }
var _built_walls: Dictionary = {}  # segment key -> true (dedup)


func build(rooms: Array, doorways: Array) -> void:
	for r in rooms:
		var h: float = r.get("h", wall_height)
		_rooms[r["name"]] = { "pos": r["pos"], "size": r["size"], "h": h }
		_emit_floor_ceiling(r["name"], r["pos"], r["size"], h)
	# Floor bridges first (guarantee no gap under doorways), then walls with the
	# openings cut out of them.
	for d in doorways:
		_emit_floor_bridge(d)
	for r in rooms:
		_emit_room_walls(r, doorways)


# ---------------------------------------------------------------- public queries

func room_center(room_name: String) -> Vector3:
	if not _rooms.has(room_name):
		return Vector3.ZERO
	var p: Vector2 = _rooms[room_name].pos
	return Vector3(p.x, 0.0, p.y)


func room_size(room_name: String) -> Vector2:
	return _rooms[room_name].size if _rooms.has(room_name) else Vector2.ZERO


func room_height(room_name: String) -> float:
	return _rooms[room_name].h if _rooms.has(room_name) else wall_height


func has_room(room_name: String) -> bool:
	return _rooms.has(room_name)


# A point inset from a room wall, at a given height. side picks the wall:
#   Vector2(-1,0)=west  (+1,0)=east  (0,-1)=south(-z)  (0,1)=north(+z).
# inset is how far in from the wall face (metres). Useful for hanging props.
func wall_point(room_name: String, side: Vector2, y: float, inset: float = 0.05) -> Vector3:
	if not _rooms.has(room_name):
		return Vector3.ZERO
	var pos: Vector2 = _rooms[room_name].pos
	var half: Vector2 = _rooms[room_name].size * 0.5
	var x: float = pos.x + side.x * (half.x - inset)
	var z: float = pos.y + side.y * (half.y - inset)
	return Vector3(x, y, z)


# ---------------------------------------------------------------- helper material

static func make_material(tex_path: String, uv_scale: Vector3, fallback: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.9
	if tex_path != "" and ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
		# Triplanar so the texture tiles at a fixed world scale regardless of the
		# box face size — rooms of different dimensions all read consistently.
		mat.uv1_triplanar = true
		mat.uv1_scale = uv_scale
	else:
		mat.albedo_color = fallback
	return mat


# ---------------------------------------------------------------- geometry

func _emit_floor_ceiling(room_name: String, pos: Vector2, size: Vector2, h: float) -> void:
	_box("%s_Floor" % room_name, Vector3(pos.x, -T / 2.0, pos.y),
		Vector3(size.x, T, size.y), floor_mat)
	_box("%s_Ceiling" % room_name, Vector3(pos.x, h + T / 2.0, pos.y),
		Vector3(size.x, T, size.y), ceil_mat)


func _emit_floor_bridge(d: Dictionary) -> void:
	var pos: Vector2 = d["pos"]
	var w: float = d.get("width", 1.4)
	var dir: String = d.get("dir", "z")
	var size: Vector3
	if dir == "z":
		size = Vector3(w, T, BRIDGE_PAD * 2.0)
	else:
		size = Vector3(BRIDGE_PAD * 2.0, T, w)
	_box("DoorFloor", Vector3(pos.x, -T / 2.0, pos.y), size, floor_mat)


func _emit_room_walls(r: Dictionary, doorways: Array) -> void:
	var pos: Vector2 = r["pos"]
	var size: Vector2 = r["size"]
	var h: float = r.get("h", wall_height)
	var x0 := pos.x - size.x / 2.0
	var x1 := pos.x + size.x / 2.0
	var z0 := pos.y - size.y / 2.0
	var z1 := pos.y + size.y / 2.0
	# Walls running along X (constant z): traversed along z.
	_emit_wall_run("z", z0, x0, x1, h, doorways)
	_emit_wall_run("z", z1, x0, x1, h, doorways)
	# Walls running along Z (constant x): traversed along x.
	_emit_wall_run("x", x0, z0, z1, h, doorways)
	_emit_wall_run("x", x1, z0, z1, h, doorways)


# Emit the solid sub-segments of one wall, leaving an archway gap wherever a
# doorway on this plane overlaps the run.
func _emit_wall_run(axis: String, fixed: float, span_min: float, span_max: float,
		h: float, doorways: Array) -> void:
	var gaps: Array = []
	for d in doorways:
		if d.get("dir", "z") != axis:
			continue
		var dpos: Vector2 = d["pos"]
		var fixed_coord: float = dpos.y if axis == "z" else dpos.x
		if absf(fixed_coord - fixed) > PLANE_TOL:
			continue
		var run_coord: float = dpos.x if axis == "z" else dpos.y
		var w: float = d.get("width", 1.4)
		var lo := run_coord - w / 2.0
		var hi := run_coord + w / 2.0
		if hi > span_min and lo < span_max:
			gaps.append([maxf(lo, span_min), minf(hi, span_max)])
	gaps.sort_custom(func(a, b): return a[0] < b[0])

	var cursor := span_min
	for g in gaps:
		if g[0] - cursor > SEG_MIN:
			_emit_wall_segment(axis, fixed, cursor, g[0], h)
		cursor = maxf(cursor, g[1])
	if span_max - cursor > SEG_MIN:
		_emit_wall_segment(axis, fixed, cursor, span_max, h)


func _emit_wall_segment(axis: String, fixed: float, a: float, b: float, h: float) -> void:
	var key := "%s|%.1f|%.1f|%.1f|%.1f" % [axis, fixed, a, b, h]
	if _built_walls.has(key):
		return
	_built_walls[key] = true
	var center := (a + b) / 2.0
	var length := b - a
	var pos: Vector3
	var size: Vector3
	if axis == "z":   # runs along X at constant z
		pos = Vector3(center, h / 2.0, fixed)
		size = Vector3(length, h, T)
	else:             # runs along Z at constant x
		pos = Vector3(fixed, h / 2.0, center)
		size = Vector3(T, h, length)
	_box("Wall", pos, size, wall_mat)


func _box(box_name: String, pos: Vector3, size: Vector3, mat: Material) -> void:
	var b := CSGBox3D.new()
	b.name = box_name
	b.size = size
	b.position = pos
	b.use_collision = true
	if mat:
		b.material = mat
	add_child(b)
