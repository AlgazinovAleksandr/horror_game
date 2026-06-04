extends Node3D

const OPENING_NOTE := "You are Subject 47.\n\nThis is a psychological experiment. Your fear response is being monitored.\n\nThe entity you may encounter is a product of your own mind — it cannot harm you unless you believe it can.\n\nStay calm. Do not touch what you are not meant to touch.\n\nThe door ahead is your first test.\n\nWe are watching."

const ENDING_NOTE := "Very good, Subject 47.\n\nBeginning trial 2."

@onready var candle_light: OmniLight3D = $CandleLight
@onready var note: Node = $Note

var _flicker_time: float = 0.0
const BASE_ENERGY := 1.8


func _ready() -> void:
	GameState.current_level = 0
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if GameState.is_ending:
		note.note_text = ENDING_NOTE
		NoteUI.closed.connect(_on_ending_note_closed, CONNECT_ONE_SHOT)
	else:
		note.note_text = OPENING_NOTE


func _process(delta: float) -> void:
	_flicker_time += delta
	candle_light.light_energy = BASE_ENERGY \
		+ sin(_flicker_time * 7.3) * 0.18 \
		+ sin(_flicker_time * 13.7) * 0.09 \
		+ sin(_flicker_time * 3.1) * 0.06


func _on_ending_note_closed() -> void:
	# Fade to black then quit (credits could be added here later)
	var canvas := CanvasLayer.new()
	canvas.layer = 200
	add_child(canvas)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(overlay)

	var tween := create_tween()
	tween.tween_property(overlay, "color", Color.BLACK, 2.5)
	await tween.finished
	get_tree().quit()
