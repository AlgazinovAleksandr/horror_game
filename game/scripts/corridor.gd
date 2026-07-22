extends Node3D

# Level 3 — The Corridor. A ~320 m zigzag hotel hallway, built procedurally
# from PATH_2D. The only test: walk it without panicking. Three zones:
#   A (0–90 m)    intact hotel — torches, paintings, the clock
#   B (90–230 m)  decay — blood, lights shatter, beartraps in the dark
#   C (230–320 m) nightmare — dead torches, the mirror, whispers, door 217

const W := 3.0   # corridor width
const H := 3.0   # corridor height
const T := 0.3   # wall thickness

# Corner points of the zigzag centerline (x, z). Segment lengths:
# 50 + 40 + 50 + 45 + 45 + 45 + 45 = 320 m.
const PATH_2D: Array[Vector2] = [
	Vector2(0, 0), Vector2(0, 50), Vector2(40, 50), Vector2(40, 100),
	Vector2(-5, 100), Vector2(-5, 145), Vector2(40, 145), Vector2(40, 190),
]

const TEX_DIR := "res://assets/textures/level_3_corridor/"

# Lit torches: [distance, side]. Zone A is generous, Zone B sparser.
# The three at 148–168 sit in the dark stretch and get shattered by the
# lights-out event before the player reaches them.
const TORCHES := [
	[8.0, 1.0], [20.0, -1.0], [32.0, 1.0], [44.0, -1.0], [56.0, 1.0],
	[68.0, -1.0], [80.0, 1.0],
	[100.0, 1.0], [120.0, -1.0], [134.0, 1.0],
	[148.0, -1.0], [158.0, 1.0], [168.0, -1.0],
	[176.0, 1.0], [196.0, -1.0], [214.0, 1.0],
]
const SHATTER_RANGE := Vector2(144.0, 172.0)  # torches extinguished by lights-out

const BEARTRAPS := [  # [distance, lateral offset]
	[150.0, 0.45], [155.0, -0.6], [162.0, 0.55], [168.0, 0.0], [245.0, -0.5],
]

# ⚠️ Difficulty fix: DARK_ZONES used to have a second entry, Vector2(240, 318),
# which sat entirely INSIDE the dread zone below. player.gd's _update_panic()
# treats dark-zone and dread-zone pressure as ADDITIVE (dark tax is +3/s on top
# of the unconditional +2/s dread pressure), so any stretch tagged as both was a
# guaranteed +5/s with the flashlight off — and the noclip ending (_ev_noclip_onset)
# FORCE-KILLS the flashlight for the final ~10 m with zero player agency to avoid
# it. A long level with beartrap QTEs earlier can also burn through the 240 s
# battery before reaching here, forcing the same double tax by attrition rather
# than choice. Either way it made the ending an unavoidable panic spike report
# read as "impossible." Dropped entirely — the dread zone's own pressure is
# already this stretch's difficulty signature; it doesn't need a second, stacking
# mechanic under it.
const DARK_ZONES := [Vector2(145.0, 172.0)]
# Shortened from 230 (90 m of flat/no-recovery pressure) to 260 (60 m) — gives
# the player real decay time after the silhouette/floor-crack events instead of
# carrying whatever panic they had straight into the endurance stretch.
const DREAD_ZONE := Vector2(260.0, 320.0)  # Zone C tail: weak decay + constant pressure

# The Manager: a survivable scare that strikes once while you walk — a flash, a
# scream, a panic spike to ride out. Distance-triggered (not wall-time) at a
# random mid-hall point, so it always fires regardless of walk/run speed.
const MANAGER_SCARE_PATH := "res://assets/textures/level_3_corridor/screamer_manager.png"
const MANAGER_PANIC := 25.0
const MANAGER_DIST := Vector2(80.0, 180.0)  # walked-distance window for the fire point

var _manager_fired: bool = false

# Turn mirrors: walk into the creature in the glass and it flashes back at you.
# [{pos, fired}] — proximity-tested in _process so each fires once.
const TURN_MIRROR_SCARE_PATH := "res://assets/textures/level_3_corridor/mirror_with_creature.png"
const TURN_MIRROR_SCARE_DIST := 2.0
const TURN_MIRROR_PANIC := 12.0

