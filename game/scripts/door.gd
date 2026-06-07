extends StaticBody3D

enum UnlockCondition { NONE, KEYCARD, CODE_ENTERED, TWIST_READ }

@export var unlock_condition: UnlockCondition = UnlockCondition.NONE
@export var advances_level: bool = true
@export var goes_back: bool = false

var _twist_activated: bool = false


func _process(_delta: float) -> void:
	if unlock_condition == UnlockCondition.TWIST_READ and not _twist_activated and GameState.twist_read:
		_twist_activated = true
		_flash_unlock()


func _flash_unlock() -> void:
	var door_mesh: MeshInstance3D = get_node_or_null("DoorMesh")
	if not door_mesh:
		return
	var mat := door_mesh.get_surface_override_material(0)
	if not mat:
		mat = door_mesh.mesh.surface_get_material(0) if door_mesh.mesh else null
	if not mat or not mat is StandardMaterial3D:
		return
	var std_mat := mat as StandardMaterial3D
	var tween := create_tween()
	tween.tween_method(
		func(e: float): std_mat.emission_energy_multiplier = e,
		std_mat.emission_energy_multiplier, 10.0, 0.3
	)
	tween.tween_method(
		func(e: float): std_mat.emission_energy_multiplier = e,
		10.0, 3.0, 0.6
	)


func interact() -> void:
	if _is_unlocked():
		_open_door()
	else:
		_show_locked_feedback()


func _is_unlocked() -> bool:
	match unlock_condition:
		UnlockCondition.NONE:
			return true
		UnlockCondition.KEYCARD:
			return GameState.has_keycard
		UnlockCondition.CODE_ENTERED:
			return GameState.level2_code_correct
		UnlockCondition.TWIST_READ:
			return GameState.twist_read
	return false


func _open_door() -> void:
	var open_audio: AudioStreamPlayer3D = get_node_or_null("OpenAudio")
	if open_audio and open_audio.stream:
		open_audio.play()
	if goes_back:
		await get_tree().create_timer(0.5).timeout
		GameState.go_back()
	elif advances_level:
		await get_tree().create_timer(0.5).timeout
		GameState.advance_level()


func _show_locked_feedback() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 50
	add_child(canvas)

	var lbl := Label.new()
	lbl.text = "LOCKED"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	lbl.add_theme_font_size_override("font_size", 48)
	canvas.add_child(lbl)

	await get_tree().create_timer(1.5).timeout
	canvas.queue_free()
