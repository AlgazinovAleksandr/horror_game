extends Area3D
class_name EscortGate

# KONTUR Gate 4 — the escort. On entering the corridor the lights behind you die
# and something starts breathing at your back. You must walk to the terminus
# without turning to look at it: the camera's horizontal heading may not stray more
# than LOOK_LIMIT_DEG from the corridor's forward axis.
#
# Mouse-look is otherwise free — you can read the walls, check the floor, glance at
# the doors. Only actually turning around trips it. A COOLDOWN after each break
# stops one panicked spin from spending every strike at once.
#
# The hint is scrawled on a Backrooms dead-end wall: "WHEN IT WALKS BEHIND YOU —
# DON'T LOOK BACK. IT ISN'T THERE UNTIL YOU LOOK."

signal broken

const LOOK_LIMIT_DEG := 100.0
const COOLDOWN := 3.0
const BREATH_OFFSET := Vector3(0, 1.2, 1.6)   # behind the player, head height

var forward: Vector3 = Vector3(0, 0, 1)

var _player: CharacterBody3D
var _camera: Camera3D
var _active: bool = false
var _cooldown: float = 0.0
var _breath: AudioStreamPlayer3D


func _ready() -> void:
	body_entered.connect(_on_entered)
	body_exited.connect(_on_exited)
	_breath = AudioStreamPlayer3D.new()
	_breath.stream = GameState.load_audio("breathing_behind")
	_breath.unit_size = 4.0
	_breath.volume_db = -4.0
	add_child(_breath)


func _on_entered(body: Node3D) -> void:
	if not (body is CharacterBody3D) or _active:
		return
	_player = body as CharacterBody3D
	_camera = _player.get_node_or_null("Camera3D") as Camera3D
	_active = true
	_cooldown = 0.0
	if _breath.stream:
		_breath.play()


func _on_exited(body: Node3D) -> void:
	if body != _player:
		return
	_active = false
	if _breath.playing:
		_breath.stop()


func _process(delta: float) -> void:
	if not _active or not is_instance_valid(_player) or not _camera:
		return

	# Keep the breathing pinned just behind the player, so it pans as they turn.
	_breath.global_position = _player.global_position + BREATH_OFFSET

	if _cooldown > 0.0:
		_cooldown -= delta
		return

	var look := -_camera.global_transform.basis.z
	look.y = 0.0
	if look.length_squared() < 0.001:
		return
	var fwd := forward
	fwd.y = 0.0
	var angle := rad_to_deg(look.normalized().angle_to(fwd.normalized()))
	if angle > LOOK_LIMIT_DEG:
		_cooldown = COOLDOWN
		broken.emit()
