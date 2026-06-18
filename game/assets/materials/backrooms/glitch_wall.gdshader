shader_type spatial;
render_mode cull_disabled, unshaded;

// The seam-tearing exit wall: vertices jitter in horizontal bands and the
// wallpaper texture is sliced and RGB-split, so the surface looks like reality
// is failing. Walking into it (Area3D in backrooms.gd) drops you into the Void.

uniform sampler2D base_tex : source_color;
uniform float tear_amount = 0.12;
uniform float speed = 6.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

void vertex() {
	// Per-horizontal-band displacement that snaps to new offsets over time.
	float band = floor(VERTEX.y * 6.0);
	float t = floor(TIME * speed);
	float j = hash(band + t) - 0.5;
	// occasional violent tears
	float burst = step(0.85, hash(band * 1.7 + t)) * 3.0;
	VERTEX.x += j * tear_amount * (1.0 + burst);
	VERTEX.z += (hash(band + t + 4.0) - 0.5) * tear_amount * 0.5;
}

void fragment() {
	vec2 uv = UV;
	float band = floor(uv.y * 24.0);
	float t = floor(TIME * speed);
	// horizontal slice offset per band
	float slice = (hash(band + t) - 0.5) * 0.08;
	uv.x += slice;
	// RGB split
	float split = 0.012 * (0.5 + hash(t));
	float r = texture(base_tex, uv + vec2(split, 0.0)).r;
	float g = texture(base_tex, uv).g;
	float b = texture(base_tex, uv - vec2(split, 0.0)).b;
	vec3 col = vec3(r, g, b);
	// darken + flicker toward black so it reads as a void seam
	float flick = 0.55 + 0.45 * hash(t + band * 0.3);
	col *= flick * 0.7;
	ALBEDO = col;
}
