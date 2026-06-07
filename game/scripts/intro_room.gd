extends Node3D

const OPENING_NOTE := "You are Subject 47.\n\nThis is a psychological experiment. Your fear response is being monitored.\n\nThe entity you may encounter is a product of your own mind — it cannot harm you unless you believe it can.\n\nStay calm. Do not touch what you are not meant to touch.\n\nThe door ahead is your first test.\n\nWe are watching."

const ENDING_NOTE := "This is not an experiment.\n\nThere is no exit.\n\nThey already know where you are."

@onready var candle_light: OmniLight3D = $CandleLight
@onready var note: Node = $Note

var _flicker_time: float = 0.0
const BASE_ENERGY := 1.8


func _ready() -> void:
	GameState.current_level = 0
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_apply_textures()

	if GameState.is_ending:
		note.note_text = ENDING_NOTE
		NoteUI.closed.connect(_on_ending_note_closed, CONNECT_ONE_SHOT)
	else:
		note.note_text = OPENING_NOTE

	_spawn_cobwebs()


func _apply_textures() -> void:
	var wall_tex: Texture2D = load("res://assets/textures/wall_intro.png") \
		if ResourceLoader.exists("res://assets/textures/wall_intro.png") else null
	var floor_tex: Texture2D = load("res://assets/textures/floor_intro.png") \
		if ResourceLoader.exists("res://assets/textures/floor_intro.png") else null
	var ceiling_tex: Texture2D = load("res://assets/textures/ceiling_intro.png") \
		if ResourceLoader.exists("res://assets/textures/ceiling_intro.png") else null
	var painting_tex: Texture2D = load("res://assets/textures/painting_intro.png") \
		if ResourceLoader.exists("res://assets/textures/painting_intro.png") else null
	var cobweb_tex: Texture2D = load("res://assets/textures/cobweb_intro.png") \
		if ResourceLoader.exists("res://assets/textures/cobweb_intro.png") else null
	for child in get_children():
		var n: String = child.name.to_lower()
		if child is CSGBox3D:
			var mat := StandardMaterial3D.new()
			mat.uv1_scale = Vector3(2.0, 2.0, 2.0)
			if n.contains("ceiling"):
				if ceiling_tex:
					mat.albedo_texture = ceiling_tex
					child.material = mat
			elif n.contains("floor"):
				if floor_tex:
					mat.albedo_texture = floor_tex
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
			elif n.contains("cobweb"):
				if cobweb_tex:
					mat.albedo_texture = cobweb_tex
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					child.set_surface_override_material(0, mat)


func _spawn_cobwebs() -> void:
	var cobweb_tex: Texture2D = load("res://assets/textures/cobweb_intro.png") \
		if ResourceLoader.exists("res://assets/textures/cobweb_intro.png") else null
	if not cobweb_tex:
		return
	var positions := [Vector3(-2.5, 2.6, -2.4), Vector3(2.5, 2.6, -2.4)]
	for pos in positions:
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "CobwebIntro"
		var plane := PlaneMesh.new()
		plane.size = Vector2(1.0, 1.0)
		mesh_inst.mesh = plane
		mesh_inst.position = pos
		mesh_inst.rotation_degrees.x = -45.0
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = cobweb_tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_inst.set_surface_override_material(0, mat)
		add_child(mesh_inst)


func _process(delta: float) -> void:
	_flicker_time += delta
	candle_light.light_energy = BASE_ENERGY \
		+ sin(_flicker_time * 7.3) * 0.18 \
		+ sin(_flicker_time * 13.7) * 0.09 \
		+ sin(_flicker_time * 3.1) * 0.06


func _on_ending_note_closed() -> void:
	await get_tree().create_timer(2.0).timeout
	Screamer.trigger_to_menu()
