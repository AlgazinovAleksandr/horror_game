extends Node3D
class_name ContainmentCell

# ⭐ OBJECT 12, CONTAINED.
#
# THE LEVEL IS CALLED "OBJECT 12" AND THE PLAYER NEVER SEES OBJECT 12. The next level,
# `level_6_breach.gd`, is *Object 12, loose* — so KONTUR is the one place in the game where
# the thing the whole facility was built around is still behind glass, and it was simply
# absent. This is a steel-and-glass isolation booth standing in the Passage, with the
# Breach's own creature inside it.
#
# ⚠️ IT HAS NO RULES AT ALL — the `watcher.gd` contract, verbatim: no `ScaryObject`, no
# gaze panic, no kill radius, no `Screamer`, no trigger volume, no fail state, and it adds
# ZERO panic. It does not move, it cannot be opened, and it cannot be interacted with. All
# it does is turn its head to follow you, and that is the whole feature.
#
# ⚠️ IT MUST NEVER BECOME A PURSUER. `SCARY.md` §8.4 is "one chase level in twelve" and
# that level is 6. The booth's collider is the only physical thing here; the occupant has
# none. If a future session wants this to open, it is a new level, not an edit.
#
# ⚠️ IT USES `Void_creature.glb` AND `creature_object12.gd`'s PALETTE — HUE SHARED, LEVEL
# SCALED (revised 2026-08-18). Meeting it here and being hunted by it one level later have
# to be recognisably the same thing, so `SPECIMEN_ALBEDO` and `SPECIMEN_EMISSION_COLOR`
# are that script's colours verbatim and are not to be re-picked. What is NOT shared is the
# LEVEL, and the reason is a measurement rather than taste:
#
#   The Breach meets this creature across a lit facility. KONTUR meets it at 1.5 m with a
#   1.2-energy torch on it, in a room lit at 0.45. Rendered from thirteen reachable
#   headings, the shipped material put the occupant at 0.21-0.23 mean luminance against a
#   background of 0.08-0.12 and the booth's own steel at 0.048-0.057 — i.e. 1.8-2.8x
#   brighter than what was behind it and 4.1-4.5x brighter than the cell around it, with
#   the top 1 % of its pixels at 0.30-0.48 and a specular hotspot clipping to 0.98. It
#   rendered as a pale man in a suit and was the brightest object in the Passage.
#
# So `SPECIMEN_DIM` scales the albedo, `SPECIMEN_EMISSION` scales the energy, and
# `specular` is taken to 0 — a dielectric's specular lobe is NOT scaled by albedo, so
# darkening alone leaves the hotspot exactly where it was. Set them all to 1.0 / 0.35 /
# 0.5 and the file is byte-equivalent to the Breach's; the numbers are one edit.
#
# ⚠️ AND DARKENING ALONE CANNOT WORK — it was measured and it is the more useful half of
# this. Sweeping the albedo scale down, the occupant reaches parity with its background at
# ~0.30 and passes under it at ~0.22 — but the measured CONTRAST at those points is
# 0.006-0.09, i.e. the figure becomes invisible before it becomes dark. `watcher.gd`'s
# premise is "a dark shape OCCLUDING A LIT SURFACE" and this booth had no lit surface in
# it. The three interior faces the player can never reach are now BACKLIT liners, so the
# figure has something to be dark against from each of the three headings it is seen from.
# ⚠️ Emission does not illuminate anything in this project (no GI, no glow), so a liner
# raises the BACKGROUND without touching the figure. That is the whole reason it works.

const GLB_PATH := "res://assets/models/Void_creature.glb"

const SIZE := Vector2(2.0, 2.0)   # footprint, x by z
const HEIGHT := 2.6
const POST := 0.12
const GLASS_T := 0.035

