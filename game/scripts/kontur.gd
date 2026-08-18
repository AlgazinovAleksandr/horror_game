extends Node3D

# Level 5 — KONTUR ("Object 12"). Built procedurally with RoomBuilder: a decaying
# Soviet stairwell landing that sterilises, room by room, into a clinical K.O.N.T.U.R.
# containment wing.
#
# THE POINT OF THIS LEVEL: it is the only level whose answers are not inside it.
# EIGHT gates, each a different verb, each one's answer planted in an earlier level:
#
#   Gate 1  THE TWO DOORS   choose      <- hidden note in L1 (the Lab morgue)
#   Gate 2  THE SHELF       use         <- the L2 House TV static card
#   Gate 5  THE ROSTER      recall      <- TWO notes in the L4 Backrooms Flood, one
#                                          digit each, both off the main route. Was
#                                          "47" from the intro note until BACKLOG #24
#   Gate 3  THE OFFERING    abstain     <- the L3 Corridor door plate
#   Gate 6  THE PHONE       destroy     <- the L4 Backrooms phone (a read-to-die trap);
#                                          was "ignore" until BUG_FIX.md 4.6 — a hammer
#                                          waits in Landing, and the ring itself now
#                                          drains panic until it's smashed
#   Gate 7  THE DARK ROOM   unlight     <- the L4 Backrooms Flood (light hides the way)
#   Gate 8  THE AIRLOCK     catch       <- self-taught. Was a 9 s stillness hold ("wait")
#                                          until BUG_FIX.md 4.7 replaced it with a marker-
#                                          catch minigame — still inverts the Backrooms
#                                          standing-still rule, still has to teach itself
#   Gate 4  THE ESCORT      don't look  <- the L4 Backrooms wall scrawl
#
# In-level signs state each rule with the operative word REDACTED, so a player who
# missed the hints is guessing, not stuck.
#
# FAIL ECONOMY (unique to this level): the whole floor is one DreadZone, whose decay
# (2/s) and pressure (2/s) cancel exactly — so panic never drains here. Each wrong
# answer is a survivable flash scare plus STRIKE_PANIC. Three strikes overshoot
# PANIC_MAX and add_panic() fires the fatal screamer on its own; there is no
# bespoke death path in this file.
#
# TWO CONSEQUENCES THAT ARE NOT STRIKES (added 2026-07-21, after the level was
# measured clearing in 32 seconds):
#
#   BANISHMENT — the wrong door at Gate 1 no longer merely stings. The two doors now
#   open into two SEPARATE antechambers, and the wrong one has no floor: you fall out
#   of the world, and wake up a whole level back, in the Backrooms, with a red
#   accusation on the screen. The previous design put both doors into the same room
#   behind a 3 m fungus block inside an 8 m wall — you just walked around it.
#
#   FORFEIT — the exit used to have NO unlock condition at all, so every gate in the
#   level was skippable and the four "answers" cost nothing but panic. The exit is now
#   held by `extra_lock` until all eight gates are passed. Failing one of the three
#   ABSTAIN gates (offering / phone / escort) cannot be undone, so it voids the run:
#   `_forfeit()` says so immediately and loudly, because a player discovering it at a
#   silent locked door would rightly read that as a bug.

const TEX := "res://assets/textures/level_5_kontur/"
const LAB_TEX := "res://assets/textures/level_1_lab/"
const HOUSE_TEX := "res://assets/textures/level_2_house/"
const PRESERVE := ["Environment", "AmbientPlayer", "HUDCanvas", "Player"]

const _DOOR_SCRIPT := preload("res://scripts/door.gd")
const _NOTE_SCRIPT := preload("res://scripts/note.gd")

const STRIKE_PANIC := 18.0        # 3 x 18 = 54 > PANIC_MAX (50)
const FLASH_PATH := TEX + "kontur_flash.png"
const FLASH_AUDIO := "kontur_flash"

# ⚠️ Was "47" — Subject 47, from the intro room's opening note. BACKLOG #24: that made
# the one gate designed to be answered from memory into the one gate nobody had to look
# for, because the answer had been on screen in the first minute of the game and is in
# the level's own objective text besides. It now has NO other source anywhere: both
# digits are written down in the Backrooms Flood (backrooms_zone3.gd:_build_digit_notes),
# one per note, in the two side runs off the main route — so clearing KONTUR requires
# having actually searched the flooded wing a level earlier.
#
# That is a deliberately hard dependency, and two other systems exist to keep it fair:
# the notes journal (re-read anything you found, from anywhere) and per-level progress
# snapshots (walk back to level 4 without replaying it).
#
# TWO digits, deliberately: on a 3-dial lock a 2-digit answer is ambiguous (063? 630?)
# and a playtester who knew the old answer still failed it twice. The lock sizes itself
# from this string.
const ROSTER_CODE := "63"

# How long gate 6's opening scrawl waits before it speaks. Not a difficulty constant — it is
# the gap that keeps two pieces of text off each other. `NoticeBriefing` is meant to be read
# from the spawn in the first seconds; the scrawl used to be drawn straight across it. 7 s is
# the shortest delay that clears the notice's own reading time with room to spare, and it is
# still a level-opening beat — you are in the Landing for far longer than this.
const SCRAWL_DELAY := 7.0
const VOID_Y := -4.0              # same threshold the Void uses (level_3.gd)
# Gate 8 was a 9s stillness hold ("stand here and wait") — measured as boring in
# playtest. Replaced with a catch minigame: a marker sweeps the track; press E while
# it's inside the lit target zone, 3 times in a row. A miss is a full gate strike
# (⚠️ DELIBERATE — confirmed with the user, who understood 3 mistimed catches alone
# could end the run before choosing this over a softer custom penalty).
const AIRLOCK_MARKER_PERIOD := 2.0   # seconds for one full sweep of the track
const AIRLOCK_TARGET_WIDTH := 0.35   # fraction of the track counted as a catch
const AIRLOCK_CATCHES_NEEDED := 3

# Gate 6 redesign: "ignore" -> "destroy". The ring itself is now a threat (see
# _tick_phone_pressure) — KONTUR's decay is zero everywhere (the level DreadZone
# cancels it exactly), so this pressure only ever accumulates until the phone is
# smashed. Silencing it, not just avoiding it, is what passes the gate now.
const PHONE_PRESSURE_RANGE := 7.0
const PHONE_PRESSURE_RATE := 4.5  # panic/s while unresolved and the player is near

# The shared "hold your nerve" apparition (Lab/House already have it; the Void,
# Corridor and Backrooms deliberately don't — they run their own bespoke scares).
# By level 5 the player has been taught the rule twice already, so this is fatal from
# the first appearance — unless they somehow reached KONTUR without ever meeting one,
# which ApparitionDirector's global teach ledger covers.
const RANDOM_APPARITIONS := true

var _builder: RoomBuilder
var _lights: Array = []           # [OmniLight3D, base_energy]
var _strikes: int = 0
var _held_bottle: String = ""     # "" | "vinegar" | "bleach" | "water"
var _barrier: FungalBarrier
var _took_offering: bool = false
var _answered_phone: bool = false
var _gate1_done: bool = false
var _gate3_scored: bool = false
var _banished: bool = false       # guards the fall handler against re-entry
var _forfeited: bool = false
var _exit_door: StaticBody3D

# Where the Blackout room's real exit lies. Randomised per run from three candidate
# x offsets, and the Airlock/Escort/Terminus spine is BUILT at that offset — so the
# answer is genuinely different each time rather than a memorised doorway.
var _dark_x: float = 0.0
# Which side of the Vestibule the BLACK (correct) door is on. Randomised per run for
# the same reason: the answer is the colour, never the position.
var _gate1_black_east: bool = true
# True once _preload_snapshot() has re-seeded BOTH of the above from a saved run. It
# is what stops _build_geometry()/_spawn_gate1_doors() re-rolling them — see the
# ⚠️ block on _preload_snapshot().
var _randomisation_restored: bool = false
var _rooms_cache: Array = []

# Gate ledger. The exit stays sealed until every one of these is true; the four
# "physical" gates set themselves simply by being passed, and the three abstain gates
# are scored as the player leaves the room that poses them.
var _gates := {
	"doors": false, "shelf": false, "roster": false, "offering": false,
	"phone": false, "dark": false, "airlock": false, "escort": false,
}

# Gate 7 state: [MeshInstance3D, is_real]
var _dark_seams: Array = []

# Gate 8 state. _airlock_t is time-in-zone, driving the marker's oscillation phase.
var _airlock_t: float = 0.0
var _in_airlock: bool = false
var _airlock_track: MeshInstance3D   # the fixed background bar
var _airlock_meter: MeshInstance3D   # fixed target-zone highlight (not a fill bar)
var _airlock_marker: MeshInstance3D  # the moving catch target
var _airlock_streak: int = 0
var _airlock_seal: CSGBox3D

# Which prop the Perëkozhnik is wearing this run — see _spawn_creature(). Restored,
# never re-rolled, on a back-door return.
var _mimic_site: String = "kitchen"
var _mimic_mark: Vector3 = Vector3.ZERO
# Derived from the generated file's measured level (tools/make_sfx_kontur_extra.py
# prints it), not from a plausible number.
# Derived: `perekozhnik_shed.wav` measures -21.88 dBFS RMS against `door_seal.wav`'s
# -11.67, and `door_seal` is what this level plays at 0.0 dB. +10.2 puts the two at the
# same perceived level (tools/make_sfx_kontur_extra.py prints both).
const MIMIC_SHED_DB := 10.2

# Gate 6 state.
var _phone: RotaryPhone
var _has_hammer: bool = false

# Everything a resumed run has to be able to UNSEAL again. Held as references rather
# than looked up by name because Godot renames colliding siblings (Issue 17) and three
# of these are built inside the same _ready().
var _black_door: ChoiceDoor
var _roster_seal: CSGBox3D



func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameState.current_level = 5

	_clear_old_scene()
	_preload_snapshot()      # FIRST — it decides what the geometry is allowed to roll
	_build_geometry()
	_place_player()
	_spawn_lights()
	_spawn_dread()
	_spawn_gate1_doors()
	_spawn_gate2_shelf()
	_spawn_gate5_roster()
	_spawn_gate3_offering()
	_spawn_gate6_phone()
	_spawn_gate7_dark()
	_spawn_gate8_airlock()
	_spawn_gate4_escort()
	_spawn_creature()
	_spawn_containment_cell()
	_spawn_apparition_director()
	_restore_progress()      # last — it re-applies the gate ledger and the exit lock
	_spawn_signs()
	_spawn_props()
	_spawn_level_doors()
	_refresh_exit()
	_start_ambience()
	_boost_ambient(0.3)

	GameState.set_objective("PROTOCOL 4-B — PROCEED TO THE MARKED EXIT")

	# Gate 6's diegetic nudge, moved off a physical note (it was clipping into the
	# Switchboard desk, and playtest asked for it as a level-opening beat instead of
	# something to find and read later). It stays a level-opening beat — you are still
	# in the Landing when it lands.
	#
	# ⚠️ DELAYED BY `SCRAWL_DELAY` (2026-08-18), and the delay is load-bearing. It used to
	# fire on the first process frame for 5 s, which put it **directly across the hero line
	# of `NoticeBriefing`** — photographed: "IF ONLY I COULD BREAK ONE" sat on top of the
	# word BRIEFED. Two pieces of text competing for the one moment the notice exists for,
	# and both harder to read for it. Backlog D12/D13.
	#
	# ⚠️ `process_always` is **false** on purpose (the 2nd arg). `SceneTreeTimer` defaults it
	# to TRUE, so a bare `create_timer()` counts down through a paused tree — and `NoteUI`
	# pauses the tree. A player who walks up and reads the notice would otherwise have the
	# scrawl fire behind the page and be gone before they closed it. With it false the beat
	# waits for them. This is cross-level X16: every set-piece built on a bare
	# `create_timer(...).timeout` plays to someone who is reading or pinned.
	get_tree().create_timer(SCRAWL_DELAY, false).timeout.connect(func() -> void:
		ScreenText.scrawl(get_tree(), "I HATE THOSE PHONES.\nIF ONLY I COULD BREAK ONE.", 5.0, 40)
	)


func _player() -> CharacterBody3D:
	return get_node_or_null("Player") as CharacterBody3D


func _clear_old_scene() -> void:
	for child in get_children():
		if PRESERVE.has(child.name):
			continue
		# ⚠️ remove_child BEFORE queue_free. queue_free() is deferred to the end of the
		# frame, so a node freed this way is STILL A CHILD — and still holding its name
		# — while _ready() builds the replacement level. Godot then renames the new
		# node on the collision (Issue 17), and every later get_node("ExitDoor") in
		# these levels silently missed: probed on the Lab, both doors came back as
		# @StaticBody3D@332 / @334. remove_child() detaches immediately, so the name is
		# free by the time the new door is added. (Found 2026-07-27 by the autoplay
		# harness, which is the first thing that ever looked a door up by name.)
		remove_child(child)
		child.queue_free()


# ---------------------------------------------------------------- geometry

# A single spine running +z. Rooms ABUT (RoomBuilder needs a shared wall plane).
#
# Gate 1's two doors open into two SEPARATE antechambers (AnteWest / AnteEast) rather
# than into one shared Passage. That separation is the whole point: the wrong one has
# its floor removed at build time, so the wrong door is a hole, not a decoration.
const ROOMS := [
	{ "name": "Landing",     "pos": Vector2(0, 0),     "size": Vector2(6, 8) },   # z  -4 ..  4
	{ "name": "Vestibule",   "pos": Vector2(0, 7),     "size": Vector2(8, 6) },   # z   4 .. 10
	{ "name": "AnteWest",    "pos": Vector2(-2, 11.5), "size": Vector2(3, 3) },   # z  10 .. 13
	{ "name": "AnteEast",    "pos": Vector2(2, 11.5),  "size": Vector2(3, 3) },   # z  10 .. 13
	{ "name": "Passage",     "pos": Vector2(0, 16.5),  "size": Vector2(8, 7) },   # z  13 .. 20
	{ "name": "Kitchen",     "pos": Vector2(0, 23.5),  "size": Vector2(8, 7) },   # z  20 .. 27
	{ "name": "Records",     "pos": Vector2(0, 31),    "size": Vector2(8, 8) },   # z  27 .. 35
	{ "name": "Archive",     "pos": Vector2(0, 39.5),  "size": Vector2(9, 9) },   # z  35 .. 44
	{ "name": "Switchboard", "pos": Vector2(0, 47.5),  "size": Vector2(7, 7) },   # z  44 .. 51
	{ "name": "Blackout",    "pos": Vector2(0, 55.5),  "size": Vector2(9, 9) },   # z  51 .. 60
]

# Gate 1's two doorways sit at x = -2 and x = +2, so the wall CENTRE (x = 0) stays
# solid — that is where the redacted sign hangs. Everywhere else the doorway is on
# the wall centre, so props must go on the east/west walls (Session 11 bug class:
# a collider on a doorway wall silently seals the room).
const GATE1_X := 2.0