var _turn_mirrors: Array = []

const NOTE_TEXT := """Hotel Vesper — night audit.

The corridor between floors does not appear on the building plans. The staff do not walk it after dark.

You will.

Walk. Do not run. Do not stop for the things you hear behind you. The lights have been paid for where they still burn — rest beneath them.

Room 217 is waiting.

— The Management"""

var _segments: Array[Dictionary] = []
var _total_len: float = 0.0
var _torch_nodes: Array = []  # [distance, Torch3D]
var _wall_mat: StandardMaterial3D
var _floor_mat: StandardMaterial3D
var _ceil_mat: StandardMaterial3D

@onready var _player: CharacterBody3D = $Player


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameState.current_level = 3

	_build_segments()
	_make_materials()
	_build_geometry()
	_spawn_torches()
	_spawn_panels()
	_spawn_beartraps()
	_spawn_dark_zones()
	_spawn_dread_zone()
	_spawn_doors()
	_spawn_intro_note()
	_spawn_events()
	_spawn_noclip()
	_start_ambience()
	Vignette.spawn(self, Color(0.9, 0.8, 0.65, 1.0), 1.2)
	RandomAmbient.register_player(_player)
	GameState.set_objective("Find room 217 — keep walking, do not run")


func _process(_delta: float) -> void:
	# Walk into a turn mirror and the creature in the glass flashes at you once.
	var pp := _player.global_position
	for m in _turn_mirrors:
		if m.fired:
			continue
		var mp: Vector3 = m.pos
		if Vector2(pp.x - mp.x, pp.z - mp.z).length() <= TURN_MIRROR_SCARE_DIST:
			m.fired = true
			Screamer.flash_scare(TURN_MIRROR_SCARE_PATH, "glass_shatter", 0.6)
			_player.jolt_camera(0.07, 0.5)
			_player.add_panic(TURN_MIRROR_PANIC)


# ---------------------------------------------------------------- path helpers

func _build_segments() -> void:
	var d := 0.0
	for i in range(PATH_2D.size() - 1):
		var p0 := PATH_2D[i]
		var p1 := PATH_2D[i + 1]
		var seg_len := p0.distance_to(p1)
		_segments.append({
			"p0": p0, "dir": (p1 - p0) / seg_len, "len": seg_len, "start_d": d,
		})
		d += seg_len
	_total_len = d


# Point on the centerline at walked distance `dist`.
# Returns pos (floor level), dir (walk direction) and side (lateral unit vector).
func _path_point(dist: float) -> Dictionary:
	for i in range(_segments.size()):
		var seg: Dictionary = _segments[i]
		if dist <= seg.start_d + seg.len or i == _segments.size() - 1:
			var t: float = clampf(dist - seg.start_d, 0.0, seg.len)
			var p: Vector2 = seg.p0 + seg.dir * t
			var dir3 := Vector3(seg.dir.x, 0, seg.dir.y)
			return {
				"pos": Vector3(p.x, 0, p.y),
				"dir": dir3,
				"side": Vector3(dir3.z, 0, -dir3.x),
			}
	return {}


# ---------------------------------------------------------------- geometry

func _make_materials() -> void:
	# Negative y: triplanar V grows upward in world space, which renders the
	# texture upside-down on walls — flip so the wainscot sits at the floor.
	_wall_mat = _make_mat(TEX_DIR + "wall.png", Vector3(1.0 / 3.6, -1.0 / 3.0, 1.0 / 3.6), Color(0.25, 0.2, 0.14))
	_floor_mat = _make_mat(TEX_DIR + "carpet.png", Vector3(0.5, 0.5, 0.5), Color(0.16, 0.12, 0.05))
	_ceil_mat = _make_mat("", Vector3.ONE, Color(0.10, 0.085, 0.07))


