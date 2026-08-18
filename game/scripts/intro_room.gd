extends Node3D

const OPENING_NOTE := "You are Subject 47.\n\nThis is a psychological experiment. Your fear response is being monitored.\n\nThe entity you may encounter is a product of your own mind — it cannot harm you unless you believe it can.\n\nStay calm. Do not touch what you are not meant to touch.\n\nIf something calls out to you — a voice, a ringing, anything that asks for an answer — do not answer it. You are not meant to speak to anyone but us.\n\nThe door ahead is your first test.\n\nWe are watching."

const ENDING_NOTE := "This is not an experiment.\n\nThere is no exit.\n\nThey already know where you are."

const TEX := "res://assets/textures/intro/"
const BASE_ENERGY := 1.8

# The twist ending's reveal — the observation room behind the eight levels, closing the loop the
# Lab's Observation tape opens. It replaces a bare 2 s pause; see _on_ending_note_closed().
# ⚠️ It ends on ~1.5 s of black BY CONSTRUCTION, because `Screamer.trigger_to_menu()` fires the
# instant it finishes and needs somewhere dark to land. If the clip is ever regenerated, keep
# that tail (assets_src/README.md records how it is padded on in transcode).
const ENDING_VIDEO := "res://assets/video/ending_scene.ogv"

# Room + beat geometry (see INTRO.md for the full design). The room is a big,
# hand-placed asylum ward — same CSGBox3D style as the original small room, just
# scaled up — built at runtime, not baked into the .tscn (see PRESERVE below).
const ROOM_SIZE := Vector2(12.0, 18.0)     # x, z
const ROOM_HEIGHT := 3.6
const WAKEUP_TWEEN_TIME := 1.8
const NIGHTMARE_TEXT := "IT WAS ONLY A DREAM."
const PATH_GLOW_ENERGY := 0.12
const PATH_GLOW_RANGE := 1.4
const PATH_GLOW_Y := 0.35          # fixed low "ankle" height — not the switch's mounting height
const GURNEY_POS := Vector3(0, 0, 7.0)
const GURNEY_TOP_Y := 0.6           # frame top 0.5, mattress top 0.6 — see _build_gurney()
# The two occupied beds. GLIMPSE_GURNEY_POS is deliberately close to the middle ceiling
# tube — see _glimpse_light() for why that tube and not the far one.
const GLIMPSE_GURNEY_POS := Vector3(3.6, 0, 1.8)
const FAR_GURNEY_POS := Vector3(4.5, 0, 6.0)
# ⚠️ The inner face of a wall is HALF A WALL THICKNESS in from its nominal boundary. Every
# prop mounted on a wall in this room is derived from these two, never hand-computed — the
# exit door was placed at a literal z and ended up floating 0.275 m clear of WallBack for
# the life of the project (playtest 2026-08-16 capture #3: "the door is not connected to
# the wall"). RoomBuilder.wall_point() exists for exactly this reason in the graph levels;
# this room is hand-built, so it derives them here instead.
const WALL_T := 0.3
const WALL_BACK_FACE_Z := -ROOM_SIZE.y / 2.0 + WALL_T / 2.0    # -8.85
const WALL_LEFT_FACE_X := -ROOM_SIZE.x / 2.0 + WALL_T / 2.0    # -5.85
const WALL_RIGHT_FACE_X := ROOM_SIZE.x / 2.0 - WALL_T / 2.0    #  5.85
# How far a wall-mounted prop's BACK face sits inside the wall. Never 0 — coplanar faces
# z-fight (Issues 19/20/23); a small negative clearance buries the back face instead.
const WALL_BITE := 0.02
# ⚠️ Was a hand-written -5.77, which stood the 0.04-deep plate 0.060 m clear of WallLeft's
# inner face — the same defect as the exit door at a fifth of the scale, and the reason the
# plate shows a floating side edge in the 2026-08-16 capture. Centred here, its back face
# lands 10 mm INSIDE the wall (never coplanar), its face 30 mm proud, and light_switch.gd's
# art quad 36 mm clear of the wall — check_wall_overlap.gd wants at least 20 mm.
const SWITCH_POS := Vector3(WALL_LEFT_FACE_X + 0.01, 1.3, -1.0)
const TABLE_POS := Vector3(0, 0.4, 0.0)
# Panel extents; _corrupt_room() boards across this.
# ⚠️ WIDTH IS DERIVED FROM THE ARTWORK, not chosen (2026-08-15). `intro_lab_door.png` is
# 780x1511 after cropping, i.e. 1:1.937, and a texture squashed onto a mismatched quad is
# SCARY.md §7.1(4) — the same fault that made KONTUR's roster plate render as a stretched
# picture on a box. 2.2 / 1.937 = 1.136. Changing the height means changing the width too.
const DOOR_SIZE := Vector3(1.136, 2.2, 0.15)
# ⚠️ DERIVED, never a literal. The leaf's BACK face lands WALL_BITE inside WallBack, which
# is exactly the convention level_1.gd / level_2.gd / kontur.gd / dungeon.gd already use.
# It was a hand-written -8.5 until 2026-08-16 and the leaf floated 0.275 m clear of the
# wall, full height, full width, with open air behind it — measured with sideways rays at
# four heights, all clear. That also dragged the game's FINAL beat with it, because
# _corrupt_room()'s planks are derived from this constant (correctly) and inherited the
# error: they hung 0.485 m in front of blank concrete.
const EXIT_DOOR_POS := Vector3(0, 1.1, WALL_BACK_FACE_Z - WALL_BITE + DOOR_SIZE.z / 2.0)
# The casing — two jambs and a lintel standing proud of the wall, lapping CASING_LAP over
# the leaf's edges so the leaf reads as RECESSED INSIDE a frame rather than stuck on a flat
# wall. The lap is what removes every coplanar face between casing and leaf.
const CASING_W := 0.14              # jamb width / lintel height
const CASING_D := 0.24              # WALL_BITE inside the wall … 0.09 proud of the leaf face
const CASING_LAP := 0.018
const WHEELCHAIR_POS := Vector3(2.4, 0.0, -3.0)    # floor anchor — open floor between the table and the door
const WALL_CHART_POS := Vector3(3.5, 1.8, -8.77)   # on WallBack, clear of the door + its casing
# ⚠️ Sized from `wall_chart_intro.png` (1402x1122 = 1.2496), not chosen. At the old
# 0.6 x 0.9 the chart was squashed 1.87x onto a PORTRAIT quad and its text — a legible
# patient observation chart, the only readable environment storytelling in the room — was
# unreadable at any distance.
const WALL_CHART_SIZE := Vector2(1.125, 0.90)
# The torn page's own sub-rect inside `intro_note.png`'s square, black-backed canvas, and
# the sheet size derived from it: 0.297 * (0.835 / 0.970) = 0.2557. See _build_table_note_candle().
const NOTE_UV_OFFSET := Vector2(0.085, 0.015)
const NOTE_UV_SCALE := Vector2(0.835, 0.970)
const NOTE_SIZE := Vector2(0.2557, 0.297)
const NORMAL_AMBIENT := 0.22        # tuned in-editor; see the verification pass

# --- "the ward is occupied" (2026-07-28) ---------------------------------------------
# This room had ZERO scares: no panic source, no RandomAmbient, no ApparitionDirector, no
# objective line — 60-120 s of nothing, which is a full level's worth of dead air relative
# to everything after it. Everything added below is DREAD ONLY: the intro has never had a
# fail state and deliberately still doesn't, so nothing here calls add_panic().
const SWITCH_PRESSES := 2           # the first press does not work — see _on_switch_stuck
const STIFF_SWITCH_TEXT := "Press harder."   # the user's own wording, 2026-08-16
const GLIMPSE_ENERGY := 0.55        # weak, dying; the working reveal settles at 0.9
const GLIMPSE_TIME := 0.4           # how long the ward is visible before it goes again
const AMBIENT_MIN := 20.0           # level-local scare metronome, ZERO panic (not
const AMBIENT_MAX := 40.0           # RandomAmbient, which carries 5/8/12)
const BREATH_VOLUME_DB := -22.0     # the thing at the far wall you walked away from

# The wheelchair turns WHILE YOU WATCH, close up, with a sound (playtest 2026-07-28).
# ⚠️ This deliberately INVERTS SCARY.md P6's MovedProp rule, which only ever applies a delta
# while the player is >6 m away and facing elsewhere. The user's call, and the reasoning is
# that an anomaly nobody notices is worth less than an event they certainly see: P6's
# asymmetry ("if the player never notices, nothing happens") is a virtue in a level with
# something else going on, and a wasted beat in a 90-second tutorial room.
const WHEELCHAIR_TURN_DIST := 3.2   # must be close
const WHEELCHAIR_TURN_DOT := 0.55   # …and actually looking at it
const WHEELCHAIR_TURN_DEG := 34.0
const WHEELCHAIR_TURN_TIME := 1.1   # slow enough to read as turning, not as snapping
# Mix, not difficulty: see the measurements in _tick_wheelchair().
const WHEELCHAIR_SFX_DB := -7.6         # wheelchair.wav is 9.6 dB hotter than gurney_creak
const WHEELCHAIR_SFX_FADE_START := 1.1  # == WHEELCHAIR_TURN_TIME: full level for the whole turn
const WHEELCHAIR_SFX_FADE_TIME := 0.5   # then a settle tail, instead of the file's hard cut at 2.0 s

# Nodes that must survive a clear-and-rebuild pass. This scene is never reloaded
# mid-playthrough in the normal flow, but the twist ending reuses this same
# scene/script, so the pattern is genuinely exercised, not just precautionary.
const PRESERVE := ["Environment", "AmbientPlayer", "Player"]

const _DOOR_SCRIPT := preload("res://scripts/door.gd")
const _NOTE_SCRIPT := preload("res://scripts/note.gd")

@onready var player: CharacterBody3D = $Player

var candle_light: OmniLight3D
var note: Node

var _flicker_time: float = 0.0
var _red_light: OmniLight3D = null   # ending only: slow blood-red throb
var _candle_lit: bool = false        # gates _process()'s candle flicker until the switch flips
var _env: Environment = null
var _path_glow_lights: Array[OmniLight3D] = []
var _path_glow_audio: AudioStreamPlayer3D = null
var _ceiling_lights: Array[OmniLight3D] = []
var _switch_flipped: bool = false     # half of the exit lock; the note is the other half
var _far_breath: AudioStreamPlayer3D = null   # cut when the lights come on
var _ambient_timer: Timer = null              # level-local, zero-panic scare metronome
var _wheelchair_armed: bool = false           # armed when the note is read
var _wheelchair_turned: bool = false          # one-shot
var _glimpse_form: Node3D = null              # the sheeted form that is gone after the reveal
var _candle_flame: MeshInstance3D = null      # hidden while the room is dark — it is emissive
var _cobweb_index: int = 0                    # unique node names — Issue 17


