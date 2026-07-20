extends Node3D
class_name BackroomsZone3

# ZONE 3 — THE FLOOD.
#
# The last inversion. Five levels have taught the player that the flashlight is
# safety; here the exit seam is only visible with it OFF, and the whole zone is a
# DarkZone, so looking for the way out costs +3/s on top of the dread. Two decoy
# seams glow only while the light is ON — the exact inverse — so the instinct to
# light the room up doesn't just fail, it actively misleads.
#
# Built on RoomBuilder rather than raw boxes: it de-dupes shared walls and bridges
# the floor under every doorway, which is the whole reason the Issue-5 void-fall
# class can't come back.

signal cleared
signal mistake

const WATER_Y := 0.12
const ROOM_H := 3.2
const WADE_SLOW := 0.6             # refreshed every frame while submerged

var spawn_point: Vector3

var _origin: Vector3
var _builder: RoomBuilder
var _player: Node3D
var _real_seam: GlitchWall
var _decoys: Array[GlitchWall] = []
var _drip_timer: float = 0.0

# An 8-room flooded wing. Deliberately branching: the seam is in Sump, off the
# main line, so the player has to explore in the dark rather than walk straight on.
const ROOMS := [
	{ "name": "Landing",  "pos": Vector2(0, 0),     "size": Vector2(6, 6) },
	{ "name": "Descent",  "pos": Vector2(0, 7),     "size": Vector2(4, 8) },
	{ "name": "Basin",    "pos": Vector2(0, 15),    "size": Vector2(12, 8) },
	{ "name": "EastRun",  "pos": Vector2(9, 15),    "size": Vector2(6, 4) },
	{ "name": "WestRun",  "pos": Vector2(-9, 15),   "size": Vector2(6, 4) },
	{ "name": "Sump",     "pos": Vector2(-9, 21),   "size": Vector2(8, 8) },
	{ "name": "Cistern",  "pos": Vector2(9, 21),    "size": Vector2(8, 8) },
	{ "name": "Throat",   "pos": Vector2(0, 23),    "size": Vector2(4, 8) },
]

const DOORS := [
	{ "pos": Vector2(0, 3),    "width": 2.0, "dir": "z" },
	{ "pos": Vector2(0, 11),   "width": 2.4, "dir": "z" },
	{ "pos": Vector2(6, 15),   "width": 2.0, "dir": "x" },
	{ "pos": Vector2(-6, 15),  "width": 2.0, "dir": "x" },
	{ "pos": Vector2(-9, 17),  "width": 2.2, "dir": "z" },
	{ "pos": Vector2(9, 17),   "width": 2.2, "dir": "z" },
	{ "pos": Vector2(0, 19),   "width": 2.0, "dir": "z" },
]


func build(origin: Vector3, player: Node3D) -> void:
	_origin = origin
	_player = player
	position = origin
	spawn_point = origin + Vector3(0, 0.1, -2.0)

	_build_rooms()
	_build_water()
	_build_seams()
	_build_pressure()
	set_process(true)


func _build_rooms() -> void:
	_builder = RoomBuilder.new()
	_builder.wall_height = ROOM_H
	# Wet concrete rather than wallpaper — this has to read as somewhere else.
	_builder.wall_mat = MazeKit.make_material(
		"res://assets/textures/level_2_house/house_basement_concrete.png",
		Vector2(1.0, 1.0 / 3.0), Color(0.20, 0.21, 0.20))
	_builder.floor_mat = MazeKit.make_material(
		"res://assets/textures/level_1_lab/lab_floor_wet.png",
		Vector2(0.5, 0.5), Color(0.13, 0.14, 0.14))
	_builder.ceil_mat = MazeKit.make_material("", Vector2.ONE, Color(0.10, 0.10, 0.11))
	add_child(_builder)
	_builder.build(ROOMS, DOORS)


func _build_water() -> void:
	# One translucent sheet over the whole footprint. No collider — the wade is a
	# speed penalty applied in _process, not physics.
	var water := MeshInstance3D.new()
	water.name = "Floodwater"
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	water.mesh = pm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.06, 0.09, 0.10, 0.72)
	m.roughness = 0.10
	m.metallic = 0.35
	water.set_surface_override_material(0, m)
	water.position = Vector3(0, WATER_Y, 14.0)
	add_child(water)


