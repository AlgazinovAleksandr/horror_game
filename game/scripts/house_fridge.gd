extends StaticBody3D
class_name HouseFridge

# The House kitchen's fridge — and the ONLY new panic term in the whole atmosphere pass.
#
# The Kitchen is the joint-largest room in the level (42 m²) and shipped with exactly one
# prop: a counter. It also carried, together with the Landing and the Hallway, a combined
# panic budget of 6 across 90 m². So there was room for one real beat, and this is the most
# conventional domestic-horror beat in existence, which the House somehow did not have.
#
# ⚠️ Why this is a legal place to spend panic (GAME_MECHANICS_IDEAS N5 — "scares triggered
# by voluntary acts, not trigger volumes"):
#   * it is entirely OPTIONAL and off the quest path — nothing in the Kitchen is required
#     except walking through it to the cellar ramp;
#   * it fires on a deliberate E press, never on entry, so it can never ambush anyone;
#   * it is one-shot and survivable.
# Contrast the cellar, which gets NO new panic in this pass: that leg already has a
# DreadZone at net-zero decay, a DarkZone, a 55-panic beartrap and an 18-panic apparition,
# and the level has no CalmZone anywhere.
#
# ⚠️ The level owns the panic, not this script (`opened` -> level_2.gd), the same
# prop-emits / level-decides split as cellar_gate.gd, bottle_item.gd and key_item.gd.
#
# ⚠️ The hum is the entire reason this works. An unremarkable white box in a dark kitchen
# is not worth walking up to; a box that is RUNNING is. The scare is what opening it costs;
# the hum only has to earn the approach.

signal opened

const SIZE := Vector3(0.78, 1.80, 0.72)
const CAVITY_DEPTH := 0.30          # a real recess, not a 6 cm dark panel
const DOOR_OPEN_DEG := 105.0
const DOOR_OPEN_TIME := 0.55        # slower: the reveal has to be watchable
const DOOR_DELAY := 0.28            # the scream lands BEFORE the door starts moving
const REVEAL_DELAY := 0.62          # …and the head as the door clears it (DOOR_DELAY + swing)
const THING_TEX := "res://assets/textures/level_2_house/house_fridge_thing.png"
const HEAD_HEIGHT := 0.46           # was 0.30 — "can you make this head bigger"
const HUM_VOLUME_DB := -20.0
const HUM_UNIT_SIZE := 4.0

# Very loud, by request. `fridge_scream.wav` is user-supplied.
const SCREAM_VOLUME_DB := 10.0

var _used: bool = false
var _hinge: Node3D = null
var _hum: AudioStreamPlayer3D = null
var _thing: Node3D = null


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build()
	_start_hum()


