extends SceneTree

# THE DROWNED — the Backrooms Flood's six searchable objects, and the three events they fire.
#
#   Godot --headless --path game --script res://tests/check_flood_drowned.gd
#
# What this guards, and why each assertion exists rather than being obvious:
#
#   * THE ITEMS ARE FOUND BY EAR. Their whole design is an intermittent knock in a near-black
#     room. A structural test that only asked "does the node exist" would have passed on the
#     build where the emitters were gated off by a footprint test that never went true — the
#     `_spawn_dark_breaker_tell()` one-line stub (Issue 34) shipped for several sessions that
#     way. So this counts REAL rising edges on the emitters, in the Lobby (must be zero) and
#     in the Flood (must be several), and asserts its own sample size in both places.
#   * THEY COST NOTHING. `GAME_MECHANICS_IDEAS.md` §0.2 — stop adding panic terms. The run
#     samples panic EVERY FRAME and asserts no step larger than the zone's own 0.3/s drip
#     could produce, which is the only way to catch a panic term added later by accident.
#   * THE SEAM ROOM AND THE TRAP ROOM STAY EMPTY. An audible object in the Sump hands out a
#     bearing to the exit; an audible object in the Cistern lures the player onto an invisible
#     beartrap (anti-pattern §5.2(11)). Both are asserted, and the Sump one carries a control
#     that plants an item there and requires the check to go red.
#   * THE MIX IS ORDERED FROM THE SAMPLE DATA, not from the constants: water bed < knock <
#     haul, measured off the .wav files on disk plus each emitter's gain. `water.wav` shipped
#     20 dB below everything else for months and every structural test passed throughout.
#   * NOTHING IS DRIVEN BY EMITTING A SIGNAL. Every search goes through `player.ai_interact()`,
#     so the real raycast, `can_interact()` and prompt path run.
#
# ⚠️ IT WAS FLAKY — 2 FAILURES IN 10 RUNS — AND THE FLAKINESS WAS A TEST BUG THAT COULD ONLY
# FIRE WHEN THE FEATURE WORKED (cross-level X60, fixed 2026-08-18). `...and the emptied one
# stayed silent` compared the first object's knock count against a mark taken at the HAUL and
# asserted it two stages later, after the TAKE. Between those two points the object sits
# opened-but-not-emptied — and `sunken_item.gd` deliberately keeps such an object knocking
# (its gate is `is_taken`, never `is_searched`, because a player who opens a lid and walks
# away must not silence the one object they still need; that is the only thing keeping the
# Flood's mandatory search winnable). So the object's own 5-11 s timer firing anywhere in that
# ~1.3 s window incremented the counter and reddened the assertion.
#
# ⚠️ THE LESSON, WHICH IS GENERAL: a mark and its assertion must bracket the state change
# they are about, and nothing else. If the object legitimately changes behaviour twice, one
# mark cannot serve both. `_knocks_at_take` is named for the moment it is taken so the next
# person cannot re-read it as "at the search" — which is what the old name said, and did.
# An intermittent guard is a guard people learn to ignore (X42, X46).
#
# ⚠️ AND FIXING IT EXPOSED THE OTHER HALF: that assertion was ALSO too weak. It watched ONE
# object for `ANSWER_WATCH` (2 s), and measured, a build with `sunken_item.gd`'s `is_taken`
# gate deleted outright still PASSED it — the object's pending 5-11 s timer simply had not
# expired inside the window. So the rule is now also asserted run-wide, with no mark and no
# window at all (`_sample_knocks()` / "NO emptied object knocked at any point in the run"),
# and that version caught the deleted gate on 4 runs out of 4. A flaky check and a vacuous
# check turned out to be the same check.

const SCENE := "res://scenes/backrooms.tscn"
const ORIGIN := Vector3(-200, 0, 0)
const OBLIQUE_DEG := 25.0
const REACH_DIST := 1.6

# Rooms that must contain NO SunkenItem, and why.
const FORBIDDEN_ROOMS := {
	"Sump": "it holds the real seam — a knock there is a bearing to the exit",
	"Cistern": "it holds the beartrap — a knock there lures the player onto it",
}
# Zone-local room rectangles, from backrooms_zone3.gd's ROOMS table. Read from the live
# script below rather than duplicated; this is only the fallback shape.
var _rooms: Dictionary = {}

# ⚠️ SIX SECONDS, NOT TWO. Each object's first knock is 1-11 s after the level builds, so a
# 2.5 s window with the gate REMOVED produced only one knock — a control that could have
# come up empty on an unlucky seed and read as green. At 6 s the expected count with the gate
# gone is ~3.6 and the chance of a silent false pass is under 1 %.
const LOBBY_WATCH := 6.0
const FLOOD_WATCH := 15.0
const ANSWER_WATCH := 2.0
const EMPTY_WATCH := 3.2
# The haul tween is 0.8 s; give it a frame or two of margin.
const LID_WATCH := 1.3

var _t := 0.0
var _stage := 0
var _stage_at := 0.0
var _scene: Node = null
var _player: Node3D = null
var _zone: Node = null
var _items: Array = []

