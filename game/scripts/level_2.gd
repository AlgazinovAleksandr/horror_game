extends Node3D

var _creak_timer: float = 0.0
const CREAK_MIN := 15.0
const CREAK_MAX := 45.0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameState.current_level = 2

	var ambient: AudioStreamPlayer = get_node_or_null("AmbientPlayer")
	if ambient:
		var s := GameState.load_audio("ambient_house")
		if s:
			ambient.stream = s
		if ambient.stream:
			ambient.play()

	var creak: AudioStreamPlayer = get_node_or_null("CreakPlayer")
	if creak:
		var s := GameState.load_audio("creak")
		if s:
			creak.stream = s

	_reset_creak_timer()
	_apply_textures()
	# Warm sepia tint, moderate vignette
	Vignette.spawn(self, Color(1.0, 0.88, 0.72, 1.0), 1.4)


func _apply_textures() -> void:
	var wall_tex: Texture2D = load("res://assets/textures/wall_house.png") \
		if ResourceLoader.exists("res://assets/textures/wall_house.png") else null
	var floor_tex: Texture2D = load("res://assets/textures/floor_house.png") \
		if ResourceLoader.exists("res://assets/textures/floor_house.png") else null
	if not wall_tex and not floor_tex:
		return
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
		elif n.contains("wall") or n.contains("ceiling"):
			if wall_tex:
				mat.albedo_texture = wall_tex
				child.material = mat


func _process(delta: float) -> void:
	_creak_timer -= delta
	if _creak_timer <= 0.0:
		_reset_creak_timer()
		var creak: AudioStreamPlayer = get_node_or_null("CreakPlayer")
		if creak and creak.stream:
			creak.play()


func _reset_creak_timer() -> void:
	_creak_timer = randf_range(CREAK_MIN, CREAK_MAX)
