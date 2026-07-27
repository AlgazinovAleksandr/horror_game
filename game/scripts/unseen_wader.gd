extends Node3D
class_name UnseenWader

# SCARY.md P10 — the thing in the Flood that is never instantiated.
#
# EVERY creature in this game is rendered: the Smiler, the Perëkozhnik, the stalkers,
# Object 12, the apparition, the Still Ones. There has never been an entity that exists only
# as sound and consequence — which is the cheapest and most-praised horror asset in the
# corpus, and in THIS engine it dodges two hard constraints at once (no glow to give it eyes,
# and static lamps that cast no shadows to sell it with). It also cannot glitch: a monster you
# never draw can never be caught clipping through a wall.
#
# So there is no mesh, no collider, no ScaryObject, no kill radius and no panic. It is a
# `.wav` on a `Tween`.
#
# ⚠️ It NEVER resolves. It stays at least MIN_RANGE away, never enters the room the player is
# in, never approaches, and there is no distance at which it becomes visible or lethal. The
# Flood already has two HOLD apparitions and a darkness tell; it does not need a third
# *thing*. It needs the two it has to feel like part of a population.
#
# ⚠️ One extension past P10's spec, and it is what makes this an encounter rather than
# ambience: **when the player stops wading, it stops too — after two more strides.** The
# player will test that. It will pass the test.

const MIN_RANGE := 12.0            # never closer than this
const UNIT_SIZE := 14.0
const VOLUME_DB := -7.0
const MOVE_SPEED := 1.6            # m/s — a heavy, unhurried wade, slower than the player
const PAUSE_MIN := 1.5
const PAUSE_MAX := 4.0
const TRAIL_STRIDES := 2           # extra strides after the player halts
const STRIDE_TIME := 0.62          # one wading stride, deliberately slower than a footstep

var _rooms: Array[Vector3] = []     # candidate world positions (room centres)
var _audio: AudioStreamPlayer3D = null
var _player: CharacterBody3D = null
var _tween: Tween = null
var _pause := 0.0
var _player_moving := false
var _trail_left := 0
var _stride := 0.0
var _halted := true                 # starts silent; the player has to move first


static func build(parent: Node, rooms: Array[Vector3]) -> UnseenWader:
	var w := UnseenWader.new()
	w.name = "UnseenWader"
	w._rooms = rooms
	parent.add_child(w)
	return w


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	var s := GameState.load_audio("wade_distant")
	if not s:
		return
	_audio = AudioStreamPlayer3D.new()
	_audio.name = "WadeAudio"
	_audio.stream = s
	_audio.unit_size = UNIT_SIZE
	_audio.volume_db = VOLUME_DB
	# Duckable: a HoldBreath dip should take this with the rest of the world. The Flood's
	# actual tell is VISUAL (the seam that shows only with the light off), so ducking audio
	# here cannot hide a puzzle answer — the rule audio_buses.gd exists to protect.
	_audio.bus = AudioBuses.AMBIENCE
	add_child(_audio)
	# Every .wav.import in this project is loop_mode=0, so loops are self-restarted.
	_audio.finished.connect(_audio.play)
	if _rooms.size() > 0:
		global_position = _farthest_room()


# The level tells it whether the player is wading. It does NOT sample the player's velocity
# itself, because "is the player moving" in ankle-deep water is the zone's business (the wade
# footprint test lives in backrooms_zone3.gd) and duplicating it would let the two disagree.
func set_player_wading(wading: bool) -> void:
	if wading == _player_moving:
		return
	_player_moving = wading
	if wading:
		_halted = false
		_trail_left = 0
		if _audio and not _audio.playing:
			_audio.play()
	else:
		# The player stopped. Two more strides, then so does it.
		_trail_left = TRAIL_STRIDES
		_stride = STRIDE_TIME


func _process(delta: float) -> void:
	if not _player or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		return

	# --- the halt ---------------------------------------------------------------------
	if not _player_moving and not _halted:
		_stride -= delta
		if _stride <= 0.0:
			_trail_left -= 1
			_stride = STRIDE_TIME * 1.35      # decelerating: the second stride is slower
			if _trail_left <= 0:
				_halted = true
				if _tween and _tween.is_running():
					_tween.kill()
				if _audio and _audio.playing:
					# Stop, do not fade. A fade reads as it walking away; a stop reads as it
					# standing still, which is the whole point of the beat.
					_audio.stop()
		return

	if _halted:
		return

	# --- the wander -------------------------------------------------------------------
	if _tween and _tween.is_running():
		return
	_pause -= delta
	if _pause > 0.0:
		return
	var target := _pick_room()
	if target == Vector3.INF:
		return
	var dist := global_position.distance_to(target)
	_pause = randf_range(PAUSE_MIN, PAUSE_MAX)
	_tween = create_tween()
	_tween.tween_property(self, "global_position", target,
		maxf(0.6, dist / MOVE_SPEED))


# A room that is far enough away, and never the one the player is standing in.
func _pick_room() -> Vector3:
	var best := Vector3.INF
	var options: Array[Vector3] = []
	for r in _rooms:
		if r.distance_to(_player.global_position) >= MIN_RANGE:
			options.append(r)
	if options.is_empty():
		return best
	return options.pick_random()


func _farthest_room() -> Vector3:
	var best := _rooms[0]
	var best_d := -1.0
	for r in _rooms:
		var d: float = r.distance_to(_player.global_position) if _player else 0.0
		if d > best_d:
			best_d = d
			best = r
	return best