func _build() -> void:
	# Interior material — declared first because the shell's back panel uses it.
	var cav_mat := StandardMaterial3D.new()
	cav_mat.albedo_color = Color(0.05, 0.05, 0.055)
	cav_mat.roughness = 1.0

	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.74, 0.73, 0.70)
	shell.roughness = 0.55
	shell.metallic = 0.25

	# ⚠️ AN OPEN-FRONTED SHELL, built from five slabs — NOT one solid box.
	#
	# The first version was a single `BoxMesh` of the full size with the interior "recess"
	# drawn as another solid box inside it. A solid box has no inside: everything placed
	# within it is occluded by its own front face, so opening the door revealed a blank
	# panel. Playtest 2026-07-28: *"when the fridge opens — there is no head inside of it."*
	# That was not the head failing to spawn; it was the carcass drawing over it.
	#
	# The collider stays a single box (colliders never render), so the player still cannot
	# walk through it.
	var t := 0.05
	var inner_z := SIZE.z - CAVITY_DEPTH      # where the interior back sits
	var parts := [
		# name,           size,                                   centre
		["Back",  Vector3(SIZE.x, SIZE.y, t),          Vector3(0, SIZE.y / 2.0, -SIZE.z / 2.0 + t / 2.0)],
		["Left",  Vector3(t, SIZE.y, SIZE.z),          Vector3(-SIZE.x / 2.0 + t / 2.0, SIZE.y / 2.0, 0)],
		["Right", Vector3(t, SIZE.y, SIZE.z),          Vector3(SIZE.x / 2.0 - t / 2.0, SIZE.y / 2.0, 0)],
		["Top",   Vector3(SIZE.x, t, SIZE.z),          Vector3(0, SIZE.y - t / 2.0, 0)],
		["Base",  Vector3(SIZE.x, t, SIZE.z),          Vector3(0, t / 2.0, 0)],
		# The interior back wall, set forward of the outer back so the recess has a floor to
		# read against and the thing has something to sit in front of.
		["Inner", Vector3(SIZE.x - 2.0 * t, SIZE.y - 2.0 * t, t),
			Vector3(0, SIZE.y / 2.0, SIZE.z / 2.0 - inner_z)],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.name = "Fridge" + String(p[0])
		var bm := BoxMesh.new()
		bm.size = p[1]
		mi.mesh = bm
		mi.material_override = shell if String(p[0]) != "Inner" else cav_mat
		mi.position = p[2]
		add_child(mi)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = SIZE
	col.shape = shape
	col.position = Vector3(0, SIZE.y / 2.0, 0)
	add_child(col)

	# Two wire shelves. Cheap, but they are what stop the inside reading as a black rectangle
	# — the silhouette does the work here, as it does for every prop in this project
	# (Issue 35).
	var shelf_mat := StandardMaterial3D.new()
	shelf_mat.albedo_color = Color(0.62, 0.62, 0.64)
	shelf_mat.metallic = 0.6
	shelf_mat.roughness = 0.45
	for sy in [SIZE.y * 0.40, SIZE.y * 0.68]:
		var sh := MeshInstance3D.new()
		var shm := BoxMesh.new()
		shm.size = Vector3(SIZE.x - 0.16, 0.015, CAVITY_DEPTH - 0.04)
		sh.mesh = shm
		sh.material_override = shelf_mat
		sh.position = Vector3(0, sy, SIZE.z / 2.0 - CAVITY_DEPTH / 2.0 - 0.02)
		add_child(sh)

	# THE THING INSIDE, hidden until the door opens.
	#
	# ⚠️ Unshaded and NOT emissive. Unshaded means its albedo is its final colour, so it reads
	# at the back of an unlit box without glowing — Issues 21/27/33, the three-time recurrence
	# where a "hidden" prop became the brightest object in the room.
	# ⚠️ Alpha-scissored, so a real RGBA cutout reads as a shape rather than as a rectangle
	# (the apparition_figure.jpg bug). Falls back to a flat dark mass until the art exists.
	# ⚠️ REAL GEOMETRY, not a flat card (playtest 2026-07-29: "can we make this head 3d from
	# this 2d texture?"). A billboard quad in a box you walk right up to gives itself away the
	# moment you step sideways — there is no parallax and the "head" is visibly a sticker.
	#
	# A squashed sphere carries the volume; the generated photo is wrapped onto it and rotated
	# so the face lands on the front. `uv1_offset.x = 0.25` is what puts the texture's centre
	# on the +Z hemisphere — a Godot SphereMesh starts its U seam at +X, so without the
	# quarter-turn the player is served the back of the head.
	#
	# ⚠️ SHADED, unlike every billboard in this project. This one is INSIDE a box the player
	# points a torch into, so it should catch that torch and turn with it — which is most of
	# what sells it as an object rather than an image. Still no emission (Issues 21/27/33).
	# ⚠️ The FACE is a flat quad; the VOLUME behind it is a separate untextured mass.
	#
	# The first attempt wrapped the photo onto a SphereMesh, and playtest called the result
	# "an egg with one eye" — which is what a front-on portrait does when you map it around a
	# sphere: the face smears across the equator, one eye lands on the silhouette edge and the
	# other disappears round the back. A sphere's UV cannot hold a frontal photograph.
	#
	# So: the photo stays on a flat, correctly-proportioned quad (the only projection it is
	# valid for), and a dark skull-shaped ellipsoid sits just behind it so the object has real
	# depth from the side and catches the torch. From the front you read a face; from an angle
	# you read a head-sized mass. That is as far as a single generated image can honestly go.
	_thing = Node3D.new()
	_thing.name = "FridgeThing"
	_thing.position = Vector3(0, SIZE.y * 0.40 + 0.16,
		SIZE.z / 2.0 - CAVITY_DEPTH / 2.0 - 0.02)
	_thing.visible = false
	add_child(_thing)

	# ⚠️ NO backing sphere. There was one here to give the head volume from the side, and
	# playtest 2026-07-29 saw it for what it was: "there is a shadow of that egg that was
	# before." A dark ellipsoid behind an alpha-cut face does not read as a skull, it reads
	# as a shadow the face is stuck to — worse than the flat card it was meant to improve.
	# The photo alone, larger, is the honest version.
	var face := MeshInstance3D.new()
	face.name = "FridgeFace"
	var fq := QuadMesh.new()
	var aspect := 0.68
	if ResourceLoader.exists(THING_TEX):
		var face_tex: Texture2D = load(THING_TEX)
		if face_tex and face_tex.get_height() > 0:
			aspect = float(face_tex.get_width()) / float(face_tex.get_height())
	# Bigger, by request. The interior is SIZE.y - 0.14 tall and SIZE.x - 0.10 wide, so a
	# 0.46 m head still clears the shelves and the carcass.
	fq.size = Vector2(HEAD_HEIGHT * aspect, HEAD_HEIGHT)
	face.mesh = fq
	var tm := StandardMaterial3D.new()
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	tm.roughness = 0.35        # wet
	if ResourceLoader.exists(THING_TEX):
		tm.albedo_texture = load(THING_TEX)
	else:
		tm.albedo_color = Color(0.42, 0.45, 0.42)
	face.material_override = tm
	face.position = Vector3(0, 0, 0.055)
	_thing.add_child(face)

	# Hinge on the LEFT edge so the door swings out of the way of a player standing in
	# front of it, rather than into their face.
	_hinge = Node3D.new()
	_hinge.name = "DoorHinge"
	_hinge.position = Vector3(-SIZE.x / 2.0, 0, SIZE.z / 2.0 + 0.01)
	add_child(_hinge)

	# Art on a QuadMesh, never on the BoxMesh face — a textured box renders a magnified
	# CROP of its own art (Issue 24, recurred as 31). Untextured today; the guard means
	# dropping `house_fridge.png` in later needs no code change.
	var door := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(SIZE.x, SIZE.y - 0.06)
	door.mesh = qm
	var door_mat := StandardMaterial3D.new()
	var tex_path := "res://assets/textures/level_2_house/house_fridge.png"
	if ResourceLoader.exists(tex_path):
		door_mat.albedo_texture = load(tex_path)
	else:
		door_mat.albedo_color = Color(0.70, 0.69, 0.66)
		door_mat.roughness = 0.5
		door_mat.metallic = 0.2
	door.material_override = door_mat
	door.position = Vector3(SIZE.x / 2.0, SIZE.y / 2.0, 0)
	_hinge.add_child(door)

	var handle := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.04, 0.42, 0.05)
	handle.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.55, 0.55, 0.57)
	hmat.metallic = 0.7
	hmat.roughness = 0.35
	handle.material_override = hmat
	handle.position = Vector3(SIZE.x - 0.10, SIZE.y / 2.0, 0.03)
	_hinge.add_child(handle)


