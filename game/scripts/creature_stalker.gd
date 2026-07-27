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
const ENGAGE_DIST := 8.0        # creature activates only when player enters its room
const FOV_DOT := 0.55           # cos of the half-angle that counts as "looked at"
const GAZE_INTENSITY := 0.6     # mild panic while you stare it down
const CHEST := 0.9              # ray target / facing height
const START_GRACE := 5.0        # opening seconds where nothing hunts — time to read the room
const STARE_OFF_TIME := 4.0     # continuous gaze to dismiss — costs 48 panic; requires nerve

# ── THE NIGHTMARE's "Still Ones" (DUNGEON_NIGHTMARES.md §B4.1) ──────────────────
# CreatureStalker is ALREADY a weeping angel, which is the luckiest fit in that
# whole proposal. These three additions port DN's skeletons on top of it.
#
# ⚠️ ALL THREE DEFAULT TO OFF, so the Void's four creatures are byte-for-byte
# unchanged. Only dungeon.gd sets them.

# ⭐ The scrape tell: a positional loop gated on ADVANCING. This is a genuine
# FAIRNESS UPGRADE over the Void, where the only tell is looking — consider
# back-porting it there once it has been played.
@export var scrape_tell: bool = false

# ⭐ The dud. ~35% of Still Ones topple with a crash when you get close and are then
# inert forever. This is the teaching beat and the tension engine at the same time:
# YOU CANNOT TELL A DUD FROM A KILLER WITHOUT WALKING UP TO ONE. And toppling is the
# GOOD outcome — a fallen one can never stand up again.
@export var is_dud: bool = false
@export var dud_fall_dist: float = 3.0

# The light reaction. A spark within SPARK_STEP_RANGE advances every Still One one
# step instantly; a spark within SPARK_KILL_DIST of an ACTIVE one is fatal. DN's
# exact rule, and the reason light is dangerous in that level.
@export var spark_reactive: bool = false
const SPARK_STEP := 1.0
const SPARK_STEP_RANGE := 8.0
const SPARK_KILL_DIST := 2.0

signal toppled

var _fallen: bool = false
var _scrape: AudioStreamPlayer3D = null

var _player: CharacterBody3D
var _camera: Camera3D
var _body: StaticBody3D
var _space: PhysicsDirectSpaceState3D
var _awakened: bool = false     # only stalks once you have actually seen it
var _fired: bool = false
var _age: float = 0.0           # seconds since the level began
var _stare_off_timer: float = 0.0


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


const _GLB_PATH := "res://assets/models/Void_creature.glb"

func _build_visual() -> void:
	if ResourceLoader.exists(_GLB_PATH):
		_build_visual_glb()
	else:
		_build_visual_procedural()
		_add_eye_glow()  # eye glow only on the procedural fallback


func _build_visual_glb() -> void:
	var scene: PackedScene = load(_GLB_PATH)
	var instance: Node3D = scene.instantiate()
	instance.scale = Vector3(1.0, 1.0, 1.0)
	_body.add_child(instance)
	# Blender adds a stray base cube to the export — remove it, keep only the character.
	var cube := instance.get_node_or_null("Cube")
	if cube:
		cube.queue_free()
	_pose_arms_down(instance)


# The Mixamo GLB ships in its bind T-pose (arms straight out) and carries no
# animation track, so nothing lowers the arms — it reads as a broken scarecrow.
# Override the upper-arm bone poses to drop the arms to the sides so it stands as
# a deliberate, menacing figure. Bone-local rotation about Z swings the arm down.
const _ARM_DROP_DEG := 80.0
const _FOREARM_TUCK_DEG := 12.0

