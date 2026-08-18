extends SceneTree

# Dev tool: place the camera at key spots in the Backrooms and dump screenshots.
# Run WITHOUT --headless (it needs a render target):
#
#   Godot --path game --script res://tests/screenshot_backrooms.gd
#
# ⚠️ THIS HARNESS USED TO PHOTOGRAPH ITS OWN DEATH, and then keep going (cross-level X35).
#
# Shot 04 parks the camera at (0, 1.6, 5) looking down the N arm with the flashlight on.
# When N is that round's dark arm — which is a coin flip — that position is inside
# `CreatureSmiler.ENGAGE_DIST` with `looking == true`, i.e. `_rush()` -> `Screamer.trigger()`
# -> scene reload. Reproduced: shots 04 and 05 came back as the fullscreen Smiler face, and
# every one of the remaining 16 was taken from the SPAWN POINT, because `_place()` kept a
# stale `Player` reference across the reload and silently did nothing. Eighteen of twenty
# files, each saved under a filename claiming to be somewhere else, all of them plausible.
#
# Three fixes, and the third is the one that matters:
#   1. Remove what can kill the camera before shooting anything — the Smiler, the beartraps
#      and the Flood's apparitions. This is a photographer, not a difficulty instrument.
#   2. Re-fetch the player and the scene on EVERY shot, never once.
#   3. FAIL LOUDLY if the scene reloads anyway. A screenshot tool that cannot fail is worse
#      than no screenshot tool, because its output looks exactly like success.

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
	[Vector3(0.6, 1.75, -4.6), Vector3(-2.0, 1.75, -4.6), "08_kontur_scrawl"],  # hint 4/4
	# BS1 — the two places the level demands the verb and never taught it.
	# ⚠️ The floor DRAG MARKS these two shots were framed for are GONE (backlog 04 R3, the
	# player cut them in two separate captures on one playthrough). The scrawl on the side
	# wall and the seam's audio are what remain, so 09 and 10 now look at the surface itself
	# and 09b / 10b carry the scrawl. Kept as a pair on purpose: the point of the framing was
	# always that a player meets the evidence while WALKING, not with their nose on the wall.
	[Vector3(8.0, 1.6, 0.0), Vector3(13.0, 1.3, 0.0), "09_east_cap_seam"],
	[Vector3(8.5, 1.6, 0.0), Vector3(12.0, 1.6, 1.4), "09b_east_cap_scrawl"],
	[Vector3(0, 1.6, 17.5), Vector3(0, 1.4, 22.8), "10_utility_seam"],
	[Vector3(0, 1.6, 18.5), Vector3(3.4, 1.7, 21.2), "10b_utility_scrawl"],
	[Vector3(0, 1.6, -1.2), Vector3(0, 1.5, 1.5), "11_arrow_north_close"],
	[Vector3(0, 1.6, -4.5), Vector3(0, 1.55, 1.5), "12_arrow_north_3m"],
	# backlog 04 R2 — the widened arm mouths, from where the player photographed them.
	[Vector3(0, 1.6, -0.2), Vector3(0.4, 1.55, 2.6), "13_hub_mouths"],
	[Vector3(0, 1.6, -3.0), Vector3(0.3, 1.55, 2.0), "13b_hub_mouths_back"],
	[Vector3(0, 1.6, -0.2), Vector3(4.0, 1.55, 0.6), "13c_mouth_east"],

	# ZONE 2 — THE SPRAWL (world offset +200 x). Wrong-scale pillar hall.
	[Vector3(200, 1.6, -16.0), Vector3(200, 1.6, 6.0), "20_sprawl_entry"],
	[Vector3(200, 1.6, 0.0), Vector3(216, 1.6, 0.0), "21_sprawl_east_wall"],
	[Vector3(200, 1.6, 0.0), Vector3(200, 1.6, 20.0), "22_sprawl_north_wall"],
	[Vector3(207, 1.6, 7.0), Vector3(200, 1.6, 0.0), "23_sprawl_pillars"],
	[Vector3(200, 1.6, 14.0), Vector3(200, 1.6, 22.0), "24_sprawl_alcove"],
	[Vector3(200, 3.4, -8.0), Vector3(200, 1.0, 8.0), "25_sprawl_scale"],
	[Vector3(189, 1.6, 18.5), Vector3(189, 1.5, 23.0), "26_sprawl_mirror"],
	[Vector3(211, 1.6, -19.0), Vector3(211, 1.4, -23.0), "27_sprawl_note"],
	# backlog 04 R1 — the exact frame the player captured (world 182.70, -12.20), which
	# showed the procedural sky through the W alcove's missing back wall.
	[Vector3(182.7, 1.6, -12.2), Vector3(178.5, 1.5, -11.0), "28_w_alcove_capture004"],
	[Vector3(217.0, 1.6, 11.0), Vector3(223.0, 1.5, 11.0), "29_e_alcove_back"],

	# ZONE 3 — THE FLOOD (world offset -200 x). ⚠️ Sump/Cistern moved 1 m outward when the
	# ROOMS table stopped overlapping the Basin; these follow them.
	[Vector3(-200, 1.6, -2.0), Vector3(-200, 1.6, 8.0), "30_flood_landing"],
	# THE DROWNED (2026-08-17) — one frame per searchable, from a realistic standing spot, so
	# "does it read as an object or as a box" (Issue 35) can be judged rather than assumed.
	[Vector3(-199.0, 1.6, 0.3), Vector3(-201.7, 0.30, 0.3), "42_drowned_footlocker"],
	[Vector3(-199.0, 1.6, 7.0), Vector3(-200.85, 0.55, 7.0), "43_drowned_gurney"],
	[Vector3(-196.6, 1.6, 14.9), Vector3(-196.6, 0.55, 16.6), "44_drowned_drawers"],
	[Vector3(-191.8, 1.6, 15.3), Vector3(-191.8, 0.25, 13.8), "45_drowned_suitcase"],
	[Vector3(-208.0, 1.6, 15.4), Vector3(-208.0, 0.30, 13.9), "46_drowned_toolchest"],
	[Vector3(-200.6, 1.6, 24.6), Vector3(-198.9, 0.55, 24.6), "47_drowned_wheelchair"],
	# B-R1 — the plate table, the Flood's assembly point. Two frames: what it looks like
	# standing at it, and what it looks like from the doorway you come in by, which is the
	# frame that decides whether "assemble it in the middle of the level" reads at all.
	[Vector3(-203.2, 1.6, 12.1), Vector3(-203.2, 0.95, 13.8), "48_flood_plate"],
	[Vector3(-200.0, 1.6, 11.6), Vector3(-203.2, 0.95, 13.8), "49_flood_plate_from_door"],
	[Vector3(-200, 1.6, 12.0), Vector3(-200, 1.6, 20.0), "31_flood_basin"],
	[Vector3(-200, 1.6, 15.0), Vector3(-209, 1.6, 15.0), "32_flood_westrun"],
	[Vector3(-210, 1.6, 19.0), Vector3(-210, 1.6, 25.0), "33_flood_sump_seam"],
	[Vector3(-190, 1.6, 19.0), Vector3(-190, 1.6, 25.0), "34_flood_cistern_decoy"],
	[Vector3(-200, 1.6, 20.0), Vector3(-200, 1.6, 27.0), "35_flood_throat"],
	# The corners that used to be 1 x 2 m dead pockets behind free-standing wall stubs.
	[Vector3(-200, 1.6, 16.0), Vector3(-206, 1.6, 18.6), "36_basin_nw_corner"],
	[Vector3(-200, 1.6, 16.0), Vector3(-194, 1.6, 18.6), "37_basin_ne_corner"],
]

