extends CanvasLayer

# Autoload singleton: Screamer
# Call Screamer.trigger() from anywhere to fire the screamer sequence.

var _black_panel: ColorRect
var _screamer_image: TextureRect
var _audio: AudioStreamPlayer
var _screamer_textures: Array[Texture2D] = []
var _corridor_texture: Texture2D = null  # level-exclusive screamer for the Corridor
var _is_triggering: bool = false

const CORRIDOR_LEVEL := 3
const CORRIDOR_TEXTURE_PATH := "res://assets/textures/level_3_corridor/screamer_hotel.png"

const RESTART_DELAY := 2.5


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	_black_panel = ColorRect.new()
	_black_panel.color = Color.BLACK
	_black_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_black_panel)

	_screamer_image = TextureRect.new()
	_screamer_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screamer_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_black_panel.add_child(_screamer_image)

	_audio = AudioStreamPlayer.new()
	add_child(_audio)

	_black_panel.visible = false

	# Scan screamers/ subfolder for any .png
	var dir := DirAccess.open("res://assets/textures/screamers")
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.ends_with(".png"):
				var tex: Texture2D = load("res://assets/textures/screamers/" + fname)  # screamers/ path unchanged
				if tex:
					_screamer_textures.append(tex)
			fname = dir.get_next()
		dir.list_dir_end()

	if ResourceLoader.exists(CORRIDOR_TEXTURE_PATH):
		_corridor_texture = load(CORRIDOR_TEXTURE_PATH)

	var audio := GameState.load_audio("jumpscare")
	if audio:
		_audio.stream = audio


func _pick_random_screamer() -> void:
	if GameState.current_level == CORRIDOR_LEVEL and _corridor_texture:
		_screamer_image.texture = _corridor_texture
		return
	if _screamer_textures.size() > 0:
		_screamer_image.texture = _screamer_textures[randi() % _screamer_textures.size()]


func set_screamer_texture(texture: Texture2D) -> void:
	_screamer_image.texture = texture


func set_screamer_audio(stream: AudioStream) -> void:
	_audio.stream = stream


func trigger() -> void:
	if _is_triggering:
		return
	_is_triggering = true
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_pick_random_screamer()
	_black_panel.visible = true
	if _audio.stream:
		_audio.play()
	await get_tree().create_timer(RESTART_DELAY).timeout
	_black_panel.visible = false
	_is_triggering = false
	GameState.restart_current_level()


func trigger_to_menu() -> void:
	if _is_triggering:
		return
	_is_triggering = true
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_pick_random_screamer()
	_black_panel.visible = true
	if _audio.stream:
		_audio.play()
	await get_tree().create_timer(RESTART_DELAY).timeout
	_black_panel.visible = false
	_is_triggering = false
	GameState.go_to_main_menu()
