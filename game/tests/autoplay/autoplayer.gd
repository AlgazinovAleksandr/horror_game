extends RefCounted
class_name AutoPlayer

# Drives the REAL Player node the way a person does: it sets the same movement vector
# the player script reads from Input, and lets gravity, collision, move_and_slide, the
# interact raycast and the panic system all run untouched.
#
# ⚠️ Why not simulated key presses: Godot's Input.parse_input_event() does not work
# under --headless (godotengine/godot#73557), so a headless test cannot press a key.
# The next-worst option is for the harness to move the player itself — but then the
# harness is testing its own movement code, and the game's could be broken without
# anything noticing. player.gd's `ai_*` surface is the narrow middle: the harness
# supplies only the input vector, and everything downstream is the shipping code path.
#
# ⚠️ And never, ever reach a win condition by emitting the signal. walk_backrooms.gd
# passed for weeks by calling `cleared.emit()` on a level that could not be finished
# (Issue 14), and walk_level6_breach.gd validated a purge sequence the player could
# never trigger because it called interact() instead of going through the ray (Issue
# 30). Everything here goes through ai_interact() -> _try_interact() -> the raycast.

const ARRIVE_DIST := 0.9        # close enough to a waypoint
const STUCK_SAMPLES := 45       # ~0.75 s of no progress at 60 fps
const STUCK_DIST := 0.05

var player: CharacterBody3D
var _last_pos: Vector3
var _still := 0

var stuck: bool = false         # set true when progress stops; the caller decides


func _init(p: CharacterBody3D) -> void:
	player = p
	player.set("ai_active", true)
	_last_pos = p.global_position


func release() -> void:
	if is_instance_valid(player):
		player.set("ai_active", false)
		player.set("ai_move_dir", Vector2.ZERO)


func stop() -> void:
	player.set("ai_move_dir", Vector2.ZERO)


# Steer toward `target` for one frame. Returns true once it has arrived.
# Face the target as well as walking at it, so the interact ray points where we go.
func step_toward(target: Vector3, sprint := false) -> bool:
	var to := target - player.global_position
	var flat := Vector2(to.x, to.z)
	if flat.length() <= ARRIVE_DIST:
		stop()
		return true

	player.call("ai_look_at", Vector3(target.x, player.global_position.y + 1.2, target.z))
	# ai_move_dir uses Input.get_vector()'s convention: y is FORWARD-negative, and the
	# player rotates its own basis by it — so "walk forward" is simply (0, -1) once we
	# are facing the target.
	player.set("ai_move_dir", Vector2(0.0, -1.0))
	player.set("ai_sprint", sprint)

	var moved := player.global_position.distance_to(_last_pos)
	_still = _still + 1 if moved < STUCK_DIST else 0
	_last_pos = player.global_position
	stuck = _still >= STUCK_SAMPLES
	return false


func reset_stuck() -> void:
	_still = 0
	stuck = false
