extends StaticBody3D
class_name KonturMailbox

# KONTUR Landing's mailbox, upgraded from a flat wall decal (debug capture #9: "make
# these objects 3D") into a real shallow interactable that opens on a hidden note.
# The level (kontur.gd) builds the mesh/collider as children and sets `hint_text` —
# this script only owns the interaction, same division of labor as key_item.gd.

@export var hint_text: String = ""


func interact() -> void:
	NoteUI.show_note(hint_text)
