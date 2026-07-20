extends Node3D
class_name CreatureShapechanger

# The Perëkozhnik ("shapechanger") — KONTUR's mimic. It stands motionless in a
# corner, looking almost like an ordinary resident, and it NEVER moves or chases.
# It is not a gate: it exists to make the infected half of the level feel occupied,
# and to punish the one instinct this level otherwise rewards — walking up to
# something to get a better look.
#
# Staring feeds gaze panic (ScaryObject). Closing to KILL_DIST is fatal.
#
# Built like living_mirror.gd: ScaryObject -> StaticBody3D -> collider, with the
# world transform seeded onto the BODY, because ScaryObject is a plain Node and
# breaks the Node3D transform chain (ISSUES_SOLUTIONS.md Issue 10).

const TEX_PATH := "res://assets/textures/level_5_kontur/creature_shapechanger.png"

# ⚠️ DELIBERATE, do not "balance" this down.
#
# 0.8 x PANIC_BASE_RATE (20) = 16 panic/s, and KONTUR is the one level with no decay
# at all (its floor-wide DreadZone cancels decay exactly), so a stare kills in ~3 s
# from an empty bar and ~2 s after a single strike. That is faster than the level's
# stated three-strike budget, and it was raised in playtest (2026-07-21, two deaths
# here in one session) and kept on purpose: in KONTUR, looking at things costs you.
# The creature sits 3.2 m off the walking line, so every second of eye contact is a
# choice the player made.
const GAZE_INTENSITY := 0.8
const KILL_DIST := 2.0
const SIZE := Vector2(0.9, 1.9)

var _player: CharacterBody3D
var _body: StaticBody3D
var _fired: bool = false


func _ready() -> void:
	_build()


func _build() -> void:
	var scary := ScaryObject.new()
	scary.scare_intensity = GAZE_INTENSITY
	add_child(scary)

	_body = StaticBody3D.new()
	scary.add_child(_body)
	_body.global_transform = global_transform

	var fig := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = SIZE
	fig.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Y-billboard: it always faces the player, but stays planted upright — a figure
	# that turns to track you without ever moving its feet.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	if ResourceLoader.exists(TEX_PATH):
		var tex := load(TEX_PATH)
		mat.albedo_texture = tex
		# A little self-illumination so it reads in a dark corner without a lamp.
		mat.emission_enabled = true
		mat.emission_texture = tex
		mat.emission_energy_multiplier = 0.25
	else:
		mat.albedo_color = Color(0.3, 0.3, 0.32)
	fig.set_surface_override_material(0, mat)
	fig.position = Vector3(0, SIZE.y / 2.0, 0)
	_body.add_child(fig)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE.x, SIZE.y, 0.3)
	col.shape = shape
	col.position = Vector3(0, SIZE.y / 2.0, 0)
	_body.add_child(col)


func _process(_delta: float) -> void:
	if _fired:
		return
	if not _player or not is_instance_valid(_player):
		_player = get_node_or_null("../Player") as CharacterBody3D
		if not _player:
			return
	if _player.global_position.distance_to(global_position) < KILL_DIST:
		_fired = true
		Screamer.trigger()
