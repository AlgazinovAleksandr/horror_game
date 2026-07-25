extends Node3D

# Level 1 — The Lab (expanded). Built procedurally with RoomBuilder from a
# room-graph: a reception, a main corridor with two exam rooms, a cross-junction
# opening onto the records room and the sealed morgue, then an observation room
# and the exit vestibule. The test: restore power (three breakers) to open the
# morgue, take the guarded keycard from between the tray and the monitor without
# looking at them, and reach the exit — all while the lights cut out, pipes groan,
# an apparition tests your nerve, and the observation mirror watches back.

const TEX := "res://assets/textures/level_1_lab/"
# Nodes kept from the .tscn; everything else is rebuilt procedurally.
const PRESERVE := ["Environment", "AmbientPlayer", "JumpscarePlayer", "HUDCanvas", "Player"]

const _DOOR_SCRIPT := preload("res://scripts/door.gd")
const _NOTE_SCRIPT := preload("res://scripts/note.gd")
const _TRIGGER_SCRIPT := preload("res://scripts/trigger_object.gd")
const _KEYCARD_SCRIPT := preload("res://scripts/keycard.gd")

# DEBUG: while true, a survivable apparition re-appears in front of the player every
# DEBUG_APPAR_INTERVAL seconds so it's easy to encounter and tune. Flip false for
# release (the scripted, fires-once taught encounter below still stands).
const DEBUG_APPARITION := true
const DEBUG_APPAR_INTERVAL := 45.0

const BLACKOUT_DURATION := 1.6
const KEYCARD_PANIC := 8.0
const PIPE_MIN := 12.0
const PIPE_MAX := 26.0
const BLACKOUT_MIN := 20.0
const BLACKOUT_MAX := 38.0
const BREAKER_SPARK_MIN := 8.0
const BREAKER_SPARK_MAX := 12.0

var _builder: RoomBuilder
var _lights: Array = []          # [OmniLight3D, base_energy, fixture_material]

# Emission on a lamp's visible diffuser at full brightness. Driven down in step
# with light_energy by _drive_lights(), so a dead or blacked-out lamp also LOOKS
# dead rather than staying a lit panel over a dark room.
#
# ⚠️ MUST stay below 1.0. The project renders with Linear tonemapping, exposure
# 1.0 and no glow (see the shared Environment in assets/elements/environment.tscn),
# so anything above 1.0 clamps to flat pure white with no detail. MazeKit uses 1.6
# and gets away with it because Backrooms strips are only ever seen down a corridor;
# these fittings hang 1.7 m above the player's head and fill the top of the frame.
const FIXTURE_EMISSION := 0.55
var _blackout_timer: float = 0.0
var _pipe_timer: float = 0.0
var _scheduled_blackout: float = 0.0
var _breakers_flipped: int = 0
var _power_on: bool = false
var _morgue_shutter: CSGBox3D
var _apparition: Apparition
var _apparition_fired: bool = false
var _pa_speaker: AudioStreamPlayer3D
var _dbg_appar_timer: float = DEBUG_APPAR_INTERVAL

# The hidden Records breaker's audio/flicker tell.
var _breaker_spark_timer: float = 0.0
var _breaker_spark_pos: Vector3
var _breaker_spark_light: OmniLight3D

# BreakerNook: sound-only tell for its breaker, and a flag the debug-apparition
# tick reads to suppress itself while the player is inside.
#
# ⚠️ There is deliberately NO on-screen proximity readout any more. A hot/cold bar
# driven by straight-line distance was the only cue strong enough to steer by, so
# it replaced the maze instead of supplementing it — and being distance-only it
# also lied, reading a warm ~0.43 from inside a dead end that was nowhere near the
# breaker in walking terms. The beacon in _spawn_dark_beacon() carries direction
# as well as distance, which is what a maze actually needs. Do not re-add a meter.
var _dark_breaker_timer: float = 0.0
var _dark_breaker_pos: Vector3
var _in_breaker_nook: bool = false


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameState.current_level = 1

	_clear_old_scene()
	_build_geometry()
	_place_player()
	_spawn_lights()
	_spawn_notes()
	_spawn_power_quest()
	_spawn_morgue_keycard()
	_spawn_observation_mirror()
	_spawn_room_props()
	_spawn_pa_speaker()
	_spawn_doors()
	_spawn_apparition()
	_start_ambience()
	_boost_ambient(0.35)

	Vignette.spawn(self, Color(0.88, 0.95, 0.88, 1.0), 0.9)
	RandomAmbient.register_player(_player())
	GameState.set_objective("Restore power — flip the breakers (0/3)")
	_pipe_timer = randf_range(PIPE_MIN, PIPE_MAX)
	_scheduled_blackout = randf_range(BLACKOUT_MIN, BLACKOUT_MAX)
	_breaker_spark_timer = randf_range(BREAKER_SPARK_MIN, BREAKER_SPARK_MAX)
	_dark_breaker_timer = randf_range(BREAKER_SPARK_MIN, BREAKER_SPARK_MAX)


func _player() -> CharacterBody3D:
	return get_node_or_null("Player") as CharacterBody3D


func _clear_old_scene() -> void:
	for child in get_children():
		if not PRESERVE.has(child.name):
			child.queue_free()


# ---------------------------------------------------------------- geometry

