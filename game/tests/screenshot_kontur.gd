extends SceneTree

# Dev tool: dump one screenshot per KONTUR gate + the Soviet->facility pivot.
# Needs a render target, so do NOT pass --headless.
#   Godot --path game --script res://tests/screenshot_kontur.gd

const OUT := "/tmp/kontur_shots/"

# ⚠️ BUILT FROM THE SCENE, NOT HARD-CODED (2026-08-18). The old list was written against
# a layout that has since gained five rooms: "08_gate3_offering" looked at z=31 (now the
# middle of Records, and the pedestal is at 39), and shots 09/10/11 photographed the
# Archive, the Switchboard and a wall while claiming to be the airlock, the escort
# corridor and the exit. Worse, all three sat at x=0 while the whole facility spine is
# built at one of THREE randomised offsets — so two runs in three they were pointing at a
# room that is not there. A screenshot harness that photographs the wrong place is worse
# than none: it produces plausible files nobody re-checks (cross-level X31/X35).
var _shots: Array = []


func _build_shots() -> void:
	var dx: float = float(current_scene.get("_dark_x"))
	_shots = [
		[Vector3(0, 1.6, -3.0), Vector3(0, 1.6, 4.0), "01_landing"],
		[Vector3(-2.0, 1.5, 0.0), Vector3(-3.0, 1.5, 0.0), "02_mailboxes"],
		[Vector3(0, 1.6, 6.0), Vector3(0, 1.6, 10.0), "03_gate1_two_doors"],
		[Vector3(0, 1.6, 8.6), Vector3(0, 1.7, 10.0), "04_gate1_sign"],
		[Vector3(1.9, 1.6, 13.6), Vector3(2.75, 1.5, 16.9), "05a_containment_cell"],
		[Vector3(0.9, 1.5, 16.9), Vector3(2.75, 1.4, 16.9), "05b_cell_glass"],
		[Vector3(2.75, 1.5, 14.6), Vector3(2.75, 1.6, 16.9), "05c_cell_door"],
		[Vector3(2.2, 1.4, 23.5), Vector3(3.4, 1.1, 23.5), "06_gate2_shelf"],
		[Vector3(2.2, 1.4, 21.9), Vector3(3.4, 1.1, 22.6), "06b_gate2_count"],
		[Vector3(0, 1.6, 24.5), Vector3(0, 1.5, 27.0), "07_gate2_barrier"],
		[Vector3(1.6, 1.4, 31.0), Vector3(3.6, 1.3, 31.0), "08_gate5_roster"],
		[Vector3(0, 1.6, 36.5), Vector3(0, 1.2, 39.0), "09_gate3_offering"],
		[Vector3(-1.1, 1.6, 39.6), Vector3(-2.2, 1.35, 40.4), "10a_archive_lots_west"],
		[Vector3(1.1, 1.6, 40.6), Vector3(2.2, 1.35, 39.9), "10b_archive_lots_east"],
		[Vector3(3.4, 1.5, 36.6), Vector3(4.34, 1.4, 36.5), "10c_archive_ledger"],
		[Vector3(-2.4, 1.6, 40.0), Vector3(-4.4, 1.7, 40.0), "10_archive_west_wall"],
		[Vector3(-0.2, 1.5, 46.2), Vector3(-1.9, 1.0, 47.5), "11_gate6_phone"],
		[Vector3(0, 1.6, 54.0), Vector3(0, 1.4, 59.9), "12_gate7_seams"],
		[Vector3(dx, 1.6, 62.0), Vector3(dx, 1.55, 65.8), "13_gate8_airlock"],
		[Vector3(dx, 1.6, 68.0), Vector3(dx, 1.6, 80.0), "14_escort_corridor"],
		[Vector3(dx, 1.6, 94.0), Vector3(dx, 1.3, 98.0), "15_terminus_exit"],
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
	if _shots.is_empty():
		_build_shots()
	var step := (_frame - 12) % 12
	if step == 0:
		_idx = (_frame - 12) / 12
		if _idx >= _shots.size():
			return true
		_place(_shots[_idx])
	elif step == 10:
		_capture(_shots[_idx][2])
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
