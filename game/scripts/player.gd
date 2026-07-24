extends CharacterBody3D

const SPEED := 4.0
const MOUSE_SENSITIVITY := 0.002
const PITCH_LIMIT := deg_to_rad(80)
const INTERACT_RANGE := 2.5
const GAZE_RANGE := 3.0          # panic detection radius — wider than interact range
const GAZE_TRIGGER_TIME := 3.0  # seconds of staring to trigger a trigger_object
const PANIC_MAX := 50.0
const PANIC_BASE_RATE := 20.0  # panic per second at scare_intensity 1.0
const PANIC_DECAY_RATE := 3.5   # 4.3× slower than the original 15/s — scares linger
const CALM_DECAY_MULT := 2.5   # decay multiplier inside a calm zone (torchlight)
const DARK_PANIC_RATE := 3.0   # panic per second in a dark zone with flashlight off
const SLOW_MULTIPLIER := 0.45  # movement factor while slowed (beartrap limp)
const SPRINT_MULTIPLIER := 1.6
const SPRINT_PANIC_RATE := 6.0   # running feeds fear — "Walk. Do not run."
const SPRINT_FOOTSTEP_INTERVAL := 0.32
const DREAD_DECAY_RATE := 2.0    # weakened decay inside a dread zone (Zone C)
const DREAD_PANIC_RATE := 2.0    # constant pressure inside a dread zone
const BATTERY_MAX := 240.0       # seconds of flashlight per level
const BATTERY_FLICKER_BELOW := 48.0
# Backrooms-only mechanics (opt-in via the methods below; default off so the
# other four levels behave exactly as before).
const STANDSTILL_GRACE := 4.0      # seconds still before the maze starts punishing
const STANDSTILL_PANIC_RATE := 3.0 # panic per second while standing still too long
const FOOTSTEP_ECHO_DELAY := 0.4   # phantom step plays this long after each real one
const FOOTSTEP_ECHO_VOLUME_DB := -11.0
const HIDE_PEEK_LIMIT := deg_to_rad(50)  # restricted look while hidden (a locker-door crack)
const HIDE_FOV := 35.0                   # narrowed FOV while hidden — peering through a gap
const HIDE_FOV_TWEEN_TIME := 0.25

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
# Backrooms-only state
var _standstill_panic_enabled: bool = false
var _standstill_timer: float = 0.0
var _smiler_active: bool = false        # suspends standstill + dark ticks (Smiler runs its own dread)
var _flashlight_dead: bool = false      # force-killed: F only clicks, never re-enables
var _flashlight_locked: bool = false    # reversible; distinct from _flashlight_dead (Intro Room)
var _input_frozen: bool = false         # blocks movement + look during a forced camera beat (Intro Room)
var _hidden: bool = false               # inside a HidingSpot — movement blocked, look restricted
var _hide_spot: Node = null
var _hide_yaw_center: float = 0.0
var _hide_overlay: Control = null
var _base_fov: float = 75.0
var _footstep_echo_enabled: bool = false
var _echo_player: AudioStreamPlayer3D = null
var _dead_click_player: AudioStreamPlayer = null
const FOOTSTEP_INTERVAL := 0.5
const _SCARY_OBJECT_SCRIPT := preload("res://scripts/scary_object.gd")
const _PANIC_HUD_SCENE := preload("res://assets/elements/hud_canvas.tscn")


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Props that live under a builder node can't reach the player by the usual
	# "../Player" path. living_mirror.gd already documents a group fallback, but
	# nothing ever joined the group, so that fallback was dead. Join it here.
	add_to_group("player")
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
	_base_fov = camera.fov
	_build_hide_overlay()


# Four opaque bars leaving a rectangular gap in the screen centre — a "peering
# through a door crack" read, built from plain ColorRects rather than a new shader
# (safer to get right without live visual iteration, same visual family as the
# existing panic_blur/vignette shader overlays but far simpler to author).
func _build_hide_overlay() -> void:
	var interact_ui: CanvasLayer = $InteractUI
	_hide_overlay = Control.new()
	_hide_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hide_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hide_overlay.visible = false
	interact_ui.add_child(_hide_overlay)

	var c := Color(0.0, 0.0, 0.0, 0.96)
	_hide_overlay.add_child(_make_hide_bar(c, 0.0, 0.0, 1.0, 0.32))    # top
	_hide_overlay.add_child(_make_hide_bar(c, 0.0, 0.68, 1.0, 1.0))    # bottom
	_hide_overlay.add_child(_make_hide_bar(c, 0.0, 0.32, 0.30, 0.68))  # left
	_hide_overlay.add_child(_make_hide_bar(c, 0.70, 0.32, 1.0, 0.68))  # right


