extends Node3D
class_name CreatureStalker

# The Void's creatures. Each stands motionless until you look at it — then,
# the moment you look away, it closes the distance. Reach you and it lunges into
# the camera and the screamer takes you. Staring to freeze it also feeds panic,
# so you cannot simply watch one forever: look too long and the panic bar fills;
# look away and it advances. Weeping-Angel logic, line-of-sight gated so a
# creature in another room stays dormant until you enter.

const STALK_SPEED := 1.25       # m/s while unobserved — slower than a walk, faster than a crawl
const CONTACT_DIST := 1.25      # horizontal distance that triggers the lunge
const ENGAGE_DIST := 11.0       # ignore the player beyond this (it's in another room)
const FOV_DOT := 0.55           # cos of the half-angle that counts as "looked at"
const GAZE_INTENSITY := 0.6     # mild panic while you stare it down
const CHEST := 0.9              # ray target / facing height
const START_GRACE := 5.0        # opening seconds where nothing hunts — time to read the room

var _player: CharacterBody3D
var _camera: Camera3D
var _body: StaticBody3D
var _space: PhysicsDirectSpaceState3D
var _awakened: bool = false     # only stalks once you have actually seen it
var _fired: bool = false
var _age: float = 0.0           # seconds since the level began


func _ready() -> void:
	# Drop the bare untextured capsule the scene shipped (the invisibility bug).
	for child in get_children():
		if child is MeshInstance3D:
			child.queue_free()

	# A gaze-reactive collider nested under a ScaryObject so player.gd's parent
	# walk from the ray-hit body finds the panic source above it. ScaryObject is
	# a plain Node and breaks the Node3D transform chain, so the body carries the
	# world transform itself — seeded here from the scene placement, then moved
	# directly in _process. The visual figure rides on the body so it follows.
	var scary := ScaryObject.new()
	scary.scare_intensity = GAZE_INTENSITY
	add_child(scary)
	_body = StaticBody3D.new()
	scary.add_child(_body)
	_body.global_transform = global_transform
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.7
	col.shape = shape
	col.position.y = 0.85
	_body.add_child(col)

	_build_visual()


# A tall, thin, faintly-lit figure with two burning eyes — so it reads as a
# watching creature in the near-black void and the player instinctively knows
# not to look. Built onto the body so it moves with the collider.
func _build_visual() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.015, 0.015, 0.02)
	dark.roughness = 1.0
	dark.emission_enabled = true
	dark.emission = Color(0.18, 0.015, 0.02)   # faint blood rim so the silhouette reads
	dark.emission_energy_multiplier = 0.5

	var torso := MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.18
	torso_mesh.height = 1.9
	torso.mesh = torso_mesh
	torso.position.y = 1.05
	torso.set_surface_override_material(0, dark)
	_body.add_child(torso)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.17
	head_mesh.height = 0.34
	head.mesh = head_mesh
	head.position.y = 2.05
	head.set_surface_override_material(0, dark)
	_body.add_child(head)

	# Eyes — the unmistakable "do not look at me" cue.
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color.BLACK
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.9, 0.1, 0.08)
	eye_mat.emission_energy_multiplier = 3.0
	for ex in [-0.06, 0.06]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.03
		eye_mesh.height = 0.06
		eye.mesh = eye_mesh
		eye.position = Vector3(ex, 2.08, 0.14)  # local +z = the face it turns toward you
		eye.set_surface_override_material(0, eye_mat)
		_body.add_child(eye)


func _process(delta: float) -> void:
	if _fired:
		return
	_age += delta
	if not _player:
		_player = get_node_or_null("../Player") as CharacterBody3D
		if not _player:
			return
		_camera = _player.get_node_or_null("Camera3D") as Camera3D
	if not _camera:
		return

	var cam_pos := _camera.global_position
	var here: Vector3 = _body.global_position
	var my_pos: Vector3 = here + Vector3(0, CHEST, 0)
	var to_me: Vector3 = my_pos - cam_pos
	if to_me.length() > ENGAGE_DIST:
		return

	var los := _has_line_of_sight(cam_pos, my_pos)
	var forward := -_camera.global_transform.basis.z
	var observed := los and forward.dot(to_me.normalized()) > FOV_DOT
	if observed:
		_awakened = true
		return  # frozen while watched
	if not _awakened or not los:
		return  # never seen, or a wall is between us — stay put
	if _age < START_GRACE:
		return  # opening grace: seen, but not yet hunting

	var flat := Vector2(here.x - _player.global_position.x,
		here.z - _player.global_position.z).length()
	if flat <= CONTACT_DIST:
		_lunge()
		return

	var dir := Vector3(_player.global_position.x - here.x, 0,
		_player.global_position.z - here.z).normalized()
	_body.global_position = here + dir * STALK_SPEED * delta
	_body.rotation.y = atan2(dir.x, dir.z)


func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	if not _space:
		_space = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid(), _body.get_rid()]
	# Nothing between the camera and the creature (excluding the two of us) = clear.
	return _space.intersect_ray(query).is_empty()


func _lunge() -> void:
	_fired = true
	global_position = _camera.global_position - _camera.global_transform.basis.z * 0.3
	Screamer.trigger()
