extends Node3D

# Level 1 — The Lab (expanded). Built procedurally with RoomBuilder from a
# room-graph: a reception, a main corridor with two exam rooms, a cross-junction
# opening onto the records room and the sealed morgue, then an observation room
# and the exit vestibule. The test: restore power (three breakers) to open the
# morgue, take the guarded keycard from between the tray and the monitor without
# looking at them, and reach the exit — all while the lights cut out, pipes groan,
# an apparition tests your nerve, and the observation mirror watches back.

const TEX := "res://assets/textures/level_1_lab/"
# Nodes kept from the .tscn; everything else is rebuilt procedurally.
const PRESERVE := ["Environment", "AmbientPlayer", "JumpscarePlayer", "HUDCanvas", "Player"]

const _DOOR_SCRIPT := preload("res://scripts/door.gd")
const _NOTE_SCRIPT := preload("res://scripts/note.gd")
const _TRIGGER_SCRIPT := preload("res://scripts/trigger_object.gd")
const _KEYCARD_SCRIPT := preload("res://scripts/keycard.gd")

const BLACKOUT_DURATION := 1.6
const KEYCARD_PANIC := 8.0
const PIPE_MIN := 12.0
const PIPE_MAX := 26.0
const BLACKOUT_MIN := 20.0
const BLACKOUT_MAX := 38.0

var _builder: RoomBuilder
var _lights: Array = []          # [OmniLight3D, base_energy]
var _blackout_timer: float = 0.0
var _pipe_timer: float = 0.0
var _scheduled_blackout: float = 0.0
var _breakers_flipped: int = 0
var _power_on: bool = false
var _morgue_shutter: CSGBox3D
var _apparition: Apparition
var _apparition_fired: bool = false


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameState.current_level = 1

	_clear_old_scene()
	_build_geometry()
	_place_player()
	_spawn_lights()
	_spawn_notes()
	_spawn_power_quest()
	_spawn_morgue_keycard()
	_spawn_observation_mirror()
	_spawn_doors()
	_spawn_apparition()
	_start_ambience()

	Vignette.spawn(self, Color(0.88, 0.95, 0.88, 1.0), 0.9)
	RandomAmbient.register_player(_player())
	_pipe_timer = randf_range(PIPE_MIN, PIPE_MAX)
	_scheduled_blackout = randf_range(BLACKOUT_MIN, BLACKOUT_MAX)


func _player() -> CharacterBody3D:
	return get_node_or_null("Player") as CharacterBody3D


func _clear_old_scene() -> void:
	for child in get_children():
		if not PRESERVE.has(child.name):
			child.queue_free()


# ---------------------------------------------------------------- geometry

const ROOMS := [
	{ "name": "Reception", "pos": Vector2(0, 0), "size": Vector2(6, 6) },
	{ "name": "MainHall1", "pos": Vector2(0, 7), "size": Vector2(3, 8) },
	{ "name": "Exam1", "pos": Vector2(-4, 7), "size": Vector2(5, 5) },
	{ "name": "Exam2", "pos": Vector2(4, 7), "size": Vector2(5, 5) },
	{ "name": "CrossHall", "pos": Vector2(0, 12.5), "size": Vector2(12, 3) },
	{ "name": "Records", "pos": Vector2(-9, 12.5), "size": Vector2(6, 6) },
	{ "name": "Morgue", "pos": Vector2(9.5, 12.5), "size": Vector2(7, 6) },
	{ "name": "MainHall2", "pos": Vector2(0, 16.5), "size": Vector2(3, 5) },
	{ "name": "Observation", "pos": Vector2(4, 17), "size": Vector2(5, 5) },
	{ "name": "ExitVestibule", "pos": Vector2(0, 20.5), "size": Vector2(4, 3) },
]

const DOORS := [
	{ "pos": Vector2(0, 3), "width": 1.6, "dir": "z" },        # Reception <-> MainHall1
	{ "pos": Vector2(-1.5, 7), "width": 1.4, "dir": "x" },     # MainHall1 <-> Exam1
	{ "pos": Vector2(1.5, 7), "width": 1.4, "dir": "x" },      # MainHall1 <-> Exam2
	{ "pos": Vector2(0, 11), "width": 1.6, "dir": "z" },       # MainHall1 <-> CrossHall
	{ "pos": Vector2(-6, 12.5), "width": 1.4, "dir": "x" },    # CrossHall <-> Records
	{ "pos": Vector2(6, 12.5), "width": 1.4, "dir": "x" },     # CrossHall <-> Morgue (shutter)
	{ "pos": Vector2(0, 14), "width": 1.6, "dir": "z" },       # CrossHall <-> MainHall2
	{ "pos": Vector2(1.5, 17), "width": 1.4, "dir": "x" },     # MainHall2 <-> Observation
	{ "pos": Vector2(0, 19), "width": 1.6, "dir": "z" },       # MainHall2 <-> ExitVestibule
]


