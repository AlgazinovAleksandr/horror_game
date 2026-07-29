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

# Whether this level arms random apparitions. Pacing and the teach/fatal decision live
# in ApparitionDirector — see level_1.gd's note on why the old DEBUG_* pair went away.
const RANDOM_APPARITIONS := true

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

# --- THE GUEST (2026-07-28) -----------------------------------------------------------
# The House is the only level in the game with genuine backtracking pressure: the Bathroom
# map -> the key -> the Kitchen -> the cellar -> back to the ChildRoom lock crosses the
# ground floor repeatedly, and every route passes through the Landing, which was EMPTY.
#
# So nothing is ever seen. The house is simply not arranged the way you left it, one step
# per quest milestone, with no sound, no event and no acknowledgement — SCARY.md P6, whose
# whole mechanic is the asymmetry that **if the player never notices, nothing happens**.
#
# ⚠️ ZERO PANIC, all four stages. The fridge below is the only new panic in this level.
const GUEST_HALLWAY_SPOT := Vector3(0.0, 0.11, 7.4)     # Hallway, between you and the exit
# The child stands at the Landing end of the Hallway — framed by a 3 m corridor, on the
# route back from the cellar, so it is seen head-on rather than found in a corner.
const GUEST_CHILD_SPOT := Vector3(0.0, 0.0, 10.0)
const CHILD_VOLUME_DB := 18.0        # "the scream should be much louder" (2026-07-29)
# The cellar sequence, timed exactly as specified on the 2026-07-29 playtest.
const CHILD_APPEAR_DELAY := 5.5      # dark first, then the child
const CHILD_HOLD := 3.0              # …and the lights come back this long after
const CHILD_DIST := 3.2              # how far in front of the player it materialises
# ⚠️ 1.25 -> 1.95 m ("the child should be way bigger"). Taller than a real child on purpose:
# this is a jumpscare at three metres in a pitch-black cellar, not a figure seen across a
# room, and at child height it read as small and far away rather than as on top of you.
const CHILD_HEIGHT := 1.95

# The bedroom painting comes off the wall in front of you, loudly.
const PAINTING_TRIGGER_DIST := 4.5
const PAINTING_TRIGGER_DOT := 0.45
const PAINTING_FALL_TIME := 0.45
const PAINTING_FALL_DB := 8.0

# The fridge — the single new panic term in the atmosphere pass. Voluntary, optional,
# off the quest path, one-shot. See house_fridge.gd's header.
const FRIDGE_PANIC := 10.0

# The footsteps overhead, after the scripted one-shot. Zero panic, on a long gap.
const OVERHEAD_MIN := 40.0
const OVERHEAD_MAX := 70.0

# The cellar's cross-level hint for THE NIGHTMARE (level 7), on the wall AND on screen.
const CELLAR_HINT := "TIMING IS EVERYTHING\nIN THE NIGHTMARE."
const CELLAR_CAPTION_TIME := 4.0

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
# THE GUEST. `_guest_stage` is the number of stages already applied, and it is what
# save_progress carries — a back-door return must not un-rearrange the house.
var _music_box: CSGBox3D = null
var _guest_child_done: bool = false
var _child_dark: bool = false        # every lamp in the house is out while the child is here
var _child_node: Watcher = null      # the figure during the cellar sequence
var _painting_armed: bool = false    # milestone reached; falls when you look at it
var _painting_fallen: bool = false
var _bedroom_painting: StaticBody3D = null
var _guest_stage: int = 0
var _guest_props: Array[MovedProp] = []
var _overhead_timer: float = 0.0     # recurring footsteps, armed by _ev_footsteps_above
var _fridge_opened: bool = false
var _creak_timer: float = 0.0
var _pipe_timer: float = 0.0
var _blackout_clock: float = 0.0
var _blackout_timer: float = 0.0
var _cellar_gate: CellarGate
var _has_cellar_key: bool = false
var _map_solved: bool = false
var _apparition: Apparition
var _apparition_fired: bool = false
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
	_spawn_landing_mirror()
	_spawn_cellar_contents()
	_spawn_cellar_props()
	_spawn_music_box()
	_spawn_room_props()
	_spawn_events()
	_spawn_apparition()
	_spawn_apparition_director()
	_start_ambience()
	_boost_ambient(0.35)

	Vignette.spawn(self, Color(1.0, 0.88, 0.72, 1.0), 1.4)
	RandomAmbient.register_player(_player())
	# ⚠️ This string has now been wrong twice — it has to be re-checked whenever the
	# key quest moves. It said "kitchen" when the key was a Landing drawer search, then
	# "somewhere upstairs" (playtest 2026-07-25) after the drawers were deleted and the
	# quest became the folded map in the BATHROOM (_spawn_bathroom_map). The key is
	# neither upstairs nor a search any more, so name the prop rather than a room: the
	# map is the thing to find, and finding it is the whole of the puzzle.
	GameState.set_objective("Find the folded map — it hides the cellar key")
	_restore_progress()      # last — overrides the fresh-level objective above
	_creak_timer = randf_range(CREAK_MIN, CREAK_MAX)
	_pipe_timer = randf_range(PIPE_MIN, PIPE_MAX)
	_blackout_clock = randf_range(BLACKOUT_MIN, BLACKOUT_MAX)


func _player() -> CharacterBody3D:
	return get_node_or_null("Player") as CharacterBody3D


func _clear_old_scene() -> void:
	for child in get_children():
		if PRESERVE.has(child.name):
			continue
		# ⚠️ remove_child BEFORE queue_free. queue_free() is deferred to the end of the
		# frame, so a node freed this way is STILL A CHILD — and still holding its name
		# — while _ready() builds the replacement level. Godot then renames the new
		# node on the collision (Issue 17), and every later get_node("ExitDoor") in
		# these levels silently missed: probed on the Lab, both doors came back as
		# @StaticBody3D@332 / @334. remove_child() detaches immediately, so the name is
		# free by the time the new door is added. (Found 2026-07-27 by the autoplay
		# harness, which is the first thing that ever looked a door up by name.)
		remove_child(child)
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


# Entry vs. exit spawn — see level_1.gd's note. Coming back from the Corridor you have
# just stepped out of the child's-room exit, not the front door.
const ENTRY_SPAWN := Vector3(0, 0.1, -2.0)
const EXIT_SPAWN := Vector3(0, 0.1, 17.6)

