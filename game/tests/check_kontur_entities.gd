extends SceneTree

# KONTUR'S TWO NEW OCCUPANTS COST NOTHING, AND THE MIMIC CANNOT ROB YOU.
#
#   Godot --headless --path game --script res://tests/check_kontur_entities.gd
#
# Guards the 2026-08-18 pass's two big swings. Both were added to a level with NO PANIC
# DECAY, where every point taken is permanent for the rest of the run — so "it adds no
# panic" is not a mood claim, it is the thing that decides whether the level is still
# survivable, and it is asserted by MEASURING THE BAR rather than by reading the code.
#
#   OBJECT 12, CONTAINED   `containment_cell.gd`. The `watcher.gd` contract: no
#                          `ScaryObject` anywhere in its subtree, no collider on the
#                          occupant, nothing with `interact()`, and standing in front of
#                          the glass for over a second moves panic by ZERO. It is also
#                          genuinely behind the glass — the booth is solid and the ray
#                          from the player's eye is stopped before it reaches the figure.
#   THE PERËKOZHNIK        `creature_shapechanger.gd` + `mimic_shell.gd`. The disguise
#                          exists, is built from parts, costs nothing to look at, and —
#                          the one that would be invisible in play and fatal in this level
#                          — TOUCHING IT CONSUMES NO GATE RESOURCE AND SPENDS NO STRIKE.
#                          Driven through `player.ai_interact()`, the same `_try_interact()`
#                          the E key calls, never `shell.interact()` (Issue 30).
#   THE TELL               MEASURED, not asserted to exist. Kitchen: four objects on a
#                          three-slot shelf, exactly two of them wearing the SAME label
#                          file, and the spacing broken. Switchboard: two phones on one
#                          desk and exactly ONE of them able to ring.
#
# ⚠️ THREE SEEDS. This level draws three dice — `_dark_x` (three spine offsets), gate 1's
# colour, and now the mimic's site. Measured with `Scenes.pin_rng`: seed 7 -> +3.0 / red
# east / switchboard, seed 3 -> -3.0 / red east / switchboard, seed 11 -> 0.0 / black east
# / KITCHEN. So the three seeds the geometry sweeps already use happen to cover BOTH
# disguises, and the run asserts it saw both rather than trusting that.
#
# LIVE CONTROLS, every run, on every seed:
#   A. a real `ScaryObject -> StaticBody3D -> collider` is planted at the cell and the same
#      stare is repeated: panic MUST rise. Without it, "the cell adds no panic" is a claim
#      about a probe that might be incapable of detecting panic at all.
#   B. the occupant is given a collider and the emptiness probe must report it.
#   C. `_validate_reveal_mark()` is called with a point buried inside a wall and must
#      REFUSE it. That function is the only thing standing between the mimic and revealing
#      itself inside masonry, and a validator that approves everything looks identical to
#      one that works.

const Scenes := preload("res://tests/lib/scenes.gd")

const SEEDS := [7, 3, 11]
const SETTLE := 1.1          # scene build + CSG collider registration (Issue 52)
const STARE := 1.3           # seconds of looking; 16 panic/s would be 20.8 points

var _fails := 0
var _seed_i := 0
var _stage := 0
var _t := 0.0
var _sites_seen := {}
var _checks := 0

var _elapsed := 0.0
var _panic_mark := 0.0
var _stare_at_disguise := 0.0
var _control_node: Node = null
var _before: Dictionary = {}


