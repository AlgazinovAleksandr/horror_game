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
	_spawn_window()
	_spawn_cursed_props()
	_spawn_events()
	Vignette.spawn(self, Color(1.0, 0.88, 0.72, 1.0), 1.4)
	RandomAmbient.register_player(_get_player())


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
	var wall_tex: Texture2D = load("res://assets/textures/level_2_house/house_wall.png") \
		if ResourceLoader.exists("res://assets/textures/level_2_house/house_wall.png") else null
	var floor_tex: Texture2D = load("res://assets/textures/level_2_house/house_floor.png") \
		if ResourceLoader.exists("res://assets/textures/level_2_house/house_floor.png") else null
	var ceiling_tex: Texture2D = load("res://assets/textures/level_2_house/house_ceiling.png") \
		if ResourceLoader.exists("res://assets/textures/level_2_house/house_ceiling.png") else null
	var painting_tex: Texture2D = load("res://assets/textures/level_2_house/painting_house.png") \
		if ResourceLoader.exists("res://assets/textures/level_2_house/painting_house.png") else null
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

	# Press your face to the glass and the forest presses back. One-shot per scene.
	if not _forest_fired:
		var player := _get_player()
		if player:
			var dx: float = player.global_position.x - WINDOW_POS.x
			var dz: float = player.global_position.z - WINDOW_POS.z
			if Vector2(dx, dz).length() <= FOREST_SCARE_DIST:
				_forest_fired = true
				Screamer.flash_scare(FOREST_SCARE_PATH, "screamer_forest", 0.8)
				player.jolt_camera(0.08, 0.5)
				player.add_panic(FOREST_SCARE_PANIC)


func _reset_creak_timer() -> void:
	_creak_timer = randf_range(CREAK_MIN, CREAK_MAX)


# ---------------------------------------------------------------- pressure

# Back wall interior face is at z = 8.0; the window sits flush on it, left of
# the trap note. Layering from the room (-z) toward the wall (+z):
#   frame bars (7.935) -> glass (7.96) -> forest view (7.99) -> wall (8.0).
# A moonlit treeline shows through the pane; getting close fires the forest scare.
const WINDOW_POS := Vector3(-0.8, 1.6, 7.96)
const FOREST_PATH := "res://assets/textures/level_2_house/forest.png"
const FOREST_SCARE_PATH := "res://assets/textures/level_2_house/screamer_forest.png"
const FOREST_SCARE_DIST := 1.5
const FOREST_SCARE_PANIC := 25.0

var _window_glass: MeshInstance3D
var _forest_fired: bool = false


func _spawn_window() -> void:
	# The forest behind the glass — a faint moonlit treeline. Self-illuminated
	# so it reads in the dark room; sits in the gap between glass and wall.
	if ResourceLoader.exists(FOREST_PATH):
		var forest := MeshInstance3D.new()
		forest.name = "WindowForest"
		var fmesh := QuadMesh.new()
		fmesh.size = Vector2(1.0, 1.2)
		forest.mesh = fmesh
		var fmat := StandardMaterial3D.new()
		var ftex := load(FOREST_PATH)
		fmat.albedo_texture = ftex
		fmat.emission_enabled = true
		fmat.emission_texture = ftex
		# Self-lit so the treeline reads through the glass in the dark room.
		fmat.emission_energy_multiplier = 0.9
		forest.set_surface_override_material(0, fmat)
		forest.position = WINDOW_POS + Vector3(0, 0, 0.03)
		forest.rotation.y = PI
		add_child(forest)

	_window_glass = MeshInstance3D.new()
	_window_glass.name = "WindowGlass"
	var pane := QuadMesh.new()
	pane.size = Vector2(1.0, 1.2)
	_window_glass.mesh = pane
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.06, 0.08, 0.10, 0.10)  # lighter so the forest reads through
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.6
	glass.roughness = 0.15
	_window_glass.set_surface_override_material(0, glass)
	_window_glass.position = WINDOW_POS
	_window_glass.rotation.y = PI  # face into the room (-z)
	add_child(_window_glass)

	# Simple wooden frame: two crossbars over the pane.
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.12, 0.08, 0.05)
	frame_mat.roughness = 0.85
	for bar_size in [Vector3(1.06, 0.06, 0.04), Vector3(0.06, 1.26, 0.04)]:
		var bar := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = bar_size
		bar.mesh = mesh
		bar.set_surface_override_material(0, frame_mat)
		bar.position = WINDOW_POS + Vector3(0, 0, -0.025)
		add_child(bar)


