extends Node3D

# Level 2 — The House (expanded). Built procedurally with RoomBuilder: entry hall,
# central hallway, living room + kitchen, an upper landing onto the bedroom,
# bathroom and child's room, plus a gently-descending CELLAR reached by a ramp and
# sealed by a gate until you find the cellar key in the kitchen. Win: read the
# three safe notes (one digit each — the third is in the cellar), enter the code
# on the lock by the exit. Scares: window/forest, living-room TV, a one-way mirror
# in the bathroom, a music box in the child's room, cursed props, scripted events,
# pipe groans, random blackouts, and a "hold your nerve" apparition in the dark.

const TEX := "res://assets/textures/level_2_house/"
const PRESERVE := ["Environment", "AmbientPlayer", "CreakPlayer", "HUDCanvas", "Player"]

const _DOOR_SCRIPT := preload("res://scripts/door.gd")
const _NOTE_SCRIPT := preload("res://scripts/note.gd")
const _LOCK_SCRIPT := preload("res://scripts/combination_lock.gd")

const CREAK_MIN := 15.0
const CREAK_MAX := 40.0
const PIPE_MIN := 14.0
const PIPE_MAX := 30.0
const BLACKOUT_MIN := 24.0
const BLACKOUT_MAX := 44.0

const FOREST_PATH := TEX + "forest.png"
const FOREST_SCARE_PATH := TEX + "screamer_forest.png"
const FOREST_SCARE_DIST := 1.5
const FOREST_SCARE_PANIC := 25.0

var _builder: RoomBuilder
var _lights: Array = []           # [OmniLight3D, base_energy]
var _window_pos: Vector3
var _forest_fired: bool = false
var _creak_timer: float = 0.0
var _pipe_timer: float = 0.0
var _blackout_clock: float = 0.0
var _blackout_timer: float = 0.0
var _cellar_gate: CSGBox3D
var _apparition: Apparition
var _apparition_fired: bool = false


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameState.current_level = 2

	_clear_old_scene()
	_build_geometry()
	_place_player()
	_spawn_lights()
	_spawn_notes()
	_spawn_lock_and_doors()
	_spawn_window()
	_spawn_cursed_props()
	_spawn_tv()
	_spawn_bathroom_mirror()
	_spawn_cellar_contents()
	_spawn_music_box()
	_spawn_events()
	_spawn_apparition()
	_start_ambience()

	Vignette.spawn(self, Color(1.0, 0.88, 0.72, 1.0), 1.4)
	RandomAmbient.register_player(_player())
	_creak_timer = randf_range(CREAK_MIN, CREAK_MAX)
	_pipe_timer = randf_range(PIPE_MIN, PIPE_MAX)
	_blackout_clock = randf_range(BLACKOUT_MIN, BLACKOUT_MAX)


func _player() -> CharacterBody3D:
	return get_node_or_null("Player") as CharacterBody3D


func _clear_old_scene() -> void:
	for child in get_children():
		if not PRESERVE.has(child.name):
			child.queue_free()


# ---------------------------------------------------------------- geometry

const ROOMS := [
	{ "name": "EntryHall", "pos": Vector2(0, 0), "size": Vector2(3, 6) },
	{ "name": "Hallway", "pos": Vector2(0, 7), "size": Vector2(3, 8) },
	{ "name": "LivingRoom", "pos": Vector2(-5, 6), "size": Vector2(7, 6) },
	{ "name": "Kitchen", "pos": Vector2(5, 6), "size": Vector2(7, 6) },
	{ "name": "Landing", "pos": Vector2(0, 12.5), "size": Vector2(8, 3) },
	{ "name": "Bedroom", "pos": Vector2(-7, 12.5), "size": Vector2(6, 6) },
	{ "name": "Bathroom", "pos": Vector2(6.5, 12.5), "size": Vector2(5, 4) },
	{ "name": "ChildRoom", "pos": Vector2(0, 16.5), "size": Vector2(5, 5) },
]

