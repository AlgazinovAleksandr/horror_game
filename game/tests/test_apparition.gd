extends SceneTree

# Headless behavior test for the HOLD apparition (apparition.gd).
# Proves the two outcomes the design promises:
#   A. Hold your nerve (stand still)         -> it fades  -> `survived` fires.
#   B. Flee (walk away, no sprint needed)    -> it rushes -> `rushed`   fires.
# Uses teach=true so the rush path is survivable (no real scene reload).
#
# apparition.gd references the Screamer autoload, so it is loaded at RUNTIME
# (not preloaded) — autoloads are not yet registered when this script compiles.
#
# Run: Godot --headless --path game --script res://tests/test_apparition.gd


# Minimal stand-in for the player: the apparition only needs is_sprinting(),
# add_panic(), jolt_camera(), a Camera3D child, and a global position.
class StubPlayer extends CharacterBody3D:
	var sprint := false
	func is_sprinting() -> bool: return sprint
	func add_panic(_a: float) -> void: pass
	func jolt_camera(_s: float = 0.0, _d: float = 0.0) -> void: pass


var _appar_script: GDScript
var _hold_time := 6.0
var _world: Node3D
var _player: StubPlayer
var _appar: Node3D
var _phase := 0          # 0 = still case, 1 = flee case
var _t := 0.0
var _survived := false
var _rushed := false
var _pass_still := false
var _pass_flee := false


var _setup_done := false

func _initialize() -> void:
	# Defer node construction to the first frame — in _initialize the tree root
	# isn't ready, so nodes aren't yet "inside the tree" (global_position errors).
	_appar_script = load("res://scripts/apparition.gd")
	_hold_time = _appar_script.HOLD_TIME


func _setup() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_player = StubPlayer.new()
	_player.name = "Player"
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	_player.add_child(cam)
	_world.add_child(_player)
	_player.global_position = Vector3.ZERO
	_arm_case()


func _arm_case() -> void:
	_t = 0.0
	_survived = false
	_rushed = false
	_player.sprint = false
	_player.global_position = Vector3.ZERO
	if _appar and is_instance_valid(_appar):
		_appar.queue_free()
	_appar = _appar_script.spawn(_world, _appar_script.Rule.HOLD, Vector3.ZERO, true)
	_appar.survived.connect(func() -> void: _survived = true)
	_appar.rushed.connect(func() -> void: _rushed = true)
	_appar.appear()


func _process(delta: float) -> bool:
	if not _setup_done:
		_setup_done = true
		_setup()
		return false
	_t += delta
	match _phase:
		0:  # STILL: expect survive within HOLD_TIME (+ slack), no rush
			if _survived and not _rushed:
				_pass_still = true
				_phase = 1
				_arm_case()
			elif _rushed or _t > _hold_time + 3.0:
				return _finish()
		1:  # FLEE: walk away (no sprint) -> expect rush
			_player.global_position += Vector3(0, 0, 2.0) * delta  # move away from it
			if _rushed:
				_pass_flee = true
				return _finish()
			elif _survived or _t > 4.0:
				return _finish()
	return false


func _finish() -> bool:
	print("--------------------------------------------------")
	print("STILL  -> survives (hold your nerve): ", "PASS" if _pass_still else "FAIL")
	print("FLEE   -> rushes (moving away kills): ", "PASS" if _pass_flee else "FAIL")
	var ok := _pass_still and _pass_flee
	print("RESULT: ", "ALL PASS" if ok else "FAILURE")
	print("--------------------------------------------------")
	quit(0 if ok else 1)
	return true
