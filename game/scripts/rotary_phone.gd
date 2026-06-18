extends StaticBody3D
class_name RotaryPhone

# A grimy 1970s rotary phone on the carpet. It rings (rotary_ring) from across the
# maze; answer it (E) and distorted overlapping voices pour out (phone_whisper) as
# a read-to-die trap beat — panic climbs while the call is "open," like a trap note.
# Builds its own primitive mesh so backrooms.gd only has to place it.

const RING_INTERVAL := 7.0       # silence between ring bursts
const ANSWER_PANIC_RATE := 11.0  # read-to-die rate fed by NoteUI while the call is up

const WHISPER_TEXT := """...hello? hello is someone—
...don't follow the arrows they want you to—
...it's been three days. three. days.
...the hum the hum the hum the—
...if you can hear this you already took a wrong—
...HANG UP. HANG UP. HANG U—"""

var _answered: bool = false
var _ring_timer: float = 2.0
var _ring_player: AudioStreamPlayer3D
var _whisper_player: AudioStreamPlayer3D


func _ready() -> void:
	_build_mesh()
	_ring_player = AudioStreamPlayer3D.new()
	var ring := GameState.load_audio("rotary_ring")
	if ring:
		_ring_player.stream = ring
	_ring_player.unit_size = 6.0
	add_child(_ring_player)

	_whisper_player = AudioStreamPlayer3D.new()
	var wh := GameState.load_audio("phone_whisper")
	if wh:
		_whisper_player.stream = wh
	_whisper_player.unit_size = 4.0
	add_child(_whisper_player)


func _build_mesh() -> void:
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.05, 0.05, 0.06)
	black.roughness = 0.4
	black.metallic = 0.1

	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.28, 0.12, 0.34)
	base.mesh = base_mesh
	base.set_surface_override_material(0, black)
	base.position.y = 0.06
	add_child(base)

	# dial face
	var dial := MeshInstance3D.new()
	var dial_mesh := CylinderMesh.new()
	dial_mesh.top_radius = 0.1
	dial_mesh.bottom_radius = 0.1
	dial_mesh.height = 0.02
	dial.mesh = dial_mesh
	dial.set_surface_override_material(0, black)
	dial.position = Vector3(0, 0.13, 0.06)
	add_child(dial)

	# handset resting on top
	var handset := MeshInstance3D.new()
	var hs_mesh := BoxMesh.new()
	hs_mesh.size = Vector3(0.3, 0.06, 0.08)
	handset.mesh = hs_mesh
	handset.set_surface_override_material(0, black)
	handset.position = Vector3(0, 0.15, -0.12)
	add_child(handset)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.32, 0.3, 0.36)
	col.shape = shape
	col.position.y = 0.15
	add_child(col)


func _process(delta: float) -> void:
	if _answered:
		return
	_ring_timer -= delta
	if _ring_timer <= 0.0:
		_ring_timer = RING_INTERVAL
		if _ring_player.stream and not _ring_player.playing:
			_ring_player.play()


func interact() -> void:
	if _answered:
		return
	_answered = true
	_ring_player.stop()
	if _whisper_player.stream:
		_whisper_player.play()
	# Read-to-die: NoteUI feeds panic while the call is open; hang up to survive.
	NoteUI.show_note(WHISPER_TEXT, ANSWER_PANIC_RATE)