const DOORS := [
	{ "pos": Vector2(0, 3), "width": 1.6, "dir": "z" },       # EntryHall <-> Hallway
	{ "pos": Vector2(-1.5, 6), "width": 1.4, "dir": "x" },    # Hallway <-> LivingRoom
	{ "pos": Vector2(1.5, 6), "width": 1.4, "dir": "x" },     # Hallway <-> Kitchen
	{ "pos": Vector2(0, 11), "width": 1.6, "dir": "z" },      # Hallway <-> Landing
	{ "pos": Vector2(-4, 12.5), "width": 1.4, "dir": "x" },   # Landing <-> Bedroom
	{ "pos": Vector2(4, 12.5), "width": 1.4, "dir": "x" },    # Landing <-> Bathroom
	{ "pos": Vector2(0, 14), "width": 1.6, "dir": "z" },      # Landing <-> ChildRoom
	{ "pos": Vector2(5, 3), "width": 1.6, "dir": "z" },       # Kitchen -> cellar ramp (gated)
]


func _build_geometry() -> void:
	_builder = RoomBuilder.new()
	_builder.wall_mat = RoomBuilder.make_material(
		TEX + "house_wall.png", Vector3(0.35, 0.35, 0.35), Color(0.4, 0.32, 0.26))
	_builder.floor_mat = RoomBuilder.make_material(
		TEX + "house_floor.png", Vector3(0.35, 0.35, 0.35), Color(0.28, 0.2, 0.13))
	_builder.ceil_mat = RoomBuilder.make_material(
		TEX + "house_ceiling.png", Vector3(0.35, 0.35, 0.35), Color(0.2, 0.16, 0.13))
	add_child(_builder)
	_builder.build(ROOMS, DOORS)
	_build_cellar()


func _place_player() -> void:
	var p := _player()
	if not p:
		return
	p.global_position = Vector3(0, 0.1, -2.0)
	p.rotation = Vector3(0, PI, 0)  # face +z into the house


# ---------------------------------------------------------------- cellar (lowered)

const CELLAR_Y := -1.5
const CELLAR_CENTER := Vector2(5, -6)
const CELLAR_SIZE := Vector2(7, 7)
const CELLAR_H := 2.6

var _cellar_mat: StandardMaterial3D


func _build_cellar() -> void:
	_cellar_mat = RoomBuilder.make_material(
		TEX + "house_basement_concrete.png", Vector3(0.35, 0.35, 0.35), Color(0.18, 0.18, 0.19))
	var c := CELLAR_CENTER
	var s := CELLAR_SIZE
	var x0 := c.x - s.x / 2.0
	var x1 := c.x + s.x / 2.0
	var z0 := c.y - s.y / 2.0   # far (south) edge
	var z1 := c.y + s.y / 2.0   # near (north) edge, where the ramp enters: z=-2.5

	# Floor + ceiling.
	_box("CellarFloor", Vector3(c.x, CELLAR_Y - 0.15, c.y), Vector3(s.x, 0.3, s.y), _cellar_mat)
	_box("CellarCeiling", Vector3(c.x, CELLAR_Y + CELLAR_H + 0.15, c.y), Vector3(s.x, 0.3, s.y), _cellar_mat)
	# Side + far walls.
	_box("CellarWallW", Vector3(x0, CELLAR_Y + CELLAR_H / 2.0, c.y), Vector3(0.2, CELLAR_H, s.y), _cellar_mat)
	_box("CellarWallE", Vector3(x1, CELLAR_Y + CELLAR_H / 2.0, c.y), Vector3(0.2, CELLAR_H, s.y), _cellar_mat)
	_box("CellarWallS", Vector3(c.x, CELLAR_Y + CELLAR_H / 2.0, z0), Vector3(s.x, CELLAR_H, 0.2), _cellar_mat)
	# Near wall split for the ramp opening (1.6 wide at x=5).
	_box("CellarWallN_A", Vector3(2.7, CELLAR_Y + CELLAR_H / 2.0, z1), Vector3(2.4, CELLAR_H, 0.2), _cellar_mat)
	_box("CellarWallN_B", Vector3(7.3, CELLAR_Y + CELLAR_H / 2.0, z1), Vector3(2.4, CELLAR_H, 0.2), _cellar_mat)

	# The ramp: from ground (y=0, z=2.6) down to the cellar floor (y=-1.5, z=-2.4).
	# A gentle ~18° slope, walls on both sides of the shaft so you can't fall off.
	var top := Vector3(5, 0, 2.6)
	var bottom := Vector3(5, CELLAR_Y, -2.4)
	var mid := (top + bottom) / 2.0
	var run := top.z - bottom.z          # 5.0 m
	var drop := top.y - bottom.y         # 1.5 m
	var length := sqrt(run * run + drop * drop)
	var angle := atan2(drop, run)        # slope
	var ramp := CSGBox3D.new()
	ramp.name = "CellarRamp"
	ramp.size = Vector3(1.6, 0.3, length)
	ramp.position = mid
	ramp.rotation.x = -angle             # descend toward -z (cellar); +angle inverts it
	ramp.use_collision = true
	ramp.material = _cellar_mat
	add_child(ramp)
	# Shaft side walls following the ramp.
	for sx in [-1.0, 1.0]:
		var w := CSGBox3D.new()
		w.size = Vector3(0.2, 2.2, length + 0.6)
		w.position = mid + Vector3(sx * 0.9, 1.0, 0)
		w.rotation.x = -angle
		w.use_collision = true
		w.material = _cellar_mat
		add_child(w)
	# Sloped ceiling over the shaft (2.1 m headroom), so the open top of the stair
	# never shows the sky through the gap above the cellar gate.
	var shaft_ceil := CSGBox3D.new()
	shaft_ceil.name = "CellarShaftCeiling"
	shaft_ceil.size = Vector3(2.0, 0.3, length + 1.2)
	shaft_ceil.position = mid + Vector3(0, 2.1, 0)
	shaft_ceil.rotation.x = -angle
	shaft_ceil.use_collision = true
	shaft_ceil.material = _cellar_mat
	add_child(shaft_ceil)


