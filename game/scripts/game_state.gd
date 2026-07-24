extends Node

# Persists across scene changes as an Autoload singleton (GameState)

signal objective_changed(text: String)  # drives the subtle objective HUD line
var current_objective: String = ""       # current level goal shown to the player

var current_level: int = 0       # 0=intro, 1=lab, 2=house, 3=corridor, 4=backrooms, 5=kontur, 6=breach, 7=void, 8=ending
var has_keycard: bool = false     # Level 1 unlock item
var level2_code: String = "472"  # Combination lock answer for Level 2
var level2_code_correct: bool = false  # Set to true by combination_lock.gd on correct entry
var twist_read: bool = false           # True once the twist note in Level 3 is read
var is_ending: bool = false       # True when loading intro room as the twist ending

# Set when KONTUR's wrong door drops the player out of the world and demotes them to
# the Backrooms. backrooms.gd reads it on arrival to show the accusation, then clears
# it. Like `is_ending`, this MUST survive a level change — so it is deliberately NOT
# touched by reset_level_state(), which runs on every transition.
var kontur_banished: bool = false

const SCENE_INTRO   := "res://scenes/intro_room.tscn"
const SCENE_LEVEL_1 := "res://scenes/level_1.tscn"
const SCENE_LEVEL_2 := "res://scenes/level_2_1.tscn"
const SCENE_CORRIDOR := "res://scenes/corridor.tscn"
const SCENE_BACKROOMS := "res://scenes/backrooms.tscn"
const SCENE_KONTUR  := "res://scenes/kontur.tscn"
const SCENE_LEVEL_6_BREACH := "res://scenes/level_6_breach.tscn"   # Object 12, loose
const SCENE_LEVEL_3 := "res://scenes/level_3.tscn"   # The Void
const SCENE_ENDING  := "res://scenes/ending.tscn"
const SCENE_MAIN_MENU := "res://scenes/main_menu.tscn"


func reset_level_state() -> void:
	has_keycard = false
	level2_code_correct = false

# Set the current objective line; the HUD (panic_hud.gd) listens for this.
func set_objective(text: String) -> void:
	current_objective = text
	objective_changed.emit(text)


func start_current_level() -> void:
	reset_level_state()
	current_objective = ""  # cleared so the next level re-announces its goal cleanly
	match current_level:
		0: get_tree().change_scene_to_file(SCENE_INTRO)
		1: get_tree().change_scene_to_file(SCENE_LEVEL_1)
		2: get_tree().change_scene_to_file(SCENE_LEVEL_2)
		3: get_tree().change_scene_to_file(SCENE_CORRIDOR)
		4: get_tree().change_scene_to_file(SCENE_BACKROOMS)
		5: get_tree().change_scene_to_file(SCENE_KONTUR)
		6: get_tree().change_scene_to_file(SCENE_LEVEL_6_BREACH)
		7: get_tree().change_scene_to_file(SCENE_LEVEL_3)
		8: get_tree().change_scene_to_file(SCENE_ENDING)
		_: get_tree().change_scene_to_file(SCENE_INTRO)

func advance_level() -> void:
	current_level += 1
	start_current_level()

const AUDIO_SUBDIRS := ["shared", "level_1_lab", "level_2_house", "level_3_corridor", "level_backrooms", "level_5_kontur", "level_6_breach", "level_4_void", "intro"]

# Try loading an audio file by base name — searches all audio subdirectories.
static func load_audio(base_name: String) -> AudioStream:
	for ext in ["wav", "ogg", "mp3"]:
		for subdir in AUDIO_SUBDIRS:
			var path := "res://assets/audio/%s/%s.%s" % [subdir, base_name, ext]
			if ResourceLoader.exists(path):
				return load(path)
	return null


func go_back() -> void:
	current_level -= 1
	start_current_level()


func go_to_main_menu() -> void:
	is_ending = false
	twist_read = false
	kontur_banished = false
	current_level = 0
	has_keycard = false
	level2_code_correct = false
	get_tree().change_scene_to_file(SCENE_MAIN_MENU)


func restart_current_level() -> void:
	start_current_level()
