extends SceneTree

# The House map minigame's SNARES and FRAGMENTS (how they are drawn) and its INSTANCE
# LIFETIME (what retires a maze, and what a close-and-reopen does to it).
#
#   Godot --headless --path game --script res://tests/check_maze_traps.gd
#
# Two 2026-08-16 changes, neither of which any existing test could see — `check_maze_gen.gd`
# and `check_maze_chase.gd` both instantiate the script outside any scene and never build the
# UI, and no scene smoke test ever opens the minigame at all.
#
# 1. SNARE LEGIBILITY (capture A2: *"the traps are not properly drawn — shall we make them
#    like freezers with blue color and the snow label?"*). The disc was drawn at
#    `SNARE_RADIUS * 1.6` diameter = radius 20.8 px against a trigger radius of 26 — 20 %
#    short in radius and 36 % in area, so you could be snared five pixels outside the only
#    thing you had been shown. And it was near-black brown on sepia parchment beside brown
#    walls, i.e. Issue 32 again.
# 2. THE INSTANCE PERSISTS across a close-and-reopen, and is retired only by a WIN or a
#    CATCH. ESC used to be a free re-roll; one human session spent 134 s shopping for an easy
#    maze while another cleared the same puzzle in 13 s.
#
# 3. THE OBJECTIVE IS TWO-STAGE (2026-08-16): collect every torn fragment, THEN reach the
#    mark. The mark is genuinely inert until the last one is in hand, the fragments RE-ARM on
#    a close-and-reopen exactly as the snares do (ESC must not become a checkpoint), and the
#    marks are drawn at their true pickup radius in a colour and a SHAPE that separate them
#    from everything else on the board.
#
# ⚠️ Both fail states AND the win are reached by driving the UI's own `_process()` across real
# frames — never by emitting `won` or `caught`. Setting `_player_pos` is the equivalent of
# moving the mouse; everything downstream (`_is_won()`, `_check_fragments()`, the catch
# radius, `_close()`, the signal) is the shipping path. ⚠️ Stage 5 is the positive control
# that makes the whole feature falsifiable: the player is put ON the mark with fragments
# still out, and the overlay must NOT close.

# The parchment the marks are drawn on. `house_map_maze_bg.png` when it exists, this when it
# does not — and the two are the same tone, which is the point: it is why brown-on-brown was
# invisible and why the assertion below is about CONTRAST, not about brightness.
const PARCHMENT := Color(0.78, 0.70, 0.55)
const MIN_CONTRAST := 0.45      # RGB-space distance; brown-on-brown measured ~0.15
const TIMEOUT := 40.0

var _t := 0.0
var _stage := 0
var _checks := 0
var _fails: Array[String] = []
var _scene: Node = null
var _map: Node = null
var _ui: Node = null
var _solo: Node = null

var _walls_a: Array = []
var _target_a := Vector2i.ZERO
var _monster_a := Vector2.ZERO
var _snares_a := 0
var _frags_a := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_2_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _find_named(node: Node, want: String, out: Array) -> void:
	if String(node.name) == want:
		out.append(node)
	for c in node.get_children():
		_find_named(c, want, out)


func _first_wall_colour() -> Color:
	# The real ColorRect the generator produced, not a constant — if the wall tint ever moves
	# toward the snare's, this measurement moves with it.
	var container: Node = _ui.get("_walls_container")
	if container:
		for c in container.get_children():
			if c is ColorRect and String(c.name) != "SnareGlyph0":
				return (c as ColorRect).color
	return Color(0.32, 0.22, 0.12)


