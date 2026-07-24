extends Node3D
class_name BackroomsZone2

# ZONE 2 — THE SPRAWL.
#
# Zone 1 taught the verb (walk into the wall). This zone makes you find the right
# wall. Four glitch walls tear identically on the four sides of a big pillar hall;
# only one is real, and the tell is not visual — near the real one the ambient bed
# fades to nothing. You listen your way out. Touch a fake and it goes solid, costs
# 18 panic, and the real wall re-randomises, so brute force is a losing line: two
# mistakes puts you at 36 of 50.
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
	_randomise_real_wall()


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
	# somewhere and none of them do. Three per side, skipping the centre (the glitch
	# wall's gap lives there).
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
