extends StaticBody3D

enum UnlockCondition { NONE, KEYCARD, CODE_ENTERED, TWIST_READ }

@export var unlock_condition: UnlockCondition = UnlockCondition.NONE
@export var advances_level: bool = true


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
	if advances_level:
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