func _initialize() -> void:
	Scenes.pin_rng(SEEDS[0])
	change_scene_to_file("res://scenes/kontur.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails += 1


func _player() -> CharacterBody3D:
	return current_scene.get_node_or_null("Player") as CharacterBody3D


func _cell() -> Node3D:
	return current_scene.get_node_or_null("ContainmentCell") as Node3D


func _creature() -> Node3D:
	return current_scene.get_node_or_null("Shapechanger") as Node3D


const BUDGET := 90.0          # wall-clock seconds for the whole run

func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > BUDGET:
		# ⚠️ Time, never a frame count: headless runs uncapped, so a frame budget measures
		# the machine (cross-level X42).
		_ok("the run finished inside its %.0f s budget" % BUDGET, false,
			"stalled at seed %d stage %d" % [SEEDS[_seed_i], _stage])
		_finish()
		return true
	_t += delta
	if _t < (SETTLE if _stage == 0 else STARE):
		return false
	_t = 0.0
	match _stage:
		0: _stage_structure()
		1: _stage_stare_at_cell()
		2: _stage_control_a()
		3: _stage_stare_at_disguise()
		31: _stage_stare_at_wall()
		4: _stage_touch_the_mimic()
		5: _stage_after_reveal()
		6: _stage_control_c()
	return false


# ---------------------------------------------------------------- stage 0: structure

func _stage_structure() -> void:
	var site := String(current_scene.get("_mimic_site"))
	_sites_seen[site] = true
	print("--- seed %d  (dark_x %.1f, mimic '%s') ---"
		% [SEEDS[_seed_i], float(current_scene.get("_dark_x")), site])

	# ---- Object 12 -----------------------------------------------------------------
	var cell := _cell()
	_ok("the containment cell exists", cell != null)
	if cell:
		var occ := cell.get_node_or_null("Object12") as Node3D
		_ok("it holds an occupant with real geometry",
			occ != null and _count_meshes(occ) >= 1,
			"%d mesh part(s)" % (_count_meshes(occ) if occ else 0))
		_ok("NOTHING in the cell is a ScaryObject", not _has_scary(cell))
		_ok("NOTHING in the cell can be interacted with", not _has_interact(cell))
		_ok("the OCCUPANT carries no collider at all",
			occ != null and _count_colliders(occ) == 0,
			"%d collider(s)" % (_count_colliders(occ) if occ else -1))
		_ok("the BOOTH does carry one, so it cannot be walked into",
			_count_colliders(cell) >= 1, "%d collider(s)" % _count_colliders(cell))

		# ...and the half nothing asserted until 2026-08-18: CAN IT BE SEEN?
		_check_occupant_material(cell)
		_check_occupant_sightlines(cell)

		# CONTROL B — give the occupant a collider; the emptiness probe must see it.
		var occ2 := cell.get_node_or_null("Object12") as Node3D
		var ctl := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		ctl.add_child(cs)
		occ2.add_child(ctl)
		_ok("CONTROL B: a collider planted on the occupant IS detected",
			_count_colliders(occ2) >= 1,
			"<- if this reads 0 the emptiness probe measures nothing")
		occ2.remove_child(ctl)
		ctl.queue_free()

	# ---- the mimic -----------------------------------------------------------------
	var c := _creature()
	_ok("the Perëkozhnik exists", c != null)
	if c:
		_ok("it is DISGUISED at level start", bool(c.get("disguised")))
		var shell := c.get_node_or_null("MimicShell")
		_ok("the disguise shell is present", shell != null)
		if shell:
			_ok("the shell is built from parts, not one box",
				_count_meshes(shell) >= 3, "%d mesh part(s)" % _count_meshes(shell))
			# ⚠️ The fairness rule that is easiest to get wrong: a shell parented UNDER
			# the ScaryObject would charge 16 panic/s for looking at a bottle, because
			# `player.gd:_find_scary_object()` walks UP from the collider it hit.
			var at: Node = shell.get_parent()
			var under_scary := false
			while at != null:
				if at is ScaryObject:
					under_scary = true
				at = at.get_parent()
			_ok("the shell is NOT under the ScaryObject", not under_scary)
		_ok("the figure is hidden while disguised", not _figure_visible(c))
		_ok("the gaze collider is DISABLED while disguised", _gaze_disabled(c))

	# ---- the tell, measured ---------------------------------------------------------
	if site == "kitchen":
		_measure_kitchen_tell()
	else:
		_measure_switchboard_tell()

	# Park in front of the cell and take a panic reading.
	_face(Vector3(1.1, 0.0, 16.9), Vector3(2.75, 1.4, 16.9))
	_panic_mark = _panic()
	_stage = 1


# ---------------------------------------------------------------- the tell

func _measure_kitchen_tell() -> void:
	# Four objects standing on a shelf that has three slots, two of them wearing the same
	# label file, and the fourth breaking the 1.2 m rhythm.
	var zs: Array = []
	var labels: Dictionary = {}
	for n in current_scene.get_children():
		var is_bottle: bool = String(n.name).begins_with("Bottle_")
		var is_mimic: bool = n == _creature()
		if not (is_bottle or is_mimic):
			continue
		if is_mimic and String(current_scene.get("_mimic_site")) != "kitchen":
			continue
		zs.append((n as Node3D).global_position.z)
		for t in _label_textures(n):
			labels[t] = int(labels.get(t, 0)) + 1
	zs.sort()
	_ok("FOUR objects on a three-slot shelf", zs.size() == 4, str(zs))
	var dup := 0
	var dup_name := ""
	for k in labels:
		if int(labels[k]) >= 2:
			dup += 1
			dup_name = String(k).get_file()
	_ok("exactly one label file appears TWICE", dup == 1, "duplicate: %s" % dup_name)
	if zs.size() == 4:
		var gaps: Array = []
		for i in range(1, zs.size()):
			gaps.append(snappedf(float(zs[i]) - float(zs[i - 1]), 0.01))
		gaps.sort()
		_ok("and the spacing is visibly broken",
			float(gaps[0]) < 0.75 * float(gaps[-1]),
			"gaps %s m" % str(gaps))


func _measure_switchboard_tell() -> void:
	# Two phone-shaped props on one desk, and exactly one of them able to ring.
	var real := current_scene.get_node_or_null("SwitchboardPhone") as Node3D
	var c := _creature()
	_ok("there are two phones on the switchboard desk",
		real != null and c != null
			and absf(real.global_position.z - c.global_position.z) < 0.4
			and absf(real.global_position.x - c.global_position.x) < 1.2,
		"real %v, mimic %v" % [real.global_position if real else Vector3.ZERO,
			c.global_position if c else Vector3.ZERO])
	var ringers := 0
	for node in [real, c]:
		if node == null:
			continue
		if _has_playing_emitter(node):
			ringers += 1
	_ok("exactly ONE of them can ring", ringers == 1, "%d ringing emitter(s)" % ringers)


# ---------------------------------------------------------------- stages 1..6

func _stage_stare_at_cell() -> void:
	var d := _panic() - _panic_mark
	_ok("staring at Object 12 for %.1f s costs ZERO panic" % STARE, absf(d) < 0.001,
		"delta %.3f of PANIC_MAX" % d)

	# It is behind the glass: the eye ray is stopped before the figure, and the booth's
	# interior is solid to a point query.
	var p := _player()
	var space := p.get_world_3d().direct_space_state
	var eye := p.global_position + Vector3(0, 1.65, 0)
	var cell := _cell()
	var q := PhysicsRayQueryParameters3D.create(eye, cell.global_position + Vector3(0, 1.2, 0))
	q.exclude = [p.get_rid()]
	var hit := space.intersect_ray(q)
	_ok("the ray to the occupant is stopped by the booth", not hit.is_empty(),
		"hit %s" % ((hit.collider as Node).name if hit.has("collider") else "<nothing>"))
	var pq := PhysicsPointQueryParameters3D.new()
	pq.position = cell.global_position + Vector3(0, 1.0, 0)
	pq.exclude = [p.get_rid()]
	_ok("the cell's interior is not standable",
		not space.intersect_point(pq, 1).is_empty())
	_ok("and nothing in the cell answers the interact ray",
		p.call("ai_interact_target") == null
			or not _is_in(p.call("ai_interact_target"), cell))

	# CONTROL A — plant a real gaze panel where the figure is and stare again.
	var scary := ScaryObject.new()
	scary.scare_intensity = 0.8
	current_scene.add_child(scary)
	var body := StaticBody3D.new()
	scary.add_child(body)
	body.global_position = Vector3(1.9, 1.4, 16.9)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.8, 1.6, 0.2)
	col.shape = shape
	body.add_child(col)
	_control_node = scary
	_face(Vector3(1.1, 0.0, 16.9), Vector3(1.9, 1.4, 16.9))
	_panic_mark = _panic()
	_stage = 2