func _start_hum() -> void:
	var s := GameState.load_audio("fridge_hum")
	if not s:
		return
	_hum = AudioStreamPlayer3D.new()
	_hum.name = "FridgeHum"
	_hum.stream = s
	_hum.volume_db = HUM_VOLUME_DB
	_hum.unit_size = HUM_UNIT_SIZE
	_hum.bus = AudioBuses.AMBIENCE
	_hum.position = Vector3(0, SIZE.y / 2.0, 0)
	add_child(_hum)
	# Every .wav.import here is loop_mode=0, so loops are self-restarted.
	_hum.finished.connect(_hum.play)
	_hum.play()


func is_open() -> bool:
	return _used


# ⚠️ Once opened this prop is COMPLETELY INERT — no prompt, no ray target, nothing.
#
# `player.gd:_update_interact_prompt()` consults an optional `can_interact()` before showing
# "Press E" *or* setting `_interact_target`, which is the general opt-out `LabLocker`
# introduced. Without it a used fridge went on advertising "Press E" and then silently did
# nothing, which playtest saw and read as the prop being broken (2026-07-28).
func can_interact() -> bool:
	return not _used


func interact() -> void:
	if _used:
		return
	_used = true

	# The hum stops. The room gets quieter at the exact moment it should get louder, which
	# is the same trick SilenceZone and HoldBreath run — and it means the kitchen is
	# permanently a little deader afterwards for having been opened.
	if _hum:
		_hum.finished.disconnect(_hum.play)
		var ht := create_tween()
		ht.tween_property(_hum, "volume_db", -60.0, 0.25)
		ht.finished.connect(_hum.queue_free)
		_hum = null

	# ⚠️ ORDER MATTERS, and this is the order the user asked for: the scream starts on the
	# key press, and the door begins to swing a beat LATER. The sound arrives before there is
	# anything to see, so for a quarter of a second the player knows something is in there and
	# is still looking at a closed door. Playing it with or after the swing wasted that.
	_scream()

	var tw := create_tween()
	tw.tween_interval(DOOR_DELAY)
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_hinge, "rotation:y", deg_to_rad(DOOR_OPEN_DEG), DOOR_OPEN_TIME)

	# ⚠️ The payload is now IN THE WORLD, not a fullscreen image.
	#
	# This used to be a bare `flash_scare` and playtest read the whole prop as useless: the
	# door swung open onto an empty box and the scare happened somewhere else, on the screen.
	# Now the thing is sitting on the shelf, revealed as the door clears it, and the flash is
	# the punctuation rather than the content. Diegetic first, screen second — the same
	# ordering KONTUR's escort gate uses for its lie.
	get_tree().create_timer(REVEAL_DELAY).timeout.connect(_reveal)


func _scream() -> void:
	var s := GameState.load_audio("fridge_scream")
	if not s:
		s = GameState.load_audio("half_scream")
	if not s:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = SCREAM_VOLUME_DB
	p.max_db = 12.0        # default is 3, which would clamp the gain above away
	p.unit_size = 14.0
	p.position = Vector3(0, SIZE.y * 0.5, SIZE.z / 2.0)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _reveal() -> void:
	if _thing:
		_thing.visible = true
	# ⚠️ The panic lands HERE, with the reveal, not on the button press — "once it is open,
	# the creepy object should be there that is triggering a panic" (playtest 2026-07-28).
	# The level owns the amount; this only says when.
	opened.emit()
	# ⚠️ NO `flash_scare` HERE, and do not put one back.
	#
	# There used to be one, and playtest 2026-07-29 caught it firing BEFORE the door had
	# finished swinging: *"I still see a jumpscare appearing before the fridge opens. It
	# should not be there."* The fullscreen image also competed with the thing it was
	# supposed to be announcing — the head is IN THE WORLD, on the shelf, and a picture of
	# something else pasted over the screen at the same moment simply hid it.
	# The reveal is now the head, the scream and the dark. Nothing covers the view.
	# (the scream already fired on the key press — see interact())
