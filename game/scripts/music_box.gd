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

signal wound

const WIND_TURNS := 3.0            # how far the crank spins per wind
const WIND_TIME := 2.6
const LOUD_DB := -2.0              # while it is playing after a wind
const IDLE_DB := -13.0             # the ambient bed the room has always had
const PLAY_TIME := 22.0            # …then it winds back down to idle

var _audio: AudioStreamPlayer3D = null
var _crank: Node3D = null
var _playing_loud: bool = false
var _timer: float = 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	set_process(true)


# The level builds the geometry and hands the pieces over, so all the placement constants stay
# in one place with the rest of the room dressing.
func attach_parts(audio: AudioStreamPlayer3D, crank: Node3D) -> void:
	_audio = audio
	_crank = crank


func interact() -> void:
	if not _audio:
		return
	_playing_loud = true
	_timer = PLAY_TIME

	# Wind it: the crank turns, and the tune comes up out of the room tone.
	if _crank:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_crank, "rotation:x",
			_crank.rotation.x + TAU * WIND_TURNS, WIND_TIME)

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
	if _audio:
		var vt := create_tween()
		vt.tween_property(_audio, "volume_db", IDLE_DB, 2.5)