func _stage_control_a() -> void:
	var d := _panic() - _panic_mark
	_ok("CONTROL A: a real gaze panel in the same spot DOES raise panic", d > 0.05,
		"delta %.3f of PANIC_MAX <- if this is 0 the panic probe measures nothing" % d)
	if is_instance_valid(_control_node):
		current_scene.remove_child(_control_node)
		_control_node.queue_free()
	var p := _player()
	p.set("_panic", 0.0)

	# ⚠️ ALWAYS ADVANCE. A stage that throws leaves `_stage` where it was and the harness
	# repeats it for ever — one run of this file spun on a null `Shapechanger` until the
	# 120 s cap, printing the same failure hundreds of times.
	_stage = 3
	var c := _creature()
	if c == null:
		_ok("the Perëkozhnik is in the scene for the disguise stages", false)
		_stage = 6
		return
	_stand_by_disguise(c, true)
	_panic_mark = _panic()


func _stage_stare_at_disguise() -> void:
	_stare_at_disguise = _panic() - _panic_mark
	# ⚠️ PAIRED, not absolute. At the switchboard site the player is standing inside the
	# ringing phone's own `PHONE_PRESSURE_RANGE` (7 m, 4.5/s), which is the level's
	# existing gate-6 mechanic and has nothing to do with the disguise — measured, it adds
	# 0.117 of PANIC_MAX over this window all by itself. An absolute "zero" assertion there
	# would be asserting that gate 6 does not work. So the same window is repeated from the
	# same spot looking at a blank wall, and what is asserted is the DIFFERENCE.
	_stand_by_disguise(_creature(), false)
	_panic_mark = _panic()
	_stage = 31

