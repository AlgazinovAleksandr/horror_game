extends Node3D
class_name BackroomsZone3

# ZONE 3 — THE FLOOD.
#
# The last inversion. Five levels have taught the player that the flashlight is
# safety; here the exit seam is only visible with it OFF. Two decoy seams glow only
# while the light is ON — the exact inverse — so the instinct to light the room up
# doesn't just fail, it actively misleads.
#
# ⚠️ There is NO DarkZone here, despite what this header said for a long time. One was
# removed deliberately: a room solved by turning the flashlight off must not also tax
# the flashlight being off (+3/s AND decay suppressed). That is ISSUES_SOLUTIONS
# Issue 18, which this project has now made twice.
#
# Built on RoomBuilder rather than raw boxes: it de-dupes shared walls and bridges
# the floor under every doorway, which is the whole reason the Issue-5 void-fall
# class can't come back.

signal cleared
signal mistake

const WATER_Y := 0.12
const ROOM_H := 3.2
const WADE_SLOW := 0.6             # refreshed every frame while submerged

# A DreadZone's decay (2.0) and pressure (2.0) cancel EXACTLY, so dread alone leaves
# the bar frozen — no threat at all in the level's finale. This is the zone's own
# slow drip on top, the way CreatureSmiler drives its own curve. Deliberately small:
# from the entry cap (`backrooms.gd:ZONE_ENTRY_PANIC_CAP`, 25% — this comment said 35%
# until 2026-07-27) it allows roughly a minute of searching, which is about one
# unhurried sweep of the wing, and the dry platform's CalmZone still nets negative so
# there is somewhere to recover. Pressure everywhere, exactly one island.
# 0.5 left ~65 s, but playtest showed a first-time player needs ~90-120 s to sweep
# the wing and find the Sump. 0.3 gives ~125 s from the entry cap.
const DREAD_DRIP := 0.3            # panic per second, flashlight-independent

# The tide line, well above head height — the water was once much deeper than this.
const TIDE_Y := 2.35
const TIDE_LEN := 7.0

var _wader: UnseenWader = null

var spawn_point: Vector3

var _origin: Vector3
var _builder: RoomBuilder
var _player: Node3D
var _real_seam: GlitchWall
var _decoys: Array[GlitchWall] = []
var _drip_timer: float = 0.0

# An 8-room flooded wing. Deliberately branching: the seam is in Sump, off the
# main line, so the player has to explore in the dark rather than walk straight on.
#
# ⚠️ ROOMS ABUT. THEY DO NOT OVERLAP (fixed 2026-08-17, backlog 04 B-A2 / OQ5).
#
# Sump was at x -13..-5 and Cistern at x 5..13, so each overlapped the Basin (x -6..6,
# z 11..19) in a 1 m x 2 m corner. CLAUDE.md states the rule this broke in as many words:
# "Rooms in a ROOMS table must ABUT, never OVERLAP." What it actually built, proved by ray
# sweep rather than by reading the table:
#
#   * a wall standing INSIDE the Basin at x = -5.10 and x = +4.90, spanning z 17..19 —
#     the Sump's east wall and the Cistern's west wall, each protruding 2 m into the
#     Flood's largest room, the one that holds the DryPlatform CalmZone;
#   * a wall standing INSIDE the Sump at x = -6.10 — the Basin's west wall, likewise 2 m in;
#   * the Basin's two north corners boxed into 1 x 2 m dead pockets (walls at z 16.90 and
#     z 18.90 crossing x = ±5.5);
#   * four coincident floor/ceiling slab pairs (Basin/Sump and Basin/Cistern, +y faces) —
#     the z-fighting half, which check_wall_overlap.gd sees and nothing had ever pointed
#     at this scene.
#
# Moving the two outer chambers 1 m OUTWARD makes every shared boundary a shared PLANE,
# which is what RoomBuilder's interval dedup is built for. The Basin and its CalmZone /
# DryPlatform do not move; the real seam, the Cistern decoy, the beartrap and the wader
# waypoints are all derived from room centres and follow automatically.
const ROOMS := [
	{ "name": "Landing",  "pos": Vector2(0, 0),     "size": Vector2(6, 6) },
	{ "name": "Descent",  "pos": Vector2(0, 7),     "size": Vector2(4, 8) },
	{ "name": "Basin",    "pos": Vector2(0, 15),    "size": Vector2(12, 8) },
	{ "name": "EastRun",  "pos": Vector2(9, 15),    "size": Vector2(6, 4) },
	{ "name": "WestRun",  "pos": Vector2(-9, 15),   "size": Vector2(6, 4) },
	{ "name": "Sump",     "pos": Vector2(-10, 21),  "size": Vector2(8, 8) },
	{ "name": "Cistern",  "pos": Vector2(10, 21),   "size": Vector2(8, 8) },
	{ "name": "Throat",   "pos": Vector2(0, 23),    "size": Vector2(4, 8) },
]

# ⚠️ The Sump/Cistern doorways move WITH their rooms. They sit in the z=17 plane shared by
# WestRun/EastRun (z 13..17) and Sump/Cistern (z 17..25); at x = ∓10 a 2.2 m opening spans
# ∓11.1..∓8.9, which is inside WestRun (x -12..-6) / EastRun (x 6..12) as well as inside
# the chamber beyond it. Leaving them at ∓9 would have put a third of each doorway outside
# the side run and opened a hole into solid ground.
const DOORS := [
	{ "pos": Vector2(0, 3),    "width": 2.0, "dir": "z" },
	{ "pos": Vector2(0, 11),   "width": 2.4, "dir": "z" },
	{ "pos": Vector2(6, 15),   "width": 2.0, "dir": "x" },
	{ "pos": Vector2(-6, 15),  "width": 2.0, "dir": "x" },
	{ "pos": Vector2(-10, 17), "width": 2.2, "dir": "z" },
	{ "pos": Vector2(10, 17),  "width": 2.2, "dir": "z" },
	{ "pos": Vector2(0, 19),   "width": 2.0, "dir": "z" },
]


