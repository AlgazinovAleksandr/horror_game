extends Node

@export var max_blur_strength: float = 1.0
@export var max_tint_blend: float = 0.5

@onready var _blur_material: ShaderMaterial = $BlurRect.material
@onready var _tint_material: ShaderMaterial = $TintRect.material

const _OBJECTIVE_REST_ALPHA := 0.5   # resting opacity — readable but unobtrusive
var _objective_label: Label = null


func _ready() -> void:
	_build_objective_label()
	GameState.objective_changed.connect(_on_objective_changed)
	# Re-announce on a mid-level reload where GameState already holds the goal.
	if GameState.current_objective != "":
		_on_objective_changed(GameState.current_objective)


func _build_objective_label() -> void:
	_objective_label = Label.new()
	_objective_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_objective_label.offset_top = 22.0
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.add_theme_font_size_override("font_size", 18)
	_objective_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.78))
	# A soft shadow so the line stays legible over bright and dark walls alike.
	_objective_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_objective_label.add_theme_constant_override("shadow_offset_x", 1)
	_objective_label.add_theme_constant_override("shadow_offset_y", 1)
	_objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_label.modulate.a = 0.0
	add_child(_objective_label)


# Announce the new goal: fade up to full, then settle to a quiet resting alpha.
func _on_objective_changed(text: String) -> void:
	if not _objective_label:
		return
	_objective_label.text = text
	if text == "":
		_objective_label.modulate.a = 0.0
		return
	var tween := create_tween()
	tween.tween_property(_objective_label, "modulate:a", 1.0, 0.35)
	tween.tween_interval(2.0)
	tween.tween_property(_objective_label, "modulate:a", _OBJECTIVE_REST_ALPHA, 1.2)


func set_panic_ratio(ratio: float) -> void:
	if not _blur_material or not _tint_material:
		return
	ratio = clampf(ratio, 0.0, 1.0)
	_blur_material.set_shader_parameter("blur_amount", ratio * max_blur_strength)
	_tint_material.set_shader_parameter("blend_amount", ratio * max_tint_blend)


var _breaker_meter_bg: ColorRect = null
var _breaker_meter_fill: ColorRect = null


func _build_breaker_meter() -> void:
	_breaker_meter_bg = ColorRect.new()
	_breaker_meter_bg.color = Color(0.05, 0.05, 0.05, 0.7)
	_breaker_meter_bg.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_breaker_meter_bg.offset_left = -110.0
	_breaker_meter_bg.offset_right = 110.0
	_breaker_meter_bg.offset_top = -70.0
	_breaker_meter_bg.offset_bottom = -52.0
	_breaker_meter_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_breaker_meter_bg.visible = false
	add_child(_breaker_meter_bg)

	var fill := ColorRect.new()
	fill.color = Color(0.3, 0.4, 0.9, 0.9)
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.anchor_right = 0.0
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_breaker_meter_bg.add_child(fill)
	_breaker_meter_fill = fill


# Lab dark-room feature: a live "hot/cold" proximity readout toward the hidden
# breaker, distance-only (no direction) — makes audio-only navigation read as an
# active mini-game rather than ambient noise, without trivializing the actual
# direction-finding with an on-screen compass. ratio < 0 hides the meter
# entirely (the caller sends this once on leaving the dark wing).
func set_breaker_proximity(ratio: float) -> void:
	if not _breaker_meter_bg:
		_build_breaker_meter()
	if ratio < 0.0:
		_breaker_meter_bg.visible = false
		return
	ratio = clampf(ratio, 0.0, 1.0)
	_breaker_meter_bg.visible = true
	_breaker_meter_fill.anchor_right = ratio
	_breaker_meter_fill.color = Color(0.3, 0.4, 0.9).lerp(Color(0.95, 0.15, 0.1), ratio)
