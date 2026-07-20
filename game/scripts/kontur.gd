extends Node3D

# Level 5 — KONTUR ("Object 12"). Built procedurally with RoomBuilder: a decaying
# Soviet stairwell landing that sterilises, room by room, into a clinical K.O.N.T.U.R.
# containment wing.
#
# THE POINT OF THIS LEVEL: it is the only level whose answers are not inside it.
# Four gates, each a different verb — choose / use / abstain / don't-look-back — and
# each one's answer was planted in an earlier level:
#
#   Gate 1  THE TWO DOORS   choose    <- hidden note in L1 (the Lab morgue)
#   Gate 2  THE SHELF       use       <- the L2 House TV static card
#   Gate 3  THE OFFERING    abstain   <- the L3 Corridor door plate
#   Gate 4  THE ESCORT      camera    <- the L4 Backrooms wall scrawl
#
# In-level signs state each rule with the operative word REDACTED, so a player who
# missed the hints is guessing, not stuck.
#
# FAIL ECONOMY (unique to this level): the whole floor is one DreadZone, whose decay
# (2/s) and pressure (2/s) cancel exactly — so panic never drains here. Each wrong
# answer is a survivable flash scare plus STRIKE_PANIC. Three strikes overshoot
# PANIC_MAX and add_panic() fires the fatal screamer on its own; there is no
# bespoke death path in this file.

const TEX := "res://assets/textures/level_5_kontur/"
const LAB_TEX := "res://assets/textures/level_1_lab/"
const HOUSE_TEX := "res://assets/textures/level_2_house/"
const PRESERVE := ["Environment", "AmbientPlayer", "HUDCanvas", "Player"]

const _DOOR_SCRIPT := preload("res://scripts/door.gd")

const STRIKE_PANIC := 18.0        # 3 x 18 = 54 > PANIC_MAX (50)
const FLASH_PATH := TEX + "kontur_flash.png"
const FLASH_AUDIO := "kontur_flash"

var _builder: RoomBuilder
var _lights: Array = []           # [OmniLight3D, base_energy]
var _strikes: int = 0
var _held_bottle: String = ""     # "" | "vinegar" | "bleach" | "water"
var _barrier: FungalBarrier
var _took_offering: bool = false
var _gate1_done: bool = false
var _gate3_scored: bool = false


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameState.current_level = 5

	_clear_old_scene()
	_build_geometry()
	_place_player()
	_spawn_lights()
	_spawn_dread()
	_spawn_gate1_doors()
	_spawn_gate2_shelf()
	_spawn_gate3_offering()
	_spawn_gate4_escort()
	_spawn_creature()
	_spawn_signs()
	_spawn_props()
	_spawn_level_doors()
	_start_ambience()
	_boost_ambient(0.3)

	GameState.set_objective("PROTOCOL 4-B — PROCEED TO THE MARKED EXIT")


func _player() -> CharacterBody3D:
	return get_node_or_null("Player") as CharacterBody3D


func _clear_old_scene() -> void:
	for child in get_children():
		if not PRESERVE.has(child.name):
			child.queue_free()


# ---------------------------------------------------------------- geometry

# A single spine running +z. Rooms ABUT (RoomBuilder needs a shared wall plane).
# The Soviet half is rooms 1-5; the facility half is 6-8.
const ROOMS := [
	{ "name": "Landing",   "pos": Vector2(0, 0),    "size": Vector2(6, 8) },     # z -4 .. 4
	{ "name": "Vestibule", "pos": Vector2(0, 7),    "size": Vector2(8, 6) },     # z  4 .. 10
	{ "name": "Passage",   "pos": Vector2(0, 15),   "size": Vector2(8, 10) },    # z 10 .. 20
	{ "name": "Kitchen",   "pos": Vector2(0, 23.5), "size": Vector2(8, 7) },     # z 20 .. 27
	{ "name": "Archive",   "pos": Vector2(0, 31.5), "size": Vector2(9, 9) },     # z 27 .. 36
	{ "name": "Airlock",   "pos": Vector2(0, 38.5), "size": Vector2(4, 5) },     # z 36 .. 41
	{ "name": "Escort",    "pos": Vector2(0, 54),   "size": Vector2(3, 26) },    # z 41 .. 67
	{ "name": "Terminus",  "pos": Vector2(0, 70),   "size": Vector2(6, 6) },     # z 67 .. 73
]

