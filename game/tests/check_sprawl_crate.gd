extends SceneTree

# THE BOX IN THE DARK — the Sprawl's crate, the thing that comes out of it, the wall it runs
# through, and the camera that is pinned to the run (backlog 04 B-R3 / B-S2, the user's own
# design, 2026-08-17 and 2026-08-18).
#
#   Godot --headless --path game --script res://tests/check_sprawl_crate.gd
#
# ⚠️⚠️ THE ASSERTION THIS TEST EXISTS FOR CHANGED ON 2026-08-18, AND IT IS NOW THE MORE
# DANGEROUS ONE. It used to prove "both routes work, independently" — the crate was an
# optional aid and the `water` + `whisper` tell at the real wall could clear the zone on its
# own. The user overturned that, twice and explicitly: *"it should run and go through the
# real wall which would not be active until it runs through."* So the crate is the GATE, and
# what has to be proved is:
#
#   COMPLETABILITY, COLD, THROUGH THE SHIPPING PATH. Spawn in the Sprawl carrying nothing
#     and knowing nothing -> the whisper is audible from where you stand -> walk to the box
#     -> `ai_interact()` opens it -> the runner crosses the hall -> the wall it goes through
#     stops being sealed -> walking into it clears the zone. `cleared` is never emitted by
#     this test; it is driven by moving the real body into the real `Area3D`.
#
#   AND THE GATE IS REAL IN BOTH DIRECTIONS. Before the run, standing in the real wall's
#     trigger volume does NOTHING — no clear, no mistake, no penalty — and there is a
#     collider there so the player cannot walk out of the 7 m hole the wall stands in.
#     After the run, the same position clears the zone.
#
#   AND THE SAFETY NET. With the wall gated, the whisper is the only thing between this
#     design and an unwinnable zone, so it is measured rather than assumed: the far cue is
#     sampled against the level's own ambient bed on a grid over every standable square
#     metre of the hall AND the eight recesses, and the worst point must still clear it.
#     It must also never stop — asserted over real seconds, not frames.
#
# ⚠️ AND THE MARK MUST NOT LIE. Touching a fake re-randomises which wall is real, so the run
# below outs a wall AFTER the dweller has run and requires the mark AND the gate to move.
#
# ⚠️ IT IS NOT A `Watcher`, AND THAT IS ASSERTED. `congregation.gd`'s figures are ruleless by
# construction and that is why the Congregation is legal at all beside a Smiler that kills
# you for looking; one of THEM charging would rewrite what the zone teaches. The runner is a
# separate script, and the Congregation's own figures must still be the same count and still
# ruleless afterwards.
#
# ⚠️ ZERO PANIC. Sampled every frame across the whole run, through the scare.

const SCENE := "res://scenes/backrooms.tscn"
const ORIGIN := Vector3(200, 0, 0)
const REACH_DIST := 1.5
const OBLIQUE_DEG := 25.0

# The Sprawl's competing bed, derived from the scene rather than typed in: see `_bed_dbfs()`.
# A cue has to clear it by this much at the WORST place a player can stand, or it is not a
# safety net.
const MIN_MARGIN_DB := 3.0
# How long the whisper must still be playing for. Real seconds, never frames — headless runs
# uncapped, so a frame count is not a clock (the bus-restore lesson).
const WHISPER_WATCH := 4.0

var _t := 0.0
var _stage := 0
var _stage_at := 0.0
var _scene: Node = null
var _player: Node3D = null
var _zone: Node = null
var _crate: Node = null

var _cleared := 0
var _mistakes := 0
var _real_before := ""
var _panic_last := 0.0
var _panic_step := 0.0
var _panic_samples := 0
var _walk_from := Vector3.ZERO
var _yaw_at_run := 0.0
var _turned := 0.0
var _frozen_seen := false

var _checks := 0
var _fails: Array[String] = []


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


func _report() -> bool:
	print("--------------------------------------------------")
	print("  %d checks, %d failed" % [_checks, _fails.size()])
	for f in _fails:
		print("    - ", f)
	print("RESULT: ", "FAIL" if _fails.size() > 0 else "PASS")
	print("--------------------------------------------------")
	quit(1 if _fails.size() > 0 else 0)
	return true


