extends SceneTree

# THROWAWAY PROBE (backlog 04, OQ3). Measures every `Watcher` and every `LivingMirror` in a
# scene and prints their exact rendered parameters, so the "before" and "after" of the two
# SHARED-FILE changes in this pass can be diffed line by line:
#
#   * watcher.gd    gained `figure_tint`, which must default to white
#   * living_mirror.gd  sizes its two quads from their own artwork
#
# Usage: ... --script res://tests/probe_shared_props.gd -- <scene>
#
# It asserts nothing on purpose — it is a measurement, and the comparison is the deliverable.

var _scene := "res://scenes/corridor.tscn"
var _t := 0.0
var _done := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_scene = args[0]
	change_scene_to_file(_scene)


func _walk(n: Node, acc: Array[Node]) -> Array[Node]:
	acc.append(n)
	for c in n.get_children():
		_walk(c, acc)
	return acc


func _gname(n: Node) -> String:
	var s: Script = n.get_script()
	return String(s.get_global_name()) if s else ""


func _process(delta: float) -> bool:
	_t += delta
	if _done:
		return true
	if _t < 2.0:
		return false
	_done = true

	print("PROBE scene=%s" % _scene)
	var watchers := 0
	var mirrors := 0
	for n in _walk(current_scene, [] as Array[Node]):
		var g := _gname(n)
		if g == "Watcher":
			watchers += 1
			for c in n.get_children():
				if c is MeshInstance3D:
					var mi: MeshInstance3D = c
					var m := mi.get_surface_override_material(0) as StandardMaterial3D
					var sz: Vector2 = (mi.mesh as QuadMesh).size if mi.mesh is QuadMesh \
						else Vector2.ZERO
					print("  WATCHER %s  quad=%.4fx%.4f  albedo=%s  emission=%s  tex=%s"
						% [n.name, sz.x, sz.y,
							str(m.albedo_color) if m else "(none)",
							str(m.emission_enabled) if m else "?",
							m.albedo_texture.resource_path.get_file() if m and m.albedo_texture
								else "(none)"])
		elif g == "LivingMirror":
			mirrors += 1
			for c in _walk(n, [] as Array[Node]):
				if c is MeshInstance3D:
					var mi2: MeshInstance3D = c
					var sz2: Vector2 = (mi2.mesh as QuadMesh).size if mi2.mesh is QuadMesh \
						else Vector2.ZERO
					print("  MIRRORQUAD %s.%s  quad=%.4fx%.4f  at %v"
						% [n.name, mi2.name, sz2.x, sz2.y, mi2.global_position.snapped(
							Vector3(0.001, 0.001, 0.001))])
				elif c is CollisionShape3D:
					var sh := (c as CollisionShape3D).shape as BoxShape3D
					if sh:
						print("  MIRRORCOL  %s  box=%v" % [n.name, sh.size])
	print("PROBE watchers=%d mirrors=%d" % [watchers, mirrors])
	quit(0)
	return true
