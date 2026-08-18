extends StaticBody3D
class_name SunkenItem

# THE DROWNED — the Backrooms Flood's searchable content.
#
# Playtest 2026-08-17, J-capture #5, Flood-local (-9.40, 15.80): *"The flood sublevel even
# though looks very cool feels very empty. Maybe we can pack it with more action somehow?"*
# The user chose "add searchable content and events" over the three other offers.
#
# ⚠️ THE DESIGN PROBLEM, AND WHY THIS IS A SOUND AND NOT A GLINT. The Flood is solved by
# standing in the dark: the real exit seam is visible only with the flashlight OFF. Any
# content that can only be FOUND by lighting the room fights that, and content that
# self-illuminates is anti-pattern §5.2(8) (Issues 21/27/33 — "the engine's answer to make
# it stand out in the dark is SILHOUETTE and AUDIO"). So these are found the way the zone
# already asks the player to work: by ear.
#
# Each unsearched item knocks — a dull hollow bump under water, `flood_knock`, at
# `unit_size 6` so it resolves in its own room and only gives a bearing from further off.
# Searching one silences it FOREVER. Six of them are a to-do list you clear by listening,
# and the wing gets measurably quieter as it empties, which is the only progress readout
# here and it is diegetic (§5.2(2) forbids a HUD one).
#
# ⚠️ ZERO PANIC. No `add_panic`, no `ScaryObject`, no gaze term, no fail state, no timer.
# `GAME_MECHANICS_IDEAS.md` §0.2: stop adding panic terms, start adding channels. The only
# cost of searching is the wall-clock it spends against the zone's existing DREAD_DRIP,
# which is measured in `tests/check_flood_drowned.gd` and reported rather than tuned.
#
# ⚠️ SILHOUETTE CARRIES A PROP, ART DOES NOT (Issue 35). Six DIFFERENT objects, each built
# from parts, no textures, no emission: a footlocker with a lid and banding straps, a
# gurney with legs and a sheet, a drawer bank, a suitcase, a tool chest with a lifting
# tray, a wheelchair with real wheels. A flat box reads as a box, and two rounds of
# playtest have photographed exactly that.
#
# ⚠️ THE VISUALS MOVE; THE COLLIDER NEVER DOES (Issue 76, `kitchen_drawer.gd`). Everything
# hangs off `_visual`; the `CollisionShape3D` is a direct child of the body. An interactable
# must not be able to narrow a lane by opening.
#
# Open-then-read, never read-then-open: the note is fired from the lid tween's `finished`
# (Issue 58 — a Tween does not advance while `NoteUI` has the tree paused, so a note shown
# two statements after `create_tween()` appears in front of a lid that has not moved).

# ⚠️ TWO PRESSES SINCE 2026-08-17, and the second one is the point (B-R2). Playtest
# capture 005, standing over the opened drawer bank: *"Why the note appears just after I
# open the cabinet - I need to collect this note"*. It is the same verdict the Lab's
# Records cabinets got a day earlier, and it has the same answer: OPENING IS NOT TAKING.
# Hauling the lid reveals a FRAGMENT lying in the object; a second, separate E lifts it,
# and only then does the page appear.
#
# ⚠️ WHICH OF THE TWO NESTED BODIES ANSWERS THE RAY IS DECIDED BY STATE, NEVER BY AIM —
# `lab_cabinet_drawer.gd:_refresh_layer()`'s rule. Here it is stronger than that, because
# this body is on layer 1 (it is furniture; the player must not walk through a gurney), so
# it cannot be made transparent to the ray the way a layer-2 drawer face can. Instead BOTH
# targets do the same thing when a fragment is present:
#
#     unsearched                  -> the ITEM answers   (E hauls it open)
#     open, fragment inside       -> EITHER answers, and both TAKE THE FRAGMENT
#     open, fragment taken        -> nothing answers    (can_interact() false, inert)
#
# That is deliberate belt-and-braces against Issues 65/66: a press aimed anywhere at an
# open object does the one thing there is to do, and no press can be silently swallowed by
# the wrong collider.
signal searched(item: SunkenItem)
signal piece_taken(item: SunkenItem)

