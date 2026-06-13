extends CharacterBody3D

const SPEED := 4.0
const MOUSE_SENSITIVITY := 0.002
const PITCH_LIMIT := deg_to_rad(80)
const INTERACT_RANGE := 2.5
const GAZE_TRIGGER_TIME := 3.0  # seconds of staring to trigger a trigger_object
const PANIC_MAX := 50.0
const PANIC_BASE_RATE := 20.0  # panic per second at scare_intensity 1.0
const PANIC_DECAY_RATE := 15.0
const CALM_DECAY_MULT := 2.5   # decay multiplier inside a calm zone (torchlight)
const DARK_PANIC_RATE := 3.0   # panic per second in a dark zone with flashlight off
const SLOW_MULTIPLIER := 0.45  # movement factor while slowed (beartrap limp)
const SPRINT_MULTIPLIER := 1.6
const SPRINT_PANIC_RATE := 6.0   # running feeds fear — "Walk. Do not run."
const SPRINT_FOOTSTEP_INTERVAL := 0.32
const DREAD_DECAY_RATE := 6.0    # weakened decay inside a dread zone (Zone C)
const DREAD_PANIC_RATE := 2.0    # constant pressure inside a dread zone
const BATTERY_MAX := 240.0       # seconds of flashlight per level
const BATTERY_FLICKER_BELOW := 48.0

@onready var camera: Camera3D = $Camera3D
@onready var flashlight: SpotLight3D = $Camera3D/Flashlight
@onready var interact_label: Label = $InteractUI/Label
@onready var footstep_player: AudioStreamPlayer3D = $FootstepPlayer

var _pitch: float = 0.0
var _gaze_timer: float = 0.0
var _gazed_object: Node = null
var _panic: float = 0.0
var _is_moving: bool = false
var _footstep_timer: float = 0.0
var _interact_target: Node = null
var _heartbeat_player: AudioStreamPlayer = null
var _panic_hud: Node = null
var _calm_zones: int = 0
var _dark_zones: int = 0
var _dread_zones: int = 0
var _slow_timer: float = 0.0
var _is_sprinting: bool = false
var _battery: float = BATTERY_MAX
var _flash_base_energy: float = 1.0
const FOOTSTEP_INTERVAL := 0.5
const _SCARY_OBJECT_SCRIPT := preload("res://scripts/scary_object.gd")
const _PANIC_HUD_SCENE := preload("res://assets/elements/hud_canvas.tscn")


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	interact_label.visible = false
	_flash_base_energy = flashlight.light_energy
	var fs := GameState.load_audio("footstep")
	if fs:
		footstep_player.stream = fs

	var hb_stream := GameState.load_audio("heartbeat")
	if hb_stream:
		_heartbeat_player = AudioStreamPlayer.new()
		_heartbeat_player.stream = hb_stream
		_heartbeat_player.volume_db = -20.0
		add_child(_heartbeat_player)

	_panic_hud = _PANIC_HUD_SCENE.instantiate()
	add_child(_panic_hud)

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
		if flashlight.visible:
			flashlight.visible = false
		elif _battery > 0.0:
			flashlight.visible = true

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _physics_process(delta: float) -> void:
	_slow_timer = maxf(0.0, _slow_timer - delta)
	_apply_gravity(delta)
	_apply_movement()
	move_and_slide()
	_tick_battery(delta)
	_handle_footsteps(delta)
	_handle_gaze(delta)
	_update_interact_prompt()


func _tick_battery(delta: float) -> void:
	if not flashlight.visible:
		return
	_battery = maxf(0.0, _battery - delta)
	if _battery <= 0.0:
		flashlight.visible = false
		flashlight.light_energy = _flash_base_energy
	elif _battery < BATTERY_FLICKER_BELOW:
		# Dying-bulb stutter warns the player before the light goes out.
		var t := Time.get_ticks_msec() * 0.001
		var drop := maxf(0.0, sin(t * 31.0) * sin(t * 7.3))
		flashlight.light_energy = _flash_base_energy * (1.0 - 0.6 * drop)
	else:
		flashlight.light_energy = _flash_base_energy


