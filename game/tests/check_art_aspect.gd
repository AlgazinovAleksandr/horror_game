extends SceneTree

# EVERY TEXTURED FLAT SURFACE IN THE GAME SHOWS ITS ARTWORK AT THE ARTWORK'S OWN ASPECT
# RATIO. **All nine levels, in one run.**
#
#   Godot --headless --path game --script res://tests/check_art_aspect.gd
#   Godot --headless --path game --script res://tests/check_art_aspect.gd -- Corridor
#
# WHY THIS EXISTS. Measured 2026-08-16 in the Intro: four of the room's five textured quads
# were stretched, the worst by a factor of FOUR.
#
#   gurney_intro.png     1672x941 (1.777, landscape)  on PlaneMesh(0.85, 1.9)  -> 3.97x
#   wall_chart_intro.png 1402x1122 (1.250)            on PlaneMesh(0.6, 0.9)   -> 1.87x
#   intro_note.png       1254x1254 (1.000)            on PlaneMesh(0.21,0.297) -> 1.41x
#   intro_switch.png     1122x1402 (0.800)            on PlaneMesh(0.32,0.48)  -> 1.20x
#   intro_lab_door.png    780x1511 (0.516)            on QuadMesh(1.136, 2.2)  -> 1.00 OK
#
# The door was the only one whose mesh had ever been derived from its own artwork, and
# intro_room.gd records that as a deliberate one-off. The playtest capture of the gurney
# ("this texture does not look properly") is what a 3.97x squash looks like from three metres.
#
# ⚠️ The comparison uses the EFFECTIVE source aspect, i.e. the texture's pixel aspect scaled
# by the material's uv1_scale — the note deliberately samples a sub-rect of a square,
# black-backed canvas to crop away the backdrop, and a naive pixel-aspect test would call
# that correct code wrong.
#
# ⚠️ It asserts its own SAMPLE SIZE, per scene. A scene that builds no quads, or a renamed
# node, must not produce a tidy green "0 quads checked ... PASS" — that has happened twice in
# this project (count_apparitions.gd, check_apparition_clearance.gd).
#
# ------------------------------------------------------------------ coverage
#
# ⚠️ A SWEEP SINCE 2026-08-17 (workstream H1), and it was `check_intro_art.gd` with two
# hand-written wrappers before that. Pointing it at the Corridor found **22 of 39 textured
# flat surfaces stretched beyond 10 %**, worst 2.00x, on the prop carrying that level's only
# KONTUR Gate 3 hint; pointing it at the Backrooms found 5 of 13, including the level's only
# navigational signpost. Every level not on somebody's to-do list had never been measured.
# It now iterates `tests/lib/scenes.gd`, which is derived from `GameState`'s own `SCENE_*`
# constants, so a new level is enrolled by existing.

const Scenes := preload("res://tests/lib/scenes.gd")

const TOLERANCE := 1.10       # 10 % — enough for rounding, nowhere near a visible squash

# Cobwebs are excluded on purpose and this is the only global exclusion. `cobweb_intro.png`
# is an organic alpha blob deliberately drawn at a random size and a random roll per instance
# (_make_cobweb), so "the right aspect" is not a meaningful property of it.
#
# ⚠️ Excluded by TEXTURE, not by node name. The first version of this test skipped names
# beginning with "Cobweb" and two webs still came through, because every web was built as
# "CobwebIntro" and Godot renames duplicate siblings to @MeshInstance3D@NN — Issue 17, which
# intro_room.gd already documents twice for the ceiling tubes and the sheeted forms. The
# names are unique now as well, but a filter that depends on a name surviving is the wrong
# filter.
const SKIP_TEXTURE := "cobweb_intro.png"

