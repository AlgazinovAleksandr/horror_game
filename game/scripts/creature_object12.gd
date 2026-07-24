extends Node3D
class_name CreatureObject12

# Level 6 — THE BREACH. Object 12, KONTUR's subject, loose. A persistent Nemesis/Mr.X
# -style pursuer: dormant until the level calls activate() (the familiarization window
# is owned by level_6_breach.gd, not here), then patrols a level-supplied waypoint
# loop, escalates to INVESTIGATE on noise, and once it has line-of-sight on the player
# it CLOSES DISTANCE EVERY FRAME in CHASE regardless of whether it is being watched —
# the deliberate opposite of creature_stalker.gd's Weeping-Angel "freeze while
# observed" rule, which would let a persistent chaser be cheesed by simply staring at
# it. Losing the player doesn't reset to PATROL: it walks to the last-seen position and
# scans there for a while first (SEARCH) — the one Mr.X/Alien:Isolation lesson worth
# stealing, because it's what makes hiding feel tense instead of a free reset.
#
# Contact is instant-fatal, exactly like every other creature in the game — no grab or
# struggle QTE. Sustained aimed flashlight (apply_light_damage(), driven every frame by
# the level orchestrator, which owns the "is the player actually aiming at it" check)
# drains a shield and stops it in STAGGERED for STAGGER_DURATION — a temporary repel,
# not a kill. The only permanent defeat is being lured into the level's PurgeChamber,
# which calls lure_into_trap() directly.

signal state_changed(old: int, new: int)
signal staggered(duration: float)
signal recovered()
signal contact_fatal()

enum State { PATROL, INVESTIGATE, CHASE, SEARCH, STAGGERED }

const PATROL_SPEED := 1.8
const INVESTIGATE_SPEED := 2.6
# Must beat the player's walk (player.gd SPEED = 4.0) or it's not a threat; must lose
# to the player's sprint (SPEED * SPRINT_MULTIPLIER = 6.4) or sprinting is pointless.
const CHASE_SPEED := 5.0
const CONTACT_DIST := 1.0
const DETECT_RANGE := 10.0
const FOV_DOT := 0.5           # wide cone (~120 deg) — this creature actively hunts
const CHEST := 0.9
const SEARCH_TIME := 8.0
const INVESTIGATE_GIVEUP_TIME := 6.0
const WAYPOINT_ARRIVE_DIST := 0.6
const LOS_LOSS_GRACE := 0.4    # forgiveness window before CHASE -> SEARCH
const SEARCH_SCAN_SPEED_DEG := 40.0
const SHIELD_MAX := 100.0
const SHIELD_DRAIN_RATE := 40.0   # ~2.5s of sustained aimed light to stagger
const SHIELD_REGEN_DELAY := 3.0
const SHIELD_REGEN_RATE := 15.0
const STAGGER_DURATION := 25.0
const STAGGER_TILT_DEG := 35.0

var _player: CharacterBody3D
var _camera: Camera3D
var _body: StaticBody3D
var _body_collider: CollisionShape3D
var _visual_root: Node3D
var _space: PhysicsDirectSpaceState3D

var _state: int = State.PATROL
var _active: bool = false

var _waypoints: PackedVector3Array = PackedVector3Array()
var _wp_index: int = 0
var _investigate_target: Vector3 = Vector3.ZERO
var _investigate_t: float = 0.0
var _last_seen_pos: Vector3 = Vector3.ZERO
var _search_t: float = 0.0
var _los_lost_t: float = 0.0
var _stagger_t: float = 0.0
var _block_t: float = 0.0   # set by force_block(); pauses movement under any state

var _shield: float = SHIELD_MAX
var _shield_idle_t: float = 0.0
var _material: StandardMaterial3D   # shared retint material, tweened for the wound flash