# Gate 1's two doorways sit at x = -2 and x = +2, so the wall CENTRE (x = 0) stays
# solid — that is where the redacted sign hangs. Everywhere else the doorway is on
# the wall centre, so props must go on the east/west walls (Session 11 bug class:
# a collider on a doorway wall silently seals the room).
const GATE1_X := 2.0

const DOORS := [
	{ "pos": Vector2(0, 4),           "width": 1.8, "dir": "z" },   # Landing  <-> Vestibule
	{ "pos": Vector2(-GATE1_X, 10),   "width": 1.4, "dir": "z" },   # Vestibule <-> Passage (west door)
	{ "pos": Vector2(GATE1_X, 10),    "width": 1.4, "dir": "z" },   # Vestibule <-> Passage (east door)
	{ "pos": Vector2(0, 20),          "width": 1.8, "dir": "z" },   # Passage  <-> Kitchen
	{ "pos": Vector2(0, 27),          "width": 1.8, "dir": "z" },   # Kitchen  <-> Archive  (barrier)
	{ "pos": Vector2(0, 36),          "width": 1.6, "dir": "z" },   # Archive  <-> Airlock
	{ "pos": Vector2(0, 41),          "width": 1.6, "dir": "z" },   # Airlock  <-> Escort
	{ "pos": Vector2(0, 67),          "width": 1.6, "dir": "z" },   # Escort   <-> Terminus
]

# Which rooms wear the sterile facility skin rather than Soviet decay.
const FACILITY_ROOMS := ["Airlock", "Escort", "Terminus"]
# Which rooms are raw infected concrete rather than wallpaper.
const CONCRETE_ROOMS := ["Passage", "Archive"]


func _build_geometry() -> void:
	_builder = RoomBuilder.new()
	_builder.wall_mat = _mat(TEX + "kontur_wallpaper_soviet.png", 0.35, Color(0.36, 0.34, 0.22))
	_builder.floor_mat = _mat(TEX + "kontur_floor_tile.png", 0.4, Color(0.24, 0.22, 0.19))
	_builder.ceil_mat = _mat(HOUSE_TEX + "house_ceiling.png", 0.35, Color(0.18, 0.17, 0.15))
	add_child(_builder)
	_builder.build(_rooms_with_skins(), DOORS)


