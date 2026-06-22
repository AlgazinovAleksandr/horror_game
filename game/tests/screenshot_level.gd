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
]

var SHOTS := LAB_SHOTS

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
	var step := (_frame - 12) % 14
	if step == 0:
		_idx = (_frame - 12) / 14
		if _idx >= SHOTS.size():
			return true
		_place(SHOTS[_idx])
	elif step == 12:
		_capture(SHOTS[_idx][4])
	return false


func _place(shot: Array) -> void:
	if not _player:
		_player = current_scene.get_node_or_null("Player") as CharacterBody3D
	if not _player:
		return
	var y: float = shot[5] if shot.size() >= 6 else 1.6
	_player.global_position = Vector3(shot[0], y, shot[1])
	_player.velocity = Vector3.ZERO
	var dx: float = shot[2]
	var dz: float = shot[3]
	_player.rotation.y = atan2(-dx, -dz)  # forward = -basis.z


func _capture(shot_name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out + shot_name + ".png")
	print("shot: ", shot_name, " @ ", _player.global_position if _player else "no player")