func _make_mat(tex_path: String, uv_scale: Vector3, fallback: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.92
	if tex_path != "" and ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
		# Triplanar = 1 texture unit per (1/scale) world metres, independent of
		# CSG face size. Wall y-scale 1/3 fits exactly one wainscot row per 3 m.
		mat.uv1_triplanar = true
		mat.uv1_scale = uv_scale
	else:
		mat.albedo_color = fallback
	return mat


func _build_geometry() -> void:
	for i in range(_segments.size()):
		var seg: Dictionary = _segments[i]
		var n: Vector2 = Vector2(seg.dir.y, -seg.dir.x)  # side normal (2D)
		# Footprint extends half a width past interior corners so overlapping
		# floor/ceiling boxes cover the corner squares.
		var lo := 0.0 if i == 0 else -W / 2.0
		var hi: float = seg.len if i == _segments.size() - 1 else seg.len + W / 2.0

		_corridor_box("Seg%dFloor" % i, seg, lo, hi, 0.0, W + 2.0 * T, -T / 2.0, T, _floor_mat)
		_corridor_box("Seg%dCeiling" % i, seg, lo, hi, 0.0, W + 2.0 * T, H + T / 2.0, T, _ceil_mat)

		for side in [1.0, -1.0]:
			var wa := lo
			var wb := hi
			# Leave a corridor-wide opening where the adjacent segment attaches.
			if i > 0 and (-_segments[i - 1].dir as Vector2).distance_to(n * side) < 0.01:
				wa = lo + W
			if i < _segments.size() - 1 and (_segments[i + 1].dir as Vector2).distance_to(n * side) < 0.01:
				wb = hi - W
			if wb - wa > 0.01:
				var wall_name := "Seg%dWall%s" % [i, "A" if side > 0 else "B"]
				_corridor_box(wall_name, seg, wa, wb, side * (W + T) / 2.0, T, H / 2.0, H + 2.0 * T, _wall_mat)

		if i == 0:
			_corridor_box("StartCapWall", seg, lo - T, lo, 0.0, W + 2.0 * T, H / 2.0, H + 2.0 * T, _wall_mat)
		if i == _segments.size() - 1:
			_corridor_box("EndCapWall", seg, hi, hi + T, 0.0, W + 2.0 * T, H / 2.0, H + 2.0 * T, _wall_mat)


# Axis-aligned CSG box spanning [a, b] along the segment direction,
# `lateral` metres off the centerline, `width` across, `height` tall.
func _corridor_box(box_name: String, seg: Dictionary, a: float, b: float,
		lateral: float, width: float, y_center: float, height: float, mat: Material) -> void:
	var n: Vector2 = Vector2(seg.dir.y, -seg.dir.x)
	var mid2: Vector2 = seg.p0 + (seg.dir as Vector2) * ((a + b) / 2.0) + n * lateral
	var box := CSGBox3D.new()
	box.name = box_name
	box.use_collision = true
	if absf(seg.dir.x) > 0.5:
		box.size = Vector3(b - a, height, width)
	else:
		box.size = Vector3(width, height, b - a)
	box.position = Vector3(mid2.x, y_center, mid2.y)
	if mat:
		box.material = mat
	add_child(box)


# ---------------------------------------------------------------- props

func _spawn_torches() -> void:
	for entry in TORCHES:
		var dist: float = entry[0]
		var side: float = entry[1]
		var pt := _path_point(dist)
		var torch := Torch3D.new()
		torch.position = pt.pos + (pt.side as Vector3) * side * (W / 2.0 - 0.12) + Vector3(0, 1.9, 0)
		var inward: Vector3 = -(pt.side as Vector3) * side
		torch.rotation.y = atan2(inward.x, inward.z)
		add_child(torch)
		_torch_nodes.append([dist, torch])


func _spawn_panels() -> void:
	# Plain decor panels: [dist, side, w, h, texture, y_center]
	var decor := [
		[60.0, 1.0, 1.5, 1.2, "painting.png", 1.8],
		[180.0, -1.0, 1.5, 1.2, "painting.png", 1.8],
		[110.0, 1.0, 2.4, 1.8, "blood_corridor.png", 1.4],
		[150.0, -1.0, 2.4, 1.8, "blood_corridor.png", 1.4],
		[200.0, 1.0, 2.4, 1.8, "blood_corridor.png", 1.4],
		[246.0, -1.0, 2.4, 1.8, "blood_corridor.png", 1.4],
		[282.0, 1.0, 2.4, 1.8, "blood_corridor.png", 1.4],
		[308.0, -1.0, 2.4, 1.8, "blood_corridor.png", 1.4],
		[240.0, 1.0, 2.0, 3.0, "torch.png", 1.5],   # dead torches — Zone C
		[262.0, -1.0, 2.0, 3.0, "torch.png", 1.5],
		[300.0, 1.0, 2.0, 3.0, "torch.png", 1.5],
		[255.0, -1.0, 1.8, 1.2, "carpet.png", 1.6],  # wall-hung carpet
		# KONTUR HINT 3/4 — the answer to KONTUR's Gate 3 (the offering). Reads as
		# hotel signage here; only later does it mean anything. Full-height panel
		# because the art carries its own wallpaper+wainscot background, like the
		# clock/mirror/torch panels. See kontur.gd.
		[172.0, -1.0, 2.0, 3.0, "kontur_plate.png", 1.5],
	]
	for p in decor:
		_spawn_quad(_panel_transform(p[0], p[1], p[5]), Vector2(p[2], p[3]), TEX_DIR + p[4])

	# Floor crack decals (static decor; the live crack event spawns its own)
	for crack in [[258.0, 0.4], [296.0, -0.5]]:
		var pt := _path_point(crack[0])
		var quad := _spawn_quad(Transform3D(), Vector2(1.6, 1.2), TEX_DIR + "floor_crack.png")
		if quad:
			quad.position = pt.pos + (pt.side as Vector3) * crack[1] + Vector3(0, 0.012, 0)
			quad.rotation_degrees.x = -90.0

	# Cursed panels (gaze fills panic): [dist, side, w, h, texture, y_center, intensity]
	# The plain mirror.png stays a full-height side-wall panel — now one on each
	# wall in Zone C so the player is flanked by their own reflection.
	var cursed := [
		[25.0, -1.0, 1.5, 1.2, "painting.png", 1.8, 0.8],
		[48.0, 1.0, 2.0, 3.0, "clock.png", 1.5, 1.0],
		[268.0, 1.0, 1.5, 1.2, "painting.png", 1.8, 1.2],
		[285.0, -1.0, 2.0, 3.0, "mirror.png", 1.5, 2.5],
		[288.0, 1.0, 2.0, 3.0, "mirror.png", 1.5, 2.0],
	]
	for p in cursed:
		_spawn_cursed_panel(p[0], p[1], Vector2(p[2], p[3]), TEX_DIR + p[4], p[5], p[6])

	# The creature in the glass: an ornate mirror set on the wall the player walks
	# straight at when reaching a turn — miss the turn and you walk into it.
	for tm in [[90.0, 1.5], [230.0, 2.0], [275.0, 2.2]]:
		_spawn_turn_mirror(tm[0], tm[1])

	# Locked hotel room doors that knock back, plus plain decor doors for atmosphere.
	for fd in [[35.0, -1.0], [130.0, 1.0], [252.0, 1.0]]:
		_spawn_fake_door(fd[0], fd[1])
	for dd in [[18.0, 1.0], [72.0, -1.0], [112.0, 1.0], [164.0, -1.0], [210.0, 1.0], [300.0, -1.0]]:
		_spawn_quad(_panel_transform(dd[0], dd[1], 1.05), Vector2(1.3, 2.1),
			TEX_DIR + "ordinary_hotel_door.png")


# Transform flush against the wall at `dist` on `side`, quad facing inward.
func _panel_transform(dist: float, side: float, y_center: float) -> Transform3D:
	var pt := _path_point(dist)
	var inward: Vector3 = -(pt.side as Vector3) * side
	var pos: Vector3 = pt.pos + (pt.side as Vector3) * side * (W / 2.0 - 0.02) + Vector3(0, y_center, 0)
	return Transform3D(Basis(Vector3.UP, atan2(inward.x, inward.z)), pos)


func _spawn_quad(xform: Transform3D, size: Vector2, tex_path: String) -> MeshInstance3D:
	if not ResourceLoader.exists(tex_path):
		return null
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(tex_path)
	mat.roughness = 0.9
	quad.set_surface_override_material(0, mat)
	quad.transform = xform
	add_child(quad)
	return quad


func _spawn_cursed_panel(dist: float, side: float, size: Vector2, tex_path: String,
		y_center: float, intensity: float) -> void:
	_make_cursed_panel_at(_panel_transform(dist, side, y_center), size, tex_path, intensity)


# A turn mirror sits flush on the wall directly ahead at a corner (the wall you
# face if you fail to turn), so you approach the creature in the glass head-on.
func _spawn_turn_mirror(corner_dist: float, intensity: float) -> void:
	var pt := _path_point(corner_dist)
	var dir_in: Vector3 = pt.dir  # at a corner distance, _path_point returns the incoming segment
	var pos: Vector3 = pt.pos + dir_in * (W / 2.0 - 0.05) + Vector3(0, 1.5, 0)
	var face := -dir_in
	var xform := Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)), pos)
	_make_cursed_panel_at(xform, Vector2(1.4, 1.95), TURN_MIRROR_SCARE_PATH, intensity)
	_turn_mirrors.append({ "pos": pos, "fired": false })