# Negative V, like corridor.gd / backrooms.gd — a positive y-scale renders the wall
# texture upside-down under triplanar mapping.
func _mat(tex_path: String, scale: float, fallback: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.92
	if tex_path != "" and ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3(scale, -scale, scale)
	else:
		mat.albedo_color = fallback
	return mat


# The visual arc IS the story: peeling Soviet wallpaper -> raw infected concrete ->
# clinical KONTUR tile. Per-room overrides do the whole job.
func _rooms_with_skins() -> Array:
	var concrete := _mat(TEX + "kontur_concrete_infected.png", 0.35, Color(0.26, 0.27, 0.24))
	var facility := _mat(TEX + "kontur_facility_wall.png", 0.4, Color(0.62, 0.66, 0.62))
	var fac_floor := _mat(LAB_TEX + "lab_floor.png", 0.4, Color(0.4, 0.42, 0.4))
	var fac_ceil := _mat(LAB_TEX + "lab_ceiling.png", 0.4, Color(0.3, 0.32, 0.3))

	var out: Array = []
	for r in ROOMS:
		var room: Dictionary = r.duplicate()
		var n: String = room["name"]
		if FACILITY_ROOMS.has(n):
			room["wall_mat"] = facility
			room["floor_mat"] = fac_floor
			room["ceil_mat"] = fac_ceil
		elif CONCRETE_ROOMS.has(n):
			room["wall_mat"] = concrete
		out.append(room)
	return out


func _place_player() -> void:
	var p := _player()
	if not p:
		return
	p.global_position = Vector3(0, 0.1, -3.0)
	p.rotation = Vector3(0, PI, 0)   # face +z, down the spine


# ---------------------------------------------------------------- lighting

func _spawn_lights() -> void:
	# Soviet half: sickly, weak, warm-green. Facility half: cold and bright.
	_add_lamp("Landing", Vector3(0, 2.6, 0), 0.55, Color(0.9, 0.78, 0.5))
	_add_lamp("Vestibule", Vector3(0, 2.6, 7), 0.5, Color(0.85, 0.8, 0.55))
	_add_lamp("PassageA", Vector3(0, 2.6, 12.5), 0.4, Color(0.7, 0.8, 0.65))
	_add_lamp("PassageB", Vector3(0, 2.6, 18), 0.32, Color(0.7, 0.8, 0.65))
	_add_lamp("Kitchen", Vector3(0, 2.6, 23.5), 0.5, Color(0.9, 0.8, 0.55))
	_add_lamp("ArchiveA", Vector3(0, 2.6, 29.5), 0.4, Color(0.75, 0.8, 0.7))
	_add_lamp("ArchiveB", Vector3(0, 2.6, 34), 0.4, Color(0.75, 0.8, 0.7))
	_add_lamp("Airlock", Vector3(0, 2.6, 38.5), 1.0, Color(0.85, 0.95, 1.0))
	for i in range(5):
		_add_lamp("Escort%d" % i, Vector3(0, 2.7, 44.0 + i * 5.5), 0.85, Color(0.85, 0.95, 1.0))
	_add_lamp("Terminus", Vector3(0, 2.6, 70), 0.9, Color(0.85, 0.95, 1.0))


func _add_lamp(lamp_name: String, pos: Vector3, energy: float, color: Color) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp_" + lamp_name
	lamp.position = pos
	lamp.light_energy = energy
	lamp.light_color = color
	lamp.omni_range = 11.0
	add_child(lamp)
	_lights.append([lamp, energy])


# ---------------------------------------------------------------- panic floor

func _spawn_dread() -> void:
	# One DreadZone over the whole level. DREAD_DECAY_RATE and DREAD_PANIC_RATE are
	# both 2.0/s in player.gd, so they cancel: panic neither drains nor grows while
	# you simply walk. That is the entire no-decay economy — no player.gd changes.
	var zone := DreadZone.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(16, 6, 82)
	col.shape = shape
	zone.add_child(col)
	zone.position = Vector3(0, 2.0, 34.5)
	add_child(zone)

	# The infected middle is also dark — the flashlight matters here.
	var dark := DarkZone.new()
	var dcol := CollisionShape3D.new()
	var dshape := BoxShape3D.new()
	dshape.size = Vector3(10, 4, 10)
	dcol.shape = dshape
	dark.add_child(dcol)
	dark.position = Vector3(0, 2.0, 15)
	add_child(dark)


# A wrong answer. Survivable on its own; the third one is not, because add_panic()
# fires the fatal screamer once _panic crosses PANIC_MAX.
func _strike(message: String) -> void:
	_strikes += 1
	Screamer.flash_scare(FLASH_PATH, FLASH_AUDIO, 0.8)
	var p := _player()
	if p:
		p.jolt_camera(0.1, 0.5)
		p.add_panic(STRIKE_PANIC)
	_notice(message, Color(1.0, 0.3, 0.25))

	# Playtest instrumentation. Guarded so removing the DebugLog autoload is enough
	# to strip it — nothing here affects play.
	var dbg := get_node_or_null("/root/DebugLog")
	if dbg and dbg.has_method("note"):
		dbg.note("STRIKE %d/3 — %s" % [_strikes, message])


# Brief centred label. Timer is connected, not awaited — an awaited timer dies with
# the node that started it (Issue 6).
func _notice(text: String, color: Color) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 50
	get_tree().root.add_child(canvas)
	var lbl := Label.new()
	lbl.text = text
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 30)
	canvas.add_child(lbl)
	get_tree().create_timer(2.2).timeout.connect(canvas.queue_free)


