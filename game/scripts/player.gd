extends CharacterBody3D

const SPEED := 4.0
const MOUSE_SENSITIVITY := 0.002
const PITCH_LIMIT := deg_to_rad(80)
const INTERACT_RANGE := 2.5
const GAZE_TRIGGER_TIME := 3.0  # seconds of staring to trigger a trigger_object

@onready var camera: Camera3D = $Camera3D
@onready var flashlight: SpotLight3D = $Camera3D/Flashlight
@onready var interact_label: Label = $InteractUI/Label
@onready var footstep_player: AudioStreamPlayer3D = $FootstepPlayer

var _pitch: float = 0.0
var _gaze_timer: float = 0.0
var _gazed_object: Node = null
var _is_moving: bool = false
var _footstep_timer: float = 0.0
var _interact_target: Node = null
var _heartbeat_player: AudioStreamPlayer = null
const FOOTSTEP_INTERVAL := 0.5


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	interact_label.visible = false
	var fs := GameState.load_audio("footstep")
	if fs:
		footstep_player.stream = fs

	var hb_stream := GameState.load_audio("heartbeat")
	if hb_stream:
		_heartbeat_player = AudioStreamPlayer.new()
		_heartbeat_player.stream = hb_stream
		_heartbeat_player.volume_db = -20.0
		add_child(_heartbeat_player)

	_add_crosshair()


func _add_crosshair() -> void:
	var interact_ui: CanvasLayer = $InteractUI
	var crosshair := Label.new()
	crosshair.text = "·"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.add_theme_font_size_override("font_size", 32)
	crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	interact_ui.add_child(crosshair)


func _unhandled_input(event: InputEvent) -> void:
	if NoteUI.is_open:
		return

	if event is InputEventMouseMotion:
		_rotate_camera(event.relative)

	if event.is_action_pressed("interact"):
		_try_interact()
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("toggle_flashlight"):
		flashlight.visible = not flashlight.visible

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_apply_movement()
	move_and_slide()
	_handle_footsteps(delta)
	_handle_gaze(delta)
	_update_interact_prompt()


func _rotate_camera(mouse_delta: Vector2) -> void:
	rotate_y(-mouse_delta.x * MOUSE_SENSITIVITY)
	_pitch = clamp(_pitch - mouse_delta.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
	camera.rotation.x = _pitch


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta


func _apply_movement() -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		_is_moving = true
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		_is_moving = false


func _handle_footsteps(delta: float) -> void:
	if _is_moving and is_on_floor():
		_footstep_timer -= delta
		if _footstep_timer <= 0.0:
			_footstep_timer = FOOTSTEP_INTERVAL
			if footstep_player.stream:
				footstep_player.play()
	else:
		_footstep_timer = 0.0


func _get_raycast_target() -> Node:
	var space_state := get_world_3d().direct_space_state
	var ray_origin := camera.global_position
	var ray_end := ray_origin + (-camera.global_transform.basis.z * INTERACT_RANGE)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)
	if result and result.collider:
		return result.collider
	return null


func _try_interact() -> void:
	if _interact_target and _interact_target.has_method("interact"):
		_interact_target.interact()


func _handle_gaze(delta: float) -> void:
	var target := _get_raycast_target()
	if target and target.has_method("on_gaze_tick"):
		if target == _gazed_object:
			_gaze_timer += delta
			if _gaze_timer >= GAZE_TRIGGER_TIME:
				target.on_gaze_trigger()
				_gaze_timer = 0.0
		else:
			_gazed_object = target
			_gaze_timer = 0.0
	else:
		_gazed_object = null
		_gaze_timer = 0.0
	_update_heartbeat()


func _update_heartbeat() -> void:
	if not _heartbeat_player:
		return
	var ratio: float = clamp(_gaze_timer / GAZE_TRIGGER_TIME, 0.0, 1.0)
	if ratio > 0.05:
		if not _heartbeat_player.playing:
			_heartbeat_player.play()
		_heartbeat_player.volume_db = lerp(-20.0, 0.0, ratio)
		_heartbeat_player.pitch_scale = lerp(0.8, 1.6, ratio)
	else:
		_heartbeat_player.stop()


func _update_interact_prompt() -> void:
	_interact_target = _get_raycast_target()
	interact_label.visible = _interact_target != null and _interact_target.has_method("interact")
