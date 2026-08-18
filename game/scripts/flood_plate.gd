extends StaticBody3D
class_name FloodPlate

# THE PLATE TABLE — the Backrooms Flood's assembly point, and the middle step of the
# puzzle the user designed on 2026-08-17 (backlog 04 B-R1):
#
#   *"we say the way out does not show itself in the light: you need to collect 6 pieces
#   of puzzle contained in different items and collect the puzzle at the middle of the
#   level. Then, the exit will appear - but you can find it only after you turn off the
#   flashlight."*
#
# Six fragments come out of the six `SunkenItem`s; they are set into this frame; the real
# seam in the Sump wakes up. The darkness rule is untouched and is still the LAST step —
# the search is the route to it, not a replacement for it.
#
# ⚠️ IT MUST ANNOUNCE ITSELF, and that is not decoration. "Assemble it in the middle of
# the level" is a second thing to hunt for, in a near-black 28 m wing, with no tell of its
# own — which is precisely the failure `backrooms.gd`'s seam beacons were built to fix in
# zone 1 and `level_1.gd`'s were built to fix in the Lab's dark wing. Three channels, none
# of them a HUD readout (§5.2(2)) and none of them panic:
#
#   1. IT IS IN THE ONLY LIT ROOM. The Basin's lamp is the single light in the Flood, and
#      this stands 3.4 m from it — so it is the one object down here you can see without
#      the torch, which is also the posture the zone's own puzzle wants.
#   2. A WRITTEN INSTRUCTION on its own backboard: dark lettering on a pale board, the
#      House/Corridor convention. Not a Label3D floating in the dark — an unshaded label
#      is a self-lit object, which is anti-pattern §5.2(8) in the one zone about light.
#   3. A TWO-LAYER POSITIONAL TELL, `plate_hum` (far, unit 18 — a BEARING from anywhere in
#      the wing) + `plate_ring` (near, unit 5 — "you are here"). Armed by the FIRST
#      fragment, not by entering the zone: before you are carrying anything there is
#      nothing for it to say, and a permanent drone would bury the knocks that are how the
#      six objects are found.
#
# ⚠️ MASTER BUS, never the level's own. `SilenceZone` ducks `"Backrooms"`, and a tell
# routed through the bus a silence pocket ducks is a tell that mutes itself —
# `backrooms_zone2.gd`'s header is a post-mortem of exactly that mistake.
#
# ⚠️ GAINS FROM THE FILES' MEASURED LEVELS (`tools/make_sfx_backrooms_puzzle.py` prints
# them; do not invent a plausible number — `water.wav` shipped 20 dB too quiet for months
# because someone did):
#
#     plate_hum   -14.7 dBFS   at  -4.0      plate_set   -26.4 dBFS   at +2.0
#     plate_ring  -22.3 dBFS   at  -2.0      plate_done  -22.1 dBFS   at +2.0
#
# ⚠️ THE FAR CUE IS BRACKETED FROM BOTH SIDES, and `check_flood_puzzle.gd` measures both
# from the .wav files on disk, in every room:
#   * ABOVE the water bed it has to be heard through, everywhere in the wing — measured
#     -20.7 dBFS at the table down to -28.2 dBFS in the far corner, against a bed of
#     -36.6 dBFS. A bearing you cannot hear over the room you are standing in is not one.
#   * BELOW the `flood_haul` one-shot (-12.6 dBFS near), because a continuous loop that
#     out-shouts the events is the mistake `HUM_VOLUME_DB` was retuned for in this level.
#   * ...and it must have a GRADIENT. That comes from `unit_size`, not from volume_db: at
#     unit 18 the whole 28 m wing sat inside the near-field clamp and the "bearing" was
#     flat to 0.4 dB, at 8 it was 3.5 dB, and at 5 it falls 7.5 dB across the wing — which
#     is what a player can actually steer by. The near confirm is unit 3 and drops BELOW
#     the water bed by the far end, which is what makes the pair two layers rather than
#     two copies.
#
# ⚠️ ZERO PANIC, NO FAIL STATE, NO TIMER. Setting a fragment cannot go wrong, cannot be
# undone, and cannot be done in the wrong order. The only cost of the whole puzzle is the
# wall clock it spends against the zone's existing DREAD_DRIP, measured in
# `tests/probe_flood_search.gd` and reported rather than tuned.

signal set_requested
signal completed

const SLOTS := 6

const TOP := Vector3(1.55, 0.07, 0.86)
const TOP_Y := 0.86
const BOARD_H := 0.52

const FAR_AUDIO := "plate_hum"
const NEAR_AUDIO := "plate_ring"
const FAR_DB := -4.0
const NEAR_DB := -2.0
const FAR_UNIT := 5.0
const NEAR_UNIT := 3.0
# ⚠️ `max_db` IS THE NEAR-FIELD CEILING, AND IT IS THE CONSTANT THAT ACTUALLY DECIDES HOW
# LOUD THIS IS. Godot 4 adds `volume_db` to the distance attenuation and THEN clamps the
# sum to `max_db` — so inside `unit_size` every emitter in this game sits at exactly
# `max_db`, whatever its volume_db says, and the default +3 made a first draft of this loop
# land at -11.7 dBFS at the table: louder than the `flood_knock` that is how the six objects
# are found, and about level with the `flood_haul` one-shot. Ceiling here, gradient from
# `unit_size`.
const FAR_MAX_DB := -6.0
const NEAR_MAX_DB := -3.0
const TELL_BUS := "Master"

