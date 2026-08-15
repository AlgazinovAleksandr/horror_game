class_name CutscenePlayer
extends CanvasLayer

# Fullscreen video cutscene, used by the two scripted transitions that are told rather than
# played: the cold open on START (main_menu.gd) and the floor giving way at the end of the
# Corridor (corridor.gd).
#
#   var cs := CutscenePlayer.play(self, PATH)
#   if cs != null:
#       await cs.finished
#
# ⚠️ `play()` RETURNS NULL rather than failing, and every caller must handle that. It is null
# headless (no decoder target), null if the file is missing, and null if the stream will not
# load. Both call sites therefore keep their pre-video behaviour as the fallback path — which
# is what lets `tests/check_noclip_fall.gd` still drive the real physics fall.
#
# ⚠️ Godot 4's VideoStreamPlayer decodes **Ogg Theora only**. An .mp4 will not play, will not
# import, and `ResourceLoader.exists()` will say it is there. Sources live in `assets_src/video/`
# and are transcoded with the ffmpeg line recorded in `assets_src/README.md`.

const LAYER := 90              # under Screamer's 100, so a scare can still fire over a cutscene
const BLACK := Color(0, 0, 0, 1)

signal finished

var _stream: VideoStream
var _volume_db: float = 0.0
var _player: VideoStreamPlayer
var _done: bool = false


static func play(host: Node, video_path: String, volume_db: float = 0.0) -> CutscenePlayer:
	# ⚠️ Deliberately NOT gated on `host.is_inside_tree()`. A CanvasLayer added to a host that is
	# not yet in the tree simply starts rendering when the host enters it, and the guard cost a
	# real caller: a SceneTree script's `root` reports false during `_initialize()`.
	if host == null:
		return null
	# Headless has no rendering target; the suite must not hang waiting on a video.
	if DisplayServer.get_name() == "headless":
		return null
	if not ResourceLoader.exists(video_path):
		push_warning("CutscenePlayer: no video at %s" % video_path)
		return null
	var stream := load(video_path) as VideoStream
	if stream == null:
		push_warning("CutscenePlayer: %s is not a VideoStream" % video_path)
		return null

	var cs := CutscenePlayer.new()
	cs._stream = stream
	cs._volume_db = volume_db
	host.add_child(cs)
	return cs


func _ready() -> void:
	layer = LAYER
	# The cutscenes are used across scene transitions and next to Screamer, which pauses the
	# tree. A cutscene that stops decoding because something else paused would hang its caller.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Opaque backing: both clips letterbox against black, and it also covers whatever the
	# caller was showing (the menu, the corridor) for the whole cutscene.
	var bg := ColorRect.new()
	bg.color = BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_player = VideoStreamPlayer.new()
	_player.stream = _stream
	_player.volume_db = _volume_db
	_player.expand = true
	_player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_player.finished.connect(_finish)
	add_child(_player)
	_player.play()

	# ⚠️ A stream that refuses to start never emits `finished`, and the caller is awaiting it.
	# One frame later is enough to tell "playing" from "silently did nothing".
	await get_tree().process_frame
	if is_instance_valid(_player) and not _player.is_playing():
		push_warning("CutscenePlayer: playback did not start")
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	queue_free()
