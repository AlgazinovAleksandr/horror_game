extends StaticBody3D
class_name FungalBarrier

# KONTUR Gate 2 — the O-41 mass sealing a doorway. interact() reports whatever the
# player is carrying; kontur.gd decides. On success, call dissolve() to shrink the
# mass away and drop the collider. On failure the level fires the scare and the
# bottle is consumed, so the player walks back for another.

signal sprayed

const DISSOLVE_TIME := 1.6

var _open: bool = false
var _mesh: MeshInstance3D
var _col: CollisionShape3D


func setup(size: Vector3, texture_path: String) -> void:
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	if texture_path != "" and ResourceLoader.exists(texture_path):
		mat.albedo_texture = load(texture_path)
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(0.5, -0.5, 0.5)
	else:
		mat.albedo_color = Color(0.42, 0.41, 0.36)
	_mesh.material_override = mat
	add_child(_mesh)

	_col = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	_col.shape = shape
	add_child(_col)


func interact() -> void:
	if _open:
		return
	sprayed.emit()


func dissolve() -> void:
	if _open:
		return
	_open = true
	# Drop the collider immediately so the player is never trapped by a mass that
	# is visually gone but still solid mid-tween.
	_col.set_deferred("disabled", true)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_mesh, "scale", Vector3(1.0, 0.02, 1.0), DISSOLVE_TIME)
	tw.parallel().tween_property(_mesh, "position:y", -0.4, DISSOLVE_TIME)
	tw.tween_callback(queue_free)
