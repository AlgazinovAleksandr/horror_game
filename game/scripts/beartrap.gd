extends Area3D
class_name Beartrap

# Floor trap. Stepping in springs the jaws and starts a 7-second escape window:
# press E 7 times to wrench free with only a 15-panic cost. Fail and 40 more panic
# lands on top — 55 total pushes you past PANIC_MAX and the screamer takes you.
# Builds its own meshes so corridor.gd only has to place it.

const ESCAPE_TIME := 7.0
const ESCAPE_PRESSES_NEEDED := 7
const ESCAPE_INITIAL_PANIC := 15.0  # on spring — survivable alone
const ESCAPE_FAIL_PANIC := 40.0     # on timeout — 55 total > PANIC_MAX
const JAW_OPEN_DEG := 75.0

var _sprung: bool = false
var _escaping: bool = false
var _escape_timer: float = 0.0
var _escape_presses: int = 0
var _body_ref: Node3D = null

var _jaw_l: MeshInstance3D
var _jaw_r: MeshInstance3D
var _snap_player: AudioStreamPlayer3D

var _ui: CanvasLayer = null
var _bar: ColorRect = null
var _press_label: Label = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_build_visuals()

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.32
	shape.height = 0.4
	col.shape = shape
	col.position.y = 0.2
	add_child(col)

	_snap_player = AudioStreamPlayer3D.new()
	var snap := GameState.load_audio("beartrap_snap")
	if snap:
		_snap_player.stream = snap
	_snap_player.unit_size = 6.0
	add_child(_snap_player)
	


# ⚠️ BACKLOG #18: "the beartraps look weird." They did. The whole prop was a 3 cm-thin
# CylinderMesh disc plus TWO FLAT RECTANGLES on hinges — no teeth, no springs, no
# pressure pan, no chain. Viewed from standing height, which is the only angle a player
# ever sees a floor trap from, that reads as two bits of card lying on the ground.
#
# Rebuilt as real geometry, following the rule Issue 35 cost this project a session to
# learn: in a game with no glow, no tonemapping and ~0.45 light energy, SILHOUETTE
# carries a prop and art does not. A photo of a beartrap on a flat disc would read as a
# sticker on the floor for exactly the same reason kontur_panel_mailboxes.png read as a
# poster. So the shape is modelled and the textures only supply surface grain.
#
# Emission stays at 0.12 — the documented ceiling for this prop (CLAUDE.md), and it is
# there so the trap is barely catchable in peripheral vision, not so it is findable.
# Anything higher and it reads as white paper in the dark.
const PLATE_R := 0.30
const PAN_R := 0.17
const JAW_SEGMENTS := 7
const JAW_SPAN_DEG := 150.0
const TOOTH_H := 0.075


func _build_visuals() -> void:
	var metal := _metal_material("res://assets/textures/shared/rusted_iron.png",
		Color(0.42, 0.36, 0.30))
	var dark := _metal_material("", Color(0.20, 0.18, 0.17))
	# Albedo is the safe knob here: emission is capped at 0.12 for this prop, and at
	# ~0.45 scene light a 0.20 tint over a dark rust photo renders as a black disc.
	var plate_mat := _metal_material("res://assets/textures/shared/beartrap_plate.png",
		Color(0.55, 0.50, 0.44))

	# Base plate — an actual plate, ~5x thicker than the old disc so it has an edge.
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = PLATE_R
	base_mesh.bottom_radius = PLATE_R
	base_mesh.height = 0.045
	base_mesh.radial_segments = 24
	base.mesh = base_mesh
	base.position.y = 0.022
	base.set_surface_override_material(0, plate_mat)
	add_child(base)

	# Raised rim, so the plate has a lip rather than a knife edge.
	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = PLATE_R - 0.03
	rim_mesh.outer_radius = PLATE_R + 0.01
	rim.mesh = rim_mesh
	rim.position.y = 0.05
	rim.set_surface_override_material(0, metal)
	add_child(rim)

	# The pressure pan the animal actually stands on — the reason the thing goes off,
	# and the single detail that most makes it read as a trap rather than a hubcap.
	var pan := MeshInstance3D.new()
	var pan_mesh := CylinderMesh.new()
	pan_mesh.top_radius = PAN_R
	pan_mesh.bottom_radius = PAN_R
	pan_mesh.height = 0.02
	pan_mesh.radial_segments = 16
	pan.mesh = pan_mesh
	pan.position.y = 0.058
	pan.set_surface_override_material(0, dark)
	add_child(pan)

	# Two coil springs either side, stacked rings — cheap, and unmistakable in profile.
	for sx in [-1.0, 1.0]:
		for i in 4:
			var coil := MeshInstance3D.new()
			var cm := TorusMesh.new()
			cm.inner_radius = 0.030
			cm.outer_radius = 0.055
			coil.mesh = cm
			coil.position = Vector3(sx * (PLATE_R - 0.04), 0.05 + i * 0.022, 0.0)
			coil.rotation_degrees.z = 90.0
			coil.set_surface_override_material(0, metal)
			add_child(coil)

	# Chain + ground stake. A beartrap that is not anchored is a hoop; the chain is what
	# says "you are not walking away with this".
	for i in 5:
		var link := MeshInstance3D.new()
		var lm := TorusMesh.new()
		lm.inner_radius = 0.018
		lm.outer_radius = 0.036
		link.mesh = lm
		link.position = Vector3(0.0, 0.03, -(PLATE_R + 0.08 + i * 0.11))
		link.rotation_degrees = Vector3(90.0, 0.0, 90.0 * float(i % 2))
		link.set_surface_override_material(0, metal)
		add_child(link)
	var stake := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.022
	sm.bottom_radius = 0.012
	sm.height = 0.20
	stake.mesh = sm
	stake.position = Vector3(0.0, 0.07, -(PLATE_R + 0.66))
	stake.set_surface_override_material(0, dark)
	add_child(stake)

	_jaw_l = _build_jaw(metal, dark, -1.0)
	_jaw_r = _build_jaw(metal, dark, 1.0)