func _process(delta: float) -> bool:
	_t += delta
	if _stage > 0 and (not is_instance_valid(_scene) or not is_instance_valid(_player)):
		_ok("the level survived the run", false, "the scene reloaded at t=%.1f s" % _t)
		return _report()
	if _stage > 0:
		_player.call("set_smiler_active", true)   # the maze charges for standing still
		var now := float(_player.call("get_panic_ratio"))
		_panic_step = maxf(_panic_step, absf(now - _panic_last))
		_panic_last = now
		_panic_samples += 1
	# The camera pin is sampled from HERE, every frame, and never in the frame of the press
	# that starts it — the run is deferred by one `flash_scare` hold and the turn is a tween.
	# Issue 113 is exactly this mistake made once already.
	if _stage >= 7 and is_instance_valid(_player):
		if bool(_player.call("is_input_frozen")):
			_frozen_seen = true
		_turned = maxf(_turned,
			absf(rad_to_deg(angle_difference(_yaw_at_run, _player.rotation.y))))

	match _stage:
		0:
			if _t < 1.0:
				return false
			return _setup()
		1:
			# ⚠️ NOT INSIDE `_setup()`. The per-frame block above — which suspends the
			# maze's standstill tax and samples panic — only runs once a stage is live, so
			# probing from stage 0 measured nothing and left the probe exposed to the very
			# tax it disables.
			_structure()
			_advance(2)
			return false
		2:
			return _the_gate_holds()
		3:
			if _t - _stage_at < 0.6:
				return false
			return _the_gate_holds_measure()
		4:
			return _the_whisper()
		5:
			# The whisper must still be running after real seconds have passed. This is the
			# safety net; it is the one thing that makes a mandatory box legal.
			if _t - _stage_at < WHISPER_WATCH:
				return false
			return _whisper_is_permanent()
		6:
			return _open_the_crate()
		7:
			# ⚠️ 12 s, FROM THE WORST CASE RATHER THAN FROM A TYPICAL ONE. The recess and
			# the real wall are both randomised per run, so the crossing is anywhere from
			# ~14 m (same side) to 42.9 m (opposite corners) — 6.6 s at SPEED 6.5, plus the
			# 0.9 s the run is deferred by the scare image and the 1.1 s the camera is held
			# past the arrival.
			if _t - _stage_at < 12.0:
				return false
			return _the_mark()
		8:
			if _t - _stage_at < 0.6:
				return false
			return _walk_through_it()
		9:
			if _t - _stage_at < 0.6:
				return false
			return _touch_a_fake()
		10:
			# ⚠️ TIME, NOT FRAMES, and NOT an `await` inside `_process` — awaiting here
			# suspends the stage machine and the continuation may never run before the
			# quit, which silently drops every assertion after it and still prints PASS.
			if _t - _stage_at < 0.5:
				return false
			return _mark_follows_a_reroll()

	if _t > 180.0:
		_ok("the probe finished inside its budget", false, "timed out at stage %d" % _stage)
		return _report()
	return false


func _setup() -> bool:
	_scene = current_scene
	_player = _scene.get_node_or_null("Player") as Node3D
	_zone = _scene.get_node_or_null("ZoneSprawl")
	_ok("the Player exists", _player != null)
	_ok("zone 2 (the Sprawl) is built", _zone != null)
	if _player == null or _zone == null:
		return _report()
	_player.call("set_smiler_active", true)
	_panic_last = float(_player.call("get_panic_ratio"))

	# Beartraps would end the run the moment the probe teleports across the hall.
	var trap_script: GDScript = load("res://scripts/beartrap.gd")
	var freed := 0
	for n in _all(_zone, []):
		if n.get_script() == trap_script:
			n.queue_free()
			freed += 1
	_ok("the Sprawl's beartraps were disarmed for this probe", freed >= 3,
		"%d freed" % freed)

	# ⚠️ Re-point the zone's own signals: `cleared` is wired to `_enter_zone(3)` and
	# `mistake` to a teleport + a flash, both of which move the probe out from under its
	# own assertions. The SEAM's physics still has to fire them, which is the half that
	# matters; the wiring is asserted in `walk_backrooms.gd`.
	for c in _zone.cleared.get_connections():
		_zone.cleared.disconnect(c["callable"])
	_zone.cleared.connect(func() -> void: _cleared += 1)
	for c in _zone.mistake.get_connections():
		_zone.mistake.disconnect(c["callable"])
	_zone.mistake.connect(func() -> void: _mistakes += 1)

	_crate = _zone.get_node_or_null("SprawlCrate")
	_ok("there is exactly one crate in the hall", _crate != null and _count_crates() == 1,
		"%d found" % _count_crates())
	_ok("...and the eight recesses still hold one thing each: the crate REPLACED a prop",
		_count_alc_props() == 3, "%d AlcProp boxes left of 4" % _count_alc_props())
	if _crate == null:
		return _report()
	_advance(1)
	return false


