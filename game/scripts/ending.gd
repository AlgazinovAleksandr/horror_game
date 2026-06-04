extends Node

# Autoload-friendly: creates its own overlay nodes at runtime.


func _ready() -> void:
	_play_ending()


func _play_ending() -> void:
	await get_tree().create_timer(1.0).timeout
	GameState.is_ending = true
	GameState.current_level = 0
	get_tree().change_scene_to_file(GameState.SCENE_INTRO)
