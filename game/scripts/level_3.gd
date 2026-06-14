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

	_break_room_c_floor()  # before textures so the new floor parts get the floor material
	_reset_shake_timer()
	_apply_textures()
	_spawn_note_tables()
	_spawn_void_zones()
	Vignette.spawn(self, Color(0.65, 0.55, 1.0, 1.0), 2.0)


# Room C's floor gives way to the void around its centre — a 1.6 m hole ringed
# by walkable borders. Step into it and you fall (see _check_void_fall).
func _break_room_c_floor() -> void:
	var floor_node := get_node_or_null("RoomCFloor")
	if not floor_node:
		return
	floor_node.free()
	var strips := [
		[Vector3(8, -0.15, 6.1), Vector3(6, 0.3, 2.2)],
		[Vector3(8, -0.15, 9.9), Vector3(6, 0.3, 2.2)],
		[Vector3(6.1, -0.15, 8), Vector3(2.2, 0.3, 1.6)],
		[Vector3(9.9, -0.15, 8), Vector3(2.2, 0.3, 1.6)],
	]
	for i in range(strips.size()):
		var part := CSGBox3D.new()
		part.name = "RoomCFloorPart%d" % i
		part.position = strips[i][0]
		part.size = strips[i][1]
		part.use_collision = true
		add_child(part)


# Ambient endurance: the far rooms (C+D) are a dread zone; Room A has two calm
# candles so the player can recover after learning the creature mechanic.
func _spawn_void_zones() -> void:
	_add_zone(DreadZone.new(), Vector3(4, 1.65, 8), Vector3(14, 3.3, 6))  # Rooms C+D only
	_add_zone(DarkZone.new(), Vector3(8, 1.5, 8), Vector3(6, 3, 6))       # Room C dark
	_add_zone(DarkZone.new(), Vector3(0, 1.5, 8), Vector3(6, 3, 6))       # Room D dark
	# Calm anchors in Room A — the only relief in the Void. Looking away from a
	# creature here lets panic drain 2.5× faster; staring at it still costs 12/s.
	_add_zone(CalmZone.new(), Vector3(-1.5, 1.0, -1.5), Vector3(2.5, 3.0, 2.5))
	_add_zone(CalmZone.new(), Vector3(1.5, 1.0, -1.5), Vector3(2.5, 3.0, 2.5))
	_spawn_candle(Vector3(-1.5, 0.0, -1.5))
	_spawn_candle(Vector3(1.5, 0.0, -1.5))


func _spawn_candle(pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.3)
	light.light_energy = 0.6
	light.omni_range = 2.5
	light.position = pos + Vector3(0, 0.8, 0)
	add_child(light)
	var candle := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = 0.025
	mesh.height = 0.15
	candle.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.85, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.4)
	mat.emission_energy_multiplier = 1.5
	candle.set_surface_override_material(0, mat)
	candle.position = pos + Vector3(0, 0.075, 0)
	add_child(candle)


func _add_zone(zone: Area3D, pos: Vector3, size: Vector3) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	zone.add_child(col)
	zone.position = pos
	add_child(zone)


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
	var wall_tex: Texture2D = load("res://assets/textures/level_4_void/wall_void.png") \
		if ResourceLoader.exists("res://assets/textures/level_4_void/wall_void.png") else null
	var floor_tex: Texture2D = load("res://assets/textures/level_4_void/floor_void.png") \
		if ResourceLoader.exists("res://assets/textures/level_4_void/floor_void.png") else null
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
	_check_void_fall()


# Fall off the broken geometry and the void claims you.
func _check_void_fall() -> void:
	var player: CharacterBody3D = get_node_or_null("Player")
	if player and player.global_position.y < -4.0:
		Screamer.trigger()


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