func _ready() -> void:
	GameState.current_level = 0
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_clear_old_scene()

	_build_room()
	_build_gurney(GURNEY_POS)                    # the player's own — never occupied
	# ⚠️ Occupied. The two spare beds were bare, which made the ward read as storage; a
	# covered body on each makes it read as a ward with other subjects in it.
	#
	# ⚠️ This used to add "…and it is the strongest thing available at level 0's strictly
	# ordinary register — nothing supernatural, nothing that moves". That is no longer true
	# and was already not true when it was written: the WHEELCHAIR in this same room turns to
	# face you unaided, which is a larger breach of that register and was accepted on the
	# user's own call (2026-07-28). The empty bed below (2026-08-16) is a smaller one, and it
	# is unwitnessable by construction — no sound, no panic, no camera move, nothing looks at
	# the player, and it happens while the room is pitch black. See _on_switch_flipped().
	_build_gurney(FAR_GURNEY_POS, true)
	# The bed the glimpse shows, and the bed that is empty afterwards.
	_glimpse_form = _build_gurney(GLIMPSE_GURNEY_POS, true)
	_build_iv_stand(Vector3(0.8, 0, 6.5))
	_build_iv_stand(Vector3(4.4, 0, 1.0))        # beside the glimpse bed, inside the same pool
	_build_wheelchair()
	_build_wall_chart()
	_build_table_note_candle()
	_build_exit_door()
	_build_cabinets()
	_apply_textures()
	_spawn_cobwebs()
	_start_ambience()

	if GameState.is_ending:
		note.note_text = ENDING_NOTE
		NoteUI.closed.connect(_on_ending_note_closed, CONNECT_ONE_SHOT)
		_corrupt_room()
		return

	note.note_text = OPENING_NOTE
	_darken_scene(0.0)
	player.lock_flashlight()
	player.freeze_input()
	_play_wakeup_beat()


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


func _start_ambience() -> void:
	var ambient: AudioStreamPlayer = get_node_or_null("AmbientPlayer")
	if ambient:
		ambient.bus = AudioBuses.AMBIENCE   # duckable — see audio_buses.gd
		var s := GameState.load_audio("ambient_asylum")
		if s:
			ambient.stream = s
		if ambient.stream:
			ambient.finished.connect(ambient.play)
			ambient.play()


# ---------------------------------------------------------------- geometry

func _make_box(box_name: String, size: Vector3, pos: Vector3) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.name = box_name
	box.size = size
	box.position = pos
	box.use_collision = true
	add_child(box)
	return box


func _build_room() -> void:
	_make_box("Floor", Vector3(ROOM_SIZE.x, 0.3, ROOM_SIZE.y), Vector3(0, -0.15, 0))
	_make_box("Ceiling", Vector3(ROOM_SIZE.x, 0.3, ROOM_SIZE.y), Vector3(0, ROOM_HEIGHT + 0.15, 0))
	_make_box("WallBack", Vector3(ROOM_SIZE.x, ROOM_HEIGHT, 0.3), Vector3(0, ROOM_HEIGHT / 2.0, -ROOM_SIZE.y / 2.0))
	_make_box("WallFront", Vector3(ROOM_SIZE.x, ROOM_HEIGHT, 0.3), Vector3(0, ROOM_HEIGHT / 2.0, ROOM_SIZE.y / 2.0))
	_make_box("WallLeft", Vector3(0.3, ROOM_HEIGHT, ROOM_SIZE.y), Vector3(-ROOM_SIZE.x / 2.0, ROOM_HEIGHT / 2.0, 0))
	_make_box("WallRight", Vector3(0.3, ROOM_HEIGHT, ROOM_SIZE.y), Vector3(ROOM_SIZE.x / 2.0, ROOM_HEIGHT / 2.0, 0))

	# Ceiling fluorescents — off until the switch is flipped, then flickered up
	# in _on_switch_flipped(). No fixture mesh: this room reads as plain damp
	# concrete, not a lab with a distinct fitting texture.
	# ⚠️ Names are UNIQUE per tube. Three siblings all called "CeilingLight" meant Godot
	# renamed two of them to @OmniLight3D@NNN (Issue 17 — the same rename that silently
	# broke every door lookup in four levels), so only one was ever findable by name.
	# Nothing depended on it yet; a suffix costs nothing and keeps them addressable.
	for i in [0, 1, 2]:
		var z: float = [6.0, 0.0, -6.0][i]
		var light := OmniLight3D.new()
		light.name = "CeilingLight_%d" % i
		light.position = Vector3(0, ROOM_HEIGHT - 0.3, z)
		light.light_energy = 0.0
		light.light_color = Color(0.75, 0.8, 0.85)
		light.omni_range = 9.0
		light.shadow_enabled = true
		add_child(light)
		_ceiling_lights.append(light)


func _build_gurney(pos: Vector3, occupied: bool = false) -> Node3D:
	# ⚠️ Unique per bed, for the same Issue-17 reason as the ceiling tubes and the sheeted
	# forms: three gurneys all called "GurneyFrame" means Godot silently renames two of
	# them, and anything that looks one up by name finds only the first.
	var tag := "%.0f_%.0f" % [pos.x * 10.0, pos.z * 10.0]
	var frame := CSGBox3D.new()
	frame.name = "GurneyFrame_" + tag
	frame.size = Vector3(0.9, 0.5, 2.0)
	frame.position = pos + Vector3(0, 0.25, 0)
	frame.use_collision = true
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.12, 0.12, 0.13)
	fm.metallic = 0.6
	fm.roughness = 0.5
	frame.material = fm
	add_child(frame)

	var mattress := CSGBox3D.new()
	mattress.name = "GurneyMattress_" + tag
	mattress.size = Vector3(0.85, 0.1, 1.9)
	mattress.position = pos + Vector3(0, 0.55, 0)
	mattress.use_collision = true
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.35, 0.33, 0.3)
	mm.roughness = 0.9
	mattress.material = mm
	add_child(mattress)

	# The gurney art is a top-facing photo, not a texture wrapped around the box
	# (a BoxMesh/CSGBox3D crops instead of fitting a whole image to one face —
	# see the QuadMesh rule in CLAUDE.md). Sits a hair proud of the mattress top.
	#
	# ⚠️ ONLY on the empty bed (2026-08-16). Two reasons, both measured. (1) A covered bed
	# shows a SHEET, not a mattress — the drape in _build_sheeted_form() covers the whole
	# mattress, so this decal was rendering underneath something opaque. (2) The decal plane
	# sat at y=0.605 and the old sheet boxes spanned 0.600-0.800, so the art plane physically
	# cut through the bottom 5 mm of the body.
	if not occupied:
		var mtex_path := TEX + "gurney_intro.png"
		if ResourceLoader.exists(mtex_path):
			var decal := MeshInstance3D.new()
			decal.name = "GurneyMattressArt_" + tag
			var qm := PlaneMesh.new()
			# ⚠️ SIZED FROM THE MATTRESS, and the ART is what was made to match — see A6.
			# The source used to be a 1672x941 LANDSCAPE photo of a whole gurney (frame,
			# side rails, buckle straps and the concrete floor around it) squashed 3.97x
			# onto this portrait quad, i.e. a second, rotated, miniature gurney printed on
			# the bed. Playtest 2026-08-16 capture #2 read its two pads as "a pillow and a
			# blanket". It is now a plain stained pad at this quad's own aspect.
			qm.size = Vector2(0.85, 1.9)
			decal.mesh = qm
			decal.position = pos + Vector3(0, 0.605, 0)
			var dm := StandardMaterial3D.new()
			dm.albedo_texture = load(mtex_path)
			dm.roughness = 0.9
			decal.set_surface_override_material(0, dm)
			add_child(decal)

	if occupied:
		return _build_sheeted_form(pos)
	return null


# ── THE COVERED BODY ────────────────────────────────────────────────────────────────────
#
# ⚠️ ONE CONTINUOUS SMOOTH SURFACE — NOT BOXES, AND NOT MORE BOXES (2026-08-16, second
# revision). The history matters, because the first fix made it worse:
#
#   v1  two axis-aligned CSG boxes (a long low mound + a head bump 6 cm proud of it).
#       Playtest capture #2: *"Is it a human on the bed? Or a pillow and a blanket?"*
#   v2  eleven axis-aligned CSG boxes — head, shoulders, chest, abdomen, hips, thighs,
#       knees, shins, two feet, on a slab drape. Playtest capture: *"This still does not
#       look realistic."* It read as a STACK OF BLOCKS: every part was individually legible
#       as a discrete rectangular step with hard 90° corners, and — the thing that actually
#       killed it — their top faces were all horizontal planes taking identical light, so
#       from standing eye height the whole mass was one uniform flat bright shape.
#
# The lesson is structural, not a tuning miss: **axis-aligned boxes cannot make a draped
# organic mass.** More parts made the wrong silhouette more detailed. So this is built from
# a smooth field instead — the surface is a heightfield sampled from a soft union of
# ellipsoidal blobs (head / neck / shoulders / chest / waist / hips / two thighs / two knees
# / two shins / two feet), blended with a polynomial smooth-max so the features are IMPLIED
# by one continuous skin rather than stacked as steps. Normals are analytic central
# differences, so the shading is a gradient across the whole form and there is not a single
# flat facet on it.
#
# The same field carries the drape: outside a rounded-rectangle boundary the height plunges
# to a hem below the mattress line, which is what makes it read as cloth hanging off a bed
# rather than as an object sitting on one. Corner radius is why the sheet corners are round.
#
# ⚠️ Nothing here is axis-symmetric. A real body under a sheet is never square to the frame:
# the head is tipped off-centre, the shoulders sit slightly the other way, one knee is higher
# and further down the bed than the other, the feet splay, and the whole form carries a small
# yaw. That asymmetry is doing as much work as the curvature.
#
# ⚠️ NOT emissive, and a dull off-white rather than a bright one (Issues 21/27/33). At this
# room's light energy a pale emissive form would be the brightest thing in a pitch-dark ward
# — it would announce itself during the blind walk, and the point is that you do not see
# these until the lights come on and then nobody mentions it. The fabric texture multiplies
# DOWN into the same measured colour v2 shipped with; see SHEET_TINT.
#
# ⚠️ Never called for the player's own gurney: something solid on the bed you spawn lying
# on would push the player out of the world, and tests/check_spawn_blocked.gd asserts
# exactly that nothing invisible blocks a spawn.
#
# Returns the parent node, so the level can remove a whole form in one call (see B2 /
# _on_switch_flipped()).

# Sheet footprint. Xin/Zin are the flat top; beyond them the hem falls away over SKIRT_W,
# so the sheet is 1.02 x 2.10 m over a 0.85 x 1.9 mattress on a 0.9 x 2.0 frame.
#
# ⚠️ THE HEM MUST NOT REACH THE FRAME'S TOP FACE (y = 0.5, i.e. 0.10 below the mattress
# top) anywhere the sheet is still OVER the frame (|x| <= 0.45 and |z| <= 1.0). The worst
# point is the frame's own corner (0.45, 1.0), where the SDF is 0.051 -> 0.060 m of drop,
# 0.038 m of clearance. Every full-depth hem point is outside the frame in at least one
# axis, so it hangs free. Change SKIRT_W, HEM or CORNER_R and this needs re-checking —
# check_intro_geometry.gd asserts it.
const SHEET_XIN := 0.425
const SHEET_ZIN := 0.965
const SHEET_CORNER_R := 0.02       # cloth has no truly square corners, but see the frame
                                   # clearance note above — a big radius drops the CORNERS
                                   # early and pushes the hem through the frame's top face
