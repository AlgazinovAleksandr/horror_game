extends SceneTree

# ZONE 1 TEACHES ITS OWN VERB — the seam's voice, the arrows, and the third turn.
#
#   Godot --headless --path game --script res://tests/check_backrooms_seam.gd
#
# WHY THIS EXISTS. The Backrooms' win verb is "walk into a blank wall", and zone 1 demands it
# three times before anything teaches it. The playtester stood still for 86 seconds, 6.2 m
# down the CORRECT arm, writing "many players might get confused that you need to go through
# the wall" — while looking at a LOOP-BACK CAP, not at the glitch wall. So:
#
#   * the tell has to serve the CAPS as well as the glitch wall (the capture position is the
#     whole reason the audio answer was chosen over making the glitch wall glow);
#   * it has to be TWO LAYERS — a far cue you can take a bearing from and a near confirm that
#     resolves at the surface. This project has shipped a single narrow-range emitter twice
#     (backrooms_zone2.gd, level_1.gd's dark wing) and had to widen it both times;
#   * it has to cost NOTHING. No panic, no fail state, no new rule;
#   * and it must not out-shout the score, which is the level's identity.
#
# And the arrows, which are the level's ONLY navigational signal and cost 18 panic when
# misread, have to be physically legible: a real alpha cutout, no baked wallpaper background,
# no emission, fully mounted on their post and clear of it.

const SCENE := "res://scenes/backrooms.tscn"

# ⚠️ TIME-BASED, never a frame count — headless runs uncapped, so a frame number is not a
# clock (this repo has shipped that mistake). Long enough for `ZONE_CARD_DELAY` (a full card,
# 2.5 s) plus the card's own fade-in, so the delayed zone name has genuinely landed. If the
# level's card timing changes, this is the number that has to follow it.
const ZONE_CARD_WAIT := 3.2

var _t := 0.0
var _stage := 0
var _stage_at := 0.0
var _scene: Node = null
var _player: CharacterBody3D = null
var _consts: Dictionary = {}
var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	change_scene_to_file(SCENE)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _advance(n: int) -> void:
	_stage = n
	_stage_at = _t


func _process(delta: float) -> bool:
	_t += delta
	# ⚠️ CSG colliders are not registered during _ready() (Issue 52); every ray below needs
	# real frames first or they all come back empty and the test reports the wrong thing.
	if _stage == 0 and _t > 1.2:
		_scene = current_scene
		_player = _scene.get_node_or_null("Player") as CharacterBody3D
		_ok("player found", _player != null)
		if _player == null:
			return _report()
		_consts = (load("res://scripts/backrooms.gd") as GDScript).get_script_constant_map()
		_ok("read the level's constants", not _consts.is_empty(), "%d" % _consts.size())
		# ⚠️ This probe stands still at the spawn, and zone 1 charges +3/s for that. It can
		# also be within CreatureSmiler.ENGAGE_DIST of a dark E/W arm's end, which would add
		# 2.5/s of its own on a coin flip and make the run non-deterministic. Both are
		# suppressed, exactly as check_backrooms_audio.gd does — neither is what is under
		# test here.
		_player.set_smiler_active(true)
		var smiler: Node = _scene.get("_smiler")
		if is_instance_valid(smiler):
			smiler.queue_free()
			_scene.set("_smiler", null)
		_arrows()
		_beacons()
		_marks()
		_entry_note()
		_advance(1)
	elif _stage == 1 and _t - _stage_at > 0.3:
		_targets()
		_advance(2)
	elif _stage == 2 and _t - _stage_at > 0.3:
		_third_turn()
		_advance(3)
	elif _stage == 3 and _t - _stage_at > ZONE_CARD_WAIT:
		_zone_card()
		return _report()
	if _t > 30.0:
		print("RESULT: FAIL — timed out at stage %d" % _stage)
		quit(1)
		return true
	return false


# ------------------------------------------------------------------------ the arrows