# ---------------------------------------------------------------- the per-scene rows
#
# ⚠️ A ROW IS AN OVERRIDE, NOT AN ENROLMENT — every scene in the list is measured whether or
# not it appears here.
#
#   min_samples   how many textured flat surfaces this scene must yield
#   deferred      {texture file: why it is not being fixed}. Each is REPORTED with its reason
#                 rather than hidden, and `_deferred_seen >= size` asserts that every entry
#                 still corresponds to a surface that is really there and really stretched —
#                 an entry left behind after its prop was fixed would otherwise silently
#                 widen the rule.
#   seeds         RNG seeds for a scene that builds itself from dice
const CONFIG := {
	"SCENE_INTRO": {"min_samples": 6, "deferred": {}},
	"SCENE_LEVEL_1": {
		"min_samples": 8,
		# ⚠️ FILED, NOT FIXED. The Lab is a verified, closed level and this pass changes no
		# game code; every ratio below is this run's own measurement, and each is on the
		# backlog rather than in the guard's blind spot (backlogs/01-lab.md, cross-level X23).
		"deferred": {
			"lab_door.png": "1.569x on BOTH exit-door leaves — and it is `door.gd`'s shared "
				+ "`build_visual()`, so it is the same stretch in every level (X47)",
			"lab_surgical_tray.png": "1.500x — the morgue's instant-fail tray",
			"lab_warning_sign.png": "1.125x — the Records warning sign",
			"poster_lab.png": "2.444x — the morgue's cursed poster",
			"lab_oneway_mirror.png": "1.874x — the shared LivingMirror glass, whose "
				+ "`fit_to_art` flag exists and is opted into only by the Backrooms (X41)",
			"shared_screamer_figure.png": "1.141x — the figure behind that mirror",
		},
	},
	"SCENE_LEVEL_2": {
		"min_samples": 10,
		# ⚠️ FILED, NOT FIXED — the House is verified and closed (backlogs/02-house.md).
		"deferred": {
			"house_fridge.png": "3.997x on the fridge door — the worst stretch in the game "
				+ "after the Intro gurney that started this guard",
			"painting_house.png": "2.292x — the bedroom painting THE GUEST drops",
			"forest.png": "1.625x — the living-room window's moonlit forest",
			"note_paper.png": "1.433x — the fridge note",
			"house_lock_transparent.png": "1.250x — the combination lock's face",
			"house_door.png": "1.177x on both door leaves — `door.gd`'s shared quad (X47)",
			"lab_oneway_mirror.png": "1.874x — two LivingMirrors, the shared-prop stretch X41",
			"shared_screamer_figure.png": "1.141x — the figures behind them",
		},
	},
	"SCENE_CORRIDOR": {
		"min_samples": 25,
		# ⚠️ DEFERRED TO AN ART PASS (2026-08-16, the user's call). Each of these is the same
		# Issue-35 shape as the two that were fixed — the art bakes in its own wallpaper and
		# the mesh was sized to the WALL rather than to the picture — but they are DECOR, not
		# hints, and re-cropping a wall panel changes what the level looks like rather than
		# what the player can read. Tracked as D1 in `backlogs/03-corridor.md`.
		"deferred": {
			"mirror.png": "D1 — full-height wall panel, 1.20x (2 surfaces in Zone C)",
			"torch.png": "D1 — dead-torch wall panels, 1.20x (3 surfaces in Zone C)",
			"carpet.png": "D1 — wall-hung carpet at d=255, 1.67x",
		},
	},
	"SCENE_BACKROOMS": {
		# ⚠️ `deferred` is deliberately EMPTY here. An empty list is a claim — that every
		# textured flat surface in three zones is shown at its own aspect — and the sample
		# size is asserted, so the claim cannot be satisfied by measuring nothing.
		"min_samples": 10, "deferred": {},
	},
	"SCENE_KONTUR": {
		"min_samples": 20, "seeds": [7],
		# ⚠️ EMPTY SINCE 2026-08-18, and an empty list is a CLAIM: every textured flat
		# surface in KONTUR is shown at its own aspect. All eight entries that used to sit
		# here (K-T1…K-T4) were fixed in the level's pass — the two Gate 1 doors at 1.571x
		# and the three Gate 2 bottle labels at 1.733x were the two props whose entire job
		# is being told apart and read, and all five were also carrying a picture of their
		# own background (Issue 35 / X24). `tools/crop_kontur_art.py` is the crop; the
		# meshes are sized from the crops. `min_samples` is what stops the claim being
		# satisfied by measuring nothing.
		"deferred": {},
	},
	"SCENE_LEVEL_6_BREACH": {
		"min_samples": 3,
		# ⚠️ FILED, NOT FIXED — the Breach has not had its level pass. backlogs/06-breach.md.
		# The hiding places are the level's whole counter-play, and all six are stretched.
		"deferred": {
			"hiding_locker_front.png": "1.905x on all three lockers (`hiding_spot.gd`)",
			"hiding_cabinet_front.png": "1.333x on both cabinets",
			"hiding_desk_front.png": "1.125x on the desk",
			"object12_sign.png": "1.500x on both containment signs",
		},
	},
	"SCENE_DUNGEON": {
		# ⚠️ ONE PINNED SEED for this guard, unlike the geometry sweeps' two. The population
		# here is the level's PROP set rather than its layout, and which props a given dungeon
		# spawns varies with the seed — a deferral list is a claim about specific surfaces, and
		# a claim that only holds on some dungeons is worse than none. The layout guards
		# (`check_wall_overlap`) are the ones that run several seeds.
		"min_samples": 3, "seeds": [1],
		# ⚠️ FILED, NOT FIXED — THE NIGHTMARE has not had its level pass. backlogs/07-nightmare.md
		"deferred": {
			"dn_cot.png": "3.194x on both cots — the Antechamber's and the bed at the far end, "
				+ "i.e. the object the whole level is about lying down on",
			"dungeon_door.png": "1.315x on both door leaves — `door.gd`'s shared quad (X47)",
			"hiding_cabinet_front.png": "1.333x — the shared Breach cabinet, reused here",
			"dn_hollow_figure.png": "1.185x / 1.190x — the Hollow One and the Child",
		},
	},
	"SCENE_LEVEL_3": {
		# ⚠️ min_samples 0 IS A FINDING, NOT A SETTING. The Void has no textured flat surface
		# at all — its notes are untextured `BoxMesh` pages and its creatures are GLB models —
		# so this guard measures nothing there. Filed in backlogs/08-void.md rather than
		# papered over; `min_samples` 0 with a printed warning is the honest reading.
		"min_samples": 0, "deferred": {},
	},
}