# The Blackout room's exit can be at any of these three x offsets. The Airlock, Escort
# and Terminus are built at whichever is drawn, so "which of the three doors is real"
# has a different answer every run.
const DARK_CANDIDATES := [-3.0, 0.0, 3.0]

const DOORS := [
	{ "pos": Vector2(0, 4),           "width": 1.8, "dir": "z" },   # Landing     <-> Vestibule
	{ "pos": Vector2(-GATE1_X, 10),   "width": 1.4, "dir": "z" },   # Vestibule   <-> AnteWest
	{ "pos": Vector2(GATE1_X, 10),    "width": 1.4, "dir": "z" },   # Vestibule   <-> AnteEast
	{ "pos": Vector2(-GATE1_X, 13),   "width": 1.4, "dir": "z" },   # AnteWest    <-> Passage
	{ "pos": Vector2(GATE1_X, 13),    "width": 1.4, "dir": "z" },   # AnteEast    <-> Passage
	{ "pos": Vector2(0, 20),          "width": 1.8, "dir": "z" },   # Passage     <-> Kitchen
	{ "pos": Vector2(0, 27),          "width": 1.8, "dir": "z" },   # Kitchen     <-> Records   (barrier)
	{ "pos": Vector2(0, 35),          "width": 1.8, "dir": "z" },   # Records     <-> Archive   (roster lock)
	{ "pos": Vector2(0, 44),          "width": 1.8, "dir": "z" },   # Archive     <-> Switchboard
	{ "pos": Vector2(0, 51),          "width": 1.8, "dir": "z" },   # Switchboard <-> Blackout
]

# Which rooms wear the sterile facility skin rather than Soviet decay.
const FACILITY_ROOMS := ["Blackout", "Airlock", "Escort", "Terminus"]
# Which rooms are raw infected concrete rather than wallpaper.
const CONCRETE_ROOMS := ["Passage", "AnteWest", "AnteEast", "Records", "Archive", "Switchboard"]


# The back half hangs off the randomised Blackout exit, so it can't be a const.
func _tail_rooms() -> Array:
	return [
		{ "name": "Airlock",  "pos": Vector2(_dark_x, 63), "size": Vector2(4, 6) },   # z 60 .. 66
		{ "name": "Escort",   "pos": Vector2(_dark_x, 79), "size": Vector2(3, 26) },  # z 66 .. 92
		{ "name": "Terminus", "pos": Vector2(_dark_x, 95), "size": Vector2(6, 6) },   # z 92 .. 98
	]


func _tail_doors() -> Array:
	return [
		{ "pos": Vector2(_dark_x, 60), "width": 1.6, "dir": "z" },  # Blackout <-> Airlock (THE real one)
		{ "pos": Vector2(_dark_x, 66), "width": 1.6, "dir": "z" },  # Airlock  <-> Escort
		{ "pos": Vector2(_dark_x, 92), "width": 1.6, "dir": "z" },  # Escort   <-> Terminus
	]


func _build_geometry() -> void:
	if not _randomisation_restored:
		_dark_x = DARK_CANDIDATES[randi() % DARK_CANDIDATES.size()]
	_builder = RoomBuilder.new()
	_builder.wall_mat = _mat(TEX + "kontur_wallpaper_soviet.png", 0.35, Color(0.36, 0.34, 0.22))
	_builder.floor_mat = _mat(TEX + "kontur_floor_tile.png", 0.4, Color(0.24, 0.22, 0.19))
	_builder.ceil_mat = _mat(HOUSE_TEX + "house_ceiling.png", 0.35, Color(0.18, 0.17, 0.15))
	add_child(_builder)
	_rooms_cache = _rooms_with_skins()
	_builder.build(_rooms_cache, DOORS + _tail_doors())


# Negative V, like corridor.gd / backrooms.gd — a positive y-scale renders the wall
# texture upside-down under triplanar mapping.
func _mat(tex_path: String, scale: float, fallback: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.92
	if tex_path != "" and ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(scale, -scale, scale)
	else:
		mat.albedo_color = fallback
	return mat


# The visual arc IS the story: peeling Soviet wallpaper -> raw infected concrete ->
# clinical KONTUR tile. Per-room overrides do the whole job.
func _rooms_with_skins() -> Array:
	var concrete := _mat(TEX + "kontur_concrete_infected.png", 0.35, Color(0.26, 0.27, 0.24))
	var facility := _mat(TEX + "kontur_facility_wall.png", 0.4, Color(0.62, 0.66, 0.62))
	var fac_floor := _mat(LAB_TEX + "lab_floor.png", 0.4, Color(0.4, 0.42, 0.4))
	var fac_ceil := _mat(LAB_TEX + "lab_ceiling.png", 0.4, Color(0.3, 0.32, 0.3))

	var out: Array = []
	for r in ROOMS + _tail_rooms():
		var room: Dictionary = r.duplicate()
		var n: String = room["name"]
		if FACILITY_ROOMS.has(n):
			room["wall_mat"] = facility
			room["floor_mat"] = fac_floor
			room["ceil_mat"] = fac_ceil
		elif CONCRETE_ROOMS.has(n):
			room["wall_mat"] = concrete
		out.append(room)
	return out


# Entry vs. exit spawn — see level_1.gd's note.
const ENTRY_SPAWN := Vector3(0, 0.1, -3.0)

func _place_player() -> void:
	var p := _player()
	if not p:
		return
	if GameState.entered_from_ahead:
		# Terminus, just inside the exit — and at the randomised _dark_x offset, since
		# the whole Airlock/Escort/Terminus spine moves per run (gate 7).
		p.global_position = Vector3(_dark_x, 0.1, 94.0)
		p.rotation = Vector3(0, 0, 0)
	else:
		p.global_position = ENTRY_SPAWN
		p.rotation = Vector3(0, PI, 0)   # face +z, down the spine


# ---------------------------------------------------------------- progress snapshot
#
# KONTUR has more state worth keeping than any other level: eight gates, a strike
# count, a forfeit flag, and two per-run randomisations (which door is black, where the
# facility spine sits) that MUST come back identical — restoring the gate ledger while
# re-rolling the answers would mark gates passed whose puzzles now have different
# solutions.
#
# ⚠️ Strikes are saved too, on purpose. They are the level's fail economy; discarding
# them on a walk-out would make the back door a free strike-reset.

func save_progress() -> Dictionary:
	return {
		"gates": _gates.duplicate(),
		"strikes": _strikes,
		"forfeited": _forfeited,
		"has_hammer": _has_hammer,
		"held_bottle": _held_bottle,
		"took_offering": _took_offering,
		"gate3_scored": _gate3_scored,
		"gate1_done": _gate1_done,
		"dark_x": _dark_x,
		"gate1_black_east": _gate1_black_east,
		"mimic_site": _mimic_site,
	}


# ⚠️ THE RANDOMISATIONS ARE RESTORED BEFORE ANYTHING IS BUILT (2026-08-18, K-T6 / X48).
#
# `save_progress()` had written "dark_x" since the day the snapshot was added and
# NOTHING EVER READ IT BACK, and the gate-1 colour was not saved at all. So a back-door
# return re-rolled both answers while restoring the ledger earned against the old ones:
# gate 7 came back marked passed with the real seam moved to a different wall, and gate
# 1 came back marked passed with the black door possibly on the other side and the hole
# in the floor under whichever antechamber drew red THIS time.
#
# It has to run before _build_geometry() and _spawn_gate1_doors(), because those two are
# what consume the dice. _restore_progress() (which runs last, on purpose, so it can
# re-apply the ledger over finished props) is far too late for this half.
func _preload_snapshot() -> void:
	var data := GameState.get_level_progress(5)
	if data.is_empty():
		return
	if not (data.has("dark_x") and data.has("gate1_black_east")):
		# A snapshot written by an older build. Re-rolling is still wrong, but there is
		# nothing to restore FROM — say so rather than silently doing the old thing.
		push_warning("KONTUR: snapshot has no randomisation; gate 1/7 answers will be re-rolled")
		return
	_dark_x = float(data["dark_x"])
	_gate1_black_east = bool(data["gate1_black_east"])
	_mimic_site = String(data.get("mimic_site", _mimic_site))
	_randomisation_restored = true


func _restore_progress() -> void:
	var data := GameState.get_level_progress(5)
	if data.is_empty():
		return
	for key in data.get("gates", {}):
		_gates[key] = bool(data["gates"][key])
	_strikes = int(data.get("strikes", 0))
	_forfeited = bool(data.get("forfeited", false))
	_has_hammer = bool(data.get("has_hammer", false))
	_held_bottle = String(data.get("held_bottle", ""))
	_took_offering = bool(data.get("took_offering", false))
	_gate3_scored = bool(data.get("gate3_scored", false))
	_gate1_done = bool(data.get("gate1_done", false))
	if _held_bottle != "":
		GameState.set_carried(_held_bottle)
		var stale := get_node_or_null("Bottle_" + _held_bottle)
		if stale:
			stale.queue_free()      # it is in the player's hands, not on the shelf
	elif _has_hammer:
		GameState.set_carried("hammer")
	if _has_hammer:
		var hammer := get_node_or_null("Hammer")
		if hammer:
			hammer.queue_free()
		if is_instance_valid(_phone):
			_phone.smashable = true
	_reopen_passed_gates()
	_refresh_exit()


# ⚠️ A PASSED GATE MUST NOT COME BACK AS A WALL (2026-08-18, found while fixing K-T6).
#
# `_restore_progress()` restored the eight-gate LEDGER and nothing else, while `_ready()`
# had just rebuilt every physical seal from scratch. Three of those seals stand across
# the spine, and one of them is unrecoverable:
#
#   AirlockSeal  z=66, Airlock -> Escort.  `_tick_airlock()` opens with
#                `if _gates["airlock"] ... return`, so on a resumed run the marker never
#                moves and E does nothing — the seal can never be removed again. A player
#                who cleared gate 8, walked back to the Backrooms for a note and returned
#                was WALLED IN at z=66 with the exit 32 m behind it. Measured, not argued:
#                `check_kontur_resume.gd` drives the real `ai_interact()` path and probes
#                the doorway by ray.
#   RosterSeal   z=35, Records -> Archive. Recoverable only by re-entering a code the
#                player has already spent, which reads as the level forgetting.
#   FungalBarrier z=27. Recoverable (the shelf restocks), but it costs a bottle walk for
#                a gate the ledger says is done.
#   ChoiceDoor   the black leaf swings shut again on a gate that cannot be re-taken.
#
# The rule this encodes: **restoring a ledger without restoring the world it describes is
# worse than not restoring it at all** — the world and the ledger then disagree, and the
# ledger is the half the exit door reads.
func _reopen_passed_gates() -> void:
	if _gates["doors"] and is_instance_valid(_black_door):
		_black_door.open_instantly()
	if _gates["shelf"] and is_instance_valid(_barrier):
		_barrier.dissolve()
	if _gates["roster"] and is_instance_valid(_roster_seal):
		_roster_seal.queue_free()
	if _gates["airlock"]:
		for widget in [_airlock_seal, _airlock_track, _airlock_meter, _airlock_marker]:
			if is_instance_valid(widget):
				widget.queue_free()
	if _gates["phone"] and is_instance_valid(_phone):
		_phone.mark_smashed()


# ---------------------------------------------------------------- lighting

func _spawn_lights() -> void:
	# Soviet half: sickly, weak, warm-green. Facility half: cold and bright.
	_add_lamp("Landing", Vector3(0, 2.6, 0), 0.55, Color(0.9, 0.78, 0.5))
	_add_lamp("Vestibule", Vector3(0, 2.6, 7), 0.5, Color(0.85, 0.8, 0.55))
	_add_lamp("PassageA", Vector3(0, 2.6, 15), 0.4, Color(0.7, 0.8, 0.65))
	_add_lamp("PassageB", Vector3(0, 2.6, 19), 0.32, Color(0.7, 0.8, 0.65))
	_add_lamp("Kitchen", Vector3(0, 2.6, 23.5), 0.5, Color(0.9, 0.8, 0.55))
	_add_lamp("Records", Vector3(0, 2.6, 31), 0.45, Color(0.8, 0.8, 0.6))
	_add_lamp("ArchiveA", Vector3(0, 2.6, 37.5), 0.4, Color(0.75, 0.8, 0.7))
	_add_lamp("ArchiveB", Vector3(0, 2.6, 42), 0.4, Color(0.75, 0.8, 0.7))
	_add_lamp("Switchboard", Vector3(0, 2.6, 47.5), 0.42, Color(0.75, 0.78, 0.7))
	# NO lamp in the Blackout — the name is the gate. Gate 7 is unplayable if lit.
	_add_lamp("Airlock", Vector3(_dark_x, 2.6, 63), 1.0, Color(0.85, 0.95, 1.0))
	for i in range(5):
		_add_lamp("Escort%d" % i, Vector3(_dark_x, 2.7, 69.0 + i * 5.5), 0.85,
			Color(0.85, 0.95, 1.0))
	_add_lamp("Terminus", Vector3(_dark_x, 2.6, 95), 0.9, Color(0.85, 0.95, 1.0))


func _add_lamp(lamp_name: String, pos: Vector3, energy: float, color: Color) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp_" + lamp_name
	lamp.position = pos
	lamp.light_energy = energy
	lamp.light_color = color
	lamp.omni_range = 11.0
	add_child(lamp)
	_lights.append([lamp, energy])


# ---------------------------------------------------------------- panic floor

func _spawn_dread() -> void:
	# One DreadZone over the whole level. DREAD_DECAY_RATE and DREAD_PANIC_RATE are
	# both 2.0/s in player.gd, so they cancel: panic neither drains nor grows while
	# you simply walk. That is the entire no-decay economy — no player.gd changes.
	var zone := DreadZone.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# Must span the WHOLE spine (z -4 .. 98) or the no-decay economy silently stops
	# applying partway through the level.
	shape.size = Vector3(24, 6, 110)
	col.shape = shape
	zone.position = Vector3(0, 2.0, 47.0)
	zone.add_child(col)
	add_child(zone)

	# The infected middle is also dark — the flashlight matters here.
	var dark := DarkZone.new()
	var dcol := CollisionShape3D.new()
	var dshape := BoxShape3D.new()
	dshape.size = Vector3(10, 4, 7)
	dcol.shape = dshape
	dark.add_child(dcol)
	dark.position = Vector3(0, 2.0, 16.5)
	add_child(dark)


# A wrong answer. Survivable on its own; the third one is not, because add_panic()
# fires the fatal screamer once _panic crosses PANIC_MAX.
func _strike(message: String) -> void:
	_strikes += 1
	Screamer.flash_scare(FLASH_PATH, FLASH_AUDIO, 0.8)
	var p := _player()
	if p:
		p.jolt_camera(0.1, 0.5)
		p.add_panic(STRIKE_PANIC)
	_notice(message, Color(1.0, 0.3, 0.25))

	# Playtest instrumentation. Guarded so removing the DebugLog autoload is enough
	# to strip it — nothing here affects play.
	var dbg := get_node_or_null("/root/DebugLog")
	if dbg and dbg.has_method("note"):
		dbg.note("STRIKE %d/3 — %s" % [_strikes, message])


func _notice(text: String, color: Color) -> void:
	ScreenText.toast(get_tree(), text, color)


# ---------------------------------------------------------------- the gate ledger

func _pass_gate(key: String) -> void:
	if _gates.get(key, true):
		return
	_gates[key] = true
	var dbg := get_node_or_null("/root/DebugLog")
	if dbg and dbg.has_method("note"):
		dbg.note("GATE PASSED — %s (%d/%d)" % [key, _passed_count(), _gates.size()])
	_refresh_exit()


func _passed_count() -> int:
	var n := 0
	for k in _gates:
		if _gates[k]:
			n += 1
	return n


func _refresh_exit() -> void:
	if not is_instance_valid(_exit_door):
		return
	if _forfeited:
		_exit_door.extra_lock = true
		_exit_door.locked_message = "PROTOCOL 4-B VOIDED\nTHIS SUBJECT DOES NOT LEAVE"
		return
	var all_done: bool = _passed_count() >= _gates.size()
	_exit_door.extra_lock = not all_done
	_exit_door.locked_message = "SEALED — PROTOCOL INCOMPLETE (%d/%d)" \
		% [_passed_count(), _gates.size()]


# An abstain gate failed, and abstaining cannot be retaken. The run is over.
#
# The user chose this over letting the player redo the section, knowing the risk:
# a sealed door with no explanation reads as a bug, not a verdict. So this has to be
# UNMISSABLE and IMMEDIATE — the scrawl, the objective line and the door's own locked
# message all say the same thing, within a second of the mistake. Do not quiet this
# down; the loudness is the mitigation.
func _forfeit(reason: String) -> void:
	if _forfeited:
		return
	_forfeited = true
	_strike(reason)
	ScreenText.scrawl(get_tree(), "THE PROTOCOL IS VOID\nYOU DO NOT LEAVE THIS FLOOR", 4.0, 46)
	GameState.set_objective("PROTOCOL 4-B VOIDED — THERE IS NO EXIT NOW")
	_refresh_exit()
	var dbg := get_node_or_null("/root/DebugLog")
	if dbg and dbg.has_method("note"):
		dbg.note("FORFEIT — %s" % reason)


# ---------------------------------------------------------------- gate 1: the doors

func _spawn_gate1_doors() -> void:
	# Which side is black is randomised per run, so the answer is the COLOUR (from
	# the L1 note), never a memorised position — and it is RESTORED, never re-rolled,
	# on a back-door return (see _preload_snapshot()).
	if not _randomisation_restored:
		_gate1_black_east = randf() < 0.5
	var black_on_east := _gate1_black_east
	_make_choice_door(GATE1_X, black_on_east)
	_make_choice_door(-GATE1_X, not black_on_east)
	var red_x: float = -GATE1_X if black_on_east else GATE1_X
	_open_the_void("AnteWest" if red_x < 0.0 else "AnteEast", red_x)


# THE PUNISHMENT FOR NOT READING.
#
# Take the floor out of the antechamber behind the red door. The player opens it,
# steps through onto the doorway's floor bridge, takes one more pace, and there is
# nothing there — `_check_void_fall` then banishes them to the Backrooms.
#
# Done by FREEING RoomBuilder's floor nodes rather than by CSG subtraction: the
# builder emits every floor as its own independent CSGBox3D root (`_box`), so a
# subtraction child would have to be added to each one separately and its collision
# regenerated. Deleting the boxes is exactly what level_3.gd:_break_room_c_floor()
# does for the Void, and it is proven.
#
# ⚠️ The floor under a doorway is NOT part of the room's floor box — RoomBuilder emits
# a separate bridge for every doorway (that is how the Issue-5 void-fall class was
# killed). The bridge on into the Passage must go too, or the hole is only the 0.4 m
# the two bridges fail to cover and the player steps straight over it. The ENTRY
# bridge is deliberately KEPT: standing on a lip and seeing the drop ahead of you
# reads as a trap you walked into, not as a glitch.
#
# ⚠️ MATCH ON GEOMETRY, NOT ON NAME. RoomBuilder names every bridge "DoorFloor", and
# Godot renames colliding siblings using the CLASS name — the second one onward are
# "@CSGBox3D@19", "@CSGBox3D@20"… so only the very first bridge in the whole level
# keeps a matchable name. Room floors are fine (their names are unique); bridges must
# be found by where they are.
func _open_the_void(ante_room: String, red_x: float) -> void:
	var killed := 0
	var bridge_at := Vector3(red_x, -RoomBuilder.T / 2.0, 13.0)
	for child in _builder.get_children():
		if not (child is CSGBox3D):
			continue
		if child.name == "%s_Floor" % ante_room:
			child.queue_free()
			killed += 1
		elif child.position.distance_to(bridge_at) < 0.25:
			child.queue_free()
			killed += 1
	if killed != 2:
		push_warning("KONTUR: the void behind the red door is incomplete (freed %d of 2)"
			% killed)


func _make_choice_door(x: float, is_black: bool) -> void:
	var d := ChoiceDoor.new()
	d.name = "ChoiceDoor_%s" % ("Black" if is_black else "Red")
	d.is_correct = is_black
	# ⚠️ `_leaf` is the CROPPED artwork. The originals are a door plus the concrete wall
	# and reveal around it — Issue 35 / X24 on the one prop the level's first gate is
	# about telling apart (tools/crop_kontur_art.py).
	d.texture_path = TEX + ("door_black_leaf.png" if is_black else "door_red_leaf.png")
	# The node is the hinge; the panel extends +x from it, so start half a width left.
	d.position = Vector3(x - ChoiceDoor.WIDTH / 2.0, 0.0, 10.0)
	d.chosen.connect(_on_gate1_chosen)
	add_child(d)
	if is_black:
		_black_door = d

	# RoomBuilder cuts doorways FULL HEIGHT, so a 2.2 m door leaves an open transom
	# you can see straight over. Fill the gap above the frame.
	var transom := CSGBox3D.new()
	transom.name = "Transom"
	transom.size = Vector3(1.5, 3.0 - ChoiceDoor.HEIGHT, 0.2)
	transom.position = Vector3(x, ChoiceDoor.HEIGHT + (3.0 - ChoiceDoor.HEIGHT) / 2.0, 10.0)
	transom.use_collision = true
	transom.material = _builder.wall_mat
	add_child(transom)


func _on_gate1_chosen(correct: bool) -> void:
	if _gate1_done:
		return
	if correct:
		_gate1_done = true
		_pass_gate("doors")
		GameState.set_objective("DECONTAMINATION REQUIRED — THE WAY ON IS SEALED")
		_play_at("door_seal", Vector3(0, 1.5, 10), 0.0)
	else:
		# No strike. The door simply opens onto nothing; the drop is the answer.
		_play_at("door_seal", Vector3(0, 1.5, 10), 0.0)


# ---------------------------------------------------------------- banishment

# Modelled on level_3.gd:_check_void_fall(), but this fall is not fatal — it is a
# DEMOTION. The player wakes a whole level back, in the Backrooms, and is told why.
func _check_void_fall() -> void:
	if _banished:
		return
	var p := _player()
	if p and p.global_position.y < VOID_Y:
		_banish()


func _banish() -> void:
	_banished = true
	var dbg := get_node_or_null("/root/DebugLog")
	if dbg and dbg.has_method("note"):
		dbg.note("BANISHED — wrong door at gate 1, demoted to the Backrooms")
	# backrooms.gd reads this on arrival and clears it. It survives the transition
	# because reset_level_state() deliberately doesn't touch it (like is_ending).
	GameState.kontur_banished = true
	GameState.current_level = 4
	GameState.start_current_level()


# ---------------------------------------------------------------- gate 2: the shelf

func _spawn_gate2_shelf() -> void:
	# Three bottles on a shelf along the kitchen's east wall (the north and south
	# walls both carry doorways).
	var shelf := CSGBox3D.new()
	shelf.name = "Shelf"
	shelf.size = Vector3(0.5, 0.08, 3.6)
	shelf.position = Vector3(3.4, 0.95, 23.5)
	# No collision: a shelf collider would intercept the interaction ray before it
	# reached the bottles standing on it (the House key-stand lesson).
	shelf.use_collision = false
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.28, 0.22, 0.16)
	shelf.material = sm
	add_child(shelf)

	for kind in BOTTLE_SLOTS:
		_spawn_bottle(kind)

	_barrier = FungalBarrier.new()
	_barrier.name = "FungalBarrier"
	_barrier.position = Vector3(0, 1.5, 27.0)
	_barrier.setup(Vector3(2.2, 3.0, 0.5), TEX + "fungal_mass.png")
	_barrier.sprayed.connect(_on_barrier_sprayed)
	add_child(_barrier)


