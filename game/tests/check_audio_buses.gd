extends SceneTree

# Is the silence architecture actually wired, or does it just read that way?
#
# Three things have to be true for any silence effect in this game to mean anything, and
# every one of them is invisible in the source:
#
#   1. `Ambience` and `Body` exist before any level loads (GameState._ready creates them).
#   2. A per-level bed bus NESTS UNDER `Ambience`. The Backrooms bus used to send straight
#      to Master, which made a global HoldBreath dip inaudible in the one level that fires
#      flash_scare on every wrong turn AND every wrong wall.
#   3. A dip ducks `Ambience` and leaves `Body` ALONE. If the heartbeat ducks with the
#      world, "silence" is just the volume going down — the effect is defined by what
#      survives it.
#
# ⚠️ This asserts against AudioServer, not against audio_buses.gd's source. Godot resolves
# a bus send by name at call time and silently falls back to Master on a miss, so reading
# the setter proves nothing about the resulting topology.
#
#   Godot --headless --path game --script res://tests/check_audio_buses.gd

# ⚠️ TIME-based, not frame-based. Headless runs uncapped, so a frame count is not a
# clock — the first version of this test checked the restore at "frame 130", which landed
# exactly on the 0.15 + 0.5 + 0.4 s boundary and reported a false failure at -18.4 dB
# mid-tween. Everything here waits on accumulated delta instead.
const DIP_HOLD := 0.5
const DIP_TOTAL := 1.05        # HoldBreath: FADE_DOWN 0.15 + hold + FADE_UP 0.4
const MID_DIP_AT := 0.30       # after the down-tween, inside the hold
const AFTER_DIP_AT := 1.60     # comfortably past the restore

var _frame := 0
var _t := 0.0
var _dip_at := -1.0
var _stage := 0
var _fails: Array[String] = []
var _checks := 0
var _amb_at_dip := 0.0
var _body_at_dip := 0.0


func _initialize() -> void:
	# The Backrooms, because it is the level with its own bed bus — the nesting case.
	change_scene_to_file("res://scenes/backrooms.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _send_of(bus_name: String) -> String:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return "<missing>"
	return str(AudioServer.get_bus_send(idx))


func _process(delta: float) -> bool:
	_frame += 1
	_t += delta

	if _frame == 10:
		var amb := AudioServer.get_bus_index(AudioBuses.AMBIENCE)
		var body := AudioServer.get_bus_index(AudioBuses.BODY)
		_ok("Ambience bus exists", amb != -1, "idx %d" % amb)
		_ok("Body bus exists", body != -1, "idx %d" % body)
		_ok("Ambience sends to Master", _send_of(AudioBuses.AMBIENCE) == "Master",
			_send_of(AudioBuses.AMBIENCE))
		# The whole point of Body: it must not hang off anything duckable.
		_ok("Body sends to Master, NOT Ambience", _send_of(AudioBuses.BODY) == "Master",
			_send_of(AudioBuses.BODY))

		# 2. The nesting case.
		var br := AudioServer.get_bus_index("Backrooms")
		_ok("the Backrooms bed bus exists", br != -1, "idx %d" % br)
		_ok("and it NESTS under Ambience", _send_of("Backrooms") == AudioBuses.AMBIENCE,
			_send_of("Backrooms"))

		# The player's own sounds are on Body.
		var player := current_scene.get_node_or_null("Player")
		_ok("player found", player != null)
		if player:
			var fs := player.get_node_or_null("FootstepPlayer") as AudioStreamPlayer3D
			_ok("footsteps are on Body", fs != null and fs.bus == AudioBuses.BODY,
				fs.bus if fs else "<no FootstepPlayer>")

	elif _frame == 14:
		HoldBreath.dip(self, DIP_HOLD)
		_dip_at = _t
		_stage = 1

	elif _stage == 1 and _dip_at >= 0.0 and _t - _dip_at >= MID_DIP_AT:
		_stage = 2
		# Mid-dip. The tween runs over FADE_DOWN (0.15 s) then holds, so by now Ambience
		# should be well down and Body untouched.
		_amb_at_dip = AudioServer.get_bus_volume_db(
			AudioServer.get_bus_index(AudioBuses.AMBIENCE))
		_body_at_dip = AudioServer.get_bus_volume_db(
			AudioServer.get_bus_index(AudioBuses.BODY))
		_ok("a dip ducks Ambience", _amb_at_dip < -20.0, "%.1f dB" % _amb_at_dip)
		_ok("a dip leaves Body alone", is_equal_approx(_body_at_dip, 0.0),
			"%.1f dB" % _body_at_dip)
		# Re-entry guard: a second dip while one is running must not stack, or the
		# restore could write back the DUCKED value and mute the level permanently.
		_ok("a second dip is refused while one runs", HoldBreath.dip(self, 0.5) == false)

	elif _stage == 2 and _t - _dip_at >= AFTER_DIP_AT:
		# Well past FADE_DOWN + hold + FADE_UP. The non-negotiable half of the contract:
		# the bus must never be left ducked.
		var amb_now := AudioServer.get_bus_volume_db(
			AudioServer.get_bus_index(AudioBuses.AMBIENCE))
		_ok("Ambience is restored afterwards", is_equal_approx(amb_now, 0.0),
			"%.1f dB" % amb_now)
		_ok("and a later dip is allowed again", HoldBreath.dip(self, 0.2) == true)

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

	if _t > 10.0:
		print("RESULT: FAIL — timed out before the dip completed (stage %d)" % _stage)
		quit(1)
		return true
	return false
