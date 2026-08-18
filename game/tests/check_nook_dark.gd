extends SceneTree

# The BreakerNook panel must be no brighter than the wall it hangs on.
#
#   Godot --headless --path game --script res://tests/check_nook_dark.gd
#
# Playtest 2026-08-16, capture 003, torch off, 9.4 m out: *"I am standing far away from the
# breaker and I see it. Should be darker"*. The whole design of that breaker is that it
# CANNOT be seen — the wing force-locks the flashlight and the panel is found by the audio
# beacon and the panel-hum meter. The frame the user photographed was essentially pure black
# with a legible pale rectangle in the middle of it.
#
# ⚠️ THE PREVIOUS PASS MEASURED THIS AND GOT IT WRONG, which is the reason this file exists.
# `screenshot_nook_panel.gd` reported "peak ~1.5/255, wall 0.0000" and the analysis called it
# negligible. Two mistakes: it compared against an ABSOLUTE floor instead of the LOCAL
# background (1.5/255 against 0.0000 is not dim, it is the only thing in the frame), and it
# averaged an 11x11 box at the panel's centre when the leak was the panel's bright BORDER.
# See ISSUES_SOLUTIONS Issue 62.
#
# The cause was in the art, not the code: `lab_breaker_panel.png` shipped as an opaque RGB
# PNG whose background was a BAKED ALPHA CHECKERBOARD — 20 % of its texels at near-white,
# and near-white is the brightest albedo obtainable in a level with no tonemapping and no
# glow, where ambient x albedo is all there is.
#
# The authoritative measurement is the rendered one (`screenshot_nook_panel.gd`, needs a
# display). This is its headless guard, and it asserts the two INPUTS that produced it:
#
#   1. the panel texture has no near-white background left in it, and its border ring is
#      dark — a re-baked checkerboard cannot get past either;
#   2. the panel's effective albedo (texel x the material's own tint, in LINEAR light,
#      which is what ambient multiplies) does not exceed the WALL's.
#
# Both are read from the shipping material, never typed in, so retuning the tint retunes the
# test with it.

# Fraction of texels allowed above this sRGB luminance. The raw asset was 20.05 % near-white.
const NEAR_WHITE := 0.90
const NEAR_WHITE_MAX_FRACTION := 0.01
# The outer 2 % ring of the texture. A transparency checkerboard always shows here: measured,
# the raw asset's border mean was 0.974 of full white, the flattened one's is 0.232.
const BORDER_FRACTION := 0.02
const BORDER_MEAN_MAX := 0.45

var _frame := 0
var _fails := 0
var _checks := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fails += 1
	print("  %s  %s%s" % ["PASS" if cond else "FAIL", label, ("   " + detail) if detail != "" else ""])


func _find(node: Node, pred: Callable) -> Node:
	if pred.call(node):
		return node
	for c in node.get_children():
		var f := _find(c, pred)
		if f:
			return f
	return null


func _srgb_to_linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


# Everything this test needs about one albedo texture, measured under one tint.
# `mean_linear` is the honest "how much ambient light can this surface throw back" figure —
# ambient is flat, so a surface's rendered brightness IS its linear albedo times a constant.
func _measure(img: Image, tint: Color) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var step: int = maxi(1, mini(w, h) / 512)
	var border: int = maxi(2, int(float(mini(w, h)) * BORDER_FRACTION))
	var tint_l := 0.2126 * tint.r + 0.7152 * tint.g + 0.0722 * tint.b
	var vals: Array[float] = []
	var near_white := 0
	var border_sum := 0.0
	var border_n := 0
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var c := img.get_pixel(x, y)
			var srgb: float = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			var lin: float = (0.2126 * _srgb_to_linear(c.r) + 0.7152 * _srgb_to_linear(c.g)
				+ 0.0722 * _srgb_to_linear(c.b)) * tint_l
			vals.append(lin)
			if srgb > NEAR_WHITE:
				near_white += 1
			if x < border or y < border or x >= w - border or y >= h - border:
				border_sum += srgb
				border_n += 1
			x += step
		y += step
	vals.sort()
	var n := vals.size()
	var sum := 0.0
	for v in vals:
		sum += v
	return {
		"n": n,
		"mean_linear": sum / float(maxi(1, n)),
		"p999_linear": vals[mini(n - 1, int(float(n) * 0.999))],
		"near_white_fraction": float(near_white) / float(maxi(1, n)),
		"border_mean": border_sum / float(maxi(1, border_n)),
	}


func _mat_of(node: Node) -> StandardMaterial3D:
	if node is CSGBox3D:
		return (node as CSGBox3D).material as StandardMaterial3D
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override:
			return mi.material_override as StandardMaterial3D
		if mi.get_surface_override_material_count() > 0:
			return mi.get_surface_override_material(0) as StandardMaterial3D
	return null


