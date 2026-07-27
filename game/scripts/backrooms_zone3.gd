extends Node3D
class_name BackroomsZone3

# ZONE 3 — THE FLOOD.
#
# The last inversion. Five levels have taught the player that the flashlight is
# safety; here the exit seam is only visible with it OFF. Two decoy seams glow only
# while the light is ON — the exact inverse — so the instinct to light the room up
# doesn't just fail, it actively misleads.
#
# ⚠️ There is NO DarkZone here, despite what this header said for a long time. One was
# removed deliberately: a room solved by turning the flashlight off must not also tax
# the flashlight being off (+3/s AND decay suppressed). That is ISSUES_SOLUTIONS
# Issue 18, which this project has now made twice.
#
# Built on RoomBuilder rather than raw boxes: it de-dupes shared walls and bridges
# the floor under every doorway, which is the whole reason the Issue-5 void-fall
# class can't come back.

signal cleared
signal mistake

const WATER_Y := 0.12
const ROOM_H := 3.2
const WADE_SLOW := 0.6             # refreshed every frame while submerged

# A DreadZone's decay (2.0) and pressure (2.0) cancel EXACTLY, so dread alone leaves
# the bar frozen — no threat at all in the level's finale. This is the zone's own
# slow drip on top, the way CreatureSmiler drives its own curve. Deliberately small:
# from the 35% entry cap it allows roughly a minute of searching, which is about one
# unhurried sweep of the wing, and the dry platform's CalmZone still nets negative so
# there is somewhere to recover. Pressure everywhere, exactly one island.
# 0.5 left ~65 s, but playtest showed a first-time player needs ~90-120 s to sweep
# the wing and find the Sump. 0.3 gives ~125 s from the entry cap.
const DREAD_DRIP := 0.3            # panic per second, flashlight-independent

var spawn_point: Vector3

var _origin: Vector3
var _builder: RoomBuilder
var _player: Node3D
var _real_seam: GlitchWall
var _decoys: Array[GlitchWall] = []
var _drip_timer: float = 0.0

# An 8-room flooded wing. Deliberately branching: the seam is in Sump, off the
# main line, so the player has to explore in the dark rather than walk straight on.
const ROOMS := [
	{ "name": "Landing",  "pos": Vector2(0, 0),     "size": Vector2(6, 6) },
	{ "name": "Descent",  "pos": Vector2(0, 7),     "size": Vector2(4, 8) },
	{ "name": "Basin",    "pos": Vector2(0, 15),    "size": Vector2(12, 8) },
	{ "name": "EastRun",  "pos": Vector2(9, 15),    "size": Vector2(6, 4) },
	{ "name": "WestRun",  "pos": Vector2(-9, 15),   "size": Vector2(6, 4) },
	{ "name": "Sump",     "pos": Vector2(-9, 21),   "size": Vector2(8, 8) },
	{ "name": "Cistern",  "pos": Vector2(9, 21),    "size": Vector2(8, 8) },
	{ "name": "Throat",   "pos": Vector2(0, 23),    "size": Vector2(4, 8) },
]

const DOORS := [
	{ "pos": Vector2(0, 3),    "width": 2.0, "dir": "z" },
	{ "pos": Vector2(0, 11),   "width": 2.4, "dir": "z" },
	{ "pos": Vector2(6, 15),   "width": 2.0, "dir": "x" },
	{ "pos": Vector2(-6, 15),  "width": 2.0, "dir": "x" },
	{ "pos": Vector2(-9, 17),  "width": 2.2, "dir": "z" },
	{ "pos": Vector2(9, 17),   "width": 2.2, "dir": "z" },
	{ "pos": Vector2(0, 19),   "width": 2.0, "dir": "z" },
]


func build(origin: Vector3, player: Node3D) -> void:
	_origin = origin
	_player = player
	position = origin
	spawn_point = origin + Vector3(0, 0.1, -2.0)

	_build_rooms()
	_build_water()
	_build_water_audio()
	_build_digit_notes()
	_build_seams()
	_build_pressure()
	set_process(true)