# Build a gaze-panic panel (StaticBody + textured quad + collision + ScaryObject)
# at an arbitrary transform.
func _make_cursed_panel_at(xform: Transform3D, size: Vector2, tex_path: String,
		intensity: float) -> void:
	# The ScaryObject must be an ANCESTOR of the collider — player.gd's gaze check
	# walks UP from the ray-hit StaticBody. Previously it was a child of the body,
	# so no cursed panel (paintings, clock, mirrors) ever fed gaze panic.
	# ScaryObject is a plain Node (no transform) and breaks the spatial chain, so
	# the world transform lives on the StaticBody3D itself (parent non-spatial ->
	# the body's local transform IS its global transform).
	var scary := ScaryObject.new()
	scary.scare_intensity = intensity
	add_child(scary)

	var body := StaticBody3D.new()
	body.transform = xform
	scary.add_child(body)

	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
	else:
		mat.albedo_color = Color(0.1, 0.08, 0.06)
	mat.roughness = 0.9
	quad.set_surface_override_material(0, mat)
	body.add_child(quad)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y, 0.1)
	col.shape = shape
	body.add_child(col)


func _spawn_fake_door(dist: float, side: float) -> void:
	var body := FakeDoor.new()
	body.transform = _panel_transform(dist, side, 1.05)
	add_child(body)

	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.4, 2.1)
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	var door_tex := TEX_DIR + "ordinary_hotel_door.png"
	if ResourceLoader.exists(door_tex):
		mat.albedo_texture = load(door_tex)
	else:
		mat.albedo_color = Color(0.15, 0.1, 0.06)
	mat.roughness = 0.9
	quad.set_surface_override_material(0, mat)
	body.add_child(quad)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.4, 2.1, 0.1)
	col.shape = shape
	body.add_child(col)


