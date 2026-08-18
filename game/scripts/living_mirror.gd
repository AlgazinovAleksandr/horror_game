extends Node3D
class_name LivingMirror

# A one-way mirror / living painting. A dark reflective panel with a figure that
# is only THERE when you are not looking straight at it (Weeping-Angel observation
# logic): look head-on and it is just a mirror; glance away and a figure fades in
# behind the glass. Staring also feeds mild gaze panic (ScaryObject), so you can't
# safely study it. Placed + oriented by the level; the panel faces local -Z.

const LOOK_DOT := 0.8       # how head-on the camera must be to "clear" the glass
const REVEAL_SPEED := 5.0   # alpha lerp rate
const FIG_BASE := "res://assets/textures/screamers/shared_screamer_figure"
const GLASS_TEX := "res://assets/textures/level_1_lab/lab_oneway_mirror.png"
const GAZE_INTENSITY := 0.7

# ⚠️ BOTH QUADS ARE SIZED FROM THEIR OWN ARTWORK (2026-08-17, backlog 04 B-A9, X2/X23).
# Measured in the Sprawl, where this prop is reused:
#
#   glass  QuadMesh(1.2, 1.8) = 0.667 aspect · lab_oneway_mirror.png 1402x1122 = 1.250
#                                                                     -> 1.874x STRETCH
#   figure QuadMesh(1.0, 1.7) = 0.588 aspect · shared_screamer_figure.png 1696x2528 = 0.671
#                                                                     -> 1.141x stretch
#
# The glass art is a LANDSCAPE framed observation window, squashed onto a portrait quad —
# the frame it draws was visibly out of square, and the "figure behind the glass" was 5 %
# wider than it should be. Sized here rather than hard-coded, so a re-cut texture cannot
# silently reintroduce the stretch.
#
# ⚠️ OPT-IN, AND DEFAULTED OFF. `fit_to_art` is false, so every existing caller — the Lab's
# Observation mirror and the House's two — renders at the historical 1.2 x 1.8 glass and
# 1.0 x 1.7 figure, BYTE-IDENTICALLY. Only the Backrooms Sprawl, which is the level this was
# measured in and the level whose pass this is, sets it true.
#
# It is opt-in rather than global because turning it on is a VISIBLE change: the glass turns
# from portrait to landscape (1.7994 x 1.4400, the same diagonal) and the figure loses 0.21 m
# of height. The Lab and the House are verified and closed, and a shared prop is not the place
# to alter two finished levels as a side effect of fixing a third. Their halves are recorded
# as a cross-level item with these measurements; each is one line in its own pass.
#
# ⚠️ Do NOT "just make it the default". The distortion is real in all three levels and the fix
# is correct in all three — the argument is about WHEN, not whether.
@export var fit_to_art: bool = false

# The historical sizes, used when fit_to_art is false. Do not change these; change the flag.
const LEGACY_GLASS := Vector2(1.2, 1.8)
const LEGACY_FIGURE := Vector2(1.0, 1.7)

# ⚠️ THE LARGEST DIMENSION IS PRESERVED (1.8 m) when the flag IS set, so the pane's diagonal is
# the size it always was — it turns from portrait to landscape rather than shrinking.
# Letterboxing it inside the old box would have been the low-risk choice and would have made
# the mirror 47 % smaller. The figure's HEIGHT is what shrinks (1.70 -> 1.49), keeping its
# width at 1.0 so it still sits inside the glass exactly as it did.
const GLASS_H := 1.44       # 1.2 x 1.8 legacy; 1.80 x 1.44 at the art's own aspect
const GLASS_W_FALLBACK := 1.8
const FIG_H := 1.49         # 1.7 legacy; the width stays 1.0 at the source's own aspect
const GLASS_DEPTH := 0.12


# Width for `height` at this texture's own pixel aspect, or `fallback` if it is missing.
static func _fit_width(tex_path: String, height: float, fallback: float) -> float:
	if not ResourceLoader.exists(tex_path):
		return fallback
	var tex: Texture2D = load(tex_path)
	if not tex or tex.get_height() <= 0:
		return fallback
	return height * (float(tex.get_width()) / float(tex.get_height()))

