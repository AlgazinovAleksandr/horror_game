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

# DEBUG: see level_1.gd — a survivable apparition re-appears in front of the player
# every DEBUG_APPAR_INTERVAL seconds while true. Flip false for release.
const DEBUG_APPARITION := true
const DEBUG_APPAR_INTERVAL := 45.0

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
var _lights: Array = []           # [OmniLight3D, base_energy, fixture_material]

# Emission on a lamp's visible bulb at full brightness, driven down in step with
# light_energy by _drive_lights() — including _ev_bedroom_dark, which kills the
# bedroom lamp permanently, so its bulb goes visibly dead with it.
# ⚠️ Must stay below 1.0 — Linear tonemapping with no glow clamps anything higher
# to flat white. See the fuller note on level_1.gd's FIXTURE_EMISSION.
const FIXTURE_EMISSION := 0.6
var _window_pos: Vector3
var _forest_fired: bool = false
var _creak_timer: float = 0.0
var _pipe_timer: float = 0.0
var _blackout_clock: float = 0.0
var _blackout_timer: float = 0.0
var _cellar_gate: CSGBox3D
var _apparition: Apparition
var _apparition_fired: bool = false
var _dbg_appar_timer: float = DEBUG_APPAR_INTERVAL
var _tv_card: Label3D
var _tv_card_clock: float = 12.0   # time until the test card next surfaces
var _tv_card_hold: float = 0.0     # time the card stays legible


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
	_spawn_room_props()
	_spawn_events()
	_spawn_apparition()
	_start_ambience()
	_boost_ambient(0.35)

	Vignette.spawn(self, Color(1.0, 0.88, 0.72, 1.0), 1.4)
	RandomAmbient.register_player(_player())
	GameState.set_objective("Find the cellar key, hidden in the kitchen")
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
	_builder.build(_rooms_with_skins(), DOORS)
	_build_cellar()


