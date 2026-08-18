extends SceneTree

# DUNGEON_NIGHTMARES.md §B10's hard constraints, as assertions.
#
# §B10 is explicitly "the double-jeopardy audit for this level" — every item on it
# is a rule this project has already broken once somewhere else and paid for. They
# are cheap to violate by accident in a later session (one enter_dark_zone(), one
# RandomAmbient.register_player()) and expensive to notice by playing, because the
# symptom is "the level feels unfair" rather than a crash.
#
# The bans, and what each one would cost:
#   NO DarkZone      +3/s for having the light off, in a level whose whole premise
#                    is that light is scarce and sometimes WRONG. Issue 18 verbatim.
#   NO standstill    the Hollow One's solution REQUIRES standing still to listen.
#   NO DreadZone     the silence must suppress decay with ZERO additive pressure,
#                    or it re-creates the Corridor Zone-C stacking problem.
#   NO RandomAmbient its blind 4 m pops are indistinguishable from this level's real
#                    positional tells, which is the ONE skill being tested.
#   NO Apparition    a HOLD apparition kills you for fleeing, dropped into a level
#                    built around walking away from a slow pursuer.
#
# Usage: Godot --headless --path game --script res://tests/check_dungeon_entities.gd

const SEEDS := [101, 404, 707]

var _fails := 0
var _checks := 0
var _started := false
var _settle := 0
var _level: Node = null
var _seed_i := 0


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails += 1


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_load(SEEDS[0])
		return false
	_settle += 1
	if _settle < 14:
		return false
	if _level == null:
		_level = current_scene
		if _level == null or not _level.has_method("get_gen"):
			print("  FAIL dungeon.tscn did not load, or dungeon.gd failed to parse")
			_fails += 1
			return _report()
		_audit(SEEDS[_seed_i])
		_seed_i += 1
		_level = null
		if _seed_i < SEEDS.size():
			_load(SEEDS[_seed_i])
			return false
		return _report()
	return false


func _load(s: int) -> void:
	_settle = 0
	var gs := root.get_node_or_null("GameState")
	if gs:
		gs.call("save_level_progress", 7, {"layout_seed": s, "content_seed": s * 31 + 7})
	change_scene_to_file("res://scenes/dungeon.tscn")