func _stage_stare_at_wall() -> void:
	var d_wall := _panic() - _panic_mark
	var excess := _stare_at_disguise - d_wall
	_ok("LOOKING AT THE DISGUISE COSTS NOTHING THE ROOM DOES NOT ALREADY CHARGE",
		absf(excess) < 0.01,
		"disguise %.3f vs blank wall %.3f of PANIC_MAX over %.1f s"
			% [_stare_at_disguise, d_wall, STARE])
	_player().set("_panic", 0.0)

	# Snapshot everything a mimic must not be able to spend.
	var scene := current_scene
	_before = {
		"strikes": int(scene.get("_strikes")),
		"gates": (scene.get("_gates") as Dictionary).duplicate(),
		"held": String(scene.get("_held_bottle")),
		"forfeited": bool(scene.get("_forfeited")),
		"bottles": _bottle_names(),
		"phone_ok": _phone_intact(),
	}
	var p := _player()
	_stand_by_disguise(_creature(), true)
	var target: Node = p.call("ai_interact_target")
	_ok("the disguise answers the interact ray",
		target != null and target is MimicShell,
		"target=%s" % (target.name if target else "<none>"))
	p.call("ai_interact")
	_stage = 4


func _stage_touch_the_mimic() -> void:
	var scene := current_scene
	_ok("touching the mimic spent NO strike",
		int(scene.get("_strikes")) == int(_before["strikes"]),
		"%d -> %d" % [int(_before["strikes"]), int(scene.get("_strikes"))])
	var gates_now: Dictionary = scene.get("_gates")
	var gates_before: Dictionary = _before["gates"]
	var moved := 0
	for k in gates_before:
		if bool(gates_before[k]) != bool(gates_now[k]):
			moved += 1
	_ok("touching the mimic passed or failed NO gate", moved == 0, "%d gate(s) moved" % moved)
	_ok("touching the mimic consumed NO carried bottle",
		String(scene.get("_held_bottle")) == String(_before["held"]))
	_ok("touching the mimic did not forfeit the run", not bool(scene.get("_forfeited")))
	_ok("all three real bottles are still on the shelf",
		_bottle_names() == _before["bottles"],
		"%s -> %s" % [str(_before["bottles"]), str(_bottle_names())])
	_ok("the real phone is neither answered nor smashed",
		_phone_intact() == bool(_before["phone_ok"]))
	_stage = 5


func _stage_after_reveal() -> void:
	var c := _creature()
	_ok("the disguise is gone", c.get_node_or_null("MimicShell") == null)
	_ok("the figure is visible now", _figure_visible(c))
	_ok("its gaze collider is live again", not _gaze_disabled(c))
	var mark: Vector3 = c.get("reveal_mark")
	_ok("a validated reveal mark was found", mark != Vector3.ZERO, str(mark))
	if mark != Vector3.ZERO:
		# ⚠️ READ THE CONSTANT OFF THE SCRIPT RESOURCE, never as `CreatureShapechanger.
		# KILL_DIST`. Naming that identifier in a `--script` SceneTree tool compiles
		# `creature_shapechanger.gd` BEFORE the autoloads exist, and it references
		# `Screamer` at function scope — so the compile fails, `.new()` throws once per
		# call, and THE LEVEL UNDER TEST IS BUILT WITH NO CREATURE while the test happily
		# reports on everything else (cross-level X29, Issue 82). Measured here: the whole
		# first seed ran with `Shapechanger` missing.
		var kill: float = float((c.get_script() as GDScript)
			.get_script_constant_map()["KILL_DIST"])
		var d := c.global_position.distance_to(_player().global_position)
		_ok("the figure is outside KILL_DIST from where the player is standing",
			d >= kill, "%.2f m against KILL_DIST %.1f" % [d, kill])
	_stage = 6


