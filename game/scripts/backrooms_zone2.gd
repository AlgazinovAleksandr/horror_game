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
signal crate_scare                 # the box in the dark was opened (the level owns the scare)
# THE RUN (2026-08-18). The zone owns the runner; the LEVEL owns the player, and the user
# asked to be made to watch it — so the run announces itself and `backrooms.gd` pins the
# camera to it with `player.turn_to_face()`. Emitted when the runner starts moving (which
# is one `flash_scare` hold AFTER the crate opens, so the image is off the screen first)
# and again when it is through the wall.
signal dweller_running(runner: Node3D)
signal dweller_arrived

const SIZE := 40.0                 # hall is SIZE x SIZE
const HALF := SIZE / 2.0
const HEIGHT := 4.5                # deliberately wrong-scale vs zone 1's 3.0
const T := 0.3
const PILLAR := 0.9
const PILLAR_GRID := 6             # 6x6 pillars
const PILLAR_SPACING := 6.0
const ALCOVE_D := 3.0              # alcove depth
const ALCOVE_W := 3.4
# ⚠️ How far along each side the two alcoves sit. This was the literal `11.0`, repeated in
# four places (`_build_alcoves`, the contents helper, the mirage doors, the mirror) — and the
# perimeter, which has to be CUT at exactly the same offset, is a fifth. One number now.
const ALCOVE_AT := 11.0
# The gap in the middle of each side where that side's glitch wall sits flush.
const GLITCH_GAP := 7.0
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

# ============================================ THE BOX IN THE DARK (2026-08-17, B-R3)
#
# The user's own design, in their words:
#
#   *"I want the true wall appear only after the player explored the dark, opened this box,
#   saw the screamer. Maybe we can also do it the following way: the creature which was a
#   jumpscare starts running towards the wall, it escapes the wall, and once it is there,
#   the wall starts being visible. And it would actually whisper, and the first whisper
#   would lead to that box hidden in the dark."*
#
# ⚠️⚠️ THE CRATE IS THE GATE (2026-08-18). This block used to say the opposite — that the
# crate was a redundant second route and the sound tell alone still cleared the zone — and
# the user overturned it, having been told the fallback existed: *"it should run and go
# through the real wall which would not be active until it runs through."* Asked for twice,
# explicitly. So: **the real wall is SEALED until the runner goes through it.** It looks
# exactly like its three neighbours, tears exactly like them, and walking into it does
# nothing at all — no clear, no penalty, no sound. `glitch_wall.gd:set_sealed()` says why it
# is a collider rather than `set_armed(false)` (this wall IS the shell; hiding it is a 7 m
# hole in the perimeter).
#
# ⚠️⚠️ WHICH MAKES THE WHISPER LOAD-BEARING, and that is now the ONLY thing standing between
# this design and an unwinnable zone. A player who never finds the crate cannot leave. So
# `sprawl_crate.gd`'s two-layer call is PERMANENT while the box is shut — no timeout, no
# one-shot, no distance gate — the same rule and for the same reason as the Flood's knocks
# (`sunken_item.gd:_process` gated on `is_taken`, never on `is_searched`). It is measured,
# not assumed: `check_sprawl_crate.gd` samples the far cue against the level's own ambient
# bed on a grid over every square metre of the hall and requires a positive margin at the
# worst point, and drives a cold start — spawn, follow the call, open the box, watch the
# run, walk through the wall — with nothing emitted.
#
# ⚠️ THE `water` + `whisper` TELL AT THE REAL WALL STAYS, and is now FLAVOUR AND
# CONFIRMATION rather than the route. Removing it would leave the wall silent until the
# moment the runner arrives, and the run is the only cue there is.
#
# ⚠️ THE MARK FOLLOWS A RE-ROLL. Touching a fake re-randomises the real wall
# (`_randomise_real_wall()`), so a mark left on the old one would be a LIE — worse than no
# mark. If the dweller has already run, the new real wall is marked in the same breath.
#
# ⚠️ ONE ALCOVE, CHOSEN PER RUN, AND ITS LIGHT IS CUT. "Hidden in the dark" is a measurable
# claim: `_build_lights()` skips any ceiling strip within `CRATE_DARK_R` of the chosen
# recess, so the box is genuinely unlit rather than merely off to one side. It takes the
# place of that recess's furniture prop — all eight recesses still hold exactly one thing
# (D17's rule).
const CRATE_ALCOVES := [["N", 1], ["W", -1], ["S", 1], ["E", -1]]
const CRATE_DARK_R := 11.0
const CRATE_SCARE_IMAGE := "res://assets/textures/level_backrooms/sprawl_dweller_face.png"
const CRATE_SCARE_AUDIO := "crate_shriek"
const CRATE_SCARE_HOLD := 0.9
# The dweller is spawned a step in front of the crate, facing out of the recess, so it is
# never inside the geometry it came out of.
const DWELLER_OUT := 1.3

