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
	[Vector3(0.6, 1.75, -4.6), Vector3(-2.0, 1.75, -4.6), "08_kontur_scrawl"],  # hint 4/4, entry arm left wall

	# ZONE 2 — THE SPRAWL (world offset +200 x). Wrong-scale pillar hall.
	[Vector3(200, 1.6, -16.0), Vector3(200, 1.6, 6.0), "20_sprawl_entry"],
	[Vector3(200, 1.6, 0.0), Vector3(216, 1.6, 0.0), "21_sprawl_east_wall"],
	[Vector3(200, 1.6, 0.0), Vector3(200, 1.6, 20.0), "22_sprawl_north_wall"],
	[Vector3(207, 1.6, 7.0), Vector3(200, 1.6, 0.0), "23_sprawl_pillars"],
	[Vector3(200, 1.6, 14.0), Vector3(200, 1.6, 22.0), "24_sprawl_alcove"],
	[Vector3(200, 3.4, -8.0), Vector3(200, 1.0, 8.0), "25_sprawl_scale"],

	# ZONE 3 — THE FLOOD (world offset -200 x).
	[Vector3(-200, 1.6, -2.0), Vector3(-200, 1.6, 8.0), "30_flood_landing"],
	[Vector3(-200, 1.6, 12.0), Vector3(-200, 1.6, 20.0), "31_flood_basin"],
	[Vector3(-200, 1.6, 15.0), Vector3(-209, 1.6, 15.0), "32_flood_westrun"],
	[Vector3(-209, 1.6, 18.0), Vector3(-209, 1.6, 25.0), "33_flood_sump_seam"],
	[Vector3(-191, 1.6, 18.0), Vector3(-191, 1.6, 25.0), "34_flood_cistern_decoy"],
	[Vector3(-200, 1.6, 20.0), Vector3(-200, 1.6, 27.0), "35_flood_throat"],
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
