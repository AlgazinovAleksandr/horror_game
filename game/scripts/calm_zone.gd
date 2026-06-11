extends Area3D
class_name CalmZone

# Sanctuary around a lit torch: panic decays faster while the player stands inside.
# player.gd tracks overlapping zones via enter/exit counters.


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("enter_calm_zone"):
		body.enter_calm_zone()


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("exit_calm_zone"):
		body.exit_calm_zone()
