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

# Audio. Everything that RECURS goes through one bus so a SilenceZone can duck the whole
# bed at once — and so nothing in this level can quietly out-shout the score from Master.
# The score leads; see the measured note on HUM_VOLUME_DB for how far, and why the gap
# between the two constants is not the answer.
# The three zones live at separate world offsets in this one scene; the glitch
# walls teleport between them. Far enough apart that no lighting or audio bleeds.
const ZONE2_ORIGIN := Vector3(200, 0, 0)
const ZONE3_ORIGIN := Vector3(-200, 0, 0)
# 18 was too steep against a 4-way guess in a zone where panic cannot decay: two
# wrong walls spent 72% of the bar before the Flood was even reached.
const WRONG_WALL_PANIC := 12.0

const AUDIO_BUS := "Backrooms"
const MUSIC_VOLUME_DB := -4.0
# ⚠️ Set these by MEASURING the files, not by reasoning about the gap between the two
# numbers (2026-08-15). "-4 vs -12, so the score leads by 8 dB" was never true: the hum
# is a dense synthesized noise bed at -8.3 dBFS RMS and the score is -18.0, so at -12 the
# hum was 1.7 dB ABOVE the music — and broadband noise masks music far better than the
# reverse. At -16 the score leads by ~2 dB measured, which is what the mix was after.
# Drop this to -20 for the full 6 dB lead if the hum still crowds it.
const HUM_VOLUME_DB := -16.0
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
	_spawn_seam_scrawls()    # BS1 — the "NO DOOR. / WALK INTO IT." scrawls
	_spawn_seam_beacons()    # BS1 — the two-layer positional tell, moved by _assign_round()
	_spawn_mirage_doors()
	_spawn_phone()
	_start_ambience()
	_build_later_zones()

	# Backrooms-only player rules: the maze forbids rest, and something walks behind you.
	_player.enable_standstill_panic()
	_player.enable_footstep_echo()

	_assign_round()
	_spawn_back_door()
	_black_background()
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
	# ⚠️ THE DROWNED go in the snapshot too (2026-08-17). Six searchable objects that are
	# silenced forever by being searched: without this, walking back from KONTUR for a roster
	# digit re-fills the wing with knocking from things the player has already emptied — the
	# same class of fault `MovedProp`'s "register applied moves or a back-door return un-moves
	# them" warning names. A death still wipes the whole snapshot, deliberately.
	var out := {"zone": _zone, "counter": _counter}
	if is_instance_valid(_zone3) and _zone3.has_method("searched_kinds"):
		out["flood_searched"] = _zone3.searched_kinds()
		# ⚠️ THE PUZZLE STATE GOES WITH IT (2026-08-17). Since the Flood's exit is gated on
		# six fragments, a snapshot that remembered which objects were emptied but not how
		# many fragments were in the frame would hand a returning player an unwinnable wing:
		# the objects are silent, and the plate is back to zero. Three numbers, all restored
		# together — emptied objects, fragments set, fragments still in hand.
		out["flood_set"] = _zone3.pieces_set()
		out["flood_held"] = _zone3.pieces_held()
	return out


func _restore_progress() -> void:
	var data := GameState.get_level_progress(4)
	if data.is_empty():
		return
	var zone: int = int(data.get("zone", 1))
	_counter = int(data.get("counter", 0))
	var searched: Array = data.get("flood_searched", [])
	var set_count: int = int(data.get("flood_set", 0))
	var held: int = int(data.get("flood_held", 0))
	if (not searched.is_empty() or set_count > 0) and is_instance_valid(_zone3) \
			and _zone3.has_method("restore_searched"):
		_zone3.restore_searched(searched, set_count, held)
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
	# THE BOX IN THE DARK (B-R3). ⚠️ The jolt is PRESENTATION and costs nothing: the zone
	# fires a survivable `flash_scare` and adds no panic, and whether that scare should
	# carry a number at all is a question this pass returned to the user rather than
	# answering (`GAME_MECHANICS_IDEAS.md` §0.2 — a scare with a number can be optimised
	# against; one without cannot). Do not add `add_panic()` here without that decision.
	_zone2.crate_scare.connect(func() -> void:
		if is_instance_valid(_player):
			_player.jolt_camera(0.12, 0.4))
	# ...and the level, which is the half that owns the player, forces the camera onto the
	# run. See `_tick_crate_watch()`.
	_zone2.dweller_running.connect(_on_dweller_running)
	_zone2.dweller_arrived.connect(_on_dweller_arrived)

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
			# ⚠️ IT USED TO READ "Only one is thin — listen for it" (2026-08-18). That was a
			# true instruction about the OLD zone, where the `water` + `whisper` tell at the
			# real wall was the route out. Since the crate became the gate, walking into the
			# real wall on the strength of that sound does nothing at all — so the line was
			# pointing at a door that is not open yet, which is worse than saying nothing.
			# The replacement names no verb and no place; the thing in the dark is calling
			# the whole time, and finding it is the puzzle.
			GameState.set_objective("Four walls tear. Something in here knows which one")
			# ⚠️ ISSUE 18 FIX, in the shipped game. `enable_standstill_panic()` is armed for
			# the WHOLE level (+3/s after 4 s still), and the Sprawl's tell is a sound you
			# have to stop and localise — on top of a floor-wide DreadZone. So the zone was
			# taxing the exact posture its own puzzle demands. Suspended here, restored on the
			# way into the Flood, whose tell is visual and where standing still is not asked
			# for. This REMOVES pressure; nothing in this pass adds any to the Backrooms.
			if is_instance_valid(_player) and _player.has_method("set_standstill_suspended"):
				_player.set_standstill_suspended(true)
		3:
			_teleport(_zone3.spawn_point)
			_announce("THE FLOOD")
			# ⚠️ ASK THE ZONE (2026-08-17). The Flood's objective is now a fragment counter
			# that ends at the old line, and it is written from three places — entry, every
			# fragment, and the back-door restore. `level_2.gd`'s OBJ_* consts exist because
			# exactly that drift shipped three times in the House.
			GameState.set_objective(_zone3.objective_text())
			if is_instance_valid(_player) and _player.has_method("set_standstill_suspended"):
				_player.set_standstill_suspended(false)


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
		# The room gets more crowded as you fail. ZERO extra panic — the mistake already
		# charges WRONG_WALL_PANIC, and a scare with no number attached cannot be optimised
		# against (SCARY.md §0.2). See congregation.gd.
		if _zone2.has_method("populate_one_more"):
			_zone2.populate_one_more()
	else:
		_teleport(_zone3.spawn_point)


