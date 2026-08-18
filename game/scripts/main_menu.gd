extends Node

const NIGHTMARE_IMAGE := "res://assets/textures/intro/nightmare_face.png"

# The cold open. START plays this, THEN the jumpscare lands in the black frame it ends on —
# the clip's last frame is near-pure black (RGB ~2) by design, so the flash has somewhere to
# hit. ⚠️ If it is ever replaced, keep that black tail or the scare arrives over a lit image.
const INTRO_VIDEO := "res://assets/video/intro_scene.ogv"

# The looping background. ⚠️ It sits BETWEEN the still and the dark overlay, so everything the
# menu says — the title, the blood notes, the buttons — is added afterwards and lands on top of
# it for free. Nothing about the layout changed to accommodate it.
#
# ⚠️ `main_menu_bg.png` is NOT dead code now. It is the fallback layer: it is what shows headless,
# if the .ogv is missing, and if playback silently fails to start. Same contract as
# `CutscenePlayer.play()` returning null — a video is never allowed to be the only thing there.
#
# ⚠️ The .ogv is a PALINDROME (forward + reversed, see assets_src/README.md), which is what makes
# `loop` seamless: the last frame is the first frame, so the rejoin has nothing to match.
const MENU_VIDEO := "res://assets/video/menu_loop.ogv"

var _start_btn: Button
var _quit_btn: Button
var _bg_video: VideoStreamPlayer


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

	# The corridor loop, over the still and under everything else.
	if DisplayServer.get_name() != "headless" and ResourceLoader.exists(MENU_VIDEO):
		var stream := load(MENU_VIDEO) as VideoStream
		if stream != null:
			_bg_video = VideoStreamPlayer.new()
			_bg_video.stream = stream
			_bg_video.expand = true
			_bg_video.loop = true
			# The .ogv carries no audio track at all; this is belt and braces.
			_bg_video.volume_db = -80.0
			# It is a Control sitting under the buttons — it must never eat a click.
			_bg_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_bg_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			canvas.add_child(_bg_video)
			_bg_video.play()

	# Dark overlay so content is readable
	# ⚠️ 0.78 is unchanged, and that was measured rather than assumed: the clip's mean luminance
	# is ~60/255 against `main_menu_bg.png`'s ~51, i.e. the video is BRIGHTER than the still it
	# covers. VIDEO_PROMPTS.md §3's "generate this brighter than looks right" was heeded, so the
	# overlay did not need to move.
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

	# ⚠️ LAST, so the whole menu is already built before this function yields. A stream that
	# refuses to start never says so — one frame is enough to tell "playing" from "silently did
	# nothing", and dropping the node uncovers the still. Lifted from cutscene_player.gd.
	if _bg_video != null:
		await get_tree().process_frame
		if is_instance_valid(_bg_video) and not _bg_video.is_playing():
			push_warning("main_menu: background video did not start, falling back to the still")
			_bg_video.queue_free()
			_bg_video = null


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

	# The blackout is layer 85 and the menu canvas is layer 1, so the loop is already hidden —
	# but it would otherwise keep decoding underneath the whole intro cutscene for nothing.
	if is_instance_valid(_bg_video):
		_bg_video.stop()
		_bg_video.queue_free()
		_bg_video = null

	var cutscene := CutscenePlayer.play(self, INTRO_VIDEO)
	if cutscene != null:
		await cutscene.finished
	await Screamer.flash_scare(NIGHTMARE_IMAGE, "nightmare_scream", 0.8)
	get_tree().change_scene_to_file(GameState.SCENE_INTRO)
