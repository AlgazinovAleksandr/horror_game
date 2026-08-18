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

# ⚠️ Set true by a level whose breaker is PHYSICALLY SEALED behind something else — the
# Lab's Records locker is the only user. While true the breaker is completely inert:
# player.gd:_update_interact_prompt() consults the optional can_interact() before it will
# show "Press E" *or* set its interact target, so E does literally nothing.
#
# This exists because a cover is not a gate. Measured on the build before it: uniform
# 0.45 m lurches left 43 % of the panel exposed after one bar of three and all of it after
# two, so the three-stage gate opened at stage one and the playtester found it immediately
# ("Even though I did not pull the case till the end, I still could flip the breaker").
#
# ⚠️ And a flag alone is not enough either. On the NEXT replay the same player reported the
# opposite complaint — the gate held, and a panel in plain sight that refuses to answer E
# read as a bug rather than as a locked door ("I should not see it fully once I do all 3
# out of 3"). Both halves are needed and they are different mechanisms: `LabLocker` now
# front-loads its travel onto the last bar so the panel is INVISIBLE until the gate opens,
# and this flag decides what you can DO. See ISSUES_SOLUTIONS Issue 57 + its amendment.
@export var blocked: bool = false

# Matches beartrap.gd's documented ceiling: above ~0.12 a small emissive prop stops
# reading as a lit indicator and starts reading as white paper glowing in the dark.
const INDICATOR_EMISSION := 0.12

var _done: bool = false
var _lever: CSGBox3D
var _lever_mat: StandardMaterial3D
var _pilot_mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build()


const PANEL_TEX := "res://assets/textures/level_1_lab/lab_breaker_panel.png"

# Albedo tint on the panel art. The dim one is for `glows = false` — a breaker that is
# meant to be genuinely invisible in the dark (BreakerNook), and which the player is never
# allowed to see anyway because the wing force-locks the flashlight. It costs nothing to
# find by torchlight later, and it buys margin against a brighter display than this one.
#
# ⚠️ 2026-08-16: neither of these was the real leak. `lab_breaker_panel.png` shipped as an
# opaque RGB PNG whose background was a BAKED ALPHA CHECKERBOARD — near-white pixel data
# that no engine can know is meant to be nothing, and near-white is the brightest albedo
# possible in a level lit at ~0.45 energy with no tonemapping. Measured across the pitch
# black wing, torch locked: the panel's brightest pixels were 4.1/255 against a wall
# averaging 0.3/255, at 6, 10 AND 15 m alike, and ~9 % of its pixels were brighter than
# anything in the wall around it. The player photographed it from 9.4 m. It is flattened
# in the source art now (`tools/flatten_alpha_checker.py`); see ISSUES_SOLUTIONS Issue 63.
const PANEL_TINT := Color(0.6, 0.6, 0.62)
const PANEL_TINT_DIM := Color(0.28, 0.28, 0.29)


func _build() -> void:
	var panel := CSGBox3D.new()
	panel.name = "Panel"
	panel.size = Vector3(0.7, 1.0, 0.12)
	var pm := StandardMaterial3D.new()
	if ResourceLoader.exists(PANEL_TEX):
		# The fuse-box art reads as a real electrical panel instead of a grey box.
		# Lit ONLY by the room — no emission branch here at all (see `glows` above).
		# The source art is a bright mid-grey photo, so it is knocked down with an
		# albedo tint as well; at full brightness it still out-read the walls.
		pm.albedo_texture = load(PANEL_TEX)
		pm.albedo_color = PANEL_TINT if glows else PANEL_TINT_DIM
		pm.roughness = 0.85
	else:
		pm.albedo_color = Color(0.18, 0.18, 0.2)
		pm.metallic = 0.6
		pm.roughness = 0.5
	panel.material = pm
	add_child(panel)

	# The handle is a HANDLE — dark moulded plastic, never the state colour. It used to
	# BE the indicator: a saturated red 0.12 x 0.26 x 0.12 block glued to the front of a
	# photographic panel, which is what playtest captures #3 and #4 both photographed.
	# A lever is a silhouette (Issue 35); the state lives in the pilot lamp below it.
	_lever = CSGBox3D.new()
	_lever.size = Vector3(0.05, 0.20, 0.05)
	_lever.position = Vector3(0.22, 0.0, 0.105)
	_lever_mat = StandardMaterial3D.new()
	_lever_mat.albedo_color = Color(0.11, 0.11, 0.12)
	_lever_mat.roughness = 0.6
	_lever.material = _lever_mat
	add_child(_lever)
	# A collar at the base, so the handle reads as something mounted through the panel
	# rather than a stick balanced on it.
	var collar := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.055
	cm.height = 0.03
	collar.mesh = cm
	collar.rotation.x = PI / 2.0
	collar.position = Vector3(0.22, 0.0, 0.07)
	var collar_mat := StandardMaterial3D.new()
	collar_mat.albedo_color = Color(0.16, 0.16, 0.17)
	collar_mat.metallic = 0.5
	collar_mat.roughness = 0.5
	collar.set_surface_override_material(0, collar_mat)
	add_child(collar)

	_build_pilot_lamp()

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.8, 1.1, 0.3)
	col.shape = shape
	add_child(col)