func _place_player() -> void:
	var p := _player()
	if not p:
		return
	if GameState.entered_from_ahead:
		p.global_position = EXIT_SPAWN
		p.rotation = Vector3(0, 0, 0)
	else:
		p.global_position = ENTRY_SPAWN
		p.rotation = Vector3(0, PI, 0)  # face +z into the house


# ---------------------------------------------------------------- progress snapshot
# See GameState.level_progress. A death still wipes this; it only survives navigation.

func save_progress() -> Dictionary:
	return {
		"map_solved": _map_solved,
		"has_cellar_key": _has_cellar_key,
		"cellar_open": is_instance_valid(_cellar_gate) and bool(_cellar_gate.get("_opened")),
		"code_correct": GameState.level2_code_correct,
		"apparition_fired": _apparition_fired,
		"forest_fired": _forest_fired,
		# ⚠️ SCARY.md P6's explicit warning: "register moved props in save_progress() so a
		# back-door return does not un-move them." One int covers all four stages because
		# they are monotonic.
		"guest_stage": _guest_stage,
		"fridge_open": _fridge_opened,
	}


func _restore_progress() -> void:
	var data := GameState.get_level_progress(2)
	if data.is_empty():
		return
	_apparition_fired = bool(data.get("apparition_fired", false))
	_forest_fired = bool(data.get("forest_fired", false))
	GameState.level2_code_correct = bool(data.get("code_correct", false))

	# The house stays rearranged. Forced rather than re-armed: the player already saw these
	# moved before they left, so waiting for another look-away would visibly un-move them.
	var stage := int(data.get("guest_stage", 0))
	if stage > 0:
		_force_guest_stages(stage)
	# A fridge that has been opened must not be re-openable for another 10 panic.
	if bool(data.get("fridge_open", false)):
		_fridge_opened = true
		var fridge := get_node_or_null("Fridge")
		if fridge:
			fridge.queue_free()
	if bool(data.get("map_solved", false)):
		_map_solved = true
		var map := get_node_or_null("HouseMap")
		if map:
			map.queue_free()          # already solved; don't offer the minigame again
	if bool(data.get("cellar_open", false)):
		if is_instance_valid(_cellar_gate):
			_cellar_gate.open()
		GameState.set_objective("Read the 3 notes for the code, then enter it at the exit lock")
	elif bool(data.get("has_cellar_key", false)):
		_has_cellar_key = true
		GameState.set_carried("cellar key")
		GameState.set_objective("Unlock the cellar door under the kitchen stairs")
	elif _map_solved:
		# Won the map but never picked the key up — it is still lying on the counter.
		GameState.set_objective("Collect the cellar key")


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
	# The cellar note is THE GUEST's last trigger: reading it is the deepest point of the
	# route, so the walk back up is the longest single stretch the player will make with
	# their back to the whole house.
	var cellar_note := _make_note(
		Vector3(CELLAR_CENTER.x - 1.5, CELLAR_Y + 1.4, CELLAR_CENTER.y - 2.0), 0.0,
		"Third digit — the one she always used — 2.\n\nDon't forget. Don't forget. Don't forget.", false)
	if cellar_note:
		cellar_note.read.connect(func() -> void: _advance_guest(4))
	# Two trap notes (read-to-die).
	_make_note(_builder.wall_point("Bathroom", Vector2(1, 0), 1.3, 0.1), -PI / 2.0,
		"it got in it got in it got in it got in it got in\n\nDONT READ THIS dont read this stop stop stop stop", true)
	_make_note(_builder.wall_point("ChildRoom", Vector2(-1, 0), 1.3, 0.1), PI / 2.0,
		"Subject 44 was removed on day 3.\nSubject 45 was removed on day 1.\nSubject 46 was removed on day 6.\n\nYou are not going to make it.", true)


# Returns the note body so a caller can hook its `read` signal (note.gd emits that on OPEN,
# which is the generic hook the project lacked until level_1.gd's locker gate needed it).
# Existing call sites ignore the return — additive.
func _make_note(pos: Vector3, y_rot: float, text: String, trap: bool) -> StaticBody3D:
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
	return note


# ---------------------------------------------------------------- lock + doors

const LOCK_SIZE := Vector2(0.36, 0.45)


func _spawn_lock_and_doors() -> void:
	var exit := _make_door("ExitDoor", true, false)
	exit.unlock_condition = _DOOR_SCRIPT.UnlockCondition.CODE_ENTERED
	exit.position = Vector3(-0.7, 1.225, 18.9)
	exit.rotation.y = PI

	# The combination lock, mounted directly on the exit door as a CHILD of it
	# (local coordinates -> inherits the door's position/rotation automatically)
	# instead of a separate wall panel 1.4 m away. Local z=0.1 sits proud of
	# the door's own face quad (at local z=0.079) so it doesn't z-fight and is
	# the first thing the interact raycast hits.
	var lock := StaticBody3D.new()
	lock.set_script(_LOCK_SCRIPT)
	lock.position = Vector3(0.0, -0.35, 0.1)
	exit.add_child(lock)

	# Artwork on a QuadMesh (CLAUDE.md rule — a BoxMesh crops instead of showing
	# the whole texture). house_lock_transparent.png has a real alpha channel (no
	# backing plate needed — it hangs directly against the door's own wood
	# texture); house_lock.png/lock_face.png stay as opaque fallbacks.
	var lface := MeshInstance3D.new()
	var lqm := QuadMesh.new()
	lqm.size = LOCK_SIZE
	lface.mesh = lqm
	lface.position = Vector3(0, 0, 0.01)
	var lmat := StandardMaterial3D.new()
	var lock_tex_path := TEX + "house_lock_transparent.png"
	if not ResourceLoader.exists(lock_tex_path):
		lock_tex_path = TEX + "house_lock.png"
	if not ResourceLoader.exists(lock_tex_path):
		lock_tex_path = TEX + "lock_face.png"
	if ResourceLoader.exists(lock_tex_path):
		lmat.albedo_texture = load(lock_tex_path)
	lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	lmat.alpha_scissor_threshold = 0.5
	lmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	lmat.metallic = 0.3
	lmat.roughness = 0.7
	lface.set_surface_override_material(0, lmat)
	lock.add_child(lface)

	var lcol := CollisionShape3D.new()
	var ls := BoxShape3D.new()
	ls.size = Vector3(LOCK_SIZE.x, LOCK_SIZE.y, 0.15)
	lcol.shape = ls
	lock.add_child(lcol)

	_add_lamp("Lock", Vector3(-0.7, 1.5, 18.75), 0.4, Color(0.8, 0.6, 0.4))

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
	# Handle kept: THE GUEST puts this face-down on the floor at stage 2.
	_bedroom_painting = _make_cursed_body(
		_builder.wall_point("Bedroom", Vector2(0, -1), 1.5, 0.08),
		Vector2(0.8, 1.0), 0.0, 0.8, Color(0.1, 0.08, 0.07), TEX + "painting_house.png")
	_make_cursed_body(_builder.wall_point("LivingRoom", Vector2(0, -1), 1.5, 0.08),
		Vector2(0.7, 1.1), 0.0, 1.2, Color(0.05, 0.07, 0.08), "")


