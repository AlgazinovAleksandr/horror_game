extends Node3D

# Level 4 — The Backrooms. A liminal mono-yellow maze. The player noclipped out
# of the Corridor and woke face-down on the carpet (see corridor.gd entry hook).
#
# The maze is a 4-way intersection hub with three choice arms (N / E / W). Arrow
# decals on the hub columns mark exactly one arm with a DOWN arrow each round.
# Take the down-arrow arm to advance the loop counter; the E/W arms loop you back
# to an identical hub (re-randomised), so it reads as an endless series of
# intersections. Three correct down-turns in a row force the win arm (N) to open
# into the exit utility room with the seam-tearing glitch wall. A wrong turn pops
# the lights, spikes panic, resets the counter and snaps you back to the start.
#
# No continuous seamless portals — the loop is a state machine over real geometry,
# so there are no seams to mis-tune (see the Backrooms design Q1).

const W := 3.0    # corridor width
const H := 3.0    # corridor / ceiling height
const T := 0.3    # wall thickness
const HALF := W / 2.0

const TEX_DIR := "res://assets/textures/level_backrooms/"

const TURNS_TO_WIN := 3
const WRONG_TURN_PANIC := 18.0
const SPAWN := Vector3(0, 0, -5.0)   # entry arm, facing +z into the hub

# Audio. Everything that loops goes through one bus so a SilenceZone can duck the
# whole bed at once. The score deliberately LEADS the hum by 8 dB — the previous
# mix had it 6 dB underneath, which made it inaudible.
# The three zones live at separate world offsets in this one scene; the glitch
# walls teleport between them. Far enough apart that no lighting or audio bleeds.
const ZONE2_ORIGIN := Vector3(200, 0, 0)
const ZONE3_ORIGIN := Vector3(-200, 0, 0)
# 18 was too steep against a 4-way guess in a zone where panic cannot decay: two
# wrong walls spent 72% of the bar before the Flood was even reached.
const WRONG_WALL_PANIC := 12.0

const AUDIO_BUS := "Backrooms"
const MUSIC_VOLUME_DB := -4.0
const HUM_VOLUME_DB := -12.0
const BED_SILENCED_DB := -30.0   # what a SilenceZone ducks the bus to

# Arm geometry: id -> { axis (unit Vector3 from hub outward), length }
const CHOICE_ARMS := {
	"N": { "axis": Vector3(0, 0, 1), "len": 14.5 },   # the win arm -> utility room
	"E": { "axis": Vector3(1, 0, 0), "len": 11.5 },   # loops back
	"W": { "axis": Vector3(-1, 0, 0), "len": 11.5 },  # loops back
}

# Navigation. The "turn" decision is purely position-based (arm-mouth sensors),
# so there is no global state flag to get stranded in — walking back into the hub
# always re-arms every choice. The loop counter only advances when you reach the
# DEAD END of a correct side arm (unreachable down a wrong arm — that mouth snaps
# you back first), so you can't shortcut to the exit.
var _counter: int = 0
var _correct: String = "E"
var _dark_arm: String = ""
var _progress_label: Label = null
var _zone: int = 1
var _zone2: BackroomsZone2 = null
var _zone3: BackroomsZone3 = null

var _arrow_quads := {}          # arm_id -> MeshInstance3D (the arrow decal)
var _arm_lights := { "N": [], "E": [], "W": [], "hub": [] }
var _arm_dark_zones := {}       # arm_id -> DarkZone
var _all_lights: Array = []     # [{ light, base_energy }] for flicker
var _smiler: CreatureSmiler = null

var _wall_mat: StandardMaterial3D
var _floor_mat: StandardMaterial3D
var _ceil_mat: StandardMaterial3D

const _NOTE_SCRIPT := preload("res://scripts/note.gd")

const NOTE_TEXT := """I stopped trying to reach the door. There is no door.

The hum lies. It tells you to keep still and listen. Do not.

Follow the arrows pointing DOWN. Three down turns, taken in a row, will tear the seam. Miss one and the room starts you over.

And if the lights die and something smiles at the end of the hall — kill your light. Stand still. Do not run. Let it pass.

— someone who is still in here"""

