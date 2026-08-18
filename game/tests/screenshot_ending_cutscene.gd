extends SceneTree

# Drives the TWIST ENDING's tail — close the note, one beat of the corrupted room, the reveal, the
# screamer — and photographs it. This is the only path in the game that goes video -> screamer, and
# the clip has to hand over ON BLACK for that to land.
#
# ⚠️ Run WITHOUT --headless (CutscenePlayer returns null headless by design).
#
#   /Applications/Godot.app/Contents/MacOS/Godot --path game \
#       --script res://tests/screenshot_ending_cutscene.gd
#
# It asserts the two things that are cheap to get wrong and invisible in a still:
#   * the player is FROZEN for the whole clip — the mouse is captured and the cutscene is opaque,
#     so without it they walk blind around the ward with footsteps playing
#   * the clip's last frame is BLACK, because Screamer.trigger_to_menu() fires on top of it
#
# ⚠️ EVERY SAMPLE IS KEYED TO `VideoStreamPlayer.get_stream_position()`, never to a wall clock.
# Two earlier versions of this script timed the shots with `create_timer` deltas and both lied:
# one sampled "the clip's last frame" half a second AFTER the clip ended and photographed the
# screamer, the other sampled it two seconds early and photographed the middle. The load time of a
# 3.8 MB .ogv plus this script's own per-pixel scan is easily a second, and it is not predictable.

const OUT_DIR := "/tmp/ending_shots/"
# ⚠️ A literal because `VideoStream` exposes no `get_length()` — only the PLAYER knows where it is,
# not how long it is.
# ⚠️ AND IT IS NOT THE CONTAINER DURATION. `ffprobe` reports 10.875 s for this file, but Godot stops
# at the last DECODED FRAME, whose pts is 10.375 — the difference is Theora run-length-coding the
# identical padded black frames into one held frame, which the container counts and the decoder does
# not. Asking for a sample at 10.5 therefore lands after `finished` and photographs the screamer.
const CLIP_LENGTH := 10.375
const TAIL_MARGIN := 0.35     # sample this far before the end, i.e. inside the padded black tail
const WAIT_LIMIT := 30.0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("screenshot_ending_cutscene: headless — CutscenePlayer is null by design here.")
		quit(0)
		return

	# ⚠️ Autoloads are NOT global identifiers in a `--script` SceneTree — the script is compiled
	# before the autoload list is processed, so a bare `GameState` is a compile error. Every test
	# in this folder reaches it by path for the same reason.
	var gs := root.get_node_or_null("/root/GameState")
	if gs == null:
		print("  FAIL  no GameState autoload")
		quit(1)
		return
	gs.set("is_ending", true)
	gs.set("current_level", 0)
	change_scene_to_file("res://scenes/intro_room.tscn")
	await create_timer(2.5).timeout

	var room := current_scene
	if room == null or not room.has_method("_on_ending_note_closed"):
		print("  FAIL  intro_room.gd is not the current scene, or the ending hook is gone")
		quit(1)
		return
	var player := room.get_node_or_null("Player")
	if player == null:
		print("  FAIL  no Player")
		quit(1)
		return

	var failures := 0
	room.call("_on_ending_note_closed")

	# The corrupted-room beat, before anything is frozen.
	await create_timer(0.4).timeout
	await _shot("01_corrupted_room")
	if player.call("is_input_frozen"):
		print("  FAIL  frozen too early — the corrupted-room beat should still be playable")
		failures += 1

	var vsp := await _await_video(room)
	if vsp == null:
		print("  FAIL  no CutscenePlayer appeared — the .ogv did not load, or play() returned null")
		quit(1)
		return
	var length := CLIP_LENGTH

	await _await_position(vsp, 0.6)
	await _shot("02_clip_opens")
	if player.call("is_input_frozen"):
		print("  OK    the player is frozen for the clip")
	else:
		print("  FAIL  the player is NOT frozen — they can walk around blind behind the video")
		failures += 1

	await _await_position(vsp, length * 0.5)
	await _shot("03_clip_middle")

	await _await_position(vsp, length - TAIL_MARGIN)
	var last := await _shot("04_clip_last_moment")
	if last >= 0.0 and last <= 0.02:
		print("  OK    the clip hands over on black, where the screamer lands")
	else:
		print("  FAIL  the clip's last frame is lit (%.4f) — the screamer will fire over a" % last)
		print("        picture. Re-check the black tail with signalstats; see VIDEO_PROMPTS §5.2a.")
		failures += 1

	await create_timer(1.5).timeout
	await _shot("05_after_the_screamer_fires")

	print("  wrote 5 frames to %s" % OUT_DIR)
	print("SCREENSHOT-ENDING %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(failures)


func _await_video(room: Node) -> VideoStreamPlayer:
	var waited := 0.0
	while waited < WAIT_LIMIT:
		for child in room.get_children():
			if child is CutscenePlayer:
				var found := child.find_children("*", "VideoStreamPlayer", true, false)
				if not found.is_empty():
					return found[0]
		await process_frame
		waited += 1.0 / 60.0
	return null


func _await_position(vsp: VideoStreamPlayer, target: float) -> void:
	var waited := 0.0
	while waited < WAIT_LIMIT:
		if not is_instance_valid(vsp) or not vsp.is_playing():
			return
		if vsp.get_stream_position() >= target:
			return
		await process_frame
		waited += 1.0 / 60.0


func _shot(name: String) -> float:
	await process_frame
	await process_frame
	var tex := root.get_texture()
	if tex == null:
		return -1.0
	var img := tex.get_image()
	img.save_png(OUT_DIR + name + ".png")
	var total := 0.0
	var n := 0
	for y in range(0, img.get_height(), 16):
		for x in range(0, img.get_width(), 16):
			var c := img.get_pixel(x, y)
			total += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			n += 1
	var mean := total / maxf(1.0, float(n))
	print("  %-24s mean luminance %.4f" % [name, mean])
	return mean
