extends StaticBody3D
class_name LightSwitch

# A wall-mounted light switch for the Intro Room. interact() flips it once and
# emits `flipped` — the level owns the actual reveal sequence (audio, path-glow
# fade-out, ceiling lights, ambient tween), matching the project's existing
# division of labor (props emit, the owning level scene reacts). Self-building
# from primitives, same pattern as breaker.gd.
#
# Deliberately plays no audio itself, unlike breaker.gd's own interact() — the
# switch_clunk needs to land in step with intro_room.gd's broader reveal beat,
# not fire in isolation from the prop.

signal flipped
# Emitted for each press that does NOT throw it, carrying the 1-based press index. The
# level decides what a failed press looks like; see intro_room.gd:_on_switch_stuck().
signal stuck(press_index: int)

const TEX := "res://assets/textures/intro/"
# ⚠️ SIZED FROM `intro_switch.png` (1122x1402 = 0.8003), not chosen. It was 0.32 x 0.48
# (0.667), stretching the plate art 1.2x vertically. This prop is intro-only, so the
# change is contained; the collider is derived from the same constant.
const PLATE_SIZE := Vector2(0.32, 0.40)
# How far the art quad stands proud of the plate's own centre. ⚠️ Not a free number: the
# plate is mounted so its back face bites into the wall, and check_wall_overlap.gd requires
# every QuadMesh to clear every CSG box by 20 mm. See SWITCH_POS in intro_room.gd.
const FACE_OFFSET := 0.026

# How many presses it actually takes. Defaults to 1 so the prop behaves exactly as before
# unless a level asks for more — the Intro sets 2, because the switch sticking once is
# the only beat in the game that can frighten a player at zero mechanical cost: the room
# is revealed for a moment and then taken away again.
@export var presses_needed: int = 1

var _used: bool = false
var _presses: int = 0
var _face_mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build()


func _build() -> void:
	var backing := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(PLATE_SIZE.x, PLATE_SIZE.y, 0.04)
	backing.mesh = bm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.08, 0.08, 0.09)
	pm.metallic = 0.4
	pm.roughness = 0.7
	backing.set_surface_override_material(0, pm)
	add_child(backing)

	# Artwork on a QuadMesh/PlaneMesh, not the box face (CLAUDE.md rule — a
	# BoxMesh crops instead of fitting a whole texture per face). Bright
	# emission on purpose: this prop is the thing the player has to physically
	# find crossing a pitch-black room, not a background detail.
	var face := MeshInstance3D.new()
	face.name = "SwitchFace"
	var qm := PlaneMesh.new()
	qm.size = PLATE_SIZE
	face.mesh = qm
	face.rotation_degrees.x = 90.0  # right-side-up — see intro_room.gd's rotation fix
	face.position = Vector3(0, 0, FACE_OFFSET)
	_face_mat = StandardMaterial3D.new()
	var tex_path := TEX + "intro_switch.png"
	if ResourceLoader.exists(tex_path):
		var tex := load(tex_path)
		_face_mat.albedo_texture = tex
		_face_mat.emission_enabled = true
		_face_mat.emission_texture = tex
		_face_mat.emission_energy_multiplier = 0.9
	else:
		_face_mat.albedo_color = Color(0.9, 0.7, 0.4)
		_face_mat.emission_enabled = true
		_face_mat.emission = Color(0.9, 0.65, 0.3)
		_face_mat.emission_energy_multiplier = 0.5
	face.set_surface_override_material(0, _face_mat)
	add_child(face)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(PLATE_SIZE.x + 0.1, PLATE_SIZE.y + 0.1, 0.15)
	col.shape = shape
	add_child(col)


func interact() -> void:
	if _used:
		return
	_presses += 1

	# The plate blips on every press, successful or not. This is what stops a stuck press
	# reading as a broken game rather than as a stuck switch: the player gets unambiguous
	# feedback that the input registered, and only the LIGHTS fail to arrive.
	var t := create_tween()
	t.tween_property(_face_mat, "emission_energy_multiplier", 2.2, 0.1)
	t.tween_property(_face_mat, "emission_energy_multiplier", 0.9, 0.2)

	if _presses < presses_needed:
		stuck.emit(_presses)
		return
	_used = true
	flipped.emit()