# ---- the observation port -------------------------------------------------------------
# ⚠️ THE DOOR IS THE FACE THE PLAYER ARRIVES ON. `_spawn_containment_cell()` turns the
# booth to look back down the spine, so the first thing anyone walking in from the
# antechambers sees is this leaf — and until 2026-08-18 it was 1.74 x 2.36 m of unbroken
# flat steel. Measured over thirteen reachable headings, SIX of them (the whole 165-210
# degree arc, at both 2.0 and 3.2 m) rendered ZERO pixels of the occupant: the level's one
# look at Object 12 was invisible from the direction it was staged for. The leaf is now
# four slabs around a glazed port, which is also what breaks up the torch hotspot that made
# a dark door photograph as a luminous white panel.
const PORT_W := 1.32              # leaf is 1.74 wide -> 0.21 m stiles
const PORT_Y0 := 1.30
const PORT_Y1 := 2.25

# Backlit interior liners (see the header). Dark albedo, because emission is most of a
# surface's colour here and a pale albedo under them would blow out (Issue 21).
const LINER_ALBEDO := Color(0.05, 0.055, 0.052)
const LINER_EMISSION := Color(0.60, 0.66, 0.64)
const LINER_ENERGY := 0.16
# ⚠️ THE NORTH BACKDROP IS ONE-SIDED, AND IT HAS TO BE. The north face is the only one
# that is both a backdrop (what a player at the port sees the occupant against) and a
# window (what a player at the north end of the Passage sees it through). The first build
# made it a FROSTED, backlit pane, which is the obvious answer and is wrong: an
# alpha-blended surface lays its emission over everything behind it, so from the north the
# same veil landed on the figure AND on the wall behind it. Measured, the occupant went to
# 0.39-0.47 against a background of 0.40-0.48 — a contrast of 1-3 %, i.e. the fix made the
# occupant invisible from four headings it had been perfectly visible from, and lifted the
# whole frame's mean luminance 0.05 -> 0.25 in a level that is meant to be dark.
# It is now a `QuadMesh` with `CULL_BACK` whose normal faces the port: drawn from the
# south, culled entirely from the north. The pane in front of it is ordinary clear glass.
const BACKLIT_ENERGY := 0.18
const BACKLIT_INSET := 0.90       # z of the panel, clear of PaneN's near face at 0.9475

# Yaw only, and slowly. A head that snaps is a creature with a rule; a head that takes a
# second to come round is a thing that noticed you.
const TRACK_RATE := 0.9           # radians per second
const TRACK_RANGE := 26.0

# Derived from the file's MEASURED level, not from taste: `object12_cell.wav` is
# -10.87 dBFS RMS (tools/make_sfx_kontur_extra.py prints it), which is 6.8 dB HOTTER than
# `breathing_behind` and 0.8 dB hotter than `door_seal`. At -18 it sits ~11 dB under the
# level's own breath loop, i.e. a bearing you notice rather than a sound you hear.
const HUM_DB := -18.0
const HUM_UNIT := 7.0

var _occupant: Node3D
var _occupant_material: StandardMaterial3D
var _player: CharacterBody3D
var _yaw: float = 0.0


# ---- the specimen's palette -----------------------------------------------------------
# `creature_object12.gd:_apply_retint()`'s colours, verbatim. Do not re-pick them.
const SPECIMEN_ALBEDO := Color(0.35, 0.4, 0.32)
const SPECIMEN_EMISSION_COLOR := Color(0.4, 0.05, 0.05)
# ...and the three numbers that are this level's, not the Breach's. 1.0 / 0.35 / 0.5 makes
# the material byte-equivalent to the Breach's; see the header for what that measured.
const SPECIMEN_DIM := 0.45             # albedo scale
const SPECIMEN_EMISSION := 0.16        # emission energy (the Breach's is 0.35)
const SPECIMEN_SPECULAR := 0.0


func _specimen_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(SPECIMEN_ALBEDO.r * SPECIMEN_DIM,
		SPECIMEN_ALBEDO.g * SPECIMEN_DIM, SPECIMEN_ALBEDO.b * SPECIMEN_DIM)
	m.roughness = 0.9
	# ⚠️ A dielectric's specular is NOT scaled by albedo. At `SPECIMEN_DIM` 0.10 the
	# occupant's mean luminance had fallen by 56 % and its peak was still 0.98 — the
	# hotspot the player photographed on its chest survives any amount of darkening.
	m.metallic_specular = SPECIMEN_SPECULAR
	m.emission_enabled = true
	m.emission = SPECIMEN_EMISSION_COLOR
	m.emission_energy_multiplier = SPECIMEN_EMISSION   # under 1.0 — Issue 21
	return m


