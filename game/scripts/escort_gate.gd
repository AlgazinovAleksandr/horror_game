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
# Fired once per stage as the player advances down the corridor, so the LEVEL owns
# what the temptation actually is (a sound, a whisper, a line of text) and this node
# only owns the pacing.
signal tempt(stage: int)
# The FREE first look. See ARM_AT.
signal warned

const LOOK_LIMIT_DEG := 100.0
const COOLDOWN := 3.0
const BREATH_OFFSET := Vector3(0, 1.2, 1.6)   # behind the player, head height

# Where each stage fires, as a fraction of the walk. Measured on PROGRESS, not on a
# timer: a cautious player and a brisk one must both get the full three beats, and
# the last one has to land while there is still corridor left to be tempted in.
const TEMPT_AT := [0.18, 0.45, 0.72]

# THE FIRST FOUR METRES ARE FREE.
#
# Playtest 2026-07-21: the player forfeited the whole run 1.5 m into a 26 m corridor,
# 3 seconds after entering — before the first temptation stage, and before reaching
# the sign that states the rule. Worse, the level had just killed the lights BEHIND
# them, which is itself an invitation to turn round. The gate went from never firing
# to firing before it could be understood.
#
# So the first look inside ARM_AT is free and produces a WARNING instead. That is the
# project's standing fairness rule — "each rule's first encounter is teach=true, so
# the player learns the tell before it can kill" — the same reason CreatureStalker has
# START_GRACE and the Lab's apparition is survivable. Nearly breaking it IS the lesson.
const ARM_AT := 0.16          # fraction of the corridor walked before it can forfeit

var forward: Vector3 = Vector3(0, 0, 1)
# The corridor's z extent, so progress can be measured. Defaults are harmless if the
# level doesn't set them — progress simply never advances and no stage fires.
var span_start_z: float = 0.0
var span_end_z: float = 0.0

var _player: CharacterBody3D
var _camera: Camera3D
var _active: bool = false
var _cooldown: float = 0.0
var _breath: AudioStreamPlayer3D
var _stage: int = 0
var _progress: float = 0.0
var _warned_once: bool = false


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
	_update_temptation()

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
	if angle <= LOOK_LIMIT_DEG:
		return
	_cooldown = COOLDOWN
	if _progress < ARM_AT:
		# Still in the free stretch: teach, don't punish. Only once — a player who
		# keeps spinning on the spot has been told.
		if not _warned_once:
			_warned_once = true
			warned.emit()
		return
	broken.emit()


# THE RULE HAD NO TEETH. Nothing in 26 m of corridor ever asked the player to turn
# round, so a correctly-played run never encountered gate 4 at all — measured across
# two playtests, it simply never fired. The escort now earns its own violation:
# something follows, it gets closer, it calls, and finally the screen itself tells you
# to look. The rule is unchanged; only the pressure on it is new.
func _update_temptation() -> void:
	var span: float = span_end_z - span_start_z
	if absf(span) < 0.5:
		return
	# Kept up to date every frame — the arming check reads it too.
	_progress = clampf((_player.global_position.z - span_start_z) / span, 0.0, 1.0)
	if _stage >= TEMPT_AT.size():
		return
	if _progress >= TEMPT_AT[_stage]:
		var fired: int = _stage
		_stage += 1
		tempt.emit(fired)