# ---------------------------------------------------------------- lighting

func _spawn_lights() -> void:
	for r in ROOMS:
		var c: Vector3 = _builder.room_center(r["name"])
		var warm := 0.55
		if r["name"] == "Bedroom" or r["name"] == "ChildRoom":
			warm = 0.45
		_add_lamp(r["name"], Vector3(c.x, 2.6, c.z), warm, Color(0.9, 0.75, 0.55))
	# A dim, cold bulb in the cellar.
	_add_lamp("Cellar", Vector3(CELLAR_CENTER.x, CELLAR_Y + 2.2, CELLAR_CENTER.y), 0.22, Color(0.6, 0.65, 0.7))


func _add_lamp(lamp_name: String, pos: Vector3, energy: float, color: Color) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp_" + lamp_name
	lamp.position = pos
	lamp.light_energy = energy
	lamp.light_color = color
	lamp.omni_range = 8.0
	add_child(lamp)
	_lights.append([lamp, energy])


# ---------------------------------------------------------------- notes

func _spawn_notes() -> void:
	# Three safe notes — one digit each (code 472). The third is in the cellar.
	_make_note(_builder.wall_point("LivingRoom", Vector2(-1, 0), 1.4, 0.1), PI / 2.0,
		"The first number is scratched by the door frame. It is 4.", false)
	_make_note(_builder.wall_point("Bedroom", Vector2(0, 1), 1.4, 0.1), PI,
		"I checked everywhere. The second number must be 7. I'm sure of it.\n\nI'm sure.", false)
	_make_note(Vector3(CELLAR_CENTER.x - 1.5, CELLAR_Y + 1.4, CELLAR_CENTER.y - 2.0), 0.0,
		"Third digit — the one she always used — 2.\n\nDon't forget. Don't forget. Don't forget.", false)
	# Two trap notes (read-to-die).
	_make_note(_builder.wall_point("Bathroom", Vector2(1, 0), 1.3, 0.1), -PI / 2.0,
		"it got in it got in it got in it got in it got in\n\nDONT READ THIS dont read this stop stop stop stop", true)
	_make_note(_builder.wall_point("ChildRoom", Vector2(-1, 0), 1.3, 0.1), PI / 2.0,
		"Subject 44 was removed on day 3.\nSubject 45 was removed on day 1.\nSubject 46 was removed on day 6.\n\nYou are not going to make it.", true)


func _make_note(pos: Vector3, y_rot: float, text: String, trap: bool) -> void:
	var note := StaticBody3D.new()
	note.set_script(_NOTE_SCRIPT)
	note.note_text = text
	note.is_trap = trap
	note.position = pos
	note.rotation.y = y_rot
	add_child(note)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.32, 0.42, 0.01)
	mesh.mesh = bm
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.05, 0.05, 0.04) if not trap else Color(0.2, 0.05, 0.05)
	paper.emission_enabled = true
	paper.emission = Color(0.55, 0.5, 0.35) if not trap else Color(0.55, 0.12, 0.1)
	paper.emission_energy_multiplier = 0.6
	mesh.set_surface_override_material(0, paper)
	note.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 0.5, 0.12)
	col.shape = shape
	note.add_child(col)


