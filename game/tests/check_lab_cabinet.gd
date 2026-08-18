extends SceneTree

# The Records filing bank is a SEARCH: eight drawers, one page, no penalty for looking.
#
#   Godot --headless --path game --script res://tests/check_lab_cabinet.gd
#
# Playtest 2026-08-16, second replay, standing at the cabinets: *"Maybe we can do it in a
# way I could open all the boxes and only one would contain the note?"*. Before this the
# bank had one openable drawer on one of the two units, and it opened straight into the
# page.
#
# What this asserts, and why each one is here rather than being obvious:
#
#   * EVERY drawer opens, from a pose a player can actually hold (1.1 m back, 25 deg off
#     axis, aiming at the drawer's own FACE MESH — never at its collider, which is what let
#     an earlier reach test pass against colliders nobody could hit). A search with two dead
#     drawers and six that do not respond is worse than no search at all.
#   * EXACTLY ONE holds the page. Not "at least one" — two would make the second one a
#     duplicate journal entry, none would make the level's only Flood hint unreachable.
#   * An empty drawer costs NOTHING and SAYS nothing. No panic, no note, no journal entry,
#     and — since the 2026-08-16 verification replay — no on-screen text either: *"What for
#     to write these messages? They are not needed, the player will see there is nothing in
#     there"*. The whole design of this prop is that the price of looking in the wrong place
#     is the looking, and this project's standing rule is to stop adding panic terms.
#     ⚠️ The "says nothing" half is counted, not assumed: `ScreenText` parents its CanvasLayer
#     to the TREE ROOT, so the labels living outside the current scene are countable and a
#     toast moves that count. Restoring the toast turns that check red.
#   * The placement MOVES between runs, and SURVIVES a back-door return. Those two pull in
#     opposite directions and both matter: a fixed slot makes the search a walk the second
#     time the level is played (and a death restarts this level), while re-rolling it on a
#     return would mark "already searched" against an answer that has moved — KONTUR's
#     `_dark_x` rule.
#
# ⚠️ THE TOGGLE (added 2026-08-16, third replay). J-capture in Records: *"There is a bug - I
# cannot see what is under the top storages. I need to be able to close them by pressing the
# E button"*. An open drawer stands 0.34 m into the room and a standing player aims DOWN at
# the slots beneath it, so an open drawer shadows them — the bank blinded itself when searched
# top-down. What this file now asserts, and why each line is not obvious:
#
#   * E on an open drawer CLOSES it, through the real ray + can_interact() + interact() path.
#   * With it shut again, EVERY drawer in the bank answers E from a standing eye position —
#     counted with a denominator, because "a drawer answered" is how 2-of-8 passed as green
#     once already (Issue 65).
#   * The page's grab collider tracks the drawer in BOTH directions: disabled while shut,
#     enabled while open, and disabled AGAIN if the drawer closes with the page still in it.
#     That last one is Issue 66 exactly — a live grab volume inside a shut drawer makes the
#     one drawer holding the level's hint impossible to open, intermittently, depending on
#     which slot the run rolled.
#   * Closing RESETS NOTHING: a page already taken does not come back and is not archived a
#     second time. (There was a `searched` flag here too. It existed only to stop the flavour
#     line repeating, so it went with the flavour line rather than staying as a field nobody
#     reads — hence no assertions about it any more.)
#
# ⚠️ Duck-typed throughout. Naming a game class in a SceneTree script compiles it before the
# autoloads exist, which breaks the level under measurement (walk_lab_wing.gd:147).

const RESEEDS := 8            # scene reloads used to prove the placement is randomised
const SLIDE_WAIT := 1.0       # > LabCabinetDrawer.SLIDE_TIME (0.55) and CLOSE_TIME (0.45)
const HARD_TIMEOUT := 180.0   # a phase machine that stops advancing must FAIL, not hang

