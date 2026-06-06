extends StaticBody3D


func _ready() -> void:
	if GameState.has_keycard:
		queue_free()


func interact() -> void:
	GameState.has_keycard = true
	_show_feedback()
	var pickup_audio: AudioStreamPlayer3D = get_node_or_null("PickupAudio")
	if pickup_audio and pickup_audio.stream:
		pickup_audio.play()
		await pickup_audio.finished
	queue_free()


func _show_feedback() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 50
	get_tree().root.add_child(canvas)

	var lbl := Label.new()
	lbl.text = "Keycard collected"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	lbl.add_theme_font_size_override("font_size", 36)
	canvas.add_child(lbl)

	get_tree().create_timer(2.0).timeout.connect(canvas.queue_free)