const SHEET_SKIRT_W := 0.085       # horizontal run of the fall-off
const SHEET_HEM := 0.13            # how far below the mattress top the hem hangs
const SHEET_LIFT := 0.014          # the flat sheet rides this far above the mattress —
                                   # never 0, which would be coplanar (Issues 19/20/23)
const SHEET_CELL := 0.024          # sampling resolution; ~44 x 89 vertices per bed
const SHEET_SMOOTH_K := 0.052      # blob blend radius — the "one skin" knob. ⚠️ Too large
                                   # and the neck pinch and the gap between the legs are
                                   # smoothed away, which is most of what makes it a body
const SHEET_WRINKLE := 0.0035       # cloth undulation; small, but it is what stops the flat
                                   # areas rendering as a single uniform plane
const SHEET_YAW_DEG := 1.8         # nothing in this room is perfectly square to the frame
const SHEET_TINT := Color(0.553, 0.560, 0.591)   # DERIVED — see _sheet_material()

# cx, cz, rx, rz, height. Supine, head toward -z, ~1.72 m crown to sole.
#
# ⚠️ THE BODY MUST BE NARROW ENOUGH TO LEAVE A GUTTER. The first draft gave the shoulders
# rx 0.37 against a mattress half-width of 0.425, so the mound reached almost the full width
# of the bed and the sheet never came back down to the mattress on either side — measured, it
# rendered as *a mattress with a slight bulge*, which is the v1 complaint again. Measured on
# the current numbers, the sheet is back down to 0.02 m by |x| = 0.24 at every station: a
# 0.19 m flat gutter each side, and that gutter is what tells the eye the mound is a body
# lying ON the bed rather than the bed itself.
#
# ⚠️ NOTHING MAY BE TALLER THAN IT IS WIDE. A blob whose height exceeds its radius renders
# as a CONE, and a render of an earlier pass had two of them at the foot of the bed: it read
# as a ridge of rock, not a person. The extremities are the ones that go wrong, because they
# are the small features. Measured side silhouette on these numbers, crown to sole:
#   head 0.203 · neck 0.104 · shoulders 0.228 · chest 0.253 · waist 0.172 · hips 0.221
#   · thighs 0.175 · knees 0.140 · shins 0.108 · foot tent 0.164
#
# ⚠️ ONE foot tent, not two. Two separate foot blobs made two spikes; a real sheet spans the
# toes as a single peak, and that peak at the end of the bed is the whole morgue image.
#
# ⚠️ CLOTH BRIDGES CONCAVITIES; it does not dive into them. Two leg blobs alone put a
# 55-degree-per-side crevasse down the middle of the legs — measured, adjacent vertices'
# normals 110 degrees apart, which is a crease, not a fold. The wide, low blob at
# (−0.004, 0.605) IS the sheet spanning between the legs: it fills the valley floor to
# 0.117 while leaving the two leg ridges at 0.140/0.128, and it takes the worst normal
# split anywhere on the top of the sheet down to 71 degrees. (A box corner is 90 and two
# coincident faces are 180 — see check_intro_sheet.gd, which asserts this.)
const SHEET_BLOBS := [
	[ 0.030, -0.700, 0.150, 0.185, 0.205],   # head, tipped to one side
	[ 0.018, -0.550, 0.100, 0.090, 0.105],   # neck — the pinch that makes the head a head
	[-0.012, -0.415, 0.255, 0.190, 0.230],   # shoulders, the widest point
	[-0.015, -0.215, 0.230, 0.305, 0.252],   # chest, the highest
	[-0.005,  0.020, 0.195, 0.260, 0.176],   # waist — a dip, not a step
	[ 0.000,  0.220, 0.235, 0.250, 0.220],   # hips
	[-0.098,  0.420, 0.175, 0.300, 0.175],   # thigh L
	[ 0.092,  0.432, 0.169, 0.300, 0.167],   # thigh R, a touch further down the bed
	[-0.094,  0.640, 0.148, 0.200, 0.140],   # knee L, the raised one
	[ 0.084,  0.662, 0.142, 0.195, 0.129],   # knee R
	[-0.089,  0.762, 0.124, 0.180, 0.108],   # shin L
	[ 0.079,  0.775, 0.118, 0.175, 0.101],   # shin R
	[-0.004,  0.605, 0.245, 0.315, 0.118],   # ⚠️ THE SHEET SPANNING THE LEGS — see below
	[-0.006,  0.855, 0.148, 0.105, 0.165],   # the foot tent — both feet, one peak
]


func _build_sheeted_form(pos: Vector3) -> Node3D:
	# Unique per bed, for the same Issue-17 reason as the ceiling tubes.
	var tag := "%.0f_%.0f" % [pos.x * 10.0, pos.z * 10.0]
	var form := Node3D.new()
	form.name = "SheetedForm_" + tag
	# Origin AT the mattress top (frame top 0.5, mattress top 0.6), so every height below is
	# stated as a height above the bed rather than as a world y.
	form.position = pos + Vector3(0, GURNEY_TOP_Y, 0)
	form.rotation.y = deg_to_rad(SHEET_YAW_DEG)
	add_child(form)

	var mi := MeshInstance3D.new()
	mi.name = "SheetSurface"
	mi.mesh = _build_sheet_mesh()
	mi.set_surface_override_material(0, _sheet_material())
	form.add_child(mi)

	# ⚠️ ONE collider, and it is a plain box, not the surface. The gurney frame and mattress
	# under this are already solid, so the only thing a collider here changes is whether you
	# can walk your face through the mound — and a 4 000-triangle trimesh collider for that
	# would be absurd. v2 put collision on the drape slab for the same reason.
	var body := StaticBody3D.new()
	body.name = "SheetCollider"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.66, 0.19, 1.84)
	shape.shape = box
	shape.position = Vector3(0, 0.095, 0)
	body.add_child(shape)
	form.add_child(body)

	return form


# Polynomial smooth maximum. `k` is the blend width in metres: at k=0 this is max().
func _smax(a: float, b: float, k: float) -> float:
	var h: float = clampf(0.5 + 0.5 * (a - b) / k, 0.0, 1.0)
	return lerpf(b, a, h) + k * h * (1.0 - h)


# Signed distance to the rounded rectangle that bounds the flat top of the sheet.
# Negative inside, 0 on the boundary, positive out in the skirt.
func _sheet_sdf(x: float, z: float) -> float:
	var qx: float = absf(x) - (SHEET_XIN - SHEET_CORNER_R)
	var qz: float = absf(z) - (SHEET_ZIN - SHEET_CORNER_R)
	var outside := Vector2(maxf(qx, 0.0), maxf(qz, 0.0)).length()
	return outside + minf(maxf(qx, qz), 0.0) - SHEET_CORNER_R


# Height of the sheet above the mattress top at (x, z).
func _sheet_height(x: float, z: float) -> float:
	var h := SHEET_LIFT
	for b in SHEET_BLOBS:
		var dx: float = (x - b[0]) / b[2]
		var dz: float = (z - b[1]) / b[3]
		var q: float = dx * dx + dz * dz
		if q >= 1.0:
			continue
		# (1-q)^2 * (1 + 0.9q): a bell with ZERO tangent at the rim, so a blob melts into
		# the sheet instead of meeting it at a crease. An ellipsoid dome (sqrt) has a
		# vertical rim and would put a hard edge round every feature — the v2 failure in
		# curved form.
		var t: float = 1.0 - q
		h = _smax(h, b[4] * t * t * (1.0 + 0.9 * q), SHEET_SMOOTH_K)

	# Cloth undulation. Two incommensurate wavelengths so it never reads as a pattern.
	h += SHEET_WRINKLE * (sin(7.3 * x + 4.1 * z + 0.7) * 0.6
		+ sin(5.1 * z - 2.2 * x + 2.3) * 0.4
		+ sin(11.7 * x + 1.1) * 0.25)

	# The hem. `t^1.7` has zero slope where it leaves the mattress (a rounded fold) and is
	# still accelerating downward at the hem (cloth hanging, not a chamfer).
	var d := _sheet_sdf(x, z)
	if d > 0.0:
		var t: float = clampf(d / SHEET_SKIRT_W, 0.0, 1.0)
		# A hem that varies a little along its length reads as cloth; a dead-level one
		# reads as a machined edge.
		var hem: float = SHEET_HEM * (1.0 + 0.16 * sin(9.0 * z + 1.3) + 0.10 * sin(11.0 * x))
		h -= hem * pow(t, 1.7)
	return h


# A heightfield surface over the sheet's footprint, with ANALYTIC normals (central
# differences), so every triangle is smooth-shaded from the field rather than flat-shaded
# from its own plane.
#
# ⚠️ INDEXED, and every quad is emitted. A first pass skipped quads whose centre lay past
# the hem, to get rounded sheet corners — and the skipped cells left a SAWTOOTH along the
# whole front hem, clearly visible in the first render. The outline is a plain rectangle
# now; the corner droop comes from the SDF instead, which is what a real sheet corner does.
func _build_sheet_mesh() -> ArrayMesh:
	var xg: float = SHEET_XIN + SHEET_SKIRT_W
	var zg: float = SHEET_ZIN + SHEET_SKIRT_W
	var nx := int(ceil(2.0 * xg / SHEET_CELL))
	var nz := int(ceil(2.0 * zg / SHEET_CELL))
	var e := SHEET_CELL * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in range(nz + 1):
		for ix in range(nx + 1):
			var x: float = -xg + 2.0 * xg * float(ix) / float(nx)
			var z: float = -zg + 2.0 * zg * float(iz) / float(nz)
			var dhdx: float = (_sheet_height(x + e, z) - _sheet_height(x - e, z)) / (2.0 * e)
			var dhdz: float = (_sheet_height(x, z + e) - _sheet_height(x, z - e)) / (2.0 * e)
			st.set_normal(Vector3(-dhdx, 1.0, -dhdz).normalized())
			# One texture tile per metre, so the weave stays square on a 1.02 x 2.10 sheet.
			st.set_uv(Vector2(x + 0.5, z + 0.5))
			st.add_vertex(Vector3(x, _sheet_height(x, z), z))

	var stride := nx + 1
	for iz in range(nz):
		for ix in range(nx):
			var i0: int = iz * stride + ix
			var i1: int = i0 + 1
			var i2: int = i0 + stride + 1
			var i3: int = i0 + stride
			st.add_index(i0)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i3)

	var mesh := ArrayMesh.new()
	st.commit(mesh)
	return mesh


