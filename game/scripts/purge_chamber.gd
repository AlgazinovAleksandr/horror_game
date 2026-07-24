extends StaticBody3D
class_name PurgeChamber

# The one-shot, permanent escalation of SlamDoor — the level's ONLY true win
# condition. Sits at the PurgeAnte -> Incinerator threshold. interact() slams a heavy
# blast door, then checks the creature's ACTUAL position against the Incinerator
# room's bounds — never a flag, the same "physics-driven, not speculative" discipline
# this project's own tests hold themselves to (Issue 16's lesson, applied to real game
# logic here rather than just a test). If the creature is inside, it's purged for
# good; if not, the door reopens so a mistimed lure is retryable, not a run-ender.

signal creature_trapped

@export var creature_path: NodePath
@export var trap_bounds: AABB = AABB(Vector3(-3.5, -0.5, -3.5), Vector3(7.0, 4.0, 7.0))

const CLOSE_TO_CONFIRM_DELAY := 1.2
const PURGE_SEQUENCE_DELAY := 2.5
const INTERACTABLE_LAYER := 2   # matches note.gd — raycast-hittable, pass-through for movement

var _used: bool = false
var _creature: Node = null
var _hinge: Node3D
var _panel: MeshInstance3D
var _collider: CollisionShape3D
var _block_body: StaticBody3D
var _block_collider: CollisionShape3D


func _ready() -> void:
	_build_frame()
	_build_visual()

	# Same fix as slam_door.gd, and the exact same bug it fixes — see that file for
	# the full story. This body's collider is always enabled, on the pass-through
	# interactable layer, purely so E always finds this door regardless of open/
	# closed state. Physical blocking (and creature LOS through the open doorway)
	# is owned by the separate body below.
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	_collider = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# ⚠️ Widened 2026-07-24 playtest: the raycast-hittable box used to match the physical
	# panel exactly (2.2 x 3.0 x 0.15) — a razor-thin slab at the doorway plane. This is
	# the level's ONLY permanent win condition and it's meant to be triggered while being
	# chased, so a player glancing back at the creature or approaching off-axis would miss
	# the 0.15 m z-depth entirely. Depth alone increased (not width/height, which were
	# already generous) so the interact ray has real margin along the approach axis.
	shape.size = Vector3(2.2, 3.0, 1.2)
	_collider.shape = shape
	_collider.position.y = 1.5
	add_child(_collider)

	_block_body = StaticBody3D.new()
	add_child(_block_body)
	_block_collider = CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(2.2, 3.0, 0.15)
	_block_collider.shape = bshape
	_block_collider.position.y = 1.5
	_block_collider.disabled = true
	_block_body.add_child(_block_collider)


# Static (not part of the hinge) — same fix as slam_door.gd's _build_frame(), scaled
# up for this door's larger 2.2x3.0 panel. See that file for why: without it, a
# swung-open panel has nothing anchoring it to the wall it's supposedly hinged to.
func _build_frame() -> void:
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.1, 0.1, 0.11)
	frame_mat.metallic = 0.6
	frame_mat.roughness = 0.4

	var jamb_size := Vector3(0.1, 3.1, 0.16)
	for side in [-1.0, 1.0]:
		var jamb := MeshInstance3D.new()
		var jm := BoxMesh.new()
		jm.size = jamb_size
		jamb.mesh = jm
		jamb.position = Vector3(side * 1.18, jamb_size.y * 0.5, 0.0)
		jamb.set_surface_override_material(0, frame_mat)
		add_child(jamb)

	var lintel := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(2.46, 0.12, 0.16)
	lintel.mesh = lm
	lintel.position = Vector3(0.0, 3.05, 0.0)
	lintel.set_surface_override_material(0, frame_mat)
	add_child(lintel)


func _build_visual() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.14, 0.14, 0.15)
	steel.metallic = 0.7
	steel.roughness = 0.4

	_hinge = Node3D.new()
	_hinge.position = Vector3(-1.1, 0.0, 0.0)
	_hinge.rotation_degrees.y = -95.0
	add_child(_hinge)

	_panel = MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(2.2, 3.0, 0.15)
	_panel.mesh = pm
	_panel.position = Vector3(1.1, 1.5, 0.0)
	_panel.set_surface_override_material(0, steel)
	_hinge.add_child(_panel)


func _resolve_creature() -> bool:
	if _creature and is_instance_valid(_creature):
		return true
	if creature_path.is_empty():
		return false
	_creature = get_node_or_null(creature_path)
	return _creature != null


func interact() -> void:
	if _used:
		return
	_used = true
	_set_closed(true)
	# Freeze the creature the INSTANT the door seals, not after the confirm/purge
	# delays below — CHASE_SPEED closes a few metres in well under a second, so a
	# player who successfully lured it in and sealed the door was still getting
	# killed before the win ever registered (found by tests/walk_level6_breach.gd).
	if _resolve_creature() and _creature.has_method("freeze_for_purge"):
		_creature.freeze_for_purge()
	var slam := GameState.load_audio("blast_door_slam")
	if slam:
		var pl := AudioStreamPlayer3D.new()
		pl.stream = slam
		pl.unit_size = 8.0
		add_child(pl)
		pl.finished.connect(pl.queue_free)
		pl.play()
	get_tree().create_timer(CLOSE_TO_CONFIRM_DELAY).timeout.connect(_confirm_trap)


func _confirm_trap() -> void:
	if not _resolve_creature():
		_reopen_failed()
		return
	var pos: Vector3 = _creature.get_creature_position() if _creature.has_method("get_creature_position") else (_creature as Node3D).global_position
	if trap_bounds.has_point(pos):
		_run_purge_sequence()
	else:
		if _creature.has_method("unfreeze_for_purge"):
			_creature.unfreeze_for_purge()
		_reopen_failed()


func _run_purge_sequence() -> void:
	# Reuses acid_hiss.wav from level_5_kontur — GameState.load_audio() already scans
	# every audio subdir, so no file copy is needed.
	var hiss := GameState.load_audio("acid_hiss")
	if hiss:
		var pl := AudioStreamPlayer3D.new()
		pl.stream = hiss
		pl.unit_size = 8.0
		add_child(pl)
		pl.finished.connect(pl.queue_free)
		pl.play()
	get_tree().create_timer(PURGE_SEQUENCE_DELAY).timeout.connect(_finish_purge)


func _finish_purge() -> void:
	if _creature and _creature.has_method("lure_into_trap"):
		_creature.lure_into_trap()
	creature_trapped.emit()


func _reopen_failed() -> void:
	_used = false
	ScreenText.toast(get_tree(), "IT ISN'T IN THERE")
	get_tree().create_timer(1.0).timeout.connect(func(): _set_closed(false))


func _set_closed(v: bool) -> void:
	_block_collider.disabled = not v
	var target_deg := 0.0 if v else -95.0
	var tween := create_tween()
	tween.tween_property(_hinge, "rotation_degrees:y", target_deg, 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