# Returns the StaticBody3D so a caller can keep a handle on it — THE GUEST needs one for
# the bedroom painting. Every existing call site ignores the return, so this is additive.
#
# ⚠️ ScaryObject is a plain Node with no transform, which BREAKS the Node3D chain, so the
# body's local transform IS its global transform. That is why the world position lives on
# the body (Issue 10) and why MovedProp's global_position arithmetic works on it unchanged.
func _make_cursed_body(pos: Vector3, size: Vector2, y_rot: float, intensity: float,
		albedo: Color, tex_path: String) -> StaticBody3D:
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
	return body


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


# The Landing was 24 m² of nothing — and it is the hub EVERY route crosses (Bathroom map ->
# Kitchen -> cellar -> ChildRoom lock all pass through it), so it was the highest-traffic
# empty space in the game.
#
# A LivingMirror rather than another gaze panel. The House already has five cursed panels
# and the living-room mirror at intensity 1.2 kills from full in ~2 s of staring, so a sixth
# would just be more of the same tax. LivingMirror's figure appears only when you are NOT
# looking head-on (LOOK_DOT 0.8) — which is exactly how you cross a hub — and it costs
# nothing at all unless the player chooses to stand and stare.
#
# ⚠️ NOT placed with wall_point(). Every one of the Landing's four walls has a doorway at
# its centre (z=11, z=14, x=-4, x=+4), and wall_point() returns the wall CENTRE — so the
# usual idiom would have sealed an exit, which is the Session-11 bug that walled off the
# third breaker room. This is hand-placed OFF-centre on the south wall, east of the
# Hallway doorway (which spans x -0.8..0.8).
func _spawn_landing_mirror() -> void:
	# South wall plane is z=11; the inner face is T/2 (0.1) in from that, and the figure
	# hangs 0.05 behind the glass, so 0.22 of inset is the documented minimum.
	var mirror := LivingMirror.new()
	mirror.name = "LandingMirror"
	mirror.position = Vector3(2.5, 1.5, 11.22)
	mirror.rotation.y = PI      # LivingMirror faces local -Z; PI turns it to face +z
	add_child(mirror)


# The cellar was 49 m² with four objects in it — atmospherically the heaviest room in the
# level and physically almost bare.
#
# ⚠️ NO NEW PANIC HERE, deliberately. This leg already carries a DreadZone at net-zero
# decay, a DarkZone, a beartrap worth 55 and an 18-panic HOLD apparition, and the level has
# no CalmZone anywhere — so it is the one stretch with no recovery mechanism at all. What it
# needed was things to search, not more cost.
func _spawn_cellar_props() -> void:
	var cx: float = CELLAR_CENTER.x
	var cz: float = CELLAR_CENTER.y
	var floor_y: float = CELLAR_Y

	# ⚠️ NO FURNITURE BOXES DOWN HERE, and do not add any back without art for them.
	#
	# This pass originally put shelving, a dead boiler and two stacked crates in the cellar,
	# reasoning that 49 m² holding four objects needed "things to search". They were untextured
	# flat-shaded CSG boxes in a room lit by one 0.5-energy lamp, so in practice they were
	# invisible smudges — confirmed by tests/screenshot_level.gd, shot `05_cellar`. Playtest
	# 2026-07-29 called the level's boxes out generally and asked for most of them to go.
	#
	# The cellar's atmosphere was never carried by props: it is a DreadZone plus a DarkZone
	# plus a beartrap plus a HOLD apparition plus the third note, and adding silhouettes that
	# cannot be seen only made the room look unfinished under a torch.

	# The NIGHTMARE hint, spoken to the screen the moment the player reaches the bottom of the
	# ramp. A scrawl rather than a caption: this is the experiment's voice, the same register
	# as the intro's "IT WAS ONLY A DREAM." and the KONTUR banishment line, and it matches the
	# blood-red text on the shelf so the two read as one thing.
	_spawn_event(Vector3(cx, floor_y + 0.9, cz + 2.9), Vector3(3.0, 2.4, 1.6),
		func() -> void:
			ScreenText.scrawl(get_tree(), CELLAR_HINT, CELLAR_CAPTION_TIME)
			_begin_cellar_blackout())

	# ⚠️ NO corner Watcher down here any more, and do not add one back.
	#
	# The atmosphere pass put one in the deepest corner. Playtest 2026-07-29, on the run where
	# the cellar sequence finally worked: *"there is both the shadow and the child jumpscare.
	# Let's leave only the child jumpscare."* Two figures in one 7x7 m room split the moment
	# in half — the corner one is a mood piece and the child is an event, and the mood piece
	# was arriving first and spending the surprise.


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