const ROOMS := [
	{ "name": "Reception", "pos": Vector2(0, 0), "size": Vector2(6, 6) },
	{ "name": "MainHall1", "pos": Vector2(0, 7), "size": Vector2(3, 8) },
	{ "name": "Exam1", "pos": Vector2(-4, 7), "size": Vector2(5, 5) },
	{ "name": "Exam2", "pos": Vector2(4, 7), "size": Vector2(5, 5) },
	{ "name": "CrossHall", "pos": Vector2(0, 12.5), "size": Vector2(12, 3) },
	{ "name": "Records", "pos": Vector2(-9, 12.5), "size": Vector2(6, 6) },
	{ "name": "Morgue", "pos": Vector2(9.5, 12.5), "size": Vector2(7, 6) },
	{ "name": "MainHall2", "pos": Vector2(0, 16.5), "size": Vector2(3, 5) },
	# ⚠️ Was pos(4,17) size(5,5) = x 1.5..6.5, z 14.5..19.5, which poked 0.5 m INTO
	# the Morgue (x>=6) and into the ExitVestibule (z>=19). Overlapping rooms emit
	# overlapping floor and ceiling slabs whose visible faces are both at y=0 / y=h,
	# and coincident surfaces z-fight. Now x 1.5..6.0, z 14.5..19.0 — it abuts both
	# neighbours instead of intersecting them. The MainHall2 doorway at (1.5, 17)
	# still lands on the west wall, so the connection is unchanged.
	{ "name": "Observation", "pos": Vector2(3.75, 16.75), "size": Vector2(4.5, 4.5) },
	{ "name": "ExitVestibule", "pos": Vector2(0, 20.5), "size": Vector2(4, 3) },
	# The dark breaker wing (new feature), redesigned three times after playtest:
	# (1) a single small room directly off Records read as "not dark at all" —
	# Records' lamp (omni_range=11) has no shadow casting to stop it (⚠️ NO light
	# in this whole project casts shadows except the Intro Room's — grep
	# `shadow_enabled` — so a solid wall does not block light here, only DISTANCE
	# does). DarkCorridor puts the terminus beyond that 11 m cutoff: Records'
	# lamp is ~3 m from the corridor doorway, +7 m of corridor, +the rest of the
	# wing = well past the light's hard range limit. The corridor itself still
	# reads as a gradient (dim near Records, genuinely black by the far end).
	# (2) a straight corridor into one room had no decision point — a Junction
	# added a branch: one dead stub, one real destination.
	# (3) Playtest 2026-07-25 (capture #2, "too simple to find this light switch
	# hidden in the dark — make the geometry of this level harder"): that was still
	# ONE binary choice over ~16 m, and the on-screen proximity meter answered it
	# outright. The meter is gone (see _spawn_dark_beacon) and the wing is now a
	# real maze: THREE decision points and THREE dead ends across ~50 m of walking.
	#
	#   Records -> DarkCorridor -> Junction  ---west--> WestCorridor -> Plant  (dead)
	#                                 |
	#                                 +------north----> NorthSpur -> NorthVault (dead)
	#                                 |
	#                                 +------south----> SouthSpur -> SouthHall
	#                                                                  |     |
	#                                                        PumpRoom (dead) |
	#                                                                 BreakerNook
	#
	# ⚠️ Layout invariants, all asserted by tests/check_wall_overlap.gd:
	#   * Rooms ABUT, never overlap. They are kept in three disjoint z-bands —
	#     north (z>=14.5), middle (z 10.5..14.5), south (z<=10.5) — so limbs of the
	#     maze cannot collide with each other as the graph grows.
	#   * A doorway only cuts walls its SPAN overlaps (room_builder.gd:199), so
	#     planes may be reused between bands. E.g. Plant's north wall is also at
	#     z=14.5, but the Junction<->NorthSpur doorway spans x -21.8..-20.2 and
	#     Plant spans x -35..-30, so Plant is untouched.
	# The terminus is ~28 m from Records' lamp — four times its 11 m range.
	{ "name": "DarkCorridor", "pos": Vector2(-15.5, 12.5), "size": Vector2(7.0, 2.2) },
	{ "name": "Junction", "pos": Vector2(-21.0, 12.5), "size": Vector2(4, 4) },
	# --- west limb (dead) ---
	{ "name": "WestCorridor", "pos": Vector2(-26.5, 12.5), "size": Vector2(7, 2.2) },
	{ "name": "Plant", "pos": Vector2(-32.5, 12.5), "size": Vector2(5, 4) },
	# --- north limb (dead) ---
	{ "name": "NorthSpur", "pos": Vector2(-21.0, 17.25), "size": Vector2(2.4, 5.5) },
	{ "name": "NorthVault", "pos": Vector2(-24.5, 22.0), "size": Vector2(9, 4) },
	# --- south limb (the real route) ---
	{ "name": "SouthSpur", "pos": Vector2(-21.0, 8.5), "size": Vector2(2.4, 4) },
	{ "name": "SouthHall", "pos": Vector2(-26.6, 7.7), "size": Vector2(8.8, 2.4) },
	{ "name": "PumpRoom", "pos": Vector2(-25.0, 5.35), "size": Vector2(4, 2.3) },
	{ "name": "BreakerNook", "pos": Vector2(-34.0, 7.7), "size": Vector2(6, 4) },
]

const DOORS := [
	{ "pos": Vector2(0, 3), "width": 1.6, "dir": "z" },        # Reception <-> MainHall1
	{ "pos": Vector2(-1.5, 7), "width": 1.4, "dir": "x" },     # MainHall1 <-> Exam1
	{ "pos": Vector2(1.5, 7), "width": 1.4, "dir": "x" },      # MainHall1 <-> Exam2
	{ "pos": Vector2(0, 11), "width": 1.6, "dir": "z" },       # MainHall1 <-> CrossHall
	{ "pos": Vector2(-6, 12.5), "width": 1.4, "dir": "x" },    # CrossHall <-> Records
	{ "pos": Vector2(6, 12.5), "width": 1.4, "dir": "x" },     # CrossHall <-> Morgue (shutter)
	{ "pos": Vector2(0, 14), "width": 1.6, "dir": "z" },       # CrossHall <-> MainHall2
	{ "pos": Vector2(1.5, 17), "width": 1.4, "dir": "x" },     # MainHall2 <-> Observation
	{ "pos": Vector2(0, 19), "width": 1.6, "dir": "z" },       # MainHall2 <-> ExitVestibule
	{ "pos": Vector2(-12, 12.5), "width": 1.4, "dir": "x" },     # Records <-> DarkCorridor
	{ "pos": Vector2(-19, 12.5), "width": 1.6, "dir": "x" },     # DarkCorridor <-> Junction
	# Junction is the first decision — three ways out, only one of them south.
	{ "pos": Vector2(-23, 12.5), "width": 1.6, "dir": "x" },     # Junction <-> WestCorridor
	{ "pos": Vector2(-30, 12.5), "width": 1.6, "dir": "x" },     # WestCorridor <-> Plant (dead)
	{ "pos": Vector2(-21, 14.5), "width": 1.6, "dir": "z" },     # Junction <-> NorthSpur
	{ "pos": Vector2(-21, 20.0), "width": 1.6, "dir": "z" },     # NorthSpur <-> NorthVault (dead)
	{ "pos": Vector2(-21, 10.5), "width": 1.6, "dir": "z" },     # Junction <-> SouthSpur
	{ "pos": Vector2(-22.2, 7.7), "width": 1.6, "dir": "x" },    # SouthSpur <-> SouthHall
	{ "pos": Vector2(-25, 6.5), "width": 1.6, "dir": "z" },      # SouthHall <-> PumpRoom (dead)
	{ "pos": Vector2(-31, 7.7), "width": 1.6, "dir": "x" },      # SouthHall <-> BreakerNook
]


func _build_geometry() -> void:
	_builder = RoomBuilder.new()
	_builder.wall_mat = RoomBuilder.make_material(
		TEX + "lab_wall.png", Vector3(0.4, 0.4, 0.4), Color(0.5, 0.55, 0.52))
	_builder.floor_mat = RoomBuilder.make_material(
		TEX + "lab_floor.png", Vector3(0.4, 0.4, 0.4), Color(0.3, 0.32, 0.3))
	_builder.ceil_mat = RoomBuilder.make_material(
		TEX + "lab_ceiling.png", Vector3(0.4, 0.4, 0.4), Color(0.22, 0.24, 0.23))
	add_child(_builder)
	_builder.build(_rooms_with_skins(), DOORS)