var _knocks: Dictionary = {}          # item -> rising-edge count
var _was_playing: Dictionary = {}
var _lobby_knocks := 0
var _flood_knocks := 0
var _answer_knocks := 0
var _answer_items: Array = []
var _counting := ""                   # "", "lobby", "flood", "answer"

var _panic_last := 0.0
var _panic_step := 0.0
var _panic_samples := 0
var _panic_start := 0.0

var _checks := 0
var _fails: Array[String] = []
var _searched_order: Array = []
var _knocks_at_take := 0
var _journal_before := 0
# Run-wide: rising edges observed on an object that was already emptied, and how long each
# emptied object was watched. See `_sample_knocks()`.
var _post_take_knocks := 0
var _taken_at: Dictionary = {}


func _initialize() -> void:
	change_scene_to_file(SCENE)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("  OK    ", label, ("  " + detail) if detail else "")
	else:
		print("  FAIL  ", label, ("  " + detail) if detail else "")
		_fails.append(label)


func _advance(n: int) -> void:
	_stage = n
	_stage_at = _t


# ------------------------------------------------------------------------ main loop

func _process(delta: float) -> bool:
	_t += delta

	# ⚠️ A DEAD SCENE MUST FAIL LOUDLY. A screamer reloads the level, frees `_scene` and
	# `_player`, and every later `get_node_or_null` then raises — which ABORTS the calling
	# function, skipping the remaining assertions rather than failing them (Issue 45).
	if _stage > 0 and (not is_instance_valid(_scene) or not is_instance_valid(_player)):
		_ok("the level survived the run", false, "the scene reloaded at t=%.1f s" % _t)
		return _report()

	if _stage > 0:
		# This probe stands still on purpose and the maze charges +3/s for that.
		_player.call("set_smiler_active", true)
		_sample_panic()
		_sample_knocks()
		# ⚠️ DISMISS EVERY PAGE ON THE FRAME IT OPENS. `NoteUI` pauses the tree, which stops
		# every node `_process` AND every Tween — including the staggered answering knocks
		# this stage is trying to count. Leaving a page up would make the beat measure the
		# pause instead of the feature.
		var ui := root.get_node_or_null("/root/NoteUI")
		if ui != null and bool(ui.get("is_open")):
			ui.call("_close")

	match _stage:
		0:
			if _t < 1.0:
				return false
			return _setup()
		1:
			if _t - _stage_at < LOBBY_WATCH:
				return false
			return _lobby_gate()
		2:
			if _t - _stage_at < 1.0:
				return false
			_ok("every item wakes up once the player is in the Flood",
				_all_active(true), _active_detail())
			_counting = "flood"
			_advance(3)
		3:
			if _t - _stage_at < FLOOD_WATCH:
				return false
			return _knocking()
		4:
			# ⚠️ WAIT OUT THE LID. `SunkenItem` activates its fragment from the haul tween's
			# `finished` (LID_TIME 0.8 s), so a second press in the same frame as the first
			# would be measuring a fragment that is not there yet — and would pass, because
			# the item forwards the press either way. This is the two-press beat's clock.
			if _t - _stage_at < LID_WATCH:
				return false
			return _take_first()
		5:
			if _t - _stage_at < ANSWER_WATCH:
				return false
			return _answer()
		6:
			if _t - _stage_at < LID_WATCH:
				return false
			return _take_two()
		7:
			if _t - _stage_at < 0.4:
				return false
			return _surfacing()
		8:
			if _t - _stage_at < LID_WATCH:
				return false
			return _take_rest()
		9:
			if _t - _stage_at < EMPTY_WATCH:
				return false
			return _emptied()

	if _t > 120.0:
		_ok("the probe finished inside its budget", false, "timed out at stage %d" % _stage)
		return _report()
	return false


# --------------------------------------------------------------------------- stage 0

func _setup() -> bool:
	_scene = current_scene
	_player = _scene.get_node_or_null("Player") as Node3D
	_ok("the Player exists", _player != null)
	if _player == null:
		return _report()
	_player.call("set_smiler_active", true)
	_panic_last = float(_player.call("get_panic_ratio"))
	_panic_start = _panic_last

	_zone = _scene.get_node_or_null("ZoneFlood")
	_ok("zone 3 (the Flood) is built", _zone != null)
	if _zone == null:
		return _report()

	# ⚠️ DISARM THE FATAL FURNITURE BEFORE TELEPORTING. This probe jumps between rooms, and a
	# teleport away from an armed HOLD apparition reads as FLEEING, which is a screamer and a
	# scene reload — the exact failure `screenshot_backrooms.gd` shipped for a whole round
	# (18 of 20 shots were the spawn point, silently). Removed, and the removal is asserted.
	var disarmed := 0
	var appar_script: GDScript = load("res://scripts/apparition.gd")
	var trap_script: GDScript = load("res://scripts/beartrap.gd")
	for n in _all(_zone, []):
		if n.get_script() == appar_script or n.get_script() == trap_script \
				or String(n.name).ends_with("Event"):
			n.queue_free()
			disarmed += 1
	_ok("the Flood's fatal props were disarmed for this probe", disarmed >= 4,
		"%d nodes freed (2 apparitions, 2 triggers, 1 beartrap)" % disarmed)

	_rooms = {}
	for r in _zone.get("ROOMS"):
		_rooms[String(r["name"])] = {"pos": r["pos"], "size": r["size"]}
	_ok("the room table was read from the level script", _rooms.size() == 8,
		"%d rooms" % _rooms.size())

	var item_script: GDScript = load("res://scripts/sunken_item.gd")
	for n in _all(_zone, []):
		if n.get_script() == item_script:
			_items.append(n)
	_ok("six searchable objects in the Flood", _items.size() == 6,
		"%d found" % _items.size())
	if _items.is_empty():
		return _report()

	_structure()
	_placement()
	_mix()
	_no_dark_zone()

	# The player is still standing in the LOBBY, 200 m away. Nothing may knock.
	_counting = "lobby"
	_advance(1)
	return false


