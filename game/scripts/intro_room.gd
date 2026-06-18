extends Node3D

const OPENING_NOTE := "You are Subject 47.\n\nThis is a psychological experiment. Your fear response is being monitored.\n\nThe entity you may encounter is a product of your own mind — it cannot harm you unless you believe it can.\n\nStay calm. Do not touch what you are not meant to touch.\n\nThe door ahead is your first test.\n\nWe are watching."

const ENDING_NOTE := "This is not an experiment.\n\nThere is no exit.\n\nThey already know where you are."

@onready var candle_light: OmniLight3D = $CandleLight
@onready var note: Node = $Note

var _flicker_time: float = 0.0
var _red_light: OmniLight3D = null  # ending only: slow blood-red throb
const BASE_ENERGY := 1.8


func _ready() -> void:
	GameState.current_level = 0
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_apply_textures()

	if GameState.is_ending:
		note.note_text = ENDING_NOTE
		NoteUI.closed.connect(_on_ending_note_closed, CONNECT_ONE_SHOT)
		_corrupt_room()
	else:
		note.note_text = OPENING_NOTE
		_show_controls_hint()

	_spawn_cobwebs()


func _apply_textures() -> void:
	var wall_tex: Texture2D = load("res://assets/textures/intro/wall_intro.png") \
		if ResourceLoader.exists("res://assets/textures/intro/wall_intro.png") else null
	var floor_tex: Texture2D = load("res://assets/textures/intro/floor_intro.png") \
		if ResourceLoader.exists("res://assets/textures/intro/floor_intro.png") else null
	var ceiling_tex: Texture2D = load("res://assets/textures/intro/ceiling_intro.png") \
		if ResourceLoader.exists("res://assets/textures/intro/ceiling_intro.png") else null
	var painting_tex: Texture2D = load("res://assets/textures/intro/painting_intro.png") \
		if ResourceLoader.exists("res://assets/textures/intro/painting_intro.png") else null
	var cobweb_tex: Texture2D = load("res://assets/textures/intro/cobweb_intro.png") \
		if ResourceLoader.exists("res://assets/textures/intro/cobweb_intro.png") else null
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


# The twist ending: same room, visibly wrong. The candle is dead, the room
# throbs blood-red, the exit is boarded over, and the new note is the only
# brightly lit thing left.
func _corrupt_room() -> void:
	candle_light.light_energy = 0.0
	candle_light.visible = false

	_red_light = OmniLight3D.new()
	_red_light.light_color = Color(0.8, 0.06, 0.04)
	_red_light.light_energy = 0.5
	_red_light.omni_range = 7.0
	_red_light.shadow_enabled = true
	_red_light.position = Vector3(0, 2.4, -1.0)
	add_child(_red_light)

	# The door you came through is gone — planks where it used to be.
	var exit_door := get_node_or_null("ExitDoor")
	if exit_door:
		exit_door.queue_free()
	var plank_mat := StandardMaterial3D.new()
	plank_mat.albedo_color = Color(0.10, 0.07, 0.04)
	plank_mat.roughness = 0.95
	for plank in [
		[Vector3(0, 1.6, -2.45), 0.35],
		[Vector3(0, 1.0, -2.45), -0.3],
		[Vector3(0, 0.5, -2.45), 0.15],
	]:
		var mesh_inst := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.7, 0.22, 0.06)
		mesh_inst.mesh = mesh
		mesh_inst.set_surface_override_material(0, plank_mat)
		mesh_inst.position = plank[0]
		mesh_inst.rotation.z = plank[1]
		add_child(mesh_inst)

	# Harsh cold spotlight pinning the note to the table.
	var spot := SpotLight3D.new()
	spot.light_color = Color(0.95, 0.93, 0.85)
	spot.light_energy = 4.0
	spot.spot_range = 4.0
	spot.spot_angle = 18.0
	spot.shadow_enabled = true
	spot.position = Vector3(0, 2.8, 0)
	spot.rotation_degrees.x = -90.0
	add_child(spot)

	# Low whisper loop under everything.
	var stream := GameState.load_audio("whispers")
	if stream:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = -14.0
		add_child(p)
		p.finished.connect(p.play)
		p.play()


