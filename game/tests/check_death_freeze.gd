extends SceneTree

# Does DEATH actually stop the player? (ISSUES_SOLUTIONS.md Issue 15)
#
# Screamer.trigger() unpauses the tree on purpose (NoteUI detects the unpause to drop
# a trap-note overlay), which left the player fully simulating behind the black panel
# for the whole restart delay — still moving, still gazing, still filling the panic
# bar. Playtest caught it as panic climbing 5% -> 78% AFTER the player died.
#
#   Godot --headless --path game --script res://tests/check_death_freeze.gd

var _frame := 0
var _player: CharacterBody3D
var _fails: Array[String] = []
var _checks := 0
var _panic_at_death := 0.0


func _initialize() -> void:
	change_scene_to_file("res://scenes/kontur.tscn")


func _ok(label: String, cond: bool) -> void:
	_checks += 1
	print(("  PASS  " if cond else "  FAIL  ") + label)
	if not cond:
		_fails.append(label)


func _process(_delta: float) -> bool:
	_frame += 1

	if _frame == 10:
		_player = current_scene.get_node_or_null("Player") as CharacterBody3D
		_ok("player found", _player != null)
		if not _player:
			quit(1)
			return true
		# The precondition the whole fix rests on — _freeze_player() finds the player
		# by group, and until Issue 12 the player was in no group at all.
		_ok("player is in the 'player' group", _player.is_in_group("player"))

	elif _frame == 12:
		# Load the bar up, then kill. trigger() is async: it returns at its first
		# await, so we can inspect the world mid-death-sequence.
		_player.set_panic_ratio(0.5)
		# Autoloads aren't bound as identifiers inside a bare SceneTree script —
		# reach the singleton by path.
		var screamer: Node = root.get_node_or_null("/root/Screamer")
		_ok("Screamer autoload reachable", screamer != null)
		if screamer:
			screamer.trigger()

	elif _frame == 14:
		_ok("player is frozen during the death sequence",
			_player.process_mode == Node.PROCESS_MODE_DISABLED)
		_panic_at_death = _player.get_panic_ratio()

	elif _frame == 40:
		# ~half a second of real frames later, nothing the player owns may have moved.
		if is_instance_valid(_player):
			var drift: float = absf(_player.get_panic_ratio() - _panic_at_death)
			_ok("panic does not accrue after death (drift %.3f)" % drift, drift < 0.001)
		else:
			# The reload already happened — also fine, the corpse is gone.
			_ok("panic does not accrue after death (player freed by reload)", true)

	elif _frame > 60:
		print("\n%d checks, %d failed" % [_checks, _fails.size()])
		for f in _fails:
			print("   ! ", f)
		quit(1 if _fails.size() > 0 else 0)
		return true
	return false