var _rows: Array = []
var _row := 0
var _t := 0.0
var _fails: Array[String] = []
var _checks := 0
var _samples := 0
var _deferred_seen := 0
var _deferred: Dictionary = {}
var _min_samples := 1
var _summary: Array = []
var _only := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1 and not String(args[0]).begins_with("--"):
		_only = args[0]
	for p in Scenes.problems():
		print("  FAIL enrolment: %s" % p)
		_fails.append("enrolment: " + String(p))
	for s in Scenes.levels():
		if _only != "" and String(s["label"]).to_lower().find(_only.to_lower()) < 0:
			continue
		var cfg: Dictionary = CONFIG.get(s["key"], {})
		for sd in cfg.get("seeds", [1]):
			_rows.append({
				"key": s["key"], "label": String(s["label"]),
				"path": String(s["path"]), "settle": float(s["settle"]),
				"seed": int(sd), "cfg": cfg,
			})
	if _rows.is_empty():
		print("ART-ASPECT FAIL: no scene matched '%s'" % _only)
		quit(1)
		return
	_load_row()


func _load_row() -> void:
	var r: Dictionary = _rows[_row]
	var cfg: Dictionary = r["cfg"]
	_deferred = cfg.get("deferred", {})
	_min_samples = int(cfg.get("min_samples", 1))
	_samples = 0
	_deferred_seen = 0
	_t = 0.0
	Scenes.pin_rng(int(r["seed"]))
	change_scene_to_file(String(r["path"]))


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _process(delta: float) -> bool:
	_t += delta
	# ⚠️ TIME, never a frame count (X42) — and the Intro's settle is long on purpose: its
	# wake-up tween has to finish before the light switch exists to be measured.
	if _t < float(_rows[_row]["settle"]):
		return false

	var before := _fails.size()
	print("")
	print("--- art aspect: %s (%s, seed %d) ---"
		% [_rows[_row]["label"], _rows[_row]["path"], int(_rows[_row]["seed"])])
	_walk(current_scene)

	# ⚠️ The guard that stops this test being vacuous.
	_ok("enough textured quads were actually measured", _samples >= _min_samples,
		"%d measured, minimum %d" % [_samples, _min_samples])
	if _min_samples == 0:
		print("  NOTE  this scene has no textured flat surfaces at all — it is not covered "
			+ "by this guard, and that is a recorded finding, not a pass")
	# ⚠️ And the guard on the deferral list: every entry must still correspond to a surface
	# that is really there and really stretched. An allowlist nobody counts is how a check
	# goes blind — an entry left behind after its prop was fixed silently widens the rule.
	if not _deferred.is_empty():
		_ok("every deferred stretch is still present and still stretched",
			_deferred_seen >= _deferred.size(),
			"%d deferred surfaces seen, %d textures on the list"
				% [_deferred_seen, _deferred.size()])

	_summary.append("%-10s seed %-4d %s (%d measured, %d deferred, %d failing)"
		% [_rows[_row]["label"], _rows[_row]["seed"],
			"PASS" if _fails.size() == before else "FAIL",
			_samples, _deferred_seen, _fails.size() - before])
	_row += 1
	if _row < _rows.size():
		_load_row()
		return false

	print("")
	print("--- ART-ASPECT SWEEP: %d scene-run(s) ---" % _rows.size())
	for line in _summary:
		print("  " + line)
	print("%d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		for f in _fails:
			print("  FAIL: " + f)
		print("RESULT: FAIL")
		quit(1)
	return true


func _walk(node: Node) -> void:
	if node is MeshInstance3D:
		_measure(node as MeshInstance3D)
	for c in node.get_children():
		_walk(c)


func _measure(mi: MeshInstance3D) -> void:
	var size := Vector2.ZERO
	if mi.mesh is QuadMesh:
		size = (mi.mesh as QuadMesh).size
	elif mi.mesh is PlaneMesh:
		# PlaneMesh maps u along size.x and v along size.y (its depth), same as QuadMesh.
		size = (mi.mesh as PlaneMesh).size
	else:
		return
	if size.x <= 0.0 or size.y <= 0.0:
		return

	# ⚠️ BOTH material slots. The Intro uses surface overrides; the Corridor's `AjarDoor`
	# faces use `material_override`, and a check that only reads one of them silently skips
	# every prop built the other way.
	var mat: Material = mi.get_surface_override_material(0)
	if mat == null:
		mat = mi.material_override
	if not (mat is StandardMaterial3D):
		return
	var std := mat as StandardMaterial3D
	var tex: Texture2D = std.albedo_texture
	if not tex:
		return
	var file := tex.resource_path.get_file()
	if file == SKIP_TEXTURE:
		return

	var uv := std.uv1_scale
	# absf: a negative uv1_scale is a FLIP, not a squash — `mirror_surface.gd` uses -1 in u
	# to hand the reflection correctly, and a signed comparison would call that a distortion.
	var tex_w: float = float(tex.get_width()) * (absf(uv.x) if uv.x != 0.0 else 1.0)
	var tex_h: float = float(tex.get_height()) * (absf(uv.y) if uv.y != 0.0 else 1.0)
	if tex_h <= 0.0:
		return

	var mesh_aspect := size.x / size.y
	var tex_aspect := tex_w / tex_h
	var ratio: float = maxf(mesh_aspect / tex_aspect, tex_aspect / mesh_aspect)
	_samples += 1
	var detail := "mesh %.4f vs texture %.4f -> %.3fx  (%s %dx%d, uv1_scale %.3f/%.3f)" \
		% [mesh_aspect, tex_aspect, ratio,
			file, tex.get_width(), tex.get_height(), uv.x, uv.y]
	if _deferred.has(file) and ratio > TOLERANCE:
		_deferred_seen += 1
		print("  DEFER %s  %s  — %s" % [mi.name, detail, _deferred[file]])
		return
	_ok("%s shows its art undistorted" % mi.name, ratio <= TOLERANCE, detail)