const SET_DB := 2.0
const DONE_DB := 2.0

const SCRAWL := "SIX PIECES.\nSET THEM HERE."

var _placed: int = 0
var _carried: int = 0
var _complete: bool = false
var _shards: Array[MeshInstance3D] = []
var _far: AudioStreamPlayer3D = null
var _near: AudioStreamPlayer3D = null
var _calling: bool = false


static func build(parent: Node, plate_name: String, pos: Vector3, yaw: float) -> FloodPlate:
	var p := FloodPlate.new()
	p.name = plate_name
	parent.add_child(p)
	p.position = pos
	p.rotation.y = yaw
	return p


func _ready() -> void:
	# Layer 1: it is furniture as well as an interactable, and the player must not walk
	# through a table. Mask 0 — it never moves, so it needs to collide with nothing.
	collision_layer = 1
	collision_mask = 0
	_build_table()
	_build_frame()
	_build_board()
	_build_collider()
	_build_tell()


# ---------------------------------------------------------------- construction
#
# ⚠️ BUILT FROM PARTS (Issue 35). Two rounds of playtest have photographed a flat box in
# this project and called it "a box that does not make any sense", and the last one was
# the Sprawl's alcove crate, in this very level. A table is trestles, a rail, a top with
# an overhang, and a raised backboard; a slab on four sticks is a slab on four sticks.