func _stage_control_c() -> void:
	# CONTROL C — a mark buried in a wall must be REFUSED. `_validate_reveal_mark()` is
	# the only thing between the mimic and revealing itself inside masonry.
	var scene := current_scene
	var inside_wall := Vector3(4.3, 0.0, 16.9)     # inside the Passage's east wall slab
	var got: Vector3 = scene.call("_validate_reveal_mark", inside_wall,
		Vector3(0.0, 0.99, 16.9))
	_ok("CONTROL C: a reveal mark inside a wall is REFUSED", got == Vector3.ZERO, str(got))
	var good: Vector3 = scene.call("_validate_reveal_mark", Vector3(0.0, 0.0, 17.0),
		Vector3(-3.0, 0.99, 17.0))
	_ok("CONTROL C: ...and an open one is accepted", good != Vector3.ZERO, str(good))

	_seed_i += 1
	if _seed_i >= SEEDS.size():
		_finish()
		return
	Scenes.pin_rng(SEEDS[_seed_i])
	change_scene_to_file("res://scenes/kontur.tscn")
	_stage = 0


func _finish() -> void:
	# ⚠️ Assert the SAMPLE. Three seeds that all drew the same disguise would leave half
	# this file measuring nothing while printing the same words.
	_ok("both disguise sites were exercised", _sites_seen.size() == 2,
		"saw %s" % str(_sites_seen.keys()))
	_ok("enough checks actually ran", _checks >= 90, "%d checks" % _checks)
	print("--------------------------------------------------")
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	quit(0 if _fails == 0 else 1)


# ---------------------------------------------------------------- helpers

func _panic() -> float:
	var p := _player()
	return float(p.call("get_panic_ratio")) if p else 0.0


# ⚠️ `stand` is where the player's FEET go, and the eye is derived. The first version of
# this file took an EYE position and set `global_position = eye - (0, 1.65, 0)`, which put
# the body half a metre BELOW the floor whenever the thing being looked at was on a desk —
# `move_and_slide` then pushed it back up over the following second while the pitch stayed
# where it was, so the ray drifted 0.5 m above its target and `ai_interact_target()` came
# back null. It failed on the switchboard and passed on the kitchen shelf by 4 cm, which is
# the worst kind of intermittent.
const EYE := 1.65

func _face(stand: Vector3, look: Vector3) -> void:
	var p := _player()
	if p == null:
		return
	p.set("ai_active", true)
	p.global_position = Vector3(stand.x, 0.1, stand.z)
	p.velocity = Vector3.ZERO
	p.call("ai_look_at", look)


# Stand a fixed distance from the disguise, either looking AT it or looking at the blank
# wall behind the player. Same spot both times, so the two readings differ only in what is
# in the crosshair.
func _stand_by_disguise(c: Node3D, at_it: bool) -> void:
	if c == null:
		return
	var kitchen: bool = String(current_scene.get("_mimic_site")) == "kitchen"
	var away := Vector3(-1.1, 0, 0) if kitchen else Vector3(1.2, 0, 0)
	var stand := c.global_position + away
	var look := c.global_position + Vector3(0, 0.16, 0)
	if not at_it:
		look = stand + away * 4.0 + Vector3(0, 1.2, 0)
	_face(stand, look)


func _count_meshes(n: Node) -> int:
	var c := 0
	for child in n.get_children():
		if child is MeshInstance3D:
			c += 1
		c += _count_meshes(child)
	return c


func _count_colliders(n: Node) -> int:
	var c := 0
	for child in n.get_children():
		if child is CollisionShape3D or child is CollisionObject3D:
			c += 1
		c += _count_colliders(child)
	return c


func _has_scary(n: Node) -> bool:
	if n is ScaryObject:
		return true
	for child in n.get_children():
		if _has_scary(child):
			return true
	return false


func _has_interact(n: Node) -> bool:
	if n.has_method("interact"):
		return true
	for child in n.get_children():
		if _has_interact(child):
			return true
	return false