func _sheet_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 0.97
	m.metallic = 0.0
	# ⚠️ Two-sided. The surface is a single skin with an open hem, so the underside of the
	# fall is visible at grazing angles; culling it would show a hole in the sheet.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var path := TEX + "sheet_linen.png"
	if ResourceLoader.exists(path):
		m.albedo_texture = load(path)
		# ⚠️ The tint is DERIVED, not chosen. `sheet_linen.png` has a measured mean of
		# sRGB(0.804, 0.777, 0.688); multiplied in LINEAR space by SHEET_TINT that lands on
		# sRGB(0.440, 0.430, 0.400) — exactly the flat colour the previous version shipped
		# with and which the playtest never complained about. Same discipline as the gurney
		# pad regeneration (A6): match what shipped, do not guess a new brightness. Emission
		# stays at zero; a self-lit sheet in a pitch-dark ward would give the beds away
		# during the blind walk (Issues 21/27/33).
		m.albedo_color = SHEET_TINT
	else:
		m.albedo_color = Color(0.44, 0.43, 0.40)
	return m


# Thin pole + small "bag" + flat base — enough silhouette to read as an IV stand
# without needing a texture (per the grill-me decision: too simple a shape to
# justify one).
func _build_iv_stand(pos: Vector3) -> void:
	var pole := CSGCylinder3D.new()
	pole.name = "IVStandPole"
	pole.radius = 0.02
	pole.height = 1.4
	pole.position = pos + Vector3(0, 0.7, 0)
	pole.use_collision = true
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.55, 0.55, 0.58)
	pm.metallic = 0.7
	pm.roughness = 0.4
	pole.material = pm
	add_child(pole)

	var base := CSGCylinder3D.new()
	base.name = "IVStandBase"
	base.radius = 0.16
	base.height = 0.03
	base.position = pos + Vector3(0, 0.015, 0)
	base.material = pm
	add_child(base)

	var bag := MeshInstance3D.new()
	bag.name = "IVStandBag"
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.16
	bag.mesh = sm
	bag.position = pos + Vector3(0, 1.42, 0)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.75, 0.7, 0.4, 0.75)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bag.set_surface_override_material(0, bm)
	add_child(bag)


# Full 3D CSG build — same level of detail as _build_gurney()/_build_cabinets(),
# replacing the earlier flat billboard cutout (which read as visibly 2D from an
# angle). Wheels are CSGCylinder3D tipped on their side: the default cylinder
# axis is local Y (stands like a can), so rotation.z=90 lays it over onto a
# horizontal axis — the flat round faces then point left/right, like a real
# wheel, instead of up/down.
func _build_wheelchair() -> void:
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.1, 0.09, 0.09)
	frame_mat.metallic = 0.75
	frame_mat.roughness = 0.45

	var fabric_mat := StandardMaterial3D.new()
	fabric_mat.albedo_color = Color(0.16, 0.13, 0.11)
	fabric_mat.roughness = 0.9

	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.5, 0.48, 0.45)
	rim_mat.metallic = 0.8
	rim_mat.roughness = 0.4

	var wc := Node3D.new()
	wc.name = "Wheelchair"
	wc.position = WHEELCHAIR_POS
	add_child(wc)

	var seat := CSGBox3D.new()
	seat.size = Vector3(0.46, 0.05, 0.46)
	seat.position = Vector3(0, 0.48, 0)
	seat.use_collision = true
	seat.material = fabric_mat
	wc.add_child(seat)

	var back := CSGBox3D.new()
	back.size = Vector3(0.46, 0.5, 0.05)
	back.position = Vector3(0, 0.74, -0.23)
	back.use_collision = true
	back.material = fabric_mat
	wc.add_child(back)

	# Armrests + their support posts (front + back, tying them to the seat).
	for sx in [-1.0, 1.0]:
		var arm := CSGBox3D.new()
		arm.size = Vector3(0.035, 0.045, 0.42)
		arm.position = Vector3(sx * 0.25, 0.62, -0.02)
		arm.material = frame_mat
		wc.add_child(arm)
		var post_front := CSGCylinder3D.new()
		post_front.radius = 0.014
		post_front.height = 0.14
		post_front.position = Vector3(sx * 0.25, 0.55, 0.18)
		post_front.material = frame_mat
		wc.add_child(post_front)
		var post_back := CSGCylinder3D.new()
		post_back.radius = 0.014
		post_back.height = 0.24
		post_back.position = Vector3(sx * 0.25, 0.6, -0.22)
		post_back.material = frame_mat
		wc.add_child(post_back)
		# Seat-to-axle side rail.
		var rail := CSGBox3D.new()
		rail.size = Vector3(0.03, 0.03, 0.5)
		rail.position = Vector3(sx * 0.25, 0.3, -0.05)
		rail.material = frame_mat
		wc.add_child(rail)

	# Big rear wheels + hand rims.
	for sx in [-1.0, 1.0]:
		var wheel := CSGCylinder3D.new()
		wheel.radius = 0.27
		wheel.height = 0.035
		wheel.rotation_degrees.z = 90.0
		wheel.position = Vector3(sx * 0.28, 0.27, -0.1)
		wheel.use_collision = true
		wheel.material = frame_mat
		wc.add_child(wheel)
		var rim := CSGCylinder3D.new()
		rim.radius = 0.22
		rim.height = 0.015
		rim.rotation_degrees.z = 90.0
		rim.position = Vector3(sx * 0.30, 0.27, -0.1)
		rim.material = rim_mat
		wc.add_child(rim)

	# Small front casters + their forks.
	for sx in [-1.0, 1.0]:
		var caster := CSGCylinder3D.new()
		caster.radius = 0.06
		caster.height = 0.03
		caster.rotation_degrees.z = 90.0
		caster.position = Vector3(sx * 0.19, 0.06, 0.21)
		caster.material = frame_mat
		wc.add_child(caster)
		var fork := CSGCylinder3D.new()
		fork.radius = 0.012
		fork.height = 0.14
		fork.position = Vector3(sx * 0.19, 0.13, 0.21)
		fork.material = frame_mat
		wc.add_child(fork)

	# Footrest.
	var footrest := CSGBox3D.new()
	footrest.size = Vector3(0.36, 0.025, 0.11)
	footrest.position = Vector3(0, 0.11, 0.3)
	footrest.material = frame_mat
	wc.add_child(footrest)
	var footrest_post := CSGCylinder3D.new()
	footrest_post.radius = 0.012
	footrest_post.height = 0.3
	footrest_post.position = Vector3(0, 0.25, 0.3)
	footrest_post.material = frame_mat
	wc.add_child(footrest_post)


# Same PlaneMesh + rotation.x=-90 pattern, mounted on WallBack (a Z-normal wall —
# deliberately not a side wall, which would need a different, unverified
# rotation axis to avoid the image rendering sideways).
func _build_wall_chart() -> void:
	var tex_path := TEX + "wall_chart_intro.png"
	if not ResourceLoader.exists(tex_path):
		return
	var chart := MeshInstance3D.new()
	chart.name = "WallChart"
	var qm := PlaneMesh.new()
	qm.size = WALL_CHART_SIZE
	chart.mesh = qm
	chart.rotation_degrees.x = 90.0
	chart.position = WALL_CHART_POS
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(tex_path)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	chart.set_surface_override_material(0, mat)
	add_child(chart)


func _build_table_note_candle() -> void:
	var table := CSGBox3D.new()
	table.name = "Table"
	table.size = Vector3(1.2, 0.8, 0.6)
	table.position = TABLE_POS
	table.use_collision = true
	const TABLE_MAT_PATH := "res://assets/materials/objects/table.tres"
	if ResourceLoader.exists(TABLE_MAT_PATH):
		table.material = load(TABLE_MAT_PATH)
	add_child(table)

	_build_candle()

	# Matches level_1.gd:_make_note()'s exact ordering: the note is added to the
	# tree (triggering note.gd's _ready()) before its mesh/collision children are
	# attached — this is the proven-working pattern elsewhere in the project.
	note = StaticBody3D.new()
	note.name = "Note"
	note.set_script(_NOTE_SCRIPT)
	note.position = TABLE_POS + Vector3(0, 0.4, 0)
	add_child(note)

	# Slab for edge/depth + a QuadMesh for the art (CLAUDE.md rule — a BoxMesh
	# crops instead of showing the whole texture per face; door.gd:build_visual()
	# is the house pattern). The note had no texture applied at all until now —
	# note.gd's _style_mesh() runs in _ready(), before this mesh exists (see the
	# add-to-tree-before-children comment above), so it never touched it.
	var note_slab := MeshInstance3D.new()
	var nbm := BoxMesh.new()
	nbm.size = Vector3(NOTE_SIZE.x, 0.005, NOTE_SIZE.y)
	note_slab.mesh = nbm
	var slab_mat := StandardMaterial3D.new()
	slab_mat.albedo_color = Color(0.7, 0.67, 0.58)
	note_slab.set_surface_override_material(0, slab_mat)
	note.add_child(note_slab)

	var note_face := MeshInstance3D.new()
	note_face.name = "NoteFace"   # addressed by tests/check_art_aspect.gd
	# PlaneMesh lies flat facing +Y by default — no rotation needed, same
	# technique _build_gurney()'s mattress art uses.
	var nqm := PlaneMesh.new()
	nqm.size = NOTE_SIZE
	note_face.mesh = nqm
	note_face.position = Vector3(0, 0.0035, 0)
	var note_mat := StandardMaterial3D.new()
	var note_tex_path := TEX + "intro_note.png"
	if ResourceLoader.exists(note_tex_path):
		var ntex := load(note_tex_path)
		note_mat.albedo_texture = ntex
		note_mat.emission_enabled = true
		note_mat.emission_texture = ntex
		note_mat.emission_energy_multiplier = 0.5
		# ⚠️ UV-CROPPED TO THE PAPER (2026-08-16). `intro_note.png` is a 1254x1254 SQUARE
		# canvas with the torn page photographed on a black backdrop, and it was mapped
		# whole onto a 0.21 x 0.297 A4 quad — so the sheet was squashed 1.41x AND wore a
		# black mat around it. Sampling the page's own sub-rect fixes both at once and
		# needs no new asset: the effective source aspect becomes 0.835 / 0.970 = 0.861,
		# which is what NOTE_SIZE is derived from.
		note_mat.uv1_scale = Vector3(NOTE_UV_SCALE.x, NOTE_UV_SCALE.y, 1.0)
		note_mat.uv1_offset = Vector3(NOTE_UV_OFFSET.x, NOTE_UV_OFFSET.y, 0.0)
	else:
		note_mat.albedo_color = Color(0.85, 0.82, 0.7)
	note_face.set_surface_override_material(0, note_mat)
	note.add_child(note_face)

	var note_col := CollisionShape3D.new()
	var nbs := BoxShape3D.new()
	nbs.size = Vector3(NOTE_SIZE.x, 0.005, NOTE_SIZE.y)
	note_col.shape = nbs
	note.add_child(note_col)

	# note.gd emits `read` on OPEN (not on close — reading to the end is a mechanic
	# reserved for trap notes), which is the same hook level_1.gd uses to unlock the
	# Records locker. Not connected during the twist ending: that note's job is to end
	# the game, and _corrupt_room() has already deleted the exit door by then.
	if not GameState.is_ending:
		note.read.connect(_on_intro_note_read)


