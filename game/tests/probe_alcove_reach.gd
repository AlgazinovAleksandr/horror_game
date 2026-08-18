extends SceneTree

# KEPT: the minimal reproduction that found the sealed alcoves (ISSUES_SOLUTIONS Issue 90).
#
#   Godot --headless --path game --script res://tests/probe_alcove_reach.gd
#
# Before 2026-08-17 this printed BLOCKED at exactly 3.00 m — the mouth plane — on all eight.
# It now prints CLEAR on all eight. The assertion lives in `tests/check_sprawl_alcoves.gd`;
# this stays because eight identical numbers are the shortest statement of what was wrong.
var _t := 0.0
var _done := false
func _initialize() -> void:
	change_scene_to_file("res://scenes/backrooms.tscn")
func _process(d: float) -> bool:
	_t += d
	if _done: return true
	if _t < 1.5: return false
	_done = true
	var z2 := current_scene.get_node_or_null("ZoneSprawl")
	var c: Dictionary = (load("res://scripts/backrooms_zone2.gd") as GDScript).get_script_constant_map()
	var half: float = c["HALF"]; var ad: float = c["ALCOVE_D"]
	var sa: Dictionary = c["SIDE_AXIS"]
	var org: Vector3 = z2.global_position
	var space := current_scene.get_viewport().world_3d.direct_space_state
	for s in c["SIDES"]:
		var axis: Vector3 = sa[s]
		for k in [-1, 1]:
			var centre: Vector3 = axis * (half + ad / 2.0) + Vector3(axis.z, 0, axis.x) * (k * 11.0)
			var inside: Vector3 = org + centre - axis * (ad / 2.0 + 3.0) + Vector3(0, 1.5, 0)
			var target: Vector3 = org + centre + Vector3(0, 1.5, 0)
			var q := PhysicsRayQueryParameters3D.create(inside, target)
			q.collision_mask = 1
			var hit := space.intersect_ray(q)
			var what := "CLEAR"
			if not hit.is_empty():
				what = "BLOCKED by %s at %.2f m" % [(hit["collider"] as Node).name,
					inside.distance_to(hit["position"])]
			print("  Alc%s%+d  hall->alcove : %s" % [s, k, what])
	quit(0)
	return true
