extends Node3D
class_name BackroomsZone2

# ZONE 2 — THE SPRAWL.
#
# Zone 1 taught the verb (walk into the wall). This zone makes you find the right
# wall. Four glitch walls tear identically on the four sides of a big pillar hall;
# only one is real, and the tell is not visual — near the real one the ambient bed
# fades to nothing. You listen your way out. Touch a fake and it goes solid, costs
# `backrooms.gd:WRONG_WALL_PANIC` (12, not the 18 this comment claimed until
# 2026-07-27), and the real wall re-randomises, so brute force is a losing line.
#
# The scale is the other half of the horror. Zone 1 is 3 m corridors; this is a
# 40 m room with a 4.5 m ceiling and nothing to orient by — the pillars are
# identical and so are the alcoves. Open space here is worse than being enclosed.

signal cleared                     # the real wall was walked through
signal mistake                     # a fake was touched (the level owns the penalty)

const SIZE := 40.0                 # hall is SIZE x SIZE
const HALF := SIZE / 2.0
const HEIGHT := 4.5                # deliberately wrong-scale vs zone 1's 3.0
const T := 0.3
const PILLAR := 0.9
const PILLAR_GRID := 6             # 6x6 pillars
const PILLAR_SPACING := 6.0
const ALCOVE_D := 3.0              # alcove depth
const ALCOVE_W := 3.4
const DEAD_LIGHT_CHANCE := 0.3

const SIDES := ["N", "S", "E", "W"]
const SIDE_AXIS := {
	"N": Vector3(0, 0, 1), "S": Vector3(0, 0, -1),
	"E": Vector3(1, 0, 0), "W": Vector3(-1, 0, 0),
}

var spawn_point: Vector3           # where the level drops the player / sends them back

var _wall_mat: StandardMaterial3D
var _floor_mat: StandardMaterial3D
var _ceil_mat: StandardMaterial3D
var _origin: Vector3
var _walls := {}                   # side -> GlitchWall
var _silence: SilenceZone
var _tell_water: AudioStreamPlayer3D    # the positive tell (BUG_FIX.md 3.5) at the real wall
var _tell_whisper: AudioStreamPlayer3D  # layered with it, closer/quieter
var _real_side: String = "N"
var _lights: Array = []
var _congregation: Congregation = null

const CONGREGATION_START := 6       # grows by one per wrong wall, capped in congregation.gd
const LOW_CEIL_H := 3.0             # zone 1's correct height, for contrast against HEIGHT 4.5
const _NOTE_SCRIPT := preload("res://scripts/note.gd")

const SPRAWL_NOTE := """The ceiling is wrong here.

I measured it. Four and a half metres in the hall, three in the corner by the alcoves. Nobody builds a room like that. Nobody builds a room this big with nothing in it.

I stopped counting the pillars at thirty. I went back and counted again and got thirty-six, and then thirty. I do not think the number is the thing that is changing.

If you are standing still to listen — good. That is the only thing that works down here. Listen for the water."""


# Called by backrooms.gd on a wrong wall: the player's own mistakes populate the room.
func populate_one_more() -> void:
	if _congregation:
		_congregation.add_one()


func _pillar_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var span := (PILLAR_GRID - 1) * PILLAR_SPACING
	var start := -span / 2.0
	for i in range(PILLAR_GRID):
		for j in range(PILLAR_GRID):
			out.append(_origin + Vector3(start + i * PILLAR_SPACING, 0.0,
				start + j * PILLAR_SPACING))
	return out


func build(origin: Vector3) -> void:
	_origin = origin
	position = origin
	spawn_point = origin + Vector3(0, 0.1, -HALF + 4.0)

	_wall_mat = MazeKit.wall_material()
	_floor_mat = MazeKit.floor_material()
	_ceil_mat = MazeKit.ceiling_material()

	_build_shell()
	_build_pillars()
	_build_alcoves()
	_build_lights()
	_build_glitch_walls()
	_build_pressure()
	_build_alcove_contents()
	_build_low_ceiling()
	_randomise_real_wall()
	# THE CONGREGATION. Zero panic, no rules — see congregation.gd. Kept OFF the calm island
	# so the one recovery anchor in the zone stays a place you can stand and breathe.
	_congregation = Congregation.build(self, _origin, _pillar_positions(),
		CONGREGATION_START, [_origin], 8.0)


# ---------------------------------------------------------------- geometry