# A mutable copy of ROOMS carrying per-room material overrides so key rooms read as
# distinct places: the morgue gets stainless lockers + a wet floor.
func _rooms_with_skins() -> Array:
	var morgue_wall := RoomBuilder.make_material(
		TEX + "lab_morgue_wall.png", Vector3(0.5, 0.5, 0.5), Color(0.32, 0.34, 0.36))
	var morgue_floor := RoomBuilder.make_material(
		TEX + "lab_floor_wet.png", Vector3(0.45, 0.45, 0.45), Color(0.18, 0.2, 0.22))
	var skins := {
		"Morgue": { "wall_mat": morgue_wall, "floor_mat": morgue_floor },
	}
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
	p.global_position = Vector3(0, 0.1, -1.5)
	p.rotation = Vector3(0, PI, 0)  # face +z (north, into the lab)


# ---------------------------------------------------------------- lighting

const EMERGENCY_ENERGY := 0.45   # dim emergency power before the breakers are thrown
const RESTORED_ENERGY := 1.0     # full institutional light once power is restored


# Rooms that must never get an automatic ceiling lamp from the loop below —
# the Morgue stays dark until the shutter opens; DarkCorridor/BreakerNook are
# meant to be genuinely lightless. ⚠️ Confirmed bug (playtest): this loop used to
# run for every room except "Morgue", so both new dark rooms got a lamp of their
# own the whole time — "no lamp is ever spawned here" was true of the code that
# built the room, but not of this separate, blanket lighting pass. Any future
# lightless room needs to be added here too, not just left off _add_lamp calls
# elsewhere.
const NO_LAMP_ROOMS := [
	"Morgue",
	# Every room of the dark wing. Keep this in sync with the wing's ROOMS block —
	# a lamp anywhere in here defeats the entire navigate-by-ear premise.
	"DarkCorridor", "Junction",
	"WestCorridor", "Plant",
	"NorthSpur", "NorthVault",
	"SouthSpur", "SouthHall", "PumpRoom", "BreakerNook",
]


func _spawn_lights() -> void:
	# One ceiling lamp per room. They start dim (emergency power); restoring power
	# brightens them.
	for r in ROOMS:
		var c: Vector3 = _builder.room_center(r["name"])
		var emergency: bool = not NO_LAMP_ROOMS.has(r["name"])
		_add_lamp(r["name"], Vector3(c.x, 2.7, c.z), EMERGENCY_ENERGY if emergency else 0.0)


func _add_lamp(lamp_name: String, pos: Vector3, energy: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp_" + lamp_name
	lamp.position = pos
	lamp.light_energy = energy
	lamp.light_color = Color(0.8, 0.88, 0.96)  # cold institutional
	lamp.omni_range = 11.0
	lamp.omni_attenuation = 1.0
	add_child(lamp)
	_lights.append([lamp, energy, _add_fixture(lamp)])


# A visible fluorescent fitting for a ceiling lamp.
#
# The Lab and the House were the only levels lighting rooms with INVISIBLE point
# lights. Corridor pairs every light with a flame mesh (torch_3d.gd, emission 3.0)
# and the Backrooms with an emissive ceiling panel (maze_kit.gd light_strip) — that
# pairing, not raw brightness, is why those levels read. Measured energy per m² is
# the same in the Lab as in KONTUR.
#
# Light energy and ambient are deliberately NOT changed here: the rooms stay just
# as dark, they simply gain a source to look at. The returned material is driven
# from _drive_lights() so flicker, blackouts and the power-restore all reach it.
func _add_fixture(lamp: OmniLight3D) -> StandardMaterial3D:
	var housing := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.86, 0.08, 0.2)
	housing.mesh = hm
	var hmat := StandardMaterial3D.new()
	# ⚠️ Keep fixture albedo DARK. These meshes sit ~0.25 m from their own point
	# light, so a bright albedo receives enormous irradiance and renders as a solid
	# blown-out white slab across the ceiling. The glow must come from EMISSION,
	# which nearby lights don't affect — that also lets a blackout drive the fitting
	# visibly dead, which a lit albedo could never do.
	hmat.albedo_color = Color(0.12, 0.125, 0.12)
	hmat.roughness = 0.8
	housing.set_surface_override_material(0, hmat)
	housing.position = Vector3(0, 0.29, 0)
	lamp.add_child(housing)

	var diffuser := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.76, 0.05, 0.15)
	diffuser.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.1, 0.1, 0.095)   # dark on purpose — see _add_fixture note
	dmat.emission_enabled = true
	dmat.emission = Color(0.85, 0.9, 1.0)
	dmat.emission_energy_multiplier = FIXTURE_EMISSION
	if ResourceLoader.exists(TEX + "lab_light_fitting.png"):
		var tex := load(TEX + "lab_light_fitting.png")
		dmat.albedo_texture = tex
		dmat.emission_texture = tex
		dmat.albedo_color = Color(0.35, 0.35, 0.33)
	diffuser.set_surface_override_material(0, dmat)
	# Flush under the 3.0 m ceiling, matching MazeKit.light_strip's placement.
	diffuser.position = Vector3(0, 0.25, 0)
	lamp.add_child(diffuser)
	return dmat


# ---------------------------------------------------------------- notes

func _spawn_notes() -> void:
	_make_note(Vector3(2.4, 1.4, -2.6), -PI / 2.0,
		"Subject 47.\n\nThe power is down. Three breakers will bring it back — one in each lab room, one in records. The morgue door stays sealed until all three are thrown.\n\nThe keycard is inside the morgue. You will need it for the exit.\n\nAnd if the figure comes — DO NOT RUN. Do not turn and flee. Stand still until it fades. Running is how it reaches you.")
	_make_note(_builder.wall_point("Exam2", Vector2(0, -1), 1.4, 0.1), 0.0,
		"Do not look at the tray. Do not look at the monitor.\n\nThey are not what they appear. When you take the card, keep your eyes on the floor.")
	# Moved off the west wall onto the north wall: the west wall now carries the
	# BreakerNook doorway (new feature), and wall_point always returns a wall's
	# CENTER — a prop there would have sat directly in the new opening (the exact
	# "prop on a doorway wall" bug class this project has hit before).
	_make_note(_builder.wall_point("Records", Vector2(0, 1), 1.4, 0.1), PI,
		"Night log — the corridor lights fail on their own now. When the dark comes, do not run. Running is how they find you. Stand still. Breathe. It passes.")
	# KONTUR HINT 1/4 — the answer to KONTUR's Gate 1 (the two doors). Deliberately
	# filed in the morgue: you only find it if you look around a room that is
	# actively trying to kill you. See kontur.gd.
	_make_note(_builder.wall_point("Morgue", Vector2(0, -1), 1.4, 0.1), 0.0,
		"K.O.N.T.U.R. — INTERNAL CIRCULAR 12/4\n(This page does not belong to this facility.)\n\n...evacuation from a Class-II Object follows Protocol 4-B. Personnel leave by the door marked in BLACK.\n\nRed seals denote contained growth. A red seal is not an exit. A red seal opened from the inside has never once been closed again.\n\nFiled: Barkhan-9. Do not remove from the archive.")


