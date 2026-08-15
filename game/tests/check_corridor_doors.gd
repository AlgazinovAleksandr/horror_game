extends SceneTree

# The Corridor's new beats: doors that open behind you, the false-ceiling telegraphs, and
# the one corner that no longer flashes.
#
# The load-bearing assertion is the FIRST one. The six decor doors used to be flat quads
# with no depth and no collider; they are real hinged bodies now, in a hall that is 3.0 m
# wide, and a panel swung too far would narrow the only route through the level. That is a
# soft-lock in a game with no checkpoints, so it is measured geometrically rather than
# trusted to a constant.
#
# Also asserted, because each is a way the beats could silently die:
#   * a door must NOT open while it is being looked at (an anomaly, not a visible effect)
#   * it must open once the player is well past it and facing elsewhere
#   * a non-payoff telegraph costs NOTHING — that is the whole anti-habituation trick
#   * exactly one of the three turn mirrors is silent this run
#
#   Godot --headless --path game --script res://tests/check_corridor_doors.gd

const MIN_FREE_WIDTH := 1.2      # a player capsule is ~0.8 m across; 1.2 is comfortable
const CORRIDOR_W := 3.0

var _t := 0.0
var _stage := 0
var _fails: Array[String] = []
var _checks := 0
var _scene: Node = null
var _player: CharacterBody3D = null
var _doors: Array = []


func _initialize() -> void:
	change_scene_to_file("res://scenes/corridor.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _process(delta: float) -> bool:
	_t += delta

	if _stage == 0 and _t > 1.0:
		_scene = current_scene
		_player = _scene.get_node_or_null("Player") as CharacterBody3D
		_doors = _scene.get("_ajar_doors")
		_ok("player found", _player != null)
		_ok("all six decor doors are real AjarDoors", _doors != null and _doors.size() == 6,
			"found %d" % (_doors.size() if _doors else -1))
		if not (_player and _doors and _doors.size() == 6):
			quit(1)
			return true

		# --- the soft-lock check ------------------------------------------------------
		# Swing every door to the maximum angle the level will ever use, then measure how
		# much of the 3 m hall is left at each one.
		var worst := 99.0
		var worst_name := ""
		var max_deg: float = float(_scene.get("DOOR_AJAR_MAX"))
		for d in _doors:
			var node: Node3D = d.node
			var pt: Dictionary = _scene.call("_path_point", float(d.dist))
			var side: Vector3 = pt.side
			# ⚠️ rotation set DIRECTLY, not via swing_ajar(). The first version of this test
			# called swing_ajar(max, 0.001) and measured in the SAME frame — but a Tween does
			# not run until the next frame, so it measured the un-swung doors and reported a
			# comfortable 2.81 m of clearance for a panel that had not moved at all. The
			# assertion was vacuous and passed. Geometry is what matters here, so set the
			# angle and measure it.
			node.rotation.y -= deg_to_rad(max_deg)
			# Project the panel's corners onto the lateral axis and find the one that
			# reaches furthest across the hall from its own wall.
			var reach := 0.0
			for child in node.get_children():
				if not (child is MeshInstance3D):
					continue
				var aabb: AABB = (child as MeshInstance3D).get_aabb()
				for c in 8:
					var corner: Vector3 = node.global_transform * (child as Node3D).transform \
						* aabb.get_endpoint(c)
					# How far across the hall this corner reaches, measured from ITS OWN wall.
					var lateral: float = absf((corner - (pt.pos as Vector3)).dot(side))
					reach = maxf(reach, CORRIDOR_W / 2.0 - lateral)
			# `reach` is the intrusion from the wall; what is left is the rest of the hall.
			var free: float = CORRIDOR_W - reach
			if free < worst:
				worst = free
				worst_name = String(node.name)
		_ok("a fully-ajar door still leaves a walkable hall", worst >= MIN_FREE_WIDTH,
			"narrowest is %s at %.2f m of %.1f" % [worst_name, worst, CORRIDOR_W])

		# --- the telegraphs -----------------------------------------------------------
		var payoff: int = int(_scene.get("_telegraph_payoff"))
		var count: int = (_scene.get("TELEGRAPH_AT") as Array).size()
		# ⚠️ WAS `count == 5`. Cut to two on 2026-08-15 (user: "too many repeating sounds…
		# the trumpet musical instrument") — `telegraph_groan` is a 3.2 s brass fall and
		# five of them in 100 m read as a loop rather than as dread. The MECHANIC is what
		# this test protects, not the number: at least one telegraph that means nothing,
		# and exactly one that delivers. `check_corridor_repeats.gd` owns the upper bound.
		_ok("more than one telegraph, exactly one of which delivers",
			count >= 2 and payoff >= 0 and payoff < count,
			"payoff index %d of %d" % [payoff, count])
		# A non-payoff telegraph must be free. If it ever charged panic, the player could not
		# afford to learn to ignore it, and the mechanic would invert.
		# ⚠️ `% count`, not `% 5` — with two telegraphs a hardcoded 5 indexes past the array.
		var quiet: int = (payoff + 1) % count
		_player.set("_panic", 0.0)
		var before: float = _player.get_panic_ratio()
		_scene.call("_telegraph", quiet)
		_ok("a telegraph that means nothing costs nothing",
			is_equal_approx(_player.get_panic_ratio(), before),
			"panic %.4f -> %.4f" % [before, _player.get_panic_ratio()])

		# --- the mirrors --------------------------------------------------------------
		var mirrors: Array = _scene.get("_turn_mirrors")
		var silent := 0
		for m in mirrors:
			if not bool(m.get("flashes", true)):
				silent += 1
		_ok("three turn mirrors exist", mirrors.size() == 3, "found %d" % mirrors.size())
		_ok("exactly one of them is silent this run", silent == 1,
			"%d silent" % silent)

		# --- a door must not open while watched --------------------------------------
		# Reset the doors, stand the player well past one, and look straight at it.
		for d in _doors:
			d.opened = false
			(d.node as Node3D).rotation.y = 0.0
		var target: Dictionary = _doors[2]
		var tpt: Dictionary = _scene.call("_path_point", float(target.dist))
		_scene.set("_furthest_reached", float(target.dist) + 25.0)
		_player.global_position = (tpt.pos as Vector3) + Vector3(0, 0.1, 0)
		var cam := _player.get_node("Camera3D") as Camera3D
		cam.look_at((target.node as Node3D).global_position + Vector3(0, 1.0, 0), Vector3.UP)
		_stage = 1
		_t = 0.0

	elif _stage == 1 and _t > 0.6:
		var target: Dictionary = _doors[2]
		_ok("a door does NOT open while you are looking at it",
			not bool(target.opened))

		# Now look away. It should open, silently, on the next tick.
		var cam := _player.get_node("Camera3D") as Camera3D
		cam.rotation.y += PI
		_stage = 2
		_t = 0.0

	elif _stage == 2 and _t > 0.6:
		var target: Dictionary = _doors[2]
		_ok("and it DOES open once you are past it and facing away",
			bool(target.opened))
		_ok("opening it cost no panic", _player.get_panic_ratio() < 0.01,
			"panic %.4f" % _player.get_panic_ratio())

		print("")
		print("%d checks, %d failed" % [_checks, _fails.size()])
		if _fails.is_empty():
			print("RESULT: PASS")
			quit(0)
		else:
			for f in _fails:
				print("  FAIL: " + f)
			print("RESULT: FAIL")
			quit(1)
		return true

	if _t > 25.0:
		print("RESULT: FAIL — timed out at stage %d" % _stage)
		quit(1)
		return true
	return false
