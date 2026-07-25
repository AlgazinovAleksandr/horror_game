extends SceneTree

# Dev tool: drop the player camera at fixed vantage points in a level and dump
# screenshots, so visual fixes can be checked without hand-playing.
#
# Run (note: NO --headless, it needs a render target):
#   Godot --path game --script res://tests/screenshot_scene.gd -- <scene_name>
# e.g. ... -- level_1     ... -- intro_room     ... -- level_2_1
#
# Shots are [feet_position, look_at_target, name]; the player is teleported to
# feet_position and the camera aimed (yaw + pitch) at the target.

const OUT := "/tmp/shots/"

const SHOTS := {
	"intro_room": [
		[Vector3(0, 0, 0.5), Vector3(-2.5, 2.9, -2.5), "intro_web_back_left"],
		[Vector3(0, 0, 0.5), Vector3(2.5, 2.9, -2.5), "intro_web_back_right"],
		[Vector3(0, 0, -0.5), Vector3(0, 2.9, 0), "intro_ceiling_up"],
	],
	"level_1": [
		[Vector3(-3.5, 0, -2.4), Vector3(-3.5, 0.85, -4.55), "lab_bench_cluster"],
		[Vector3(-3.9, 0, -3.2), Vector3(-4.4, 0.95, -4.55), "lab_monitor"],
		[Vector3(-2.9, 0, -3.4), Vector3(-2.6, 0.82, -4.55), "lab_tray_keycard"],
		[Vector3(-3.5, 0, 2.9), Vector3(-3.5, 0.9, 0.9), "lab_exam_note3"],
		[Vector3(0.4, 0, -1.1), Vector3(1.49, 1.5, -1.1), "lab_note1_wall"],
		[Vector3(-0.4, 0, -1.0), Vector3(-1.49, 1.5, -1.0), "lab_note2_wall"],
	],
	"level_2_1": [
		[Vector3(-0.8, 0, 5.8), Vector3(-0.8, 1.6, 7.96), "house_window_forest"],
		[Vector3(0.6, 0, 6.4), Vector3(-0.8, 1.6, 7.96), "house_window_angle"],
		[Vector3(-0.7, 0, 16.5), Vector3(-0.7, 0.9, 18.9), "house_lock_on_door"],
		[Vector3(-0.7, 0, 15.5), Vector3(-0.7, 1.2, 18.9), "house_exit_door_wide"],
	],
	"level_3": [
		[Vector3(0, 0, -2), Vector3(0, 1.4, 1.0), "void_spawn_creature"],
		[Vector3(0, 0, -0.5), Vector3(0, 1.4, 1.0), "void_creature_near"],
	],
	# The two props rebuilt from flat decals into real geometry (playtest 2026-07-25,
	# captures #4 and #5). Head-on AND from an angle: a billboard/decal looks passable
	# straight on and gives itself away off-axis, which is how both survived this long.
	"kontur": [
		[Vector3(-1.2, 0, 0.0), Vector3(-2.78, 1.5, 0.0), "kontur_mailbox_head_on"],
		[Vector3(-1.4, 0, 1.6), Vector3(-2.78, 1.4, 0.0), "kontur_mailbox_angle"],
		[Vector3(2.2, 0, 31.0), Vector3(3.6, 1.3, 31.0), "kontur_roster_lock_head_on"],
		[Vector3(2.4, 0, 32.4), Vector3(3.6, 1.3, 31.0), "kontur_roster_lock_angle"],
	],
}

var _scene := "intro_room"
var _shots: Array = []
var _frame := 0
var _idx := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_scene = args[0]
	_shots = SHOTS.get(_scene, [])
	DirAccess.make_dir_recursive_absolute(OUT)
	change_scene_to_file("res://scenes/%s.tscn" % _scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 12:
		return false
	var step := (_frame - 12) % 14
	if step == 0:
		_idx = (_frame - 12) / 14
		if _idx >= _shots.size():
			return true
		_place(_shots[_idx])
	elif step == 12:
		_capture(_shots[_idx][2])
	return false


func _place(shot: Array) -> void:
	var player: CharacterBody3D = current_scene.get_node_or_null("Player")
	if not player:
		return
	player.global_position = shot[0]
	var cam: Camera3D = player.get_node("Camera3D")
	var eye: Vector3 = shot[0] + Vector3(0, 1.65, 0)
	var to: Vector3 = (shot[1] as Vector3) - eye
	player.rotation.y = atan2(-to.x, -to.z)  # player forward = -basis.z
	cam.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())


func _capture(shot_name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT + _scene + "_" + shot_name + ".png")
	print("shot: ", _scene, " / ", shot_name)
