extends Area3D
class_name SilenceZone

# Zone 2's tell. Four glitch walls tear identically; only the real one is wrapped
# in one of these. Step inside and the entire ambient bed — hum and score alike —
# fades away, so the exit is found by LISTENING rather than looking.
#
# It ducks the shared "Backrooms" audio bus rather than chasing individual players,
# which is why backrooms.gd routes everything looping through that bus.

const FADE_TIME := 1.1

var quiet_db: float = -30.0
var normal_db: float = 0.0

var _tween: Tween


func _ready() -> void:
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)


func _on_enter(body: Node3D) -> void:
	if body.is_in_group("player"):
		_fade_to(quiet_db)


func _on_exit(body: Node3D) -> void:
	if body.is_in_group("player"):
		_fade_to(normal_db)


func _fade_to(db: float) -> void:
	var idx := AudioServer.get_bus_index("Backrooms")
	if idx == -1:
		return
	if _tween and _tween.is_running():
		_tween.kill()
	# Tween a throwaway object's property and mirror it onto the bus each step —
	# AudioServer bus volume isn't a node property, so it can't be tweened directly.
	_tween = create_tween()
	_tween.tween_method(
		func(v: float) -> void: AudioServer.set_bus_volume_db(idx, v),
		AudioServer.get_bus_volume_db(idx), db, FADE_TIME)


# The bus must not be left ducked if the zone is freed while the player is inside
# (a teleport out on a wrong answer does exactly that).
func _exit_tree() -> void:
	var idx := AudioServer.get_bus_index("Backrooms")
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, normal_db)
