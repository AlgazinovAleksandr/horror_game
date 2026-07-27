extends SceneTree

# 200-seed stress test of DungeonGen (THE NIGHTMARE's procedural layout).
#
# Pure data, no scene. This exists for the reason check_maze_gen.gd exists: the
# generator's output is only ever seen through a level the player walks around in,
# so a scene smoke test exercises ONE seed and asserts nothing about the other
# 4 billion. A procedural generator that CAN emit a broken dungeon eventually WILL.
#
# What it asserts (DUNGEON_NIGHTMARES.md §B14):
#   - every room is reachable from the spawn (BFS over the doorway graph)
#   - chamber count is in range
#   - no two rooms overlap (RoomBuilder's hard constraint, Issue 23)
#   - every doorway lies on a genuinely SHARED edge between two rooms
#   - the seven sconces are in seven DISTINCT chambers
#   - the bed is far enough from the spawn to be a walk
#   - at least one CYCLE exists (a spanning tree makes a chaser unbeatable)
#   - no sconce and no frame sits on a wall that carries a doorway
#   - the Hollow One's alcove is sealed, and shares no chamber with a Still One
#
# ⚠️ It also asserts its own SAMPLE SIZE. check_apparition_clearance.gd reported a
# cheerful "0 spawns checked ... PASS" when the script under test failed to compile;
# a green run on zero samples is the most dangerous result a test can give.
#
# Usage: Godot --headless --path game --script res://tests/check_dungeon_gen.gd

const RUNS := 200

var _fails := 0
var _checked := 0
var _gen_script: GDScript = null

# Aggregates, printed so a human can see the shape of what shipped rather than just
# a green light.
var _rooms_min := 99999
var _rooms_max := -1
var _rooms_total := 0
var _cycles_total := 0
var _bed_dist_min := 99999
var _sconce_short := 0


func _fail(msg: String) -> void:
	print("  FAIL %s" % msg)
	_fails += 1


func _initialize() -> void:
	# Loaded at runtime rather than named as a class_name: naming a game class in a
	# SceneTree test forces it to compile before the autoloads exist.
	_gen_script = load("res://scripts/dungeon_gen.gd")


func _process(_delta: float) -> bool:
	if _gen_script == null:
		print("  FAIL could not load res://scripts/dungeon_gen.gd")
		_report()
		return true

	for i in range(RUNS):
		var g = _gen_script.new()
		if g == null:
			_fail("DungeonGen.new() returned null at run %d — did it fail to compile?" % i)
			break
		# Derived, not random: a failure is reproducible from its seed alone.
		g.generate(i * 7919 + 13, i * 104729 + 7)
		_check_one(i, g)

	_report()
	return true