# Zone name card on entry — reuses the progress label's presentation so the level
# keeps one visual voice.
#
# ⚠️ HELD BACK A FULL CARD LENGTH. The third down-turn now prints "(3/3)" on this same label
# in the SAME FRAME the zone is entered, and two tweens driving one font_colour override is a
# race the player loses either way — the completion they just earned would be blanked. The
# delay is what makes it a beat instead: (3/3) lands, holds, fades, and only then THE SPRAWL.
# See `_show_progress_text()` for why this is the card's full length and not a smaller number.
const CARD_FADE_IN := 0.3
const CARD_HOLD := 1.4
const CARD_FADE_OUT := 0.8
const CARD_LENGTH := CARD_FADE_IN + CARD_HOLD + CARD_FADE_OUT
const ZONE_CARD_DELAY := CARD_LENGTH

func _announce(title: String) -> void:
	_show_progress_text(title, ZONE_CARD_DELAY)


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
	#
	# ⚠️⚠️ THE ARM SPANS FROM THE HUB'S SOUTH EDGE (z = -HALF) OUT TO `lo`, NOT FROM THE HUB
	# CENTRE. It used to be centred at `(lo - HALF) / 2` with length `HALF - lo`, which is
	# the whole arm displaced 1.5 m (= HALF) south of where its own comment says it is. Two
	# consequences, both shipped for the life of the level:
	#
	#   * the two SIDE WALLS ran to z = +0.15 — i.e. 1.65 m INTO the hub, past its centre —
	#     so they stood across the southern half of the E and W arm mouths. Measured with
	#     the player's own capsule: the only way into the E arm was a 1.01 m slot against
	#     an 0.80 m capsule, a 0.21 m margin. The playtester photographed the hub and wrote
	#     "the spaces between columns to walk into are too small" (backlog 04 R2); a
	#     0.25 m reachability grid could not thread it either and called both Sprawl mirage
	#     doors unreachable as a false positive.
	#   * the floor and ceiling ran to z = 0 and overlapped the hub's slab over a 3 x 1.5 m
	#     patch — the coincident-face bug class (Issues 19/20/23). It was found by
	#     `check_wall_overlap.gd` (then a Backrooms wrapper) on 2026-08-17 and WAIVED as deliberate, on the
	#     strength of this function's own "overlapping the hub corner" comment. It was not
	#     deliberate; it was this arithmetic. The waiver is gone with it.
	#     ⚠️ There is no third symptom hiding behind the cap: the floor also ran 1.35 m PAST
	#     `EntryCap` into a sealed dead box, which is why nobody ever saw either fault.
	#
	# Same form as `_build_choice_arm()` now — one T/2 of overlap into the hub corner at one
	# end and T/2 past the cap at the other, which is what the corner post is made of.
	var lo := -7.0
	var span_mid := (-HALF + lo) / 2.0
	var span_len := (-HALF - lo) + T
	_slab("Entry", Vector3(0, 0, span_mid), Vector3(W, 0, span_len))
	# side walls at x = ±(HALF+T/2), running the arm length, overlapping the hub corner
	for sx in [1.0, -1.0]:
		_wall("EntryWall%s" % ("R" if sx > 0 else "L"),
			Vector3(sx * (HALF + T / 2.0), 0, span_mid),
			Vector3(T, 0, span_len))
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


const UTIL_DEPTH := 7.0   # utility room depth; _seam_face() derives the seam plane from it
const UTIL_WIDTH := 7.0

