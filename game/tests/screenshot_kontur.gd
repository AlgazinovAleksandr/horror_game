extends SceneTree

# Dev tool: dump one screenshot per KONTUR gate + the Soviet->facility pivot.
# Needs a render target, so do NOT pass --headless.
#   Godot --path game --script res://tests/screenshot_kontur.gd

const OUT := "/tmp/kontur_shots/"

# [pos, look_at, shot_name]
const SHOTS := [
	[Vector3(0, 1.6, -3.0), Vector3(0, 1.6, 4.0), "01_landing"],
	[Vector3(-2.4, 1.5, -1.0), Vector3(-3.0, 1.5, -1.0), "02_mailboxes"],
	[Vector3(0, 1.6, 6.0), Vector3(0, 1.6, 10.0), "03_gate1_two_doors"],
	[Vector3(0, 1.6, 8.6), Vector3(0, 1.7, 10.0), "04_gate1_sign"],
	[Vector3(0, 1.6, 13.0), Vector3(-3.2, 1.4, 18.0), "05_shapechanger"],
	[Vector3(0, 1.6, 22.0), Vector3(3.4, 1.1, 23.5), "06_gate2_shelf"],
	[Vector3(0, 1.6, 24.5), Vector3(0, 1.5, 27.0), "07_gate2_barrier"],
	[Vector3(0, 1.6, 33.5), Vector3(0, 1.2, 31.0), "08_gate3_offering"],
	[Vector3(0, 1.6, 38.0), Vector3(0, 1.6, 44.0), "09_airlock_pivot"],
	[Vector3(0, 1.6, 50.0), Vector3(0, 1.6, 62.0), "10_escort_corridor"],
	[Vector3(0, 1.6, 69.0), Vector3(0, 1.6, 73.0), "11_terminus_exit"],
]

var _frame := 0
var _idx := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	change_scene_to_file("res://scenes/kontur.tscn")


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
	var player: CharacterBody3D = current_scene.get_node("Player")
	player.global_position = (shot[0] as Vector3) - Vector3(0, 1.6, 0)
	var to: Vector3 = (shot[1] as Vector3) - (shot[0] as Vector3)
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() > 0.01:
		player.rotation.y = atan2(-flat.x, -flat.z)
	var cam: Camera3D = player.get_node("Camera3D")
	if flat.length() > 0.01:
		cam.rotation.x = atan2(to.y, flat.length())


func _capture(shot_name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT + shot_name + ".png")
	print("shot: ", shot_name)