func _ready() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			child.queue_free()

	# Same transform-chain discipline as creature_stalker.gd (Issue 10): ScaryObject
	# is a plain Node with no transform, so the world position lives on _body, not
	# on the ScaryObject or this outer Node3D. scare_intensity is 0 — this creature's
	# fail states are driven directly (contact, detection), not gaze-panic.
	var scary := ScaryObject.new()
	scary.scare_intensity = 0.0
	add_child(scary)
	_body = StaticBody3D.new()
	scary.add_child(_body)
	_body.global_transform = global_transform
	_body_collider = CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.7
	_body_collider.shape = shape
	_body_collider.position.y = 0.85
	_body.add_child(_body_collider)

	_build_visual()


const _GLB_PATH := "res://assets/models/Void_creature.glb"

func _build_visual() -> void:
	if ResourceLoader.exists(_GLB_PATH):
		_build_visual_glb()
	else:
		_build_visual_procedural()
	_apply_retint()


func _build_visual_glb() -> void:
	var scene: PackedScene = load(_GLB_PATH)
	var instance: Node3D = scene.instantiate()
	_visual_root = instance
	_body.add_child(instance)
	# Blender adds a stray base cube to the export — remove it, keep only the character.
	var cube := instance.get_node_or_null("Cube")
	if cube:
		cube.queue_free()
	_pose_arms_down(instance)


# The Mixamo GLB ships in bind T-pose with no animation track (same model
# creature_stalker.gd uses) — override the upper-arm bone poses so it doesn't read as
# a broken scarecrow.
const _ARM_DROP_DEG := 80.0
const _FOREARM_TUCK_DEG := 12.0

func _pose_arms_down(instance: Node3D) -> void:
	var skel := instance.find_child("Skeleton3D", true, false) as Skeleton3D
	if not skel:
		return
	_rotate_bone(skel, "mixamorig_LeftArm", deg_to_rad(_ARM_DROP_DEG))
	_rotate_bone(skel, "mixamorig_RightArm", deg_to_rad(-_ARM_DROP_DEG))
	_rotate_bone(skel, "mixamorig_LeftForeArm", deg_to_rad(_FOREARM_TUCK_DEG))
	_rotate_bone(skel, "mixamorig_RightForeArm", deg_to_rad(-_FOREARM_TUCK_DEG))


func _rotate_bone(skel: Skeleton3D, bone_name: String, angle_z: float) -> void:
	var idx := skel.find_bone(bone_name)
	if idx == -1:
		return
	var rest := skel.get_bone_rest(idx)
	skel.set_bone_pose_rotation(idx, rest.basis.get_rotation_quaternion() * Quaternion(Vector3.FORWARD, angle_z))


func _build_visual_procedural() -> void:
	_visual_root = Node3D.new()
	_body.add_child(_visual_root)

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.02, 0.02)
	dark.roughness = 1.0

	var torso := MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.15
	torso_mesh.height = 2.2
	torso.mesh = torso_mesh
	torso.position.y = 1.2
	torso.set_surface_override_material(0, dark)
	_visual_root.add_child(torso)

	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.38, 0.06, 0.07)
		arm.mesh = arm_mesh
		arm.set_surface_override_material(0, dark)
		arm.position = Vector3(side * 0.24, 1.7, 0.0)
		arm.rotation_degrees.z = -side * 18.0
		_visual_root.add_child(arm)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.16
	head_mesh.height = 0.32
	head.mesh = head_mesh
	head.position.y = 2.45
	head.set_surface_override_material(0, dark)
	_visual_root.add_child(head)


# Distinguishes Object 12 from the Void's identical GLB by palette alone (v1 has no
# new 3D asset). This same material is what apply_light_damage()'s wound flash tweens.
func _apply_retint() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.35, 0.4, 0.32)
	_material.roughness = 0.9
	_material.emission_enabled = true
	_material.emission = Color(0.4, 0.05, 0.05)
	_material.emission_energy_multiplier = 0.35   # stays under 1.0 — Issue 21, no glow/tonemap
	for mi in _find_mesh_instances(_visual_root):
		mi.material_override = _material


func _find_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_mesh_instances(child))
	return out


# ------------------------------------------------------------------ level wiring

# Called once by level_6_breach.gd after RoomBuilder.build() — keeps this script
# graph-agnostic, matching how no existing creature ever reads RoomBuilder directly.
func set_waypoints(points: PackedVector3Array) -> void:
	_waypoints = points
	_wp_index = 0