# ------------------------------------------------------- the crate, before it is opened

func _structure() -> void:
	print("\n--- the box in the dark ---")
	# ⚠️ It must be IN a recess, not merely near one: "hidden in the dark" is the premise.
	var side: String = String(_zone.get("_crate_side"))
	var k: int = int(_zone.get("_crate_k"))
	var centre: Vector3 = _zone.call("_alc_centre", side, k)
	var d := (_crate as Node3D).global_position.distance_to(centre)
	_ok("the crate stands in one of the eight recesses", d < 1.2,
		"%.2f m from the %s%+d recess centre" % [d, side, k])

	# ...and the ceiling over that corner is dark by construction, not by a 30 % coin flip.
	var lit_near := 0
	var nearest := 999.0
	for n in _all(_zone, []):
		if n is OmniLight3D and (n as OmniLight3D).light_energy > 0.01:
			var dist: float = (n as Node3D).global_position.distance_to(centre)
			nearest = minf(nearest, dist)
			if dist < 9.0:
				lit_near += 1
	_ok("the light over that corner of the ceiling was cut", lit_near == 0,
		"%d lit fixtures within 9 m; nearest is %.1f m" % [lit_near, nearest])

	# It is built from parts, not a box (Issue 35) — the prop it replaced was one CSG cube
	# and the player photographed it as scenery.
	var meshes := 0
	for n in _all(_crate, []):
		if n is MeshInstance3D:
			meshes += 1
	_ok("it is built from parts rather than being a box", meshes >= 12,
		"%d mesh parts" % meshes)

	# The two-layer call, on Master, self-looping, and NOT the same sound as the real
	# wall's own tell — two cues in one room that sound alike is one cue pointing twice.
	var far := _crate.get_node_or_null("CrateCallFar") as AudioStreamPlayer3D
	var near := _crate.get_node_or_null("CrateCallNear") as AudioStreamPlayer3D
	_ok("the crate has a two-layer positional call", far != null and near != null)
	if far == null or near == null:
		return
	_ok("...the far cue carries further than the near confirm",
		far.unit_size > near.unit_size, "unit %.1f vs %.1f" % [far.unit_size, near.unit_size])
	_ok("...both are on Master, so a SilenceZone cannot mute the tell it provides",
		far.bus == "Master" and near.bus == "Master", "%s / %s" % [far.bus, near.bus])
	_ok("...both are playing before anything is touched", far.playing and near.playing)
	_ok("...both restart themselves (every .wav.import here is loop_mode=0)",
		far.finished.is_connected(far.play) and near.finished.is_connected(near.play))

	var wall_tell := ""
	for n in _all(_zone, []):
		if n is AudioStreamPlayer3D and n.stream != null \
				and String(n.name).begins_with("Tell") == false \
				and _zone.get("_tell_water") == n:
			wall_tell = String(n.stream.resource_path)
	var crate_far := "" if far.stream == null else String(far.stream.resource_path)
	_ok("...and it is a DIFFERENT sound from the real wall's own tell",
		crate_far != wall_tell and crate_far.contains("sprawl_call"),
		"crate %s vs wall %s" % [crate_far.get_file(), wall_tell.get_file()])

	# The shipping prompt must find it, square on and 25 degrees either side.
	var poses := 0
	for off in [0.0, OBLIQUE_DEG, -OBLIQUE_DEG]:
		var hit := _reads(_crate, REACH_DIST, off)
		if hit == _crate or (hit != null and _crate.is_ancestor_of(hit)):
			poses += 1
	_ok("the crate answers the shipping prompt square on and 25° either side", poses == 3,
		"%d of 3" % poses)

	# Zero panic, and no rules of its own.
	var scary: GDScript = load("res://scripts/scary_object.gd")
	var bad: Array[String] = []
	for n in _all(_crate, []):
		if n.get_script() == scary or n is Area3D:
			bad.append(String(n.name))
	_ok("no ScaryObject and no Area3D anywhere on the crate", bad.is_empty(),
		"found: %s" % ", ".join(bad))


