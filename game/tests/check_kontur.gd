extends SceneTree

# KONTUR geometry probe. Two checks, both guarding recurring bug classes in this
# project:
#   1. Every doorway along the spine is CLEAR at head height (Session-11 "a prop on
#      the doorway wall silently seals the room").
#   2. There is solid floor under the whole walking line (Issue 5 void-fall).
#
#   Godot --headless --path game --script res://tests/check_kontur.gd

# ⚠️ DERIVED FROM THE LEVEL, NOT COPIED (2026-08-18). This used to be a hand-written
# mirror of `kontur.gd:DOORS`, and the level's room table had moved on underneath it:
# three of its eight rows — "Archive<->Airlock" at z=36, "Airlock<->Escort" at z=41 and
# "Escort<->Terminus" at (0, 67) — named doorways that no longer exist anywhere. Each
# fired its ray through open floor, found nothing, and printed a comfortable OK. The last
# one is the sharpest: it probed x=0, while the whole facility spine is built at one of
# THREE randomised x offsets, so two runs in three it was measuring a different room.
#
# The table is now read off the scene's own `DOORS` + `_tail_doors()`, which is also what
# `RoomBuilder` was handed — so a doorway cannot be added, moved or renumbered without
# this probe following it. `_labels` only supplies the human names.
const _LABELS := {
	4.0: "Landing<->Vestibule",
	10.0: "Vestibule<->Ante (choice door)",
	13.0: "Ante<->Passage",
	20.0: "Passage<->Kitchen",
	27.0: "Kitchen<->Records (BARRIER expected)",
	35.0: "Records<->Archive (ROSTER SEAL expected)",
	44.0: "Archive<->Switchboard",
	51.0: "Switchboard<->Blackout",
	60.0: "Blackout<->Airlock (gate 7's real door)",
	66.0: "Airlock<->Escort (AIRLOCK SEAL expected)",
	92.0: "Escort<->Terminus",
}
const MIN_DOORWAYS := 10

const FLOOR_Z_MIN := -3.5
# ⚠️ 97.5, not 72.5 (2026-08-18). The spine runs z -4 .. 98 — Escort 66..92, Terminus
# 92..98 — so the old bound stopped 25 m short and never looked at the last two rooms or
# at the floor under the exit door. Stale the same way the doorway table above was.
const FLOOR_Z_MAX := 97.5
const FLOOR_STEP := 1.0

# The deliberate hole behind the red door (kontur.gd:_open_the_void()) and the z at
# which the spine jumps to the randomised `_dark_x` offset.
const VOID_Z_MIN := 9.5
const VOID_Z_MAX := 13.5
const FACILITY_SPINE_Z := 58.0

var _frame := 0
var _fails := 0
var _stage := 0
var _settle := 0.0


func _initialize() -> void:
	change_scene_to_file("res://scenes/kontur.tscn")


