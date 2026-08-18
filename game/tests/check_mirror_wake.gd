extends SceneTree

# `mirror_wake` — the sound the Corridor's turn mirrors make when the glass comes alive.
#
#   Godot --headless --path game --script res://tests/check_mirror_wake.gd
#
# User request, 2026-08-16: *"The mirror appears out of nowhere. I think it is good,
# generate a noisy sound for it so that it would scary the player."*
#
# WHY THIS FILE EXISTS. Every failure mode of a new sound in this project is SILENT:
#   * the .wav is never imported, so `load_audio()` returns null and `_play_at` returns
#     early — no error, no sound, nothing in the log
#   * the base name collides with an existing one in another subdir, and `load_audio()`
#     resolves the WRONG file (`door_slam` already exists twice and the corridor copy wins)
#   * the one-shot flag is missed, so it re-fires every frame you stand inside 14 m
#   * the facing gate is inverted, so it fires at the player's back on the way OUT
# None of those would fail a smoke test and none would fail a screenshot.
#
# It also pins the beat to the RIGHT distance: the cue is fired at
# `MirrorSurface.ACTIVE_DIST`, the same constant that switches the SubViewport from
# UPDATE_DISABLED to UPDATE_ALWAYS, because the sound is what the picture is doing.

const SCENE := "res://scenes/corridor.tscn"
const BASE := "mirror_wake"

var _t := 0.0
var _fails: Array[String] = []
var _checks := 0
var _scene: Node
var _player: CharacterBody3D = null


func _initialize() -> void:
	change_scene_to_file(SCENE)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print("  %s  %s%s" % ["OK  " if cond else "FAIL", label, ("  " + detail) if detail else ""])
	if not cond:
		_fails.append(label)


# Every AudioStreamPlayer3D under the level that is playing OUR sample, right now.
func _wake_players() -> int:
	var n := 0
	for c in _scene.get_children():
		if c is AudioStreamPlayer3D:
			var st: AudioStream = (c as AudioStreamPlayer3D).stream
			if st != null and st.resource_path.get_file().get_basename() == BASE:
				n += 1
	return n


# Point the player at a world position. The camera is a child at local (0, 1.65, 0) with
# only PITCH of its own, so the player's yaw is what `_facing_dot` reads.
func _face(from: Vector3, target: Vector3) -> void:
	var d := target - from
	d.y = 0.0
	d = d.normalized()
	_player.global_position = Vector3(from.x, 0.0, from.z)
	_player.rotation.y = atan2(-d.x, -d.z)