# ------------------------------------------------------------------- THE GATE (B-S2)

func _the_gate_holds() -> bool:
	print("\n--- the real wall is INACTIVE until the runner goes through it ---")
	var real: String = String(_zone.call("real_side"))
	var wall: GlitchWall = _zone.get("_walls")[real]
	_ok("the real wall is sealed before the crate is opened", wall.is_sealed())
	_ok("...and the three fakes are NOT — a wrong wall is still a wrong answer",
		not _any_fake_sealed(), "sealed fakes: %s" % ", ".join(_sealed_fakes()))
	_ok("...it still looks like the other three: visible, tearing, not solid",
		wall.visible and not wall.is_solid() and not wall.is_agitated())

	# ⚠️ SEALED IS A COLLIDER, NOT A HIDDEN NODE, and the reason is a hole in the world:
	# `_side_runs()` cuts a 7 m gap in the perimeter for each glitch wall, so this wall IS
	# the shell. Prove it physically — a ray from inside the hall must be stopped.
	var space: PhysicsDirectSpaceState3D = _scene.get_world_3d().direct_space_state
	var wpos: Vector3 = wall.global_position
	var inward: Vector3 = (_zone.global_position - wpos).normalized()
	var q := PhysicsRayQueryParameters3D.create(wpos + inward * 3.0 + Vector3(0, -0.6, 0),
		wpos - inward * 2.0 + Vector3(0, -0.6, 0))
	var hit: Dictionary = space.intersect_ray(q)
	_ok("a sealed wall stops a ray, so it cannot be walked out of the world through",
		not hit.is_empty(), "hit: %s" % ("nothing" if hit.is_empty()
			else String((hit["collider"] as Node).name)))

	# ...and standing in its trigger does nothing at all.
	_player.global_position = wpos + inward * 0.6
	_player.call("force_update_transform")
	_advance(3)
	return false


func _the_gate_holds_measure() -> bool:
	_ok("walking into the real wall before the run does NOT clear the zone",
		_cleared == 0, "cleared fired %d time(s)" % _cleared)
	_ok("...and does not cost a strike either — it is inert, not a wrong answer",
		_mistakes == 0, "%d mistake(s)" % _mistakes)
	_ok("...and the crate is still shut", not bool(_crate.call("is_opened")))
	_player.global_position = _zone.get("spawn_point")
	_player.call("force_update_transform")
	_advance(4)
	return false


# ------------------------------------------ THE SAFETY NET: is the whisper findable?

# The bed the call has to be heard over: the loudest non-positional ambience playing in the
# level, at its own volume_db, measured from the file.
#
# ⚠️ THE SCORE CANNOT BE MEASURED HERE and it is the loudest of the two. `backrooms_music`
# is an .mp3 and `_rms_dbfs()` reads RIFF only, so it returns "no data" rather than a wrong
# number. `backrooms.gd` states its own measurement — a -18.0 dBFS file at
# `MUSIC_VOLUME_DB` -4 = **-22.0 dBFS effective** — and that is the floor used here. Taking
# the max of the two means a future louder hum is picked up automatically, while the score
# can never be silently dropped from the comparison.
const SCORE_EFFECTIVE_DBFS := -22.0

func _bed_dbfs() -> float:
	var worst := SCORE_EFFECTIVE_DBFS
	var measured := 0
	for n in _all(_scene, []):
		if n is AudioStreamPlayer and (n as AudioStreamPlayer).stream != null:
			var a := n as AudioStreamPlayer
			var rms := _rms_dbfs(String(a.stream.resource_path))
			if rms > -900.0:
				worst = maxf(worst, rms + a.volume_db)
				measured += 1
	# Sample-size discipline: a bed derived from nothing is a comparison against a constant.
	_ok("the level's ambient bed was measured from its own files", measured >= 1,
		"%d measurable non-positional bed(s); score floor %.1f dBFS"
		% [measured, SCORE_EFFECTIVE_DBFS])
	return worst


