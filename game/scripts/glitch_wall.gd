extends Node3D
class_name GlitchWall

# A wall running the screen-space vertex-jitter shader — the Backrooms' one real
# verb. Walking INTO it is how you leave a zone; there is never a door.
#
# Extracted from backrooms.gd when zones 2 and 3 started needing several of these
# at once, most of them lies. A wall knows whether it is real and reports contact;
# the zone that owns it decides what that means.

signal touched(is_real: bool)

const SHADER_PATH := "res://assets/materials/backrooms/glitch_wall.gdshader"
const TEX_DIR := "res://assets/textures/level_backrooms/"

var is_real: bool = true
var _mesh: MeshInstance3D
var _area: Area3D
var _solid: bool = false
var _shader_mat: ShaderMaterial
var _trigger_size: Vector3 = Vector3.ONE
var _body: StaticBody3D = null
# See set_armed() at the bottom of this file: armed by default, so nothing else moves.
var _armed: bool = true
# See set_sealed() at the bottom of this file: unsealed by default, likewise.
var _sealed: bool = false
var _seal_body: StaticBody3D = null


func setup(size: Vector2, height: float, real: bool = true,
		base_tex_path: String = "") -> void:
	is_real = real

	_mesh = MeshInstance3D.new()
	_mesh.name = "GlitchSurface"
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.subdivide_width = 48
	mesh.subdivide_depth = 48
	mesh.orientation = PlaneMesh.FACE_Z
	_mesh.mesh = mesh

	var tex_path := base_tex_path if base_tex_path != "" \
		else TEX_DIR + "backrooms_wallpaper_albedo.png"
	if ResourceLoader.exists(SHADER_PATH):
		_shader_mat = ShaderMaterial.new()
		_shader_mat.shader = load(SHADER_PATH)
		if ResourceLoader.exists(tex_path):
			_shader_mat.set_shader_parameter("base_tex", load(tex_path))
		_mesh.material_override = _shader_mat
	else:
		_mesh.material_override = MazeKit.wall_material()
	add_child(_mesh)

	# Walk-into trigger sitting just in front of the surface.
	_area = Area3D.new()
	_area.name = "GlitchTrigger"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	_trigger_size = Vector3(size.x, height, 1.2)
	shape.size = _trigger_size
	col.shape = shape
	_area.add_child(col)
	_area.position = Vector3(0, 0, -0.9)
	_area.body_entered.connect(_on_body)
	add_child(_area)


func _on_body(body: Node3D) -> void:
	if _solid or _sealed or not body.is_in_group("player"):
		return
	touched.emit(is_real)


func is_solid() -> bool:
	return _solid


# A fake that has been found out: the tearing stops and it becomes ordinary wall,
# so the player is never asked the same dead question twice.
func go_solid() -> void:
	if _solid:
		return
	_solid = true
	visible = true          # an outed wall is ordinary wall, and must be seen as such
	_mesh.material_override = MazeKit.wall_material()
	if is_instance_valid(_area):
		_area.queue_free()
	# An outed wall builds its own collider below; drop the gate's, or the wall carries two
	# and `revive()` would leave one of them behind.
	_sealed = false
	if is_instance_valid(_seal_body):
		_seal_body.queue_free()
		_seal_body = null

	# ⚠️ A solidified wall MUST gain a collider. Without one it is a hole in the
	# perimeter with no floor behind it, and the player walks straight out of the
	# world — found in playtest, at (200.69, -6.30, 21.78).
	if not is_instance_valid(_body):
		_body = StaticBody3D.new()
		_body.name = "SolidBody"
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(_trigger_size.x, _trigger_size.y, 0.3)
		col.shape = shape
		_body.add_child(col)
		add_child(_body)


# Tear a solidified wall back open. Only used to rescue zone 2 if the player has
# outed every wall — a maze with no exit left is worse than a maze that cheats.
func revive() -> void:
	if not _solid:
		return
	_solid = false
	if is_instance_valid(_body):
		_body.queue_free()
		_body = null
	if _shader_mat:
		_mesh.material_override = _shader_mat
	_area = Area3D.new()
	_area.name = "GlitchTrigger"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = _trigger_size
	col.shape = shape
	_area.add_child(col)
	_area.position = Vector3(0, 0, -0.9)
	_area.body_entered.connect(_on_body)
	add_child(_area)
	# A wall revived while disarmed must come back disarmed, or the rescue path in
	# zone 2 would silently re-arm a seam the level is deliberately holding back.
	# The same is true of a SEALED wall: zone 2's all-walls-outed rescue can promote a
	# wall the crate has not opened yet, and it must come back with its gate on.
	_area.monitoring = _armed and not _sealed
	if _sealed:
		_build_seal_body()


