extends SceneTree

# DIAGNOSTIC — what actually moves inside a turn mirror, measured in PIXELS.
#
#   ⚠️ NO --headless. It reads back the SubViewport's rendered image, and a headless run
#      has no render target, so it would measure a blank texture and report a tidy zero.
#
#   /Applications/Godot.app/Contents/MacOS/Godot --path game \
#     --script res://tests/probe_mirror_motion.gd
#
# WHY. User report on the verification replay, 2026-08-16: *"It used to be in a way that the
# reflection in the mirror moves, now it is static. can we make it move again?"*
#
# `check_mirror_frustum.gd` proves the wiring is live — the viewport is at UPDATE_ALWAYS
# inside 14 m and the projection responds to the eye moving. What it CANNOT prove is whether
# any of that is visible: a reflection of a black corridor is a live render of nothing, and
# is indistinguishable from a frozen one to anybody holding a mouse.
#
# So this measures the picture itself, in three phases per mirror:
#   HOLD    the player stands perfectly still. A correct mirror is a still photograph here,
#           EXCEPT for anything in the reflected world that moves on its own — the flicker
#           of a lit torch, and the player's own flashlight if it is sweeping.
#   TURN    the player turns their head 3 deg/frame and does not move a millimetre. The
#           reflection's FRAMING cannot change (a mirror is a fixed window, and
#           player.gd:_rotate_camera yaws about the axis the camera sits on) — but the
#           flashlight is a world light, so whatever it sweeps ACROSS the reflected corridor
#           does change. This number is how much of "it moves" the torch alone is worth.
#   WALK    the player backs away 0.06 m/frame. This is the motion the mirror is supposed to
#           have, and after the off-axis frustum fix it is 5x what it used to be.
#
# Also printed: mean LUMINANCE. If the glass reads as static because it is nearly black,
# that is a legibility finding and no amount of parallax will fix it.

const HOLD_FRAMES := 12
const TURN_FRAMES := 12
const WALK_FRAMES := 12
const STAND_OFF := 2.45          # metres in front of the glass — capture C1b's own distance
const TURN_STEP_DEG := 3.0
const WALK_STEP := 0.06

var _frame := 0
var _stage := 0
var _phase := 0
var _mirrors: Array = []
var _player: CharacterBody3D
var _prev: Image = null
var _lum: Array[float] = []
var _delta: Array[float] = []
var _peak: Array[float] = []
var _lit: Array[float] = []
var _results: Array[String] = []
var _phase_start := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/corridor.tscn")


func _find(n: Node, out: Array) -> void:
	if String(n.name) == "MirrorSurface" and n.has_node("SubViewport"):
		out.append(n)
	for c in n.get_children():
		_find(c, out)


func _face(target: Vector3) -> void:
	var d := target - _player.global_position
	d.y = 0.0
	_player.rotation.y = atan2(-d.normalized().x, -d.normalized().z)


func _sample(vp: SubViewport) -> void:
	var tex := vp.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.get_width() == 0:
		return
	# Downsample hard: this runs every frame and only the aggregate matters.
	img.resize(64, 88, Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGB8)
	var total := 0.0
	var diff := 0.0
	var mx := 0.0
	var lit := 0.0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			total += l
			mx = maxf(mx, l)
			# "Legible" = distinguishable from the black surround at all. 0.04 is roughly
			# where a surface stops being the same colour as an unlit corridor here.
			if l >= 0.04:
				lit += 1.0
			if _prev != null:
				var p := _prev.get_pixel(x, y)
				diff += absf(l - (0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b))
	var n := float(img.get_width() * img.get_height())
	_lum.append(total / n)
	_peak.append(mx)
	_lit.append(lit / n)
	if _prev != null:
		_delta.append(diff / n)
	_prev = img