func _spawn_beartraps() -> void:
	for entry in BEARTRAPS:
		var pt := _path_point(entry[0])
		var trap := Beartrap.new()
		trap.position = pt.pos + (pt.side as Vector3) * entry[1]
		add_child(trap)


func _spawn_dark_zones() -> void:
	for zone_range in DARK_ZONES:
		_spawn_zone_boxes(zone_range, func() -> Area3D: return DarkZone.new())


func _spawn_dread_zone() -> void:
	_spawn_zone_boxes(DREAD_ZONE, func() -> Area3D: return DreadZone.new())


# Cover [range.x, range.y] of the path with axis-aligned Area3D boxes, one per
# segment slice. `make_zone` constructs the zone node type.
func _spawn_zone_boxes(zone_range: Vector2, make_zone: Callable) -> void:
	for seg in _segments:
		var a: float = maxf(zone_range.x, seg.start_d)
		var b: float = minf(zone_range.y, seg.start_d + seg.len)
		if b - a < 0.5:
			continue
		var zone: Area3D = make_zone.call()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(W, H, b - a)
		col.shape = shape
		zone.add_child(col)
		var mid2: Vector2 = seg.p0 + (seg.dir as Vector2) * ((a + b) / 2.0 - seg.start_d)
		zone.position = Vector3(mid2.x, H / 2.0, mid2.y)
		zone.rotation.y = atan2(seg.dir.x, seg.dir.y)
		add_child(zone)


