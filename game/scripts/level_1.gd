extends Node3D

@onready var lights: Array[SpotLight3D] = []
@onready var ambient_player: AudioStreamPlayer = $AmbientPlayer
@onready var jumpscare_player: AudioStreamPlayer = $JumpscarePlayer

var _flicker_timers: Array[float] = []
var _jumpscare_timer: float = 0.0
const JUMPSCARE_MIN := 30.0
const JUMPSCARE_MAX := 90.0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameState.current_level = 1

	# Collect all SpotLight3D children into lights array
	for child in get_children():
		if child is SpotLight3D:
			lights.append(child)
			_flicker_timers.append(0.0)

	var ambient: AudioStreamPlayer = get_node_or_null("AmbientPlayer")
	if ambient:
		var s := GameState.load_audio("ambient_lab")
		if s:
			ambient.stream = s
		if ambient.stream:
			ambient.play()

	var js: AudioStreamPlayer = get_node_or_null("JumpscarePlayer")
	if js:
		var s := GameState.load_audio("jumpscare")
		if s:
			js.stream = s

	_reset_jumpscare_timer()
	_apply_textures()
	_spawn_note_tables()
	# Subtle grey-green tint, mild vignette
	Vignette.spawn(self, Color(0.88, 0.95, 0.88, 1.0), 0.9)


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
	var wall_tex: Texture2D = load("res://assets/textures/wall_lab.png") \
		if ResourceLoader.exists("res://assets/textures/wall_lab.png") else null
	var floor_tex: Texture2D = load("res://assets/textures/floor_lab.png") \
		if ResourceLoader.exists("res://assets/textures/floor_lab.png") else null
	var ceiling_tex: Texture2D = load("res://assets/textures/ceiling_lab.png") \
		if ResourceLoader.exists("res://assets/textures/ceiling_lab.png") else null
	var poster_tex: Texture2D = load("res://assets/textures/poster_lab.png") \
		if ResourceLoader.exists("res://assets/textures/poster_lab.png") else null
	var blood_tex: Texture2D = load("res://assets/textures/blood_lab.png") \
		if ResourceLoader.exists("res://assets/textures/blood_lab.png") else null
	for child in get_children():
		var n: String = child.name.to_lower()
		if child is CSGBox3D:
			var mat := StandardMaterial3D.new()
			mat.uv1_scale = Vector3(2.0, 2.0, 2.0)
			if n.contains("floor"):
				if floor_tex:
					mat.albedo_texture = floor_tex
					child.material = mat
			elif n.contains("ceiling"):
				if ceiling_tex:
					mat.albedo_texture = ceiling_tex
					child.material = mat
			elif n.contains("wall"):
				if wall_tex:
					mat.albedo_texture = wall_tex
					child.material = mat
		elif child is MeshInstance3D:
			var mat := StandardMaterial3D.new()
			mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
			if n.contains("poster"):
				if poster_tex:
					mat.albedo_texture = poster_tex
					child.set_surface_override_material(0, mat)
			elif n.contains("blood"):
				if blood_tex:
					mat.albedo_texture = blood_tex
					child.set_surface_override_material(0, mat)


func _process(delta: float) -> void:
	_flicker_lights(delta)
	_tick_jumpscare(delta)


func _flicker_lights(delta: float) -> void:
	for i in range(lights.size()):
		_flicker_timers[i] += delta
		var t := _flicker_timers[i]
		lights[i].light_energy = 1.0 + sin(t * 11.3) * 0.08 + sin(t * 23.7) * 0.04


func _tick_jumpscare(delta: float) -> void:
	_jumpscare_timer -= delta
	if _jumpscare_timer <= 0.0:
		_reset_jumpscare_timer()
		var js: AudioStreamPlayer = get_node_or_null("JumpscarePlayer")
		if js and js.stream:
			js.play()


func _reset_jumpscare_timer() -> void:
	_jumpscare_timer = randf_range(JUMPSCARE_MIN, JUMPSCARE_MAX)
