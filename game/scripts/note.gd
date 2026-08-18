extends StaticBody3D

const INTERACTABLE_LAYER := 2  # pass-through for player; raycast still hits this layer

@export var note_text: String = ""
@export var is_trap: bool = false
@export var is_twist_note: bool = false

# Emitted when the player opens this note. The only per-note "was it read?" state
# this project had was the bespoke GameState.twist_read flag, so a puzzle gated on
# reading a specific note had nowhere to hook. Connect it from the level that spawns
# the note (see level_1.gd's maintenance note -> LabLocker.unlocked).
#
# Deliberately fires on OPEN rather than on NoteUI.closed: these notes are four lines
# long, and "read to the end" is a mechanic reserved for trap notes, where staying in
# is what kills you.
signal read


const PAPER_TEX := "res://assets/textures/shared/note_paper.png"


func _ready() -> void:
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	_style_mesh()
	# _enlarge_collision()


# Build the material a note sheet should wear. Shared with the levels that spawn
# notes procedurally (level_1.gd / level_2.gd `_make_note`) so a note looks the
# same whether it came from a .tscn or from code.
#
# note_paper.png sat unused on disk while every note in the game rendered as a
# flat near-black box — the khaki rectangle visible in the House living room.
# The emission is what keeps a sheet of paper findable in these dark levels, so
# it stays even now that there's a texture: albedo carries the paper, emission
# carries the "look at me".
static func paper_material(trap: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.95
	if ResourceLoader.exists(PAPER_TEX):
		mat.albedo_texture = load(PAPER_TEX)
		mat.albedo_color = Color(0.6, 0.25, 0.25) if trap else Color(0.85, 0.82, 0.7)
		mat.emission_enabled = true
		mat.emission_texture = mat.albedo_texture
		mat.emission = Color(0.5, 0.08, 0.08) if trap else Color(0.5, 0.46, 0.33)
		mat.emission_energy_multiplier = 0.5 if trap else 0.6
	else:
		# Pre-texture fallback — the original flat look.
		mat.albedo_color = Color(0.55, 0.15, 0.15) if trap else Color(0.05, 0.05, 0.04)
		mat.emission_enabled = true
		mat.emission = Color(0.4, 0.05, 0.05) if trap else Color(0.55, 0.5, 0.35)
		mat.emission_energy_multiplier = 0.5 if trap else 0.6
	return mat


func _style_mesh() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			child.set_surface_override_material(0, paper_material(is_trap))


# func _enlarge_collision() -> void:
# 	# Notes stand upright (rotated -90° X in scene). Local Z maps to world Y.
# 	# size.z=0.8 gives 0.4m half-height; center at y=1.2 spans y=0.8–1.6.
# 	for child in get_children():
# 		if child is CollisionShape3D:
# 			var box := BoxShape3D.new()
# 			box.size = Vector3(0.35, 0.35, 0.8)
# 			child.shape = box


# Trap notes are read-to-die: the note opens normally, but panic climbs while
# it stays open. Closing early leaves you shaken; reading to the end kills you.
const TRAP_PANIC_RATE := 12.0  # panic per second while a trap note is open


func interact() -> void:
	if is_twist_note:
		GameState.twist_read = true

	# Archive it for the journal (TAB). ⚠️ NON-TRAP ONLY: a trap note is read-to-die,
	# and a safely re-readable copy would let the player open it here, read to the end
	# and learn the text at no cost — deleting the mechanic. Recorded on OPEN, matching
	# `read` below: finding a note is what earns the copy, not surviving it.
	if not is_trap:
		GameState.record_note(note_text, GameState.current_level)

	# Playtest instrumentation only — no gameplay effect, and it strips cleanly with the
	# autoload. Added 2026-08-16 because NOTHING recorded note reads: a playtest log could
	# not distinguish "read all three notes" from "typed the code they already knew", and a
	# session was misread on exactly that ambiguity. `name` rather than `note_text` so the
	# log stays one line and never leaks a trap note's contents into a file the analyst reads
	# before the player has met it.
	var dbg := get_node_or_null("/root/DebugLog")
	if dbg:
		dbg.note("NOTE READ %s%s" % [name, "  (TRAP)" if is_trap else ""])

	read.emit()
	NoteUI.show_note(note_text, TRAP_PANIC_RATE if is_trap else 0.0)