var _frame := 0
var _elapsed := 0.0
var _fails := 0
var _checks := 0
var _phase := "load"
var _t0 := 0.0
var _gs: Node
var _note_ui: Node
var _drawers: Array = []
var _seen: Dictionary = {}
var _reload := 0
var _empty: Node = null
var _panic_before := 0.0
var _reach_ok := 0
var _reach_tried := 0
var _saved: Dictionary = {}
var _holder: Node = null
var _empty_shut_z := 0.0
var _empty_open_z := 0.0
var _reach_while_open := -1
var _journal_after_take := -1
var _labels_before := -1


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fails += 1
	print("  %s  %s%s" % ["PASS" if cond else "FAIL", label, ("   " + detail) if detail != "" else ""])


func _walk(node: Node, pred: Callable, out: Array) -> void:
	if pred.call(node):
		out.append(node)
	for c in node.get_children():
		_walk(c, pred, out)


func _all_drawers() -> Array:
	var out: Array = []
	_walk(current_scene, func(n: Node) -> bool:
		return n.has_method("has_note") and n.has_method("is_open") and n.has_method("open_instantly"),
		out)
	return out


func _aim_from(player: CharacterBody3D, aim: Vector3, dist: float, deg: float) -> void:
	var offset := Vector3(sin(deg_to_rad(deg)), 0.0, cos(deg_to_rad(deg))) * dist
	player.global_position = Vector3(aim.x + offset.x, 0.1, aim.z + offset.z)
	player.ai_active = true
	player.ai_look_at(aim)
	player.ai_interact_target()


func _face_of(drawer: Node) -> Node3D:
	for c in drawer.get_children():
		if c is MeshInstance3D and String(c.name) == "DrawerFace":
			return c
	return null


# The page object lying in a drawer, if it is still there.
func _page_of(drawer: Node) -> Node:
	for c in drawer.get_children():
		if String(c.name) == "HintPage":
			return c
	return null


# Its grab volume. ⚠️ Read as a real property off a real CollisionShape3D — never
# `bool(node.get("flag"))`, which throws on a missing property and hangs the run (Issue 45).
func _page_collider(drawer: Node) -> CollisionShape3D:
	var page := _page_of(drawer)
	if page == null:
		return null
	for c in page.get_children():
		if c is CollisionShape3D:
			return c
	return null


# Every Label currently on screen from OUTSIDE the level scene. ScreenText.toast/caption/
# scrawl all parent their CanvasLayer to the tree root, so this counts exactly the transient
# text a prop can put in front of the player — and nothing the level's own HUD owns.
func _root_labels() -> int:
	var n := 0
	for c in root.get_children():
		if c == current_scene:
			continue
		var found: Array = []
		_walk(c, func(x: Node) -> bool: return x is Label, found)
		n += found.size()
	return n


func _mesh_named(drawer: Node, want: String) -> Node3D:
	for c in drawer.get_children():
		if c is MeshInstance3D and String(c.name) == want:
			return c
		var deep := _mesh_named(c, want)
		if deep:
			return deep
	return null


# How many of the bank's drawers answer E right now, each aimed at its OWN face mesh from a
# standing pose. The denominator is the point: this is the measurement that caught Issue 65.
func _reach_all(player: CharacterBody3D) -> int:
	var n := 0
	for d in _drawers:
		var f := _face_of(d)
		if not f:
			continue
		_aim_from(player, f.global_position, 1.1, 25.0)
		if player.ai_interact_target() == d:
			n += 1
	return n


# Aim at a drawer's own face and press E, through the shipping path.
func _press(player: CharacterBody3D, drawer: Node) -> void:
	var f := _face_of(drawer)
	if not f:
		return
	_aim_from(player, f.global_position, 1.1, 25.0)
	player.ai_interact()
	_t0 = _elapsed


