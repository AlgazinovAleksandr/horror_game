extends SceneTree

# Photographs the main menu, twice, a few seconds apart.
#
# ⚠️ Run WITHOUT --headless — a VideoStreamPlayer has nothing to decode into without a render
# target, and `main_menu.gd` deliberately does not even build one when `DisplayServer.get_name()`
# is "headless". That is also why this cannot join tools/run_tests.sh.
#
#   /Applications/Godot.app/Contents/MacOS/Godot --path game --script res://tests/screenshot_menu.gd
#
# Two shots rather than one, because the single question a still cannot answer is "is the
# background MOVING or is it the fallback still?" — the two frames are 3 s apart in a 20 s loop,
# so they must differ. The script prints the mean absolute difference between them and the mean
# luminance of each, and asserts:
#   * the background is live video, not `main_menu_bg.png`
#   * SUBJECT 47 is still legible over it (the 0.78 overlay is doing its job)

const OUT_DIR := "/tmp/menu_shots/"
const SETTLE := 2.0
const GAP := 3.0
# The clip is 20 s and mostly still by design (one flickering tube, drifting dust), so the bar is
# "not identical", not "obviously different". The fallback still would score exactly 0.0.
const MIN_MOTION := 0.0005


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("screenshot_menu: headless, nothing to photograph — run without --headless")
		quit(0)
		return

	change_scene_to_file("res://scenes/main_menu.tscn")
	await create_timer(SETTLE).timeout
	var a := await _shot("menu_a")
	await create_timer(GAP).timeout
	var b := await _shot("menu_b")

	var failures := 0
	if a == null or b == null:
		print("  FAIL  could not capture the viewport")
		quit(1)
		return

	var motion := _mean_abs_diff(a, b)
	var lum_a := _mean_luma(a)
	print("  frames %.1f s apart: mean abs diff %.5f" % [GAP, motion])
	print("  mean luminance: a %.4f  b %.4f" % [lum_a, _mean_luma(b)])

	if motion > MIN_MOTION:
		print("  OK    the background is LIVE VIDEO (a still would score exactly 0)")
	else:
		print("  FAIL  the two frames are identical — the video is not playing, or the")
		print("        fallback still is showing. Check the .ogv imported and that")
		print("        main_menu.gd's one-frame did-it-start guard is not freeing it.")
		failures += 1

	# The menu is deliberately dark. What matters is that the text still reads against it, which
	# is a contrast question, not a brightness one — CLAUDE.md's Issue 62 rule.
	var title_band := _mean_luma_rect(a, 0.30, 0.38, 0.70, 0.50)
	var edge_band := _mean_luma_rect(a, 0.02, 0.38, 0.20, 0.50)
	print("  title band %.4f vs the wall beside it %.4f" % [title_band, edge_band])
	if title_band > edge_band:
		print("  OK    SUBJECT 47 is brighter than the background it sits on")
	else:
		print("  FAIL  the title does not stand out — the overlay alpha may need raising")
		failures += 1

	print("  wrote %smenu_a.png and %smenu_b.png" % [OUT_DIR, OUT_DIR])
	print("SCREENSHOT-MENU %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(failures)


func _shot(name: String) -> Image:
	await process_frame
	await process_frame
	var tex := root.get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	img.save_png(OUT_DIR + name + ".png")
	return img


func _mean_luma(img: Image) -> float:
	return _mean_luma_rect(img, 0.0, 0.0, 1.0, 1.0)


func _mean_luma_rect(img: Image, x0: float, y0: float, x1: float, y1: float) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var total := 0.0
	var n := 0
	var px0 := int(x0 * w)
	var px1 := int(x1 * w)
	var py0 := int(y0 * h)
	var py1 := int(y1 * h)
	for y in range(py0, py1, 4):
		for x in range(px0, px1, 4):
			var c := img.get_pixel(x, y)
			total += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			n += 1
	return total / maxf(1.0, float(n))


func _mean_abs_diff(a: Image, b: Image) -> float:
	var w: int = mini(a.get_width(), b.get_width())
	var h: int = mini(a.get_height(), b.get_height())
	var total := 0.0
	var n := 0
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			n += 1
	return total / maxf(1.0, float(n) * 3.0)