var _player: CharacterBody3D
var _camera: Camera3D
var _figure: MeshInstance3D
var _fmat: StandardMaterial3D
var _reveal: float = 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	# Gaze panic: ScaryObject must be an ancestor of the collider; the body carries
	# the world transform (ScaryObject is a plain Node — see the transform gotcha).
	var scary := ScaryObject.new()
	scary.scare_intensity = GAZE_INTENSITY
	add_child(scary)
	var body := StaticBody3D.new()
	scary.add_child(body)
	# ScaryObject is a plain Node and breaks the Node3D transform chain, so the
	# body would otherwise sit at the world origin (an invisible wall blocking the
	# level). Seed it with this mirror's world transform — same fix as creature_stalker.
	body.global_transform = global_transform

	var glass := LEGACY_GLASS
	var figure := LEGACY_FIGURE
	if fit_to_art:
		glass = Vector2(_fit_width(GLASS_TEX, GLASS_H, GLASS_W_FALLBACK), GLASS_H)
		figure = Vector2(_fit_width(Apparition._resolve_tex(FIG_BASE), FIG_H, 1.0), FIG_H)
	var mirror := MeshInstance3D.new()
	mirror.name = "MirrorGlass"
	var mm := QuadMesh.new()
	mm.size = glass
	mirror.mesh = mm
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.06, 0.07, 0.09)
	mmat.metallic = 0.9
	mmat.roughness = 0.12
	# The glass texture gives the panel a frame, grime and a suggestion of depth.
	# It shipped on disk unused while every one-way mirror in the game was a flat
	# dark quad. Kept guarded so the mirror still works if the file is absent, and
	# the albedo tint above stays as the multiplier so it reads dark either way.
	if ResourceLoader.exists(GLASS_TEX):
		mmat.albedo_texture = load(GLASS_TEX)
		mmat.albedo_color = Color(0.7, 0.75, 0.8)
	mirror.set_surface_override_material(0, mmat)
	body.add_child(mirror)

	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	# The collider is the gaze target, so it must track the glass it represents.
	cs.size = Vector3(glass.x, glass.y, GLASS_DEPTH)
	col.shape = cs
	body.add_child(col)

	_figure = MeshInstance3D.new()
	_figure.name = "MirrorFigure"
	var fq := QuadMesh.new()
	fq.size = figure
	_figure.mesh = fq
	_fmat = StandardMaterial3D.new()
	_fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var fig := Apparition._resolve_tex(FIG_BASE)
	if fig != "":
		var tex := load(fig)
		_fmat.albedo_texture = tex
		_fmat.emission_enabled = true
		_fmat.emission_texture = tex
		_fmat.emission_energy_multiplier = 0.5
	else:
		_fmat.albedo_color = Color(0.5, 0.5, 0.55, 1.0)
	_fmat.albedo_color.a = 0.0
	_figure.set_surface_override_material(0, _fmat)
	# Just in front of the glass on the room side (-Z local), so it reads.
	_figure.position = Vector3(0, 0, -0.05)
	body.add_child(_figure)


func _process(delta: float) -> void:
	if not _player or not is_instance_valid(_player):
		_player = get_node_or_null("../Player") as CharacterBody3D
		if not _player:
			_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		if _player:
			_camera = _player.get_node_or_null("Camera3D") as Camera3D
		if not _camera:
			return

	# Direction from the camera to the mirror; how head-on is the player looking?
	var to_mirror := (global_position + Vector3(0, 1.5, 0)) - _camera.global_position
	if to_mirror.length() < 0.01:
		return
	var looking := (-_camera.global_transform.basis.z).dot(to_mirror.normalized())
	# Looking head-on -> clear (target 0). Looking away -> figure present (target 1).
	var target := 0.0 if looking > LOOK_DOT else 1.0
	_reveal = move_toward(_reveal, target, REVEAL_SPEED * delta)
	_fmat.albedo_color.a = _reveal