func build(origin: Vector3, player: Node3D) -> void:
	_origin = origin
	_player = player
	position = origin
	spawn_point = origin + Vector3(0, 0.1, -2.0)

	_build_rooms()
	_build_water()
	_build_water_audio()
	_build_digit_notes()
	_build_seams()
	_build_pressure()
	_build_tide_marks()
	_build_drowned()
	_build_plate()
	_build_wader()
	# ⚠️ NO WADING FOOTSTEP (2026-08-15, user's call, second report).
	#
	# This zone used to swap the player's footstep sample for `wade_step` — a synthesized
	# splash+thud (tools/make_sfx_atmos.py:199) whose stated purpose was P10's anchor:
	# "what you hear in the distance has to be audibly the same ACT you are performing."
	# Two problems, one of them fatal:
	#
	#   1. It was installed in build(), which runs at LEVEL START for all three zones, so
	#      the player waded audibly across the DRY CARPET OF THE LOBBY from their first
	#      step. Fixed once by gating it on the footprint; the user then asked for the
	#      sound gone in the Flood as well.
	#   2. Measured, it was the wrong sound to lead with anyway: -17.1 dBFS RMS at 0 dB,
	#      at the ear, on the un-duckable Body bus, every 0.5 s — against a water bed at
	#      -39.6 dBFS. The zone announced wading twice a second and never sounded wet.
	#
	# The replacement is the inverse and is what _build_water_audio() now does: an audible
	# standing body of water, and ordinary footsteps in it. `wade_distant` (the unseen
	# wader) is untouched and still reads correctly — it is something moving through water
	# you can now actually hear.
	set_process(true)


# SCARY.md P10 — never rendered, never resolving. It patrols the room graph's own centres, so
# it is always somewhere that is actually a room rather than inside the geometry.
func _build_wader() -> void:
	var centres: Array[Vector3] = []
	for r in ROOMS:
		var p: Vector2 = r["pos"]
		centres.append(_origin + Vector3(p.x, 0.9, p.y))
	_wader = UnseenWader.build(self, centres)


# ================================================================= THE DROWNED (2026-08-17)
#
# J-capture #5, Flood-local (-9.40, 15.80): *"The flood sublevel even though looks very cool
# feels very empty. Maybe we can pack it with more action somehow?"* Offered four directions,
# the user chose **searchable content and events**.
#
# Six half-submerged objects, one per room, each found BY EAR (`sunken_item.gd` knocks while
# unsearched) and silenced forever by searching it. Four things are load-bearing about the
# placement and each of them is asserted in `tests/check_flood_drowned.gd`:
#
#   * ⚠️ **NOTHING IN THE SUMP.** The Sump holds the real seam. An audible object in the exit
#     room would hand out a bearing to the answer, and this pass was explicitly told not to
#     touch the seam puzzle. The Sump stays silent and empty.
#   * ⚠️ **NOTHING IN THE CISTERN.** The Cistern holds the beartrap. Luring a player across an
#     invisible 15-panic trap with a sound is anti-pattern §5.2(11) — punishing a player for a
#     scare they could not have seen coming — and it is exactly why two of the three original
#     beartraps were removed from the forced path (see `_build_pressure()`).
#   * The Basin item sits ~2.3 m from the Basin DECOY seam, in view of it. A player who turns
#     the torch on to look at what they have hauled out watches the decoy light up and the
#     real seam go out, in the same second, without being told anything. That is the zone's
#     own rule DEMONSTRATED rather than stated, and it costs nothing.
#   * No item is within 1.2 m of a doorway span or of a digit note. `wall_point()`'s standing
#     lesson in prop form: a collider in the wrong place silently seals a room.
#
# ⚠️ ZERO PANIC, ZERO FAIL STATES, ZERO NEW RULES. Reading is free (NoteUI pauses the tree, so
# the zone's DREAD_DRIP does not tick behind a page). The only cost of a full search is the
# WALKING, measured against the entry cap in `check_flood_drowned.gd` and reported to the user
# rather than tuned — this file changes no difficulty constant.
const DROWNED := [
	{"name": "Drowned_Landing", "room": "Landing", "kind": "footlocker",
		"offset": Vector2(-1.70, 0.30), "yaw": 0.35},
	{"name": "Drowned_Descent", "room": "Descent", "kind": "gurney",
		"offset": Vector2(-0.85, 0.00), "yaw": PI / 2.0},
	{"name": "Drowned_Basin", "room": "Basin", "kind": "drawers",
		"offset": Vector2(3.40, 1.60), "yaw": -0.30},
	{"name": "Drowned_EastRun", "room": "EastRun", "kind": "suitcase",
		"offset": Vector2(-0.80, -1.20), "yaw": 0.9},
	{"name": "Drowned_WestRun", "room": "WestRun", "kind": "toolchest",
		"offset": Vector2(1.00, -1.10), "yaw": -0.6},
	{"name": "Drowned_Throat", "room": "Throat", "kind": "wheelchair",
		"offset": Vector2(1.10, 1.60), "yaw": 2.4},
]

# Six short pages of one story: the wing was staffed, the water came, and the things down
# here are not all from this building. ⚠️ NONE of them states the seam rule. The zone already
# says it in its own objective line ("The way out does not show itself in the light"), and a
# second statement of the answer inside optional content would make the puzzle easier for
# exactly the players who need it least.
const DROWNED_NOTES := {
	"footlocker": """Footlocker, unlabelled. Everything inside it is folded.

Somebody packed to leave and then did not leave.

There is a duty card in the lid. Every name on it has been crossed out in the same hand — including, at the bottom, that hand's own.""",
	"gurney": """The sheet comes away wet and far heavier than a sheet.

Underneath: an impression the shape of a person, and a wristband cut through with scissors.

This is ward furniture. The ward is nine floors up and four levels back. Nobody carried it down here.""",
	"drawers": """Sodden files. The ink has run out of all of them but one.

INCIDENT — LOWER WING. Water ingress 03:40. Wing sealed 03:52. No personnel unaccounted for.

Underneath, later, in pencil: WE SEALED IT FROM THE INSIDE.""",
	"suitcase": """A suitcase. Not staff issue.

Clothes for a child, packed neatly, and a photograph so far gone that it is only a shape now.

Whoever brought this thought they were going somewhere.""",
	"toolchest": """Bolt cutters. A lamp with no bulb in it. And a page with one sentence on it, written out forty times.

I KEEP THE LIGHT ON SO I CAN SEE WHAT I AM PULLING OUT OF THE WATER.

The last line runs off the edge of the paper.""",
	"wheelchair": """The chair turns when you touch it. The brake has been off for a long time.

A child's shoe is wedged in the footplate, laces still tied.

There is no child in this wing. There is no wing above this one, either. You came down three times and there was never a stair.""",
}