# A recessed pilot lamp above the handle: a dark bezel standing proud of the panel with
# the coloured lens sunk ~2 cm inside it. That recess is the whole point — the old flat
# emissive block read as a sticker on a photograph from any angle, whereas a lens down a
# barrel only shows its colour when you are roughly in front of it, which is exactly when
# "did I already throw this one?" is the question you are asking.
#
# ⚠️ The emission stays on the LENS alone, at INDICATOR_EMISSION, and only when `glows`.
# The panel and the handle never self-illuminate in either mode (Issues 21/27/33).
func _build_pilot_lamp() -> void:
	var bezel := MeshInstance3D.new()
	bezel.name = "PilotBezel"
	var bm := CylinderMesh.new()
	bm.top_radius = 0.035
	bm.bottom_radius = 0.038
	bm.height = 0.03
	bezel.mesh = bm
	bezel.rotation.x = PI / 2.0
	bezel.position = Vector3(0.22, 0.22, 0.072)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.09, 0.09, 0.10)
	bmat.metallic = 0.4
	bmat.roughness = 0.55
	bezel.set_surface_override_material(0, bmat)
	add_child(bezel)

	var lens := MeshInstance3D.new()
	lens.name = "PilotLens"
	var lm := CylinderMesh.new()
	lm.top_radius = 0.022
	lm.bottom_radius = 0.022
	lm.height = 0.012
	lens.mesh = lm
	lens.rotation.x = PI / 2.0
	lens.position = Vector3(0.22, 0.22, 0.062)   # sunk behind the bezel's front lip
	_pilot_mat = StandardMaterial3D.new()
	_pilot_mat.albedo_color = Color(0.30, 0.05, 0.03)   # dark red glass, not red paint
	_pilot_mat.roughness = 0.3
	if glows:
		_pilot_mat.emission_enabled = true
		_pilot_mat.emission = Color(0.7, 0.05, 0.02)
		_pilot_mat.emission_energy_multiplier = INDICATOR_EMISSION
	lens.set_surface_override_material(0, _pilot_mat)
	add_child(lens)


# Red -> green on the lens. Kept in one place so interact() and set_already_flipped()
# cannot drift apart.
func _pilot_green() -> void:
	if not _pilot_mat:
		return
	_pilot_mat.albedo_color = Color(0.04, 0.30, 0.08)
	if glows:
		_pilot_mat.emission = Color(0.05, 0.7, 0.1)


# player.gd asks this before showing a prompt or setting an interact target. See `blocked`.
func can_interact() -> bool:
	return not blocked


# The level calls this when whatever was sealing the panel has finished moving.
func unblock() -> void:
	blocked = false


# Put it in the already-thrown state without the clunk or the signal. Used when a
# level restores a saved snapshot (GameState.level_progress) — the player flipped this
# breaker before walking back a level, so it must come back green, not fresh.
func set_already_flipped() -> void:
	if _done:
		return
	_done = true
	_lever.position.y = -0.14
	_pilot_green()


func is_flipped() -> bool:
	return _done


func interact() -> void:
	if _done or blocked:
		return
	_done = true
	var t := create_tween()
	t.tween_property(_lever, "position:y", -0.14, 0.18)
	_pilot_green()
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
