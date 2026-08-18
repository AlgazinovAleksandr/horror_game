extends SceneTree

# CEILING FITTINGS ARE NOT BLOWN OUT — **in every level in the game**.
#
#   Godot --headless --path game --script res://tests/check_fixtures.gd
#   Godot --headless --path game --script res://tests/check_fixtures.gd -- House
#
# WHY THIS EXISTS. This project has **no glow, no fog and no tonemapping**, and renders at
# ~0.45 light energy — so a surface's EMISSION outweighs its albedo, and any
# `emission_energy_multiplier` above 1.0 clamps to flat pure white with no detail at all
# (Issue 21). That is not a style question; it is a fitting that stops being a fitting and
# becomes a white rectangle, and it has shipped three times: the Lab breaker panel wearing its
# own art at 0.25 with a lever at 0.7 (Issue 33), the KONTUR roster lock as a glowing mint box
# (Issue 27), and the fittings this file was written for.
#
# ⚠️ IT ASSERTED NOTHING UNTIL 2026-08-17 (workstream H2). It walked the lamps, printed their
# meshes and emission values, and returned without ever calling `quit()` — so it exited 0
# whatever it found, in a suite whose only signals are the exit code and a grep. It was listed
# in `tools/run_tests.sh` as "ceiling fittings are not blown out"; it could not have told you
# if every fitting in the game were at 5.0. It also took a scene argument the runner never
# passed, so it only ever looked at the Lab.
#
# Now: it sweeps `tests/lib/scenes.gd`, asserts the ceiling, asserts its own sample size, and
# carries a control that pushes one real fitting to 3.0 every run and requires it to be caught.

const Scenes := preload("res://tests/lib/scenes.gd")

# ⚠️ 1.0 is the physical ceiling, not a taste threshold: above it the renderer clamps.
const MAX_EMISSION := 1.0

# ---------------------------------------------------------------- the per-scene rows
#
#   min_fittings   how many emissive ceiling meshes this scene must yield
#   allow_energy   [value, count, why] — exactly this many fittings may sit at this
#                  emission above the ceiling. ⚠️ BY VALUE AND COUNT, never by node name:
#                  every fitting in this game is built in code and never named, so Godot
#                  calls them all `@MeshInstance3D@NN` and a name rule matches nothing.
#                  ⚠️ `count` may be [lo, hi] where the number is genuinely stochastic —
#                  see the Backrooms row, whose strip grid has a dead-light chance in it.
#                  An exact count there is not stricter, it is just seed-dependent, and a
#                  guard that goes red when an unrelated RNG draw moves teaches nothing.
#   no_fittings    this level legitimately hangs no lamp-mounted mesh, with the reason
const CONFIG := {
	"SCENE_INTRO": {"min_fittings": 2},
	"SCENE_LEVEL_1": {"min_fittings": 8},
	"SCENE_LEVEL_2": {"min_fittings": 6},
	"SCENE_CORRIDOR": {
		# ⚠️ The Corridor's "fittings" are Torch3D flame cups, which is exactly what this
		# guard should measure: an emissive mesh sitting inside a light is the thing that
		# blows out.
		"min_fittings": 10,
		# ⚠️ FILED, NOT FIXED, and it is a real finding: `torch_3d.gd:59` sets the flame's
		# emission to **3.00**, i.e. three times the clamp — every torch cup in the level
		# renders as flat pure white with no flame detail at all (Issue 21's exact shape).
		# It may well be intended for a FLAME; it is also the only place in the game running
		# 3x the ceiling, and the Corridor is a verified, closed level whose art this pass
		# does not touch. backlogs/03-corridor.md; the count is exact, so a 17th torch or a
		# retune both move it.
		"allow_energy": [3.0, 16, "Torch3D flame cups, filed as a Corridor art finding"],
	},
	"SCENE_BACKROOMS": {
		"min_fittings": 20,
		# ⚠️ DELIBERATE AND DOCUMENTED IN CLAUDE.md: `MazeKit`'s recessed strips run at 1.6,
		# which only survives because they are seen down a corridor and never directly
		# overhead. The COUNT is asserted exactly, so a twenty-eighth fitting drifting into
		# this rule fails rather than joining it.
		# ⚠️ A RANGE, AND THE REASON IS IN THE LEVEL: `_build_lights()` kills ~30 % of the
		# strip grid at random, and since 2026-08-17 it also skips every cell within 11 m of
		# the Sprawl recess holding the crate (B-R3 — "hidden in the dark" is measured, not
		# asserted by hope). Both draws move with the seed, so the count is 22-24 rather than
		# one number. What still bites: anything over the 1.0 ceiling at a DIFFERENT energy
		# is not waived at all, and the per-run control proves the walker still finds them.
		"allow_energy": [1.6, [22, 26],
			"MazeKit light strips, seen down a corridor and never directly overhead"],
	},
	"SCENE_KONTUR": {"min_fittings": 3, "seeds": [7]},
	"SCENE_LEVEL_6_BREACH": {
		# ⚠️ 0 IS A FINDING, NOT A SETTING: the Breach hangs bare `OmniLight3D`s with no
		# housing mesh at all, so there is nothing here for this guard to measure and nothing
		# in the level to look at where the light comes from. backlogs/06-breach.md.
		"no_fittings": "the Breach's lights are bare OmniLights with no fitting mesh",
	},
	# ⚠️ THE NIGHTMARE has no electric light, but it does have the candle flame and the
	# sconces, and those are emissive meshes sitting inside lights — the same thing, and the
	# same failure mode.
	"SCENE_DUNGEON": {"min_fittings": 1, "seeds": [1]},
	"SCENE_LEVEL_3": {
		"min_fittings": 1,
		# ⚠️ FILED, NOT FIXED — the Void has not had its level pass. Its two candle flames
		# run at 1.50, half again over the clamp, so both render as flat white blobs in the
		# level's ONLY recovery anchor (Room A's CalmZone is lit by exactly these two).
		# backlogs/08-void.md.
		"allow_energy": [1.5, 2, "the two Room A candle flames — filed as a Void art finding"],
	},
}

