extends SceneTree

# Dev tool: place the camera at key spots in the Backrooms and dump screenshots.
# Run:  Godot --path game --script res://tests/screenshot_backrooms.gd

const OUT := "/tmp/backrooms_shots/"

# [pos, look_at, shot_name]
const SHOTS := [
	[Vector3(0, 1.6, -4.0), Vector3(0, 1.6, 4.0), "01_hub_north"],
	[Vector3(0, 1.6, -0.5), Vector3(6.0, 1.6, -0.5), "02_hub_east"],
	[Vector3(0, 1.6, -0.5), Vector3(-6.0, 1.6, -0.5), "03_hub_west"],
	[Vector3(0, 1.6, 5.0), Vector3(0, 1.6, 16.0), "04_north_arm"],
	[Vector3(0, 1.6, 19.0), Vector3(0, 1.6, 24.0), "05_glitch_wall"],
	[Vector3(6.0, 1.6, 0.0), Vector3(13.0, 1.6, 0.0), "06_east_arm"],
	[Vector3(0, 1.6, -4.0), Vector3(0.9, 1.0, -4.0), "07_clue_note"],
]

var _frame := 0
var _idx := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	change_scene_to_file("res://scenes/backrooms.tscn")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 12:
		return false
	var step := (_frame - 12) % 12
	if step == 0:
		_idx = (_frame - 12) / 12
		if _idx >= SHOTS.size():
			return true
		_place(SHOTS[_idx])
	elif step == 10:
		_capture(SHOTS[_idx][2])
	return false


func _place(shot: Array) -> void:
	var lvl := current_scene
	var player: CharacterBody3D = lvl.get_node("Player")
	player.global_position = shot[0] - Vector3(0, 1.6, 0)
	var to: Vector3 = (shot[1] as Vector3) - (shot[0] as Vector3)
	to.y = 0.0
	if to.length() > 0.01:
		player.rotation.y = atan2(-to.x, -to.z)


func _capture(shot_name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT + shot_name + ".png")
	print("shot: ", shot_name)
