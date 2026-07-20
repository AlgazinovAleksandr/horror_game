extends Node3D
class_name GlitchWall

# A wall running the screen-space vertex-jitter shader — the Backrooms' one real
# verb. Walking INTO it is how you leave a zone; there is never a door.
#
# Extracted from backrooms.gd when zones 2 and 3 started needing several of these
# at once, most of them lies. A wall knows whether it is real and reports contact;
# the zone that owns it decides what that means.

signal touched(is_real: bool)

const SHADER_PATH := "res://assets/materials/backrooms/glitch_wall.gdshader"
const TEX_DIR := "res://assets/textures/level_backrooms/"

var is_real: bool = true
var _mesh: MeshInstance3D
var _area: Area3D
var _solid: bool = false
var _shader_mat: ShaderMaterial
var _trigger_size: Vector3 = Vector3.ONE


func setup(size: Vector2, height: float, real: bool = true,
		base_tex_path: String = "") -> void:
	is_real = real

	_mesh = MeshInstance3D.new()
	_mesh.name = "GlitchSurface"
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.subdivide_width = 48
	mesh.subdivide_depth = 48
	mesh.orientation = PlaneMesh.FACE_Z
	_mesh.mesh = mesh

	var tex_path := base_tex_path if base_tex_path != "" \
		else TEX_DIR + "backrooms_wallpaper_albedo.png"
	if ResourceLoader.exists(SHADER_PATH):
		_shader_mat = ShaderMaterial.new()
		_shader_mat.shader = load(SHADER_PATH)
		if ResourceLoader.exists(tex_path):
			_shader_mat.set_shader_parameter("base_tex", load(tex_path))
		_mesh.material_override = _shader_mat
	else:
		_mesh.material_override = MazeKit.wall_material()
	add_child(_mesh)

	# Walk-into trigger sitting just in front of the surface.
	_area = Area3D.new()
	_area.name = "GlitchTrigger"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	_trigger_size = Vector3(size.x, height, 1.2)
	shape.size = _trigger_size
	col.shape = shape
	_area.add_child(col)
	_area.position = Vector3(0, 0, -0.9)
	_area.body_entered.connect(_on_body)
	add_child(_area)


func _on_body(body: Node3D) -> void:
	if _solid or not body.is_in_group("player"):
		return
	touched.emit(is_real)


func is_solid() -> bool:
	return _solid


# A fake that has been found out: the tearing stops and it becomes ordinary wall,
# so the player is never asked the same dead question twice.
func go_solid() -> void:
	if _solid:
		return
	_solid = true
	visible = true          # an outed wall is ordinary wall, and must be seen as such
	_mesh.material_override = MazeKit.wall_material()
	if is_instance_valid(_area):
		_area.queue_free()


# Tear a solidified wall back open. Only used to rescue zone 2 if the player has
# outed every wall — a maze with no exit left is worse than a maze that cheats.
func revive() -> void:
	if not _solid:
		return
	_solid = false
	if _shader_mat:
		_mesh.material_override = _shader_mat
	_area = Area3D.new()
	_area.name = "GlitchTrigger"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = _trigger_size
	col.shape = shape
	_area.add_child(col)
	_area.position = Vector3(0, 0, -0.9)
	_area.body_entered.connect(_on_body)
	add_child(_area)


# Zone 3 drives this per-frame from the flashlight state: the seam is only
# legible in the dark, which is exactly where the panic lives.
#
# Hides the whole node, not just the mesh — Node3D visibility is inherited, so the
# surface goes with it, while the Area3D trigger keeps monitoring (physics is
# independent of visibility). A seam you can't see is still a seam you can walk
# through once you've found it.
func set_seam_visible(v: bool) -> void:
	if _solid:
		return
	visible = v


func set_tear_amount(amount: float) -> void:
	if _shader_mat:
		_shader_mat.set_shader_parameter("tear_amount", amount)