# --- the events -------------------------------------------------------------------------
#
# Three beats on the search count, and every one of them is a CHANNEL rather than a number:
# nothing below adds panic, spawns an entity, or changes a rule.
const ANSWER_AT := 1        # every remaining item knocks once — "there are more"
const SURFACING_AT := 3     # something else hauls something out of the water
const SURFACE_MIN := 5.0
const SURFACE_MAX := 13.0
const SURFACE_DB := -1.0
const EMPTIED_BED_DROP := 3.0    # dB, permanent — the wing is quieter than you found it
const EMPTIED_DRIP := Vector2(6.0, 16.0)

var _drowned: Array[SunkenItem] = []
var _searched := 0
var _surfaced := false
var _emptied := false
var _drip_range := Vector2(3.0, 8.0)
var _zone_active := false


# ========================================================== THE PLATE (2026-08-17, B-R1)
#
# The user's own design, chosen over two alternatives:
#
#   *"we say the way out does not show itself in the light: you need to collect 6 pieces
#   of puzzle contained in different items and collect the puzzle at the middle of the
#   level. Then, the exit will appear - but you can find it only after you turn off the
#   flashlight."*
#
# So THE DROWNED stop being six optional pages and become the route to the exit: each one
# holds a fragment, the six fragments are set into the plate table in the Basin, and only
# then does the Sump seam exist at all. ⚠️ The darkness rule is UNCHANGED and is still the
# last step — this pass adds a route to it, it does not replace it.
#
# ⚠️⚠️ THE UNWINNABLE RISK, AND THE ONE THING THAT MAKES THIS SAFE. A mandatory six-object
# search in a near-black 28 m wing is exactly the shape this project has shipped broken
# before: a player who cannot find the last object is stuck with no exit and no
# explanation. The whole safety net is that **an object with its fragment still in it
# knocks every 5-11 s, for ever** — `sunken_item.gd:_process` is gated on `is_taken`, not
# on `is_searched`, precisely so hauling a lid and walking away cannot silence the one
# object you still need. `tests/check_flood_puzzle.gd` asserts that, and asserts the whole
# zone is completable from a cold start through the real interact path.
#
# ⚠️ ZERO new panic, zero new fail states. Fragments cost nothing; setting them cannot go
# wrong; there is no order and no timer. What the puzzle costs is WALL CLOCK against the
# zone's existing DREAD_DRIP, measured in `tests/probe_flood_search.gd`.
#
# ⚠️ THE TABLE STANDS OFF THE DRY PLATFORM, NOT ON IT (D21): the platform is a 0.44 m step
# `move_and_slide` cannot climb, so a table on top of it would be a puzzle you can see and
# cannot reach. It sits 1.5 m west of the platform's edge, 3.4 m from the Basin lamp — the
# only light in the wing — and clear of all three of the Basin's doorways by >2.5 m.
const PLATE_OFFSET := Vector2(-3.2, -1.2)   # from the Basin's centre
const PLATE_YAW := 0.35

var _plate: FloodPlate = null
var _held := 0          # fragments in hand, not yet set
var _taken := 0         # fragments lifted out of objects, ever
var _plate_done := false


func _build_plate() -> void:
	var c: Vector3 = _builder.room_center("Basin")
	_plate = FloodPlate.build(self, "FloodPlate",
		Vector3(c.x + PLATE_OFFSET.x, 0.0, c.z + PLATE_OFFSET.y), PLATE_YAW)
	_plate.set_requested.connect(_on_plate_used)
	_plate.completed.connect(_on_plate_complete)


func _on_plate_used() -> void:
	if _held <= 0:
		return
	var n := _held
	_held = 0
	_plate.set_carried(0)
	_plate.seat(n)
	_refresh_objective()


# The exit is EARNED here, and this is the only place it is armed. Note what does NOT
# happen: no panic, no scare, no teleport, no light change. The wing simply now contains
# something it did not contain before, and finding it is still a search in the dark.
func _on_plate_complete() -> void:
	_plate_done = true
	if is_instance_valid(_real_seam):
		_real_seam.set_armed(true)
	_refresh_objective()
	ScreenText.caption(get_tree(),
		"The plate is whole.\nSomething in this wing has come open.", 4.5)


# One source of truth for the zone's objective line, so the entry announcement, every
# fragment and the back-door restore path cannot drift apart — `level_2.gd`'s OBJ_* consts
# exist because that drift happened three times in the House.
#
# ⚠️ IT NAMES A RULE, NEVER A PLACE, AND SINCE 2026-08-18 IT NAMES NO TASK EITHER.
# Playtest capture 005: *"The message should not be that obvious. It should be like 'Solve
# the mystery' or something like this. And do not write that hint, just write that the
# ex[it] won['t show itself in the light]."* The line was `Six pieces are sunk in this wing
# (n/6)`, which is a shopping list with a progress bar on it — it stated the quantity, the
# verb and the score before the player had found anything.
#
# So there are two states now and neither is instructional:
#   before the plate is whole  — a mystery, no count, no verb, no place;
#   after it                   — the darkness RULE, which is the only thing left to know
#                                and which arrives at the exact moment it becomes usable.
#
# ⚠️⚠️ REMOVING THE COUNTER IS SAFE **BECAUSE THE KNOCKS ARE THE COUNTER**, and that is not
# a consolation, it is the design. Every drowned object with its fragment still in it knocks
# every 5-11 s for ever (`sunken_item.gd:_process`, gated on `is_taken` and never on
# `is_searched`), and goes silent the moment it is emptied. An object still knocking IS a
# piece outstanding; the wing gets audibly emptier as you work it. That channel is permanent,
# positional and asserted — which the HUD number never was. Do not "restore" the counter
# under the impression that the progress feedback was lost with it.
#
# ⚠️ AND THE PLATE STILL HAS TO BE FINDABLE WITH NO LINE POINTING AT IT. Its three
# announcement channels now carry all of that weight: it stands in the wing's only lit room,
# its own backboard reads `SIX PIECES. / SET THEM HERE.`, and the two-layer `plate_hum` /
# `plate_ring` tell arms on the FIRST fragment and is a measured bearing (`+8.3 dB` over the
# water bed at the worst room, falling 7.6 dB across the wing). `check_flood_puzzle.gd`
# measures all three every run.
func objective_text() -> String:
	if _plate_done:
		return "The way out does not show itself in the light"
	return "Something in this wing is unfinished"