# ---------------------------------------------------------------- gate 1: the doors

func _spawn_gate1_doors() -> void:
	# Which side is black is randomised per run, so the answer is the COLOUR (from
	# the L1 note), never a memorised position.
	var black_on_east := randf() < 0.5
	_make_choice_door(GATE1_X, black_on_east)
	_make_choice_door(-GATE1_X, not black_on_east)
	# Seal the red doorway with a wall of O-41 a little way inside the passage, so
	# opening the wrong door shows you exactly what you just invited in.
	var red_x := -GATE1_X if black_on_east else GATE1_X
	var fungus := CSGBox3D.new()
	fungus.name = "Gate1Fungus"
	fungus.size = Vector3(3.0, 3.0, 0.5)
	fungus.position = Vector3(red_x, 1.5, 11.7)
	fungus.use_collision = true
	fungus.material = _mat(TEX + "fungal_mass.png", 0.5, Color(0.4, 0.4, 0.35))
	add_child(fungus)


func _make_choice_door(x: float, is_black: bool) -> void:
	var d := ChoiceDoor.new()
	d.name = "ChoiceDoor_%s" % ("Black" if is_black else "Red")
	d.is_correct = is_black
	d.texture_path = TEX + ("door_black.png" if is_black else "door_red.png")
	# The node is the hinge; the panel extends +x from it, so start half a width left.
	d.position = Vector3(x - ChoiceDoor.WIDTH / 2.0, 0.0, 10.0)
	d.chosen.connect(_on_gate1_chosen)
	add_child(d)

	# RoomBuilder cuts doorways FULL HEIGHT, so a 2.2 m door leaves an open transom
	# you can see straight over. Fill the gap above the frame.
	var transom := CSGBox3D.new()
	transom.name = "Transom"
	transom.size = Vector3(1.5, 3.0 - ChoiceDoor.HEIGHT, 0.2)
	transom.position = Vector3(x, ChoiceDoor.HEIGHT + (3.0 - ChoiceDoor.HEIGHT) / 2.0, 10.0)
	transom.use_collision = true
	transom.material = _builder.wall_mat
	add_child(transom)


func _on_gate1_chosen(correct: bool) -> void:
	if _gate1_done:
		return
	if correct:
		_gate1_done = true
		GameState.set_objective("DECONTAMINATION REQUIRED — THE WAY ON IS SEALED")
		_play_at("door_seal", Vector3(0, 1.5, 10), 0.0)
	else:
		_strike("THE SEAL WAS NOT AN EXIT")


# ---------------------------------------------------------------- gate 2: the shelf

