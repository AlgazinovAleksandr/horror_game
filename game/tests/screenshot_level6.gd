extends SceneTree

# Dev tool: dump one screenshot per Level 6 room/beat, same pattern as
# screenshot_kontur.gd. Needs a render target, so do NOT pass --headless.
#   Godot --path game --script res://tests/screenshot_level6.gd

const OUT := "/tmp/level6_shots/"

# [pos, look_at, shot_name]
const SHOTS := [
	[Vector3(0, 1.6, -2.0), Vector3(3.0, 1.6, -2.0), "01_entry_sign"],
	[Vector3(0, 1.6, 0.0), Vector3(0, 1.6, 5.0), "02_entry_spine"],
	[Vector3(0, 1.6, 6.0), Vector3(1.5, 1.6, 7.0), "03_corridor1_locker"],
	[Vector3(0, 1.6, 13.0), Vector3(0, 1.6, 17.0), "04_junction1"],
	[Vector3(-4, 1.6, 13.0), Vector3(-6.0, 1.6, 14.0), "05_records_cabinet"],
	[Vector3(0, 1.6, 20.0), Vector3(-2.5, 1.6, 22.0), "06_atrium_desk"],
	[Vector3(2, 1.6, 22.0), Vector3(5.0, 1.6, 22.0), "07_atrium_warda_door"],
	[Vector3(7, 1.6, 25.0), Vector3(7.0, 1.6, 20.0), "08_warda_loop"],
	[Vector3(0, 1.6, 29.0), Vector3(0, 1.6, 32.0), "09_junction2"],
	[Vector3(-6, 1.6, 30.5), Vector3(-8.0, 1.6, 30.5), "10_archiveA_locker"],
	[Vector3(-6, 1.6, 37.5), Vector3(-8.0, 1.6, 37.5), "11_archiveB"],
	[Vector3(0, 1.6, 36.0), Vector3(3.0, 1.6, 37.0), "12_wardb_locker"],
	[Vector3(0, 1.6, 44.0), Vector3(-3.0, 1.6, 45.0), "13_wardc_cabinet"],
	[Vector3(0, 1.6, 51.0), Vector3(0, 1.6, 54.0), "14_purgeante"],
	[Vector3(0, 1.6, 57.0), Vector3(0, 1.6, 59.5), "15_incinerator_purge_chamber"],
]

var _frame := 0
var _idx := 0
var _creature_placed := false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	change_scene_to_file("res://scenes/level_6_breach.tscn")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 12:
		return false

	# Once, after the level's own _ready() has run, pull the creature out and
	# park it in clear view near Junction1 for one extra shot (visually confirms
	# the Void_creature.glb retint reads correctly).
	if not _creature_placed and _frame == 12:
		var creature: Node = current_scene.get("_creature")
		if creature and creature.has_method("activate"):
			creature.activate()
			creature.position = Vector3(0, 0, 16)
			creature.rotation.y = PI
		_creature_placed = true

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