# ------------------------------------------------------------------- what they are

func _structure() -> void:
	var with_mesh := 0
	var with_collider := 0
	var with_knock := 0
	var parts := 0
	var emissive: Array[String] = []
	var scary: Array[String] = []
	for it in _items:
		var meshes := _meshes(it)
		parts += meshes.size()
		if meshes.size() >= 4:
			with_mesh += 1
		for m in meshes:
			var mat := m.material_override as StandardMaterial3D
			if mat and mat.emission_enabled and mat.emission_energy_multiplier > 0.0:
				emissive.append("%s/%s" % [it.name, m.name])
		if _first(it, "CollisionShape3D") != null:
			with_collider += 1
		var k: Node = it.get_node_or_null("Knock")
		if k is AudioStreamPlayer3D and (k as AudioStreamPlayer3D).stream != null:
			with_knock += 1
		if _has_scary_ancestor(it):
			scary.append(String(it.name))
	# Issue 35: silhouette carries a prop. A one-box "crate" is the failure this asserts away.
	_ok("each object is built from parts, not one box", with_mesh == _items.size(),
		"%d parts across %d objects" % [parts, _items.size()])
	_ok("each object has a collider so the interact ray can hit it",
		with_collider == _items.size())
	_ok("each object has a knock emitter with a real stream", with_knock == _items.size(),
		"%d of %d" % [with_knock, _items.size()])
	# Anti-pattern §5.2(8): the engine's answer to "make it visible in the dark" is silhouette
	# and audio, never emission — and this zone's whole puzzle is about light.
	_ok("nothing down here is self-lit", emissive.is_empty(), ", ".join(emissive))
	# A ScaryObject ancestor would make these gaze-panic props, i.e. a new panic term.
	_ok("no object feeds gaze panic", scary.is_empty(), ", ".join(scary))


func _placement() -> void:
	var rooms_used: Array[String] = []
	var outside: Array[String] = []
	for it in _items:
		var room := _room_of(it.global_position)
		if room == "":
			outside.append(String(it.name))
		else:
			rooms_used.append(room)
	_ok("every object stands inside a room of the wing", outside.is_empty(),
		", ".join(outside))
	_ok("one per room, no doubling up", rooms_used.size() == _dedup(rooms_used).size(),
		", ".join(rooms_used))
	for bad in FORBIDDEN_ROOMS:
		_ok("nothing in the %s — %s" % [bad, FORBIDDEN_ROOMS[bad]],
			not rooms_used.has(bad))

	# ⚠️ PROVE THE ROOM CHECK CAN FAIL. Plant one in the Sump and require the same predicate
	# to see it; a green "nothing in the Sump" on a test that cannot detect an item there
	# measures nothing. The intruder is removed immediately afterwards.
	var sump: Vector2 = _rooms["Sump"]["pos"]
	var spy := Node3D.new()
	spy.name = "SumpControlProbe"
	_zone.add_child(spy)
	spy.position = Vector3(sump.x, 0.0, sump.y)
	_ok("...and the check can see one when it is there (control)",
		_room_of(spy.global_position) == "Sump", _room_of(spy.global_position))
	spy.queue_free()

	# Clear of every doorway span: a collider in a doorway silently seals a room, which is
	# this project's oldest prop bug (the Records warning sign).
	var worst := 1e9
	var worst_name := ""
	for it in _items:
		for d in _zone.get("DOORS"):
			var p: Vector2 = d["pos"]
			var dp := Vector2(it.global_position.x - ORIGIN.x, it.global_position.z) \
				.distance_to(p)
			if dp < worst:
				worst = dp
				worst_name = String(it.name)
	_ok("no object sits in a doorway", worst > 1.2,
		"closest is %s at %.2f m from a doorway centre" % [worst_name, worst])

	# The Basin object is deliberately in sight of the Basin DECOY seam: a player who lights
	# the room to look at what they hauled out watches the decoy come on and the real seam go
	# out, in the same second, without being told anything.
	var basin := _named("Drowned_Basin")
	var decoy := _named("DecoyBasin")
	_ok("the Basin object and the Basin decoy both exist",
		basin != null and decoy != null)
	if basin != null and decoy != null:
		var d := basin.global_position.distance_to(decoy.global_position)
		_ok("the Basin object stands in sight of the decoy seam", d < 5.0,
			"%.2f m apart" % d)
		var space := _player.get_world_3d().direct_space_state
		var from: Vector3 = basin.global_position + Vector3(0, 1.1, 0)
		var q := PhysicsRayQueryParameters3D.create(from, decoy.global_position)
		q.collision_mask = 1
		q.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(q)
		var clear: bool = hit.is_empty() \
			or from.distance_to(Vector3(hit["position"])) > d * 0.85
		_ok("...with nothing standing between them", clear,
			"blocked by %s" % (hit.get("collider") if not hit.is_empty() else "nothing"))


