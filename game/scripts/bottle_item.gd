extends StaticBody3D
class_name BottleItem

# KONTUR Gate 2 — one bottle on the communal-kitchen shelf. Picking one up carries
# it; the fungal barrier asks what you are holding. Only "vinegar" works (the L2
# House TV card is the hint). Self-building: a glass body + a paper label quad.
#
# Layer 2 / mask 0 like note.gd, so the player can walk through the shelf line
# rather than bumping into it — the interaction ray still hits it.

signal taken(kind: String)

const INTERACTABLE_LAYER := 2
const BODY_H := 0.26
const BODY_R := 0.045

@export var kind: String = "vinegar"
@export var label_path: String = ""

var _taken: bool = false


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	_build()


func _build() -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.42, 0.46, 0.38, 1.0)
	glass.roughness = 0.25
	glass.metallic = 0.15

	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = BODY_R * 0.55
	cyl.bottom_radius = BODY_R
	cyl.height = BODY_H
	mesh.mesh = cyl
	mesh.material_override = glass
	mesh.position = Vector3(0, BODY_H / 2.0, 0)
	add_child(mesh)

	if label_path != "" and ResourceLoader.exists(label_path):
		var lab := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(BODY_R * 2.0, BODY_H * 0.45)
		lab.mesh = quad
		var lmat := StandardMaterial3D.new()
		lmat.albedo_texture = load(label_path)
		lmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Lift the label off the glass so it never z-fights with the cylinder.
		lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lab.material_override = lmat
		lab.position = Vector3(0, BODY_H * 0.5, BODY_R + 0.004)
		add_child(lab)

	# A generous collider — the bottle mesh is small and the interaction ray is
	# unforgiving on thin geometry (Issue 2).
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.22, 0.36, 0.22)
	col.shape = shape
	col.position = Vector3(0, BODY_H / 2.0, 0)
	add_child(col)


func interact() -> void:
	if _taken:
		return
	_taken = true
	taken.emit(kind)
	queue_free()