func _the_whisper() -> bool:
	print("\n--- the whisper is the safety net, so it is MEASURED ---")
	var far := _crate.get_node_or_null("CrateCallFar") as AudioStreamPlayer3D
	var near := _crate.get_node_or_null("CrateCallNear") as AudioStreamPlayer3D
	var far_rms := _rms_dbfs(String(far.stream.resource_path))
	var near_rms := _rms_dbfs(String(near.stream.resource_path))
	var bed := _bed_dbfs()
	_ok("the crate call and the level's own bed both have real sample data",
		far_rms > -900.0 and near_rms > -900.0 and bed > -900.0,
		"far %.1f dBFS, near %.1f dBFS, bed %.1f dBFS effective" % [far_rms, near_rms, bed])
	if far_rms < -900.0 or bed < -900.0:
		_advance(5)
		return false

	# ⚠️ EVERY STANDABLE SQUARE METRE, not the room centres. The hall is 40 x 40 m and the
	# eight recesses hang off it; a cue measured only at the middle would say nothing about
	# the corner the player is actually lost in.
	var worst := 999.0
	var worst_at := Vector3.ZERO
	var sampled := 0
	for p in _standable_points():
		var cue: float = far_rms + _level_at(far, p)
		var margin: float = cue - bed
		sampled += 1
		if margin < worst:
			worst = margin
			worst_at = p
	_ok("the far cue was sampled across the whole hall and every recess", sampled >= 1500,
		"%d points on a 1 m grid" % sampled)
	# ⚠️ THE ASSERTION THAT MAKES THE GATE LEGAL. A box you cannot hear is a zone you
	# cannot leave.
	_ok("the whisper clears the level's own bed from EVERYWHERE a player can stand",
		worst >= MIN_MARGIN_DB,
		"worst margin %+.1f dB at %v (%.1f m from the box)"
		% [worst, worst_at, worst_at.distance_to((_crate as Node3D).global_position)])

	# ...and the near confirm is a second layer, not a second copy: it has to die away.
	var near_worst := 999.0
	var near_best := -999.0
	for p in _standable_points():
		var n: float = near_rms + _level_at(near, p)
		near_worst = minf(near_worst, n - bed)
		near_best = maxf(near_best, n - bed)
	_ok("the near confirm dies below the bed out in the hall, so it means \"you are here\"",
		near_worst < 0.0 and near_best > MIN_MARGIN_DB,
		"near confirm ranges %+.1f dB to %+.1f dB over the bed" % [near_worst, near_best])
	_advance(5)
	return false


func _whisper_is_permanent() -> bool:
	var far := _crate.get_node_or_null("CrateCallFar") as AudioStreamPlayer3D
	var near := _crate.get_node_or_null("CrateCallNear") as AudioStreamPlayer3D
	# ⚠️ REAL SECONDS. The guarantee is "it never stops while the box is shut" — no timeout,
	# no one-shot, no distance gate — and the only way to see a stop is to let time pass.
	_ok("the whisper is still calling %.0f s later, with the box still shut" % WHISPER_WATCH,
		far != null and near != null and far.playing and near.playing
		and not bool(_crate.call("is_opened")),
		"far playing=%s near playing=%s" % [far.playing, near.playing])
	_advance(6)
	return false


# ------------------------------------------------- COLD START: walk to it and open it

func _open_the_crate() -> bool:
	print("\n--- cold start: walk to the box, open it, watch the run ---")
	_real_before = String(_zone.call("real_side"))
	var congregation_before := _count_watchers()

	# ⚠️ WALKED, NOT TELEPORTED, for the last stretch: the point of a cold start is that the
	# shipping raycast, `can_interact()` and the prompt path all run from a pose a player
	# could really have arrived in. `_reads()` places and aims; `ai_interact()` presses E.
	_walk_from = _player.global_position
	_reads(_crate, REACH_DIST, 0.0)
	_ok("the player crossed the hall to reach the box",
		_walk_from.distance_to(_player.global_position) > 5.0,
		"%.1f m from the spawn" % _walk_from.distance_to(_player.global_position))
	_ok("the shipping prompt offers it", _player.call("ai_interact_target") != null)
	_player.call("ai_interact")
	_ok("pressing E opens the crate", bool(_crate.call("is_opened")))
	_ok("...and it goes inert afterwards", not bool(_crate.call("can_interact")))

	var dweller := _zone.get_node_or_null("SprawlDweller")
	_ok("something comes out of it", dweller != null)
	# ⚠️ AND IT HAS NOT SET OFF YET. The run is deferred by one `flash_scare` hold so the
	# player is not made to watch it through a fullscreen image. Measuring this in the frame
	# of the press is the whole of Issue 113, so it is measured as a NEGATIVE here and as a
	# positive twelve seconds later.
	_ok("...and it has not started running while the scare image is up",
		dweller != null and not bool(dweller.get("_running")))
	if dweller != null:
		# ⚠️ NOT A Watcher, and not one of the Congregation's — see the header.
		var watcher_script: GDScript = load("res://scripts/watcher.gd")
		_ok("the runner is its own object, not a Congregation figure",
			dweller.get_script() != watcher_script
			and String(dweller.get_script().resource_path).contains("sprawl_dweller"))
		_ok("...and the Congregation is untouched by it",
			_count_watchers() == congregation_before,
			"%d figures before, %d after" % [congregation_before, _count_watchers()])
		var bad: Array[String] = []
		for n in _all(dweller, []):
			if n.get_script() == load("res://scripts/scary_object.gd") \
					or n is Area3D or n is CollisionShape3D:
				bad.append(String(n.name))
		_ok("the runner has no collider, no gaze term and no kill radius", bad.is_empty(),
			"found: %s" % ", ".join(bad))
		# It must start OUTSIDE the recess it came from rather than inside the geometry.
		var d := (dweller as Node3D).global_position.distance_to(
			(_crate as Node3D).global_position)
		_ok("it spawns clear of the crate, out in the hall", d > 0.8 and d < 4.0,
			"%.2f m from the crate" % d)
	# Deliberately aim the player AWAY from the run, so the camera pin has something to do.
	_yaw_at_run = _player.rotation.y
	_advance(7)
	return false