func _rotate_camera(mouse_delta: Vector2) -> void:
	rotate_y(-mouse_delta.x * MOUSE_SENSITIVITY)
	_pitch = clamp(_pitch - mouse_delta.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
	camera.rotation.x = _pitch


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta


func _apply_movement() -> void:
	var speed := SPEED * (SLOW_MULTIPLIER if _slow_timer > 0.0 else 1.0)
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	_is_sprinting = Input.is_action_pressed("sprint") and direction != Vector3.ZERO and is_on_floor()
	if _is_sprinting:
		speed *= SPRINT_MULTIPLIER
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		_is_moving = true
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		_is_moving = false


func _handle_footsteps(delta: float) -> void:
	if _is_moving and is_on_floor():
		_footstep_timer -= delta
		if _footstep_timer <= 0.0:
			_footstep_timer = SPRINT_FOOTSTEP_INTERVAL if _is_sprinting else FOOTSTEP_INTERVAL
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

	_update_panic(delta, target)
	_update_heartbeat()


func _find_scary_object(node: Node) -> Node:
	var current: Node = node
	while current:
		if current.get_script() == _SCARY_OBJECT_SCRIPT:
			return current
		current = current.get_parent()
	return null


func _update_panic(delta: float, target: Node) -> void:
	var scary := _find_scary_object(target) if target else null
	if scary:
		var intensity: float = scary.scare_intensity
		_panic += delta * intensity * PANIC_BASE_RATE
	elif _is_sprinting:
		_panic += delta * SPRINT_PANIC_RATE
	elif _dark_zones > 0 and not flashlight.visible:
		_panic += delta * DARK_PANIC_RATE
	else:
		var base_decay := DREAD_DECAY_RATE if _dread_zones > 0 else PANIC_DECAY_RATE
		var decay := base_decay * (CALM_DECAY_MULT if _calm_zones > 0 else 1.0)
		_panic = maxf(0.0, _panic - delta * decay)

	# Dread zones (Zone C whispers) press on the mind no matter what else happens.
	if _dread_zones > 0:
		_panic += delta * DREAD_PANIC_RATE

	if _panic >= PANIC_MAX:
		_panic = 0.0
		Screamer.trigger()

	if _panic_hud:
		_panic_hud.set_panic_ratio(_panic / PANIC_MAX)


func get_panic_ratio() -> float:
	return clampf(_panic / PANIC_MAX, 0.0, 1.0)


func add_panic(amount: float) -> void:
	_panic += amount
	if _panic >= PANIC_MAX:
		_panic = 0.0
		Screamer.trigger()
	if _panic_hud:
		_panic_hud.set_panic_ratio(_panic / PANIC_MAX)


func apply_slow(duration: float) -> void:
	_slow_timer = maxf(_slow_timer, duration)


func jolt_camera(strength: float = 0.05, duration: float = 0.35) -> void:
	var tween := create_tween()
	tween.tween_property(camera, "rotation:z", strength, duration * 0.15)
	tween.tween_property(camera, "rotation:z", 0.0, duration * 0.85) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func enter_calm_zone() -> void:
	_calm_zones += 1


func exit_calm_zone() -> void:
	_calm_zones = maxi(0, _calm_zones - 1)


func enter_dark_zone() -> void:
	_dark_zones += 1


func exit_dark_zone() -> void:
	_dark_zones = maxi(0, _dark_zones - 1)


func enter_dread_zone() -> void:
	_dread_zones += 1


func exit_dread_zone() -> void:
	_dread_zones = maxi(0, _dread_zones - 1)


func _update_heartbeat() -> void:
	if not _heartbeat_player:
		return
	var ratio: float = 0.0
	if _panic > 0.05:
		ratio = clamp(_panic / PANIC_MAX, 0.0, 1.0)
	elif _gaze_timer > 0.0:
		ratio = clamp(_gaze_timer / GAZE_TRIGGER_TIME, 0.0, 1.0)
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
