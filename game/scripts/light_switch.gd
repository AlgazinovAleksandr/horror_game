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

const TEX := "res://assets/textures/intro/"
const PLATE_SIZE := Vector2(0.32, 0.48)

var _used: bool = false
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
	face.position = Vector3(0, 0, 0.022)
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
	_used = true
	var t := create_tween()
	t.tween_property(_face_mat, "emission_energy_multiplier", 2.2, 0.1)
	t.tween_property(_face_mat, "emission_energy_multiplier", 0.9, 0.2)
	flipped.emit()
