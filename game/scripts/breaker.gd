extends StaticBody3D
class_name Breaker

# A power breaker switch for the Lab's restore-power quest. interact() flips it
# once (lever drops, indicator goes red->green, clunk) and emits `flipped`. The
# level counts flips and, on the third, restores power + opens the morgue shutter.
# Self-building from primitives.

signal flipped

# BreakerNook's breaker sets this false: emission SELF-ILLUMINATES regardless of
# scene ambient/darkness (confirmed playtest bug — "even though it is now dark,
# I can still see the texture of the light switcher"), so a breaker meant to be
# genuinely invisible in the dark must not use it at all.
#
# ⚠️ Playtest 2026-07-25 (capture #1, "the way the light switch is hidden here is
# very obvious"): this flag used to gate a LOT more, and the lit branch made even
# a deliberately-hidden-in-plain-sight breaker the single brightest object in the
# level — the panel wore its own art as an EMISSION texture at 0.25 and the lever
# glowed red at 0.7, while the Lab is lit at ~0.45 energy with Linear tonemap and
# no glow (Issue 21: emission is most of a surface's colour here). A "hidden"
# breaker was, literally, a lamp. This is Issue 27 recurring — a findability glow
# that outlived the art it stood in for.
#
# So `glows` now gates only the LEVER INDICATOR, at a fraction of its old energy,
# because red-vs-green is real state feedback ("did I already flip this?") rather
# than an affordance. The panel never self-illuminates any more, in either mode.
@export var glows: bool = true

# Matches beartrap.gd's documented ceiling: above ~0.12 a small emissive prop stops
# reading as a lit indicator and starts reading as white paper glowing in the dark.
const INDICATOR_EMISSION := 0.12

var _done: bool = false
var _lever: CSGBox3D
var _lever_mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build()


const PANEL_TEX := "res://assets/textures/level_1_lab/lab_breaker_panel.png"


func _build() -> void:
	var panel := CSGBox3D.new()
	panel.size = Vector3(0.7, 1.0, 0.12)
	var pm := StandardMaterial3D.new()
	if ResourceLoader.exists(PANEL_TEX):
		# The fuse-box art reads as a real electrical panel instead of a grey box.
		# Lit ONLY by the room — no emission branch here at all (see `glows` above).
		# The source art is a bright mid-grey photo, so it is knocked down with an
		# albedo tint as well; at full brightness it still out-read the walls.
		pm.albedo_texture = load(PANEL_TEX)
		pm.albedo_color = Color(0.6, 0.6, 0.62)
		pm.roughness = 0.85
	else:
		pm.albedo_color = Color(0.18, 0.18, 0.2)
		pm.metallic = 0.6
		pm.roughness = 0.5
	panel.material = pm
	add_child(panel)

	_lever = CSGBox3D.new()
	_lever.size = Vector3(0.12, 0.26, 0.12)
	_lever.position = Vector3(0.22, 0.0, 0.1)
	_lever_mat = StandardMaterial3D.new()
	_lever_mat.albedo_color = Color(0.8, 0.1, 0.05)
	if glows:
		_lever_mat.emission_enabled = true
		_lever_mat.emission = Color(0.7, 0.05, 0.02)
		_lever_mat.emission_energy_multiplier = INDICATOR_EMISSION
	_lever.material = _lever_mat
	add_child(_lever)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.8, 1.1, 0.3)
	col.shape = shape
	add_child(col)


# Put it in the already-thrown state without the clunk or the signal. Used when a
# level restores a saved snapshot (GameState.level_progress) — the player flipped this
# breaker before walking back a level, so it must come back green, not fresh.
func set_already_flipped() -> void:
	if _done:
		return
	_done = true
	_lever.position.y = -0.14
	_lever_mat.albedo_color = Color(0.1, 0.8, 0.2)
	if glows:
		_lever_mat.emission = Color(0.05, 0.7, 0.1)


func is_flipped() -> bool:
	return _done


func interact() -> void:
	if _done:
		return
	_done = true
	var t := create_tween()
	t.tween_property(_lever, "position:y", -0.14, 0.18)
	_lever_mat.albedo_color = Color(0.1, 0.8, 0.2)
	if glows:
		_lever_mat.emission = Color(0.05, 0.7, 0.1)
	var clunk := GameState.load_audio("breaker_throw")
	if not clunk:
		clunk = GameState.load_audio("light_pop")
	if clunk:
		var p := AudioStreamPlayer3D.new()
		p.stream = clunk
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
	flipped.emit()
