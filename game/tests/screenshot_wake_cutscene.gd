extends SceneTree

# Drives THE NIGHTMARE's WAKE transition and photographs the two moments that can only be judged
# by eye: the cut INTO the clip (black -> the clip's first frame) and the cut OUT of it (the clip's
# last frame -> the live Antechamber).
#
# ⚠️ Run WITHOUT --headless. `CutscenePlayer.play()` returns null headless by design, so headless
# this exercises the fallback path and photographs nothing.
#
#   /Applications/Godot.app/Contents/MacOS/Godot --path game \
#       --script res://tests/screenshot_wake_cutscene.gd -- --dungeon-seed 404
#
# The handover out is the risky one and the reason this exists: dungeon.gd frees the black in the
# SAME FRAME the clip ends, with no fade-up, because the clip's last frame is already the lit
# Antechamber. If that cut ever reads as a snap, the fix is a short fade on that leg — but it has
# to be looked at, not reasoned about.

const OUT_DIR := "/tmp/wake_shots/"
const FADE := 1.6          # dungeon.gd's fade-to-black, before anything is shown
const CLIP := 10.0         # dungeon_wake.ogv


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("screenshot_wake_cutscene: headless — CutscenePlayer is null by design here.")
		quit(0)
		return

	change_scene_to_file("res://scenes/dungeon.tscn")
	await create_timer(2.0).timeout
	var level := current_scene
	if level == null or not level.has_method("_sleep_transition"):
		print("  FAIL  dungeon.gd is not the current scene, or _sleep_transition is gone")
		quit(1)
		return

	# Put the player in the dungeon first — _on_bed_used() refuses unless `_in_dungeon`, and the
	# wake leg is the one under test. Going in uses the unchanged fade path.
	level.call("_sleep_transition", true)
	await create_timer(FADE + 1.6).timeout
	print("  in the dungeon: %s" % str(level.get("_in_dungeon")))

	# …then wake.
	level.call("_sleep_transition", false)
	await create_timer(FADE * 0.5).timeout
	await _shot("01_mid_fade_to_black")
	await create_timer(FADE * 0.5 + 0.35).timeout
	await _shot("02_clip_opens")            # must be black or nearly so
	await create_timer(CLIP * 0.5).timeout
	await _shot("03_clip_middle")
	# ⚠️ These two straddle the JOIN, which is the whole point of the script. Both must be dark:
	# the clip fades out to black and the layer-60 ColorRect under it is already black, so nothing
	# should change on screen at the moment CutscenePlayer frees itself.
	await create_timer(CLIP * 0.5 - 0.30).timeout
	await _shot("04_clip_last_moment")
	await create_timer(0.55).timeout
	await _shot("05_just_after_the_join")
	await create_timer(1.5).timeout
	await _shot("06_live_antechamber")

	print("  wrote 6 frames to %s" % OUT_DIR)
	print("  in the dungeon after waking (must be false): %s" % str(level.get("_in_dungeon")))
	print("SCREENSHOT-WAKE done — 04 and 05 straddle the join and must BOTH be near black.")
	print("  A bright 04 against a dark 05 is the snap this script was written to catch:")
	print("  it measured 0.171 vs 0.008 before dungeon_wake.ogv was given its fade=t=out.")
	quit(0)


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var tex := root.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	img.save_png(OUT_DIR + name + ".png")
	var total := 0.0
	var n := 0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			var c := img.get_pixel(x, y)
			total += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			n += 1
	print("  %-24s mean luminance %.4f" % [name, total / maxf(1.0, float(n))])