# Mutable copy of ROOMS with per-room skins so the kitchen and bathroom read as
# their own rooms rather than more of the same wallpaper.
func _rooms_with_skins() -> Array:
	var skins := {}
	var kw := TEX + "house_kitchen_wall.png"
	if ResourceLoader.exists(kw):
		skins["Kitchen"] = { "wall_mat": RoomBuilder.make_material(
			kw, Vector3(0.4, 0.4, 0.4), Color(0.4, 0.36, 0.28)) }
	var bw := TEX + "house_bathroom_tile.png"
	if ResourceLoader.exists(bw):
		skins["Bathroom"] = { "wall_mat": RoomBuilder.make_material(
			bw, Vector3(0.5, 0.5, 0.5), Color(0.5, 0.52, 0.5)) }
	var out: Array = []
	for r in ROOMS:
		var room: Dictionary = r.duplicate()
		if skins.has(room["name"]):
			room.merge(skins[room["name"]])
		out.append(room)
	return out


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
	# ⚠️ Nudged 1 cm west. The cellar shell reaches y=+1.1 (CELLAR_Y + CELLAR_H), so
	# above ground level it runs alongside the ground-floor walls, and this one shared
	# a plane with a RoomBuilder wall — coincident faces z-fight. 1 cm cannot open a
	# gap (the slab is 0.2 thick and still overlaps everything it did before), it just
	# breaks the tie. Asserted by tests/check_wall_overlap.gd.
	_box("CellarWallW", Vector3(x0 - 0.01, CELLAR_Y + CELLAR_H / 2.0, c.y), Vector3(0.2, CELLAR_H, s.y), _cellar_mat)
	_box("CellarWallE", Vector3(x1, CELLAR_Y + CELLAR_H / 2.0, c.y), Vector3(0.2, CELLAR_H, s.y), _cellar_mat)
	_box("CellarWallS", Vector3(c.x, CELLAR_Y + CELLAR_H / 2.0, z0), Vector3(s.x, CELLAR_H, 0.2), _cellar_mat)
	# Near wall split for the ramp opening (1.6 wide at x=5).
	_box("CellarWallN_A", Vector3(2.7, CELLAR_Y + CELLAR_H / 2.0, z1), Vector3(2.4, CELLAR_H, 0.2), _cellar_mat)
	_box("CellarWallN_B", Vector3(7.3, CELLAR_Y + CELLAR_H / 2.0, z1), Vector3(2.4, CELLAR_H, 0.2), _cellar_mat)

	# The descent ramp. Its top surface MUST be continuous with the floors at both ends
	# or the player can't walk it: a tilted box pokes an end-lip above the floor where
	# it meets it, and Godot's move_and_slide does not climb steps (the real "can't
	# enter the cellar" bug — the player jammed against the top lip). So:
	#   • the top starts at z=1.7, exactly where RoomBuilder's doorway floor-bridge ends
	#     (both at y=0) — the walker crosses bridge→ramp on one flush plane;
	#   • the bottom meets the cellar floor at y=-1.5 and is extended 0.6 m further south
	#     so its lower end-lip is buried under the cellar floor.
	const RAMP_T := 0.3
	var p_top := Vector3(5, 0.0, 1.7)
	var p_bot := Vector3(5, CELLAR_Y, z1)               # cellar near wall, floor level
	var along := (p_bot - p_top).normalized()
	var ang := atan2(-along.y, -along.z)                # slope below horizontal (>0)
	var up_n := Vector3(0, cos(ang), sin(ang))          # ramp top-face normal (points up)
	var s_bot := p_bot + along * 0.6                    # bury the bottom end under the floor
	var surf_mid := (p_top + s_bot) * 0.5
	var ramp_len := (s_bot - p_top).length()

	var stairs_tex: String = TEX + "house_wood_stairs.png"
	var ramp_mat: Material = _cellar_mat
	if ResourceLoader.exists(stairs_tex):
		ramp_mat = RoomBuilder.make_material(stairs_tex, Vector3(0.5, 0.5, 0.5), Color(0.25, 0.17, 0.1))
	var ramp := CSGBox3D.new()
	ramp.name = "CellarRamp"
	ramp.size = Vector3(2.2, RAMP_T, ramp_len)
	ramp.position = surf_mid - up_n * (RAMP_T * 0.5)    # drop centre so the TOP face is the surface line
	ramp.rotation.x = -ang
	ramp.use_collision = true
	ramp.material = ramp_mat
	add_child(ramp)
	# Shaft side walls — parallel to the ramp, offset ±1.2 m in x, raised to seal the
	# sides from the ramp up past the cap.
	for sx in [-1.0, 1.0]:
		var w := CSGBox3D.new()
		w.size = Vector3(0.2, 3.6, ramp_len + 0.4)
		w.position = surf_mid + Vector3(sx * 1.2, 1.4, 0)
		w.rotation.x = -ang
		w.use_collision = true
		w.material = _cellar_mat
		add_child(w)
	# Sloped ceiling, offset a CONSTANT 2.6 m along the ramp normal so headroom is
	# uniform (~2.45 m vertical over the 1.8 m player) the whole way down.
	var shaft_ceil := CSGBox3D.new()
	shaft_ceil.name = "CellarShaftCeiling"
	shaft_ceil.size = Vector3(2.6, 0.3, ramp_len)
	shaft_ceil.position = surf_mid + up_n * 2.6
	shaft_ceil.rotation.x = -ang
	shaft_ceil.use_collision = true
	shaft_ceil.material = _cellar_mat
	add_child(shaft_ceil)
	# Flat cap at kitchen-ceiling height (y=3) over the shaft mouth: seals the wedge
	# above the sloped ceiling (the background is black now, so any residual gap reads
	# as darkness rather than sky).
	var cap := CSGBox3D.new()
	cap.name = "CellarShaftCap"
	cap.size = Vector3(3.0, 0.3, 7.0)
	cap.position = Vector3(5, 3.0, -0.15)
	cap.use_collision = true
	cap.material = _cellar_mat
	add_child(cap)


# ---------------------------------------------------------------- lighting

func _spawn_lights() -> void:
	for r in ROOMS:
		var c: Vector3 = _builder.room_center(r["name"])
		var warm := 0.9
		if r["name"] == "Bedroom" or r["name"] == "ChildRoom":
			warm = 0.75   # bedrooms a touch dimmer / moodier
		_add_lamp(r["name"], Vector3(c.x, 2.6, c.z), warm, Color(0.95, 0.8, 0.6))
	# A dim, cold bulb in the cellar.
	_add_lamp("Cellar", Vector3(CELLAR_CENTER.x, CELLAR_Y + 2.2, CELLAR_CENTER.y), 0.5, Color(0.6, 0.65, 0.7))