# The Kitchen was 42 m² — the joint-largest room in the level — holding ONE counter.
#
# ⚠️ Two doorways constrain everything here and both have a test watching them:
#   * the cellar ramp at (5, z=3), width 1.6, i.e. x 4.2..5.8. check_cellar_key.gd
#     raycasts (5, 1.2, 3 +/- 1.2), so nothing may stand in z 1.8..4.2 near x=5.
#   * Hallway <-> Kitchen at (x=1.5, z=6), width 1.4, i.e. z 5.3..6.7.
# Everything below is placed clear of both, and check_doorways.gd re-asserts it.
func _furnish_kitchen(kc: Vector3) -> void:
	# ⚠️ No sink unit. There was a 1.1 x 0.9 x 0.7 pale box here standing in for one, and it
	# read as exactly that — a featureless slab, made worse by sitting next to a fridge that
	# now has a door, a handle and an interior. Cut 2026-07-29 with the cellar boxes.

	# The drawer, set into the counter's south face — the side you approach from. It carries
	# the KONTUR Gate 1 hint; see kitchen_drawer.gd for why this level gets a second one.
	var drawer := KitchenDrawer.new()
	drawer.name = "KitchenDrawer"
	# Counter front face is at kc.z + 2.4 - 0.35; sit the panel just proud of it.
	drawer.position = Vector3(kc.x - 1.0, 0.58, kc.z + 2.4 - 0.36)
	add_child(drawer)

	# ⚠️ A table and two chairs built from REAL PARTS, not single boxes.
	#
	# The first version used `_make_prop` for all three, which is the project's flat-tinted
	# BACKGROUND DRESSING helper — one CSGBox, one colour. Playtest 2026-07-28 photographed
	# the result and called it what it was: *"these boxes … are completely useless."* A
	# 0.44 m cube is not a chair. Issue 35 already says the silhouette carries a prop here and
	# art does not; `intro_room.gd:_build_wheelchair()` and `kontur_mailbox.gd` are the
	# precedent — a dozen cheap primitives that add up to a recognisable object.
	_build_table(Vector3(kc.x - 0.4, 0.0, kc.z + 0.4))
	_build_chair(Vector3(kc.x - 1.5, 0.0, kc.z + 0.4), PI / 2.0)
	_build_chair(Vector3(kc.x + 0.7, 0.0, kc.z + 0.4), -PI / 2.0)

	# The fridge, against the east wall. x=7.9 leaves its face at 8.28, clear of the wall's
	# inner face at 8.4 — the >= 2 cm rule check_wall_overlap.gd asserts.
	var fridge := HouseFridge.new()
	fridge.name = "Fridge"
	fridge.position = Vector3(7.9, 0.0, kc.z + 0.9)
	fridge.rotation.y = -PI / 2.0     # its door faces -x, into the room
	fridge.opened.connect(_on_fridge_opened)
	add_child(fridge)


# A table: top plus four legs. `house_wood_stairs.png` is the House's own timber texture and
# is already in the level, so the top reads as wood without a new asset.
func _build_table(base: Vector3) -> void:
	var top := _make_prop(base + Vector3(0, 0.74, 0), Vector3(1.5, 0.07, 0.95),
		Color(0.42, 0.31, 0.21), 0.0, TEX + "house_wood_stairs.png")
	top.name = "KitchenTable"
	var leg := Color(0.24, 0.17, 0.12)
	for dx in [-0.65, 0.65]:
		for dz in [-0.40, 0.40]:
			_make_prop(base + Vector3(dx, 0.37, dz), Vector3(0.07, 0.74, 0.07), leg)


# A bed: frame, four legs, mattress, pillow, and a headboard.
#
# ⚠️ Both beds used to be a SINGLE flat box — 2.2 x 0.5 x 1.5, one flat colour. Playtest
# 2026-07-29 photographed the child's one and asked "still do not understand what this box is
# for?", which is the correct reaction to a slab on a floor. My earlier reasoning that a
# bed-shaped box in a bedroom reads as a bed was simply wrong: what makes a bed legible is the
# headboard and the mattress sitting proud of a frame, not the footprint. Same lesson as the
# kitchen chairs, and the same fix — a handful of cheap primitives (Issue 35).
func _build_bed(base: Vector3, size: Vector2, y_rot: float = 0.0) -> void:
	var frame_col := Color(0.26, 0.19, 0.14)
	var sheet_col := Color(0.52, 0.49, 0.44)
	var w: float = size.y
	var l: float = size.x
	# Every part is placed in bed-space and then rotated as a group, so `y_rot` turns the
	# whole thing — headboard, pillow and all — rather than just spinning the slabs in place.
	var at := func(off: Vector3) -> Vector3:
		return base + off.rotated(Vector3.UP, y_rot)

	var frame := _make_prop(at.call(Vector3(0, 0.22, 0)), Vector3(l, 0.16, w),
		frame_col, y_rot)
	frame.name = "BedFrame"
	for dx in [-l / 2.0 + 0.09, l / 2.0 - 0.09]:
		for dz in [-w / 2.0 + 0.09, w / 2.0 - 0.09]:
			_make_prop(at.call(Vector3(dx, 0.07, dz)), Vector3(0.09, 0.14, 0.09),
				frame_col, y_rot)
	# The mattress sits PROUD of the frame — that overhang is most of the read.
	_make_prop(at.call(Vector3(0, 0.36, 0)), Vector3(l - 0.06, 0.14, w - 0.04),
		sheet_col, y_rot)
	# Pillow at the head end.
	_make_prop(at.call(Vector3(-l / 2.0 + 0.26, 0.46, 0)),
		Vector3(0.42, 0.09, w * 0.62), Color(0.60, 0.58, 0.53), y_rot)
	# Headboard — the single most identifying part of the silhouette.
	_make_prop(at.call(Vector3(-l / 2.0 - 0.03, 0.44, 0)), Vector3(0.07, 0.72, w),
		frame_col, y_rot)


# A chair: seat, four legs, and a back — the back is what makes the silhouette read as a
# chair rather than as a crate, so it is the one part that must never be dropped.
func _build_chair(base: Vector3, y_rot: float) -> void:
	var wood := Color(0.30, 0.22, 0.16)
	var seat := _make_prop(base + Vector3(0, 0.45, 0), Vector3(0.44, 0.06, 0.44), wood, y_rot)
	seat.name = "KitchenChair"
	var back_offset := Vector3(sin(y_rot), 0.0, cos(y_rot)) * -0.19
	_make_prop(base + Vector3(0, 0.74, 0) + back_offset,
		Vector3(0.44, 0.52, 0.05), wood, y_rot)
	for dx in [-0.17, 0.17]:
		for dz in [-0.17, 0.17]:
			var off := Vector3(dx, 0.0, dz).rotated(Vector3.UP, y_rot)
			_make_prop(base + Vector3(0, 0.22, 0) + off, Vector3(0.05, 0.45, 0.05), wood)


# The level owns the consequence, not the prop. A voluntary, optional, one-shot 10 —
# see the header of house_fridge.gd for why this is the one place panic is spent.
func _on_fridge_opened() -> void:
	_fridge_opened = true
	var p := _player()
	if not p:
		return
	p.jolt_camera(0.08, 0.45)
	p.add_panic(FRIDGE_PANIC)