func _audit(s: int) -> void:
	var gen = _level.call("get_gen")

	# ⚠️ EVERY ASSERTION IN THIS FILE IS AN ABSENCE — "no DarkZone", "no DreadZone", "no
	# ApparitionDirector" — and an absence is trivially TRUE of a level that failed to build.
	# So the first thing asserted is that there IS a level: chambers, sconces and the entity
	# roster. Without this, a dungeon.gd that threw on the first line would print eleven
	# comfortable OKs per seed (workstream H2, 2026-08-17).
	# ⚠️ `rooms` is the generator's own emitted room list; `_chambers` is private. Reading a
	# property that does not exist returns null, and `null as Array` THROWS — which aborts
	# `_audit()` before every ban in this file, and a thrown test still exits 0 (Issue 45).
	var rooms: Variant = gen.get("rooms") if gen != null else null
	var chambers: int = (rooms as Array).size() if rooms is Array else 0
	var sconce_list: Variant = _level.call("get_sconces")
	var sconces: int = (sconce_list as Array).size() if sconce_list is Array else 0
	_ok("seed %d: the dungeon actually built" % s, chambers >= 9 and sconces == 7,
		"%d rooms, %d sconces" % [chambers, sconces])

	# ⚠️ ...AND A LIVE CONTROL, because an absence check can also stop looking. Add a real
	# `DarkZone` to the scene and require the same counter to see it: if `_count_script()`
	# ever stops matching — a moved script path, a renamed file, a subclass — every ban in
	# this file goes quietly green forever.
	var planted: Node = (load("res://scripts/dark_zone.gd") as GDScript).new()
	planted.name = "DarkZoneControl"
	_level.add_child(planted)
	var seen := _count_script(_level, load("res://scripts/dark_zone.gd"))
	_ok("seed %d CONTROL: a planted DarkZone IS counted" % s, seen == 1, "%d found" % seen)
	_level.remove_child(planted)
	planted.queue_free()

	# ── The banned zones, by TYPE not by name ──────────────────────────────────
	# Counted by script identity so a renamed node cannot hide one.
	var dark := _count_script(_level, load("res://scripts/dark_zone.gd"))
	var dread := _count_script(_level, load("res://scripts/dread_zone.gd"))
	_ok("seed %d: no DarkZone anywhere" % s, dark == 0, "%d found" % dark)
	_ok("seed %d: no DreadZone anywhere" % s, dread == 0, "%d found" % dread)

	# ── The banned player opt-ins ──────────────────────────────────────────────
	var p := _level.get_node_or_null("Player") as CharacterBody3D
	if p:
		# Read the private flags directly: the alternative is inferring them from
		# behaviour, which would take 4 s of standing still per seed.
		_ok("seed %d: standstill panic never enabled" % s,
			not bool(p.get("_standstill_panic_enabled")))
		_ok("seed %d: the flashlight is dead (the candle replaces it)" % s,
			not bool(p.call("is_flashlight_on")))

	# ── RandomAmbient is not registered ────────────────────────────────────────
	# ⚠️ The single most important implementation note in the design doc. It is a
	# GLOBAL autoload that keeps whatever player was last registered, so the check
	# is "does it point at OUR player", not "is it null".
	var ra := root.get_node_or_null("RandomAmbient")
	if ra and p:
		var registered = ra.get("_player")
		_ok("seed %d: RandomAmbient is not driving this level" % s,
			registered != p,
			"registered=%s" % ("our player" if registered == p else "not us"))

	# ── No ApparitionDirector ──────────────────────────────────────────────────
	var appar := _count_script(_level, load("res://scripts/apparition_director.gd"))
	_ok("seed %d: no ApparitionDirector" % s, appar == 0, "%d found" % appar)

	# ── Entity placement (§B4.3, §B10) ─────────────────────────────────────────
	# Sparking is MANDATORY to solve the Hollow One and LETHAL near a Still One, so
	# they may never share a chamber. Textbook double jeopardy.
	var clash := 0
	for nm in gen.still_one_rooms:
		if nm == gen.teach_room:
			clash += 1
	_ok("seed %d: no Still One in the Hollow One's alcove" % s, clash == 0)

	# The spawn chamber, the bed chamber and every lit-sconce chamber hold nothing.
	var bad := 0
	if gen.still_one_rooms.has(gen.spawn_room):
		bad += 1
	if gen.still_one_rooms.has(gen.bed_room):
		bad += 1
	for spot in gen.sconce_spots:
		if gen.still_one_rooms.has(spot["room"]):
			bad += 1
	_ok("seed %d: no entity in the spawn / bed / sconce chambers" % s, bad == 0,
		"%d violations" % bad)

	# A limp during a chase is the double-jeopardy shape, so no beartrap may sit in
	# a corridor adjacent to a chamber the Matron can spawn in.
	var trap_bad := 0
	var adj: Dictionary = gen.adjacency()
	for t in gen.beartrap_rooms:
		for nb in adj.get(t, []):
			if gen.matron_spawn_rooms.has(nb):
				trap_bad += 1
	_ok("seed %d: no beartrap next to a Matron spawn chamber" % s, trap_bad == 0,
		"%d violations" % trap_bad)

	# ── The Matron is below the player's walk speed ────────────────────────────
	# ⚠️ THE resolution of the level's central design problem (§B1 rule 1). If this
	# ever creeps above 4.0 the correct play becomes sprinting, which costs +6/s
	# panic with decay suppressed — the exact double jeopardy the whole level was
	# designed to avoid. Worth an assertion because it is one @export away.
	var matron := _level.get_node_or_null("TheMatron")
	if matron:
		var cs: float = float(matron.get("chase_speed"))
		_ok("seed %d: Matron chase speed %.1f is below the 4.0 walk" % [s, cs], cs < 4.0)

	# ── The audio bus exists and the heartbeat is NOT on it ────────────────────
	# The silence only works if your own pulse survives the duck.
	var bus := AudioServer.get_bus_index("Dungeon")
	_ok("seed %d: the Dungeon bus exists" % s, bus != -1)
	if p:
		var hb = p.get("_heartbeat_player")
		if hb != null:
			_ok("seed %d: the heartbeat is NOT on the duckable bus" % s,
				str(hb.bus) != "Dungeon", "bus=%s" % hb.bus)


func _count_script(node: Node, script: Resource) -> int:
	var n := 0
	if node.get_script() == script:
		n += 1
	for c in node.get_children():
		n += _count_script(c, script)
	return n


func _report() -> bool:
	# ⚠️ Sample-size assertion — a level that fails to parse must not report PASS.
	if _checks < SEEDS.size() * 6:
		print("  FAIL only %d checks ran — did dungeon.gd fail to load?" % _checks)
		_fails += 1
	print("  %d checks, %d failed" % [_checks, _fails])
	print("--------------------------------------------------")
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	print("--------------------------------------------------")
	quit(0 if _fails == 0 else 1)
	return true
