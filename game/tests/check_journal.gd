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

	_note_ui.call("show_note", "a note is already open", 0.0)
	_ok("refuses to open over a note", _ui.call("can_open") == false)
	_note_ui.call("_close")

	print("--------------------------------------------------")
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	print("--------------------------------------------------")
	quit(0 if _fails == 0 else 1)
	return true


func _walk(node: Node, script: GDScript, safe: Array[Node], traps: Array[Node]) -> void:
	if node.get_script() == script:
		if bool(node.get("is_trap")):
			traps.append(node)
		else:
			safe.append(node)
	for c in node.get_children():
		_walk(c, script, safe, traps)