func _is_in(node: Node, root: Node) -> bool:
	var at: Node = node
	while at != null:
		if at == root:
			return true
		at = at.get_parent()
	return false


# The figure is the one quad whose ancestry runs through the `ScaryObject`; the disguise
# hangs off the creature directly and never does.
func _figure_visible(c: Node) -> bool:
	for mi in _all_meshes(c):
		if mi.mesh is QuadMesh and _under_scary(mi):
			return mi.visible
	return false


func _under_scary(n: Node) -> bool:
	var at: Node = n
	while at != null:
		if at is ScaryObject:
			return true
		at = at.get_parent()
	return false


func _gaze_disabled(c: Node) -> bool:
	for child in _all_nodes(c):
		if child is CollisionShape3D and _under_scary(child):
			return bool((child as CollisionShape3D).disabled)
	return false


# ---------------------------------------------------------------- can it be SEEN?
#
# ⚠️ THE CELL WAS TESTED ONLY FOR WHAT IT DOES NOT DO. Everything above this line proves
# the booth is harmless — no `ScaryObject`, no collider on the occupant, nothing to press,
# zero panic — and nothing in it, or in any other guard in the project, ever asked whether
# the player can see the one thing the prop exists to show. It shipped so that SIX of
# thirteen reachable headings rendered ZERO pixels of the occupant (the whole 165-210
# degree arc, which is the direction the booth is deliberately turned to face), and on the
# seven that did it rendered 1.8-2.8x BRIGHTER than what was behind it.
#
# This is the headless half. It asserts LINE OF SIGHT and the MATERIAL. The photometric
# half — what the occupant renders at against what is directly behind it, over thirteen
# headings — needs a render target and lives in `tests/screenshot_cell_visibility.gd`,
# which is deliberately outside `tools/run_tests.sh` like every other `screenshot_*`.
#
# ⚠️ IT IS ANALYTIC, NOT A PHYSICS QUERY, AND THAT IS A COMPROMISE WORTH KNOWING ABOUT.
# The rule in this project is to assert with physics queries — but the booth's panes, door
# and port carry NO colliders at all (the whole cell is one box `CellBody`, on purpose), so
# a raycast cannot tell a glazed port from solid steel. This walks the built meshes instead
# and does a segment/AABB test against the OPAQUE, double-sided ones. The live control
# below is what stops that degrading into a test of nothing.

const CELL_HEADINGS := 24
const CELL_RADII := [2.0, 3.2]
const CELL_EYE := 1.6
const CELL_PLAYER_R := 0.45
const PASSAGE_MIN := Vector2(-4.0, 13.0)     # Passage: pos (0, 16.5), size (8, 7)
const PASSAGE_MAX := Vector2(4.0, 20.0)


func _check_occupant_material(cell: Node3D) -> void:
	var occ := cell.get_node_or_null("Object12") as Node3D
	if occ == null:
		return
	var shared: StandardMaterial3D = cell.call("occupant_material")
	_ok("the cell publishes the occupant's material", shared != null)
	if shared == null:
		return
	# ⚠️ EVERY renderable, not "at least one". `Void_creature.glb` is a Mixamo export and
	# CLAUDE.md's standing warning about it is that an embedded skin texture breaks the
	# dark-material override — a split re-export that left one part unretinted would render
	# half a pale man in a suit and read as a lighting bug rather than a missing call.
	var meshes := _all_meshes(occ)
	_ok("the occupant has renderable geometry", meshes.size() >= 1,
		"%d MeshInstance3D" % meshes.size())
	var missed := 0
	for mi in meshes:
		if (mi as MeshInstance3D).material_override != shared:
			missed += 1
	_ok("EVERY mesh in the occupant carries the retint", missed == 0,
		"%d of %d mesh(es) render the GLB's own material" % [missed, meshes.size()])

	# The retint is the DIM one, not the Breach's. These are ceilings, not equalities —
	# `SPECIMEN_DIM` is meant to be tunable; what may not come back is the pale material.
	var a := shared.albedo_color
	var lum := 0.2126 * a.r + 0.7152 * a.g + 0.0722 * a.b
	_ok("the occupant's albedo is dim enough to read as a shadow", lum <= 0.25,
		"albedo luminance %.3f (the Breach's is 0.383)" % lum)
	_ok("its emission cannot self-light it out of the dark",
		shared.emission_energy_multiplier <= 0.25,
		"energy %.2f (the Breach's is 0.35)" % shared.emission_energy_multiplier)
	_ok("its specular lobe is off", shared.metallic_specular <= 0.01,
		"metallic_specular %.2f — a dielectric's specular is NOT scaled by albedo"
			% shared.metallic_specular)
	# ⚠️ CLAUDE.md's other standing warning about this GLB: Mixamo autoplays an animation,
	# and a CONTAINED specimen doing idle motion is a different creature.
	var moving := 0
	for n in _all_nodes(occ):
		if n is AnimationPlayer and (n as AnimationPlayer).is_playing():
			moving += 1
	_ok("nothing in the occupant is animating", moving == 0,
		"%d AnimationPlayer(s) playing" % moving)


