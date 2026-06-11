shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 1.0) = 0.0;

const float WEIGHTS[5] = float[](0.38, 0.31, 0.2, 0.08, 0.03);

void fragment() {
	vec2 uv = SCREEN_UV;
	if (blur_amount < 0.001) {
		COLOR = texture(screen_texture, uv);
	}
	else{
		vec2 px = SCREEN_PIXEL_SIZE * blur_amount * 10.0;
		vec4 col = texture(screen_texture, uv) * WEIGHTS[0];

		for (int i = 1; i < 5; i++) {
			vec2 offset = px * float(i);
			col += texture(screen_texture, uv + vec2(offset.x, 0.0)) * WEIGHTS[i] / 4.0;
			col += texture(screen_texture, uv + vec2(-offset.x, 0.0)) * WEIGHTS[i] / 4.0;
			col += texture(screen_texture, uv + vec2(0.0, offset.y)) * WEIGHTS[i] / 4.0;
			col += texture(screen_texture, uv + vec2(0.0, -offset.y)) * WEIGHTS[i] / 4.0;
		}

		COLOR = col;
	}
}