func _build_utility_room() -> void:
	# Dead-end room at the end of the N arm. Wider than the corridor, so a junction
	# front wall closes the width step (the fix-void rule). The far wall is the
	# seam-tearing glitch wall (the exit).
	var z0 := HALF + CHOICE_ARMS["N"].len   # front of the room (= N arm end)
	var z1 := z0 + UTIL_DEPTH                # back wall (glitch)
	var rw := UTIL_WIDTH                     # room width
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
		# ⚠️ THE THIRD TURN IS BANKED HERE (fixed 2026-08-17, backlog 04 B-A8). Two
		# loop-backs plus this walk IS the third down-turn, but the counter was never
		# incremented for it — so the HUD advertised three turns, printed (1/3) and (2/3),
		# and then cut straight to the zone card. Both playtest logs show the objective
		# stuck on (2/3) at the moment "THE SPRAWL" appears; (3/3) is never printed. A
		# progress meter that never completes reads as a bug, not as a reward.
		_counter = TURNS_TO_WIN
		_show_progress()
		_enter_zone(2)   # zone 1 cleared — the descent continues, it doesn't end
	else:
		_wrong_turn()


# ---------------------------------------------------------------- arrows

# ⚠️ REBUILT 2026-08-17 (backlog 04 B-A3). This is the level's ONLY navigational signal and
# a misread costs WRONG_TURN_PANIC (18 = 36 % of PANIC_MAX) and resets the counter to zero.
# Measured from real frames, the old sign was five separate faults at once:
#
#   glyph at 3 m ............... 120.7 lum
#   its own panel background ... 126.3 lum   -> 2.2 % contrast  (the information)
#   the column behind it ....... 153.9 lum   -> 22 % contrast   (the packaging)
#
#   * `arrow_decal.png` was a 1254x1254 PHOTOGRAPH OF YELLOW WALLPAPER with a slightly
#     darker arrow on it — a wall prop whose texture contains a picture of the surface it
#     is mounted on (Issue 35, X24's FIFTH recurrence, and the first one on a sign rather
#     than on decoration);
#   * it was RGB with NO ALPHA on a TRANSPARENCY_ALPHA material, so it rendered as a solid
#     rectangle and there was nothing for the cutout to cut;
#   * square source on a 0.45 x 0.70 quad = 1.556x vertical stretch;
#   * the quad was 0.45 m wide on a 0.28 m post, so 38 % of the sign hung in mid-air;
#   * it sat at exactly 0.02 m of clearance, check_wall_overlap.gd's bare minimum;
#   * and it was emissive at 0.25, which in a project with no tonemapping is most of a
#     surface's colour (Issues 21/27/33) — it lit the wallpaper background, i.e. the part
#     with no information in it.
#
# Now: a real RGBA cutout with NO background of its own (the post IS the background,
# tools/make_arrow_decal.py), sized from its own aspect, NO EMISSION AT ALL, and a post
# widened to carry it rather than a sign shrunk to fit — the sign is the thing that has to
# be readable at 15 m. The two constraints (wider than the post / too close to it) pull
# against each other, so both were resolved on the post's side.
const ARROW_TEX := TEX_DIR + "backrooms_arrow_glyph.png"
const ARROW_POST := 0.68     # square in plan. Was 0.28 — narrower than its own sign.
const ARROW_HEIGHT := 0.72   # the glyph's height in metres; width follows the art's aspect
const ARROW_CLEAR := 0.06    # air between glyph and post face — the house-style clearance
# ⚠️ HOW FAR THE POST IS BURIED IN THE JAMB IT STANDS AGAINST (2026-08-17, backlog 04 R2).
# Flush would put the post's far face and the wall's inner face in ONE PLANE — this
# project's most expensive bug class (Issues 19/20/23/24/25/26). Sinking it means the only
# faces the player can see are the three that stand proud of the wall.
const ARROW_BURY := 0.10