var _frame := 0
var _idx := 0
# ⚠️ The Sprawl's crate stands in a recess chosen PER RUN, so its shot cannot be a literal.
# `_disarm()` appends it once the scene is up. Same reason the dweller's frame is dynamic.
var _shots: Array = []
var _shot_at := -1
var _reloaded := false
var _taken := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	change_scene_to_file("res://scenes/backrooms.tscn")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 14:
		return false
	if _frame == 14:
		_disarm()
	var step := (_frame - 14) % 12
	if step == 0:
		_idx = (_frame - 14) / 12
		if _idx >= _shots.size():
			return _finish()
		_place(_shots[_idx])
	elif step == 10:
		_capture(_shots[_idx][2])
	return false


# Everything in this level that can end a stationary camera's life. Removing them is the
# whole difference between a shot list and a slideshow of one room.
func _disarm() -> void:
	var lvl := current_scene
	var player := lvl.get_node_or_null("Player") as CharacterBody3D
	if player:
		# Suspends the standstill tick and the dark-zone tick; this camera never moves.
		player.set_smiler_active(true)
		player.set("_panic", 0.0)
	var killed := 0
	for n in _all(lvl):
		var s: Script = n.get_script()
		if s == null:
			continue
		var g := String(s.get_global_name())
		if g == "CreatureSmiler" or g == "Beartrap" or g == "Apparition":
			n.queue_free()
			killed += 1
	lvl.set("_smiler", null)
	print("disarmed %d fatal object(s) before shooting" % killed)

	_shots = SHOTS.duplicate()
	var zone2 := lvl.get_node_or_null("ZoneSprawl")
	var crate := zone2.get_node_or_null("SprawlCrate") if zone2 else null
	if crate != null:
		var c: Vector3 = (crate as Node3D).global_position
		var toward: Vector3 = ((zone2 as Node3D).global_position - c)
		toward.y = 0.0
		toward = toward.normalized()
		# Straight on from the hall, standing where a player who followed the whisper is.
		_shots.append([c + toward * 2.4 + Vector3(0, 1.6, 0), c + Vector3(0, 0.5, 0),
			"50_sprawl_crate"])
		# ...and from further out, which is the frame that decides whether a recess with a
		# box in it reads as different from the seven with a box in them.
		_shots.append([c + toward * 7.0 + Vector3(0, 1.6, 0), c + Vector3(0, 0.7, 0),
			"51_sprawl_crate_far"])