func _the_mark() -> bool:
	var real: String = String(_zone.call("real_side"))
	_ok("the real wall did not change while the runner crossed the hall",
		real == _real_before, "%s -> %s" % [_real_before, real])
	_ok("the runner reached a wall and is gone", bool(_zone.call("dweller_has_run"))
		and _zone.get_node_or_null("SprawlDweller") == null,
		"has_run=%s node=%s" % [bool(_zone.call("dweller_has_run")),
			_zone.get_node_or_null("SprawlDweller")])

	# THE CAMERA WAS FORCED ONTO IT (B-S2). Both halves: the player was pinned, and the view
	# actually moved. Sampled every frame since the press, never in the frame of the press.
	_ok("the player was frozen for the run", _frozen_seen)
	_ok("...and the camera was turned onto it", _turned > 20.0,
		"the view swung %.1f° from where it was pointing when the box opened" % _turned)
	_ok("...and control came back afterwards",
		not bool(_player.call("is_input_frozen")))

	# THE MARK. Motion, not brightness: the shader's own vertex-jitter amplitude.
	var marked: Array[String] = []
	for s in ["N", "S", "E", "W"]:
		var w: GlitchWall = _zone.get("_walls")[s]
		if is_instance_valid(w) and w.is_agitated():
			marked.append(s)
	_ok("exactly one wall is marked", marked.size() == 1,
		"marked: %s" % ", ".join(marked))
	_ok("...and it is the REAL one", marked.size() == 1 and marked[0] == real,
		"marked %s, real %s" % [", ".join(marked), real])

	# THE GATE OPENED, and nothing else did.
	_ok("the wall it ran through is no longer sealed",
		not bool(_zone.call("real_wall_is_sealed")))
	_ok("...and no fake was opened by it", not _any_fake_sealed()
		and _sealed_walls().is_empty(), "sealed: %s" % ", ".join(_sealed_walls()))

	# ...and the voice that led the player into the dark now comes from that wall.
	var wall: Node3D = _zone.get("_walls")[real]
	var voices := 0
	for c in wall.get_children():
		if c is AudioStreamPlayer3D and c.stream != null \
				and String(c.stream.resource_path).contains("sprawl_call"):
			voices += 1
	_ok("the whisper it carried now comes from the wall it left through", voices == 2,
		"%d of 2 layers" % voices)
	# The crate is silent: the voice LEFT it, it was not duplicated.
	var left := 0
	for c in _crate.get_children():
		if c is AudioStreamPlayer3D and c.stream != null \
				and String(c.stream.resource_path).contains("sprawl_call"):
			left += 1
	_ok("...and no copy of it was left behind in the box", left == 0, "%d left" % left)

	# ⚠️ AND THE ORIGINAL TELL IS STILL THERE. It is flavour and confirmation now rather than
	# the route, and removing it would leave the wall silent until the runner arrives.
	var water: AudioStreamPlayer3D = _zone.get("_tell_water")
	var whisper: AudioStreamPlayer3D = _zone.get("_tell_whisper")
	_ok("the real wall still carries its own water + whisper tell",
		water != null and whisper != null and water.playing and whisper.playing)
	if water != null and whisper != null:
		_ok("...positioned AT the real wall, on Master",
			water.global_position.distance_to(wall.global_position) < 0.6
			and water.bus == "Master" and whisper.bus == "Master")
	var pocket := _zone.get_node_or_null("SilencePocket")
	_ok("the silence pocket is still there, at the real wall", pocket != null
		and (pocket as Node3D).global_position.distance_to(wall.global_position) < 6.0)

	# NOW walk into it. Real Area3D, no emit.
	var inward: Vector3 = (_zone.global_position - wall.global_position).normalized()
	_player.global_position = wall.global_position + inward * 0.6
	_player.call("force_update_transform")
	_advance(8)
	return false


