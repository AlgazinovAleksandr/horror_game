extends SceneTree

# Can the player actually REACH the props in Levels 6 and 7?
#
#   Godot --headless --path game --script res://tests/check_interact_reach.gd
#
# Why this exists. `SlamDoor`, `HidingSpot` and `PurgeChamber` are built in exactly two
# levels, `DungeonCot` and `WallSconce` in one — and the suite probed NONE of them. The
# only reach test it had (`autoplay_exit_reachable.gd`) teleported to a hardcoded 1.2 m
# standoff before asking, so it proved a door answers from 1.2 m and nothing more. Behind
# that, four separate props had colliders that did not match what the player sees:
#
#   * slam_door.gd     an interact box 0.1 m deep at the doorway plane — thinner than the
#                      0.15 that purge_chamber.gd was explicitly widened away from on the
#                      2026-07-24 playtest, on doors you walk THROUGH (oblique approach)
#   * slam_door.gd     interact and blocker colliders identical in size AND position, so a
#                      CLOSED door's ray could return the blocker, which has no interact()
#   * dungeon_cot.gd   a volume topping out at y 0.70 against a camera at 1.65 — and it
#                      gates BOTH of Level 7's transitions
#   * hiding_spot.gd   the swinging door is a child of _hinge and had no collider on it
#   * wall_sconce.gd   0.4 x 0.5 subtends ~9 degrees at arm's length; seven of them are
#                      the level's progress gate
#
# Reported by the user as "very hard to interact with the doors, you need to stand very
# close." So this asks the question that was never asked: from a realistic distance, and
# from an OBLIQUE angle as well as square on, does the real interact ray find the prop?

const SCENES := [
	{"label": "Breach", "path": "res://scenes/level_6_breach.tscn"},
	{"label": "Nightmare", "path": "res://scenes/dungeon.tscn"},
]
# Classes to probe, by the method that identifies them (duck-typed: naming a game class in
# a SceneTree script compiles it before the autoloads exist — the walk_lab_wing lesson).
const OBLIQUE_DEG := 25.0

var _stage := 0
var _t := 0.0
var _scene: Node
var _player: CharacterBody3D
var _fails: Array[String] = []
var _checks := 0
var _probed := 0


func _initialize() -> void:
	change_scene_to_file(SCENES[0]["path"])


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print("  %s  %s%s" % ["OK  " if cond else "FAIL", label, ("  " + detail) if detail else ""])
	if not cond:
		_fails.append(label)


func _process(delta: float) -> bool:
	_t += delta
	if _t < 1.2:
		return false
	_t = 0.0
	if _stage >= SCENES.size():
		return _report()
	_scene = current_scene
	_player = _scene.get_node_or_null("Player") as CharacterBody3D
	if _player == null:
		_ok("%s: player exists" % SCENES[_stage]["label"], false)
		_stage += 1
		return false
	_player.set("ai_active", true)
	_probe_scene(String(SCENES[_stage]["label"]))
	_stage += 1
	if _stage < SCENES.size():
		change_scene_to_file(SCENES[_stage]["path"])
		return false
	return _report()


func _probe_scene(label: String) -> void:
	var props := _collect(_scene, [])
	_ok("%s: found props to probe" % label, not props.is_empty(), "%d props" % props.size())

	var by_kind: Dictionary = {}
	for p in props:
		var kind := _kind_of(p)
		by_kind[kind] = int(by_kind.get(kind, 0)) + 1

	# One representative of each kind, square on and oblique. Probing every instance would
	# make this a slow test of the same five colliders.
	var seen: Dictionary = {}
	for p in props:
		var kind := _kind_of(p)
		if seen.has(kind):
			continue
		seen[kind] = true
		_probe(label, kind, p, 0.0)
		_probe(label, kind, p, OBLIQUE_DEG)
		# ⚠️ A closed SlamDoor is a DIFFERENT case: that is when its blocker collider is
		# enabled, coincident with the interact one, and the ray can pick the wrong body.
		# It is also the only state from which the player can undo their own slam, so if
		# E does nothing here they are softlocked.
		if kind == "SlamDoor" and p.has_method("interact"):
			p.call("interact")           # slam it shut
			_probe(label, "SlamDoor (closed)", p, 0.0)
			_probe(label, "SlamDoor (closed)", p, OBLIQUE_DEG)

	var kinds: Array = by_kind.keys()
	kinds.sort()
	print("      kinds: %s" % ", ".join(kinds.map(func(k): return "%s x%d" % [k, by_kind[k]])))


