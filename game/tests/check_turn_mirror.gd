extends SceneTree

# The Corridor's turn mirrors: are they mirrors, and is the figure only in the glass?
#
#   Godot --headless --path game --script res://tests/check_turn_mirror.gd
#
# User report, 2026-08-15: "the mirror in the corridor level does not really look like a
# mirror." It wasn't one. There is no ReflectionProbe, no SSR and no SubViewport anywhere
# in this project — the turn mirrors were `mirror_with_creature.png` on a flat quad at
# roughness 0.9, and `living_mirror.gd`'s metallic 0.9 sampled an environment that does
# not exist. See mirror_surface.gd.
#
# ⚠️ A reflection cannot be ASSERTED — whether it looks right is a job for
# `screenshot_corridor.gd` and an eyeball. What can be asserted is the wiring, and the
# wiring is where this effect fails silently:
#
#   * a SubViewport that renders on a world it does not share shows black
#   * a reflection camera that drops the mirror-only layer shows an empty corridor, which
#     looks exactly like a working mirror and quietly deletes the entire scare
#   * a PLAYER camera that KEEPS that layer shows the figure standing in the corridor,
#     which deletes the scare the other way round and is much worse: the player sees a
#     creature that has no rules and cannot be interacted with
#   * a viewport left at UPDATE_ALWAYS renders three extra scene passes for a 320 m walk
#
# None of those would fail a smoke test, and two of them look plausible on a screenshot.

var _t := 0.0
var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/corridor.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print("  %s  %s%s" % ["OK  " if cond else "FAIL", label, ("  " + detail) if detail else ""])
	if not cond:
		_fails.append(label)


func _process(delta: float) -> bool:
	_t += delta
	if _t < 1.0:
		return false
	var scene := current_scene
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	_ok("the player exists", player != null)
	if player == null:
		return _report()

	var mirrors: Array = []
	var watchers: Array = []
	_collect(scene, mirrors, watchers)

	# corridor.gd builds three turn mirrors, at 90 / 230 / 275 m.
	_ok("every turn mirror is a real mirror", mirrors.size() == 3, "%d found" % mirrors.size())
	if mirrors.is_empty():
		return _report()

	var layer_bit: int = 1 << (int(mirrors[0].get_script().get("MIRROR_ONLY_LAYER")) - 1)

	for m in mirrors:
		var vp: SubViewport = m.get_node_or_null("SubViewport")
		if vp == null:
			_ok("a mirror has a SubViewport", false)
			continue
		# Sharing the world is what makes it render the corridor rather than a void.
		_ok("the mirror renders THIS world", vp.world_3d == scene.get_viewport().world_3d)
		_ok("it is idle until you approach",
			vp.render_target_update_mode == SubViewport.UPDATE_DISABLED,
			"mode %d" % vp.render_target_update_mode)
		var cam: Camera3D = vp.get_node_or_null("Camera3D")
		_ok("it has a reflection camera", cam != null)
		if cam != null:
			_ok("the reflection camera KEEPS the mirror-only layer",
				(cam.cull_mask & layer_bit) != 0)
		var quad: MeshInstance3D = m.get_parent() as MeshInstance3D
		_ok("the glass shows the viewport", quad != null
			and quad.get_surface_override_material(0) != null
			and quad.get_surface_override_material(0).albedo_texture is ViewportTexture)

	# ⚠️ The other half of the contract, and the one that fails open.
	_ok("the PLAYER camera drops the mirror-only layer",
		(player.get_node("Camera3D").cull_mask & layer_bit) == 0,
		"cull_mask %d" % player.get_node("Camera3D").cull_mask)

	# The figure: one per mirror, and every mesh of it on the mirror-only layer.
	_ok("there is a figure for each mirror", watchers.size() == mirrors.size(),
		"%d figures / %d mirrors" % [watchers.size(), mirrors.size()])
	var meshes := 0
	var wrong := 0
	for w in watchers:
		for vi in _visuals(w, []):
			meshes += 1
			if vi.layers != layer_bit:
				wrong += 1
	_ok("the figures have meshes at all", meshes > 0, "%d visuals" % meshes)
	_ok("every one renders ONLY into mirrors", wrong == 0, "%d on the wrong layer" % wrong)

	# It must be harmless: watcher.gd has no ScaryObject, no collider and no kill radius,
	# and this placement must not accidentally give it one.
	var armed := 0
	for w in watchers:
		if _has_collider(w):
			armed += 1
	_ok("and none of them can touch you", armed == 0, "%d with colliders" % armed)

	return _report()


func _collect(n: Node, mirrors: Array, watchers: Array) -> void:
	# ⚠️ By NAME and shape, not by `get("MIRROR_ONLY_LAYER")` — `get()` reads properties,
	# and a GDScript `const` is not one, so that predicate silently matched nothing and the
	# first run of this test reported "0 found" against three working mirrors.
	if String(n.name) == "MirrorSurface" and n.has_node("SubViewport"):
		mirrors.append(n)
	elif String(n.name).begins_with("MirrorFigure"):
		watchers.append(n)
	for c in n.get_children():
		_collect(c, mirrors, watchers)


func _visuals(n: Node, acc: Array) -> Array:
	if n is VisualInstance3D:
		acc.append(n)
	for c in n.get_children():
		_visuals(c, acc)
	return acc


func _has_collider(n: Node) -> bool:
	if n is CollisionShape3D:
		return true
	for c in n.get_children():
		if _has_collider(c):
			return true
	return false


func _report() -> bool:
	print("  %d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL — ", ", ".join(_fails))
		quit(1)
	return true