@onready var _player: CharacterBody3D = $Player


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameState.current_level = 4

	_make_materials()
	_build_hub()
	_build_entry_arm()
	for id in CHOICE_ARMS:
		_build_choice_arm(id)
	_build_utility_room()
	_spawn_arrow_columns()
	_spawn_lights()
	_spawn_arm_sensors()
	_spawn_intro_note()
	_spawn_kontur_scrawl()
	_spawn_mirage_doors()
	_spawn_phone()
	_start_ambience()
	_build_later_zones()

	# Backrooms-only player rules: the maze forbids rest, and something walks behind you.
	_player.enable_standstill_panic()
	_player.enable_footstep_echo()

	_assign_round()
	_spawn_back_door()
	Vignette.spawn(self, Color(0.95, 0.88, 0.45, 1.0), 1.4)
	GameState.set_objective("Follow the DOWN arrows — three turns in a row (0/3)")
	_restore_progress()
	_check_banishment()


# ---------------------------------------------------------------- back door
#
# ⚠️ A deliberate softening of "no way out behind you", and worth stating plainly.
#
# The Backrooms is the ONLY level with no back door: it is entered by a one-way noclip
# fall out of the Corridor, and the entry arm is capped. That was fine while it was a
# dead end in one direction — but KONTUR's own back door leads HERE, so a player who
# walked back from KONTUR to re-read something landed in a level with no exit but
# clearing all three zones again. That is the precise complaint in BACKLOG #30, and it
# is worse than the fiction it protects.
#
# So: one blood-red door in the entry cap, the same convention every other level uses,
# returning to the Corridor. The zone/counter snapshot means coming back does not cost
# the descent, and corridor.gd drops the player near the noclip rather than at its
# mouth, so the round trip is short.
const _DOOR_SCRIPT := preload("res://scripts/door.gd")

func _spawn_back_door() -> void:
	var body := StaticBody3D.new()
	body.name = "BackDoor"
	body.set_script(_DOOR_SCRIPT)
	body.advances_level = false
	body.goes_back = true
	body.position = Vector3(0, 1.225, -6.9)     # inside face of EntryCap (z = -7)
	add_child(body)
	_DOOR_SCRIPT.build_visual(body, Vector3(1.25, 2.45, 0.15), "")
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.25, 2.45, 0.2)
	col.shape = shape
	body.add_child(col)


# ---------------------------------------------------------------- progress snapshot
#
# The descent (which of the three zones) and the loop counter within zone 1. Without
# this, walking back from KONTUR for one note costs the whole Lobby -> Sprawl -> Flood
# run again — and the Flood is where the roster digits now live, so that trip is one
# players will actually make.

func save_progress() -> Dictionary:
	return {"zone": _zone, "counter": _counter}


func _restore_progress() -> void:
	var data := GameState.get_level_progress(4)
	if data.is_empty():
		return
	var zone: int = int(data.get("zone", 1))
	_counter = int(data.get("counter", 0))
	if zone > 1:
		_enter_zone(zone)      # teleports to that zone's spawn and re-announces it
	elif _counter > 0:
		GameState.set_objective("Follow the DOWN arrows — three turns in a row (%d/%d)"
			% [_counter, TURNS_TO_WIN])


# KONTUR sends the player back here when they open its wrong door and fall out of the
# world. The flag survives the level change because GameState.reset_level_state()
# deliberately doesn't clear it (the same trick `is_ending` uses). Clear it here, so
# the accusation shows exactly once and a later death in the Backrooms doesn't repeat
# it on every reload.
func _check_banishment() -> void:
	if not GameState.kontur_banished:
		return
	GameState.kontur_banished = false
	ScreenText.scrawl(get_tree(),
		"YOU DIDN'T READ.\n\nTHE COLOUR WAS WRITTEN DOWN\nSOMEWHERE YOU DIDN'T LOOK.\n\nGO BACK. FIND IT.",
		6.0, 46)


# ---------------------------------------------------------------- zones 2 & 3

# The three zones are one scene at three world offsets, and the glitch walls
# teleport between them. Keeping it one scene keeps current_level == 4 and avoids
# inventing scene constants for what is, to the player, a single descent.
func _build_later_zones() -> void:
	_zone2 = BackroomsZone2.new()
	_zone2.name = "ZoneSprawl"
	add_child(_zone2)
	_zone2.build(ZONE2_ORIGIN)
	_zone2.cleared.connect(func() -> void: _enter_zone(3))
	_zone2.mistake.connect(_on_zone_mistake.bind(2))

	_zone3 = BackroomsZone3.new()
	_zone3.name = "ZoneFlood"
	add_child(_zone3)
	_zone3.build(ZONE3_ORIGIN, _player)
	_zone3.cleared.connect(func() -> void: GameState.advance_level())  # -> KONTUR
	_zone3.mistake.connect(_on_zone_mistake.bind(3))