# ---------------------------------------------------------------- lock + doors

func _spawn_lock_and_doors() -> void:
	# Exit + combination lock on the north wall of the child's room.
	var lock := StaticBody3D.new()
	lock.set_script(_LOCK_SCRIPT)
	lock.position = Vector3(0.7, 1.3, 18.85)
	add_child(lock)
	var lmesh := MeshInstance3D.new()
	var lbm := BoxMesh.new()
	lbm.size = Vector3(0.6, 0.8, 0.15)
	lmesh.mesh = lbm
	var lmat := StandardMaterial3D.new()
	if ResourceLoader.exists(TEX + "lock_face.png"):
		lmat.albedo_texture = load(TEX + "lock_face.png")
	lmat.metallic = 0.3
	lmat.roughness = 0.9
	lmesh.set_surface_override_material(0, lmat)
	lock.add_child(lmesh)
	var lcol := CollisionShape3D.new()
	var ls := BoxShape3D.new()
	ls.size = Vector3(0.6, 0.8, 0.15)
	lcol.shape = ls
	lock.add_child(lcol)
	_add_lamp("Lock", Vector3(0.7, 1.8, 18.6), 0.5, Color(0.8, 0.6, 0.4))

	var exit := _make_door("ExitDoor", true, false)
	exit.unlock_condition = _DOOR_SCRIPT.UnlockCondition.CODE_ENTERED
	exit.position = Vector3(-0.7, 1.1, 18.9)
	exit.rotation.y = PI

	var back := _make_door("BackDoor", false, true)
	back.position = Vector3(0, 1.1, -2.85)


func _make_door(door_name: String, advances: bool, goes_back: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = door_name
	body.set_script(_DOOR_SCRIPT)
	body.advances_level = advances
	body.goes_back = goes_back
	add_child(body)
	var mesh := MeshInstance3D.new()
	mesh.name = "DoorMesh"
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 2.2, 0.15)
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.01, 0.01)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.02, 0.02)
	mat.emission_energy_multiplier = 1.5
	mesh.set_surface_override_material(0, mat)
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 2.2, 0.2)
	col.shape = shape
	body.add_child(col)
	return body


# ---------------------------------------------------------------- window/forest

func _spawn_window() -> void:
	# Moonlit forest behind glass on the living room's far (north) wall. Inset 0.25
	# keeps it IN FRONT of the 0.2 m-thick wall (room side); the quads are rotated
	# PI to face into the room (-z) and culling is disabled so they read either way.
	_window_pos = _builder.wall_point("LivingRoom", Vector2(0, 1), 1.6, 0.25)
	if ResourceLoader.exists(FOREST_PATH):
		var forest := MeshInstance3D.new()
		var fmesh := QuadMesh.new()
		fmesh.size = Vector2(1.2, 1.3)
		forest.mesh = fmesh
		var fmat := StandardMaterial3D.new()
		var ftex := load(FOREST_PATH)
		fmat.albedo_texture = ftex
		fmat.emission_enabled = true
		fmat.emission_texture = ftex
		fmat.emission_energy_multiplier = 0.9
		fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		forest.set_surface_override_material(0, fmat)
		forest.position = _window_pos + Vector3(0, 0, 0.05)  # behind the glass (+z, toward wall)
		forest.rotation.y = PI
		add_child(forest)

	var glass := MeshInstance3D.new()
	var pane := QuadMesh.new()
	pane.size = Vector2(1.2, 1.3)
	glass.mesh = pane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.06, 0.08, 0.1, 0.1)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.metallic = 0.6
	gmat.roughness = 0.15
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.set_surface_override_material(0, gmat)
	glass.position = _window_pos
	glass.rotation.y = PI
	add_child(glass)

	# A simple wooden frame so the window reads as a window, not a floating picture.
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.12, 0.08, 0.05)
	frame_mat.roughness = 0.85
	for bar_size in [Vector3(1.32, 0.08, 0.05), Vector3(0.08, 1.42, 0.05)]:
		var bar := MeshInstance3D.new()
		var bmesh := BoxMesh.new()
		bmesh.size = bar_size
		bar.mesh = bmesh
		bar.set_surface_override_material(0, frame_mat)
		bar.position = _window_pos + Vector3(0, 0, -0.03)
		add_child(bar)


# ---------------------------------------------------------------- cursed props

