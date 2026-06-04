extends Node

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_ui()


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.02)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(400, 260)
	vbox.add_theme_constant_override("separation", 20)
	canvas.add_child(vbox)

	var title := Label.new()
	title.text = "SUBJECT 47"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.85, 0.15, 0.15))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "A psychological experiment"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	vbox.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	var start_btn := Button.new()
	start_btn.text = "START"
	start_btn.pressed.connect(_on_start)
	vbox.add_child(start_btn)

	var quit_btn := Button.new()
	quit_btn.text = "QUIT"
	quit_btn.pressed.connect(get_tree().quit)
	vbox.add_child(quit_btn)


func _on_start() -> void:
	get_tree().change_scene_to_file(GameState.SCENE_INTRO)
