extends Node3D

@onready var world_env: WorldEnvironment = $WorldEnvironment

var _shake_timer: float = 0.0
var _shake_duration: float = 0.0
var _shake_strength: float = 0.0
const SHAKE_MIN := 20.0
const SHAKE_MAX := 60.0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameState.current_level = 3

	var ambient: AudioStreamPlayer = get_node_or_null("AmbientPlayer")
	if ambient:
		var s := GameState.load_audio("ambient_void")
		if s:
			ambient.stream = s
		if ambient.stream:
			ambient.play()

	_reset_shake_timer()
	# Strong blue-purple tint, heavy vignette
	Vignette.spawn(self, Color(0.65, 0.55, 1.0, 1.0), 2.0)


func _process(delta: float) -> void:
	_tick_shake(delta)


func _tick_shake(delta: float) -> void:
	if _shake_duration > 0.0:
		_shake_duration -= delta
		var player: CharacterBody3D = get_node_or_null("Player")
		if player:
			var cam: Camera3D = player.get_node_or_null("Camera3D")
			if cam:
				cam.rotation.z = sin(Time.get_ticks_msec() * 0.05) * _shake_strength * (_shake_duration / 0.4)
		return

	# Timer to next shake
	_shake_timer -= delta
	if _shake_timer <= 0.0:
		_reset_shake_timer()
		_shake_duration = 0.4
		_shake_strength = 0.008


func _reset_shake_timer() -> void:
	_shake_timer = randf_range(SHAKE_MIN, SHAKE_MAX)