func _walk_through_it() -> bool:
	# ⚠️ THE COMPLETABILITY ASSERTION. Cold start -> whisper -> box -> run -> wall -> out,
	# and `cleared` was never emitted by this test.
	_ok("walking into the wall the runner opened CLEARS the zone (real Area3D, no emit)",
		_cleared == 1, "cleared fired %d time(s)" % _cleared)
	_ok("...and it cost no strikes on the way", _mistakes == 0,
		"%d mistake(s)" % _mistakes)
	_player.global_position = _zone.get("spawn_point")
	_player.call("force_update_transform")
	_advance(9)
	return false


func _touch_a_fake() -> bool:
	print("\n--- the mark may not lie: out a fake and the answer moves ---")
	_real_before = String(_zone.call("real_side"))
	# Touch a fake through its own trigger, the way a player does.
	var fake := ""
	for s in ["N", "S", "E", "W"]:
		if s != _real_before:
			fake = s
			break
	var w: Node3D = _zone.get("_walls")[fake]
	_player.global_position = w.global_position \
		+ (_zone.global_position - w.global_position).normalized() * 0.6
	_player.call("force_update_transform")
	_advance(10)
	return false


func _mark_follows_a_reroll() -> bool:
	var before: String = _real_before
	var after: String = String(_zone.call("real_side"))
	_ok("touching a fake was registered as a mistake", _mistakes >= 1,
		"%d mistake(s)" % _mistakes)
	var marked: Array[String] = []
	for s in ["N", "S", "E", "W"]:
		var g: GlitchWall = _zone.get("_walls")[s]
		if is_instance_valid(g) and g.is_agitated():
			marked.append(s)
	_ok("the mark moved with the answer rather than lying about the old one",
		marked.size() == 1 and marked[0] == after,
		"real %s -> %s, marked %s" % [before, after, ", ".join(marked)])
	# ⚠️ AND THE GATE STAYS OPEN. The runner has been through; a re-roll must not put the
	# seal back on the new answer, or a single wrong wall would strand the player for good.
	_ok("the promoted wall is NOT re-sealed once the runner has been through",
		not bool(_zone.call("real_wall_is_sealed")))

	_ok("nothing in the whole sequence added panic", _panic_step < 0.02,
		"largest single-frame panic step %.4f of the bar" % _panic_step)
	_ok("the panic audit sampled the whole run", _panic_samples > 600,
		"%d frames" % _panic_samples)
	return _report()


# ------------------------------------------------------------------------- helpers

# Every point on a 1 m grid inside the hall and inside the eight recesses, at ear height.
# Derived from the zone's own constants, so the grid moves if the room does.
func _standable_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	# ⚠️ `Object.get()` does NOT reach a `const` — constants are not properties, and the
	# call returns null, which silently becomes 0.0 and collapses the grid to one point.
	var k_map: Dictionary = (_zone.get_script() as GDScript).get_script_constant_map()
	var half: float = float(k_map["HALF"])
	var d: float = float(k_map["ALCOVE_D"])
	var wdt: float = float(k_map["ALCOVE_W"])
	var at: float = float(k_map["ALCOVE_AT"])
	var axes: Dictionary = k_map["SIDE_AXIS"]
	var o: Vector3 = _zone.global_position
	var x := -half + 1.0
	while x <= half - 1.0:
		var z := -half + 1.0
		while z <= half - 1.0:
			out.append(o + Vector3(x, 1.6, z))
			z += 1.0
		x += 1.0
	for s in ["N", "S", "E", "W"]:
		var axis: Vector3 = axes[s]
		for k in [-1.0, 1.0]:
			var c: Vector3 = o + axis * (half + d / 2.0) \
				+ Vector3(axis.z, 0, axis.x) * (k * at)
			for a in [-1.0, 0.0, 1.0]:
				for b in [-1.0, 0.0, 1.0]:
					out.append(c + Vector3(a * wdt / 3.0, 1.6, b * d / 3.0))
	return out


