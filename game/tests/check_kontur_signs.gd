extends SceneTree

# THE EIGHT REDACTED SIGNS ARE READABLE FROM THE WALKING LINE, AND STILL REDACTED —
# AND THE NINTH DOCUMENT, THE BRIEFING NOTICE, IS READABLE AND SAYS NOTHING USEFUL.
#
#   Godot --headless --path game --script res://tests/check_kontur_signs.gd
#
# WHY THIS EXISTS. These plates are the only in-level help KONTUR has: every gate's rule
# is on one of them with the operative word censored. Until 2026-08-18 they were engine
# `Label3D` text over a blank enamel rectangle, sized by eye; they are now generated
# printed notices (`tools/make_kontur_signs.py`). Both halves of "a redacted sign" are
# assertable and neither had ever been asserted:
#
#   LEGIBLE   the rule's ink has to subtend enough SCREEN PIXELS from where a player
#             actually walks. Measured, not eyeballed — the texture is sampled to find
#             the real height of the rule's ink, that height is converted to metres
#             through the quad, and then to pixels through the camera's own FOV and the
#             viewport height at the sign's distance from its room's walking line.
#   REDACTED  the censor bar has to be present, dark, and wide enough to be a removed
#             word rather than an underline.
#
# ⚠️ IT MEASURES THE IMAGE, NOT A CONSTANT SHARED WITH THE GENERATOR. A test that read the
# generator's own font size would agree with it by construction and prove nothing; this
# one finds ink by thresholding rows of the actual imported texture. If somebody halves
# the type size, this goes red without anybody editing it.
#
# THE BRIEFING NOTICE (added 2026-08-18 with the item it guards). `kontur.gd` now hangs ONE
# unredacted document in the spawn room, stating the level's own design rule as a principle:
# the answers were issued before you got here. Three things have to be true of it and all
# three are asserted, because the first two are what make it worth having and the third is
# what makes it legal:
#
#   EARLY      it is inside the Landing, i.e. before Gate 1 — a statement that reframes the
#              level in hindsight is worth much less than one that reframes it in advance.
#   LEGIBLE    same measurement as the signs, at the distance from the player's own SPAWN,
#              which is the hardest honest reading distance and the level's first frame.
#   EMPTY      it names no gate answer, no earlier level, and no room in this one. This is
#              the constraint the whole item lives under ("a principle, never a place") and
#              a keyword scan is crude, but it is falsifiable and it is checked in the one
#              place the wording can drift.
#
# ⚠️ THE KEYWORD LIST IS TYPED BY HAND ON PURPOSE, and that is the honest thing to say about
# it: the eight gate answers are deliberately stored NOWHERE in this level (that is the
# level's whole design), so there is nothing to derive them from. The room names ARE derived,
# from the scene's own `ROOMS` constant. Two positive controls prove the scan can fire.
#
# ⚠️ AND IT COVERS THE ARTWORK BY CONTAINMENT, not by reading pixels. The three words printed
# on the plate — "YOU WERE BRIEFED ELSEWHERE." — appear verbatim inside `note_text`, and that
# containment is asserted, so scanning the note text scans the wall too. Nothing here can
# read the words back out of a rendered image; what it CAN do is refuse to let the two
# strings drift apart.
#
# CONTROLS (all permanent):
#   A. the same measurement is run against a deliberately quarter-size copy of one sign,
#      and must FAIL the pixel floor. A legibility check that cannot report "too small"
#      is a legibility check that measures nothing.
#   B. a solid card with no bar must fail the redaction test.
#   C. the notice's text with a gate answer spliced into it must be REJECTED — once for a
#      word (Gate 1's colour) and once for a number (Gate 5's roster code), because a scan
#      that only matched letters would pass the code silently.

const Scenes := preload("res://tests/lib/scenes.gd")

