extends SceneTree

# P3 (REWRITTEN 2026-08-16) — is the BreakerNook panel visible from across the dark wing?
#
#   Godot --path game --script res://tests/screenshot_nook_panel.gd      (NO --headless)
#
# ⚠️ THE FIRST VERSION OF THIS PROBE WAS PHYSICALLY CORRECT AND PERCEPTUALLY WRONG, and it
# is the reason the panel shipped visible twice. It sampled an 11x11 pixel box at the panel's
# CENTRE, took the MEAN, reported "peak ~1.5 of 255, wall 0.0000", and the analysis it fed
# concluded "does not leak". Two independent mistakes, both worth naming:
#
#   1. ABSOLUTE vs CONTRAST. 1.5/255 is negligible against a lit room. Against a background
#      of literally 0.0000 it is the ONLY thing in the frame, and a dark-adapted eye on a
#      real display reads it instantly. The quantity that matters is the DIFFERENCE from the
#      local background, never the level.
#   2. MEAN vs MAX, at the CENTRE. The leak was the panel's bright BORDER — the source art
#      carries a baked alpha-checkerboard around the fuse box — so the brightest pixels were
#      the ones the sample box was positioned to miss, and averaging would have buried them
#      anyway.
#
# The user photographed the result: an essentially black frame with a legible pale rectangle
# and a lighter outline in the middle of it (capture 003, torch off, 10 m out).
#
# So this version:
#   * projects the panel's own front face and samples its WHOLE screen bounding box;
#   * reports MAX (and a high percentile), never the mean alone;
#   * compares against a RING of wall pixels around the panel, not against an absolute floor;
#   * counts how many panel pixels exceed the ring's own maximum by more than 1/255 — the
#     "is there anything here an eye could latch onto" question, in pixels.
#
# The wing is meant to be solved by ear (`_spawn_dark_beacon`) and by the panel-hum meter.
# The panel is allowed to be found by touch at arm's length; it is not allowed to be a
# landmark at 10 m.

const OUT := "/tmp/nook_panel/"
const DISTANCES := [2.0, 3.5, 6.0, 10.0, 15.0]
# ⚠️ The exact spot the player stood on when they took capture 003 and wrote "I am standing
# far away from the breaker and I see it" — 9.4 m out and slightly off the wall's centre
# line, so it is NOT one of the clean on-axis rows above. Measured explicitly, because a
# probe that only ever samples its own convenient sightline is a probe that can miss the
# frame the complaint came from.
const CAPTURE_POSE := Vector3(-27.50, 0.10, 8.30)

# A pixel difference this small cannot be seen on any display and is inside PNG rounding.
const JND := 1.0 / 255.0
# How far out the wall ring reaches, as a multiple of the panel's own screen size.
const RING_SCALE := 2.6
# Keep the ring clear of the panel's own antialiased edge.
const RING_GAP_PX := 4

var _frame := 0
var _step := 0
var _settle := 0
var _player: CharacterBody3D
var _cam: Camera3D
var _panel: CSGBox3D
var _rows: Array = []
var _worst := 0.0
var _worst_far := 0.0
# ⚠️ On a HiDPI display the rendered image is BIGGER than the viewport rect that
# unproject_position() reports in — measured here, 3024x1701 against a 1152x648 viewport,
# a factor of 2.625. The first version of this probe sampled un-scaled coordinates, so its
# 11x11 box landed roughly a third of the way in from the top-left corner of where the panel
# actually was: it measured WALL and reported the panel as dark. Always convert.
var _px_scale := 1.0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	change_scene_to_file("res://scenes/level_1.tscn")


# Every CanvasLayer in the tree — crosshair, "Press E", the panic overlays, the wing meter.
# All of them draw ON TOP of the frame this probe is trying to measure, and the crosshair in
# particular is a pure-white dot at the exact aim point.
func _hide_hud(n: Node) -> void:
	if n is CanvasLayer:
		(n as CanvasLayer).visible = false
	for c in n.get_children():
		_hide_hud(c)


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


# The panel's four front-face corners in world space, taken from the node itself rather than
# typed in — so this keeps measuring the right rectangle when the prop is rebuilt.
func _panel_corners() -> Array:
	var s: Vector3 = _panel.size
	var out: Array = []
	for sx in [-0.5, 0.5]:
		for sy in [-0.5, 0.5]:
			out.append(_panel.global_transform * Vector3(s.x * sx, s.y * sy, s.z * 0.5))
	return out


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 12:
		return false
	if not _player:
		_player = current_scene.get_node_or_null("Player") as CharacterBody3D
		_cam = _player.get_node_or_null("Camera3D") as Camera3D
		var breaker: Node = current_scene.get_node_or_null("Breaker_Nook")
		if breaker:
			for c in breaker.get_children():
				if c is CSGBox3D:
					_panel = c
					break
		if not _panel:
			print("NOOK-PANEL FAIL: no Breaker_Nook panel found — measured nothing")
			quit(1)
			return true
		_player.lock_flashlight()
		print("--- P3: nook panel CONTRAST against the wall around it, torch locked off ---")
		print("    (HUD hidden: the crosshair is pure white and sits exactly on the aim point,")
		print("     so leaving it in reports the RETICLE as the brightest pixel of the panel)")
		print("    panel front face at %s, size %s" % [_panel.global_position, _panel.size])

	if _step >= DISTANCES.size() + 1:
		print("")
		for r in _rows:
			print(r)
		print("")
		print("  worst excess over the surrounding wall, any distance: %.4f (%.1f/255)"
			% [_worst, _worst * 255.0])
		print("  worst at 6 m and beyond:                              %.4f (%.1f/255)"
			% [_worst_far, _worst_far * 255.0])
		print("  frames + boosted crops in " + OUT)
		quit(0)
		return true

	var is_capture: bool = _step == DISTANCES.size()
	var d: float = _panel.global_position.distance_to(CAPTURE_POSE) if is_capture \
		else float(DISTANCES[_step])
	if _settle == 0:
		# On the sightline: the breaker is on BreakerNook's west wall at z = 7.7, and both
		# doorways east of it (x = -31 and x = -22.2) are centred on z = 7.7, so a straight
		# line from here to the panel passes through both openings.
		# The extra last row is the player's own capture pose.
		if is_capture:
			_player.global_position = CAPTURE_POSE
		else:
			_player.global_position = Vector3(_panel.global_position.x + d, 0.1, 7.7)
		_player.lock_flashlight()
		_player.ai_active = true
		_player.ai_look_at(_panel.global_position)
	_hide_hud(root)
	_settle += 1
	if _settle < 6:
		return false
	_settle = 0

	var img := _cam.get_viewport().get_texture().get_image()
	var vp_w: float = float(_cam.get_viewport().get_visible_rect().size.x)
	_px_scale = float(img.get_width()) / maxf(1.0, vp_w)
	_measure(img, d, "capture pose" if is_capture else "")
	_step += 1
	return false