func _add_lamp(lamp_name: String, pos: Vector3, energy: float, color: Color) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp_" + lamp_name
	lamp.position = pos
	lamp.light_energy = energy
	lamp.light_color = color
	lamp.omni_range = 10.0
	add_child(lamp)
	_lights.append([lamp, energy, _add_fixture(lamp, color)])


# A visible bulb-and-shade for a ceiling lamp — the domestic counterpart to the
# Lab's fluorescent fitting. See the note in level_1.gd:_add_fixture for why this
# matters: levels 1 and 2 were the only ones lighting rooms with lights that had
# no geometry, and that (not brightness) is what made them read as empty.
#
# Ambient and light energy are unchanged; this only gives the eye a source.
func _add_fixture(lamp: OmniLight3D, color: Color) -> StandardMaterial3D:
	var flex := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.012
	fm.bottom_radius = 0.012
	fm.height = 0.34
	flex.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.1, 0.09, 0.08)
	flex.set_surface_override_material(0, fmat)
	flex.position = Vector3(0, 0.3, 0)
	lamp.add_child(flex)

	var shade := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.07
	sm.bottom_radius = 0.2
	sm.height = 0.18
	shade.mesh = sm
	var smat := StandardMaterial3D.new()
	# ⚠️ Dark albedo on purpose: the shade sits centimetres from its own point
	# light, and a bright albedo renders as a blown-out white slab. See the note in
	# level_1.gd:_add_fixture — the glow belongs to the bulb's emission.
	smat.albedo_color = Color(0.16, 0.13, 0.1)
	smat.roughness = 0.9
	shade.set_surface_override_material(0, smat)
	shade.position = Vector3(0, 0.1, 0)
	lamp.add_child(shade)

	var bulb := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.05
	bm.height = 0.1
	bulb.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = color.darkened(0.85)
	bmat.emission_enabled = true
	bmat.emission = color
	bmat.emission_energy_multiplier = FIXTURE_EMISSION
	bulb.set_surface_override_material(0, bmat)
	bulb.position = Vector3(0, 0.02, 0)
	lamp.add_child(bulb)
	return bmat


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
	mesh.set_surface_override_material(0, _NOTE_SCRIPT.paper_material(trap))
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
	exit.position = Vector3(-0.7, 1.225, 18.9)
	exit.rotation.y = PI

	var back := _make_door("BackDoor", false, true)
	back.position = Vector3(0, 1.225, -2.85)


func _make_door(door_name: String, advances: bool, goes_back: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = door_name
	body.set_script(_DOOR_SCRIPT)
	body.advances_level = advances
	body.goes_back = goes_back
	add_child(body)
	_DOOR_SCRIPT.build_visual(body, Vector3(1.25, 2.45, 0.15), TEX + "house_door.png")
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.25, 2.45, 0.2)
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
	# Four bars around the PERIMETER of the 1.2 x 1.3 pane. Both bars used to be
	# placed at the pane centre, which drew a cross through the middle of the glass
	# instead of a frame around it. The window sits in the north wall (constant z),
	# so the frame spans world X/Y and the offsets are literal.
	const HALF_W := 0.6   # pane half-width
	const HALF_H := 0.65  # pane half-height
	const BAR := 0.08     # bar thickness
	var bars := [
		[Vector3(1.32, BAR, 0.05), Vector3(0, HALF_H + BAR / 2.0, 0)],   # top
		[Vector3(1.32, BAR, 0.05), Vector3(0, -HALF_H - BAR / 2.0, 0)],  # bottom
		[Vector3(BAR, 1.42, 0.05), Vector3(-HALF_W - BAR / 2.0, 0, 0)],  # left
		[Vector3(BAR, 1.42, 0.05), Vector3(HALF_W + BAR / 2.0, 0, 0)],   # right
	]
	for entry in bars:
		var bar := MeshInstance3D.new()
		var bmesh := BoxMesh.new()
		bmesh.size = entry[0]
		bar.mesh = bmesh
		bar.set_surface_override_material(0, frame_mat)
		bar.position = _window_pos + entry[1] + Vector3(0, 0, -0.03)
		add_child(bar)


# ---------------------------------------------------------------- cursed props