# ⚠️ There was NO CANDLE (2026-08-16). `_build_table_note_candle()` created a `Table`, a
# `Note` and an `OmniLight3D` called `CandleLight` — and no mesh at all. The light hung
# 2.2 m above the table, a metre below the ceiling, with nothing under it. The
# hand-built .tscn had a candle before this room was rebuilt procedurally; the rebuild kept
# the light and lost the emitter, and nobody noticed because the light never came on either
# (see _on_switch_flipped()).
#
# ⚠️ The FLAME is the one legitimately self-lit thing in this room, and it is capped well
# under 1.0 with a dark albedo (Issues 21/27/33): above 1.0 emission clamps to flat white,
# and the actual illumination is the OmniLight's job, not the mesh's.
const CANDLE_XZ := Vector2(0.3, 0.0)   # on the table top, clear of the note at x=0
const TABLE_TOP_Y := 0.8               # table centre 0.4, height 0.8

func _build_candle() -> void:
	var base := Vector3(TABLE_POS.x + CANDLE_XZ.x, TABLE_TOP_Y, TABLE_POS.z + CANDLE_XZ.y)

	var wax := StandardMaterial3D.new()
	wax.albedo_color = Color(0.60, 0.56, 0.46)
	wax.roughness = 0.85

	# ⚠️ No colliders anywhere in the candle. It stands 0.3 m from the note, and a body
	# here would answer the interaction raycast before the note does.
	var collar := CSGCylinder3D.new()
	collar.name = "CandleCollar"
	collar.radius = 0.045
	collar.height = 0.022
	collar.position = base + Vector3(0, 0.011, 0)
	collar.material = wax
	add_child(collar)

	var stub := CSGCylinder3D.new()
	stub.name = "CandleStub"
	stub.radius = 0.032
	stub.height = 0.16
	# Overlaps the collar rather than sitting on it — no coplanar faces.
	stub.position = base + Vector3(0, 0.095, 0)
	stub.material = wax
	add_child(stub)

	var wick := CSGCylinder3D.new()
	wick.name = "CandleWick"
	wick.radius = 0.004
	wick.height = 0.045
	wick.position = base + Vector3(0, 0.19, 0)
	var wick_mat := StandardMaterial3D.new()
	wick_mat.albedo_color = Color(0.06, 0.05, 0.04)
	wick_mat.roughness = 1.0
	wick.material = wick_mat
	add_child(wick)

	var flame := MeshInstance3D.new()
	flame.name = "CandleFlame"
	var sm := SphereMesh.new()
	sm.radius = 0.017
	sm.height = 0.055
	flame.mesh = sm
	flame.position = base + Vector3(0, 0.222, 0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.30, 0.12, 0.03)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.62, 0.22)
	fm.emission_energy_multiplier = 0.85
	flame.set_surface_override_material(0, fm)
	add_child(flame)
	# ⚠️ Tracked so _darken_scene() can hide it. It is the only emissive surface in the
	# room, and an emissive mesh is visible with every light in the world switched off —
	# a lit-looking candle throwing no light would give the blind fumble a landmark it is
	# not supposed to have, and would flatly contradict the twist ending's dead candle.
	_candle_flame = flame

	candle_light = OmniLight3D.new()
	candle_light.name = "CandleLight"
	# ⚠️ AT the flame, not 2 m over it. The tube above the table is deliberately left dead
	# in _on_switch_flipped() "so the note is lit by the candle alone" — for that sentence
	# to be true the candle has to actually be where the candle is.
	candle_light.position = base + Vector3(0, 0.235, 0)
	candle_light.light_color = Color(1, 0.58, 0.18, 1)
	candle_light.light_energy = BASE_ENERGY
	candle_light.shadow_enabled = true
	candle_light.omni_range = 5.5
	add_child(candle_light)


func _on_intro_note_read() -> void:
	GameState.intro_note_read = true
	# Observation only, and optional: DebugLog is a playtest autoload that CLAUDE.md says
	# can be removed from project.godot outright, so this must never be a hard reference.
	# It exists because "did they read the note?" was unanswerable from the 2026-08-16 log,
	# and the exit is sealed until they do.
	var dbg := get_node_or_null("/root/DebugLog")
	if dbg and dbg.has_method("note"):
		dbg.note("INTRO note read — exit lock half two satisfied")
	_refresh_exit_lock()
	_arm_wheelchair()


# The wheelchair turns to face the table — and you WATCH it happen.
#
# It has stood at WHEELCHAIR_POS since this room was rebuilt, fully modelled, doing nothing.
# It sits in the open floor between the table and the door, so the walk from reading the note
# to leaving passes it.
#
# Armed on the note being read, then fired by proximity: the player has to be within
# WHEELCHAIR_TURN_DIST **and looking at it**, so unlike the MovedProp version this cannot be
# missed. It turns over WHEELCHAIR_TURN_TIME with a metal creak.
#
# ⚠️ Rotation only, no translation. Wheeling it across the floor would need clearance checks
# against the table and the door; a 34° turn cannot collide with anything and is the more
# unsettling read anyway — nothing moved, something is facing you.
func _arm_wheelchair() -> void:
	_wheelchair_armed = true


func _tick_wheelchair() -> void:
	if not _wheelchair_armed or _wheelchair_turned:
		return
	var wc := get_node_or_null("Wheelchair") as Node3D
	if not wc or not player:
		return
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	if not cam:
		return
	# ⚠️ HORIZONTAL-ONLY, both tests (2026-08-16). The facing test below was already
	# horizontal for the stated reason; the DISTANCE test was not, and that made the beat
	# unreachable. The camera sits 1.65 m above the chair's floor anchor, so a full-3D
	# radius of WHEELCHAIR_TURN_DIST 3.2 is really sqrt(3.2^2 - 1.65^2) = 2.741 m of floor
	# — and the walk from the note to the exit door passes the chair at 3.0 m. It could not
	# fire at any yaw, and the 2026-08-16 playtest is the log of it not firing. The chair
	# also moved x 3.0 -> 2.4 (WHEELCHAIR_POS) so the clearance is ~0.8 m rather than a
	# knife-edge 0.2: a beat that only fires on a perfect line is worse than one that never
	# fires, because nobody can tell it is broken. WHEELCHAIR_TURN_DIST is unchanged.
	var to_it := wc.global_position - cam.global_position
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	to_it.y = 0.0
	if to_it.length() > WHEELCHAIR_TURN_DIST:
		return
	if fwd.length() < 0.01 or to_it.length() < 0.01:
		return
	if fwd.normalized().dot(to_it.normalized()) < WHEELCHAIR_TURN_DOT:
		return

	_wheelchair_turned = true
	# ⚠️ THE SOUND OUTLASTS THE MOTION, ON PURPOSE, AND IS FADED RATHER THAN TRUNCATED.
	# `wheelchair.wav` is a user-supplied sample (2026-08-16), measured: 2.009 s, mono
	# 44.1 kHz, and it does NOT decay — its last 0.1 s is still at -1.3 dBFS RMS, i.e. the
	# file ENDS at full level. The turn is WHEELCHAIR_TURN_TIME 1.1 s. Three options and why
	# this one:
	#   * stop it at 1.1 s -> a creak that ends the instant the chair does, which reads as a
	#     recording being cut, and the brief's own rule is that a creak finishing before the
	#     motion is worse than no creak;
	#   * let it run to 2.009 s -> a hard cut at full amplitude 0.9 s after the chair stops;
	#   * FADE_START/FADE_TIME: full level for the whole turn, then a 0.5 s decay under the
	#     settle. The caster is still complaining after the chair has stopped moving, which is
	#     what a real one does.
	# A gain envelope is a mix decision, not a pitch-shift or a time-stretch (the brief
	# forbids those, and neither is used).
	#
	# ⚠️ GAIN IS SET FROM THE FILE'S MEASURED LEVEL, not from a plausible number. The old
	# `gurney_creak` fallback is -11.9 dBFS RMS and was played here at +2.0 dB; wheelchair.wav
	# is -2.3 dBFS RMS, i.e. 9.6 dB hotter, so 2.0 - 9.6 = -7.6 lands at the same loudness.
	# Same rule as the Flood's water bed (CLAUDE.md, Level 4 zone 3).
	var s := GameState.load_audio("wheelchair")
	if not s:
		# Degrade rather than error, matching the rest of this file: the intro's own
		# metal-on-metal creak is the closest existing thing to a caster under load.
		s = GameState.load_audio("gurney_creak")
	if s:
		var p := AudioStreamPlayer3D.new()
		p.name = "WheelchairTurnSfx"
		p.stream = s
		p.volume_db = WHEELCHAIR_SFX_DB
		p.unit_size = 4.0
		p.position = wc.position
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
		# Connected, never awaited (Issue 6): an awaited timer dies with whatever started it.
		var fade := create_tween()
		fade.tween_interval(WHEELCHAIR_SFX_FADE_START)
		fade.tween_property(p, "volume_db", WHEELCHAIR_SFX_DB - 40.0,
			WHEELCHAIR_SFX_FADE_TIME)
		fade.tween_callback(p.queue_free)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(wc, "rotation:y", wc.rotation.y + deg_to_rad(WHEELCHAIR_TURN_DEG),
		WHEELCHAIR_TURN_TIME)


# The exit opens only once the room is lit AND the briefing has been read. Kept in one
# place so neither half can silently stop mattering, the way KONTUR's exit did before
# Issue 16 gave it a ledger.
func _refresh_exit_lock() -> void:
	var exit_door := get_node_or_null("ExitDoor")
	if not exit_door:
		return
	if not _switch_flipped:
		exit_door.locked_message = "Find the light switch first."
		exit_door.extra_lock = true
		return
	if not GameState.intro_note_read:
		exit_door.locked_message = "Read the note on the table first."
		exit_door.extra_lock = true
		return
	exit_door.extra_lock = false


func _build_exit_door() -> void:
	var body := StaticBody3D.new()
	body.name = "ExitDoor"  # _corrupt_room() looks this up by name — keep it exact
	body.set_script(_DOOR_SCRIPT)
	body.unlock_condition = _DOOR_SCRIPT.UnlockCondition.NONE
	body.advances_level = true
	# The door glows blood-red (findable in the dark, per project convention) and
	# would otherwise be walkable the instant the player wakes up, skipping the
	# whole dark-fumble/switch/reveal beat entirely — extra_lock seals it until
	# BOTH the switch is thrown and the note is read, same mechanism KONTUR uses
	# for its exit.
	#
	# ⚠️ The note half is BACKLOG #12: "you can access level 1 without reading the
	# intro note. It cannot be that way." That note is not flavour — it is where the
	# player is told they are Subject 47, told the rules the whole game then enforces
	# ("Stay calm", "do not touch what you are not meant to touch"), and warned in
	# advance not to answer the Backrooms phone. Walking past it makes several later
	# levels read as arbitrary cruelty.
	body.extra_lock = not GameState.is_ending
	body.locked_message = "Find the light switch first."
	body.position = EXIT_DOOR_POS
	add_child(body)

	# ⚠️ Was `""` for the life of the project — the ONLY door in a textured level with no
	# art, so the first door the player ever sees rendered as a flat red box at emission
	# 1.5 while every later level had a real door. The textured branch of
	# `door.gd:door_material()` drops emission to 0.08 by itself; do not raise it (Issue
	# 21 — at 0.5 the red swamps the steel and the door renders salmon pink).
	_DOOR_SCRIPT.build_visual(body, DOOR_SIZE, TEX + "intro_lab_door.png")

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(DOOR_SIZE.x, DOOR_SIZE.y, 0.2)
	col.shape = shape
	body.add_child(col)

	_build_door_casing()


