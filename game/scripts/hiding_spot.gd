extends StaticBody3D
class_name HidingSpot

# A locker / cabinet / desk the player can duck into to break Object 12's detection.
# interact() toggles hiding via player.gd's enter_hiding()/exit_hiding() — reuses the
# existing E -> _try_interact() path, no new input action. Self-builds its own mesh,
# same convention as every other prop in this codebase (beartrap.gd, key_item.gd).
#
# The door is a real hinged panel (mirrors slam_door.gd's hinge-tween pattern) that
# visibly swings open then shut on every interact() — entering AND exiting both play
# the same open-then-close beat, so the prop always settles back to its normal closed
# look. This is deliberately paired with player.gd's own reposition/FOV/overlay
# changes on enter_hiding(): the door swing alone isn't enough to sell "you are
# inside something" (a closed locker viewed from 0.4m away still just reads as a
# closed locker) — see player.gd for the rest of that.

@export var prop_kind: String = "locker"   # "locker" | "cabinet" | "desk"

const DOOR_OPEN_DEG := -110.0
const DOOR_SWING_TIME := 0.18
const DOOR_HOLD_OPEN := 0.22

var _occupied: bool = false
var _hinge: Node3D


func _ready() -> void:
	_build_visual()
	# ⚠️ The interact volume is the carcass GROWN FORWARD, not the carcass (2026-08-15).
	# Two reasons, both reported as "you have to stand very close" in Levels 6 and 7:
	#
	#   * `wall_point(room, side, 0.0, 0.22)` mounts these against a wall, which buries
	#     ~0.18 m of the box inside it and leaves only ~0.42 m protruding to be hit.
	#   * the swinging door is a child of `_hinge` and is NOT covered by this shape, so an
	#     open locker's art stands clear of the only interactable surface (the same fault
	#     as slam_door.gd — see the note there).
	#
	# Growing depth and pushing the volume into the room covers both without changing what
	# is drawn. A desk is 0.9 m tall, so the height is floored to keep it findable by a ray
	# from a camera at 1.65 rather than only by one aimed at the floor.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var size := _kind_size()
	shape.size = Vector3(size.x + 0.35, maxf(size.y, 1.3), size.z + 0.6)
	col.shape = shape
	col.position = Vector3(0.0, shape.size.y * 0.5, size.z * 0.35)
	add_child(col)


func is_occupied() -> bool:
	return _occupied


# A point just in front of the door, at floor height — player.gd repositions here on
# enter_hiding() so the player ends up facing the (now-closing) door instead of
# staying wherever they happened to be standing when they pressed E.
func hide_anchor() -> Vector3:
	var size := _kind_size()
	return global_position + global_transform.basis.z * (size.z * 0.5 + 0.4)


# Handles BOTH directions: player.gd's _try_interact() routes here on the normal
# raycast to enter, and routes here directly (bypassing the raycast, which is
# unreliable from inside the spot's own collider) to exit.
func interact() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return
	if _occupied:
		_occupied = false
		_swing_door()
		if player.has_method("exit_hiding"):
			player.exit_hiding()
	else:
		if player.has_method("is_hidden") and player.is_hidden():
			return  # already hiding somewhere else
		_occupied = true
		if player.has_method("enter_hiding"):
			player.enter_hiding(self)
		_swing_door()


func _swing_door() -> void:
	if not _hinge:
		return
	var tween := create_tween()
	tween.tween_property(_hinge, "rotation_degrees:y", DOOR_OPEN_DEG, DOOR_SWING_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(DOOR_HOLD_OPEN)
	tween.tween_property(_hinge, "rotation_degrees:y", 0.0, DOOR_SWING_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _kind_size() -> Vector3:
	match prop_kind:
		"cabinet":
			return Vector3(0.8, 1.6, 0.5)
		"desk":
			return Vector3(1.2, 0.9, 0.7)
		_:
			return Vector3(0.7, 2.0, 0.6)   # locker


func _door_texture_path() -> String:
	match prop_kind:
		"cabinet":
			return "res://assets/textures/level_6_breach/hiding_cabinet_front.png"
		"desk":
			return "res://assets/textures/level_6_breach/hiding_desk_front.png"
		_:
			return "res://assets/textures/level_6_breach/hiding_locker_front.png"


func _build_visual() -> void:
	var size := _kind_size()

	# The carcass stays a dark, unremarkable box — the door panel carries the art,
	# per Issue 24 (never texture a BoxMesh face directly; art goes on a QuadMesh).
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.08, 0.08, 0.08)
	body_mat.roughness = 0.85

	var body_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	body_mesh.mesh = bm
	body_mesh.position.y = size.y * 0.5
	body_mesh.set_surface_override_material(0, body_mat)
	add_child(body_mesh)

	_build_door(size)


func _build_door(size: Vector3) -> void:
	_hinge = Node3D.new()
	_hinge.position = Vector3(-size.x * 0.5, size.y * 0.5, size.z * 0.5)
	add_child(_hinge)

	var door := MeshInstance3D.new()
	var dq := QuadMesh.new()
	dq.size = Vector2(size.x, size.y)
	door.mesh = dq
	# QuadMesh is centered on its own origin; offset so its LEFT edge sits at the
	# hinge pivot (matches slam_door.gd's exact hinge/panel offset convention).
	door.position = Vector3(size.x * 0.5, 0, 0.01)

	var door_mat := StandardMaterial3D.new()
	var tex_path := _door_texture_path()
	if ResourceLoader.exists(tex_path):
		door_mat.albedo_texture = load(tex_path)
	else:
		door_mat.albedo_color = Color(0.18, 0.14, 0.1) if prop_kind == "desk" else Color(0.15, 0.16, 0.15)
	door_mat.roughness = 0.7
	door_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	door.set_surface_override_material(0, door_mat)
	_hinge.add_child(door)