func _spawn_cursed_props() -> void:
	# Family painting on the bedroom's SOUTH wall; tarnished mirror in the living room.
	# (The east wall is the bedroom's only doorway — a collider/ScaryObject there both
	# blocks entry AND spikes panic as you push against it. The note with digit 2 is on
	# the north wall, the bed on the west, so the south wall is clear.)
	_make_cursed_body(_builder.wall_point("Bedroom", Vector2(0, -1), 1.5, 0.08),
		Vector2(0.8, 1.0), 0.0, 0.8, Color(0.1, 0.08, 0.07), TEX + "painting_house.png")
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
	# The face art is a .jpg on disk; resolve .png then .jpg (it was looking only for
	# .png, so the TV silently fell back to a grey screen).
	var tv_tex := Apparition._resolve_tex(TEX + "tv_static_face")
	if tv_tex != "":
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

	# KONTUR HINT 2/4 — the answer to KONTUR's Gate 2 (which bottle). Every so often
	# the static resolves into a broadcast test card for a few seconds, then loses it
	# again: you have to be in the room, looking, at the right moment. Rendered as
	# text over the screen so it needs no new texture. See kontur.gd.
	_tv_card = Label3D.new()
	_tv_card.name = "KonturTestCard"
	_tv_card.text = "O-41 RETARDS ON CONTACT\nWITH ACETIC ACID.\n\nHOUSEHOLD VINEGAR.\nNOTHING ELSE."
	_tv_card.font_size = 44
	_tv_card.pixel_size = 0.0016
	_tv_card.modulate = Color(0.75, 0.95, 0.8, 0.0)
	_tv_card.outline_size = 0
	_tv_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tv_card.position = pos + Vector3(0, 0, 0.05)   # proud of the +z screen face
	add_child(_tv_card)


func _spawn_bathroom_mirror() -> void:
	# North wall — the west wall (Vector2(-1,0)) is the bathroom's only doorway, and the
	# mirror's collider there blocks the entrance.
	# ⚠️ 0.22 — see the note on the Lab's observation mirror. The figure hangs 0.05
	# behind the glass, so the glass needs clearance for the figure as well or the
	# figure ends up inside the wall and is never visible.
	var pos: Vector3 = _builder.wall_point("Bathroom", Vector2(0, 1), 1.5, 0.22)
	var mirror := LivingMirror.new()
	mirror.position = pos
	mirror.rotation.y = 0.0   # LivingMirror faces local -Z → into the room (-z)
	add_child(mirror)


func _spawn_music_box() -> void:
	_loop_audio("music_box", _builder.room_center("ChildRoom") + Vector3(0, 0.6, 0), -12.0)


# Solid furniture so each room reads as a place. No panic — these are just props.
# A solid CSG prop. `tex_path` is optional and guarded, so a prop keeps its
# flat-colour look until art for it exists — same contract as level_1.gd.
func _make_prop(pos: Vector3, size: Vector3, color: Color, y_rot := 0.0,
		tex_path := "") -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.rotation.y = y_rot
	b.use_collision = true
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	if tex_path != "" and ResourceLoader.exists(tex_path):
		m.albedo_texture = load(tex_path)
		m.albedo_color = Color(1, 1, 1)
	b.material = m
	add_child(b)
	return b


