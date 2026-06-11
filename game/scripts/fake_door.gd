extends StaticBody3D
class_name FakeDoor

# Locked hotel room door along the corridor. Trying it answers with a slam
# from the other side — and a jolt of panic the first time.

const FIRST_TRY_PANIC := 8.0

var _tried: bool = false
var _slam_player: AudioStreamPlayer3D


func _ready() -> void:
	_slam_player = AudioStreamPlayer3D.new()
	var slam := GameState.load_audio("door_slam")
	if slam:
		_slam_player.stream = slam
	_slam_player.unit_size = 5.0
	add_child(_slam_player)


func interact() -> void:
	if _slam_player.stream and not _slam_player.playing:
		_slam_player.play()
	if _tried:
		return
	_tried = true
	var player := get_parent().get_node_or_null("Player")
	if player and player.has_method("add_panic"):
		player.add_panic(FIRST_TRY_PANIC)