func _make_note(pos: Vector3, y_rot: float, text: String, trap := false) -> void:
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


# ---------------------------------------------------------------- power quest

func _spawn_power_quest() -> void:
	# Three breakers, three difficulty tiers. Exam1 sits in the open, lit, on the
	# wall centre — obvious on sight. Records is the odd one out (BUG_FIX.md 4.1,
	# "too simple, add a moment of searching"): moved off the doorway-facing wall
	# onto the room's other dead-end wall, findable by a spark/flicker tell
	# (_tick_breaker_spark). Exam2's breaker (formerly also "obvious on sight") now
	# lives in BreakerNook at the far end of the lightless wing — findable by sound
	# alone (see _spawn_dark_beacon below).
	#
	# ⚠️ None of these three self-illuminate any more. breaker.gd used to wear its
	# own art as an emission texture, which made even the "hidden" Records one the
	# brightest object in the level (playtest capture #1).
	var exam1 := Breaker.new()
	exam1.position = _builder.wall_point("Exam1", Vector2(-1, 0), 1.3, 0.15)
	exam1.rotation.y = PI / 2.0
	exam1.flipped.connect(_on_breaker_flipped)
	add_child(exam1)

	var hidden_pos: Vector3 = _builder.wall_point("Records", Vector2(0, -1), 1.1, 0.15)
	var hidden := Breaker.new()
	hidden.position = hidden_pos
	hidden.rotation.y = 0.0
	hidden.flipped.connect(_on_breaker_flipped)
	add_child(hidden)
	_spawn_breaker_spark_tell(hidden_pos)

	var dark_pos: Vector3 = _builder.wall_point("BreakerNook", Vector2(-1, 0), 1.1, 0.15)
	var dark := Breaker.new()
	dark.position = dark_pos
	dark.rotation.y = PI / 2.0
	# Confirmed playtest bug: emission self-illuminates regardless of scene
	# darkness, so the "pitch black" room's breaker was clearly visible the
	# whole time. This is the only breaker in the level that must not glow.
	dark.glows = false
	dark.flipped.connect(_on_breaker_flipped)
	add_child(dark)
	_spawn_dark_beacon(dark_pos)
	_spawn_breaker_nook_zone()

	# Morgue shutter: fills the CrossHall<->Morgue doorway at x=6, z=12.5.
	_morgue_shutter = CSGBox3D.new()
	_morgue_shutter.name = "MorgueShutter"
	_morgue_shutter.size = Vector3(0.3, 2.6, 1.7)
	_morgue_shutter.position = Vector3(6.0, 1.3, 12.5)
	_morgue_shutter.use_collision = true
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.25, 0.22, 0.2)
	sm.metallic = 0.7
	sm.roughness = 0.5
	# Without a texture this is a 2.6 m featureless slab filling the morgue doorway
	# — the single most conspicuous untextured surface in the level.
	if ResourceLoader.exists(TEX + "lab_morgue_shutter.png"):
		sm.albedo_texture = load(TEX + "lab_morgue_shutter.png")
		sm.albedo_color = Color(1, 1, 1)
		sm.metallic = 0.35
		# The shutter is a thin CSGBox, so the faces the player can see are the ±X
		# ones, and Godot mirrors box UVs across opposite faces — the stencilled
		# "MORTUARY" text came out backwards. The player only ever approaches from
		# the CrossHall (-x) side, since the morgue is sealed until this drops, so
		# flipping U puts the lettering the right way round where it's read.
		sm.uv1_scale = Vector3(-1, 1, 1)
	_morgue_shutter.material = sm
	add_child(_morgue_shutter)


func _on_breaker_flipped() -> void:
	_breakers_flipped += 1
	# Each throw lifts the emergency glow a little.
	for entry in _lights:
		if entry[1] > 0.0:
			entry[1] = minf(RESTORED_ENERGY, entry[1] + 0.18)
	if _breakers_flipped >= 3 and not _power_on:
		_restore_power()
	else:
		GameState.set_objective("Restore power — flip the breakers (%d/3)" % _breakers_flipped)


func _restore_power() -> void:
	_power_on = true
	for entry in _lights:
		var lamp: OmniLight3D = entry[0]
		entry[1] = RESTORED_ENERGY
		lamp.light_color = Color(0.9, 0.94, 0.9)
		var t := create_tween()
		t.tween_property(lamp, "light_energy", RESTORED_ENERGY, 0.5)
	# Open the morgue shutter (drops into the floor).
	var t2 := create_tween()
	t2.tween_property(_morgue_shutter, "position:y", -1.5, 0.9).set_trans(Tween.TRANS_QUAD)
	t2.tween_callback(func() -> void: _morgue_shutter.use_collision = false)
	_play_at("breaker_throw", Vector3(6, 1.5, 12.5), 2.0)
	GameState.set_objective("Power restored — take the keycard from the morgue")
	# The PA can only speak once the power is back, so the hint lands on a player
	# who has actually finished the breaker quest.
	_announce_trial_four()


# ---------------------------------------------------------------- the PA hint

# LEVEL 4 HINT, spoken half. Pairs with the observation-room whiteboard. The line
# names neither the wall nor the Backrooms — it describes the exit as "the surface
# that will not hold still" and is cut off by the relay before it finishes. See
# tools/make_pa_voice.py.
const PA_CAPTION := "PA: \"...the way out is the surface that will not hold still.\nThrough. Not around. Subject forty-seven is not to be—\""

func _announce_trial_four() -> void:
	# A beat after the lights settle, so it doesn't collide with the breaker clunk.
	var delay := get_tree().create_timer(1.4)
	delay.timeout.connect(func() -> void:
		if not is_instance_valid(_pa_speaker):
			return
		_pa_speaker.play()
		_show_caption(PA_CAPTION, 13.0)
	)


func _spawn_pa_speaker() -> void:
	# A tannoy horn high on the cross-hall wall, above head height so it reads as
	# building infrastructure rather than a prop you can interact with.
	var pos := Vector3(0.0, 2.55, 11.4)
	_make_prop(pos, Vector3(0.42, 0.3, 0.26), Color(0.24, 0.25, 0.23))

	_pa_speaker = AudioStreamPlayer3D.new()
	_pa_speaker.name = "PASpeaker"
	var s := GameState.load_audio("pa_trial4")
	if s:
		_pa_speaker.stream = s
	_pa_speaker.unit_size = 14.0     # carries down the corridors, as a tannoy should
	_pa_speaker.volume_db = 4.0
	_pa_speaker.position = pos
	add_child(_pa_speaker)


