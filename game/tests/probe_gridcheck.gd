extends "res://tests/check_wall_overlap.gd"

# THROWAWAY PROBE (backlog 04, OQ3): check_wall_overlap with the EXTRA SAMPLING MODE on, for
# a scene that does not normally use it. Written to answer one question that no existing guard
# can: the Lab's and the House's LivingMirror glass grew from 1.2 m wide to 1.8 m, and the
# centre-point test is structurally blind to a prop whose EDGES have moved into a wall.
#
#   ... --script res://tests/probe_gridcheck.gd -- res://scenes/level_1.tscn

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_scene = args[0]
	_quad_grid = 7
	change_scene_to_file(_scene)