func _process(delta: float) -> bool:
	_t += delta
	if _t < 1.0:
		return false
	_scene = current_scene
	_player = _scene.get_node_or_null("Player") as CharacterBody3D
	_ok("the player exists", _player != null)
	if _player == null:
		return _report()

	# ---- 1. the asset actually resolves -------------------------------------------------
	# ⚠️ Through the NODE, never the bare identifier. A `--script` tool is parsed before the
	# autoloads exist, so `GameState.load_audio(...)` is a COMPILE error — and a test that
	# fails to compile exits 0 (Issue 44). Same convention as check_bus_leak/check_journal.
	var gs: Node = root.get_node_or_null("/root/GameState")
	_ok("the GameState autoload is present", gs != null)
	if gs == null:
		return _report()
	var subdirs_v: Variant = gs.get_script().get("AUDIO_SUBDIRS")
	var subdirs: Array = subdirs_v if subdirs_v is Array else []
	var stream: AudioStream = gs.call("load_audio", BASE)
	_ok("load_audio(\"%s\") resolves" % BASE, stream != null,
		stream.resource_path if stream != null else "null — was --import run?")
	if stream != null:
		_ok("and it is a real stream with length", stream.get_length() > 0.5,
			"%.2f s" % stream.get_length())

	# ---- 2. the base name is globally unique --------------------------------------------
	# ⚠️ `load_audio()` walks a HARDCODED subdir list and the first hit wins, so a duplicate
	# base name anywhere in the tree silently redirects this sound to another level's file.
	var hits: Array[String] = []
	for sub in subdirs:
		var dir := "res://assets/audio/%s/" % sub
		var da := DirAccess.open(dir)
		if da == null:
			continue
		for f in da.get_files():
			var clean := f.trim_suffix(".import").trim_suffix(".remap")
			if clean.get_basename() == BASE:
				hits.append(dir + clean)
	# The same file shows up once as `x.wav` and once as `x.wav.import`; dedup by path.
	var uniq := {}
	for h in hits:
		uniq[h] = true
	_ok("the base name is unique across every audio subdir", uniq.size() == 1,
		"%d file(s): %s" % [uniq.size(), str(uniq.keys())])
	_ok("audio subdirs were actually scanned", subdirs.size() >= 5,
		"%d subdirs" % subdirs.size())

	# ---- 3. behaviour, driven through the real function ---------------------------------
	var mirrors_v: Variant = _scene.get("_turn_mirrors")
	var mirrors: Array = mirrors_v if mirrors_v is Array else []
	_ok("there are turn mirrors to test", mirrors.size() >= 1, "%d" % mirrors.size())
	if mirrors.is_empty():
		return _report()

	var active: float = float(load("res://scripts/mirror_surface.gd").get("ACTIVE_DIST"))
	_ok("the cue is tied to MirrorSurface.ACTIVE_DIST", active > 1.0, "%.1f m" % active)

	# ⚠️ Captured ONCE, before anything moves the player. Recomputing it inside the loop
	# reads the position this test itself just set, which silently makes every mirror after
	# the first one test a direction of its own making.
	var spawn: Vector3 = _player.global_position

	var tested := 0
	for m in mirrors:
		var mp: Vector3 = m.pos
		# A direction to stand off in. Only the distance and the facing are under test, so
		# any consistent horizontal bearing does; the level entrance is a real one.
		var approach: Vector3 = spawn - mp
		approach.y = 0.0
		if approach.length() < 1.0:
			approach = Vector3(0, 0, -1)
		approach = approach.normalized()

		m.woke = false
		var before := _wake_players()

		# (a) OUTSIDE the gate, facing it — must stay silent.
		_face(mp + approach * (active + 6.0), mp)
		_scene.call("_tick_mirror_wake", m, _player.global_position)
		_ok("mirror @%s: silent at %.0f m" % [str(mp.round()), active + 6.0],
			_wake_players() == before and not bool(m.woke))

		# (b) INSIDE the gate but facing AWAY — must stay silent, and must NOT burn the
		#     one-shot. This is the "it fired at my back on the way out" failure.
		# ⚠️ The look target is FURTHER ALONG the approach vector, i.e. away from the glass.
		# `mp - approach * 50` would be 50 m on the far side of the mirror, which points the
		# player straight THROUGH it — a facing test that passes and proves nothing.
		_face(mp + approach * (active * 0.6), mp + approach * 60.0)
		_scene.call("_tick_mirror_wake", m, _player.global_position)
		_ok("mirror @%s: silent when it is behind you" % str(mp.round()),
			_wake_players() == before and not bool(m.woke))

		# (c) INSIDE and facing it — fires, exactly once.
		var panic_before: float = _player.get_panic_ratio()
		_face(mp + approach * (active * 0.6), mp)
		_scene.call("_tick_mirror_wake", m, _player.global_position)
		var after_first := _wake_players()
		_ok("mirror @%s: fires on approach" % str(mp.round()), after_first == before + 1,
			"%d -> %d players" % [before, after_first])
		_ok("mirror @%s: and it is marked woken" % str(mp.round()), bool(m.woke))

		# (d) five more ticks in range — still exactly one.
		for i in range(5):
			_scene.call("_tick_mirror_wake", m, _player.global_position)
		_ok("mirror @%s: it is a one-shot, not a per-frame loop" % str(mp.round()),
			_wake_players() == after_first,
			"%d players after 6 ticks" % _wake_players())

		# (e) ZERO PANIC. The corner already carries TURN_MIRROR_PANIC 12 and a 30-40/s gaze
		#     panel; this is a channel, not a term.
		_ok("mirror @%s: the cue costs no panic" % str(mp.round()),
			is_equal_approx(_player.get_panic_ratio(), panic_before),
			"%.4f -> %.4f" % [panic_before, _player.get_panic_ratio()])
		tested += 1

	_ok("every turn mirror was exercised", tested == mirrors.size(),
		"%d of %d" % [tested, mirrors.size()])

	# ---- 4. the level's existing 2 m sting is UNTOUCHED ---------------------------------
	# The wake cue is a second beat 12 m earlier, not a replacement for and not a doubling of
	# the existing `flash_scare(..., "glass_shatter")` at TURN_MIRROR_SCARE_DIST. If the two
	# are ever collapsed into one, this is what notices.
	var cs: GDScript = _scene.get_script()
	_ok("the 2 m sting still fires at its own distance",
		is_equal_approx(float(cs.get("TURN_MIRROR_SCARE_DIST")), 2.0),
		"%.2f m" % float(cs.get("TURN_MIRROR_SCARE_DIST")))
	_ok("and still costs TURN_MIRROR_PANIC 12",
		is_equal_approx(float(cs.get("TURN_MIRROR_PANIC")), 12.0),
		"%.1f" % float(cs.get("TURN_MIRROR_PANIC")))
	# ⚠️ 2026-08-17: this used to read `active > STING_DIST * 4.0`, which is a RATIO, and a
	# ratio is the wrong shape for the property. What has to hold is that the two are far
	# enough apart to be two BEATS rather than one layered event — the level's own note on the
	# cue puts that at "12 m apart" when ACTIVE_DIST was 14. It is 7 now (the user asked for
	# the mirror to wake much closer), and 5 m of separation is still about 1.3 s of walking
	# between the wake and the sting. Asserted as a gap, with a ratio floor kept as a second
	# guard against someone shrinking the sting instead.
	var sting: float = float(cs.get("TURN_MIRROR_SCARE_DIST"))
	_ok("the wake cue and the 2 m sting are separate beats",
		active - sting >= 4.0 and active >= sting * 3.0,
		"gap %.1f m (%.1f m vs %.1f m)" % [active - sting, active, sting])
	_ok("the wake cue's facing gate is a real cone",
		float(cs.get("MIRROR_WAKE_FACING")) > 0.0 and float(cs.get("MIRROR_WAKE_FACING")) < 1.0,
		"dot %.2f" % float(cs.get("MIRROR_WAKE_FACING")))

	_check_stare(mirrors, cs)
	return _report()


