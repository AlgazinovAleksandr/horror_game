extends StaticBody3D

@export var note_text: String = ""
@export var is_trap: bool = false
@export var is_twist_note: bool = false


func _ready() -> void:
	_style_mesh()
	_enlarge_collision()


func _style_mesh() -> void:
	var paper_tex: Texture2D = load("res://assets/textures/note_paper.png") \
		if ResourceLoader.exists("res://assets/textures/note_paper.png") else null
	for child in get_children():
		if not child is MeshInstance3D:
			continue
		var mat := StandardMaterial3D.new()
		if is_trap:
			# Trap notes: red tint over paper
			if paper_tex:
				mat.albedo_texture = paper_tex
			mat.albedo_color = Color(0.9, 0.55, 0.55, 1.0)
			mat.emission_enabled = true
			mat.emission = Color(0.4, 0.05, 0.05)
			mat.emission_energy_multiplier = 0.5
		else:
			# Safe notes: warm paper tint with glow so they're visible in dark
			if paper_tex:
				mat.albedo_texture = paper_tex
			mat.albedo_color = Color(0.92, 0.88, 0.80, 1.0)
			mat.emission_enabled = true
			mat.emission = Color(0.55, 0.50, 0.35)
			mat.emission_energy_multiplier = 0.6
		child.set_surface_override_material(0, mat)


func _enlarge_collision() -> void:
	# Notes stand upright (rotated -90° X in scene). Local Z maps to world Y.
	# size.z=0.8 gives 0.4m half-height; center at y=1.2 spans y=0.8–1.6.
	for child in get_children():
		if child is CollisionShape3D:
			var box := BoxShape3D.new()
			box.size = Vector3(0.35, 0.35, 0.8)
			child.shape = box


func interact() -> void:
	if is_trap:
		Screamer.trigger()
		return

	if is_twist_note:
		GameState.twist_read = true

	NoteUI.show_note(note_text)