var _crate: SprawlCrate = null
var _crate_side: String = "S"
var _crate_k: int = 1
var _dweller: SprawlDweller = null
var _dweller_done := false
var _voice: Array = []

const CONGREGATION_START := 6       # grows by one per wrong wall, capped in congregation.gd
# House-style wall-prop clearance. RoomBuilder's `wall_point()` clamps its own 3 cm minimum
# (Issue 26); this zone builds its walls by hand, so it states the number itself.
const NOTE_INSET := 0.16
# ...and 0.22 for anything that hangs a second surface behind or in front of its own face.
const MIRROR_INSET := 0.22
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

	# ⚠️ CHOSEN BEFORE THE LIGHTS ARE BUILT: `_build_lights()` reads it to leave that corner
	# of the ceiling dark, which is what makes "hidden in the dark" true rather than stated.
	var pick: Array = CRATE_ALCOVES[randi() % CRATE_ALCOVES.size()]
	_crate_side = String(pick[0])
	_crate_k = int(pick[1])

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

# The solid runs along ONE side, in that side's own lateral coordinate, once every opening
# has been removed: the central glitch-wall gap, and one MOUTH per alcove.
#
# ⚠️ A mouth is the alcove's interior width PLUS a wall thickness at each end, so the
# perimeter stops exactly at the OUTER face of the alcove's own side walls and the two boxes
# ABUT. Ending it at the alcove's interior width instead would leave the perimeter's end cap
# and the side wall's end cap coplanar and both facing into the mouth — two visible surfaces
# in one plane, which is this project's most expensive bug class (Issues 19/20/23/24/25/26).
func _side_runs() -> Array:
	var mouth_half: float = ALCOVE_W / 2.0 + T
	var openings: Array = [Vector2(-GLITCH_GAP / 2.0, GLITCH_GAP / 2.0)]
	for k in [-1.0, 1.0]:
		var c: float = k * ALCOVE_AT
		openings.append(Vector2(c - mouth_half, c + mouth_half))
	openings.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var runs: Array = []
	var cursor := -HALF
	for o in openings:
		if o.x > cursor:
			runs.append(Vector2(cursor, o.x))
		cursor = maxf(cursor, o.y)
	if cursor < HALF:
		runs.append(Vector2(cursor, HALF))
	return runs


func _build_shell() -> void:
	MazeKit.slab(self, "Sprawl", Vector3.ZERO, Vector3(SIZE, 0, SIZE),
		HEIGHT, T, _floor_mat, _ceil_mat)
	# Perimeter. FOUR runs per side, not two: a gap in the middle where that side's glitch
	# wall sits flush, and one opening at each alcove.
	#
	# ⚠️ THE OPENINGS ARE THE FIX FOR F1 (2026-08-17). Until this date the perimeter was two
	# unbroken 16.5 m runs per side and the eight "recesses" below were built entirely BEHIND
	# it — sealed, for the whole life of the zone, along with the only readable page in
	# 1600 m². See `_build_alcoves()`.
	var runs := _side_runs()
	for s in SIDES:
		var axis: Vector3 = SIDE_AXIS[s]
		var is_x: bool = absf(axis.x) > 0.5
		for i in range(runs.size()):
			var r: Vector2 = runs[i]
			var mid: float = (r.x + r.y) / 2.0
			var length: float = r.y - r.x
			if is_x:
				MazeKit.wall(self, "Perim%s%d" % [s, i],
					Vector3(axis.x * (HALF + T / 2.0), 0, mid),
					Vector3(T, 0, length), HEIGHT, _wall_mat)
			else:
				MazeKit.wall(self, "Perim%s%d" % [s, i],
					Vector3(mid, 0, axis.z * (HALF + T / 2.0)),
					Vector3(length, 0, T), HEIGHT, _wall_mat)