var _rows: Array = []
var _row := 0
var _t := 0.0
var _checks := 0
var _fails: Array[String] = []
var _summary: Array = []
var _only := ""
var _stage := "measure"
var _control: MeshInstance3D = null
var _control_mat: StandardMaterial3D = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if not a.begins_with("--"):
			_only = a
	for p in Scenes.problems():
		print("  FAIL enrolment: %s" % p)
		_fails.append("enrolment: " + String(p))
	for row in Scenes.levels():
		if _only != "" and String(row["label"]).to_lower().find(_only.to_lower()) < 0:
			continue
		var cfg: Dictionary = (CONFIG.get(row["key"], {}) as Dictionary).duplicate(true)
		cfg["label"] = String(row["label"])
		cfg["path"] = String(row["path"])
		cfg["settle"] = float(row["settle"])
		for sd in cfg.get("seeds", [1]):
			var one := cfg.duplicate(true)
			one["seed"] = int(sd)
			_rows.append(one)
	if _rows.is_empty():
		print("FIXTURES FAIL: no scene matched %s" % _only)
		quit(1)
		return
	_load_row()


func _load_row() -> void:
	_t = 0.0
	_stage = "measure"
	_control = null
	_control_mat = null
	Scenes.pin_rng(int(_rows[_row]["seed"]))
	change_scene_to_file(String(_rows[_row]["path"]))


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _process(delta: float) -> bool:
	_t += delta
	var cfg: Dictionary = _rows[_row]
	if _stage == "measure":
		if _t < float(cfg["settle"]):
			return false
		_measure(cfg)
		if _control == null:
			return _advance()
		_stage = "control"
		_t = 0.0
		return false
	_control_check(cfg)
	return _advance()


