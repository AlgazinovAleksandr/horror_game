extends SceneTree

# Dev tool: walk the corridor camera through key spots and dump screenshots.
# Run:  Godot --path game --script res://tests/screenshot_corridor.gd

const OUT := "/tmp/corridor_shots/"

# [player_dist, look_at_dist, shot_name]
const SHOTS := [
	[2.5, 8.0, "01_start_ahead"],
	[21.0, 25.0, "02_painting"],
	[43.0, 48.0, "03_clock"],
	[105.0, 110.0, "04_blood"],
	[150.0, 158.0, "05_dark_stretch"],
	[280.0, 285.0, "06_mirror"],
	[313.0, 319.5, "07_exit_door"],
	[43.0, 53.0, "08_corner1"],
	[83.0, 93.0, "09_corner2"],
	[178.0, 188.0, "10_corner4"],
]

var _frame := 0
var _idx := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	change_scene_to_file("res://scenes/corridor.tscn")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 10:
		return false
	var step := (_frame - 10) % 12
	if step == 0:
		_idx = (_frame - 10) / 12
		if _idx >= SHOTS.size():
			return true
		_place(SHOTS[_idx])
	elif step == 10:
		_capture(SHOTS[_idx][2])
	return false


func _place(shot: Array) -> void:
	var lvl := current_scene
	var player: CharacterBody3D = lvl.get_node("Player")
	var pt: Dictionary = lvl._path_point(shot[0])
	var target: Dictionary = lvl._path_point(shot[1])
	player.global_position = (pt.pos as Vector3) + Vector3(0, 0.05, 0)
	var to: Vector3 = (target.pos as Vector3) - (pt.pos as Vector3)
	to.y = 0.0
	if to.length() > 0.01:
		player.rotation.y = atan2(-to.x, -to.z)  # player forward = -basis.z


func _capture(shot_name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT + shot_name + ".png")
	print("shot: ", shot_name)