func _spawn_arrow_columns() -> void:
	# A pilaster just inside each choice-arm mouth, carrying an arrow decal facing
	# the hub centre so the player reads it on approach.
	#
	# ⚠️ AGAINST A JAMB, NOT ON THE CENTRELINE (2026-08-17, backlog 04 R2). It used to stand
	# dead centre in the mouth, which split a 3 m opening into two lanes and put a post in
	# the doorway of every choice the level asks you to make. The playtester photographed the
	# hub: "the spaces between columns to walk into are too small."
	#
	# ⚠️ THE ARROW IS THE LEVEL'S ONLY NAVIGATIONAL SIGNAL and a misread costs
	# WRONG_TURN_PANIC, so this move is constrained on three sides and none of them gave:
	#   * it stays AT the mouth, so it is read before the arm is committed to (the wrong-turn
	#     sensor is a further 1.0 m in — `check_backrooms_seam.gd` asserts that ordering);
	#   * it stays at eye height on the hub-facing face, at the same size, same cutout, same
	#     zero emission (the 92.7 % contrast measured in `_arrow_contrast()` is untouched);
	#   * the three land in THREE DIFFERENT CORNERS of the hub rather than two sharing one,
	#     so no arrow can be mistaken for its neighbour's. That is what `jamb` is for: the
	#     side clockwise from the arm as seen from above — N takes the NE corner, E the SE,
	#     W the NW.
	var aspect := 0.75
	if ResourceLoader.exists(ARROW_TEX):
		var t: Texture2D = load(ARROW_TEX)
		if t and t.get_height() > 0:
			aspect = float(t.get_width()) / float(t.get_height())
	for id in CHOICE_ARMS:
		var axis: Vector3 = CHOICE_ARMS[id].axis
		# Clockwise-neighbouring side, in plan: N(+z) -> +x, E(+x) -> -z, W(-x) -> +z.
		var jamb := Vector3(axis.z, 0.0, -axis.x)
		var col_pos: Vector3 = axis * (HALF - 0.05) \
			+ jamb * (HALF - ARROW_POST / 2.0 + ARROW_BURY)
		_box("ArrowCol%s" % id, Vector3(col_pos.x, H / 2.0, col_pos.z),
			Vector3(ARROW_POST, H, ARROW_POST), _wall_mat)
		# arrow quad on the hub-facing side of the column
		var quad := MeshInstance3D.new()
		# ⚠️ NAMED. These were three anonymous siblings, so every finding about them read
		# "@MeshInstance3D@50" and could not be asserted on (Issue 17's family).
		quad.name = "ArrowDecal%s" % id
		var mesh := QuadMesh.new()
		mesh.size = Vector2(ARROW_HEIGHT * aspect, ARROW_HEIGHT)
		quad.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 1.0
		if ResourceLoader.exists(ARROW_TEX):
			mat.albedo_texture = load(ARROW_TEX)
		else:
			# Flat stencil paint, same value as the artwork's ink.
			mat.albedo_color = Color(0.055, 0.051, 0.043)
		# ⚠️ NO emission_enabled anywhere in this function, deliberately. The contrast here
		# is albedo contrast against a hub-lit wallpaper post, and the hub lamp is never
		# switched off by _apply_dark_arm() (it only touches _arm_lights[arm_id]), so the
		# posts are lit on every round including the one whose arm went black.
		quad.set_surface_override_material(0, mat)
		# face the hub centre (-axis), lifted to eye height, just off the column
		var face := -axis
		quad.transform = Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)),
			col_pos + face * (ARROW_POST / 2.0 + ARROW_CLEAR) + Vector3(0, 1.6, 0))
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
	# The seam's voice follows the arrows. One source of truth for "which surface".
	_move_seam_beacons()
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
#
# `delay` holds a card back so a message already on screen gets its moment.
#
# ⚠️ TWO TWEENS DRIVING ONE `theme_override_colors/font_color` FIGHT, and the failure is
# silent: the loser's `.a = 0` lands on top of the winner's fade-in and blanks a message that
# is supposed to be readable. So exactly one of them may exist at a time, and the two cases
# are handled differently on purpose:
#
#   * delay == 0 — an IMMEDIATE message PRE-EMPTS. Kill whatever is running, swap the text now.
#   * delay  > 0 — a QUEUED card WAITS. It must NOT kill, because the thing it is waiting for
#     is precisely the message it would be killing. `ZONE_CARD_DELAY` is therefore `CARD_LENGTH`
#     — the full length of one card — so the two never overlap at all rather than merely
#     mostly not overlapping.
#
# ⚠️ The first version of this got it backwards: it killed in both cases, so the (3/3) it
# exists to make visible was set as text and then left at alpha 0 until it was replaced.
var _progress_tween: Tween = null

func _show_progress_text(text: String, delay: float = 0.0) -> void:
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
	var c: Color = _progress_label.get_theme_color("font_color")
	var tween := create_tween()
	if delay <= 0.0:
		if is_instance_valid(_progress_tween):
			_progress_tween.kill()
		_progress_tween = tween
		_progress_label.text = text
	else:
		tween.tween_interval(delay)
		# Swap the text at the START of this card's own fade-in, never when it was requested,
		# or the queued card overwrites the message it is meant to be waiting behind.
		tween.tween_callback(func() -> void: _progress_label.text = text)
	tween.tween_property(_progress_label, "theme_override_colors/font_color",
		Color(c.r, c.g, c.b, 0.9), CARD_FADE_IN)
	tween.tween_interval(CARD_HOLD)
	tween.tween_property(_progress_label, "theme_override_colors/font_color",
		Color(c.r, c.g, c.b, 0.0), CARD_FADE_OUT)


# ---------------------------------------------------------------- note / extras