func _arrows() -> void:
	print("  -- the arrow: a cutout, mounted, unlit --")
	var post: float = _consts["ARROW_POST"]
	var clear: float = _consts["ARROW_CLEAR"]
	var seen := 0
	for id in ["N", "E", "W"]:
		var quad := _scene.get_node_or_null("ArrowDecal%s" % id) as MeshInstance3D
		_ok("ArrowDecal%s exists and is named" % id, quad != null)
		if quad == null:
			continue
		seen += 1
		var size: Vector2 = (quad.mesh as QuadMesh).size
		# ⚠️ Fully mounted. The old sign was 0.45 m wide on a 0.28 m post, so 38 % of it hung
		# in mid-air — the single most obvious thing about it in a screenshot.
		_ok("ArrowDecal%s fits on its post" % id, size.x <= post - 0.04,
			"sign %.3f m wide, post %.3f m" % [size.x, post])
		var col := _scene.get_node_or_null("ArrowCol%s" % id) as CSGBox3D
		_ok("ArrowCol%s exists" % id, col != null)
		if col != null:
			# Distance from the glyph's plane to the post's near face, measured HORIZONTALLY —
			# the quad hangs at eye height and the post's origin is at mid-wall, so a 3D
			# distance would fold that 0.1 m into the answer. The old value was 0.02, i.e.
			# check_wall_overlap.gd's bare minimum.
			var d := quad.global_position - col.global_position
			var gap := Vector2(d.x, d.z).length() - post / 2.0
			_ok("ArrowDecal%s stands clear of its post" % id,
				gap > 0.03 and gap < 0.20, "%.3f m of air (built for %.2f)" % [gap, clear])
		var mat := quad.get_surface_override_material(0) as StandardMaterial3D
		_ok("ArrowDecal%s has a material" % id, mat != null)
		if mat == null:
			continue
		# ⚠️ NO EMISSION. Emission is most of a surface's colour here (Issues 21/27/33), and
		# the old sign's 0.25 lit its own wallpaper BACKGROUND — the part with no information
		# in it. If this ever comes back the sign stops being a silhouette.
		_ok("ArrowDecal%s is not self-lit" % id, not mat.emission_enabled)
		_ok("ArrowDecal%s is an alpha cutout" % id,
			mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA)
	_ok("all three arrows were measured", seen == 3, "%d of 3" % seen)
	_arrow_contrast()
	_mouths()


# ------------------------------------------------------------------- you can walk in

# ⚠️ THE ARM MOUTHS HAVE TO BE WIDE ENOUGH TO WALK THROUGH, and until 2026-08-17 they were
# not. The arrow post stood dead centre in a 3 m opening whose southern half was already
# blocked by the entry arm's side walls (which sat 1.65 m too far north — see
# `backrooms.gd:_build_entry_arm()`), leaving a single 1.01 m slot against an 0.80 m player
# capsule. The playtester photographed the hub: "the spaces between columns to walk into are
# too small" (backlog 04 R2). The reachability sweep had hit it too and misread it, calling
# two reachable mirage doors unreachable because its 0.25 m grid could not thread the slot.
#
# ⚠️ MEASURED WITH RAYS, NEVER `intersect_shape`. A shape query against CSG reports NOTHING
# when the query shape's origin is inside the box (Issue 40) — measured again while
# diagnosing this: a capsule centred ON the arrow post came back CLEAR, so a shape-query
# version of this check would have called the post no obstacle at all and passed happily on
# the broken build. Eight short rays at the capsule's own radius, plus a point query for
# "am I inside something", is the `apparition.gd:_fits()` idiom and is here for that reason.
#
# ⚠️ NOT A DIFFICULTY CONSTANT. `MIN_LANE` is a legibility floor — "an opening a person can
# see is an opening they can use" — not a tuning knob; nothing about panic, speed or scoring
# reads it.
const MIN_LANE := 1.8
const CAPSULE_R := 0.4