func _make_hide_bar(color: Color, l: float, t: float, r: float, b: float) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.anchor_left = l
	rect.anchor_top = t
	rect.anchor_right = r
	rect.anchor_bottom = b
	rect.offset_left = 0.0
	rect.offset_top = 0.0
	rect.offset_right = 0.0
	rect.offset_bottom = 0.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _add_crosshair() -> void:
	var interact_ui: CanvasLayer = $InteractUI
	var crosshair := Label.new()
	crosshair.text = "·"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.add_theme_font_size_override("font_size", 32)
	crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	interact_ui.add_child(crosshair)


func _unhandled_input(event: InputEvent) -> void:
	# _input_frozen also covers "hidden" (movement must stay blocked — see
	# _apply_movement), but a hidden player still needs to look around (restricted,
	# see _rotate_camera) and press E to come back out, so hiding is exempted here.
	if _input_frozen and not _hidden:
		return
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
		elif _battery > 0.0 and not _flashlight_dead and not _flashlight_locked:
			flashlight.visible = true
		else:
			_play_dead_click()  # dead battery — only a useless click answers

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
	if _hidden:
		# Peeking through a crack: yaw is clamped around the angle you were facing
		# when you hid, pitch stays free (matches "looking out" more than "turning").
		var new_yaw := rotation.y - mouse_delta.x * MOUSE_SENSITIVITY
		rotation.y = clamp(new_yaw, _hide_yaw_center - HIDE_PEEK_LIMIT, _hide_yaw_center + HIDE_PEEK_LIMIT)
	else:
		rotate_y(-mouse_delta.x * MOUSE_SENSITIVITY)
	_pitch = clamp(_pitch - mouse_delta.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
	camera.rotation.x = _pitch


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta


func _apply_movement() -> void:
	if _input_frozen:
		return
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
			if _footstep_echo_enabled and _echo_player:
				# A phantom step answers a beat later, two paces behind you.
				get_tree().create_timer(FOOTSTEP_ECHO_DELAY).timeout.connect(_play_echo_step)
	else:
		_footstep_timer = 0.0


func _play_echo_step() -> void:
	if _echo_player and _echo_player.stream:
		_echo_player.play()


func _play_dead_click() -> void:
	if _dead_click_player and _dead_click_player.stream:
		_dead_click_player.play()


func _get_raycast_target(range: float = INTERACT_RANGE) -> Node:
	var space_state := get_world_3d().direct_space_state
	var ray_origin := camera.global_position
	var ray_end := ray_origin + (-camera.global_transform.basis.z * range)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)
	if result and result.collider:
		return result.collider
	return null


func _try_interact() -> void:
	# While hidden, the interact ray originates from inside the spot's own
	# collider (unreliable to hit-test), so route E straight to it instead.
	if _hidden and _hide_spot and _hide_spot.has_method("interact"):
		_hide_spot.interact()
		return
	if _interact_target and _interact_target.has_method("interact"):
		_interact_target.interact()


func _handle_gaze(delta: float) -> void:
	var target := _get_raycast_target(GAZE_RANGE)
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
	elif _dark_zones > 0 and not flashlight.visible and not _smiler_active:
		# A live Smiler suspends the dark creep — its own dread curve takes over.
		_panic += delta * DARK_PANIC_RATE
	else:
		var base_decay := DREAD_DECAY_RATE if _dread_zones > 0 else PANIC_DECAY_RATE
		var decay := base_decay * (CALM_DECAY_MULT if _calm_zones > 0 else 1.0)
		_panic = maxf(0.0, _panic - delta * decay)

	# Dread zones (Zone C whispers) press on the mind no matter what else happens.
	if _dread_zones > 0:
		_panic += delta * DREAD_PANIC_RATE

	# Backrooms: standing still too long lets panic climb (the maze forbids rest).
	# Suspended while a Smiler is active — then freezing is the correct, safe move.
	if _standstill_panic_enabled and not _smiler_active and not _is_moving:
		_standstill_timer += delta
		if _standstill_timer >= STANDSTILL_GRACE:
			_panic += delta * STANDSTILL_PANIC_RATE
	else:
		_standstill_timer = 0.0

	if _panic >= PANIC_MAX:
		_panic = 0.0
		Screamer.trigger()

	if _panic_hud:
		_panic_hud.set_panic_ratio(_panic / PANIC_MAX)


func get_panic_ratio() -> float:
	return clampf(_panic / PANIC_MAX, 0.0, 1.0)


func get_panic_hud() -> Node:
	return _panic_hud


func add_panic(amount: float) -> void:
	_panic += amount
	if _panic >= PANIC_MAX:
		_panic = 0.0
		Screamer.trigger()
	if _panic_hud:
		_panic_hud.set_panic_ratio(_panic / PANIC_MAX)