# The familiarization window is level-owned (see level_6_breach.gd); until this is
# called the creature stays motionless at its spawn point.
func activate() -> void:
	_active = true


func get_state() -> int:
	return _state


func get_shield_ratio() -> float:
	return _shield / SHIELD_MAX


func get_creature_position() -> Vector3:
	return _body.global_position if _body else global_position


# Used by the level's light-weapon raycast so it excludes the creature's own
# collider (otherwise the ray from camera to creature hits the creature itself
# just short of the endpoint and reads as "blocked").
func get_body_rid() -> RID:
	return _body.get_rid() if _body else RID()


# Where the creature is currently headed — used by SlamDoor's path-block scan.
func get_current_target() -> Vector3:
	match _state:
		State.CHASE:
			return _player.global_position if _player else get_creature_position()
		State.INVESTIGATE:
			return _investigate_target
		State.SEARCH:
			return _last_seen_pos
		_:
			return get_creature_position()


# Player sprinting or a slammed door within earshot — escalates PATROL -> INVESTIGATE.
func notify_noise(pos: Vector3, radius: float) -> void:
	if not _active or _state != State.PATROL:
		return
	if get_creature_position().distance_to(pos) > radius:
		return
	_investigate_target = pos
	_investigate_t = 0.0
	_enter(State.INVESTIGATE)


# Called every frame by the level orchestrator while it determines the player is
# aiming a lit flashlight at this creature within FOV+LOS (mirrors _detect_player's
# raycast shape, camera -> creature instead of creature -> camera).
func apply_light_damage(delta: float) -> void:
	if not _active or _state == State.STAGGERED:
		return
	_shield_idle_t = 0.0
	_shield = maxf(0.0, _shield - SHIELD_DRAIN_RATE * delta)
	_update_wound_tint()
	if _shield <= 0.0 and (_state == State.CHASE or _state == State.INVESTIGATE):
		_enter_stagger()


# A SlamDoor blocking the creature's current path calls this. Movement pauses under
# WHATEVER state is active without changing state — a chased player who breaks LOS
# while the door is being battered should still transition CHASE -> SEARCH the instant
# the door timer ends, not get reset to CHASE blindly.
func force_block(seconds: float) -> void:
	_block_t = maxf(_block_t, seconds)


# PurgeChamber calls this the INSTANT the player seals the blast door — before its
# own confirmation delay, not after. Reuses force_block()'s pause (all ticking,
# including the contact check, stops) with a large sentinel duration.
#
# ⚠️ This one exists because a walk-to-win test caught a real bug: PurgeChamber
# used to wait ~1.2s to confirm the creature was inside, then another ~2.5s for the
# purge sequence, before ever calling lure_into_trap() — CHASE_SPEED (5.0) closes a
# few metres in well under a second, so a player who successfully lured the
# creature in and sealed the door was still getting killed by it before the win
# ever registered. Freezing on interact(), not on confirmation, is what actually
# fixes that: the creature can't hurt you starting the moment you commit to
# sealing it in, regardless of how long the confirm/purge sequence takes.
const _PURGE_FREEZE := 9999.0

func freeze_for_purge() -> void:
	_block_t = _PURGE_FREEZE


# Called by PurgeChamber if the lure attempt failed (creature wasn't inside) — lets
# it resume the chase instead of staying inexplicably frozen after the door reopens.
func unfreeze_for_purge() -> void:
	if _block_t >= _PURGE_FREEZE:
		_block_t = 0.0


# Called only by PurgeChamber after its own physics-position confirmation. Permanent.
func lure_into_trap() -> void:
	_active = false
	set_process(false)
	if _visual_root:
		_visual_root.rotation.x = deg_to_rad(-90.0)


# ------------------------------------------------------------------ state machine

