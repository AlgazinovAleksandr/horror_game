extends RefCounted

# THE ONE SCENE LIST. Every scene-parameterised guard iterates this, and it is DERIVED from
# `GameState`'s own `SCENE_*` constants rather than hand-maintained.
#
#   const Scenes := preload("res://tests/lib/scenes.gd")
#   for s in Scenes.levels():
#       ... s["key"], s["label"], s["path"], s["settle"]
#
# WHY THIS EXISTS (workstream H1, backlogs/00-test-hardening.md). Enrolling a level in a
# geometry guard used to mean remembering to write a three-line wrapper, and that was
# forgotten EVERY SINGLE TIME it was possible to forget it: `check_wall_overlap.gd` and
# `check_note_mounting.gd` were pinned to `level_1.tscn` for their entire lives — two guards
# for "do two surfaces coincide" and "is this prop on a wall", running on one level out of
# nine. The first run against the Corridor produced 32 findings and against the Backrooms 23.
#
# So: adding a level to `GameState` now enrols it in every sweep automatically, and if it is
# NOT a level (the menu, the ending redirector) the omission has to be written down here or
# `problems()` goes red. There is no wrapper to remember, and no way to forget.
#
# ⚠️ NO `class_name`, deliberately (cross-level X29). A `class_name` referenced from a
# `--script` SceneTree tool compiles that script before the autoloads exist; if it touches
# `GameState` at class scope the compile fails, the constructor throws once per call, and the
# thing under test is built WRONG while the test still passes. `preload()` a plain script
# instead — this file references nothing global.

const GAME_STATE_SCRIPT := "res://scripts/game_state.gd"

# ⚠️ EVERY `SCENE_*` CONSTANT IN `game_state.gd` MUST APPEAR IN `META` OR IN `NOT_A_LEVEL`,
# and `problems()` asserts exactly that. A new scene constant with no row here fails every
# sweep until it is classified — which is the whole point: the failure mode being designed
# out is "nobody remembered to enrol the new level".
const NOT_A_LEVEL := {
	"SCENE_MAIN_MENU":
		"the menu — no world, no player, nothing a geometry guard can measure",
	# ⚠️ `ending.gd` waits 1 s and then CHANGES SCENE on its own. A sweep that loaded it would
	# find itself measuring the corrupted intro room a moment later, under the ending's name.
	"SCENE_ENDING":
		"a 1 s redirector into the corrupted intro room; it changes scene out from under a "
		+ "sweep, and its geometry IS the Intro's",
}

# Per-scene facts that cannot be derived from the constant name. Everything else a guard
# needs — the level script, the room tables, the props — it reads off the loaded scene.
#
#   label   : what a report calls it
#   settle  : seconds to wait after load before querying physics. ⚠️ CSG colliders are not
#             registered during `_ready()` (Issue 52) and every level here builds itself
#             there, so a guard that queries too early measures an empty world and reports
#             the level as a hole. Never a frame count: headless runs uncapped, so a frame
#             count measures the machine (cross-level X42).
#   random  : this scene rolls dice at build time, so a guard that asserts exact counts must
#             pin the RNG (see `pin_rng`) and say which seeds it used.
const META := {
	"SCENE_INTRO":          {"label": "Intro",     "settle": 2.6, "random": false},
	"SCENE_LEVEL_1":        {"label": "Lab",       "settle": 1.4, "random": false},
	"SCENE_LEVEL_2":        {"label": "House",     "settle": 1.4, "random": false},
	"SCENE_CORRIDOR":       {"label": "Corridor",  "settle": 1.4, "random": false},
	# The three zones are built at 0 / +200 x / -200 x in ONE scene, and the arm assignment
	# is re-rolled per round.
	"SCENE_BACKROOMS":      {"label": "Backrooms", "settle": 1.6, "random": true},
	# `_dark_x` (three spine offsets) and which vestibule door is black are rolled in
	# `_build_geometry()` / `_spawn_gate1_doors()`, and the red door DELETES a floor.
	"SCENE_KONTUR":         {"label": "KONTUR",    "settle": 1.4, "random": true},
	"SCENE_LEVEL_6_BREACH": {"label": "Breach",    "settle": 1.4, "random": false},
	# The whole dungeon is regenerated on every load from `randi()` seeds.
	"SCENE_DUNGEON":        {"label": "Nightmare", "settle": 1.8, "random": true},
	"SCENE_LEVEL_3":        {"label": "Void",      "settle": 1.4, "random": false},
}


# The playable scenes, in `GameState`'s own declaration order — which is level order, and is
# asserted to be by `problems()` via the intro-first / void-last check below.
static func levels() -> Array:
	var out: Array = []
	var i := 0
	for key in _scene_consts():
		if NOT_A_LEVEL.has(key):
			continue
		if not META.has(key):
			continue        # reported by problems(); skipped rather than crashing the sweep
		var m: Dictionary = META[key]
		out.append({
			"key": key,
			"label": String(m["label"]),
			"path": String(_scene_consts()[key]),
			"settle": float(m["settle"]),
			"random": bool(m["random"]),
			"order": i,
		})
		i += 1
	return out


# Everything wrong with the enrolment, as human sentences. A sweep prints these and fails.
static func problems() -> Array:
	var out: Array = []
	var consts := _scene_consts()
	if consts.is_empty():
		out.append("read no SCENE_* constants from %s — did it fail to parse?"
			% GAME_STATE_SCRIPT)
		return out
	for key in consts:
		if not META.has(key) and not NOT_A_LEVEL.has(key):
			out.append("%s exists in game_state.gd and is in neither META nor NOT_A_LEVEL "
				% key + "in tests/lib/scenes.gd — classify it, or every sweep skips it")
	for key in META:
		if not consts.has(key):
			out.append("%s is in META but no longer exists in game_state.gd" % key)
	for key in NOT_A_LEVEL:
		if not consts.has(key):
			out.append("%s is in NOT_A_LEVEL but no longer exists in game_state.gd" % key)
	for row in levels():
		if not ResourceLoader.exists(String(row["path"])):
			out.append("%s -> %s does not exist" % [row["key"], row["path"]])
	return out


# `key` -> scene path, in declaration order. ⚠️ `get_script_constant_map()`, not `get()`:
# Object.get() reads PROPERTIES and returns null for a const (Issue 54).
static func _scene_consts() -> Dictionary:
	var out: Dictionary = {}
	var gs: GDScript = load(GAME_STATE_SCRIPT)
	if gs == null:
		return out
	for key in gs.get_script_constant_map():
		if String(key).begins_with("SCENE_"):
			out[key] = gs.get_script_constant_map()[key]
	return out


# Pin the global RNG so a `random` scene builds the same world twice.
#
# ⚠️ This works because NOTHING in `game/scripts` calls `randomize()` — verified by grep, and
# it is the only reason a level whose geometry is chosen by `randi()` can be asserted with an
# exact count at all. `dungeon.gd` also takes `--dungeon-seed`, but `tools/run_tests.sh` has
# no per-test argument mechanism, and needing one is exactly what put six levels outside
# every geometry guard for a year. Seeding the engine RNG needs no argument and covers
# KONTUR's `_dark_x`, the gate-1 colour and the Backrooms' arm assignment at the same time.
static func pin_rng(n: int) -> void:
	seed(n)
