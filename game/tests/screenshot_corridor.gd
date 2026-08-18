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
	# ⚠️ 152.6, not 150.0. `BEARTRAPS` puts one at d=150 with a 0.32 m trigger radius against
	# a 0.4 m player capsule, so teleporting the camera onto the centreline there SPRANG it —
	# and the "TRAPPED — PRESS [E] TO ESCAPE" CanvasLayer then sat over shots 06 to 15, i.e.
	# over every frame this harness exists to judge, including every turn mirror. The
	# traps in this stretch are at 150 / 155 / 162 / 168; 152.6 is 2.4 m clear of the nearest.
	[152.6, 160.0, "05_dark_stretch"],
	[280.0, 285.0, "06_mirror"],
	[313.0, 319.5, "07_exit_door"],
	[43.0, 53.0, "08_corner1"],
	[83.0, 93.0, "09_corner2"],
	[178.0, 188.0, "10_corner4"],
	[88.3, 89.8, "11_turnmirror_90"],
	# ⚠️ There is no mirror at 230 any more (2026-08-16, the user asked for the first corner
	# and the last one only). The shot is KEPT, pointed at the same wall, because what it now
	# judges is whether that corner reads as an ordinary corner rather than as a hole where
	# a prop used to be.
	[228.3, 229.8, "12_corner_230_bare"],
	[273.3, 274.8, "13_turnmirror_275"],
	[13.0, 19.0, "14_ordinary_door"],
	# ⚠️ 169.6, not 168.0 — there is a beartrap at exactly d=168, and this shot sprang it.
	# The escape HUD then sat over the ONE frame in this harness that exists to judge whether
	# a four-word cross-level hint can be read.
	[169.6, 172.6, "15_kontur_plate"],   # KONTUR hint 3/4, side wall at d=172
	# NIGHTMARE hint 3/3 at d=250 — the game's most important cross-level hint, and the prop
	# the playtest called "does not match the level vibe". Nothing photographed it before.
	[247.4, 250.4, "16_vesper_plate"],
	# The moment `mirror_wake` fires: `MirrorSurface.ACTIVE_DIST` is 14 m, and the glass
	# switches from a dark rectangle to a live corridor as the player crosses it. This shot
	# stands just OUTSIDE that, so the pair 17/11 is the before and after of the beat the
	# new sound lands on.
	[75.0, 90.0, "17_mirror_wake_90"],
	# ⚠️ 2026-08-17: `MirrorSurface.ACTIVE_DIST` moved 14 -> 7 (the user asked for the mirror
	# to wake much closer), so shot 17's 15 m stand-off is now well OUTSIDE the gate and this
	# is the new "just inside" frame — 6 m out, where the pane comes alive and `mirror_wake`
	# fires. 17/18/11 is now the full before / at / after of the beat.
	[84.3, 89.8, "18_mirror_wake_close"],
	# THE ENTRANCE NOTE. It was an untextured BoxMesh for the whole life of the level; the
	# capture that ended that reads "The note looks boring." ⚠️ AIMED AT THE PROP since
	# 2026-08-18: the page then shipped 180° out for a further round because this shot pointed
	# down the corridor and the note was a smudge in the corner of it (Issue 121). Stood where
	# a walking player is when the page is readable, looking at it.
	[3.3, 0.0, "19_entrance_note", "IntroNote"],
	# THE FALSE ROOM 217, from the far end of its own approach leg — this is the frame that
	# decides whether the trap works at all. If the red-lit doorway does not read as an exit
	# from here, nobody walks toward it believing and the beat never happens.
	[141.0, 185.0, "20_false_door_far"],
	# ...and from reading distance, where the 217 plate has to be legible.
	[183.0, 185.0, "21_false_door_near"],
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
	# ⚠️ AN OPTIONAL 4th ELEMENT AIMS AT A NAMED NODE INSTEAD (2026-08-18). Two of these shots
	# are of objects standing OFF the centreline and BELOW eye height — the entrance note lies
	# on a table 1.05 m to one side at y=1.25 — and a heading computed from two path distances
	# points straight down the hall and photographs the far end of the corridor with the
	# subject as a smudge in the corner. That is how shot 19 came to be the evidence for a
	# note whose orientation it could not actually show.
	if shot.size() > 3:
		var subject := lvl.find_child(String(shot[3]), true, false) as Node3D
		if subject != null:
			var cam := player.get_node_or_null("Camera3D") as Camera3D
			var eye: Vector3 = player.global_position + Vector3(0, 1.65, 0)
			var d: Vector3 = subject.global_position - eye
			var flat := Vector3(d.x, 0.0, d.z)
			if flat.length() > 0.01:
				player.rotation.y = atan2(-flat.x, -flat.z)
			# Yaw on the body, pitch on the camera child — `player.gd`'s own split.
			if cam != null:
				cam.rotation.x = atan2(d.y, flat.length())
			return
	var to: Vector3 = (target.pos as Vector3) - (pt.pos as Vector3)
	to.y = 0.0
	if to.length() > 0.01:
		player.rotation.y = atan2(-to.x, -to.z)  # player forward = -basis.z
	var cam2 := player.get_node_or_null("Camera3D") as Camera3D
	if cam2 != null:
		cam2.rotation.x = 0.0


func _capture(shot_name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT + shot_name + ".png")
	print("shot: ", shot_name)
