shader_type canvas_item;

uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float vignette_strength : hint_range(0.0, 3.0) = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float d = distance(uv, vec2(0.5));
	float vignette = 1.0 - smoothstep(0.3, 0.9, d) * vignette_strength;
	COLOR = tint_color * vec4(vignette, vignette, vignette, 0.6 * (1.0 - vignette));
}