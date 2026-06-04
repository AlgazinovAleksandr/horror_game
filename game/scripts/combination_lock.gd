extends StaticBody3D

# 3-digit combination lock for Level 2 exit door.
# Builds its own UI programmatically — no child nodes required in the scene.

var _canvas: CanvasLayer
var _panel: PanelContainer
var _digit_labels: Array[Label] = []
var _feedback_label: Label
var _digits: Array[int] = [0, 0, 0]
var _selected: int = 0
var _ui_open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 60
	add_child(_canvas)

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(320, 180)
	_canvas.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "COMBINATION LOCK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	for i in range(3):
		var lbl := Label.new()
		lbl.text = "0"
		lbl.custom_minimum_size = Vector2(48, 48)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(lbl)
		_digit_labels.append(lbl)

	_feedback_label = Label.new()
	_feedback_label.text = "↑↓ change  ←→ select  E confirm  Esc cancel"
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(_feedback_label)

	_panel.visible = false


func interact() -> void:
	_ui_open = true
	_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true
	_refresh_display()


func _unhandled_input(event: InputEvent) -> void:
	if not _ui_open:
		return

	if event.is_action_pressed("ui_left"):
		_selected = max(0, _selected - 1)
	elif event.is_action_pressed("ui_right"):
		_selected = min(2, _selected + 1)
	elif event.is_action_pressed("ui_up"):
		_digits[_selected] = (_digits[_selected] + 1) % 10
	elif event.is_action_pressed("ui_down"):
		_digits[_selected] = (_digits[_selected] - 1 + 10) % 10
	elif event.is_action_pressed("interact"):
		_submit()
		return
	elif event.is_action_pressed("ui_cancel"):
		_close_ui()
		return

	_refresh_display()


func _submit() -> void:
	var entered := "%d%d%d" % [_digits[0], _digits[1], _digits[2]]
	if entered == GameState.level2_code:
		GameState.level2_code_correct = true
		_feedback_label.text = "UNLOCKED"
		await get_tree().create_timer(0.8).timeout
		_close_ui()
	else:
		_feedback_label.text = "INCORRECT — try again"


func _close_ui() -> void:
	_panel.visible = false
	_ui_open = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _refresh_display() -> void:
	for i in range(3):
		_digit_labels[i].text = str(_digits[i])
		_digit_labels[i].modulate = Color.WHITE if i == _selected else Color(0.5, 0.5, 0.5)
