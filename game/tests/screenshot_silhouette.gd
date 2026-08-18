extends SceneTree

# Photograph the Corridor's running silhouette mid-stride, from where the player stands when
# it fires. Needs a render target — run WITHOUT --headless:
#
#   Godot --path game --script res://tests/screenshot_silhouette.gd
#
# ⚠️ `screenshot_corridor.gd` structurally cannot take this shot: its `SHOTS` table teleports
# the camera to a path distance and captures, and this figure exists for 0.8 s inside a Tween
# started by an event. `check_corridor_events.gd` measures its APPARENT SIZE headlessly (13.2 %
# of screen height, against 4.9 % for the placement it replaced) — this is the other half, the
# one a number cannot answer: does the thing that is now big enough to see read as a PERSON?
# It was one capsule until 2026-08-17 and bringing a pill closer only makes a bigger pill.

const OUT := "/tmp/corridor_shots/"

var _t := 0.0
var _stage := 0
var _shot := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	change_scene_to_file("res://scenes/corridor.tscn")


func _process(delta: float) -> bool:
	_t += delta
	if _stage == 0:
		if _t < 1.0:
			return false
		var lvl := current_scene
		var player: CharacterBody3D = lvl.get_node("Player")
		var cs: GDScript = lvl.get_script()
		var here: Dictionary = lvl.call("_path_point", float(cs.get("SILHOUETTE_TRIGGER")))
		var there: Dictionary = lvl.call("_path_point", float(cs.get("SILHOUETTE_CROSS")))
		var to: Vector3 = (there.pos as Vector3) - (here.pos as Vector3)
		to.y = 0.0
		player.global_position = (here.pos as Vector3) + Vector3(0, 0.05, 0)
		player.rotation.y = atan2(-to.x, -to.z)
		lvl.call("_ev_silhouette")
		_stage = 1
		_t = 0.0
		return false
	# Four frames across the 0.8 s crossing — the figure is only in view for about 0.6 s of it.
	var want := [0.18, 0.34, 0.48, 0.62]
	if _shot < want.size() and _t >= want[_shot]:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(OUT + "22_silhouette_%d.png" % _shot)
		print("shot: 22_silhouette_%d  (t=%.2f s)" % [_shot, _t])
		_shot += 1
	return _shot >= want.size()
