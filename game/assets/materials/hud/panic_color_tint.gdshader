shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 target_color : source_color = vec4(0.55, 0.02, 0.02, 1.0);
uniform float blend_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	COLOR = vec4(target_color.rgb, blend_amount);
}
