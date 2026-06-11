extends StaticBody3D

const INTERACTABLE_LAYER := 2  # pass-through for player; raycast still hits this layer

@export var note_text: String = ""
@export var is_trap: bool = false
@export var is_twist_note: bool = false


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	# _style_mesh()
	# _enlarge_collision()


# func _style_mesh() -> void:
# 	for child in get_children():
# 		if not child is MeshInstance3D:
# 			continue
# 		var mat := StandardMaterial3D.new()
# 		if is_trap:
# 			# Trap notes: faint red tint
# 			mat.albedo_color = Color(0.55, 0.15, 0.15, 1.0)
# 			mat.emission_enabled = true
# 			mat.emission = Color(0.4, 0.05, 0.05)
# 			mat.emission_energy_multiplier = 0.5
# 		else:
# 			# Safe notes: near-black with warm paper glow so they're visible in dark
# 			mat.albedo_color = Color(0.05, 0.05, 0.04, 1.0)
# 			mat.emission_enabled = true
# 			mat.emission = Color(0.55, 0.50, 0.35)
# 			mat.emission_energy_multiplier = 0.6
# 		child.set_surface_override_material(0, mat)


# func _enlarge_collision() -> void:
# 	# Notes stand upright (rotated -90° X in scene). Local Z maps to world Y.
# 	# size.z=0.8 gives 0.4m half-height; center at y=1.2 spans y=0.8–1.6.
# 	for child in get_children():
# 		if child is CollisionShape3D:
# 			var box := BoxShape3D.new()
# 			box.size = Vector3(0.35, 0.35, 0.8)
# 			child.shape = box


func interact() -> void:
	if is_trap:
		Screamer.trigger()
		return

	if is_twist_note:
		GameState.twist_read = true

	NoteUI.show_note(note_text)