func _refresh_objective() -> void:
	GameState.set_objective(objective_text())


func _build_drowned() -> void:
	for spec in DROWNED:
		var c: Vector3 = _builder.room_center(String(spec["room"]))
		var off: Vector2 = spec["offset"]
		var kind := String(spec["kind"])
		# ⚠️ `room_center()` is ZONE-LOCAL (this node already sits at `_origin`), and so is a
		# child's `position`. Adding `_origin` here would put every item 200 m away in the
		# Lobby — the same two-errors-cancelling trap the drip ticker's comment describes.
		var item := SunkenItem.build(self, String(spec["name"]), kind,
			Vector3(c.x + off.x, 0.0, c.z + off.y), float(spec["yaw"]),
			String(DROWNED_NOTES.get(kind, "")))
		item.searched.connect(_on_item_searched)
		item.piece_taken.connect(_on_piece_taken)
		_drowned.append(item)


func searched_kinds() -> Array:
	var out: Array = []
	for it in _drowned:
		if is_instance_valid(it) and it.is_taken:
			out.append(it.name)
	return out


func pieces_set() -> int:
	return _plate.pieces_set() if is_instance_valid(_plate) else 0


func pieces_held() -> int:
	return _held


func pieces_taken() -> int:
	return _taken


func plate_done() -> bool:
	return _plate_done


# The restore path for a back-door return (`backrooms.gd:save_progress`). Empties the
# items silently — no fragment, no note, no sound, no event — and re-applies the end state
# if the wing was already emptied, because "the wing is quieter now" is progress the player
# earned. ⚠️ The FRAGMENTS restore too: an emptied object whose fragment came back would
# hand the player a seventh piece, and one whose fragment did not would strand them.
func restore_searched(names: Array, set_count: int = 0, held: int = 0) -> void:
	for it in _drowned:
		if is_instance_valid(it) and names.has(it.name):
			it.mark_searched_instantly()
			_searched += 1
			_taken += 1
	if _searched >= _drowned.size() and _drowned.size() > 0:
		_apply_emptied()
		_surfaced = true
	if is_instance_valid(_plate):
		_plate.restore(set_count)
		_held = clampi(held, 0, maxi(0, _taken - set_count))
		_plate.set_carried(_held)
		if _held > 0 or set_count > 0:
			_plate.begin_calling()
		if _plate.is_complete():
			_plate_done = true
			if is_instance_valid(_real_seam):
				_real_seam.set_armed(true)
	# ⚠️ DELIBERATELY DOES NOT WRITE THE OBJECTIVE. `GameState.set_objective()` is one global
	# line, and this runs from `backrooms.gd:_restore_progress()` — which then calls
	# `_enter_zone()`, whose job that is. A restore that wrote it here would put a Flood
	# fragment counter on screen for a player standing in the Lobby.


# Opening is not taking (B-R2): this fires on the lid, and nothing depends on it. The
# events below all key on the FRAGMENT count, which is the thing the player has actually
# banked — an object standing open with its fragment still in it is not done.
func _on_item_searched(_item: SunkenItem) -> void:
	_searched += 1


func _on_piece_taken(_item: SunkenItem) -> void:
	_taken += 1
	_held += 1
	if is_instance_valid(_plate):
		_plate.set_carried(_held)
		_plate.begin_calling()
	_refresh_objective()
	if _taken == ANSWER_AT:
		_answering_knock()
	if _taken == SURFACING_AT and not _surfaced:
		_surfacing()
	if _taken >= _drowned.size():
		_the_wing_is_empty()


# BEAT 1 — the answer. One knock from every item still out there, staggered so it reads as
# several separate objects rather than one chord. This is the invitation: without it a
# player who searches the first thing they trip over never learns there is a set.
func _answering_knock() -> void:
	for it in _drowned:
		if is_instance_valid(it) and not it.is_taken:
			it.knock_once(randf_range(0.15, 1.10))


# BEAT 2 — THE SURFACING. Something else in the wing hauls something out of the water, once,
# at 5-13 m, and goes back under.
#
# ⚠️ IT IS `flood_haul` — THE SAME SOUND THE PLAYER HAS JUST MADE THREE TIMES, and that is
# the whole beat. `SCARY.md` P10's stated anchor is *"what you hear in the distance has to be
# audibly the same ACT you are performing"*, and this is the only place in the game where the
# player performs an act distinctive enough to be echoed. Nothing spawns; there is no entity,
# no mesh, no collider, no panic and no second occurrence.
#
# ⚠️ IT IS NOT THE WADER. `UnseenWader` is untouched by this pass — same emitter, same
# `wade_distant` loop, same ≥12 m floor, same two-strides-and-stop rule. This is a separate
# one-shot on the zone itself, and a test asserts the wader's node is not involved.
func _surfacing() -> void:
	_surfaced = true
	if not is_instance_valid(_player):
		return
	var p: Vector3 = _player.global_position
	var best := Vector3.INF
	var best_score := 1e9
	for r in ROOMS:
		var v: Vector2 = r["pos"]
		var c := _origin + Vector3(v.x, WATER_Y + 0.1, v.y)
		var d := c.distance_to(p)
		if d < SURFACE_MIN or d > SURFACE_MAX:
			continue
		# Prefer ~8 m: close enough to be unmistakably in the room next door, far enough
		# that nothing is expected to be standing there.
		var score := absf(d - 8.0)
		if score < best_score:
			best_score = score
			best = c
	if best == Vector3.INF:
		# Nowhere in band (the player is in a corner of the wing): fall back to the farthest
		# room centre, clamped, so the beat always fires rather than silently not happening.
		var far := Vector3.INF
		var far_d := -1.0
		for r in ROOMS:
			var v2: Vector2 = r["pos"]
			var c2 := _origin + Vector3(v2.x, WATER_Y + 0.1, v2.y)
			var d2 := c2.distance_to(p)
			if d2 > far_d:
				far_d = d2
				far = c2
		best = far
	if best == Vector3.INF:
		return
	_play("flood_haul", best - _origin, SURFACE_DB)


