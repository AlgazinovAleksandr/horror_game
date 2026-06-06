extends Node

# Persists across scene changes as an Autoload singleton (GameState)

var current_level: int = 0       # 0=intro, 1=lab, 2=house, 3=void
var has_keycard: bool = false     # Level 1 unlock item
var level2_code: String = "472"  # Combination lock answer for Level 2
var level2_code_correct: bool = false  # Set to true by combination_lock.gd on correct entry
var twist_read: bool = false           # True once the twist note in Level 3 is read
var is_ending: bool = false       # True when loading intro room as the twist ending

const SCENE_INTRO   := "res://scenes/intro_room.tscn"
const SCENE_LEVEL_1 := "res://scenes/level_1.tscn"
const SCENE_LEVEL_2 := "res://scenes/level_2.tscn"
const SCENE_LEVEL_3 := "res://scenes/level_3.tscn"
const SCENE_ENDING  := "res://scenes/ending.tscn"


func reset_level_state() -> void:
	has_keycard = false
	level2_code_correct = false


func advance_level() -> void:
	current_level += 1
	reset_level_state()
	match current_level:
		1: get_tree().change_scene_to_file(SCENE_LEVEL_1)
		2: get_tree().change_scene_to_file(SCENE_LEVEL_2)
		3: get_tree().change_scene_to_file(SCENE_LEVEL_3)
		_: get_tree().change_scene_to_file(SCENE_ENDING)


# Try loading an audio file by base name — accepts .wav or .ogg, whichever exists.
static func load_audio(base_name: String) -> AudioStream:
	for ext in ["wav", "ogg"]:
		var path := "res://assets/audio/%s.%s" % [base_name, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return null


func go_back() -> void:
	current_level -= 1
	match current_level:
		0: get_tree().change_scene_to_file(SCENE_INTRO)
		1: get_tree().change_scene_to_file(SCENE_LEVEL_1)
		2: get_tree().change_scene_to_file(SCENE_LEVEL_2)


func restart_current_level() -> void:
	reset_level_state()
	match current_level:
		0: get_tree().change_scene_to_file(SCENE_INTRO)
		1: get_tree().change_scene_to_file(SCENE_LEVEL_1)
		2: get_tree().change_scene_to_file(SCENE_LEVEL_2)
		3: get_tree().change_scene_to_file(SCENE_LEVEL_3)
