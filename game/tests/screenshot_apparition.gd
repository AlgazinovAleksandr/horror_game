extends SceneTree

# Loads the Lab, positions the player in the main hall, triggers the apparition
# (dynamic call — avoids force-compiling autoload-dependent classes here), waits
# for the fade-in, and screenshots it. Confirms the figure renders + is placed
# ahead of the player. Run: Godot --path game --script res://tests/screenshot_apparition.gd

const OUT := "/tmp/appar_shots/"
var _frame := 0
var _player: CharacterBody3D
var _triggered := false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	change_scene_to_file("res://scenes/level_1.tscn")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 10:
		_player = current_scene.get_node_or_null("Player") as CharacterBody3D
		if _player:
			_player.global_position = Vector3(0, 1.6, 6.5)
			_player.rotation.y = atan2(0.0, -1.0)  # look +z down the hall
	elif _frame == 14 and not _triggered:
		_triggered = true
		if current_scene.has_method("_trigger_apparition"):
			current_scene._trigger_apparition()
			print("apparition triggered")
	elif _frame == 60:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(OUT + "apparition.png")
		print("shot saved")
		return true
	return false
