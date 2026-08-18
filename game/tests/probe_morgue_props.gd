extends SceneTree

# DIAGNOSTIC PRINTER, not a guard — renamed from `check_morgue_props.gd` and REMOVED from
# `tools/run_tests.sh` on 2026-08-17 (workstream H2).
#
# It dumps the morgue trigger props and the exit door, with their meshes, materials and
# textures, so "the face isn't showing" / "the door art is cropped" can be diagnosed from
# facts rather than from screenshots. It asserts NOTHING and never calls `quit()`, so it
# exited 0 whatever it found — while the runner listed it as "morgue trigger objects are not
# buried", a claim it could not make. The claim itself is covered, by things that do assert:
#
#   * `check_reachable.gd`      — both morgue triggers are among the Lab's 22 REACHABLE
#                                 interactables, found by flood fill + the shipping interact ray
#   * `check_wall_overlap.gd`   — their quads are not coincident with the wall
#   * `check_prop_mounting.gd`  — and not floating off it
#
# Usage: Godot --headless --path game --script res://tests/probe_morgue_props.gd

var _frame := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_1.tscn")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 20:
		return false
	print("PROBE begin")
	for child in current_scene.get_children():
		var is_trigger := child is StaticBody3D and child.get_script() != null
		if not is_trigger:
			continue
		var n3: Node3D = child
		if n3.global_position.distance_to(Vector3(9.5, 1.0, 13.5)) > 4.0 \
				and n3.name != "ExitDoor":
			continue
		print("NODE %s at %s rot=%s" % [n3.name, n3.global_position, n3.rotation])
		for sub in n3.get_children():
			if not (sub is MeshInstance3D):
				continue
			var mi: MeshInstance3D = sub
			var mat: Material = mi.get_surface_override_material(0)
			var tex := "-"
			var emis := "-"
			if mat is StandardMaterial3D:
				var sm: StandardMaterial3D = mat
				tex = sm.albedo_texture.resource_path if sm.albedo_texture else "-"
				emis = "%.2f uv1=%s" % [sm.emission_energy_multiplier, sm.uv1_scale]
			var msize := "-"
			if mi.mesh is QuadMesh:
				msize = str((mi.mesh as QuadMesh).size)
			elif mi.mesh is BoxMesh:
				msize = str((mi.mesh as BoxMesh).size)
			print("   %s %s size=%s localpos=%s rot=%s vis=%s\n      tex=%s emis=%s" % [
				mi.name, mi.mesh.get_class(), msize, mi.position, mi.rotation,
				mi.is_visible_in_tree(), tex, emis])
	return true
