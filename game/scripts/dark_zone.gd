extends Area3D
class_name DarkZone

# Dark stretch of corridor: panic creeps upward while the player is inside
# with the flashlight off. player.gd tracks overlapping zones via counters.


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("enter_dark_zone"):
		body.enter_dark_zone()


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("exit_dark_zone"):
		body.exit_dark_zone()
