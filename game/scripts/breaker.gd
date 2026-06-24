extends StaticBody3D
class_name Breaker

# A power breaker switch for the Lab's restore-power quest. interact() flips it
# once (lever drops, indicator goes red->green, clunk) and emits `flipped`. The
# level counts flips and, on the third, restores power + opens the morgue shutter.
# Self-building from primitives.

signal flipped

var _done: bool = false
var _lever: CSGBox3D
var _lever_mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build()


const PANEL_TEX := "res://assets/textures/level_1_lab/lab_breaker_panel.png"


func _build() -> void:
	var panel := CSGBox3D.new()
	panel.size = Vector3(0.7, 1.0, 0.12)
	var pm := StandardMaterial3D.new()
	if ResourceLoader.exists(PANEL_TEX):
		# The fuse-box art reads as a real electrical panel instead of a grey box.
		pm.albedo_texture = load(PANEL_TEX)
		pm.emission_enabled = true
		pm.emission_texture = load(PANEL_TEX)
		pm.emission_energy_multiplier = 0.25
	else:
		pm.albedo_color = Color(0.18, 0.18, 0.2)
		pm.metallic = 0.6
		pm.roughness = 0.5
	panel.material = pm
	add_child(panel)

	_lever = CSGBox3D.new()
	_lever.size = Vector3(0.12, 0.26, 0.12)
	_lever.position = Vector3(0.22, 0.0, 0.1)
	_lever_mat = StandardMaterial3D.new()
	_lever_mat.albedo_color = Color(0.8, 0.1, 0.05)
	_lever_mat.emission_enabled = true
	_lever_mat.emission = Color(0.7, 0.05, 0.02)
	_lever_mat.emission_energy_multiplier = 0.7
	_lever.material = _lever_mat
	add_child(_lever)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.8, 1.1, 0.3)
	col.shape = shape
	add_child(col)


func interact() -> void:
	if _done:
		return
	_done = true
	var t := create_tween()
	t.tween_property(_lever, "position:y", -0.14, 0.18)
	_lever_mat.albedo_color = Color(0.1, 0.8, 0.2)
	_lever_mat.emission = Color(0.05, 0.7, 0.1)
	var clunk := GameState.load_audio("breaker_throw")
	if not clunk:
		clunk = GameState.load_audio("light_pop")
	if clunk:
		var p := AudioStreamPlayer3D.new()
		p.stream = clunk
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
	flipped.emit()
