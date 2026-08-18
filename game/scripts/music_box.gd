extends StaticBody3D
class_name MusicBoxProp

# The child's music box — and, since 2026-07-29, something you can actually play.
#
# Playtest: *"it would be cool if you can play the music using this box."* Until then it was a
# looping emitter you could only walk past, which was a waste of the one object in the level
# whose sound the player will hear from three rooms away.
#
# ⚠️ It is also THE GUEST's payoff. The audio player is a CHILD of this body, so when the
# house moves the box into the Hallway the tune travels with it — that is the entire reason
# the last stage of the ladder works, and it is why the loop must never be re-parented to the
# level.
#
# ⚠️ NOT a one-shot. The crank can be wound as many times as the player likes; there is no
# resource here and no fail state. The horror is that a toy in an empty house answers you.
#
# ⚠️ TWO STREAMS, on the user's explicit instruction (2026-08-16): *"the music that was used in
# the level should remain — only when I interact with the music box should [the new recording]
# appear."*
#   • `_audio`      — `music_box` (synthesized). The room tone the child's room has always had.
#                     Continuous, quiet, and NOT what you hear when you wind it.
#   • `_tune_audio` — `music_box_tune` (a real recording the user supplied). Plays ONLY on a wind.
# The bed ducks to `BED_DUCK_DB` while the tune plays and comes back after, so the two never sit
# on top of each other. Both are CHILDREN of this body — see the GUEST note above; if either is
# re-parented to the level, the sound stops travelling with the box and the last stage breaks.
#
# ⚠️ Do NOT collapse these back into one stream by giving the recording the base name
# `music_box`. `GameState.load_audio()` searches the ".wav" extension across EVERY subdir before
# it tries ".ogg", so a `music_box.ogg` would be shadowed by the synthesized `music_box.wav`
# anyway — and if the .wav were deleted instead, the recording would become the idle bed, which
# is exactly what the user ruled out.

signal wound

const WIND_TURNS := 3.0            # how far the crank spins per wind
const WIND_TIME := 2.6
const LOUD_DB := -2.0              # the tune, while it plays after a wind
const IDLE_DB := -13.0             # the ambient bed the room has always had
const BED_DUCK_DB := -30.0         # …the bed, pushed under the tune rather than stopped
const PLAY_TIME := 22.0            # …then it winds back down to idle

var _audio: AudioStreamPlayer3D = null
var _tune_audio: AudioStreamPlayer3D = null
var _crank: Node3D = null
var _playing_loud: bool = false
var _timer: float = 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	set_process(true)


# The level builds the geometry and hands the pieces over, so all the placement constants stay
# in one place with the rest of the room dressing.
func attach_parts(audio: AudioStreamPlayer3D, crank: Node3D, tune_audio: AudioStreamPlayer3D = null) -> void:
	_audio = audio
	_crank = crank
	_tune_audio = tune_audio


func interact() -> void:
	if not _audio and not _tune_audio:
		return
	_playing_loud = true
	_timer = PLAY_TIME

	# Wind it: the crank turns, and the tune comes up out of the room tone.
	if _crank:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_crank, "rotation:x",
			_crank.rotation.x + TAU * WIND_TURNS, WIND_TIME)

	# The recording is what a wind plays. The bed ducks under it rather than stopping, so the
	# room never goes silent between the two.
	if _tune_audio:
		var tt := create_tween()
		tt.tween_property(_tune_audio, "volume_db", LOUD_DB, 0.35)
		_tune_audio.play()          # restart from the top on every wind
		if _audio:
			var bt := create_tween()
			bt.tween_property(_audio, "volume_db", BED_DUCK_DB, 0.35)
	elif _audio:
		# No recording present — fall back to the old one-stream behaviour rather than silence.
		var vt := create_tween()
		vt.tween_property(_audio, "volume_db", LOUD_DB, 0.35)
		if not _audio.playing:
			_audio.play()
	wound.emit()


func _process(delta: float) -> void:
	if not _playing_loud:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_playing_loud = false
	# Back down to the room tone it has always sat at, rather than stopping dead — the box
	# running out mid-phrase is a better sound than the box being switched off.
	if _tune_audio:
		var tt := create_tween()
		tt.tween_property(_tune_audio, "volume_db", -40.0, 2.5)
		tt.finished.connect(_tune_audio.stop)
	if _audio:
		var vt := create_tween()
		vt.tween_property(_audio, "volume_db", IDLE_DB, 2.5)