func _build_rooms() -> void:
	_builder = RoomBuilder.new()
	_builder.wall_height = ROOM_H
	# Wet concrete rather than wallpaper — this has to read as somewhere else.
	_builder.wall_mat = MazeKit.make_material(
		"res://assets/textures/level_2_house/house_basement_concrete.png",
		Vector2(1.0, 1.0 / 3.0), Color(0.20, 0.21, 0.20))
	_builder.floor_mat = MazeKit.make_material(
		"res://assets/textures/level_1_lab/lab_floor_wet.png",
		Vector2(0.5, 0.5), Color(0.13, 0.14, 0.14))
	_builder.ceil_mat = MazeKit.make_material("", Vector2.ONE, Color(0.10, 0.10, 0.11))
	add_child(_builder)
	_builder.build(ROOMS, DOORS)


func _build_water() -> void:
	# One translucent sheet over the whole footprint. No collider — the wade is a
	# speed penalty applied in _process, not physics.
	var water := MeshInstance3D.new()
	water.name = "Floodwater"
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	water.mesh = pm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.06, 0.09, 0.10, 0.72)
	m.roughness = 0.10
	m.metallic = 0.35
	water.set_surface_override_material(0, m)
	water.position = Vector3(0, WATER_Y, 14.0)
	add_child(water)


# BACKLOG #20: "in the backrooms when you are at the water stage there is no water
# sound. Make it look more realistic like it is indeed the water."
#
# It was right: this zone had NO continuous audio of any kind. The only sound was a
# `water_drip` one-shot every 3-8 s — and that name resolves to the HOUSE CELLAR's
# drip (level_2_house/water_drip.wav), a lone plink in an empty room, which is the
# opposite of standing in it.
#
# Four looping emitters rather than one: AudioStreamPlayer3D attenuates with distance,
# and this wing is ~28 m end to end, so a single source at the centre fades out in the
# rooms furthest from it — the Sump and the Cistern, which is exactly where the player
# spends longest. Placed at the room centres of the four largest chambers so coverage
# is continuous while every position still has a nearest source, which keeps it
# directional rather than a flat wall of noise.
const WATER_BED_ROOMS := ["Basin", "Cistern", "Sump", "Throat"]
const WATER_BED_UNIT := 13.0
const WATER_BED_DB := -6.0

var _water_beds: Array[AudioStreamPlayer3D] = []


func _build_water_audio() -> void:
	var stream := GameState.load_audio("water")
	if not stream:
		return
	for room in WATER_BED_ROOMS:
		var c: Vector3 = _builder.room_center(room)
		var a := AudioStreamPlayer3D.new()
		a.name = "WaterBed_" + room
		a.stream = stream
		a.volume_db = WATER_BED_DB
		a.unit_size = WATER_BED_UNIT
		a.max_db = 0.0
		add_child(a)
		a.position = Vector3(c.x, WATER_Y + 0.2, c.z)
		# ⚠️ Every .wav.import in this project is loop_mode=0, so the node has to
		# restart itself. Canonical form, lifted from level_1.gd:_add_beacon_layer().
		a.finished.connect(a.play)
		a.play()
		_water_beds.append(a)


# Mirror of the above. ⚠️ DISCONNECT BEFORE STOP: `finished` is wired to `play`, so
# stopping a still-connected player makes it emit `finished` and immediately restart
# itself. level_1.gd learned this the hard way with the breaker beacons.
func _free_water_audio() -> void:
	for a in _water_beds:
		if is_instance_valid(a):
			if a.finished.is_connected(a.play):
				a.finished.disconnect(a.play)
			a.stop()
			a.queue_free()
	_water_beds.clear()


func _exit_tree() -> void:
	_free_water_audio()


