extends CanvasLayer

# Autoload singleton: Screamer
# Call Screamer.trigger() from anywhere to fire the screamer sequence.

var _black_panel: ColorRect
var _screamer_image: TextureRect
var _audio: AudioStreamPlayer

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

	# Auto-load screamer texture and audio if they exist
	var tex: Texture2D = load("res://assets/textures/screamer.png") if ResourceLoader.exists("res://assets/textures/screamer.png") else null
	if tex:
		_screamer_image.texture = tex

	var audio := GameState.load_audio("jumpscare")
	if audio:
		_audio.stream = audio


func set_screamer_texture(texture: Texture2D) -> void:
	_screamer_image.texture = texture


func set_screamer_audio(stream: AudioStream) -> void:
	_audio.stream = stream


func trigger() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_black_panel.visible = true
	if _audio.stream:
		_audio.play()
	await get_tree().create_timer(RESTART_DELAY).timeout
	_black_panel.visible = false
	GameState.restart_current_level()