func _check_occupant_sightlines(cell: Node3D) -> void:
	var blockers := _cell_blockers(cell)
	_ok("the sightline probe found opaque cell geometry to test against",
		blockers.size() >= 6, "%d blocker(s)" % blockers.size())
	var poses := _cell_poses(cell)
	# ⚠️ Assert the SAMPLE, or a filter that rejected everything passes in silence.
	_ok("enough reachable headings were generated", poses.size() >= 18,
		"%d pose(s)" % poses.size())

	var blind := _blind_headings(cell, poses, blockers)
	_ok("the occupant is visible from EVERY reachable heading", blind.is_empty(),
		"blind at %s" % str(blind))

	# CONTROL — plug the observation port with an opaque slab and require the same probe to
	# go blind across the door arc. Without this, a segment test that never intersects
	# anything (a wrong AABB, an empty blocker list, a target inside a wall) looks exactly
	# like a port that works.
	var plug := MeshInstance3D.new()
	plug.name = "PortPlugControl"
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 1.2, 0.08)
	plug.mesh = bm
	var om := StandardMaterial3D.new()
	plug.material_override = om
	cell.add_child(plug)
	plug.position = Vector3(0, 1.775, -0.97)
	var blind_now := _blind_headings(cell, poses, _cell_blockers(cell))
	_ok("CONTROL: plugging the port DOES blind the door arc", blind_now.size() >= 4,
		"%d heading(s) went blind, wanted >= 4 — the sightline probe is not measuring the port"
			% blind_now.size())
	cell.remove_child(plug)
	plug.queue_free()


# Every heading from which too little of the occupant can be seen.
#
# ⚠️ TWELVE POINTS ACROSS THE BODY, NOT TWO ON THE CENTRELINE, AND A FRACTION RATHER THAN
# "ANY". The first version aimed at the chest and the crown, both at local x = 0, and
# declared five headings blind that `screenshot_cell_visibility.gd` measures 19 000-30 000
# pixels of silhouette at: the occupant is ~0.5 m wide, so an oblique ray to its centreline
# clips a door stile while most of the body is in plain view. "Any one point" is the
# opposite failure — a visible fingertip is not a visible creature.
const CELL_MIN_POINTS := 3        # of 12

func _blind_headings(cell: Node3D, poses: Array, blockers: Array) -> Array:
	# The occupant is parented at local (0, 0.16, 0.12) and stands ~1.9 m; measured bone
	# positions put its head at y 2.05 and its hands at x = +-0.49.
	var targets: Array[Vector3] = []
	for x in [-0.28, 0.0, 0.28]:
		for y in [1.10, 1.45, 1.75, 2.00]:
			targets.append(cell.to_global(Vector3(x, y, 0.12)))
	var blind: Array = []
	for pose in poses:
		var eye: Vector3 = (pose["pos"] as Vector3) + Vector3(0, CELL_EYE, 0)
		var seen := 0
		for t in targets:
			if _clear(eye, t, blockers):
				seen += 1
		if seen < CELL_MIN_POINTS:
			blind.append("%d@%.1f(%d)" % [int(pose["deg"]), float(pose["r"]), seen])
	return blind


