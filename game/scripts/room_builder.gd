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
# Rooms may overlap or abut freely, but COPLANAR VISIBLE FACES ARE NOT FREE. An
# earlier version of this comment claimed "the game is dark; seam z-fighting is
# invisible at these scales" — that was wrong, and it was the cause of the visible
# flicker along every Lab/House hallway. Two boxes whose top faces sit at the same
# y will fight for depth no matter how dim the room is. Rooms themselves abut
# edge-to-edge so their floors don't overlap; the floor bridges do, which is why
# they are sunk by BRIDGE_SINK. If you add geometry here, keep visible surfaces
# off each other's planes.
# Full-height shared interior walls are de-duped by plane+span so a shared divider
# is only built once; doorway openings are subtracted from EVERY wall on the same
# plane, so a passage between two abutting rooms opens regardless of build order.
#
# Data formats (plain Dictionaries):
#   room    = { "name": String, "pos": Vector2(x,z), "size": Vector2(w,d), "h": float?,
#               "wall_mat": Material?, "floor_mat": Material?, "ceil_mat": Material? }
#       the optional *_mat keys override the builder-wide materials for THIS room, so
#       a morgue / kitchen / bathroom can read as a distinct place. Shared interior
#       walls keep whichever room builds them first (dedup); perimeter walls are unique.
#   doorway = { "pos": Vector2(x,z), "width": float, "dir": "x"|"z", "h": float? }
#       dir is the axis you WALK THROUGH the opening. dir "z" sits in a wall that
#       runs along X (constant z); dir "x" sits in a wall that runs along Z.

const DEFAULT_H := 3.0
const T := 0.2            # wall / floor / ceiling thickness
const BRIDGE_PAD := 1.3   # half-length a floor bridge extends past the doorway centre
# A floor bridge always overlaps INTO the rooms on both sides (BRIDGE_PAD guarantees
# it). If its top face sat at y=0 like the room floors, the two coplanar surfaces
# would z-fight at every doorway — the flicker-while-walking bug. Sinking the bridge
# a few mm makes the room floor win the depth test, so the bridge is only visible
# through the gap it exists to fill. 4 mm is far below move_and_slide's step
# tolerance (the Session 11 cellar-lip bug was 0.14 m, ~35x larger).
const BRIDGE_SINK := 0.004
const PLANE_TOL := 0.4    # a doorway lies "on" a wall if its fixed coord is within this
const SEG_MIN := 0.05     # ignore wall sub-segments thinner than this
# How far proud of a wall's inner FACE wall_point() guarantees to sit. Enough to
# clear depth-buffer precision at these room scales without the prop looking like
# it floats off the wall.
const MIN_FACE_CLEAR := 0.03

var wall_mat: Material
var floor_mat: Material
var ceil_mat: Material
var wall_height: float = DEFAULT_H

var _rooms: Dictionary = {}        # name -> { pos, size, h }
var _built_walls: Dictionary = {}  # "axis|plane|height" -> Array of covered [lo,hi]


func build(rooms: Array, doorways: Array) -> void:
	for r in rooms:
		var h: float = r.get("h", wall_height)
		_rooms[r["name"]] = { "pos": r["pos"], "size": r["size"], "h": h }
		# Per-room material overrides fall back to the builder-wide defaults. A room
		# can carry "wall_mat"/"floor_mat"/"ceil_mat" to read as a distinct place.
		var fmat: Material = r.get("floor_mat", floor_mat)
		var cmat: Material = r.get("ceil_mat", ceil_mat)
		_emit_floor_ceiling(r["name"], r["pos"], r["size"], h, fmat, cmat)
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
	# ⚠️ `inset` is measured from the room's NOMINAL boundary, but the wall's inner
	# face is half a wall-thickness in from that. So the usable clearance is
	# (inset - T/2), and an inset of 0.1 puts a prop EXACTLY on the wall face —
	# coplanar, which z-fights and slices the prop apart with the wall texture
	# (the half-eaten morgue poster). Anything under 0.1 is buried inside the wall
	# (Issue 11). Callers passed 0.06, 0.08 and 0.1 all over both levels, so rather
	# than fix each site we guarantee a minimum clearance here.
	var min_inset := T / 2.0 + MIN_FACE_CLEAR
	var used: float = maxf(inset, min_inset)
	var x: float = pos.x + side.x * (half.x - used)
	var z: float = pos.y + side.y * (half.y - used)
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
		# ⚠️ The V component MUST be negative. A positive uv1_scale.y renders every
		# wall texture upside-down: the wainscot/baseboard band ends up at mid-wall
		# and the lower half reads as a mirrored duplicate of the upper half — which
		# is exactly the "two textures merging into each other" bug. Callers pass a
		# positive scale and we flip it here, so no call site has to remember.
		# Z reuses the X component to keep horizontal tiling square.
		# Same convention as MazeKit.make_material() (maze_kit.gd) and corridor.gd.
		mat.uv1_scale = Vector3(uv_scale.x, -absf(uv_scale.y), uv_scale.x)
	else:
		mat.albedo_color = fallback
	return mat