# The jambs and lintel that make the leaf read as a door SET INTO the wall.
#
# Seating the leaf correctly (EXIT_DOOR_POS) stops it floating, but a flush panel on a flat
# wall still reads as a panel: a real opening has a frame around it and the leaf sits back
# inside that frame. These three boxes are the whole difference, and they cost nothing.
#
# ⚠️ SIBLINGS of ExitDoor, never children. _corrupt_room() frees ExitDoor by name, and the
# boarded-over ending wants the frame to survive — planks nailed across a doorway need a
# doorway to be nailed across.
#
# ⚠️ NO COLLIDERS. A collider on the only doorway wall is this project's documented way of
# silently sealing a room (the Lab's Records warning sign did exactly that). The leaf has
# its own collider and the wall behind is solid, so these are visual only.
func _build_door_casing() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.12, 0.12)
	mat.metallic = 0.35
	mat.roughness = 0.8

	var z := WALL_BACK_FACE_Z - WALL_BITE + CASING_D / 2.0
	var half_in := DOOR_SIZE.x / 2.0 - CASING_LAP     # jamb inner face, lapping over the leaf
	var lintel_y := DOOR_SIZE.y - CASING_LAP + CASING_W / 2.0

	# ⚠️ Every junction here OVERLAPS rather than abuts, and each overlap is named:
	#   * the jambs run UP INTO the lintel (top at lintel_y, lintel spans lintel_y ± W/2)
	#   * the lintel OVERHANGS the jambs by CASING_LAP, so no side face is ever coplanar
	#   * the jambs run WALL_BITE below the floor, so no bottom face is coplanar with it
	# Two coplanar visible faces is this project's single most common bug class.
	for spec in [
		["DoorJambL", Vector3(CASING_W, lintel_y + WALL_BITE, CASING_D),
			Vector3(-(half_in + CASING_W / 2.0), lintel_y / 2.0 - WALL_BITE / 2.0, z)],
		["DoorJambR", Vector3(CASING_W, lintel_y + WALL_BITE, CASING_D),
			Vector3(half_in + CASING_W / 2.0, lintel_y / 2.0 - WALL_BITE / 2.0, z)],
		["DoorLintel", Vector3(2.0 * (half_in + CASING_W + CASING_LAP), CASING_W, CASING_D),
			Vector3(0, lintel_y, z)],
	]:
		var mi := MeshInstance3D.new()
		mi.name = spec[0]
		var bm := BoxMesh.new()
		bm.size = spec[1]
		mi.mesh = bm
		mi.position = spec[2]
		mi.set_surface_override_material(0, mat)
		add_child(mi)


# ⚠️ REBUILT 2026-08-16 (Issue 24 / Issue 35). `cabinet_intro.png` is a 1672x941 LANDSCAPE
# front elevation of a WIDE two-door medical cabinet — glazed panels, visible bottles,
# hinges, a keyhole. It was applied straight onto the material of a 0.6 x 1.8 x 0.5
# CSGBox3D, which does two wrong things at once:
#   * a box does not map a whole texture per face, it renders a magnified CROP (Issue 24 —
#     the exit doors did exactly this until they were split into slab + quad)
#   * the carcass was a TALL NARROW locker turned side-on (0.6 deep, 0.5 wide), so it
#     presented a 0.5 m sliver to the room and the art disagreed with the object entirely
# The carcass now matches what the art depicts, and the art lives on a QuadMesh sized from
# its own aspect, inset inside the carcass edge so the body reads as a frame around a door.
const CABINET_SIZE := Vector3(0.45, 0.90, 1.60)     # depth (into the room), height, width
const CABINET_ART := Vector2(1.4215, 0.80)          # 1.4215 / 0.80 = 1.7769 = 1672 / 941
const CABINET_ART_PROUD := 0.03

func _build_cabinets() -> void:
	var cabinet_tex_path := TEX + "cabinet_intro.png"
	var cabinet_tex: Texture2D = load(cabinet_tex_path) if ResourceLoader.exists(cabinet_tex_path) else null
	var half_d := CABINET_SIZE.x / 2.0
	# x is derived from the wall face, never written down — see WALL_BACK_FACE_Z's comment.
	var left_x := WALL_LEFT_FACE_X - WALL_BITE + half_d
	var right_x := WALL_RIGHT_FACE_X + WALL_BITE - half_d
	var y := CABINET_SIZE.y / 2.0
	# [position, facing] — facing is the outward normal of the front face, +1 = +x.
	var specs := [
		[Vector3(left_x, y, 4.0), 1.0],
		[Vector3(right_x, y, 2.0), -1.0],
		[Vector3(right_x, y, -4.0), -1.0],
	]
	for i in range(specs.size()):
		var pos: Vector3 = specs[i][0]
		var facing: float = specs[i][1]
		var body := CSGBox3D.new()
		body.name = "Cabinet%d" % i
		body.size = CABINET_SIZE
		body.position = pos
		body.use_collision = true
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.14, 0.16, 0.14)
		bm.metallic = 0.4
		bm.roughness = 0.7
		body.material = bm
		add_child(body)

		if not cabinet_tex:
			continue
		var art := MeshInstance3D.new()
		art.name = "CabinetArt%d" % i
		var qm := QuadMesh.new()
		qm.size = CABINET_ART
		art.mesh = qm
		# A QuadMesh faces +Z; rotating +90 deg about Y turns that to +X, and its own width
		# axis lands along z, which is the axis the carcass is wide on.
		art.rotation.y = facing * PI / 2.0
		art.position = pos + Vector3(facing * (half_d + CABINET_ART_PROUD), 0, 0)
		var am := StandardMaterial3D.new()
		am.albedo_texture = cabinet_tex
		am.metallic = 0.3
		am.roughness = 0.75
		art.set_surface_override_material(0, am)
		add_child(art)


func _apply_textures() -> void:
	var wall_tex: Texture2D = load(TEX + "intro_wall.png") if ResourceLoader.exists(TEX + "intro_wall.png") else null
	var floor_tex: Texture2D = load(TEX + "floor_intro.png") if ResourceLoader.exists(TEX + "floor_intro.png") else null
	var ceiling_tex: Texture2D = load(TEX + "ceiling_intro.png") if ResourceLoader.exists(TEX + "ceiling_intro.png") else null
	for child in get_children():
		if child is CSGBox3D:
			var n: String = child.name.to_lower()
			var tex: Texture2D = null
			if n.contains("ceiling"):
				tex = ceiling_tex
			elif n.contains("floor"):
				tex = floor_tex
			elif n.contains("wall"):
				tex = wall_tex
			if tex:
				var mat := StandardMaterial3D.new()
				mat.uv1_scale = Vector3(4.0, 4.0, 4.0)
				mat.albedo_texture = tex
				child.material = mat


# ---------------------------------------------------------------- darkness / reveal beat

func _darken_scene(energy: float) -> void:
	var we: WorldEnvironment = get_node_or_null("Environment/WorldEnvironment")
	if we and we.environment:
		_env = we.environment.duplicate()
		_env.ambient_light_energy = energy
		we.environment = _env
	if candle_light:
		candle_light.light_energy = 0.0
		candle_light.visible = false
	if _candle_flame:
		_candle_flame.visible = false


func _play_wakeup_beat() -> void:
	player.global_position = GURNEY_POS + Vector3(0, GURNEY_TOP_Y, 0)
	player.rotation.y = 0.0  # identity already faces -Z, same side the table/door are on
	player.camera.position.y = 1.0
	player.camera.rotation.x = -0.25

	var creak := GameState.load_audio("gurney_creak")
	if creak:
		var p := AudioStreamPlayer3D.new()
		p.stream = creak
		p.position = GURNEY_POS
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(player.camera, "position:y", 1.65, WAKEUP_TWEEN_TIME)
	t.tween_property(player.camera, "rotation:x", 0.0, WAKEUP_TWEEN_TIME)
	t.finished.connect(_on_wakeup_finished)


func _on_wakeup_finished() -> void:
	player.unfreeze_input()
	ScreenText.scrawl(get_tree(), NIGHTMARE_TEXT, 4.0)
	_spawn_path_glow()
	_spawn_light_switch()
	_spawn_far_breath()
	_start_local_ambient()

# ⚠️ NO MID-FUMBLE JUMPSCARE HERE, and do not re-add one.
#
# `INTRO.md` §2 specced one ("~50-60% of the way: ONE scripted jolt — nightmare image
# flashes again for ~0.35 s + camera jolt"), it was never built, this pass built it, and the
# user cut it on the first playtest (2026-07-28): *"the screamer at the intro level is not
# needed."*
#
# The reasoning is sound and worth keeping: the cold-open jumpscare on START already spends
# that exact image, and firing it a second time four minutes into the game — in the one room
# that has no fail state — teaches the player that the image is free. Everything else in this
# room is dread that costs nothing and threatens nothing, and a startle in the middle of it
# is the only beat that was working at a different register from the rest.
#
# The dark walk is now carried entirely by the breathing behind you, the ambient
# metronome, and the stuck switch at the end of it.


# Something breathing at the wall you WAKE AGAINST.
#
# ⚠️ It is CLOSE, not far, and that is the beat (measured and confirmed 2026-08-16). This
# was documented for months as "at the far wall" — it is not. The emitter sits at z=+8.4
# and the player wakes on the gurney at z=+7.0: **1.61 m**, well inside its unit_size of
# 5.0, so it plays at its full BREATH_VOLUME_DB straight into the ear at the moment of
# sitting up. Then it recedes as they walk to the switch at the other end of the room.
#
# Keep it that way. Something breathing right behind you as you wake, which quietens the
# further you get from it, is a better opening than a distant sound you could walk toward
# and inspect — and it is the one beat in the room the player cannot resolve, because the
# lights coming on delete it (see _on_switch_flipped()). The node name FarBreath is kept
# only because tests/check_intro_beats.gd looks it up by name.
#
# ⚠️ On the duckable Ambience bus, so flash_scare's HoldBreath pre-duck takes it with the
# rest of the world.
func _spawn_far_breath() -> void:
	var s := GameState.load_audio("nook_breath")
	if not s:
		return
	_far_breath = AudioStreamPlayer3D.new()
	_far_breath.name = "FarBreath"
	_far_breath.stream = s
	_far_breath.volume_db = BREATH_VOLUME_DB
	_far_breath.unit_size = 5.0
	_far_breath.bus = AudioBuses.AMBIENCE
	# Just inside WallFront, the one wall in the room with nothing on it at all — and
	# 1.6 m from where the player wakes. See the note above; this is deliberate.
	_far_breath.position = Vector3(0, 1.4, ROOM_SIZE.y / 2.0 - 0.6)
	add_child(_far_breath)
	# Every .wav.import in this project is loop_mode=0, so loops are self-restarted.
	_far_breath.finished.connect(_far_breath.play)
	_far_breath.play()


