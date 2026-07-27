extends SceneTree

# KONTUR gate 2 (the shelf) — proves the vinegar softlock is gone.
#   Godot --headless --path game --script res://tests/check_kontur_bottles.gd
#
# The bug (BACKLOG #22, reported from a real playtest): BottleItem.interact()
# queue_free()s the bottle on PICKUP, and kontur.gd:_on_bottle_taken() overwrote
# _held_bottle with no check — so "take vinegar, then take water" destroyed the vinegar
# permanently. Gate 2 could then never pass, _refresh_exit() kept the exit sealed at
# n/8 forever, and the only way out of the level was to die on purpose.
#
# Everything here drives the REAL interact() path on the real nodes. Nothing calls
# dissolve()/`_pass_gate` directly — a test that reaches the win condition by emitting
# the signal is exactly how walk_backrooms.gd passed for weeks on an uncompletable
# level (Issue 14).

var _frame := 0
var _fails := 0
var _kontur: Node
# ⚠️ Referencing the `GameState` autoload by identifier in a --script SceneTree is a
# COMPILE error ("Identifier not found") — autoloads aren't registered when this file
# is parsed. Fetch it by path at runtime instead (same trap test_apparition.gd and
# check_level6_breach.gd already document for eagerly-compiled class_names).
var _gs: Node


func _initialize() -> void:
	change_scene_to_file("res://scenes/kontur.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails += 1


# Deliberately treats a node that is already queued for deletion as ABSENT. Without
# this the "went back on the shelf" assertion passes on a corpse: queue_free() is
# deferred to the end of the frame, so a picked-up bottle is still findable by name for
# the rest of the frame it died in — and interacting with it does nothing, because its
# own _taken guard is already true.
func _bottle(kind: String) -> Node:
	var n := _kontur.get_node_or_null("Bottle_" + kind)
	if n and n.is_queued_for_deletion():
		return null
	return n


# Drives the real interact() and reports (rather than crashing) when the bottle the
# player would reach for is not on the shelf — which IS the bug under test.
func _take(kind: String) -> bool:
	var b := _bottle(kind)
	if not b:
		_ok("can pick up %s" % kind, false, "no live Bottle_%s on the shelf" % kind)
		return false
	b.call("interact")
	return true


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 8:
		return false
	_kontur = current_scene
	_gs = root.get_node_or_null("/root/GameState")

	print("--- the shelf starts stocked ---")
	for kind in ["bleach", "vinegar", "water"]:
		_ok("Bottle_%s present" % kind, _bottle(kind) != null)

	# The exact sequence a real player reported: grab the right bottle, then grab
	# another one before reaching the barrier.
	# ⚠️ Every step is guarded. When the fix was removed to prove this test can fail,
	# an unguarded `_bottle("vinegar").call(...)` on a null aborted _process BEFORE
	# quit() — so the SceneTree just ran the whole test again, forever, and spewed 1.9 MB.
	# A test that can't fail cleanly can't be trusted to fail at all.
	print("--- take vinegar, then take water (the softlock sequence) ---")
	if _take("vinegar"):
		_ok("holding vinegar", _kontur.get("_held_bottle") == "vinegar")
	if _take("water"):
		_ok("holding water", _kontur.get("_held_bottle") == "water")
	_ok("the vinegar went back on the shelf", _bottle("vinegar") != null,
		"<- this is the whole bug: it used to be gone forever")

	print("--- spraying the wrong bottle costs a strike but restocks ---")
	var strikes_before: int = _kontur.get("_strikes")
	var barrier := _kontur.get_node_or_null("FungalBarrier")
	_ok("FungalBarrier present", barrier != null)
	if barrier:
		barrier.call("interact")
		_ok("a wrong bottle still strikes", _kontur.get("_strikes") == strikes_before + 1,
			"%d -> %d" % [strikes_before, _kontur.get("_strikes")])
		_ok("hands are empty after spraying", _kontur.get("_held_bottle") == "")
		_ok("the spent water restocked", _bottle("water") != null)
		_ok("gate 2 is still unpassed", _kontur.get("_gates")["shelf"] == false)

		print("--- the gate is still winnable afterwards ---")
		if _take("vinegar"):
			barrier.call("interact")
		_ok("gate 2 passes with vinegar", _kontur.get("_gates")["shelf"] == true)
		_ok("the carried line cleared", _gs != null and _gs.get("carried_item") == "")

	print("--------------------------------------------------")
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	print("--------------------------------------------------")
	quit(0 if _fails == 0 else 1)
	return true
