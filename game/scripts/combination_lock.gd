extends StaticBody3D

# Combination lock. Level 2's exit uses it (3 digits, 472); KONTUR's roster gate uses
# it (2 digits, 47). The number of dials is derived from the answer — see _digit_count.
# Builds its own UI programmatically — no child nodes required in the scene.

const WRONG_CODE_PANIC := 10.0  # brute-forcing the lock is the fail path

# KONTUR reuses this lock for its roster gate, which needs a different answer and its
# own bookkeeping. Leave `code` empty and the lock behaves exactly as Level 2 always
# has (GameState.level2_code / level2_code_correct); set it and the lock reports
# through the signals instead of touching GameState at all.
@export var code: String = ""
@export var title_text: String = "COMBINATION LOCK"
signal unlocked
signal wrong_code(attempts: int)

var _attempts: int = 0

# The controls, stated once and never overwritten. Typing is listed FIRST because it is
# what a player reaches for; the dials stay for anyone who prefers them.
const HINT_TEXT := "type 0-9  ·  ↑↓ change  ·  ←→ select  ·  Enter/E confirm  ·  Esc cancel"


# THE LOCK SIZES ITSELF FROM ITS ANSWER.
#
# It used to be hard-coded to three digits. KONTUR's roster gate answers a two-digit
# code, and on a three-digit lock that is ambiguous — is it 047 or 470? Nothing in the game
# states a padding convention, so a playtester who knew the answer still failed twice
# and spent 87 seconds at it. A two-digit answer now gets a two-digit lock and the
# question disappears.
func _digit_count() -> int:
	return code.length() if code != "" else GameState.level2_code.length()

var _canvas: CanvasLayer
var _panel: PanelContainer
var _digit_labels: Array[Label] = []
var _feedback_label: Label   # UNLOCKED / INCORRECT — transient
var _hint_label: Label       # the controls — never written to after _build_ui()
var _digits: Array[int] = []
var _selected: int = 0
var _ui_open: bool = false
var _buzz_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_buzz_player = AudioStreamPlayer.new()
	var buzz := GameState.load_audio("lock_buzz")
	if buzz:
		_buzz_player.stream = buzz
	add_child(_buzz_player)


func _process(_delta: float) -> void:
	# Tree unpausing while the lock is open means a screamer fired —
	# drop the UI silently so it doesn't survive the scene reload.
	if _ui_open and not get_tree().paused:
		_panel.visible = false
		_ui_open = false


func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 60
	add_child(_canvas)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(320, 180)
	center.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	_digits.resize(_digit_count())
	_digits.fill(0)
	for i in range(_digit_count()):
		var lbl := Label.new()
		lbl.text = "0"
		lbl.custom_minimum_size = Vector2(48, 48)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(lbl)
		_digit_labels.append(lbl)

	# ⚠️ TWO LABELS, and this is the fix, not a tidy-up (2026-08-15).
	#
	# There was one label doing both jobs, and `_submit()` overwrote it with "INCORRECT"
	# on the first wrong guess — so the line telling the player how to LEAVE disappeared
	# exactly when they most needed it, while WRONG_CODE_PANIC was ticking against them.
	# It only ever came back on the next `interact()`. Reported as "double check if it is
	# written that you need to press Esc to escape the lock": it was written, and then it
	# was destroyed.
	#
	# `note_ui.gd:77` and `journal_ui.gd:125` both carry a separate, immutable hint label
	# for this reason. This matches their styling so the three read as one convention.
	_hint_label = Label.new()
	_hint_label.text = HINT_TEXT
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.add_theme_color_override("font_color", Color(0.45, 0.42, 0.38))
	vbox.add_child(_hint_label)

	_feedback_label = Label.new()
	_feedback_label.text = ""
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(_feedback_label)

	_panel.visible = false


func interact() -> void:
	_ui_open = true
	_panel.visible = true
	_feedback_label.text = ""
	_feedback_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	# ⚠️ Start from zero every time. The dials used to persist between opens, so a second
	# attempt began on the digits of the previous wrong guess — which reads as the lock
	# having remembered something, and quietly makes brute-forcing cheaper.
	_digits.fill(0)
	_selected = 0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true
	_refresh_display()


func _input(event: InputEvent) -> void:
	if not _ui_open:
		return

	# ⚠️ TYPING COMES FIRST, before the action checks (2026-08-15, user's request: "we shall
	# make it possible to enter the digits directly from the keyboard").
	#
	# The order matters. `ui_up`/`ui_down` are bound to more than the arrow keys by Godot's
	# built-in InputMap, so an action check can swallow a key that was meant as a digit.
	# Reading the raw keycode first makes 0-9 unambiguous, and the dials still work exactly
	# as they did for anyone who prefers them.
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode
		var digit := -1
		if key >= KEY_0 and key <= KEY_9:
			digit = key - KEY_0
		elif key >= KEY_KP_0 and key <= KEY_KP_9:
			digit = key - KEY_KP_0
		if digit >= 0:
			_digits[_selected] = digit
			# Advance, but STOP on the last dial rather than wrapping to the first —
			# wrapping would silently overwrite the digit you typed first.
			_selected = min(_digit_count() - 1, _selected + 1)
			_refresh_display()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_BACKSPACE:
			# Step back and clear, the way a text field behaves.
			_selected = max(0, _selected - 1)
			_digits[_selected] = 0
			_refresh_display()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_ENTER or key == KEY_KP_ENTER:
			_submit()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("ui_left"):
		_selected = max(0, _selected - 1)
	elif event.is_action_pressed("ui_right"):
		_selected = min(_digit_count() - 1, _selected + 1)
	elif event.is_action_pressed("ui_up"):
		_digits[_selected] = (_digits[_selected] + 1) % 10
	elif event.is_action_pressed("ui_down"):
		_digits[_selected] = (_digits[_selected] - 1 + 10) % 10
	elif event.is_action_pressed("interact"):
		_submit()
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("ui_cancel"):
		_close_ui()
		get_viewport().set_input_as_handled()
		return

	_refresh_display()
	get_viewport().set_input_as_handled()


func _submit() -> void:
	var entered := ""
	for d in _digits:
		entered += str(d)
	var answer: String = code if code != "" else GameState.level2_code
	if entered == answer:
		if code == "":
			GameState.level2_code_correct = true
		_feedback_label.text = "UNLOCKED"
		unlocked.emit()
		await get_tree().create_timer(0.8).timeout
		_close_ui()
	else:
		_attempts += 1
		_feedback_label.text = "INCORRECT"
		_feedback_label.add_theme_color_override("font_color", Color(0.85, 0.2, 0.15))
		if _buzz_player.stream:
			_buzz_player.play()
		var player := get_tree().current_scene.get_node_or_null("Player")
		if player and player.has_method("add_panic"):
			player.add_panic(WRONG_CODE_PANIC)
		wrong_code.emit(_attempts)


func _close_ui() -> void:
	_panel.visible = false
	_ui_open = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _refresh_display() -> void:
	for i in range(_digit_labels.size()):
		_digit_labels[i].text = str(_digits[i])
		_digit_labels[i].modulate = Color.WHITE if i == _selected else Color(0.5, 0.5, 0.5)