# Test surface. `check_kontur_entities.gd` asserts that every renderable in the occupant
# carries this one material, which is the regression guard for "the override reached some
# of the meshes and the rest rendered as a man in a suit".
func occupant_material() -> StandardMaterial3D:
	return _occupant_material


func _ready() -> void:
	_build_shell()
	_build_occupant()
	_build_audio()


# ---------------------------------------------------------------- the booth

func _build_shell() -> void:
	var steel := _mat(Color(0.115, 0.120, 0.112), 0.15, 0.7)
	var trim := _mat(Color(0.075, 0.080, 0.075), 0.2, 0.6)
	var hazard := _mat(Color(0.32, 0.26, 0.06), 0.0, 0.85)

	var hx: float = SIZE.x / 2.0
	var hz: float = SIZE.y / 2.0

	_box("Plinth", Vector3(SIZE.x + 0.14, 0.16, SIZE.y + 0.14), Vector3(0, 0.08, 0), trim)
	_box("Cap", Vector3(SIZE.x + 0.14, 0.14, SIZE.y + 0.14), Vector3(0, HEIGHT + 0.07, 0), trim)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box("Post", Vector3(POST, HEIGHT, POST),
				Vector3(sx * (hx - POST / 2.0), HEIGHT / 2.0, sz * (hz - POST / 2.0)), steel)

	# ⚠️ The glass is INSET 0.02 from the posts on every edge. Two visible surfaces in one
	# plane is this project's most common bug class (Issues 19/20/23/24/25/26), and a pane
	# flush against a post is exactly that — with the added misery that one of the two is
	# transparent, so the fight is invisible in a still and obvious in motion.
	var glass := _glass_mat()
	var liner := _liner_mat()
	var pane_w: float = SIZE.x - 2.0 * POST - 0.04
	var pane_z: float = SIZE.y - 2.0 * POST - 0.04
	var pane_h: float = HEIGHT - 0.30
	var pane_y: float = 0.16 + pane_h / 2.0
	_box("PaneN", Vector3(pane_w, pane_h, GLASS_T),
		Vector3(0, pane_y, hz - GLASS_T), glass)
	# ...and the one-sided backlit panel standing just inside it. See BACKLIT_ENERGY.
	_backlit_panel("LinerNorth", Vector2(pane_w, pane_h),
		Vector3(0, pane_y, BACKLIT_INSET), PI)
	# West: the clear viewing window, on the side the walking line runs down.
	_box("PaneWest", Vector3(GLASS_T, pane_h, pane_z),
		Vector3(-(hx - GLASS_T), pane_y, 0), glass)
	# ⚠️ EAST IS AN OPAQUE BACKLIT LINER, NOT GLASS. The booth's east face stands 0.15 m
	# from the Passage wall — nobody can get behind it, so it is worth more as the lit
	# surface the occupant is a shadow against from the west than as a fourth window.
	_box("LinerEast", Vector3(GLASS_T, pane_h, pane_z),
		Vector3(hx - GLASS_T, pane_y, 0), liner)

	# The door: an opaque steel leaf with an observation port, a wheel, a rail and a
	# hazard placard. It is geometry only — no hinge, no `interact()`, nothing to press.
	var dz: float = -hz + 0.03
	var leaf_w: float = SIZE.x - 2.0 * POST - 0.02
	var leaf_y0: float = 0.16
	var leaf_y1: float = 0.16 + HEIGHT - 0.24
	_port_panels("Door", leaf_w, leaf_y0, leaf_y1, dz, 0.07, steel)
	# ⚠️ THE SOUTH BACKDROP IS THE SAME ONE-SIDED TRICK, MIRRORED, AND THE OBVIOUS BUILD
	# FAILED FOR A REASON WORTH KEEPING. The first version lined the door with a four-slab
	# inner skin carrying the SAME port opening, so that the port still saw through it.
	# Measured, that left the north headings at a contrast of 0.13-0.20 — because the
	# occupant stands at chest height, which is exactly where the hole is: the liner
	# backed the figure everywhere except behind the figure. A single full-height panel
	# facing +z solves both halves at once. It is drawn for anyone at the north end of the
	# Passage and culled for anyone at the port, who therefore still looks straight
	# through the opening at the occupant.
	_backlit_panel("LinerSouth", Vector2(pane_w, pane_h), Vector3(0, pane_y, dz + 0.10), 0.0)

	# The port itself: recessed glass, a proud bead frame, and two bars.
	var port_h: float = PORT_Y1 - PORT_Y0
	var port_y: float = (PORT_Y0 + PORT_Y1) / 2.0
	_box("PortGlass", Vector3(PORT_W, port_h, GLASS_T), Vector3(0, port_y, dz), glass)
	var bead_z: float = dz - 0.055
	_box("PortBeadTop", Vector3(PORT_W + 0.12, 0.06, 0.02),
		Vector3(0, PORT_Y1 + 0.03, bead_z), trim)
	_box("PortBeadBottom", Vector3(PORT_W + 0.12, 0.06, 0.02),
		Vector3(0, PORT_Y0 - 0.03, bead_z), trim)
	for sxb in [-1.0, 1.0]:
		_box("PortBeadSide", Vector3(0.06, port_h + 0.12, 0.02),
			Vector3(sxb * (PORT_W / 2.0 + 0.03), port_y, bead_z), trim)
	# ⚠️ TWO bars, not a grid. Every bar is silhouette taken away from the one thing this
	# prop exists to show; two at 22 mm cost 3.3 % of the opening.
	for sxg in [-1.0, 1.0]:
		_box("PortBar", Vector3(0.022, port_h, 0.022),
			Vector3(sxg * 0.30, port_y, bead_z), trim)

	# ⚠️ THE WHEEL, THE RAIL, THE CHEVRONS AND THE PLACARD ALL MOVED WITH THE PORT. Every
	# one of them used to sit inside what is now the opening — the wheel at y 1.16, the
	# rail straight across at 1.34, the chevron band at 2.16 and the placard at 1.80.
	var wheel := MeshInstance3D.new()
	wheel.name = "DoorWheel"
	var tor := TorusMesh.new()
	tor.inner_radius = 0.11
	tor.outer_radius = 0.16
	wheel.mesh = tor
	wheel.material_override = trim
	wheel.rotation.x = PI / 2.0
	wheel.position = Vector3(0.42, 0.62, dz - 0.09)
	add_child(wheel)
	# ⚠️ Two CROSSED bars in the door's own plane, not four rotated about the wrong axis.
	# The first pass rotated each spoke by (PI/2, 0, a) — Godot composes YXZ, so all four
	# ended up in very nearly the same place and the wheel rendered as a "Ø".
	for a in [0.0, PI / 2.0]:
		_box("WheelSpoke", Vector3(0.30, 0.026, 0.030),
			Vector3(0.42, 0.62, dz - 0.09), trim, Vector3(0, 0, a))
	_box("DoorRail", Vector3(leaf_w, 0.06, 0.10), Vector3(0, 1.14, dz - 0.02), trim)

	# A hazard chevron band and a bilingual placard. Cheap, and it is what says "sealed
	# Soviet facility" rather than "a grey box with a window".
	# ⚠️ The band stands PROUD OF THE BEAD (z -0.085 against -0.055): on the head panel it
	# shares a height band with the port's top bead, and two 12 mm slabs in one plane is
	# this project's most common bug class.
	for i2 in range(7):
		_box("Chevron", Vector3(0.16, 0.10, 0.012),
			Vector3(-0.66 + i2 * 0.22, 2.40, dz - 0.085), hazard, Vector3(0, 0, 0.5))
	var plate := Label3D.new()
	plate.name = "CellPlacard"
	plate.text = "ОБЪЕКТ 12\nOBJECT 12 — CONTAINED\nНЕ ОТКРЫВАТЬ"
	plate.font_size = 44
	plate.pixel_size = 0.00095
	plate.modulate = Color(0.74, 0.72, 0.66)
	plate.outline_size = 0
	plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.position = Vector3(-0.30, 0.90, dz - 0.06)
	plate.rotation.y = PI
	add_child(plate)

	# ⚠️ ONE collider for the whole booth. The occupant has none at all — a collider
	# around the creature would be a thing the player could bump into through glass, and
	# it is also the first step toward it having a rule.
	var body := StaticBody3D.new()
	body.name = "CellBody"
	add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE.x + 0.14, HEIGHT, SIZE.y + 0.14)
	col.shape = shape
	col.position = Vector3(0, HEIGHT / 2.0, 0)
	body.add_child(col)