# BEAT 3 — the wing is empty. Every knock is gone, the drips halve, and the water beds settle
# for good: the room is measurably quieter than the one the player walked into.
#
# ⚠️ AN ABSENCE CANNOT TEACH ITSELF (the Corridor's Hotel Vesper plate, the most important
# hint in the game). So the last word is one more knock, from nothing, ~3.5 m behind the
# player — the seventh knock in a wing with six objects in it, all of which are now open. It
# is ray-clamped to the first wall behind them so it never originates inside geometry
# (`SCARY.md` P9's fix), it costs nothing, and it never happens again.
func _the_wing_is_empty() -> void:
	if _emptied:
		return
	_apply_emptied()
	if not is_instance_valid(_player):
		return
	var behind := -_player.global_transform.basis.z
	behind.y = 0.0
	if behind.length() < 0.01:
		behind = Vector3(0, 0, 1)
	behind = behind.normalized()
	var from: Vector3 = _player.global_position + Vector3(0, 1.0, 0)
	var to: Vector3 = from - behind * 3.5
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [_player.get_rid()]
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	var at: Vector3 = to
	if not hit.is_empty():
		at = from + (Vector3(hit["position"]) - from) * 0.7
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.finished.connect(func() -> void:
		_play("flood_knock", at - _origin + Vector3(0, -0.6, 0), SunkenItem.KNOCK_DB + 2.0))


func _apply_emptied() -> void:
	_emptied = true
	_drip_range = EMPTIED_DRIP
	for a in _water_beds:
		if is_instance_valid(a):
			var tw := create_tween()
			tw.tween_property(a, "volume_db", a.volume_db - EMPTIED_BED_DROP, 6.0)


# A tide line well above head height in the two rooms that most need a reason to exist: the
# Descent (a 4x8 corridor on the MANDATORY route that was completely empty) and the Throat (an
# empty 4x8 dead end whose only function was holding one apparition).
#
# It says the water was once far deeper than it is now, which is the cheapest possible way to
# make a flooded wing feel like it has a history.
func _build_tide_marks() -> void:
	var tex := "res://assets/textures/level_backrooms/flood_tide_mark.png"
	for spec in [["Descent", Vector2(1, 0)], ["Descent", Vector2(-1, 0)],
			["Throat", Vector2(1, 0)], ["Throat", Vector2(-1, 0)]]:
		var room: String = spec[0]
		var side: Vector2 = spec[1]
		# wall_point() clamps its own minimum clearance (Issue 26), and a flat decal only
		# needs the house-style 0.16.
		var pos: Vector3 = _builder.wall_point(room, side, TIDE_Y, 0.16)
		var quad := MeshInstance3D.new()
		quad.name = "TideMark_%s_%d" % [room, int(side.x)]
		var qm := QuadMesh.new()
		qm.size = Vector2(TIDE_LEN, 0.34)
		quad.mesh = qm
		var m := StandardMaterial3D.new()
		if ResourceLoader.exists(tex):
			m.albedo_texture = load(tex)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		else:
			# Flat-tinted fallback: a dark waterline stain. No emission (Issue 8.8) — it is
			# scenery, and scenery in this level must not out-shine the seam tell.
			m.albedo_color = Color(0.10, 0.12, 0.11)
		m.roughness = 1.0
		quad.set_surface_override_material(0, m)
		quad.position = pos
		# Face into the room: side (1,0) is the east wall, so its decal turns to -x.
		quad.rotation.y = -PI / 2.0 if side.x > 0 else PI / 2.0
		add_child(quad)


func _build_rooms() -> void:
	_builder = RoomBuilder.new()
	_builder.wall_height = ROOM_H
	# Wet concrete rather than wallpaper — this has to read as somewhere else.
	_builder.wall_mat = MazeKit.make_material(
		"res://assets/textures/level_2_house/house_basement_concrete.png",
		Vector2(1.0, 1.0 / 3.0), Color(0.20, 0.21, 0.20))
	_builder.floor_mat = MazeKit.make_material(
		"res://assets/textures/level_1_lab/lab_floor_wet.png",
		Vector2(0.5, 0.5), Color(0.13, 0.14, 0.14))
	_builder.ceil_mat = MazeKit.make_material("", Vector2.ONE, Color(0.10, 0.10, 0.11))
	add_child(_builder)
	_builder.build(ROOMS, DOORS)


func _build_water() -> void:
	# One translucent sheet over the whole footprint. No collider — the wade is a
	# speed penalty applied in _process, not physics.
	var water := MeshInstance3D.new()
	water.name = "Floodwater"
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	water.mesh = pm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.06, 0.09, 0.10, 0.72)
	m.roughness = 0.10
	m.metallic = 0.35
	water.set_surface_override_material(0, m)
	water.position = Vector3(0, WATER_Y, 14.0)
	add_child(water)


