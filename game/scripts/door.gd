extends StaticBody3D

enum UnlockCondition { NONE, KEYCARD, CODE_ENTERED, TWIST_READ }

@export var unlock_condition: UnlockCondition = UnlockCondition.NONE
@export var advances_level: bool = true
@export var goes_back: bool = false

# An additional lock the OWNING LEVEL controls, on top of `unlock_condition`.
#
# KONTUR needs its exit sealed until all eight gates are passed — a condition no enum
# value can express, because it lives in the level script's own state rather than in
# GameState. The level sets this true at build time and clears it when the last gate
# falls. `locked_message` lets it say WHY, which matters there: a run can be forfeit,
# and "LOCKED" would read as a bug rather than as a verdict.
@export var extra_lock: bool = false
@export var locked_message: String = "LOCKED"

var _twist_activated: bool = false


# The material an exit / back door should wear.
#
# Project convention (CLAUDE.md): exit and back doors glow blood-red so the player
# can find the way on in the dark. Levels 1 and 2 implemented that as a flat red
# emissive box with no texture at all, which read as a red brick rather than a door.
# With a texture the albedo carries the door and the emission is tinted red THROUGH
# that same texture, so the glow takes the door's shape and the blood-red signature
# survives.
#
# emission stays enabled and starts at 1.5 in both branches because _flash_unlock()
# tweens emission_energy_multiplier from wherever it is up to 10.0 and back to 3.0.
# Build a door's visible geometry under `body` and return the node _flash_unlock()
# should tween.
#
# ⚠️ The artwork goes on QUADS, not on the slab. A BoxMesh does not map the whole
# texture onto each face, so a door textured directly on the box rendered a
# magnified CROP of its own art — one hinge and a blank panel, no window, no push
# bar. The tray and monitor in the morgue use quads and show their full textures,
# which is what made the difference obvious. The slab stays as the dark edge/depth.
#
# Only the FRONT face is textured. Every door in the game is mounted against a solid
# wall, so a second quad on the back is buried in that wall — dead geometry that also
# trips the wall-prop assertion in tests/check_wall_overlap.gd. Leaving it off turns
# that assertion into a useful check: a door built facing the wrong way has its front
# quad inside the wall, and the test fails.
static func build_visual(body: Node3D, size: Vector3, tex_path: String) -> MeshInstance3D:
	var slab := MeshInstance3D.new()
	slab.name = "DoorSlab"
	var bm := BoxMesh.new()
	bm.size = size
	slab.mesh = bm
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color(0.09, 0.08, 0.08)
	edge.roughness = 0.9
	slab.set_surface_override_material(0, edge)
	body.add_child(slab)

	var face := MeshInstance3D.new()
	face.name = "DoorMesh"   # _flash_unlock() looks this node up by name
	var qm := QuadMesh.new()
	qm.size = Vector2(size.x, size.y)
	face.mesh = qm
	face.set_surface_override_material(0, door_material(tex_path))
	face.position = Vector3(0, 0, size.z / 2.0 + 0.004)
	body.add_child(face)
	return face


static func door_material(tex_path: String = "") -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 1.5
	if tex_path != "" and ResourceLoader.exists(tex_path):
		var tex := load(tex_path)
		mat.albedo_texture = tex
		mat.albedo_color = Color(1, 1, 1)
		mat.emission_texture = tex
		# Very restrained on purpose. These levels are lit at ~0.45 energy, so a
		# surface's albedo contributes far less than its emission — at 0.5 the red
		# swamped the pale steel texture and the door rendered salmon pink. The
		# glow only has to make the door findable; its shape does the rest.
		mat.emission = Color(0.6, 0.09, 0.09)
		mat.emission_energy_multiplier = 0.08
		mat.roughness = 0.85
	else:
		mat.albedo_color = Color(0.15, 0.01, 0.01)
		mat.emission = Color(0.35, 0.02, 0.02)
	return mat


func _process(_delta: float) -> void:
	if unlock_condition == UnlockCondition.TWIST_READ and not _twist_activated and GameState.twist_read:
		_twist_activated = true
		_flash_unlock()


func _flash_unlock() -> void:
	var door_mesh: MeshInstance3D = get_node_or_null("DoorMesh")
	if not door_mesh:
		return
	var mat := door_mesh.get_surface_override_material(0)
	if not mat:
		mat = door_mesh.mesh.surface_get_material(0) if door_mesh.mesh else null
	if not mat or not mat is StandardMaterial3D:
		return
	var std_mat := mat as StandardMaterial3D
	var tween := create_tween()
	tween.tween_method(
		func(e: float): std_mat.emission_energy_multiplier = e,
		std_mat.emission_energy_multiplier, 10.0, 0.3
	)
	tween.tween_method(
		func(e: float): std_mat.emission_energy_multiplier = e,
		10.0, 3.0, 0.6
	)


func interact() -> void:
	if _is_unlocked():
		_open_door()
	else:
		_show_locked_feedback()


func _is_unlocked() -> bool:
	if extra_lock:
		return false
	match unlock_condition:
		UnlockCondition.NONE:
			return true
		UnlockCondition.KEYCARD:
			return GameState.has_keycard
		UnlockCondition.CODE_ENTERED:
			return GameState.level2_code_correct
		UnlockCondition.TWIST_READ:
			return GameState.twist_read
	return false


func _open_door() -> void:
	var open_audio: AudioStreamPlayer3D = get_node_or_null("OpenAudio")
	if open_audio and open_audio.stream:
		open_audio.play()
	if goes_back:
		await get_tree().create_timer(0.5).timeout
		GameState.go_back()
	elif advances_level:
		await get_tree().create_timer(0.5).timeout
		GameState.advance_level()


func _show_locked_feedback() -> void:
	ScreenText.toast(get_tree(), locked_message, Color(1.0, 0.2, 0.2), 1.5, 48)