# ---------------------------------------------------------------- the occupant

func _build_occupant() -> void:
	_occupant = Node3D.new()
	_occupant.name = "Object12"
	_occupant.position = Vector3(0, 0.16, 0.12)
	add_child(_occupant)

	var visual: Node3D
	if ResourceLoader.exists(GLB_PATH):
		var scene: PackedScene = load(GLB_PATH)
		visual = scene.instantiate()
		# Blender adds a stray base cube to the export (creature_object12.gd removes the
		# same one) — keep only the character.
		var cube := visual.get_node_or_null("Cube")
		if cube:
			cube.queue_free()
		_pose_arms_down(visual)
	else:
		# Fallback silhouette, so a missing GLB leaves a shape rather than an empty box.
		visual = Node3D.new()
		var torso := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.16
		cap.height = 2.1
		torso.mesh = cap
		torso.position.y = 1.15
		visual.add_child(torso)
		var head := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.16
		sph.height = 0.32
		head.mesh = sph
		head.position.y = 2.32
		visual.add_child(head)
	_occupant.add_child(visual)

	# `creature_object12.gd`'s palette, scaled for this level's viewing distance — see the
	# header for the measurement, and `SPECIMEN_DIM` for how to put it back.
	_occupant_material = _specimen_mat()
	var applied := 0
	for mi in _mesh_instances(visual):
		mi.material_override = _occupant_material
		applied += 1
	# ⚠️ A GLB WITH ONE MESH TODAY IS NOT A CONTRACT. `Void_creature.glb` currently
	# instantiates a single skinned `WhiteClown` under `Armature/Skeleton3D`, and if a
	# re-export ever splits it, an override that reached only some of the parts would
	# render half a pale man and look like a lighting bug rather than a missing call.
	# `check_kontur_entities.gd` asserts every renderable carries this exact material.
	if applied == 0:
		push_warning("ContainmentCell: no MeshInstance3D to retint — occupant will render raw")