func _build_shell() -> void:
	MazeKit.slab(self, "Sprawl", Vector3.ZERO, Vector3(SIZE, 0, SIZE),
		HEIGHT, T, _floor_mat, _ceil_mat)
	# Perimeter. Each side is split into two runs leaving a gap in the middle,
	# which is where that side's glitch wall sits flush.
	var gap := 7.0
	var run := (SIZE - gap) / 2.0
	var off := gap / 2.0 + run / 2.0
	for s in ["N", "S"]:
		var z: float = SIDE_AXIS[s].z * (HALF + T / 2.0)
		for sx in [1.0, -1.0]:
			MazeKit.wall(self, "Perim%s%s" % [s, sx], Vector3(sx * off, 0, z),
				Vector3(run, 0, T), HEIGHT, _wall_mat)
	for s in ["E", "W"]:
		var x: float = SIDE_AXIS[s].x * (HALF + T / 2.0)
		for sz in [1.0, -1.0]:
			MazeKit.wall(self, "Perim%s%s" % [s, sz], Vector3(x, 0, sz * off),
				Vector3(T, 0, run), HEIGHT, _wall_mat)


func _build_pillars() -> void:
	var span := (PILLAR_GRID - 1) * PILLAR_SPACING
	var start := -span / 2.0
	for i in range(PILLAR_GRID):
		for j in range(PILLAR_GRID):
			var p := Vector3(start + i * PILLAR_SPACING, 0, start + j * PILLAR_SPACING)
			MazeKit.box(self, "Pillar%d_%d" % [i, j],
				Vector3(p.x, HEIGHT / 2.0, p.z),
				Vector3(PILLAR, HEIGHT, PILLAR), _wall_mat)


func _build_alcoves() -> void:
	# Identical recesses punched into the perimeter — they look like they must lead
	# somewhere. TWO per side (8 total), at ±11 m, skipping the centre (the glitch
	# wall's gap lives there). The comment here said "three per side" until 2026-07-27;
	# the loop has always been `for k in [-1, 1]`.
	for s in SIDES:
		var axis: Vector3 = SIDE_AXIS[s]
		for k in [-1, 1]:
			var along: Vector3 = Vector3(axis.z, 0, axis.x) * (k * 11.0)
			var centre: Vector3 = axis * (HALF + ALCOVE_D / 2.0) + along
			var is_x: bool = absf(axis.x) > 0.5
			var box_size := Vector3(ALCOVE_D, 0, ALCOVE_W) if is_x \
				else Vector3(ALCOVE_W, 0, ALCOVE_D)
			MazeKit.slab(self, "Alc%s%d" % [s, k], centre, box_size,
				HEIGHT, T, _floor_mat, _ceil_mat)
			# back + two sides of the recess
			var back: Vector3 = centre + axis * (ALCOVE_D / 2.0 + T / 2.0)
			MazeKit.wall(self, "AlcBack%s%d" % [s, k], back,
				Vector3(ALCOVE_D, 0, T) if is_x else Vector3(ALCOVE_W, 0, T),
				HEIGHT, _wall_mat)
			for side_sign in [1.0, -1.0]:
				var lat: Vector3 = Vector3(axis.z, 0, axis.x) * side_sign * (ALCOVE_W / 2.0 + T / 2.0)
				# Side walls run along the recess DEPTH and are thin across it, so
				# the long axis is z for an N/S alcove and x for an E/W one.
				MazeKit.wall(self, "AlcSide%s%d%s" % [s, k, side_sign], centre + lat,
					Vector3(ALCOVE_D, 0, T) if is_x else Vector3(T, 0, ALCOVE_D),
					HEIGHT, _wall_mat)


func _build_lights() -> void:
	# A sparse grid, ~30% of it dead. The dark patches are not zones — they are just
	# places you can't see, which is enough.
	for i in range(-2, 3):
		for j in range(-2, 3):
			if randf() < DEAD_LIGHT_CHANCE:
				continue
			var f := MazeKit.light_strip(self,
				Vector3(i * 9.0, 0, j * 9.0), HEIGHT, 1.0, 8.0)
			_lights.append(f)


# ---------------------------------------------------------------- the four walls

func _build_glitch_walls() -> void:
	for s in SIDES:
		var axis: Vector3 = SIDE_AXIS[s]
		var w := GlitchWall.new()
		w.name = "Glitch" + s
		add_child(w)
		w.setup(Vector2(7.0, HEIGHT), HEIGHT, false)
		w.position = axis * (HALF - 0.05) + Vector3(0, HEIGHT / 2.0, 0)
		# Face the hall centre. The mesh's front is -Z, and the trigger sits at -Z
		# too, so a single yaw orients both.
		w.rotation.y = atan2(axis.x, axis.z)
		w.touched.connect(_on_wall_touched.bind(s))
		_walls[s] = w


