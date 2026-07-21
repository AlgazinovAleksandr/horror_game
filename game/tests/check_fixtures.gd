extends SceneTree

# Dev tool: report the visible ceiling-fixture meshes a level builds, so a blown-out
# or mis-sized fitting can be diagnosed without eyeballing screenshots.
# Usage: Godot --path game --script res://tests/check_fixtures.gd -- <scene>

var _scene := "res://scenes/level_1.tscn"
var _frame := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_scene = args[0]
	change_scene_to_file(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 20:
		return false
	for child in current_scene.get_children():
		if child is OmniLight3D:
			print("LAMP %s  pos=%s  energy=%.3f" % [child.name, child.global_position, child.light_energy])
			for sub in child.get_children():
				if sub is MeshInstance3D:
					var aabb: AABB = sub.get_aabb()
					var mat: Material = sub.get_surface_override_material(0)
					var emis := "-"
					if mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled:
						emis = "%.2f" % (mat as StandardMaterial3D).emission_energy_multiplier
					print("    %s  mesh=%s  local_aabb_size=%s  global_y=%.2f  scale=%s  emission=%s" % [
						sub.name, sub.mesh.get_class(), aabb.size, sub.global_position.y,
						sub.global_transform.basis.get_scale(), emis])
	return true