func _build_pillars() -> void:
	var span := (PILLAR_GRID - 1) * PILLAR_SPACING
	var start := -span / 2.0
	for i in range(PILLAR_GRID):
		for j in range(PILLAR_GRID):
			var p := Vector3(start + i * PILLAR_SPACING, 0, start + j * PILLAR_SPACING)
			MazeKit.box(self, "Pillar%d_%d" % [i, j],
				Vector3(p.x, HEIGHT / 2.0, p.z),
				Vector3(PILLAR, HEIGHT, PILLAR), _wall_mat)


# ⚠️⚠️ THESE ALCOVES WERE SEALED FOR THE WHOLE LIFE OF THE ZONE. OPENED 2026-08-17 (F1).
#
# This function builds each recess as a floor, a back wall and two side walls OUTSIDE the
# perimeter — and until 2026-08-17 nothing ever removed the length of perimeter wall in front
# of it, so the word "punched" was never true. `_build_shell()` split each side into two
# unbroken runs of `(SIZE - GLITCH_GAP) / 2 = 16.5 m` spanning 3.5..20 and -20..-3.5, and the
# alcoves sit at ±ALCOVE_AT. They were behind wall.
#
# Proved by ray, not by reading the table (tests/probe_alcove_reach.gd) — a ray fired from 3 m
# inside the hall toward each alcove's centre was BLOCKED AT EXACTLY 3.00 m, the mouth plane,
# on all eight. Behind it: `SprawlNote` — the ONLY readable object in a 1600 m² zone, and the
# page that states the zone's own tell — the off-hook `SprawlPhone`, the `LivingMirror`, two
# `MirageDoor`s and five furniture props. The playtest finding "SprawlNote was not read in
# either session" was read as a placement problem. It was not; it was unreachable.
#
# ⚠️ THE OPENINGS ARE OWNED BY `_side_runs()`, WHICH DERIVES THEM FROM THE SAME CONSTANTS
# THIS FUNCTION USES. If you change `ALCOVE_AT`, `ALCOVE_W` or `T`, the mouths follow; if you
# ever place an alcove by hand, cut its mouth in the same breath or you have built another
# sealed room. `tests/check_reachable.gd` is the guard: it flood-fills the standable space
# with the player's own capsule and requires every interactable to answer the real interact
# ray, and it carries a control that seals this very alcove back up to prove it can fail.
func _build_alcoves() -> void:
	# Identical recesses punched into the perimeter — they look like they must lead
	# somewhere. TWO per side (8 total), at ±ALCOVE_AT, skipping the centre (the glitch
	# wall's gap lives there). The comment here said "three per side" until 2026-07-27;
	# the loop has always been `for k in [-1, 1]`.
	for s in SIDES:
		var axis: Vector3 = SIDE_AXIS[s]
		for k in [-1, 1]:
			var along: Vector3 = Vector3(axis.z, 0, axis.x) * (k * ALCOVE_AT)
			var centre: Vector3 = axis * (HALF + ALCOVE_D / 2.0) + along
			var is_x: bool = absf(axis.x) > 0.5
			var box_size := Vector3(ALCOVE_D, 0, ALCOVE_W) if is_x \
				else Vector3(ALCOVE_W, 0, ALCOVE_D)
			MazeKit.slab(self, "Alc%s%d" % [s, k], centre, box_size,
				HEIGHT, T, _floor_mat, _ceil_mat)
			# back + two sides of the recess
			#
			# ⚠️⚠️ THE BACK WALL IS THIN ACROSS THE ALCOVE'S DEPTH AXIS AND LONG ACROSS ITS
			# WIDTH — the OPPOSITE of a side wall, which is thin across the width and long
			# down the depth. Until 2026-08-17 both lines carried the SAME ternary, so on the
			# E and W sides (`is_x`) the back wall was built `(ALCOVE_D, h, T)`: a 3 m blade
			# lying ALONG the depth axis, centred on the back plane, half inside the recess
			# and half outside it — and the back of all four E/W alcoves was OPEN SKY.
			#
			# The player photographed it (backlog 04 R1, capture 004): a gap in the shell
			# showing the procedural sky horizon, split down the middle by the blade, with
			# the alcove's `MirageDoor` silhouetted against it. Measured: 3.40 m wide x 4.50 m
			# tall of open world per alcove, x4.
			#
			# ⚠️ IT SURVIVED A GUARD. `check_sprawl_alcoves.gd`'s "shell closed" probe fired
			# ONE ray outward from the recess CENTRE — and the blade sits exactly on that
			# line, so the ray hit it at 0.15 m and reported the wall present. A single
			# centred ray cannot see a hole shaped like a doorway; `apparition.gd:_fits()`
			# fans 16 of them for the same reason. Both that check and the new
			# `check_shell_sealed.gd` now sweep laterally.
			var back: Vector3 = centre + axis * (ALCOVE_D / 2.0 + T / 2.0)
			MazeKit.wall(self, "AlcBack%s%d" % [s, k], back,
				Vector3(T, 0, ALCOVE_W) if is_x else Vector3(ALCOVE_W, 0, T),
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
	#
	# ⚠️ AND ONE PATCH IS DARK ON PURPOSE (2026-08-17, B-R3): every strip within
	# CRATE_DARK_R of the crate's recess is skipped, so the box the whisper leads to is
	# genuinely unlit. Without this the alcove's darkness was a 30 % coin flip, and a beat
	# whose whole premise is "explored the dark" cannot be left to one.
	var dark_at: Vector3 = _alc_centre(_crate_side, _crate_k) - _origin
	for i in range(-2, 3):
		for j in range(-2, 3):
			var at := Vector3(i * 9.0, 0, j * 9.0)
			if Vector2(at.x - dark_at.x, at.z - dark_at.z).length() < CRATE_DARK_R:
				continue
			if randf() < DEAD_LIGHT_CHANCE:
				continue
			var f := MazeKit.light_strip(self, at, HEIGHT, 1.0, 8.0)
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

	# ⚠️ THE GATE FOLLOWS THE RE-ROLL TOO (2026-08-18). A wrong wall re-randomises which one
	# is real, so the seal has to move with it: the wall that WAS real becomes an ordinary
	# fake (unsealed, touchable, worth a strike) and the new one takes the gate. Applying
	# this before the mark, because `_apply_gate()` is also what re-opens the answer when
	# the runner has already been through.
	_apply_gate()

	# ⚠️ THE MARK FOLLOWS THE RE-ROLL (2026-08-17, B-R3). A wrong wall re-randomises which
	# one is real, so a mark left where the dweller ran would be pointing at a wall that is
	# now a fake — a tell that lies is worse than no tell, and this one was earned. If the
	# dweller has already run, the new real wall is marked in the same breath.
	if _dweller_done:
		_mark_real_wall()

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
			+ Vector3(axis.z, 0, axis.x) * (k * ALCOVE_AT)

	# A note — the only thing to read in the zone.
	#
	# ⚠️ ON THE ALCOVE'S BACK WALL, not floating at its centre (fixed 2026-08-17, backlog 04
	# B-A4). It used to be placed at `alc("S", -1) + (0, 1.35, 0)` with `rotation` left at
	# identity — measured, 1.20 m of air behind it in the nearer of the two directions. That
	# is the House third-digit-note fault (Issues 71/79, "1.40 m out in mid-air") in a second
	# level, on the ONE page in a 1600 m² hall, and the page that states the zone's own tell
	# ("Listen for the water"). It was not read in either playtest session.
	#
	# The alcove's back wall is built at `centre + axis * (ALCOVE_D/2 + T/2)` with thickness
	# T, so its inner face is `centre + axis * ALCOVE_D/2`. Sitting NOTE_INSET in from that
	# gives the same ~0.16 m of air every wall prop in this project hangs on — and it is
	# derived from the geometry above rather than hand-typed, so it follows if the alcove
	# ever changes shape. The alcove's open side faces the hall, so this wall has no doorway.
	var alc_axis: Vector3 = SIDE_AXIS["S"]
	var alc_centre: Vector3 = alc.call("S", -1)
	var note_pos: Vector3 = alc_centre + alc_axis * (ALCOVE_D / 2.0 - NOTE_INSET)
	var note := StaticBody3D.new()
	note.name = "SprawlNote"
	note.set_script(_NOTE_SCRIPT)
	note.note_text = SPRAWL_NOTE
	note.is_trap = false
	note.position = note_pos + Vector3(0, 1.35, 0)
	# Face into the alcove, i.e. back along the alcove's outward axis. The note mesh carries
	# its paper on +Z, so the yaw that turns +Z to -alc_axis is the one that shows it.
	note.rotation.y = atan2(-alc_axis.x, -alc_axis.z)
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
	# Just off the wall and into the alcove, so it lights the PAGE rather than the plaster
	# behind it — the note now hangs flat on that wall.
	nl.position = note_pos - alc_axis * 0.35 + Vector3(0, 1.8, 0)
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
	#
	# ⚠️ W+1 IS DELIBERATELY NOT IN THIS LIST (2026-08-17, backlog 04 D17). `_build_pressure()`
	# puts a `MirageDoor` on the back wall of both the E+1 and the W+1 recess, and a
	# 1.1 x 0.75 x 0.6 crate standing 0.8 m in front of one made the W recess the only one in
	# the zone with two large objects in it — photographed on the verification replay
	# (`28_w_alcove_capture004.png`) and read as clutter. It never blocked the door (measured),
	# but a mirage door is "the retreat that isn't" and it only lands if the recess reads as a
	# way out rather than as a storage nook. All eight recesses still hold exactly one thing:
	# N-1 mirror, N+1 furniture, S-1 note, S+1 furniture, E-1 furniture, E+1 phone,
	# W-1 furniture, W+1 the mirage door alone.
	# ⚠️ ONE OF THESE FOUR IS THE CRATE (2026-08-17, B-R3), chosen per run in `build()`. It
	# takes the place of that recess's box rather than being added beside it, so all eight
	# recesses still hold exactly one thing — D17's rule, taken on a photographed replay.
	for spec in [["N", 1], ["W", -1], ["S", 1], ["E", -1]]:
		var side := String(spec[0])
		var k := int(spec[1])
		var p: Vector3 = alc.call(side, k)
		if side == _crate_side and k == _crate_k:
			# Set back into the recess and turned to face the hall, so the lid opens toward
			# whoever walked in after the whisper.
			var axis: Vector3 = SIDE_AXIS[side]
			_crate = SprawlCrate.build(self, "SprawlCrate",
				p + axis * 0.55, atan2(-axis.x, -axis.z))
			_crate.opened.connect(_on_crate_opened)
			continue
		var b := CSGBox3D.new()
		b.name = "AlcProp%s%d" % [side, k]
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
	#
	# ⚠️ SIZED TO COVER THE ALCOVES TOO (2026-08-17, with F1). This box was `SIZE x SIZE`,
	# i.e. the hall exactly, because the alcoves were sealed and nobody could stand in one.
	# Opening them without widening it would have handed the zone EIGHT new recovery pockets
	# — outside the dread, decay runs at the full PANIC_DECAY_RATE 3.5/s, so a few seconds in
	# an alcove is worth a double-digit slice of PANIC_MAX — in a zone whose written design
	# has exactly ONE recovery anchor ("three net-positive zones back to back is not
	# survivable"). That would be a difficulty change made by accident. Widening it is the
	# change that keeps the pressure profile IDENTICAL to the sealed build, which is the
	# conservative half of the choice; reverting is one expression, and it is the user's call.
	var dread_span: float = SIZE + 2.0 * (ALCOVE_D + T)
	MazeKit.zone_box(self, DreadZone.new(), Vector3(0, HEIGHT / 2.0, 0),
		Vector3(dread_span, HEIGHT, dread_span), "SprawlDread")

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
			+ Vector3(axis.z, 0, axis.x) * ALCOVE_AT
		door.rotation.y = atan2(-axis.x, -axis.z)
		add_child(door)

	# A one-way mirror in a third alcove (N, k = -1). Reuses lab_oneway_mirror.png, which was
	# sitting unreferenced in the project.
	#
	# ⚠️ IT FACED ITS OWN WALL, and it was 0.70 m off it (found 2026-08-17 by pointing
	# check_note_mounting.gd at this scene for the first time; Issue 83's family).
	#
	# `LivingMirror` faces its LOCAL -Z — level_1.gd:1222 and level_2.gd:866/921 all say so
	# and all orient by it. This alcove is on the N side, so its back wall is at +z and the
	# hall is at -z; `rotation.y = PI` therefore turned the glass to face the back wall
	# 0.7 m behind it. A QuadMesh is single-sided, so from the hall the panel rendered as
	# NOTHING AT ALL — and the figure, which lives 0.05 m off the glass on the same local
	# axis, was between the glass and the plaster. The one interactive-looking object in
	# 1600 m² could never have been seen.
	#
	# Yaw ZERO faces it back into the hall. Inset 0.22, not the usual 0.16, for the same
	# reason level_1.gd gives: this prop hangs a second quad 0.05 m off its glass, so it needs
	# clearance for the figure as well as for itself (Issue 26).
	var mirror := LivingMirror.new()
	mirror.name = "SprawlMirror"
	# ⚠️ The ONLY caller that opts in (backlog 04 B-A9). Measured here: the glass was a
	# 1.250-aspect landscape observation window squashed onto a 0.667 portrait quad — a
	# 1.874x stretch — and the figure behind it 1.141x. The same fault exists in the Lab and
	# the House and is deliberately NOT fixed from here: those levels are closed, and turning
	# the flag on is a visible change (portrait -> landscape at the same diagonal), not a
	# silent correction. See living_mirror.gd's `fit_to_art`.
	mirror.fit_to_art = true
	mirror.position = SIDE_AXIS["N"] * (HALF + ALCOVE_D / 2.0) \
		+ SIDE_AXIS["N"] * (ALCOVE_D / 2.0 - MIRROR_INSET) \
		+ Vector3(1, 0, 0) * -ALCOVE_AT + Vector3(0, 1.5, 0)
	mirror.rotation.y = 0.0
	add_child(mirror)


# ============================================================== THE CRATE SEQUENCE (B-R3)

# World-space centre of one recess. One expression, used by the lighting cut, the crate
# placement and the tests — `ALCOVE_AT` was a literal repeated in four places once already.
func _alc_centre(side: String, k: int) -> Vector3:
	var axis: Vector3 = SIDE_AXIS[side]
	return _origin + axis * (HALF + ALCOVE_D / 2.0) \
		+ Vector3(axis.z, 0, axis.x) * (float(k) * ALCOVE_AT)


func crate() -> SprawlCrate:
	return _crate


func real_side() -> String:
	return _real_side


func dweller_has_run() -> bool:
	return _dweller_done


# E on the box. The prop has already started its lid; this is the level's half.
#
# ⚠️ THE SCARE IS `flash_scare`, WHICH IS SURVIVABLE AND ADDS NOTHING. No `add_panic()`, no
# `Screamer.trigger()`, no fail state, no rule. The user asked for the scare; whether it
# should carry a panic number is a decision returned to them rather than taken here, because
# a scare with a number attached can be optimised against and one without cannot
# (`GAME_MECHANICS_IDEAS.md` §0.2). The camera jolt is presentation, not cost.
func _on_crate_opened() -> void:
	crate_scare.emit()
	Screamer.flash_scare(CRATE_SCARE_IMAGE, CRATE_SCARE_AUDIO, CRATE_SCARE_HOLD)

	# ...and the thing that was in it leaves. Spawned a step out of the recess, facing the
	# hall, so it is never standing inside the geometry it came out of (Issue 59 — CSG
	# backfaces do not collide, so "inside a wall" is a placement bug you cannot ray your
	# way out of afterwards).
	var axis: Vector3 = SIDE_AXIS[_crate_side]
	var at: Vector3 = _alc_centre(_crate_side, _crate_k) - axis * DWELLER_OUT
	_dweller = SprawlDweller.build(self, "SprawlDweller", Vector3(at.x, _origin.y, at.z))
	if is_instance_valid(_crate):
		_dweller.adopt_voice(_crate.voice_players())
	_dweller.arrived.connect(_on_dweller_arrived)

	# ⚠️ IT DOES NOT SET OFF UNDER THE SCARE (2026-08-18). `flash_scare` puts a fullscreen
	# image over everything for `CRATE_SCARE_HOLD`, so a run started here is a run the
	# player cannot see — and the whole of the user's note is *"Force my camera to see that
	# action."* The start is deferred by exactly the image's own hold, and the level pins
	# the camera to it from `dweller_running`.
	#
	# ⚠️ `SceneTreeTimer` defaults to `process_always = true`, so a bare `create_timer()`
	# fires straight through a tree pause — a note or the journal opened in that window
	# would run the whole beat behind the overlay (the House's cellar child, 2026-08-16).
	# Pass false.
	var t := get_tree().create_timer(CRATE_SCARE_HOLD, false)
	t.timeout.connect(_start_the_run)


func _start_the_run() -> void:
	if not is_instance_valid(_dweller) or _dweller_done:
		return
	_dweller.run_to((_walls[_real_side] as Node3D).global_position)
	dweller_running.emit(_dweller)


# It went through that wall, and the wall keeps saying so — and the wall is now a way out.
func _on_dweller_arrived() -> void:
	_dweller_done = true
	if is_instance_valid(_dweller):
		_voice = _dweller.release_voice(_walls[_real_side])
	# ⚠️ THIS IS THE GATE OPENING, and it is the only place it opens. Everything else about
	# the beat is presentation; this line is the zone's win condition becoming reachable.
	_apply_gate()
	_mark_real_wall()
	dweller_arrived.emit()


# The seal, in one expression: before the runner has been through, the REAL wall is the only
# sealed one; afterwards, nothing is. The three fakes are never sealed — touching one is
# still a wrong answer and still costs `backrooms.gd:WRONG_WALL_PANIC`.
#
# ⚠️ Written as a sweep over all four rather than as "seal the new one, unseal the old one":
# `_randomise_real_wall()` can promote a REVIVED wall, and `revive()` rebuilds the trigger
# from scratch, so the only state that can be trusted is the one recomputed from `_real_side`.
func _apply_gate() -> void:
	for s in SIDES:
		var w: GlitchWall = _walls.get(s)
		if is_instance_valid(w):
			w.set_sealed(s == _real_side and not _dweller_done)


func real_wall_is_sealed() -> bool:
	var w: GlitchWall = _walls.get(_real_side)
	return is_instance_valid(w) and w.is_sealed()


# ⚠️ THE MARK IS MOTION AND A VOICE, NEVER BRIGHTNESS. The glitch wall is already the
# brightest surface in its room by 2.3x (measured), so light is not an available channel
# here; `set_agitated()` drives the shader's own vertex-jitter amplitude instead, and the
# whisper the player followed into the dark stays at the wall it left through.
func _mark_real_wall() -> void:
	for s in SIDES:
		var w: GlitchWall = _walls[s]
		if is_instance_valid(w):
			w.set_agitated(s == _real_side)
	_move_voice_to(_walls[_real_side])


func _move_voice_to(to: Node3D) -> void:
	for a in _voice:
		if not is_instance_valid(a) or not is_instance_valid(to):
			continue
		var node := a as Node3D
		if node.get_parent() == to:
			continue
		node.get_parent().remove_child(node)
		to.add_child(node)
		node.position = Vector3(0, 0, 0.4)