# A level-LOCAL scare metronome at zero panic.
#
# ⚠️ Deliberately NOT RandomAmbient.register_player(). That autoload is global and carries
# 5 / 8 / 12 panic per event, which would give this room a fail state by the back door and
# break the "unloseable intro" rule. This plays the same kinds of sound and adds nothing.
func _start_local_ambient() -> void:
	_ambient_timer = Timer.new()
	_ambient_timer.one_shot = true
	_ambient_timer.timeout.connect(_on_local_ambient)
	add_child(_ambient_timer)
	_ambient_timer.start(randf_range(AMBIENT_MIN, AMBIENT_MAX))


func _on_local_ambient() -> void:
	var pick: String = ["floor_creak", "pipe_groan", "gurney_creak"].pick_random()
	var s := GameState.load_audio(pick)
	if s:
		var p := AudioStreamPlayer3D.new()
		p.stream = s
		p.volume_db = -8.0
		p.bus = AudioBuses.AMBIENCE
		# Somewhere in the room that is not on top of the player.
		p.position = Vector3(
			randf_range(-ROOM_SIZE.x / 2.0 + 1.0, ROOM_SIZE.x / 2.0 - 1.0),
			randf_range(0.3, 2.4),
			randf_range(-ROOM_SIZE.y / 2.0 + 1.0, ROOM_SIZE.y / 2.0 - 1.0))
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
	if _ambient_timer:
		_ambient_timer.start(randf_range(AMBIENT_MIN, AMBIENT_MAX))


func _spawn_path_glow() -> void:
	var g0 := Vector2(GURNEY_POS.x, GURNEY_POS.z)
	var g1 := Vector2(SWITCH_POS.x, SWITCH_POS.z)
	for progress in [0.2, 0.45, 0.7, 0.9]:
		var xz := g0.lerp(g1, progress)
		var light := OmniLight3D.new()
		light.name = "PathGlow"
		light.position = Vector3(xz.x, PATH_GLOW_Y, xz.y)
		light.light_energy = PATH_GLOW_ENERGY
		light.omni_range = PATH_GLOW_RANGE
		light.light_color = Color(0.6, 0.45, 0.3)
		add_child(light)
		_path_glow_lights.append(light)

	var hum := GameState.load_audio("emergency_hum")
	if hum:
		_path_glow_audio = AudioStreamPlayer3D.new()
		_path_glow_audio.stream = hum
		_path_glow_audio.volume_db = -18.0
		var mid := g0.lerp(g1, 0.5)
		_path_glow_audio.position = Vector3(mid.x, PATH_GLOW_Y, mid.y)
		add_child(_path_glow_audio)
		_path_glow_audio.finished.connect(_path_glow_audio.play)
		_path_glow_audio.play()


func _spawn_light_switch() -> void:
	var sw := LightSwitch.new()
	sw.name = "LightSwitch"   # findable by name for tests/check_intro_gate.gd
	sw.position = SWITCH_POS
	# The switch's own local +Z is its face normal; WallLeft is at x=-6.0 so "into
	# the room" is +X. Without this the plate stood parallel to the wall instead
	# of flush against it — visible edge-on, not as a mounted switch.
	sw.rotation.y = PI / 2.0
	sw.presses_needed = SWITCH_PRESSES
	sw.stuck.connect(_on_switch_stuck)
	sw.flipped.connect(_on_switch_flipped)
	add_child(sw)


# The first press does not work.
#
# The switch clunks, and one tube at the FAR end of the ward — the end the player is
# walking toward — stutters alight for GLIMPSE_TIME and dies. That is the whole beat: for
# a third of a second the room is not an abstract dark space, it is a ward with things in
# it, and then it is taken away again. Nothing chases, nothing spawns, no panic is added
# (this room has no fail state and must not gain one).
#
# ⚠️ WHICH TUBE — overridden 2026-08-16, and the old reasoning is kept because it was
# sound. It used to be the FAR tube (z=-6), on the grounds that the glimpse should show the
# player somewhere they have NOT been: they wake at z=+7 and the table, wheelchair and door
# are all at negative z. That argument is fine and it lost to a measurement. The far tube
# has omni_range 9 from z=-6, and everything the whole "the ward is occupied" pass built —
# both sheeted beds, both IV stands — sat at z=+5..+6.5, eleven metres away and completely
# out of reach. The best beat in the room was lighting bare floor. It is now the MIDDLE
# tube (z=0), with one occupied bed pulled into its pool (GLIMPSE_GURNEY_POS).
#
# The middle tube is chosen over simply moving the beds because of what happens LATER:
# _on_switch_flipped() deliberately leaves the tube over the table dead forever. So this
# 0.4 s flash is the only moment in the entire game that the centre of the ward is lit from
# above, and for the rest of the level that exact spot is a hole in the ceiling light.
#
# ⚠️ Raises a LIGHT, never emission (Issues 21/27/33). And it tweens back to exactly 0.0
# rather than to a small value, so a stuck press cannot leave the room permanently dimly
# lit and rob the reveal of its contrast.
func _on_switch_stuck(_press_index: int) -> void:
	# ⚠️ LOUD, and told in words (playtest 2026-07-28: *"the switch starting from the second
	# time is fine, but you need to accompany it with the sound and something like press E
	# again"*). The clunk was already here at default volume and did not register, and a
	# stuck switch that gives no feedback is indistinguishable from a broken game — which was
	# the one risk this beat carried. Two channels now: a heavier clunk plus a dead spark,
	# and an explicit prompt.
	# Prefers a purpose-made `switch_stuck` if one exists (see TODO_sounds.md) and otherwise
	# layers the working clunk with a dead spark. The guard means dropping the real file in
	# needs no code change.
	if GameState.load_audio("switch_stuck"):
		_play_at_switch("switch_stuck", 3.0)
	else:
		_play_at_switch("switch_clunk", 4.0)
		_play_at_switch("breaker_spark", -6.0)
	_show_switch_text(STIFF_SWITCH_TEXT, 3.0)

	var tube := _glimpse_light()
	if tube:
		var t := create_tween()
		t.tween_property(tube, "light_energy", GLIMPSE_ENERGY, 0.06)
		t.tween_interval(GLIMPSE_TIME)
		t.tween_property(tube, "light_energy", 0.0, 0.10)
		# A dying tube, not a working one: the buzz is quiet and it stops with the light.
		var buzz := GameState.load_audio("fluorescent_buzz_on")
		if buzz:
			var bp := AudioStreamPlayer3D.new()
			bp.stream = buzz
			bp.volume_db = -12.0
			bp.position = tube.position
			add_child(bp)
			bp.finished.connect(bp.queue_free)
			bp.play()


# The tube the stuck press briefly wakes: the one over the table, which is also the one
# _on_switch_flipped() leaves dead forever. See that function's ⚠️ for the full reasoning.
func _glimpse_light() -> OmniLight3D:
	for light in _ceiling_lights:
		if is_equal_approx((light as OmniLight3D).position.z, TABLE_POS.z):
			return light
	return null


# The stuck-press line.
#
# Local rather than ScreenText.toast() for one reason: toast() is hard-anchored to
# PRESET_CENTER, i.e. it lands on the crosshair, which is by definition on the object it is
# describing — the 2026-08-16 capture is the text printed across the switch plate. Fixing
# that properly means an anchor argument on screen_text.gd, which is a shared file with 18
# call sites in 11 other files and is out of scope for a level pass; it is filed in
# backlogs/00-cross-level.md instead. The outline convention matches ScreenText._outline().
func _show_switch_text(text: String, seconds: float) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 45
	add_child(canvas)

	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	lbl.position.y -= 210.0
	lbl.add_theme_color_override("font_color", ScreenText.BLOOD)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.modulate.a = 0.0
	canvas.add_child(lbl)

	# Connected, never awaited — an awaited timer dies with the node that started it
	# (Issue 6), which is the same reason ScreenText cleans up this way.
	var t := canvas.create_tween()
	t.tween_property(lbl, "modulate:a", 1.0, 0.25)
	t.tween_interval(seconds)
	t.tween_property(lbl, "modulate:a", 0.0, 0.6)
	t.finished.connect(canvas.queue_free)


func _play_at_switch(base_name: String, volume_db: float = 0.0) -> void:
	var s := GameState.load_audio(base_name)
	if not s:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.unit_size = 6.0
	p.position = SWITCH_POS
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _on_switch_flipped() -> void:
	_play_at_switch("switch_clunk")

	# ⚠️ FIRST, before a single light moves. One of the two covered beds — the one the
	# stuck press showed you (GLIMPSE_GURNEY_POS) — is empty when the lights come on.
	#
	# This is the whole point of the glimpse. Without it that 0.4 s flash is a mood beat
	# and nothing more; with it, the flash is the only evidence that the room used to be
	# different, and a player who did not look during it loses nothing and never knows.
	#
	# It is SCARY.md P6 / MovedProp's register, not a scare: no sound, no panic, no camera
	# move, no acknowledgement, and nothing ever looks at the player. It is unwitnessable
	# by construction — the room is still pitch black on this line, the switch is 9.5 m
	# from the bed, and the first flicker tween is not created until further down.
	#
	# ⚠️ queue_free(), not `visible = false`. Node3D visibility is inherited but CSG
	# COLLISION is not — hiding the form would leave an invisible body on the mattress
	# (the same trap glitch_wall.gd's set_seam_visible() documents from the other side).
	if is_instance_valid(_glimpse_form):
		_glimpse_form.queue_free()
	_glimpse_form = null

	player.unlock_flashlight()

	_switch_flipped = true
	_refresh_exit_lock()

	for light in _path_glow_lights:
		var t := create_tween()
		t.tween_property(light, "light_energy", 0.0, 0.6)
		t.finished.connect(light.queue_free)
	_path_glow_lights.clear()

	if _path_glow_audio:
		_path_glow_audio.finished.disconnect(_path_glow_audio.play)
		var at := create_tween()
		at.tween_property(_path_glow_audio, "volume_db", -40.0, 0.6)
		at.finished.connect(_path_glow_audio.queue_free)
		_path_glow_audio = null

	# The breathing stops with the darkness. It is never available for inspection under
	# the lights — a sound the player cannot go and check is a sound they keep.
	if _far_breath:
		_far_breath.finished.disconnect(_far_breath.play)
		var bt := create_tween()
		bt.tween_property(_far_breath, "volume_db", -50.0, 0.5)
		bt.finished.connect(_far_breath.queue_free)
		_far_breath = null

	# ⚠️ One tube stays dead — the one over the table (z = TABLE_POS.z), so the note the
	# player has to walk over and read is lit by the candle alone. The reveal otherwise
	# floods the room evenly and hands back every shadow the fumble just earned; leaving a
	# hole in the middle of the ceiling keeps the one place the player MUST stand still
	# lit by a single flickering source.
	for light in _ceiling_lights:
		if is_equal_approx((light as OmniLight3D).position.z, TABLE_POS.z):
			continue
		_flicker_on(light, 0.9)

	# ⚠️ `visible` MUST be restored, not just the energy (fixed 2026-08-16). `_darken_scene()`
	# hides this light for the blind fumble and nothing ever un-hid it, so for the life of
	# the procedural room the candle tweened up to a perfectly good 1.97 energy on a node
	# that was still invisible — and a hidden Node3D light emits NOTHING. Combined with the
	# tube above deliberately staying dead, the note the player is REQUIRED to read was the
	# darkest object in the room. `tests/check_intro_beats.gd` asserted the dead tube and
	# never the lit candle, i.e. it asserted the absence half of its own sentence.
	candle_light.visible = true
	if _candle_flame:
		_candle_flame.visible = true
	var ct := create_tween()
	ct.tween_property(candle_light, "light_energy", BASE_ENERGY, 1.0)
	ct.finished.connect(func(): _candle_lit = true)

	var buzz := GameState.load_audio("fluorescent_buzz_on")
	if buzz:
		var bp := AudioStreamPlayer3D.new()
		bp.stream = buzz
		bp.position = Vector3(0, ROOM_HEIGHT - 0.3, 0)
		add_child(bp)
		bp.finished.connect(bp.queue_free)
		bp.play()

	if _env:
		var et := create_tween()
		et.tween_property(_env, "ambient_light_energy", NORMAL_AMBIENT, 1.2)

	_show_controls_hint()