func _randomise_real_wall() -> void:
	# Only walls that haven't already been outed can become the real one — promoting
	# a wall that has gone solid would leave the zone with no reachable exit.
	var candidates: Array = []
	for s in SIDES:
		var w: GlitchWall = _walls[s]
		if is_instance_valid(w) and not w.is_solid():
			candidates.append(s)
	if candidates.is_empty():
		# Every wall was touched and outed. Rather than soft-lock, tear one back
		# open — the maze is allowed to cheat in the player's favour here.
		var revived: String = SIDES[randi() % SIDES.size()]
		_walls[revived].revive()
		candidates = [revived]
	for s in SIDES:
		if is_instance_valid(_walls[s]):
			_walls[s].is_real = false
	_real_side = candidates[randi() % candidates.size()]
	_walls[_real_side].is_real = true

	# Move the silence pocket to the new real wall.
	if is_instance_valid(_silence):
		_silence.queue_free()
	var axis: Vector3 = SIDE_AXIS[_real_side]
	_silence = SilenceZone.new()
	MazeKit.zone_box(self, _silence, axis * (HALF - 5.0) + Vector3(0, HEIGHT / 2.0, 0),
		Vector3(11.0, HEIGHT, 11.0), "SilencePocket")

	# The positive tell (BUG_FIX.md 3.5, revised after playtest): silence alone tested
	# as too subtle, and the first version of this tell (a procedural hum) used
	# unit_size=4.5 — audible only once you were basically already at the correct
	# wall, in a 40x40 m room with 4 identical ones. Two layers now, both MUCH wider
	# range so there's something to actually walk toward from across the hall:
	# `water` carries from far off as a background cue, `whisper` confirms up close.
	# Both sit at the wall itself (not the wider silence pocket) and stay OFF the
	# "Backrooms" bus on purpose — routing through the bus SilenceZone ducks would
	# have the pocket mute the very tell it's supposed to provide.
	if is_instance_valid(_tell_water):
		_tell_water.queue_free()
	if is_instance_valid(_tell_whisper):
		_tell_whisper.queue_free()

	_tell_water = AudioStreamPlayer3D.new()
	var water_stream := GameState.load_audio("water")
	if water_stream:
		_tell_water.stream = water_stream
		_tell_water.unit_size = 16.0
		_tell_water.volume_db = 0.0
		_tell_water.bus = "Master"
		_tell_water.finished.connect(_tell_water.play)
	add_child(_tell_water)
	_tell_water.position = _walls[_real_side].position
	if _tell_water.stream:
		_tell_water.play()

	_tell_whisper = AudioStreamPlayer3D.new()
	var whisper_stream := GameState.load_audio("whisper")
	if whisper_stream:
		_tell_whisper.stream = whisper_stream
		_tell_whisper.unit_size = 9.0
		_tell_whisper.volume_db = 1.0
		_tell_whisper.bus = "Master"
		_tell_whisper.finished.connect(_tell_whisper.play)
	add_child(_tell_whisper)
	_tell_whisper.position = _walls[_real_side].position
	if _tell_whisper.stream:
		_tell_whisper.play()


func _on_wall_touched(is_real: bool, side: String) -> void:
	if is_real:
		cleared.emit()
	else:
		_walls[side].go_solid()
		mistake.emit()
		_randomise_real_wall()


# ---------------------------------------------------------------- pressure

