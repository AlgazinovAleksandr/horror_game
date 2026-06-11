extends Node

@export var max_blur_strength: float = 1.0
@export var max_tint_blend: float = 0.5

@onready var _blur_material: ShaderMaterial = $BlurRect.material
@onready var _tint_material: ShaderMaterial = $TintRect.material


func set_panic_ratio(ratio: float) -> void:
	if not _blur_material or not _tint_material:
		return
	ratio = clampf(ratio, 0.0, 1.0)
	_blur_material.set_shader_parameter("blur_amount", ratio * max_blur_strength)
	_tint_material.set_shader_parameter("blend_amount", ratio * max_tint_blend)
