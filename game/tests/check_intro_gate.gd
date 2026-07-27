extends SceneTree

# The intro room's exit must stay sealed until the player has BOTH thrown the light
# switch and read the opening note (BACKLOG #12).
#   Godot --headless --path game --script res://tests/check_intro_gate.gd
#
# Why this matters more than it looks: that note is where the player is told they are
# Subject 47 (which KONTUR's roster gate used to rely on), told the rules the rest of
# the game enforces, and warned not to answer a ringing phone three levels before they
# meet one. Walking straight past it turns several later deaths into arbitrary cruelty.
#
# Everything below drives the real interact() path and then asks door.gd's own
# _is_unlocked() whether it would open — Issue 16's lesson restated: assert that
# FAILING the gate changes the outcome, not merely that the gate fires.

var _frame := 0
var _fails := 0
var _gs: Node
# ⚠️ The switch does not exist at scene load. intro_room.gd spawns it from
# _on_wakeup_finished(), i.e. only after the wake-up camera tween completes, so a test
# that samples at a fixed early frame finds no switch and "fails" for the wrong reason.
# Poll for it instead of guessing a frame number.
const SWITCH_WAIT_FRAMES := 900


func _initialize() -> void:
	change_scene_to_file("res://scenes/intro_room.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails += 1


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 10:
		return false
	var scene := current_scene
	_gs = root.get_node_or_null("/root/GameState")
	# A previous test in the same session may have left the flag set; this scene is
	# entered fresh at the start of a run, so clear it to model that.
	if _gs:
		_gs.set("intro_note_read", false)

	var door := scene.get_node_or_null("ExitDoor")
	var note := scene.get_node_or_null("Note")
	var switch_node := scene.get_node_or_null("LightSwitch")
	if switch_node == null and _frame < SWITCH_WAIT_FRAMES:
		return false     # still waking up — see SWITCH_WAIT_FRAMES
	_ok("ExitDoor exists", door != null)
	_ok("Note exists", note != null)
	_ok("light switch appears after the wake-up sequence", switch_node != null,
		"frame %d" % _frame)
	if not (door and note and switch_node):
		quit(1)
		return true

	print("--- nothing done yet ---")
	_ok("door is locked", door.call("_is_unlocked") == false)
	_ok("message points at the switch",
		String(door.get("locked_message")).to_lower().contains("switch"),
		"'%s'" % door.get("locked_message"))

	print("--- switch thrown, note still unread ---")
	switch_node.call("interact")
	_ok("door is STILL locked", door.call("_is_unlocked") == false,
		"<- BACKLOG #12: this used to open here")
	_ok("message now points at the note",
		String(door.get("locked_message")).to_lower().contains("note"),
		"'%s'" % door.get("locked_message"))

	print("--- note read ---")
	note.call("interact")
	_ok("GameState.intro_note_read set", _gs != null and _gs.get("intro_note_read") == true)
	_ok("door opens", door.call("_is_unlocked") == true)

	print("--------------------------------------------------")
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	print("--------------------------------------------------")
	quit(0 if _fails == 0 else 1)
	return true