func _build_geometry() -> void:
	_builder = RoomBuilder.new()
	_builder.wall_mat = RoomBuilder.make_material(
		TEX + "lab_wall.png", Vector3(0.4, 0.4, 0.4), Color(0.5, 0.55, 0.52))
	_builder.floor_mat = RoomBuilder.make_material(
		TEX + "lab_floor.png", Vector3(0.4, 0.4, 0.4), Color(0.3, 0.32, 0.3))
	_builder.ceil_mat = RoomBuilder.make_material(
		TEX + "lab_ceiling.png", Vector3(0.4, 0.4, 0.4), Color(0.22, 0.24, 0.23))
	add_child(_builder)
	_builder.build(ROOMS, DOORS)


func _place_player() -> void:
	var p := _player()
	if not p:
		return
	p.global_position = Vector3(0, 0.1, -1.5)
	p.rotation = Vector3(0, PI, 0)  # face +z (north, into the lab)


# ---------------------------------------------------------------- lighting

func _spawn_lights() -> void:
	# One ceiling lamp per room. They start dim (emergency power); restoring power
	# brightens them. The morgue's lamp stays dark until the shutter opens.
	for r in ROOMS:
		var c: Vector3 = _builder.room_center(r["name"])
		var emergency: bool = r["name"] != "Morgue"
		_add_lamp(r["name"], Vector3(c.x, 2.7, c.z), 0.22 if emergency else 0.0)


func _add_lamp(lamp_name: String, pos: Vector3, energy: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp_" + lamp_name
	lamp.position = pos
	lamp.light_energy = energy
	lamp.light_color = Color(0.75, 0.85, 0.95)  # cold institutional
	lamp.omni_range = 9.0
	lamp.omni_attenuation = 1.2
	add_child(lamp)
	_lights.append([lamp, energy])


# ---------------------------------------------------------------- notes

func _spawn_notes() -> void:
	_make_note(Vector3(2.4, 1.4, -2.6), -PI / 2.0,
		"Subject 47.\n\nThe power is down. Three breakers will bring it back — one in each lab room, one in records. The morgue door stays sealed until all three are thrown.\n\nThe keycard is inside the morgue. You will need it for the exit.")
	_make_note(_builder.wall_point("Exam2", Vector2(0, -1), 1.4, 0.1), 0.0,
		"Do not look at the tray. Do not look at the monitor.\n\nThey are not what they appear. When you take the card, keep your eyes on the floor.")
	_make_note(_builder.wall_point("Records", Vector2(-1, 0), 1.4, 0.1), PI / 2.0,
		"Night log — the corridor lights fail on their own now. When the dark comes, do not run. Running is how they find you. Stand still. Breathe. It passes.")


func _make_note(pos: Vector3, y_rot: float, text: String, trap := false) -> void:
	var note := StaticBody3D.new()
	note.set_script(_NOTE_SCRIPT)
	note.note_text = text
	note.is_trap = trap
	note.position = pos
	note.rotation.y = y_rot
	add_child(note)

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.32, 0.42, 0.01)
	mesh.mesh = bm
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.05, 0.05, 0.04) if not trap else Color(0.18, 0.05, 0.05)
	paper.emission_enabled = true
	paper.emission = Color(0.55, 0.5, 0.35) if not trap else Color(0.5, 0.12, 0.1)
	paper.emission_energy_multiplier = 0.6
	mesh.set_surface_override_material(0, paper)
	note.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 0.5, 0.12)
	col.shape = shape
	note.add_child(col)


# ---------------------------------------------------------------- power quest

func _spawn_power_quest() -> void:
	# Three breakers in reachable rooms. The morgue shutter blocks its doorway
	# until all three are thrown.
	for spot in [
		[_builder.wall_point("Exam1", Vector2(-1, 0), 1.3, 0.15), PI / 2.0],
		[_builder.wall_point("Exam2", Vector2(1, 0), 1.3, 0.15), -PI / 2.0],
		[_builder.wall_point("Records", Vector2(0, 1), 1.3, 0.15), PI],
	]:
		var b := Breaker.new()
		b.position = spot[0]
		b.rotation.y = spot[1]
		b.flipped.connect(_on_breaker_flipped)
		add_child(b)

	# Morgue shutter: fills the CrossHall<->Morgue doorway at x=6, z=12.5.
	_morgue_shutter = CSGBox3D.new()
	_morgue_shutter.name = "MorgueShutter"
	_morgue_shutter.size = Vector3(0.3, 2.6, 1.7)
	_morgue_shutter.position = Vector3(6.0, 1.3, 12.5)
	_morgue_shutter.use_collision = true
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.25, 0.22, 0.2)
	sm.metallic = 0.7
	sm.roughness = 0.5
	_morgue_shutter.material = sm
	add_child(_morgue_shutter)


