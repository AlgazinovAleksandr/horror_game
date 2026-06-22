extends Node3D
class_name LivingMirror

# A one-way mirror / living painting. A dark reflective panel with a figure that
# is only THERE when you are not looking straight at it (Weeping-Angel observation
# logic): look head-on and it is just a mirror; glance away and a figure fades in
# behind the glass. Staring also feeds mild gaze panic (ScaryObject), so you can't
# safely study it. Placed + oriented by the level; the panel faces local -Z.

const LOOK_DOT := 0.8       # how head-on the camera must be to "clear" the glass
const REVEAL_SPEED := 5.0   # alpha lerp rate
const FIG_BASE := "res://assets/textures/level_1_lab/apparition_figure"
const GAZE_INTENSITY := 0.7

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

	var mirror := MeshInstance3D.new()
	var mm := QuadMesh.new()
	mm.size = Vector2(1.2, 1.8)
	mirror.mesh = mm
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.06, 0.07, 0.09)
	mmat.metallic = 0.9
	mmat.roughness = 0.12
	mirror.set_surface_override_material(0, mmat)
	body.add_child(mirror)

	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(1.2, 1.8, 0.12)
	col.shape = cs
	body.add_child(col)

	_figure = MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(1.0, 1.7)
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
