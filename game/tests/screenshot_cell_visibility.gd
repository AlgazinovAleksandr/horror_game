extends SceneTree

# CAN THE PLAYER ACTUALLY SEE OBJECT 12, AND IS IT A DARK SHAPE OR A PALE ONE?
#
#   Godot --path game --script res://tests/screenshot_cell_visibility.gd
#
# ⚠️ NO `--headless`. This is the photometric half of the containment cell's guard and it
# needs a render target, so — like every other `screenshot_*` here — it is deliberately
# NOT in `tools/run_tests.sh`. The half that CAN run headless (line of sight from every
# reachable heading, and the occupant's material) lives in `check_kontur_entities.gd`, and
# the two are meant to be read together: that one proves the port is open, this one proves
# what comes through it looks like.
#
# It exists because the cell shipped 2026-08-18 having been tested for everything it does
# NOT do — no collider, no panic, not interactable — and never once for whether it can be
# seen. It could not: SIX of thirteen reachable headings rendered zero pixels of the
# occupant, and on the seven that did it rendered 1.8-2.8x BRIGHTER than what was behind
# it, as a pale man in a suit.
#
# ⚠️ EVERY NUMBER HERE IS RELATIVE. This project has twice reached a confident wrong
# conclusion by measuring an absolute level against no reference (Issue 62, and the first
# probe written for this very cell). What is asserted is the occupant against WHAT IS
# DIRECTLY BEHIND IT, over one identical set of pixels.
#
# ⚠️ THE MASK IS BUILT WITH THE GLASS HIDDEN, AND THE LEVELS ARE READ WITH IT BACK.
# Four renders per pose:
#     A0  occupant visible, glass hidden       -.
#     B0  occupant hidden,  glass hidden        |- mask = eroded diff(A0, B0)
#     A1  everything visible                   -'   occ = A1 over the mask
#     B1  occupant hidden, glass visible            bg  = B1 over the mask
# The glass is alpha-blended, so hiding the occupant perturbs every pane pixel slightly and
# a naive diff mask picks up the whole pane — including the ceiling fixtures seen through
# it. That is how a 0.9-luminance "highlight on the creature's chest" got measured three
# times on an object that was, at the time, painted pure black with its emission off and no
# light on it at all (Issue 148). One ray, one pixel, one frame is never enough.
#
# ⚠️ AND THE MASK IS ERODED. A raw diff includes the silhouette's antialiased rim, where
# the pixel is a blend of figure and background.

const Scenes := preload("res://tests/lib/scenes.gd")

const OUT := "/tmp/cell_visibility/"
const SEED := 7
const HEADINGS := 24
const RADII := [2.0, 3.2]
const EYE := 1.6
const AIM_Y := 1.45
const DIFF_EPS := 0.012
const PLAYER_R := 0.45

# The Passage: pos (0, 16.5), size (8, 7) -> x -4..4, z 13..20. ⚠️ Reachability is bounds
# arithmetic, NOT a point query: CSG collides as a concave trimesh and `intersect_point`
# returns nothing inside one, so every candidate — including the ones buried in the east
# wall — came back "reachable" and the sweep photographed the inside of the masonry
# (Issue 40 / 94).
const ROOM_MIN := Vector2(-4.0, 13.0)
const ROOM_MAX := Vector2(4.0, 20.0)

# What a pass looks like. Both are RATIOS.
const MIN_PIXELS := 1500          # the silhouette is genuinely on screen
const MIN_CONTRAST := 0.15        # |occ - bg| / max(occ, bg)
const MAX_RATIO := 1.0            # occ / bg — it must be the DARK shape, not the bright one

var _cell: Node3D
var _occ: Node3D
var _panes: Array = []
var _player: CharacterBody3D
var _cam: Camera3D

var _poses: Array = []
var _rows: Array = []
var _i := 0
var _f := 0
var _a0: Image
var _b0: Image
var _a1: Image
var _fails := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	Scenes.pin_rng(SEED)
	change_scene_to_file("res://scenes/kontur.tscn")


func _process(_d: float) -> bool:
	_f += 1
	if _f < 24:
		return false
	if _poses.is_empty():
		_setup()
		if _poses.is_empty():
			print("RESULT: FAIL (no reachable pose was generated — the filter is wrong)")
			quit(1)
			return true
	var step := (_f - 24) % 16
	if step == 0:
		_i = (_f - 24) / 16
		if _i >= _poses.size():
			_report()
			return true
		_place(_poses[_i])
		_set_panes(false)
		_occ.visible = true
	elif step == 3:
		_a0 = root.get_viewport().get_texture().get_image()
		_occ.visible = false
	elif step == 6:
		_b0 = root.get_viewport().get_texture().get_image()
		_set_panes(true)
	elif step == 9:
		_b1 = root.get_viewport().get_texture().get_image()
		_occ.visible = true
	elif step == 12:
		_a1 = root.get_viewport().get_texture().get_image()
		_measure(_poses[_i], _a0, _b0, _a1, _b1)
	return false

var _b1: Image