func _process(delta: float) -> bool:
	_frame += 1
	_elapsed += delta
	if _frame < 10:
		return false
	if not _gs:
		_gs = root.get_node_or_null("/root/GameState")
		_note_ui = root.get_node_or_null("/root/NoteUI")

	if _elapsed > HARD_TIMEOUT and _phase != "done":
		_ok("the test finished inside %.0f s" % HARD_TIMEOUT, false, "stuck in phase '%s'" % _phase)
		_phase = "done"

	match _phase:
		"load": _do_load()
		"empty_wait": _do_empty_wait()
		"close_wait": _do_close_wait()
		"reopen_wait": _do_reopen_wait()
		"holder_wait": _do_holder_wait()
		"page_open_wait": _do_page_open_wait()
		"page_close_wait": _do_page_close_wait()
		"take_open_wait": _do_take_open_wait()
		"take_wait": _do_take_wait()
		"taken_close_wait": _do_taken_close_wait()
		"taken_reopen_wait": _do_taken_reopen_wait()
		"reseed": _do_reseed()
		"persist_load": _do_persist_load()
		"done":
			print("%d checks, %d failed" % [_checks, _fails])
			print("LAB-CABINET PASS" if _fails == 0 else "LAB-CABINET FAIL")
			quit(1 if _fails > 0 else 0)
			return true
	return false


func _do_load() -> void:
	print("--- Records filing bank: eight drawers, one page ---")
	_drawers = _all_drawers()
	_ok("the bank has a real number of drawers", _drawers.size() >= 8,
		"%d found" % _drawers.size())
	if _drawers.size() < 2:
		_phase = "done"
		return

	var holders := 0
	for d in _drawers:
		if bool(d.call("has_note")):
			holders += 1
	_ok("EXACTLY ONE of them holds the page", holders == 1, "%d holders" % holders)

	# Reach: every drawer, from a realistic pose, aiming at its own mesh.
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	for d in _drawers:
		var face := _face_of(d)
		if not (player and face):
			continue
		_reach_tried += 1
		_aim_from(player, face.global_position, 1.1, 25.0)
		if player.ai_interact_target() == d:
			_reach_ok += 1
	_ok("every drawer answers E from 1.1 m and 25 deg off-axis",
		_reach_tried >= 8 and _reach_ok == _reach_tried,
		"%d of %d" % [_reach_ok, _reach_tried])

	# Open an EMPTY one and prove it costs nothing.
	# ⚠️ The TOP drawer of a cabinet, not just the first empty one found: the whole complaint
	# is that an open drawer hides the ones UNDER it, so the shadow only exists if the one
	# left open has drawers below it.
	_empty = null
	for d in _drawers:
		if not bool(d.call("has_note")) and int(d.get("index")) == 0:
			_empty = d
			break
	if not _empty:
		for d in _drawers:
			if not bool(d.call("has_note")):
				_empty = d
				break
	for d in _drawers:
		if bool(d.call("has_note")):
			_holder = d
	# ⚠️ Recorded HERE, before the toggle phases take the page — "none" is not a placement, and
	# counting it would let a run with no page at all inflate the randomisation evidence.
	_seen[_slot_signature()] = true
	_ok("there is an empty drawer to open", _empty != null)
	if not _empty or not player:
		_phase = "done"
		return
	if _gs:
		_gs.journal.clear()
	_empty_shut_z = _empty.global_position.z
	_panic_before = float(player.get_panic_ratio())
	_labels_before = _root_labels()
	_press(player, _empty)
	_phase = "empty_wait"