# BACKLOG #20: "in the backrooms when you are at the water stage there is no water
# sound. Make it look more realistic like it is indeed the water."
#
# It was right: this zone had NO continuous audio of any kind. The only sound was a
# `water_drip` one-shot every 3-8 s — and that name resolves to the HOUSE CELLAR's
# drip (level_2_house/water_drip.wav), a lone plink in an empty room, which is the
# opposite of standing in it.
#
# Four looping emitters rather than one: AudioStreamPlayer3D attenuates with distance,
# and this wing is ~28 m end to end, so a single source at the centre fades out in the
# rooms furthest from it — the Sump and the Cistern, which is exactly where the player
# spends longest. Placed at the room centres of the four largest chambers so coverage
# is continuous while every position still has a nearest source, which keeps it
# directional rather than a flat wall of noise.
#
# ⚠️ COVERS EVERY ROOM, and the gain is set from the FILE's measured level, not from a
# number that looks reasonable (2026-08-15). Two faults, and together they are why the
# player reported the Flood as having a step-splash but no water:
#
#   * `water.wav` is a very quiet asset — **-39.6 dBFS RMS**, some 20 dB below every other
#     sound in this level (the score is -18.0, `wade_step` -17.1). At the old -6 dB it
#     landed near -46 dBFS: present in the node tree, inaudible in the room. A volume_db
#     that reads as sensible means nothing without the level of the file under it.
#   * `max_db = 0.0` capped it again at close range, which is exactly where a bed the
#     player is standing IN should be loudest. Back to Godot's default.
#
# The four skipped rooms (Landing, Descent, EastRun, WestRun) are the entrance, the whole
# mandatory approach and both digit-note side runs — i.e. most of the walking. Now wet too.
const WATER_BED_ROOMS := ["Landing", "Descent", "Basin", "EastRun", "WestRun",
	"Sump", "Cistern", "Throat"]
const WATER_BED_UNIT := 13.0
const WATER_BED_DB := 14.0     # +14 over a -39.6 dBFS file ≈ -26 dBFS at the emitter
const WATER_BED_MAX_DB := 3.0  # Godot's default; 0.0 clamped the near field

var _water_beds: Array[AudioStreamPlayer3D] = []


func _build_water_audio() -> void:
	var stream := GameState.load_audio("water")
	if not stream:
		return
	for room in WATER_BED_ROOMS:
		var c: Vector3 = _builder.room_center(room)
		var a := AudioStreamPlayer3D.new()
		a.name = "WaterBed_" + room
		a.stream = stream
		a.volume_db = WATER_BED_DB
		a.unit_size = WATER_BED_UNIT
		a.max_db = WATER_BED_MAX_DB
		add_child(a)
		a.position = Vector3(c.x, WATER_Y + 0.2, c.z)
		# ⚠️ Every .wav.import in this project is loop_mode=0, so the node has to
		# restart itself. Canonical form, lifted from level_1.gd:_add_beacon_layer().
		a.finished.connect(a.play)
		# Start each bed at a different point in the same 31.5 s file. Eight coherent
		# copies of one loop comb-filter against each other into something that reads as
		# a synthesizer; offset, they read as one continuous body of water. The offsets
		# persist, because each player re-arms off its OWN finished signal.
		a.play(randf_range(0.0, 20.0))
		_water_beds.append(a)


# Mirror of the above. ⚠️ DISCONNECT BEFORE STOP: `finished` is wired to `play`, so
# stopping a still-connected player makes it emit `finished` and immediately restart
# itself. level_1.gd learned this the hard way with the breaker beacons.
func _free_water_audio() -> void:
	for a in _water_beds:
		if is_instance_valid(a):
			if a.finished.is_connected(a.play):
				a.finished.disconnect(a.play)
			a.stop()
			a.queue_free()
	_water_beds.clear()


func _exit_tree() -> void:
	_free_water_audio()


# BACKLOG #24: KONTUR's roster gate used to answer to "47", which the player already
# knew from the intro note ("You are Subject 47") — so a gate designed to be the one
# whose answer is carried from the first minute of the game was, in practice, the one
# gate nobody had to look for. The code is now KONTUR's own ROSTER_CODE with no other
# source anywhere in the game, and both digits are written down HERE, in the Flood, in
# the same shape the House uses for its lock: one digit per note, deliberately split.
#
# Placement is the point. Both notes are OFF THE MANDATORY ROUTE — the Throat is a dead end
# and EastRun is a side run — so a player who walks the main line from the Descent and takes
# the Sump seam never sees either.
#
# ⚠️ That was only half true until 2026-07-28: note A sat on WestRun, which is the ONLY
# corridor into the Sump (this file says so itself further down, where it explains why two of
# three beartraps were removed from the forced path), so the first digit was unmissable. Fixed
# by moving it to the Throat — see _build_digit_notes().
#
# That is the intent (this
# level is entered before KONTUR, and the whole design of KONTUR is "the answers are
# not inside it"), and it is why the notes journal exists: a player who read them in
# passing can re-read them at the lock instead of walking two levels back.
#
# ⚠️ Both walls are chosen for having NO doorway. EastRun (x 6..12, z 13..17) is
# entered from its west wall and its north wall; WestRun (x -12..-6, z 13..17) from its
# east and north. So the free faces are the outer ones. wall_point() returns the wall
# CENTRE, which is exactly where a doorway sits — hanging a prop on a wall that has one
# silently seals the room (the Records warning-sign bug, CLAUDE.md).
const _NOTE_SCRIPT := preload("res://scripts/note.gd")

const DIGIT_NOTE_A := """KONTUR — INTERNAL. DO NOT COPY.

The personnel gate on sub-level 2 wants the subject number. I keep forgetting it, so I
am writing it where the water will not reach.

The FIRST digit is 6.

I have put the second one on the far side. If they find one of these they still do not
get in."""

const DIGIT_NOTE_B := """...and the SECOND digit is 3.

If you are holding both halves then you have been down here longer than I managed. The
gate is past the kitchen, in records. It does not open twice.

— Ops"""


func _build_digit_notes() -> void:
	# EastRun's east face and WestRun's west face — the two outer walls, both
	# doorway-free. Inset 0.22: wall_point() measures from the room's NOMINAL boundary
	# and the wall's inner face is T/2 (0.1) inside that, so 0.22 leaves ~12 cm of
	# clearance (Issue 26 — at 0.10 a wall prop is exactly coplanar and gets sliced).
	# ⚠️ MOVED 2026-07-28: note A used to be on WestRun's west face, and WestRun is the ONLY
	# corridor into the Sump — so the first digit was UNMISSABLE and only the second was
	# actually hidden. KONTUR's roster gate was rebuilt (BACKLOG #24) precisely so that both
	# digits require having searched this wing; half a code is half a rebuild. It now lives on
	# the Throat's north face, a true dead end reached only by leaving the route.
	#
	# Both walls are still doorway-free: the Throat (x -2..2, z 19..27) is entered from its
	# SOUTH wall only, and EastRun from its west and north.
	_make_note("DigitNote_Throat",
		_builder.wall_point("Throat", Vector2(0, 1), 1.4, 0.22), PI, DIGIT_NOTE_A)
	_make_note("DigitNote_EastRun",
		_builder.wall_point("EastRun", Vector2(1, 0), 1.4, 0.22), -PI / 2.0, DIGIT_NOTE_B)