func _flat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _part(part_name: String, size: Vector3, pos: Vector3,
		mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _build_table() -> void:
	var steel := _flat(Color(0.22, 0.23, 0.24), 0.5, 0.55)
	var dark := _flat(Color(0.12, 0.12, 0.13), 0.2, 0.85)
	# Two trestles, each a foot, a post and a shoulder — a silhouette rather than a leg.
	for sx in [-1.0, 1.0]:
		_part("Foot%d" % int(sx), Vector3(0.14, 0.06, 0.72),
			Vector3(0.60 * sx, 0.03, 0.0), dark)
		_part("Post%d" % int(sx), Vector3(0.09, TOP_Y - 0.10, 0.09),
			Vector3(0.60 * sx, (TOP_Y - 0.10) / 2.0 + 0.06, 0.0), steel)
		_part("Shoulder%d" % int(sx), Vector3(0.16, 0.07, 0.56),
			Vector3(0.60 * sx, TOP_Y - 0.07, 0.0), steel)
	# The rail that makes the two trestles one object.
	_part("Rail", Vector3(1.16, 0.06, 0.08), Vector3(0, 0.34, 0.0), steel)
	# The top, standing PROUD of the trestles at both ends (the mattress rule).
	_part("Top", TOP, Vector3(0, TOP_Y, 0.0), steel)
	_part("TopLip", Vector3(TOP.x + 0.06, 0.03, 0.05),
		Vector3(0, TOP_Y - 0.03, -TOP.z / 2.0 - 0.01), dark)


# The frame the fragments go into: a shallow tray with six empty recesses, so the thing
# reads as unfinished before you have set anything in it.
func _build_frame() -> void:
	var frame := _flat(Color(0.30, 0.28, 0.25), 0.35, 0.6)
	var hollow := _flat(Color(0.05, 0.05, 0.06), 0.0, 1.0)
	var top := TOP_Y + TOP.y / 2.0
	var w := 1.20
	var d := 0.56
	for sx in [-1.0, 1.0]:
		_part("FrameSide%d" % int(sx), Vector3(0.05, 0.05, d + 0.10),
			Vector3(sx * (w / 2.0 + 0.02), top + 0.02, 0.0), frame)
	for sz in [-1.0, 1.0]:
		_part("FrameEnd%d" % int(sz), Vector3(w + 0.09, 0.05, 0.05),
			Vector3(0.0, top + 0.02, sz * (d / 2.0 + 0.02)), frame)
	for i in range(SLOTS):
		var c := _slot_pos(i, top)
		# The empty recess, and then the fragment that fills it (hidden until set).
		_part("Recess%d" % i, Vector3(0.34, 0.012, 0.24), c, hollow)
		var shard := _part("Shard%d" % i, Vector3(0.30, 0.020, 0.22),
			c + Vector3(0, 0.016, 0), _flat(Color(0.17, 0.18, 0.19), 0.35, 0.45))
		shard.visible = false
		_shards.append(shard)


func _slot_pos(i: int, top: float) -> Vector3:
	var col := i % 3
	var row := i / 3
	return Vector3((float(col) - 1.0) * 0.40, top + 0.03, (float(row) - 0.5) * 0.26)


# ⚠️ DARK LETTERING ON A PALE BOARD, not a pale label in the dark. Label3D is UNSHADED, so
# its modulate colour is its final colour — a bright one is a self-lit object, which is
# the anti-pattern this whole zone is built against. The board takes the Basin lamp; the
# text takes its contrast from the board.
func _build_board() -> void:
	var top := TOP_Y + TOP.y / 2.0
	var board := _part("Backboard", Vector3(TOP.x - 0.10, BOARD_H, 0.04),
		Vector3(0, top + BOARD_H / 2.0, TOP.z / 2.0 - 0.06),
		# ⚠️ Grimy, not white. Photographed at 0.46 under the Basin lamp it was the brightest
		# thing in the frame — a pristine board in a flooded ruin, and a beacon in the one
		# zone whose puzzle is about light. At 0.34 the dark lettering still holds ~3.7:1.
		_flat(Color(0.34, 0.33, 0.30), 0.0, 0.95))
	var lbl := Label3D.new()
	lbl.name = "PlateScrawl"
	lbl.text = SCRAWL
	lbl.font_size = 46
	lbl.pixel_size = 0.0030
	lbl.modulate = Color(0.09, 0.08, 0.07)
	lbl.outline_size = 0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# On the board's -Z face, i.e. the side the player approaches from.
	lbl.position = board.position + Vector3(0, 0, -0.035)
	lbl.rotation.y = PI
	add_child(lbl)


func _build_collider() -> void:
	var col := CollisionShape3D.new()
	col.name = "PlateCollision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(TOP.x, TOP_Y + TOP.y + BOARD_H, TOP.z)
	col.shape = shape
	col.position = Vector3(0, (TOP_Y + TOP.y + BOARD_H) / 2.0, 0)
	add_child(col)


func _build_tell() -> void:
	_far = _make_loop("PlateFar", FAR_AUDIO, FAR_DB, FAR_UNIT, FAR_MAX_DB)
	_near = _make_loop("PlateNear", NEAR_AUDIO, NEAR_DB, NEAR_UNIT, NEAR_MAX_DB)


func _make_loop(loop_name: String, base: String, db: float,
		unit: float, ceiling: float) -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.name = loop_name
	a.volume_db = db
	a.unit_size = unit
	a.max_db = ceiling
	a.bus = TELL_BUS
	add_child(a)
	a.position = Vector3(0, TOP_Y, 0)
	var s := GameState.load_audio(base)
	if not s:
		push_warning("FloodPlate: '%s' has no audio — the assembly point is silent" % base)
		return a
	a.stream = s
	# ⚠️ Every .wav.import here is loop_mode=0, so the node restarts itself. Canonical
	# form, lifted from level_1.gd:_add_beacon_layer().
	a.finished.connect(a.play)
	return a


# ---------------------------------------------------------------- state

# Armed by the first fragment, silenced for good by the sixth being set.
func begin_calling() -> void:
	if _calling or _complete:
		return
	_calling = true
	for a in [_far, _near]:
		if is_instance_valid(a) and a.stream:
			a.play()


func _stop_calling() -> void:
	_calling = false
	for a in [_far, _near]:
		if is_instance_valid(a):
			if a.finished.is_connected(a.play):
				a.finished.disconnect(a.play)
			a.stop()


func is_calling() -> bool:
	return _calling


func pieces_set() -> int:
	return _placed


func is_complete() -> bool:
	return _complete


# The zone tells the plate what the player is holding, so the prop can be genuinely INERT
# rather than merely refusing — `player.gd:_update_interact_prompt()`'s can_interact()
# opt-out. A table that offers "Press E" and then does nothing reads as a bug (the Lab
# locker's lesson, Issue 57).
func set_carried(n: int) -> void:
	_carried = n


func can_interact() -> bool:
	return not _complete and _carried > 0


func interact() -> void:
	if not can_interact():
		return
	set_requested.emit()


# Seat `n` fragments. Staggered, so setting three at once reads as three acts.
func seat(n: int) -> void:
	for i in range(n):
		if _placed >= SLOTS:
			break
		var shard: MeshInstance3D = _shards[_placed]
		_placed += 1
		var delay := 0.22 * float(i)
		var tw := create_tween()
		tw.tween_interval(delay)
		# Connected, never awaited (Issue 6).
		tw.finished.connect(func() -> void:
			if is_instance_valid(shard):
				shard.visible = true
			_play("plate_set", SET_DB))
	if _placed >= SLOTS and not _complete:
		_complete = true
		var done := create_tween()
		done.tween_interval(0.22 * maxf(1.0, float(n)) + 0.35)
		done.finished.connect(_finish)


func _finish() -> void:
	_stop_calling()
	_play("plate_done", DONE_DB)
	completed.emit()


# The restore path for a back-door return: silent, instant, no events.
func restore(n: int) -> void:
	for i in range(mini(n, SLOTS)):
		_shards[i].visible = true
	_placed = mini(n, SLOTS)
	if _placed >= SLOTS:
		_complete = true
		_stop_calling()


func _play(base: String, db: float) -> void:
	var s := GameState.load_audio(base)
	if not s:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = db
	p.unit_size = 8.0
	p.bus = TELL_BUS
	add_child(p)
	p.position = Vector3(0, TOP_Y, 0)
	p.finished.connect(p.queue_free)
	p.play()
