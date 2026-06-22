extends StaticBody3D
class_name KeyItem

# A generic pickup key. interact() emits `picked_up` once, shows a brief label,
# and frees itself. The level connects `picked_up` to whatever it unlocks (the
# House uses it for the cellar gate). State is level-local, so a scene reload
# after a screamer correctly puts the key back.

signal picked_up

@export var label_text: String = "Key collected"

var _taken: bool = false


func interact() -> void:
	if _taken:
		return
	_taken = true
	picked_up.emit()
	_show_feedback()
	var pickup := get_node_or_null("PickupAudio") as AudioStreamPlayer3D
	if pickup and pickup.stream:
		pickup.play()
	queue_free()


func _show_feedback() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 50
	get_tree().root.add_child(canvas)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	lbl.add_theme_font_size_override("font_size", 36)
	canvas.add_child(lbl)
	get_tree().create_timer(2.0).timeout.connect(canvas.queue_free)