func _make_note(note_name: String, pos: Vector3, y_rot: float, text: String) -> void:
	var note := StaticBody3D.new()
	note.name = note_name    # findable, and legible in a failing assertion (Issue 17)
	note.set_script(_NOTE_SCRIPT)
	note.note_text = text
	note.is_trap = false
	note.position = pos
	note.rotation.y = y_rot
	add_child(note)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.32, 0.42, 0.01)
	mesh.mesh = bm
	mesh.set_surface_override_material(0, _NOTE_SCRIPT.paper_material(false))
	note.add_child(mesh)
	# Faintly lit. Every other note in the game sits in a room with a lamp; this wing
	# is near-black by design and a wholly unlit page on a dark wall is not "hidden",
	# it is absent. Kept low (Issue 21: emission is most of a surface's colour here).
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.85, 0.85, 0.78)
	glow.light_energy = 0.22
	glow.omni_range = 1.8
	note.add_child(glow)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 0.5, 0.12)
	col.shape = shape
	note.add_child(col)


func _build_seams() -> void:
	# ⚠️ ORIENTATION. GlitchWall puts its walk-into trigger at local -Z. These seams sit
	# on their room's NORTH wall, so the player approaches from -Z and the trigger must
	# stay at -Z: yaw ZERO. A PI yaw (which reads as "turn it to face the room") pushes
	# the trigger to +Z, straight through the wall behind it — the seam then renders
	# perfectly and can never be touched. That shipped, and it made the Flood
	# unwinnable: the only reachable trigger in the zone was a decoy.
	# Same convention as backrooms_zone2.gd: rotation.y = atan2(axis.x, axis.z) with
	# `axis` pointing OUTWARD from the room, which is 0 for a north wall.
	const NORTH_YAW := 0.0

	# The real seam, hidden off the main line in the Sump.
	var c: Vector3 = _builder.room_center("Sump")
	_real_seam = GlitchWall.new()
	_real_seam.name = "FloodSeam"
	add_child(_real_seam)
	_real_seam.setup(Vector2(3.6, 2.6), 2.6, true)
	_real_seam.position = Vector3(c.x, 1.35, c.z + 3.85)
	_real_seam.rotation.y = NORTH_YAW
	_real_seam.touched.connect(_on_seam_touched)
	# ⚠️ THE EXIT DOES NOT EXIST YET (2026-08-17, B-R1). Disarmed means hidden AND not
	# monitoring: hidden alone would leave the trigger live, because `set_seam_visible()`
	# deliberately keeps a dark seam walk-through, and a player who wandered into the Sump
	# early would clear the zone without ever meeting the puzzle. `_on_plate_complete()` is
	# the only thing that arms it, and after that the flashlight rule below owns it exactly
	# as it always did.
	_real_seam.set_armed(false)

	# Two decoys, lit by the inverse rule.
	#
	# The Basin decoy is offset +4 m in x rather than centred: the Basin's north wall
	# carries the Throat doorway at x=0, and a 3.6 m-wide trigger centred there means
	# walking into the Throat at all is scored as a wrong answer, before the player has
	# chosen anything. Wrong guesses should cost; walking down a corridor shouldn't.
	for spec in [["Cistern", 0.0], ["Basin", 4.0]]:
		var rc: Vector3 = _builder.room_center(spec[0])
		var d := GlitchWall.new()
		d.name = "Decoy" + str(spec[0])
		add_child(d)
		d.setup(Vector2(3.6, 2.6), 2.6, false)
		d.position = Vector3(rc.x + float(spec[1]), 1.35, rc.z + 3.85)
		d.rotation.y = NORTH_YAW
		d.touched.connect(_on_seam_touched)
		_decoys.append(d)


func _on_seam_touched(is_real: bool) -> void:
	if is_real:
		cleared.emit()
	else:
		mistake.emit()


