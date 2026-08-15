extends Node3D

const OPENING_NOTE := "You are Subject 47.\n\nThis is a psychological experiment. Your fear response is being monitored.\n\nThe entity you may encounter is a product of your own mind — it cannot harm you unless you believe it can.\n\nStay calm. Do not touch what you are not meant to touch.\n\nIf something calls out to you — a voice, a ringing, anything that asks for an answer — do not answer it. You are not meant to speak to anyone but us.\n\nThe door ahead is your first test.\n\nWe are watching."

const ENDING_NOTE := "This is not an experiment.\n\nThere is no exit.\n\nThey already know where you are."

const TEX := "res://assets/textures/intro/"
const BASE_ENERGY := 1.8

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
const SWITCH_POS := Vector3(-5.77, 1.3, -1.0)  # snug against WallLeft's inner face (-5.85)
const TABLE_POS := Vector3(0, 0.4, 0.0)
const EXIT_DOOR_POS := Vector3(0, 1.1, -8.5)
# Panel extents; _corrupt_room() boards across this.
# ⚠️ WIDTH IS DERIVED FROM THE ARTWORK, not chosen (2026-08-15). `intro_lab_door.png` is
# 780x1511 after cropping, i.e. 1:1.937, and a texture squashed onto a mismatched quad is
# SCARY.md §7.1(4) — the same fault that made KONTUR's roster plate render as a stretched
# picture on a box. 2.2 / 1.937 = 1.136. Changing the height means changing the width too.
const DOOR_SIZE := Vector3(1.136, 2.2, 0.15)
const WHEELCHAIR_POS := Vector3(3.0, 0.0, -3.0)    # floor anchor — open floor between the table and the door
const WALL_CHART_POS := Vector3(3.5, 1.8, -8.77)   # on WallBack, clear of the door (spans x ±DOOR_SIZE.x/2)
const NORMAL_AMBIENT := 0.22        # tuned in-editor; see the verification pass

# --- "the ward is occupied" (2026-07-28) ---------------------------------------------
# This room had ZERO scares: no panic source, no RandomAmbient, no ApparitionDirector, no
# objective line — 60-120 s of nothing, which is a full level's worth of dead air relative
# to everything after it. Everything added below is DREAD ONLY: the intro has never had a
# fail state and deliberately still doesn't, so nothing here calls add_panic().
const SWITCH_PRESSES := 2           # the first press does not work — see _on_switch_stuck
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


func _ready() -> void:
	GameState.current_level = 0
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_clear_old_scene()

	_build_room()
	_build_gurney(GURNEY_POS)                    # the player's own — never occupied
	# ⚠️ Occupied. The two spare beds were bare, which made the ward read as storage; a
	# covered body on each makes it read as a ward with other subjects in it, and it is the
	# strongest thing available at level 0's "strictly ordinary" register — nothing
	# supernatural, nothing that moves, nothing the game ever comments on.
	_build_gurney(Vector3(4.5, 0, 6.0), true)
	_build_gurney(Vector3(-4.3, 0, 5.0), true)
	_build_iv_stand(Vector3(0.8, 0, 6.5))
	_build_iv_stand(Vector3(5.3, 0, 6.3))
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


func _build_gurney(pos: Vector3, occupied: bool = false) -> void:
	var frame := CSGBox3D.new()
	frame.name = "GurneyFrame"
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
	mattress.name = "GurneyMattress"
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
	# Reused across all 3 gurneys — one texture, multiple placements, same trick
	# _spawn_cobwebs() already uses.
	var mtex_path := TEX + "gurney_intro.png"
	if ResourceLoader.exists(mtex_path):
		var decal := MeshInstance3D.new()
		decal.name = "GurneyMattressArt"
		var qm := PlaneMesh.new()
		qm.size = Vector2(0.85, 1.9)
		decal.mesh = qm
		decal.position = pos + Vector3(0, 0.605, 0)
		var dm := StandardMaterial3D.new()
		dm.albedo_texture = load(mtex_path)
		dm.roughness = 0.9
		decal.set_surface_override_material(0, dm)
		add_child(decal)

	if occupied:
		_build_sheeted_form(pos)