func _on_breaker_flipped() -> void:
	_breakers_flipped += 1
	# Each throw lifts the emergency glow a little.
	for entry in _lights:
		if entry[1] > 0.0:
			entry[1] = minf(0.7, entry[1] + 0.12)
	if _breakers_flipped >= 3 and not _power_on:
		_restore_power()


func _restore_power() -> void:
	_power_on = true
	for entry in _lights:
		var lamp: OmniLight3D = entry[0]
		entry[1] = 0.7
		lamp.light_color = Color(0.85, 0.9, 0.85)
		var t := create_tween()
		t.tween_property(lamp, "light_energy", 0.7, 0.5)
	# Open the morgue shutter (drops into the floor).
	var t2 := create_tween()
	t2.tween_property(_morgue_shutter, "position:y", -1.5, 0.9).set_trans(Tween.TRANS_QUAD)
	t2.tween_callback(func() -> void: _morgue_shutter.use_collision = false)
	_play_at("breaker_throw", Vector3(6, 1.5, 12.5), 2.0)


# ---------------------------------------------------------------- morgue keycard

func _spawn_morgue_keycard() -> void:
	var c: Vector3 = _builder.room_center("Morgue")  # (9.5, 0, 12.5)
	var base := Vector3(c.x, 0, c.z + 1.0)           # toward the back of the morgue

	# Cart.
	var cart := CSGBox3D.new()
	cart.size = Vector3(2.8, 0.8, 0.5)
	cart.position = base + Vector3(0, 0.4, 0)
	cart.use_collision = true
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.2, 0.21, 0.22)
	cm.metallic = 0.5
	cart.material = cm
	add_child(cart)

	# Trigger objects flanking the card, sitting ON TOP of the cart (top = 0.8),
	# instant fail on interact / 3 s gaze. The note warns: don't look at them.
	_make_trigger(base + Vector3(-0.95, 0.86, 0), Vector3(0.6, 0.12, 0.4),
		Color(0.6, 0.6, 0.62))                                   # surgical tray
	_make_trigger(base + Vector3(0.95, 1.0, 0), Vector3(0.5, 0.4, 0.1),
		Color(0.02, 0.03, 0.04), Color(0.1, 0.25, 0.15))         # monitor with a face

	# A cursed portrait on the morgue's far wall — staring at it feeds panic.
	_make_cursed_panel(Vector3(c.x, 1.6, c.z + 2.9), Vector2(0.9, 1.2), PI, 0.9,
		TEX + "poster_lab.png")

	# The guarded keycard, between them.
	var key := StaticBody3D.new()
	key.set_script(_KEYCARD_SCRIPT)
	key.position = base + Vector3(0, 0.83, 0)
	add_child(key)
	var km := MeshInstance3D.new()
	var kb := BoxMesh.new()
	kb.size = Vector3(0.1, 0.02, 0.15)
	km.mesh = kb
	var kmat := StandardMaterial3D.new()
	kmat.albedo_color = Color(0.2, 0.8, 0.3)
	kmat.emission_enabled = true
	kmat.emission = Color(0.1, 0.6, 0.2)
	kmat.emission_energy_multiplier = 1.5
	km.set_surface_override_material(0, kmat)
	key.add_child(km)
	var kcol := CollisionShape3D.new()
	var ks := BoxShape3D.new()
	ks.size = Vector3(0.3, 0.3, 0.6)
	kcol.shape = ks
	key.add_child(kcol)

	# The morgue is a dark zone with a beartrap near the entrance.
	var zone := DarkZone.new()
	var zcol := CollisionShape3D.new()
	var zs := BoxShape3D.new()
	zs.size = Vector3(7, 3, 6)
	zcol.shape = zs
	zone.add_child(zcol)
	zone.position = Vector3(c.x, 1.5, c.z)
	add_child(zone)

	var trap := Beartrap.new()
	trap.position = Vector3(c.x - 1.5, 0, c.z - 1.5)
	add_child(trap)


func _make_trigger(pos: Vector3, size: Vector3, albedo: Color, emission := Color(0, 0, 0)) -> void:
	var body := StaticBody3D.new()
	body.set_script(_TRIGGER_SCRIPT)
	body.position = pos
	add_child(body)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	if emission != Color(0, 0, 0):
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = 0.4
	mesh.set_surface_override_material(0, mat)
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)