# Zone 3 drives this per-frame from the flashlight state: the seam is only
# legible in the dark, which is exactly where the panic lives.
#
# Hides the whole node, not just the mesh — Node3D visibility is inherited, so the
# surface goes with it, while the Area3D trigger keeps monitoring (physics is
# independent of visibility). A seam you can't see is still a seam you can walk
# through once you've found it.
func set_seam_visible(v: bool) -> void:
	if _solid or not _armed:
		return
	visible = v


func set_tear_amount(amount: float) -> void:
	if _shader_mat:
		_shader_mat.set_shader_parameter("tear_amount", amount)


# ⚠️ DORMANT IS NOT THE SAME AS INVISIBLE, and that distinction is why this exists
# (2026-08-17, the Flood's plate gate). `set_seam_visible()` deliberately leaves the
# Area3D monitoring — a seam you cannot see is still one you can walk through once you
# have found it, which is the whole of zone 3's darkness rule.
#
# A seam that has not been EARNED yet is a different thing: the Flood's real seam does
# not exist until the six fragments are in the frame, so it must be untouchable as well
# as unseen, or a player who blunders into the Sump early clears the zone without ever
# meeting the puzzle. Disarming stops the trigger monitoring AND hides the node, which
# is also what `check_reachable.gd` reads as DORMANT rather than as unreachable.
#
# Defaults to armed, so every existing caller is byte-identical.
func set_armed(on: bool) -> void:
	if _armed == on:
		return
	_armed = on
	if is_instance_valid(_area):
		_area.monitoring = on
	if not on:
		visible = false


func is_armed() -> bool:
	return _armed


# ⚠️ THE MARK THE DWELLER LEAVES (2026-08-17, B-R3). When the thing out of the Sprawl's
# crate escapes through a wall, that wall has to stay identifiable afterwards or the whole
# beat is a cutscene. The mark is MOTION, not brightness: `tear_amount` drives the shader's
# per-band vertex displacement, so an agitated wall visibly thrashes where the other three
# only shimmer. Nothing here is emissive — the glitch wall is already the brightest surface
# in its room by 2.3x (measured, backlog 04 BS1), and adding light to it was offered to the
# user and declined.
const TEAR_CALM := 0.12       # the shader's own default
const TEAR_AGITATED := 0.34

var _agitated: bool = false


func set_agitated(on: bool) -> void:
	_agitated = on
	set_tear_amount(TEAR_AGITATED if on else TEAR_CALM)


func is_agitated() -> bool:
	return _agitated


# ⚠️ SEALED IS A THIRD STATE, and it is not `set_armed(false)` (2026-08-18, the Sprawl's
# crate gate). The user's call, asked for twice: *"it should run and go through the real
# wall which would not be active until it runs through."*
#
# Three states, three different jobs, and they are deliberately separate:
#   solid   an outed FAKE. Ordinary wall for ever, trigger freed, collider added.
#   armed   the Flood's plate gate. The seam does not EXIST yet: hidden AND not monitoring.
#   sealed  the Sprawl's crate gate. The seam looks exactly like its three neighbours —
#           same shader, same tearing, same brightness — and walking into it does NOTHING.
#
# Why the Sprawl cannot use `set_armed(false)`: `backrooms_zone2.gd:_side_runs()` cuts a
# `GLITCH_GAP` 7 m hole in the perimeter for each wall to stand in, so the wall IS the
# shell there. Hiding it leaves a 7 m hole with no floor behind it and the player walks out
# of the world — the exact playtest failure `go_solid()`'s collider was added for. So a
# sealed wall keeps its mesh and gains a collider instead: the surface is unchanged and the
# BODY is what refuses.
#
# ⚠️ The trigger stops monitoring as well as being blocked. Belt and braces: `_area` is a
# 1.2 m deep box standing 0.9 m in FRONT of the surface, and the seal body is only 0.3 m
# thick at the surface itself, so a player pressed against a sealed wall is standing inside
# the trigger volume. Blocking alone would not have been enough.
#
# Defaults to false, so every existing caller is byte-identical.
const SEAL_THICK := 0.3

func set_sealed(on: bool) -> void:
	if _sealed == on:
		return
	_sealed = on
	if is_instance_valid(_area):
		_area.monitoring = _armed and not on
	if on:
		_build_seal_body()
	elif is_instance_valid(_seal_body):
		_seal_body.queue_free()
		_seal_body = null


func is_sealed() -> bool:
	return _sealed


func _build_seal_body() -> void:
	if is_instance_valid(_seal_body):
		return
	_seal_body = StaticBody3D.new()
	_seal_body.name = "SealBody"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(_trigger_size.x, _trigger_size.y, SEAL_THICK)
	col.shape = shape
	_seal_body.add_child(col)
	add_child(_seal_body)
