extends SceneTree

# Reproduces a DEATH in the Backrooms and asserts the level restarts cleanly.
#
# A screamer during a live playtest logged an error inside
# start_current_level() -> change_scene_to_file(). Dying is the single most common
# thing a player does in this level, so the restart path has to be clean.
#
#   Godot --headless --path game --script res://tests/check_backrooms_death.gd

var _frame := 0
var _fired := false
var _fails: Array[String] = []
var _checks := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/backrooms.tscn")


func _ok(label: String, cond: bool) -> void:
	_checks += 1
	print(("  PASS  " if cond else "  FAIL  ") + label)
	if not cond:
		_fails.append(label)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 10:
		var player: CharacterBody3D = current_scene.get_node_or_null("Player")
		_ok("scene loaded with player", player != null)
		if player:
			# Fill the panic bar the way any real death does.
			print("  ... killing the player via add_panic(999)")
			player.add_panic(999.0)
			_fired = true
	elif _frame > 400:
		# Screamer waits RESTART_DELAY (2.5 s) then restarts. By now we should be
		# back in a live Backrooms scene with a fresh player.
		_ok("screamer fired", _fired)
		var scene := current_scene
		_ok("a scene is loaded after restart", scene != null)
		if scene:
			print("  ... current scene: ", scene.scene_file_path)
			_ok("restarted back into the Backrooms",
				scene.scene_file_path.contains("backrooms"))
			_ok("restarted scene has a live player",
				scene.get_node_or_null("Player") != null)
			_ok("restarted scene rebuilt zone 2",
				scene.get_node_or_null("ZoneSprawl") != null)
			_ok("restarted scene rebuilt zone 3",
				scene.get_node_or_null("ZoneFlood") != null)
			# The bus must survive a restart, or SilenceZone silently stops working.
			_ok("Backrooms audio bus still present",
				AudioServer.get_bus_index("Backrooms") != -1)
			_ok("audio bus not left ducked",
				AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Backrooms")) > -5.0)

		print("\n%d checks, %d failed" % [_checks, _fails.size()])
		for f in _fails:
			print("   ! ", f)
		quit(1 if _fails.size() > 0 else 0)
		return true
	return false