# A gaze-panic panel: ScaryObject (ancestor) -> StaticBody (world transform) ->
# textured quad + collider. Staring at it fills the panic bar.
func _make_cursed_panel(pos: Vector3, size: Vector2, y_rot: float, intensity: float,
		tex_path: String) -> void:
	var scary := ScaryObject.new()
	scary.scare_intensity = intensity
	add_child(scary)
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = y_rot
	scary.add_child(body)
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	if tex_path != "" and ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
	else:
		mat.albedo_color = Color(0.12, 0.06, 0.06)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.04, 0.04)
		mat.emission_energy_multiplier = 0.4
	mat.roughness = 0.9
	quad.set_surface_override_material(0, mat)
	body.add_child(quad)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y, 0.1)
	col.shape = shape
	body.add_child(col)


# ---------------------------------------------------------------- observation

func _spawn_observation_mirror() -> void:
	# One-way mirror on the far wall of the observation room — a figure stands in
	# the glass when you are not looking straight at it.
	var pos: Vector3 = _builder.wall_point("Observation", Vector2(1, 0), 1.5, 0.1)
	var mirror := LivingMirror.new()
	mirror.position = pos
	mirror.rotation.y = -PI / 2.0  # face back into the room (-x)
	add_child(mirror)


# ---------------------------------------------------------------- doors

func _spawn_doors() -> void:
	# Exit door at the north wall of the vestibule (needs the keycard).
	var exit := _make_door("ExitDoor", true, false)
	exit.unlock_condition = _DOOR_SCRIPT.UnlockCondition.KEYCARD
	exit.position = Vector3(0, 1.1, 21.85)
	exit.rotation.y = PI

	# Back door at the south wall of reception.
	var back := _make_door("BackDoor", false, true)
	back.position = Vector3(0, 1.1, -2.85)


func _make_door(door_name: String, advances: bool, goes_back: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = door_name
	body.set_script(_DOOR_SCRIPT)
	body.advances_level = advances
	body.goes_back = goes_back
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
	col.position.y = 0.0
	body.add_child(col)
	return body


# ---------------------------------------------------------------- apparition

func _spawn_apparition() -> void:
	# A taught "hold your nerve" apparition, armed when the player first steps into
	# the main corridor. teach=true: even a panicked sprint only shocks, not kills.
	_apparition = Apparition.spawn(self, Apparition.Rule.HOLD, Vector3.ZERO, true) as Apparition
	_spawn_event(Vector3(0, 1.5, 6.0), Vector3(3, 3, 1.5), _trigger_apparition)


func _trigger_apparition() -> void:
	if _apparition_fired or not _apparition:
		return
	_apparition_fired = true
	_apparition.appear()


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


# ---------------------------------------------------------------- ambience / ticks

func _start_ambience() -> void:
	var ambient: AudioStreamPlayer = get_node_or_null("AmbientPlayer")
	if ambient:
		var s := GameState.load_audio("ambient_lab")
		if s:
			ambient.stream = s
		if ambient.stream:
			ambient.finished.connect(ambient.play)
			ambient.play()


func _process(delta: float) -> void:
	_tick_blackout(delta)
	_tick_pipes(delta)
	_drive_lights(delta)


func _tick_blackout(delta: float) -> void:
	_blackout_timer = maxf(0.0, _blackout_timer - delta)
	_scheduled_blackout -= delta
	if _scheduled_blackout <= 0.0:
		_scheduled_blackout = randf_range(BLACKOUT_MIN, BLACKOUT_MAX)
		_blackout_timer = 1.5
		_play_at("creak", _random_room_point(2.4), 2.0)
		var p := _player()
		if p:
			p.add_panic(4.0)


func _tick_pipes(delta: float) -> void:
	_pipe_timer -= delta
	if _pipe_timer <= 0.0:
		_pipe_timer = randf_range(PIPE_MIN, PIPE_MAX)
		_play_at("pipe_groan", _random_room_point(1.6), 0.0)


func _drive_lights(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for entry in _lights:
		var lamp: OmniLight3D = entry[0]
		var base: float = entry[1]
		if _blackout_timer > 0.0:
			lamp.light_energy = base * (0.04 + maxf(0.0, sin(t * 37.0) * sin(t * 8.1)) * 0.15)
		else:
			lamp.light_energy = base * (1.0 + sin(t * 11.3 + lamp.position.x) * 0.06)


func _random_room_point(y: float) -> Vector3:
	var r: Dictionary = ROOMS[randi() % ROOMS.size()]
	var c: Vector3 = _builder.room_center(r["name"])
	return Vector3(c.x, y, c.z)


# Keycard pickup feedback (called by keycard.gd via current_scene).
func on_keycard_taken() -> void:
	_blackout_timer = BLACKOUT_DURATION
	_play_at("creak", _player().global_position if _player() else Vector3.ZERO, 2.0)
	var p := _player()
	if p and p.has_method("add_panic"):
		p.add_panic(KEYCARD_PANIC)


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