func _show_controls_hint() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 40
	add_child(canvas)

	var lbl := Label.new()
	lbl.text = "WASD — move    ·    E — interact    ·    F — flashlight    ·    Shift — run"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	lbl.position.y -= 60.0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.7, 0.66, 0.58, 0.9))
	lbl.add_theme_font_size_override("font_size", 18)
	canvas.add_child(lbl)

	var tween := create_tween()
	tween.tween_interval(8.0)
	tween.tween_property(lbl, "modulate:a", 0.0, 2.0)
	tween.tween_callback(canvas.queue_free)


# Room is 5.6 m square -> walls at +-2.8, ceiling at 3.0. Webs nestle into the
# top corners (each spanning the two walls + ceiling) with per-web variation in
# size, tilt, roll and position so they read as grown, not stamped. Seeded for
# reproducibility.
func _spawn_cobwebs() -> void:
	var cobweb_tex: Texture2D = load("res://assets/textures/intro/cobweb_intro.png") \
		if ResourceLoader.exists("res://assets/textures/intro/cobweb_intro.png") else null
	if not cobweb_tex:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 870261 if not GameState.is_ending else 870262

	# Top corners as (x sign, z sign). The opening room only webs the two back
	# corners; the corrupted ending fills all four, denser.
	var corners := [Vector2(-1, -1), Vector2(1, -1)]
	if GameState.is_ending:
		corners.append(Vector2(-1, 1))
		corners.append(Vector2(1, 1))

	for c in corners:
		var count := rng.randi_range(1, 2) if not GameState.is_ending else rng.randi_range(2, 3)
		for i in range(count):
			_make_cobweb(cobweb_tex, c.x, c.y, rng)
		# In the ending, a few extra webs sag lower down the corner walls.
		if GameState.is_ending and rng.randf() < 0.7:
			_make_cobweb(cobweb_tex, c.x, c.y, rng, rng.randf_range(1.2, 1.9))


func _make_cobweb(tex: Texture2D, sx: float, sz: float, rng: RandomNumberGenerator,
		y_anchor: float = 2.95) -> void:
	var corner := Vector3(sx * 2.7, y_anchor, sz * 2.7)
	var inward := Vector3(-sx, 0, -sz).normalized()
	# Pull inward off the exact corner and drop a little, with jitter.
	var pos: Vector3 = corner + inward * rng.randf_range(0.08, 0.55) \
		+ Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.55, -0.05), rng.randf_range(-0.12, 0.12))
	# Normal faces into the room and downward so the web droops toward the player.
	var normal := (inward + Vector3(0, -rng.randf_range(0.5, 0.9), 0)).normalized()

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "CobwebIntro"
	var quad := QuadMesh.new()
	var s := rng.randf_range(0.7, 1.3)
	quad.size = Vector2(s, s * rng.randf_range(0.85, 1.15))
	mesh_inst.mesh = quad

	var basis := _basis_from_normal(normal)
	basis = basis.rotated(normal, rng.randf_range(0.0, TAU))  # random roll
	mesh_inst.transform = Transform3D(basis, pos)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(1, 1, 1, rng.randf_range(0.5, 0.85))  # vary how thick each web reads
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.set_surface_override_material(0, mat)
	add_child(mesh_inst)


# Orthonormal basis whose local +Z (a QuadMesh's face normal) equals `normal`.
func _basis_from_normal(normal: Vector3) -> Basis:
	normal = normal.normalized()
	var up := Vector3.UP
	if absf(normal.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var x := up.cross(normal).normalized()
	var y := normal.cross(x).normalized()
	return Basis(x, y, normal)


func _process(delta: float) -> void:
	_flicker_time += delta
	if _red_light:
		# Slow arrhythmic throb, like something breathing through the walls.
		_red_light.light_energy = 0.5 \
			+ maxf(0.0, sin(_flicker_time * 1.7)) * 0.35 \
			+ sin(_flicker_time * 0.6) * 0.1
		return
	candle_light.light_energy = BASE_ENERGY \
		+ sin(_flicker_time * 7.3) * 0.18 \
		+ sin(_flicker_time * 13.7) * 0.09 \
		+ sin(_flicker_time * 3.1) * 0.06


func _on_ending_note_closed() -> void:
	await get_tree().create_timer(2.0).timeout
	Screamer.trigger_to_menu()