# ---- 5. THE STARE TELL (2026-08-17) -------------------------------------------------------
#
# The second mirror sound, and the one that exists because a player DIED at the 275 m glass:
# 36 % -> 73 % -> 97 % in fifteen seconds of standing still, which is that mirror's own gaze
# panel at 44 panic/s. The user's ruling was to leave the cost alone and make it legible.
#
# Everything here is a failure mode that is SILENT in play, exactly like §1-3 above:
#   * the loop is not restarted, so the tell plays once and then leaves you in silence while
#     the panel keeps charging — the precise failure it exists to prevent
#   * the facing gate is missing, so it plays at anyone who walks past
#   * it never stops, so a mirror hums for the rest of the level
#   * it acquires a panic term, which would be taxing the same posture twice (Issue 18)
func _check_stare(mirrors: Array, cs: GDScript) -> void:
	var gs: Node = root.get_node_or_null("/root/GameState")
	var stream: AudioStream = gs.call("load_audio", "mirror_stare")
	_ok("load_audio(\"mirror_stare\") resolves", stream != null,
		stream.resource_path if stream != null else "null — was --import run?")

	var range_m: float = float(cs.get("MIRROR_STARE_RANGE"))
	var ramp: float = float(cs.get("MIRROR_STARE_RAMP"))
	var release: float = float(cs.get("MIRROR_STARE_RELEASE"))
	# ⚠️ The tell must cover the volume the panel actually charges in. player.gd's GAZE_RANGE
	# is the authority; a tell with a shorter reach than the damage is a tell that arrives
	# after the damage has started.
	var gaze_range: float = float(load("res://scripts/player.gd").get("GAZE_RANGE"))
	_ok("the stare tell reaches as far as player.gd's GAZE_RANGE",
		range_m >= gaze_range - 0.001, "%.1f m vs %.1f m" % [range_m, gaze_range])
	_ok("the ramp is a real ramp, not instant", ramp >= 1.0 and ramp <= 6.0, "%.1f s" % ramp)

	var tested := 0
	for m in mirrors:
		var p: AudioStreamPlayer3D = m.get("stare_player")
		var label := "mirror @%s" % str((m.pos as Vector3).round())
		_ok("%s: has a stare emitter" % label, p != null and is_instance_valid(p))
		if p == null or not is_instance_valid(p):
			continue
		_ok("%s: the emitter is positional AND at the glass" % label,
			p.global_position.distance_to(m.pos) < 0.01)
		# ⚠️ Every .wav.import here is loop_mode=0. This connection IS the loop.
		_ok("%s: the loop restarts itself (finished -> play)" % label,
			p.finished.is_connected(p.play))
		_ok("%s: it starts silent" % label, not p.playing)

		var mp: Vector3 = m.pos
		var approach: Vector3 = (_player.global_position - mp)
		approach.y = 0.0
		if approach.length() < 1.0:
			approach = Vector3(0, 0, -1)
		approach = approach.normalized()

		# (a) inside range but looking AWAY — silent, meter stays down.
		m.stare = 0.0
		_face(mp + approach * (range_m * 0.5), mp + approach * 60.0)
		for i in range(20):
			_scene.call("_tick_mirror_stare", m, _player.global_position, 0.1)
		_ok("%s: silent while you look away inside range" % label,
			not p.playing and is_zero_approx(float(m.stare)))

		# (b) outside range but looking straight at it — silent. The gaze panel does not
		#     charge out here either.
		_face(mp + approach * (range_m + 4.0), mp)
		for i in range(20):
			_scene.call("_tick_mirror_stare", m, _player.global_position, 0.1)
		_ok("%s: silent from outside the gaze range" % label,
			not p.playing and is_zero_approx(float(m.stare)))

		# (c) close AND looking at it — climbs, and reaches full in about MIRROR_STARE_RAMP.
		var panic_before: float = _player.get_panic_ratio()
		_face(mp + approach * (range_m * 0.5), mp)
		_scene.call("_tick_mirror_stare", m, _player.global_position, 0.1)
		var first_db: float = p.volume_db
		var first_pitch: float = p.pitch_scale
		_ok("%s: starts playing when you hold the stare" % label, p.playing)
		var steps := int(ceil(ramp / 0.1)) + 2
		for i in range(steps):
			_scene.call("_tick_mirror_stare", m, _player.global_position, 0.1)
		_ok("%s: it gets LOUDER as the stare is held" % label, p.volume_db > first_db + 6.0,
			"%.1f -> %.1f dB" % [first_db, p.volume_db])
		_ok("%s: and the pulse gets FASTER (pitch)" % label,
			p.pitch_scale > first_pitch + 0.1, "%.2f -> %.2f" % [first_pitch, p.pitch_scale])
		_ok("%s: the meter saturates at 1.0" % label, is_equal_approx(float(m.stare), 1.0),
			"%.3f" % float(m.stare))

		# (d) look away — it falls back to silence and STOPS. A mirror humming for the rest
		#     of the level is how this feature would fail quietly.
		_face(mp + approach * (range_m * 0.5), mp + approach * 60.0)
		for i in range(int(ceil(1.0 / release / 0.1)) + 4):
			_scene.call("_tick_mirror_stare", m, _player.global_position, 0.1)
		_ok("%s: it stops when you look away" % label,
			not p.playing and is_zero_approx(float(m.stare)))

		# (e) ZERO PANIC, over the whole cycle. The point is to make an EXISTING cost legible.
		_ok("%s: the stare tell costs no panic at all" % label,
			is_equal_approx(_player.get_panic_ratio(), panic_before),
			"%.4f -> %.4f" % [panic_before, _player.get_panic_ratio()])
		tested += 1

	_ok("every mirror's stare tell was exercised", tested == mirrors.size() and tested > 0,
		"%d of %d" % [tested, mirrors.size()])
	# ⚠️ The gaze panels themselves are UNTOUCHED and must stay that way — this whole feature
	# was accepted on the condition that the cost does not change.
	var table: Array = cs.get("TURN_MIRRORS")
	_ok("the mirrors' gaze intensities are still 1.5 and 2.2", table.size() == 2
		and is_equal_approx(float(table[0][1]), 1.5) and is_equal_approx(float(table[1][1]), 2.2),
		str(table))


func _report() -> bool:
	print("  %d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL — ", ", ".join(_fails))
		quit(1)
	return true