const _ARM_DROP_DEG := 80.0
const _FOREARM_TUCK_DEG := 12.0

func _pose_arms_down(instance: Node3D) -> void:
	var skel := instance.find_child("Skeleton3D", true, false) as Skeleton3D
	if not skel:
		return
	_rotate_bone(skel, "mixamorig_LeftArm", deg_to_rad(_ARM_DROP_DEG))
	_rotate_bone(skel, "mixamorig_RightArm", deg_to_rad(-_ARM_DROP_DEG))
	_rotate_bone(skel, "mixamorig_LeftForeArm", deg_to_rad(_FOREARM_TUCK_DEG))
	_rotate_bone(skel, "mixamorig_RightForeArm", deg_to_rad(-_FOREARM_TUCK_DEG))


func _rotate_bone(skel: Skeleton3D, bone_name: String, angle_z: float) -> void:
	var idx := skel.find_bone(bone_name)
	if idx == -1:
		return
	var rest := skel.get_bone_rest(idx)
	skel.set_bone_pose_rotation(idx,
		rest.basis.get_rotation_quaternion() * Quaternion(Vector3.FORWARD, angle_z))


func _build_audio() -> void:
	var stream := GameState.load_audio("object12_cell")
	if stream == null:
		return
	var pl := AudioStreamPlayer3D.new()
	pl.name = "CellHum"
	pl.stream = stream
	pl.volume_db = HUM_DB
	pl.unit_size = HUM_UNIT
	pl.max_db = 0.0
	pl.position = Vector3(0, 1.2, 0)
	add_child(pl)
	# Every .wav.import here is loop_mode=0, so loops are restarted in code.
	pl.finished.connect(pl.play)
	pl.play()


# ---------------------------------------------------------------- tracking

