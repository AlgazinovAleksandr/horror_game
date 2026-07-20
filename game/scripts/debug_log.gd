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
var _deaths := 0
var _reported_fall := false


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
	if scene and scene.scene_file_path != _last_scene:
		_last_scene = scene.scene_file_path
		_say("SCENE      -> %s   (GameState.current_level=%d)"
			% [_last_scene.get_file(), GameState.current_level])
		_player = null
		_still = 0
		_reported_fall = false
		_peak_panic = 0.0

	if not scene:
		return
	if not is_instance_valid(_player):
		_player = scene.get_node_or_null("Player")
		if _player:
			_last_pos = _player.global_position
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
		# Log meaningful jumps, not noise.
		if absf(r - _last_panic) > 0.18:
			_say("PANIC      %.0f%%  (was %.0f%%) at %v"
				% [r * 100.0, _last_panic * 100.0, pos.snappedf(0.1)])
		if r >= 0.99 and _last_panic < 0.99:
			_deaths += 1
			_say("!! PANIC MAXED — death #%d at %v" % [_deaths, pos.snappedf(0.01)])
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
			_say("=== session end: peak panic %.0f%%, %d deaths ==="
				% [_peak_panic * 100.0, _deaths])
			_f.flush()
