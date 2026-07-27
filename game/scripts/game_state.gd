extends Node

# Persists across scene changes as an Autoload singleton (GameState)

signal objective_changed(text: String)  # drives the subtle objective HUD line
signal carried_changed(item: String)    # drives the "CARRYING: …" HUD line
var current_objective: String = ""       # current level goal shown to the player
var carried_item: String = ""            # "" | "cellar key" | "vinegar" | "hammer" | …

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

# The intro room's exit door is held until the opening note has been read — you cannot
# be told the rules and then walk past them (BACKLOG #12). Survives reset_level_state()
# so a death-restart of the intro room doesn't demand a re-read.
var intro_note_read: bool = false

# One global teach ledger for the apparition. The FIRST HOLD encounter in a run is
# survivable wherever it happens, so a fatal one can never be the one that teaches you
# the rule. Previously each level decided this alone and the House cellar's non-teach
# copy could be your first if you missed the Lab's.
var apparition_taught: bool = false

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
	carried_item = ""
	carried_changed.emit("")

# Set the current objective line; the HUD (panic_hud.gd) listens for this.
func set_objective(text: String) -> void:
	current_objective = text
	objective_changed.emit(text)


# Set what the player is visibly carrying. "" clears the line.
func set_carried(item: String) -> void:
	carried_item = item
	carried_changed.emit(item)


# ------------------------------------------------------------ notes journal
#
# Every non-trap note you actually READ is archived so it can be re-read at any time
# (journal_ui.gd, TAB). This exists because the game hides answers across levels —
# KONTUR's gates are all hinted in levels 1-4 — and "I skipped a note" used to mean
# walking a whole level back. Trap notes are deliberately NOT archived: replaying one
# safely would hand the read-to-die mechanic a free loophole.
var journal: Array[Dictionary] = []

func record_note(text: String, level: int) -> void:
	if text.strip_edges() == "":
		return
	for e in journal:
		if e["text"] == text:
			return                      # already have it
	journal.append({"level": level, "text": text, "title": _note_title(text)})


func _note_title(text: String) -> String:
	var first := text.strip_edges().split("\n")[0].strip_edges()
	if first.length() > 42:
		first = first.substr(0, 39) + "…"
	return first


# ------------------------------------------------- per-level progress snapshots
#
# BACKLOG #30: walking back to an earlier level used to replay it from scratch, because
# advance_level() / go_back() / restart_current_level() were all literally the same
# thing — every one funnelled into start_current_level(), which reloads the scene and
# rebuilds it from _ready(). All puzzle state lived in level-script locals and died.
#
# Contract: a level script MAY implement
#     func save_progress() -> Dictionary
#     func restore_progress(data: Dictionary) -> void
# `_capture_progress()` (below) calls the first on the way out; the level calls
# `get_level_progress(n)` itself in _ready() and passes the result to the second.
#
# ⚠️ A DEATH still wipes the level. restart_current_level() erases the snapshot on
# purpose — the no-checkpoint fail philosophy in COMMENTS.md is intact. This is about
# NAVIGATION (going back for a note you missed), not about softening failure.
var level_progress: Dictionary = {}

# How many times the player has RESTARTED each level after dying there, keyed by level
# number. Unlike level_progress this deliberately SURVIVES a death — it is the record of
# the deaths themselves — and is only cleared by go_to_main_menu(), i.e. per run.
# Level 6 uses it to shorten Object 12's familiarization window on a retry: the point of
# that window is learning the layout, and a player on their second attempt already has.
var level_attempts: Dictionary = {}


# 0 the first time a level is entered in this run, 1 after the first death there, etc.
func get_level_attempts(level: int) -> int:
	return int(level_attempts.get(level, 0))

# True when the player entered the current level through the NEXT level's back door.
# Levels use it to spawn the player at their EXIT end rather than their entrance —
# you came back through the exit, so that is where you should be standing, and for
# the 320 m Corridor it is the difference between a walk and a re-run.
var entered_from_ahead: bool = false


func get_level_progress(level: int) -> Dictionary:
	return level_progress.get(level, {})


func save_level_progress(level: int, data: Dictionary) -> void:
	level_progress[level] = data


func _capture_progress() -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_method("save_progress"):
		level_progress[current_level] = scene.call("save_progress")


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
	_capture_progress()
	entered_from_ahead = false
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
	_capture_progress()
	entered_from_ahead = true
	current_level -= 1
	start_current_level()


func go_to_main_menu() -> void:
	is_ending = false
	twist_read = false
	kontur_banished = false
	intro_note_read = false
	apparition_taught = false
	current_level = 0
	has_keycard = false
	level2_code_correct = false
	entered_from_ahead = false
	level_progress.clear()
	level_attempts.clear()
	journal.clear()
	set_carried("")
	get_tree().change_scene_to_file(SCENE_MAIN_MENU)


func restart_current_level() -> void:
	# A death resets the level completely — the snapshot is discarded, not restored.
	# See the ⚠️ on level_progress above: resume is for navigation, not for failure.
	level_progress.erase(current_level)
	level_attempts[current_level] = get_level_attempts(current_level) + 1
	entered_from_ahead = false
	start_current_level()