# ⚠️ THREE SEEDS. Two of the eight signs hang in the Airlock, and the whole
# Airlock/Escort/Terminus spine is built at one of THREE randomised x offsets — so a
# single-seed run measures those two at one of three positions and says nothing about the
# other two. Same seeds the geometry sweeps use (`tests/lib/scenes.gd`): +3.0, -3.0, 0.0.
const SEEDS := [7, 3, 11]

const SETTLE := 1.6

# The player's eye height and the camera's vertical FOV, read off `player.gd`'s scene so
# they cannot drift. 1080p is the reference viewport.
const VIEWPORT_H := 1080.0

# ⚠️ 15 px of CAP HEIGHT is the floor, and it is a legibility threshold rather than a
# difficulty constant — nothing about the level's rules changes with it. For scale: 15 px
# is roughly an 11 pt word on a 1080p screen, which is the point at which a short line of
# set caps stops being shape-recognisable at a glance.
const MIN_CAP_PX := 15.0

# A censor bar is at least this wide as a fraction of the plate, and this dark.
const MIN_BAR_FRAC := 0.30
const MAX_BAR_LUM := 0.16

# ---------------------------------------------------------------- the briefing notice

const NOTICE_NODE := "NoticeBriefing"
const NOTICE_TEX := "kontur_notice_briefing.png"
# The hero band on that card, as fractions of its height. The three lines sit on baselines
# 0.375 / 0.555 / 0.735 (`tools/make_kontur_notice.py:BASELINES`); this band brackets them
# and excludes the kicker at 0.160 and the sub-line at 0.835, which are deliberately small
# and are not what a player reads while walking toward it.
const NOTICE_BAND := Vector2(0.20, 0.79)
# The words printed on the plate. Asserted to be a substring of `note_text`, which is what
# makes the keyword scan below cover the artwork as well as the memo.
const NOTICE_HERO := "YOU WERE BRIEFED ELSEWHERE."

# ⚠️ ONE ROW PER GATE, and the comment is the point: this is the list of things the notice
# is not allowed to say. Typed rather than derived because the level stores none of them —
# KONTUR's design is that every one of these lives in an EARLIER level, and putting them in
# a constant here would be the first copy inside the building.
const BANNED := {
	# Gate 1 — the two doors. Which side is black is randomised per run, so even the colour
	# is a rule rather than a position; naming either colour hands the gate over.
	"BLACK": "gate 1", "RED": "gate 1",
	# Gate 2 — the shelf. Vinegar dissolves the mass; a wrong bottle is consumed.
	"VINEGAR": "gate 2", "BLEACH": "gate 2", "ACETIC": "gate 2", "ACID": "gate 2",
	# Gate 5 — the roster code, whose digits are two notes in the Backrooms Flood.
	"63": "gate 5", "SIXTY-THREE": "gate 5",
	# Gate 3 — the offering. The verb is abstain.
	"BAIT": "gate 3", "ABSTAIN": "gate 3",
	# Gate 6 — the phone. The verb is destroy.
	"SMASH": "gate 6", "HAMMER": "gate 6", "DESTROY": "gate 6",
	# Gate 7 — the blackout. The verb is unlight.
	"FLASHLIGHT": "gate 7", "TORCH": "gate 7", "UNLIT": "gate 7", "DARKNESS": "gate 7",
	# Gate 8 — the airlock catch, and gate 4 — the escort's camera discipline.
	"MOTIONLESS": "gate 8", "BEHIND": "gate 4",
	# The levels the hints are planted in. "Elsewhere" is allowed; a destination is not.
	"LAB": "names a level", "LABORATORY": "names a level", "HOUSE": "names a level",
	"CELLAR": "names a level", "MORGUE": "names a level", "CORRIDOR": "names a level",
	"HOTEL": "names a level", "BACKROOMS": "names a level", "FLOOD": "names a level",
}

var _fails := 0
var _t := 0.0
var _done := false


var _seed_i := 0
var _measured := 0
var _notices := 0
var _text_scans := 0