# The booth's OPAQUE SOLIDS. Glass is excluded because it is glass. The two backlit
# liners are excluded by being `QuadMesh`: they are single-sided panels that exist to be a
# lit backdrop and are genuinely — not approximately — invisible from the side the occupant
# is viewed through, so counting them would report the working build as blind.
# ⚠️ DO NOT filter those out with `cull_mode == CULL_BACK`. That is Godot's DEFAULT for
# every material, so the first version of this line excluded the entire booth and reported
# "0 blockers"; the control immediately below is the only reason that was not a silent pass
# of a probe that could not see anything at all.
func _cell_blockers(cell: Node3D) -> Array:
	var out: Array = []
	for mi in _all_meshes(cell):
		var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
		if m == null:
			continue
		if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		if not ((mi as MeshInstance3D).mesh is BoxMesh):
			continue
		var size: Vector3 = ((mi as MeshInstance3D).mesh as BoxMesh).size
		var g := (mi as MeshInstance3D).global_transform
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for i in range(8):
			var c := g * Vector3(
				size.x * (0.5 if (i & 1) else -0.5),
				size.y * (0.5 if (i & 2) else -0.5),
				size.z * (0.5 if (i & 4) else -0.5))
			lo = lo.min(c)
			hi = hi.max(c)
		out.append(AABB(lo, hi - lo))
	return out


# Slab-method segment/AABB. ⚠️ A tiny epsilon shrink, so a segment that grazes a face
# exactly — which is what a target sitting on a plane does — is not counted as blocked.
func _clear(from: Vector3, to: Vector3, blockers: Array) -> bool:
	var d := to - from
	for box in blockers:
		var b := (box as AABB).grow(-0.001)
		if b.size.x <= 0.0 or b.size.y <= 0.0 or b.size.z <= 0.0:
			continue
		var t0 := 0.0
		var t1 := 1.0
		var hit := true
		for axis in range(3):
			var lo: float = b.position[axis]
			var hi: float = b.position[axis] + b.size[axis]
			if absf(d[axis]) < 1e-9:
				if from[axis] < lo or from[axis] > hi:
					hit = false
					break
				continue
			var ta: float = (lo - from[axis]) / d[axis]
			var tb: float = (hi - from[axis]) / d[axis]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				hit = false
				break
		if hit:
			return false
	return true


# ⚠️ Bounds arithmetic, NOT a point query. CSG collides as a concave trimesh and
# `intersect_point` finds nothing inside one, so the first version of this filter called
# every candidate reachable — including the ones buried in the east wall (Issue 40 / 94).
func _cell_poses(cell: Node3D) -> Array:
	var out: Array = []
	var c := cell.global_position
	var half := Vector2(1.07, 1.07)     # booth half-extent + plinth overhang
	for r in CELL_RADII:
		for k in range(CELL_HEADINGS):
			var a := TAU * float(k) / float(CELL_HEADINGS)
			var p := c + Vector3(sin(a) * r, 0.0, cos(a) * r)
			if p.x < PASSAGE_MIN.x + CELL_PLAYER_R or p.x > PASSAGE_MAX.x - CELL_PLAYER_R:
				continue
			if p.z < PASSAGE_MIN.y + CELL_PLAYER_R or p.z > PASSAGE_MAX.y - CELL_PLAYER_R:
				continue
			if absf(p.x - c.x) < half.x + CELL_PLAYER_R \
					and absf(p.z - c.z) < half.y + CELL_PLAYER_R:
				continue
			out.append({ "deg": rad_to_deg(a), "r": r, "pos": p })
	return out


func _all_meshes(n: Node) -> Array:
	var out: Array = []
	for child in n.get_children():
		if child is MeshInstance3D:
			out.append(child)
		out.append_array(_all_meshes(child))
	return out


func _all_nodes(n: Node) -> Array:
	var out: Array = []
	for child in n.get_children():
		out.append(child)
		out.append_array(_all_nodes(child))
	return out


func _label_textures(n: Node) -> Array:
	var out: Array = []
	for mi in _all_meshes(n):
		var mat: Material = mi.material_override
		if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture:
			out.append((mat as StandardMaterial3D).albedo_texture.resource_path)
	return out


func _has_playing_emitter(n: Node) -> bool:
	for child in _all_nodes(n):
		if child is AudioStreamPlayer3D and (child as AudioStreamPlayer3D).stream != null:
			return true
	return false


func _bottle_names() -> Array:
	var out: Array = []
	for n in current_scene.get_children():
		if String(n.name).begins_with("Bottle_"):
			out.append(String(n.name))
	out.sort()
	return out


func _phone_intact() -> bool:
	var ph := current_scene.get_node_or_null("SwitchboardPhone")
	if ph == null:
		return false
	return not bool(ph.get("_answered")) and not bool(ph.get("_smashed"))
