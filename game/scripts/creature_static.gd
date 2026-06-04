extends Node3D

# Level 3 only. Stands motionless in the room.
# Call rush_camera() before Screamer.trigger() for a brief lunge effect.

var _rushing: bool = false


func rush_camera(camera_pos: Vector3) -> void:
	if _rushing:
		return
	_rushing = true
	var tween := create_tween()
	tween.tween_property(self, "global_position", camera_pos, 0.4) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
