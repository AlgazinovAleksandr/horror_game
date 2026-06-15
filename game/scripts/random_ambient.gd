extends Node

# Глобальный менеджер случайных атмосферных событий
# Зарегистрировать в project.godot как Autoload: RandomAmbient

const MIN_INTERVAL := 5
const MAX_INTERVAL := 10

var _timer: float = 0.0
var _next_trigger: float = 0.0
var _player: CharacterBody3D = null


func _ready() -> void:
	_schedule_next()


func register_player(p: CharacterBody3D) -> void:
	_player = p
	_schedule_next()


func _process(delta: float) -> void:
	if _player == null:
		return
	_timer += delta
	if _timer >= _next_trigger:
		_fire_random_event()
		_schedule_next()


func _schedule_next() -> void:
	_timer = 0.0
	_next_trigger = randf_range(MIN_INTERVAL, MAX_INTERVAL)


func _fire_random_event() -> void:
	var events := ["floor_creak", "painting_fall", "half_scream"]
	var choice: String = events[randi() % events.size()]
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