func _measure(img: Image, d: float, tag: String) -> void:
	# Screen bounding box of the panel's front face, in IMAGE pixels (see _px_scale).
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for w in _panel_corners():
		var p: Vector2 = _cam.unproject_position(w) * _px_scale
		lo = lo.min(p)
		hi = hi.max(p)
	var x0 := int(floor(lo.x))
	var y0 := int(floor(lo.y))
	var x1 := int(ceil(hi.x))
	var y1 := int(ceil(hi.y))

	var panel_max := 0.0
	var panel_sum := 0.0
	var panel_n := 0
	var samples: Array[float] = []
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var v := _lum(img.get_pixel(x, y))
			panel_max = maxf(panel_max, v)
			panel_sum += v
			panel_n += 1
			samples.append(v)

	# Wall ring: the same box grown RING_SCALE, minus the panel box plus a small gap.
	var cx := (float(x0) + float(x1)) * 0.5
	var cy := (float(y0) + float(y1)) * 0.5
	var hw := (float(x1) - float(x0)) * 0.5 * RING_SCALE
	var hh := (float(y1) - float(y0)) * 0.5 * RING_SCALE
	var wall_max := 0.0
	var wall_sum := 0.0
	var wall_n := 0
	for y in range(int(cy - hh), int(cy + hh) + 1):
		for x in range(int(cx - hw), int(cx + hw) + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			if x >= x0 - RING_GAP_PX and x <= x1 + RING_GAP_PX \
					and y >= y0 - RING_GAP_PX and y <= y1 + RING_GAP_PX:
				continue
			var v := _lum(img.get_pixel(x, y))
			wall_max = maxf(wall_max, v)
			wall_sum += v
			wall_n += 1

	if panel_n == 0 or wall_n == 0:
		print("  !! %.1f m: sampled %d panel px / %d wall px — MEASURED NOTHING" % [d, panel_n, wall_n])
		return

	samples.sort()
	var p995: float = samples[mini(samples.size() - 1, int(float(samples.size()) * 0.995))]
	var wall_mean := wall_sum / float(wall_n)
	# How many panel pixels stand clear of the brightest thing in the wall around it?
	var over := 0
	for v in samples:
		if v > wall_max + JND:
			over += 1
	var excess: float = maxf(0.0, panel_max - wall_max)
	# Michelson, the classic contrast figure, against the local background mean.
	var michelson: float = 0.0
	if panel_max + wall_mean > 0.0:
		michelson = (panel_max - wall_mean) / (panel_max + wall_mean)

	_worst = maxf(_worst, excess)
	if d >= 6.0:
		_worst_far = maxf(_worst_far, excess)

	img.save_png(OUT + "nook_%02dm%s.png" % [int(d), "_capture" if tag != "" else ""])
	_save_crop(img, x0, y0, x1, y1, d, tag)

	_rows.append(("  %5.1f m%s panel max %.4f  p99.5 %.4f  mean %.4f | wall max %.4f mean %.4f"
		+ " | EXCESS %.4f (%.1f/255)  michelson %.3f  px over wall %d/%d")
		% [d, " *" if tag != "" else "  ", panel_max, p995, panel_sum / float(panel_n), wall_max, wall_mean,
			excess, excess * 255.0, michelson, over, panel_n])


# A x24 exposure boost of the panel's neighbourhood, so a human can SEE what the numbers say.
func _save_crop(img: Image, x0: int, y0: int, x1: int, y1: int, d: float, tag: String) -> void:
	var pad := 40
	var rx := maxi(0, x0 - pad)
	var ry := maxi(0, y0 - pad)
	var rw := mini(img.get_width() - rx, x1 - x0 + pad * 2)
	var rh := mini(img.get_height() - ry, y1 - y0 + pad * 2)
	if rw <= 0 or rh <= 0:
		return
	var crop := img.get_region(Rect2i(rx, ry, rw, rh))
	for y in range(crop.get_height()):
		for x in range(crop.get_width()):
			var c := crop.get_pixel(x, y)
			crop.set_pixel(x, y, Color(minf(1.0, c.r * 24.0), minf(1.0, c.g * 24.0),
				minf(1.0, c.b * 24.0)))
	crop.save_png(OUT + "nook_%02dm%s_boost24x.png" % [int(d), "_capture" if tag != "" else ""])
