class_name Vignette
extends RefCounted

# Full-screen vignette + tint overlay. Usage:
#   Vignette.spawn(self, Color(0.9, 1.0, 0.9), 0.9)
#
# ⚠️ RESTORED 2026-07-28. This entire file was commented out and `spawn()` was a
# bare `pass`, while `level_3.gd:29` (the Void) went on calling it — so the Void has
# shipped with no vignette for its whole life, and so has every other caller.
# SCARY.md §2.11 defect #3.
#
# Two things had to change for it to be safe to re-enable:
#
# 1. `canvas.layer = -1` put it BEHIND the 3D viewport, where it did nothing
#    visible at all. It now sits at layer 5 — above the world, below PanicHUD's
#    blur/tint stack (which builds its own CanvasLayer) and far below Screamer's
#    100 and DebugLog's 90, so a screamer still wins.
#
# 2. The old fragment shader multiplied the tint into COLOR *and* drove alpha from
#    the same term, so at strength ~2 it washed the centre of the screen. It now
#    darkens the EDGES only and leaves the centre untouched: alpha is zero until
#    `INNER`, which is what makes it a framing device rather than a colour filter.
#
# ⚠️ This is deliberately NOT fog. DUNGEON_NIGHTMARES.md §B7 and SCARY.md §8.9 both
# reject a depth-fade overlay: it is outside this project's rendering contract and
# would fight the panic HUD. A vignette is screen-space and depth-independent —
# it frames, it does not simulate distance.

const SHADER_CODE := """
shader_type canvas_item;
// ⚠️ MULTIPLY, not alpha-over. Every caller passes a LIGHT tint (the Void's is
// Color(0.65, 0.55, 1.0)) because the tint is meant to colour the DARKENING, not to
// be painted on. Drawing it with ordinary alpha blending puts a bright purple halo
// around the screen edges — measured, and the exact opposite of a vignette.
// With blend_mul the centre multiplies by white (unchanged) and the edges multiply
// by a dark version of the tint.
render_mode blend_mul, unshaded;

uniform vec4 tint_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float vignette_strength : hint_range(0.0, 3.0) = 1.0;

// Nothing happens inside this radius: the middle of the screen is where the player
// is actually looking, and tinting it is how the first version washed the image.
const float INNER = 0.34;
const float OUTER = 0.82;

void fragment() {
	float d = distance(SCREEN_UV, vec2(0.5));
	float v = clamp(smoothstep(INNER, OUTER, d) * clamp(vignette_strength, 0.0, 3.0), 0.0, 1.0);
	// 0.18 keeps the corners readable — a vignette that reaches pure black is a
	// letterbox, and this project already has enough darkness to be going on with.
	vec3 edge = tint_color.rgb * 0.18;
	COLOR = vec4(mix(vec3(1.0), edge, v), 1.0);
}
"""


static func spawn(parent: Node, tint: Color, strength: float) -> void:
	if parent == null:
		return
	# Idempotent: levels rebuild themselves from _ready() on every restart, and a
	# second overlay would double the darkening.
	if parent.has_node("VignetteLayer"):
		return

	var canvas := CanvasLayer.new()
	canvas.name = "VignetteLayer"
	canvas.layer = 5
	parent.add_child(canvas)

	var rect := ColorRect.new()
	rect.name = "VignetteRect"
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(rect)

	var shader := Shader.new()
	shader.code = SHADER_CODE

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tint_color", tint)
	mat.set_shader_parameter("vignette_strength", strength)
	rect.material = mat