func _spawn_cursed_props() -> void:
	# Family painting in the bedroom (mesh already in the scene) — staring feeds panic.
	_make_cursed_body(Vector3(8.0, 1.5, 7.97), Vector2(0.8, 1.0), PI, 0.8)
	# Tarnished mirror on the living room's left wall.
	var mirror := _make_cursed_body(Vector3(-1.88, 1.5, 6.5), Vector2(0.7, 1.1), PI / 2.0, 1.2)
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.7, 1.1)
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.07, 0.08)
	mat.metallic = 0.9
	mat.roughness = 0.12
	quad.set_surface_override_material(0, mat)
	mirror.add_child(quad)


func _make_cursed_body(pos: Vector3, size: Vector2, y_rot: float, intensity: float) -> StaticBody3D:
	# The ScaryObject must sit ABOVE the collider: player.gd walks UP from the
	# ray-hit StaticBody to find it. Nesting it under the body (as before) meant
	# gaze panic never registered. ScaryObject is a plain Node and breaks the
	# spatial chain, so the transform lives on the StaticBody3D itself (its
	# non-spatial parent makes local == global). Body is returned for the mesh.
	var scary := ScaryObject.new()
	scary.scare_intensity = intensity
	add_child(scary)
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = y_rot
	scary.add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y, 0.1)
	col.shape = shape
	body.add_child(col)
	return body


func _spawn_events() -> void:
	# Front door slams behind you as you head for the living room.
	_spawn_event(Vector3(0, 1.5, 2.0), Vector3(2.4, 3, 1.5), _ev_front_door_slam)
	# Someone paces the floor above the living room.
	_spawn_event(Vector3(1.5, 1.5, 5.0), Vector3(5.0, 3, 1.5), _ev_footsteps_above)
	# The bedroom light dies as you step through its doorway.
	_spawn_event(Vector3(4.65, 1.5, 5.5), Vector3(1.2, 3, 1.6), _ev_bedroom_dark)


func _spawn_event(pos: Vector3, size: Vector3, callback: Callable) -> void:
	var ev := CorridorEvent.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	ev.add_child(col)
	ev.position = pos
	ev.fired.connect(callback)
	add_child(ev)


func _play_at(base_name: String, pos: Vector3, volume_db: float = 0.0) -> void:
	var stream := GameState.load_audio(base_name)
	if not stream:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.unit_size = 8.0
	p.max_db = 6.0
	add_child(p)
	p.position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _ev_front_door_slam() -> void:
	_play_at("door_slam", Vector3(0, 1.2, -3.0), 2.0)
	var player := _get_player()
	if player:
		player.add_panic(8.0)


func _ev_footsteps_above() -> void:
	_play_at("footsteps_above", Vector3(2.0, 3.2, 5.5), 3.0)
	var player := _get_player()
	if player:
		player.add_panic(6.0)


func _ev_bedroom_dark() -> void:
	_play_at("creak", Vector3(7.5, 2.5, 5.5), 2.0)
	var light: OmniLight3D = get_node_or_null("LightBedroom")
	if light:
		var tween := create_tween()
		tween.tween_property(light, "light_energy", 1.4, 0.12)
		tween.tween_property(light, "light_energy", 0.1, 0.08)
		tween.tween_property(light, "light_energy", 0.9, 0.10)
		tween.tween_property(light, "light_energy", 0.0, 0.25)
	# The bedroom is a dark zone from now on — flashlight off costs panic.
	var zone := DarkZone.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.7, 3.0, 5.2)
	col.shape = shape
	zone.add_child(col)
	zone.position = Vector3(7.15, 1.5, 5.5)
	add_child(zone)
	var player := _get_player()
	if player:
		player.add_panic(6.0)


func _get_player() -> CharacterBody3D:
	return get_node_or_null("Player") as CharacterBody3D
