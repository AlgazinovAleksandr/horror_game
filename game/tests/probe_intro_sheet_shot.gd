extends SceneTree

# Throwaway diagnostic: photograph the covered body from the EXACT camera the playtester
# was standing at when they filed the J-capture, in the room's real post-reveal lighting.
#
# The note was logged at (2.80, 0.00, 6.10) looking at the near gurney (FAR_GURNEY_POS,
# (4.5, 0, 6.0)). Judging a prop from a convenient angle is how v2 shipped.
#
# Needs a window: Godot --path game --script res://tests/probe_intro_sheet_shot.gd -- <dir>

var _out := "/tmp/intro_sheet/"
var _t := 0.0
var _stage := 0
var _stage_at := 0.0
var _scene: Node = null
var _player: CharacterBody3D = null
var _cam: Camera3D = null

# name, eye position, look-at target
const SHOTS := [
	["01_user_camera",   Vector3(2.80, 1.65, 6.10), Vector3(4.50, 1.05, 6.00)],
	["02_user_camera_level", Vector3(2.80, 1.65, 6.10), Vector3(4.50, 1.35, 6.00)],
	["03_from_the_foot", Vector3(4.45, 1.65, 8.40), Vector3(4.50, 0.75, 6.00)],
	["04_from_the_head", Vector3(4.55, 1.65, 3.70), Vector3(4.50, 0.75, 6.00)],
	["05_walk_past",     Vector3(2.20, 1.65, 4.60), Vector3(4.50, 0.80, 6.00)],
]
var _shot := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	change_scene_to_file("res://scenes/intro_room.tscn")


func _advance(next: int) -> void:
	_stage = next
	_stage_at = _t


func _process(delta: float) -> bool:
	_t += delta
	if _stage == 0:
		_scene = current_scene
		if _t < 3.0:
			return false
		_player = _scene.get_node_or_null("Player") as CharacterBody3D
		_cam = _player.get_node_or_null("Camera3D") as Camera3D
		print("camera fov=%.1f" % _cam.fov)
		var sw = _scene.get_node_or_null("LightSwitch")
		sw.call("interact")
		_advance(1)
	elif _stage == 1 and _t - _stage_at > 1.2:
		_scene.get_node_or_null("LightSwitch").call("interact")
		_advance(2)
	elif _stage == 2 and _t - _stage_at > 2.0:
		_advance(3)
	elif _stage == 3:
		if _shot >= SHOTS.size():
			print("done")
			quit(0)
			return true
		var s = SHOTS[_shot]
		_player.global_position = s[1] - Vector3(0, 1.65, 0)
		_player.velocity = Vector3.ZERO
		_cam.global_position = s[1]
		_cam.look_at(s[2], Vector3.UP)
		_advance(4)
	elif _stage == 4 and _t - _stage_at > 0.4:
		# Re-assert the pose: player.gd owns the camera and moves with physics.
		var s = SHOTS[_shot]
		_player.global_position = s[1] - Vector3(0, 1.65, 0)
		_player.velocity = Vector3.ZERO
		_cam.global_position = s[1]
		_cam.look_at(s[2], Vector3.UP)
		_capture(s[0])
		_shot += 1
		_advance(3)
	if _t > 60.0:
		quit(1)
		return true
	return false


func _capture(name: String) -> void:
	var img := get_root().get_texture().get_image()
	var p: String = _out.path_join(name + ".png")
	img.save_png(p)
	print("shot: " + p)
