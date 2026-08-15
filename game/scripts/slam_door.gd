extends StaticBody3D
class_name SlamDoor

# Interior chase door — deliberately NOT built on door.gd (its UnlockCondition /
# extra_lock / advances_level machinery is irrelevant baggage here). Press E while
# passing through to slam it shut behind you; while closed, the level orchestrator's
# per-frame scan (level_6_breach.gd::_tick_slam_doors) checks whether it's blocking
# Object 12's current path and, if so, calls start_battering(), which in turn calls
# the creature's force_block() — a temporary delay, not a permanent block, matching
# a Nemesis-style chase rather than a puzzle lock.

signal slammed
signal broken_open

@export var batter_time: float = 10.0

const THUD_INTERVAL := 0.6
const INTERACTABLE_LAYER := 2   # matches note.gd — raycast-hittable, pass-through for movement

var _closed: bool = false
var _battering: bool = false
var _batter_t: float = 0.0
var _thud_t: float = 0.0

var _hinge: Node3D
var _panel: MeshInstance3D
var _collider: CollisionShape3D
var _block_body: StaticBody3D
var _block_collider: CollisionShape3D
var _batter_audio: AudioStreamPlayer3D


func _ready() -> void:
	_build_frame()
	_build_visual()

	# ⚠️ A raycast never reports a hit against a DISABLED CollisionShape3D. This
	# body's own collider used to start disabled (meant to represent "open, not
	# physically blocking") and only got re-enabled from INSIDE interact() — which
	# made it undetectable by the player's interact ray from the very start: a real
	# playtest could never get a "Press E" prompt on this door at all (found
	# 2026-07-24 — the automated win-path test missed it because it called
	# interact() directly, never through the player's actual raycast/prompt path).
	#
	# Fix: split into two bodies. THIS body's collider is always enabled, on the
	# pass-through interactable layer (note.gd's exact convention: raycast-hittable,
	# invisible to normal movement collision) — it exists purely so E always finds
	# this door. Physical blocking is a separate child body below, since
	# collision_layer/mask apply to a whole body, not per-shape, so one body can't
	# be "always raycastable, sometimes solid" on its own.
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	_collider = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# ⚠️ DEPTH 1.2, NOT 0.1 (2026-08-15). `purge_chamber.gd:43-49` had this exact fault
	# fixed on the 2026-07-24 playtest and wrote down why: "the raycast-hittable box used
	# to match the physical panel exactly — a razor-thin slab at the doorway plane… a
	# player glancing back at the creature or approaching off-axis would miss the z-depth
	# entirely." SlamDoor was never given the same fix and was THINNER still, on doors the
	# player is walking THROUGH (so the approach is routinely oblique) while being chased.
	# Reported as "you need to stand very close" in Levels 6 and 7 — the two levels that
	# are the only users of this class.
	#
	# ⚠️ It is also what de-conflicts this shape from the blocker below. The two used to be
	# identical in size AND position, so on a CLOSED door `intersect_ray` could return
	# `_block_body` — which has no `interact()`, so `player.gd:_is_interactable()` nulled
	# the target and E did nothing in exactly the state you need to reopen it. Depth is
	# what makes the interact box win, the same way PurgeChamber's 1.2 wins over its 0.15.
	#
	# ⚠️ And WIDER than the doorway, offset toward the hinge side, because an OPEN door's
	# art is not where its collider is. `_build_visual()` parks the panel at -100°, which
	# puts it about 0.65 m to -x and 0.54 m to +z of the frame — a metre from the only
	# interactable surface. A player aiming at the door they can SEE got nothing, while a
	# player standing in the empty doorway got the prompt. A CollisionShape3D has to be a
	# direct child of its body, so it cannot simply be parented to the hinge; spanning both
	# positions is the fix that needs no second body and no forwarding script.
	shape.size = Vector3(1.9, 2.2, 1.2)
	_collider.shape = shape
	_collider.position = Vector3(-0.3, 1.1, 0.0)
	add_child(_collider)

	# The actual physical blocker — default layer (matches the player/walls/every
	# other solid thing), only solid while _closed. Also excluded from creature
	# LOS/detection checks by mask (see creature_object12.gd/_has_los,
	# level_6_breach.gd/_has_clear_los) — an open door must not block sight through
	# its own doorway.
	_block_body = StaticBody3D.new()
	add_child(_block_body)
	_block_collider = CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(1.1, 2.2, 0.1)
	_block_collider.shape = bshape
	_block_collider.position.y = 1.1
	_block_collider.disabled = true   # only solid while _closed
	_block_body.add_child(_block_collider)

	_batter_audio = AudioStreamPlayer3D.new()
	var batter := GameState.load_audio("door_batter")
	if batter:
		_batter_audio.stream = batter
	_batter_audio.unit_size = 6.0
	add_child(_batter_audio)