func _show_caption(text: String, seconds: float) -> void:
	# Subtitle for the PA, so a player with the sound down still gets the hint.
	# Deliberately NOT GameState.set_objective — that line belongs to the quest.
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.82, 0.84, 0.78))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -140.0
	label.offset_bottom = -60.0
	label.modulate.a = 0.0
	canvas.add_child(label)

	var t := create_tween()
	t.tween_property(label, "modulate:a", 0.95, 0.5)
	t.tween_interval(seconds)
	t.tween_property(label, "modulate:a", 0.0, 1.0)
	# Connect rather than await: the tween must still clean up if the node goes away.
	t.finished.connect(canvas.queue_free)


# ---------------------------------------------------------------- morgue keycard

func _spawn_morgue_keycard() -> void:
	var c: Vector3 = _builder.room_center("Morgue")  # (9.5, 0, 12.5)
	var base := Vector3(c.x, 0, c.z + 1.0)           # toward the back of the morgue

	# Cart.
	var cart := CSGBox3D.new()
	cart.size = Vector3(2.8, 0.8, 0.5)
	cart.position = base + Vector3(0, 0.4, 0)
	cart.use_collision = true
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.2, 0.21, 0.22)
	cm.metallic = 0.5
	cart.material = cm
	add_child(cart)

	# Trigger objects flanking the card, sitting ON TOP of the cart (top = 0.8),
	# instant fail on interact / 3 s gaze. The note warns: don't look at them.
	_make_trigger(base + Vector3(-0.95, 0.86, 0), Vector3(0.6, 0.12, 0.4),
		Color(0.6, 0.6, 0.62), Color(0, 0, 0),
		"tray", TEX + "lab_surgical_tray.png")                   # surgical tray
	# Sized like an actual CRT (and to the art's 4:3 aspect) rather than the old
	# 0.5 x 0.4 x 0.1 slab, which was too thin to read as a monitor at all.
	# ⚠️ The casing carries NO emission. It used to glow green so the slab was findable
	# before the art existed; now the screen quad glows at 0.85 and the casing beside it
	# read as a bright green lamp rather than as beige CRT plastic. Emission is most of
	# a surface's colour in this project (Issue 21) — once a prop has a lit face, its
	# body must go back to being an ordinary unlit object.
	#
	# BUG_FIX.md 4.2: moved off the cart onto the east wall — the wall directly facing
	# a player stepping through the morgue's only doorway (west, x=6) — so it's the
	# first thing visible entering, instead of something you find at an angle on the
	# cart. y_rot=PI/2 turns the trigger's -z-facing screen quad to face -x, into the
	# room from the east wall. The east wall carries no doorway of its own (the only
	# one is the shutter at x=6) and no other prop, so this is clear.
	_make_trigger(_builder.wall_point("Morgue", Vector2(1, 0), 1.4, 0.16),
		Vector3(0.5, 0.38, 0.34),
		Color(0.17, 0.165, 0.15), Color(0, 0, 0),
		"monitor", TEX + "lab_monitor_face.png", PI / 2.0)       # monitor with a face

	# A cursed portrait on the morgue's far wall — staring at it feeds panic.
	# ⚠️ Use wall_point rather than a hand-computed offset. The old c.z + 2.9 landed
	# exactly on the wall's inner face (the Morgue is 6 m deep, so half - 0.1), and
	# the poster was sliced apart by the drawer texture z-fighting through it.
	# wall_point now guarantees MIN_FACE_CLEAR off the face.
	_make_cursed_panel(_builder.wall_point("Morgue", Vector2(0, 1), 1.6, 0.16),
		Vector2(0.9, 1.2), PI, 0.9, TEX + "poster_lab.png")

	# The guarded keycard, between them.
	var key := StaticBody3D.new()
	key.set_script(_KEYCARD_SCRIPT)
	key.position = base + Vector3(0, 0.83, 0)
	add_child(key)
	var km := MeshInstance3D.new()
	var kb := BoxMesh.new()
	# ⚠️ Landscape, matching lab_keycard.png (1586x992 = 1.6:1) and a real ID card
	# (85.6x54 mm). This slab used to be portrait (0.1 x 0.15), which would have
	# rendered the card art rotated a quarter turn and squashed.
	kb.size = Vector3(0.16, 0.02, 0.10)
	km.mesh = kb
	var kmat := StandardMaterial3D.new()
	# Same lesson as the monitor casing: with the card art on top, this slab is only
	# the card's EDGE. At the old bright green (0.2,0.8,0.3) emitting at 0.9 it out-shone
	# the art and the card read as a green bar on the cart. Pale card stock, unlit —
	# the glow now comes from the art quad, which is the part worth looking at.
	kmat.albedo_color = Color(0.55, 0.56, 0.54)
	km.set_surface_override_material(0, kmat)
	key.add_child(km)
	# The card art rides on a top-facing quad — the card lies flat on the cart, so
	# its top is the only face the player ever sees. (A texture on the BoxMesh would
	# render a crop; see door.gd:build_visual and Issue 24.) The green emissive box
	# stays underneath as the edge and as the pre-texture fallback.
	_add_face_quad(key, Vector2(0.16, 0.10), Vector3(0, 0.013, 0),
		Vector3(-PI / 2.0, 0, 0), TEX + "lab_keycard.png", 0.7)
	var kcol := CollisionShape3D.new()
	var ks := BoxShape3D.new()
	ks.size = Vector3(0.3, 0.3, 0.6)
	kcol.shape = ks
	key.add_child(kcol)

	# The morgue is a dark zone with a beartrap near the entrance.
	var zone := DarkZone.new()
	var zcol := CollisionShape3D.new()
	var zs := BoxShape3D.new()
	zs.size = Vector3(7, 3, 6)
	zcol.shape = zs
	zone.add_child(zcol)
	zone.position = Vector3(c.x, 1.5, c.z)
	add_child(zone)

	var trap := Beartrap.new()
	trap.position = Vector3(c.x - 1.5, 0, c.z - 1.5)
	add_child(trap)