func _load_src(mat: StandardMaterial3D) -> Image:
	if not mat or not mat.albedo_texture:
		return null
	var path: String = mat.albedo_texture.resource_path
	if path == "" or not FileAccess.file_exists(path):
		return null
	return Image.load_from_file(path)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 8:
		return false

	print("--- nook breaker: darker than the wall it hangs on ---")
	var scene := current_scene
	var breaker := scene.get_node_or_null("Breaker_Nook")
	_ok("Breaker_Nook exists", breaker != null)
	if not breaker:
		return _finish()
	_ok("it does not glow (no indicator emission at all)", not bool(breaker.get("glows")))

	var panel := _find(breaker, func(n: Node) -> bool: return n is CSGBox3D) as CSGBox3D
	_ok("its panel exists", panel != null)
	if not panel:
		return _finish()
	var pmat := _mat_of(panel)
	_ok("the panel carries a StandardMaterial3D", pmat != null)
	if not pmat:
		return _finish()
	_ok("the panel does not self-illuminate", not pmat.emission_enabled)

	# The wall this thing is bolted to — read from the built geometry, not assumed.
	# RoomBuilder names every wall slab "Wall" (Godot then uniquifies), so match the prefix
	# and take the nearest one to the breaker — the wall it is actually bolted to.
	var wall: CSGBox3D = null
	var best := INF
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is CSGBox3D and String(n.name).begins_with("Wall"):
			var d: float = (n as CSGBox3D).global_position.distance_to(
				(breaker as Node3D).global_position)
			if d < best:
				best = d
				wall = n as CSGBox3D
	_ok("a built wall was found to compare against", wall != null,
		"" if not wall else String(wall.name))
	if not wall:
		return _finish()
	var wmat := _mat_of(wall)

	var pimg := _load_src(pmat)
	var wimg := _load_src(wmat)
	_ok("both source textures loaded", pimg != null and wimg != null)
	if pimg == null or wimg == null:
		return _finish()

	var p := _measure(pimg, pmat.albedo_color)
	var w := _measure(wimg, wmat.albedo_color)
	# ⚠️ Assert the sample size. "0 texels checked ... PASS" has happened in this project.
	_ok("sampled a real number of texels", int(p["n"]) > 10000 and int(w["n"]) > 10000,
		"panel %d, wall %d" % [int(p["n"]), int(w["n"])])
	print("     panel tint %s  mean_linear %.4f  p99.9 %.4f  near-white %.2f%%  border %.3f"
		% [pmat.albedo_color, p["mean_linear"], p["p999_linear"],
			100.0 * float(p["near_white_fraction"]), p["border_mean"]])
	print("     wall  tint %s  mean_linear %.4f  p99.9 %.4f  near-white %.2f%%  border %.3f"
		% [wmat.albedo_color, w["mean_linear"], w["p999_linear"],
			100.0 * float(w["near_white_fraction"]), w["border_mean"]])

	_ok("the panel art has no near-white background left in it",
		float(p["near_white_fraction"]) < NEAR_WHITE_MAX_FRACTION,
		"%.2f%% of texels over %.2f (limit %.2f%%) — the raw asset was 20.05%%"
			% [100.0 * float(p["near_white_fraction"]), NEAR_WHITE,
				100.0 * NEAR_WHITE_MAX_FRACTION])
	_ok("its border ring is dark (a baked alpha checkerboard cannot hide here)",
		float(p["border_mean"]) < BORDER_MEAN_MAX,
		"%.3f (limit %.2f) — the raw asset was 0.974" % [p["border_mean"], BORDER_MEAN_MAX])
	_ok("the panel bounces LESS ambient light than the wall around it",
		float(p["mean_linear"]) <= float(w["mean_linear"]),
		"panel %.4f vs wall %.4f" % [p["mean_linear"], w["mean_linear"]])
	_ok("and its brightest 0.1 % does not out-read the wall's either",
		float(p["p999_linear"]) <= float(w["p999_linear"]),
		"panel %.4f vs wall %.4f" % [p["p999_linear"], w["p999_linear"]])

	# POSITIVE CONTROL — proof these limits have teeth. The lit tint the OTHER two breakers
	# use is the same art under a 0.6 tint, and it must fail the "darker than the wall" pair.
	# (The checkerboard checks are proved by restoring assets_src/.../lab_breaker_panel_raw.png
	# and re-running: 20.05 % near-white, border 0.974 — both go red.)
	var lit := _measure(pimg, Color(0.6, 0.6, 0.62))
	_ok("control: the same art at the LIT tint would NOT pass the wall comparison",
		float(lit["p999_linear"]) > float(w["p999_linear"]),
		"lit p99.9 %.4f vs wall %.4f — if this fails, the two checks above prove nothing"
			% [lit["p999_linear"], w["p999_linear"]])
	return _finish()


func _finish() -> bool:
	print("%d checks, %d failed" % [_checks, _fails])
	print("NOOK-DARK PASS" if _fails == 0 else "NOOK-DARK FAIL")
	quit(1 if _fails > 0 else 0)
	return true