# ⚠️ MEASURED FROM THE FILES ON DISK, plus each emitter's gain. The constants in
# sunken_item.gd quote `tools/make_sfx_flood.py`'s printed RMS; if a regenerated asset moves,
# this is what notices. The ORDER is the assertion, not any single number.
func _mix() -> void:
	var bed: AudioStreamPlayer3D = null
	for c in _zone.get_children():
		if c is AudioStreamPlayer3D and String(c.name).begins_with("WaterBed_"):
			bed = c
			break
	_ok("the Flood has a water bed to be heard through", bed != null)
	var knock := _items[0].get_node_or_null("Knock") as AudioStreamPlayer3D
	_ok("an item knock emitter exists", knock != null)
	if bed == null or knock == null:
		return
	var bed_db := _rms_dbfs(bed.stream.resource_path) + bed.volume_db
	var knock_db := _rms_dbfs(knock.stream.resource_path) + knock.volume_db
	var haul_path := "res://assets/audio/level_backrooms/flood_haul.wav"
	var haul_file := _rms_dbfs(haul_path)
	var haul_db := haul_file + float(_items[0].get("HAUL_DB"))
	_ok("all three samples could be measured",
		bed_db > -200.0 and knock_db > -200.0 and haul_file > -200.0,
		"bed %.1f  knock %.1f  haul %.1f dBFS at the emitter"
		% [bed_db, knock_db, haul_db])
	_ok("the knock carries over the water bed", knock_db > bed_db + 1.0,
		"knock %.1f dBFS vs bed %.1f" % [knock_db, bed_db])
	_ok("the haul — the sound the player asked for — is the loudest of the three",
		haul_db > knock_db, "haul %.1f dBFS vs knock %.1f" % [haul_db, knock_db])
	_ok("neither is shouting: both sit under 0 dBFS by a wide margin",
		haul_db < -10.0 and knock_db < -10.0)
	_ok("the knocks are duckable room detail, not an un-duckable tell",
		knock.bus == "Ambience", knock.bus)


# ⚠️ THE FLOOD IS NOT A DARKZONE, AND THAT IS THE POINT (verified 2026-08-17).
#
# `CLAUDE.md` said, in as many words, "The zone is a `DarkZone`, so searching costs +3/s" —
# and it is not, and it has not been for a long time. `backrooms_zone3.gd:_build_pressure()`
# carries the reason: the zone's puzzle requires the flashlight OFF, and a `DarkZone` charges
# +3/s for exactly that AND suppresses decay through `player.gd`'s if/elif chain, so the
# puzzle and the panic system were fighting and the puzzle lost (three deaths inside 10 s
# without the mechanic ever being attempted). That is Issue 18, resolved.
#
# It was documented wrong, so it is asserted here: reading a doc is not a measurement, and a
# future pass "restoring" the DarkZone would silently re-create a fixed bug.
func _no_dark_zone() -> void:
	var found: Array[String] = []
	for n in _all(_scene, []):
		if n is DarkZone:
			var a: Node3D = n
			if absf(a.global_position.x - ORIGIN.x) < 40.0:
				found.append(String(a.name))
	_ok("the Flood is not a DarkZone — the room solved by turning the light off does not "
		+ "also tax the light being off (Issue 18)", found.is_empty(), ", ".join(found))
	# Control: the scan can see one. Zone 1 puts DarkZones on its dark arm, 200 m away, so
	# a global "no DarkZone anywhere" would be a different (and false) claim.
	var elsewhere := 0
	for n in _all(_scene, []):
		if n is DarkZone:
			elsewhere += 1
	_ok("...and the scan can find a DarkZone when there is one (control)", elsewhere > 0,
		"%d DarkZone(s) elsewhere in the level" % elsewhere)


# --------------------------------------------------------------------------- stage 1

func _lobby_gate() -> bool:
	_counting = ""
	# Sample size first: "0 knocks" is only meaningful if there were emitters to hear and
	# frames in which to hear them.
	_ok("the Lobby watch actually sampled", _panic_samples > 30,
		"%d frames over %.1f s" % [_panic_samples, LOBBY_WATCH])
	_ok("no object knocks while the player is up in the Lobby", _lobby_knocks == 0,
		"%d knocks heard 200 m from the water" % _lobby_knocks)
	_ok("...because they are asleep, not because they are broken", _all_active(false),
		_active_detail())

	var spawn: Vector3 = _zone.get("spawn_point")
	_player.global_position = spawn
	_player.call("force_update_transform")
	_advance(2)
	return false


