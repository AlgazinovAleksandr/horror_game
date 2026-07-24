extends StaticBody3D
class_name HouseMap

# The House's cellar-key quest (new feature, replacing last session's Landing
# 2-drawer search): a folded paper map, currently on a stand in the Bathroom.
# interact() opens the 2D maze-chase minigame (maze_chase_ui.gd) as a paused
# full-screen overlay. Winning it pops a "Collect the key." toast, frees this
# prop, and emits `won` — the level (level_2.gd) reacts by spawning the real 3D
# key at this exact spot. Getting caught by the maze's monster is handled
# entirely here — a jolt + a one-time panic hit, then the map is interactable
# again for a retry (a fresh maze is generated every attempt).

const _NOTE_SCRIPT := preload("res://scripts/note.gd")

# Bracketed between beartrap.gd's ESCAPE_INITIAL_PANIC (15, a clean single fail)
# and ESCAPE_FAIL_PANIC (40, a true multi-attempt QTE fail) — a maze catch is a
# single clean fail-and-retry, but ejects the player entirely rather than
# offering an escape window, so it sits just above the lighter of those two.
const CATCH_PANIC := 18.0

signal won

var _solved: bool = false
var _ui: MazeChaseUI


func _ready() -> void:
	_style_mesh()
	_ui = MazeChaseUI.new()
	_ui.won.connect(_on_won)
	_ui.caught.connect(_on_caught)
	add_child(_ui)


func _style_mesh() -> void:
	var mesh := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.3, 0.24)
	mesh.mesh = qm
	mesh.rotation = Vector3(-PI / 2.0, 0, 0)  # lie flat, face up, same as the key
	mesh.set_surface_override_material(0, _NOTE_SCRIPT.paper_material(false))
	add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.34, 0.1, 0.28)
	col.shape = shape
	add_child(col)


func interact() -> void:
	if _solved:
		ScreenText.toast(get_tree(), "Already found it.", Color(0.75, 0.75, 0.75))
		return
	_ui.open()


func _on_won() -> void:
	_solved = true
	# Playtest: on a win, pop a clear "go get it" message, and the map itself
	# should vanish rather than linger as a solved-but-still-there prop — the
	# level spawns the real key at this exact spot once the map is gone.
	ScreenText.toast(get_tree(), "Collect the key.", Color(0.4, 1.0, 0.4))
	won.emit()
	queue_free()


func _on_caught() -> void:
	var p := get_tree().current_scene.get_node_or_null("Player")
	if p and p.has_method("jolt_camera"):
		p.jolt_camera(0.09, 0.45)
	if p and p.has_method("add_panic"):
		p.add_panic(CATCH_PANIC)