# ---------------------------------------------------------------- geometry

func _emit_floor_ceiling(room_name: String, pos: Vector2, size: Vector2, h: float,
		fmat: Material, cmat: Material) -> void:
	_box("%s_Floor" % room_name, Vector3(pos.x, -T / 2.0, pos.y),
		Vector3(size.x, T, size.y), fmat)
	_box("%s_Ceiling" % room_name, Vector3(pos.x, h + T / 2.0, pos.y),
		Vector3(size.x, T, size.y), cmat)


func _emit_floor_bridge(d: Dictionary) -> void:
	var pos: Vector2 = d["pos"]
	var w: float = d.get("width", 1.4)
	var dir: String = d.get("dir", "z")
	var size: Vector3
	if dir == "z":
		size = Vector3(w, T, BRIDGE_PAD * 2.0)
	else:
		size = Vector3(BRIDGE_PAD * 2.0, T, w)
	_box("DoorFloor", Vector3(pos.x, -T / 2.0 - BRIDGE_SINK, pos.y), size, floor_mat)


func _emit_room_walls(r: Dictionary, doorways: Array) -> void:
	var pos: Vector2 = r["pos"]
	var size: Vector2 = r["size"]
	var h: float = r.get("h", wall_height)
	var wmat: Material = r.get("wall_mat", wall_mat)
	var x0 := pos.x - size.x / 2.0
	var x1 := pos.x + size.x / 2.0
	var z0 := pos.y - size.y / 2.0
	var z1 := pos.y + size.y / 2.0
	# Walls running along X (constant z): traversed along z.
	_emit_wall_run("z", z0, x0, x1, h, doorways, wmat)
	_emit_wall_run("z", z1, x0, x1, h, doorways, wmat)
	# Walls running along Z (constant x): traversed along x.
	_emit_wall_run("x", x0, z0, z1, h, doorways, wmat)
	_emit_wall_run("x", x1, z0, z1, h, doorways, wmat)


# Emit the solid sub-segments of one wall, leaving an archway gap wherever a
# doorway on this plane overlaps the run.
func _emit_wall_run(axis: String, fixed: float, span_min: float, span_max: float,
		h: float, doorways: Array, wmat: Material) -> void:
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
			_emit_wall_segment(axis, fixed, cursor, g[0], h, wmat)
		cursor = maxf(cursor, g[1])
	if span_max - cursor > SEG_MIN:
		_emit_wall_segment(axis, fixed, cursor, span_max, h, wmat)


# Emit a wall segment, but only the part of it not already walled by another room.
#
# ⚠️ This subtracts INTERVALS; it used to dedup on an exact span match, and that was
# the "overlapping / merging textures" bug. Two rooms that abut share a wall plane,
# but only rooms of identical depth produce identical spans. The Lab's CrossHall
# emits x=6 over z 11..14 while the Morgue emits x=6 over z 9.5..15.5 — different
# keys, so BOTH were built, occupying the same 0.2 m slab on the same plane. Two
# coincident visible surfaces z-fight, and because the two rooms use different
# skins (morgue lockers vs corridor concrete) the fight showed as one room's
# texture bleeding through the other along a jagged contour. Exact-match dedup only
# ever caught the equal-size case.
#
# Coverage is tracked per (axis, plane, height); whichever room builds first owns
# the shared stretch, which is the documented behaviour for shared interior walls.
func _emit_wall_segment(axis: String, fixed: float, a: float, b: float, h: float,
		wmat: Material) -> void:
	var key := "%s|%.2f|%.2f" % [axis, fixed, h]
	var covered: Array = _built_walls.get(key, [])
	for piece in _free_intervals(a, b, covered):
		_emit_wall_box(axis, fixed, piece[0], piece[1], h, wmat)
		covered.append(piece)
	_built_walls[key] = covered


# The parts of [a,b] not already inside one of `covered`'s [lo,hi] intervals.
func _free_intervals(a: float, b: float, covered: Array) -> Array:
	var pending: Array = [[a, b]]
	for c in covered:
		var next: Array = []
		for p in pending:
			# No overlap — keep the piece whole.
			if c[1] <= p[0] or c[0] >= p[1]:
				next.append(p)
				continue
			# Keep whatever sticks out either side of the covered span.
			if c[0] - p[0] > SEG_MIN:
				next.append([p[0], c[0]])
			if p[1] - c[1] > SEG_MIN:
				next.append([c[1], p[1]])
		pending = next
	var out: Array = []
	for p in pending:
		if p[1] - p[0] > SEG_MIN:
			out.append(p)
	return out


func _emit_wall_box(axis: String, fixed: float, a: float, b: float, h: float,
		wmat: Material) -> void:
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
	_box("Wall", pos, size, wmat)


func _box(box_name: String, pos: Vector3, size: Vector3, mat: Material) -> void:
	var b := CSGBox3D.new()
	b.name = box_name
	b.size = size
	b.position = pos
	b.use_collision = true
	if mat:
		b.material = mat
	add_child(b)