# Give panic back. Used at major structural beats — surviving a Backrooms zone —
# where the fiction says the pressure just came off. Without this, panic is a
# one-way ratchet across a multi-zone level and the later zones are unwinnable
# regardless of how well you play them.
func relieve_panic(amount: float) -> void:
	_panic = maxf(0.0, _panic - amount)


func set_panic_ratio(ratio: float) -> void:
	_panic = clampf(ratio, 0.0, 1.0) * PANIC_MAX


func apply_slow(duration: float) -> void:
	_slow_timer = maxf(_slow_timer, duration)


func cancel_slow() -> void:
	_slow_timer = 0.0


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


# ----------------------------------------------------- Backrooms-only opt-ins

# Punish standing still (the maze forbids rest). Off by default everywhere else.
func enable_standstill_panic() -> void:
	_standstill_panic_enabled = true


# Phantom footsteps two paces behind. Builds a quiet echo player behind the head.
func enable_footstep_echo() -> void:
	if _footstep_echo_enabled:
		return
	_footstep_echo_enabled = true
	_echo_player = AudioStreamPlayer3D.new()
	if footstep_player.stream:
		_echo_player.stream = footstep_player.stream
	_echo_player.volume_db = FOOTSTEP_ECHO_VOLUME_DB
	_echo_player.position = Vector3(0, 0, 1.4)  # +z is behind (forward is -z)
	add_child(_echo_player)


# Lazily builds the dead-battery click player shared by kill_flashlight() and
# lock_flashlight() — either path can be the first to need it.
func _ensure_dead_click_player() -> void:
	if _dead_click_player:
		return
	_dead_click_player = AudioStreamPlayer.new()
	var click := GameState.load_audio("light_pop")
	if click:
		_dead_click_player.stream = click
	_dead_click_player.volume_db = -14.0
	add_child(_dead_click_player)


# Force the flashlight off for the rest of the scene; F now only clicks uselessly.
func kill_flashlight() -> void:
	_flashlight_dead = true
	_battery = 0.0
	flashlight.visible = false
	_ensure_dead_click_player()


# The Smiler toggles this: while active, standstill + dark ticks pause and the
# creature drives panic itself (see Q2 of the Backrooms design).
func set_smiler_active(active: bool) -> void:
	_smiler_active = active


# Intro Room opt-ins (default off everywhere else). Reversible, unlike
# kill_flashlight()'s permanent one-way lock — the Intro Room's switch un-locks it.
func lock_flashlight() -> void:
	_flashlight_locked = true
	flashlight.visible = false
	_ensure_dead_click_player()


func unlock_flashlight() -> void:
	_flashlight_locked = false


func freeze_input() -> void:
	_input_frozen = true


func unfreeze_input() -> void:
	_input_frozen = false


# ------------------------------------------------------------------ hiding

# HidingSpot.interact() calls these. Movement blocks via the existing
# _input_frozen gate (_apply_movement already early-returns on it); look is
# exempted from that gate above and instead clamped to a peek cone in
# _rotate_camera(). A pursuing creature should query is_hidden() to skip
# detection entirely while true.
func enter_hiding(spot: Node) -> void:
	if _hidden:
		return
	_hidden = true
	_hide_spot = spot
	if spot.has_method("hide_anchor"):
		global_position = spot.hide_anchor()
	_hide_yaw_center = rotation.y
	velocity = Vector3.ZERO
	_input_frozen = true
	lock_flashlight()
	if _hide_overlay:
		_hide_overlay.visible = true
	var tween := create_tween()
	tween.tween_property(camera, "fov", HIDE_FOV, HIDE_FOV_TWEEN_TIME)


func exit_hiding() -> void:
	_hidden = false
	_hide_spot = null
	_input_frozen = false
	unlock_flashlight()
	if _hide_overlay:
		_hide_overlay.visible = false
	var tween := create_tween()
	tween.tween_property(camera, "fov", _base_fov, HIDE_FOV_TWEEN_TIME)


func is_hidden() -> bool:
	return _hidden


# Cosmetic only (e.g. SlamDoor picking a "slammed while fleeing" audio variant) —
# never gameplay-gating.
func get_horizontal_speed() -> float:
	var v := velocity
	v.y = 0.0
	return v.length()


func is_flashlight_on() -> bool:
	return flashlight.visible


func is_sprinting() -> bool:
	return _is_sprinting


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
	if _hidden:
		interact_label.visible = true  # always "press E to come out" while hidden
		return
	_interact_target = _get_raycast_target()
	interact_label.visible = _interact_target != null and _interact_target.has_method("interact")