func _do_empty_wait() -> void:
	if _elapsed - _t0 < 1.2:
		return
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	_ok("the empty drawer opened", bool(_empty.call("is_open")))
	_ok("opening an empty drawer shows no note", not bool(_note_ui.get("is_open")))
	_ok("it archives nothing", _gs == null or _gs.journal.is_empty(),
		"journal has %d" % [0 if _gs == null else _gs.journal.size()])
	# ⚠️ The panic bar is the thing this prop is forbidden to touch. Measured across the
	# whole slide, not sampled once: a per-frame drip would show up here.
	var after := float(player.get_panic_ratio())
	_ok("and it costs NO panic", after <= _panic_before + 0.001,
		"panic %.4f -> %.4f" % [_panic_before, after])
	# ⚠️ THE ASSERTION THIS ROUND EXISTS FOR: an empty drawer puts NO text on the screen. The
	# drawer sliding out with nothing in the tray is the whole message.
	var labels_after := _root_labels()
	_ok("and it prints NO on-screen line — the empty tray is the message",
		labels_after <= _labels_before,
		"root labels %d -> %d" % [_labels_before, labels_after])

	# --- the toggle ------------------------------------------------------------------
	_empty_open_z = _empty.global_position.z
	_ok("it actually travelled out", absf(_empty_open_z - _empty_shut_z) > 0.3,
		"z %.3f -> %.3f" % [_empty_shut_z, _empty_open_z])
	_aim_from(player, _face_of(_empty).global_position, 1.1, 25.0)
	_ok("an OPEN drawer offers E again — the toggle exists",
		player.ai_interact_target() == _empty,
		"ray saw %s" % [player.ai_interact_target()])
	# The defect itself, measured rather than asserted: with one drawer hanging out, how much
	# of the bank can a standing player still reach? This is the denominator for the check in
	# _do_close_wait, and it is what the J-capture photographed.
	_reach_while_open = _reach_all(player)
	print("  MEASURED  with one drawer open, %d of %d drawers in the bank answer E"
		% [_reach_while_open, _drawers.size()])
	_press(player, _empty)
	_phase = "close_wait"


# ⚠️ THE ASSERTION THIS ROUND EXISTS FOR. E on an open drawer must put it back, through the
# real ray -> can_interact() -> interact() path, and the bank must become legible again.
func _do_close_wait() -> void:
	if _elapsed - _t0 < SLIDE_WAIT:
		return
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	_ok("pressing E on an open drawer CLOSES it", not bool(_empty.call("is_open")))
	_ok("and it travels all the way back to where it started",
		absf(_empty.global_position.z - _empty_shut_z) < 0.005,
		"z %.3f (open %.3f, shut %.3f)"
			% [_empty.global_position.z, _empty_open_z, _empty_shut_z])
	var reach_after := _reach_all(player)
	_ok("with it shut, EVERY drawer answers E again from a standing eye position",
		reach_after == _drawers.size(),
		"%d of %d shut, versus %d of %d while it was open"
			% [reach_after, _drawers.size(), _reach_while_open, _drawers.size()])
	var after := float(player.get_panic_ratio())
	_ok("and closing costs NO panic and archives nothing",
		after <= _panic_before + 0.001 and (_gs == null or _gs.journal.is_empty()),
		"panic %.4f, journal %d" % [after, 0 if _gs == null else _gs.journal.size()])
	_press(player, _empty)
	_phase = "reopen_wait"


func _do_reopen_wait() -> void:
	if _elapsed - _t0 < SLIDE_WAIT:
		return
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	_ok("it opens again", bool(_empty.call("is_open")))
	var labels_reopen := _root_labels()
	_ok("re-opening it still archives nothing, costs nothing and says nothing",
		(_gs == null or _gs.journal.is_empty())
			and float(player.get_panic_ratio()) <= _panic_before + 0.001
			and labels_reopen <= _labels_before,
		"root labels %d -> %d" % [_labels_before, labels_reopen])
	# Tidy it away so it cannot shadow the holder's assertions below.
	_press(player, _empty)
	_phase = "holder_wait"


# --- the page's grab collider, both directions (Issue 66) ----------------------------