func _lane(id: String) -> float:
	var axis: Vector3 = _consts["CHOICE_ARMS"][id]["axis"]
	var lat := Vector3(axis.z, 0, axis.x)
	var half: float = _consts["HALF"]
	var space := _player.get_world_3d().direct_space_state
	var step := 0.02
	var best := 0.0
	var run := 0.0
	var width: float = float(_consts["W"]) + 1.0
	var i := 0
	var n := int(width / step)
	while i <= n:
		var u: float = (float(i) * step) - width / 2.0 + 0.007
		var eye: Vector3 = axis * (half - 0.05) + lat * u + Vector3(0, 1.2, 0)
		var free := true
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = eye
		pq.collide_with_bodies = true
		pq.exclude = [_player.get_rid()]
		if not space.intersect_point(pq, 2).is_empty():
			free = false
		if free:
			for k in range(8):
				var a := TAU * float(k) / 8.0 + 0.0646
				var q := PhysicsRayQueryParameters3D.create(
					eye, eye + Vector3(cos(a), 0, sin(a)) * CAPSULE_R)
				q.collision_mask = 1
				q.exclude = [_player.get_rid()]
				if not space.intersect_ray(q).is_empty():
					free = false
					break
		if free:
			run += step
			best = maxf(best, run)
		else:
			run = 0.0
		i += 1
	# `best` is the span of legal capsule CENTRES; the walkable gap is that plus a diameter.
	return best + 2.0 * CAPSULE_R if best > 0.0 else 0.0


func _mouths() -> void:
	print("  -- the arm mouths are walkable --")
	var measured := 0
	for id in ["N", "E", "W"]:
		var lane := _lane(id)
		_ok("%s: the mouth has a lane a player fits through" % id, lane >= MIN_LANE,
			"%.2f m clear (capsule 0.80 m, margin %.2f m) — was 1.01 m before 2026-08-17"
				% [lane, lane - 0.80])
		measured += 1
		# ⚠️ AND THE WRONG-TURN SENSOR STILL COVERS IT. Widening a mouth past the sensor's
		# lateral span would let a player enter an arm without the turn being scored — the
		# level's whole navigation state machine runs off these three volumes.
		var area := _scene.get_node_or_null("ArmSensor%s" % id) as Area3D
		_ok("%s: the wrong-turn sensor exists" % id, area != null)
		if area == null:
			continue
		var col := area.get_child(0) as CollisionShape3D
		var box: Vector3 = (col.shape as BoxShape3D).size
		var axis: Vector3 = _consts["CHOICE_ARMS"][id]["axis"]
		var along := absf(axis.x) > 0.5
		var sensor_span: float = box.z if along else box.x
		_ok("%s: the sensor spans the whole opening" % id, sensor_span >= lane - 0.01,
			"sensor %.2f m vs lane %.2f m" % [sensor_span, lane])
		# ...and it is BEYOND the arrow, or the turn is scored before the sign is read.
		var post := _scene.get_node_or_null("ArrowCol%s" % id) as CSGBox3D
		if post:
			var d_sensor: float = area.global_position.dot(axis)
			var d_arrow: float = post.global_position.dot(axis)
			_ok("%s: the sensor sits deeper in than the arrow" % id, d_sensor > d_arrow,
				"sensor %.2f m vs arrow %.2f m along the arm" % [d_sensor, d_arrow])
	_ok("all three mouths were measured", measured == 3, "%d of 3" % measured)


# The glyph must be far darker than the post it is painted on. Both surfaces take the same
# light from the same hub lamp and both leave albedo_color white, so the ratio of the two
# textures' mean luminance IS the rendered contrast ratio — no frame needed.
#
# Measured on the old sign, from real frames: glyph 120.7 lum against its own baked panel
# background at 126.3 = 2.2 % contrast, while the panel carried 22 % against the column.
# Every part of the sign that contained no information was ten times louder than the part
# that did.
#
# ⚠️ THIS ASSERTION IS ONLY MEANINGFUL FOR A REAL CUTOUT, and the limit is worth stating
# because it looks stronger than it is. Measured by re-pointing ARROW_TEX at the retired
# `arrow_decal.png` (2026-08-17): this check reported **40.8 % and PASSED**, because with no
# alpha channel `opaque_only` averages the WHOLE image — baked wallpaper background included —
# so it answers "is this rectangle darker than the wall" rather than "is the glyph darker than
# what it is painted on". The 2.2 % figure could only ever come from a rendered frame.
#
# What actually caught the old asset in that experiment was the pair of assertions either side
# of this one: the alpha check went red, and so did "fits on its post" (a square source makes
# the quad 0.72 m wide on a 0.68 m post). ⚠️ So do not delete either of those on the grounds
# that the contrast bar covers them. It does not.
const MIN_CONTRAST := 0.25