# A covered body on a gurney. Two boxes — a long low mound and a slightly taller rise at
# the head end — which is all the silhouette needs to read, per Issue 35's finding that
# "the SILHOUETTE carries a prop here and art does not".
#
# ⚠️ NOT emissive, and a plain dull off-white rather than a bright one (Issue 8.8 /
# 21/27/33). At this room's light energy a pale emissive form would be the brightest thing
# in a pitch-dark ward, i.e. it would announce itself during the blind walk — and the whole
# point is that you do not see these until the lights come on, and then nobody mentions it.
#
# ⚠️ Never called for the player's own gurney: something solid on the bed you spawn lying
# on would push the player out of the world, and tests/check_spawn_blocked.gd asserts
# exactly that nothing invisible blocks a spawn.
func _build_sheeted_form(pos: Vector3) -> void:
	var sheet_mat := StandardMaterial3D.new()
	sheet_mat.albedo_color = Color(0.44, 0.43, 0.40)
	sheet_mat.roughness = 0.95

	# Head end toward -z, matching the gurneys' long axis.
	# Unique per bed, for the same Issue-17 reason as the ceiling tubes.
	var tag := "%.0f_%.0f" % [pos.x * 10.0, pos.z * 10.0]
	var body := CSGBox3D.new()
	body.name = "GurneySheet_" + tag
	body.size = Vector3(0.62, 0.20, 1.55)
	body.position = pos + Vector3(0, 0.70, 0.10)
	body.use_collision = true
	body.material = sheet_mat
	add_child(body)

	var head := CSGBox3D.new()
	head.name = "GurneySheetHead_" + tag
	head.size = Vector3(0.34, 0.26, 0.38)
	# Sits proud of the mound rather than flush with it — two coplanar faces here would
	# be the coincident-surface family all over again (Issues 19/20/23).
	head.position = pos + Vector3(0, 0.73, -0.80)
	head.use_collision = true
	head.material = sheet_mat
	add_child(head)


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
	qm.size = Vector2(0.6, 0.9)
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

	candle_light = OmniLight3D.new()
	candle_light.name = "CandleLight"
	candle_light.position = TABLE_POS + Vector3(0.3, 2.2, 0)
	candle_light.light_color = Color(1, 0.58, 0.18, 1)
	candle_light.light_energy = BASE_ENERGY
	candle_light.shadow_enabled = true
	candle_light.omni_range = 5.5
	add_child(candle_light)

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
	nbm.size = Vector3(0.21, 0.005, 0.297)
	note_slab.mesh = nbm
	var slab_mat := StandardMaterial3D.new()
	slab_mat.albedo_color = Color(0.7, 0.67, 0.58)
	note_slab.set_surface_override_material(0, slab_mat)
	note.add_child(note_slab)

	var note_face := MeshInstance3D.new()
	# PlaneMesh lies flat facing +Y by default — no rotation needed, same
	# technique _build_gurney()'s mattress art uses.
	var nqm := PlaneMesh.new()
	nqm.size = Vector2(0.21, 0.297)
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
	else:
		note_mat.albedo_color = Color(0.85, 0.82, 0.7)
	note_face.set_surface_override_material(0, note_mat)
	note.add_child(note_face)

	var note_col := CollisionShape3D.new()
	var nbs := BoxShape3D.new()
	nbs.size = Vector3(0.21, 0.005, 0.297)
	note_col.shape = nbs
	note.add_child(note_col)

	# note.gd emits `read` on OPEN (not on close — reading to the end is a mechanic
	# reserved for trap notes), which is the same hook level_1.gd uses to unlock the
	# Records locker. Not connected during the twist ending: that note's job is to end
	# the game, and _corrupt_room() has already deleted the exit door by then.
	if not GameState.is_ending:
		note.read.connect(_on_intro_note_read)


