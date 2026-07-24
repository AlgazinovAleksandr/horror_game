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
const CAPTURE_DIR := "user://debug_captures/"

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

# --- debug capture (J): screenshot + typed note, both landing in this same log ---
var _capture_count := 0
var _capture_open := false
var _capture_layer: CanvasLayer = null
var _capture_panel: Control = null
var _capture_line_edit: LineEdit = null
var _capture_shot_path := ""
var _capture_scene_name := ""
var _capture_pos := Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep logging while the tree is paused
	_f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	_say("=== playtest session %s ===" % Time.get_datetime_string_from_system())
	_say("log file: %s" % ProjectSettings.globalize_path(LOG_PATH))
	if GameState.has_signal("objective_changed"):
		GameState.objective_changed.connect(_on_objective)
	_build_capture_ui()


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


# ⚠️ Called directly by Screamer.trigger()/trigger_to_menu() (found 2026-07-24 playtest):
# EVERY fatal death in this game funnels through Screamer.trigger() exactly once (guarded
# by its own _is_triggering flag) — panic-max deaths call it from player.gd, but instant
# creature-contact kills (creature_object12.gd's _contact(), creature_stalker lunges,
# trigger_object.gd) call it DIRECTLY, never touching the panic system at all. The old
# poll-based heuristic below only caught deaths by watching panic collapse from >70% to
# <15%, so a player killed by creature contact while panic was, say, 20% was invisible —
# a silent respawn with no DIED line and no entry in the death count. This is the single
# source of truth now; the panic-collapse watch was removed to avoid double-counting the
# deaths it DID catch (those also call Screamer.trigger()).
func record_death(pos: Vector3, cause: String) -> void:
	_deaths += 1
	_say("!! DIED (%s) — death #%d at %v" % [cause, _deaths, pos.snappedf(0.01)])


func _on_objective(text: String) -> void:
	if text != _last_objective:
		_last_objective = text
		_say("OBJECTIVE  %s" % text)


func _process(delta: float) -> void:
	# A real screamer fired while a debug note was being composed — Screamer already
	# owns pause/mouse-mode now, so just log whatever was typed and drop the overlay
	# silently rather than fighting for that state (same discipline note_ui.gd uses).
	if _capture_open and not get_tree().paused:
		var typed := _capture_line_edit.text if _capture_line_edit else ""
		_capture_panel.visible = false
		_capture_open = false
		note("DEBUG CAPTURE #%d -> %s | scene=%s pos=%v | note: \"%s\" (screamer interrupted)" % [
			_capture_count, _capture_shot_path, _capture_scene_name,
			_capture_pos.snappedf(0.1), typed])

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
		# Death detection used to live here, inferred from the panic bar COLLAPSING
		# (>70% -> <15%). Replaced by record_death(), called directly from
		# Screamer.trigger() — see that function's comment for why the collapse-watch
		# missed every non-panic death (creature contact, instant-fail traps).
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


# ------------------------------------------------------------- debug capture
#
# Press J during play: takes a screenshot immediately (before any UI appears, so
# it captures what the tester actually saw), then pauses and opens a one-line note
# box. The note (or "(none)" if skipped) is written into THIS SAME log via the
# existing note() method — a later session just greps "DEBUG CAPTURE" and reads
# the referenced PNGs. See .agents/skills/game-testing/SKILL.md.

func _unhandled_input(event: InputEvent) -> void:
	if _capture_open:
		if event.is_action_pressed("ui_cancel"):
			_close_capture(_capture_line_edit.text)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("debug_capture"):
		_start_capture()
		get_viewport().set_input_as_handled()


func _start_capture() -> void:
	_capture_count += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	_capture_shot_path = "%s%03d.png" % [CAPTURE_DIR, _capture_count]
	var img := get_tree().root.get_viewport().get_texture().get_image()
	img.save_png(_capture_shot_path)

	_capture_scene_name = _last_scene.get_file() if _last_scene != "" else "?"
	_capture_pos = _player.global_position if is_instance_valid(_player) else Vector3.ZERO

	_capture_open = true
	_capture_line_edit.text = ""
	_capture_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true
	_capture_line_edit.grab_focus.call_deferred()


func _on_capture_submitted(text: String) -> void:
	_close_capture(text)


func _close_capture(note_text: String) -> void:
	_capture_panel.visible = false
	_capture_open = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	note("DEBUG CAPTURE #%d -> %s | scene=%s pos=%v | note: \"%s\"" % [
		_capture_count, _capture_shot_path, _capture_scene_name,
		_capture_pos.snappedf(0.1), note_text])


func _build_capture_ui() -> void:
	_capture_layer = CanvasLayer.new()
	_capture_layer.layer = 90   # below Screamer's 100 — a real screamer still wins
	_capture_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_capture_layer)

	_capture_panel = Control.new()
	_capture_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_capture_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_capture_panel.visible = false
	_capture_layer.add_child(_capture_panel)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capture_panel.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capture_panel.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 120)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08, 0.95)
	style.set_border_width_all(2)
	style.border_color = Color(0.7, 0.1, 0.1)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var hint := Label.new()
	hint.text = "DEBUG CAPTURE — screenshot saved. Type a note (Enter to save, Esc to skip):"
	hint.add_theme_color_override("font_color", Color(0.85, 0.82, 0.78))
	vbox.add_child(hint)

	_capture_line_edit = LineEdit.new()
	_capture_line_edit.custom_minimum_size = Vector2(520, 0)
	_capture_line_edit.text_submitted.connect(_on_capture_submitted)
	vbox.add_child(_capture_line_edit)
