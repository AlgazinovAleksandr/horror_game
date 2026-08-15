extends SceneTree

# The Backrooms mix: the score must be the thing you hear, and no other zone's
# ambience may follow the player into the Lobby.
#
#   Godot --headless --path game --script res://tests/check_backrooms_audio.gd
#
# Why this exists. Two audio regressions shipped and survived for weeks, and NEITHER
# could fail a test the suite had — a scene smoke test loads a level with a silent
# mixer and reports PASS:
#
#   1. THE_FLOOD's drip ticker (backrooms_zone3.gd:_process) is not gated on the player
#      being in the Flood, and all three zones are built at level start. It followed the
#      player around the LOBBY, dropping a wet plink beside them every 3-8 s, 200 m from
#      any water, for the entire level.
#   2. The Lobby phone was given KONTUR's ring settings (0 dB, unit_size 12, Master bus).
#      Measured against the files, that put it ~3 dB ABOVE the score, from 3 m away, on a
#      bus no SilenceZone or HoldBreath dip can duck — the loudest recurring sound in a
#      level whose identity is its music.
#
# So the assertions are about RELATIVE LEVELS and ROUTING, which is what "I cannot hear
# the music" actually means, rather than about any sound merely existing.

const SCENE := "res://scenes/backrooms.tscn"
const BUS := "Backrooms"

# How long to watch each place. The drip fires every 3-8 s, so 20 s is ~3-6 chances to
# catch a leak and enough time for at least one real drip in the Flood.
const LOBBY_WATCH := 20.0
const FLOOD_WATCH := 25.0

var _t := 0.0
var _phase := 0
var _scene: Node
var _player: Node3D
var _lobby_drips := 0
var _flood_drips := 0
var _heard: Dictionary = {}   # stream file -> volume_db, for everything self-starting nearby
var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	change_scene_to_file(SCENE)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("  OK    ", label, ("  " + detail) if detail else "")
	else:
		print("  FAIL  ", label, ("  " + detail) if detail else "")
		_fails.append(label)


func _process(delta: float) -> bool:
	_t += delta
	# ⚠️ A DEAD SCENE MUST FAIL, LOUDLY. If the player dies the level reloads, `_scene` and
	# `_player` are freed, and every subsequent `_scene.get_node_or_null(...)` raises — and
	# a GDScript runtime error ABORTS THE CALLING FUNCTION, so each remaining assertion is
	# skipped rather than failed. This test printed "16 checks, 0 failed / RESULT: PASS"
	# having measured neither the footsteps nor the water. ISSUES_SOLUTIONS Issue 45, in a
	# new costume.
	if _phase > 0 and (not is_instance_valid(_scene) or not is_instance_valid(_player)):
		print("  FAIL  the level survived the run  scene reloaded at t=%.1fs "
			% _t + "(a death — the probe cannot measure a level that restarted)")
		_fails.append("the level survived the run")
		return _report()
	# ⚠️ EVERY FRAME, not once. This probe stands still by design, and the maze charges
	# +3/s for that (restored in the Flood on purpose). One call at startup was not enough:
	# `_maybe_spawn_smiler()` clears a previous Smiler with `set_smiler_active(false)`,
	# which silently re-armed the tax and killed the run 21 s into the Flood — turning the
	# whole measurement into the vacuous pass above.
	if _phase > 0:
		_player.set_smiler_active(true)
	match _phase:
		0:
			if _t < 1.0:
				return false
			_scene = current_scene
			_player = _scene.get_node_or_null("Player") as Node3D
			if _player == null:
				print("FAIL: no Player in ", SCENE)
				quit(1)
				return true
			# This test stands still on purpose; the maze charges +3/s for that and would
			# kill it mid-measurement, taking the scene with it.
			_player.call("set_smiler_active", true)
			_mix()
			_phase = 1
		1:
			_lobby_drips += _new_drips()
			_watch_levels()
			if _t > 1.0 + LOBBY_WATCH:
				_levels()
				_footsteps("Lobby", false)
				var z3 := _scene.get_node_or_null("ZoneFlood")
				if z3 == null:
					print("FAIL: no ZoneFlood")
					quit(1)
					return true
				_player.global_position = z3.get("spawn_point")
				_phase = 2
		2:
			_flood_drips += _new_drips()
			if _t > 1.0 + LOBBY_WATCH + FLOOD_WATCH:
				_footsteps("Flood", false)
				_water_bed()
				_drips()
				return _report()
	return false


# --------------------------------------------------------------- the mix