func _process(delta: float) -> bool:
	# Stage 1: the door swing (0.7 s) and barrier dissolve (1.6 s) are tweens, so
	# give them real time to finish before re-probing.
	if _stage == 1:
		_settle += delta
		if _settle < 2.6:
			return false
		_recheck()
		return true

	_frame += 1
	if _frame < 10:
		return false

	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	if not player:
		print("FAIL: no Player in kontur.tscn")
		quit(1)
		return true
	var space := player.get_world_3d().direct_space_state

	var doors := _doors_from_scene()
	print("--- doorway clearance @ y=1.6 (gates still shut) — %d doorways ---" % doors.size())
	if doors.size() < MIN_DOORWAYS:
		# A derived table that comes back short means the level's own DOORS array could
		# not be read, and every row below would then be measuring nothing at all.
		print("  FAIL      only %d doorways derived, expected >= %d"
			% [doors.size(), MIN_DOORWAYS])
		_fails += 1
	for d in doors:
		var nm := _probe(space, player, d)
		if nm == "":
			print("  OK        %s" % d[3])
		else:
			# A shut gate is SUPPOSED to seal its doorway; anything else is the
			# "prop blocks the room" bug.
			#
			# ⚠️ RosterSeal and AirlockSeal were missing from this list, so this check
			# reported FAIL on a level that was behaving exactly as designed — and had
			# done so for long enough that the red result was just background noise. A
			# permanently-failing test is worse than no test: it teaches everyone to
			# stop reading the column. (Found 2026-07-27; confirmed identical on HEAD
			# before any of this session's changes.)
			var is_gate: bool = nm == "FungalBarrier" \
				or nm.begins_with("ChoiceDoor_") \
				or nm == "RosterSeal" or nm == "AirlockSeal"
			print("  %s %s  <- %s" % ["GATE(ok)  " if is_gate else "BLOCKED   ", d[3], nm])
			if not is_gate:
				_fails += 1

	# ⚠️ Two things this probe used to get wrong, both of which made it report holes in
	# a floor that is exactly as designed:
	#
	#   * It walked x = 0 the whole way. KONTUR builds the Airlock/Escort/Terminus
	#     spine at ONE OF THREE randomised x offsets (`_dark_x`) so gate 7's answer
	#     moves every run — so past the Blackout there is genuinely no floor at x=0
	#     about two runs in three, and the test's verdict was a coin flip.
	#   * It counted the deliberate void behind the red door (gate 1's whole point,
	#     `_open_the_void()`) as a defect.
	#
	# Follow the actual spine, and skip the void on purpose.
	var dark_x: float = float(current_scene.get("_dark_x"))
	print("--- floor coverage along the spine (x=0, then x=%.1f past the Blackout) ---" % dark_x)
	var z := FLOOR_Z_MIN
	var holes: Array = []
	while z <= FLOOR_Z_MAX:
		if z >= VOID_Z_MIN and z <= VOID_Z_MAX:
			z += FLOOR_STEP
			continue                      # the hole behind the red door, by design
		var probe_x: float = 0.0 if z < FACILITY_SPINE_Z else dark_x
		var q2 := PhysicsRayQueryParameters3D.create(
			Vector3(probe_x, 1.0, z), Vector3(probe_x, -1.5, z))
		q2.exclude = [player.get_rid()]
		if space.intersect_ray(q2).is_empty():
			holes.append(z)
		z += FLOOR_STEP
	if holes.is_empty():
		print("  OK      solid floor from z=%.1f to z=%.1f" % [FLOOR_Z_MIN, FLOOR_Z_MAX])
	else:
		print("  HOLES   at z = %s" % str(holes))
		_fails += 1

	# Audio wiring: load_audio() silently returns null for a missing base name, so a
	# typo or a missing AUDIO_SUBDIRS entry is invisible in-game. Assert it here.
	print("--- audio ---")
	var ambient := current_scene.get_node_or_null("AmbientPlayer") as AudioStreamPlayer
	if ambient and ambient.stream:
		print("  OK        ambient bed loaded")
	else:
		print("  FAIL      AmbientPlayer has no stream")
		_fails += 1
	# Autoloads are not registered at compile time inside a SceneTree script, so
	# reach load_audio() (a static func) through the script resource instead.
	var gs: GDScript = load("res://scripts/game_state.gd")
	for base in ["ambient_kontur", "breathing_behind", "door_seal", "acid_hiss",
			"pedestal_alarm", "kontur_flash", "screamer_kontur"]:
		if gs.load_audio(base):
			print("  OK        %s" % base)
		else:
			print("  FAIL      %s did not resolve" % base)
			_fails += 1

	_check_recovery_archive(space, player)

	# The win path: open the correct door and dissolve the barrier, then re-probe.
	# This is what proves the level is actually completable, not just well-formed.
	print("--- win path: opening the black door + dissolving the barrier ---")
	var black := _find_by_prefix(current_scene, "ChoiceDoor_Black")
	var barrier := current_scene.get_node_or_null("FungalBarrier")
	if black:
		black.interact()
	else:
		print("  FAIL    no ChoiceDoor_Black in the scene")
		_fails += 1
	if barrier:
		barrier.dissolve()
	else:
		print("  FAIL    no FungalBarrier in the scene")
		_fails += 1
	_stage = 1
	return false


# ---------------------------------------------------------------- the recovery archive
#
# THE ARCHIVE HAS AN INVENTORY, IT COSTS NOTHING, AND IT DOES NOT BLOCK THE ROOM.
#
# Three separate properties, and the third is the one this project keeps re-learning:
# `autoplay_house_route.gd` exists because a drawer that opened into a walkway closed the
# only lane past a counter (Issue 76). Two aisle racks 5 m long in a 9 m room is exactly
# that shape of risk, and the offering pedestal — gate 3's whole test — stands between
# them. The lane is measured with RAYS and a POINT QUERY, never `intersect_shape`: a
# capsule centred inside a CSG box comes back CLEAR (Issue 40).
const ARCHIVE_LOTS := ["Lot_sheet", "Lot_lever", "Lot_box", "Lot_plate", "Lot_handset",
	"Lot_empty"]
const AISLE_Z := [37.4, 38.6, 39.8, 41.0, 42.0]
const CAPSULE_D := 0.80          # player.gd's capsule diameter
const AISLE_MIN := CAPSULE_D + 0.40