func _spawn_cursed_props() -> void:
	# Family painting in the bedroom; tarnished mirror in the living room.
	_make_cursed_body(_builder.wall_point("Bedroom", Vector2(1, 0), 1.5, 0.08),
		Vector2(0.8, 1.0), -PI / 2.0, 0.8, Color(0.1, 0.08, 0.07), TEX + "painting_house.png")
	_make_cursed_body(_builder.wall_point("LivingRoom", Vector2(0, -1), 1.5, 0.08),
		Vector2(0.7, 1.1), 0.0, 1.2, Color(0.05, 0.07, 0.08), "")


func _make_cursed_body(pos: Vector3, size: Vector2, y_rot: float, intensity: float,
		albedo: Color, tex_path: String) -> void:
	var scary := ScaryObject.new()
	scary.scare_intensity = intensity
	add_child(scary)
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = y_rot
	scary.add_child(body)
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	if tex_path != "" and ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
	else:
		mat.albedo_color = albedo
		mat.metallic = 0.8
		mat.roughness = 0.15
	quad.set_surface_override_material(0, mat)
	body.add_child(quad)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y, 0.1)
	col.shape = shape
	body.add_child(col)


# ---------------------------------------------------------------- new scares

func _spawn_tv() -> void:
	# A dead TV in the living room whose static resolves into a face — gaze panic.
	var pos: Vector3 = _builder.room_center("LivingRoom") + Vector3(2.6, 0.9, -2.4)
	var scary := ScaryObject.new()
	scary.scare_intensity = 1.0
	add_child(scary)
	var body := StaticBody3D.new()
	body.position = pos
	scary.add_child(body)
	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.8, 0.55, 0.08)
	screen.mesh = sm
	var mat := StandardMaterial3D.new()
	var tv_tex := TEX + "tv_static_face.png"
	if ResourceLoader.exists(tv_tex):
		mat.albedo_texture = load(tv_tex)
		mat.emission_enabled = true
		mat.emission_texture = load(tv_tex)
		mat.emission_energy_multiplier = 0.7
	else:
		mat.albedo_color = Color(0.05, 0.06, 0.06)
		mat.emission_enabled = true
		mat.emission = Color(0.1, 0.15, 0.12)
		mat.emission_energy_multiplier = 0.5
	screen.set_surface_override_material(0, mat)
	body.add_child(screen)
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(0.8, 0.55, 0.1)
	col.shape = cs
	body.add_child(col)
	# Static hiss loop.
	_loop_audio("tv_static", pos, -14.0)


func _spawn_bathroom_mirror() -> void:
	var pos: Vector3 = _builder.wall_point("Bathroom", Vector2(-1, 0), 1.5, 0.1)
	var mirror := LivingMirror.new()
	mirror.position = pos
	mirror.rotation.y = PI / 2.0   # face +x into the bathroom
	add_child(mirror)


func _spawn_music_box() -> void:
	_loop_audio("music_box", _builder.room_center("ChildRoom") + Vector3(0, 0.6, 0), -12.0)