# Five of the eight alcoves were completely empty, so all eight read as holes rather than as
# a set — and the zone had NOTHING to read and NOTHING to interact with anywhere in 1600 m².
#
# ⚠️ Zero panic here, deliberately. The phone is an EMITTER, not a trap: `open_note` stays
# false, so it cannot be answered into the Backrooms' read-to-die note the way zone 1's can.
# It is already off the hook — something else answered it.
func _build_alcove_contents() -> void:
	var alc := func(side: String, k: int) -> Vector3:
		var axis: Vector3 = SIDE_AXIS[side]
		return axis * (HALF + ALCOVE_D / 2.0) \
			+ Vector3(axis.z, 0, axis.x) * (k * 11.0)

	# A note — the only thing to read in the zone.
	var note_pos: Vector3 = alc.call("S", -1)
	var note := StaticBody3D.new()
	note.name = "SprawlNote"
	note.set_script(_NOTE_SCRIPT)
	note.note_text = SPRAWL_NOTE
	note.is_trap = false
	note.position = note_pos + Vector3(0, 1.35, 0)
	add_child(note)
	var nm := MeshInstance3D.new()
	var nb := BoxMesh.new()
	nb.size = Vector3(0.32, 0.42, 0.01)
	nm.mesh = nb
	nm.set_surface_override_material(0, _NOTE_SCRIPT.paper_material(false))
	note.add_child(nm)
	var ncol := CollisionShape3D.new()
	var nshape := BoxShape3D.new()
	nshape.size = Vector3(0.4, 0.5, 0.12)
	ncol.shape = nshape
	note.add_child(ncol)
	# A small lamp, or a sheet of paper in a 40 m hall is unfindable.
	var nl := OmniLight3D.new()
	nl.light_energy = 0.22
	nl.omni_range = 2.0
	nl.position = note_pos + Vector3(0, 1.8, 0)
	add_child(nl)

	# A rotary phone, already off the hook, whispering. Audible from across a few metres and
	# it stops as you close on it — so it is a thing to walk toward that gives nothing back.
	var phone := RotaryPhone.new()
	phone.name = "SprawlPhone"
	phone.position = alc.call("E", 1)
	phone.open_note = false
	phone.rings = false
	add_child(phone)

	# The remaining alcoves get furniture, so the eight read as a set.
	for spec in [["N", 1], ["W", -1], ["W", 1], ["S", 1], ["E", -1]]:
		var p: Vector3 = alc.call(spec[0], int(spec[1]))
		var b := CSGBox3D.new()
		b.name = "AlcProp%s%d" % [spec[0], int(spec[1])]
		b.size = Vector3(1.1, 0.75, 0.6)
		b.position = p + Vector3(0, 0.375, 0)
		b.use_collision = true
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.42, 0.36, 0.20)
		m.roughness = 0.9
		b.material = m
		add_child(b)


# The 4.5 m ceiling is this zone's stated identity — "deliberately wrong-scale against zone
# 1's 3 m corridors" — and NOTHING sold it, because a ceiling you never see the edge of has
# no scale at all. A second, partial ceiling at zone 1's correct 3.0 m over one corner gives
# the eye a join to compare against, so the wrongness becomes legible instead of theoretical.
#
# ⚠️ Offset well clear of the 4.5 m slab (a 1.5 m gap), and sized to stop short of the
# pillars' outer row, so no two surfaces are anywhere near coplanar (Issues 19/20/23).
func _build_low_ceiling() -> void:
	var low := CSGBox3D.new()
	low.name = "SprawlLowCeiling"
	low.size = Vector3(16.0, T, 16.0)
	low.position = Vector3(-10.0, LOW_CEIL_H + T / 2.0, -10.0)
	low.use_collision = true
	low.material = _ceil_mat
	add_child(low)


func _build_pressure() -> void:
	# The whole hall is a DreadZone. Per player.gd:_update_panic, dread is the only
	# genuinely ADDITIVE source — gaze / sprint / dark-creep are an if/elif chain and
	# never stack — so this is what actually makes the room grind.
	MazeKit.zone_box(self, DreadZone.new(), Vector3(0, HEIGHT / 2.0, 0),
		Vector3(SIZE, HEIGHT, SIZE), "SprawlDread")

	# One recovery anchor: a working light island dead centre. Without it, three
	# net-positive zones back to back is not survivable.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.96, 0.8)
	lamp.light_energy = 2.2
	lamp.omni_range = 11.0
	lamp.position = Vector3(0, HEIGHT - 0.6, 0)
	add_child(lamp)
	MazeKit.zone_box(self, CalmZone.new(), Vector3(0, HEIGHT / 2.0, 0),
		Vector3(9.0, HEIGHT, 9.0), "SprawlCalm")

	# Beartraps in the pillar shadows, off the calm island.
	for p in [Vector3(-15, 0, 8), Vector3(13, 0, -11), Vector3(4, 0, 16)]:
		var trap := Beartrap.new()
		trap.position = p
		add_child(trap)

	# Mirage doors in two alcoves — the retreat that isn't.
	for s in ["E", "W"]:
		var axis: Vector3 = SIDE_AXIS[s]
		var door := MirageDoor.new()
		door.position = axis * (HALF + ALCOVE_D - 0.15) \
			+ Vector3(axis.z, 0, axis.x) * 11.0
		door.rotation.y = atan2(-axis.x, -axis.z)
		add_child(door)

	# A one-way mirror in a third alcove. Reuses lab_oneway_mirror.png, which was
	# sitting unreferenced in the project.
	var mirror := LivingMirror.new()
	mirror.position = SIDE_AXIS["N"] * (HALF + ALCOVE_D - 0.2) \
		+ Vector3(1, 0, 0) * -11.0 + Vector3(0, 1.5, 0)
	mirror.rotation.y = PI
	add_child(mirror)