func _check_recovery_archive(space: PhysicsDirectSpaceState3D, player: CharacterBody3D) -> void:
	print("--- the recovery archive ---")
	var seen := 0
	var empties := 0
	for lot_name in ARCHIVE_LOTS:
		var lot := current_scene.get_node_or_null(lot_name) as Node3D
		if lot == null:
			print("  FAIL      %s is missing" % lot_name)
			_fails += 1
			continue
		seen += 1
		# ⚠️ Silhouette from PARTS, never one box (Issue 35). Counted on the built tree,
		# including a hinged lid's child, so a lot that collapses back into a single
		# rectangle fails here rather than at a playtest.
		var parts := _count_meshes(lot)
		if parts < 3:
			print("  FAIL      %s is %d mesh part(s) — that is a box" % [lot_name, parts])
			_fails += 1
		# Zero rules: nothing on these shelves may be taken, and nothing may charge panic.
		if lot.has_method("interact"):
			print("  FAIL      %s has interact() — a lot must not be takeable" % lot_name)
			_fails += 1
		if _has_scary_ancestor_or_child(lot):
			print("  FAIL      %s carries a ScaryObject — a lot must cost no panic" % lot_name)
			_fails += 1
		if lot_name == "Lot_empty":
			empties += 1
	print("  OK        %d of %d lots present, all built from parts, none interactive"
		% [seen, ARCHIVE_LOTS.size()])
	if empties != 1:
		print("  FAIL      expected exactly one EMPTY lot, found %d" % empties)
		_fails += 1

	# Every lot card faces the aisle. `Label3D` is double-sided, so a card turned the
	# wrong way still renders — mirrored and unreadable — and no headless assertion about
	# its existence would ever notice. Measured as a facing.
	var cards := 0
	var wrong := 0
	for c in current_scene.get_children():
		if not (c is Label3D and String(c.name).begins_with("LotCard")):
			continue
		cards += 1
		var lbl := c as Label3D
		var facing: Vector3 = lbl.global_transform.basis.z    # Label3D reads along +Z
		var to_aisle := Vector3(-signf(lbl.global_position.x), 0, 0)
		if facing.dot(to_aisle) < 0.9:
			print("  FAIL      a LotCard at %v faces away from the aisle" % lbl.global_position)
			wrong += 1
			_fails += 1
	if cards != ARCHIVE_LOTS.size():
		print("  FAIL      %d lot cards, expected %d" % [cards, ARCHIVE_LOTS.size()])
		_fails += 1
	elif wrong == 0:
		print("  OK        all %d lot cards face the aisle" % cards)

	# The ledger — the level's only note.gd page, and what gives check_note_mounting.gd a
	# population here at all (K-T5).
	var note_script := load("res://scripts/note.gd")
	var ledger: Node = null
	for c in current_scene.get_children():
		if c.get_script() == note_script:
			ledger = c
	if ledger == null:
		print("  FAIL      no inventory ledger note in the Archive")
		_fails += 1
	elif bool(ledger.get("is_trap")):
		print("  FAIL      the ledger is a TRAP note — the Archive charges no panic")
		_fails += 1
	else:
		print("  OK        the inventory ledger is a plain, archivable note")

	# The lane. Sampled across the room at five z stations, at knee and chest height.
	var narrowest := 999.0
	var at_z := 0.0
	for z in AISLE_Z:
		var w := _free_lane(space, player, z)
		if w < narrowest:
			narrowest = w
			at_z = z
	if narrowest >= AISLE_MIN:
		print("  OK        the Archive's narrowest lane is %.2f m (need %.2f) at z=%.1f"
			% [narrowest, AISLE_MIN, at_z])
	else:
		print("  FAIL      the Archive's lane narrows to %.2f m at z=%.1f (need %.2f)"
			% [narrowest, at_z, AISLE_MIN])
		_fails += 1

	# CONTROL: a slab dropped across the aisle must be SEEN by the same measurement.
	# Without it, "the lane is clear" is a claim the probe might be incapable of denying.
	# ⚠️ A `StaticBody3D` + `BoxShape3D`, NOT a `CSGBox3D`. A CSG box created at runtime
	# answers `intersect_ray` and is invisible to `intersect_point`/`intersect_shape`
	# (cross-level X45, Issue 91) — so a CSG control here would have proved only half the
	# probe and hidden the other half, which is the exact shape of the bug this control
	# exists to catch.
	var plug := StaticBody3D.new()
	plug.name = "ArchiveLaneControl"
	var pcol := CollisionShape3D.new()
	var pshape := BoxShape3D.new()
	# Full room width: the property under test is "this room has a walkable lane", and a
	# control has to make that property FALSE. A slab across the CENTRE aisle only is not
	# enough — the two side aisles are 1.83 m wide and would still satisfy the threshold,
	# which is how a control quietly becomes a no-op.
	pshape.size = Vector3(9.6, 2.0, 0.4)
	pcol.shape = pshape
	plug.add_child(pcol)
	plug.position = Vector3(0, 1.0, 39.8)
	current_scene.add_child(plug)
	plug.force_update_transform()
	var blocked := _free_lane(space, player, 39.8)
	if blocked < AISLE_MIN:
		print("  OK        CONTROL: a slab across the aisle reads %.2f m — the probe works"
			% blocked)
	else:
		print("  FAIL      CONTROL: a slab across the aisle still measured %.2f m" % blocked)
		_fails += 1
	current_scene.remove_child(plug)
	plug.queue_free()