# ⚠️ WIDTH only. The depth is derived from `backrooms_note.png`'s own aspect — a hard-coded
# pair is how a 3.97x stretch got into the Intro's gurney decal.
const NOTE_PAGE_W := 0.22

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

	# ⭐ THE PAGE IS A PAGE NOW (2026-08-18). Playtest capture 003, taken at the spawn:
	# *"Again, make the note more like the backrooms atmosphere"* — the word "again" is the
	# point; the Corridor's entrance note was rebuilt the day before for the identical
	# defect, and `tools/make_backrooms_note.py` is `make_vesper_note.py`'s direct child.
	#
	# It was an untextured `BoxMesh` — albedo (0.85, 0.82, 0.60), emission (0.50, 0.48,
	# 0.35) at 0.3 — i.e. a near-white self-lit slab, in a level whose wallpaper measures
	# mean luma 171.9/255. It was the brightest object in the frame it was photographed in.
	#
	# ⚠️ Art on a QUAD, never on a BoxMesh face (Issue 24), and the quad is sized from the
	# ARTWORK's own aspect (`check_art_aspect.gd` sweeps this level).
	# ⚠️ The sheet is still a real object rather than a floating decal: a thin `BoxMesh`
	# carries the edge and the paper quad sits 1 mm proud of its top face.
	# ⚠️ NOTE_TEXT is untouched — the complaint was the prop's appearance, and the artwork
	# letters the opening paragraph verbatim.
	var tex_path := TEX_DIR + "backrooms_note.png"
	var has_art: bool = ResourceLoader.exists(tex_path)
	var page_w := NOTE_PAGE_W
	var page_d := NOTE_PAGE_W / 1.0543
	if has_art:
		var tex: Texture2D = load(tex_path)
		if tex != null and tex.get_width() > 0:
			page_d = page_w * float(tex.get_height()) / float(tex.get_width())

	var note_mesh := MeshInstance3D.new()
	note_mesh.name = "NotePad"
	note_mesh.mesh = BoxMesh.new()
	(note_mesh.mesh as BoxMesh).size = Vector3(page_w * 0.97, 0.006, page_d * 0.97)
	var paper := StandardMaterial3D.new()
	# ⚠️ DARK, AND NOT EMISSIVE. The pad is the page's edge; the page's own tone is carried
	# by the artwork. Emission is most of a surface's colour here (no glow, no fog, light
	# energy ~0.45), so a lit pad would put a bright rim round a deliberately dim sheet.
	paper.albedo_color = Color(0.08, 0.07, 0.05)
	paper.roughness = 0.95
	note_mesh.set_surface_override_material(0, paper)
	note.add_child(note_mesh)

	if has_art:
		var page := MeshInstance3D.new()
		page.name = "NotePage"
		var qm := QuadMesh.new()
		qm.size = Vector2(page_w, page_d)
		page.mesh = qm
		page.rotation_degrees.x = -90.0        # lay it flat, facing up
		page.position.y = 0.004
		var page_mat := StandardMaterial3D.new()
		page_mat.albedo_texture = load(tex_path)
		page_mat.roughness = 0.95
		# The generated sheet is an RGBA cutout with the torn deckle edge keyed out.
		page_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# ⚠️ FAINTLY SELF-LIT, and through `EMISSION_OP_MULTIPLY`. Godot's default is ADD,
		# which lays a flat wash over the artwork and knocks the type out of it (Issue 81).
		# With MULTIPLY it is the paper's own tone that glows, and the paper is already
		# darkened to mean luma ~99 against the wallpaper's 171.9 — so the page reads as
		# something lying in the room rather than as a light in it. Well under 1.0, or it
		# clamps to flat white (Issue 21).
		page_mat.emission_enabled = true
		page_mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		page_mat.emission = Color(1.0, 0.96, 0.80)
		page_mat.emission_texture = load(tex_path)
		page_mat.emission_energy_multiplier = 0.45
		page.set_surface_override_material(0, page_mat)
		note.add_child(page)

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
	# own Gate 6 phone.
	#
	# ⚠️ KONTUR's LEVELS came with it, and they are Gate 6's levels, not this level's
	# (2026-08-15). At 0 dB / unit_size 12 the ring measured -19.3 dBFS RMS at the
	# emitter against the score's -22.0, i.e. the phone was ~3 dB LOUDER than the music
	# — from a source 3 m from the spawn point, with a 12 m unit size that barely
	# attenuates across the whole Lobby, on Master where no SilenceZone or HoldBreath dip
	# could touch it. KONTUR wants exactly that (its gate is "ignore the unmissable
	# phone"); here it buried the score the level is built around.
	#
	# Now UNDER the score, as rotary_phone.gd's own header always said the Backrooms ring
	# should be: -8 dB, a 8 m unit size so walking away actually quietens it, and on the
	# level's bed bus. The clip is unchanged, so the "I never heard it" fix stands.
	phone.ring_audio = "phone_ringing"
	phone.ring_volume_db = -8.0
	phone.ring_unit_size = 8.0
	phone.ring_bus = AUDIO_BUS
	add_child(phone)


