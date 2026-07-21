extends SceneTree

# Dev tool: teleport the player to key spots in a level and dump screenshots.
# Usage: Godot --path game --script res://tests/screenshot_level.gd -- <scene> <out>
# Defaults to the Lab. Each SHOTS entry is [x, z, yaw_dir_x, yaw_dir_z, name].

var _scene := "res://scenes/level_1.tscn"
var _out := "/tmp/level_shots/"

const LAB_SHOTS := [
	[0.0, -1.0, 0.0, 1.0, "01_reception_north"],
	[0.0, 7.0, 0.0, 1.0, "02_mainhall1"],
	[-4.0, 7.0, -1.0, 0.0, "03_exam1_breaker"],
	[0.0, 12.5, 1.0, 0.0, "04_crosshall_to_morgue"],
	[4.0, 12.5, 1.0, 0.0, "05_morgue_shutter"],
	[0.0, 12.5, -1.0, 0.0, "06_crosshall_to_records"],
	[0.0, 16.5, 0.0, 1.0, "07_mainhall2"],
	[4.0, 17.0, 1.0, 0.0, "08_observation_mirror"],
	[0.0, 20.0, 0.0, 1.0, "09_exit_vestibule"],
	[0.0, 7.0, -1.0, 0.0, "10_exam1_doorway"],
	[9.5, 11.4, 0.0, 1.0, "11_keycard_cart"],
	# The camera sits ~1.65 m above a capsule that rests at ~0.9, so the eye is at
	# ~2.55 m. Cart-top props at y~0.9 are 1.7 m BELOW eye level, so stand ~3 m back
	# or they fall out of the bottom of the frame entirely.
	[9.5, 10.5, 0.0, 1.0, "12_tray_and_monitor"],
]

const HOUSE_SHOTS := [
	[0.0, -2.0, 0.0, 1.0, "01_entry_north"],
	[-5.0, 6.0, -1.0, 0.0, "02_living_room"],
	[5.0, 6.0, 0.0, -1.0, "03_kitchen_to_cellar"],
	[5.0, 1.0, 0.0, -1.0, "04_cellar_gate"],
	[5.0, -6.0, 0.0, 1.0, "05_cellar", -1.4],
	[0.0, 12.5, 0.0, 1.0, "06_landing"],
	[-7.0, 12.5, 0.0, 1.0, "07_bedroom"],
	[6.5, 12.5, -1.0, 0.0, "08_bathroom_mirror"],
	[0.0, 16.5, 0.0, 1.0, "09_childroom_exit"],
	[0.0, 7.0, 0.0, 1.0, "10_hallway"],
	[5.5, 7.0, 1.0, 0.6, "11_kitchen_key"],
	[-5.0, 6.5, 0.0, 1.0, "12_living_window"],
	# Just outside FOREST_SCARE_DIST (1.5 m) so the window can be photographed
	# without the proximity scare firing over it.
	[-5.0, 6.9, 0.0, 1.0, "13_window_frame"],
]

var SHOTS := LAB_SHOTS

const SETTLE := 32   # frames between placing the player and capturing (~0.53 s)
const CYCLE := 36    # frames per shot

var _frame := 0
var _idx := 0
var _player: CharacterBody3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_scene = args[0]
	if args.size() >= 2:
		_out = args[1]
	if _scene.contains("level_2"):
		SHOTS = HOUSE_SHOTS
	DirAccess.make_dir_recursive_absolute(_out)
	change_scene_to_file(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 12:
		return false
	# ⚠️ SETTLE must be long enough for gravity to finish. The player is placed at
	# y=1.6 and the Camera3D sits 1.65 m above it, so an unsettled capture shoots
	# from y=3.25 — ABOVE the 3.0 m ceiling, which renders as a near-black frame
	# with a stray light pool. At the old 12-frame delay some shots settled and
	# some didn't, so the eye height silently varied from shot to shot.
	var step := (_frame - 12) % CYCLE
	if step == 0:
		_idx = (_frame - 12) / CYCLE
		if _idx >= SHOTS.size():
			return true
		_place(SHOTS[_idx])
	elif step == SETTLE:
		_capture(SHOTS[_idx][4])
	return false


func _place(shot: Array) -> void:
	if not _player:
		_player = current_scene.get_node_or_null("Player") as CharacterBody3D
	if not _player:
		return
	_suppress_scares()
	var y: float = shot[5] if shot.size() >= 6 else 1.6
	_player.global_position = Vector3(shot[0], y, shot[1])
	_player.velocity = Vector3.ZERO
	var dx: float = shot[2]
	var dz: float = shot[3]
	_player.rotation.y = atan2(-dx, -dz)  # forward = -basis.z


# Teleporting the camera around drops it inside gaze range of cursed props, so panic
# climbs and a screamer eventually fires and covers the very geometry we came to
# photograph. This is an artifact of the harness, not of the level — so hold panic
# at zero and keep the Screamer overlay hidden for the duration of a capture run.
func _suppress_scares() -> void:
	# Hiding the overlay is not enough. Screamer.trigger() also calls _freeze_player(),
	# which sets the player's process_mode to DISABLED — so the player stops falling
	# and stays at the placed y=1.6, leaving the camera at 3.25 m, ABOVE the 3.0 m
	# ceiling. Every shot after the first scare then came back black, which looked
	# like missing geometry rather than a frozen player. Undo the freeze, the pause
	# and the re-entry guards every time.
	paused = false
	var screamer := root.get_node_or_null("Screamer")
	if screamer:
		screamer.visible = false
		screamer.set("_is_triggering", false)
		screamer.set("_is_flashing", false)
	if _player:
		_player.process_mode = Node.PROCESS_MODE_INHERIT
		if "_panic" in _player:
			_player.set("_panic", 0.0)


func _capture(shot_name: String) -> void:
	_suppress_scares()
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out + shot_name + ".png")
	print("shot: ", shot_name, " @ ", _player.global_position if _player else "no player")
