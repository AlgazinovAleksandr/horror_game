extends SceneTree

# The cellar must not open by itself when the key is found (BACKLOG #16).
#   Godot --headless --path game --script res://tests/check_cellar_key.gd
#
# It used to: level_2.gd wired the KeyItem's `picked_up` straight to
# _open_cellar_gate(), so winning the Bathroom map minigame flung the cellar door open
# from the other end of the house. The key was a formality and the walk back down —
# the only thing that made it feel like a key — never happened.
#
# Asserted with a PHYSICS QUERY, not a flag: `_opened` being true says nothing about
# whether the doorway is walkable, and this project has been caught by exactly that
# before (Issue 13 — a wall whose is_solid() returned true was a hole in the world for
# its entire life). A ray through the ramp opening is the real question.

const GATE_POS := Vector3(5.0, 1.5, 3.0)

var _frame := 0
var _fails := 0
var _scene: Node
var _gate: Node3D
var _gs: Node


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_2_1.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails += 1


# Can the player actually get through the ramp opening? Cast across the doorway at
# chest height; a hit means the gate is still physically in the way.
func _doorway_blocked() -> bool:
	var player := _scene.get_node_or_null("Player") as CharacterBody3D
	var space := player.get_world_3d().direct_space_state
	var from := Vector3(GATE_POS.x, 1.2, GATE_POS.z - 1.2)
	var to := Vector3(GATE_POS.x, 1.2, GATE_POS.z + 1.2)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	q.collision_mask = 1
	return not space.intersect_ray(q).is_empty()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 10:
		return false
	_scene = current_scene
	_gs = root.get_node_or_null("/root/GameState")
	_gate = _scene.get_node_or_null("CellarGate") as Node3D
	_ok("CellarGate exists", _gate != null)
	if not _gate:
		quit(1)
		return true

	print("--- at level start ---")
	_ok("gate is interactable (has interact())", _gate.has_method("interact"))
	_ok("ramp doorway is blocked", _doorway_blocked())

	print("--- press E with empty hands ---")
	_gate.call("interact")
	_ok("still blocked", _doorway_blocked(), "<- refuses without the key")
	_ok("level did not mark it opened", _scene.get("_has_cellar_key") == false)

	print("--- the key is found (the map minigame's payoff) ---")
	# Call the level's own handler, which is what KeyItem.picked_up is wired to. The
	# key node only exists after the minigame is won, so there is nothing to interact
	# with here — but the assertion that matters is what does NOT happen.
	_scene.call("_on_cellar_key_taken")
	_ok("player is now carrying the key", _scene.get("_has_cellar_key") == true)
	_ok("HUD shows it", _gs != null and _gs.get("carried_item") == "cellar key")
	_ok("ramp is STILL blocked", _doorway_blocked(),
		"<- BACKLOG #16: finding the key used to open the door by itself")

	print("--- press E holding the key ---")
	_gate.call("interact")
	_ok("gate reports opened", _gate.get("_opened") == true)
	_ok("carried item cleared", _gs != null and _gs.get("carried_item") == "")

	print("--------------------------------------------------")
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	print("--------------------------------------------------")
	quit(0 if _fails == 0 else 1)
	return true