# --------------------------------------------------------------------------- stage 3

func _knocking() -> bool:
	_counting = ""
	var heard := 0
	for it in _items:
		if int(_knocks.get(it, 0)) > 0:
			heard += 1
	_ok("the wing knocks once the player is in it", _flood_knocks >= 4,
		"%d knocks from %d of 6 objects in %.0f s" % [_flood_knocks, heard, FLOOD_WATCH])
	_ok("most of the wing is audible, not just one object", heard >= 4,
		"%d of 6 objects knocked" % heard)

	# --- the shipping interact path, square on and 25 degrees off, aimed at the MESH ---
	var reached := 0
	for it in _items:
		var ok := true
		for off in [0.0, OBLIQUE_DEG, -OBLIQUE_DEG]:
			var hit := _reads(it, REACH_DIST, off)
			if not (hit == it or (hit != null and it.is_ancestor_of(hit))):
				ok = false
				_ok("%s answers E at %.1f m, %d° off-axis" % [it.name, REACH_DIST, int(off)],
					false, "the prompt saw %s" % hit)
		if ok:
			reached += 1
	_ok("every object answers the shipping prompt, square on and 25° either side",
		reached == _items.size(), "%d of %d" % [reached, _items.size()])

	# --- haul the first one open, through player.ai_interact(), never by emitting ---
	#
	# ⚠️ ONE PRESS OPENS, IT DOES NOT TAKE (2026-08-17, B-R2). The page used to arrive on the
	# lid tween's `finished`; the player's verdict on capture 005 was *"Why the note appears
	# just after I open the cabinet - I need to collect this note"*. So the first press must
	# leave the object OPEN AND STILL LIVE, with a fragment lying in it.
	var first: Node3D = _items[0]
	_reads(first, REACH_DIST, 0.0)
	_journal_before = _journal_size()
	_player.call("ai_interact")
	_searched_order.append(first)
	_ok("the first object is hauled open by pressing E", bool(first.get("is_searched")))
	_ok("...and it does not go inert — the fragment is still in it",
		bool(first.call("can_interact")))

	_advance(4)
	return false


# --------------------------------------------------------------------------- stage 4

# THE SECOND PRESS. The fragment is a body of its own, and this aims at IT rather than at
# the furniture around it — the whole `lab_cabinet_drawer.gd` beat, one level on.
func _take_first() -> bool:
	var first: Node3D = _items[0]
	# ⚠️ CHECKED HERE, A BEAT LATER, NOT IN THE FRAME OF THE PRESS. The page used to be
	# archived from the haul tween's `finished` (Issue 58's ordering), so a journal
	# comparison taken immediately after the press was green even with the regression
	# restored — measured. The lid has finished by now.
	_ok("...and opening TAKES NOTHING: no page, no journal entry",
		_journal_size() == _journal_before,
		"journal %d -> %d across the whole haul" % [_journal_before, _journal_size()])
	var frag := first.get_node_or_null("Fragment") as Node3D
	_ok("the open object has a fragment lying in it", frag != null and frag.visible)
	_ok("...and it is hittable now that the lid is open",
		frag != null and bool(frag.call("can_interact")))
	_journal_before = _journal_size()
	var seen := _reads(frag if frag != null else first, REACH_DIST, 0.0)
	_ok("the shipping prompt finds something to press E on", seen != null,
		"prompt saw %s" % ("nothing" if seen == null else String(seen.name)))
	_player.call("ai_interact")
	_ok("a second, separate E takes the fragment", bool(first.get("is_taken")))
	# ⚠️ THE SILENCE MARK IS TAKEN HERE, AFTER `is_taken`, AND IT USED TO BE TAKEN AT THE
	# HAUL — which made this guard fail 2 runs in 10 BECAUSE THE FEATURE WORKS (cross-level
	# X60). `sunken_item.gd:_process()` gates the knock on `is_taken`, deliberately not on
	# `is_searched`: an object whose lid is open but whose fragment is still in it MUST keep
	# calling, or a player who hauls one and walks away silences the object they still need
	# and the wing becomes unwinnable. The old mark spanned the whole of stage 4 — LID_WATCH
	# plus a frame — during which the object is in exactly that state, so its own 5-11 s
	# timer firing anywhere in that window reddened "the emptied one stayed silent".
	# The mark must be the moment the object is EMPTIED, which is this line and no earlier.
	_knocks_at_take = int(_knocks.get(first, 0))
	_ok("...and NOW it goes inert: no prompt, nothing left to do",
		not bool(first.call("can_interact")) and _reads(first, REACH_DIST, 0.0) == null)

	_counting = "answer"
	_advance(5)
	return false


# --------------------------------------------------------------------------- stage 5

