extends CanvasLayer

# Autoload singleton: Screamer
# Call Screamer.trigger() from anywhere to fire the fatal screamer (image +
# matching sound for the current level, then restart). Call flash_scare() for a
# survivable scare (fullscreen flash + sound, no restart — the caller adds panic).

var _black_panel: ColorRect
var _screamer_image: TextureRect
var _audio: AudioStreamPlayer
var _screamer_textures: Array[Texture2D] = []  # fallback pool (intro / ending)
var _is_triggering: bool = false
var _is_flashing: bool = false

# Per-level fatal screamer: current_level -> [image path, audio base name].
# load_audio() resolves the base name across the audio subdirs (.wav/.ogg).
const LEVEL_SCREAMERS := {
	1: ["res://assets/textures/level_1_lab/screamer_lab.png", "screamer_lab"],
	2: ["res://assets/textures/level_2_house/screamer_house.png", "screamer_house"],
	3: ["res://assets/textures/level_3_corridor/screamer_hotel.png", "screamer_corridor"],
	4: ["res://assets/textures/level_backrooms/screamer_smiler.png", "all_levels_screamer"],
	5: ["res://assets/textures/level_5_kontur/screamer_kontur.png", "kontur_scream"],
	6: ["res://assets/textures/level_4_void/screamer_void.png", "screamer_void"],
}

const FALLBACK_AUDIO := "all_levels_screamer"  # intro / ending levels with no dedicated scream

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

	# Fallback pool: every .png in screamers/ (used for intro / ending only).
	var dir := DirAccess.open("res://assets/textures/screamers")
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.ends_with(".png"):
				var tex: Texture2D = load("res://assets/textures/screamers/" + fname)
				if tex:
					_screamer_textures.append(tex)
			fname = dir.get_next()
		dir.list_dir_end()


# Set both the screamer image and the scream audio for the current level.
# Falls back to a random screamers/ image + the shared all_levels_screamer for intro/ending.
func _apply_level_av() -> void:
	var entry: Variant = LEVEL_SCREAMERS.get(GameState.current_level)
	if entry != null and ResourceLoader.exists(entry[0]):
		_screamer_image.texture = load(entry[0])
		var stream := GameState.load_audio(entry[1])
		if stream:
			_audio.stream = stream
			return
	# Fallback path.
	if _screamer_textures.size() > 0:
		_screamer_image.texture = _screamer_textures[randi() % _screamer_textures.size()]
	var fallback := GameState.load_audio(FALLBACK_AUDIO)
	if fallback:
		_audio.stream = fallback


func set_screamer_texture(texture: Texture2D) -> void:
	_screamer_image.texture = texture


func set_screamer_audio(stream: AudioStream) -> void:
	_audio.stream = stream


# Death has to actually STOP the player.
#
# trigger() deliberately UNPAUSES the tree — NoteUI pauses while a note is open and
# detects the unpause to drop its overlay, so pausing here instead would strand a
# trap note on screen. But that left the player fully simulating behind the black
# panel for the whole restart delay: still walking, still gazing, still feeding the
# panic bar. Playtest showed panic climbing 5% -> 78% AFTER death, because the corpse
# was still staring at the Perekozhnik.
#
# So freeze the player alone. The node is freed by the reload a moment later; this
# only has to hold for RESTART_DELAY.
func _freeze_player() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p:
		p.process_mode = Node.PROCESS_MODE_DISABLED


func trigger() -> void:
	if _is_triggering:
		return
	_is_triggering = true
	get_tree().paused = false
	_freeze_player()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_apply_level_av()
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
	_freeze_player()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_apply_level_av()
	_black_panel.visible = true
	if _audio.stream:
		_audio.play()
	await get_tree().create_timer(RESTART_DELAY).timeout
	_black_panel.visible = false
	_is_triggering = false
	GameState.go_to_main_menu()


# Survivable scare: flash an image fullscreen + play a sound for `hold` seconds,
# then clear. Does NOT pause or restart — the caller is responsible for any
# panic spike. Used by the forest (house) and manager (corridor) scares.
func flash_scare(image_path: String, audio_base: String, hold: float = 0.8) -> void:
	if _is_triggering or _is_flashing:
		return
	_is_flashing = true
	if ResourceLoader.exists(image_path):
		_screamer_image.texture = load(image_path)
	var stream := GameState.load_audio(audio_base)
	if stream:
		_audio.stream = stream
		_audio.play()
	_black_panel.visible = true
	await get_tree().create_timer(hold).timeout
	# A fatal trigger may have taken over mid-flash — don't yank its panel.
	if not _is_triggering:
		_black_panel.visible = false
	_is_flashing = false