# ---------------------------------------------------------------- doors & note

const _DOOR_SCRIPT := preload("res://scripts/door.gd")
const _NOTE_SCRIPT := preload("res://scripts/note.gd")


func _spawn_doors() -> void:
	# Exit: room 217 at the far end. Reaching it IS the win — unlock NONE.
	var end_pt := _path_point(_total_len)
	var exit_door: StaticBody3D = _make_door_body("ExitDoor")
	# Room 217 is a lie — you never walk through it. The noclip floor trigger in
	# front of it drops you into the Backrooms instead (see _spawn_noclip).
	exit_door.advances_level = false
	exit_door.position = end_pt.pos + Vector3(end_pt.dir.x, 0, end_pt.dir.z) * -0.08
	var exit_inward: Vector3 = -(end_pt.dir as Vector3)
	exit_door.rotation.y = atan2(exit_inward.x, exit_inward.z)
	_dress_exit_door(exit_door)

	# Back door at the start, returns to The House (blood-red per convention).
	var start_pt := _path_point(0.0)
	var back_door: StaticBody3D = _make_door_body("BackDoor")
	back_door.advances_level = false
	back_door.goes_back = true
	back_door.position = start_pt.pos + Vector3(start_pt.dir.x, 0, start_pt.dir.z) * 0.08
	back_door.rotation.y = atan2(start_pt.dir.x, start_pt.dir.z)
	_dress_back_door(back_door)


func _make_door_body(door_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = door_name
	body.set_script(_DOOR_SCRIPT)
	add_child(body)
	var col := CollisionShape3D.new()
	col.name = door_name + "Col"
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.6, 2.8, 0.2)
	col.shape = shape
	col.position.y = 1.4
	body.add_child(col)
	return body


func _dress_exit_door(body: StaticBody3D) -> void:
	var quad := MeshInstance3D.new()
	quad.name = "DoorMesh"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 3.0)
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	if ResourceLoader.exists(TEX_DIR + "door.png"):
		mat.albedo_texture = load(TEX_DIR + "door.png")
	# Soft red glow that still lets the room-217 texture read through.
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.02, 0.02)
	mat.emission_energy_multiplier = 0.6
	quad.set_surface_override_material(0, mat)
	quad.position.y = 1.5
	body.add_child(quad)


func _dress_back_door(body: StaticBody3D) -> void:
	var door_mesh := MeshInstance3D.new()
	door_mesh.name = "DoorMesh"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 2.2, 0.15)
	door_mesh.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.01, 0.01)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.02, 0.02)
	mat.emission_energy_multiplier = 1.5
	door_mesh.set_surface_override_material(0, mat)
	door_mesh.position.y = 1.1
	body.add_child(door_mesh)


func _spawn_intro_note() -> void:
	var pt := _path_point(4.0)
	var table_pos: Vector3 = pt.pos + (pt.side as Vector3) * (W / 2.0 - 0.45)

	var table := CSGBox3D.new()
	table.name = "NoteTable"
	table.size = Vector3(0.5, 1.2, 0.4)
	table.use_collision = true
	table.position = table_pos + Vector3(0, 0.6, 0)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.16, 0.10, 0.05)
	wood.roughness = 0.8
	table.material = wood
	add_child(table)

	var note := StaticBody3D.new()
	note.name = "IntroNote"
	note.set_script(_NOTE_SCRIPT)
	note.note_text = NOTE_TEXT
	note.position = table_pos + Vector3(0, 1.25, 0)
	add_child(note)

	var note_mesh := MeshInstance3D.new()
	note_mesh.mesh = BoxMesh.new()
	(note_mesh.mesh as BoxMesh).size = Vector3(0.21, 0.01, 0.297)
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.05, 0.05, 0.04)
	paper.emission_enabled = true
	paper.emission = Color(0.55, 0.50, 0.35)
	paper.emission_energy_multiplier = 0.6
	note_mesh.set_surface_override_material(0, paper)
	note.add_child(note_mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.35, 0.12, 0.45)
	col.shape = shape
	note.add_child(col)