# Panic carried between zones with no way to shed it: the Sprawl and the Flood are
# both no-decay zones, so a player arriving at 90% simply died on entry, three times
# in a row in playtest, without ever getting to attempt the puzzle. Clearing a zone
# is the level's biggest beat — it has to come with real relief, or the difficulty
# is decided by the previous room rather than by this one.
const ZONE_ENTRY_PANIC_CAP := 0.25

func _enter_zone(n: int) -> void:
	_zone = n
	if is_instance_valid(_player) and _player.has_method("set_panic_ratio"):
		if _player.get_panic_ratio() > ZONE_ENTRY_PANIC_CAP:
			_player.set_panic_ratio(ZONE_ENTRY_PANIC_CAP)
	match n:
		2:
			_teleport(_zone2.spawn_point)
			_announce("THE SPRAWL")
			GameState.set_objective("Four walls tear. Only one is thin — listen for it")
		3:
			_teleport(_zone3.spawn_point)
			_announce("THE FLOOD")
			GameState.set_objective("The way out does not show itself in the light")


func _teleport(to: Vector3) -> void:
	_player.global_position = to
	_player.velocity = Vector3.ZERO


func _on_zone_mistake(which: int) -> void:
	# A wrong wall: the same shape of penalty as a wrong turn in zone 1, but it also
	# sends you back across the room, so guessing costs distance as well as panic.
	_play("light_pop", _player.global_position + Vector3(0, 2, 0), 2.0)
	Screamer.flash_scare(TEX_DIR + "backrooms_wallpaper_albedo.png", "light_pop", 0.35)
	_player.add_panic(WRONG_WALL_PANIC)
	_player.jolt_camera(0.1, 0.35)
	if which == 2:
		_teleport(_zone2.spawn_point)
	else:
		_teleport(_zone3.spawn_point)


# Zone name card on entry — reuses the progress label's presentation so the level
# keeps one visual voice.
func _announce(title: String) -> void:
	_show_progress_text(title)


# ---------------------------------------------------------------- materials

func _make_materials() -> void:
	_wall_mat = _make_mat(TEX_DIR + "backrooms_wallpaper_albedo.png", Vector2(1.0, 1.0 / 3.0),
		Color(0.78, 0.70, 0.32))
	_floor_mat = _make_mat(TEX_DIR + "backrooms_carpet_albedo.png", Vector2(0.4, 0.4),
		Color(0.32, 0.28, 0.14))
	_ceil_mat = _make_mat("", Vector2.ONE, Color(0.55, 0.52, 0.42))  # stained ceiling tiles (flat)