# ⚠️ SOFTLOCK FIX (2026-07-27). BottleItem.interact() queue_free()s the bottle on
# PICKUP, and _on_bottle_taken() used to overwrite _held_bottle with no check — so
# "take vinegar, then take water" destroyed the vinegar permanently and gate 2 became
# unpassable, with the exit sealed at n/8 forever and no way out but dying on purpose.
# The shelf is now restockable and every path that would consume a bottle the player
# still needs puts it back. A wrong guess still costs a full _strike(), so guessing
# remains expensive (3 x 18 > PANIC_MAX ends the run on its own) — it is just no
# longer a dead end.
const BOTTLE_SLOTS := {
	"bleach": 22.3,
	"vinegar": 23.5,
	"water": 24.7,
}

# One silhouette per agent (see bottle_item.gd's PROFILES). Legibility only — the shape
# says nothing at all about which one dissolves O-41.
const BOTTLE_PROFILES := {
	"bleach": "jug",
	"vinegar": "flask",
	"water": "carboy",
}

func _spawn_bottle(kind: String) -> void:
	if not BOTTLE_SLOTS.has(kind):
		return
	# ⚠️ BottleItem.interact() emits `taken` BEFORE its own queue_free(), and queue_free
	# is deferred to the end of the frame — so the bottle we are replacing is still in
	# the tree, still holding the name, when we get here. add_child() would then rename
	# the NEW bottle (Godot renames colliding siblings, Issue 17) and every later
	# get_node("Bottle_vinegar") would resolve to the dead one, whose _taken is already
	# true, so E on it does nothing. Push the corpse's name out of the way first.
	var stale := get_node_or_null("Bottle_" + kind)
	if stale:
		stale.name = "DeadBottle_" + kind
	var b := BottleItem.new()
	b.name = "Bottle_" + kind          # unique, so it can be found again (Issue 17)
	b.kind = kind
	b.profile = BOTTLE_PROFILES.get(kind, "flask")
	# ⚠️ `_paper` is the CROPPED, alpha-keyed label (tools/crop_kontur_art.py). The raw
	# `label_%s.png` is the generator's original — a label photographed on a saturated
	# backdrop, kept as the crop's only input, never hung on a bottle again.
	b.label_path = TEX + "label_%s_paper.png" % kind
	b.position = Vector3(3.4, 0.99, BOTTLE_SLOTS[kind])
	b.rotation.y = -PI / 2.0    # label faces into the room (-x)
	b.taken.connect(_on_bottle_taken)
	add_child(b)


func _on_bottle_taken(kind: String) -> void:
	# One hand, one bottle: picking a second one up puts the first back on its slot
	# rather than silently annihilating it.
	if _held_bottle != "" and _held_bottle != kind:
		_spawn_bottle(_held_bottle)
		_notice("You set the %s back." % _held_bottle, Color(0.75, 0.75, 0.7))
	_held_bottle = kind
	GameState.set_carried(kind)
	_notice("Carrying: %s" % kind.to_upper(), Color(0.6, 0.9, 0.6))
	# Keep it on the HUD too — the notice fades, and the barrier may be a walk away.
	GameState.set_objective("DECONTAMINATION REQUIRED — CARRYING: %s" % kind.to_upper())


func _on_barrier_sprayed() -> void:
	if _held_bottle == "":
		_notice("It will not move. Something has to break it down.", Color(0.85, 0.85, 0.7))
		return
	if _held_bottle == "vinegar":
		_held_bottle = ""
		GameState.set_carried("")
		_barrier.dissolve()
		_pass_gate("shelf")
		_play_at("acid_hiss", Vector3(0, 1.5, 27), 0.0)
		GameState.set_objective("PERSONNEL CHECKPOINT — STATE YOUR SUBJECT NUMBER")
	else:
		# The bottle is spent — but the store room is not empty, so the shelf restocks.
		# The cost of a wrong guess is the strike and the walk back, not the run.
		var spent := _held_bottle
		_held_bottle = ""
		GameState.set_carried("")
		_spawn_bottle(spent)
		_strike("IT DRANK IT")


# ---------------------------------------------------------------- gate 3: the offering

func _spawn_gate3_offering() -> void:
	var ped := OfferingPedestal.new()
	ped.name = "OfferingPedestal"
	ped.position = Vector3(0, 0, 39.0)
	ped.taken.connect(_on_offering_taken)
	add_child(ped)

	# Scored on crossing into the Switchboard: by then the choice is made either way.
	_spawn_event(Vector3(0, 1.5, 43.2), Vector3(6, 3, 1.2), _score_gate3)


func _on_offering_taken() -> void:
	_took_offering = true
	_play_at("pedestal_alarm", Vector3(0, 1.2, 39), 0.0)


func _score_gate3() -> void:
	if _gate3_scored:
		return
	_gate3_scored = true
	if _took_offering:
		_forfeit("RECOVERED ITEMS ARE BAIT")
	else:
		_pass_gate("offering")


# ---------------------------------------------------------------- gate 5: the roster