# ---------------------------------------------------------------- THE SEAM HAS A VOICE
#
# ⚠️ BS1 (2026-08-17). The level's win verb is "walk into a blank wall", and zone 1 demands
# it THREE times before anything teaches it: twice at the E/W loop-back caps, once at the
# utility room. The caps are the worse half — they are built from `_wall_mat`, identical to
# every other wall in the level, and `_spawn_arm_sensors()` puts LoopBack{E,W} 0.30 m from
# the cap's inner face, so the turn only counts once you are a foot from a plain wallpapered
# dead end. The playtester stood still for 86 seconds, 6.2 m down the CORRECT arm, writing
# "many players might get confused that you need to go through the wall".
#
# ⚠️ THE TIMED GLOW WAS OFFERED AND DECLINED, and the measurements are why — do not re-pitch
# it. The glitch wall is ALREADY the brightest surface in its room by 2.3x (132.7 lum against
# side walls 56.9 / 58.9, ceiling 55.8, floor 51.9), and 10 % brighter than the corridor
# walls from the decision point 15 m back. Luminance is not the missing channel; a STATEMENT
# OF THE VERB is. And a glow on the glitch wall would not have helped at all where the
# capture was actually taken, which was a loop-back cap five metres short of the dead end.
#
# So: two channels, neither of them brightness and neither of them panic.
#   1. A two-layer POSITIONAL AUDIO cue on whichever surface this round wants — a far cue
#      that gives a bearing from the arm mouth, and a near confirm that only resolves in the
#      last few metres. This project has solved "a cue nobody can walk toward" twice in this
#      exact idiom (backrooms_zone2.gd:_randomise_real_wall, level_1.gd's dark-wing beacon),
#      and both times the first attempt was a single narrow-range emitter.
#   2. A SCRAWL in the level's existing hand, echoing the Lab's TRIAL 4 whiteboard, which
#      already shows a hatched slab with an arrow driven through it captioned "NO DOOR".
#
# ⚠️ A THIRD CHANNEL — drag marks on the carpet running into the surface — shipped here and
# was CUT on the verification replay (backlog 04 R3). See `_spawn_seam_scrawls()`.
#
# ⚠️ ONE emitter pair, moved to the round's target by `_assign_round()`. Three permanent
# beacons would be noise rather than a bearing, and the wrong arms are unreachable anyway
# (their mouth sensor ejects you first), so the singular cue is also the honest one.
#
# ⚠️ ZERO PANIC. Nothing here reads or writes the panic bar.
#
# ⚠️ AND IT MUST NOT MAKE ZONE 2 REDUNDANT. Zone 2's whole puzzle is "find the wall by
# sound", so this cue is deliberately UNMISSABLE AND SINGULAR — what it teaches is the VERB.
# Zone 2 keeps its difficulty entirely in DISCRIMINATION BETWEEN FOUR, which is a different
# skill, and its own tell stays two layers of a different sound (water + whisper).
const SEAM_FAR_AUDIO := "seam_draw"    # tools/make_sfx_seam.py — measured -12.7 dBFS RMS
const SEAM_NEAR_AUDIO := "seam_rip"    # ...and -20.8 dBFS RMS
# ⚠️ GAINS SET FROM THOSE MEASURED FILE LEVELS, not from numbers that read as sensible.
# The score is -18.0 dBFS at MUSIC_VOLUME_DB -4 => -22.0 dBFS effective. Far cue lands at
# -27.7 dBFS (5.7 dB under the score, about level with the hum, directional); near confirm
# at -26.8 dBFS but on a 5 m unit size, so it is ~-35 dBFS from the hub and ~-19 dBFS with
# your nose against the wall. Both stay under MUSIC_VOLUME_DB, which check_backrooms_audio
# asserts for every self-starting emitter near the player.
const SEAM_FAR_DB := -15.0
const SEAM_NEAR_DB := -6.0
const SEAM_FAR_UNIT := 16.0
const SEAM_NEAR_UNIT := 5.0
# ⚠️ MASTER, NOT the level's own bus — the same call, for the same reason, as
# backrooms_zone2.gd's water/whisper tell: a SilenceZone ducks AUDIO_BUS, and a tell routed
# through the bus a silence pocket ducks is a tell that mutes itself. Zone 1 has no
# SilenceZone today; the rule is about what a future one would do to it.
const SEAM_BUS := "Master"

var _seam_far: AudioStreamPlayer3D = null
var _seam_near: AudioStreamPlayer3D = null


# The world-space plane of the surface this arm asks you to walk into: the loop-back cap's
# inner face for E/W, the glitch wall for N. Derived, never a literal — the arm lengths and
# the utility room's depth are all constants above and have moved before.
func _seam_face(id: String) -> Vector3:
	var axis: Vector3 = CHOICE_ARMS[id].axis
	if id == "N":
		return Vector3(0, 0, HALF + CHOICE_ARMS["N"].len + UTIL_DEPTH - T / 2.0)
	return axis * (HALF + CHOICE_ARMS[id].len)


# Half the clear width of whatever the seam stands at the end of.
func _seam_half_width(id: String) -> float:
	return UTIL_WIDTH / 2.0 if id == "N" else HALF


func _spawn_seam_beacons() -> void:
	_seam_far = _make_beacon("SeamFar", SEAM_FAR_AUDIO, SEAM_FAR_DB, SEAM_FAR_UNIT)
	_seam_near = _make_beacon("SeamNear", SEAM_NEAR_AUDIO, SEAM_NEAR_DB, SEAM_NEAR_UNIT)


