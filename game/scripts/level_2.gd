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
	_spawn_note_tables()
	# Warm sepia tint, moderate vignette
	Vignette.spawn(self, Color(1.0, 0.88, 0.72, 1.0), 1.4)


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
	var wall_tex: Texture2D = load("res://assets/textures/wall_house.png") \
		if ResourceLoader.exists("res://assets/textures/wall_house.png") else null
	var floor_tex: Texture2D = load("res://assets/textures/floor_house.png") \
		if ResourceLoader.exists("res://assets/textures/floor_house.png") else null
	var ceiling_tex: Texture2D = load("res://assets/textures/ceiling_house.png") \
		if ResourceLoader.exists("res://assets/textures/ceiling_house.png") else null
	var painting_tex: Texture2D = load("res://assets/textures/painting_house.png") \
		if ResourceLoader.exists("res://assets/textures/painting_house.png") else null
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
			if n.contains("painting"):
				if painting_tex:
					var plane := PlaneMesh.new()
					plane.size = Vector2(1.0, 0.8)
					child.mesh = plane
					child.rotation_degrees.x = -90.0
					mat.albedo_texture = painting_tex
					mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					child.set_surface_override_material(0, mat)


func _process(delta: float) -> void:
	_creak_timer -= delta
	if _creak_timer <= 0.0:
		_reset_creak_timer()
		var creak: AudioStreamPlayer = get_node_or_null("CreakPlayer")
		if creak and creak.stream:
			creak.play()


func _reset_creak_timer() -> void:
	_creak_timer = randf_range(CREAK_MIN, CREAK_MAX)
