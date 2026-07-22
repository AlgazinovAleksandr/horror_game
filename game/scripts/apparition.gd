extends Node3D
class_name Apparition

# The random "apparition" — a figure that materialises in front of the player at
# a scripted-but-randomised moment and tests whether they can HOLD THEIR NERVE.
#
# RULE_HOLD (the new, flagship behaviour built here):
#   It fades in ~7 m ahead, where you are already looking, with a low drone. It
#   adds steady dread while present. SURVIVE by NOT sprinting and riding out the
#   panic for HOLD_TIME seconds — then it fades. SPRINT while it stands there and
#   it rushes you -> fatal screamer. This reinforces the game's "Walk. Do not
#   run." rule using the one enforceable, fair signal (is_sprinting()), never an
#   un-telegraphable "did you turn your head".
#
# RULE_STARE / RULE_LOOKAWAY reuse the proven creatures (CreatureStalker /
# CreatureSmiler) so all three "correct responses" exist with one new script.
#
# teach = true makes the FIRST encounter of a rule survivable: even a panicked
# sprint only triggers a flash + panic, not death, so the player learns the tell.
# (Same teaching philosophy as the Void's CreatureA + START_GRACE.)

enum Rule { HOLD, STARE, LOOKAWAY }

signal rushed    # emitted when it lunges (flee detected) — for tests / hooks
signal survived  # emitted when the player held their nerve and it faded

const APPEAR_DIST := 7.0     # metres ahead of the player it materialises
const HOLD_TIME := 6.0       # seconds of nerve (no flee) before it fades — long enough to read
const DREAD_RATE := 3.0      # panic/s while it stands there — the climb to endure
const FADE_IN := 0.6
const TEACH_PANIC := 18.0    # panic spike when the taught version "rushes"
const TELEGRAPH_TIME := 0.22 # the lurch-forward warning before the rush lands
const TELEGRAPH_LUNGE := 0.35 # metres the figure jerks toward you as the tell

const FIG_BASE := "res://assets/textures/screamers/shared_screamer_figure"
const RUSH_BASE := "res://assets/textures/screamers/shared_screamer"

var rule: int = Rule.HOLD
var teach: bool = false

var _player: CharacterBody3D
var _camera: Camera3D
var _engaged: bool = false
var _hold: float = 0.0
var _done: bool = false
var _spawn_dist: float = 0.0   # horizontal player↔figure distance at appear()
var _telegraphing: bool = false  # the brief lurch-warning is playing; rush lands after
var _quad: MeshInstance3D
var _mat: StandardMaterial3D


# One entry point for all three response types. For HOLD the returned node is
# dormant — call appear() (e.g. from a CorridorEvent) to make it materialise.
static func spawn(parent: Node, which_rule: int, pos: Vector3, is_teach: bool = false) -> Node3D:
	match which_rule:
		Rule.STARE:
			var c := CreatureStalker.new()
			c.position = pos
			parent.add_child(c)
			return c
		Rule.LOOKAWAY:
			var s := CreatureSmiler.new()
			s.position = pos
			parent.add_child(s)
			return s
		_:
			var a := Apparition.new()
			a.rule = Rule.HOLD
			a.teach = is_teach
			a.position = pos
			parent.add_child(a)
			return a


static func _resolve_tex(base_no_ext: String) -> String:
	for ext in [".png", ".jpg"]:
		if ResourceLoader.exists(base_no_ext + ext):
			return base_no_ext + ext
	return ""


func _ready() -> void:
	visible = false  # dormant until appear()
	_build_figure()


func _build_figure() -> void:
	_quad = MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.6, 2.4)  # a touch larger so it reads clearly in the dark
	_quad.mesh = mesh
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED  # always faces you
	var fig := _resolve_tex(FIG_BASE)
	if fig != "":
		var tex := load(fig)
		_mat.albedo_texture = tex
		_mat.emission_enabled = true
		_mat.emission_texture = tex
		_mat.emission_energy_multiplier = 1.6  # brighter — unmistakably there
		_mat.albedo_color = Color(1, 1, 1, 0)  # alpha tweened in on appear
	else:
		# Procedural pale silhouette if no art is present.
		_mat.albedo_color = Color(0.55, 0.55, 0.62, 0)
		_mat.emission_enabled = true
		_mat.emission = Color(0.3, 0.32, 0.4)
		_mat.emission_energy_multiplier = 0.5
	_quad.set_surface_override_material(0, _mat)
	_quad.position.y = 1.2
	add_child(_quad)


const MIN_DIST := 2.0        # never closer than this — spawns a step nearer now
const WALL_MARGIN := 0.5     # stop short of a wall by this much
const FLEE_MARGIN := 0.4     # any meaningful move away from it counts as fleeing