func _build_seams() -> void:
	# The real seam, hidden off the main line in the Sump.
	var c: Vector3 = _builder.room_center("Sump")
	_real_seam = GlitchWall.new()
	_real_seam.name = "FloodSeam"
	add_child(_real_seam)
	_real_seam.setup(Vector2(3.6, 2.6), 2.6, true)
	_real_seam.position = Vector3(c.x, 1.35, c.z + 3.85)
	_real_seam.rotation.y = PI
	_real_seam.touched.connect(_on_seam_touched)

	# Two decoys, lit by the inverse rule.
	for spec in [["Cistern", 3.85], ["Basin", 3.85]]:
		var rc: Vector3 = _builder.room_center(spec[0])
		var d := GlitchWall.new()
		d.name = "Decoy" + str(spec[0])
		add_child(d)
		d.setup(Vector2(3.6, 2.6), 2.6, false)
		d.position = Vector3(rc.x, 1.35, rc.z + spec[1])
		d.rotation.y = PI
		d.touched.connect(_on_seam_touched)
		_decoys.append(d)


func _on_seam_touched(is_real: bool) -> void:
	if is_real:
		cleared.emit()
	else:
		mistake.emit()


func _build_pressure() -> void:
	# Dark + dread over the whole wing. Dread is the additive source; dark is what
	# makes holding the flashlight off in order to SEE the seam actually cost you.
	var centre := Vector3(0, ROOM_H / 2.0, 14.0)
	var extent := Vector3(40, ROOM_H, 40)
	MazeKit.zone_box(self, DreadZone.new(), centre, extent, "FloodDread")
	MazeKit.zone_box(self, DarkZone.new(), centre, extent, "FloodDark")

	# The one dry place in the level: a raised platform in the Basin with a lamp.
	# Recovery has to exist somewhere or the three-zone run is unsurvivable.
	var bc: Vector3 = _builder.room_center("Basin")
	MazeKit.box(self, "DryPlatform", Vector3(bc.x, 0.22, bc.z),
		Vector3(3.4, 0.44, 3.4),
		MazeKit.make_material("", Vector2.ONE, Color(0.26, 0.25, 0.22)))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.6)
	lamp.light_energy = 1.5
	lamp.omni_range = 7.0
	lamp.position = Vector3(bc.x, 2.2, bc.z)
	add_child(lamp)
	MazeKit.zone_box(self, CalmZone.new(), Vector3(bc.x, 1.2, bc.z),
		Vector3(4.5, 2.4, 4.5), "FloodCalm")

	# Beartraps UNDER the water — invisible by construction, only the snap warns you.
	for r in ["EastRun", "WestRun", "Cistern"]:
		var rc: Vector3 = _builder.room_center(r)
		var trap := Beartrap.new()
		trap.position = Vector3(rc.x + randf_range(-1.5, 1.5), 0,
			rc.z + randf_range(-1.5, 1.5))
		add_child(trap)

	# One non-teach HOLD apparition in the Throat: by now the player has been taught
	# the rule in the Lab, so this one is allowed to be fatal.
	var tc: Vector3 = _builder.room_center("Throat")
	var appar := Apparition.spawn(self, Apparition.Rule.HOLD,
		Vector3(tc.x, 0, tc.z), false)
	var trigger := CorridorEvent.new()
	MazeKit.zone_box(self, trigger, Vector3(tc.x, 1.2, tc.z - 3.0),
		Vector3(4.0, 2.4, 1.2), "ThroatEvent")
	trigger.fired.connect(func() -> void:
		if is_instance_valid(appar) and appar.has_method("appear"):
			appar.appear()
	)


func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	# THE TELL. Seam visibility is inverted against the flashlight: the real one
	# shows in darkness, the decoys show in light. `is_flashlight_on()` returns
	# false for a dead battery too, so a player who burned the light through zones
	# 1 and 2 can still finish — the rule is "not lit", not "toggled off".
	var lit: bool = _player.is_flashlight_on()
	if is_instance_valid(_real_seam):
		_real_seam.set_seam_visible(not lit)
	for d in _decoys:
		if is_instance_valid(d):
			d.set_seam_visible(lit)

	# Wading: refresh the slow every frame while inside the flooded footprint, so
	# it lapses naturally the moment the zone is left.
	var p: Vector3 = _player.global_position
	var local: Vector3 = p - _origin
	if local.z > -4.0 and local.z < 30.0 and absf(local.x) < 20.0 and p.y < _origin.y + 1.5:
		_player.apply_slow(WADE_SLOW)

	_drip_timer -= delta
	if _drip_timer <= 0.0:
		_drip_timer = randf_range(3.0, 8.0)
		_play("water_drip", Vector3(local.x + randf_range(-6, 6), 2.0,
			local.z + randf_range(-6, 6)), -4.0)


func _play(base_name: String, pos: Vector3, volume_db: float) -> void:
	var stream := GameState.load_audio(base_name)
	if not stream:
		return
	var a := AudioStreamPlayer3D.new()
	a.stream = stream
	a.volume_db = volume_db
	a.unit_size = 7.0
	add_child(a)
	a.position = pos
	a.finished.connect(a.queue_free)
	a.play()
