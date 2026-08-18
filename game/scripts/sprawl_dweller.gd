extends Node3D
class_name SprawlDweller

# THE THING IN THE CRATE — the Sprawl's one-shot runner, and the second half of the user's
# own design for zone 2 (backlog 04 B-R3, 2026-08-17):
#
#   *"I want the true wall appear only after the player explored the dark, opened this box,
#   saw the screamer. Maybe we can also do it the following way: the creature which was a
#   jumpscare starts running towards the wall, it escapes the wall, and once it is there,
#   the wall starts being visible. And it would actually whisper, and the first whisper
#   would lead to that box hidden in the dark."*
#
# So: a whisper leads you into a dark alcove, the crate answers E with a scare, and the
# thing that was in it RUNS — across the hall, through one of the four identical glitch
# walls, and out. The wall it leaves through is the real one. The thing that frightened you
# shows you the way out by escaping through it.
#
# ⚠️⚠️ THIS IS NOT A `Watcher`, AND THAT IS A HARD LINE, not a coding preference.
# `congregation.gd`'s figures are ruleless BY CONSTRUCTION — no `ScaryObject`, no collider,
# no kill radius, no fail state — and `CLAUDE.md` records that as the reason the Congregation
# is legal at all under `SCARY.md` §8.3, standing in the same level as a Smiler that kills
# you for looking at it. One of THOSE suddenly charging would rewrite what the zone teaches
# about which silhouettes are safe. This is a separate object with its own script, and the
# Congregation is untouched.
#
# ⚠️ IT CANNOT TOUCH YOU. No collider, no `ScaryObject`, no gaze term, no kill radius, no
# `Screamer.trigger()`, no panic of its own. It runs a fixed path and vanishes. The whole
# encounter's cost is the one `flash_scare` the crate fires, which is survivable and which
# the user asked for; whether that scare should carry a panic number at all is the OPEN
# QUESTION this pass returned rather than answered.
#
# ⚠️ THE VOICE TRAVELS WITH IT. The crate's two whisper loops are reparented onto this node
# when it spawns and are handed to the wall when it arrives — so the sound that led you into
# the dark is the sound that leaves through the exit and then stays there. That continuity
# is the tell; nothing about it is a new rule and none of it is on the duckable bus.
#
# ⚠️ UNSHADED BILLBOARD, REAL RGBA CUTOUT. `sprawl_dweller.png` is keyed by
# `tools/cutout_alpha.py` and the mesh is sized FROM ITS ASPECT (0.375) — a texture with no
# alpha billboards as a solid rectangle (the `apparition_figure.jpg` bug), and a mesh that
# does not match its art is stretched (Issue 35 / `check_art_aspect.gd`).

signal arrived

const TEX := "res://assets/textures/level_backrooms/sprawl_dweller.png"
const HEIGHT := 2.15
const SPEED := 6.5              # m/s — a run, not a stalk. It is fleeing, not hunting.
const THROUGH := 2.2            # how far past the wall it keeps going before it is gone
const FADE_IN := 0.35
const FADE_OUT := 0.55

var _quad: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _target: Vector3 = Vector3.ZERO
var _running := false
var _done := false
var _alpha := 0.0
var _fade_dir := 1.0


static func build(parent: Node, dweller_name: String, at: Vector3) -> SprawlDweller:
	var d := SprawlDweller.new()
	d.name = dweller_name
	parent.add_child(d)
	d.global_position = at
	return d


func _ready() -> void:
	_quad = MeshInstance3D.new()
	_quad.name = "DwellerArt"
	var qm := QuadMesh.new()
	# Sized from the artwork's own aspect. Falls back to a plausible human ratio only if
	# the texture is missing entirely, which would already be a louder failure.
	var aspect := 0.375
	if ResourceLoader.exists(TEX):
		var t: Texture2D = load(TEX)
		if t != null and t.get_height() > 0:
			aspect = float(t.get_width()) / float(t.get_height())
	qm.size = Vector2(HEIGHT * aspect, HEIGHT)
	_quad.mesh = qm
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if ResourceLoader.exists(TEX):
		_mat.albedo_texture = load(TEX)
	# ⚠️ Albedo is a TINT on an unshaded material, so this is the only brightness control
	# there is. Kept dark: the figure must read as a shape against the Sprawl's lit floor,
	# never as a light source (Issues 21/27/33, and `watcher.gd`'s figure_tint lesson —
	# measured there, a "shadow" lighter than the floor it crossed).
	_mat.albedo_color = Color(0.40, 0.40, 0.44, 0.0)
	_quad.material_override = _mat
	_quad.position = Vector3(0, HEIGHT / 2.0, 0)
	add_child(_quad)
	set_process(true)


# Take the crate's whisper loops with you: the voice that led the player into the dark is
# the voice that leaves through the wall.
func adopt_voice(players: Array) -> void:
	for p in players:
		if not is_instance_valid(p):
			continue
		var a := p as Node3D
		var keep := a.global_transform
		a.get_parent().remove_child(a)
		add_child(a)
		a.global_transform = keep
		a.position = Vector3(0, HEIGHT * 0.6, 0)


# Hand the voice on to whatever it ran through, at that surface's position.
func release_voice(to: Node3D) -> Array:
	var out: Array = []
	for c in get_children():
		if c is AudioStreamPlayer3D:
			out.append(c)
	for a in out:
		remove_child(a)
		to.add_child(a)
		(a as Node3D).position = Vector3(0, 0, 0.4)
	return out


func run_to(target: Vector3) -> void:
	_target = Vector3(target.x, global_position.y, target.z)
	_running = true


func is_done() -> bool:
	return _done


func _process(delta: float) -> void:
	# Fade the alpha rather than the visibility: an unshaded billboard popping in at full
	# opacity reads as a texture error, and this one arrives ON a scare that is already
	# spending the player's attention.
	_alpha = clampf(_alpha + _fade_dir * delta / (FADE_IN if _fade_dir > 0.0 else FADE_OUT),
		0.0, 1.0)
	if _mat:
		_mat.albedo_color.a = _alpha

	if not _running or _done:
		return
	var to: Vector3 = _target - global_position
	to.y = 0.0
	var step: float = SPEED * delta
	if to.length() <= step:
		# Through the wall and out. It keeps going for THROUGH metres on the far side,
		# fading, so it reads as leaving rather than as being deleted at the surface.
		global_position = _target
		_running = false
		_done = true
		_fade_dir = -1.0
		var dir: Vector3 = to.normalized() if to.length() > 0.001 else -global_transform.basis.z
		var tw := create_tween()
		tw.tween_property(self, "global_position",
			global_position + dir * THROUGH, FADE_OUT)
		# Connected, never awaited (Issue 6).
		tw.finished.connect(queue_free)
		arrived.emit()
		return
	global_position += to.normalized() * step
