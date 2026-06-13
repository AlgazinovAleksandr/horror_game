extends Area3D
class_name DreadZone

# Zone C pressure: while the player is inside, panic decay weakens and a
# constant low pressure accrues (player.gd tracks overlapping zones via counters).


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("enter_dread_zone"):
		body.enter_dread_zone()


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("exit_dread_zone"):
		body.exit_dread_zone()
