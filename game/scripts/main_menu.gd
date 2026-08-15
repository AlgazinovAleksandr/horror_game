extends Node

const NIGHTMARE_IMAGE := "res://assets/textures/intro/nightmare_face.png"

# The cold open. START plays this, THEN the jumpscare lands in the black frame it ends on —
# the clip's last frame is near-pure black (RGB ~2) by design, so the flash has somewhere to
# hit. ⚠️ If it is ever replaced, keep that black tail or the scare arrives over a lit image.
const INTRO_VIDEO := "res://assets/video/intro_scene.ogv"

var _start_btn: Button
var _quit_btn: Button


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_ui()


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# Background image (corridor silhouette)
	var bg_tex_path := "res://assets/textures/ui/main_menu_bg.png"
	if ResourceLoader.exists(bg_tex_path):
		var bg_img := TextureRect.new()
		bg_img.texture = load(bg_tex_path)
		bg_img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		canvas.add_child(bg_img)

	# Dark overlay so content is readable
	var overlay := ColorRect.new()
	overlay.color = Color(0.03, 0.02, 0.02, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(overlay)

	# Blood-written atmospheric labels
	var blood_notes := [
		{"text": "Are you strong enough?",       "pos": Vector2(80,  120), "rot": -8.0},
		{"text": "Will you find your way back?", "pos": Vector2(900, 380), "rot":  5.0},
		{"text": "They are watching you.",        "pos": Vector2(60,  620), "rot": -3.0},
	]
	for entry in blood_notes:
		var lbl := Label.new()
		lbl.text = entry["text"] as String
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", Color(0.72, 0.04, 0.04))
		lbl.position = entry["pos"] as Vector2
		lbl.rotation_degrees = entry["rot"] as float
		canvas.add_child(lbl)

	# Centered vbox for title + buttons
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(400, 260)
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)

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

	_start_btn = Button.new()
	_start_btn.text = "START"
	_start_btn.pressed.connect(_on_start)
	vbox.add_child(_start_btn)

	_quit_btn = Button.new()
	_quit_btn.text = "QUIT"
	_quit_btn.pressed.connect(get_tree().quit)
	vbox.add_child(_quit_btn)


func _on_start() -> void:
	_start_btn.disabled = true
	_quit_btn.disabled = true

	# Black goes down FIRST and is never lifted: the cutscene frees itself the moment it ends,
	# and without this the menu would flash back for the frames between the video, the scare
	# and the scene change.
	var blackout := CanvasLayer.new()
	blackout.layer = 85
	add_child(blackout)
	var fill := ColorRect.new()
	fill.color = Color(0, 0, 0, 1)
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blackout.add_child(fill)

	var cutscene := CutscenePlayer.play(self, INTRO_VIDEO)
	if cutscene != null:
		await cutscene.finished
	await Screamer.flash_scare(NIGHTMARE_IMAGE, "nightmare_scream", 0.8)
	get_tree().change_scene_to_file(GameState.SCENE_INTRO)