# An instant-fail trigger prop.
#
# `detail` adds the geometry that makes the thing read as the object the morgue
# note names ("Do not look at the tray. Do not look at the monitor."). Without it
# both were anonymous slabs, so the note was warning the player about two bricks:
#   "tray"    — a raised lip around the rim + a top-facing texture quad
#   "monitor" — the box becomes the bezel and an inset screen quad faces the room
# A BoxMesh takes one material across all six faces, so the artwork has to ride on
# its own quad rather than on the box.
func _make_trigger(pos: Vector3, size: Vector3, albedo: Color, emission := Color(0, 0, 0),
		detail := "", tex_path := "", y_rot := 0.0) -> void:
	var body := StaticBody3D.new()
	body.set_script(_TRIGGER_SCRIPT)
	body.position = pos
	body.rotation.y = y_rot
	add_child(body)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	if emission != Color(0, 0, 0):
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = 0.4
	mesh.set_surface_override_material(0, mat)
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	match detail:
		"tray":
			_add_tray_lip(body, size, albedo)
			_add_face_quad(body, Vector2(size.x * 0.92, size.z * 0.92),
				Vector3(0, size.y / 2.0 + 0.003, 0), Vector3(-PI / 2.0, 0, 0), tex_path)
		"monitor":
			# The art is a WHOLE CRT — bezel, stand and all — not just the glass, so
			# it gets the full face rather than an inset "screen". It also carries its
			# own glow: this is a monitor that is ON, and at 0.35 in a room lit to
			# 0.45 it just read as a dark rectangle. Still under 1.0 so it doesn't
			# clamp to white (see FIXTURE_EMISSION).
			_add_face_quad(body, Vector2(size.x, size.y),
				Vector3(0, 0, -size.z / 2.0 - 0.003), Vector3(0, PI, 0), tex_path, 0.85)


# Four thin bars around the rim so a tray reads as a tray and not as a flat plate.
func _add_tray_lip(body: Node3D, size: Vector3, albedo: Color) -> void:
	var lip := 0.03
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo.darkened(0.15)
	mat.metallic = 0.6
	mat.roughness = 0.4
	var bars := [
		[Vector3(size.x, lip, lip), Vector3(0, size.y / 2.0, size.z / 2.0)],
		[Vector3(size.x, lip, lip), Vector3(0, size.y / 2.0, -size.z / 2.0)],
		[Vector3(lip, lip, size.z), Vector3(size.x / 2.0, size.y / 2.0, 0)],
		[Vector3(lip, lip, size.z), Vector3(-size.x / 2.0, size.y / 2.0, 0)],
	]
	for entry in bars:
		var bar := MeshInstance3D.new()
		var bmesh := BoxMesh.new()
		bmesh.size = entry[0]
		bar.mesh = bmesh
		bar.set_surface_override_material(0, mat)
		bar.position = entry[1]
		body.add_child(bar)


# A textured quad sitting just proud of one face of a prop. Unshaded + emissive so
# it stays legible in a room lit at 0.45 energy — these are objects the player is
# meant to recognise before deciding not to look at them.
func _add_face_quad(body: Node3D, size: Vector2, offset: Vector3, rot: Vector3,
		tex_path: String, emission := 0.35) -> void:
	if tex_path == "" or not ResourceLoader.exists(tex_path):
		return
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	quad.mesh = qm
	var mat := StandardMaterial3D.new()
	var tex := load(tex_path)
	mat.albedo_texture = tex
	mat.emission_enabled = true
	mat.emission_texture = tex
	mat.emission_energy_multiplier = emission
	mat.roughness = 0.6
	quad.set_surface_override_material(0, mat)
	quad.position = offset
	quad.rotation = rot
	body.add_child(quad)


# A gaze-panic panel: ScaryObject (ancestor) -> StaticBody (world transform) ->
# textured quad + collider. Staring at it fills the panic bar.
func _make_cursed_panel(pos: Vector3, size: Vector2, y_rot: float, intensity: float,
		tex_path: String) -> void:
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
		mat.albedo_color = Color(0.12, 0.06, 0.06)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.04, 0.04)
		mat.emission_energy_multiplier = 0.4
	mat.roughness = 0.9
	quad.set_surface_override_material(0, mat)
	body.add_child(quad)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y, 0.1)
	col.shape = shape
	body.add_child(col)


# ---------------------------------------------------------------- room props

# A solid CSG prop (no panic), so each room reads as a place, not an empty box.
#
# `tex_path` is optional and guarded the same way _make_cursed_panel does it, so a
# prop keeps its flat-colour look until art for it exists. The colour is retained
# as an albedo multiplier rather than being discarded, which keeps a textured prop
# sitting in the same tonal range as its untextured neighbours.
func _make_prop(pos: Vector3, size: Vector3, color: Color, y_rot := 0.0,
		tex_path := "") -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.rotation.y = y_rot
	b.use_collision = true
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.3
	m.roughness = 0.7
	if tex_path != "" and ResourceLoader.exists(tex_path):
		m.albedo_texture = load(tex_path)
		m.albedo_color = Color(1, 1, 1)
		m.metallic = 0.0
	b.material = m
	add_child(b)
	return b


func _accent_lamp(pos: Vector3, color: Color, energy: float, lrange := 6.0) -> void:
	var lamp := OmniLight3D.new()
	lamp.position = pos
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = lrange
	add_child(lamp)


func _spawn_room_props() -> void:
	# Exam rooms: a surgical table each.
	for room in ["Exam1", "Exam2"]:
		var c: Vector3 = _builder.room_center(room)
		_make_prop(Vector3(c.x, 0.45, c.z), Vector3(0.9, 0.9, 2.0), Color(0.6, 0.62, 0.64))
	# Records: a bank of filing cabinets along the back wall + a warning sign.
	var rc: Vector3 = _builder.room_center("Records")
	for i in range(3):
		_make_prop(Vector3(rc.x - 2.0 + i * 0.8, 0.65, rc.z - 2.4),
			Vector3(0.7, 1.3, 0.6), Color(0.28, 0.3, 0.27))
	# Warning sign, on the NORTH wall (moved off the west wall alongside the note
	# above — west now carries the BreakerNook doorway, new feature).
	# Same burial bug as the whiteboard: at inset 0.06 this sign was inside the wall
	# and had never actually been visible in game.
	_make_cursed_panel(_builder.wall_point("Records", Vector2(0, 1), 1.8, 0.16),
		Vector2(0.8, 0.6), PI, 0.0, TEX + "lab_warning_sign.png")
	_accent_lamp(Vector3(rc.x, 1.9, rc.z), Color(0.7, 0.85, 0.6), 0.5)
	# Observation: a monitoring desk in front of the one-way mirror (east wall), with a
	# screen glow — kept clear of the west (x=1.5) doorway.
	var oc: Vector3 = _builder.room_center("Observation")
	_make_prop(Vector3(oc.x + 1.0, 0.5, oc.z), Vector3(1.6, 1.0, 0.7), Color(0.22, 0.23, 0.25))
	_accent_lamp(Vector3(oc.x + 1.0, 1.3, oc.z), Color(0.4, 0.7, 0.9), 0.4, 3.5)

	# LEVEL 4 HINT — the researchers' whiteboard. A flow diagram of the Backrooms
	# trial whose final node is a hatched WALL with an arrow driven through it, and
	# a half-wiped "NO DOOR" in the margin. intensity 0.0 = decorative, no gaze panic;
	# the board should reward a careful player, not punish them for reading it.
	# NORTH wall: Observation's only doorway is west (1.5, 17), and a panel there
	# carries a collider that would seal the room (the Session-11 bug class).
	# ⚠️ inset must exceed RoomBuilder's HALF wall thickness (T=0.2, so >0.1) —
	# wall_point() measures from the room's nominal boundary, not the wall's inner
	# face, so the usual 0.06 buries the panel inside the wall and it renders as
	# nothing at all. 0.16 leaves it sitting 0.06 proud.
	_make_cursed_panel(_builder.wall_point("Observation", Vector2(0, 1), 1.7, 0.16),
		Vector2(2.0, 1.25), PI, 0.0, TEX + "lab_whiteboard.png")
	_accent_lamp(Vector3(oc.x, 2.2, oc.z + 1.6), Color(0.85, 0.88, 0.8), 0.5, 4.0)


