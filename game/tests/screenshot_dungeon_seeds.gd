extends SceneTree

# Seed frames for the two dungeon cutscenes in VIDEO_PROMPTS.md
# (`dungeon_sleep.mp4` and `dungeon_wake.mp4`).
#
# ⚠️ Run WITHOUT --headless — it needs a real render target:
#   Godot --path game --script res://tests/screenshot_dungeon_seeds.gd
#
# Why this exists rather than reusing screenshot_dungeon.gd: both clips are shot
# FROM THE COT, LOOKING UP. That is a ~80° pitch from an eye height of 0.6 m, and
# screenshot_dungeon.gd's `_place(feet, look_at)` cannot express it — it assumes a
# standing 1.65 m eye and derives pitch from a look-at point, which degenerates as
# the target approaches straight overhead. This one sets yaw and pitch directly.
#
# The Antechamber is hand-built and always identical (dungeon.gd:380), so these
# frames are deterministic and the maze seed is irrelevant.

const OUT := "/tmp/dungeon_seed_shots/"
const SETTLE := 20
const HOLD := 10

const ANTE := Vector3(0, 0, -46)
const COT := Vector3(0, 0, -44)        # dungeon.gd:419 — ANTE_ORIGIN + (0,0,2)
const BRAZIER := Vector3(3.0, 1.6, -43)  # dungeon.gd:404 — the only warm light here
const LYING_EYE := 0.62                 # cot frame 0.42 + mattress; a head on the pillow

# [eye position, yaw radians, pitch radians, name]
var _shots: Array = []

var _started := false
var _settle := 0
var _level: Node = null
var _player: CharacterBody3D = null
var _cam: Camera3D = null
var _i := 0
var _step := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		change_scene_to_file("res://scenes/dungeon.tscn")
		return false

	_settle += 1
	if _settle < SETTLE:
		return false

	if _level == null:
		_level = current_scene
		if _level == null:
			print("dungeon.tscn did not load")
			quit(1)
			return true
		_player = _level.get_node_or_null("Player") as CharacterBody3D
		_cam = _player.get_node_or_null("Camera3D") as Camera3D if _player else null
		if _cam == null:
			print("no player camera")
			quit(1)
			return true
		# Keep gravity and the level's own logic from undoing the placements.
		_player.set_physics_process(false)
		# ⚠️ Hide EVERY CanvasLayer before capturing. These frames are seeds for
		# image-to-video, and the objective line, the "Press E" prompt and the
		# crosshair all render into the viewport — a generator handed a frame with
		# burned-in UI text will try to reproduce it, which is the one thing
		# VIDEO_PROMPTS.md's negative prompts exist to prevent.
		_hide_ui(root)
		# The Antechamber is lit by one brazier; the sleep clip is specified as
		# candlelit ("lit by one guttering candle just out of frame"), so light it.
		var candle = _level.get("_candle")
		if candle != null and candle.has_method("toggle"):
			candle.call("toggle")
		_build_shots()
		return false

	if _i >= _shots.size():
		print("shots written to ", OUT)
		quit(0)
		return true

	if _step == 0:
		var s: Array = _shots[_i]
		_place(s[0], s[1], s[2])
	_step += 1
	if _step >= HOLD:
		_capture(_shots[_i][3])
		_i += 1
		_step = 0
	return false


func _build_shots() -> void:
	var yaw_to_brazier: float = atan2(-(BRAZIER.x - COT.x), -(BRAZIER.z - COT.z))
	_shots = [
		# --- dungeon_sleep: the descent starts here, looking straight up ---
		[Vector3(COT.x, LYING_EYE, COT.z), 0.0, deg_to_rad(84.0), "sleep_01_ceiling_straight_up"],
		[Vector3(COT.x, LYING_EYE, COT.z), 0.0, deg_to_rad(64.0), "sleep_02_ceiling_and_far_wall"],
		# --- dungeon_wake: rises INTO the lit room, so the seed is the arrival frame ---
		[Vector3(COT.x, LYING_EYE, COT.z), yaw_to_brazier, deg_to_rad(62.0), "wake_01_ceiling_toward_brazier"],
		[Vector3(COT.x, LYING_EYE, COT.z), yaw_to_brazier, deg_to_rad(38.0), "wake_02_brazier_corner_low"],
		# --- context, so the room itself can be judged ---
		[ANTE + Vector3(-3.0, 1.65, -2.5), atan2(-(3.0), -(5.5)), deg_to_rad(8.0), "ctx_01_ante_wide"],
		[Vector3(COT.x - 2.2, 1.65, COT.z - 1.6), atan2(-(2.2), -(1.6)), deg_to_rad(-18.0), "ctx_02_the_cot"],
	]


func _place(eye: Vector3, yaw: float, pitch: float, _n := "") -> void:
	_player.global_position = eye - Vector3(0, 1.65, 0)   # body origin is at the feet
	_player.rotation.y = yaw
	_cam.position = Vector3(0, 1.65, 0)
	_cam.rotation.x = pitch
	# The camera hangs off the player, so both transforms have to be flushed or the
	# capture lands one frame behind the placement.
	_player.force_update_transform()
	_cam.force_update_transform()


func _hide_ui(n: Node) -> void:
	if n is CanvasLayer:
		(n as CanvasLayer).visible = false
	for c in n.get_children():
		_hide_ui(c)


func _capture(shot_name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT + shot_name + ".png")
	print("shot: ", shot_name)