func _spawn_gate2_shelf() -> void:
	# Three bottles on a shelf along the kitchen's east wall (the north and south
	# walls both carry doorways).
	var shelf := CSGBox3D.new()
	shelf.name = "Shelf"
	shelf.size = Vector3(0.5, 0.08, 3.6)
	shelf.position = Vector3(3.4, 0.95, 23.5)
	# No collision: a shelf collider would intercept the interaction ray before it
	# reached the bottles standing on it (the House key-stand lesson).
	shelf.use_collision = false
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.28, 0.22, 0.16)
	shelf.material = sm
	add_child(shelf)

	var kinds := [
		["bleach", TEX + "label_bleach.png", 22.3],
		["vinegar", TEX + "label_vinegar.png", 23.5],
		["water", TEX + "label_water.png", 24.7],
	]
	for entry in kinds:
		var b := BottleItem.new()
		b.kind = entry[0]
		b.label_path = entry[1]
		b.position = Vector3(3.4, 0.99, entry[2])
		b.rotation.y = -PI / 2.0    # label faces into the room (-x)
		b.taken.connect(_on_bottle_taken)
		add_child(b)

	_barrier = FungalBarrier.new()
	_barrier.name = "FungalBarrier"
	_barrier.position = Vector3(0, 1.5, 27.0)
	_barrier.setup(Vector3(2.2, 3.0, 0.5), TEX + "fungal_mass.png")
	_barrier.sprayed.connect(_on_barrier_sprayed)
	add_child(_barrier)


func _on_bottle_taken(kind: String) -> void:
	_held_bottle = kind
	_notice("Carrying: %s" % kind.to_upper(), Color(0.6, 0.9, 0.6))
	# Keep it on the HUD too — the notice fades, and the barrier may be a walk away.
	GameState.set_objective("DECONTAMINATION REQUIRED — CARRYING: %s" % kind.to_upper())


func _on_barrier_sprayed() -> void:
	if _held_bottle == "":
		_notice("It will not move. Something has to break it down.", Color(0.85, 0.85, 0.7))
		return
	if _held_bottle == "vinegar":
		_barrier.dissolve()
		_play_at("acid_hiss", Vector3(0, 1.5, 27), 0.0)
		GameState.set_objective("DO NOT DEVIATE FROM THE INVENTORY PROTOCOL")
	else:
		# The bottle is spent, so a wrong guess costs a walk back as well as panic.
		_held_bottle = ""
		_strike("IT DRANK IT")


# ---------------------------------------------------------------- gate 3: the offering

func _spawn_gate3_offering() -> void:
	var ped := OfferingPedestal.new()
	ped.name = "OfferingPedestal"
	ped.position = Vector3(0, 0, 31.0)
	ped.taken.connect(_on_offering_taken)
	add_child(ped)

	# Scored on crossing into the Airlock: by then the choice is made either way.
	_spawn_event(Vector3(0, 1.5, 37.5), Vector3(4, 3, 1.5), _score_gate3)


func _on_offering_taken() -> void:
	_took_offering = true
	_play_at("pedestal_alarm", Vector3(0, 1.2, 31), 0.0)


func _score_gate3() -> void:
	if _gate3_scored:
		return
	_gate3_scored = true
	if _took_offering:
		_strike("RECOVERED ITEMS ARE BAIT")
	GameState.set_objective("PROCEED TO TERMINUS. AN ESCORT HAS BEEN ASSIGNED.")


# ---------------------------------------------------------------- gate 4: the escort

func _spawn_gate4_escort() -> void:
	var gate := EscortGate.new()
	gate.name = "EscortGate"
	gate.forward = Vector3(0, 0, 1)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 3, 24)
	col.shape = shape
	gate.add_child(col)
	gate.position = Vector3(0, 1.5, 54)
	gate.broken.connect(_on_escort_broken)
	add_child(gate)

	# The lights behind you die as you commit to the corridor.
	_spawn_event(Vector3(0, 1.5, 42.5), Vector3(3, 3, 1.5), _ev_escort_begins)


func _ev_escort_begins() -> void:
	for entry in _lights:
		var lamp: OmniLight3D = entry[0]
		if lamp.position.z < 43.0:
			var t := create_tween()
			t.tween_property(lamp, "light_energy", 0.0, 0.35)
			entry[1] = 0.0
	_play_at("door_seal", Vector3(0, 1.5, 41), -2.0)


func _on_escort_broken() -> void:
	_strike("YOU LOOKED")


# ---------------------------------------------------------------- creature