func _spawn_cellar_contents() -> void:
	var c := CELLAR_CENTER
	# Dread + dark zone over the whole cellar.
	for maker in [func() -> Area3D: return DreadZone.new(), func() -> Area3D: return DarkZone.new()]:
		var zone: Area3D = maker.call()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(CELLAR_SIZE.x, CELLAR_H, CELLAR_SIZE.y)
		col.shape = shape
		zone.add_child(col)
		zone.position = Vector3(c.x, CELLAR_Y + CELLAR_H / 2.0, c.y)
		add_child(zone)
	# Water drips ambience.
	_loop_audio("water_drip", Vector3(c.x, CELLAR_Y + 1.0, c.y), -10.0)
	# A beartrap waiting in the dark.
	var trap := Beartrap.new()
	trap.position = Vector3(c.x + 1.5, CELLAR_Y, c.y + 0.5)
	add_child(trap)

	# The cellar gate (blocks the ramp opening until the key is found) + the key.
	_cellar_gate = CSGBox3D.new()
	_cellar_gate.name = "CellarGate"
	_cellar_gate.size = Vector3(1.7, 3.0, 0.2)  # fills the full opening — no transom leak
	_cellar_gate.position = Vector3(5.0, 1.5, 3.0)
	_cellar_gate.use_collision = true
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.12, 0.08, 0.05)
	gm.roughness = 0.85
	_cellar_gate.material = gm
	add_child(_cellar_gate)

	var key := KeyItem.new()
	key.label_text = "Cellar key"
	# On top of the stand (top y=0.9), clear of it so the interaction ray hits the
	# key, not the stand. A small gold glow makes it findable in the dark kitchen.
	key.position = _builder.room_center("Kitchen") + Vector3(2.0, 1.05, 1.6)
	key.picked_up.connect(_open_cellar_gate)
	add_child(key)
	var km := MeshInstance3D.new()
	var kb := BoxMesh.new()
	kb.size = Vector3(0.18, 0.04, 0.07)
	km.mesh = kb
	var kmat := StandardMaterial3D.new()
	kmat.albedo_color = Color(0.85, 0.7, 0.2)
	kmat.metallic = 0.8
	kmat.emission_enabled = true
	kmat.emission = Color(0.6, 0.5, 0.1)
	kmat.emission_energy_multiplier = 0.8
	km.set_surface_override_material(0, kmat)
	key.add_child(km)
	var kcol := CollisionShape3D.new()
	var ks := BoxShape3D.new()
	ks.size = Vector3(0.32, 0.24, 0.32)
	kcol.shape = ks
	key.add_child(kcol)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.9, 0.75, 0.3)
	glow.light_energy = 0.35
	glow.omni_range = 2.5
	key.add_child(glow)
	# A small visual stand so the key isn't floating. NO collision — otherwise its
	# box intercepts the interaction raycast and the key can't be picked up.
	var stand := CSGBox3D.new()
	stand.size = Vector3(0.5, 0.9, 0.5)
	stand.position = key.position - Vector3(0, 0.6, 0)
	stand.use_collision = false
	var stm := StandardMaterial3D.new()
	stm.albedo_color = Color(0.2, 0.14, 0.08)
	stand.material = stm
	add_child(stand)


func _open_cellar_gate() -> void:
	if not _cellar_gate:
		return
	var t := create_tween()
	t.tween_property(_cellar_gate, "position:y", 4.6, 0.9).set_trans(Tween.TRANS_QUAD)
	t.tween_callback(func() -> void: _cellar_gate.use_collision = false)
	_play_at("creak", Vector3(5, 1.2, 3), 2.0)


# ---------------------------------------------------------------- apparition

func _spawn_apparition() -> void:
	# A "hold your nerve" apparition that appears as you descend into the cellar.
	# Not a teaching encounter — it was taught in the Lab — so sprinting is fatal.
	_apparition = Apparition.spawn(self, Apparition.Rule.HOLD, Vector3.ZERO, false) as Apparition
	_spawn_event(Vector3(5, CELLAR_Y + 1.5, -2.0), Vector3(2.5, CELLAR_H, 1.5), _trigger_apparition)


func _trigger_apparition() -> void:
	if _apparition_fired or not _apparition:
		return
	_apparition_fired = true
	_apparition.appear()


# ---------------------------------------------------------------- events

func _spawn_events() -> void:
	_spawn_event(Vector3(0, 1.5, 1.5), Vector3(3, 3, 1.5), _ev_front_door_slam)
	_spawn_event(Vector3(0, 1.5, 8.0), Vector3(3, 3, 1.5), _ev_footsteps_above)
	_spawn_event(_builder.room_center("Bedroom") + Vector3(0, 1.5, -2.4), Vector3(2, 3, 1.2), _ev_bedroom_dark)


func _spawn_event(pos: Vector3, size: Vector3, callback: Callable) -> void:
	var ev := CorridorEvent.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	ev.add_child(col)
	ev.position = pos
	ev.fired.connect(callback)
	add_child(ev)


func _ev_front_door_slam() -> void:
	_play_at("door_slam", Vector3(0, 1.2, -3.0), 2.0)
	var p := _player()
	if p:
		p.add_panic(8.0)


func _ev_footsteps_above() -> void:
	_play_at("footsteps_above", Vector3(0, 3.2, 8.0), 3.0)
	var p := _player()
	if p:
		p.add_panic(6.0)


func _ev_bedroom_dark() -> void:
	var lamp: OmniLight3D = get_node_or_null("Lamp_Bedroom")
	if lamp:
		var t := create_tween()
		t.tween_property(lamp, "light_energy", 1.2, 0.12)
		t.tween_property(lamp, "light_energy", 0.05, 0.1)
		t.tween_property(lamp, "light_energy", 0.0, 0.25)
		for entry in _lights:
			if entry[0] == lamp:
				entry[1] = 0.0
	var zone := DarkZone.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(6, 3, 6)
	col.shape = shape
	zone.add_child(col)
	zone.position = _builder.room_center("Bedroom") + Vector3(0, 1.5, 0)
	add_child(zone)
	_play_at("creak", _builder.room_center("Bedroom") + Vector3(0, 2.5, 0), 2.0)
	var p := _player()
	if p:
		p.add_panic(6.0)


