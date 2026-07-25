extends SceneTree

# Dev tool: open the House's map-and-chase minigame and dump a screenshot of it.
#
# Run (note: NO --headless, it needs a render target):
#   Godot --path game --script res://tests/screenshot_maze_ui.gd
#
# The existing screenshot_scene.gd harness can only teleport the player and aim a
# camera, so it can never reach this UI — the minigame is behind an interact() call
# on the Bathroom map prop. Its legibility was a confirmed playtest finding (capture
# #3: "the text is not clearly visible, as well as the icons — they are too small"),
# and legibility is exactly the kind of fix that cannot be asserted, so it needs an
# eyeball. This drives the real interaction path rather than instancing MazeChaseUI
# on its own, so what lands in the shot is what a player actually sees.

const OUT := "/tmp/shots/"

var _frame := 0
var _opened := false


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_2_1.tscn")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 8:
		var map := _find_map(current_scene)
		if not map:
			print("FAIL: no HouseMap prop found in the level")
			quit(1)
			return true
		map.interact()
		_opened = true
		print("opened the map")
	elif _opened and _frame == 40:
		DirAccess.make_dir_recursive_absolute(OUT)
		var img := get_root().get_texture().get_image()
		img.save_png(OUT + "house_maze_ui.png")
		print("shot: house_maze_ui")
		quit(0)
		return true
	return false


func _find_map(n: Node) -> Node:
	# Duck-typed on the `won` signal rather than `is HouseMap`: naming a game class
	# in a SceneTree script compiles it before the autoloads exist, which is how
	# walk_lab_wing.gd once broke the very level it was measuring.
	if n.has_signal("won") and n.has_method("interact"):
		return n
	for c in n.get_children():
		var found := _find_map(c)
		if found:
			return found
	return null