func _make_mat(tex_path: String, uv_scale: Vector2, fallback: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.95
	if tex_path != "" and ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
		mat.uv1_triplanar = true
		# Negative V (like corridor.gd) keeps the wallpaper upright on walls.
		mat.uv1_scale = Vector3(uv_scale.x, -uv_scale.y, uv_scale.x)
	else:
		mat.albedo_color = fallback
	return mat


# ---------------------------------------------------------------- geometry

# Axis-aligned box. center = world centre, size = full extents.
func _box(box_name: String, center: Vector3, size: Vector3, mat: Material) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = box_name
	b.size = size
	b.position = center
	b.use_collision = true
	if mat:
		b.material = mat
	add_child(b)
	return b


# Floor + ceiling slab pair spanning a rectangle on the xz plane.
func _slab(prefix: String, center_xz: Vector3, size_xz: Vector3) -> void:
	_box(prefix + "Floor", Vector3(center_xz.x, -T / 2.0, center_xz.z),
		Vector3(size_xz.x, T, size_xz.z), _floor_mat)
	_box(prefix + "Ceil", Vector3(center_xz.x, H + T / 2.0, center_xz.z),
		Vector3(size_xz.x, T, size_xz.z), _ceil_mat)


func _wall(wall_name: String, center_xz: Vector3, size_xz: Vector3) -> void:
	_box(wall_name, Vector3(center_xz.x, H / 2.0, center_xz.z),
		Vector3(size_xz.x, H, size_xz.z), _wall_mat)


func _build_hub() -> void:
	# Open 4-way intersection: floor + ceiling only, walls belong to the arms.
	_slab("Hub", Vector3.ZERO, Vector3(W, 0, W))


func _build_entry_arm() -> void:
	# South arm (-z): where you wake. Capped at the back — no way out behind you.
	var lo := -7.0
	_slab("Entry", Vector3(0, 0, (lo - HALF) / 2.0), Vector3(W, 0, HALF - lo))
	# side walls at x = ±(HALF+T/2), running the arm length, overlapping the hub corner
	for sx in [1.0, -1.0]:
		_wall("EntryWall%s" % ("R" if sx > 0 else "L"),
			Vector3(sx * (HALF + T / 2.0), 0, (lo - HALF) / 2.0),
			Vector3(T, 0, HALF - lo + T))
	# back cap
	_wall("EntryCap", Vector3(0, 0, lo - T / 2.0), Vector3(W + 2.0 * T, 0, T))


func _build_choice_arm(id: String) -> void:
	var axis: Vector3 = CHOICE_ARMS[id].axis
	var length: float = CHOICE_ARMS[id].len
	var along := absf(axis.x) > 0.5  # true = arm runs along X
	var mid: float = (HALF + length) / 2.0 + (HALF / 2.0)  # centre of the [HALF, HALF+length] span
	var span_lo := HALF
	var span_hi := HALF + length
	var span_mid := (span_lo + span_hi) / 2.0
	var span_len := span_hi - span_lo + T  # overlap hub corner by T

	if along:
		var cx := axis.x * span_mid
		_slab("Arm%sF" % id, Vector3(cx, 0, 0), Vector3(span_len, 0, W))
		for sz in [1.0, -1.0]:
			_wall("Arm%sWall%s" % [id, "P" if sz > 0 else "N"],
				Vector3(cx, 0, sz * (HALF + T / 2.0)), Vector3(span_len, 0, T))
		# end cap (dead end) for looping arms
		_wall("Arm%sCap" % id, Vector3(axis.x * (span_hi + T / 2.0), 0, 0),
			Vector3(T, 0, W + 2.0 * T))
	else:
		var cz := axis.z * span_mid
		_slab("Arm%sF" % id, Vector3(0, 0, cz), Vector3(W, 0, span_len))
		for sx in [1.0, -1.0]:
			_wall("Arm%sWall%s" % [id, "R" if sx > 0 else "L"],
				Vector3(sx * (HALF + T / 2.0), 0, cz), Vector3(T, 0, span_len))
		# N arm opens into the utility room — no cap, handled in _build_utility_room


func _build_utility_room() -> void:
	# Dead-end room at the end of the N arm. Wider than the corridor, so a junction
	# front wall closes the width step (the fix-void rule). The far wall is the
	# seam-tearing glitch wall (the exit).
	var z0 := HALF + CHOICE_ARMS["N"].len   # front of the room (= N arm end)
	var z1 := z0 + 7.0                       # back wall (glitch)
	var rw := 7.0                            # room width
	var cz := (z0 + z1) / 2.0
	_slab("Util", Vector3(0, 0, cz), Vector3(rw, 0, z1 - z0))
	# side walls
	for sx in [1.0, -1.0]:
		_wall("UtilWall%s" % ("R" if sx > 0 else "L"),
			Vector3(sx * (rw / 2.0 + T / 2.0), 0, cz), Vector3(T, 0, z1 - z0 + T))
	# front junction walls (close the width step, leave the W-wide doorway)
	var side_w := (rw - W) / 2.0
	for sx in [1.0, -1.0]:
		_wall("UtilFront%s" % ("R" if sx > 0 else "L"),
			Vector3(sx * (HALF + side_w / 2.0), 0, z0 - T / 2.0), Vector3(side_w, 0, T))
	_build_glitch_wall(Vector3(0, H / 2.0, z1 - T / 2.0), Vector2(rw, H))


# The exit: a back wall running a screen-space vertex-jitter shader. Walking into
# it tears the seam and drops you into the Void.
func _build_glitch_wall(center: Vector3, size: Vector2) -> void:
	var wall := MeshInstance3D.new()
	wall.name = "GlitchWall"
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.subdivide_width = 48
	mesh.subdivide_depth = 48
	mesh.orientation = PlaneMesh.FACE_Z
	wall.mesh = mesh
	var shader_path := "res://assets/materials/backrooms/glitch_wall.gdshader"
	if ResourceLoader.exists(shader_path):
		var sm := ShaderMaterial.new()
		sm.shader = load(shader_path)
		if ResourceLoader.exists(TEX_DIR + "backrooms_wallpaper_albedo.png"):
			sm.set_shader_parameter("base_tex", load(TEX_DIR + "backrooms_wallpaper_albedo.png"))
		wall.material_override = sm
	else:
		wall.material_override = _wall_mat
	wall.position = center
	add_child(wall)

	# Walk-into trigger just in front of the glitch wall.
	var area := Area3D.new()
	area.name = "ExitTrigger"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, H, 1.2)
	col.shape = shape
	area.add_child(col)
	area.position = center - Vector3(0, 0, 0.9)
	area.body_entered.connect(_on_exit_reached)
	add_child(area)