func _spawn_creature() -> void:
	# The Perëkozhnik, planted in the passage's far west corner — off the walking
	# line, so only curiosity brings you inside its 2 m kill radius.
	var c := CreatureShapechanger.new()
	c.name = "Shapechanger"
	c.position = Vector3(-3.2, 0, 18.0)
	add_child(c)


# ---------------------------------------------------------------- signs

func _spawn_signs() -> void:
	# Each gate's rule, with the operative word censored. A player who found the
	# earlier-level hints reads straight through these; one who didn't gets the
	# shape of the question but not the answer.
	_make_sign(Vector3(0, 1.7, 9.85), PI,
		"K.O.N.T.U.R. — PROTOCOL 4-B", "EVACUATION ROUTE IS MARKED IN:")
	_make_sign(_builder.wall_point("Kitchen", Vector2(-1, 0), 1.7, 0.12), PI / 2.0,
		"DECONTAMINATION — CLASS II", "APPROVED AGENT: DOMESTIC")
	_make_sign(_builder.wall_point("Archive", Vector2(1, 0), 1.7, 0.12), -PI / 2.0,
		"RECOVERY LOG — OBJECT 12", "ITEMS RECOVERED FROM AN OBJECT ARE:")
	_make_sign(_builder.wall_point("Airlock", Vector2(1, 0), 1.7, 0.12), -PI / 2.0,
		"TRANSIT PROTOCOL 7", "DO NOT ___ THE ESCORT")


# A plate + two text lines + a censor bar on its own line, so the redaction needs no
# text measurement to place (and reads exactly like a real censored form).
func _make_sign(pos: Vector3, y_rot: float, title: String, body: String) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = y_rot
	add_child(root)

	var plate := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 0.95)
	plate.mesh = quad
	var pmat := StandardMaterial3D.new()
	if ResourceLoader.exists(TEX + "kontur_sign_blank.png"):
		var ptex := load(TEX + "kontur_sign_blank.png")
		pmat.albedo_texture = ptex
		# Faintly backlit, so the rules stay readable in rooms this dark — these are
		# the only in-level help there is, and an unreadable sign is no help at all.
		pmat.emission_enabled = true
		pmat.emission_texture = ptex
		pmat.emission_energy_multiplier = 0.55
	else:
		pmat.albedo_color = Color(0.62, 0.65, 0.6)
	pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plate.set_surface_override_material(0, pmat)
	root.add_child(plate)

	var lbl := Label3D.new()
	lbl.text = "%s\n\n%s" % [title, body]
	lbl.font_size = 44
	# Sized so the longest line stays inside the plate's engraved inner frame.
	lbl.pixel_size = 0.0014
	lbl.modulate = Color(0.1, 0.1, 0.1)
	lbl.outline_size = 0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector3(0, 0.13, 0.012)
	root.add_child(lbl)

	var bar := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(0.85, 0.11)
	bar.mesh = bq
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.04, 0.04, 0.04)
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bar.set_surface_override_material(0, bmat)
	bar.position = Vector3(0, -0.24, 0.014)
	root.add_child(bar)


# ---------------------------------------------------------------- props

func _spawn_props() -> void:
	# Stairwell dressing on the Landing's side walls (the north wall is the doorway).
	_wall_panel(_builder.wall_point("Landing", Vector2(-1, 0), 1.5, 0.08), PI / 2.0,
		Vector2(1.6, 1.4), TEX + "kontur_panel_mailboxes.png")
	_wall_panel(_builder.wall_point("Landing", Vector2(1, 0), 1.3, 0.08), -PI / 2.0,
		Vector2(1.1, 1.1), TEX + "kontur_panel_chute.png")
	# The safety poster, on the Archive's west wall.
	_wall_panel(_builder.wall_point("Archive", Vector2(-1, 0), 1.7, 0.08), PI / 2.0,
		Vector2(1.0, 1.4), TEX + "kontur_poster.png")


