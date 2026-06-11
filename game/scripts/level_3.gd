extends Node3D

@onready var world_env: WorldEnvironment = $Environment.get_child(0)

var _shake_timer: float = 0.0
var _shake_duration: float = 0.0
var _shake_strength: float = 0.0
const SHAKE_MIN := 20.0
const SHAKE_MAX := 60.0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameState.current_level = 4

	var ambient: AudioStreamPlayer = get_node_or_null("AmbientPlayer")
	if ambient:
		var s := GameState.load_audio("ambient_void")
		if s:
			ambient.stream = s
		if ambient.stream:
			ambient.play()

	_reset_shake_timer()
	_apply_textures()
	_spawn_note_tables()
	# Vignette.spawn(self, Color(0.65, 0.55, 1.0, 1.0), 2.0)


func _spawn_note_tables() -> void:
	for child in get_children():
		if not ("note_text" in child):
			continue
		var table := CSGBox3D.new()
		table.size = Vector3(0.5, 1.2, 0.4)
		table.use_collision = true
		table.position = Vector3(child.position.x, 0.6, child.position.z)
		add_child(table)


func _apply_textures() -> void:
	var wall_tex: Texture2D = load("res://assets/textures/wall_void.png") \
		if ResourceLoader.exists("res://assets/textures/wall_void.png") else null
	var floor_tex: Texture2D = load("res://assets/textures/floor_void.png") \
		if ResourceLoader.exists("res://assets/textures/floor_void.png") else null
	for child in get_children():
		if not child is CSGBox3D:
			continue
		var n: String = child.name.to_lower()
		var mat := StandardMaterial3D.new()
		mat.uv1_scale = Vector3(2.0, 2.0, 2.0)
		if n.contains("floor"):
			if floor_tex:
				mat.albedo_texture = floor_tex
				child.material = mat
		elif n.contains("wall"):
			if wall_tex:
				mat.albedo_texture = wall_tex
				child.material = mat


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