# Static (not part of the hinge, so it never rotates with the panel) — a playtest
# note flagged that the door "looks weird" / "floats in the corridor": swung open,
# the bare panel has nothing anchoring it to a wall, so it reads as a random plank
# rather than a door. A visible frame around the closed-door envelope fixes that in
# BOTH states — closed, it reads as a door in a doorway; open, the frame is still
# right there showing what the panel is hinged to.
func _build_frame() -> void:
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.07, 0.07, 0.07)
	frame_mat.metallic = 0.3
	frame_mat.roughness = 0.6

	var jamb_size := Vector3(0.08, 2.3, 0.12)
	for side in [-1.0, 1.0]:
		var jamb := MeshInstance3D.new()
		var jm := BoxMesh.new()
		jm.size = jamb_size
		jamb.mesh = jm
		jamb.position = Vector3(side * 0.62, jamb_size.y * 0.5, 0.0)
		jamb.set_surface_override_material(0, frame_mat)
		add_child(jamb)

	var lintel := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(1.36, 0.1, 0.12)
	lintel.mesh = lm
	lintel.position = Vector3(0.0, 2.25, 0.0)
	lintel.set_surface_override_material(0, frame_mat)
	add_child(lintel)


func _build_visual() -> void:
	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.16, 0.15, 0.13)
	door_mat.metallic = 0.4
	door_mat.roughness = 0.5

	_hinge = Node3D.new()
	_hinge.position = Vector3(-0.55, 0.0, 0.0)
	_hinge.rotation_degrees.y = -100.0   # starts open, swung clear of the doorway
	add_child(_hinge)

	_panel = MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(1.1, 2.2, 0.06)
	_panel.mesh = pm
	_panel.position = Vector3(0.55, 1.1, 0.0)
	_panel.set_surface_override_material(0, door_mat)
	_hinge.add_child(_panel)


# ⚠️ Player-reopenable (found 2026-07-24 playtest): interact() used to be one-way —
# once _closed, E did nothing, because the ONLY reopen path was the creature battering
# it via level_6_breach.gd::_tick_slam_doors(), which early-returns while the creature
# is still in PATROL (i.e. the whole familiarization window, or any time it hasn't
# noticed the player). Corridor1 <-> Junction1 has no bypass — a player who slammed it
# early softlocked themselves with no way back and no way forward. Toggling lets the
# player undo their own slam any time the creature isn't already mid-batter.
func interact() -> void:
	if _closed:
		if _battering:
			return   # the creature is already breaking it down; don't fight the tween
		_set_closed(false)   # player can reopen their own slam — see softlock note above interact()
		return
	_set_closed(true)
	slammed.emit()
	var player := get_tree().get_first_node_in_group("player")
	var fleeing: bool = false
	if player and player.has_method("get_horizontal_speed"):
		fleeing = player.get_horizontal_speed() > 3.0
	var slam := GameState.load_audio("door_slam")
	if slam:
		var pl := AudioStreamPlayer3D.new()
		pl.stream = slam
		pl.unit_size = 6.0
		pl.volume_db = 2.0 if fleeing else 0.0
		add_child(pl)
		pl.finished.connect(pl.queue_free)
		pl.play()


# Called by the level orchestrator once it determines this door is between the
# creature and its current target. Idempotent — repeated calls while already
# battering just keep the existing countdown.
func start_battering(creature: Node) -> void:
	if not _closed or _battering:
		return
	_battering = true
	_batter_t = batter_time
	_thud_t = 0.0
	if creature and creature.has_method("force_block"):
		creature.force_block(batter_time)


func check_blocks_path(from: Vector3, to: Vector3) -> bool:
	if not _closed:
		return false
	var col_shape := _collider.shape as BoxShape3D
	if not col_shape:
		return false
	var half := col_shape.size * 0.5
	var local_from := to_local(from)
	local_from.y -= _collider.position.y
	var local_to := to_local(to)
	local_to.y -= _collider.position.y
	var aabb := AABB(-half, col_shape.size)
	# ⚠️ AABB.intersects_segment() returns a VARIANT, not a bool — the intersection
	# POINT (Vector3) on a hit and null on a miss. Returning it straight out of a
	# `-> bool` function is a hard runtime type error, which drops the game window:
	# every SlamDoor crashed the level the moment the player slammed one AND Object 12
	# left PATROL (the two guards above). Found 2026-07-27 in the user's own Godot logs;
	# the BackDoor/ExitDoor "worked" only because door.gd has no check_blocks_path.
	return aabb.intersects_segment(local_from, local_to) != null


func _process(delta: float) -> void:
	if not _battering:
		return
	_batter_t -= delta
	_thud_t -= delta
	if _thud_t <= 0.0:
		_thud_t = THUD_INTERVAL
		if _batter_audio.stream:
			_batter_audio.play()
		var player := get_tree().get_first_node_in_group("player")
		if player and player.has_method("jolt_camera"):
			player.jolt_camera(0.05, 0.3)
	if _batter_t <= 0.0:
		_break_open()


func _break_open() -> void:
	_battering = false
	_batter_t = 0.0
	_set_closed(false)
	broken_open.emit()
	var brk := GameState.load_audio("door_break")
	if brk:
		var pl := AudioStreamPlayer3D.new()
		pl.stream = brk
		pl.unit_size = 6.0
		add_child(pl)
		pl.finished.connect(pl.queue_free)
		pl.play()


func _set_closed(v: bool) -> void:
	_closed = v
	_block_collider.disabled = not v
	var target_deg := 0.0 if v else -100.0
	var tween := create_tween()
	tween.tween_property(_hinge, "rotation_degrees:y", target_deg, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
