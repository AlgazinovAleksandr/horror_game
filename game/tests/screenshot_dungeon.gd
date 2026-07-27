extends SceneTree

# Photograph THE NIGHTMARE.
#
# ⚠️ Run WITHOUT --headless — it needs a real render target:
#   Godot --path game --script res://tests/screenshot_dungeon.gd
#
# Two jobs. The first is the ordinary one: static shots of the Antechamber, a
# corridor, a chamber, a lit sconce, so the art and lighting can be reviewed.
#
# The second is the reason this file has custom logic rather than reusing
# screenshot_scene.gd's spot table: the Hollow One's spark reveal lives for
# REVEAL_SECONDS = 0.30 s and its ALPHA is what is animated. A fixed frame counter
# cannot reliably catch a 0.3 s window — screenshot_nook_scare.gd learned this on a
# 0.2 s one — so this POLLS the figure's alpha every frame and fires the capture on
# the frame it is actually visible.

const OUT := "/tmp/dungeon_shots/"
const SEED := 101
const SETTLE := 16
const HOLD := 12       # frames between placing the camera and taking the shot

# [feet position, look-at, name]
var _shots: Array = []

var _started := false
var _settle := 0
var _level: Node = null
var _gen = null
var _player: CharacterBody3D = null
var _cam: Camera3D = null
var _i := 0
var _step := 0
var _phase := "static"
var _spark_frames := 0
var _got_reveal := false
var _teach = null


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		var gs := root.get_node_or_null("GameState")
		if gs:
			gs.call("save_level_progress", 7,
				{"layout_seed": SEED, "content_seed": SEED * 31 + 7})
		change_scene_to_file("res://scenes/dungeon.tscn")
		return false

	_settle += 1
	if _settle < SETTLE:
		return false

	if _level == null:
		_level = current_scene
		if _level == null or not _level.has_method("get_gen"):
			print("dungeon.tscn did not load")
			quit(1)
			return true
		_gen = _level.call("get_gen")
		_player = _level.get_node_or_null("Player") as CharacterBody3D
		_cam = _player.get_node_or_null("Camera3D") as Camera3D
		_player.set_physics_process(false)   # keep teleports from being undone
		_build_shots()
		return false

	match _phase:
		"static":
			return _tick_static()
		"spark":
			return _tick_spark()
	return false


func _build_shots() -> void:
	var ante := Vector3(0, 0, -46)
	_shots = [
		[ante + Vector3(-3.0, 0, 0), ante + Vector3(0, 1.2, 2.0), "01_antechamber"],
		[ante + Vector3(0, 0, -1.0), ante + Vector3(0, 1.6, -4.0), "02_ante_scrawl"],
		[ante + Vector3(0.5, 0, 3.2), ante + Vector3(0, 0.5, 2.0), "03_the_cot"],
	]
	# Spawn chamber, its sconce, a corridor, and the bed chamber.
	var spawn_c: Vector3 = _gen.room_center_world(_gen.spawn_room)
	_shots.append([spawn_c + Vector3(-2, 0, -2), spawn_c + Vector3(0, 1.4, 0), "04_spawn_chamber"])
	var sc: Array = _level.call("get_sconces")
	if sc.size() > 0:
		var s = sc[0]
		var n: Vector3 = s.global_transform.basis.z.normalized()
		_shots.append([s.global_position + n * 3.0 - Vector3(0, 1.7, 0),
			s.global_position, "05_sconce_unlit"])
	if _gen.corridor_names.size() > 0:
		var hall: String = _gen.corridor_names[_gen.corridor_names.size() / 2]
		var hc: Vector3 = _gen.room_center_world(hall)
		_shots.append([hc + Vector3(0, 0, -4), hc + Vector3(0, 1.4, 4), "06_corridor"])
	var bed: Vector3 = _gen.room_center_world(_gen.bed_room)
	_shots.append([bed + Vector3(-3, 0, -3), bed + Vector3(0, 0.6, 0), "07_bed_chamber"])


func _tick_static() -> bool:
	if _i >= _shots.size():
		_phase = "spark"
		_step = 0
		_begin_spark()
		return false
	if _step == 0:
		_place(_shots[_i][0], _shots[_i][1])
		# ⚠️ Light the candle before leaving the Antechamber. Beyond the brazier
		# there is NO light in this level by design (§B7: darkness is range falloff,
		# not fog), so a shot taken without it is a photograph of pure black and
		# says nothing about how the level looks in play.
		if _i == 3:
			var candle = _level.get("_candle")
			if candle != null:
				candle.call("toggle")
		# Light the first sconce halfway through so the "after" shot has real light.
		if _i == 4:
			var sc: Array = _level.call("get_sconces")
			if sc.size() > 0:
				sc[0].call("light_it")
	_step += 1
	if _step >= HOLD:
		_capture(_shots[_i][2])
		# Re-shoot the sconce once it is burning.
		if _i == 4:
			_capture("05b_sconce_lit")
		_i += 1
		_step = 0
	return false


# ── The spark reveal ────────────────────────────────────────────────────────────
func _begin_spark() -> void:
	# Drive the level's own teaching beat rather than hand-placing a figure: this
	# photographs the beat the player actually gets.
	_level.call("_run_hollow_teach")
	_teach = _level.get("_teach_hollow")
	if _teach == null:
		print("no teaching Hollow One was created — nothing to photograph")
		_finish()
		return
	# Stand in the corridor the grate is in, looking at it.
	var corridor: String = _gen.teach_corridor
	if corridor != "":
		var c: Vector3 = _gen.room_center_world(corridor)
		var a: Vector3 = _gen.room_center_world(_gen.teach_room)
		_place(c, Vector3(a.x, 1.4, a.z))


func _tick_spark() -> bool:
	_spark_frames += 1
	if _spark_frames == 6:
		_capture("08_grate_before_spark")
	if _spark_frames == 10:
		_level.call("_do_spark")
	if _spark_frames > 10 and not _got_reveal:
		# ⚠️ POLL the alpha. The reveal is 0.30 s of an ALPHA tween on an unshaded
		# billboard; a frame counter would photograph either an empty corridor or a
		# fully faded one depending on the frame rate that day.
		var fig := _teach.get_node_or_null("HollowFigure") as MeshInstance3D
		if fig != null and fig.visible:
			var mat := fig.material_override as StandardMaterial3D
			if mat != null and mat.albedo_color.a > 0.45:
				_capture("09_hollow_revealed_alpha_%.2f" % mat.albedo_color.a)
				_got_reveal = true
	if _spark_frames > 90:
		if not _got_reveal:
			print("WARNING: never caught the reveal — alpha never exceeded 0.45")
		_finish()
		return true
	return false


func _finish() -> void:
	print("shots written to ", OUT)
	quit(0)


func _place(feet: Vector3, look_at: Vector3) -> void:
	_player.global_position = feet
	var eye: Vector3 = feet + Vector3(0, 1.65, 0)
	var to: Vector3 = look_at - eye
	_player.rotation.y = atan2(-to.x, -to.z)   # player forward is -basis.z
	_cam.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	_player.force_update_transform()
	_cam.force_update_transform()


func _capture(shot_name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT + shot_name + ".png")
	print("shot: ", shot_name)