func _answer() -> bool:
	_counting = ""
	# BEAT 1 — every remaining object answers the first search with one knock.
	#
	# ⚠️ COUNT DISTINCT OBJECTS, not knocks. Each item also knocks on its own 5-11 s timer, so
	# a raw event count inside a 2 s window can be satisfied by two chatty objects and would
	# stay green with the beat deleted. Five separate objects answering inside two seconds
	# cannot happen by coincidence: the odds of any one of them firing spontaneously in a 2 s
	# slice of a 5-11 s cycle are about one in four.
	_ok("the rest of the wing answers the first search", _answer_items.size() >= 4,
		"%d of the 5 remaining objects knocked within %.1f s (%d knocks total)"
		% [_answer_items.size(), ANSWER_WATCH, _answer_knocks])
	# ⚠️ EMPTIED, NOT OPENED — see the mark's own comment in `_take_first()`. Comparing
	# against a count taken at the HAUL is what made this line intermittent.
	_ok("...and the emptied one stayed silent",
		int(_knocks.get(_searched_order[0], 0)) == _knocks_at_take,
		"%d knocks since it was emptied; an emptied object must never knock again"
			% (int(_knocks.get(_searched_order[0], 0)) - _knocks_at_take))
	_ok("the first object's page is archived so TAB can re-read it",
		_journal_size() > _journal_before,
		"journal %d -> %d" % [_journal_before, _journal_size()])

	# Haul two more open; taking them fires THE SURFACING on the third fragment.
	for i in range(1, 3):
		_haul(_items[i])
		_searched_order.append(_items[i])
	_advance(6)
	return false


# --------------------------------------------------------------------------- stage 6

func _take_two() -> bool:
	for i in range(1, 3):
		_take(_items[i])
	_ok("three fragments taken", _emptied_count() == 3, "%d" % _emptied_count())
	_advance(7)
	return false


# --------------------------------------------------------------------------- stage 7

func _surfacing() -> bool:
	# BEAT 2 — something else in the wing hauls something out of the water, once.
	var found: AudioStreamPlayer3D = null
	for c in _zone.get_children():
		if c is AudioStreamPlayer3D and c.stream != null \
				and String(c.stream.resource_path).contains("flood_haul"):
			found = c
			break
	_ok("THE SURFACING fires on the third search", found != null)
	if found != null:
		var d := found.global_position.distance_to(_player.global_position)
		_ok("it happens across the room, not on top of the player",
			d >= 4.5 and d <= 14.0, "%.1f m away" % d)
		# ⚠️ It must not be the wader. `UnseenWader` is untouched by this feature and owns its
		# own emitter; a beat that hijacked it would break P10's never-resolving contract.
		var wader := _first(_zone, "UnseenWader")
		_ok("it is not the unseen wader", wader == null or not wader.is_ancestor_of(found))
		if wader != null:
			var wd: float = (wader as Node3D).global_position \
				.distance_to(_player.global_position)
			_ok("the wader is still keeping its distance", wd >= 11.0, "%.1f m" % wd)

	# Haul the last three open.
	for i in range(3, 6):
		_haul(_items[i])
		_searched_order.append(_items[i])
	_advance(8)
	return false


# --------------------------------------------------------------------------- stage 8

func _take_rest() -> bool:
	for i in range(3, 6):
		_take(_items[i])
	_ok("all six objects are emptied", _emptied_count() == 6, "%d" % _emptied_count())
	_advance(9)
	return false


# --------------------------------------------------------------------------- stage 9

