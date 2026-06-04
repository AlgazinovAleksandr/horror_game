extends CanvasLayer

# Autoload singleton: NoteUI
# Creates its own UI nodes at runtime — no scene file needed.

signal closed

var _root: Control
var _text_label: RichTextLabel
var is_open: bool = false
var _block_close: bool = false


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Root control fills the CanvasLayer. We toggle its visibility to show/hide.
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Dark full-screen backdrop
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	# CenterContainer — sibling of bg, also fills the root — auto-centers its child
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	# Dark panel with explicit StyleBox so it's always readable
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 480)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.07, 0.97)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.35, 0.3, 0.25)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	margin.add_child(vbox)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = false
	_text_label.fit_content = true
	_text_label.custom_minimum_size = Vector2(0, 360)
	_text_label.scroll_active = false
	_text_label.add_theme_color_override("default_color", Color(0.92, 0.88, 0.80))
	_text_label.add_theme_font_size_override("normal_font_size", 18)
	vbox.add_child(_text_label)

	var hint := Label.new()
	hint.text = "[ Press E to close ]"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.45, 0.42, 0.38))
	hint.add_theme_font_size_override("font_size", 14)
	vbox.add_child(hint)

	_root.visible = false


func show_note(text: String) -> void:
	_text_label.text = text
	_root.visible = true
	is_open = true
	_block_close = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true
	set_deferred("_block_close", false)


func _unhandled_input(event: InputEvent) -> void:
	if is_open and not _block_close and (event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel")):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	_root.visible = false
	is_open = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	closed.emit()