func _mix() -> void:
	var music: AudioStreamPlayer = _scene.get_node_or_null("MusicPlayer")
	var hum: AudioStreamPlayer = _scene.get_node_or_null("AmbientPlayer")
	_ok("the score is playing", music != null and music.playing)
	if music == null:
		return
	_ok("the score is on the level bed bus", music.bus == BUS, music.bus)
	_ok("the hum is on the level bed bus", hum != null and hum.bus == BUS)

	# The bed bus must nest under Ambience, or a HoldBreath dip does nothing here — the
	# level that fires flash_scare on every wrong turn is the one that most needs it.
	var idx := AudioServer.get_bus_index(BUS)
	_ok("the bed bus exists", idx != -1)
	if idx != -1:
		_ok("the bed bus nests under Ambience", AudioServer.get_bus_send(idx) == "Ambience",
			AudioServer.get_bus_send(idx))
		_ok("the bed bus is not left ducked", AudioServer.get_bus_volume_db(idx) > -1.0,
			"%.1f dB" % AudioServer.get_bus_volume_db(idx))

	var phone := _find_stream(_scene, "phone_ringing")
	_ok("the Lobby phone exists", phone != null)
	if phone != null:
		_ok("the Lobby ring rides the bed bus, not Master", phone.bus == BUS, phone.bus)
		_ok("the Lobby ring sits under the score", phone.volume_db < music.volume_db,
			"%+.1f dB vs score %+.1f" % [phone.volume_db, music.volume_db])


# Sampled every frame of the Lobby watch: anything that STARTS ITSELF near the player and
# plays louder than the score. Sampling over time rather than once is what catches a
# recurring sound — the phone is silent between bursts, so a single snapshot can miss the
# very thing this test exists for.
#
# ⚠️ Only self-starting sources count. A footstep, a smashed phone or an answered call are
# LOUD ON PURPOSE: the player asked for them, and the `Body` bus is deliberately never
# ducked (audio_buses.gd). The invariant is about ambience the player did not choose.
func _watch_levels() -> void:
	var music: AudioStreamPlayer = _scene.get_node_or_null("MusicPlayer")
	if music == null:
		return
	for p in _emitters(_scene):
		if not (p is AudioStreamPlayer3D) or not p.playing or p.bus == AudioBuses.BODY:
			continue
		if p.global_position.distance_to(_player.global_position) > 15.0:
			continue
		_heard[_stream_of(p)] = p.volume_db


func _levels() -> void:
	var music: AudioStreamPlayer = _scene.get_node_or_null("MusicPlayer")
	var loud: Array[String] = []
	for name in _heard:
		if _heard[name] > music.volume_db:
			loud.append("%s %+.1fdB" % [name, _heard[name]])
	_ok("self-starting sound heard near the spawn", not _heard.is_empty(),
		", ".join(_heard.keys()))
	_ok("none of it is louder than the score", loud.is_empty(), ", ".join(loud))


# --------------------------------------------------------------- the drip gate

# The Flood must SOUND flooded, and a `volume_db` cannot tell you whether it does.
#
# `water.wav` measures -39.6 dBFS RMS — roughly 20 dB below every other asset in this
# level. At the -6 dB it originally shipped with, the bed landed near -46 dBFS: four
# players faithfully looping a sound nobody could hear, in the level's one flooded wing,
# while the per-step splash ran 22 dB louder. Every structural test passed throughout.
#
# So this measures the SAMPLE DATA and adds the gain, and asserts the result clears an
# absolute audibility floor. It is the only assertion here that could have caught it.
const WATER_FLOOR_DBFS := -32.0

func _water_bed() -> void:
	var z3 := _scene.get_node_or_null("ZoneFlood")
	if z3 == null:
		return
	var beds: Array[Node] = []
	for c in z3.get_children():
		if c is AudioStreamPlayer3D and String(c.name).begins_with("WaterBed_"):
			beds.append(c)
	# One per room: a room added to ROOMS without a bed is a dry room in a flooded wing.
	var rooms: int = z3.get("ROOMS").size()
	_ok("every Flood room has a water bed", beds.size() == rooms,
		"%d beds / %d rooms" % [beds.size(), rooms])

	var playing := 0
	for b in beds:
		if b.playing:
			playing += 1
	_ok("the water beds are playing", playing == beds.size(), "%d playing" % playing)

	if beds.is_empty():
		_ok("the water bed is audible", false, "no beds to measure")
		return
	var bed: AudioStreamPlayer3D = beds[0]
	var file_db := _rms_dbfs(bed.stream.resource_path)
	_ok("the water sample could be measured", file_db > -200.0, "%.1f dBFS" % file_db)
	var effective: float = file_db + bed.volume_db
	_ok("the water bed is audible", effective > WATER_FLOOR_DBFS,
		"%.1f dBFS at the emitter (%+.1f dB on a %.1f dBFS file, floor %.1f)"
		% [effective, bed.volume_db, file_db, WATER_FLOOR_DBFS])