# The child's music box, as a real object.
#
# ⚠️ It used to be a bare looping AudioStreamPlayer3D at the ChildRoom's centre with NO
# physical object at all — the level's most distinctive sound had no source you could ever
# find. Giving it a body matters for its own sake, and it is also what makes The Guest's
# last beat possible: the loop is a CHILD of the body, so when MovedProp carries the body
# into the Hallway the sound goes with it, and the level's soundtrack becomes retroactively
# suspicious. See _arm_guest().
func _spawn_music_box() -> void:
	var cc: Vector3 = _builder.room_center("ChildRoom")
	# On the floor by the west wall, clear of the small bed at x+1.5 and of both doorways
	# (ChildRoom is entered at (0, z=14); the exit lock is on its north wall).
	var pos := Vector3(cc.x - 1.6, 0.11, cc.z - 1.2)
	_music_box = _make_prop(pos, Vector3(0.30, 0.22, 0.24), Color(0.42, 0.26, 0.14),
		0.0, TEX + "house_music_box.png")
	_music_box.name = "MusicBox"

	# ⚠️ It has to READ as a music box, not as a cube. Playtest 2026-07-29 pointed at it and
	# asked what the box was for — which matters more here than anywhere else in the level,
	# because this object IS The Guest's payoff: finding it in the Hallway only lands if the
	# player recognises it as the thing that was playing in the child's room.
	# So: a lid standing half-open, brass feet, and a crank on the side.
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.62, 0.50, 0.22)
	brass.metallic = 0.7
	brass.roughness = 0.35

	var lid := CSGBox3D.new()
	lid.name = "MusicBoxLid"
	lid.size = Vector3(0.32, 0.03, 0.26)
	# Hinged at the back and tipped open, so the silhouette has a wedge in it.
	lid.position = Vector3(0, 0.19, -0.09)
	lid.rotation.x = deg_to_rad(-52.0)
	lid.material = brass
	_music_box.add_child(lid)

	# Four small feet — they lift it off the floor, which is what stops it reading as a crate.
	for dx in [-0.12, 0.12]:
		for dz in [-0.09, 0.09]:
			var foot := CSGBox3D.new()
			foot.size = Vector3(0.03, 0.04, 0.03)
			foot.position = Vector3(dx, -0.13, dz)
			foot.material = brass
			_music_box.add_child(foot)

	# The crank, on a pivot so winding it actually turns. The stub lies along X (the cylinder
	# is rotated a quarter-turn about Z), so the handle sweeps the YZ plane when the pivot
	# spins about X — which is what `MusicBoxProp.interact()` tweens.
	var crank_pivot := Node3D.new()
	crank_pivot.name = "CrankPivot"
	crank_pivot.position = Vector3(0.18, 0.02, 0)
	_music_box.add_child(crank_pivot)
	var stub := CSGCylinder3D.new()
	stub.radius = 0.012
	stub.height = 0.07
	stub.rotation.z = PI / 2.0
	stub.material = brass
	crank_pivot.add_child(stub)
	var handle := CSGBox3D.new()
	handle.size = Vector3(0.012, 0.07, 0.012)
	handle.position = Vector3(0.035, 0.035, 0)
	handle.material = brass
	crank_pivot.add_child(handle)

	var audio: AudioStreamPlayer3D = null
	var s := GameState.load_audio("music_box")
	if s:
		audio = AudioStreamPlayer3D.new()
		audio.name = "MusicBoxAudio"
		audio.stream = s
		audio.volume_db = -13.0
		audio.unit_size = 6.0
		audio.max_db = 6.0
		audio.bus = AudioBuses.AMBIENCE
		audio.position = Vector3(0, 0.2, 0)
		_music_box.add_child(audio)      # a child, so it travels with the box
		audio.finished.connect(audio.play)
		audio.play()

	# You can wind it (playtest 2026-07-29: "it would be cool if you can play the music using
	# this box"). The interactable body is a separate child rather than the CSG box itself,
	# because `_make_prop` returns a plain CSGBox3D with no script and the interact raycast
	# needs something that answers `interact()`.
	var box := MusicBoxProp.new()
	box.name = "MusicBoxCrank"
	box.position = Vector3.ZERO
	_music_box.add_child(box)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.42, 0.34, 0.34)
	col.shape = shape
	col.position = Vector3(0, 0.05, 0)
	box.add_child(col)
	box.attach_parts(audio, crank_pivot)


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
	_furnish_kitchen(kc)
	# Bathroom: a bathtub.
	var bc: Vector3 = _builder.room_center("Bathroom")
	_make_prop(Vector3(bc.x + 1.4, 0.3, bc.z), Vector3(0.9, 0.6, 2.2), Color(0.7, 0.72, 0.72))
	_spawn_bathroom_map(bc)
	# Bedroom: a bed (the cursed painting is already here).
	var bd: Vector3 = _builder.room_center("Bedroom")
	_build_bed(Vector3(bd.x - 1.6, 0.0, bd.z), Vector2(2.0, 1.4))
	# Child's room: a small bed + an unsettling crayon drawing on the wall.
	var cc: Vector3 = _builder.room_center("ChildRoom")
	# Turned 180° on request (playtest 2026-07-29) — the headboard now faces the other way.
	_build_bed(Vector3(cc.x + 1.5, 0.0, cc.z), Vector2(1.7, 0.95), PI)
	var drawing := TEX + "child_drawing.png"
	if ResourceLoader.exists(drawing):
		# East wall (the north wall holds the exit lock/door; the west holds a note).
		_make_cursed_body(_builder.wall_point("ChildRoom", Vector2(1, 0), 1.5, 0.06),
			Vector2(0.7, 0.7), -PI / 2.0, 0.6, Color(0.6, 0.55, 0.5), drawing)


# The Bathroom map-and-chase minigame (new feature, replaces the Landing 2-drawer
# search — briefly lived on the Kitchen counter first, moved here per playtest:
# "this room has nothing except the [trap] note, put the map there"). The trap
# note ("it got in it got in...") is on the east wall; the bathtub occupies
# roughly x:7.45-8.35, z:11.4-13.6. One small stand sits clear of both and of the
# west-wall doorway's swing (x=4, z:11.8-13.2). Playtest: "once I pass the maze,
# the map should disappear and the key spawn instead of it" — HouseMap now
# queue_frees itself on a win (house_map_prop.gd), so the key reuses this exact
# stand/position rather than a separate one.
func _spawn_bathroom_map(bc: Vector3) -> void:
	var map_pos := Vector3(bc.x - 1.0, 0.65, bc.z - 1.5)
	_make_prop(Vector3(map_pos.x, 0.3, map_pos.z), Vector3(0.5, 0.6, 0.4), Color(0.55, 0.5, 0.45))
	var map := HouseMap.new()
	map.position = map_pos
	map.name = "HouseMap"
	map.won.connect(func() -> void:
		_map_solved = true
		_build_cellar_key(map_pos)
		_advance_guest(1)
	)
	add_child(map)


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

	# The cellar gate. Blocks the ramp opening (1.7 x 3.0 fills it completely — no
	# transom leak) until the player UNLOCKS it themselves with the key; see
	# cellar_gate.gd and _on_cellar_gate_used() below.
	_cellar_gate = CellarGate.new()
	_cellar_gate.name = "CellarGate"
	_cellar_gate.position = Vector3(5.0, 1.5, 3.0)
	_cellar_gate.used.connect(_on_cellar_gate_used)
	add_child(_cellar_gate)

	_spawn_nightmare_hint(c)

	# The key itself is no longer a straight pickup — see _spawn_bathroom_map(), a 2D
	# map-and-chase minigame on a stand in the Bathroom. Winning it calls
	# _build_cellar_key() below directly; the Landing 2-drawer search from an earlier
	# pass has been removed (Landing reverts to being an empty pass-through — a
	# deliberate trade for this bigger quest). The map lived on the Kitchen counter
	# briefly in between; that is why some comments still said "Kitchen".