# The gate whose answer is written down two levels earlier and nowhere else: both
# digits of ROSTER_CODE are on notes in the Backrooms Flood's side runs. Nothing in
# KONTUR ever says the number — the roster plate just leaves the field blank.
func _spawn_gate5_roster() -> void:
	var lock := StaticBody3D.new()
	lock.name = "RosterLock"
	lock.set_script(load("res://scripts/combination_lock.gd"))
	lock.code = ROSTER_CODE
	lock.title_text = "PERSONNEL GATE — SUBJECT No."
	# East wall of Records: the north and south walls both carry doorways, and a
	# collider on a doorway wall silently seals the room (Session 11 bug class).
	lock.position = Vector3(3.6, 1.3, 31.0)
	add_child(lock)

	# ⚠️ Rebuilt 2026-07-25 (playtest capture #5: "the lock should be a 3d version of
	# the 2d texture — now it is the 2d texture on top of a 3d random cube").
	#
	# Two separate faults, both visible in that screenshot:
	#   1. The casing carried GREEN EMISSION at 0.4 on top of a pale albedo. Emission
	#      is most of a surface's colour in this project (Issue 21), so the box read
	#      as a glowing mint cube with a picture stuck to one side. This is Issue 27
	#      again — a findability glow that outlived the art it stood in for. It is
	#      gone entirely; the Records lamp lights this wall perfectly well.
	#   2. It was ONE box + ONE quad, and the quad squashed a 1.5:1 landscape source
	#      onto a 0.75:1 portrait mesh — a ~2x aspect distortion.
	#
	# Now a real mechanism, built the intro_room.gd:_build_wheelchair() way: a recessed
	# body, a raised bezel, four corner screws and an actual dial cylinder standing off
	# the face. combination_lock.gd's 2D dial UI is untouched — only the world prop
	# changed.
	# Local axes: the lock sits on Records' EAST wall with no node rotation, so the
	# face the player sees is -x. "Width" therefore runs along z and "height" along y.
	# The body is deliberately LANDSCAPE (0.40 z x 0.30 y) because the plate art is a
	# 1.5:1 landscape source — the old portrait mesh is what squashed it 2x.
	var body_d := 0.14
	var body_h := 0.30
	var body_w := 0.40
	var front := -body_d / 2.0          # x of the body's front face
	var rim_t := 0.025

	var steel := _mb_mat(Color(0.17, 0.18, 0.17), 0.45, 0.65)
	var bezel := _mb_mat(Color(0.26, 0.27, 0.25), 0.55, 0.5)
	var screw := _mb_mat(Color(0.34, 0.34, 0.31), 0.7, 0.35)
	var dial_mat := _mb_mat(Color(0.28, 0.27, 0.23), 0.6, 0.4)

	_mb_box(lock, "LockBody", Vector3(body_d, body_h, body_w), Vector3.ZERO, steel)

	# ⚠️ The bezel is a RIM (four bars), not a slab. A first pass made it one solid
	# box across the whole face and it buried the plate: the bar's front face and the
	# art quad landed ~2 mm apart, so the artwork was hidden behind its own frame.
	# Four bars leave the middle open, which is the point of a recess. Same
	# thin-bars-from-a-loop trick as level_1.gd:_add_tray_lip().
	var rim_x := front - rim_t / 2.0
	_mb_box(lock, "RimTop", Vector3(rim_t, rim_t, body_w),
		Vector3(rim_x, body_h / 2.0 - rim_t / 2.0, 0), bezel)
	_mb_box(lock, "RimBottom", Vector3(rim_t, rim_t, body_w),
		Vector3(rim_x, -body_h / 2.0 + rim_t / 2.0, 0), bezel)
	for sz in [-1.0, 1.0]:
		_mb_box(lock, "RimSide", Vector3(rim_t, body_h, rim_t),
			Vector3(rim_x, 0, sz * (body_w / 2.0 - rim_t / 2.0)), bezel)
	for sy in [-1.0, 1.0]:
		for sz2 in [-1.0, 1.0]:
			_mb_box(lock, "Screw", Vector3(0.014, 0.022, 0.022),
				Vector3(rim_x - rim_t / 2.0, sy * (body_h / 2.0 - rim_t / 2.0),
					sz2 * (body_w / 2.0 - rim_t / 2.0)), screw)

	# Dial on the RIGHT half of the face, art plate on the left — a real panel lock,
	# and it keeps the cylinder off the artwork. CylinderMesh's axis is local Y, so
	# rotation.z = PI/2 lays it on its side to face -x (the wheelchair's wheel trick).
	var dial := MeshInstance3D.new()
	dial.name = "Dial"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.055
	cyl.bottom_radius = 0.055
	cyl.height = 0.03
	dial.mesh = cyl
	dial.material_override = dial_mat
	dial.rotation.z = PI / 2.0
	dial.position = Vector3(front - 0.02, 0.0, 0.115)
	lock.add_child(dial)
	# Index mark, so the dial reads as something that turns to a value.
	_mb_box(dial, "Index", Vector3(0.010, 0.045, 0.007), Vector3(0.018, 0.0, 0.0), screw)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.26, body_h + 0.08, body_w + 0.08)
	col.shape = shape
	lock.add_child(col)

	# Art on a QuadMesh, never the box (Issue 24). Sized from the SOURCE's aspect and
	# fitted into the left half of the recess, rather than forced to the mesh's shape.
	#
	# ⚠️ The quad carries a little emission and the BODY carries none. That split is
	# Issue 27's documented fix: this lock used to glow mint green because its casing
	# kept a findability glow after it gained real art. But it is still a gate the
	# player has to locate on a dark wall, so the affordance moves onto the lit face
	# instead of being deleted outright — the same trade door.gd makes at 0.08.
	var lock_tex := TEX + "kontur_lock_roster.png"
	if ResourceLoader.exists(lock_tex):
		var tex: Texture2D = load(lock_tex)
		var aspect: float = float(tex.get_width()) / float(tex.get_height())
		var qw: float = 0.20
		var qh: float = qw / aspect
		if qh > body_h - 2.0 * rim_t - 0.02:
			qh = body_h - 2.0 * rim_t - 0.02
			qw = qh * aspect
		var face := MeshInstance3D.new()
		face.name = "LockPlate"
		var qm := QuadMesh.new()
		qm.size = Vector2(qw, qh)
		face.mesh = qm
		var fm := StandardMaterial3D.new()
		fm.albedo_texture = tex
		fm.roughness = 0.8
		fm.emission_enabled = true
		fm.emission_texture = tex
		fm.emission_energy_multiplier = 0.35
		face.material_override = fm
		face.position = Vector3(front - 0.006, 0.0, -0.085)
		face.rotation.y = -PI / 2.0
		lock.add_child(face)

	# The way on is welded shut until the number is entered.
	var seal := CSGBox3D.new()
	seal.name = "RosterSeal"
	seal.size = Vector3(2.0, 3.0, 0.3)
	seal.position = Vector3(0, 1.5, 35.0)
	seal.use_collision = true
	seal.material = _mat(TEX + "kontur_facility_wall.png", 0.4, Color(0.45, 0.48, 0.45))
	add_child(seal)
	_roster_seal = seal

	lock.unlocked.connect(func() -> void:
		_pass_gate("roster")
		seal.queue_free()
		_play_at("door_seal", Vector3(0, 1.5, 35), 0.0)
		GameState.set_objective("RECOVERY ARCHIVE — DO NOT DISTURB THE INVENTORY")
	)
	# Fumbling costs the lock's own 10 panic; only real brute-forcing draws a strike.
	lock.wrong_code.connect(func(attempts: int) -> void:
		if attempts == 4:
			_strike("STOP GUESSING")
	)


# ---------------------------------------------------------------- gate 6: the phone

# The Backrooms taught this one the hard way: its rotary phone is a read-to-die trap.
# Here the verb used to be IGNORE — walk past without answering. It no longer is:
# while the phone rings unresolved, it drains panic on its own (_tick_phone_pressure),
# so simply not touching it is no longer survivable if you dawdle. The verb is now
# DESTROY. A Hammer waits near the level entrance (see _spawn_gate6_hammer, called
# from _spawn_props); carry it here and interact() smashes the phone for good instead
# of answering it. Answering it (without the hammer, or by choice) still instantly
# forfeits the run — that temptation is unchanged.
func _spawn_gate6_phone() -> void:
	var phone := RotaryPhone.new()
	phone.name = "SwitchboardPhone"
	phone.open_note = false     # the forfeit IS the punishment; don't also bleed them
	phone.smashable = _has_hammer
	# A real recorded ring, at full level and audible across the room. The gate is
	# "silence the phone" — if the player cannot clearly hear it ringing, the rule on
	# the sign is about nothing and the whole gate reads as a bug.
	phone.ring_audio = "phone_ringing"
	phone.ring_volume_db = 0.0
	phone.ring_unit_size = 12.0
	phone.position = Vector3(-2.2, 0.75, 47.5)
	phone.answered.connect(func() -> void:
		_answered_phone = true
		_forfeit("YOU ANSWERED IT")
	)
	phone.smashed.connect(func() -> void:
		_pass_gate("phone")
		GameState.set_objective("LIGHTING FAULT — SECTOR DARK. FIND THE TRANSIT DOOR.")
	)
	add_child(phone)
	_phone = phone

	# A desk to stand it on, with no collider — a desk collider would intercept the
	# interaction ray before it reached the phone (the House key-stand lesson).
	var desk := CSGBox3D.new()
	desk.name = "SwitchboardDesk"
	desk.size = Vector3(1.4, 0.75, 0.7)
	desk.position = Vector3(-2.2, 0.375, 47.5)
	desk.use_collision = false
	desk.material = _mat("", 1.0, Color(0.26, 0.24, 0.2))
	add_child(desk)


# While the phone rings unsmashed and the player is nearby, it costs panic every
# frame — KONTUR's floor-wide DreadZone cancels decay exactly everywhere, so this
# pressure never drains on its own. Fatal within ~11s of dawdling; a quick hammer
# run is cheap by comparison. Called from _process().
func _tick_phone_pressure(delta: float) -> void:
	if not is_instance_valid(_phone) or _gates["phone"] or _forfeited:
		return
	var p := _player()
	if not p:
		return
	if p.global_position.distance_to(_phone.global_position) <= PHONE_PRESSURE_RANGE:
		p.add_panic(PHONE_PRESSURE_RATE * delta)


# The hammer that resolves Gate 6, planted near the level entrance so the player
# already has it well before the Switchboard. kontur_hammer.png is an isolated,
# transparent-background render, so it's built as an alpha QuadMesh billboard
# (matching _wall_panel's convention) rather than wrapped onto a 3D box.
func _spawn_gate6_hammer() -> void:
	var hammer := KeyItem.new()
	hammer.name = "Hammer"
	hammer.label_text = "Hammer collected"
	hammer.position = Vector3(-1.8, 0.9, -1.5)
	hammer.picked_up.connect(func() -> void:
		_has_hammer = true
		GameState.set_carried("hammer")
		if is_instance_valid(_phone):
			_phone.smashable = true
	)
	add_child(hammer)

	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	mesh.mesh = quad
	var tex_path := TEX + "kontur_hammer.png"
	var mat := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		mat.albedo_color = Color(0.35, 0.3, 0.22)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.set_surface_override_material(0, mat)
	hammer.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 0.4, 0.2)
	col.shape = shape
	hammer.add_child(col)


# ---------------------------------------------------------------- gate 7: the dark room

# The Flood's rule, restated: the light hides the way out. Three door panels on the
# far wall; the real one is the one you can only see with the flashlight OFF, and the
# two that glow under the beam are painted on. The Airlock/Escort/Terminus spine is
# built behind whichever x was drawn, so the answer moves every run.
func _spawn_gate7_dark() -> void:
	# ⚠️ NO DarkZone HERE, and it is not an oversight.
	#
	# This room is solved with the flashlight OFF. A DarkZone charges +3/s for exactly
	# that, and because player.gd's panic chain is if/elif the dark branch also
	# SUPPRESSES decay — on top of the level-wide DreadZone's additive +2/s that is
	# +5/s with no way down. Playtest 2026-07-21: 45% of the bar in four seconds of
	# looking, then death. The only surviving strategy was to flick the light off for
	# one second and back on, which is not the room anyone designed.
	#
	# This is the SAME conflict as the Backrooms Flood (backrooms_zone3.gd) and it has
	# the same fix. The room has no lamp, so it is pitch black regardless; the DarkZone
	# only ever added the tax that fought the puzzle.

	for x in DARK_CANDIDATES:
		var is_real: bool = absf(x - _dark_x) < 0.01
		var marker := MeshInstance3D.new()
		marker.name = "DarkSeam_%s" % ("real" if is_real else str(int(x)))
		var quad := QuadMesh.new()
		quad.size = Vector2(1.6, 2.4)
		marker.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.05, 0.06, 0.06)
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.62, 0.58) if is_real else Color(0.62, 0.55, 0.4)
		mat.emission_energy_multiplier = 1.1
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		marker.set_surface_override_material(0, mat)
		marker.position = Vector3(x, 1.25, 59.86)
		marker.rotation.y = PI
		add_child(marker)
		_dark_seams.append([marker, is_real])

		if is_real:
			continue
		# A decoy is solid wall. Walking into it costs a strike — retryable, because
		# the room's whole job is to make you try the wrong one first.
		var trap := CorridorEvent.new()
		var tcol := CollisionShape3D.new()
		var tshape := BoxShape3D.new()
		tshape.size = Vector3(1.8, 3.0, 1.2)
		tcol.shape = tshape
		trap.add_child(tcol)
		trap.position = Vector3(x, 1.5, 59.2)
		trap.fired.connect(func() -> void: _strike("THAT WAS PAINTED ON"))
		add_child(trap)

	# Passing is simply arriving in the Airlock, which only the real door reaches.
	_spawn_event(Vector3(_dark_x, 1.5, 61.0), Vector3(3.5, 3, 1.2), func() -> void:
		_pass_gate("dark")
	)


# ---------------------------------------------------------------- gate 8: the airlock

# Used to be a 9s stillness hold — playtest called it "boring, you just stand and
# wait". Replaced with a catch minigame: a marker sweeps the track; press E while
# it's inside the lit target zone, 3 times running. No hint anywhere else in the
# game explains this gate, so the visible track + target still has to teach itself.
func _spawn_gate8_airlock() -> void:
	var zone := CorridorEvent.new()
	zone.name = "AirlockZone"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.6, 3.0, 5.0)
	col.shape = shape
	zone.add_child(col)
	zone.position = Vector3(_dark_x, 1.5, 63.0)
	add_child(zone)
	zone.body_entered.connect(func(b: Node3D) -> void:
		if b.is_in_group("player"):
			_in_airlock = true
			# Playtest needed a strike before finding the timing by feel; the
			# redacted sign states the RULE but never explains the INPUT.
			ScreenText.caption(get_tree(), "PRESS E WHEN THE MARKER IS IN THE LIT ZONE", 4.0)
	)
	zone.body_exited.connect(func(b: Node3D) -> void:
		if b.is_in_group("player"):
			_in_airlock = false
			_airlock_t = 0.0
			_airlock_streak = 0
	)

	# The track — fixed background bar the marker sweeps across.
	var back := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(2.0, 0.16)
	back.mesh = bq
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.08, 0.09, 0.09)
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	back.set_surface_override_material(0, bmat)
	back.position = Vector3(_dark_x, 1.55, 65.8)
	back.rotation.y = PI
	add_child(back)
	_airlock_track = back

	# The target zone — fixed, centred on the track, lit up distinctly. Catching the
	# marker means pressing E while it's inside this band.
	_airlock_meter = MeshInstance3D.new()
	var mq := QuadMesh.new()
	mq.size = Vector2(2.0 * AIRLOCK_TARGET_WIDTH, 0.16)
	_airlock_meter.mesh = mq
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.4, 0.95, 0.7)
	mmat.emission_enabled = true
	mmat.emission = Color(0.4, 0.95, 0.7)
	mmat.emission_energy_multiplier = 1.6
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_airlock_meter.set_surface_override_material(0, mmat)
	# 6 cm clear of the seal behind it — at 1 cm the meter and its backing plate sat
	# inside the AirlockSeal box and fought it for depth.
	_airlock_meter.position = Vector3(_dark_x, 1.55, 65.79)
	_airlock_meter.rotation.y = PI
	add_child(_airlock_meter)

	# The marker — the moving catch target, one layer closer to the player so it
	# always renders on top of the track and the target band.
	_airlock_marker = MeshInstance3D.new()
	var kq := QuadMesh.new()
	kq.size = Vector2(0.12, 0.22)
	_airlock_marker.mesh = kq
	var kmat := StandardMaterial3D.new()
	kmat.albedo_color = Color(1.0, 0.95, 0.6)
	kmat.emission_enabled = true
	kmat.emission = Color(1.0, 0.95, 0.6)
	kmat.emission_energy_multiplier = 1.6
	kmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	kmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_airlock_marker.set_surface_override_material(0, kmat)
	_airlock_marker.position = Vector3(_dark_x, 1.55, 65.78)
	_airlock_marker.rotation.y = PI
	add_child(_airlock_marker)

	var seal := CSGBox3D.new()
	seal.name = "AirlockSeal"
	seal.size = Vector3(1.8, 3.0, 0.3)
	seal.position = Vector3(_dark_x, 1.5, 66.0)
	seal.use_collision = true
	seal.material = _mat(TEX + "kontur_facility_wall.png", 0.4, Color(0.45, 0.48, 0.45))
	add_child(seal)
	_airlock_seal = seal


