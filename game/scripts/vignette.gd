class_name Vignette
extends RefCounted

# Utility class for adding a full-screen vignette + tint overlay to a level.
# Usage: Vignette.spawn(self, Color(0.9, 1.0, 0.9), 0.9)

# const SHADER_CODE := """
# shader_type canvas_item;
# uniform vec4 tint_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
# uniform float vignette_strength : hint_range(0.0, 3.0) = 1.0;
# void fragment() {
# 	vec2 uv = SCREEN_UV;
# 	float d = distance(uv, vec2(0.5));
# 	float vignette = 1.0 - smoothstep(0.3, 0.9, d) * vignette_strength;
# 	COLOR = tint_color * vec4(vignette, vignette, vignette, 0.6 * (1.0 - vignette));
# }
# """


static func spawn(parent: Node, tint: Color, strength: float) -> void:
	pass
	# var canvas := CanvasLayer.new()
	# canvas.layer = -1
	# canvas.name = "VignetteLayer"
	# parent.add_child(canvas)

	# var rect := ColorRect.new()
	# rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# canvas.add_child(rect)

	# var shader := Shader.new()
	# shader.code = SHADER_CODE

	# var mat := ShaderMaterial.new()
	# mat.shader = shader
	# mat.set_shader_parameter("tint_color", tint)
	# mat.set_shader_parameter("vignette_strength", strength)
	# rect.material = mat