func _metal_material(tex_path: String, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.metallic = 0.75
	m.roughness = 0.55
	# Guarded, and the fallback is a real material rather than an untextured white —
	# ResourceLoader.exists() returns TRUE for a .png whose import FAILED (Issue 25),
	# so load() is allowed to come back null and we check that too.
	if tex_path != "" and ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path)
		if tex:
			m.albedo_texture = tex
			m.uv1_scale = Vector3(1.0, 1.0, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.15, 0.17, 0.21)
	m.emission_energy_multiplier = 0.12   # ceiling — above this it reads as white paper
	return m


# An arc of segments with a tooth on each, rather than one flat plate. The arc is what
# makes the closed trap read as a mouth: the two jaws meet as interlocking curves and
# the teeth pass each other instead of butting flat.
#
# ⚠️ Geometry that looks obviously right and is not: the hinge must sit at the trap's
# CENTRE, not out at the rim. Hinging at the rim makes the arc wrap AROUND the pivot,
# so rotating it just spins a ring in place and the jaws stay flat on the plate — which
# is exactly how the first rebuild rendered (screenshot: teeth scattered round the rim,
# no mouth). With the pivot at the centre, each jaw is a half-ring lying on one side of
# the hinge axis, and rotating about X swings it up and outward like a clamshell.
func _build_jaw(metal: StandardMaterial3D, dark: StandardMaterial3D, side: float) -> MeshInstance3D:
	var hinge := Node3D.new()
	hinge.position = Vector3(0, 0.05, 0)          # trap centre — see the note above
	# ⚠️ NEGATIVE side. A rotation of +θ about X maps a point at +z to y = -z·sin θ,
	# i.e. it swings the jaw DOWN through the base plate — which rendered as a trap with
	# no jaws at all, the teeth hidden under the disc. The jaws must open upward.
	hinge.rotation_degrees.x = -side * JAW_OPEN_DEG
	add_child(hinge)

	# The node the close-tween and the escape UI look up. It stays the jaw's own root
	# so _on_body_entered()'s `jaw_mesh.get_parent()` still finds the hinge.
	var jaw := MeshInstance3D.new()
	jaw.mesh = null                     # the arc is built from children below
	hinge.add_child(jaw)

	var arc_r := PLATE_R - 0.015
	for i in JAW_SEGMENTS:
		var t := float(i) / float(JAW_SEGMENTS - 1)          # 0..1 across the arc
		var ang := deg_to_rad(-JAW_SPAN_DEG * 0.5 + JAW_SPAN_DEG * t)
		# Half-ring on ONE side of the hinge axis: z keeps `side`'s sign, so the left
		# and right jaws bow away from each other and the rotation lifts them apart.
		var x := sin(ang) * arc_r
		var z := side * cos(ang) * arc_r

		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.075, 0.030, 0.038)
		seg.mesh = bm
		seg.position = Vector3(x, 0.0, z)
		seg.rotation.y = -ang
		seg.set_surface_override_material(0, metal)
		jaw.add_child(seg)

		# Teeth stand off the arc along the jaw's own +Y, so they point straight up when
		# the trap is set and inward when it snaps. Alternating lengths, plus a half-
		# tooth offset between the two jaws, so closed they interlock instead of butting.
		var tooth := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.004
		tm.bottom_radius = 0.020
		tm.height = TOOTH_H * (1.0 if i % 2 == 0 else 0.72)
		tm.radial_segments = 6
		tooth.mesh = tm
		tooth.position = Vector3(x, tm.height * 0.5 + 0.012, z + side * 0.010)
		tooth.set_surface_override_material(0, dark)
		jaw.add_child(tooth)

	return jaw