# Materialise in front of the player, where they're already looking. The spawn
# distance is raycast-clamped to land in OPEN view: in the tight 3 m halls a fixed
# 7 m would drop the figure inside/behind a wall, so it was never actually seen.
func appear() -> void:
	if _engaged or _done:
		return
	_resolve_player()
	if not _player or not _camera:
		return
	var fwd := -_camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()

	var eye := _player.global_position + Vector3(0, 1.2, 0)
	var dist := APPEAR_DIST
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye, eye + fwd * APPEAR_DIST)
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		dist = clampf(eye.distance_to(hit.position) - WALL_MARGIN, MIN_DIST, APPEAR_DIST)

	global_position = _player.global_position + fwd * dist
	_spawn_dist = _horiz_dist_to_player()
	# Reset for re-arm (debug repeat) so a recycled instance fades in cleanly.
	_hold = 0.0
	_done = false
	_mat.albedo_color.a = 0.0
	visible = true
	_engaged = true
	_play_drone()
	var t := create_tween()
	t.tween_property(_mat, "albedo_color:a", 1.0, FADE_IN)


func _process(delta: float) -> void:
	if _done or _telegraphing or not _engaged:
		return
	_resolve_player()
	if not _player:
		return
	_player.add_panic(DREAD_RATE * delta)
	# The one rule: do not run. Sprinting OR moving away from it (fleeing) makes it
	# rush. Turning the camera while standing your ground never trips it — fair, and
	# it matches "stand still until it fades".
	if _is_fleeing():
		_telegraph_then_rush()
		return
	_hold += delta
	if _hold >= HOLD_TIME:
		_survive()


func _is_fleeing() -> bool:
	if _player.is_sprinting():
		return true
	return _horiz_dist_to_player() > _spawn_dist + FLEE_MARGIN


func _horiz_dist_to_player() -> float:
	if not _player:
		return 0.0
	var a := global_position
	var b := _player.global_position
	return Vector2(a.x - b.x, a.z - b.z).length()


# Fleeing is detected → give a fast, unmistakable tell (sting + lurch toward you)
# before the rush lands, so the kill is telegraphed rather than instant.
func _telegraph_then_rush() -> void:
	if _telegraphing or _done:
		return
	_telegraphing = true
	_play_sting()
	if _player:
		_player.jolt_camera(0.06, TELEGRAPH_TIME)
		# Jerk the whole figure a step toward the player — the visual half of the tell.
		var to := _player.global_position - global_position
		to.y = 0.0
		if to.length() > 0.01:
			var target := global_position + to.normalized() * TELEGRAPH_LUNGE
			var t := create_tween()
			t.tween_property(self, "global_position", target, TELEGRAPH_TIME)
	get_tree().create_timer(TELEGRAPH_TIME).timeout.connect(_rush)


func _rush() -> void:
	if _done:
		return
	_done = true
	rushed.emit()
	if teach:
		# A survivable lesson: it lunges, you flinch, you live — learn not to run.
		var img := _resolve_tex(RUSH_BASE)
		if img == "":
			img = _resolve_tex(FIG_BASE)
		Screamer.flash_scare(img, "all_levels_screamer", 0.7)
		if _player:
			_player.jolt_camera(0.1, 0.4)
			_player.add_panic(TEACH_PANIC)
		_fade_out()
	else:
		if _player:
			_player.jolt_camera(0.12, 0.4)
		Screamer.trigger()  # fatal (uses the level's screamer image)


func _survive() -> void:
	_done = true
	survived.emit()
	_fade_out()


func _fade_out() -> void:
	if not _mat:
		queue_free()
		return
	var t := create_tween()
	t.tween_property(_mat, "albedo_color:a", 0.0, 0.5)
	t.parallel().tween_property(_mat, "emission_energy_multiplier", 0.0, 0.5)
	t.tween_callback(queue_free)


func _play_drone() -> void:
	var stream := GameState.load_audio("apparition_drone")
	if not stream:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = -2.0
	p.unit_size = 10.0
	add_child(p)
	p.position = Vector3(0, 1.2, 0)
	p.finished.connect(p.queue_free)
	p.play()


# A short sharp sting the instant it decides to rush — the audio half of the tell.
func _play_sting() -> void:
	var stream := GameState.load_audio("creak")
	if not stream:
		stream = GameState.load_audio("apparition_drone")
	if not stream:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = 2.0
	p.pitch_scale = 1.4
	p.unit_size = 12.0
	add_child(p)
	p.position = Vector3(0, 1.2, 0)
	p.finished.connect(p.queue_free)
	p.play()


func _resolve_player() -> void:
	if _player and is_instance_valid(_player):
		return
	_player = get_node_or_null("../Player") as CharacterBody3D
	if _player:
		_camera = _player.get_node_or_null("Camera3D") as Camera3D