func _do_holder_wait() -> void:
	if _elapsed - _t0 < SLIDE_WAIT:
		return
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	_ok("the empty drawer is shut again", not bool(_empty.call("is_open")))
	if _holder == null:
		_ok("a drawer holding the page was found", false)
		_phase = "reseed"
		_t0 = _elapsed
		change_scene_to_file("res://scenes/level_1.tscn")
		return
	var col := _page_collider(_holder)
	_ok("the page is a real object with a real grab volume", col != null)
	if col == null:
		_phase = "reseed"
		_t0 = _elapsed
		change_scene_to_file("res://scenes/level_1.tscn")
		return
	_ok("the page's grab collider is DISABLED while its drawer is shut", col.disabled)
	# The symptom Issue 66 actually produced: the one drawer holding the level's only Flood
	# hint could not be opened at all, because the page inside it took the ray and then
	# refused it.
	_aim_from(player, _face_of(_holder).global_position, 1.1, 25.0)
	_ok("so the shut drawer holding it still answers E",
		player.ai_interact_target() == _holder,
		"ray saw %s" % [player.ai_interact_target()])
	_press(player, _holder)
	_phase = "page_open_wait"


func _do_page_open_wait() -> void:
	if _elapsed - _t0 < SLIDE_WAIT:
		return
	_ok("the drawer holding the page opened", bool(_holder.call("is_open")))
	var col := _page_collider(_holder)
	_ok("the page's grab collider is ENABLED once the drawer is open",
		col != null and not col.disabled)
	_ok("and the drawer steps aside while the page is still in it — the page is what E is for",
		not bool(_holder.call("can_interact")))
	# The defensive direction: close it with the page still inside. A player cannot reach this
	# (can_interact() refuses above), the restore path and the level can, and if the collider
	# were left live this is the state that becomes an unopenable drawer.
	_holder.call("close")
	_t0 = _elapsed
	_phase = "page_close_wait"


func _do_page_close_wait() -> void:
	if _elapsed - _t0 < SLIDE_WAIT:
		return
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	_ok("closing with the page still inside puts the drawer back and KEEPS the page",
		not bool(_holder.call("is_open")) and bool(_holder.call("has_note")))
	var col := _page_collider(_holder)
	_ok("and the page's grab collider goes back to DISABLED",
		col != null and col.disabled)
	_aim_from(player, _face_of(_holder).global_position, 1.1, 25.0)
	_ok("so the drawer is openable again rather than sealed by its own contents",
		player.ai_interact_target() == _holder,
		"ray saw %s" % [player.ai_interact_target()])
	_press(player, _holder)
	_phase = "take_open_wait"


# --- taken-state survives a close/reopen cycle ---------------------------------------

func _do_take_open_wait() -> void:
	if _elapsed - _t0 < SLIDE_WAIT:
		return
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	_ok("the drawer re-opened on the page", bool(_holder.call("is_open")))
	var sheet := _mesh_named(_holder, "Sheet")
	_ok("the page is visible in the tray", sheet != null)
	if sheet == null:
		_phase = "reseed"
		_t0 = _elapsed
		change_scene_to_file("res://scenes/level_1.tscn")
		return
	_aim_from(player, sheet.global_position, 0.85, 20.0)
	var target: Node = player.ai_interact_target()
	_ok("the press finds the PAGE, not the drawer",
		target != null and target != _holder, "ray saw %s" % [target])
	player.ai_interact()
	_t0 = _elapsed
	_phase = "take_wait"


func _do_take_wait() -> void:
	if _elapsed - _t0 < 0.5:
		return
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	_ok("taking it opened the note", bool(_note_ui.get("is_open")))
	# ⚠️ NoteUI pauses the tree, and a paused tree does not advance the close tween. Drop it
	# before asking the drawer to move, or the next phase measures a drawer that never left.
	_note_ui.call("_close")
	_journal_after_take = 0 if _gs == null else _gs.journal.size()
	_ok("and it was archived exactly once", _journal_after_take == 1,
		"journal has %d" % _journal_after_take)
	_ok("the drawer is empty and now offers to close",
		not bool(_holder.call("has_note")) and bool(_holder.call("can_interact")))
	_press(player, _holder)
	_phase = "taken_close_wait"