func _setup() -> void:
	_cell = current_scene.get_node_or_null("ContainmentCell")
	if _cell == null:
		return
	_occ = _cell.get_node_or_null("Object12")
	_player = current_scene.get_node("Player")
	_cam = _player.get_node("Camera3D")
	for c in _cell.get_children():
		if c is MeshInstance3D and (c.name.begins_with("Pane") or c.name == "PortGlass"):
			_panes.append(c)
	# ⚠️ The occupant's own shadow is excluded. With it on, the diff also lights up wherever
	# its shadow falls — pixels whose "background" is a LIT floor — which inflated the mask
	# fivefold and dragged the background term up to meet the figure.
	for n in _all(_occ):
		if n is MeshInstance3D:
			(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var c3 := _cell.global_position
	# ⚠️ The booth's own half-extent + plinth overhang, as literals. Naming
	# `ContainmentCell.SIZE` here forces that script to compile before the autoloads are
	# registered in a `--script` SceneTree run, and it dies on `GameState`.
	var half := Vector2(1.07, 1.07)
	for r in RADII:
		for k in range(HEADINGS):
			var a := TAU * float(k) / float(HEADINGS)
			var p := c3 + Vector3(sin(a) * r, 0.0, cos(a) * r)
			if p.x < ROOM_MIN.x + PLAYER_R or p.x > ROOM_MAX.x - PLAYER_R:
				continue
			if p.z < ROOM_MIN.y + PLAYER_R or p.z > ROOM_MAX.y - PLAYER_R:
				continue
			if absf(p.x - c3.x) < half.x + PLAYER_R and absf(p.z - c3.z) < half.y + PLAYER_R:
				continue
			_poses.append({ "deg": rad_to_deg(a), "r": r, "pos": p })


func _set_panes(on: bool) -> void:
	for p in _panes:
		(p as MeshInstance3D).visible = on


func _place(pose: Dictionary) -> void:
	var p: Vector3 = pose["pos"]
	_player.global_position = p
	var aim := _cell.global_position + Vector3(0, AIM_Y, 0)
	var to := aim - (p + Vector3(0, EYE, 0))
	var flat := Vector3(to.x, 0.0, to.z)
	_player.rotation.y = atan2(-flat.x, -flat.z)
	_cam.rotation.x = atan2(to.y, flat.length())


func _mask(a: Image, b: Image) -> PackedByteArray:
	var cols := int(a.get_width() / 2)
	var rows := int(a.get_height() / 2)
	var raw := PackedByteArray()
	raw.resize(cols * rows)
	for gy in range(rows):
		for gx in range(cols):
			var ca := a.get_pixel(gx * 2, gy * 2)
			var cb := b.get_pixel(gx * 2, gy * 2)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > DIFF_EPS:
				raw[gy * cols + gx] = 1
	var out := PackedByteArray()
	out.resize(cols * rows)
	for gy in range(1, rows - 1):
		for gx in range(1, cols - 1):
			var i := gy * cols + gx
			if raw[i] == 1 and raw[i - 1] == 1 and raw[i + 1] == 1 \
					and raw[i - cols] == 1 and raw[i + cols] == 1:
				out[i] = 1
	return out


func _mean(mask: PackedByteArray, img: Image) -> float:
	var cols := int(img.get_width() / 2)
	var n := 0
	var s := 0.0
	for i in range(mask.size()):
		if mask[i] == 0:
			continue
		n += 1
		s += _lum(img.get_pixel((i % cols) * 2, int(i / cols) * 2))
	return (s / n) if n > 0 else 0.0


func _measure(pose: Dictionary, a0: Image, b0: Image, a1: Image, b1: Image) -> void:
	var m := _mask(a0, b0)
	var n := 0
	for i in range(m.size()):
		n += m[i]
	var occ := _mean(m, a1)
	var bg := _mean(m, b1)
	_rows.append({ "deg": pose["deg"], "r": pose["r"], "px": n, "occ": occ, "bg": bg })
	if int(pose["deg"]) % 45 == 0 and pose["r"] == RADII[0]:
		a1.save_png(OUT + "h%03d.png" % int(pose["deg"]))


func _ok(label: String, cond: bool, detail: String) -> void:
	if cond:
		return
	_fails += 1
	print("  FAIL  %s  (%s)" % [label, detail])


func _report() -> void:
	print("\n  r   deg     px   occupant   behind   occ/bg  contrast")
	var worst_contrast := 1.0
	var worst_ratio := 0.0
	for r in _rows:
		var ratio: float = (r["occ"] / r["bg"]) if r["bg"] > 0.0001 else 999.0
		var hi: float = maxf(r["occ"], r["bg"])
		var contrast: float = (absf(r["occ"] - r["bg"]) / hi) if hi > 0.0001 else 0.0
		print("%4.1f  %4d %6d   %8.5f %8.5f   %5.2f     %5.3f"
			% [r["r"], int(r["deg"]), r["px"], r["occ"], r["bg"], ratio, contrast])
		_ok("heading %d @ %.1f m shows the occupant" % [int(r["deg"]), r["r"]],
			r["px"] >= MIN_PIXELS, "%d px of silhouette" % r["px"])
		if r["px"] >= MIN_PIXELS:
			_ok("heading %d @ %.1f m: occupant is distinguishable" % [int(r["deg"]), r["r"]],
				contrast >= MIN_CONTRAST, "contrast %.3f < %.2f" % [contrast, MIN_CONTRAST])
			_ok("heading %d @ %.1f m: occupant is the DARK shape" % [int(r["deg"]), r["r"]],
				ratio <= MAX_RATIO, "occ/bg %.2f > %.2f" % [ratio, MAX_RATIO])
			worst_contrast = minf(worst_contrast, contrast)
			worst_ratio = maxf(worst_ratio, ratio)
	# ⚠️ Assert the SAMPLE. A filter that rejected every pose would print a clean table of
	# nothing and pass.
	_ok("enough reachable headings were measured", _rows.size() >= 18,
		"%d poses" % _rows.size())
	print("\nworst contrast %.3f (floor %.2f) · worst occ/bg %.2f (ceiling %.2f) · %d poses"
		% [worst_contrast, MIN_CONTRAST, worst_ratio, MAX_RATIO, _rows.size()])
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	quit(0 if _fails == 0 else 1)


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


static func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