func _check_one(seed_i: int, g) -> void:
	_checked += 1
	var rooms: Array = g.rooms
	var doors: Array = g.doorways

	if rooms.size() < 8:
		_fail("seed=%d only %d rooms" % [seed_i, rooms.size()])
		return
	_rooms_min = mini(_rooms_min, rooms.size())
	_rooms_max = maxi(_rooms_max, rooms.size())
	_rooms_total += rooms.size()

	# --- chamber count ---------------------------------------------------------
	var chambers: Array = g.chamber_names
	if chambers.size() < 9 or chambers.size() > 12:
		_fail("seed=%d chamber count %d outside 9..12" % [seed_i, chambers.size()])

	# --- no two rooms overlap --------------------------------------------------
	# Rooms in a ROOMS table must ABUT, never OVERLAP, or their floor and ceiling
	# slabs coincide and z-fight (Issue 23). The lattice should make this impossible
	# by construction; assert it anyway, because "impossible by construction" is
	# what everyone said about the Lab's Observation room too.
	for a in range(rooms.size()):
		for b in range(a + 1, rooms.size()):
			var ra: Dictionary = rooms[a]
			var rb: Dictionary = rooms[b]
			var ax0: float = ra["pos"].x - ra["size"].x * 0.5
			var ax1: float = ra["pos"].x + ra["size"].x * 0.5
			var az0: float = ra["pos"].y - ra["size"].y * 0.5
			var az1: float = ra["pos"].y + ra["size"].y * 0.5
			var bx0: float = rb["pos"].x - rb["size"].x * 0.5
			var bx1: float = rb["pos"].x + rb["size"].x * 0.5
			var bz0: float = rb["pos"].y - rb["size"].y * 0.5
			var bz1: float = rb["pos"].y + rb["size"].y * 0.5
			var ox: float = minf(ax1, bx1) - maxf(ax0, bx0)
			var oz: float = minf(az1, bz1) - maxf(az0, bz0)
			if ox > 0.01 and oz > 0.01:
				_fail("seed=%d rooms %s and %s OVERLAP by %.2f x %.2f" % [
					seed_i, ra["name"], rb["name"], ox, oz])
				return

	# --- reachability ----------------------------------------------------------
	# Every room must be reachable from the spawn. The Alcove is the one deliberate
	# exception: it is SEALED (that is what makes the teaching beat zero-risk).
	var reachable: Array = g.reachable_rooms()
	for r in rooms:
		var nm: String = r["name"]
		if nm == g.teach_room:
			continue
		if not reachable.has(nm):
			_fail("seed=%d room %s is UNREACHABLE from spawn %s" % [seed_i, nm, g.spawn_room])
			return

	# --- cycles ----------------------------------------------------------------
	# ⚠️ The single most important structural assertion here. A spanning tree is a
	# perfect maze; in a perfect maze a corridor-following pursuer is unbeatable,
	# because every corridor is a dead end with extra steps. maze_chase_ui.gd's BFS
	# monster taught this project that lesson at a cost of 12 instant deaths in 40.
	if g.extra_edge_count < 1:
		_fail("seed=%d NO CYCLES — the layout is a perfect maze" % seed_i)
	_cycles_total += g.extra_edge_count

	# --- doorways lie on genuinely shared edges --------------------------------
	for d in doors:
		if not _doorway_is_shared(g, d):
			_fail("seed=%d doorway at %s dir=%s is not on a shared room edge" % [
				seed_i, d["pos"], d["dir"]])
			break

	# --- seven sconces in seven distinct chambers ------------------------------
	# ⚠️ Exactly seven, every seed, no tolerance. Lighting 7/7 is what reveals the
	# bed, so a dungeon that placed 6 is one the player can explore forever and
	# never finish. This is the single assertion in this file that is about the
	# level being WINNABLE rather than about it being well-formed.
	var spots: Array = g.sconce_spots
	if spots.size() != 7:
		_fail("seed=%d placed %d sconces, not 7 — the level is UNWINNABLE" % [
			seed_i, spots.size()])
		_sconce_short += 1
	var seen: Dictionary = {}
	for s in spots:
		var nm2: String = s["room"]
		if seen.has(nm2):
			_fail("seed=%d two sconces in the same chamber %s" % [seed_i, nm2])
		seen[nm2] = true
		if not chambers.has(nm2):
			_fail("seed=%d sconce in %s which is not a chamber" % [seed_i, nm2])

	# --- no sconce or frame on a wall carrying a doorway -----------------------
	# wall_point() returns the wall CENTRE, which is exactly where a doorway sits.
	# A collider there silently seals the room — a documented recurrence (the
	# Records warning sign sealed a breaker room in the Lab).
	for s in spots:
		if not g.free_sides(s["room"]).has(s["side"]):
			_fail("seed=%d SCONCE in %s is on side %s which carries a doorway" % [
				seed_i, s["room"], s["side"]])
			break
	for f in g.frame_spots:
		if not g.free_sides(f["room"]).has(f["side"]):
			_fail("seed=%d FRAME in %s is on side %s which carries a doorway" % [
				seed_i, f["room"], f["side"]])
			break

	# --- the bed is a walk away ------------------------------------------------
	var bed_d: int = g.room_distance(g.spawn_room, g.bed_room)
	if bed_d < 3:
		_fail("seed=%d bed is only %d rooms from spawn" % [seed_i, bed_d])
	_bed_dist_min = mini(_bed_dist_min, bed_d)

	# --- entity exclusion zones (§B10) -----------------------------------------
	if g.still_one_rooms.has(g.spawn_room):
		_fail("seed=%d a Still One is in the SPAWN chamber" % seed_i)
	if g.still_one_rooms.has(g.bed_room):
		_fail("seed=%d a Still One is in the BED chamber" % seed_i)
	for s in spots:
		if g.still_one_rooms.has(s["room"]):
			_fail("seed=%d a Still One shares the sconce chamber %s" % [seed_i, s["room"]])
			break
	# Sparking is MANDATORY to solve the Hollow One and LETHAL near a Still One:
	# textbook double jeopardy, so they may never share a chamber.
	if g.teach_room != "" and g.still_one_rooms.has(g.teach_room):
		_fail("seed=%d the Hollow One's alcove holds a Still One" % seed_i)

	# --- the alcove is genuinely sealed ----------------------------------------
	if g.teach_room != "":
		for d in doors:
			if _doorway_touches_room(g, d, g.teach_room):
				_fail("seed=%d the teaching alcove has a DOORWAY — it must be sealed" % seed_i)
				break

	# --- beartraps are not next to a Matron spawn ------------------------------
	var adj: Dictionary = g.adjacency()
	for t in g.beartrap_rooms:
		for nb in adj.get(t, []):
			if g.matron_spawn_rooms.has(nb):
				_fail("seed=%d beartrap corridor %s is adjacent to Matron chamber %s" % [
					seed_i, t, nb])
				break