# --- audio ---------------------------------------------------------------------------
#
# ⚠️ GAINS ARE SET FROM THE FILES' MEASURED LEVELS, not from numbers that read as sensible
# (the `water.wav` lesson: -39.6 dBFS shipped at -6 dB and was inaudible for months).
# `tools/make_sfx_flood.py` prints and this file quotes:
#
#     flood_knock.wav   RMS -19.8 dBFS      flood_haul.wav   RMS -15.6 dBFS
#
# The Flood's water bed is -39.6 dBFS at +14.0 dB = -25.6 dBFS at the emitter. The knock at
# -4.0 dB lands at -23.8 dBFS, ~1.8 dB over the bed it has to be heard through; the haul at
# -5.0 dB lands at -20.6 dBFS, the loudest single thing in the wing, which is correct for a
# one-shot the player asked for. `check_flood_drowned.gd` asserts that ORDERING (bed <
# knock < haul) from the sample data, not the constants, so a regenerated asset cannot
# silently invert it.
const KNOCK_DB := -4.0
const HAUL_DB := -5.0
const KNOCK_UNIT := 6.0
const HAUL_UNIT := 8.0
const KNOCK_MIN := 5.0
const KNOCK_MAX := 11.0

const LID_TIME := 0.8

# Palette. Flat-tinted, dark, and NEVER emissive — everything down here is under water in a
# room whose puzzle is about light.
const MAT_STEEL := 0
const MAT_WOOD := 1
const MAT_FABRIC := 2
const MAT_PALE := 3
const MAT_DARK := 4

var kind: String = "footlocker"
var note_text: String = ""

var is_searched: bool = false
var is_taken: bool = false

# The fragment's resting place, in this body's local space. Set by each `_build_*` so it
# sits IN the thing it came out of and — load-bearing — so its grab volume stands proud
# of `_collider_size`. The item's own collider is layer 1 and cannot be turned off, so the
# fragment has to be the FIRST thing a downward-looking ray meets; the item forwarding
# `interact()` is the second line of defence, not the first.
var _piece_at: Vector3 = Vector3.ZERO
var _piece: SunkenPiece = null

var _visual: Node3D = null
var _lid: Node3D = null
var _content: Node3D = null
var _knock: AudioStreamPlayer3D = null
var _knock_timer: float = 0.0
var _zone_active: bool = false
var _lid_open_rot: float = 0.0
var _lid_open_pos: Vector3 = Vector3.ZERO
var _collider_size: Vector3 = Vector3(1, 1, 1)


static func build(parent: Node, item_name: String, item_kind: String, pos: Vector3,
		yaw: float, text: String) -> SunkenItem:
	var s := SunkenItem.new()
	s.name = item_name
	s.kind = item_kind
	s.note_text = text
	parent.add_child(s)
	s.position = pos
	s.rotation.y = yaw
	return s


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_build()
	_build_collider()
	_build_piece()
	_build_knock()
	set_process(true)


# --------------------------------------------------------------------- the six shapes