func _emptied() -> bool:
	# BEAT 3 — the wing is emptied and stays quieter than the player found it.
	_ok("the wing registers as emptied", bool(_zone.get("_emptied")))
	var range_now: Vector2 = _zone.get("_drip_range")
	_ok("the drips halve, permanently", range_now.x >= 6.0,
		"drip interval now %.0f-%.0f s" % [range_now.x, range_now.y])
	var beds_down := 0
	var beds := 0
	for c in _zone.get_children():
		if c is AudioStreamPlayer3D and String(c.name).begins_with("WaterBed_"):
			beds += 1
			if (c as AudioStreamPlayer3D).volume_db < 14.0 - 0.5:
				beds_down += 1
	_ok("the water settles across the whole wing", beds > 0 and beds_down == beds,
		"%d of %d beds down from +14.0 dB" % [beds_down, beds])

	# The seventh knock, from nothing, behind the player — an absence cannot teach itself.
	var last: AudioStreamPlayer3D = null
	for c in _zone.get_children():
		if c is AudioStreamPlayer3D and c.stream != null \
				and String(c.stream.resource_path).contains("flood_knock"):
			last = c
	_ok("one last knock, from a wing with nothing left in it to knock", last != null)
	if last != null:
		var d := last.global_position.distance_to(_player.global_position)
		_ok("it is close, and behind you", d <= 4.5, "%.1f m away" % d)

	# --- the whole point: none of it cost anything ---
	_ok("no object added panic", _panic_step < 0.02,
		"largest single-frame panic step was %.4f of the bar (the zone's own 0.3/s drip "
		% _panic_step + "produces ~0.0001); anything larger is a new panic term")
	print("      panic across the whole probe: %.1f%% -> %.1f%% of PANIC_MAX over %.0f s"
		% [_panic_start * 100.0, float(_player.call("get_panic_ratio")) * 100.0, _t])

	# --- control: the emitters are silenced by the GATE, not merely dead ---
	# Everything is searched now, so re-arming the gate must NOT produce a knock; a fresh
	# unsearched item at the same settings must. Build one, prove it knocks, free it.
	var fresh = load("res://scripts/sunken_item.gd").new()
	fresh.name = "GateControlProbe"
	fresh.kind = "footlocker"
	_zone.add_child(fresh)
	fresh.position = Vector3(0, 0, -2)
	fresh.call("set_zone_active", true)
	fresh.call("knock_once", 0.0)
	var k := fresh.get_node_or_null("Knock") as AudioStreamPlayer3D
	_ok("control: an unsearched object at these settings does play (so 0 in the Lobby "
		+ "was the gate, not a dead emitter)", k != null and k.playing)
	fresh.queue_free()

	# --- the run-wide silence rule, and its own sample size ---------------------------
	var watched := 0.0
	for it in _taken_at.keys():
		watched += _t - float(_taken_at[it])
	_ok("NO emptied object knocked at any point in the run", _post_take_knocks == 0,
		"%d post-empty knocks" % _post_take_knocks)
	# ⚠️ ASSERT THE WINDOW. `_post_take_knocks == 0` is trivially true of a run that never
	# emptied anything, or that ended the frame after the last take. 20 object-seconds is
	# ~2.5 expected knocks at the shipped 5-11 s cadence if the gate were removed.
	_ok("...and it was watched for long enough to mean something", watched >= 20.0,
		"%.1f object-seconds across %d emptied objects" % [watched, _taken_at.size()])
	return _report()


# ------------------------------------------------------------------------- sampling

func _sample_knocks() -> void:
	for it in _items:
		if not is_instance_valid(it):
			continue
		var k := it.get_node_or_null("Knock") as AudioStreamPlayer3D
		if k == null:
			continue
		var now: bool = k.playing
		var before: bool = bool(_was_playing.get(it, false))
		_was_playing[it] = now
		# ⚠️ THE RUN-WIDE VERSION OF "AN EMPTIED OBJECT NEVER KNOCKS AGAIN", added with the
		# X60 fix. The stage-5 assertion is a BEAT check and only ever watched one object
		# for `ANSWER_WATCH` (2 s) — measured, a build with the `is_taken` gate removed
		# entirely still passed it, because the object's pending 5-11 s timer had not
		# expired inside that window. This one has no window and no mark at all: a rising
		# edge on an object that is already emptied is a violation, whenever it happens and
		# to whichever object. `_taken_at` records how long each object was WATCHED in that
		# state so "0 violations" cannot be satisfied by never looking.
		if bool(it.get("is_taken")) and not _taken_at.has(it):
			_taken_at[it] = _t
		if now and not before:
			_knocks[it] = int(_knocks.get(it, 0)) + 1
			if bool(it.get("is_taken")):
				_post_take_knocks += 1
			match _counting:
				"lobby": _lobby_knocks += 1
				"flood": _flood_knocks += 1
				"answer":
					if not bool(it.get("is_taken")):
						_answer_knocks += 1
						if not _answer_items.has(it):
							_answer_items.append(it)


func _sample_panic() -> void:
	var now := float(_player.call("get_panic_ratio"))
	_panic_step = maxf(_panic_step, absf(now - _panic_last))
	_panic_last = now
	_panic_samples += 1


# --------------------------------------------------------------------------- helpers