func _initialize() -> void:
	Scenes.pin_rng(SEEDS[0])
	change_scene_to_file("res://scenes/kontur.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails += 1


func _process(delta: float) -> bool:
	if _done:
		return true
	_t += delta
	if _t < SETTLE:
		return false
	print("--- seed %d (dark_x %.1f) ---"
		% [SEEDS[_seed_i], float(current_scene.get("_dark_x"))])
	_run()
	_seed_i += 1
	if _seed_i < SEEDS.size():
		# ⚠️ RESET THE CLOCK. Without this the next seed is measured on the frame straight
		# after `change_scene_to_file()` instead of after `SETTLE`, and the run reported
		# seed 11's `dark_x` as 3.0 when it is 0.0 — i.e. two of the three "seeds" were
		# measuring the same level.
		_t = 0.0
		Scenes.pin_rng(SEEDS[_seed_i])
		change_scene_to_file("res://scenes/kontur.tscn")
		return false
	_done = true
	# ⚠️ Assert the sample. 8 signs x 3 seeds; a scene that failed to build would print
	# nothing but "found the eight printed signs FAIL" and then measure zero plates.
	_ok("enough signs were actually measured", _measured == 8 * SEEDS.size(),
		"%d measured, expected %d" % [_measured, 8 * SEEDS.size()])
	_ok("the briefing notice was measured on every seed", _notices == SEEDS.size(),
		"%d of %d" % [_notices, SEEDS.size()])
	_ok("the keyword scan actually ran", _text_scans == SEEDS.size() and BANNED.size() >= 20,
		"%d scans against %d banned terms" % [_text_scans, BANNED.size()])
	print("--------------------------------------------------")
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	quit(0 if _fails == 0 else 1)
	return true


func _run() -> void:
	var scene := current_scene
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		_ok("Player present", false)
		return
	var cam := player.get_node_or_null("Camera3D") as Camera3D
	var fov: float = cam.fov if cam else 75.0
	var eye_y: float = (player.global_position.y + cam.position.y) if cam else 1.65

	var signs := _sign_plates(scene)
	_ok("found the eight printed signs", signs.size() == 8, "%d found" % signs.size())
	if signs.is_empty():
		return

	var worst_px := 9999.0
	var worst_name := ""
	for entry in signs:
		var root: Node3D = entry[0]
		var plate: MeshInstance3D = entry[1]
		var img: Image = entry[2]
		var quad: QuadMesh = plate.mesh as QuadMesh

		# --- redaction --------------------------------------------------------------
		var bar := _find_bar(img)
		var bar_frac: float = bar[0]
		var bar_lum: float = bar[1]
		_ok("%s carries a censor bar" % root.name,
			bar_frac >= MIN_BAR_FRAC and bar_lum <= MAX_BAR_LUM,
			"width %.0f%% of the plate, luminance %.3f" % [bar_frac * 100.0, bar_lum])

		# --- legibility -------------------------------------------------------------
		# The rule's ink, measured on the image: the tallest run of consecutive rows
		# containing dark pixels in the band between the title rule and the censor bar.
		var cap_frac := _rule_ink_frac(img)
		var cap_m: float = cap_frac * quad.size.y
		var dist := _walking_distance(scene, root, eye_y)
		var px: float = (cap_m / dist) / (2.0 * tan(deg_to_rad(fov) * 0.5)) * VIEWPORT_H
		_measured += 1
		if px < worst_px:
			worst_px = px
			worst_name = String(root.name)
		_ok("%s is readable from the walking line" % root.name, px >= MIN_CAP_PX,
			"cap %.0f mm at %.2f m -> %.1f px (floor %.0f)"
				% [cap_m * 1000.0, dist, px, MIN_CAP_PX])

	print("  ...worst sign is %s at %.1f px" % [worst_name, worst_px])

	# --- CONTROL A: a quarter-size rule must be reported as unreadable ---------------
	var probe: Array = signs[0]
	var small := (probe[2] as Image).duplicate() as Image
	small.resize(int(small.get_width() / 4), int(small.get_height() / 4),
		Image.INTERPOLATE_LANCZOS)
	small.resize((probe[2] as Image).get_width(), (probe[2] as Image).get_height(),
		Image.INTERPOLATE_NEAREST)
	# Blurring the ink away is not the control; SHRINKING the type is. Rebuild a plate's
	# worth of ink at a quarter of the height by stamping the rule band into a blank card.
	var shrunk := _synthetic_small_rule(probe[2] as Image)
	var ctl_frac := _rule_ink_frac(shrunk)
	var ctl_quad: QuadMesh = (probe[1] as MeshInstance3D).mesh as QuadMesh
	var ctl_dist := _walking_distance(current_scene, probe[0] as Node3D, eye_y)
	var ctl_px: float = (ctl_frac * ctl_quad.size.y / ctl_dist) \
		/ (2.0 * tan(deg_to_rad(fov) * 0.5)) * VIEWPORT_H
	_ok("CONTROL A: a quarter-height rule is reported UNREADABLE", ctl_px < MIN_CAP_PX,
		"%.1f px against a floor of %.0f" % [ctl_px, MIN_CAP_PX])

	# --- CONTROL B: a plate with no bar must fail the redaction test -----------------
	var blank := Image.create(300, 200, false, Image.FORMAT_RGB8)
	blank.fill(Color(0.59, 0.56, 0.50))
	var b := _find_bar(blank)
	_ok("CONTROL B: a card with no censor bar is rejected",
		b[0] < MIN_BAR_FRAC or b[1] > MAX_BAR_LUM,
		"width %.0f%%, luminance %.3f" % [b[0] * 100.0, b[1]])

	_check_notice(scene, player, cam, fov)


# ---------------------------------------------------------------- the briefing notice

func _check_notice(scene: Node, player: CharacterBody3D, cam: Camera3D,
		fov: float) -> void:
	var notice := scene.get_node_or_null(NOTICE_NODE) as Node3D
	_ok("the briefing notice exists", notice != null)
	if notice == null:
		return

	# --- it is EARLY: inside the Landing, i.e. before the level's first gate -----------
	# ⚠️ The room rectangle is DERIVED from the scene's own ROOMS table, not typed. A
	# literal here would keep passing after somebody moved the room (X18).
	var rooms: Array = _const(scene, "ROOMS", [])
	var landing := {}
	for r in rooms:
		if String(r.get("name", "")) == "Landing":
			landing = r
	_ok("the level still has a Landing to hang it in", not landing.is_empty())
	if not landing.is_empty():
		var c: Vector2 = landing["pos"]
		var half: Vector2 = (landing["size"] as Vector2) * 0.5
		var p := notice.global_position
		_ok("...and the notice is inside it, before Gate 1",
			absf(p.x - c.x) <= half.x and absf(p.z - c.y) <= half.y,
			"at (%.2f, %.2f), Landing spans x +-%.1f z %.1f..%.1f"
				% [p.x, p.z, half.x, c.y - half.y, c.y + half.y])

	# --- it is not a ninth GATE sign ---------------------------------------------------
	var art := notice.get_node_or_null("NoticeArt") as MeshInstance3D
	_ok("the notice carries printed artwork on a quad",
		art != null and art.mesh is QuadMesh)
	if art == null or not (art.mesh is QuadMesh):
		return
	var mat := art.get_surface_override_material(0) as StandardMaterial3D
	var tex: Texture2D = mat.albedo_texture if mat != null else null
	_ok("...and it is the briefing notice's own artwork",
		tex != null and tex.resource_path.get_file() == NOTICE_TEX,
		"" if tex == null else tex.resource_path.get_file())
	if tex == null:
		return
	var img := tex.get_image()

	# ⚠️ THE MIRROR OF THE EIGHT SIGNS' ASSERTION. Every gate notice must carry a censor
	# bar; this one must not. It withholds nothing, and that visible difference is what
	# stops a player reading it as a rule they failed to decode.
	var bar := _find_bar(img)
	_ok("the notice redacts NOTHING — no censor bar",
		float(bar[0]) < MIN_BAR_FRAC or float(bar[1]) > MAX_BAR_LUM,
		"widest dark run %.0f%% of the plate at luminance %.3f"
			% [float(bar[0]) * 100.0, float(bar[1])])

	# --- LEGIBLE from the player's own spawn -------------------------------------------
	# ⚠️ THE SPAWN, not the nearest point on the walking line. This plate faces back down
	# the room the player materialises in, so the hardest honest reading distance is the
	# level's very first frame — and it only gets easier from there (it is ~39 px by the
	# time they are 3 m away). `ENTRY_SPAWN` is read out of the level's own constants.
	var spawn: Vector3 = _const(scene, "ENTRY_SPAWN", Vector3(0, 0.1, -3.0))
	var eye := spawn + Vector3(0, cam.position.y if cam else 1.55, 0)
	var quad: QuadMesh = art.mesh as QuadMesh
	var cap_frac := _rule_ink_frac(img, NOTICE_BAND.x, NOTICE_BAND.y)
	var cap_m: float = cap_frac * quad.size.y
	var dist: float = eye.distance_to(notice.global_position)
	var px: float = (cap_m / dist) / (2.0 * tan(deg_to_rad(fov) * 0.5)) * VIEWPORT_H
	_notices += 1
	_ok("the notice is readable from the player's spawn", px >= MIN_CAP_PX,
		"cap %.0f mm at %.2f m -> %.1f px (floor %.0f)"
			% [cap_m * 1000.0, dist, px, MIN_CAP_PX])

	# --- EMPTY: it names no gate answer, no level, no room -----------------------------
	var text := String(notice.get("note_text"))
	_ok("the notice carries the full memo as a readable note", text.length() > 200,
		"%d characters" % text.length())
	# ⚠️ Containment is what makes this scan cover the WALL as well as the memo: the three
	# words printed on the plate appear verbatim inside `note_text`, so one scan does both.
	# Nothing here can read words back out of a rendered image; it can refuse to let the
	# two strings drift apart.
	_ok("the printed hero line is verbatim inside the note text",
		text.to_upper().contains(NOTICE_HERO))

	var room_names: Array[String] = []
	for r in rooms:
		room_names.append(String(r.get("name", "")))
	var hits := _banned_hits(text, room_names)
	_text_scans += 1
	_ok("the notice names no gate answer, no level and no room in this one",
		hits.is_empty(), "found: " + ", ".join(hits))

	# --- CONTROL C: the scan can fire, on a word AND on a number ------------------------
	var spliced := text + "\n\nThe BLACK door is the way out."
	_ok("CONTROL C1: a gate answer spliced into the text is caught",
		not _banned_hits(spliced, room_names).is_empty())
	var spliced2 := text + "\n\nRoster: this subject is number 63."
	_ok("CONTROL C2: a gate answer that is a NUMBER is caught",
		not _banned_hits(spliced2, room_names).is_empty())
	# ...and a control on the room half, derived from the scene rather than typed.
	if not room_names.is_empty():
		var spliced3 := text + "\n\nSee the " + room_names[0] + "."
		_ok("CONTROL C3: naming a room of this level is caught",
			not _banned_hits(spliced3, room_names).is_empty(),
			"room used: " + room_names[0])

	# --- it archives to the journal, through the SHIPPING interact path -----------------
	# Once per run, on the first seed only: `NoteUI.show_note()` pauses the tree.
	if _seed_i == 0:
		_drive_read(player, notice)


# Drive the real `player.ai_interact()` so the raycast, `can_interact()` and prompt path
# all run — never `interact()` on the node and never the `read` signal.
func _drive_read(player: CharacterBody3D, notice: Node3D) -> void:
	var gs := root.get_node_or_null("/root/GameState")
	var ui := root.get_node_or_null("/root/NoteUI")
	if gs == null or ui == null:
		_ok("GameState and NoteUI are available", false)
		return
	var before: int = (gs.get("journal") as Array).size()
	var aim := notice.global_position
	# ⚠️ 1.4 m out along the plate's OWN facing, and the sign matters: the plate is turned
	# by PI, so its local +Z (the side a `QuadMesh` shows) is `basis.z` in world terms.
	# Subtracting it puts the probe 1.4 m BEHIND the north wall, in the next room, where
	# the wall stops the ray and the prompt correctly reports nothing — which is what the
	# first version of this measured.
	var stand := aim + notice.global_transform.basis.z * 1.4
	player.global_position = Vector3(stand.x, 0.1, stand.z)
	player.call("force_update_transform")
	player.call("ai_look_at", aim)
	var pcam := player.get_node_or_null("Camera3D") as Camera3D
	if pcam:
		pcam.force_update_transform()
	var target: Node = player.call("ai_interact_target")
	_ok("the shipping prompt finds the notice at 1.4 m",
		target == notice or (target != null and notice.is_ancestor_of(target)),
		"prompt saw %s" % ("nothing" if target == null else String(target.name)))
	player.call("ai_interact")
	_ok("pressing E opens it", bool(ui.get("is_open")))
	var after: int = (gs.get("journal") as Array).size()
	_ok("...and archives it so TAB can re-read it two gates later", after > before,
		"journal %d -> %d" % [before, after])
	if bool(ui.get("is_open")):
		ui.call("_close")


# Whole-word, case-insensitive. ⚠️ Word boundaries matter: "recorded" must not match
# "records" and "office" must not match "off". A substring scan would have made this guard
# unusable and it would have been switched off rather than fixed.
func _banned_hits(text: String, room_names: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var upper := text.to_upper()
	var terms: Array[String] = []
	for k in BANNED.keys():
		terms.append(String(k))
	for r in room_names:
		if r.length() >= 4:
			terms.append(r.to_upper())
	for term in terms:
		var re := RegEx.new()
		# \b does not fire between two non-word characters, so a term like "SIXTY-THREE"
		# is matched on its outer boundaries only.
		if re.compile("\\b" + _escape(term) + "\\b") != OK:
			continue
		if re.search(upper) != null:
			out.append(term)
	return out


func _escape(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s[i]
		var alnum: bool = (c >= "A" and c <= "Z") or (c >= "a" and c <= "z") \
			or (c >= "0" and c <= "9")
		if not alnum:
			out += "\\"
		out += c
	return out


# A constant out of the level script's own map — `Node.get()` returns null for consts.
func _const(scene: Node, key: String, fallback: Variant) -> Variant:
	var scr: Script = scene.get_script() as Script
	if scr == null:
		return fallback
	var m: Dictionary = scr.get_script_constant_map()
	return m.get(key, fallback)


# ---------------------------------------------------------------- collectors

func _sign_plates(scene: Node) -> Array:
	var out: Array = []
	for c in scene.get_children():
		if not (c is Node3D):
			continue
		for gc in c.get_children():
			if not (gc is MeshInstance3D and (gc as MeshInstance3D).mesh is QuadMesh):
				continue
			var mat := (gc as MeshInstance3D).get_surface_override_material(0)
			if not (mat is StandardMaterial3D):
				continue
			var tex: Texture2D = (mat as StandardMaterial3D).albedo_texture
			if tex == null or not tex.resource_path.get_file().begins_with("kontur_sign_"):
				continue
			out.append([c, gc, tex.get_image()])
			break
	return out


# ---------------------------------------------------------------- measurements

func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


# The widest contiguous run of very dark pixels on any single row, and that run's mean
# luminance. A censor bar is the only thing on these plates that is both.
func _find_bar(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var best := 0
	var best_lum := 1.0
	var y := int(h * 0.30)
	while y < int(h * 0.90):
		var run := 0
		var run_sum := 0.0
		var x := 0
		while x < w:
			var l := _lum(img.get_pixel(x, y))
			if l <= MAX_BAR_LUM:
				run += 1
				run_sum += l
			else:
				if run > best:
					best = run
					best_lum = run_sum / float(run)
				run = 0
				run_sum = 0.0
			x += 2
		if run > best:
			best = run
			best_lum = run_sum / float(maxi(run, 1))
		y += 3
	return [float(best * 2) / float(w), best_lum]


# The height of the RULE's ink, as a fraction of the plate. Found by scanning rows in the
# band between the title's hairline and the censor bar, and taking the tallest contiguous
# run of rows that contain ink but are NOT the bar (a bar row is almost entirely dark).
# ⚠️ THE BAND IS AN ARGUMENT SINCE 2026-08-18 so the briefing notice is measured by THIS
# instrument rather than by a second copy of it. Its card is 1500x1300 and its hero sits on
# different baselines, so it passes its own band; everything else about the measurement —
# thresholding the imported image, refusing rows that are a solid bar — is shared.
func _rule_ink_frac(img: Image, y0: float = 0.24, y1: float = 0.86) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var best := 0
	var run := 0
	# ⚠️ 0.24 .. 0.86, not 0.40 .. 0.60. A single-line rule is set at a baseline of 0.395,
	# so its caps live ABOVE 0.40 — the first version of this band measured 0 mm of ink on
	# the two signs whose rule fits on one line and reported them as unreadable. The band
	# still excludes the kicker (0.185) and the footer (0.95), which are deliberately
	# small and are not what a player reads while walking.
	var y := int(h * y0)
	while y < int(h * y1):
		var dark := 0
		var x := 0
		while x < w:
			if _lum(img.get_pixel(x, y)) < 0.22:
				dark += 1
			x += 2
		var frac: float = float(dark) / float(w / 2)
		# ink present, but not a solid bar
		if frac > 0.008 and frac < 0.55:
			run += 1
			best = maxi(best, run)
		else:
			run = 0
		y += 1
	return float(best) / float(h)


# Reduce the rule band to a quarter height, in place, so CONTROL A measures a genuinely
# smaller SETTING rather than a blurrier one.
func _synthetic_small_rule(src: Image) -> Image:
	var out := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGB8)
	out.fill(Color(0.59, 0.56, 0.50))
	var band_top := int(src.get_height() * 0.24)
	var band_h := int(src.get_height() * 0.60)
	for row in range(band_h / 4):
		var sy: int = band_top + row * 4
		for x in range(src.get_width()):
			out.set_pixel(x, band_top + row, src.get_pixel(x, sy))
	return out


# How far is this sign from the line a player actually walks? Every KONTUR room on the
# spine is centred on x = 0 except the randomised facility tail, and every sign is on a
# side wall, so the horizontal offset from the room's own centre axis IS the reading
# distance — with the eye-to-sign height difference folded in.
func _walking_distance(scene: Node, root: Node3D, eye_y: float) -> float:
	var axis_x: float = 0.0
	if root.global_position.z > 60.0:
		axis_x = float(scene.get("_dark_x"))
	var dx: float = absf(root.global_position.x - axis_x)
	var dy: float = absf(root.global_position.y - eye_y)
	# The gate-1 sign faces down the spine rather than across it: the player reads it
	# while walking toward the two doors, so its distance is measured along z from the
	# far side of the Vestibule (z = 4).
	if dx < 0.2:
		dx = absf(root.global_position.z - 4.0)
	return maxf(0.5, sqrt(dx * dx + dy * dy))