# ---------------------------------------------------------------- ambience / ticks

func _start_ambience() -> void:
	var ambient: AudioStreamPlayer = get_node_or_null("AmbientPlayer")
	if ambient:
		var s := GameState.load_audio("ambient_house")
		if s:
			ambient.stream = s
		if ambient.stream:
			ambient.finished.connect(ambient.play)
			ambient.play()
	var creak: AudioStreamPlayer = get_node_or_null("CreakPlayer")
	if creak:
		var cs := GameState.load_audio("creak")
		if cs:
			creak.stream = cs


func _process(delta: float) -> void:
	_tick_forest()
	_tick_timers(delta)
	_drive_lights()


func _tick_forest() -> void:
	if _forest_fired:
		return
	var p := _player()
	if not p:
		return
	var d := Vector2(p.global_position.x - _window_pos.x, p.global_position.z - _window_pos.z)
	if d.length() <= FOREST_SCARE_DIST:
		_forest_fired = true
		Screamer.flash_scare(FOREST_SCARE_PATH, "screamer_forest", 0.8)
		p.jolt_camera(0.08, 0.5)
		p.add_panic(FOREST_SCARE_PANIC)


func _tick_timers(delta: float) -> void:
	_creak_timer -= delta
	if _creak_timer <= 0.0:
		_creak_timer = randf_range(CREAK_MIN, CREAK_MAX)
		var creak: AudioStreamPlayer = get_node_or_null("CreakPlayer")
		if creak and creak.stream:
			creak.play()

	_pipe_timer -= delta
	if _pipe_timer <= 0.0:
		_pipe_timer = randf_range(PIPE_MIN, PIPE_MAX)
		_play_at("pipe_groan", _random_room_point(1.6), 0.0)

	_blackout_timer = maxf(0.0, _blackout_timer - delta)
	_blackout_clock -= delta
	if _blackout_clock <= 0.0:
		_blackout_clock = randf_range(BLACKOUT_MIN, BLACKOUT_MAX)
		_blackout_timer = 1.4
		var p := _player()
		if p:
			p.add_panic(4.0)


func _drive_lights() -> void:
	var t := Time.get_ticks_msec() * 0.001
	for entry in _lights:
		var lamp: OmniLight3D = entry[0]
		var base: float = entry[1]
		if _blackout_timer > 0.0:
			lamp.light_energy = base * (0.05 + maxf(0.0, sin(t * 33.0) * sin(t * 9.0)) * 0.15)
		else:
			lamp.light_energy = base * (1.0 + sin(t * 7.0 + lamp.position.x) * 0.04)


func _random_room_point(y: float) -> Vector3:
	var r: Dictionary = ROOMS[randi() % ROOMS.size()]
	var c: Vector3 = _builder.room_center(r["name"])
	return Vector3(c.x, y, c.z)


func _loop_audio(base_name: String, pos: Vector3, volume_db: float) -> void:
	var stream := GameState.load_audio(base_name)
	if not stream:
		return
	var pl := AudioStreamPlayer3D.new()
	pl.stream = stream
	pl.volume_db = volume_db
	pl.unit_size = 6.0
	pl.max_db = 0.0
	add_child(pl)
	pl.position = pos
	pl.finished.connect(pl.play)
	pl.play()


func _play_at(base_name: String, pos: Vector3, volume_db: float = 0.0) -> void:
	var stream := GameState.load_audio(base_name)
	if not stream:
		return
	var pl := AudioStreamPlayer3D.new()
	pl.stream = stream
	pl.volume_db = volume_db
	pl.unit_size = 8.0
	pl.max_db = 6.0
	add_child(pl)
	pl.position = pos
	pl.finished.connect(pl.queue_free)
	pl.play()


func _box(box_name: String, pos: Vector3, size: Vector3, mat: Material) -> void:
	var b := CSGBox3D.new()
	b.name = box_name
	b.size = size
	b.position = pos
	b.use_collision = true
	if mat:
		b.material = mat
	add_child(b)