# NIGHTMARE HINT 2/3 — a candle stub on a cellar shelf with a scrawl over it
# (DUNGEON_NIGHTMARES.md §B2). It teaches the ONE number a player of THE NIGHTMARE
# needs and is never told in that level: a candle burns for sixty seconds.
#
# The cellar is the right place for it — it is already a DreadZone + DarkZone the
# player enters carrying a light they are watching the battery of, so a note about
# a light running out reads as atmosphere here and as instructions later. Same
# plant-it-early logic as the four KONTUR hints.
func _spawn_nightmare_hint(c: Vector2) -> void:
	var shelf := CSGBox3D.new()
	shelf.name = "CellarShelf"
	shelf.size = Vector3(0.9, 0.06, 0.3)
	shelf.position = Vector3(c.x - 2.6, CELLAR_Y + 1.15, c.y - 1.8)
	shelf.use_collision = true
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.15, 0.11, 0.07)
	wood.roughness = 0.9
	shelf.material = wood
	add_child(shelf)

	# A burned-down stub. Unlit, dark albedo, NO emission: this is a clue to find
	# with the flashlight, not a beacon (Issues 27/33 — a prop with real presence
	# does not also wear a findability glow).
	var stub := MeshInstance3D.new()
	stub.name = "CandleStub"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.028
	cm.bottom_radius = 0.032
	cm.height = 0.09
	stub.mesh = cm
	var wax := StandardMaterial3D.new()
	wax.albedo_color = Color(0.52, 0.50, 0.44)
	wax.roughness = 0.9
	stub.set_surface_override_material(0, wax)
	stub.position = shelf.position + Vector3(0.0, 0.08, 0.0)
	add_child(stub)

	# ⚠️ REWRITTEN 2026-07-28 on playtest feedback: *"Why would I count these sixty seconds?
	# Does not make sense to me."* The old text ("SIXTY SECONDS. COUNT THEM.") is the
	# cross-level hint for THE NIGHTMARE, where a candle burns for sixty seconds — but it
	# gave the player nothing to act on in the House and nothing to attach it to, so it read
	# as noise rather than as foreshadowing. It now NAMES the level it is about, which is what
	# makes it a hint instead of a riddle, and it is also delivered as an on-screen line when
	# the player enters the cellar (see _spawn_cellar_caption) rather than depending on them
	# happening to point a torch at this shelf.
	# ⚠️ NO WALL SCRAWL HERE, and do not put one back.
	#
	# There used to be a `Label3D` over this shelf reading "SIXTY SECONDS. COUNT THEM.".
	# Playtest 2026-07-28 first found it meaningless ("why would I count these sixty
	# seconds?") and then, once the text was rewritten and also thrown to the screen on
	# entering the cellar, asked for the wall copy to go: *"we do not need this text here —
	# appearing it on the screen is enough."*
	#
	# The candle stub above stays. It is the diegetic half — an object you find with the
	# torch — and the sentence is now delivered once, on screen, by _spawn_cellar_caption().
	# Saying it twice in one room made the shelf read as a label rather than as a thing
	# somebody left behind.


# The key's own visual — an alpha-cutout quad lying flat, same trick as the
# apparition billboard, with a gold-box fallback if the art is missing. Unchanged
# from the version that used to sit on a Kitchen stand; only the calling site and
# position moved.
func _build_cellar_key(pos: Vector3) -> void:
	var key := KeyItem.new()
	key.label_text = "Cellar key"
	key.position = pos
	key.picked_up.connect(_on_cellar_key_taken)
	add_child(key)
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
		# sorts correctly against the drawer and the room gloom instead of blending.
		qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		qmat.alpha_scissor_threshold = 0.5
		qmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		qmat.emission_enabled = true
		qmat.emission_texture = tex
		qmat.emission_energy_multiplier = 0.5   # findable in the dim Landing
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


# ⚠️ BACKLOG #16. This used to be wired straight to the key's `picked_up`, so winning
# the map minigame in the Bathroom flung the cellar open from across the house and the
# key was a formality. Now taking the key only means you are CARRYING it; the door is
# a separate act, at the door.
func _on_cellar_key_taken() -> void:
	_has_cellar_key = true
	GameState.set_carried("cellar key")
	GameState.set_objective("Unlock the cellar door under the kitchen stairs")
	_advance_guest(2)


# ------------------------------------------------------------------------- THE GUEST
#
# Four stages, one per quest milestone. Each one is a MovedProp: the delta is applied the
# first time the player is more than 6 m away AND facing elsewhere, so the change always
# happens off-screen and is always discovered rather than witnessed.
#
# ⚠️ Stages are IDEMPOTENT and monotonic. `_advance_guest(n)` is a no-op if stage n is
# already applied, because the milestones that drive it are not strictly ordered — a player
# can re-enter the level through a back door with the key already taken.
#
# ⚠️ Deliberately only FOUR authored moves, and the chair moves at most twice. A prop that
# keeps moving is a mechanic; this has to stay an anomaly. Do not add a repeating cycle.
func _advance_guest(stage: int) -> void:
	if stage <= _guest_stage:
		return
	# Apply every stage up to `stage`, so a restored snapshot lands in the right state even
	# if it skipped one (e.g. the key was taken but the map's stage never fired).
	for s in range(_guest_stage + 1, stage + 1):
		_apply_guest_stage(s)
	_guest_stage = stage