# ---------------------------------------------------------------- observation

func _spawn_observation_mirror() -> void:
	# One-way mirror on the far wall of the observation room — a figure stands in
	# the glass when you are not looking straight at it.
	# ⚠️ Inset 0.22, not the usual 0.16. LivingMirror hangs its figure 0.05 BEHIND
	# the glass (it is supposed to appear inside the mirror), so the glass needs
	# clearance for the figure too — at inset 0.1 the glass sat on the wall face and
	# the figure was 0.05 INSIDE the wall, occluded by it. The one-way mirror's
	# figure could never have been visible here. Asserted by check_wall_overlap.gd.
	var pos: Vector3 = _builder.wall_point("Observation", Vector2(1, 0), 1.5, 0.22)
	var mirror := LivingMirror.new()
	mirror.position = pos
	mirror.rotation.y = -PI / 2.0  # face back into the room (-x)
	add_child(mirror)


# ---------------------------------------------------------------- doors

func _spawn_doors() -> void:
	# Exit door at the north wall of the vestibule (needs the keycard).
	var exit := _make_door("ExitDoor", true, false)
	exit.unlock_condition = _DOOR_SCRIPT.UnlockCondition.KEYCARD
	exit.position = Vector3(0, 1.225, 21.85)
	exit.rotation.y = PI

	# Back door at the south wall of reception.
	var back := _make_door("BackDoor", false, true)
	back.position = Vector3(0, 1.225, -2.85)


func _make_door(door_name: String, advances: bool, goes_back: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = door_name
	body.set_script(_DOOR_SCRIPT)
	body.advances_level = advances
	body.goes_back = goes_back
	add_child(body)

	_DOOR_SCRIPT.build_visual(body, Vector3(1.25, 2.45, 0.15), TEX + "lab_door.png")

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.25, 2.45, 0.2)
	col.shape = shape
	col.position.y = 0.0
	body.add_child(col)
	return body


# ---------------------------------------------------------------- apparition

func _spawn_apparition() -> void:
	# A taught "hold your nerve" apparition, armed when the player first steps into
	# the main corridor. teach=true: even a panicked sprint only shocks, not kills.
	_apparition = Apparition.spawn(self, Apparition.Rule.HOLD, Vector3.ZERO, true) as Apparition
	_spawn_event(Vector3(0, 1.5, 6.0), Vector3(3, 3, 1.5), _trigger_apparition)


func _trigger_apparition() -> void:
	if _apparition_fired or not _apparition:
		return
	_apparition_fired = true
	_apparition.appear()


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


# ---------------------------------------------------------------- ambience / ticks

# Lift this scene's ambient light so textures read a few metres out (corners stay
# dark). environment.tscn's Environment resource is SHARED across every level, so we
# DUPLICATE it first — mutating it in place would bleed into the corridor/void.
func _boost_ambient(energy: float) -> void:
	var we: WorldEnvironment = get_node_or_null("Environment/WorldEnvironment")
	if not we or not we.environment:
		return
	var env: Environment = we.environment.duplicate()
	env.ambient_light_energy = energy
	env.ambient_light_color = Color(0.1, 0.11, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Black background instead of the procedural sky, so any geometry gap reads as
	# darkness rather than blue sky (see level_2.gd cellar).
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	we.environment = env


func _start_ambience() -> void:
	var ambient: AudioStreamPlayer = get_node_or_null("AmbientPlayer")
	if ambient:
		var s := GameState.load_audio("ambient_lab")
		if s:
			ambient.stream = s
		if ambient.stream:
			ambient.finished.connect(ambient.play)
			ambient.play()


func _process(delta: float) -> void:
	_tick_blackout(delta)
	_tick_pipes(delta)
	_drive_lights(delta)
	_tick_debug_apparition(delta)
	_tick_breaker_spark(delta)
	_tick_dark_breaker_tell(delta)


func _tick_debug_apparition(delta: float) -> void:
	if not DEBUG_APPARITION:
		return
	# A player who can't see the apparition materialise has no fair way to judge
	# "hold still or flee" — the same double-jeopardy mistake this project has
	# already made twice (KONTUR Gate 7, Backrooms Flood: never stack an
	# unmitigated extra threat on a room whose whole premise is "solve it blind").
	if _in_breaker_nook:
		return
	_dbg_appar_timer -= delta
	if _dbg_appar_timer > 0.0:
		return
	_dbg_appar_timer = DEBUG_APPAR_INTERVAL
	# A fresh FATAL apparition each cycle (teach=false): hold still and it fades, but
	# sprint or back away and it rushes → the real screamer + restart. The scripted
	# first encounter below stays taught/survivable so the rule is learned first.
	var a := Apparition.spawn(self, Apparition.Rule.HOLD, Vector3.ZERO, false) as Apparition
	if a:
		a.appear()


func _tick_blackout(delta: float) -> void:
	_blackout_timer = maxf(0.0, _blackout_timer - delta)
	_scheduled_blackout -= delta
	if _scheduled_blackout <= 0.0:
		_scheduled_blackout = randf_range(BLACKOUT_MIN, BLACKOUT_MAX)
		_blackout_timer = 1.5
		_play_at("creak", _random_room_point(2.4), 2.0)
		var p := _player()
		if p:
			p.add_panic(4.0)


func _tick_pipes(delta: float) -> void:
	_pipe_timer -= delta
	if _pipe_timer <= 0.0:
		_pipe_timer = randf_range(PIPE_MIN, PIPE_MAX)
		_play_at("pipe_groan", _random_room_point(1.6), 0.0)


# A small, off-by-default light beside the hidden Records breaker. _tick_breaker_spark
# flicks it on and plays a crackle every 8-12s — the audio/visual tell that finds it
# without the room needing to spotlight it (BUG_FIX.md 4.1).
func _spawn_breaker_spark_tell(pos: Vector3) -> void:
	_breaker_spark_pos = pos
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0.15, 0.1, 0.0)
	light.light_color = Color(0.75, 0.85, 1.0)
	light.light_energy = 0.0
	light.omni_range = 2.5
	add_child(light)
	_breaker_spark_light = light


