extends SceneTree

# KEPT, because it documents something durable — ISSUES_SOLUTIONS Issue 91.
#
#   Godot --headless --path game --script res://tests/probe_csg_shapequery.gd
#
# A `CSGBox3D` created and added to the tree AFTER a level has built generates a collider that
# answers `intersect_ray` and is INVISIBLE to `intersect_shape`. A `StaticBody3D` with a
# `BoxShape3D` of the same size, added in the same frame, answers both. Expected output:
#
#   CSG         ray=ProbeCSG   shape_hits=[]
#   StaticBody  ray=ProbeSB    shape_hits=[ProbeSB]
#
# It is not an ordering problem: `use_collision` before or after `add_child`, `size` before or
# after, and 2.5 s of settling all behave identically. The levels' own `_ready()`-time CSG
# boxes are unaffected — `ArrowColE`, `EntryWallR` and `CellarRamp` all block capsule queries
# normally — which is exactly what makes this easy to trust and expensive to discover.
#
# ⚠️ WHY IT MATTERS: it made TWO test controls half-vacuous on the day they were written
# (`check_reachable.gd` and `check_sprawl_alcoves.gd` both seal a doorway to prove they can
# fail). Build a control out of the simplest primitive that exists, and assert its halves
# separately, or the half that works hides the half that does not.
var _t := 0.0
var _stage := 0
var _csg: CSGBox3D
var _sb: StaticBody3D

func _initialize() -> void:
	change_scene_to_file("res://scenes/backrooms.tscn")

func _process(d: float) -> bool:
	_t += d
	match _stage:
		0:
			if _t < 1.5: return false
			_csg = CSGBox3D.new()
			_csg.name = "ProbeCSG"
			current_scene.add_child(_csg)
			_csg.size = Vector3(4.0, 4.5, 0.3)
			_csg.use_collision = true          # AFTER entering the tree
			_csg.global_position = Vector3(189, 2.25, 20)
			_sb = StaticBody3D.new()
			_sb.name = "ProbeSB"
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(4.0, 4.5, 0.3)
			cs.shape = bs
			_sb.add_child(cs)
			current_scene.add_child(_sb)
			_sb.global_position = Vector3(189, 2.25, 14)
			_stage = 1
			_t = 0.0
		1:
			if _t < 2.5: return false
			var space := current_scene.get_viewport().find_world_3d().direct_space_state
			for spec in [["CSG", Vector3(189, 0.97, 20)], ["StaticBody", Vector3(189, 0.97, 14)]]:
				var p: Vector3 = spec[1]
				var rq := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0, -3), p + Vector3(0, 0, 3))
				rq.collision_mask = 1
				var rh := space.intersect_ray(rq)
				var shape := CapsuleShape3D.new()
				shape.radius = 0.4
				shape.height = 1.8
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = shape
				q.collision_mask = 1
				q.transform = Transform3D(Basis(), p)
				var sh := space.intersect_shape(q, 4)
				var names: Array = []
				for r in sh:
					names.append((r["collider"] as Node).name)
				print("  %-11s ray=%s   shape_hits=%s" % [spec[0],
					("none" if rh.is_empty() else String((rh["collider"] as Node).name)), str(names)])
			quit(0)
			return true
	return false
