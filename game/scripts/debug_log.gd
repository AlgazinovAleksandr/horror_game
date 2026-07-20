extends Node

# PLAYTEST INSTRUMENTATION — observation only, never changes game behaviour.
#
# Registered as an autoload while playtesting so a human session produces a
# timeline we can diagnose from: level transitions, deaths, panic spikes, zone
# entries, interactions, and the two silent-failure classes that automated tests
# can't catch — falling out of the world, and getting stuck.
#
# Writes to user:// (see LOG_PATH printed at startup) AND to stdout.
# Remove the autoload entry in project.godot to disable.

const LOG_PATH := "user://playtest_log.txt"
const POLL := 0.5            # seconds between position/panic samples
const STUCK_DIST := 0.25     # moved less than this between samples = possibly stuck
const STUCK_SAMPLES := 24    # ~12 s of not moving while not in a menu
const FALL_Y := -6.0         # below this, the player has left the world

var _f: FileAccess
var _t := 0.0
var _poll := 0.0
var _player: Node3D = null
var _last_pos := Vector3.ZERO
var _still := 0
var _last_panic := 0.0
var _last_scene := ""
var _last_objective := ""
var _peak_panic := 0.0
var _session_peak := 0.0
var _deaths := 0
var _reported_fall := false
var _scene_changed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep logging while the tree is paused
	_f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	_say("=== playtest session %s ===" % Time.get_datetime_string_from_system())
	_say("log file: %s" % ProjectSettings.globalize_path(LOG_PATH))
	if GameState.has_signal("objective_changed"):
		GameState.objective_changed.connect(_on_objective)


func _say(msg: String) -> void:
	var line := "[%7.2f] %s" % [_t, msg]
	print("LOG ", line)
	if _f:
		_f.store_line(line)
		_f.flush()          # flush every line — a crash must not lose the tail


# Called by game code for events the poller cannot infer — a strike names WHICH gate
# failed, which a panic jump alone never tells us. Observation only; safe to no-op.
func note(msg: String) -> void:
	_say("EVENT      %s" % msg)


func _on_objective(text: String) -> void:
	if text != _last_objective:
		_last_objective = text
		_say("OBJECTIVE  %s" % text)


func _process(delta: float) -> void:
	_t += delta
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL

	# --- scene / level transitions ---
	var scene := get_tree().current_scene
	_scene_changed = false
	if scene and scene.scene_file_path != _last_scene:
		if _last_scene != "":
			_say("   %s peak panic %.0f%%" % [_last_scene.get_file(), _peak_panic * 100.0])
		_last_scene = scene.scene_file_path
		_say("SCENE      -> %s   (GameState.current_level=%d)"
			% [_last_scene.get_file(), GameState.current_level])
		_player = null
		_still = 0
		_reported_fall = false
		_scene_changed = true
		_peak_panic = 0.0
		_last_panic = 0.0     # or the drop to the new player's zero reads as a death

	if not scene:
		return
	if not is_instance_valid(_player):
		_player = scene.get_node_or_null("Player")
		if _player:
			_last_pos = _player.global_position
			# A restart reloads the SAME scene, so the scene-change guard above never
			# fires and the new player's zero panic reads as a second collapse — every
			# death was logged twice. Rebase on whoever just spawned.
			if _player.has_method("get_panic_ratio"):
				_last_panic = _player.get_panic_ratio()
			_say("PLAYER     spawned at %v" % _last_pos.snappedf(0.01))
		return

	var pos: Vector3 = _player.global_position

	# --- fell out of the world ---
	if pos.y < FALL_Y and not _reported_fall:
		_reported_fall = true
		_say("!! FELL OUT OF WORLD at %v — floor gap or missing collider" % pos.snappedf(0.01))

	# --- stuck detection (only counts while the player is trying to move) ---
	if pos.distance_to(_last_pos) < STUCK_DIST:
		_still += 1
		if _still == STUCK_SAMPLES:
			_say("?? STATIONARY ~%ds at %v — possible geometry trap"
				% [int(STUCK_SAMPLES * POLL), pos.snappedf(0.01)])
	else:
		if _still >= STUCK_SAMPLES:
			_say("   ...moving again from %v" % pos.snappedf(0.01))
		_still = 0
	_last_pos = pos

	# --- panic ---
	if _player.has_method("get_panic_ratio"):
		var r: float = _player.get_panic_ratio()
		_peak_panic = maxf(_peak_panic, r)
		_session_peak = maxf(_session_peak, r)
		# Log meaningful jumps, not noise.
		if absf(r - _last_panic) > 0.18:
			_say("PANIC      %.0f%%  (was %.0f%%) at %v"
				% [r * 100.0, _last_panic * 100.0, pos.snappedf(0.1)])
		# Detect death by the COLLAPSE, not by catching the peak: at a 0.5 s poll the
		# bar is often already reset by the time we look, which is why three real
		# deaths logged as zero. A fall from near-full to near-empty is a death.
		#
		# But NOT across a scene change: advancing a level on high panic also collapses
		# the bar (new scene, new player, zero panic), and that logged as a death for a
		# run the player actually WON. `_last_panic` is zeroed on transition above; this
		# guard covers the poll the transition lands on.
		if not _scene_changed and _last_panic > 0.70 and r < 0.15:
			_deaths += 1
			_say("!! DIED (panic %.0f%% -> %.0f%%) — death #%d at %v"
				% [_last_panic * 100.0, r * 100.0, _deaths, pos.snappedf(0.01)])
		_last_panic = r

	# --- flashlight / battery, the resource the Flood depends on ---
	if _player.has_method("is_flashlight_on"):
		var lit: bool = _player.is_flashlight_on()
		if lit != _flash_was:
			_flash_was = lit
			_say("FLASHLIGHT %s" % ("ON" if lit else "OFF"))

var _flash_was := true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _f:
			# _peak_panic is per-scene and resets on every transition, so reporting it
			# here always showed the last scene's spawn value (i.e. 0%).
			_say("=== session end: peak panic %.0f%%, %d deaths ==="
				% [_session_peak * 100.0, _deaths])
			_f.flush()