func _spawn_room_props() -> void:
	# Kitchen: a counter along the NORTH wall (z-2.4 would sit across the cellar-ramp
	# doorway at z=3 and re-block the descent).
	var kc: Vector3 = _builder.room_center("Kitchen")
	_make_prop(Vector3(kc.x, 0.45, kc.z + 2.4), Vector3(4.0, 0.9, 0.7), Color(0.35, 0.3, 0.24))
	# Bathroom: a bathtub.
	var bc: Vector3 = _builder.room_center("Bathroom")
	_make_prop(Vector3(bc.x + 1.4, 0.3, bc.z), Vector3(0.9, 0.6, 2.2), Color(0.7, 0.72, 0.72))
	# Bedroom: a bed (the cursed painting is already here).
	var bd: Vector3 = _builder.room_center("Bedroom")
	_make_prop(Vector3(bd.x - 1.6, 0.3, bd.z), Vector3(2.2, 0.5, 1.5), Color(0.3, 0.22, 0.2))
	# Child's room: a small bed + an unsettling crayon drawing on the wall.
	var cc: Vector3 = _builder.room_center("ChildRoom")
	_make_prop(Vector3(cc.x + 1.5, 0.25, cc.z), Vector3(1.6, 0.4, 1.0), Color(0.32, 0.24, 0.26))
	var drawing := TEX + "child_drawing.png"
	if ResourceLoader.exists(drawing):
		# East wall (the north wall holds the exit lock/door; the west holds a note).
		_make_cursed_body(_builder.wall_point("ChildRoom", Vector2(1, 0), 1.5, 0.06),
			Vector2(0.7, 0.7), -PI / 2.0, 0.6, Color(0.6, 0.55, 0.5), drawing)


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
	# A key is not box-shaped, so unlike the keycards this one cannot be sold with a
	# face texture on a slab — it needs an ALPHA CUTOUT on a flat quad lying face-up,
	# the same trick as the apparition billboard. If the art is missing we fall back
	# to the old gold box so the level stays completable.
	var key_tex := TEX + "house_cellar_key.png"
	if ResourceLoader.exists(key_tex):
		var kq := MeshInstance3D.new()
		var qm := QuadMesh.new()
		# ⚠️ Must match the art's aspect or the key renders squashed. house_cellar_key.png
		# is cropped to its own alpha bounds at 1435x381 = 3.77:1; a 20 cm key is
		# therefore 0.053 m tall. Re-crop the art and this number has to move with it.
		qm.size = Vector2(0.20, 0.053)
		kq.mesh = qm
		var qmat := StandardMaterial3D.new()
		var tex := load(key_tex)
		qmat.albedo_texture = tex
		# ALPHA_SCISSOR, not ALPHA: a scissored cutout still writes depth, so the key
		# sorts correctly against the stand and the cellar gloom instead of blending.
		qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		qmat.alpha_scissor_threshold = 0.5
		qmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		qmat.emission_enabled = true
		qmat.emission_texture = tex
		qmat.emission_energy_multiplier = 0.5   # findable in a dark kitchen
		kq.set_surface_override_material(0, qmat)
		kq.rotation = Vector3(-PI / 2.0, 0, 0)  # lie flat, face up
		key.add_child(kq)
	else:
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
	GameState.set_objective("Read the 3 notes for the code, then enter it at the exit lock")


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

# See level_1.gd: duplicate the SHARED Environment resource before retuning it, so
# the changes don't bleed into the other levels.
func _boost_ambient(energy: float) -> void:
	var we: WorldEnvironment = get_node_or_null("Environment/WorldEnvironment")
	if not we or not we.environment:
		return
	var env: Environment = we.environment.duplicate()
	env.ambient_light_energy = energy
	env.ambient_light_color = Color(0.12, 0.1, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Black background instead of the procedural sky: any geometry gap (e.g. above the
	# cellar) reads as darkness, not jarring blue sky — the right call for an interior.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	we.environment = env


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
	_tick_debug_apparition(delta)
	_tick_tv_card(delta)


const TV_CARD_HOLD := 4.5
const TV_CARD_GAP_MIN := 16.0
const TV_CARD_GAP_MAX := 26.0


func _tick_tv_card(delta: float) -> void:
	if not _tv_card:
		return
	if _tv_card_hold > 0.0:
		_tv_card_hold -= delta
		# Fade out over the last second so it reads as the signal slipping away.
		var a: float = clampf(_tv_card_hold, 0.0, 1.0)
		_tv_card.modulate.a = a if _tv_card_hold < 1.0 else 1.0
		if _tv_card_hold <= 0.0:
			_tv_card.modulate.a = 0.0
			_tv_card_clock = randf_range(TV_CARD_GAP_MIN, TV_CARD_GAP_MAX)
		return
	_tv_card_clock -= delta
	if _tv_card_clock <= 0.0:
		_tv_card_hold = TV_CARD_HOLD


func _tick_debug_apparition(delta: float) -> void:
	if not DEBUG_APPARITION:
		return
	_dbg_appar_timer -= delta
	if _dbg_appar_timer > 0.0:
		return
	_dbg_appar_timer = DEBUG_APPAR_INTERVAL
	# Fatal (teach=false): hold still to survive, flee → screamer + restart.
	var a := Apparition.spawn(self, Apparition.Rule.HOLD, Vector3.ZERO, false) as Apparition
	if a:
		a.appear()


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
		# Keep the visible bulb in step with the light it stands for.
		if entry.size() > 2 and entry[2] != null:
			var fixture: StandardMaterial3D = entry[2]
			var ratio: float = lamp.light_energy / base if base > 0.0 else 0.0
			fixture.emission_energy_multiplier = FIXTURE_EMISSION * ratio


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