func _on_exit_reached(body: Node3D) -> void:
	if body != _player:
		return
	# Belt-and-braces: the N mouth already blocks early entry, but never let the
	# seam tear unless the three down-turns are genuinely banked.
	if _counter >= TURNS_TO_WIN - 1:
		_enter_zone(2)   # zone 1 cleared — the descent continues, it doesn't end
	else:
		_wrong_turn()


# ---------------------------------------------------------------- arrows

func _spawn_arrow_columns() -> void:
	# A column just inside each choice-arm mouth, carrying an arrow decal facing
	# the hub centre so the player reads it on approach.
	for id in CHOICE_ARMS:
		var axis: Vector3 = CHOICE_ARMS[id].axis
		var col_pos: Vector3 = axis * (HALF - 0.05)
		var column := _box("ArrowCol%s" % id, Vector3(col_pos.x, H / 2.0, col_pos.z),
			Vector3(0.28, H, 0.28), _wall_mat)
		# arrow quad on the hub-facing side of the column
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.45, 0.7)
		quad.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if ResourceLoader.exists(TEX_DIR + "arrow_decal.png"):
			mat.albedo_texture = load(TEX_DIR + "arrow_decal.png")
		else:
			mat.albedo_color = Color(0.2, 0.18, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(0.6, 0.55, 0.3)
		mat.emission_energy_multiplier = 0.25
		quad.set_surface_override_material(0, mat)
		# face the hub centre (-axis), lifted to eye height, just off the column
		var face := -axis
		quad.transform = Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)),
			col_pos + face * 0.16 + Vector3(0, 1.6, 0))
		add_child(quad)
		_arrow_quads[id] = quad


# Pick the correct arm + dark arm for this round and orient the arrows.
func _assign_round() -> void:
	if _counter >= TURNS_TO_WIN - 1:
		_correct = "N"                       # the winning turn forces the exit arm
	else:
		_correct = ["E", "W"][randi() % 2]   # early rounds loop back
	for id in _arrow_quads:
		# Down arrow = rotate 180° about the face normal (roll) so the tip points down.
		var q: MeshInstance3D = _arrow_quads[id]
		q.rotation.z = PI if id == _correct else 0.0
	_apply_dark_arm()


# ---------------------------------------------------------------- lights

func _spawn_lights() -> void:
	_add_light_strip("hub", Vector3.ZERO)
	# entry arm
	for z in [-2.5, -5.5]:
		_add_light_strip("hub", Vector3(0, 0, z))
	# choice arms
	for id in CHOICE_ARMS:
		var axis: Vector3 = CHOICE_ARMS[id].axis
		var n := int(CHOICE_ARMS[id].len / 4.0)
		for k in range(1, n + 1):
			_add_light_strip(id, axis * (HALF + k * 4.0))
	# utility room
	var uz := HALF + CHOICE_ARMS["N"].len + 3.5
	_add_light_strip("N", Vector3(0, 0, uz))


# A recessed fluorescent fixture: a flat emissive panel flush with the ceiling +
# an OmniLight below it. The aggressive uniform yellow glow of the Backrooms.
func _add_light_strip(arm_id: String, pos: Vector3) -> void:
	var panel := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.2, 0.06, 0.5)
	panel.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.92, 0.75)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.95, 0.7)
	mat.emission_energy_multiplier = 1.6
	panel.set_surface_override_material(0, mat)
	panel.position = pos + Vector3(0, H - 0.05, 0)
	add_child(panel)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.93, 0.65)
	light.light_energy = 1.1
	light.omni_range = 6.0
	light.position = pos + Vector3(0, H - 0.3, 0)
	add_child(light)

	_arm_lights[arm_id].append({ "light": light, "panel": panel, "mat": mat })
	_all_lights.append({ "light": light, "base": 1.1 })