func _tick_airlock(delta: float) -> void:
	if _gates["airlock"] or not _in_airlock:
		return
	var p := _player()
	if not p:
		return

	_airlock_t += delta
	var u := 0.5 + 0.5 * sin(TAU * _airlock_t / AIRLOCK_MARKER_PERIOD)
	if is_instance_valid(_airlock_marker):
		_airlock_marker.position.x = _dark_x + (u - 0.5) * 2.0

	if not Input.is_action_just_pressed("interact"):
		return

	var half_target := AIRLOCK_TARGET_WIDTH / 2.0
	if absf(u - 0.5) <= half_target:
		_airlock_streak += 1
		if _airlock_streak >= AIRLOCK_CATCHES_NEEDED:
			_pass_airlock()
	else:
		_airlock_streak = 0
		_strike("MISTIMED")


# The cycle completes. Extracted from _tick_airlock() so a headless test can drive the
# SHIPPING success path — Input.is_action_just_pressed() cannot be faked headless, so a
# test that re-implemented "free the seal" would have been asserting its own code.
func _pass_airlock() -> void:
	_pass_gate("airlock")
	if is_instance_valid(_airlock_seal):
		_airlock_seal.queue_free()
	# Playtest: the track/target/marker stayed on screen after the gate was already
	# solved, reading as unfinished business. Cycle's done — clear the whole widget,
	# not just the seal it unlocks.
	for widget in [_airlock_track, _airlock_meter, _airlock_marker]:
		if is_instance_valid(widget):
			widget.queue_free()
	_play_at("door_seal", Vector3(_dark_x, 1.5, 66), 0.0)
	GameState.set_objective("PROCEED TO TERMINUS. AN ESCORT HAS BEEN ASSIGNED.")


# ---------------------------------------------------------------- gate 4: the escort

func _spawn_gate4_escort() -> void:
	var gate := EscortGate.new()
	gate.name = "EscortGate"
	gate.forward = Vector3(0, 0, 1)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 3, 24)
	col.shape = shape
	gate.add_child(col)
	gate.position = Vector3(_dark_x, 1.5, 79.0)
	# The corridor runs z 66 -> 92; the gate paces its own temptation along that.
	gate.span_start_z = 67.0
	gate.span_end_z = 91.0
	gate.broken.connect(_on_escort_broken)
	gate.tempt.connect(_on_escort_tempt)
	gate.warned.connect(_on_escort_warned)
	add_child(gate)

	# The lights behind you die as you commit to the corridor.
	_spawn_event(Vector3(_dark_x, 1.5, 67.5), Vector3(3, 3, 1.5), _ev_escort_begins)

	# Reaching the Terminus with the escort unbroken is what passes gate 4.
	_spawn_event(Vector3(_dark_x, 1.5, 93.0), Vector3(5, 3, 1.2), func() -> void:
		if not _gates["escort"] and not _forfeited:
			_pass_gate("escort")
	)


func _ev_escort_begins() -> void:
	for entry in _lights:
		var lamp: OmniLight3D = entry[0]
		if lamp.position.z < 68.0:
			var t := create_tween()
			t.tween_property(lamp, "light_energy", 0.0, 0.35)
			entry[1] = 0.0
	_play_at("door_seal", Vector3(_dark_x, 1.5, 66), -2.0)


# The escort's three-stage lie. Stages 0 and 1 are diegetic — something is back there
# and it is getting closer — so by the time the screen itself tells you to turn round,
# the urge is already yours. That ordering is deliberate: a UI that lies to you out of
# nowhere reads as cheap, but a UI that lies to you about something you can already
# HEAR reads as the level doing what this level does.
func _on_escort_tempt(stage: int) -> void:
	match stage:
		0:
			_play_behind("footstep", -2.0)
		1:
			_play_behind("whispers", -4.0)
		2:
			ScreenText.scrawl(get_tree(), "LOOK BEHIND YOU", 3.2, 62)


func _play_behind(base_name: String, volume_db: float) -> void:
	var p := _player()
	if not p:
		return
	_play_at(base_name, p.global_position - p.global_transform.basis.z * -1.8 + Vector3(0, 1.2, 0),
		volume_db)


# The free first look, inside EscortGate.ARM_AT. It costs nothing — it exists so the
# rule is learned by nearly breaking it, rather than by losing a 90-second run to a
# reflex three seconds after entering a corridor.
func _on_escort_warned() -> void:
	_notice("IT IS BEHIND YOU. DO NOT LOOK AGAIN.", Color(1.0, 0.75, 0.3))
	_play_at("door_seal", Vector3(_dark_x, 1.5, 67.0), -6.0)
	var dbg := get_node_or_null("/root/DebugLog")
	if dbg and dbg.has_method("note"):
		dbg.note("ESCORT WARNING — free look inside the grace stretch")


func _on_escort_broken() -> void:
	# Looking back cannot be taken back — so it voids the run rather than costing a
	# strike. This is the sharpest edge in the level: we tempt, then we punish.
	_forfeit("YOU LOOKED")


# ---------------------------------------------------------------- creature

# ⭐ THE PERËKOZHNIK CHANGES SHAPE (2026-08-18). ⚠️ ITS RULES DID NOT.
#
# Its name means *shapechanger*; for its whole life it was a static billboard in a corner
# of the Passage, and a player who never swept a torch across that corner never met the
# level's only creature. It now stands somewhere on the spine WEARING SOMETHING the
# player has already learned to read — and the tell is a COUNT, which is the one thing
# this level's design rewards anyway:
#
#   "kitchen"      a FOURTH bottle on a shelf with three slots, and it wears a duplicate
#                  of a label already on that shelf. Two BLEACHes.
#   "switchboard"  a SECOND phone on the desk. Only one of them is ringing, and the
#                  ringing one is the gate.
#
# ⚠️ Neither disguise can cost a gate. The shell is a `MimicShell`, not a `BottleItem` and
# not a `RotaryPhone` — E on it consumes no bottle, spends no strike, answers nothing and
# smashes nothing. See the four fairness rules at the top of `creature_shapechanger.gd`.
#
# ⚠️ Which site is drawn is RESTORED, never re-rolled, on a back-door return (K-T6's rule
# applied to the third randomisation in this level).
const MIMIC_SITES := ["kitchen", "switchboard"]

func _spawn_creature() -> void:
	if not _randomisation_restored:
		_mimic_site = MIMIC_SITES[randi() % MIMIC_SITES.size()]
	var c := CreatureShapechanger.new()
	c.name = "Shapechanger"

	var shell := MimicShell.new()
	shell.name = "MimicShell"
	if _mimic_site == "kitchen":
		# ⚠️ z = 21.9, deliberately off the three-slot rhythm (22.3 / 23.5 / 24.7). The
		# spacing is the second tell, and it costs nothing to look at.
		c.position = Vector3(3.4, 0.99, 21.9)
		c.rotation.y = -PI / 2.0
		BottleItem.build_visual(shell, BOTTLE_PROFILES["bleach"],
			TEX + "label_bleach_paper.png")
		_mimic_mark = Vector3(-2.6, 0.0, 22.4)
	else:
		# The desk runs x -2.9 .. -1.5; the real phone is at -2.2. Two phones, one desk.
		c.position = Vector3(-1.75, 0.75, 47.5)
		RotaryPhone.build_visual(shell)
		_mimic_mark = Vector3(2.4, 0.0, 49.6)
	# ⚠️ POSITION BEFORE add_child. `ScaryObject` is a plain `Node` and breaks the Node3D
	# transform chain, so `creature_shapechanger.gd:_build()` seeds the BODY's world
	# transform from this node's — at `_ready()` time. Adding first and moving after left
	# the gaze collider at the world origin (Issue 10).
	add_child(c)

	# A generous interact volume, the same reason bottle_item.gd and light_switch.gd
	# oversize theirs (Issue 2) — and layer 2 / mask 0, note.gd's convention, so a
	# disguise standing on a shelf or a desk can never be walked into.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.34, 0.36, 0.34)
	col.shape = shape
	col.position = Vector3(0, 0.16, 0)
	shell.add_child(col)
	shell.collision_layer = 2
	shell.collision_mask = 0

	c.set_disguise(shell)
	c.revealed.connect(_on_mimic_revealed)

	# ⚠️ VALIDATED BY RAYS, LATER. CSG colliders are not registered during `_ready()`
	# (Issue 52), so a ray fired here hits nothing and every candidate would be approved
	# for the wrong reason — a validation that cannot fail is worse than none. 0.6 s is
	# 25 m short of the nearest disguise at a walk.
	get_tree().create_timer(0.6).timeout.connect(_validate_mimic_mark)


# Is this a place a 1.78 m figure can stand, in sight of where the disguise was? Rays
# only: a head-height ray down the column, a 16-ray horizontal fan at the figure's own
# half-width (8 would fly through a doorway and report clear), and the line of sight from
# the disguise, which is the member of the set that catches "inside a wall" — CSG
# backfaces do not collide (Issue 59).
func _validate_mimic_mark() -> void:
	var c := get_node_or_null("Shapechanger") as CreatureShapechanger
	if c == null:
		return
	c.reveal_mark = _validate_reveal_mark(_mimic_mark, c.global_position)