# A flat decal quad. No collider — these hang on walls that already have one, and a
# second collider in front of a wall is how props end up blocking doorways.
func _wall_panel(pos: Vector3, y_rot: float, size: Vector2, tex_path: String) -> void:
	if not ResourceLoader.exists(tex_path):
		return
	var m := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	m.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(tex_path)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.set_surface_override_material(0, mat)
	m.position = pos
	m.rotation.y = y_rot
	add_child(m)


# ---------------------------------------------------------------- level doors

func _spawn_level_doors() -> void:
	var back := _make_door("BackDoor", false, true)
	back.position = Vector3(0, 1.1, -3.85)

	var exit_door := _make_door("ExitDoor", true, false)
	exit_door.position = Vector3(0, 1.1, 72.85)
	exit_door.rotation.y = PI


func _make_door(door_name: String, advances: bool, back: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = door_name
	body.set_script(_DOOR_SCRIPT)
	body.advances_level = advances
	body.goes_back = back
	add_child(body)
	var mesh := MeshInstance3D.new()
	mesh.name = "DoorMesh"
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 2.2, 0.15)
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.01, 0.01)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.02, 0.02)
	mat.emission_energy_multiplier = 1.5
	mesh.set_surface_override_material(0, mat)
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 2.2, 0.2)
	col.shape = shape
	body.add_child(col)
	return body


# ---------------------------------------------------------------- events / ambience

func _spawn_event(pos: Vector3, size: Vector3, callback: Callable) -> void:
	var ev := CorridorEvent.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	ev.add_child(col)
	ev.position = pos
	ev.fired.connect(callback)
	add_child(ev)


# See level_1.gd / level_2.gd: duplicate the SHARED environment before retuning it,
# and use a BLACK background — the procedural sky leaks through any geometry seam
# as daylight, which is fatal to an interior.
func _boost_ambient(energy: float) -> void:
	var we: WorldEnvironment = get_node_or_null("Environment/WorldEnvironment")
	if not we or not we.environment:
		return
	var env: Environment = we.environment.duplicate()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = energy
	env.ambient_light_color = Color(0.1, 0.11, 0.1)
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	we.environment = env


func _start_ambience() -> void:
	var ambient: AudioStreamPlayer = get_node_or_null("AmbientPlayer")
	if not ambient:
		return
	var s := GameState.load_audio("ambient_kontur")
	if not s:
		s = GameState.load_audio("ambient_lab")   # fallback until the KONTUR bed exists
	if s:
		ambient.stream = s
		ambient.volume_db = -8.0
		ambient.finished.connect(ambient.play)
		ambient.play()
	var music := GameState.load_audio("kontur_music")
	if music:
		var mp := AudioStreamPlayer.new()
		mp.stream = music
		mp.volume_db = -14.0
		add_child(mp)
		mp.finished.connect(mp.play)
		mp.play()


func _play_at(base_name: String, pos: Vector3, volume_db: float = 0.0) -> void:
	var stream := GameState.load_audio(base_name)
	if not stream:
		return
	var pl := AudioStreamPlayer3D.new()
	pl.stream = stream
	pl.volume_db = volume_db
	pl.unit_size = 8.0
	pl.max_db = 6.0
	add_child(pl)
	pl.position = pos
	pl.finished.connect(pl.queue_free)
	pl.play()


func _process(_delta: float) -> void:
	# Fluorescent unsteadiness in the facility half, a slow sick pulse in the Soviet half.
	var t := Time.get_ticks_msec() * 0.001
	for entry in _lights:
		var lamp: OmniLight3D = entry[0]
		var base: float = entry[1]
		if base <= 0.0:
			continue
		if lamp.position.z > 36.0:
			var flicker := 1.0 if sin(t * 47.0 + lamp.position.z) > -0.93 else 0.35
			lamp.light_energy = base * flicker
		else:
			lamp.light_energy = base * (1.0 + sin(t * 5.0 + lamp.position.z) * 0.06)