func _do_taken_close_wait() -> void:
	if _elapsed - _t0 < SLIDE_WAIT:
		return
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	_ok("an emptied drawer closes on E like any other", not bool(_holder.call("is_open")))
	_press(player, _holder)
	_phase = "taken_reopen_wait"


func _do_taken_reopen_wait() -> void:
	if _elapsed - _t0 < SLIDE_WAIT:
		return
	_ok("it opens again", bool(_holder.call("is_open")))
	_ok("and the page you already took does NOT come back",
		not bool(_holder.call("has_note")) and _page_of(_holder) == null)
	_ok("nor is it archived a second time",
		(0 if _gs == null else _gs.journal.size()) == _journal_after_take,
		"journal has %d" % [0 if _gs == null else _gs.journal.size()])
	_phase = "reseed"
	_t0 = _elapsed
	change_scene_to_file("res://scenes/level_1.tscn")


# Which (cabinet, drawer) is holding it, as a string, so repeats are countable.
func _slot_signature() -> String:
	var sig := "none"
	for d in _all_drawers():
		if bool(d.call("has_note")):
			sig = "%s/%s" % [d.get_parent().name, d.name]
	return sig


func _do_reseed() -> void:
	if _elapsed - _t0 < 0.4 or current_scene == null:
		return
	_seen[_slot_signature()] = true
	_reload += 1
	_t0 = _elapsed
	if _reload < RESEEDS:
		change_scene_to_file("res://scenes/level_1.tscn")
		return
	_ok("the page moves between runs", _seen.size() >= 2,
		"%d distinct placements over %d builds: %s" % [_seen.size(), RESEEDS + 1, _seen.keys()])

	# Persistence: capture this build's state, then reload and assert it came back.
	var scene := current_scene
	_ok("the level implements save_progress()", scene.has_method("save_progress"))
	if not scene.has_method("save_progress"):
		_phase = "done"
		return
	# Open one drawer first, so "left open" has something to restore.
	var d0: Node = _all_drawers()[0]
	d0.call("open_instantly")
	_saved = scene.call("save_progress")
	_ok("the snapshot records where the page is",
		int(_saved.get("hint_cab", -1)) >= 0 and int(_saved.get("hint_slot", -1)) >= 0,
		"cab %s slot %s" % [_saved.get("hint_cab"), _saved.get("hint_slot")])
	_ok("and which drawers were left open",
		_saved.get("drawers_opened", []).size() >= 1,
		"%s" % [_saved.get("drawers_opened", [])])
	if _gs:
		_gs.save_level_progress(1, _saved)
	_t0 = _elapsed
	_phase = "persist_load"
	change_scene_to_file("res://scenes/level_1.tscn")


func _do_persist_load() -> void:
	if _elapsed - _t0 < 0.4 or current_scene == null:
		return
	var want := "RecordsCabinet%d/Drawer%d" % [int(_saved.get("hint_cab", -1)),
		int(_saved.get("hint_slot", -1))]
	# ⚠️ This pair is what stops a future "just re-roll it, nobody will notice". A re-roll
	# would agree with the snapshot 1 build in 8 by luck; the reseed block above has already
	# shown the placement really is random, so agreement here is not a coincidence.
	_ok("a back-door return restores the SAME drawer, it does not re-roll",
		_slot_signature() == want, "wanted %s, got %s" % [want, _slot_signature()])
	var reopened := false
	for d in _all_drawers():
		if bool(d.call("is_open")):
			reopened = true
	_ok("and the drawers left open come back open", reopened)
	_ok("sampled a real number of drawers overall", _reach_tried >= 8,
		"%d drawers reached-tested, %d scene builds" % [_reach_tried, RESEEDS + 2])
	_phase = "done"