func _process(delta: float) -> void:
	if not _active:
		return
	if not _ensure_player():
		return

	if _block_t > 0.0:
		_block_t = maxf(0.0, _block_t - delta)
		_regen_shield(delta)
		return

	match _state:
		State.PATROL:
			_tick_patrol(delta)
		State.INVESTIGATE:
			_tick_investigate(delta)
		State.CHASE:
			_tick_chase(delta)
		State.SEARCH:
			_tick_search(delta)
		State.STAGGERED:
			_tick_staggered(delta)

	_regen_shield(delta)


func _ensure_player() -> bool:
	if _player and is_instance_valid(_player):
		return true
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if not _player:
		return false
	_camera = _player.get_node_or_null("Camera3D") as Camera3D
	return _camera != null


func _enter(new_state: int) -> void:
	var old := _state
	_state = new_state
	state_changed.emit(old, new_state)


func _tick_patrol(delta: float) -> void:
	if _detect_player():
		_last_seen_pos = _player.global_position
		_enter(State.CHASE)
		return
	_follow_waypoints(delta, PATROL_SPEED)


func _tick_investigate(delta: float) -> void:
	if _detect_player():
		_last_seen_pos = _player.global_position
		_enter(State.CHASE)
		return
	_investigate_t += delta
	if _investigate_t >= INVESTIGATE_GIVEUP_TIME:
		_enter(State.PATROL)
		return
	_move_toward(_investigate_target, INVESTIGATE_SPEED, delta)


func _tick_chase(delta: float) -> void:
	var here := get_creature_position()
	var flat := Vector2(here.x - _player.global_position.x, here.z - _player.global_position.z).length()
	if flat <= CONTACT_DIST:
		_contact()
		return
	_move_toward(_player.global_position, CHASE_SPEED, delta)
	if _detect_player():
		_last_seen_pos = _player.global_position
		_los_lost_t = 0.0
	else:
		_los_lost_t += delta
		if _los_lost_t >= LOS_LOSS_GRACE:
			_search_t = 0.0
			_enter(State.SEARCH)


func _tick_search(delta: float) -> void:
	if _detect_player():
		_last_seen_pos = _player.global_position
		_enter(State.CHASE)
		return
	var here := get_creature_position()
	var to_target := Vector2(_last_seen_pos.x - here.x, _last_seen_pos.z - here.z)
	if to_target.length() > WAYPOINT_ARRIVE_DIST:
		_move_toward(_last_seen_pos, INVESTIGATE_SPEED, delta)
		return
	# Arrived at the last-known position — scan in place for the rest of SEARCH_TIME
	# before giving up. This is the one Mr.X/Alien:Isolation lesson worth keeping:
	# losing the player must not read as a free reset.
	_search_t += delta
	_body.rotation.y += deg_to_rad(SEARCH_SCAN_SPEED_DEG) * delta
	if _search_t >= SEARCH_TIME:
		_wp_index = _nearest_waypoint_index()
		_enter(State.PATROL)


func _tick_staggered(delta: float) -> void:
	_stagger_t += delta
	if _stagger_t >= STAGGER_DURATION:
		_shield = SHIELD_MAX
		_update_wound_tint()
		if _body_collider:
			_body_collider.disabled = false
		if _visual_root:
			_visual_root.rotation.x = 0.0
		# Recovers where it collapsed, not straight back onto the player standing
		# next to it — SEARCH re-detects fairly instead of instantly re-CHASE-ing.
		_last_seen_pos = get_creature_position()
		_search_t = 0.0
		_enter(State.SEARCH)
		recovered.emit()


func _enter_stagger() -> void:
	_enter(State.STAGGERED)
	_stagger_t = 0.0
	# ⚠️ Non-solid while staggered (found 2026-07-24 playtest): the capsule (radius 0.3)
	# stops wherever it happened to be walking, which can be dead-center in a doorway
	# (width as low as 1.6-1.8 m). Each side gap then shrinks to ~0.6 m — less than the
	# player's own capsule diameter (radius 0.4 -> 0.8 m) — so a staggered creature could
	# permanently wall off a corridor. contact_fatal is a pure distance check (CONTACT_DIST,
	# see _detect_player/_contact), never physics collision, so disabling this collider
	# only removes the "solid obstacle" side-effect, not the danger.
	if _body_collider:
		_body_collider.disabled = true
	if _visual_root:
		_visual_root.rotation.x = deg_to_rad(-STAGGER_TILT_DEG)
	staggered.emit(STAGGER_DURATION)


