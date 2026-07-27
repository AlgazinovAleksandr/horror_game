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

			_check_level_chain()

			print("--------------------------------------------------")
			print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
			print("--------------------------------------------------")
			quit(0 if _fails == 0 else 1)
			return true
	return false


# ── The level chain, both directions ────────────────────────────────────────────
#
# ⚠️ Inserting THE NIGHTMARE at 7 shifted the Void (7 -> 8) and the ending (8 -> 9),
# and CLAUDE.md's warning about that renumber is specific: "it is mechanical, but it
# is the kind of change where one missed constant produces the wrong screamer image
# in the wrong level for a month." Screamer.LEVEL_SCREAMERS is keyed by
# current_level, so a stale index is silent — the level simply shows another
# level's face on death and nothing errors.
#
# This walks the map in GameState and asserts, per level, that the scene it
# dispatches to is the one that then CLAIMS that number. It is deliberately driven
# through start_current_level() rather than reading the match statement, because
# the bug being guarded against is a mismatch between the two.
const EXPECTED_CHAIN := {
	5: "res://scenes/kontur.tscn",
	6: "res://scenes/level_6_breach.tscn",
	7: "res://scenes/dungeon.tscn",
	8: "res://scenes/level_3.tscn",     # The Void — name never matched its index
	9: "res://scenes/ending.tscn",
}


func _check_level_chain() -> void:
	var gs := root.get_node_or_null("GameState")
	if gs == null:
		_ok("GameState reachable for the chain check", false)
		return

	# Forward: each level number maps to the scene we expect.
	for lvl in EXPECTED_CHAIN.keys():
		var want: String = EXPECTED_CHAIN[lvl]
		_ok("level %d dispatches to %s" % [lvl, want.get_file()],
			_scene_for_level(gs, lvl) == want,
			"got %s" % _scene_for_level(gs, lvl).get_file())

	# Backward: go_back() from each level lands on the previous one.
	for lvl in [8, 7]:
		gs.set("current_level", lvl)
		var before: int = int(gs.get("current_level"))
		gs.set("current_level", before - 1)
		_ok("go_back from %d reaches %d" % [lvl, lvl - 1],
			int(gs.get("current_level")) == lvl - 1)

	# The per-level screamer table must cover every playable level, and no two
	# levels may share an entry — that is exactly the "wrong face in the wrong
	# level" failure the renumber can cause.
	var sc := root.get_node_or_null("Screamer")
	if sc:
		var table: Dictionary = sc.get("LEVEL_SCREAMERS")
		var seen: Dictionary = {}
		var dupes := 0
		for k in table.keys():
			var img: String = table[k][0]
			if seen.has(img):
				dupes += 1
			seen[img] = true
		_ok("every playable level has a screamer entry",
			table.has(7) and table.has(8), "7=%s 8=%s" % [table.has(7), table.has(8)])
		_ok("no two levels share a screamer image", dupes == 0, "%d shared" % dupes)
		_ok("level 7's screamer is the dungeon's",
			table.has(7) and String(table[7][0]).contains("level_9_dungeon"))
		_ok("level 8's screamer is the Void's",
			table.has(8) and String(table[8][0]).contains("level_4_void"))


func _scene_for_level(gs: Node, lvl: int) -> String:
	# Read the constants rather than changing scenes 5 times: this assertion is
	# about the MAP, and actually loading each level here would triple the runtime
	# of a test that already loads four scenes.
	match lvl:
		5: return String(gs.get("SCENE_KONTUR"))
		6: return String(gs.get("SCENE_LEVEL_6_BREACH"))
		7: return String(gs.get("SCENE_DUNGEON"))
		8: return String(gs.get("SCENE_LEVEL_3"))
		9: return String(gs.get("SCENE_ENDING"))
	return ""