func _make_beacon(beacon_name: String, base: String, db: float, unit: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = beacon_name
	p.volume_db = db
	p.unit_size = unit
	p.bus = SEAM_BUS
	add_child(p)
	var s := GameState.load_audio(base)
	if not s:
		push_warning("Backrooms: seam beacon '%s' has no audio — the verb is untaught" % base)
		return p
	p.stream = s
	# ⚠️ Every .wav.import here is loop_mode=0, so the node restarts itself. Canonical form,
	# lifted from level_1.gd:_add_beacon_layer().
	p.finished.connect(p.play)
	p.play()
	return p


# Follow the round's answer. Called from _assign_round(), so the cue and the arrows can
# never disagree about which surface is live.
func _move_seam_beacons() -> void:
	if not is_instance_valid(_seam_far) or not is_instance_valid(_seam_near):
		return
	var into: Vector3 = CHOICE_ARMS[_correct].axis
	var at: Vector3 = _seam_face(_correct) - into * 0.25 + Vector3(0, 1.5, 0)
	_seam_far.position = at
	_seam_near.position = at


# THE NON-AUDIO STATEMENT OF THE VERB.
#
# ⚠️⚠️ THE FLOOR DRAG MARKS ARE DELETED AND MUST NOT COME BACK (2026-08-17, backlog 04 R3).
# Four dark scuffs used to run down the carpet into each seam surface — "something was
# dragged through here". The player judged them in two separate captures on one playthrough:
# *"These stripes look weird - remove them"* (001) and *"Yeah, remove the stripes. The hints
# on the walls are sufficient"* (003). Recorded in `GAME_MECHANICS_IDEAS.md` §5 so no future
# session re-pitches them.
#
# What survives is what the player named as sufficient: the `NO DOOR. / WALK INTO IT.` scrawl
# on the side wall, and the two-layer seam audio (`_spawn_seam_beacons()`), which is the tell
# they chose over making the glitch wall glow. `check_backrooms_seam.gd` asserts both, and
# asserts that NO node named `DragMark*` exists anywhere in the scene.
func _spawn_seam_scrawls() -> void:
	for id in CHOICE_ARMS:
		var face: Vector3 = _seam_face(id)
		var into: Vector3 = CHOICE_ARMS[id].axis
		var lateral := Vector3(into.z, 0.0, into.x)   # perpendicular in plan

		# The statement of the verb, on the SIDE wall rather than on the seam itself —
		# the seam is walk-through and tears open, and text riding a vertex-jitter shader is
		# text nobody can read. Same Label3D convention as _spawn_kontur_scrawl(): no new
		# texture, unshaded, constant-dark so the contrast survives any lighting the arm has.
		#
		# ⚠️ "NO DOOR" is quoted deliberately. The Lab's Observation whiteboard already shows
		# TRIAL 4 as boxes 1 -> 2 -> 3 and then a hatched slab with an arrow driven through
		# it, captioned NO DOOR. Two levels apart, the same two words: the hint stops being
		# decoration and becomes an instruction the player has already been given.
		var lbl := Label3D.new()
		lbl.name = "SeamScrawl%s" % id
		lbl.text = "NO DOOR.\nWALK INTO IT."
		lbl.font_size = 40
		lbl.pixel_size = 0.0032
		lbl.modulate = Color(0.10, 0.08, 0.07)
		lbl.outline_size = 0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var hw := _seam_half_width(id)
		lbl.position = face - into * 1.7 + lateral * (hw - 0.06) + Vector3(0, 1.75, 0)
		lbl.rotation.y = atan2(-lateral.x, -lateral.z)
		add_child(lbl)


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
	#
	# Delegates to AudioBuses rather than hand-rolling the add/name/send, which also
	# changes the ROUTING: this bus used to send straight to Master, so a global
	# HoldBreath dip of "Ambience" was inaudible in the one level that fires
	# flash_scare on every wrong turn and every wrong wall. It now nests under
	# Ambience, so the level's own SilenceZone duck and the global dip compose.
	AudioBuses.ensure(AUDIO_BUS)


func set_bed_volume_db(db: float) -> void:
	var idx := AudioServer.get_bus_index(AUDIO_BUS)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, db)


# ---------------------------------------------------------------- background
#
# ⚠️ SECOND LAYER OF DEFENCE AGAINST A HOLE IN THE SHELL (2026-08-17, backlog 04 R1).
#
# `assets/elements/environment.tscn` ships `background_mode = BG_SKY` over a
# `ProceduralSkyMaterial`, so ANY gap in a level's geometry renders as a blue-grey daylit
# horizon — the single most jarring thing that can appear in a windowless yellow maze. The
# Lab, the House and the Corridor each switched to a black background for exactly this
# reason (`level_1.gd:_boost_ambient()`, and the Corridor's `_black_background()`); the
# Backrooms never did, and when its Sprawl alcoves turned out to be open at the back, the
# player got a photograph of the sky (capture 004).
#
# The hole is fixed in `backrooms_zone2.gd`. This is the thing that makes the NEXT one a
# black rectangle instead of a window — a defect either way, but not one that shows the
# player they are standing in a box on an empty plane.
#
# ⚠️ AMBIENT IS HELD AT ITS SHIPPED VALUE, deliberately, because this level's difficulty is
# under active judgement. The scene's environment sets `ambient_light_color` (0.04,0.03,0.02)
# at energy 0.2 with `ambient_light_sky_contribution = 0.08` and no explicit source, i.e.
# 92 % colour and 8 % sky. Pinning the source to COLOR keeps the 92 % exactly as it is and
# drops only the 8 % — measured as a change of 0.0026 in linear ambient luminance, which is
# below anything the eye or the panic economy can register. It is NOT a lighting pass.
#
# ⚠️ `duplicate()` first. The `Environment` is a sub-resource of a shared PackedScene, so
# editing it in place would reach every other level that instances the same file.
func _black_background() -> void:
	var we: WorldEnvironment = get_node_or_null("Environment/WorldEnvironment")
	if not we or not we.environment:
		return
	var env: Environment = we.environment.duplicate()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment = env


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