func _build_pressure() -> void:
	# Dread only — NO blanket DarkZone.
	#
	# This zone's puzzle requires the flashlight OFF to see the exit seam. A DarkZone
	# charges +3/s for exactly that, and because player.gd's panic resolution is an
	# if/elif chain, the dark branch also SUPPRESSES decay entirely: light off was
	# +5/s with no way down, light on was a frozen bar and an invisible exit. The
	# puzzle and the panic system were fighting each other and the puzzle lost —
	# three playtest deaths inside 10 s, without the mechanic ever being attempted.
	#
	# Dread alone still means no decay and a steady climb, so the room is on a timer;
	# it just no longer punishes the one thing it asks you to do.
	var centre := Vector3(0, ROOM_H / 2.0, 14.0)
	var extent := Vector3(40, ROOM_H, 40)
	MazeKit.zone_box(self, DreadZone.new(), centre, extent, "FloodDread")

	# The one dry place in the level: a raised platform in the Basin with a lamp.
	# Recovery has to exist somewhere or the three-zone run is unsurvivable.
	var bc: Vector3 = _builder.room_center("Basin")
	MazeKit.box(self, "DryPlatform", Vector3(bc.x, 0.22, bc.z),
		Vector3(3.4, 0.44, 3.4),
		MazeKit.make_material("", Vector2.ONE, Color(0.26, 0.25, 0.22)))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.6)
	lamp.light_energy = 1.5
	lamp.omni_range = 7.0
	lamp.position = Vector3(bc.x, 2.2, bc.z)
	add_child(lamp)
	MazeKit.zone_box(self, CalmZone.new(), Vector3(bc.x, 1.2, bc.z),
		Vector3(4.5, 2.4, 4.5), "FloodCalm")

	# ONE beartrap, under the water, in the CISTERN only.
	#
	# There were three, in EastRun/WestRun/Cistern — but EastRun and WestRun are the
	# only corridors to the Sump, so the required route was mined with invisible
	# traps (15 panic each, unrecoverable in a no-decay zone). Both playtest deaths
	# were beartraps on that forced path. A trap the player cannot see, avoid, or
	# recover from is a toll, not a challenge.
	#
	# The Cistern holds a DECOY seam, so it is optional exploration — a trap there
	# punishes chasing the wrong answer, which is a choice the player actually made.
	var cist: Vector3 = _builder.room_center("Cistern")
	var trap := Beartrap.new()
	trap.position = Vector3(cist.x + randf_range(-1.5, 1.5), 0,
		cist.z + randf_range(-1.5, 1.5))
	add_child(trap)

	# A HOLD apparition in the Throat. Fatal by now — the rule was taught in the Lab —
	# but armed through ApparitionDirector.arm(), whose global ledger keeps it
	# survivable in the rare case this is the player's first one.
	var tc: Vector3 = _builder.room_center("Throat")
	var appar := Apparition.spawn(self, Apparition.Rule.HOLD,
		Vector3(tc.x, 0, tc.z), false)
	var trigger := CorridorEvent.new()
	MazeKit.zone_box(self, trigger, Vector3(tc.x, 1.2, tc.z - 3.0),
		Vector3(4.0, 2.4, 1.2), "ThroatEvent")
	trigger.fired.connect(func() -> void:
		if is_instance_valid(appar):
			ApparitionDirector.arm(appar as Apparition)
	)

	# BUG_FIX.md 4.4: a second one in the Sump — the deepest, most remote room (it
	# also holds the real seam), reached only via WestRun. Playtest read the Flood as
	# "nice vibe, not packed enough with action" despite the Throat encounter above,
	# so this doubles the count rather than replacing it. Same non-teach HOLD pattern,
	# verbatim, just relocated; entered from the north (the only doorway into Sump),
	# so the trigger sits 3 m north of centre, just past that threshold.
	var suc: Vector3 = _builder.room_center("Sump")
	var sump_appar := Apparition.spawn(self, Apparition.Rule.HOLD,
		Vector3(suc.x, 0, suc.z), false)
	var sump_trigger := CorridorEvent.new()
	MazeKit.zone_box(self, sump_trigger, Vector3(suc.x, 1.2, suc.z - 3.0),
		Vector3(4.0, 2.4, 1.2), "SumpEvent")
	sump_trigger.fired.connect(func() -> void:
		if is_instance_valid(sump_appar):
			ApparitionDirector.arm(sump_appar as Apparition)
	)


func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	# THE TELL. Seam visibility is inverted against the flashlight: the real one
	# shows in darkness, the decoys show in light. `is_flashlight_on()` returns
	# false for a dead battery too, so a player who burned the light through zones
	# 1 and 2 can still finish — the rule is "not lit", not "toggled off".
	var lit: bool = _player.is_flashlight_on()
	if is_instance_valid(_real_seam):
		_real_seam.set_seam_visible(not lit)
	for d in _decoys:
		if is_instance_valid(d):
			d.set_seam_visible(lit)

	# Wading: refresh the slow every frame while inside the flooded footprint, so
	# it lapses naturally the moment the zone is left.
	var p: Vector3 = _player.global_position
	var local: Vector3 = p - _origin
	var submerged: bool = _in_footprint(local) and p.y < _origin.y + 1.5
	if submerged:
		_player.apply_slow(WADE_SLOW)
		_player.add_panic(DREAD_DRIP * delta)

	# Tell the wader whether the player is wading. It does not sample this itself — the wade
	# footprint test above is the zone's business, and duplicating it would let the two
	# disagree about when the player has stopped, which is the entire beat.
	if is_instance_valid(_wader):
		var moving: bool = submerged and _player.get_horizontal_speed() > 0.35
		_wader.set_player_wading(moving)

	# Drips on top of the bed, for texture. ⚠️ `local` is player-minus-origin, but this
	# node is ALREADY at `origin`, so a child placed at `local` lands at origin+local —
	# i.e. near the player, which is what was wanted, but only by accident of the two
	# errors cancelling. Stated plainly now: place it relative to the player IN LOCAL
	# SPACE, which is what a child of this node needs.
	#
	# ⚠️ GATED ON THE PLAYER BEING IN THIS ZONE (2026-08-15). All three zones are built at
	# level start and this `_process` runs from the first frame, so an ungated drip
	# followed the player into the LOBBY: a wet plink landing beside them every 3-8 s, at
	# -4 dB from a source ~1 m away, in a dry mono-yellow corridor 200 m from any water,
	# for the whole level. Measured in `tests/probe_backrooms_audio.gd` — it was the
	# loudest thing near the player after the phone, and it is the single most likely
	# thing a player means by "a weird sound that shouldn't be there".
	#
	# The gate is the horizontal footprint, NOT `submerged`: the Flood's dry platform is
	# the zone's one CalmZone anchor, and the drips should still be heard from it — it is
	# the y-test, not the room, that ends them.
	# THE DROWNED knock only while the player is actually down here, for the same reason the
	# drips are gated: all three zones are built at level start and this `_process` has been
	# running since the Lobby. `_drip_range` widens permanently once the wing is emptied.
	var in_zone: bool = _in_footprint(local)
	if in_zone != _zone_active:
		_zone_active = in_zone
		for it in _drowned:
			if is_instance_valid(it):
				it.set_zone_active(in_zone)

	_drip_timer -= delta
	if _drip_timer <= 0.0:
		_drip_timer = randf_range(_drip_range.x, _drip_range.y)
		if _in_footprint(local):
			var near_player := Vector3(local.x + randf_range(-6, 6), 2.0, local.z + randf_range(-6, 6))
			_play("water_drip", near_player, -4.0)


# The Flood's horizontal extent, in this node's local space. Shared by the wade test
# (which adds a height test on top) and the drip ticker, so the two cannot drift apart.
func _in_footprint(local: Vector3) -> bool:
	return local.z > -4.0 and local.z < 30.0 and absf(local.x) < 20.0


func _play(base_name: String, pos: Vector3, volume_db: float) -> void:
	var stream := GameState.load_audio(base_name)
	if not stream:
		return
	var a := AudioStreamPlayer3D.new()
	a.stream = stream
	a.volume_db = volume_db
	a.unit_size = 7.0
	add_child(a)
	a.position = pos
	a.finished.connect(a.queue_free)
	a.play()
