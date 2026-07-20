extends SceneTree

# Can the Flood's real seam actually be TOUCHED?
#
# walk_backrooms.gd drives `cleared.emit()` and `_on_seam_touched()` directly, so it
# proves the wiring and nothing about geometry. This puts a body where the player can
# stand and asks the physics server whether the trigger is there.

var _frame := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/backrooms.tscn")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 10:
		return false

	var z3 = current_scene.get_node_or_null("ZoneFlood")
	var builder = z3.get_node("RoomBuilder") if z3.has_node("RoomBuilder") else null
	for c in z3.get_children():
		if c is RoomBuilder:
			builder = c

	for seam in z3.get_children():
		if not (seam is GlitchWall):
			continue
		var area: Area3D = seam.get_node_or_null("GlitchTrigger")
		if not area:
			print("  %s: NO TRIGGER" % seam.name)
			continue
		var ap: Vector3 = area.global_position
		var sp: Vector3 = seam.global_position
		# Which side of the seam plane did the trigger land on?
		var toward: Vector3 = (ap - sp)
		print("  %-14s seam %v  trigger %v  offset %v  real=%s"
			% [seam.name, sp.snappedf(0.01), ap.snappedf(0.01),
				toward.snappedf(0.01), seam.is_real])

		# Is there solid geometry between the room and the trigger?
		var space: PhysicsDirectSpaceState3D = current_scene.get_world_3d().direct_space_state
		# Approach the trigger from further out on the trigger's OWN side — that is
		# where the player walks in from. Casting from the seam's far side just hits
		# the wall the seam is mounted on and reports a false block.
		var from: Vector3 = ap + toward.normalized() * 2.0
		from.y = sp.y
		var q := PhysicsRayQueryParameters3D.create(from, ap)
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			print("      -> trigger is reachable from the room side")
		else:
			print("      -> BLOCKED by %s at %v (trigger is behind a wall)"
				% [hit.collider.name, (hit.position as Vector3).snappedf(0.01)])

	quit(0)
	return true