# Stand at 90% of the real interact range, on whichever side of the prop is reachable,
# then ask the SHIPPING ray what it sees.
func _probe(label: String, kind: String, prop: Node3D, off_axis_deg: float) -> void:
	_probed += 1
	var reach: float = float(_player.get_script().get("INTERACT_RANGE")) * 0.9
	var found := false
	var saw := "nothing"
	# ⚠️ AIM AT WHAT THE PLAYER CAN SEE, which is the mesh — never at the collider.
	#
	# The first version of this test aimed at the collider's centre and PASSED against the
	# old, broken colliders, which makes it worthless: a ray fired dead at the middle of a
	# box hits it however thin the box is. The reported bug is precisely that the art and
	# the interactable surface are in different places — an open SlamDoor's panel sits a
	# metre from its doorway collider — so a test that aims at the collider is asking a
	# question no player can ask. Proven both ways before this comment was written.
	#
	# A hinged prop's swinging panel is the thing you look at, so it wins over the carcass.
	var aim: Vector3 = _art_centre(prop)
	var kind_of_prop := _kind_of(prop)
	for side in [1.0, -1.0]:
		var normal: Vector3 = prop.global_transform.basis.z.normalized()
		var dir: Vector3 = (normal * side).rotated(Vector3.UP, deg_to_rad(off_axis_deg))
		var stand: Vector3 = aim + dir * reach
		_player.global_position = Vector3(stand.x, _player.global_position.y, stand.z)
		_player.force_update_transform()
		_player.call("ai_look_at", aim)
		# ⚠️ The camera is a CHILD of the player and the ray fires from its global
		# position, which stays stale for the rest of the frame after a teleport.
		var cam := _player.get_node_or_null("Camera3D") as Camera3D
		if cam:
			cam.force_update_transform()
		var target: Node = _player.call("ai_interact_target")
		if target != null:
			saw = target.name
		# ⚠️ Accept ANY prop of the same kind, not just this instance. THE NIGHTMARE
		# regenerates its layout on every load, and on some seeds two SlamDoors stand close
		# enough that an oblique probe of one lands on its neighbour — the ray found a
		# SlamDoor, which is exactly what this test asks. Demanding the specific instance
		# made the result seed-dependent and produced intermittent failures that said
		# nothing about the game.
		if target == prop or (target != null and prop.is_ancestor_of(target)) \
				or (target is Node3D and _kind_of(target) == kind_of_prop):
			found = true
			break
	var how := "square on" if off_axis_deg == 0.0 else "%d° off-axis" % int(off_axis_deg)
	_ok("%s: %s answers %s at %.1f m" % [label, kind, how, reach], found, "ray sees %s" % saw)


# World-space centre of the prop's visible art. Prefers a mesh hanging off a hinge — that
# is the panel that swings away from the doorway, and the one a player aims at.
func _art_centre(prop: Node3D) -> Vector3:
	var hinge: Variant = prop.get("_hinge")
	if hinge is Node3D:
		var m := _first_mesh(hinge)
		if m != null:
			return m.global_transform * m.get_aabb().get_center()
	var any := _first_mesh(prop)
	if any != null:
		return any.global_transform * any.get_aabb().get_center()
	return prop.global_position


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and n.mesh != null:
		return n
	for c in n.get_children():
		var found := _first_mesh(c)
		if found != null:
			return found
	return null


func _kind_of(n: Node) -> String:
	if n.has_method("check_blocks_path"):
		return "SlamDoor"
	if n.has_method("is_occupied"):
		return "HidingSpot"
	# ⚠️ By its own SIGNAL, not by `lure_into_trap` — that method is on the creature, not on
	# the chamber, so the first version of this file silently probed no PurgeChamber at all
	# while its header claimed to cover one. A duck-type that matches nothing fails open.
	if n.has_signal("creature_trapped"):
		return "PurgeChamber"
	if n.get("is_lit") != null:
		return "WallSconce"
	return "DungeonCot"


# Duck-typed collection: anything interactable that belongs to the five classes at issue.
func _collect(n: Node, acc: Array) -> Array:
	if n is Node3D and n.has_method("interact"):
		if n.has_method("check_blocks_path") or n.has_method("is_occupied") \
				or n.has_signal("creature_trapped") or n.get("is_lit") != null \
				or n.get_script() != null and String(n.get_script().resource_path).ends_with("dungeon_cot.gd"):
			acc.append(n)
	for c in n.get_children():
		_collect(c, acc)
	return acc


func _report() -> bool:
	# ⚠️ A run that probed nothing is not a pass. This suite has shipped several green
	# tests that measured zero things; the sample size is part of the assertion.
	_ok("probed a meaningful number of props", _probed >= 8, "%d probes" % _probed)
	print("  %d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL — ", ", ".join(_fails))
		quit(1)
	return true
