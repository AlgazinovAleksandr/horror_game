extends SceneTree

# The notes journal (TAB): every non-trap note you read is kept and can be re-read.
#   Godot --headless --path game --script res://tests/check_journal.gd
#
# This exists because the game hides answers across level boundaries on purpose — all
# of KONTUR's gates are hinted in levels 1-4, and BACKLOG #24 moved the roster code out
# to two notes in the Backrooms Flood. Without a journal the only recovery from "I
# walked past a note" is replaying whole levels, which is the complaint in BACKLOG #30.
#
# The assertion that matters most is the NEGATIVE one: trap notes must never be
# archived. A trap note is read-to-die (+12 panic/s while open); a safely re-readable
# copy would let the player open it in the journal, read to the end, learn the text and
# take no damage — deleting the mechanic rather than supporting it.

var _frame := 0
var _stage := 0
var _fails := 0
var _gs: Node
var _ui: Node
# ⚠️ Autoloads must be fetched by PATH in a --script SceneTree: naming `NoteUI` or
# `GameState` as an identifier is a COMPILE error here, because the file is parsed
# before autoloads are registered. Likewise `get_tree()` — in a SceneTree script `self`
# IS the tree, so it is `paused`, not `get_tree().paused`.
var _note_ui: Node


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_2_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails += 1


func _titles() -> Array:
	var out: Array = []
	for e in _gs.get("journal"):
		out.append(e.get("title", ""))
	return out


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 10:
		return false
	# ⚠️ TWO FRAMES, and it has to be. `open_journal()` sets `_block_close = true` and clears it
	# with `set_deferred()` (Issue 3 — the TAB that opened the panel must not close it again in
	# the same frame). A SceneTree script's `_process` runs BEFORE node processing and before
	# the deferred flush, so a TAB pushed in the same call is legitimately swallowed. Pressing
	# it on the next frame is what a player does; doing it in one frame measures the guard.
	if _stage == 1:
		return _tab_close()
	_gs = root.get_node_or_null("/root/GameState")
	_ui = root.get_node_or_null("/root/JournalUI")
	_note_ui = root.get_node_or_null("/root/NoteUI")
	_ok("GameState autoload present", _gs != null)
	_ok("JournalUI autoload registered", _ui != null)
	_ok("NoteUI autoload present", _note_ui != null)
	if not (_gs and _ui and _note_ui):
		quit(1)
		return true
	_gs.get("journal").clear()

	print("--- the House's notes ---")
	var safe: Array[Node] = []
	var traps: Array[Node] = []
	var note_script: GDScript = load("res://scripts/note.gd")
	_walk(current_scene, note_script, safe, traps)
	_ok("found safe notes", safe.size() >= 3, "%d" % safe.size())
	_ok("found trap notes", traps.size() >= 1, "%d" % traps.size())

	print("--- reading them ---")
	for n in safe:
		n.call("interact")
		_note_ui.call("_close")
	_ok("every safe note archived", _gs.get("journal").size() == safe.size(),
		"%d archived / %d read" % [_gs.get("journal").size(), safe.size()])

	var before: int = _gs.get("journal").size()
	for n in traps:
		n.call("interact")
		_note_ui.call("_close")
	_ok("trap notes are NOT archived", _gs.get("journal").size() == before,
		"<- a re-readable trap note would delete the read-to-die mechanic")

	print("--- re-reading the same note does not duplicate it ---")
	safe[0].call("interact")
	_note_ui.call("_close")
	_ok("no duplicate entry", _gs.get("journal").size() == before)

	print("--- entries carry the level they came from ---")
	var all_level_2 := true
	for e in _gs.get("journal"):
		if int(e.get("level", -1)) != 2:
			all_level_2 = false
	_ok("all entries tagged level 2 (The House)", all_level_2)
	_ok("entries have a title", not _titles().has(""))

	print("--- the overlay opens, and refuses when another UI owns the screen ---")
	_ok("can_open() while free", _ui.call("can_open") == true)
	_ui.call("open_journal")
	_ok("is_open after open_journal()", _ui.get("is_open") == true)
	_ok("the tree is paused", paused == true)
	_ui.call("_close")
	_ok("closed cleanly", _ui.get("is_open") == false and paused == false)

	# ── the arrows must work WITHOUT clicking first ──────────────────────────────────────
	#
	# Reported in two consecutive playtests (2026-08-16 captures A5 and B3): *"When I press
	# the tab I cannot navigate between notes using arrows on my keyboard. I need to click
	# first and only after that arrows are available."*
	#
	# `ItemList.select()` neither emits `item_selected` nor takes focus, and nothing set
	# `focus_mode` — which defaults to FOCUS_NONE — so the viewport had no focused Control to
	# route `ui_up`/`ui_down` to and the keys went nowhere.
	#
	# ⚠️ AND THE OBVIOUS FIX HAS A TRAP, which is why the second half of this block exists.
	# TAB is `ui_focus_next`; the GUI layer consumes it before `_unhandled_input` is reached as
	# soon as ANY Control has focus. Granting focus without moving the close handler into
	# `_input()` fixes the arrows and silently breaks TAB-to-close.
	#
	# ⚠️ `Window.push_input()` is the only way to press a key headless — `Input.parse_input_event()`
	# does not work without a display server.
	print("--- keyboard navigation, with no click ---")
	_ui.call("open_journal")
	var list: ItemList = _ui.get("_list")
	var body: RichTextLabel = _ui.get("_text")
	_ok("the list and the page pane exist", list != null and body != null)
	if list and body:
		_ok("there is more than one entry to navigate",
			list.item_count >= 2, "%d entries" % list.item_count)
		_ok("the list is focusable at all", list.focus_mode != Control.FOCUS_NONE)
		_ok("it has keyboard focus straight after open_journal(), with NO click",
			list.has_focus())
		var sel_before: int = list.get_selected_items()[0] if list.get_selected_items().size() > 0 else -1
		var text_before: String = body.text
		_ok("something is selected to start from", sel_before >= 0, "index %d" % sel_before)
		root.push_input(_key(KEY_DOWN))
		var sel_after: int = list.get_selected_items()[0] if list.get_selected_items().size() > 0 else -1
		_ok("ui_down moves the selection", sel_after == sel_before + 1,
			"%d -> %d" % [sel_before, sel_after])
		# ⚠️ The selection moving is not enough — `select()` moves it without emitting
		# `item_selected`, so the page could stay on the old note forever. Assert the TEXT.
		_ok("…and the page on the right follows it", body.text != text_before,
			"'%s…' -> '%s…'" % [text_before.substr(0, 24), body.text.substr(0, 24)])
		root.push_input(_key(KEY_UP))
		var sel_back: int = list.get_selected_items()[0] if list.get_selected_items().size() > 0 else -1
		_ok("ui_up comes back", sel_back == sel_before, "%d -> %d" % [sel_after, sel_back])
	# The panel stays open; TAB is pressed on the NEXT frame — see the note in _process().
	_stage = 1
	return false