func _process(delta: float) -> void:
	# Cheap fluorescent flicker: nudge a couple of random lit fixtures each frame.
	for _i in range(2):
		var f: Dictionary = _all_lights[randi() % _all_lights.size()]
		if f.light.visible:
			f.light.light_energy = f.base * randf_range(0.82, 1.04)

	_tick_crate_watch(delta)
	_catch_out_of_world()


# ================================================ FORCED TO WATCH THE RUN (2026-08-18)
#
# The user's own note, capture 004: *"it should run and go through the real wall ... Force
# my camera to see that action."* The run is the ONLY thing that tells you which of the four
# identical walls is real, and it is over in a few seconds — a player looking the wrong way
# when it happens has watched nothing and learned nothing.
#
# ⚠️ `player.turn_to_face()` IS THE MECHANISM, not a second one. `level_1.gd`'s nook reveal
# is the precedent: freeze input, tween the camera, release. The only difference is that the
# thing to look at MOVES, so the aim is refreshed on a cadence rather than set once —
# `turn_to_face()` kills its own previous tween, so re-calling it is a re-target rather than
# a stack of fighting tweens.
#
# ⚠️ `freeze_input()` DOES NOT STOP THE BODY. `_physics_process` still calls
# `move_and_slide()`, so a player frozen mid-stride coasts (Issue 49). Zero the velocity.
#
# ⚠️ AND IT HAS A BACKSTOP. `WATCH_MAX` is not a difficulty constant, it is a safety valve of
# the `CHILD_POSTPONE_MAX` kind: `dweller_arrived` is what releases the camera, and if the
# runner is ever freed or blocked, an un-released freeze is a player who can neither move nor
# look for the rest of the level. The crossing is 2.2-6.6 s measured (recess and wall are
# both randomised), so this is roughly double the worst case.
const WATCH_REAIM := 0.18       # s between re-targets — a re-aim cadence, not a tween rate
const WATCH_MAX := 12.0
# ⚠️ HELD PAST THE ARRIVAL. `SprawlDweller` emits `arrived` at the surface and only THEN
# fades out over 0.55 s while it carries on through — and the wall starts thrashing on the
# same frame. Releasing on `arrived` would hand control back at the exact moment the payoff
# renders, so the player's own first mouse movement would take the answer off the screen.
const WATCH_AFTER := 1.1

var _watching: Node3D = null    # the runner, or the wall it went through once it has landed
var _watch_t := 0.0
var _watch_reaim := 0.0
var _watch_after := 0.0
# The runner's origin is at its feet, so the aim point is chest height; a `GlitchWall`'s own
# origin is already the middle of the pane, so it needs none.
var _watch_offset := Vector3(0, 1.1, 0)

func _on_dweller_running(runner: Node3D) -> void:
	if not is_instance_valid(_player) or not is_instance_valid(runner):
		return
	_watching = runner
	_watch_offset = Vector3(0, 1.1, 0)
	_watch_t = 0.0
	_watch_reaim = 0.0
	_watch_after = 0.0
	_player.velocity = Vector3.ZERO
	_player.freeze_input()
	_player.turn_to_face(runner.global_position + Vector3(0, 1.1, 0), 0.45)


func _on_dweller_arrived() -> void:
	if _watching == null:
		return
	# Keep looking at the wall it left through, not at the space where it used to be.
	var wall: Node3D = null
	if is_instance_valid(_zone2):
		wall = (_zone2.get("_walls") as Dictionary).get(String(_zone2.call("real_side")))
	if is_instance_valid(wall):
		_watching = wall
		_watch_offset = Vector3.ZERO
	_watch_after = WATCH_AFTER


func _release_watch() -> void:
	if _watching == null:
		return
	_watching = null
	if is_instance_valid(_player):
		_player.unfreeze_input()


func _tick_crate_watch(delta: float) -> void:
	if _watching == null:
		return
	if not is_instance_valid(_player):
		_watching = null
		return
	_watch_t += delta
	if _watch_t > WATCH_MAX:
		push_warning("Backrooms: the crate run did not finish inside %.0f s — camera released"
			% WATCH_MAX)
		_release_watch()
		return
	if not is_instance_valid(_watching):
		_release_watch()
		return
	if _watch_after > 0.0:
		_watch_after -= delta
		if _watch_after <= 0.0:
			_release_watch()
			return
	_player.velocity = Vector3.ZERO
	_watch_reaim -= delta
	if _watch_reaim <= 0.0:
		_watch_reaim = WATCH_REAIM
		_player.turn_to_face(_watching.global_position + _watch_offset, WATCH_REAIM)


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