func _contrast(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _rects_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not (a[i] as Rect2).is_equal_approx(b[i] as Rect2):
			return false
	return true


func _process(delta: float) -> bool:
	_t += delta

	if _stage == 0 and _t > 1.2:
		_scene = current_scene
		_map = _scene.get_node_or_null("HouseMap")
		_ok("the House map prop exists", _map != null)
		if not _map:
			_finish()
			return true
		_ui = _map.get("_ui")
		_ok("its minigame UI exists", _ui != null)
		if not _ui:
			_finish()
			return true
		_ok("no maze is live before it is ever opened",
			_ui.get("_instance_live") == false)
		_map.call("interact")
		_stage = 1
		_t = 0.0

	elif _stage == 1 and _t > 0.4:
		_ok("interacting opens the overlay", _ui.get("_ui_open") == true)
		_ok("…and that generates a maze", _ui.get("_instance_live") == true)
		_check_snare_visuals()
		_check_fragment_visuals()

		_walls_a = (_ui.get("_wall_rects") as Array).duplicate()
		_target_a = _ui.get("_target_cell")
		_monster_a = _ui.get("_monster_start")
		_snares_a = (_ui.get("_snares") as Array).size()
		_frags_a = (_ui.get("_fragments") as Array).size()
		_ok("the maze has walls, snares and fragments to compare",
			_walls_a.size() > 0 and _snares_a > 0 and _frags_a > 0,
			"%d wall rects, %d snares, %d fragments" % [_walls_a.size(), _snares_a, _frags_a])

		# ---- SPEND some of the instance, so the reopen assertions below are real ------------
		# Freeze the hunter for good (the head start counter is what gates its movement), so
		# teleporting the icon around cannot be interrupted by a catch.
		_ui.set("_monster_start_timer", 999.0)
		# Spring every snare at once. The reopen check then measures a genuine RE-ARM rather
		# than "nothing had happened yet".
		var no_snares: Array[Vector2] = []
		_ui.set("_snares", no_snares)
		# ⚠️ And park BOTH pursuers off the board. The catch test in `_process()` runs whether
		# or not they are ticking, and this scene is not seeded — a fragment that happened to
		# sit on the patroller's start cell would fail this test at random. `_reset_positions()`
		# restores both from their `*_start` values on the reopen below, which stage 3 asserts.
		var away := Vector2(-99999.0, -99999.0)
		_ui.set("_monster_pos", away)
		_ui.set("_patrol_pos", away)
		# And collect one fragment, through the real `_check_fragments()` path.
		if _frags_a > 0:
			_ui.set("_player_pos", (_ui.get("_fragments") as Array)[0])
		_stage = 2
		_t = 0.0

	elif _stage == 2 and _t > 0.4:
		_ok("walking onto a fragment collects it",
			(_ui.get("_fragments") as Array).size() == _frags_a - 1,
			"%d left of %d" % [(_ui.get("_fragments") as Array).size(), _frags_a])
		_ok("…and its drawn mark disappears with it",
			_count_named(_ui, "FragFill") == _frags_a - 1,
			"%d marks for %d fragments"
				% [_count_named(_ui, "FragFill"), (_ui.get("_fragments") as Array).size()])
		# ⚠️ The text is read into a local FIRST. `_ok()`'s detail argument is evaluated before
		# the call, so a null label would throw there even though the condition guards it.
		var readout: String = _label_text(_ui, "_counter_label")
		# ⚠️ N-AGNOSTIC. At the shipped `fragment_count` of 1 this collection is also the LAST
		# one, so the readout goes straight to the mark-is-open line and never shows "1 / N".
		# The assertion's intent is "the readout followed the collection", and pinning it to
		# one wording made it an assertion about N instead.
		_ok("…and the readout follows it",
			readout.contains("%d /" % (_frags_a - 1)) or readout.contains("REACH THE MARK"),
			"\"%s\"" % readout)
		# Put the map down. This is what ESC does — `_unhandled_input` -> `_close()`.
		_ui.call("_close")
		_stage = 3
		_t = 0.0

	elif _stage == 3 and _t > 0.4:
		_ok("closing puts the map down but does NOT retire the maze",
			_ui.get("_instance_live") == true)
		_map.call("interact")
		_ok("picking it up again resumes the SAME maze",
			_rects_equal(_ui.get("_wall_rects"), _walls_a),
			"%d rects then, %d now" % [_walls_a.size(), (_ui.get("_wall_rects") as Array).size()])
		_ok("…the same mark", _ui.get("_target_cell") == _target_a,
			"%s vs %s" % [_target_a, _ui.get("_target_cell")])
		_ok("…the same hunter start", (_ui.get("_monster_pos") as Vector2).is_equal_approx(_monster_a))
		_ok("…and every snare re-armed, including any already sprung",
			(_ui.get("_snares") as Array).size() == _snares_a,
			"%d of %d" % [(_ui.get("_snares") as Array).size(), _snares_a])
		# ⚠️ THE ONE THAT MATTERS FOR THE REDESIGN. If collected fragments survived a close,
		# ESC would be a checkpoint — bank a piece, put the map down, and the hunter is back
		# at its start with your progress kept. That is the opposite of what killing the
		# re-roll was for.
		_ok("…and every FRAGMENT re-armed, including the one already collected",
			(_ui.get("_fragments") as Array).size() == _frags_a,
			"%d of %d" % [(_ui.get("_fragments") as Array).size(), _frags_a])
		_ok("…and the player is back at the start, not where they left off",
			(_ui.get("_player_pos") as Vector2).is_equal_approx(
				_ui.call("_cell_center", _ui.get("_start_cell"))))

		# --- a CATCH, through the real _process() path --------------------------------------
		# Clear the head start and walk the icon onto the hunter. The catch test, the close and
		# the signal all belong to the UI; nothing here emits anything.
		_ui.set("_monster_start_timer", 0.0)
		_ui.set("_player_pos", _ui.get("_monster_pos"))
		_stage = 4
		_t = 0.0

	elif _stage == 4 and _t > 0.4:
		_ok("walking into the hunter closes the overlay", _ui.get("_ui_open") == false)
		_ok("…and RETIRES the maze", _ui.get("_instance_live") == false)
		_map.call("interact")
		var fresh_walls: Array = _ui.get("_wall_rects")
		var fresh_target: Vector2i = _ui.get("_target_cell")
		# ⚠️ Two 10x8 braided mazes agreeing on every wall rect AND the mark is not a
		# realistic coincidence; either quantity differing proves a regeneration happened.
		_ok("a retry is a brand-new maze",
			not _rects_equal(fresh_walls, _walls_a) or fresh_target != _target_a,
			"%d rects vs %d, mark %s vs %s" % [
				fresh_walls.size(), _walls_a.size(), fresh_target, _target_a])
		_ok("…with a full set of fragments re-armed, not the ones left over",
			(_ui.get("_fragments") as Array).size() == int(_ui.get("fragment_count")),
			"%d of %d" % [(_ui.get("_fragments") as Array).size(), int(_ui.get("fragment_count"))])
		_ui.call("_close")
		_stage = 5
		_t = 0.0

	elif _stage == 5 and _t > 0.4:
		# --- a WIN, on a standalone instance -------------------------------------------------
		# Deliberately not the prop's UI: `HouseMap._on_won()` queue_frees the prop, so the
		# flag could not be read on the far side of the frame that set it.
		var script: GDScript = load("res://scripts/maze_chase_ui.gd")
		_solo = script.new()
		_solo.name = "SoloMaze"
		_scene.add_child(_solo)
		_solo.call("open")
		_ok("a standalone instance opens and generates", _solo.get("_instance_live") == true)
		_ok("…with fragments still to collect",
			(_solo.get("_fragments") as Array).size() > 0,
			"%d armed" % (_solo.get("_fragments") as Array).size())
		# Freeze the hunter and disarm the snares — this stage is about the objective gate,
		# and a 1.2 s snare hold or a catch mid-teleport would only add flake.
		_solo.set("_monster_start_timer", 999.0)
		var none: Array[Vector2] = []
		_solo.set("_snares", none)
		var far := Vector2(-99999.0, -99999.0)
		_solo.set("_monster_pos", far)
		_solo.set("_patrol_pos", far)
		# ⚠️ THE POSITIVE CONTROL. Stand ON the mark with fragments still out.
		_solo.set("_player_pos", _solo.get("_target_pos"))
		_stage = 6
		_t = 0.0

	elif _stage == 6 and _t > 0.4:
		_ok("the mark is INERT while fragments remain — standing on it does nothing",
			_solo.get("_ui_open") == true and _solo.get("_instance_live") == true)
		_ok("…and it LOOKS shut", _solo.get("_target_seal") != null
			and (_solo.get("_target_seal") as CanvasItem).visible == true)
		_stage = 7
		_t = 0.0

	elif _stage == 7:
		# Collect them one at a time, each through the real `_check_fragments()` path.
		var frags: Array = _solo.get("_fragments")
		if not frags.is_empty():
			_solo.set("_player_pos", frags[0])
			if _t > 12.0:
				_ok("every fragment can be collected", false,
					"%d still out after 12 s" % frags.size())
				_finish()
				return true
		else:
			_ok("collecting the last fragment opens the mark",
				_solo.get("_target_seal") != null
					and (_solo.get("_target_seal") as CanvasItem).visible == false)
			var open_text: String = _label_text(_solo, "_counter_label")
			_ok("…and says so", open_text.contains("REACH THE MARK"), "\"%s\"" % open_text)
			_solo.set("_player_pos", _solo.get("_target_pos"))
			_stage = 8
			_t = 0.0

	elif _stage == 8 and _t > 0.4:
		_ok("reaching the mark with everything collected closes the overlay",
			_solo.get("_ui_open") == false)
		_ok("…and RETIRES the maze", _solo.get("_instance_live") == false)
		_ok("the tree was un-paused on the way out", paused == false)
		_finish()
		return true

	if _t > TIMEOUT:
		print("RESULT: FAIL — timed out at stage %d" % _stage)
		quit(1)
		return true
	return false


# B1 — a trap you can be caught five pixels outside of is a dice roll, not a decision.
func _check_snare_visuals() -> void:
	print("  -- snares: drawn at their true radius, and visible --")
	var consts: Dictionary = (_ui.get_script() as GDScript).get_script_constant_map()
	# ⚠️ Object.get() reads PROPERTIES, not consts (Issue 54) — a 0 here would make every
	# assertion below meaningless.
	var radius: float = float(consts.get("SNARE_RADIUS", 0.0))
	var fill_col: Color = consts.get("SNARE_FILL", Color.BLACK)
	var rim_col: Color = consts.get("SNARE_RIM", Color.WHITE)
	_ok("read SNARE_RADIUS from the script", radius > 1.0, "%.1f px" % radius)

	var fills: Array = []
	var rims: Array = []
	var glyphs: Array = []
	_find_named(_ui, "SnareFill", fills)
	_find_named(_ui, "SnareRim", rims)
	_find_named(_ui, "SnareGlyph0", glyphs)
	var expected: int = (_ui.get("_snares") as Array).size()
	# ⚠️ Assert the sample size. "0 snares checked … PASS" is exactly the vacuous green this
	# repo has shipped before.
	_ok("every live snare has a drawn mark", fills.size() == expected and expected > 0,
		"%d marks for %d snares" % [fills.size(), expected])
	_ok("…each with a dark rim to separate it from the parchment", rims.size() == expected)
	_ok("…and a frost glyph", glyphs.size() == expected)

	var wrong := 0
	for f in fills:
		var drawn_r: float = (f as Control).size.x / 2.0
		if absf(drawn_r - radius) > 0.51:
			wrong += 1
	_ok("the drawn disc IS the trigger radius", wrong == 0,
		"%d of %d marks drawn at the wrong size (was 20.8 px for a 26 px trigger)"
			% [wrong, fills.size()])

	# ⚠️ CONTRAST, not luminance (Issue 62): the old mark was Color(0.12,0.05,0.03) on sepia
	# parchment beside Color(0.32,0.22,0.12) walls — same hue family as both, and `modulate`
	# could not have rescued it because modulate MULTIPLIES.
	var wall_col := _first_wall_colour()
	var c_parch := _contrast(fill_col, PARCHMENT)
	var c_wall := _contrast(fill_col, wall_col)
	_ok("the mark contrasts with the parchment", c_parch >= MIN_CONTRAST,
		"distance %.2f (min %.2f)" % [c_parch, MIN_CONTRAST])
	_ok("…and with the maze walls", c_wall >= MIN_CONTRAST,
		"distance %.2f vs wall %s" % [c_wall, wall_col])
	_ok("…and the rim is darker than the fill it surrounds",
		rim_col.get_luminance() < fill_col.get_luminance(),
		"%.2f vs %.2f" % [rim_col.get_luminance(), fill_col.get_luminance()])


# The fragments are the new half of the objective, and they are drawn under the two rules the
# snares had to be taught the hard way: the drawn footprint IS the trigger footprint, and the
# colour comes from geometry because `modulate` multiplies (Issue 32). Plus one rule the
# snares did not need — the SILHOUETTE has to differ, because everything else on this board is
# a disc and shape is read before colour (Issue 35).
func _check_fragment_visuals() -> void:
	print("  -- fragments: drawn at their true radius, visible, and NOT another disc --")
	var consts: Dictionary = (_ui.get_script() as GDScript).get_script_constant_map()
	# ⚠️ Object.get() reads PROPERTIES, not consts (Issue 54) — a 0 here would make every
	# assertion below meaningless.
	var radius: float = float(consts.get("FRAGMENT_PICKUP_RADIUS", 0.0))
	var fill_col: Color = consts.get("FRAGMENT_FILL", Color.BLACK)
	var rim_col: Color = consts.get("FRAGMENT_RIM", Color.WHITE)
	var snare_col: Color = consts.get("SNARE_FILL", Color.WHITE)
	_ok("read FRAGMENT_PICKUP_RADIUS from the script", radius > 1.0, "%.1f px" % radius)

	var expected: int = (_ui.get("_fragments") as Array).size()
	# ⚠️ Assert the sample size FIRST. "0 fragments checked … PASS" would be this repo's
	# fourth vacuous green, and it would also be the two-stage objective silently absent.
	_ok("the maze placed fragments at all", expected == int(_ui.get("fragment_count")),
		"%d placed, fragment_count = %d" % [expected, int(_ui.get("fragment_count"))])
	if expected == 0:
		return

	var fills: Array = []
	var rims: Array = []
	_find_named(_ui, "FragFill", fills)
	_find_named(_ui, "FragRim", rims)
	_ok("every live fragment has a drawn mark", fills.size() == expected,
		"%d marks for %d fragments" % [fills.size(), expected])
	_ok("…each with a dark rim at the pickup radius", rims.size() == expected)

	var wrong := 0
	for r in rims:
		# The rim is the honest one: its radius is the pickup radius plus the rim pad.
		var drawn: float = (r as Control).size.x / 2.0 - float(consts.get("FRAGMENT_RIM_PAD", 0.0))
		if absf(drawn - radius) > 0.51:
			wrong += 1
	_ok("the drawn footprint IS the pickup radius", wrong == 0,
		"%d of %d marks drawn at the wrong size" % [wrong, rims.size()])

	# A square rotated 45° whose half-diagonal is the radius: size.x * sqrt(2)/2 == radius.
	var shape_wrong := 0
	for f in fills:
		var rect := f as ColorRect
		if not is_equal_approx(rect.rotation, deg_to_rad(45.0)):
			shape_wrong += 1
		elif absf(rect.size.x * 0.70710678 - radius) > 0.6:
			shape_wrong += 1
	_ok("…and the mark is a DIAMOND, not one more disc", shape_wrong == 0,
		"%d of %d wrong" % [shape_wrong, fills.size()])

	var wall_col := _first_wall_colour()
	_ok("the fragment contrasts with the parchment",
		_contrast(fill_col, PARCHMENT) >= MIN_CONTRAST,
		"distance %.2f (min %.2f)" % [_contrast(fill_col, PARCHMENT), MIN_CONTRAST])
	_ok("…and with the maze walls", _contrast(fill_col, wall_col) >= MIN_CONTRAST,
		"distance %.2f" % _contrast(fill_col, wall_col))
	# ⚠️ And with the SNARES specifically. A pickup and a hazard that read alike is a coin
	# flip, which is the same objection B1 raised against an invisible trap.
	_ok("…and it cannot be confused with a snare", _contrast(fill_col, snare_col) >= MIN_CONTRAST,
		"distance %.2f" % _contrast(fill_col, snare_col))
	_ok("…and the rim is darker than the fill it surrounds",
		rim_col.get_luminance() < fill_col.get_luminance(),
		"%.2f vs %.2f" % [rim_col.get_luminance(), fill_col.get_luminance()])

	# The readout, which is the only thing that explains the rule to the player.
	var readout: String = _label_text(_ui, "_counter_label")
	_ok("the objective readout exists", readout.contains("0 /"), "\"%s\"" % readout)
	_ok("…with a pip per fragment", (_ui.get("_pip_nodes") as Array).size() == expected,
		"%d pips" % (_ui.get("_pip_nodes") as Array).size())
	_ok("…and the mark starts sealed", _ui.get("_target_seal") != null
		and (_ui.get("_target_seal") as CanvasItem).visible == true)


# ⚠️ Never `bool(node.get("flag"))` and never a bare `.text` on a maybe-null node in a test:
# a missing property throws, the throw aborts _process before the stage counter AND before
# the timeout check, and the run then loops forever (Issue 45 — 28 minutes on a 30 s budget).
func _label_text(host: Node, prop: String) -> String:
	if host == null:
		return "<no host>"
	var lbl := host.get(prop) as Label
	if lbl == null:
		return "<no label>"
	return String(lbl.text)


func _count_named(node: Node, want: String) -> int:
	var out: Array = []
	_find_named(node, want, out)
	return out.size()


func _finish() -> void:
	print("")
	print("%d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		for f in _fails:
			print("  FAIL: " + f)
		print("RESULT: FAIL")
		quit(1)