func _arrow_contrast() -> void:
	var glyph := _mean_lum(_consts["ARROW_TEX"], true)
	var wall := _mean_lum(_consts["TEX_DIR"] + "backrooms_wallpaper_albedo.png", false)
	_ok("both textures could be measured", glyph >= 0.0 and wall > 0.0,
		"glyph %.1f, wallpaper %.1f" % [glyph, wall])
	if glyph < 0.0 or wall <= 0.0:
		return
	var contrast: float = (wall - glyph) / wall
	_ok("the glyph reads against its post", contrast >= MIN_CONTRAST,
		"%.1f%% (glyph %.1f lum vs wallpaper %.1f) — the old sign carried 2.2%%"
		% [contrast * 100.0, glyph, wall])
	# And it must genuinely have an alpha channel, or there is nothing to cut out and it
	# renders as a solid rectangle (the apparition_figure.jpg bug).
	var img := _image(_consts["ARROW_TEX"])
	_ok("the arrow texture has a real alpha channel",
		img != null and img.detect_alpha() != Image.ALPHA_NONE)


# ------------------------------------------------------------------- the entry note
#
# The first thing the player is asked to interact with in this level, and the second prop in
# two days rebuilt for the same complaint. Playtest capture 003, 2026-08-18: *"Again, make
# the note more like the backrooms atmosphere."*
#
# ⚠️ WHAT IS ASSERTED IS THE THING THE USER JUDGED — that it is a document rather than a
# glowing card. Two measurable halves: the art exists on a QUAD (a `BoxMesh` face renders a
# magnified crop, Issue 24, and `check_art_aspect.gd` owns the stretch half), and its mean
# luminance is BELOW the wallpaper it is seen against. In a level with no glow, no fog and
# light energy ~0.45, a near-white page is the brightest object in the room — this is
# `lab_breaker_panel.png`'s Issue 63 stated as a rule instead of rediscovered.
func _entry_note() -> void:
	print("\n--- the entry note ---")
	var note := _scene.get_node_or_null("ClueNote") as Node3D
	_ok("the entry note exists", note != null)
	if note == null:
		return
	var page := note.get_node_or_null("NotePage") as MeshInstance3D
	var pad := note.get_node_or_null("NotePad") as MeshInstance3D
	_ok("its artwork is on a QuadMesh, not on a BoxMesh face",
		page != null and page.mesh is QuadMesh)
	_ok("...standing proud of a real pad, so the sheet has an edge",
		pad != null and pad.mesh is BoxMesh)
	if page == null:
		return
	var mat := page.get_surface_override_material(0) as StandardMaterial3D
	_ok("the page carries a texture", mat != null and mat.albedo_texture != null)
	if mat == null or mat.albedo_texture == null:
		return
	# ⚠️ Emission through MULTIPLY, never Godot's default ADD — ADD lays a flat wash over the
	# artwork and knocks the type out of it (Issue 81) — and well under 1.0 or it clamps to
	# flat white (Issue 21).
	_ok("it is lit through its own tone (MULTIPLY) and stays under 1.0",
		mat.emission_enabled
		and mat.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY
		and mat.emission_energy_multiplier < 1.0,
		"op %d, energy %.2f" % [mat.emission_operator, mat.emission_energy_multiplier])

	var paper := _mean_lum(String(mat.albedo_texture.resource_path), true)
	var wall := _mean_lum(_consts["TEX_DIR"] + "backrooms_wallpaper_albedo.png", false)
	_ok("both textures could be measured", paper >= 0.0 and wall > 0.0,
		"paper %.1f, wallpaper %.1f" % [paper, wall])
	if paper < 0.0 or wall <= 0.0:
		return
	_ok("the page is DARKER than the wallpaper it lies in front of", paper < wall,
		"paper %.1f lum vs wallpaper %.1f — the old flat card was albedo 0.85 and emissive"
		% [paper, wall])


