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
#   Gate 5  THE ROSTER      recall      <- the INTRO note ("You are Subject 47")
#   Gate 3  THE OFFERING    abstain     <- the L3 Corridor door plate
#   Gate 6  THE PHONE       ignore      <- the L4 Backrooms phone (a read-to-die trap)
#   Gate 7  THE DARK ROOM   unlight     <- the L4 Backrooms Flood (light hides the way)
#   Gate 8  THE AIRLOCK     wait        <- self-taught (it INVERTS the Backrooms rule
#                                          that standing still kills you, so it has to
#                                          teach itself with a visible cycle meter)
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

const STRIKE_PANIC := 18.0        # 3 x 18 = 54 > PANIC_MAX (50)
const FLASH_PATH := TEX + "kontur_flash.png"
const FLASH_AUDIO := "kontur_flash"

# Subject 47 — the intro room's opening note. TWO digits, deliberately: on a 3-dial
# lock "47" is ambiguous (047? 470?) and a playtester who knew the answer still failed
# it twice. The lock now sizes itself from this string.
const ROSTER_CODE := "47"
const VOID_Y := -4.0              # same threshold the Void uses (level_3.gd)
const AIRLOCK_CYCLE := 9.0        # seconds of stillness the decontamination needs
const STILL_SPEED := 0.35         # m/s below which the player counts as still

var _builder: RoomBuilder
var _lights: Array = []           # [OmniLight3D, base_energy]
var _strikes: int = 0
var _held_bottle: String = ""     # "" | "vinegar" | "bleach" | "water"
var _barrier: FungalBarrier
var _took_offering: bool = false
var _answered_phone: bool = false
var _gate1_done: bool = false
var _gate3_scored: bool = false
var _gate6_scored: bool = false
var _banished: bool = false       # guards the fall handler against re-entry
var _forfeited: bool = false
var _exit_door: StaticBody3D

# Where the Blackout room's real exit lies. Randomised per run from three candidate
# x offsets, and the Airlock/Escort/Terminus spine is BUILT at that offset — so the
# answer is genuinely different each time rather than a memorised doorway.
var _dark_x: float = 0.0
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

# Gate 8 state.
var _airlock_t: float = 0.0
var _in_airlock: bool = false
var _airlock_meter: MeshInstance3D
var _airlock_seal: CSGBox3D


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameState.current_level = 5

	_clear_old_scene()
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
	_spawn_signs()
	_spawn_props()
	_spawn_level_doors()
	_refresh_exit()
	_start_ambience()
	_boost_ambient(0.3)

	GameState.set_objective("PROTOCOL 4-B — PROCEED TO THE MARKED EXIT")


func _player() -> CharacterBody3D:
	return get_node_or_null("Player") as CharacterBody3D


func _clear_old_scene() -> void:
	for child in get_children():
		if not PRESERVE.has(child.name):
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


func _place_player() -> void:
	var p := _player()
	if not p:
		return
	p.global_position = Vector3(0, 0.1, -3.0)
	p.rotation = Vector3(0, PI, 0)   # face +z, down the spine


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
	# the L1 note), never a memorised position.
	var black_on_east := randf() < 0.5
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
	d.texture_path = TEX + ("door_black.png" if is_black else "door_red.png")
	# The node is the hinge; the panel extends +x from it, so start half a width left.
	d.position = Vector3(x - ChoiceDoor.WIDTH / 2.0, 0.0, 10.0)
	d.chosen.connect(_on_gate1_chosen)
	add_child(d)

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

	var kinds := [
		["bleach", TEX + "label_bleach.png", 22.3],
		["vinegar", TEX + "label_vinegar.png", 23.5],
		["water", TEX + "label_water.png", 24.7],
	]
	for entry in kinds:
		var b := BottleItem.new()
		b.kind = entry[0]
		b.label_path = entry[1]
		b.position = Vector3(3.4, 0.99, entry[2])
		b.rotation.y = -PI / 2.0    # label faces into the room (-x)
		b.taken.connect(_on_bottle_taken)
		add_child(b)

	_barrier = FungalBarrier.new()
	_barrier.name = "FungalBarrier"
	_barrier.position = Vector3(0, 1.5, 27.0)
	_barrier.setup(Vector3(2.2, 3.0, 0.5), TEX + "fungal_mass.png")
	_barrier.sprayed.connect(_on_barrier_sprayed)
	add_child(_barrier)


func _on_bottle_taken(kind: String) -> void:
	_held_bottle = kind
	_notice("Carrying: %s" % kind.to_upper(), Color(0.6, 0.9, 0.6))
	# Keep it on the HUD too — the notice fades, and the barrier may be a walk away.
	GameState.set_objective("DECONTAMINATION REQUIRED — CARRYING: %s" % kind.to_upper())


func _on_barrier_sprayed() -> void:
	if _held_bottle == "":
		_notice("It will not move. Something has to break it down.", Color(0.85, 0.85, 0.7))
		return
	if _held_bottle == "vinegar":
		_barrier.dissolve()
		_pass_gate("shelf")
		_play_at("acid_hiss", Vector3(0, 1.5, 27), 0.0)
		GameState.set_objective("PERSONNEL CHECKPOINT — STATE YOUR SUBJECT NUMBER")
	else:
		# The bottle is spent, so a wrong guess costs a walk back as well as panic.
		_held_bottle = ""
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