func _all(n: Node, acc: Array[Node] = []) -> Array[Node]:
	acc.append(n)
	for c in n.get_children():
		_all(c, acc)
	return acc


func _place(shot: Array) -> void:
	# ⚠️ Re-fetched every shot. The old version cached `current_scene`'s Player once; after a
	# death-and-reload that reference is freed and every later `_place()` was a no-op that
	# still produced a file.
	var lvl := current_scene
	var player := lvl.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		_reloaded = true
		return
	if lvl.get_node_or_null("SeamFar") == null:
		# The scene reloaded under us: _ready() ran again, _disarm() did not.
		_reloaded = true
		_disarm()
	player.global_position = (shot[0] as Vector3) - Vector3(0, 1.6, 0)
	player.velocity = Vector3.ZERO
	var to: Vector3 = (shot[1] as Vector3) - (shot[0] as Vector3)
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() > 0.01:
		player.rotation.y = atan2(-flat.x, -flat.z)
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	if cam and flat.length() > 0.01:
		cam.rotation.x = atan2(to.y, flat.length())


func _capture(shot_name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT + shot_name + ".png")
	_taken += 1
	print("shot: ", shot_name)


func _finish() -> bool:
	print("%d of %d shots written to %s" % [_taken, _shots.size(), OUT])
	if _reloaded:
		# ⚠️ LOUD. Some of the files above are of somewhere other than their filename says.
		print("RESULT: FAIL — the scene reloaded during the run; shots after that point "
			+ "are NOT of the places they are named after")
		quit(1)
	else:
		print("RESULT: PASS")
		quit(0)
	return true