# A doorway is legitimate only if two DIFFERENT rooms actually meet on that plane
# and both span the doorway's position. A doorway on an unshared edge is a hole
# into the void — Issue 5's whole family.
func _doorway_is_shared(g, d: Dictionary) -> bool:
	var p: Vector2 = d["pos"]
	var on_low := 0
	var on_high := 0
	for r in g.rooms:
		var x0: float = r["pos"].x - r["size"].x * 0.5
		var x1: float = r["pos"].x + r["size"].x * 0.5
		var z0: float = r["pos"].y - r["size"].y * 0.5
		var z1: float = r["pos"].y + r["size"].y * 0.5
		if d["dir"] == "x":
			if p.y <= z0 + 0.01 or p.y >= z1 - 0.01:
				continue
			if absf(p.x - x1) < 0.01:
				on_low += 1     # this room ends at the plane
			elif absf(p.x - x0) < 0.01:
				on_high += 1    # this room starts at the plane
		else:
			if p.x <= x0 + 0.01 or p.x >= x1 - 0.01:
				continue
			if absf(p.y - z1) < 0.01:
				on_low += 1
			elif absf(p.y - z0) < 0.01:
				on_high += 1
	return on_low >= 1 and on_high >= 1


func _doorway_touches_room(g, d: Dictionary, room_name: String) -> bool:
	for r in g.rooms:
		if r["name"] != room_name:
			continue
		var p: Vector2 = d["pos"]
		var x0: float = r["pos"].x - r["size"].x * 0.5
		var x1: float = r["pos"].x + r["size"].x * 0.5
		var z0: float = r["pos"].y - r["size"].y * 0.5
		var z1: float = r["pos"].y + r["size"].y * 0.5
		if d["dir"] == "x":
			return (absf(p.x - x0) < 0.01 or absf(p.x - x1) < 0.01) \
				and p.y > z0 - 0.01 and p.y < z1 + 0.01
		return (absf(p.y - z0) < 0.01 or absf(p.y - z1) < 0.01) \
			and p.x > x0 - 0.01 and p.x < x1 + 0.01
	return false


func _report() -> void:
	# ⚠️ Sample-size assertion. Without it, a DungeonGen that fails to compile makes
	# every .new() return null, every check short-circuit, and this test print a
	# tidy PASS having asserted precisely nothing.
	if _checked < RUNS:
		_fail("only %d/%d seeds were generated — did dungeon_gen.gd fail to load?" % [
			_checked, RUNS])

	print("DUNGEON-GEN seeds=%d" % _checked)
	if _checked > 0:
		print("  rooms per dungeon: min %d  mean %.1f  max %d" % [
			_rooms_min, float(_rooms_total) / _checked, _rooms_max])
		print("  extra (cycle) edges: mean %.1f" % [float(_cycles_total) / _checked])
		print("  shortest spawn->bed distance seen: %d rooms" % _bed_dist_min)
		print("  seeds with fewer than 7 sconces: %d" % _sconce_short)
	print("  %d checks, %d failed" % [_checked, _fails])
	print("--------------------------------------------------")
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	print("--------------------------------------------------")
	quit(0 if _fails == 0 else 1)