func _pose_arms_down(instance: Node3D) -> void:
	var skel := instance.find_child("Skeleton3D", true, false) as Skeleton3D
	if not skel:
		return
	# Godot sanitizes the glTF "mixamorig:" prefix to "mixamorig_". +Z bone-local
	# rotation drops the left arm; the right arm mirrors it. A small forearm tuck
	# pulls the hands in so they hang at the sides instead of splaying outward.
	_rotate_bone(skel, "mixamorig_LeftArm", deg_to_rad(_ARM_DROP_DEG))
	_rotate_bone(skel, "mixamorig_RightArm", deg_to_rad(-_ARM_DROP_DEG))
	_rotate_bone(skel, "mixamorig_LeftForeArm", deg_to_rad(_FOREARM_TUCK_DEG))
	_rotate_bone(skel, "mixamorig_RightForeArm", deg_to_rad(-_FOREARM_TUCK_DEG))


func _rotate_bone(skel: Skeleton3D, bone_name: String, angle_z: float) -> void:
	var idx := skel.find_bone(bone_name)
	if idx == -1:
		return
	var rest := skel.get_bone_rest(idx)
	# Compose the drop onto the bind-pose rotation, in bone-local space.
	skel.set_bone_pose_rotation(idx, rest.basis.get_rotation_quaternion() * Quaternion(Vector3.FORWARD, angle_z))


func _build_visual_procedural() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.012, 0.012, 0.018)
	dark.roughness = 1.0
	dark.emission_enabled = true
	dark.emission = Color(0.18, 0.015, 0.02)
	dark.emission_energy_multiplier = 0.5

	var torso := MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.15
	torso_mesh.height = 2.2
	torso.mesh = torso_mesh
	torso.position.y = 1.2
	torso.set_surface_override_material(0, dark)
	_body.add_child(torso)

	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.38, 0.06, 0.07)
		arm.mesh = arm_mesh
		arm.set_surface_override_material(0, dark)
		arm.position = Vector3(side * 0.24, 1.7, 0.0)
		arm.rotation_degrees.z = -side * 18.0
		_body.add_child(arm)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.16
	head_mesh.height = 0.32
	head.mesh = head_mesh
	head.position.y = 2.45
	head.set_surface_override_material(0, dark)
	_body.add_child(head)

	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color.BLACK
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.95, 0.08, 0.05)
	eye_mat.emission_energy_multiplier = 5.0
	for ex in [-0.06, 0.06]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.03
		eye_mesh.height = 0.06
		eye.mesh = eye_mesh
		eye.position = Vector3(ex, 2.48, 0.13)
		eye.set_surface_override_material(0, eye_mat)
		_body.add_child(eye)


func _add_eye_glow() -> void:
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.25, 0.35, 1.0)
	glow.light_energy = 0.35
	glow.omni_range = 1.8
	glow.position = Vector3(0, 1.75, 0.1)  # eye height — ~1.75 m on GLB, near head on procedural
	_body.add_child(glow)


func _process(delta: float) -> void:
	if _fired or _fallen:
		return
	_age += delta
	if not _player:
		# ⚠️ The relative path holds only while this node is a DIRECT child of the
		# level root next to Player. THE NIGHTMARE spawns these from a builder-owned
		# graph, so fall back to the "player" group — the same lookup player.gd
		# registers itself into, and what creature_object12.gd already uses.
		_player = get_node_or_null("../Player") as CharacterBody3D
		if not _player:
			_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		if not _player:
			return
		_camera = _player.get_node_or_null("Camera3D") as Camera3D
	if not _camera:
		return

	var cam_pos := _camera.global_position
	var here: Vector3 = _body.global_position
	var my_pos: Vector3 = here + Vector3(0, CHEST, 0)
	var to_me: Vector3 = my_pos - cam_pos

	# A dud topples when you get close enough to find out what it was. Checked
	# BEFORE the engage-distance early-out, and regardless of whether it is being
	# observed — walking up to one is exactly the act being resolved.
	if is_dud and to_me.length() <= dud_fall_dist:
		_topple()
		return

	if to_me.length() > ENGAGE_DIST:
		_set_scrape(false)
		return

	var los := _has_line_of_sight(cam_pos, my_pos)
	var forward := -_camera.global_transform.basis.z
	var observed := los and forward.dot(to_me.normalized()) > FOV_DOT
	if observed:
		_awakened = true
		_stare_off_timer += delta
		_set_scrape(false)   # frozen while watched, so the drag stops too
		if _stare_off_timer >= STARE_OFF_TIME:
			_dismiss()
		return  # frozen while watched
	_stare_off_timer = 0.0  # reset the moment the player looks away
	if not _awakened or not los:
		_set_scrape(false)
		return  # never seen, or a wall is between us — stay put
	if _age < START_GRACE:
		_set_scrape(false)
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
	_set_scrape(true)   # advancing: the dry wooden drag is the tell