# BACKLOG #24: KONTUR's roster gate used to answer to "47", which the player already
# knew from the intro note ("You are Subject 47") — so a gate designed to be the one
# whose answer is carried from the first minute of the game was, in practice, the one
# gate nobody had to look for. The code is now KONTUR's own ROSTER_CODE with no other
# source anywhere in the game, and both digits are written down HERE, in the Flood, in
# the same shape the House uses for its lock: one digit per note, deliberately split.
#
# Placement is the point. Both notes are in the SIDE RUNS — the short east/west
# corridors off the Basin — not on the route from the Descent to the Sump. A player who
# walks the main line and takes the seam never sees either. That is the intent (this
# level is entered before KONTUR, and the whole design of KONTUR is "the answers are
# not inside it"), and it is why the notes journal exists: a player who read them in
# passing can re-read them at the lock instead of walking two levels back.
#
# ⚠️ Both walls are chosen for having NO doorway. EastRun (x 6..12, z 13..17) is
# entered from its west wall and its north wall; WestRun (x -12..-6, z 13..17) from its
# east and north. So the free faces are the outer ones. wall_point() returns the wall
# CENTRE, which is exactly where a doorway sits — hanging a prop on a wall that has one
# silently seals the room (the Records warning-sign bug, CLAUDE.md).
const _NOTE_SCRIPT := preload("res://scripts/note.gd")

const DIGIT_NOTE_A := """KONTUR — INTERNAL. DO NOT COPY.

The personnel gate on sub-level 2 wants the subject number. I keep forgetting it, so I
am writing it where the water will not reach.

The FIRST digit is 6.

I have put the second one on the far side. If they find one of these they still do not
get in."""

const DIGIT_NOTE_B := """...and the SECOND digit is 3.

If you are holding both halves then you have been down here longer than I managed. The
gate is past the kitchen, in records. It does not open twice.

— Ops"""


func _build_digit_notes() -> void:
	# EastRun's east face and WestRun's west face — the two outer walls, both
	# doorway-free. Inset 0.22: wall_point() measures from the room's NOMINAL boundary
	# and the wall's inner face is T/2 (0.1) inside that, so 0.22 leaves ~12 cm of
	# clearance (Issue 26 — at 0.10 a wall prop is exactly coplanar and gets sliced).
	_make_note("DigitNote_WestRun",
		_builder.wall_point("WestRun", Vector2(-1, 0), 1.4, 0.22), PI / 2.0, DIGIT_NOTE_A)
	_make_note("DigitNote_EastRun",
		_builder.wall_point("EastRun", Vector2(1, 0), 1.4, 0.22), -PI / 2.0, DIGIT_NOTE_B)


func _make_note(note_name: String, pos: Vector3, y_rot: float, text: String) -> void:
	var note := StaticBody3D.new()
	note.name = note_name    # findable, and legible in a failing assertion (Issue 17)
	note.set_script(_NOTE_SCRIPT)
	note.note_text = text
	note.is_trap = false
	note.position = pos
	note.rotation.y = y_rot
	add_child(note)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.32, 0.42, 0.01)
	mesh.mesh = bm
	mesh.set_surface_override_material(0, _NOTE_SCRIPT.paper_material(false))
	note.add_child(mesh)
	# Faintly lit. Every other note in the game sits in a room with a lamp; this wing
	# is near-black by design and a wholly unlit page on a dark wall is not "hidden",
	# it is absent. Kept low (Issue 21: emission is most of a surface's colour here).
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.85, 0.85, 0.78)
	glow.light_energy = 0.22
	glow.omni_range = 1.8
	note.add_child(glow)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 0.5, 0.12)
	col.shape = shape
	note.add_child(col)