func _process(delta: float) -> void:
	if _occupant == null:
		return
	if not _player or not is_instance_valid(_player):
		_player = get_node_or_null("../Player") as CharacterBody3D
		if not _player:
			return
	var to := _player.global_position - global_position
	if Vector2(to.x, to.z).length() > TRACK_RANGE:
		return
	var want := atan2(to.x, to.z)
	_yaw = _step_angle(_yaw, want, TRACK_RATE * delta)
	_occupant.rotation.y = _yaw


static func _step_angle(from: float, to: float, max_step: float) -> float:
	var d := wrapf(to - from, -PI, PI)
	return from + clampf(d, -max_step, max_step)


# ---------------------------------------------------------------- helpers

func _mat(albedo: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = rough
	return m


# Four slabs around the observation port — two full-height stiles, a sill and a head. They
# ABUT on the port's edges and never overlap. ⚠️ They cannot trip `check_wall_overlap.gd`
# even though their faces are coincident, and it is worth knowing why: `_faces_fight()`
# only considers a pair that overlaps by more than 0.35 m in BOTH other axes, and a door
# leaf is 0.07 m thick. Give this leaf real depth and the abutment becomes a finding.
func _port_panels(prefix: String, w: float, y0: float, y1: float,
		z: float, thick: float, mat: Material) -> void:
	var hw: float = w / 2.0
	var phw: float = PORT_W / 2.0
	for sx in [-1.0, 1.0]:
		var stile_w: float = hw - phw
		_box(prefix + "Stile", Vector3(stile_w, y1 - y0, thick),
			Vector3(sx * (phw + stile_w / 2.0), (y0 + y1) / 2.0, z), mat)
	_box(prefix + "Sill", Vector3(PORT_W, PORT_Y0 - y0, thick),
		Vector3(0, (y0 + PORT_Y0) / 2.0, z), mat)
	_box(prefix + "Head", Vector3(PORT_W, y1 - PORT_Y1, thick),
		Vector3(0, (PORT_Y1 + y1) / 2.0, z), mat)


# The lit surface the occupant is a shadow against. ⚠️ Emission, not albedo: a pale albedo
# would need a light in the booth, and a light in the booth lights the occupant too, which
# is the one thing that must not happen.
func _liner_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = LINER_ALBEDO
	m.roughness = 0.85
	m.metallic_specular = 0.0
	m.emission_enabled = true
	m.emission = LINER_EMISSION
	m.emission_energy_multiplier = LINER_ENERGY
	return m


# ⚠️ CULL_BACK is doing the work, not the colour. See BACKLIT_ENERGY. A `QuadMesh` faces
# +z, so `y_rot` PI turns it to face the port.
func _backlit_panel(n: String, size: Vector2, pos: Vector3, y_rot: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	var m := _liner_mat()
	m.emission_energy_multiplier = BACKLIT_ENERGY
	m.cull_mode = BaseMaterial3D.CULL_BACK
	mi.material_override = m
	mi.position = pos
	mi.rotation.y = y_rot
	add_child(mi)
	return mi


func _glass_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	# ⚠️ DARK, and no emission. Emission is most of a surface's colour in this project and
	# a lit pane would hide what is behind it, which is the whole prop.
	m.albedo_color = Color(0.10, 0.13, 0.12, 0.20)
	# ⚠️ ROUGHNESS 0.22, NOT 0.08 (2026-08-18). At 0.08 the pane is a mirror and the torch
	# put a near-pinpoint specular glare on it, which — because the player faces the booth
	# head-on — landed ON THE OCCUPANT'S CHEST and was the brightest thing in the frame at
	# 0.90 luminance. It was mistaken for a highlight on the creature twice, and it is not:
	# it survives `metallic_specular = 0` on the occupant, an albedo of pure black, emission
	# off, AND the flashlight switched off entirely (ISSUES_SOLUTIONS Issue 148).
	# Institutional glass is not a mirror; spreading the lobe both dims it and makes the
	# pane read as glass rather than as a hole.
	m.roughness = 0.22
	m.metallic = 0.0
	m.metallic_specular = 0.25
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _box(n: String, size: Vector3, pos: Vector3, mat: Material,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi


func _mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_mesh_instances(c))
	return out