func _on_body_entered(body: Node3D) -> void:
	if _sprung or not body.has_method("add_panic"):
		return
	_sprung = true
	_body_ref = body

	if _snap_player.stream:
		_snap_player.play()
	if body.has_method("jolt_camera"):
		body.jolt_camera(0.09, 0.5)
	body.add_panic(ESCAPE_INITIAL_PANIC)
	body.apply_slow(ESCAPE_TIME + 1.0)  # keep player barely moving during escape window

	for jaw_mesh in [_jaw_l, _jaw_r]:
		var hinge: Node3D = jaw_mesh.get_parent()
		var tween := create_tween()
		tween.tween_property(hinge, "rotation_degrees:x", 0.0, 0.07) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)

	_start_escape()


func _start_escape() -> void:
	_escaping = true
	_escape_timer = ESCAPE_TIME
	_escape_presses = 0
	# Mark the player busy WITHOUT freezing input — the limp-and-look is the beartrap's
	# design. This is only so ApparitionDirector and JournalUI can see the QTE; the
	# protection they both document did not exist before (GAME_MECHANICS_IDEAS §3(e)).
	if _body_ref and _body_ref.has_method("begin_qte"):
		_body_ref.begin_qte()
	_build_escape_ui()


func _process(delta: float) -> void:
	if not _escaping:
		return

	_escape_timer -= delta
	_update_escape_ui()

	if Input.is_action_just_pressed("interact"):
		_escape_presses += 1
		# Replay snap at low volume for each press — ratcheting sound
		if _snap_player.stream:
			_snap_player.volume_db = -18.0
			_snap_player.play()
		if _escape_presses >= ESCAPE_PRESSES_NEEDED:
			_escape_success()
			return

	if _escape_timer <= 0.0:
		_escape_fail()


func _escape_success() -> void:
	_escaping = false
	_drop_ui()
	_end_qte()
	if _body_ref and _body_ref.has_method("cancel_slow"):
		_body_ref.cancel_slow()


func _escape_fail() -> void:
	_escaping = false
	_drop_ui()
	# Cleared BEFORE the panic hit: add_panic() can fire the screamer at >= PANIC_MAX,
	# and the flag must not survive into the reloaded scene's fairness checks.
	_end_qte()
	if _body_ref and _body_ref.has_method("add_panic"):
		_body_ref.add_panic(ESCAPE_FAIL_PANIC)


func _end_qte() -> void:
	if _body_ref and is_instance_valid(_body_ref) and _body_ref.has_method("end_qte"):
		_body_ref.end_qte()


func _drop_ui() -> void:
	if _ui:
		_ui.queue_free()
		_ui = null
		_bar = null
		_press_label = null


func _build_escape_ui() -> void:
	_ui = CanvasLayer.new()
	get_parent().add_child(_ui)

	# Timer bar background — anchored to bottom centre
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.1, 0.0, 0.0, 0.85)
	bar_bg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar_bg.offset_top = -95
	bar_bg.offset_bottom = -65
	bar_bg.offset_left = -205
	bar_bg.offset_right = 205
	_ui.add_child(bar_bg)

	# Timer bar fill — shrinks rightward as time runs out
	_bar = ColorRect.new()
	_bar.color = Color(0.85, 0.12, 0.08, 1.0)
	_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.add_child(_bar)

	# Press counter / instruction label
	_press_label = Label.new()
	_press_label.text = "TRAPPED — PRESS [E] TO ESCAPE  (0 / %d)" % ESCAPE_PRESSES_NEEDED
	_press_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.85))
	_press_label.add_theme_font_size_override("font_size", 22)
	_press_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_press_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_press_label.offset_top = -140
	_press_label.offset_bottom = -98
	_press_label.offset_left = -350
	_press_label.offset_right = 350
	_ui.add_child(_press_label)


func _update_escape_ui() -> void:
	if not _bar or not _press_label:
		return
	var ratio := clampf(_escape_timer / ESCAPE_TIME, 0.0, 1.0)
	_bar.anchor_right = ratio
	_press_label.text = "TRAPPED — PRESS [E] TO ESCAPE  (%d / %d)" % \
		[_escape_presses, ESCAPE_PRESSES_NEEDED]
