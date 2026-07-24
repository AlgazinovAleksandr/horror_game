extends StaticBody3D
class_name RotaryPhone

# A grimy 1970s rotary phone on the carpet. It rings (rotary_ring) from across the
# maze; answer it (E) and distorted overlapping voices pour out (phone_whisper) as
# a read-to-die trap beat — panic climbs while the call is "open," like a trap note.
# Builds its own primitive mesh so backrooms.gd only has to place it.

const RING_INTERVAL := 7.0       # silence between ring bursts
const ANSWER_PANIC_RATE := 11.0  # read-to-die rate fed by NoteUI while the call is up

# These used to default to 0 dB, which made the ring the loudest recurring sound in
# the level despite reading as "distant". Pulled down under the score.
const RING_VOLUME_DB := -6.0
const WHISPER_VOLUME_DB := -3.0

const WHISPER_TEXT := """...hello? hello is someone—
...don't follow the arrows they want you to—
...it's been three days. three. days.
...the hum the hum the hum the—
...if you can hear this you already took a wrong—
...HANG UP. HANG UP. HANG U—"""

signal answered
signal smashed

# KONTUR reuses this phone as its "ignore" gate, where picking up is itself the whole
# failure — stacking a read-to-die note on top of a forfeited run would be punishing
# the same mistake twice. Backrooms leaves this true and keeps the trap note.
@export var open_note: bool = true

# KONTUR's Gate 6 redesign: once the player is carrying a hammer, E no longer answers
# the phone — it smashes it. Defaults false so Backrooms' phone (the only other
# caller) is completely unaffected.
@export var smashable: bool = false

# Which ring to load, and how loud.
#
# The Backrooms keeps `rotary_ring` — a procedurally generated stinger from
# make_sfx_backrooms.py, deliberately mixed UNDER that level's score at -6 dB so it
# reads as "distant". KONTUR needs the opposite: Gate 6 is "ignore the phone", so the
# ring has to be an unmistakable, sustained temptation heard for a whole room's
# length. It overrides both to a real recorded ring at full level.
@export var ring_audio: String = "rotary_ring"
@export var ring_volume_db: float = RING_VOLUME_DB
# Larger unit_size = audible from further away before distance attenuation bites.
@export var ring_unit_size: float = 6.0

var _answered: bool = false
var _smashed: bool = false
var _ring_timer: float = 2.0
var _ring_player: AudioStreamPlayer3D
var _whisper_player: AudioStreamPlayer3D
var _smash_player: AudioStreamPlayer3D


func _ready() -> void:
	_build_mesh()
	_ring_player = AudioStreamPlayer3D.new()
	var ring := GameState.load_audio(ring_audio)
	if ring == null and ring_audio != "rotary_ring":
		ring = GameState.load_audio("rotary_ring")   # fall back rather than go silent
	if ring:
		_ring_player.stream = ring
	_ring_player.unit_size = ring_unit_size
	_ring_player.volume_db = ring_volume_db
	add_child(_ring_player)

	_whisper_player = AudioStreamPlayer3D.new()
	var wh := GameState.load_audio("phone_whisper")
	if wh:
		_whisper_player.stream = wh
	_whisper_player.unit_size = 4.0
	_whisper_player.volume_db = WHISPER_VOLUME_DB
	add_child(_whisper_player)

	_smash_player = AudioStreamPlayer3D.new()
	var smash := GameState.load_audio("phone_smash")
	if smash:
		_smash_player.stream = smash
	_smash_player.unit_size = 8.0
	add_child(_smash_player)


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
	if _answered or _smashed:
		return
	_ring_timer -= delta
	if _ring_timer <= 0.0:
		_ring_timer = RING_INTERVAL
		if _ring_player.stream and not _ring_player.playing:
			_ring_player.play()


func interact() -> void:
	if _answered or _smashed:
		return
	if smashable:
		_smash()
		return
	_answered = true
	_ring_player.stop()
	if _whisper_player.stream:
		_whisper_player.play()
	answered.emit()
	# Read-to-die: NoteUI feeds panic while the call is open; hang up to survive.
	if open_note:
		NoteUI.show_note(WHISPER_TEXT, ANSWER_PANIC_RATE)


# KONTUR Gate 6: the hammer resolution. Silences the phone for good instead of
# answering it.
func _smash() -> void:
	_smashed = true
	_ring_player.stop()
	if _smash_player.stream:
		_smash_player.play()
	smashed.emit()
	# A quick, permanent visual tell that this phone is done ringing.
	var tw := create_tween()
	tw.tween_property(self, "rotation:z", deg_to_rad(28.0), 0.15)
	tw.parallel().tween_property(self, "position:y", position.y - 0.06, 0.15)