# RMS of the SOURCE .wav on disk, in dBFS. Subsampled — this is a level check, not an
# audio analyser, and these files run to half a million samples.
#
# ⚠️ Reads the file rather than `AudioStreamWAV.data`. This project imports .wav with
# `compress/mode=2` (QOA), so the in-memory stream is FORMAT_QOA and its bytes are not
# PCM — a decode_s16() walk over them returns garbage, or, as it did here, a tidy -999
# "could not measure" that would have been easy to wave through.
func _rms_dbfs(res_path: String) -> float:
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return -999.0
	var bytes: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return -999.0

	# Walk the RIFF chunks — `data` is not always at offset 44.
	var bits := 16
	var pos := 12
	var data_at := -1
	var data_len := 0
	while pos + 8 <= bytes.size():
		var id: String = bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size: int = bytes.decode_u32(pos + 4)
		if id == "fmt ":
			bits = bytes.decode_u16(pos + 22)
		elif id == "data":
			data_at = pos + 8
			data_len = size
			break
		pos += 8 + size + (size & 1)
	if data_at == -1 or bits != 16:
		return -999.0

	var frames: int = mini(data_len, bytes.size() - data_at) / 2
	if frames == 0:
		return -999.0
	var step: int = maxi(1, frames / 20000)
	var acc := 0.0
	var n := 0
	var i := 0
	while i < frames:
		var s: float = float(bytes.decode_s16(data_at + i * 2)) / 32768.0
		acc += s * s
		n += 1
		i += step
	return 20.0 * log(sqrt(acc / float(n)) + 1e-9) / log(10.0)


# The player's own footsteps are the loudest recurring sound in any level — they fire on
# every step, on the un-duckable Body bus, ~1 m from the ear. The Flood swaps them for
# wading, and that swap leaked into the Lobby for the life of the zone.
func _footsteps(where: String, expect_wade: bool) -> void:
	var fp: AudioStreamPlayer3D = _player.get_node_or_null("FootstepPlayer")
	_ok("%s: footstep player exists" % where, fp != null)
	if fp == null:
		return
	var file := _stream_of(fp)
	var wading: bool = file.begins_with("wade_step")
	_ok("%s: footsteps are %s" % [where, "wading" if expect_wade else "ordinary"],
		wading == expect_wade, file)

	# The phantom step two paces behind must match the step that casts it, or it reads as
	# a glitch rather than as someone walking behind you.
	for c in _player.get_children():
		if c is AudioStreamPlayer3D and c != fp and _stream_of(c) != "":
			_ok("%s: the echo matches the footstep" % where, _stream_of(c) == file,
				"%s vs %s" % [_stream_of(c), file])
			break


func _drips() -> void:
	_ok("the Flood's drips stay in the Flood", _lobby_drips == 0,
		"%d in the Lobby over %ds" % [_lobby_drips, int(LOBBY_WATCH)])
	# ⚠️ The other half, and the reason this is not just `== 0`: a gate that silences the
	# drip everywhere would pass the line above and delete the Flood's texture.
	_ok("the Flood still drips when you are in it", _flood_drips > 0,
		"%d in %ds" % [_flood_drips, int(FLOOD_WATCH)])


# Drips free themselves when finished, so count each one once, as it appears.
func _new_drips() -> int:
	var z3 := _scene.get_node_or_null("ZoneFlood")
	if z3 == null:
		return 0
	var n := 0
	for c in z3.get_children():
		if c is AudioStreamPlayer3D and not c.has_meta("counted") \
				and _stream_of(c).begins_with("water_drip"):
			c.set_meta("counted", true)
			n += 1
	return n


# --------------------------------------------------------------- helpers

func _stream_of(p: Node) -> String:
	var s: AudioStream = p.get("stream")
	return s.resource_path.get_file() if s else ""


func _emitters(n: Node, acc: Array[Node] = []) -> Array[Node]:
	if n is AudioStreamPlayer3D or n is AudioStreamPlayer:
		acc.append(n)
	for c in n.get_children():
		_emitters(c, acc)
	return acc


func _find_stream(root: Node, base: String) -> Node:
	for p in _emitters(root):
		if _stream_of(p).begins_with(base):
			return p
	return null


func _report() -> bool:
	print("  %d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL — ", ", ".join(_fails))
		quit(1)
	return true