func _tab_close() -> bool:
	var list: ItemList = _ui.get("_list")
	# ⚠️ THE SECOND HALF OF THE A4 FIX. TAB is `ui_focus_next`'s default binding, so the moment
	# a Control has focus the GUI layer consumes it — a `grab_focus()` alone would fix the
	# arrows and make the journal impossible to close. The close handler lives in `_input()`
	# with `set_input_as_handled()` precisely to get in front of that.
	root.push_input(_key(KEY_TAB))
	_ok("TAB still closes it even though the list has focus",
		_ui.get("is_open") == false and paused == false,
		"if this is red, ui_focus_next ate the key before _input() saw it")
	if list:
		_ok("…and focus is released on the way out", not list.has_focus())

	_note_ui.call("show_note", "a note is already open", 0.0)
	_ok("refuses to open over a note", _ui.call("can_open") == false)
	_note_ui.call("_close")

	# ── the feature has to be DISCOVERABLE ───────────────────────────────────────────
	#
	# Everything above passed for several sessions while NOTHING IN THE GAME EVER MENTIONED
	# TAB. Grepping every script found the key named only in comments and in the string
	# inside the journal's own panel — which you can only read once you have already opened
	# it. The 2026-08-16 playtester asked for the notes journal as a NEW FEATURE while
	# standing in front of an open note with the feature running.
	print("--- and the player is told it exists ---")
	var labels: Array = []
	_labels_of(_note_ui, labels)
	_ok("NoteUI has label text to inspect", labels.size() > 0, "%d labels" % labels.size())
	var footer := ""
	for l in labels:
		if String(l.text).contains("TAB"):
			footer = String(l.text)
	_ok("NoteUI's footer names TAB", footer != "", footer)
	# ⚠️ On a Label of its own, never on the text body — combination_lock.gd's feedback label
	# doubled as its instruction line and the first INCORRECT wiped the controls off the
	# screen (check_lock_input.gd). A trap note recolours the RichTextLabel every frame; this
	# line must not be part of it.
	_ok("the hint is a separate Label, not the note text itself",
		footer != "" and not String(_note_ui.get("_text_label").text).contains("TAB"))
	# And it survives a note being shown — including a trap note, which rewrites colours on
	# the body every frame.
	_note_ui.call("show_note", "TRAP", 12.0)
	var after := ""
	labels.clear()
	_labels_of(_note_ui, labels)
	for l in labels:
		if String(l.text).contains("TAB"):
			after = String(l.text)
	_ok("the hint is immutable — a trap note does not touch it", after == footer)
	_note_ui.call("_close")

	print("--------------------------------------------------")
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	print("--------------------------------------------------")
	quit(0 if _fails == 0 else 1)
	return true


# A real key press. Both keycode and physical_keycode are set because the project's own
# actions are defined by PHYSICAL keycode (`journal` = physical 4194306 = TAB) while Godot's
# built-in `ui_*` actions are defined by keycode — an event carrying only one of the two
# matches only half the actions, silently.
func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e


func _walk(node: Node, script: GDScript, safe: Array[Node], traps: Array[Node]) -> void:
	if node.get_script() == script:
		if bool(node.get("is_trap")):
			traps.append(node)
		else:
			safe.append(node)
	for c in node.get_children():
		_walk(c, script, safe, traps)


func _labels_of(n: Node, out: Array) -> void:
	if n is Label:
		out.append(n)
	for c in n.get_children():
		_labels_of(c, out)