# The only gate whose answer the player has been carrying since the first minute of
# the game: the intro room's note opens "You are Subject 47." Nothing in KONTUR ever
# says the number — the roster plate just leaves the field blank.
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
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.4, 0.3)
	mesh.mesh = bm
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.3, 0.32, 0.3)
	lm.emission_enabled = true
	lm.emission = Color(0.5, 0.7, 0.5)
	lm.emission_energy_multiplier = 0.4
	mesh.set_surface_override_material(0, lm)
	lock.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.16, 0.44, 0.34)
	col.shape = shape
	lock.add_child(col)

	# The way on is welded shut until the number is entered.
	var seal := CSGBox3D.new()
	seal.name = "RosterSeal"
	seal.size = Vector3(2.0, 3.0, 0.3)
	seal.position = Vector3(0, 1.5, 35.0)
	seal.use_collision = true
	seal.material = _mat(TEX + "kontur_facility_wall.png", 0.4, Color(0.45, 0.48, 0.45))
	add_child(seal)

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
# Here the verb is simply IGNORE. Picking up voids the run — but the phone rings for
# a whole room's length first, so the temptation is real and the choice is deliberate.
func _spawn_gate6_phone() -> void:
	var phone := RotaryPhone.new()
	phone.name = "SwitchboardPhone"
	phone.open_note = false     # the forfeit IS the punishment; don't also bleed them
	phone.position = Vector3(-2.2, 0.75, 47.5)
	phone.answered.connect(func() -> void:
		_answered_phone = true
		_forfeit("YOU ANSWERED IT")
	)
	add_child(phone)

	# A desk to stand it on, with no collider — a desk collider would intercept the
	# interaction ray before it reached the phone (the House key-stand lesson).
	var desk := CSGBox3D.new()
	desk.name = "SwitchboardDesk"
	desk.size = Vector3(1.4, 0.75, 0.7)
	desk.position = Vector3(-2.2, 0.375, 47.5)
	desk.use_collision = false
	desk.material = _mat("", 1.0, Color(0.26, 0.24, 0.2))
	add_child(desk)

	_spawn_event(Vector3(0, 1.5, 50.2), Vector3(7, 3, 1.2), _score_gate6)


func _score_gate6() -> void:
	if _gate6_scored:
		return
	_gate6_scored = true
	if not _answered_phone:
		_pass_gate("phone")
		GameState.set_objective("LIGHTING FAULT — SECTOR DARK. FIND THE TRANSIT DOOR.")


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

# The inversion the Backrooms spent a whole level setting up: there, standing still
# raises panic; here it is the only way through. That flips a rule the player has been
# trained on, so unlike every other gate this one must TEACH ITSELF — hence the cycle
# meter on the wall, which fills while you are still and drains the moment you move.
# No hint anywhere else in the game explains it.
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
	)
	zone.body_exited.connect(func(b: Node3D) -> void:
		if b.is_in_group("player"):
			_in_airlock = false
			_airlock_t = 0.0
	)

	# The meter: a bar that grows along +x as the cycle completes.
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

	_airlock_meter = MeshInstance3D.new()
	var mq := QuadMesh.new()
	mq.size = Vector2(2.0, 0.16)
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
	_airlock_meter.scale.x = 0.001
	add_child(_airlock_meter)

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
	# Horizontal speed only — looking around is not moving, and this gate is about
	# holding your ground, not holding the mouse still.
	var v: Vector3 = p.velocity
	v.y = 0.0
	if v.length() <= STILL_SPEED:
		_airlock_t = minf(AIRLOCK_CYCLE, _airlock_t + delta)
	else:
		_airlock_t = maxf(0.0, _airlock_t - delta * 2.0)   # drains faster than it fills

	if is_instance_valid(_airlock_meter):
		_airlock_meter.scale.x = maxf(0.001, _airlock_t / AIRLOCK_CYCLE)

	if _airlock_t >= AIRLOCK_CYCLE:
		_pass_gate("airlock")
		if is_instance_valid(_airlock_seal):
			_airlock_seal.queue_free()
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

func _spawn_creature() -> void:
	# The Perëkozhnik, planted in the passage's far west corner — off the walking
	# line, so only curiosity brings you inside its 2 m kill radius.
	var c := CreatureShapechanger.new()
	c.name = "Shapechanger"
	c.position = Vector3(-3.2, 0, 18.0)
	add_child(c)


# ---------------------------------------------------------------- signs

