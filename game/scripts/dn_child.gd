class_name DnChild
extends Node3D

# THE CHILD — DN's Ghost Girl (DUNGEON_NIGHTMARES.md §B4.4).
#
# ⚠️ HARMLESS. ALWAYS. NO EXCEPTIONS. ZERO FAIL STATE, EVER.
#
# Her entire function is to burn your nerve and to make the REAL threats ambiguous.
# She costs `PANIC` and nothing else — about a third of the Lab nook scare.
#
# Two gates, and both are what make the level's scare economy legible:
#   1. Only while the candle is OUT. Suppressing her is the candle's one unambiguous
#      UPSIDE, and it is what makes the light/dark choice a genuine dilemma rather
#      than a strict tax.
#   2. ⚠️ Only when NO PRIMARY ENTITY IS PRESENT. DN2's own rule: the game never
#      stacks a fake scare onto a real threat. Break this and every subsequent
#      "was that something?" becomes unanswerable, which would destroy the one
#      skill this level is actually testing.
# The level owns both checks — it is the thing that knows about candles and Matrons.

signal appeared

const PANIC := 6.0
const MIN_GAP := 45.0
const MAX_GAP := 90.0
const SMEAR_TEX := "res://assets/textures/level_9_dungeon/dn_child_smear.png"
const PEEK_SECONDS := 0.35
const FACE_SECONDS := 0.2

enum Variant { PEEK, SPRINT_PAST, FACE }

var _player: CharacterBody3D = null
var _timer: float = 0.0
var _peek: MeshInstance3D = null
var _peek_mat: StandardMaterial3D = null
var _peek_t: float = 0.0
var _sfx: AudioStreamPlayer3D = null


const PARKED := Vector3(0, -60, 0)


func _ready() -> void:
	_timer = randf_range(MIN_GAP, MAX_GAP)
	# ⚠️ Parked far below the world while idle, not left at the origin. The billboard
	# is invisible either way, but tests/check_wall_overlap.gd collects EVERY
	# QuadMesh regardless of visibility and correctly reported a quad sitting inside
	# whichever chamber floor happened to straddle (0,0,0). Weakening that assertion
	# to ignore hidden nodes would blind it to a real buried-prop bug; moving the
	# prop is free.
	global_position = PARKED
	_build()


func _build() -> void:
	# Reuses the Hollow One's silhouette cutout, tinted paler and smaller. A second
	# generated asset would buy nothing: what distinguishes the Child from a real
	# threat is her BEHAVIOUR and her sound, not her outline — and the ambiguity is
	# the point.
	_peek = MeshInstance3D.new()
	_peek.name = "ChildPeek"
	var qm := QuadMesh.new()
	qm.size = Vector2(0.7, 1.25)
	_peek.mesh = qm
	_peek_mat = StandardMaterial3D.new()
	_peek_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_peek_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_peek_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_peek_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tex_path := "res://assets/textures/level_9_dungeon/dn_hollow_figure.png"
	if ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path)
		if tex != null:
			_peek_mat.albedo_texture = tex
	_peek_mat.albedo_color = Color(0.85, 0.82, 0.78, 0.0)
	_peek.material_override = _peek_mat
	_peek.visible = false
	add_child(_peek)

	_sfx = AudioStreamPlayer3D.new()
	_sfx.name = "ChildSfx"
	_sfx.unit_size = 10.0
	_sfx.volume_db = -6.0
	add_child(_sfx)


func register_player(p: CharacterBody3D) -> void:
	_player = p


# `allowed` is the level's answer to "candle out AND no primary present". Passing it
# in rather than querying keeps this script ignorant of both systems.
func tick(delta: float, allowed: bool) -> void:
	if _peek_t > 0.0:
		_peek_t -= delta
		_peek_mat.albedo_color.a = clampf(_peek_t / PEEK_SECONDS, 0.0, 1.0) * 0.9
		if _peek_t <= 0.0:
			_peek.visible = false
			global_position = PARKED   # back out of the world between appearances
		return

	if not allowed or _player == null or not is_instance_valid(_player):
		return

	_timer -= delta
	if _timer > 0.0:
		return
	_timer = randf_range(MIN_GAP, MAX_GAP)
	_fire()


func _fire() -> void:
	var pick: int = randi() % 3
	match pick:
		Variant.PEEK:
			_do_peek()
		Variant.SPRINT_PAST:
			_do_sprint_past()
		_:
			_do_face()
	if _player.has_method("add_panic"):
		_player.add_panic(PANIC)
	appeared.emit()


# Gone when you look again.
func _do_peek() -> void:
	var basis_z: Vector3 = _player.global_transform.basis.z
	var ahead: Vector3 = _player.global_position - basis_z * 4.0
	global_position = Vector3(ahead.x, 0.0, ahead.z)
	_peek.position = Vector3(0, 0.62, 0)
	_peek.visible = true
	_peek_t = PEEK_SECONDS
	_play("child_peek")


# A laugh and a blood smear across the view.
func _do_sprint_past() -> void:
	global_position = _player.global_position
	_play("child_laugh")
	# flash_scare is SURVIVABLE by construction: no pause, no restart, and the
	# caller owns the panic (which here is 6 and nothing else).
	Screamer.flash_scare(SMEAR_TEX, "child_laugh", 0.5)


# A face in the dark two metres ahead, for a fifth of a second.
func _do_face() -> void:
	var basis_z: Vector3 = _player.global_transform.basis.z
	var ahead: Vector3 = _player.global_position - basis_z * 2.0
	global_position = Vector3(ahead.x, 0.0, ahead.z)
	_peek.position = Vector3(0, 1.2, 0)
	_peek.visible = true
	_peek_t = FACE_SECONDS
	_play("child_laugh")


func _play(base_name: String) -> void:
	var s := GameState.load_audio(base_name)
	if s == null or _sfx == null:
		return
	_sfx.stream = s
	_sfx.pitch_scale = randf_range(0.95, 1.08)
	_sfx.play()