# Dynamic dark zone: one choice arm goes black each round. The player must brave
# the dark (panic creep / flashlight battery) — and it's where the Smiler waits.
func _apply_dark_arm() -> void:
	# restore previously dark arm
	if _dark_arm != "":
		_set_arm_lit(_dark_arm, true)
	# the dark arm is never the correct arm (so the correct path is always readable)
	var candidates := ["E", "W", "N"].filter(func(a): return a != _correct)
	_dark_arm = candidates[randi() % candidates.size()]
	_set_arm_lit(_dark_arm, false)
	_maybe_spawn_smiler(_dark_arm)


func _set_arm_lit(arm_id: String, lit: bool) -> void:
	for f in _arm_lights[arm_id]:
		f.light.visible = lit
		f.mat.emission_energy_multiplier = 1.6 if lit else 0.0
	# manage a DarkZone covering the arm
	if not lit and not _arm_dark_zones.has(arm_id):
		_arm_dark_zones[arm_id] = _make_arm_dark_zone(arm_id)
	elif lit and _arm_dark_zones.has(arm_id):
		_arm_dark_zones[arm_id].queue_free()
		_arm_dark_zones.erase(arm_id)


func _make_arm_dark_zone(arm_id: String) -> Area3D:
	var axis: Vector3 = CHOICE_ARMS[arm_id].axis
	var length: float = CHOICE_ARMS[arm_id].len
	var zone := DarkZone.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var along := absf(axis.x) > 0.5
	shape.size = Vector3(length, H, W) if along else Vector3(W, H, length)
	col.shape = shape
	zone.add_child(col)
	zone.position = axis * (HALF + length / 2.0) + Vector3(0, H / 2.0, 0)
	add_child(zone)
	return zone


# ---------------------------------------------------------------- navigation

func _spawn_arm_sensors() -> void:
	for id in CHOICE_ARMS:
		var axis: Vector3 = CHOICE_ARMS[id].axis
		var along := absf(axis.x) > 0.5
		var area := Area3D.new()
		area.name = "ArmSensor%s" % id
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.6, H, W) if along else Vector3(W, H, 0.6)
		col.shape = shape
		area.add_child(col)
		area.position = axis * (HALF + 1.0) + Vector3(0, H / 2.0, 0)
		area.body_entered.connect(_on_arm_mouth.bind(id))
		add_child(area)

	# Loop-back trigger at the dead end of each looping arm. Only reachable down a
	# CORRECT E/W arm — the wrong-arm mouth teleports you out before you get here.
	for id in ["E", "W"]:
		var axis: Vector3 = CHOICE_ARMS[id].axis
		var area := Area3D.new()
		area.name = "LoopBack%s" % id
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.0, H, W)
		col.shape = shape
		area.add_child(col)
		area.position = axis * (HALF + CHOICE_ARMS[id].len - 0.8) + Vector3(0, H / 2.0, 0)
		area.body_entered.connect(_on_loopback.bind(id))
		add_child(area)


# Crossing an arm mouth IS the turn decision. A wrong arm snaps you back; the
# correct arm just lets you walk on (the dead end / exit does the rest).
func _on_arm_mouth(body: Node3D, id: String) -> void:
	if body != _player:
		return
	if id != _correct:
		_wrong_turn()


# Reached the dead end of the correct side arm = one good down-turn banked.
func _on_loopback(body: Node3D, id: String) -> void:
	if body != _player or id != _correct:
		return
	_counter += 1
	_show_progress()
	_teleport_to_spawn()


func _wrong_turn() -> void:
	_play("light_pop", Vector3(0, H, 0), 2.0)
	_player.add_panic(WRONG_TURN_PANIC)
	_counter = 0
	GameState.set_objective("Wrong turn — follow the DOWN arrows (0/3)")
	_teleport_to_spawn()


func _teleport_to_spawn() -> void:
	_player.global_position = SPAWN
	_player.velocity = Vector3.ZERO
	_assign_round()


# Brief, dim confirmation that a down-turn registered — otherwise a correct turn
# (which loops you back to an identical hub) reads as "nothing happened."
func _show_progress() -> void:
	_show_progress_text("the seam loosens…  (%d / %d)" % [_counter, TURNS_TO_WIN])
	GameState.set_objective("Follow the DOWN arrows — three turns in a row (%d/%d)" % [_counter, TURNS_TO_WIN])


