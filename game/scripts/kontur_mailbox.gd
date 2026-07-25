extends StaticBody3D
class_name KonturMailbox

# KONTUR Landing's mailbox. The level (kontur.gd:_spawn_mailbox) builds the mesh and
# collider as children and sets `hint_text` — this script only owns the interaction,
# the same division of labor as key_item.gd and offering_pedestal.gd.
#
# Rebuilt 2026-07-25 from a flat photo-decal into a real 12-slot bank (playtest
# capture #4). Only SLOT 12 opens: `door_hinge` is handed over by the builder, and
# the first interact() swings it before the note appears, so the note reads as having
# come OUT of the box rather than off the wall. Re-reading afterwards leaves the door
# open — the box has already been opened; closing it again would be a lie.

@export var hint_text: String = ""

const OPEN_ANGLE_DEG := -105.0
const SWING_TIME := 0.35

# Set by the builder, not exported — it is a node from the mesh this script does not
# construct, so there is nothing sensible to point an inspector path at.
var door_hinge: Node3D = null

var _opened: bool = false


func interact() -> void:
	if not _opened:
		_opened = true
		_swing_open()
	NoteUI.show_note(hint_text)


func _swing_open() -> void:
	if not is_instance_valid(door_hinge):
		return
	var creak := GameState.load_audio("creak")
	if creak:
		var p := AudioStreamPlayer3D.new()
		p.stream = creak
		p.unit_size = 5.0
		p.volume_db = -6.0
		add_child(p)
		p.position = door_hinge.position
		p.finished.connect(p.queue_free)
		p.play()
	var t := create_tween()
	t.set_trans(Tween.TRANS_QUAD)
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(door_hinge, "rotation_degrees:y", OPEN_ANGLE_DEG, SWING_TIME)
