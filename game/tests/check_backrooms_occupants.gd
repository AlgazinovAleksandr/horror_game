extends SceneTree

# The Sprawl's Congregation and the Flood's unseen wader.
#
# The most important assertions here are NEGATIVE ones, because both features are defined by
# what they do not do:
#
#   * **The Congregation has no rules.** No ScaryObject ancestor (so no gaze panic), no
#     collider, no kill radius. If any of that crept in it would become a second
#     observation-dependent creature, which SCARY.md §8.3 bans outright — and it would
#     destabilise the Sprawl's tuned 12-panic mistake cost.
#   * **A figure never relocates while it can be seen**, and never while it is close enough
#     to be studied. Either would turn an anomaly into a visible teleport.
#   * **The wader is never rendered.** No mesh, no collider, no ScaryObject: SCARY.md P10's
#     entire point is a threat that cannot be caught clipping through a wall.
#   * **The wader stops when the player stops** — after a couple of strides, not instantly.
#   * **Standing still in the Sprawl is free.** Its tell is a SOUND you have to stop and
#     localise, and `enable_standstill_panic()` is armed level-wide, so the zone used to tax
#     the exact posture its own puzzle demands (Issue 18).
#
#   Godot --headless --path game --script res://tests/check_backrooms_occupants.gd

const SPRAWL_ORIGIN := Vector3(200, 0, 0)
const FLOOD_ORIGIN := Vector3(-200, 0, 0)

var _t := 0.0
var _stage := 0
var _stage_at := 0.0
var _fails: Array[String] = []
var _checks := 0
var _scene: Node = null
var _player: CharacterBody3D = null
var _cong: Node = null
var _wader: Node = null
var _watched: Node3D = null
var _watched_pos := Vector3.ZERO


func _initialize() -> void:
	change_scene_to_file("res://scenes/backrooms.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _find(node: Node, cls: String) -> Node:
	if node.get_class() == cls or (node.get_script() and \
			String(node.get_script().get_global_name()) == cls):
		return node
	for c in node.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null


func _has_ancestor_scary(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if p.get_script() and String(p.get_script().get_global_name()) == "ScaryObject":
			return true
		p = p.get_parent()
	return false


func _advance(next: int) -> void:
	_stage = next
	_stage_at = _t


func _process(delta: float) -> bool:
	_t += delta

	if _stage == 0 and _t > 1.2:
		_scene = current_scene
		_player = _scene.get_node_or_null("Player") as CharacterBody3D
		_ok("player found", _player != null)
		if not _player:
			quit(1)
			return true
		# Both later zones are built at _ready(); jump straight into the Sprawl.
		_scene.call("_enter_zone", 2)
		_advance(1)

	elif _stage == 1 and _t - _stage_at > 0.6:
		_cong = _find(_scene, "Congregation")
		_ok("the Congregation exists in the Sprawl", _cong != null)
		if not _cong:
			_finish()
			return true
		var n: int = int(_cong.call("figure_count"))
		_ok("it starts with a field of figures", n >= 5, "%d figures" % n)

		# --- the negative assertions --------------------------------------------------
		var bad_scary := 0
		var bad_collider := 0
		for f in _cong.get_children():
			if not (f is Node3D):
				continue
			if _has_ancestor_scary(f):
				bad_scary += 1
			if _find(f, "CollisionShape3D") != null:
				bad_collider += 1
		_ok("no figure feeds gaze panic (no ScaryObject ancestor)", bad_scary == 0,
			"%d offenders" % bad_scary)
		_ok("no figure has a collider", bad_collider == 0, "%d offenders" % bad_collider)

		# Standing still in the Sprawl must be free.
		_ok("standstill panic is suspended in the Sprawl",
			bool(_player.get("_standstill_suspended")))

		# A mistake adds one more of them, at no panic.
		var before_n: int = int(_cong.call("figure_count"))
		var before_p: float = _player.get_panic_ratio()
		_cong.call("add_one")
		_ok("a mistake can add another figure",
			int(_cong.call("figure_count")) == before_n + 1,
			"%d -> %d" % [before_n, int(_cong.call("figure_count"))])
		_ok("and adding one costs no panic",
			is_equal_approx(_player.get_panic_ratio(), before_p))

		# --- it must not move while watched ------------------------------------------
		# Stand right next to a figure and look at it.
		for f in _cong.get_children():
			if f is Node3D:
				_watched = f
				break
		if _watched:
			_player.global_position = _watched.global_position + Vector3(0, 0.1, -3.0)
			var cam := _player.get_node("Camera3D") as Camera3D
			cam.look_at(_watched.global_position + Vector3(0, 1.2, 0), Vector3.UP)
			_watched_pos = _watched.global_position
		_advance(2)

	elif _stage == 2 and _t - _stage_at > 1.2:
		if _watched and is_instance_valid(_watched):
			_ok("a watched figure does not move",
				_watched.global_position.distance_to(_watched_pos) < 0.01)
			# Still close, but now looking away: the distance guard alone must hold it.
			var cam := _player.get_node("Camera3D") as Camera3D
			cam.rotation.y += PI
		_advance(3)

	elif _stage == 3 and _t - _stage_at > 1.2:
		if _watched and is_instance_valid(_watched):
			_ok("nor does one standing right next to you, even unwatched",
				_watched.global_position.distance_to(_watched_pos) < 0.01,
				"RELOCATE_MIN_DIST is what stops a figure popping at arm's length")

		# --- the Flood ----------------------------------------------------------------
		_scene.call("_enter_zone", 3)
		_advance(4)

	elif _stage == 4 and _t - _stage_at > 0.8:
		_ok("standstill panic is restored outside the Sprawl",
			not bool(_player.get("_standstill_suspended")))
		_wader = _find(_scene, "UnseenWader")
		_ok("the unseen wader exists in the Flood", _wader != null)
		if not _wader:
			_finish()
			return true
		# It is NEVER rendered, and can never be touched.
		_ok("the wader has no mesh", _find(_wader, "MeshInstance3D") == null)
		_ok("the wader has no collider", _find(_wader, "CollisionShape3D") == null)
		_ok("the wader feeds no gaze panic", not _has_ancestor_scary(_wader))
		_ok("it keeps its distance",
			(_wader as Node3D).global_position.distance_to(_player.global_position) >= 11.0,
			"%.1f m away" % (_wader as Node3D).global_position.distance_to(_player.global_position))

		# Start it, then stop the player and watch it take a couple more strides.
		_wader.call("set_player_wading", true)
		_advance(5)

	elif _stage == 5 and _t - _stage_at > 0.5:
		_ok("it is audible while you wade", bool(_wader.get("_halted")) == false)
		_wader.call("set_player_wading", false)
		_advance(6)

	elif _stage == 6 and _t - _stage_at > 0.3:
		# Immediately after the player halts it must STILL be going — that gap is the beat.
		_ok("it does not stop the instant you do", bool(_wader.get("_halted")) == false,
			"two more strides first")
		_advance(7)

	elif _stage == 7 and _t - _stage_at > 2.4:
		_ok("but it does stop, a moment later", bool(_wader.get("_halted")) == true)
		_ok("and none of it cost any panic", _player.get_panic_ratio() < 0.30,
			"panic %.2f — the Flood's own 0.3/s drip is the only source here"
			% _player.get_panic_ratio())
		_finish()
		return true

	if _t > 40.0:
		print("RESULT: FAIL — timed out at stage %d" % _stage)
		quit(1)
		return true
	return false


func _finish() -> void:
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