# Shared presentation for both the turn counter and the zone name cards, so the
# level speaks with one voice as it descends.
func _show_progress_text(text: String) -> void:
	if not _progress_label:
		var layer := CanvasLayer.new()
		add_child(layer)
		_progress_label = Label.new()
		_progress_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_progress_label.offset_top = -120
		_progress_label.offset_bottom = -80
		_progress_label.offset_left = -260
		_progress_label.offset_right = 260
		_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_progress_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.5, 0.0))
		_progress_label.add_theme_font_size_override("font_size", 24)
		layer.add_child(_progress_label)
	_progress_label.text = text
	var c: Color = _progress_label.get_theme_color("font_color")
	var tween := create_tween()
	tween.tween_property(_progress_label, "theme_override_colors/font_color",
		Color(c.r, c.g, c.b, 0.9), 0.3)
	tween.tween_interval(1.4)
	tween.tween_property(_progress_label, "theme_override_colors/font_color",
		Color(c.r, c.g, c.b, 0.0), 0.8)


# ---------------------------------------------------------------- note / extras

func _spawn_intro_note() -> void:
	var pos := Vector3(0.9, 0.0, -4.0)
	var table := CSGBox3D.new()
	table.name = "NoteTable"
	table.size = Vector3(0.45, 0.6, 0.4)
	table.use_collision = true
	table.position = pos + Vector3(0, 0.3, 0)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.2, 0.16, 0.1)
	table.material = wood
	add_child(table)

	var note := StaticBody3D.new()
	note.name = "ClueNote"
	note.set_script(_NOTE_SCRIPT)
	note.note_text = NOTE_TEXT
	note.position = pos + Vector3(0, 0.65, 0)
	add_child(note)
	var note_mesh := MeshInstance3D.new()
	note_mesh.mesh = BoxMesh.new()
	(note_mesh.mesh as BoxMesh).size = Vector3(0.21, 0.01, 0.297)
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.85, 0.82, 0.6)
	paper.emission_enabled = true
	paper.emission = Color(0.5, 0.48, 0.35)
	paper.emission_energy_multiplier = 0.3
	note_mesh.set_surface_override_material(0, paper)
	note.add_child(note_mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.35, 0.12, 0.45)
	col.shape = shape
	note.add_child(col)


# KONTUR HINT 4/4 — the answer to KONTUR's Gate 4 (the escort). Marker scrawl on
# the ENTRY arm's left wall: behind you at spawn, so you only read it if you turn
# and look around before walking into the maze. Rendered as text rather than a decal
# so it needs no new texture. See kontur.gd.
#
# ⚠️ NOT on a choice arm's dead end: that is where the Smiler spawns, and reading a
# scrawl there would mean shining your flashlight at it — which is fatal. The entry
# arm is never dark and never hosts a creature.
func _spawn_kontur_scrawl() -> void:
	var lbl := Label3D.new()
	lbl.name = "KonturScrawl"
	lbl.text = "WHEN IT WALKS BEHIND YOU —\nDON'T LOOK BACK.\nIT ISN'T THERE\nUNTIL YOU LOOK."
	lbl.font_size = 44
	lbl.pixel_size = 0.0032
	# Label3D is unshaded, so this stays constant-dark while the wallpaper behind it
	# brightens or dims — the contrast survives any lighting the arm happens to have.
	lbl.modulate = Color(0.09, 0.08, 0.07)
	lbl.outline_size = 0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector3(-(HALF - 0.06), 1.75, -4.6)
	lbl.rotation.y = PI / 2.0   # face +x, across the entry arm
	add_child(lbl)


# Blood-red doors that mock the hope of retreat: [lateral_pos, facing_yaw].
func _spawn_mirage_doors() -> void:
	# [position, facing direction (into corridor)]
	var placements := [
		[Vector3(HALF - 0.06, 0, -3.5), Vector3(-1, 0, 0)],   # entry arm, right wall
		[Vector3(7.0, 0, HALF - 0.06), Vector3(0, 0, -1)],    # E arm, +z wall
		[Vector3(-7.0, 0, -(HALF - 0.06)), Vector3(0, 0, 1)], # W arm, -z wall
	]
	for p in placements:
		var door := MirageDoor.new()
		var face: Vector3 = p[1]
		door.transform = Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)), p[0])
		add_child(door)