func _tick_breaker_spark(delta: float) -> void:
	_breaker_spark_timer -= delta
	if _breaker_spark_timer > 0.0:
		return
	_breaker_spark_timer = randf_range(BREAKER_SPARK_MIN, BREAKER_SPARK_MAX)
	_play_at("breaker_spark", _breaker_spark_pos, -2.0)
	if not is_instance_valid(_breaker_spark_light):
		return
	var tw := create_tween()
	tw.tween_property(_breaker_spark_light, "light_energy", 1.4, 0.03)
	tw.tween_property(_breaker_spark_light, "light_energy", 0.0, 0.05)
	tw.tween_property(_breaker_spark_light, "light_energy", 0.9, 0.03)
	tw.tween_property(_breaker_spark_light, "light_energy", 0.0, 0.12)


# BreakerNook's tell: sound only — there's nothing to flicker in total darkness,
# unlike the Records breaker's light-and-sound version above.
#
# ⚠️ This used to be a one-line stub that recorded a position and spawned NOTHING.
# The entire "navigate by ear" mechanic was _tick_dark_breaker_tell() firing a
# 0.45 s non-looping transient every 8-12 s through the generic _play_at() helper:
# a ~4% duty cycle, unit_size 8, no max_distance, no attenuation model. You cannot
# steer by that, which is exactly why the on-screen proximity meter ended up doing
# all the work and the wing played as trivial (playtest capture #2).
#
# Replaced with a CONTINUOUS two-layer positional beacon, lifted from
# backrooms_zone2.gd:186-227 — whose own header comment is a post-mortem of this
# identical mistake ("audible only once you were basically already at the correct
# wall ... two layers now, both MUCH wider range so there's something to actually
# walk toward"). Both layers sit AT the breaker:
#
#   far cue  (unit_size 16) — carries the length of the wing; this is the thing you
#                             turn your head to locate at a junction.
#   near confirm (unit_size 9) — only resolves in the last room or two; this is what
#                             says "right branch" rather than "right direction".
#
# Two layers matter because one gives you a bearing but never a distance: with a
# single source, "quiet" is ambiguous between far-away-and-correct and
# nearby-through-a-wall. The pair disambiguates, which is what makes the maze
# solvable without a HUD readout.
#
# Looped via finished->play: every .wav.import in this project is loop_mode=0
# except fluorescent_hum, so the node has to restart itself.
const BEACON_FAR_UNIT := 16.0
const BEACON_NEAR_UNIT := 9.0

func _spawn_dark_beacon(pos: Vector3) -> void:
	_dark_breaker_pos = pos
	_add_beacon_layer("breaker_hum", pos, BEACON_FAR_UNIT, -3.0)
	_add_beacon_layer("breaker_buzz", pos, BEACON_NEAR_UNIT, -1.0)


func _add_beacon_layer(base_name: String, pos: Vector3, unit: float, vol: float) -> void:
	var stream := GameState.load_audio(base_name)
	if not stream:
		return
	var pl := AudioStreamPlayer3D.new()
	pl.name = "Beacon_" + base_name
	pl.stream = stream
	pl.unit_size = unit
	pl.volume_db = vol
	pl.max_db = 3.0
	add_child(pl)
	pl.position = pos
	pl.finished.connect(pl.play)
	pl.play()


# The old spark transient stays on top of the beacon as flavour — an occasional
# arc pop over a steady hum reads as failing equipment rather than as a locator
# tone. It is no longer load-bearing for navigation.
func _tick_dark_breaker_tell(delta: float) -> void:
	_dark_breaker_timer -= delta
	if _dark_breaker_timer > 0.0:
		return
	_dark_breaker_timer = randf_range(BREAKER_SPARK_MIN, BREAKER_SPARK_MAX)
	_play_at("breaker_spark", _dark_breaker_pos, -2.0)


# Flashlight lock/unlock for the DarkCorridor+BreakerNook pair, symmetric on
# entry AND exit — leaving without finding the breaker always restores the light
# immediately. No DarkZone (would double-tax the exact posture the room's premise
# requires — Issue 18); no kill_flashlight() (permanent, wrong tool for a room you
# can walk back out of).
#
# ONE zone spanning the whole wing's combined bounds, not separate ones per room —
# adjacent Area3Ds would false-unlock the instant you cross from one into the
# next (body_exited fires on the first zone before body_entered fires on the
# second), the same class of bug player.gd's own DarkZone counter exists to
# avoid. This is why the zone is a single hand-computed AABB rather than one box
# per room, and why it MUST be re-derived whenever the wing's ROOMS change.
#
# Union of all ten wing rooms: x -37 (BreakerNook west) .. -12 (Records' wall),
# z 4.2 (PumpRoom south) .. 24 (NorthVault north) -> size (25, h, 19.8) centred
# at (-24.5, 14.1). Records itself starts at x=-12, so the wing's east edge is
# exactly the doorway the player steps through.
func _spawn_breaker_nook_zone() -> void:
	var h: float = _builder.room_height("BreakerNook")
	var zone := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(25.0, h, 19.8)
	col.shape = shape
	zone.add_child(col)
	zone.position = Vector3(-24.5, h / 2.0, 14.1)
	add_child(zone)
	zone.body_entered.connect(func(b: Node3D) -> void:
		if b.is_in_group("player"):
			_in_breaker_nook = true
			var p := b as CharacterBody3D
			if p and p.has_method("lock_flashlight"):
				p.lock_flashlight()
	)
	zone.body_exited.connect(func(b: Node3D) -> void:
		if b.is_in_group("player"):
			_in_breaker_nook = false
			var p := b as CharacterBody3D
			if p and p.has_method("unlock_flashlight"):
				p.unlock_flashlight()
	)


func _drive_lights(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for entry in _lights:
		var lamp: OmniLight3D = entry[0]
		var base: float = entry[1]
		if _blackout_timer > 0.0:
			lamp.light_energy = base * (0.04 + maxf(0.0, sin(t * 37.0) * sin(t * 8.1)) * 0.15)
		else:
			lamp.light_energy = base * (1.0 + sin(t * 11.3 + lamp.position.x) * 0.06)
		# Keep the visible fitting in step with the light it stands for.
		if entry.size() > 2 and entry[2] != null:
			var fixture: StandardMaterial3D = entry[2]
			var ratio: float = lamp.light_energy / base if base > 0.0 else 0.0
			fixture.emission_energy_multiplier = FIXTURE_EMISSION * ratio


func _random_room_point(y: float) -> Vector3:
	var r: Dictionary = ROOMS[randi() % ROOMS.size()]
	var c: Vector3 = _builder.room_center(r["name"])
	return Vector3(c.x, y, c.z)


# Keycard pickup feedback (called by keycard.gd via current_scene).
func on_keycard_taken() -> void:
	_blackout_timer = BLACKOUT_DURATION
	_play_at("creak", _player().global_position if _player() else Vector3.ZERO, 2.0)
	var p := _player()
	if p and p.has_method("add_panic"):
		p.add_panic(KEYCARD_PANIC)
	GameState.set_objective("Keycard taken — reach the exit door")


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