func _validate_reveal_mark(mark: Vector3, from: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var eye := from + Vector3(0, 0.4, 0)
	var chest := mark + Vector3(0, 1.0, 0)

	var down := PhysicsRayQueryParameters3D.create(mark + Vector3(0, 2.6, 0),
		mark + Vector3(0, 0.05, 0))
	if not space.intersect_ray(down).is_empty():
		push_warning("KONTUR: mimic reveal mark has something overhead; no figure")
		return Vector3.ZERO
	var floor_q := PhysicsRayQueryParameters3D.create(mark + Vector3(0, 1.0, 0),
		mark - Vector3(0, 1.0, 0))
	if space.intersect_ray(floor_q).is_empty():
		push_warning("KONTUR: mimic reveal mark has no floor; no figure")
		return Vector3.ZERO
	for i in range(16):
		var a: float = TAU * float(i) / 16.0
		var dir := Vector3(cos(a), 0, sin(a))
		var fan := PhysicsRayQueryParameters3D.create(chest, chest + dir * 0.45)
		if not space.intersect_ray(fan).is_empty():
			push_warning("KONTUR: mimic reveal mark is not clear; no figure")
			return Vector3.ZERO
	var los := PhysicsRayQueryParameters3D.create(eye, chest)
	if not space.intersect_ray(los).is_empty():
		push_warning("KONTUR: mimic reveal mark is not in sight of the disguise; no figure")
		return Vector3.ZERO
	if mark.distance_to(from) < CreatureShapechanger.REVEAL_MIN_DIST:
		push_warning("KONTUR: mimic reveal mark is inside KILL_DIST; no figure")
		return Vector3.ZERO
	return mark


# ⚠️ ZERO PANIC. The reveal itself adds nothing to the bar — no `add_panic`, no
# `flash_scare`, no strike. What it costs is that from now on there is something in the
# room that charges 16/s to look at, and the player chose to find that out.
func _on_mimic_revealed() -> void:
	var c := get_node_or_null("Shapechanger") as CreatureShapechanger
	if c:
		_play_at("perekozhnik_shed", c.global_position + Vector3(0, 1.0, 0), MIMIC_SHED_DB)
	var p := _player()
	if p:
		p.jolt_camera(0.08, 0.4)
	var dbg := get_node_or_null("/root/DebugLog")
	if dbg and dbg.has_method("note"):
		dbg.note("PEREKOZHNIK REVEALED — disguise site '%s'" % _mimic_site)


# ⭐ OBJECT 12, CONTAINED (2026-08-18). See `containment_cell.gd` for the contract; the
# short version is that it has NO RULES — zero panic, no collider on the occupant, no kill
# radius, no trigger volume, nothing to interact with. It turns its head. That is all.
#
# ⚠️ IN THE PASSAGE, WHICH IS THE THINNEST ROOM ON THE SPINE. Gate 1 is at z=10 and gate 2
# at z=27, so the seven metres between them were the longest stretch of the level with
# nothing in it at all — and it is now the stretch where the player meets the thing the
# facility is named after. Deliberately NOT in a gate room: it must be something you come
# upon, never something a puzzle points at.
#
# ⚠️ The Perëkozhnik used to stand in this room's west corner and now wears a disguise
# somewhere else on the spine (see _spawn_creature), so the Passage is not gaining an
# occupant on top of one it already had — it is exchanging a billboard nobody reliably saw
# for something standing on the walking line.
const CELL_POS := Vector3(2.75, 0.0, 16.9)

func _spawn_containment_cell() -> void:
	var cell := ContainmentCell.new()
	cell.name = "ContainmentCell"
	cell.position = CELL_POS
	# Faces -z, i.e. the door and the placard look back down the spine at someone walking
	# in from the antechambers; the three glazed faces are the ones they pass.
	add_child(cell)


# Hold still and it fades; sprint or back away and it rushes -> the real screamer +
# restart. Position-agnostic (appear() sites itself ahead of wherever the player is
# looking), so it works anywhere along the spine without a scripted trigger volume.
func _spawn_apparition_director() -> void:
	if not RANDOM_APPARITIONS:
		return
	var d := ApparitionDirector.new()
	d.name = "ApparitionDirector"
	add_child(d)


# ---------------------------------------------------------------- signs

func _spawn_signs() -> void:
	# Each gate's rule, with the operative word censored. A player who found the
	# earlier-level hints reads straight through these; one who didn't gets the
	# shape of the question but not the answer.
	#
	# ⚠️ REAL PRINTED DOCUMENTS SINCE 2026-08-18. Each is a generated Soviet notice
	# (`tools/make_kontur_signs.py`) with the head band, the form number, the rule set in
	# type and the redaction STRUCK INTO THE IMAGE. They used to be a `Label3D` of engine
	# text floating in front of a blank plate with a separate black quad for the bar —
	# the level's only documentation, rendered as UI.
	_make_sign(Vector3(0, 1.7, 9.85), PI, "gate1_doors")
	_make_sign(_builder.wall_point("Kitchen", Vector2(-1, 0), 1.7, 0.16), PI / 2.0,
		"gate2_shelf")
	_make_sign(_builder.wall_point("Records", Vector2(-1, 0), 1.7, 0.16), PI / 2.0,
		"gate5_roster")
	# ⚠️ Offset 3.3 m SOUTH of the Archive's wall centre. The recovery racks run z 37..42
	# a metre and a half in front of that wall, so a sign on the centre point is read
	# through open shelving — and this is the sign for the gate the player is standing in
	# the room to pass.
	_make_sign(_builder.wall_point("Archive", Vector2(1, 0), 1.7, 0.16)
		+ Vector3(0, 0, -3.3), -PI / 2.0, "gate3_offering")
	_make_sign(_builder.wall_point("Switchboard", Vector2(1, 0), 1.7, 0.16), -PI / 2.0,
		"gate6_phone")
	_make_sign(_builder.wall_point("Blackout", Vector2(-1, 0), 1.7, 0.16), PI / 2.0,
		"gate7_dark")
	# Gate 8's sign is the one that must nearly give the game away: it inverts a rule
	# the Backrooms spent a whole level teaching, and no earlier level hints at it.
	_make_sign(_builder.wall_point("Airlock", Vector2(1, 0), 1.7, 0.16), -PI / 2.0,
		"gate8_airlock")
	# ⚠️ The escort's rule hangs in the AIRLOCK, not in the corridor it governs. It used
	# to sit at the corridor's midpoint — 13 m past the point where breaking it voids
	# the run, so a playtester forfeited before ever reading it. Here the player is
	# already standing still for gate 8's cycle, with nothing to do but read.
	_make_sign(_builder.wall_point("Airlock", Vector2(-1, 0), 1.7, 0.16), PI / 2.0,
		"gate4_escort")


# One printed notice, mounted flat on a wall.
#
# ⚠️ The quad is SIZED FROM THE ARTWORK (1500x1000 -> 1.5 x 1.0 m), never chosen to suit
# the wall — that is the mistake this level's poster and chute panel were both making
# until this pass (K-T3), and `check_art_aspect.gd` sweeps every scene for it.
#
# ⚠️ Emission 0.40, down from 0.55. These are the only in-level help there is and they
# have to stay readable in rooms this dark, but the card is now a mid-tone printed sheet
# rather than a near-blank plate, so it needs less lift — and emission is most of a
# surface's colour here (Issue 21). `check_kontur_signs.gd` measures the ink-vs-card
# contrast and the on-screen size from the walking line rather than trusting either.
# ⚠️ 1.2 m, not 1.0. `check_kontur_signs.gd` measures the rule's ink on the imported
# texture and converts it to screen pixels at each sign's own reading distance; at 1.0 m
# with the old layout six of the eight came out at 5-9 px of cap height. The plate grew
# and the artwork's hierarchy inverted (the RULE is the hero now, not the title). 1.2 was
# still 13.1 px on the gate-1 sign — the one read from the far side of a 6 m room — so
# the plate is 1.4 m tall and 2.1 m wide, which is what an institutional wall notice
# actually is. Worst sign on the shipped build: 15.3 px.
const SIGN_H := 1.4
const SIGN_EMISSION := 0.40

func _make_sign(pos: Vector3, y_rot: float, key: String) -> void:
	var tex_path := TEX + "kontur_sign_%s.png" % key
	var root := Node3D.new()
	root.name = "Sign_" + key
	root.position = pos
	root.rotation.y = y_rot
	add_child(root)

	var plate := MeshInstance3D.new()
	plate.name = "SignPlate"
	var quad := QuadMesh.new()
	var pmat := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		var ptex: Texture2D = load(tex_path)
		quad.size = Vector2(SIGN_H * float(ptex.get_width()) / float(ptex.get_height()),
			SIGN_H)
		pmat.albedo_texture = ptex
		pmat.emission_enabled = true
		pmat.emission_texture = ptex
		# ⚠️ MULTIPLY, not Godot's default ADD. An emission COLOUR beside an emission
		# TEXTURE lays a flat wash over the whole surface instead of modulating the
		# artwork — it turned a near-black brass plate into a pale cream slab in the
		# Corridor (Issue 81, cross-level X30).
		pmat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		pmat.emission_energy_multiplier = SIGN_EMISSION
	else:
		quad.size = Vector2(1.5, SIGN_H)
		pmat.albedo_color = Color(0.62, 0.65, 0.6)
	plate.mesh = quad
	pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plate.set_surface_override_material(0, pmat)
	root.add_child(plate)


# A plain readable note (not a redacted sign) — same pattern as level_1.gd/level_2.gd's
# _make_note, reusing note.gd so it looks identical to a note anywhere else in the game.
func _make_note(pos: Vector3, y_rot: float, text: String) -> void:
	var note := StaticBody3D.new()
	note.set_script(_NOTE_SCRIPT)
	note.note_text = text
	note.position = pos
	note.rotation.y = y_rot
	add_child(note)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.32, 0.42, 0.01)
	mesh.mesh = bm
	mesh.set_surface_override_material(0, _NOTE_SCRIPT.paper_material(false))
	note.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 0.5, 0.12)
	col.shape = shape
	note.add_child(col)


# ---------------------------------------------------------------- props

func _spawn_props() -> void:
	# The mailbox (debug capture #9: "make these objects 3D") is now a real
	# interactable holding a hint; the chute stays the flat decal it always was.
	# ⚠️ inset 0.22, not 0.16 — unlike a paper-thin QuadMesh decal, this prop has a
	# 0.15 m casing centred on the wall point, so its back half needs the deeper
	# "something hangs behind it" clearance (CLAUDE.md) or it clips the wall.
	_spawn_mailbox(_builder.wall_point("Landing", Vector2(-1, 0), 1.5, 0.22), PI / 2.0)
	_wall_panel(_builder.wall_point("Landing", Vector2(1, 0), 1.3, 0.16), -PI / 2.0,
		1.10, TEX + "kontur_chute_hatch.png")
	# The safety poster, on the Archive's west wall.
	# ⚠️ inset 0.16, not 0.08: wall_point measures from the room's NOMINAL boundary and
	# the wall is 0.2 m thick centred on it, so anything under ~0.11 is buried inside
	# the wall and invisible in game (ISSUES_SOLUTIONS Issue 11).
	_wall_panel(_builder.wall_point("Archive", Vector2(-1, 0), 1.7, 0.16), PI / 2.0,
		1.40, TEX + "kontur_poster_sheet.png")

	_spawn_briefing_notice()
	_spawn_gate6_hammer()
	_spawn_recovery_archive()
	_spawn_stencils()
	_spawn_floor_markings()


# ---------------------------------------------------------------- the one unredacted notice
#
# ⭐ KONTUR STATES ITS OWN RULE, ONCE, AS A PRINCIPLE (2026-08-18, the user's call).
#
# Six of this level's eight gates are answerable only from a hint planted in an EARLIER
# level, and nothing anywhere in the game said so. The only place the principle was ever
# stated is the banishment scrawl — which fires AFTER a wrong door, i.e. only to the
# players who have already lost a level to it.
#
# Nothing here gets easier. This notice contains no answer to anything, and it is asserted
# to contain none (`check_kontur_signs.gd` scans its text for every gate's operative word,
# every earlier level's name and every room name in this one). What changes is a stuck
# player's READING: "I am missing something in this room" becomes "I should have read
# more", and those two produce completely different behaviour in a level with no decay.
#
# ⚠️ A PRINCIPLE, NEVER A PLACE. `kitchen_drawer.gd` states Gate 1's rule the same way and
# for the same reason (the colours are randomised per run, so a position would be a lie).
# "Elsewhere" is the negation of a place; "briefed" is a claim about WHEN the information
# was issued, not about where it now is.
#
# ⚠️ IT IS BOTH A WALL NOTICE AND A NOTE, and both halves are load-bearing. The ART states
# the principle in three words legible from the player's very first frame 7.1 m away — the
# target reader is the one who RUSHED, and a statement they have to walk up to and press E
# on is a statement they will skip. The `note.gd` body carries the full memo and archives
# it to the TAB journal, because the principle is worth re-reading two gates later when it
# has become relevant. `corridor.gd:_spawn_nightmare_plate()` is the same pairing.
#
# ⚠️ NOT A NINTH GATE SIGN. It carries NO censor bar, it is a different form series and a
# different shape, and it is not named `Sign_*` — `check_kontur_signs.gd` still asserts
# there are exactly EIGHT redacted signs, so this cannot quietly join them.
#
# ⚠️ ZERO PANIC, no rule, no gate, no trigger volume. It is a sentence on a wall.
#
# Geometry: the Landing's north wall, east of the doorway (which occupies x -0.9..0.9;
# `wall_point()` returns the wall CENTRE, which is exactly where a doorway sits, so the
# lateral offset is mandatory rather than stylistic). 1.70 m wide centred at x = 1.90
# leaves 0.15 m to the doorway edge and 0.15 m to the east wall's inner face.
const NOTICE_X := 1.90
const NOTICE_W := 1.70
const NOTICE_Y := 1.55
# The backing plate's own thickness, and how far the art stands proud of it.
const NOTICE_BACK_T := 0.03
const NOTICE_ART_PROUD := 0.02

const NOTICE_TEXT := """K.O.N.T.U.R. — FORM 1-А
NOTICE TO TRANSFERRED SUBJECTS

YOU WERE BRIEFED ELSEWHERE.

No copy of that briefing is held on these premises. This facility posts its procedures \
and nothing more. What a procedure is FOR, and what it costs to get one wrong, was \
issued to you before you were admitted, and is not reproduced inside the perimeter.

Staff will not repeat it. Staff are not permitted to repeat it.

A subject who cannot satisfy a posted procedure is to be filed as UNPREPARED. The file \
does not distinguish between a subject who was never told and a subject who did not \
attend.

СЕКТОР 1 · ЛЕСТНИЦА · ЭКЗ. 1 · НЕ ВЫНОСИТЬ"""


func _spawn_briefing_notice() -> void:
	var art_path := TEX + "kontur_notice_briefing.png"
	# Height from the ARTWORK's own aspect (1500x1300), never chosen to suit the wall.
	var art_h := NOTICE_W * 1300.0 / 1500.0
	var art_tex: Texture2D = null
	if ResourceLoader.exists(art_path):
		art_tex = load(art_path)
		art_h = NOTICE_W * float(art_tex.get_height()) / float(art_tex.get_width())

	var body := StaticBody3D.new()
	body.name = "NoticeBriefing"
	body.set_script(_NOTE_SCRIPT)
	body.note_text = NOTICE_TEXT
	body.position = _builder.wall_point("Landing", Vector2(0, 1), NOTICE_Y, 0.16) \
		+ Vector3(NOTICE_X, 0.0, 0.0)
	# Local +Z becomes world -Z: the plate faces back down the room at the player, who
	# spawns at z = -3 looking this way.
	body.rotation.y = PI
	add_child(body)

	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color(0.075, 0.068, 0.055)
	back_mat.metallic = 0.4
	back_mat.roughness = 0.6

	var back := MeshInstance3D.new()
	back.name = "NoticeBack"
	var bm := BoxMesh.new()
	bm.size = Vector3(NOTICE_W + 0.06, art_h + 0.06, NOTICE_BACK_T)
	back.mesh = bm
	back.material_override = back_mat
	back.position = Vector3(0, 0, NOTICE_BACK_T / 2.0)
	body.add_child(back)

	# THE ART, on a QuadMesh — a textured BoxMesh face renders a magnified crop of its own
	# artwork (Issue 24). ⚠️ Emission lives on the ART and not on the body (the Issue 27/33
	# split), and it is MULTIPLY rather than Godot's default ADD, which lays a flat wash
	# over the whole surface instead of modulating the print (Issue 81 / X30). Matched to
	# the eight signs' `SIGN_EMISSION` so the level's documents read as one stationery set.
	if art_tex != null:
		var art := MeshInstance3D.new()
		art.name = "NoticeArt"
		var quad := QuadMesh.new()
		quad.size = Vector2(NOTICE_W, art_h)
		art.mesh = quad
		var amat := StandardMaterial3D.new()
		amat.albedo_texture = art_tex
		amat.emission_enabled = true
		amat.emission_texture = art_tex
		amat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		amat.emission_energy_multiplier = SIGN_EMISSION
		amat.cull_mode = BaseMaterial3D.CULL_DISABLED
		art.set_surface_override_material(0, amat)
		art.position = Vector3(0, 0, NOTICE_BACK_T + NOTICE_ART_PROUD)
		body.add_child(art)

	# ⚠️ Layer 2 / mask 0 is `note.gd`'s own `_ready()`, so the collider is ray-hittable and
	# movement-invisible: a 1.7 m board standing in the spawn room can never block a lane.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(NOTICE_W, art_h, 0.16)
	col.shape = shape
	col.position = Vector3(0, 0, 0.06)
	body.add_child(col)


# ---------------------------------------------------------------- Cyrillic signage
#
# ⭐ THE FACILITY IS LABELLED (2026-08-18). Every room on the spine now carries a
# stencilled Russian designation high on a wall, and the three thresholds where the
# facility changes its mind about you carry painted floor hazard bands. It is the
# cheapest thing in this pass and it is what makes the difference between "a sealed
# Soviet facility" and "grey rooms with props in them".
#
# ⚠️ PAINT, NOT SIGNS. The stencils are `Label3D`s tinted dark and set flat against the
# wall — no mesh, no plate, no emission. They cannot be confused with the eight redacted
# NOTICES, which are the level's only actual help, and they are invisible to
# `check_art_aspect.gd` because there is no textured quad to distort.
#
# ⚠️ Room designations only. Not one of them says anything about a gate: a stencil that
# hinted would put an answer inside a level whose whole premise is that the answers are
# somewhere else.
const STENCILS := [
	["Landing", Vector2(1, 0), -PI / 2.0, "Л-1\nЛЕСТНИЦА"],
	["Vestibule", Vector2(-1, 0), PI / 2.0, "В-2\nВЕСТИБЮЛЬ"],
	["Passage", Vector2(-1, 0), PI / 2.0, "П-3\nПЕРЕХОД"],
	["Kitchen", Vector2(1, 0), -PI / 2.0, "К-4\nБЫТОВАЯ"],
	["Records", Vector2(1, 0), -PI / 2.0, "У-5\nУЧЁТ"],
	["Archive", Vector2(-1, 0), PI / 2.0, "А-6\nАРХИВ"],
	["Switchboard", Vector2(-1, 0), PI / 2.0, "С-7\nКОММУТАТОР"],
	["Blackout", Vector2(1, 0), -PI / 2.0, "Э-8\nЭЛЕКТРО"],
]

const STENCIL_Y := 2.45
const STENCIL_TINT := Color(0.30, 0.28, 0.23)