func _all(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children():
		_all(c, out)
	return out


func _first(n: Node, cls: String) -> Node:
	for c in _all(n, []):
		if c.is_class(cls) or String(c.name) == cls:
			return c
	return null


func _named(nm: String) -> Node3D:
	for n in _all(_zone, []):
		if String(n.name) == nm and n is Node3D:
			return n as Node3D
	return null


# World-space union of every part's AABB.
func _world_aabb(n: Node3D) -> AABB:
	var out := AABB(n.global_position, Vector3.ZERO)
	var first := true
	for m in _meshes(n):
		var mi: MeshInstance3D = m
		var local := mi.get_aabb()
		var t := mi.global_transform
		for i in range(8):
			var corner: Vector3 = local.position + Vector3(
				local.size.x * float(i & 1),
				local.size.y * float((i >> 1) & 1),
				local.size.z * float((i >> 2) & 1))
			var w: Vector3 = t * corner
			if first:
				out = AABB(w, Vector3.ZERO)
				first = false
			else:
				out = out.expand(w)
	return out


func _meshes(n: Node) -> Array:
	var out: Array = []
	for c in _all(n, []):
		if c is MeshInstance3D:
			out.append(c)
	return out


func _has_scary_ancestor(n: Node) -> bool:
	var scary: GDScript = load("res://scripts/scary_object.gd")
	var p: Node = n
	while p != null:
		if p.get_script() == scary:
			return true
		p = p.get_parent()
	return false


func _dedup(a: Array) -> Array:
	var out: Array = []
	for v in a:
		if not out.has(v):
			out.append(v)
	return out


func _room_of(world: Vector3) -> String:
	var local := world - ORIGIN
	for name in _rooms:
		var p: Vector2 = _rooms[name]["pos"]
		var s: Vector2 = _rooms[name]["size"]
		if absf(local.x - p.x) <= s.x / 2.0 and absf(local.z - p.y) <= s.y / 2.0:
			return String(name)
	return ""


func _emptied_count() -> int:
	var n := 0
	for it in _items:
		if is_instance_valid(it) and bool(it.get("is_taken")):
			n += 1
	return n


# One press, aimed at the object: hauls the lid.
func _haul(it: Node3D) -> void:
	_reads(it, REACH_DIST, 0.0)
	_player.call("ai_interact")


# One press, aimed at the FRAGMENT: lifts it out. Always called at least LID_WATCH after
# the haul, because the fragment does not exist until the lid tween finishes.
func _take(it: Node3D) -> void:
	var frag := it.get_node_or_null("Fragment") as Node3D
	_reads(frag if frag != null and frag.visible else it, REACH_DIST, 0.0)
	_player.call("ai_interact")


func _journal_size() -> int:
	var gs := root.get_node_or_null("/root/GameState")
	if gs == null:
		return 0
	var j = gs.get("journal")
	return j.size() if j != null else 0


func _all_active(want: bool) -> bool:
	for it in _items:
		if bool(it.get("_zone_active")) != want:
			return false
	return true


func _active_detail() -> String:
	var n := 0
	for it in _items:
		if bool(it.get("_zone_active")):
			n += 1
	return "%d of %d awake" % [n, _items.size()]


# Stand `dist` from the object's ART, `off_axis` degrees round, and ask the SHIPPING prompt
# path what it sees. Aims at the MESH, never at the collider — aiming at the collider is what
# let an earlier version of this idiom pass against colliders a player could not hit.
func _reads(prop: Node3D, dist: float, off_axis: float) -> Node:
	# The union AABB of every part, in world space: aiming at the FIRST mesh would aim at a
	# gurney's castor, and standing `dist` from a castor can put the camera inside the
	# object's own collider — which `hit_from_inside` would then happily approve.
	var aabb := _world_aabb(prop)
	var aim: Vector3 = aabb.get_center()
	var radius: float = maxf(aabb.size.x, aabb.size.z) * 0.5
	# Approach from the room centre — the open side of the object.
	var room := _room_of(prop.global_position)
	var toward := Vector3(0, 0, 1)
	if room != "":
		var p: Vector2 = _rooms[room]["pos"]
		toward = (ORIGIN + Vector3(p.x, 0, p.y)) - prop.global_position
		toward.y = 0.0
		if toward.length() < 0.2:
			toward = Vector3(0, 0, 1)
	toward = toward.normalized().rotated(Vector3.UP, deg_to_rad(off_axis))
	var stand: Vector3 = aim + toward * (dist + radius)
	_player.global_position = Vector3(stand.x, ORIGIN.y + 0.1, stand.z)
	_player.call("force_update_transform")
	_player.call("ai_look_at", aim)
	var cam := _player.get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.force_update_transform()
	return _player.call("ai_interact_target")


# RMS of the SOURCE .wav on disk, in dBFS. Same helper as check_backrooms_audio.gd — it must
# read the FILE, because this project imports .wav as QOA and the in-memory bytes are not PCM.
func _rms_dbfs(res_path: String) -> float:
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return -999.0
	var bytes: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return -999.0
	var bits := 16
	var pos := 12
	var data_at := -1
	var data_len := 0
	while pos + 8 <= bytes.size():
		var id: String = bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size: int = bytes.decode_u32(pos + 4)
		if id == "fmt ":
			bits = bytes.decode_u16(pos + 22)
		elif id == "data":
			data_at = pos + 8
			data_len = size
			break
		pos += 8 + size + (size & 1)
	if data_at == -1 or bits != 16:
		return -999.0
	var frames: int = mini(data_len, bytes.size() - data_at) / 2
	if frames == 0:
		return -999.0
	var step: int = maxi(1, frames / 20000)
	var acc := 0.0
	var n := 0
	var i := 0
	while i < frames:
		var s: float = float(bytes.decode_s16(data_at + i * 2)) / 32768.0
		acc += s * s
		n += 1
		i += step
	if n == 0:
		return -999.0
	return 20.0 * log(sqrt(acc / float(n)) + 1e-12) / log(10.0)


func _report() -> bool:
	print("--------------------------------------------------")
	print("  %d checks, %d failed" % [_checks, _fails.size()])
	for f in _fails:
		print("    - ", f)
	print("RESULT: ", "PASS" if _fails.is_empty() else "FAIL")
	print("--------------------------------------------------")
	quit(0 if _fails.is_empty() else 1)
	return true