# ⚠️ THE REFERENCE. "The reflection is dark" means nothing on its own in a level whose
# darkness is deliberately tuned (`corridor.gd:_black_background`). The only number that
# answers it is the corridor the player is looking at, measured the same way, from the same
# spot, on the same frame — so the question becomes "is the glass darker than the wall it
# hangs on", which is answerable.
func _sample_main() -> Array:
	var img := get_root().get_texture().get_image()
	if img == null or img.get_width() == 0:
		return [-1.0, -1.0, -1.0]
	img.resize(64, 88, Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGB8)
	var total := 0.0
	var mx := 0.0
	var lit := 0.0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			total += l
			mx = maxf(mx, l)
			if l >= 0.04:
				lit += 1.0
	var n := float(img.get_width() * img.get_height())
	return [total / n, mx, lit / n]


func _flush(label: String) -> void:
	var lum := 0.0
	for v in _lum:
		lum += v
	var dl := 0.0
	for v in _delta:
		dl = maxf(dl, v)
	var avg_d := 0.0
	for v in _delta:
		avg_d += v
	var pk := 0.0
	for v in _peak:
		pk = maxf(pk, v)
	var li := 0.0
	for v in _lit:
		li += v
	_results.append("    %-6s  frames %2d   mean lum %.4f   brightest px %.4f   >=0.04 %5.1f%%   mean frame delta %.5f   peak %.5f"
		% [label, _lum.size(), lum / maxf(1.0, float(_lum.size())), pk,
			100.0 * li / maxf(1.0, float(_lit.size())),
			avg_d / maxf(1.0, float(_delta.size())), dl])
	_lum.clear()
	_delta.clear()
	_peak.clear()
	_lit.clear()
	_prev = null


func _process(_dt: float) -> bool:
	_frame += 1
	if _frame < 20:
		return false
	if _mirrors.is_empty():
		_player = current_scene.get_node_or_null("Player") as CharacterBody3D
		_find(current_scene, _mirrors)
		print("MIRROR-MOTION probe: %d mirror(s), player %s"
			% [_mirrors.size(), "found" if _player != null else "MISSING"])
		if _player == null or _mirrors.is_empty():
			print("RESULT: nothing to measure")
			quit(1)
			return true
		_begin()
		return false

	var m: Node3D = _mirrors[_stage]
	var quad: MeshInstance3D = m.get_parent() as MeshInstance3D
	var vp: SubViewport = m.get_node("SubViewport") as SubViewport
	var n: Vector3 = quad.global_transform.basis.z.normalized()
	var step := _frame - _phase_start

	match _phase:
		0:
			_sample(vp)
			if step >= HOLD_FRAMES:
				_flush("HOLD")
				_phase = 1
				_phase_start = _frame
		1:
			_player.rotation.y += deg_to_rad(TURN_STEP_DEG)
			_sample(vp)
			if step >= TURN_FRAMES:
				_flush("TURN")
				_face(quad.global_position)
				_phase = 2
				_phase_start = _frame
		2:
			_player.global_position += n * WALK_STEP
			_sample(vp)
			if step >= WALK_FRAMES:
				_flush("WALK")
				for line in _results:
					print(line)
				_results.clear()
				_stage += 1
				if _stage >= _mirrors.size():
					print("MIRROR-MOTION probe done")
					quit(0)
					return true
				_begin()
	return false


func _begin() -> void:
	var m: Node3D = _mirrors[_stage]
	var quad: MeshInstance3D = m.get_parent() as MeshInstance3D
	var n: Vector3 = quad.global_transform.basis.z.normalized()
	var stand: Vector3 = quad.global_position + n * STAND_OFF
	_player.global_position = Vector3(stand.x, 0.0, stand.z)
	_face(quad.global_position)
	_phase = 0
	_phase_start = _frame
	_prev = null
	_lum.clear()
	_delta.clear()
	var ref := _sample_main()
	print("  mirror %d at %s — standing %.2f m off, flashlight %s"
		% [_stage, str(quad.global_position.round()), STAND_OFF,
			"ON" if _player.is_flashlight_on() else "OFF"])
	print("    REF     the corridor the player is looking at, same spot, same frame:"
		+ "  mean lum %.4f   brightest px %.4f   >=0.04 %5.1f%%"
		% [float(ref[0]), float(ref[1]), 100.0 * float(ref[2])])