func _flicker_on(light: OmniLight3D, target: float) -> void:
	var t := create_tween()
	for i in range(3):
		t.tween_property(light, "light_energy", target * randf_range(0.15, 0.6), 0.05)
		t.tween_property(light, "light_energy", 0.0, 0.05)
	t.tween_property(light, "light_energy", target, 0.3)


# ---------------------------------------------------------------- twist ending (unchanged)

# The twist ending: same room, visibly wrong. The candle is dead, the room
# throbs blood-red, the exit is boarded over, and the new note is the only
# brightly lit thing left.
#
# ⚠️ FIXED 2026-07-27 (INTRO.md §7's deferred follow-up). Every position below used to
# be a literal computed against the OLD 5.6 m room: the planks sat at z = -2.45 while
# the door is at z = -8.5, so the game's FINAL BEAT rendered three boards floating in
# open space in the middle of the ward. They are now derived from EXIT_DOOR_POS and
# DOOR_SIZE, so they follow the door if the room is ever rescaled again. The spotlight
# at (0, 2.8, 0) was always correct — TABLE_POS is (0, 0.4, 0) — and is left alone.
func _corrupt_room() -> void:
	candle_light.light_energy = 0.0
	candle_light.visible = false
	# The candle is DEAD in the ending, which now means the stub stays and the flame goes.
	# (The ending branch of _ready() never calls _darken_scene(), so this is the only place
	# that hides it here.)
	if _candle_flame:
		_candle_flame.visible = false

	_red_light = OmniLight3D.new()
	_red_light.light_color = Color(0.8, 0.06, 0.04)
	_red_light.light_energy = 0.5
	# Range was 7.0 for a 5.6 m room. In an 18 m ward that left the far half unlit,
	# so the throb — the whole visual of the corrupted room — only reached the table.
	_red_light.omni_range = 11.0
	_red_light.shadow_enabled = true
	_red_light.position = Vector3(0, 2.4, ROOM_SIZE.y * -0.25)
	add_child(_red_light)

	# The door you came through is gone — planks where it used to be.
	var exit_door := get_node_or_null("ExitDoor")
	if exit_door:
		exit_door.queue_free()
	var plank_mat := StandardMaterial3D.new()
	plank_mat.albedo_color = Color(0.10, 0.07, 0.04)
	plank_mat.roughness = 0.95
	# Boarded flush across the doorway, standing proud of where the door panel was so
	# the planks never z-fight the back wall (the coincident-surface family, Issue 20).
	#
	# ⚠️ 2026-08-16: this DERIVATION was already correct — it was fixed on 2026-07-27
	# precisely so the boards would follow the door. What was wrong was the door: at the
	# old EXIT_DOOR_POS.z the planks landed 0.485 m in front of the wall face, so the game's
	# final beat was three boards hovering in open air with blank concrete behind them.
	# Seating the door fixed this for free, and the planks now sit inside the casing's
	# recess, which is what boards nailed across a doorway are supposed to look like.
	var plank_z := EXIT_DOOR_POS.z + DOOR_SIZE.z / 2.0 + 0.06
	for plank in [
		[Vector3(0, EXIT_DOOR_POS.y + 0.55, plank_z), 0.35],
		[Vector3(0, EXIT_DOOR_POS.y - 0.05, plank_z), -0.3],
		[Vector3(0, EXIT_DOOR_POS.y - 0.65, plank_z), 0.15],
	]:
		var mesh_inst := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.7, 0.22, 0.06)
		mesh_inst.mesh = mesh
		mesh_inst.set_surface_override_material(0, plank_mat)
		mesh_inst.position = plank[0]
		mesh_inst.rotation.z = plank[1]
		add_child(mesh_inst)

	# Harsh cold spotlight pinning the note to the table.
	var spot := SpotLight3D.new()
	spot.light_color = Color(0.95, 0.93, 0.85)
	spot.light_energy = 4.0
	spot.spot_range = 4.0
	spot.spot_angle = 18.0
	spot.shadow_enabled = true
	spot.position = Vector3(0, 2.8, 0)
	spot.rotation_degrees.x = -90.0
	add_child(spot)

	# Low whisper loop under everything.
	var stream := GameState.load_audio("whispers")
	if stream:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = -14.0
		add_child(p)
		p.finished.connect(p.play)
		p.play()


func _show_controls_hint() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 40
	add_child(canvas)

	var lbl := Label.new()
	lbl.text = "WASD — move    ·    E — interact    ·    F — flashlight    ·    Shift — run"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	lbl.position.y -= 60.0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.7, 0.66, 0.58, 0.9))
	lbl.add_theme_font_size_override("font_size", 18)
	canvas.add_child(lbl)

	var tween := create_tween()
	tween.tween_interval(8.0)
	tween.tween_property(lbl, "modulate:a", 0.0, 2.0)
	tween.tween_callback(canvas.queue_free)


# Room is ROOM_SIZE wide/deep, ceiling at ROOM_HEIGHT -> webs nestle into the top
# corners (each spanning the two walls + ceiling) with per-web variation in size,
# tilt, roll and position so they read as grown, not stamped. Seeded for
# reproducibility.
func _spawn_cobwebs() -> void:
	var cobweb_tex: Texture2D = load(TEX + "cobweb_intro.png") \
		if ResourceLoader.exists(TEX + "cobweb_intro.png") else null
	if not cobweb_tex:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 870261 if not GameState.is_ending else 870262

	var corner_x := ROOM_SIZE.x / 2.0 - 0.1
	var corner_z := ROOM_SIZE.y / 2.0 - 0.1
	var y_anchor := ROOM_HEIGHT - 0.05

	# Top corners as (x sign, z sign). The opening room only webs the two back
	# corners; the corrupted ending fills all four, denser.
	var corners := [Vector2(-1, -1), Vector2(1, -1)]
	if GameState.is_ending:
		corners.append(Vector2(-1, 1))
		corners.append(Vector2(1, 1))

	for c in corners:
		var count := rng.randi_range(1, 2) if not GameState.is_ending else rng.randi_range(2, 3)
		for i in range(count):
			_make_cobweb(cobweb_tex, c.x, c.y, rng, corner_x, corner_z, y_anchor)
		# In the ending, a few extra webs sag lower down the corner walls.
		if GameState.is_ending and rng.randf() < 0.7:
			_make_cobweb(cobweb_tex, c.x, c.y, rng, corner_x, corner_z, rng.randf_range(1.2, 1.9))


func _make_cobweb(tex: Texture2D, sx: float, sz: float, rng: RandomNumberGenerator,
		corner_x: float, corner_z: float, y_anchor: float) -> void:
	var corner := Vector3(sx * corner_x, y_anchor, sz * corner_z)
	var inward := Vector3(-sx, 0, -sz).normalized()
	# Pull inward off the exact corner and drop a little, with jitter.
	var pos: Vector3 = corner + inward * rng.randf_range(0.08, 0.55) \
		+ Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.55, -0.05), rng.randf_range(-0.12, 0.12))
	# Normal faces into the room and downward so the web droops toward the player.
	var normal := (inward + Vector3(0, -rng.randf_range(0.5, 0.9), 0)).normalized()

	var mesh_inst := MeshInstance3D.new()
	# ⚠️ UNIQUE per web (Issue 17, the third instance of it in this file). Every web was
	# called "CobwebIntro", so Godot renamed all but the first to @MeshInstance3D@NN and
	# they were unaddressable — which is how two of them slipped past a name filter in
	# tests/check_art_aspect.gd.
	_cobweb_index += 1
	mesh_inst.name = "CobwebIntro_%d" % _cobweb_index
	var quad := QuadMesh.new()
	var s := rng.randf_range(0.7, 1.3)
	quad.size = Vector2(s, s * rng.randf_range(0.85, 1.15))
	mesh_inst.mesh = quad

	var basis := _basis_from_normal(normal)
	basis = basis.rotated(normal, rng.randf_range(0.0, TAU))  # random roll
	mesh_inst.transform = Transform3D(basis, pos)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(1, 1, 1, rng.randf_range(0.5, 0.85))  # vary how thick each web reads
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.set_surface_override_material(0, mat)
	add_child(mesh_inst)


# Orthonormal basis whose local +Z (a QuadMesh's face normal) equals `normal`.
func _basis_from_normal(normal: Vector3) -> Basis:
	normal = normal.normalized()
	var up := Vector3.UP
	if absf(normal.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var x := up.cross(normal).normalized()
	var y := normal.cross(x).normalized()
	return Basis(x, y, normal)


func _process(delta: float) -> void:
	_flicker_time += delta
	if _red_light:
		# Slow arrhythmic throb, like something breathing through the walls.
		_red_light.light_energy = 0.5 \
			+ maxf(0.0, sin(_flicker_time * 1.7)) * 0.35 \
			+ sin(_flicker_time * 0.6) * 0.1
		return
	_tick_wheelchair()
	if not candle_light or not _candle_lit:
		return
	candle_light.light_energy = BASE_ENERGY \
		+ sin(_flicker_time * 7.3) * 0.18 \
		+ sin(_flicker_time * 13.7) * 0.09 \
		+ sin(_flicker_time * 3.1) * 0.06


func _on_ending_note_closed() -> void:
	# One beat of the corrupted room before the reveal takes the screen. The red throb and the
	# planked door are all the player has actually seen of it — the note overlay covered
	# everything else — so cutting straight to video would spend a room nobody looked at.
	await get_tree().create_timer(1.0).timeout
	# ⚠️ Not cosmetic. The mouse is captured and the cutscene is opaque, so without this the
	# player walks blind around the ward for the length of the clip, with footsteps playing.
	player.freeze_input()
	var cutscene := CutscenePlayer.play(self, ENDING_VIDEO)
	if cutscene != null:
		await cutscene.finished
	else:
		# Headless, or no file: the original 2 s pause, to the frame.
		await get_tree().create_timer(1.0).timeout
	# The twist ending is the ONLY death that uses this image — never the random
	# intro/ending fallback pool.
	Screamer.trigger_to_menu("res://assets/textures/screamers/shared_screamer.png")
