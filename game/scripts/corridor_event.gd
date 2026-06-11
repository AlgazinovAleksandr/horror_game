extends Area3D
class_name CorridorEvent

# One-shot trigger volume. corridor.gd creates these along the corridor and
# connects `fired` to the matching event behaviour (slam, chime, lights-out...).

signal fired

var _done: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _done or not body is CharacterBody3D:
		return
	_done = true
	fired.emit()