func _spawn_phone() -> void:
	var phone := RotaryPhone.new()
	phone.position = Vector3(-0.95, 0, -2.2)  # entry arm carpet, beside the clue note
	# Playtest reported the ring as inaudible three times running — two tuning
	# passes on the procedural `rotary_ring` (duration, then volume/range) didn't
	# fix it, so the synthesized tone itself was likely the problem, not the mix.
	# Switched to the same `phone_ringing` KONTUR already uses successfully for its
	# own Gate 6 phone, at the same proven volume/range.
	phone.ring_audio = "phone_ringing"
	phone.ring_volume_db = 0.0
	phone.ring_unit_size = 12.0
	add_child(phone)


const SMILER_CHANCE := 0.5  # not every dark arm hides one — keep it a threat, not a tax

# A Smiler waits at the end of the (always-wrong) dark arm roughly half the time.
# Only one exists at a time; clear the old one when the round re-rolls.
func _maybe_spawn_smiler(arm_id: String) -> void:
	if is_instance_valid(_smiler):
		if _player:
			_player.set_smiler_active(false)
		_smiler.queue_free()
		_smiler = null
	if randf() > SMILER_CHANCE:
		return
	var axis: Vector3 = CHOICE_ARMS[arm_id].axis
	var end_pos: Vector3 = axis * (HALF + CHOICE_ARMS[arm_id].len - 1.0)
	_smiler = CreatureSmiler.new()
	add_child(_smiler)
	_smiler.global_position = Vector3(end_pos.x, 0, end_pos.z)


# ---------------------------------------------------------------- audio

func _play(base_name: String, pos: Vector3, volume_db: float = 0.0) -> void:
	var stream := GameState.load_audio(base_name)
	if not stream:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.unit_size = 8.0
	add_child(p)
	p.position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _ensure_bus() -> void:
	# One bus for the whole ambient bed, so Zone 2's SilenceZone can duck every
	# looping source with a single tween instead of chasing individual players.
	if AudioServer.get_bus_index(AUDIO_BUS) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, AUDIO_BUS)
	AudioServer.set_bus_send(idx, "Master")


func set_bed_volume_db(db: float) -> void:
	var idx := AudioServer.get_bus_index(AUDIO_BUS)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, db)


func _start_ambience() -> void:
	_ensure_bus()
	var ambient: AudioStreamPlayer = get_node_or_null("AmbientPlayer")
	if not ambient:
		return
	var s := GameState.load_audio("fluorescent_hum")
	if s:
		ambient.stream = s
		# Bed sits UNDER the score now — the music leads by 8 dB.
		ambient.volume_db = HUM_VOLUME_DB
		ambient.bus = AUDIO_BUS
		ambient.finished.connect(ambient.play)
		ambient.play()
	var music := GameState.load_audio("backrooms_music")
	if music:
		var mp := AudioStreamPlayer.new()
		mp.name = "MusicPlayer"
		mp.stream = music
		mp.volume_db = MUSIC_VOLUME_DB
		mp.bus = AUDIO_BUS
		add_child(mp)
		mp.finished.connect(mp.play)
		mp.play()


# ---------------------------------------------------------------- flicker

func _process(_delta: float) -> void:
	# Cheap fluorescent flicker: nudge a couple of random lit fixtures each frame.
	for _i in range(2):
		var f: Dictionary = _all_lights[randi() % _all_lights.size()]
		if f.light.visible:
			f.light.light_energy = f.base * randf_range(0.82, 1.04)

	_catch_out_of_world()


# Safety net. The glitch walls are deliberately walk-through, so any gap they leave
# is a hole in the shell — a playtest ended with the player falling forever out of
# the Sprawl. Rather than trust every future bit of geometry, catch the fall and
# put them back at the current zone's start. This is a bug backstop, NOT a designed
# death: it costs no panic and fires no screamer.
const FALL_Y := -5.0

func _catch_out_of_world() -> void:
	if not is_instance_valid(_player) or _player.global_position.y > FALL_Y:
		return
	var back: Vector3 = SPAWN
	match _zone:
		2: back = _zone2.spawn_point if is_instance_valid(_zone2) else SPAWN
		3: back = _zone3.spawn_point if is_instance_valid(_zone3) else SPAWN
	push_warning("Backrooms: player left the world at %v (zone %d) — recovered"
		% [_player.global_position, _zone])
	_teleport(back)