func _apply_guest_stage(stage: int) -> void:
	match stage:
		1:
			# ⚠️ ARMED, not dropped — it falls WHILE THE PLAYER IS LOOKING, with a bang
			# (playtest 2026-07-29). See _tick_painting().
			#
			# This is the third beat the user has moved off SCARY.md P6's happens-off-screen
			# rule, after the Intro wheelchair and the child, so it is now the house style for
			# this level: in rooms this dark an anomaly nobody witnesses is an anomaly nobody
			# gets. P6 still stands where it belongs — the music box's move at stage 4 is
			# discovered, not watched.
			_painting_armed = true
		2:
			pass    # the key itself is the beat; nothing changes in the house here
		3:
			# ⚠️ THE GUEST SHOWS ITSELF — once, and only once, in the whole level.
			#
			# This stage used to relocate a kitchen chair. Playtest 2026-07-28 saw it and
			# reported *"the objects that are appearing on the floor look just like brown
			# boxes… it should look like a creepy boy or something like that, accompanied by
			# the weird noise"* — and the screenshot proved the point: `_make_prop` builds a
			# single flat-shaded CSGBox, so the "chair" was a 0.44 m cube.
			#
			# Rather than model a better chair, the user's call was to make the thing that
			# appears a FIGURE. So the house's rearrangement is now bracketed by one
			# sighting: the painting goes down, then the child is standing in the Hallway,
			# then the music box has moved. It is a `Watcher` — no panic, no collider, no
			# kill radius, no rule — so it costs the level's tuned budget nothing.
			pass    # the child is owned by the cellar sequence, not by this ladder
		4:
			# The payoff. The music box — the level's signature sound, which until this
			# pass had no object at all — is sitting in the Hallway, playing, between the
			# player and the exit. The loop is a child of the body, so the sound moved too.
			_move_guest_prop(_music_box, "music_box_hallway", GUEST_HALLWAY_SPOT)


# The child, standing in the Hallway, facing you. Once per run.
#
# Placed at the Landing end of the 3 m-wide, 8 m-long Hallway, which is the corridor every
# route back from the cellar has to pass through — so it is framed by the walls and cannot be
# missed the way a prop in the corner of a room can.
#
# ⚠️ A `Watcher`, deliberately: zero panic, no `ScaryObject` ancestor, no collider, no kill
# radius, nothing to learn and no way to fail. It is an image. The whole House rearrangement
# is worth 0 panic and this keeps it that way — the fridge remains the level's only new cost.
#
# ⚠️ `vanish_within` 4.0 so it is gone if the player walks up to it, and `Watcher`'s own
# look-away-then-look-back roll may take it sooner. That is the intent: it is not a thing you
# get to inspect.
# THE CHILD — a scripted three-beat sequence in the cellar, specified by the user on the
# 2026-07-29 playtest after two earlier placements failed to land:
#
#   1. the moment you reach the bottom of the ramp, every light dies AND the torch goes out
#   2. ~5.5 s of nothing but the dark
#   3. the child, screaming, three metres in front of you
#   4. ~3 s later the lights come back and it is gone
#
# Both earlier versions put it in the Hallway and both missed: the first spawned it two rooms
# from the player (the LOS check failed and silently ate the whole beat), the second waited
# for the player to walk back into the Hallway, which happened long after they had left the
# cellar — "the light off actually happened, but after I got away from the cellar".
#
# ⚠️ The dark-zone and standstill taxes are SUSPENDED for the whole sequence
# (`set_smiler_active`, which exists to do exactly this). The cellar is a DarkZone, so forcing
# the torch off would otherwise charge +3/s for a scripted event the player cannot avoid or
# react to — Issue 18, and the player died here at 99 % panic on the run that prompted this.
# The bedroom painting comes off the wall in front of you.
#
# ⚠️ It requires BOTH proximity and a facing check, so it cannot happen behind your back —
# the opposite of the MovedProp rule this level started with, and the explicit request.
func _tick_painting() -> void:
	if not _painting_armed or _painting_fallen:
		return
	if not _bedroom_painting or not is_instance_valid(_bedroom_painting):
		return
	var pl := _player()
	if not pl:
		return
	var cam := pl.get_node_or_null("Camera3D") as Camera3D
	if not cam:
		return
	var to_it := _bedroom_painting.position - cam.global_position
	if to_it.length() > PAINTING_TRIGGER_DIST:
		return
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	to_it.y = 0.0
	if fwd.length() < 0.01 or to_it.length() < 0.01:
		return
	if fwd.normalized().dot(to_it.normalized()) < PAINTING_TRIGGER_DOT:
		return
	_drop_painting(true)


# `animate` false is the restore path — a player returning through a back door should find it
# already down, not watch it fall a second time.
func _drop_painting(animate: bool) -> void:
	if _painting_fallen or not _bedroom_painting:
		return
	_painting_fallen = true
	var p: Vector3 = _bedroom_painting.position
	# -90° pitch lays it flat with the picture facing UP; +90° would point the quad's own +Z
	# at the floor and backface culling would erase it (Issue 28, and it shipped that way
	# once). The small yaw stops it landing squarely.
	var end_pos := Vector3(p.x, 0.06, p.z + 0.55)
	var end_rot := _bedroom_painting.rotation \
		+ Vector3(deg_to_rad(-90.0), deg_to_rad(14.0), 0.0)
	if not animate:
		_bedroom_painting.position = end_pos
		_bedroom_painting.rotation = end_rot
		return

	# `painting_fall` is a shared asset RandomAmbient already uses; loud and local here.
	var s := GameState.load_audio("painting_fall")
	if s:
		var a := AudioStreamPlayer3D.new()
		a.stream = s
		a.volume_db = PAINTING_FALL_DB
		a.max_db = 20.0
		a.unit_size = 10.0
		a.position = p
		add_child(a)
		a.finished.connect(a.queue_free)
		a.play()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_bedroom_painting, "position", end_pos, PAINTING_FALL_TIME)
	tw.tween_property(_bedroom_painting, "rotation", end_rot, PAINTING_FALL_TIME)
	var pl := _player()
	if pl:
		pl.jolt_camera(0.05, 0.3)


func _begin_cellar_blackout() -> void:
	if _guest_child_done:
		return
	_guest_child_done = true
	_child_dark = true
	var pl := _player()
	if pl:
		pl.force_flashlight_off()
		pl.set_smiler_active(true)
	get_tree().create_timer(CHILD_APPEAR_DELAY).timeout.connect(_cellar_child_appear)