func _image(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img != null and img.is_compressed():
		if img.decompress() != OK:
			return null
	return img


# Mean luminance 0..255. `opaque_only` skips transparent pixels, which is the only
# meaningful average for a cutout.
func _mean_lum(path: String, opaque_only: bool) -> float:
	var img := _image(path)
	if img == null:
		return -1.0
	var acc := 0.0
	var n := 0
	var step: int = maxi(1, img.get_width() / 96)
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var p := img.get_pixel(x, y)
			if opaque_only and p.a < 0.8:
				continue
			acc += (0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b) * 255.0
			n += 1
	if n == 0:
		return -1.0
	return acc / float(n)


# ------------------------------------------------------------------------ the voice

func _beacons() -> void:
	print("  -- the seam's voice: two layers, under the score, free --")
	var far := _scene.get_node_or_null("SeamFar") as AudioStreamPlayer3D
	var near := _scene.get_node_or_null("SeamNear") as AudioStreamPlayer3D
	_ok("the far cue exists", far != null)
	_ok("the near confirm exists", near != null)
	if far == null or near == null:
		return
	_ok("both are playing", far.playing and near.playing)
	_ok("both have real audio", far.stream != null and near.stream != null,
		"%s / %s" % [_file_of(far), _file_of(near)])

	# ⚠️ TWO LAYERS, and the far one has to be the wide one. A single emitter, or two at the
	# same range, is the mistake backrooms_zone2.gd and level_1.gd each shipped once: a cue
	# only audible once you have already arrived tells you nothing you did not know.
	_ok("the far cue carries further than the near confirm",
		far.unit_size >= near.unit_size * 2.0,
		"unit_size %.1f vs %.1f" % [far.unit_size, near.unit_size])

	# ⚠️ NOT on the level's bed bus. A SilenceZone ducks that bus, and a tell routed through
	# the bus a silence pocket ducks is a tell that mutes itself — the mistake
	# backrooms_zone2.gd's header is a post-mortem of.
	var bed: String = _consts["AUDIO_BUS"]
	_ok("the tell is off the duckable bed bus", far.bus != bed and near.bus != bed,
		"%s / %s (bed is '%s')" % [far.bus, near.bus, bed])

	# The score leads. check_backrooms_audio.gd asserts this for every self-starting emitter
	# near the player; asserted here too because these two are the ones that are ALWAYS on.
	var music: float = _consts["MUSIC_VOLUME_DB"]
	_ok("the far cue sits under the score", far.volume_db < music,
		"%+.1f dB vs score %+.1f" % [far.volume_db, music])
	_ok("the near confirm sits under the score", near.volume_db < music,
		"%+.1f dB vs score %+.1f" % [near.volume_db, music])

	# ⚠️ ZERO PANIC, structurally. No script, no Area3D, no children of any kind: there is
	# nothing here that could reach player.add_panic(). GAME_MECHANICS_IDEAS §0.2 — a scare
	# with a number attached can be optimised against; one without cannot.
	_ok("the tell carries no logic at all",
		far.get_script() == null and near.get_script() == null
			and far.get_child_count() == 0 and near.get_child_count() == 0)


func _file_of(p: Node) -> String:
	var s: AudioStream = p.get("stream")
	return s.resource_path.get_file() if s else "(none)"


# ------------------------------------------------------------------------ it follows the round

# Force each arm to be the answer in turn and check the beacon lands ON that arm's surface,
# is reachable from inside the arm, and that the surface really is the thing you have to walk
# into.
func _targets() -> void:
	print("  -- the voice follows the round, INCLUDING the loop-back caps --")
	var far := _scene.get_node_or_null("SeamFar") as AudioStreamPlayer3D
	if far == null:
		return
	var space := _player.get_world_3d().direct_space_state
	var arms: Dictionary = _consts["CHOICE_ARMS"]
	for id in ["E", "W", "N"]:
		_scene.set("_correct", id)
		_scene.call("_move_seam_beacons")
		var face: Vector3 = _scene.call("_seam_face", id)
		var into: Vector3 = arms[id]["axis"]
		var at: Vector3 = far.global_position
		_ok("%s: the tell sits at that arm's surface" % id,
			Vector2(at.x - face.x, at.z - face.z).length() < 0.6,
			"beacon %v vs surface %v" % [at, face])

		# Reachable: a clear line from 3 m back inside the arm. A tell you cannot walk to is
		# the failure this whole feature exists to avoid.
		var from: Vector3 = face - into * 3.0 + Vector3(0, 1.5, 0)
		var q := PhysicsRayQueryParameters3D.create(from, Vector3(at.x, 1.5, at.z))
		q.exclude = [_player.get_rid()]
		q.collision_mask = 1
		_ok("%s: it is on the player's side of the surface" % id,
			space.intersect_ray(q).is_empty())

		if id == "N":
			# The glitch wall is deliberately walk-through and has no collider, so what has
			# to be there is its trigger.
			var trig := _scene.get_node_or_null("ExitTrigger") as Area3D
			_ok("N: the glitch wall's walk-into trigger is right there", trig != null
				and trig.global_position.distance_to(Vector3(at.x, at.y, at.z)) < 2.5)
		else:
			# ⚠️ THE POINT OF THE WHOLE FEATURE. The E/W targets are LOOP-BACK CAPS — plain
			# wallpapered dead ends built from the same material as every other wall, two of
			# the three times this level asks you to walk into one. A tell that only served
			# the glitch wall would have left the capture position untouched.
			var beyond := PhysicsRayQueryParameters3D.create(
				Vector3(at.x, 1.5, at.z), Vector3(at.x, 1.5, at.z) + into * 1.2)
			beyond.exclude = [_player.get_rid()]
			beyond.collision_mask = 1
			_ok("%s: and the surface behind it is a SOLID dead-end cap" % id,
				not space.intersect_ray(beyond).is_empty())
			var loop := _scene.get_node_or_null("LoopBack%s" % id) as Area3D
			_ok("%s: the loop-back trigger is at that cap" % id, loop != null
				and Vector2(loop.global_position.x - at.x,
					loop.global_position.z - at.z).length() < 2.0)


# ------------------------------------------------------------------------ the scrawl

# ⚠️ THE FLOOR DRAG MARKS ARE GONE AND THIS CHECK MUST NOT GO VACUOUS WITH THEM.
#
# Until 2026-08-17 this section asserted `here >= 3` streaks per arm and `marks >= 9` in
# total, alongside the scrawl checks. The player cut the streaks in two separate captures on
# one playthrough — "These stripes look weird - remove them" / "Yeah, remove the stripes. The
# hints on the walls are sufficient" (backlog 04 R3) — so those five assertions had to go.
#
# Deleting five assertions from a test is how a test quietly stops measuring anything, so
# this section GAINED two in the same edit:
#   * `_scrawls_measured` is asserted at the end, exactly as `_arrows()` asserts "all three
#     arrows were measured" — a scrawl that stops being built now fails rather than skipping;
#   * every arm is checked for the ABSENCE of any `DragMark*` node, anywhere in the scene,
#     so a future session cannot re-add them without this going red and being pointed at
#     GAME_MECHANICS_IDEAS §5.
var _scrawls_measured := 0

func _marks() -> void:
	print("  -- the non-audio statement of the verb --")
	var space := _player.get_world_3d().direct_space_state
	# Whole-scene sweep, not `get_node_or_null` on the three names the old builder used: a
	# re-added mark parented anywhere at all has to be caught.
	var drag: Array[String] = []
	for n in _all(_scene):
		if String(n.name).begins_with("DragMark"):
			drag.append(String(n.name))
	_ok("the floor drag marks are gone (the player cut them twice)", drag.is_empty(),
		"%d found: %s" % [drag.size(), ", ".join(drag.slice(0, 6))])
	for id in ["N", "E", "W"]:
		var lbl := _scene.get_node_or_null("SeamScrawl%s" % id) as Label3D
		_ok("%s: the verb is written on the wall" % id, lbl != null and lbl.text != "")
		if lbl == null:
			continue
		# It quotes the Lab's TRIAL 4 whiteboard on purpose, and that is the hint the user
		# asked twice to be made clearer. If the wording drifts, the link is gone.
		_ok("%s: it says NO DOOR, echoing the Lab whiteboard" % id,
			lbl.text.contains("NO DOOR"), lbl.text.replace("\n", " / "))
		# Unshaded Label3D, so `modulate` is its final colour — it must be DARK against
		# wallpaper, never a glowing sign (Issue 33).
		var lum: float = 0.2126 * lbl.modulate.r + 0.7152 * lbl.modulate.g \
			+ 0.0722 * lbl.modulate.b
		_ok("%s: the scrawl is dark, not lit" % id, lum < 0.25, "%.3f" % lum)
		# And it must not be buried in the wall it hangs on.
		var q := PhysicsRayQueryParameters3D.create(
			lbl.global_position, lbl.global_position + lbl.global_basis.z * 0.6)
		q.exclude = [_player.get_rid()]
		q.collision_mask = 1
		_ok("%s: the scrawl faces open floor, not masonry" % id,
			space.intersect_ray(q).is_empty())
		_scrawls_measured += 1
	# ⚠️ SAMPLE SIZE. Four assertions per scrawl are worth nothing if zero scrawls were found
	# — `_ok` is only ever reached inside the loop body past the null guard.
	_ok("all three scrawls were measured", _scrawls_measured == 3,
		"%d of 3" % _scrawls_measured)


# ------------------------------------------------------------------------ the third turn

# ⚠️ EVERY Label under EVERY CanvasLayer, not "the first one". The scene already carries
# `HUDCanvas` with `PanicHUD`'s objective label on it, and which CanvasLayer comes first in the
# child order is an accident of `_ready()`. The two strings looked for below cannot collide
# with the objective line: the objective formats "(3/3)" with no spaces, and never says SPRAWL.
func _label_texts() -> String:
	var out := ""
	for c in _all(_scene):
		if c is Label:
			out += (c as Label).text + " | "
	return out


func _all(n: Node, acc: Array[Node] = []) -> Array[Node]:
	acc.append(n)
	for c in n.get_children():
		_all(c, acc)
	return acc


func _third_turn() -> void:
	print("  -- the counter reaches 3/3 --")
	# Drive the REAL path: two turns banked, then walk into the glitch wall. Both playtest
	# logs show the objective stuck at (2/3) at the exact moment the zone card appears —
	# the level advertises three turns, banks two, and never prints the third.
	_scene.set("_counter", 2)
	_scene.call("_on_exit_reached", _player)
	_ok("the third down-turn is banked", int(_scene.get("_counter")) == 3,
		"counter = %d" % int(_scene.get("_counter")))
	var texts := _label_texts()
	_ok("and the HUD prints 3 / 3 before anything else", texts.contains("3 / 3"), texts)
	var z2 := _scene.get_node_or_null("ZoneSprawl")
	_ok("and the player is in the Sprawl", z2 != null
		and _player.global_position.distance_to(z2.get("spawn_point")) < 1.5)


func _zone_card() -> void:
	# ⚠️ The other half. The zone card is held back so (3/3) gets its moment — a delay that
	# never resolves would mean the player is dropped into a new zone with no name card at
	# all, which is worse than the bug being fixed.
	var texts := _label_texts()
	_ok("the zone card still lands, a moment later", texts.contains("SPRAWL"), texts)


func _report() -> bool:
	print("")
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