# ---------------------------------------------------------------- events

func _spawn_events() -> void:
	_spawn_event(6.0, _ev_entry_slam)
	_spawn_event(46.0, _ev_clock_chime)
	_spawn_event(72.0, _ev_painting_fall)    
	_spawn_event(138.0, _ev_lights_out)
	_spawn_event(188.0, _ev_whisper_oneshot)
	_spawn_event(195.0, _ev_painting_fall)   
	_spawn_event(205.0, _ev_silhouette)
	_spawn_event(235.0, _ev_whisper_loop)
	_spawn_event(250.0, _ev_floor_crack)
	# The Manager strikes once when you pass a random mid-hall point.
	_spawn_event(randf_range(MANAGER_DIST.x, MANAGER_DIST.y), _ev_manager)


# ---------------------------------------------------------------- the noclip

# The player never reaches room 217. Ten metres out, the corridor plunges black
# and the flashlight dies; the floor at the door is a trigger that drops them
# into the Backrooms (GameState level 4). Replaces the old clean door advance.
var _noclip_armed: bool = false
var _noclip_fired: bool = false

func _spawn_noclip() -> void:
	_spawn_event(_total_len - 10.0, _ev_noclip_onset)
	# Floor trigger right at the door.
	var pt := _path_point(_total_len - 1.5)
	var area := CorridorEvent.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(W, H, 2.5)
	col.shape = shape
	area.add_child(col)
	area.position = pt.pos + Vector3(0, H / 2.0, 0)
	area.rotation.y = atan2(pt.dir.x, pt.dir.z)
	area.fired.connect(_ev_noclip_fall)
	add_child(area)


func _ev_noclip_onset() -> void:
	# Pitch black: every torch dies and the flashlight is force-killed (F now
	# only clicks). The last ten metres are walked blind.
	_noclip_armed = true
	for entry in _torch_nodes:
		entry[1].extinguish()
	if _player.has_method("kill_flashlight"):
		_player.kill_flashlight()
	_play_at("creak", _path_point(_total_len - 6.0).pos + Vector3(0, 1.5, 0), 2.0)


func _ev_noclip_fall() -> void:
	if not _noclip_armed or _noclip_fired:
		return
	_noclip_fired = true
	# Fade to black, a two-second drop, then wake in the Backrooms.
	var layer := CanvasLayer.new()
	layer.layer = 80
	add_child(layer)
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(fade)
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 1.0)
	_player.jolt_camera(0.05, 0.4)
	_play_at("creak", _player.global_position, 3.0)
	await get_tree().create_timer(2.0).timeout
	GameState.advance_level()  # -> The Backrooms


func _spawn_event(dist: float, callback: Callable) -> void:
	var pt := _path_point(dist)
	var ev := CorridorEvent.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(W, H, 2.0)
	col.shape = shape
	ev.add_child(col)
	ev.position = pt.pos + Vector3(0, H / 2.0, 0)
	ev.rotation.y = atan2(pt.dir.x, pt.dir.z)
	ev.fired.connect(callback)
	add_child(ev)


func _play_at(base_name: String, pos: Vector3, volume_db: float = 0.0) -> void:
	var stream := GameState.load_audio(base_name)
	if not stream:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.unit_size = 8.0
	p.max_db = 6.0
	add_child(p)
	p.position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _ev_manager() -> void:
	# Survivable: a flash, a scream, a panic spike — only fatal if you were
	# already near the edge. Guarded so it never double-fires.
	if _manager_fired:
		return
	_manager_fired = true
	Screamer.flash_scare(MANAGER_SCARE_PATH, "screamer_manager", 0.85)
	_player.jolt_camera(0.09, 0.6)
	_player.add_panic(MANAGER_PANIC)