func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	if not _space:
		_space = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid(), _body.get_rid()]
	# Nothing between the camera and the creature (excluding the two of us) = clear.
	return _space.intersect_ray(query).is_empty()


func _dismiss() -> void:
	_stare_off_timer = 0.0
	_awakened = false
	if _player:
		var away := Vector3(_body.global_position.x - _player.global_position.x,
			0, _body.global_position.z - _player.global_position.z).normalized()
		_body.global_position += away * 3.0


func _lunge() -> void:
	_fired = true
	_set_scrape(false)
	global_position = _camera.global_position - _camera.global_transform.basis.z * 0.3
	Screamer.trigger()


# ── THE NIGHTMARE additions (inert unless the matching @export is set) ──────────

# The dud outcome: a loud crash, and it is inert forever. Pure jumpscare — and this
# is the GOOD result, which is what makes approaching one a real decision.
func _topple() -> void:
	_fallen = true
	_set_scrape(false)
	var tw := create_tween()
	tw.tween_property(_body, "rotation:x", deg_to_rad(-88.0), 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var s := GameState.load_audio("skeleton_fall")
	if s:
		var pl := AudioStreamPlayer3D.new()
		pl.stream = s
		pl.unit_size = 14.0
		pl.volume_db = 2.0
		_body.add_child(pl)
		pl.play()
	toppled.emit()


func _set_scrape(on: bool) -> void:
	if not scrape_tell:
		return
	if _scrape == null:
		_scrape = AudioStreamPlayer3D.new()
		_scrape.name = "BoneScrape"
		var s := GameState.load_audio("bone_scrape")
		if s == null:
			scrape_tell = false
			return
		_scrape.stream = s
		_scrape.unit_size = 6.0
		_scrape.volume_db = -4.0
		# ⚠️ Every .wav.import in this project is loop_mode=0, so a loop has to be
		# re-triggered from `finished`. walk_lab_wing.gd asserts this exact idiom.
		_body.add_child(_scrape)
		_scrape.finished.connect(_scrape.play)
	if on and not _scrape.playing:
		_scrape.play()
	elif not on and _scrape.playing:
		_scrape.stop()


# Called by dungeon.gd for every Still One when the player sparks.
# DN's exact rule: light advances them, and light too close to an ACTIVE one kills.
func on_spark(spark_pos: Vector3) -> void:
	if not spark_reactive or _fired or _fallen:
		return
	var here: Vector3 = _body.global_position
	var d: float = Vector2(here.x - spark_pos.x, here.z - spark_pos.z).length()
	if d > SPARK_STEP_RANGE:
		return
	if _awakened and d <= SPARK_KILL_DIST:
		_lunge()
		return
	# One step closer, instantly. The flash woke it and it used the moment.
	_awakened = true
	var dir := Vector3(spark_pos.x - here.x, 0.0, spark_pos.z - here.z)
	if dir.length() < 0.05:
		return
	_body.global_position = here + dir.normalized() * SPARK_STEP


func has_fallen() -> bool:
	return _fallen


func is_active() -> bool:
	return _awakened and not _fallen and not _fired
