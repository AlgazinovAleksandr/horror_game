extends SceneTree

# Dev tool: photograph the BreakerNook payoff scare at the two moments that matter.
#
#   Godot --path game --script res://tests/screenshot_nook_scare.gd
#
# Not headless — it needs a real render. Both frames are timing-critical and only a
# few frames wide, so it POLLS for the state it wants rather than counting frames:
#
#   1. the in-world reveal — caught while the figure's albedo alpha is up. This is
#      the shot that proves lab_nook_figure.png has a real alpha channel; an opaque
#      PNG billboards as a solid rectangle floating in the dark, which is exactly how
#      apparition_figure.jpg shipped once.
#   2. the fullscreen flash_scare — caught while Screamer's black panel is visible,
#      proving lab_nook_face.png loaded and is framed sensibly.

const OUT := "/tmp/nook_shots/"
const NOOK_BREAKER_POS := Vector3(-36.85, 1.1, 7.7)

var _frame := 0
var _scene: Node
var _flipped := false
var _aimed := false
var _got_reveal := false
var _got_flash := false


func _initialize() -> void:
	change_scene_to_file("res://scenes/level_1.tscn")


func _shoot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := get_root().get_texture().get_image()
	img.save_png(OUT + name + ".png")
	print("shot: " + name)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 8:
		return false
	if not _flipped:
		_scene = current_scene
		var player := _scene.get_node_or_null("Player") as CharacterBody3D
		if not player:
			print("FAIL: no Player")
			quit(1)
			return true
		# Stand at the breaker facing the west wall, exactly where a player who has
		# just thrown it is standing — that is the geometry _place_nook_figure() has
		# to cope with (barely a metre of clearance dead ahead).
		player.global_position = Vector3(-35.8, 0.2, 7.7)
		player.rotation.y = PI / 2.0
		var nook: Node3D = null
		for n in _scene.get_children():
			if n is Node3D and n.has_signal("flipped") and n.has_method("interact") \
					and n.global_position.distance_to(NOOK_BREAKER_POS) < 0.5:
				nook = n
		if not nook:
			print("FAIL: nook breaker not found")
			quit(1)
			return true
		nook.interact()
		_flipped = true
		print("nook breaker flipped; waiting for the reveal")
		return false

	if not _got_reveal:
		var fig := _scene.get_node_or_null("NookFigure") as Node3D
		if not fig:
			return false
		if not _aimed:
			# The fan in _place_nook_figure() will usually put it BEHIND the player,
			# because a breaker on the west wall leaves no room in front. Turn to look
			# at it — the point of this shot is the figure's alpha, not the framing.
			var player := _scene.get_node_or_null("Player") as CharacterBody3D
			var to := fig.global_position - player.global_position
			player.rotation.y = atan2(-to.x, -to.z)
			_aimed = true
			print("figure at %v, %.2f m from the player" % [
				fig.global_position.snappedf(0.01),
				player.global_position.distance_to(fig.global_position)])
			return false
		var quad := fig.get_child(0) as MeshInstance3D
		var mat := quad.get_surface_override_material(0) as StandardMaterial3D
		if mat and mat.albedo_color.a > 0.5:
			_shoot("01_nook_reveal")
			_got_reveal = true
		return false

	if not _got_flash:
		# Screamer builds a black ColorRect panel it shows for the flash's duration.
		# ⚠️ Reached by node path, not by the `Screamer` identifier: naming an autoload
		# in a SceneTree script is a compile-time lookup that happens before the
		# autoloads exist, so it fails to compile outright.
		var screamer := get_root().get_node_or_null("/root/Screamer")
		var panel := _find_panel(screamer) if screamer else null
		if panel and panel.visible:
			_shoot("02_nook_flash")
			_got_flash = true
		return false

	if _frame > 1400:
		print("TIMEOUT")
	print("NOOK-SHOTS DONE  reveal=%s flash=%s" % [_got_reveal, _got_flash])
	quit(0 if (_got_reveal and _got_flash) else 1)
	return true


func _find_panel(root: Node) -> ColorRect:
	for c in root.get_children():
		if c is ColorRect:
			return c
		var f := _find_panel(c)
		if f:
			return f
	return null
