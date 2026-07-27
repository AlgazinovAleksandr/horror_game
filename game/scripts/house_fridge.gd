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
const DOOR_OPEN_DEG := 105.0
const DOOR_OPEN_TIME := 0.35
const HUM_VOLUME_DB := -20.0
const HUM_UNIT_SIZE := 4.0

# The face on the dead living-room TV, reused deliberately.
#
# ⚠️ NOT `screamer_house.png`. That is this level's FATAL sting, and spending a death image
# on a survivable scare teaches the player to discount the real one — the same reasoning
# INTRO.md used to keep the cold-open scream distinct from `all_levels_screamer`. Reusing
# the TV face instead means the thing in the fridge is the thing already in the house,
# which is a better story than a new asset would have told.
const SCARE_IMAGE := "res://assets/textures/level_2_house/tv_static_face.jpg"

var _used: bool = false
var _hinge: Node3D = null
var _hum: AudioStreamPlayer3D = null


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build()
	_start_hum()


func _build() -> void:
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.74, 0.73, 0.70)
	shell.roughness = 0.55
	shell.metallic = 0.25

	var carcass := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = SIZE
	carcass.mesh = bm
	carcass.material_override = shell
	carcass.position = Vector3(0, SIZE.y / 2.0, 0)
	add_child(carcass)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = SIZE
	col.shape = shape
	col.position = carcass.position
	add_child(col)

	# The interior, recessed behind the door so opening it reads as depth rather than as a
	# flat panel swinging off a solid block. Very dark, and NOT emissive — the light inside
	# a fridge you are afraid of does not come on (Issues 21/27/33).
	var cavity := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(SIZE.x - 0.10, SIZE.y - 0.14, 0.06)
	cavity.mesh = cm
	var cav_mat := StandardMaterial3D.new()
	cav_mat.albedo_color = Color(0.03, 0.03, 0.035)
	cav_mat.roughness = 1.0
	cavity.material_override = cav_mat
	cavity.position = Vector3(0, SIZE.y / 2.0, SIZE.z / 2.0 - 0.05)
	add_child(cavity)

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

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_hinge, "rotation:y", deg_to_rad(DOOR_OPEN_DEG), DOOR_OPEN_TIME)

	# flash_scare now carries its own 0.6 s HoldBreath pre-duck (screamer.gd), so the hum
	# dying and the world going quiet land together.
	Screamer.flash_scare(SCARE_IMAGE, "half_scream", 0.5)
	opened.emit()