func _cellar_child_appear() -> void:
	var pl := _player()
	if not pl:
		_end_cellar_blackout()
		return
	var cam := pl.get_node_or_null("Camera3D") as Camera3D
	var fwd := -cam.global_basis.z if cam else Vector3.FORWARD
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()

	# Straight ahead if it fits, otherwise closer, otherwise the middle of the room. It must
	# NOT be allowed to fail silently the way the Hallway version did.
	var here := pl.global_position
	for d in [CHILD_DIST, 2.4, 1.8]:
		var cand := Vector3(here.x + fwd.x * d, CELLAR_Y, here.z + fwd.z * d)
		_child_node = Watcher.spawn(self, cand, TEX + "house_child.png", 0.0, false, CHILD_HEIGHT)
		if _child_node:
			break
	if not _child_node:
		_child_node = Watcher.spawn(self,
			Vector3(CELLAR_CENTER.x, CELLAR_Y, CELLAR_CENTER.y),
			TEX + "house_child.png", 0.0, false, CHILD_HEIGHT)
	if _child_node:
		# Only this sequence decides when it goes — no lifetime, no look-away roll.
		_child_node.persistent = true
		# Named so it is distinguishable from the cellar's OTHER Watcher (the one in the far
		# corner). Two anonymous "Watcher" nodes in one room made the test's count ambiguous.
		_child_node.name = "GuestChild"
	_spawn_guest_child()
	get_tree().create_timer(CHILD_HOLD).timeout.connect(_end_cellar_blackout)


func _end_cellar_blackout() -> void:
	_child_dark = false
	var pl := _player()
	if pl:
		pl.restore_flashlight()
		pl.set_smiler_active(false)
	if is_instance_valid(_child_node):
		_child_node.queue_free()
		_child_node = null


# Just the scream — the figure and the darkness are owned by the cellar sequence above.
#
# VERY loud, by request. The figure itself has no rules, no collider and costs no panic, so
# sound and darkness are the only two channels this thing has.
func _spawn_guest_child() -> void:
	var s := GameState.load_audio("childe_scream")
	if not s:
		s = GameState.load_audio("guest_child")
	if not s:
		s = GameState.load_audio("music_box")
	if not s:
		return
	var p := AudioStreamPlayer3D.new()
	p.name = "GuestChildAudio"
	p.stream = s
	p.volume_db = CHILD_VOLUME_DB
	p.max_db = 24.0            # default is 3; the gain above is clamped without this
	p.unit_size = 18.0
	p.bus = AudioBuses.AMBIENCE
	# At the figure if there is one, otherwise at the player — the scream must never be
	# stranded at a fixed world point the sequence no longer uses.
	p.position = (_child_node.global_position + Vector3(0, 1.0, 0)) \
		if is_instance_valid(_child_node) else _player().global_position
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# `target_or_delta` is an ABSOLUTE position for props being relocated across the house, and
# MovedProp wants a delta — so convert here, once, rather than at four call sites.
func _move_guest_prop(prop: Node3D, key: String, target: Vector3,
		rot: Vector3 = Vector3.ZERO, absolute: bool = true) -> void:
	if not prop or not is_instance_valid(prop):
		return
	var delta: Vector3 = (target - prop.position) if absolute else target
	var mp := MovedProp.attach(prop, key, delta, rot)
	mp.arm()
	_guest_props.append(mp)


# Restoring a snapshot must not re-arm the wait — the player already SAW these moved before
# they walked back through the door, so re-arming would silently un-move them until they
# happened to look away again. apply_now() is MovedProp's restore path.
#
# ⚠️ Delegates to _advance_guest() rather than looping _apply_guest_stage() itself. The first
# version did the latter and DOUBLE-APPLIED every delta that _advance_guest had already
# attached: the chair's Landing move is (-3.9, 0, +6.1), and applying it twice put the chair
# at (-2.3, 18.6) — outside the house, through two walls. Caught by
# tests/check_house_guest.gd. `_advance_guest` is the only thing that may attach, precisely
# because it is the only thing that tracks what has already been attached.
func _force_guest_stages(stage: int) -> void:
	_advance_guest(stage)
	if _painting_armed and not _painting_fallen:
		_drop_painting(false)
	for mp in _guest_props:
		mp.apply_now()


func _on_cellar_gate_used() -> void:
	if not _cellar_gate:
		return
	if not _has_cellar_key:
		ScreenText.toast(get_tree(), "It is locked. Something holds it from the other side.",
			Color(0.9, 0.85, 0.75), 2.0)
		return
	_has_cellar_key = false
	GameState.set_carried("")
	_cellar_gate.open()
	_play_at("creak", Vector3(5, 1.2, 3), 2.0)
	GameState.set_objective("Read the 3 notes for the code, then enter it at the exit lock")
	_advance_guest(3)


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
	# Fatal — unless this is somehow the player's first HOLD encounter, which the
	# global ledger in ApparitionDirector.arm() decides.
	ApparitionDirector.arm(_apparition)


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
	# ⚠️ And from now on they come back, at ZERO panic, on a 40-70 s gap.
	#
	# This fired exactly once, for 6 panic, and never again — in a house that is entirely
	# SINGLE-STOREY (every room's floor is at y=0; the only vertical element is the cellar
	# ramp). One footstep event is a noise; a recurring one makes an upstairs that does not
	# exist into a permanent resident. The panic stays on the first one only, because the
	# point is presence, not pressure.
	_overhead_timer = randf_range(OVERHEAD_MIN, OVERHEAD_MAX)


# Footsteps on the ceiling of whichever room the player is standing in — so they track,
# rather than always coming from the fixed Hallway spot the one-shot used.
func _tick_overhead(delta: float) -> void:
	if _overhead_timer <= 0.0:
		return
	_overhead_timer -= delta
	if _overhead_timer > 0.0:
		return
	var p := _player()
	if p:
		var above := p.global_position + Vector3(randf_range(-1.5, 1.5), 3.2,
			randf_range(-1.5, 1.5))
		_play_at("footsteps_above", above, 1.0)
	_overhead_timer = randf_range(OVERHEAD_MIN, OVERHEAD_MAX)


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
		ambient.bus = AudioBuses.AMBIENCE   # duckable — see audio_buses.gd
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
	_tick_tv_card(delta)
	_tick_overhead(delta)
	_tick_painting()


const TV_CARD_HOLD := 8.0  # BUG_FIX.md 2.2: was 4.5 — playtest read it as gone too fast
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


func _spawn_apparition_director() -> void:
	if not RANDOM_APPARITIONS:
		return
	var d := ApparitionDirector.new()
	d.name = "ApparitionDirector"
	add_child(d)


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
		if _child_dark:
			# THE GUEST is present: total darkness, no flicker, no exceptions. Checked before
			# the blackout branch so the two cannot fight over the same lamp.
			lamp.light_energy = 0.0
		elif _blackout_timer > 0.0:
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