func _on_intro_note_read() -> void:
	GameState.intro_note_read = true
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
	var to_it := wc.global_position - cam.global_position
	if to_it.length() > WHEELCHAIR_TURN_DIST:
		return
	# Horizontal-only facing test — mixing in the vertical component gives false negatives at
	# close range, where the height gap is a large fraction of the distance.
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	to_it.y = 0.0
	if fwd.length() < 0.01 or to_it.length() < 0.01:
		return
	if fwd.normalized().dot(to_it.normalized()) < WHEELCHAIR_TURN_DOT:
		return

	_wheelchair_turned = true
	# Prefers a purpose-made `wheelchair_turn` (see TODO_sounds.md); falls back to the intro's
	# own metal-on-metal `gurney_creak`, the closest existing thing to a caster under load.
	var s := GameState.load_audio("wheelchair_turn")
	if not s:
		s = GameState.load_audio("gurney_creak")
	if s:
		var p := AudioStreamPlayer3D.new()
		p.stream = s
		p.volume_db = 2.0
		p.unit_size = 4.0
		p.position = wc.position
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
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


func _build_cabinets() -> void:
	var cabinet_tex_path := TEX + "cabinet_intro.png"
	var cabinet_tex: Texture2D = load(cabinet_tex_path) if ResourceLoader.exists(cabinet_tex_path) else null
	var positions := [
		Vector3(-5.55, 0.9, 4.0),
		Vector3(5.55, 0.9, 2.0),
		Vector3(5.55, 0.9, -4.0),
	]
	for i in range(positions.size()):
		var pos: Vector3 = positions[i]
		var body := CSGBox3D.new()
		body.name = "Cabinet%d" % i
		body.size = Vector3(0.6, 1.8, 0.5)
		body.position = pos
		body.use_collision = true
		var bm := StandardMaterial3D.new()
		if cabinet_tex:
			bm.albedo_texture = cabinet_tex
			bm.uv1_scale = Vector3(1.0, 1.0, 1.0)
		else:
			bm.albedo_color = Color(0.14, 0.18, 0.14)
		bm.metallic = 0.4
		bm.roughness = 0.7
		body.material = bm
		add_child(body)


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
# The dark walk is now carried entirely by the breathing at the far wall, the ambient
# metronome, and the stuck switch at the end of it.


# Something breathing at the far wall — the end of the ward the player is walking AWAY
# from. Audible only during the blind fumble; cut the instant the lights come on, so it is
# never available for inspection and never resolves into anything.
#
# ⚠️ On the duckable Ambience bus, so flash_scare's HoldBreath pre-duck takes it with the
# rest of the world. During the fumble jolt the breathing stops for 0.6 s — which is the
# correct reading, because the dip is the room holding its breath too.
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
	# Just inside WallFront, the one wall in the room with nothing on it at all.
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
# ⚠️ Why the far tube and not the near one: the glimpse has to show the player somewhere
# they have NOT been. They woke at z=+7 and have crossed that end already; the table, the
# wheelchair and the door are all at negative z. Lighting the end behind them would reveal
# only floor they have walked.
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
	ScreenText.toast(get_tree(), "The switch is stiff. Press E again.",
		Color(0.92, 0.88, 0.78), 3.0, 26)

	var far := _far_ceiling_light()
	if far:
		var t := create_tween()
		t.tween_property(far, "light_energy", GLIMPSE_ENERGY, 0.06)
		t.tween_interval(GLIMPSE_TIME)
		t.tween_property(far, "light_energy", 0.0, 0.10)
		# A dying tube, not a working one: the buzz is quiet and it stops with the light.
		var buzz := GameState.load_audio("fluorescent_buzz_on")
		if buzz:
			var bp := AudioStreamPlayer3D.new()
			bp.stream = buzz
			bp.volume_db = -12.0
			bp.position = far.position
			add_child(bp)
			bp.finished.connect(bp.queue_free)
			bp.play()


# The ceiling tube furthest from where the player woke up.
func _far_ceiling_light() -> OmniLight3D:
	var best: OmniLight3D = null
	var best_d := -1.0
	for light in _ceiling_lights:
		var d: float = absf((light as OmniLight3D).position.z - GURNEY_POS.z)
		if d > best_d:
			best_d = d
			best = light
	return best


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
	mesh_inst.name = "CobwebIntro"
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
	await get_tree().create_timer(2.0).timeout
	# The twist ending is the ONLY death that uses this image — never the random
	# intro/ending fallback pool.
	Screamer.trigger_to_menu("res://assets/textures/screamers/shared_screamer.png")
