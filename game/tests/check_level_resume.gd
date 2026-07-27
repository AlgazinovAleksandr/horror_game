extends SceneTree

# Walking back to an earlier level must not replay it (BACKLOG #30).
#   Godot --headless --path game --script res://tests/check_level_resume.gd
#
# Reported as: "If the player tries to go to the previous level (for example, to find
# some important notes), the level always starts from the beginning... I will need to
# pass all the levels from the beginning, which is not how it should work."
#
# It was literally true. advance_level(), go_back() and restart_current_level() were
# the same function in three coats: all three called start_current_level(), which
# called reset_level_state() and reloaded the scene, rebuilding it from _ready(). Every
# puzzle's state lived in a level-script local and died with the scene — the Lab's
# three breakers, the House's cellar, the Backrooms' zone, KONTUR's eight-gate ledger.
#
# The three properties asserted here:
#   1. FORWARD then BACK restores what the player had done.
#   2. A DEATH still wipes it. The no-checkpoint fail philosophy in COMMENTS.md is
#      deliberate; this feature is about navigation, not about softening failure.
#   3. Coming back through a level's exit spawns you AT that exit, not at its entrance
#      — otherwise every trip back for a note costs the level's full walk again.

var _fails := 0
var _gs: Node
var _phase := 0
var _frame := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails += 1


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 10:
		return false
	_frame = 0
	if _gs == null:
		_gs = root.get_node_or_null("/root/GameState")
		_gs.set("level_progress", {})

	match _phase:
		0:
			print("--- GameState API ---")
			_ok("has level_progress", _gs.get("level_progress") != null)
			_ok("has entered_from_ahead", _gs.get("entered_from_ahead") != null)
			_ok("Lab exposes save_progress()", current_scene.has_method("save_progress"))

			print("--- do some of the Lab, then leave forward ---")
			var lab := current_scene
			var breaker := lab.get_node_or_null("Breaker_Exam1")
			_ok("Breaker_Exam1 exists", breaker != null)
			if breaker:
				breaker.call("interact")
			_ok("the level counted it", int(lab.get("_breakers_flipped")) == 1)
			_gs.call("advance_level")     # -> the House, capturing the Lab on the way
			_phase = 1
		1:
			print("--- the snapshot was taken on the way out ---")
			var saved: Dictionary = _gs.call("get_level_progress", 1)
			_ok("Lab snapshot exists", not saved.is_empty())
			_ok("it remembers WHICH breaker", saved.get("breakers", []).has("Breaker_Exam1"),
				str(saved.get("breakers", [])))
			_ok("entered_from_ahead is false going forward",
				_gs.get("entered_from_ahead") == false)
			_ok("now in the House", int(_gs.get("current_level")) == 2)

			print("--- walk back into the Lab ---")
			_gs.call("go_back")
			_phase = 2
		2:
			var lab := current_scene
			_ok("back in the Lab", int(_gs.get("current_level")) == 1)
			_ok("entered_from_ahead is true going back",
				_gs.get("entered_from_ahead") == true)
			_ok("the breaker is still thrown", int(lab.get("_breakers_flipped")) == 1,
				"<- this is BACKLOG #30: it used to come back at 0")
			var b := lab.get_node_or_null("Breaker_Exam1")
			_ok("and its lever is green, not fresh", b != null and bool(b.call("is_flipped")))

			# Spawned at the EXIT end, because that is the door we came back through.
			var p := lab.get_node_or_null("Player") as CharacterBody3D
			_ok("spawned at the Lab's exit, not its entrance",
				p != null and p.global_position.z > 10.0,
				"z=%.1f" % (p.global_position.z if p else -999.0))

			print("--- now die ---")
			_gs.call("restart_current_level")
			_phase = 3
		3:
			var lab := current_scene
			_ok("a death clears the snapshot",
				(_gs.call("get_level_progress", 1) as Dictionary).is_empty())
			_ok("the level is fresh again", int(lab.get("_breakers_flipped")) == 0,
				"<- deliberate: resume is for navigation, not for failure")
			var p := lab.get_node_or_null("Player") as CharacterBody3D
			_ok("and back at the entrance", p != null and p.global_position.z < 0.0,
				"z=%.1f" % (p.global_position.z if p else -999.0))

			print("--------------------------------------------------")
			print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
			print("--------------------------------------------------")
			quit(0 if _fails == 0 else 1)
			return true
	return false