func _spawn_stencils() -> void:
	for row in STENCILS:
		var lbl := Label3D.new()
		lbl.name = "Stencil_%s" % row[0]
		lbl.text = row[3]
		lbl.font_size = 64
		lbl.pixel_size = 0.0042
		lbl.modulate = STENCIL_TINT
		lbl.outline_size = 0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Same 0.16 inset as every other wall prop here: wall_point() measures from the
		# room's NOMINAL boundary and the wall face is T/2 in from that (Issue 11).
		lbl.position = _builder.wall_point(row[0], row[1], STENCIL_Y, 0.16)
		lbl.rotation.y = row[2]
		add_child(lbl)

	# The tail spine moves per run, so its rooms are stencilled from _dark_x.
	for row2 in [["Ш-9\nШЛЮЗ", Vector3(_dark_x - 1.84, STENCIL_Y, 63.0), PI / 2.0],
			["Т-11\nТЕРМИНАЛ", Vector3(_dark_x - 2.84, STENCIL_Y, 95.0), PI / 2.0]]:
		var l2 := Label3D.new()
		l2.name = "Stencil_%s" % String(row2[0]).split("\n")[0]
		l2.text = row2[0]
		l2.font_size = 64
		l2.pixel_size = 0.0042
		l2.modulate = STENCIL_TINT
		l2.outline_size = 0
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l2.position = row2[1]
		l2.rotation.y = row2[2]
		add_child(l2)


# Painted hazard bands across the floor at the three thresholds where the protocol
# changes: the decontamination line, the personnel gate and the airlock.
#
# ⚠️ y = 0.03, which is `corridor.gd`'s own `FLOOR_DECAL_Y`. A decal at 0.02 sits exactly
# on `check_wall_overlap.gd`'s 2 cm minimum and `AABB.has_point()` includes its boundary —
# that is how every flat decal in the Corridor got reported the first time that guard was
# pointed at it. ⚠️ And they are unlit dark ochre, never emissive: paint on a floor is the
# darkest thing in the room, not the brightest (anti-pattern §5.2(8)).
const FLOOR_MARK_Y := 0.03
const FLOOR_MARKS := [
	[0.0, 26.4, 2.6],     # decontamination line, in front of the fungal barrier
	[0.0, 34.4, 2.6],     # personnel gate
]

func _spawn_floor_markings() -> void:
	var marks: Array = FLOOR_MARKS.duplicate(true)
	marks.append([_dark_x, 65.3, 2.4])     # the airlock threshold, on the drawn spine
	var ochre := StandardMaterial3D.new()
	ochre.albedo_color = Color(0.30, 0.25, 0.07)
	ochre.roughness = 0.95
	var slate := StandardMaterial3D.new()
	slate.albedo_color = Color(0.07, 0.07, 0.065)
	slate.roughness = 0.95
	for m in marks:
		var n := int(float(m[2]) / 0.30)
		for i in range(n):
			var q := MeshInstance3D.new()
			q.name = "FloorHazard"
			var qm := QuadMesh.new()
			qm.size = Vector2(0.22, 0.55)
			q.mesh = qm
			q.material_override = ochre if i % 2 == 0 else slate
			q.position = Vector3(float(m[0]) - float(m[2]) / 2.0 + 0.15 + i * 0.30,
				FLOOR_MARK_Y, float(m[1]))
			q.rotation = Vector3(-PI / 2.0, 0, deg_to_rad(24.0))
			add_child(q)


# The mailbox: a shallow real object (not a flat decal), opening on a hint note for
# Gate 7 (the dark room) — a second, earlier hint alongside the Backrooms Flood one.
# Art goes on a QuadMesh face, never the depth box (Issue 24) — same pattern as
# choice_door.gd and the roster lock above.
const MAILBOX_HINT := "MAILBOX — SLOT 12\n\nI stopped switching them on. I am too afraid of what the light finds. If you want the way out, you will have to feel for it in the dark."

# ⚠️ Rebuilt 2026-07-25 (playtest capture #4: "need to make these objects 3d, and
# probably only one of them should open and keep the note").
#
# The old version was ONE BoxMesh wearing kontur_panel_mailboxes.png — a photograph
# of seven cabinets WITH THE WALLPAPER BAKED INTO ITS BACKGROUND (TEXTURES.md). That
# baked-in wallpaper is exactly why it read as a poster taped to the wall rather than
# as an object: the prop's own "background" was a picture of the surface behind it.
# It also set TRANSPARENCY_ALPHA on an image with no alpha channel (inert, and it
# bought a transparent-pass sort for nothing) and stretched a 1.333 source onto a
# 1.143 quad.
#
# Now built the way intro_room.gd:_build_wheelchair() was rebuilt after the same
# complaint — real multi-part geometry with FLAT-TINTED materials and no texture at
# all. rotary_phone.gd proves the same point at small scale: silhouette carries a
# prop here, art does not. Divider/shelf bars come from level_1.gd:_add_tray_lip()'s
# trick of driving thin bars off a data array, and the hinge is hiding_spot.gd's.
#
# Twelve numbered slots, and only SLOT 12 opens — the note's own header already said
# "MAILBOX — SLOT 12", so every slot is numbered and the hint names its own address.
const MAILBOX_COLS := 3
const MAILBOX_ROWS := 4
const MAILBOX_FRAME := 0.04    # divider/shelf bar thickness
const MAILBOX_DEPTH := 0.20    # back half (0.10) must stay under wall_point's 0.12 clearance

func _spawn_mailbox(pos: Vector3, y_rot: float) -> void:
	var box := KonturMailbox.new()
	box.name = "Mailbox"
	box.hint_text = MAILBOX_HINT
	box.position = pos
	box.rotation.y = y_rot
	add_child(box)

	var w := 1.6
	var h := 1.4
	var d := MAILBOX_DEPTH

	var steel := _mb_mat(Color(0.20, 0.22, 0.20), 0.35, 0.7)
	var trim := _mb_mat(Color(0.09, 0.10, 0.09), 0.2, 0.85)
	var door_mat := _mb_mat(Color(0.17, 0.25, 0.21), 0.3, 0.75)
	var slot12_mat := _mb_mat(Color(0.30, 0.20, 0.14), 0.3, 0.7)   # repainted once, badly
	var brass := _mb_mat(Color(0.36, 0.30, 0.16), 0.6, 0.5)
	var card := _mb_mat(Color(0.60, 0.58, 0.52), 0.0, 0.95)

	# Carcass, plus a plinth and a top overhang that stand proud of it. Without the
	# overhangs a wall-mounted box still reads as flush panelling from an angle —
	# slam_door.gd:_build_frame() learned the same thing ("a bare panel floats").
	_mb_box(box, "Carcass", Vector3(w, h, d), Vector3(0, 0, 0), steel)
	_mb_box(box, "Top", Vector3(w + 0.08, 0.05, d + 0.05), Vector3(0, h / 2.0 + 0.025, 0.02), trim)
	_mb_box(box, "Plinth", Vector3(w + 0.08, 0.06, d + 0.05), Vector3(0, -h / 2.0 - 0.03, 0.02), trim)

	var cell_w: float = (w - (MAILBOX_COLS + 1) * MAILBOX_FRAME) / float(MAILBOX_COLS)
	var cell_h: float = (h - (MAILBOX_ROWS + 1) * MAILBOX_FRAME) / float(MAILBOX_ROWS)
	var face_z: float = d / 2.0

	# Vertical dividers and horizontal shelves — the grid the doors sit inside.
	for c in range(MAILBOX_COLS + 1):
		var x: float = -w / 2.0 + MAILBOX_FRAME / 2.0 + c * (cell_w + MAILBOX_FRAME)
		_mb_box(box, "Divider", Vector3(MAILBOX_FRAME, h, 0.03), Vector3(x, 0, face_z), trim)
	for r in range(MAILBOX_ROWS + 1):
		var y: float = h / 2.0 - MAILBOX_FRAME / 2.0 - r * (cell_h + MAILBOX_FRAME)
		_mb_box(box, "Shelf", Vector3(w, MAILBOX_FRAME, 0.03), Vector3(0, y, face_z), trim)

	var n := 0
	for r in range(MAILBOX_ROWS):
		for c in range(MAILBOX_COLS):
			n += 1
			var cx: float = -w / 2.0 + MAILBOX_FRAME + cell_w / 2.0 + c * (cell_w + MAILBOX_FRAME)
			var cy: float = h / 2.0 - MAILBOX_FRAME - cell_h / 2.0 - r * (cell_h + MAILBOX_FRAME)
			var is_12 := n == 12
			_mb_slot(box, n, Vector3(cx, cy, face_z), cell_w, cell_h,
				slot12_mat if is_12 else door_mat, brass, card, is_12)

	# Padded so the interaction ray is forgiving on a shallow prop (Issue 2), the
	# same reason bottle_item.gd and light_switch.gd oversize theirs.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(w + 0.06, h + 0.14, d + 0.12)
	col.shape = shape
	box.add_child(col)


# ---------------------------------------------------------------- the recovery archive
#
# ⭐ THE ARCHIVE HAD NOTHING IN IT (2026-08-18).
#
# The level's own objective line on entering this room is "RECOVERY ARCHIVE — DO NOT
# DISTURB THE INVENTORY", the sign on its east wall says "ITEMS RECOVERED FROM AN OBJECT
# ARE: [REDACTED]", and gate 3's whole test is walking past a recovered item. All of that
# was staged in an empty 9 x 9 m room containing one black box on the floor. Photographed
# in `screenshot_kontur.gd`'s 09_gate3_offering before this pass.
#
# So: two aisle racks and SIX NUMBERED LOTS, five of them holding something the player has
# already walked past in an earlier level, and the sixth EMPTY with their own subject
# number on the card. It is the level's thesis — *the answers are not inside it* — made
# physical: KONTUR has been collecting from every floor the player has crossed.
#
# ⚠️ ZERO RULES. No `interact()` on any lot, so nothing shows a prompt and nothing can be
# taken; no `ScaryObject`, so looking costs nothing; no panic, no fail state, no trigger
# volume, no sound. The only interactable added here is the inventory ledger — an ordinary
# `note.gd` page, which is also what finally gives `check_note_mounting.gd` a population in
# this level (K-T5).
#
# ⚠️ FREE-STANDING, not against the walls. The obvious placement is wall racks, and the
# Archive's two long walls already carry the poster and the redacted RECOVERY LOG sign at
# their centres — a rack there would simply hide both. Aisle racks also read as an archive
# rather than as shelving, and they leave the 1.8 m doorways at z=35 and z=44 (both on the
# wall centre, x=0) on the central aisle.
#
# ⚠️ Everything is FLAT-TINTED and untextured (Issue 35, `kontur_mailbox.gd`'s precedent):
# what makes a lot read is its silhouette, and each of the six is a different one.
const ARCH_RACK_X := 2.30       # aisle racks, back to back either side of the walking line
const ARCH_RACK_D := 0.55
const ARCH_RACK_H := 2.00
const ARCH_RACK_Z0 := 37.0
const ARCH_RACK_Z1 := 42.0
const ARCH_SHELF_Y := [0.42, 1.02, 1.62]

func _spawn_recovery_archive() -> void:
	# ⚠️ DARK, and barely metallic. The first build used 0.19/0.26 albedo at metallic 0.4
	# and the racks came back as the BRIGHTEST surfaces in the room — a pale blue-grey
	# cage in front of the two things this room is actually about (the lots and the
	# pedestal). With no reflection probes anywhere in this project a metallic surface
	# just takes the flat ambient, so metallic buys nothing here and costs contrast.
	var steel := _mb_mat(Color(0.115, 0.120, 0.112), 0.10, 0.75)
	var board := _mb_mat(Color(0.150, 0.140, 0.120), 0.05, 0.90)
	for side in [-1.0, 1.0]:
		_build_rack(side, steel, board)

	# side, shelf index, z, builder, lot card
	var lots := [
		[-1.0, 1, 38.0, "sheet", "LOT 04-A   WARD 4 — BEDDING, ONE SET"],
		[-1.0, 2, 40.4, "lever", "LOT 07-C   WING 1 — ISOLATOR, DEFEATED"],
		[-1.0, 0, 41.4, "box", "LOT 11-B   DOMESTIC — MUSICAL, WOUND"],
		[1.0, 2, 37.9, "plate", "LOT 14-D   HOTEL VESPER — ROOM PLATE"],
		[1.0, 1, 39.9, "handset", "LOT 19-F   INTERNAL LINE — HANDSET, CUT"],
		[1.0, 0, 41.6, "empty", "LOT 23-Z   SUBJECT 47 — PENDING"],
	]
	for l in lots:
		_build_lot(float(l[0]), int(l[1]), float(l[2]), String(l[3]), String(l[4]))

	# The ledger. ⚠️ On the WEST wall, 3.1 m south of the safety poster that shares it,
	# and clear of both doorways (which are on the wall centres at z=35 and z=44). It is
	# on the opposite wall from the gate-3 sign on purpose: those two are the only things
	# in this room a player is meant to stop and read, and a wall carrying both is a wall
	# nobody reads twice.
	#
	# It states no answer to any gate — this level's answers are in other levels, and a
	# page in the Archive that gave one away would undo the whole design.
	_make_note(_builder.wall_point("Archive", Vector2(-1, 0), 1.4, 0.16)
		+ Vector3(0, 0, -3.1), PI / 2.0, ARCHIVE_LEDGER)


const ARCHIVE_LEDGER := """RECOVERY LEDGER — WING 4, SHELF INVENTORY

04-A  bedding, one set. Ward 4. The occupant was not with it.
07-C  isolator handle. Someone had already thrown it.
11-B  musical box, domestic. Still wound when it came in.
14-D  room plate, 217. The room is not on any floor plan we hold.
19-F  handset. Cord cut at the wall, from the inside.
23-Z  reserved.

Nothing on these shelves is to leave this room. Nothing on these
shelves arrived here on its own."""


func _build_rack(side: float, steel: Material, board: Material) -> void:
	var rack := StaticBody3D.new()
	rack.name = "RecoveryRack_%s" % ("E" if side > 0.0 else "W")
	rack.position = Vector3(side * ARCH_RACK_X, 0.0, (ARCH_RACK_Z0 + ARCH_RACK_Z1) / 2.0)
	add_child(rack)

	var length: float = ARCH_RACK_Z1 - ARCH_RACK_Z0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_mb_box(rack, "Upright", Vector3(0.06, ARCH_RACK_H, 0.06),
				Vector3(sx * (ARCH_RACK_D / 2.0 - 0.03), ARCH_RACK_H / 2.0,
					sz * (length / 2.0 - 0.03)), steel)
	# Two mid uprights, so a 5 m rack does not read as one long slab.
	for sz2 in [-1.0, 1.0]:
		for sx2 in [-1.0, 1.0]:
			_mb_box(rack, "Upright", Vector3(0.05, ARCH_RACK_H, 0.05),
				Vector3(sx2 * (ARCH_RACK_D / 2.0 - 0.03), ARCH_RACK_H / 2.0,
					sz2 * length / 6.0), steel)
	for y in ARCH_SHELF_Y:
		_mb_box(rack, "Shelf", Vector3(ARCH_RACK_D, 0.035, length),
			Vector3(0, y, 0), board)
		# A lip along the aisle edge — the part that says "shelf" rather than "plank".
		_mb_box(rack, "ShelfLip", Vector3(0.02, 0.05, length),
			Vector3(-side * (ARCH_RACK_D / 2.0 - 0.01), y + 0.042, 0), steel)
	_mb_box(rack, "RackTop", Vector3(ARCH_RACK_D + 0.04, 0.04, length + 0.04),
		Vector3(0, ARCH_RACK_H, 0), steel)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(ARCH_RACK_D, ARCH_RACK_H, length)
	col.shape = shape
	col.position = Vector3(0, ARCH_RACK_H / 2.0, 0)
	rack.add_child(col)


