extends Area3D
class_name Beartrap

# Floor trap. Stepping in springs the jaws and starts a 7-second escape window:
# press E 7 times to wrench free with only a 15-panic cost. Fail and 40 more panic
# lands on top — 55 total pushes you past PANIC_MAX and the screamer takes you.
# Builds its own meshes so corridor.gd only has to place it.

const ESCAPE_TIME := 7.0
const ESCAPE_PRESSES_NEEDED := 7
const ESCAPE_INITIAL_PANIC := 15.0  # on spring — survivable alone
const ESCAPE_FAIL_PANIC := 40.0     # on timeout — 55 total > PANIC_MAX
const JAW_OPEN_DEG := 75.0

var _sprung: bool = false
var _escaping: bool = false
var _escape_timer: float = 0.0
var _escape_presses: int = 0
var _body_ref: Node3D = null

var _jaw_l: MeshInstance3D
var _jaw_r: MeshInstance3D
var _snap_player: AudioStreamPlayer3D

var _ui: CanvasLayer = null
var _bar: ColorRect = null
var _press_label: Label = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_build_visuals()

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.32
	shape.height = 0.4
	col.shape = shape
	col.position.y = 0.2
	add_child(col)

	_snap_player = AudioStreamPlayer3D.new()
	var snap := GameState.load_audio("beartrap_snap")
	if snap:
		_snap_player.stream = snap
	_snap_player.unit_size = 6.0
	add_child(_snap_player)


func _build_visuals() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.18, 0.18, 0.2)
	metal.metallic = 0.9
	metal.roughness = 0.35
	metal.emission_enabled = true
	metal.emission = Color(0.15, 0.17, 0.21)
	metal.emission_energy_multiplier = 0.12

	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.28
	base_mesh.bottom_radius = 0.28
	base_mesh.height = 0.03
	base.mesh = base_mesh
	base.position.y = 0.015
	base.set_surface_override_material(0, metal)
	add_child(base)

	_jaw_l = _build_jaw(metal, -1.0)
	_jaw_r = _build_jaw(metal, 1.0)


func _build_jaw(metal: StandardMaterial3D, side: float) -> MeshInstance3D:
	var jaw := MeshInstance3D.new()
	var plate := BoxMesh.new()
	plate.size = Vector3(0.5, 0.26, 0.02)
	jaw.mesh = plate
	jaw.set_surface_override_material(0, metal)
	jaw.position = Vector3(0, 0.13, 0)

	var hinge := Node3D.new()
	hinge.position = Vector3(0, 0.03, side * 0.24)
	hinge.rotation_degrees.x = side * JAW_OPEN_DEG
	hinge.add_child(jaw)
	add_child(hinge)
	return jaw


func _on_body_entered(body: Node3D) -> void:
	if _sprung or not body.has_method("add_panic"):
		return
	_sprung = true
	_body_ref = body

	if _snap_player.stream:
		_snap_player.play()
	if body.has_method("jolt_camera"):
		body.jolt_camera(0.09, 0.5)
	body.add_panic(ESCAPE_INITIAL_PANIC)
	body.apply_slow(ESCAPE_TIME + 1.0)  # keep player barely moving during escape window

	for jaw_mesh in [_jaw_l, _jaw_r]:
		var hinge: Node3D = jaw_mesh.get_parent()
		var tween := create_tween()
		tween.tween_property(hinge, "rotation_degrees:x", 0.0, 0.07) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)

	_start_escape()


func _start_escape() -> void:
	_escaping = true
	_escape_timer = ESCAPE_TIME
	_escape_presses = 0
	_build_escape_ui()


func _process(delta: float) -> void:
	if not _escaping:
		return

	_escape_timer -= delta
	_update_escape_ui()

	if Input.is_action_just_pressed("interact"):
		_escape_presses += 1
		# Replay snap at low volume for each press — ratcheting sound
		if _snap_player.stream:
			_snap_player.volume_db = -18.0
			_snap_player.play()
		if _escape_presses >= ESCAPE_PRESSES_NEEDED:
			_escape_success()
			return

	if _escape_timer <= 0.0:
		_escape_fail()


func _escape_success() -> void:
	_escaping = false
	_drop_ui()
	if _body_ref and _body_ref.has_method("cancel_slow"):
		_body_ref.cancel_slow()


func _escape_fail() -> void:
	_escaping = false
	_drop_ui()
	if _body_ref and _body_ref.has_method("add_panic"):
		_body_ref.add_panic(ESCAPE_FAIL_PANIC)


func _drop_ui() -> void:
	if _ui:
		_ui.queue_free()
		_ui = null
		_bar = null
		_press_label = null


func _build_escape_ui() -> void:
	_ui = CanvasLayer.new()
	get_parent().add_child(_ui)

	# Timer bar background — anchored to bottom centre
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.1, 0.0, 0.0, 0.85)
	bar_bg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar_bg.offset_top = -95
	bar_bg.offset_bottom = -65
	bar_bg.offset_left = -205
	bar_bg.offset_right = 205
	_ui.add_child(bar_bg)

	# Timer bar fill — shrinks rightward as time runs out
	_bar = ColorRect.new()
	_bar.color = Color(0.85, 0.12, 0.08, 1.0)
	_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.add_child(_bar)

	# Press counter / instruction label
	_press_label = Label.new()
	_press_label.text = "TRAPPED — PRESS [E] TO ESCAPE  (0 / %d)" % ESCAPE_PRESSES_NEEDED
	_press_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.85))
	_press_label.add_theme_font_size_override("font_size", 22)
	_press_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_press_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_press_label.offset_top = -140
	_press_label.offset_bottom = -98
	_press_label.offset_left = -350
	_press_label.offset_right = 350
	_ui.add_child(_press_label)


func _update_escape_ui() -> void:
	if not _bar or not _press_label:
		return
	var ratio := clampf(_escape_timer / ESCAPE_TIME, 0.0, 1.0)
	_bar.anchor_right = ratio
	_press_label.text = "TRAPPED — PRESS [E] TO ESCAPE  (%d / %d)" % \
		[_escape_presses, ESCAPE_PRESSES_NEEDED]