# Widest contiguous run of free floor across the room at this z, in metres. Point query
# at ankle height for "is this spot inside something", plus a chest-height ray pair to
# catch anything overhanging that a floor-level point would miss.
func _free_lane(space: PhysicsDirectSpaceState3D, player: CharacterBody3D, z: float) -> float:
	const STEP := 0.05
	var best := 0.0
	var run := 0.0
	var x := -4.3
	while x <= 4.3:
		var free := true
		for y in [0.35, 1.20]:
			var pq := PhysicsPointQueryParameters3D.new()
			pq.position = Vector3(x, y, z)
			pq.exclude = [player.get_rid()]
			pq.collide_with_areas = false
			if not space.intersect_point(pq, 1).is_empty():
				free = false
			# CSG walls collide as a concave trimesh, which a point query cannot be
			# inside; a short horizontal ray is what catches those.
			var rq := PhysicsRayQueryParameters3D.create(
				Vector3(x, y, z), Vector3(x + STEP, y, z))
			rq.exclude = [player.get_rid()]
			if not space.intersect_ray(rq).is_empty():
				free = false
		if free:
			run += STEP
			best = maxf(best, run)
		else:
			run = 0.0
		x += STEP
	return best


func _count_meshes(n: Node) -> int:
	var c := 0
	for child in n.get_children():
		if child is MeshInstance3D:
			c += 1
		c += _count_meshes(child)
	return c


func _has_scary_ancestor_or_child(n: Node) -> bool:
	var at: Node = n
	while at != null:
		if at is ScaryObject:
			return true
		at = at.get_parent()
	for child in n.get_children():
		if _has_scary_ancestor_or_child(child):
			return true
	return false


# The scene's own doorway table: the constant DOORS array plus the three tail doors,
# which hang off the randomised `_dark_x` and therefore cannot be a constant anywhere.
func _doors_from_scene() -> Array:
	var out: Array = []
	var script_doors: Array = current_scene.get("DOORS")
	var tail: Array = current_scene.call("_tail_doors")
	for entry in script_doors + tail:
		var pos: Vector2 = entry["pos"]
		out.append([pos.x, pos.y, String(entry.get("dir", "z")),
			String(_LABELS.get(pos.y, "doorway @ z=%.1f" % pos.y))])
	return out


func _recheck() -> void:
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	var space := player.get_world_3d().direct_space_state
	var doors := _doors_from_scene()
	var recheck: Array = []
	for d in doors:
		if float(d[1]) == 10.0 or float(d[1]) == 27.0:
			recheck.append(d)
	# ⚠️ Which of the two z=10 doorways is the BLACK one is randomised per run, so the old
	# "the east one may stay shut" rule was reading a stale label. State the property
	# instead: after opening the black door exactly one of the pair is clear and the other
	# is still held by the RED leaf, and the dissolved barrier is clear.
	var opened := 0
	var red_shut := 0
	var barrier_clear := false
	for d in recheck:
		var nm := _probe(space, player, d)
		var at_choice: bool = float(d[1]) == 10.0
		if nm == "":
			print("  OK        %s now clear" % d[3])
			if at_choice:
				opened += 1
			else:
				barrier_clear = true
		elif nm.begins_with("ChoiceDoor_Red"):
			print("  OK        %s still shut (red door — correct)" % d[3])
			red_shut += 1
		else:
			print("  BLOCKED   %s  <- %s" % [d[3], nm])
			_fails += 1
	if opened != 1 or red_shut != 1:
		print("  FAIL      expected 1 open + 1 red-shut choice doorway, got %d/%d"
			% [opened, red_shut])
		_fails += 1
	if not barrier_clear:
		print("  FAIL      the dissolved fungal barrier still blocks z=27")
		_fails += 1

	print("--- result: %s ---" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


func _probe(space: PhysicsDirectSpaceState3D, player: CharacterBody3D, d: Array) -> String:
	var c := Vector3(d[0], 1.6, d[1])
	var dir: Vector3 = Vector3(0, 0, 1) if d[2] == "z" else Vector3(1, 0, 0)
	var q := PhysicsRayQueryParameters3D.create(c - dir * 1.8, c + dir * 1.8)
	q.exclude = [player.get_rid()]
	var r := space.intersect_ray(q)
	if r.is_empty():
		return ""
	return (r.collider as Node).name if r.collider is Node else "?"


func _find_by_prefix(root: Node, prefix: String) -> Node:
	for child in root.get_children():
		if child.name.begins_with(prefix):
			return child
	return null