# Godot's inverse-distance attenuation, in dB, capped at the emitter's own max_db.
func _level_at(a: AudioStreamPlayer3D, listener: Vector3) -> float:
	var d: float = maxf(0.1, a.global_position.distance_to(listener))
	return minf(a.max_db, a.volume_db + 20.0 * (log(a.unit_size / d) / log(10.0)))


# RMS of the SOURCE .wav on disk, in dBFS — it must read the FILE, because this project
# imports .wav as QOA and the in-memory bytes are not PCM. Non-.wav sources return -999,
# which callers treat as "no data" rather than as silence.
func _rms_dbfs(res_path: String) -> float:
	if res_path == "" or not res_path.ends_with(".wav"):
		return -999.0
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return -999.0
	var bytes: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return -999.0
	var pos := 12
	var data_at := -1
	var data_len := 0
	while pos + 8 <= bytes.size():
		var id: String = bytes.slice(pos, pos + 4).get_string_from_ascii()
		var sz: int = bytes.decode_u32(pos + 4)
		if id == "data":
			data_at = pos + 8
			data_len = sz
			break
		pos += 8 + sz + (sz & 1)
	if data_at < 0:
		return -999.0
	var n: int = mini(data_len, bytes.size() - data_at) / 2
	if n <= 0:
		return -999.0
	var acc := 0.0
	var step: int = maxi(1, n / 40000)
	var used := 0
	for i in range(0, n, step):
		var v: float = float(bytes.decode_s16(data_at + i * 2)) / 32768.0
		acc += v * v
		used += 1
	if used == 0:
		return -999.0
	return 20.0 * (log(sqrt(acc / float(used)) + 1e-12) / log(10.0))


func _sealed_walls() -> Array[String]:
	var out: Array[String] = []
	for s in ["N", "S", "E", "W"]:
		var w: GlitchWall = _zone.get("_walls").get(s)
		if is_instance_valid(w) and w.is_sealed():
			out.append(s)
	return out


func _sealed_fakes() -> Array[String]:
	var real: String = String(_zone.call("real_side"))
	var out: Array[String] = []
	for s in _sealed_walls():
		if s != real:
			out.append(s)
	return out


func _any_fake_sealed() -> bool:
	return not _sealed_fakes().is_empty()


func _count_crates() -> int:
	var n := 0
	var s: GDScript = load("res://scripts/sprawl_crate.gd")
	for c in _all(_zone, []):
		if c.get_script() == s:
			n += 1
	return n


func _count_alc_props() -> int:
	var n := 0
	for c in _zone.get_children():
		if String(c.name).begins_with("AlcProp"):
			n += 1
	return n


func _count_watchers() -> int:
	var n := 0
	var s: GDScript = load("res://scripts/watcher.gd")
	for c in _all(_zone, []):
		if c.get_script() == s:
			n += 1
	return n


func _reads(prop: Node3D, dist: float, off_axis: float) -> Node:
	var aabb := _world_aabb(prop)
	var aim: Vector3 = aabb.get_center()
	var radius: float = maxf(aabb.size.x, aabb.size.z) * 0.5
	# Approach from the hall centre — the open side of the recess.
	var toward: Vector3 = _zone.global_position - prop.global_position
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


func _world_aabb(root_node: Node) -> AABB:
	var out := AABB()
	var first := true
	for n in _all(root_node, []):
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null \
				and (n as Node3D).visible:
			var mi := n as MeshInstance3D
			var box := mi.global_transform * mi.mesh.get_aabb()
			if first:
				out = box
				first = false
			else:
				out = out.merge(box)
	if first and root_node is Node3D:
		out = AABB((root_node as Node3D).global_position - Vector3(0.2, 0.2, 0.2),
			Vector3(0.4, 0.4, 0.4))
	return out


func _all(n: Node, acc: Array) -> Array:
	for c in n.get_children():
		acc.append(c)
		_all(c, acc)
	return acc
