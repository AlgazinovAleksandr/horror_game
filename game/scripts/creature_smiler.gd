extends Node3D
class_name CreatureSmiler

# The Backrooms darkness entity: a wide glowing smile floating at the end of a
# blacked-out arm. Its logic INVERTS the rest of the maze (see Backrooms Q2):
#   * Shine your flashlight on it, or sprint, and it rushes you -> fatal screamer.
#   * Turn the light OFF and stay calm (don't sprint) and the smile fades — you
#     survived. Walking away (not sprinting) also lets you slip past.
# While engaged it suspends the maze's standstill + dark panic ticks and drives a
# slow dread of its own, so freezing to wait it out is tense but fair.

const ENGAGE_DIST := 16.0      # smile "notices" you within this range
const DISENGAGE_DIST := 21.0   # walk this far (without sprinting) and it lets go
const FADE_TIME := 5.0         # seconds of light-off calm before it fades
const LOOK_DOT := 0.55         # camera-forward·to-smile that counts as "lit"
const DREAD_RATE := 2.5        # panic/s while engaged — the climb you must endure
const TEX_PATH := "res://assets/textures/level_backrooms/screamer_smiler.png"

var _player: CharacterBody3D
var _camera: Camera3D
var _engaged: bool = false
var _fade: float = 0.0
var _done: bool = false


func _ready() -> void:
	_build_face()


func _build_face() -> void:
	var quad := MeshInstance3D.new()
	quad.name = "SmilerFace"
	var mesh := QuadMesh.new()
	# ⚠️ SIZED FROM THE ARTWORK (2026-08-17, backlog 04 B-A9 / X2). `screamer_smiler.png` is
	# 1024x1024, i.e. square, and this was a 1.5 x 1.1 quad — the face was squashed 36 %
	# vertically, on the only object in the level that kills you for looking at it with a
	# light on. Width is the fixed dimension, so the face does not get smaller.
	const FACE_W := 1.5
	var aspect := 1.0
	if ResourceLoader.exists(TEX_PATH):
		var t: Texture2D = load(TEX_PATH)
		if t and t.get_width() > 0:
			aspect = float(t.get_width()) / float(t.get_height())
	mesh.size = Vector2(FACE_W, FACE_W / aspect)
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var tex_path := TEX_PATH
	if ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
		mat.emission_enabled = true
		mat.emission_texture = load(tex_path)
		mat.emission_energy_multiplier = 2.2
	else:
		mat.albedo_color = Color(1, 1, 1)
		mat.emission_enabled = true
		mat.emission = Color(1, 1, 1)
		mat.emission_energy_multiplier = 2.0
	quad.set_surface_override_material(0, mat)
	quad.position.y = 1.6
	add_child(quad)


func _process(delta: float) -> void:
	if _done:
		return
	if not _player:
		_player = get_node_or_null("../Player") as CharacterBody3D
		if not _player:
			return
		_camera = _player.get_node_or_null("Camera3D") as Camera3D
	if not _camera:
		return

	var to: Vector3 = global_position + Vector3(0, 1.6, 0) - _camera.global_position
	var dist := to.length()

	if not _engaged:
		if dist <= ENGAGE_DIST:
			_engaged = true
			_player.set_smiler_active(true)
		return

	# Engaged: a slow dread climbs no matter what (the darkness presses in).
	_player.add_panic(DREAD_RATE * delta)

	var looking := (-_camera.global_transform.basis.z).dot(to.normalized()) > LOOK_DOT

	# Fatal: lighting it up, or losing your nerve and bolting.
	if _player.is_sprinting():
		_rush()
		return
	if _player.is_flashlight_on() and looking:
		_rush()
		return

	# Survive: light off, no sprint — hold your nerve until it fades.
	if not _player.is_flashlight_on():
		_fade += delta
		if _fade >= FADE_TIME:
			_despawn()
			return
	else:
		_fade = 0.0

	# Slip away: put real distance between you and it (at a walk) and it releases.
	if dist >= DISENGAGE_DIST:
		_despawn()


func _rush() -> void:
	_done = true
	if _player:
		_player.set_smiler_active(false)
		_player.jolt_camera(0.12, 0.4)
	Screamer.trigger()  # LEVEL_SCREAMERS[4] -> the smiler image fills the screen


func _despawn() -> void:
	_done = true
	if _player:
		_player.set_smiler_active(false)
	queue_free()