func _mat(which: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	match which:
		MAT_STEEL:
			m.albedo_color = Color(0.21, 0.23, 0.24)
			m.metallic = 0.55
			m.roughness = 0.55
		MAT_WOOD:
			m.albedo_color = Color(0.17, 0.13, 0.10)
			m.roughness = 0.92
		MAT_FABRIC:
			m.albedo_color = Color(0.24, 0.23, 0.21)
			m.roughness = 1.0
		MAT_PALE:
			m.albedo_color = Color(0.46, 0.44, 0.39)
			m.roughness = 0.95
		_:
			m.albedo_color = Color(0.09, 0.09, 0.10)
			m.roughness = 0.9
	return m


func _part(parent: Node3D, part_name: String, size: Vector3, pos: Vector3,
		which: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(which)
	mi.position = pos
	parent.add_child(mi)
	return mi


# A wheel. ⚠️ `axle_x` is not cosmetic: a `TorusMesh` lies in the XZ plane with its axis on Y,
# so which 90° turn you apply decides which way the thing ROLLS. A wheelchair rolls along its
# own -Z (the footplate end), so its axle is on X; a gurney is 1.86 m long on X and rolls that
# way, so its castors' axle is on Z. Getting it wrong renders a wheelchair whose wheels face
# sideways, which reads as a chair on skids.
func _ring(parent: Node3D, part_name: String, radius: float, thickness: float,
		pos: Vector3, which: int, axle_x: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	var tm := TorusMesh.new()
	tm.inner_radius = maxf(0.01, radius - thickness)
	tm.outer_radius = radius
	tm.rings = 12
	tm.ring_segments = 10
	mi.mesh = tm
	mi.material_override = _mat(which)
	mi.position = pos
	if axle_x:
		mi.rotation.z = PI / 2.0
	else:
		mi.rotation.x = PI / 2.0
	parent.add_child(mi)
	return mi


func _new_lid(pivot: Vector3) -> Node3D:
	_lid = Node3D.new()
	_lid.name = "Lid"
	_lid.position = pivot
	_visual.add_child(_lid)
	return _lid


func _new_content() -> Node3D:
	_content = Node3D.new()
	_content.name = "Content"
	_content.visible = false
	_visual.add_child(_content)
	return _content


func _build() -> void:
	match kind:
		"footlocker": _build_footlocker()
		"gurney": _build_gurney()
		"drawers": _build_drawers()
		"suitcase": _build_suitcase()
		"toolchest": _build_toolchest()
		"wheelchair": _build_wheelchair()
		_: _build_footlocker()


# A steel footlocker: carcass, banding straps, a hasp, and a lid that hinges back.
func _build_footlocker() -> void:
	_collider_size = Vector3(1.00, 0.62, 0.62)
	_piece_at = Vector3(0.10, 0.50, -0.02)
	_part(_visual, "Carcass", Vector3(0.90, 0.40, 0.52), Vector3(0, 0.20, 0), MAT_WOOD)
	_part(_visual, "Plinth", Vector3(0.94, 0.06, 0.56), Vector3(0, 0.03, 0), MAT_STEEL)
	for i in [-1, 1]:
		_part(_visual, "Strap%d" % i, Vector3(0.05, 0.42, 0.56),
			Vector3(0.28 * i, 0.21, 0), MAT_STEEL)
	_part(_visual, "Hasp", Vector3(0.12, 0.10, 0.05), Vector3(0, 0.36, -0.28), MAT_STEEL)
	var lid := _new_lid(Vector3(0, 0.41, 0.26))
	_part(lid, "LidSlab", Vector3(0.94, 0.07, 0.56), Vector3(0, 0.03, -0.28), MAT_WOOD)
	_part(lid, "LidRim", Vector3(0.96, 0.04, 0.06), Vector3(0, 0.00, -0.55), MAT_STEEL)
	_lid_open_rot = -1.75
	var c := _new_content()
	_part(c, "FoldedCloth", Vector3(0.62, 0.12, 0.34), Vector3(0, 0.31, 0), MAT_FABRIC)
	_part(c, "RosterCard", Vector3(0.20, 0.01, 0.14), Vector3(0.18, 0.38, -0.05), MAT_PALE)


# A ward gurney, standing in the water on short legs, with a sheet over it.
# The sheet is the "lid": it slides off the far side.
func _build_gurney() -> void:
	_collider_size = Vector3(1.96, 0.90, 0.76)
	_piece_at = Vector3(0.30, 0.78, 0.00)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_part(_visual, "Leg%d%d" % [sx, sz], Vector3(0.06, 0.46, 0.06),
				Vector3(0.82 * sx, 0.23, 0.28 * sz), MAT_STEEL)
			_ring(_visual, "Castor%d%d" % [sx, sz], 0.09, 0.035,
				Vector3(0.82 * sx, 0.09, 0.28 * sz), MAT_DARK)
	_part(_visual, "Frame", Vector3(1.86, 0.07, 0.68), Vector3(0, 0.49, 0), MAT_STEEL)
	# The mattress stands PROUD of the frame — the thing that makes a bed read as a bed.
	_part(_visual, "Mattress", Vector3(1.76, 0.16, 0.62), Vector3(0, 0.60, 0), MAT_FABRIC)
	_part(_visual, "HeadRail", Vector3(0.06, 0.34, 0.62), Vector3(-0.94, 0.66, 0), MAT_STEEL)
	var lid := _new_lid(Vector3(0, 0.70, 0))
	# The Intro ward's own linen, so the callback is literal: this is that furniture, 200 m
	# down and under water. Falls back to the flat pale tint if the texture is missing.
	var sheet := _part(lid, "Sheet", Vector3(1.70, 0.05, 0.66), Vector3(0, 0, 0), MAT_PALE)
	var linen := "res://assets/textures/intro/sheet_linen.png"
	if ResourceLoader.exists(linen):
		var lm := _mat(MAT_PALE)
		lm.albedo_texture = load(linen)
		lm.albedo_color = Color(0.72, 0.70, 0.66)
		sheet.material_override = lm
	_part(lid, "SheetFold", Vector3(1.70, 0.10, 0.08), Vector3(0, -0.03, 0.32), MAT_PALE)
	_lid_open_pos = Vector3(0, -0.28, 0.72)
	var c := _new_content()
	_part(c, "Impression", Vector3(1.30, 0.04, 0.40), Vector3(0.05, 0.67, 0), MAT_DARK)
	_part(c, "Wristband", Vector3(0.10, 0.01, 0.05), Vector3(0.52, 0.69, -0.16), MAT_PALE)


# A three-drawer steel bank, tipped, with the top drawer already half out.
func _build_drawers() -> void:
	_collider_size = Vector3(0.86, 1.20, 0.76)
	_piece_at = Vector3(0.00, 1.10, -0.30)
	_visual.rotation.z = 0.14
	_part(_visual, "Carcass", Vector3(0.76, 1.06, 0.62), Vector3(0, 0.53, 0), MAT_STEEL)
	for i in range(3):
		var y := 0.20 + float(i) * 0.33
		_part(_visual, "Face%d" % i, Vector3(0.70, 0.28, 0.03),
			Vector3(0, y, -0.325), MAT_STEEL)
		_part(_visual, "Pull%d" % i, Vector3(0.24, 0.03, 0.04),
			Vector3(0, y, -0.36), MAT_DARK)
	var lid := _new_lid(Vector3(0, 0.86, -0.32))
	_part(lid, "TopFace", Vector3(0.70, 0.28, 0.03), Vector3(0, 0, 0), MAT_STEEL)
	_part(lid, "TopSideL", Vector3(0.03, 0.26, 0.44), Vector3(-0.335, 0, 0.22), MAT_STEEL)
	_part(lid, "TopSideR", Vector3(0.03, 0.26, 0.44), Vector3(0.335, 0, 0.22), MAT_STEEL)
	_part(lid, "TopBottom", Vector3(0.70, 0.03, 0.44), Vector3(0, -0.13, 0.22), MAT_STEEL)
	_lid_open_pos = Vector3(0, 0, -0.40)
	var c := _new_content()
	_part(c, "Files", Vector3(0.60, 0.16, 0.34), Vector3(0, 0.94, -0.30), MAT_PALE)


# A suitcase lying flat in the water, lid hinged along its far edge.
func _build_suitcase() -> void:
	_collider_size = Vector3(0.92, 0.60, 0.72)
	_piece_at = Vector3(0.06, 0.28, 0.04)
	_part(_visual, "Shell", Vector3(0.82, 0.22, 0.60), Vector3(0, 0.11, 0), MAT_WOOD)
	_part(_visual, "Rim", Vector3(0.86, 0.03, 0.64), Vector3(0, 0.23, 0), MAT_DARK)
	_part(_visual, "Handle", Vector3(0.22, 0.05, 0.04), Vector3(0, 0.14, -0.32), MAT_DARK)
	for i in [-1, 1]:
		_part(_visual, "Clasp%d" % i, Vector3(0.08, 0.06, 0.04),
			Vector3(0.26 * i, 0.20, -0.31), MAT_STEEL)
	var lid := _new_lid(Vector3(0, 0.25, 0.30))
	_part(lid, "LidShell", Vector3(0.82, 0.18, 0.60), Vector3(0, 0.09, -0.30), MAT_WOOD)
	# ⚠️ Corner caps and a strap, because from behind, a suitcase with its handle and clasps
	# on the far face is a brown box (Issue 35). These read from every angle.
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_part(lid, "Corner%d%d" % [sx, sz], Vector3(0.09, 0.09, 0.09),
				Vector3(0.37 * sx, 0.13, -0.30 + 0.26 * sz), MAT_DARK)
	_part(lid, "Strap", Vector3(0.07, 0.20, 0.62), Vector3(-0.14, 0.09, -0.30), MAT_DARK)
	_lid_open_rot = -1.9
	var c := _new_content()
	_part(c, "Clothes", Vector3(0.66, 0.10, 0.44), Vector3(0, 0.18, 0), MAT_FABRIC)
	_part(c, "Photograph", Vector3(0.14, 0.01, 0.10), Vector3(-0.22, 0.24, -0.12), MAT_PALE)


# A tool chest with a lifting tray.
func _build_toolchest() -> void:
	_collider_size = Vector3(0.82, 0.72, 0.56)
	_piece_at = Vector3(-0.08, 0.46, 0.02)
	_part(_visual, "Body", Vector3(0.72, 0.40, 0.42), Vector3(0, 0.20, 0), MAT_STEEL)
	_part(_visual, "Foot", Vector3(0.76, 0.05, 0.46), Vector3(0, 0.02, 0), MAT_DARK)
	for i in [-1, 1]:
		_part(_visual, "Latch%d" % i, Vector3(0.07, 0.09, 0.04),
			Vector3(0.24 * i, 0.34, -0.22), MAT_DARK)
	var lid := _new_lid(Vector3(0, 0.40, 0))
	_part(lid, "Tray", Vector3(0.68, 0.09, 0.38), Vector3(0, 0.05, 0), MAT_STEEL)
	_part(lid, "TrayLip", Vector3(0.68, 0.06, 0.03), Vector3(0, 0.10, -0.18), MAT_STEEL)
	# ⚠️ The grip belongs to the TRAY and sits ON it. It used to be a child of the body at
	# y = 0.44, i.e. 1 cm under the tray that covers it — the one part added to make the chest
	# readable was buried, exactly as `kitchen_drawer.gd`'s handle was.
	_part(lid, "Grip", Vector3(0.30, 0.035, 0.05), Vector3(0, 0.14, 0), MAT_DARK)
	for i in [-1, 1]:
		_part(lid, "GripPost%d" % i, Vector3(0.035, 0.09, 0.045),
			Vector3(0.13 * i, 0.11, 0), MAT_DARK)
	_lid_open_pos = Vector3(0, 0.26, -0.34)
	var c := _new_content()
	# Bolt cutters — two long jaws crossing, which is a silhouette rather than a box.
	var bc := Node3D.new()
	bc.name = "BoltCutters"
	bc.position = Vector3(0, 0.42, 0)
	c.add_child(bc)
	for i in [-1, 1]:
		var arm := _part(bc, "Arm%d" % i, Vector3(0.05, 0.04, 0.50), Vector3(0, 0, 0), MAT_DARK)
		arm.rotation.y = 0.16 * float(i)
	_part(c, "DeadLamp", Vector3(0.12, 0.14, 0.12), Vector3(0.24, 0.47, 0.08), MAT_DARK)


# A wheelchair, standing in the water. There is no lid: the whole chair TURNS, which is
# the intro ward's beat (`intro_room.gd`'s wheelchair) two hundred metres down and under
# water — deliberately, because this level's pillar is escalating unreality.
func _build_wheelchair() -> void:
	_collider_size = Vector3(0.80, 1.20, 0.96)
	_piece_at = Vector3(0.06, 0.58, 0.00)
	_part(_visual, "Seat", Vector3(0.52, 0.06, 0.46), Vector3(0, 0.50, 0), MAT_FABRIC)
	_part(_visual, "Back", Vector3(0.52, 0.52, 0.06), Vector3(0, 0.77, 0.22), MAT_FABRIC)
	_part(_visual, "BackFrameL", Vector3(0.04, 0.62, 0.04), Vector3(-0.26, 0.82, 0.24), MAT_STEEL)
	_part(_visual, "BackFrameR", Vector3(0.04, 0.62, 0.04), Vector3(0.26, 0.82, 0.24), MAT_STEEL)
	for i in [-1, 1]:
		_part(_visual, "Arm%d" % i, Vector3(0.05, 0.05, 0.42),
			Vector3(0.28 * i, 0.68, 0.02), MAT_STEEL)
		_part(_visual, "ArmPost%d" % i, Vector3(0.04, 0.18, 0.04),
			Vector3(0.28 * i, 0.59, -0.16), MAT_STEEL)
		_ring(_visual, "Wheel%d" % i, 0.30, 0.045, Vector3(0.31 * i, 0.30, 0.10),
			MAT_DARK, true)
		# Hub and spoke plate, so the wheel is joined to the chair rather than beside it.
		_part(_visual, "Hub%d" % i, Vector3(0.06, 0.08, 0.08),
			Vector3(0.28 * i, 0.30, 0.10), MAT_STEEL)
		_ring(_visual, "Castor%d" % i, 0.10, 0.035, Vector3(0.22 * i, 0.10, -0.34),
			MAT_DARK, true)
		# The fork the castor hangs from — without it the small wheels float.
		_part(_visual, "Fork%d" % i, Vector3(0.04, 0.26, 0.04),
			Vector3(0.22 * i, 0.22, -0.34), MAT_STEEL)
		_part(_visual, "SideRail%d" % i, Vector3(0.04, 0.04, 0.50),
			Vector3(0.25 * i, 0.33, -0.10), MAT_STEEL)
	_part(_visual, "Footplate", Vector3(0.40, 0.03, 0.18), Vector3(0, 0.17, -0.36), MAT_STEEL)
	var c := _new_content()
	_part(c, "Shoe", Vector3(0.09, 0.07, 0.19), Vector3(-0.08, 0.22, -0.36), MAT_PALE)


func _build_collider() -> void:
	var col := CollisionShape3D.new()
	col.name = "SunkenCollision"
	var shape := BoxShape3D.new()
	shape.size = _collider_size
	col.shape = shape
	col.position = Vector3(0, _collider_size.y / 2.0, 0)
	add_child(col)


# ------------------------------------------------------------------------- the knock

func _build_knock() -> void:
	var stream := GameState.load_audio("flood_knock")
	if not stream:
		return
	_knock = AudioStreamPlayer3D.new()
	_knock.name = "Knock"
	_knock.stream = stream
	_knock.volume_db = KNOCK_DB
	_knock.unit_size = KNOCK_UNIT
	# Duckable with the rest of the world: it is room detail, not a puzzle answer. The
	# Flood's tell is VISUAL (the seam that shows only with the light off), so nothing that
	# ducks audio here can hide the way out — the rule `audio_buses.gd` exists to protect.
	_knock.bus = AudioBuses.AMBIENCE
	add_child(_knock)
	_knock.position = Vector3(0, 0.25, 0)
	_knock_timer = randf_range(1.0, KNOCK_MAX)


# ⚠️ GATED ON THE PLAYER BEING IN THE FLOOD, and the reason is a shipped bug: all three
# Backrooms zones are built at LEVEL START, so anything that ticks from `_ready()` runs for
# the whole game. The Flood's own drip ticker followed the player around the dry Lobby for
# months (see `backrooms_zone3.gd:_process`). These emitters are 200 m away and therefore
# inaudible either way, but a to-do list that has been knocking since before the player
# entered the level is the wrong beat as well as wasted work.
func set_zone_active(active: bool) -> void:
	if active == _zone_active:
		return
	_zone_active = active
	if active:
		_knock_timer = randf_range(0.8, 3.0)


# ⚠️⚠️ THE KNOCK STOPS WHEN THE FRAGMENT IS OUT, NOT WHEN THE LID IS OPEN (2026-08-17).
#
# This is the safety net that makes B-R1 — six mandatory fragments — legal at all. The
# exit does not exist until all six are in the frame, so a player who cannot find the
# last object is STUCK; the only thing standing between this design and an unwinnable
# level is that every outstanding object keeps calling, indefinitely, for as long as its
# fragment is outstanding.
#
# The gate used to be `is_searched`. That was correct while opening WAS taking; the
# moment the two split, a player who hauled a lid and walked away without the fragment
# would have silenced the one object they still needed. `check_flood_puzzle.gd` asserts
# an opened-but-not-emptied object still knocks.
func _process(delta: float) -> void:
	if is_taken or not _zone_active or _knock == null:
		return
	_knock_timer -= delta
	if _knock_timer <= 0.0:
		_knock_timer = randf_range(KNOCK_MIN, KNOCK_MAX)
		_knock.play()


# One knock, now — used by the zone's "answering knock" beat after the first fragment.
func knock_once(delay: float = 0.0) -> void:
	if is_taken or _knock == null:
		return
	if delay <= 0.0:
		_knock.play()
		return
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.finished.connect(func() -> void:
		if is_instance_valid(_knock) and not is_taken:
			_knock.play())


# ----------------------------------------------------------------------- the search

# Inert once the fragment is out, so it never advertises a prompt for something that
# cannot happen again — the `can_interact()` opt-out `player.gd:_update_interact_prompt()`
# consults. Note the two live states: shut (E hauls) and open-with-fragment (E takes).
func can_interact() -> bool:
	return not is_taken


func has_piece() -> bool:
	return is_instance_valid(_piece) and not _piece.taken


func interact() -> void:
	if is_taken:
		return
	if not is_searched:
		_haul_open()
		return
	# Open already: the only thing left to do here is lift the fragment out, and the item
	# does it whether the ray found the fragment's own small body or the furniture around
	# it. See the header — a press that lands on the wrong collider is the bug this avoids.
	if has_piece():
		_piece.take()


func _haul_open() -> void:
	is_searched = true

	var s := GameState.load_audio("flood_haul")
	if s:
		var p := AudioStreamPlayer3D.new()
		p.name = "Haul"
		p.stream = s
		p.volume_db = HAUL_DB
		p.unit_size = HAUL_UNIT
		p.bus = AudioBuses.AMBIENCE
		add_child(p)
		p.position = Vector3(0, 0.4, 0)
		p.finished.connect(p.queue_free)
		p.play()

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _lid != null and _lid_open_rot != 0.0:
		tw.tween_property(_lid, "rotation:x", _lid_open_rot, LID_TIME)
	elif _lid != null:
		tw.tween_property(_lid, "position", _lid.position + _lid_open_pos, LID_TIME)
	else:
		# No lid (the wheelchair): the whole VISUAL turns. The collider does not move.
		tw.tween_property(_visual, "rotation:y", _visual.rotation.y + 0.9, LID_TIME)
	tw.finished.connect(_reveal)
	searched.emit(self)


# ⚠️ NO NOTE HERE ANY MORE. Opening shows you a fragment lying in the thing you have just
# hauled open, and nothing else happens — no page, no journal entry, no caption. The page
# is the reward for the SECOND press. B-R2, and `lab_cabinet_drawer.gd`'s beat exactly.
func _reveal() -> void:
	if _content:
		_content.visible = true
	if is_instance_valid(_piece):
		_piece.set_active(true)


# Called by the fragment when it is lifted. The page arrives now, and the knock — which
# has kept calling through the open lid — finally stops.
func _on_piece_taken() -> void:
	is_taken = true
	if _knock:
		_knock.stop()
	if note_text != "":
		# Archived like any other safe note, so TAB can re-read it. `note.gd` only records
		# non-trap notes; none of these is a trap and none costs anything to read.
		GameState.record_note(note_text, 4)
		NoteUI.show_note(note_text)
	piece_taken.emit(self)


# Restore path (a back-door return): open, emptied, silent — no note, no sound, no event.
func mark_searched_instantly() -> void:
	if not is_searched:
		is_searched = true
		if _lid != null and _lid_open_rot != 0.0:
			_lid.rotation.x = _lid_open_rot
		elif _lid != null:
			_lid.position += _lid_open_pos
		else:
			_visual.rotation.y += 0.9
		if _content:
			_content.visible = true
	if not is_taken:
		is_taken = true
		if _knock:
			_knock.stop()
		if is_instance_valid(_piece):
			_piece.vanish()


# ------------------------------------------------------------------------ the fragment

# ⚠️ Built LAST, after `_build()` has set `_piece_at`, and given its own body so the
# player is reaching for a thing rather than for the box around it. Layer 2 / mask 0
# (`note.gd`'s convention): raycast-hittable, never solid — a fragment sitting in an open
# gurney must not be something you can walk into.
func _build_piece() -> void:
	var p := SunkenPiece.new()
	p.name = "Fragment"
	p.item = self
	add_child(p)
	p.position = _piece_at
	p.rotation.y = randf_range(-0.5, 0.5)
	_piece = p


# One of the six pieces of THE PLATE. A shard of dark enamel with a pale broken edge —
# the pale edge is the whole readability budget, because this zone is solved in the dark
# and nothing down here may be emissive (§5.2(8)).
class SunkenPiece extends StaticBody3D:
	const SHARD := Vector3(0.30, 0.020, 0.22)
	const GRAB := Vector3(0.42, 0.30, 0.36)

	var item: Node = null
	var taken: bool = false
	var _col: CollisionShape3D = null

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0

		var mi := MeshInstance3D.new()
		mi.name = "Shard"
		var bm := BoxMesh.new()
		bm.size = SHARD
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.16, 0.17, 0.18)
		mat.metallic = 0.35
		mat.roughness = 0.45
		mi.material_override = mat
		mi.rotation.x = deg_to_rad(-9.0)
		add_child(mi)

		# The broken edge, standing proud of the shard so the thing has a silhouette
		# rather than being a dark rectangle on a dark object (Issue 35, small).
		var edge := MeshInstance3D.new()
		edge.name = "BreakEdge"
		var eb := BoxMesh.new()
		eb.size = Vector3(SHARD.x * 0.92, 0.028, 0.035)
		edge.mesh = eb
		var em := StandardMaterial3D.new()
		em.albedo_color = Color(0.55, 0.53, 0.47)
		em.roughness = 0.9
		edge.material_override = em
		edge.position = Vector3(0.0, 0.012, -SHARD.z / 2.0 + 0.02)
		edge.rotation.x = deg_to_rad(-9.0)
		add_child(edge)

		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		# Generous, like the Lab page's: the player is reaching into an open object from
		# above at an angle. ⚠️ And DISABLED until the lid is open (Issue 66) — a live grab
		# volume inside a shut object is exactly what made one Lab drawer un-openable.
		shape.size = GRAB
		col.shape = shape
		_col = col
		add_child(col)
		set_active(false)

	func set_active(on: bool) -> void:
		visible = on
		if _col:
			_col.disabled = not on

	func can_interact() -> bool:
		return not taken and visible

	func interact() -> void:
		take()

	func take() -> void:
		if taken:
			return
		taken = true
		var s := GameState.load_audio("piece_lift")
		if s:
			var p := AudioStreamPlayer3D.new()
			p.stream = s
			p.volume_db = -3.0
			p.unit_size = 5.0
			p.bus = AudioBuses.AMBIENCE
			# ⚠️ Parented to the ITEM, not to self: this node is about to be freed, and a
			# player freed mid-stream is a sound that never happens.
			if is_instance_valid(item):
				item.add_child(p)
				p.position = position + Vector3(0, 0.1, 0)
			else:
				add_child(p)
			p.finished.connect(p.queue_free)
			p.play()
		if is_instance_valid(item):
			item.call("_on_piece_taken")
		# It is in your hands now, not in the object.
		queue_free()

	func vanish() -> void:
		taken = true
		queue_free()
