extends Node

# Глобальный менеджер случайных атмосферных событий
# Зарегистрировать в project.godot как Autoload: RandomAmbient

# ⚠️ Was 5-10 s. At that rate this autoload fired a positional scare within 4 m of the
# player every few seconds, in EVERY level, for 5/8/12 panic a time — a half_scream
# alone is 24% of the bar. Two 2026-07-26 playtest logs are wall-to-wall with the
# resulting ~21-24% spikes, and it is the most likely thing a player means by "it
# appeared right next to me again": at 7 s average it reads as a metronome rather than
# as an event, and it drowns out the scares the levels script deliberately.
#
# At 18-35 s it is punctuation. Note this is GLOBAL — changing it retunes the ambient
# pressure of all eight levels at once, so re-check any level balanced against the old
# rate before assuming a difficulty change came from somewhere else.
const MIN_INTERVAL := 18
const MAX_INTERVAL := 35

var _timer: float = 0.0
var _next_trigger: float = 0.0
var _player: CharacterBody3D = null
var _since_last_scare: float = 999.0   # large, so the first apparition isn't blocked
var _once_per_type: bool = false       # see set_once_per_type()
var _used: Dictionary = {}             # event name -> played, this level


# How long since this autoload last startled the player. ApparitionDirector reads it so
# the two scare systems stop landing on top of each other: they are independent timers
# with no knowledge of one another, and a floor_creak + an apparition in the same second
# reads as one incoherent event rather than two.
func seconds_since_last_scare() -> float:
	return _since_last_scare


func _ready() -> void:
	_schedule_next()


func register_player(p: CharacterBody3D) -> void:
	_player = p
	_used.clear()          # a fresh level starts with every event available again
	_schedule_next()


# ⭐ OPT-IN: play each event AT MOST ONCE for this level.
#
# ⚠️ Deliberately opt-in, and deliberately not a change to MIN/MAX_INTERVAL. This autoload
# is GLOBAL — `CLAUDE.md` warns that retuning it "changes ambient pressure everywhere at
# once", and the levels that were balanced against a repeating creak should keep it. The
# Corridor is the level the user walked, and at ~300 m it is by far the longest, so the
# same three sounds came round again and again: "too many repeating sounds… falling
# painting." One of each is punctuation; five is a playlist.
#
# Cleared by `register_player()`, so it is per-level and cannot leak into the next one.
func set_once_per_type(enabled: bool) -> void:
	_once_per_type = enabled
	_used.clear()


func _process(delta: float) -> void:
	_since_last_scare += delta
	if _player == null:
		return
	_timer += delta
	if _timer >= _next_trigger:
		_fire_random_event()
		_since_last_scare = 0.0
		_schedule_next()


func _schedule_next() -> void:
	_timer = 0.0
	_next_trigger = randf_range(MIN_INTERVAL, MAX_INTERVAL)


func _fire_random_event() -> void:
	var events := ["floor_creak", "painting_fall", "half_scream"]
	if _once_per_type:
		# Only what has not been heard yet. When the list empties this autoload simply
		# stops making noise for the rest of the level, which is the intent.
		var left: Array[String] = []
		for e in events:
			if not _used.has(e):
				left.append(e)
		if left.is_empty():
			return
		events = left
	var choice: String = events[randi() % events.size()]
	_used[choice] = true
	match choice:
		"floor_creak":
			_play_near_player("floor_creak", -2.0)
			_player.add_panic(5.0)
		"painting_fall":
			_play_near_player("painting_fall", 0.0)
			_player.add_panic(8.0)
		"half_scream":
			_play_near_player("half_scream", -8.0)
			_player.add_panic(12.0)


func _play_near_player(base_name: String, vol_db: float) -> void:
	var stream := GameState.load_audio(base_name)
	if not stream:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = vol_db
	p.unit_size = 10.0
	p.position = _player.global_position + Vector3(
		randf_range(-4.0, 4.0),
		randf_range(0.0, 2.0),
		randf_range(-4.0, 4.0)
	)
	get_tree().current_scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()