func _ev_entry_slam() -> void:
	# The way back slams shut behind you.
	_play_at("door_slam", _path_point(0.5).pos + Vector3(0, 1.2, 0), 2.0)
	_player.add_panic(10.0)


func _ev_clock_chime() -> void:
	_play_at("clock_chime", _panel_transform(48.0, 1.0, 1.5).origin, 1.0)
	_player.add_panic(10.0)


func _ev_lights_out() -> void:
	_play_at("glass_shatter", _path_point(150.0).pos + Vector3(0, 2.4, 0), 3.0)
	for entry in _torch_nodes:
		if entry[0] >= SHATTER_RANGE.x and entry[0] <= SHATTER_RANGE.y:
			entry[1].extinguish()


func _ev_whisper_oneshot() -> void:
	_play_at("whispers", _path_point(200.0).pos + Vector3(0, 1.5, 0), -6.0)


func _ev_silhouette() -> void:
	# Something crosses the junction ahead, far down the hall.
	var pt := _path_point(228.5)
	var fig := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.75
	fig.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.03)
	mat.emission_enabled = true
	mat.emission = Color(0.06, 0.05, 0.07)
	mat.emission_energy_multiplier = 0.4
	fig.set_surface_override_material(0, mat)
	add_child(fig)
	var side3: Vector3 = pt.side
	fig.position = pt.pos + side3 * 1.2 + Vector3(0, 0.9, 0)
	var tween := create_tween()
	tween.tween_property(fig, "position", pt.pos - side3 * 1.2 + Vector3(0, 0.9, 0), 0.7)
	tween.tween_callback(fig.queue_free)
	_play_at("jumpscare", pt.pos + Vector3(0, 1.2, 0), -14.0)
	_player.add_panic(20.0)


func _ev_whisper_loop() -> void:
	# Constant low whispers for the rest of the walk (Zone C).
	var stream := GameState.load_audio("whispers")
	if not stream:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = -10.0
	p.unit_size = 14.0
	p.max_db = -4.0
	add_child(p)
	p.position = _path_point(290.0).pos + Vector3(0, 1.5, 0)
	p.finished.connect(p.play)
	p.play()


func _ev_floor_crack() -> void:
	# The floor splits under your feet.
	_play_at("creak", _player.global_position, 4.0)
	_player.jolt_camera(0.06, 0.45)
	_player.add_panic(10.0)
	if ResourceLoader.exists(TEX_DIR + "floor_crack.png"):
		var quad := _spawn_quad(Transform3D(), Vector2(1.8, 1.4), TEX_DIR + "floor_crack.png")
		if quad:
			quad.position = Vector3(_player.global_position.x, 0.012, _player.global_position.z)
			quad.rotation_degrees.x = -90.0

func _ev_painting_fall() -> void:
	# Картина срывается со стены перед игроком.
	var pt := _path_point(_player.global_position.length())
	var painting_pos := _player.global_position + Vector3(randf_range(-2.0, 2.0), 1.8, randf_range(-2.0, 2.0))

	# Звук падения
	_play_at("painting_fall", painting_pos, 1.5)
	_player.add_panic(8.0)

	# Визуал: квад-картина падает вниз
	var quad := _spawn_quad(Transform3D(), Vector2(1.5, 1.2), TEX_DIR + "painting.png")
	if quad:
		quad.position = painting_pos
		quad.rotation.y = randf_range(-PI, PI)
		var tween := create_tween()
		tween.tween_property(quad, "rotation:z", PI / 2.0, 0.35).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(quad, "position:y", 0.05, 0.4).set_ease(Tween.EASE_IN)
		tween.tween_callback(quad.queue_free)

# ---------------------------------------------------------------- ambience

func _start_ambience() -> void:
	var ambient: AudioStreamPlayer = get_node_or_null("AmbientPlayer")
	if not ambient:
		return
	var s := GameState.load_audio("ghost_house")
	if s:
		ambient.stream = s
	if ambient.stream:
		ambient.volume_db = -6.0
		ambient.finished.connect(ambient.play)
		ambient.play()