func _build_seams() -> void:
	# ⚠️ ORIENTATION. GlitchWall puts its walk-into trigger at local -Z. These seams sit
	# on their room's NORTH wall, so the player approaches from -Z and the trigger must
	# stay at -Z: yaw ZERO. A PI yaw (which reads as "turn it to face the room") pushes
	# the trigger to +Z, straight through the wall behind it — the seam then renders
	# perfectly and can never be touched. That shipped, and it made the Flood
	# unwinnable: the only reachable trigger in the zone was a decoy.
	# Same convention as backrooms_zone2.gd: rotation.y = atan2(axis.x, axis.z) with
	# `axis` pointing OUTWARD from the room, which is 0 for a north wall.
	const NORTH_YAW := 0.0

	# The real seam, hidden off the main line in the Sump.
	var c: Vector3 = _builder.room_center("Sump")
	_real_seam = GlitchWall.new()
	_real_seam.name = "FloodSeam"
	add_child(_real_seam)
	_real_seam.setup(Vector2(3.6, 2.6), 2.6, true)
	_real_seam.position = Vector3(c.x, 1.35, c.z + 3.85)
	_real_seam.rotation.y = NORTH_YAW
	_real_seam.touched.connect(_on_seam_touched)

	# Two decoys, lit by the inverse rule.
	#
	# The Basin decoy is offset +4 m in x rather than centred: the Basin's north wall
	# carries the Throat doorway at x=0, and a 3.6 m-wide trigger centred there means
	# walking into the Throat at all is scored as a wrong answer, before the player has
	# chosen anything. Wrong guesses should cost; walking down a corridor shouldn't.
	for spec in [["Cistern", 0.0], ["Basin", 4.0]]:
		var rc: Vector3 = _builder.room_center(spec[0])
		var d := GlitchWall.new()
		d.name = "Decoy" + str(spec[0])
		add_child(d)
		d.setup(Vector2(3.6, 2.6), 2.6, false)
		d.position = Vector3(rc.x + float(spec[1]), 1.35, rc.z + 3.85)
		d.rotation.y = NORTH_YAW
		d.touched.connect(_on_seam_touched)
		_decoys.append(d)


func _on_seam_touched(is_real: bool) -> void:
	if is_real:
		cleared.emit()
	else:
		mistake.emit()


func _build_pressure() -> void:
	# Dread only — NO blanket DarkZone.
	#
	# This zone's puzzle requires the flashlight OFF to see the exit seam. A DarkZone
	# charges +3/s for exactly that, and because player.gd's panic resolution is an
	# if/elif chain, the dark branch also SUPPRESSES decay entirely: light off was
	# +5/s with no way down, light on was a frozen bar and an invisible exit. The
	# puzzle and the panic system were fighting each other and the puzzle lost —
	# three playtest deaths inside 10 s, without the mechanic ever being attempted.
	#
	# Dread alone still means no decay and a steady climb, so the room is on a timer;
	# it just no longer punishes the one thing it asks you to do.
	var centre := Vector3(0, ROOM_H / 2.0, 14.0)
	var extent := Vector3(40, ROOM_H, 40)
	MazeKit.zone_box(self, DreadZone.new(), centre, extent, "FloodDread")

	# The one dry place in the level: a raised platform in the Basin with a lamp.
	# Recovery has to exist somewhere or the three-zone run is unsurvivable.
	var bc: Vector3 = _builder.room_center("Basin")
	MazeKit.box(self, "DryPlatform", Vector3(bc.x, 0.22, bc.z),
		Vector3(3.4, 0.44, 3.4),
		MazeKit.make_material("", Vector2.ONE, Color(0.26, 0.25, 0.22)))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.6)
	lamp.light_energy = 1.5
	lamp.omni_range = 7.0
	lamp.position = Vector3(bc.x, 2.2, bc.z)
	add_child(lamp)
	MazeKit.zone_box(self, CalmZone.new(), Vector3(bc.x, 1.2, bc.z),
		Vector3(4.5, 2.4, 4.5), "FloodCalm")

	# ONE beartrap, under the water, in the CISTERN only.
	#
	# There were three, in EastRun/WestRun/Cistern — but EastRun and WestRun are the
	# only corridors to the Sump, so the required route was mined with invisible
	# traps (15 panic each, unrecoverable in a no-decay zone). Both playtest deaths
	# were beartraps on that forced path. A trap the player cannot see, avoid, or
	# recover from is a toll, not a challenge.
	#
	# The Cistern holds a DECOY seam, so it is optional exploration — a trap there
	# punishes chasing the wrong answer, which is a choice the player actually made.
	var cist: Vector3 = _builder.room_center("Cistern")
	var trap := Beartrap.new()
	trap.position = Vector3(cist.x + randf_range(-1.5, 1.5), 0,
		cist.z + randf_range(-1.5, 1.5))
	add_child(trap)

	# A HOLD apparition in the Throat. Fatal by now — the rule was taught in the Lab —
	# but armed through ApparitionDirector.arm(), whose global ledger keeps it
	# survivable in the rare case this is the player's first one.
	var tc: Vector3 = _builder.room_center("Throat")
	var appar := Apparition.spawn(self, Apparition.Rule.HOLD,
		Vector3(tc.x, 0, tc.z), false)
	var trigger := CorridorEvent.new()
	MazeKit.zone_box(self, trigger, Vector3(tc.x, 1.2, tc.z - 3.0),
		Vector3(4.0, 2.4, 1.2), "ThroatEvent")
	trigger.fired.connect(func() -> void:
		if is_instance_valid(appar):
			ApparitionDirector.arm(appar as Apparition)
	)

	# BUG_FIX.md 4.4: a second one in the Sump — the deepest, most remote room (it
	# also holds the real seam), reached only via WestRun. Playtest read the Flood as
	# "nice vibe, not packed enough with action" despite the Throat encounter above,
	# so this doubles the count rather than replacing it. Same non-teach HOLD pattern,
	# verbatim, just relocated; entered from the north (the only doorway into Sump),
	# so the trigger sits 3 m north of centre, just past that threshold.
	var suc: Vector3 = _builder.room_center("Sump")
	var sump_appar := Apparition.spawn(self, Apparition.Rule.HOLD,
		Vector3(suc.x, 0, suc.z), false)
	var sump_trigger := CorridorEvent.new()
	MazeKit.zone_box(self, sump_trigger, Vector3(suc.x, 1.2, suc.z - 3.0),
		Vector3(4.0, 2.4, 1.2), "SumpEvent")
	sump_trigger.fired.connect(func() -> void:
		if is_instance_valid(sump_appar):
			ApparitionDirector.arm(sump_appar as Apparition)
	)