func _advance() -> bool:
	_row += 1
	if _row < _rows.size():
		_load_row()
		return false
	print("")
	print("--- FIXTURE SWEEP: %d scene-run(s) ---" % _rows.size())
	for line in _summary:
		print("  " + line)
	print("%d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("FIXTURES PASS")
		quit(0)
	else:
		for f in _fails:
			print("  FAIL: " + f)
		print("FIXTURES FAIL")
		quit(1)
	return true


# Every emissive mesh that is part of a light fitting, as [node, material, emission].
#
# ⚠️ NEAR a light, not UNDER one. The Lab parents its fitting mesh to the `OmniLight3D` and
# the original version of this file walked exactly that; KONTUR, the Breach, the Backrooms and
# the Intro all add the lamp and its housing as SIBLINGS, so a parent-only walk found ZERO
# fittings in four levels and reported nothing wrong with any of them. Proximity covers both
# conventions and cannot be got wrong by a future level built the third way.
const FITTING_RADIUS := 0.8

func _fittings() -> Array:
	var lights: Array[Vector3] = []
	var meshes: Array = []
	for n in _all(current_scene, []):
		if n is Light3D:
			lights.append((n as Light3D).global_position)
		elif n is MeshInstance3D:
			var mi: MeshInstance3D = n
			var mat: Material = mi.get_surface_override_material(0)
			if mat == null:
				mat = mi.material_override
			if not (mat is StandardMaterial3D):
				continue
			var std := mat as StandardMaterial3D
			if not std.emission_enabled:
				continue
			meshes.append([mi, std])
	var out: Array = []
	for m in meshes:
		var mi: MeshInstance3D = m[0]
		for lp in lights:
			if mi.global_position.distance_to(lp) <= FITTING_RADIUS:
				out.append([mi, m[1], float((m[1] as StandardMaterial3D)
					.emission_energy_multiplier)])
				break
	return out


func _all(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children():
		_all(c, out)
	return out


func _measure(cfg: Dictionary) -> void:
	print("")
	print("--- ceiling fittings: %s (%s, seed %d) ---"
		% [cfg["label"], cfg["path"], int(cfg["seed"])])
	var fittings := _fittings()
	var no_fit: String = String(cfg.get("no_fittings", ""))
	if no_fit != "":
		# ⚠️ Asserted, not assumed: a level that GAINS a fitting must lose this row rather
		# than keep a waiver written when it had none.
		_ok("%s legitimately has no emissive ceiling fittings" % cfg["label"],
			fittings.is_empty(), no_fit)
		_summary.append("%-10s seed %-4d not applicable — %s"
			% [cfg["label"], int(cfg["seed"]), no_fit])
		return

	_ok("%s: found fittings to measure" % cfg["label"],
		fittings.size() >= int(cfg.get("min_fittings", 1)),
		"%d fittings, minimum %d" % [fittings.size(), int(cfg.get("min_fittings", 1))])

	var allow: Array = cfg.get("allow_energy", [])
	var allow_e: float = float(allow[0]) if not allow.is_empty() else -1.0
	var allowed := 0
	var hot := 0
	for f in fittings:
		var mi: MeshInstance3D = f[0]
		var e: float = f[2]
		if allow_e > 0.0 and absf(e - allow_e) < 0.01:
			allowed += 1
			continue
		if e > MAX_EMISSION:
			hot += 1
			_ok("%s: %s is not blown out" % [cfg["label"], mi.name], false,
				"emission %.2f, ceiling %.2f (above 1.0 clamps to flat white)"
					% [e, MAX_EMISSION])
	if not allow.is_empty():
		var want = allow[1]
		var lo: int = int(want[0]) if want is Array else int(want)
		var hi: int = int(want[1]) if want is Array else int(want)
		_ok("%s: exactly the documented over-bright fittings, no more" % cfg["label"],
			allowed >= lo and allowed <= hi,
			"%d at %.2f, expected %s — %s"
				% [allowed, allow_e,
					("%d-%d" % [lo, hi]) if lo != hi else ("exactly %d" % lo), allow[2]])
	_summary.append("%-10s seed %-4d %d fittings, %d waived, %d over the ceiling"
		% [cfg["label"], int(cfg["seed"]), fittings.size(), allowed, hot])

	# ⚠️ THE CONTROL, on the scene under test, every run: push a REAL fitting to 3.0 and
	# require the same pass to call it out. A walker that stopped finding fittings — a
	# renamed node, a material moved to `material_override`, a light no longer parenting its
	# mesh — would otherwise report "0 blown out" forever.
	# ⚠️ 5.0, and ANY fitting — including a waived one. In the Corridor every fitting is
	# waived (all sixteen torches run at 3.0), so a control that insisted on an unwaived one
	# had nothing to push and the level's only proof of life went missing exactly where the
	# real finding is.
	for f in fittings:
		_control = f[0]
		_control_mat = f[1]
		# ⚠️ A NEW MATERIAL IN THE MESH'S OWN OVERRIDE SLOT, not a write into the material the
		# LEVEL holds. `level_1.gd`'s blackout stutter and `_restore_power()` both drive
		# `emission_energy_multiplier` on their stored material every frame, so the control's
		# 3.0 was overwritten before it could be read — measured, it reported "not caught" on
		# the Lab and the House while working perfectly on the Intro, which has no such tween.
		var hot_mat: StandardMaterial3D = _control_mat.duplicate() as StandardMaterial3D
		hot_mat.emission_energy_multiplier = 5.0
		_control.set_surface_override_material(0, hot_mat)
		break
	if _control == null and not fittings.is_empty():
		_ok("%s CONTROL: a non-waived fitting exists to push" % cfg["label"], false)


func _control_check(cfg: Dictionary) -> void:
	var allow: Array = cfg.get("allow_energy", [])
	var allow_e: float = float(allow[0]) if not allow.is_empty() else -1.0
	var found := false
	for f in _fittings():
		if f[0] != _control:
			continue
		var e: float = float(f[2])
		if e > MAX_EMISSION and (allow_e < 0.0 or absf(e - allow_e) > 0.01):
			found = true
	_ok("%s CONTROL: a fitting pushed to 5.0 IS reported" % cfg["label"], found,
		"%s" % (_control.name if is_instance_valid(_control) else "-"))
	if is_instance_valid(_control) and _control_mat != null:
		_control.set_surface_override_material(0, _control_mat)


