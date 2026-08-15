extends SceneTree

# The combination lock: can you TYPE the code, and does it still tell you how to leave?
#
#   Godot --headless --path game --script res://tests/check_lock_input.gd
#
# Two user reports, one file. "When using the locks, the player needs to use arrows on the
# keyboard — we shall make it possible to enter the digits directly," and "double check if
# it is written that you need to press Esc to escape the lock."
#
# The second one was the interesting half. The text WAS there — and then `_submit()` wrote
# "INCORRECT" over the very label carrying it, so the only instruction for how to get out
# vanished on the first wrong guess, while WRONG_CODE_PANIC ticked. A player who did not
# already know Esc was now trapped in a UI that was hurting them. So the assertion that
# matters most here is the last one: the hint survives a failure.
#
# ⚠️ Godot's `Input.parse_input_event()` does not work headless, so this cannot press keys.
# It feeds `InputEventKey` objects straight into the lock's own `_input()` — the same
# handler the key path calls, one level below the OS.

var _t := 0.0
var _fails: Array[String] = []
var _checks := 0
var _lock: Node


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_2_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print("  %s  %s%s" % ["OK  " if cond else "FAIL", label, ("  " + detail) if detail else ""])
	if not cond:
		_fails.append(label)


func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	_lock.call("_input", ev)


func _digits() -> Array:
	return _lock.get("_digits")


func _process(delta: float) -> bool:
	_t += delta
	if _t < 1.0:
		return false

	_lock = _find_lock(current_scene)
	_ok("the House lock exists", _lock != null)
	if _lock == null:
		return _report()

	var count: int = _lock.call("_digit_count")
	_ok("it sizes itself from its answer", count == 3, "%d dials" % count)

	_lock.call("interact")
	_ok("it opens", bool(_lock.get("_ui_open")))
	_ok("it starts cleared", _digits() == [0, 0, 0], str(_digits()))

	# 1. Typing. The House code is 472 (GameState.level2_code).
	_key(KEY_4)
	_key(KEY_7)
	_key(KEY_2)
	_ok("typed digits land in order", _digits() == [4, 7, 2], str(_digits()))
	_ok("the cursor stops on the last dial, it does not wrap",
		int(_lock.get("_selected")) == count - 1, "selected %d" % int(_lock.get("_selected")))

	# 2. Backspace steps back and clears.
	_key(KEY_BACKSPACE)
	_ok("backspace clears the previous dial", _digits() == [4, 0, 2], str(_digits()))
	_ok("backspace moves the cursor back", int(_lock.get("_selected")) == 1)

	# 3. The keypad works too — a numpad is still a number row.
	_key(KEY_KP_7)
	_ok("the numeric keypad types as well", _digits() == [4, 7, 2], str(_digits()))

	# 4. The arrows still work; nothing was taken away.
	_key_action("ui_left")
	_ok("arrows still move the cursor", int(_lock.get("_selected")) == 1)
	_key_action("ui_up")
	_ok("arrows still change a digit", _digits()[1] == 8, str(_digits()))
	_key_action("ui_down")
	_ok("and back down", _digits()[1] == 7, str(_digits()))

	# 5. ⚠️ THE ONE THAT MATTERS. Submit a WRONG code, then check the hint survived.
	var hint: Label = _lock.get("_hint_label")
	var feedback: Label = _lock.get("_feedback_label")
	_ok("there is a separate hint label", hint != null and feedback != null and hint != feedback)
	if hint != null:
		_ok("the hint says how to type", hint.text.to_lower().contains("0-9"), hint.text)
		_ok("the hint says how to leave", hint.text.to_lower().contains("esc"))

	_digits()[2] = 9                       # 479 — wrong
	_lock.call("_submit")
	_ok("a wrong code is reported", feedback != null and feedback.text == "INCORRECT",
		"" if feedback == null else feedback.text)
	if hint != null:
		_ok("THE HINT SURVIVES A WRONG GUESS", hint.text == String(_lock.get_script().get("HINT_TEXT")), hint.text)

	# 6. Enter submits, like E.
	_lock.call("interact")
	_ok("re-opening clears the dials", _digits() == [0, 0, 0], str(_digits()))
	_key(KEY_4)
	_key(KEY_7)
	_key(KEY_2)
	_key(KEY_ENTER)
	# ⚠️ Through the node, never the identifier. `GameState` as a bare name is a COMPILE
	# error in a SceneTree script — the file is parsed before the autoloads are registered
	# (check_journal.gd:21 says the same thing).
	var gs: Node = root.get_node_or_null("/root/GameState")
	_ok("GameState autoload present", gs != null)
	_ok("Enter submits the right code", gs != null and bool(gs.get("level2_code_correct")))

	return _report()


func _key_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_lock.call("_input", ev)


func _find_lock(n: Node) -> Node:
	# Duck-typed, not by class_name: naming a game class in a SceneTree script compiles it
	# before the autoloads exist (the walk_lab_wing lesson).
	if n.has_method("_digit_count") and n.has_method("_submit"):
		return n
	for c in n.get_children():
		var f := _find_lock(c)
		if f != null:
			return f
	return null


func _report() -> bool:
	print("  %d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL — ", ", ".join(_fails))
		quit(1)
	return true