# One lot: a small part-built object standing on a shelf, plus a stencilled card on the
# shelf lip beneath it. `side` is which rack; the object is pushed toward the aisle so it
# is visible from the walking line rather than filed at the back.
func _build_lot(side: float, shelf: int, z: float, kind: String, card: String) -> void:
	var y: float = ARCH_SHELF_Y[shelf] + 0.018
	var x: float = side * (ARCH_RACK_X - 0.10)
	var root := Node3D.new()
	root.name = "Lot_%s" % kind
	root.position = Vector3(x, y, z)
	root.rotation.y = -PI / 2.0 if side > 0.0 else PI / 2.0
	add_child(root)

	var cloth := _mb_mat(Color(0.44, 0.43, 0.40), 0.0, 0.95)
	var dark := _mb_mat(Color(0.13, 0.13, 0.14), 0.25, 0.55)
	var wood := _mb_mat(Color(0.27, 0.19, 0.12), 0.0, 0.8)
	var brass2 := _mb_mat(Color(0.36, 0.30, 0.16), 0.6, 0.5)
	var tin := _mb_mat(Color(0.30, 0.31, 0.29), 0.55, 0.6)

	match kind:
		"sheet":
			# Three offset folds — a folded sheet is a stack that does NOT line up.
			_mb_box(root, "Fold0", Vector3(0.34, 0.05, 0.24), Vector3(0, 0.025, 0), cloth)
			_mb_box(root, "Fold1", Vector3(0.31, 0.045, 0.21), Vector3(0.012, 0.072, -0.01), cloth)
			_mb_box(root, "Fold2", Vector3(0.28, 0.04, 0.19), Vector3(-0.01, 0.114, 0.012), cloth)
		"lever":
			_mb_box(root, "Plate", Vector3(0.22, 0.30, 0.05), Vector3(0, 0.15, 0), tin)
			_mb_box(root, "Handle", Vector3(0.04, 0.11, 0.035), Vector3(0.045, 0.19, 0.04), dark)
			_mb_box(root, "Pilot", Vector3(0.03, 0.03, 0.02), Vector3(-0.06, 0.24, 0.032),
				_mb_mat(Color(0.22, 0.04, 0.04), 0.1, 0.6))
		"box":
			_mb_box(root, "Case", Vector3(0.26, 0.13, 0.18), Vector3(0, 0.065, 0), wood)
			# Lid ajar, hinged at the back — a closed box is a box (Issue 35).
			var lid := Node3D.new()
			lid.name = "LidHinge"
			lid.position = Vector3(0, 0.132, -0.09)
			lid.rotation.x = deg_to_rad(-38.0)
			root.add_child(lid)
			_mb_box(lid, "Lid", Vector3(0.26, 0.02, 0.18), Vector3(0, 0.01, 0.09), wood)
			var crank := MeshInstance3D.new()
			crank.name = "Crank"
			var ccyl := CylinderMesh.new()
			ccyl.top_radius = 0.008
			ccyl.bottom_radius = 0.008
			ccyl.height = 0.06
			crank.mesh = ccyl
			crank.material_override = brass2
			crank.rotation.z = PI / 2.0
			crank.position = Vector3(0.16, 0.075, 0)
			root.add_child(crank)
			_mb_box(root, "CrankArm", Vector3(0.012, 0.05, 0.012), Vector3(0.19, 0.052, 0), brass2)
		"plate":
			_mb_box(root, "Backing", Vector3(0.26, 0.14, 0.02), Vector3(0, 0.10, 0), brass2)
			_mb_box(root, "Stand", Vector3(0.05, 0.03, 0.09), Vector3(0, 0.015, 0.03), tin)
			for sx4 in [-1.0, 1.0]:
				_mb_box(root, "PlateScrew", Vector3(0.016, 0.016, 0.008),
					Vector3(sx4 * 0.105, 0.10, 0.014), tin)
			var num := Label3D.new()
			num.text = "217"
			num.font_size = 64
			num.pixel_size = 0.0011
			num.modulate = Color(0.09, 0.08, 0.07)
			num.position = Vector3(0, 0.10, 0.013)
			root.add_child(num)
		"handset":
			_mb_box(root, "Body", Vector3(0.30, 0.05, 0.06), Vector3(0, 0.03, 0), dark)
			for sx in [-1.0, 1.0]:
				_mb_box(root, "Cup", Vector3(0.07, 0.06, 0.08),
					Vector3(sx * 0.125, 0.055, 0), dark)
			# The cut cord: three short segments falling off the shelf lip.
			for i in range(3):
				_mb_box(root, "Cord", Vector3(0.02, 0.02, 0.02),
					Vector3(0.10 + i * 0.035, 0.012 - i * 0.004, 0.05 + i * 0.02), dark)
		"empty":
			# ⚠️ THE ONE THAT IS EMPTY. An open tray with the player's own number on the
			# card and nothing in it. No sound, no light, no acknowledgement — SCARY P6's
			# register applied to an absence. A player who does not read the cards loses
			# nothing and never knows.
			_mb_box(root, "TrayBase", Vector3(0.34, 0.015, 0.24), Vector3(0, 0.008, 0), tin)
			for sx3 in [-1.0, 1.0]:
				_mb_box(root, "TrayEndS", Vector3(0.015, 0.05, 0.24),
					Vector3(sx3 * 0.1625, 0.033, 0), tin)
			for sz3 in [-1.0, 1.0]:
				_mb_box(root, "TrayEndL", Vector3(0.34, 0.05, 0.015),
					Vector3(0, 0.033, sz3 * 0.1125), tin)

	# The card. On the shelf LIP, under the lot, facing the aisle.
	var lbl := Label3D.new()
	# ⚠️ A UNIQUE NAME PER CARD (Issue 17, and this file has now hit it three times).
	# Six siblings called "LotCard" and Godot renames five of them to @Label3D@NN, so
	# anything that looks one up — including the guard that checks they face the aisle —
	# finds exactly one.
	lbl.name = "LotCard_%s" % kind
	lbl.text = card
	# ⚠️ The card is the LOT'S PAYLOAD — the object is the silhouette, the card is what
	# it means. At pixel_size 0.00072 it photographed as a yellow smudge from the aisle.
	lbl.font_size = 40
	lbl.pixel_size = 0.00115
	lbl.modulate = Color(0.80, 0.78, 0.71)
	lbl.outline_size = 0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# ⚠️ THE SAME ROTATION THE LOT USES, not its negation. The first build faced both
	# card rows INTO their own rack: `Label3D` is double-sided by default, so they still
	# rendered — mirrored, edge-lit and unreadable — which is exactly the failure mode a
	# screenshot catches and a headless assertion cannot.
	lbl.rotation.y = -PI / 2.0 if side > 0.0 else PI / 2.0
	lbl.position = Vector3(side * (ARCH_RACK_X - ARCH_RACK_D / 2.0 - 0.02),
		ARCH_SHELF_Y[shelf] + 0.042, z)
	add_child(lbl)


func _mb_mat(albedo: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = rough
	return m


func _mb_box(parent: Node3D, n: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


# One mail slot: a door recessed into its cell, a pull handle, and a card holder
# with the slot number on it. Slot 12 additionally hangs off a hinge so it can swing.
func _mb_slot(box: Node3D, n: int, at: Vector3, cw: float, ch: float,
		door_mat: Material, brass: Material, card: Material, hinged: bool) -> void:
	var door_size := Vector3(cw - 0.012, ch - 0.012, 0.025)
	var door_parent: Node3D = box
	var door_pos := Vector3(at.x, at.y, at.z - 0.012)

	if hinged:
		# Hinge on the door's LEFT edge, panel offset half its width so the pivot sits
		# on the edge rather than the centre — hiding_spot.gd:_build_door()'s pattern.
		var hinge := Node3D.new()
		hinge.name = "Slot12Hinge"
		hinge.position = Vector3(at.x - cw / 2.0, at.y, at.z - 0.012)
		box.add_child(hinge)
		door_parent = hinge
		door_pos = Vector3(cw / 2.0, 0, 0)
		(box as KonturMailbox).door_hinge = hinge

	var door := _mb_box(door_parent, "Slot%dDoor" % n, door_size, door_pos, door_mat)
	# Handle + card ride ON the door so they swing with it.
	_mb_box(door, "Handle", Vector3(0.09, 0.016, 0.022),
		Vector3(cw * 0.30, -ch * 0.16, door_size.z / 2.0 + 0.011), brass)
	_mb_box(door, "Card", Vector3(0.13, 0.055, 0.008),
		Vector3(-cw * 0.22, ch * 0.20, door_size.z / 2.0 + 0.004), card)

	var lbl := Label3D.new()
	lbl.text = str(n)
	lbl.pixel_size = 0.0016
	lbl.font_size = 48
	lbl.modulate = Color(0.12, 0.11, 0.10)
	lbl.position = Vector3(-cw * 0.22, ch * 0.20, door_size.z / 2.0 + 0.010)
	door.add_child(lbl)


# A flat decal quad. No collider — these hang on walls that already have one, and a
# second collider in front of a wall is how props end up blocking doorways.
#
# ⚠️ `height` is the ONLY dimension the caller gives (2026-08-18, K-T3). The width comes
# from the artwork's own aspect, because both callers here used to pass a shape chosen to
# suit the WALL: the poster was 1.867x stretched and the chute 1.333x, and both textures
# were a picture of the concrete they hang on (Issue 35 / X24). They now use the cropped
# `kontur_poster_sheet.png` / `kontur_chute_hatch.png`.
func _wall_panel(pos: Vector3, y_rot: float, height: float, tex_path: String) -> void:
	if not ResourceLoader.exists(tex_path):
		return
	var tex: Texture2D = load(tex_path)
	var m := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(height * float(tex.get_width()) / float(tex.get_height()), height)
	m.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	# ⚠️ Only when there IS an alpha channel. TRANSPARENCY_ALPHA on an 8-bit RGB image
	# does nothing except buy a transparent-pass sort — it was set unconditionally here,
	# on two images that had no alpha at all, which is the same inert flag the old
	# mailbox decal carried.
	var img := tex.get_image()
	if img and img.detect_alpha() != Image.ALPHA_NONE:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.set_surface_override_material(0, mat)
	m.position = pos
	m.rotation.y = y_rot
	add_child(m)


# ---------------------------------------------------------------- level doors

func _spawn_level_doors() -> void:
	var back := _make_door("BackDoor", false, true)
	back.position = Vector3(0, 1.1, -3.85)

	_exit_door = _make_door("ExitDoor", true, false)
	_exit_door.position = Vector3(_dark_x, 1.1, 97.85)
	_exit_door.rotation.y = PI


func _make_door(door_name: String, advances: bool, back: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = door_name
	body.set_script(_DOOR_SCRIPT)
	body.advances_level = advances
	body.goes_back = back
	add_child(body)
	var mesh := MeshInstance3D.new()
	mesh.name = "DoorMesh"
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 2.2, 0.15)
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.01, 0.01)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.02, 0.02)
	mat.emission_energy_multiplier = 1.5
	mesh.set_surface_override_material(0, mat)
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 2.2, 0.2)
	col.shape = shape
	body.add_child(col)
	return body


# ---------------------------------------------------------------- events / ambience

func _spawn_event(pos: Vector3, size: Vector3, callback: Callable) -> void:
	var ev := CorridorEvent.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	ev.add_child(col)
	ev.position = pos
	ev.fired.connect(callback)
	add_child(ev)


# See level_1.gd / level_2.gd: duplicate the SHARED environment before retuning it,
# and use a BLACK background — the procedural sky leaks through any geometry seam
# as daylight, which is fatal to an interior.
func _boost_ambient(energy: float) -> void:
	var we: WorldEnvironment = get_node_or_null("Environment/WorldEnvironment")
	if not we or not we.environment:
		return
	var env: Environment = we.environment.duplicate()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = energy
	env.ambient_light_color = Color(0.1, 0.11, 0.1)
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	we.environment = env


func _start_ambience() -> void:
	var ambient: AudioStreamPlayer = get_node_or_null("AmbientPlayer")
	if not ambient:
		return
	var s := GameState.load_audio("ambient_kontur")
	if not s:
		s = GameState.load_audio("ambient_lab")   # fallback until the KONTUR bed exists
	if s:
		ambient.stream = s
		ambient.volume_db = -8.0
		ambient.finished.connect(ambient.play)
		ambient.play()
	var music := GameState.load_audio("kontur_music")
	if music:
		var mp := AudioStreamPlayer.new()
		mp.stream = music
		mp.volume_db = -14.0
		add_child(mp)
		mp.finished.connect(mp.play)
		mp.play()


func _play_at(base_name: String, pos: Vector3, volume_db: float = 0.0) -> void:
	var stream := GameState.load_audio(base_name)
	if not stream:
		return
	var pl := AudioStreamPlayer3D.new()
	pl.stream = stream
	pl.volume_db = volume_db
	pl.unit_size = 8.0
	pl.max_db = 6.0
	add_child(pl)
	pl.position = pos
	pl.finished.connect(pl.queue_free)
	pl.play()


func _process(delta: float) -> void:
	_check_void_fall()
	_tick_airlock(delta)
	_update_dark_seams()
	_tick_phone_pressure(delta)

	# Fluorescent unsteadiness in the facility half, a slow sick pulse in the Soviet half.
	var t := Time.get_ticks_msec() * 0.001
	for entry in _lights:
		var lamp: OmniLight3D = entry[0]
		var base: float = entry[1]
		if base <= 0.0:
			continue
		if lamp.position.z > 51.0:
			var flicker := 1.0 if sin(t * 47.0 + lamp.position.z) > -0.93 else 0.35
			lamp.light_energy = base * flicker
		else:
			lamp.light_energy = base * (1.0 + sin(t * 5.0 + lamp.position.z) * 0.06)


# Gate 7's tell, inverted against the flashlight exactly like the Backrooms Flood:
# the real seam shows in the dark, the painted ones show under the beam.
# `is_flashlight_on()` reports false for a dead battery too, so a player who burned
# the light getting here can still finish — the rule is "not lit", not "switched off".
func _update_dark_seams() -> void:
	if _dark_seams.is_empty():
		return
	var p := _player()
	if not p or not p.has_method("is_flashlight_on"):
		return
	var lit: bool = p.is_flashlight_on()
	for entry in _dark_seams:
		var marker: MeshInstance3D = entry[0]
		if is_instance_valid(marker):
			marker.visible = (not lit) if entry[1] else lit