func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	# THE TELL. Seam visibility is inverted against the flashlight: the real one
	# shows in darkness, the decoys show in light. `is_flashlight_on()` returns
	# false for a dead battery too, so a player who burned the light through zones
	# 1 and 2 can still finish — the rule is "not lit", not "toggled off".
	var lit: bool = _player.is_flashlight_on()
	if is_instance_valid(_real_seam):
		_real_seam.set_seam_visible(not lit)
	for d in _decoys:
		if is_instance_valid(d):
			d.set_seam_visible(lit)

	# Wading: refresh the slow every frame while inside the flooded footprint, so
	# it lapses naturally the moment the zone is left.
	var p: Vector3 = _player.global_position
	var local: Vector3 = p - _origin
	var submerged: bool = local.z > -4.0 and local.z < 30.0 \
		and absf(local.x) < 20.0 and p.y < _origin.y + 1.5
	if submerged:
		_player.apply_slow(WADE_SLOW)
		_player.add_panic(DREAD_DRIP * delta)

	# Drips on top of the bed, for texture. ⚠️ `local` is player-minus-origin, but this
	# node is ALREADY at `origin`, so a child placed at `local` lands at origin+local —
	# i.e. near the player, which is what was wanted, but only by accident of the two
	# errors cancelling. Stated plainly now: place it relative to the player IN LOCAL
	# SPACE, which is what a child of this node needs.
	_drip_timer -= delta
	if _drip_timer <= 0.0:
		_drip_timer = randf_range(3.0, 8.0)
		var near_player := Vector3(local.x + randf_range(-6, 6), 2.0, local.z + randf_range(-6, 6))
		_play("water_drip", near_player, -4.0)


func _play(base_name: String, pos: Vector3, volume_db: float) -> void:
	var stream := GameState.load_audio(base_name)
	if not stream:
		return
	var a := AudioStreamPlayer3D.new()
	a.stream = stream
	a.volume_db = volume_db
	a.unit_size = 7.0
	add_child(a)
	a.position = pos
	a.finished.connect(a.queue_free)
	a.play()
