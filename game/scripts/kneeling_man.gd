class_name KneelingMan
extends Node3D

# THE KNEELING MAN — DN's Shadow Corpse (DUNGEON_NIGHTMARES.md §B4.5).
#
# ⚠️ HE CANNOT HARM YOU AT ALL. There is no KILL_DIST here — that is the single
# deliberate difference from creature_shapechanger.gd, whose pattern this follows.
# Within DISSOLVE_DIST he simply dissolves and relocates; a lit candle dispels him.
#
# He is a NERVE TAX WITH NO FAIL STATE, and his job is to make the REAL threats
# ambiguous. He arrives at 6 sconces, BEFORE the Hollow One's teaching beat, so
# that by the time a genuinely invisible threat exists the player has already
# learned that a shape in the dark might be nothing at all.
#
# ⭐ He is also the whisperer. Two of these lines are load-bearing continuity:
#   "Look behind you."       — the exact lie KONTUR's Gate 4 escort already tells.
#                              A harmless ghost saying it here retroactively makes
#                              KONTUR's version read as THE SAME VOICE. Free
#                              narrative cohesion, and very good.
#   "I wouldn't look in the mirror." — points back at the House and Corridor mirrors.

const SPEED := 0.8
const DISSOLVE_DIST := 2.5
const GAZE_INTENSITY := 0.7
const RELOCATE_MIN := 14.0
const WHISPER_MIN_GAP := 9.0
const WHISPER_MAX_GAP := 20.0

const LINES := [
	"Look behind you.",
	"I wouldn't look in the mirror.",
	"Every room feels alive. I hear it breathing.",
	"Don't stare at me.",
	"No one ever leaves this place.",
	"Wake up.",
	"So scared, so scared, so scared...",
]

var _player: CharacterBody3D = null
var _scary: ScaryObject = null
var _body: StaticBody3D = null
var _quad: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _whisper: AudioStreamPlayer3D = null
var _whisper_t: float = 0.0
var _dispelled: bool = false


func _ready() -> void:
	# Same transform-chain discipline as every other gaze prop: ScaryObject is a
	# plain Node with no transform and breaks the Node3D chain, so the world
	# position lives on the BODY, which is also what moves (Issue 10).
	_scary = ScaryObject.new()
	_scary.scare_intensity = GAZE_INTENSITY
	add_child(_scary)
	_body = StaticBody3D.new()
	_body.name = "KneelerBody"
	_scary.add_child(_body)
	_body.global_transform = global_transform

	_quad = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.5, 1.0)   # low and wide: a crawling shape, not a standing one
	_quad.mesh = qm
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tex_path := "res://assets/textures/level_9_dungeon/dn_hollow_figure.png"
	if ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path)
		if tex != null:
			_mat.albedo_texture = tex
	_mat.albedo_color = Color(0.1, 0.1, 0.12, 0.85)
	_quad.material_override = _mat
	_quad.position = Vector3(0, 0.5, 0)
	_body.add_child(_quad)

	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.4, 1.0, 0.4)
	col.shape = sh
	col.position = Vector3(0, 0.5, 0)
	_body.add_child(col)

	_whisper = AudioStreamPlayer3D.new()
	_whisper.name = "Whisper"
	var s := GameState.load_audio("whisper_dungeon")
	if s:
		_whisper.stream = s
	_whisper.unit_size = 9.0
	_whisper.volume_db = -8.0
	_body.add_child(_whisper)
	_whisper_t = randf_range(WHISPER_MIN_GAP, WHISPER_MAX_GAP)


func register_player(p: CharacterBody3D) -> void:
	_player = p


# The level passes candle state in rather than this script knowing about candles.
func set_dispelled(dispelled: bool) -> void:
	_dispelled = dispelled
	_body.visible = not dispelled


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		return

	_tick_whisper(delta)
	if _dispelled:
		return

	var here: Vector3 = _body.global_position
	var to := Vector3(_player.global_position.x - here.x, 0.0,
		_player.global_position.z - here.z)
	var d: float = to.length()

	# He knows exactly where you are — and it does not matter, because reaching you
	# does nothing at all.
	if d <= DISSOLVE_DIST:
		_relocate()
		return
	if d > 0.05:
		_body.global_position = here + to.normalized() * SPEED * delta
		_body.rotation.y = atan2(to.x, to.z)


func _relocate() -> void:
	# Dissolve and reappear somewhere well away. No damage, no panic spike beyond
	# whatever staring already cost — the disappointment IS the mechanic.
	var angle := randf() * TAU
	var away := Vector3(cos(angle), 0.0, sin(angle)) * RELOCATE_MIN
	_body.global_position = _player.global_position + away
	_whisper_t = minf(_whisper_t, 2.0)


func _tick_whisper(delta: float) -> void:
	_whisper_t -= delta
	if _whisper_t > 0.0:
		return
	_whisper_t = randf_range(WHISPER_MIN_GAP, WHISPER_MAX_GAP)
	if _whisper and _whisper.stream and not _whisper.playing:
		_whisper.pitch_scale = randf_range(0.9, 1.1)
		_whisper.play()
	# The text is what carries the two continuity lines; the audio is texture.
	if randf() < 0.5:
		ScreenText.toast(get_tree(), LINES[randi() % LINES.size()],
			Color(0.55, 0.55, 0.6), 2.4, 26)