func _contact() -> void:
	if not _active:
		return
	_active = false
	contact_fatal.emit()
	Screamer.trigger()


func _regen_shield(delta: float) -> void:
	if _state == State.STAGGERED:
		return
	_shield_idle_t += delta
	if _shield_idle_t >= SHIELD_REGEN_DELAY and _shield < SHIELD_MAX:
		_shield = minf(SHIELD_MAX, _shield + SHIELD_REGEN_RATE * delta)
		_update_wound_tint()


func _update_wound_tint() -> void:
	if not _material:
		return
	var wound: float = 1.0 - (_shield / SHIELD_MAX)
	_material.emission = Color(0.4, 0.05, 0.05).lerp(Color(1.0, 0.25, 0.15), wound)
	_material.emission_energy_multiplier = lerp(0.35, 0.9, wound)


# ------------------------------------------------------------------ movement / detection

func _follow_waypoints(delta: float, speed: float) -> void:
	if _waypoints.is_empty():
		return
	var target: Vector3 = _waypoints[_wp_index]
	_move_toward(target, speed, delta)
	var here := get_creature_position()
	if Vector2(here.x - target.x, here.z - target.z).length() <= WAYPOINT_ARRIVE_DIST:
		_wp_index = (_wp_index + 1) % _waypoints.size()


func _move_toward(target: Vector3, speed: float, delta: float) -> void:
	var here := get_creature_position()
	var dir := Vector3(target.x - here.x, 0, target.z - here.z)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	_body.global_position = here + dir * speed * delta
	_body.rotation.y = atan2(dir.x, dir.z)


func _nearest_waypoint_index() -> int:
	if _waypoints.is_empty():
		return 0
	var here := get_creature_position()
	var best := 0
	var best_dist := INF
	for i in range(_waypoints.size()):
		var d: float = here.distance_to(_waypoints[i])
		if d < best_dist:
			best_dist = d
			best = i
	return best


# The creature as observer: ray from its chest to the player's camera, FOV cone
# centered on the creature's own facing direction. This is the mirror direction of
# every existing gaze check in the codebase (which is always player -> prop).
func _detect_player() -> bool:
	if _player.has_method("is_hidden") and _player.is_hidden():
		return false
	var here := get_creature_position() + Vector3(0, CHEST, 0)
	var target := _camera.global_position
	var to_player := target - here
	if to_player.length() > DETECT_RANGE:
		return false
	if not _has_los(here, target):
		return false
	# The FOV check compares against the creature's FACING, which is horizontal
	# only (_body.rotation.y). Dotting that against the FULL 3D to-player vector
	# mixes in whatever vertical gap exists between chest height and camera height
	# (CHEST=0.9 vs. the player's ~1.65 eye height) — at close range that vertical
	# component can dominate the vector and fail the dot-product test regardless of
	# facing, making the creature blind to a player standing right next to it (e.g.
	# converged on by a SEARCH scan). Flatten to horizontal for the facing check;
	# height only matters for range/LOS above.
	var flat := Vector2(to_player.x, to_player.z)
	if flat.length() < 0.3:
		return true   # point-blank horizontally — no meaningful facing to check
	var flat_dir := Vector3(flat.x, 0, flat.y).normalized()
	var forward := Vector3(sin(_body.rotation.y), 0, cos(_body.rotation.y))
	return forward.dot(flat_dir) >= FOV_DOT


func _has_los(from: Vector3, to: Vector3) -> bool:
	if not _space:
		_space = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid(), _body.get_rid()]
	# Layer 1 only — the default "solid world geometry" layer. SlamDoor/PurgeChamber
	# expose an ALWAYS-enabled interact collider on layer 2 (note.gd's pass-through
	# convention) so E can always find them; without this mask, that collider would
	# block detection through an open doorway, which a real door wouldn't do.
	query.collision_mask = 1
	return _space.intersect_ray(query).is_empty()