func _spawn_signs() -> void:
	# Each gate's rule, with the operative word censored. A player who found the
	# earlier-level hints reads straight through these; one who didn't gets the
	# shape of the question but not the answer.
	_make_sign(Vector3(0, 1.7, 9.85), PI,
		"K.O.N.T.U.R. — PROTOCOL 4-B", "EVACUATION ROUTE IS MARKED IN:")
	_make_sign(_builder.wall_point("Kitchen", Vector2(-1, 0), 1.7, 0.16), PI / 2.0,
		"DECONTAMINATION — CLASS II", "APPROVED AGENT: DOMESTIC")
	_make_sign(_builder.wall_point("Records", Vector2(-1, 0), 1.7, 0.16), PI / 2.0,
		"PERSONNEL GATE — OBJECT 12", "THIS SUBJECT IS NUMBER:")
	_make_sign(_builder.wall_point("Archive", Vector2(1, 0), 1.7, 0.16), -PI / 2.0,
		"RECOVERY LOG — OBJECT 12", "ITEMS RECOVERED FROM AN OBJECT ARE:")
	_make_sign(_builder.wall_point("Switchboard", Vector2(1, 0), 1.7, 0.16), -PI / 2.0,
		"INTERNAL LINE — WING 4", "AN INCOMING CALL MUST BE:")
	_make_sign(_builder.wall_point("Blackout", Vector2(-1, 0), 1.7, 0.16), PI / 2.0,
		"LIGHTING FAULT — SECTOR 9", "THE TRUE DOOR IS SEEN WHEN:")
	# Gate 8's sign is the one that must nearly give the game away: it inverts a rule
	# the Backrooms spent a whole level teaching, and no earlier level hints at it.
	_make_sign(_builder.wall_point("Airlock", Vector2(1, 0), 1.7, 0.16), -PI / 2.0,
		"DECONTAMINATION CYCLE", "TO CYCLE, THE SUBJECT MUST REMAIN:")
	# ⚠️ The escort's rule hangs in the AIRLOCK, not in the corridor it governs. It used
	# to sit at the corridor's midpoint — 13 m past the point where breaking it voids
	# the run, so a playtester forfeited before ever reading it. Here the player is
	# already standing still for gate 8's cycle, with nothing to do but read.
	_make_sign(_builder.wall_point("Airlock", Vector2(-1, 0), 1.7, 0.16), PI / 2.0,
		"TRANSIT PROTOCOL 7", "DO NOT ___ THE ESCORT")


# A plate + two text lines + a censor bar on its own line, so the redaction needs no
# text measurement to place (and reads exactly like a real censored form).
func _make_sign(pos: Vector3, y_rot: float, title: String, body: String) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = y_rot
	add_child(root)

	var plate := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 0.95)
	plate.mesh = quad
	var pmat := StandardMaterial3D.new()
	if ResourceLoader.exists(TEX + "kontur_sign_blank.png"):
		var ptex := load(TEX + "kontur_sign_blank.png")
		pmat.albedo_texture = ptex
		# Faintly backlit, so the rules stay readable in rooms this dark — these are
		# the only in-level help there is, and an unreadable sign is no help at all.
		pmat.emission_enabled = true
		pmat.emission_texture = ptex
		pmat.emission_energy_multiplier = 0.55
	else:
		pmat.albedo_color = Color(0.62, 0.65, 0.6)
	pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plate.set_surface_override_material(0, pmat)
	root.add_child(plate)

	var lbl := Label3D.new()
	lbl.text = "%s\n\n%s" % [title, body]
	lbl.font_size = 44
	# Sized so the longest line stays inside the plate's engraved inner frame.
	lbl.pixel_size = 0.0014
	lbl.modulate = Color(0.1, 0.1, 0.1)
	lbl.outline_size = 0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector3(0, 0.13, 0.012)
	root.add_child(lbl)

	var bar := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(0.85, 0.11)
	bar.mesh = bq
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.04, 0.04, 0.04)
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bar.set_surface_override_material(0, bmat)
	bar.position = Vector3(0, -0.24, 0.014)
	root.add_child(bar)


# ---------------------------------------------------------------- props

func _spawn_props() -> void:
	# Stairwell dressing on the Landing's side walls (the north wall is the doorway).
	_wall_panel(_builder.wall_point("Landing", Vector2(-1, 0), 1.5, 0.16), PI / 2.0,
		Vector2(1.6, 1.4), TEX + "kontur_panel_mailboxes.png")
	_wall_panel(_builder.wall_point("Landing", Vector2(1, 0), 1.3, 0.16), -PI / 2.0,
		Vector2(1.1, 1.1), TEX + "kontur_panel_chute.png")
	# The safety poster, on the Archive's west wall.
	# ⚠️ inset 0.16, not 0.08: wall_point measures from the room's NOMINAL boundary and
	# the wall is 0.2 m thick centred on it, so anything under ~0.11 is buried inside
	# the wall and invisible in game (ISSUES_SOLUTIONS Issue 11).
	_wall_panel(_builder.wall_point("Archive", Vector2(-1, 0), 1.7, 0.16), PI / 2.0,
		Vector2(1.0, 1.4), TEX + "kontur_poster.png")


# A flat decal quad. No collider — these hang on walls that already have one, and a
# second collider in front of a wall is how props end up blocking doorways.
func _wall_panel(pos: Vector3, y_rot: float, size: Vector2, tex_path: String) -> void:
	if not ResourceLoader.exists(tex_path):
		return
	var m := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	m.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(tex_path)
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
