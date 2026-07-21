extends SceneTree

# Dev tool: dump every Node3D the House builds near the living-room window, so a
# missing / mispositioned window can be diagnosed without guessing from screenshots.
# Usage: Godot --headless --path game --script res://tests/check_window.gd

const TARGET := Vector3(-5.0, 1.6, 8.75)
const RADIUS := 2.0

var _frame := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_2_1.tscn")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 20:
		return false
	print("WINDOW-PROBE target=%s radius=%.1f" % [TARGET, RADIUS])
	_walk(current_scene, 0)
	return true


func _walk(node: Node, depth: int) -> void:
	if node is Node3D:
		var n3: Node3D = node
		if n3.global_position.distance_to(TARGET) <= RADIUS:
			var extra := ""
			if n3 is MeshInstance3D:
				var mi: MeshInstance3D = n3
				var m: Material = mi.get_surface_override_material(0)
				extra = "  mesh=%s aabb=%s visible=%s mat=%s" % [
					mi.mesh.get_class() if mi.mesh else "-",
					mi.get_aabb().size, mi.is_visible_in_tree(),
					m.get_class() if m else "-"]
			print("  %s (%s) pos=%s rotY=%.2f%s" % [
				n3.name, n3.get_class(), n3.global_position, n3.rotation.y, extra])
	for c in node.get_children():
		_walk(c, depth + 1)
