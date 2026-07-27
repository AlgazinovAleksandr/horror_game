class_name CreatureHollow
extends Node3D

# THE HOLLOW ONE — DN2's Asmodeus (DUNGEON_NIGHTMARES.md §B4.3).
#
# The flagship, and the purest expression of this project's philosophy anywhere in
# the game. The correct play is:
#
#     hear something wrong -> STOP WALKING -> listen -> spark once ->
#     read the bearing -> walk calmly around it
#
# STOPPING AND LISTENING IS THE WINNING MOVE. Running is actively fatal, because
# your own footsteps mask a -12 dB knock: you cannot hear it while sprinting, and
# you will walk into it. A player who panics dies; a player who stands still in the
# dark and thinks lives. That is the thesis statement of the level, inside a
# franchise about panicking.
#
# Properties, all load-bearing:
#   - COMPLETELY INVISIBLE. No mesh, no billboard, visible = false permanently.
#   - THE CANDLE DOES NOTHING. Explicitly. The player must learn this.
#   - SLOW (2.2 m/s, well below the 4.0 walk) so escaping is TRIVIAL once you know
#     where it is. All the difficulty is in the knowing.
#   - It does not know where you are until it gets within LOCK_RANGE, then follows.
#   - ⭐ A SPARK is the only way to see it: an unshaded RGBA billboard fades
#     1.0 -> 0 over 0.30 s. One frame of truth, then gone.
#
# ⚠️ FAIRNESS, non-negotiable (§B10):
#   - Arrives at 6 sconces, never before, and only after a scripted zero-risk
#     teaching beat through the grate of a sealed alcove.
#   - ONE instance. It is not a swarm.
#   - NEVER simultaneous with the Matron — two unseeable threats at once is a coin
#     flip, and DN's own rule is "he never spawns when Mary is already around".
#   - NEVER in a chamber with a Still One: sparking is MANDATORY to solve this and
#     LETHAL near one of those. Textbook double jeopardy.
# The generator enforces the placement half; dungeon.gd enforces the timing half.

signal revealed
signal contact

const SPEED := 2.2               # well below the player's 4.0 walk
const CONTACT_DIST := 1.2
const LOCK_RANGE := 5.0          # it does not know where you are until this close
const LOSE_RANGE := 14.0         # ...and forgets if you get properly clear
const SHAKE_DIST := 1.8          # DN's screen-shake last warning, then ~0.3 s
const REVEAL_SECONDS := 0.30     # the spark silhouette's whole life
const FIG_TEX := "res://assets/textures/level_9_dungeon/dn_hollow_figure.png"
const FIG_SIZE := Vector2(0.9, 1.6)   # a small child-shadow, not an adult

# ⚠️ -12 dB and a tight falloff, on purpose. §B4.3: "quiet enough that you have to
# stop moving to hear it clearly." Get this loud and the finale stops being a test
# of nerve and becomes a waypoint marker.
const KNOCK_DB := -12.0
const KNOCK_UNIT := 8.0
const KNOCK_MIN_GAP := 1.1
const KNOCK_MAX_GAP := 2.6

var active: bool = false

var _player: CharacterBody3D = null
var _fig: MeshInstance3D = null
var _fig_mat: StandardMaterial3D = null
var _knock: AudioStreamPlayer3D = null
var _reveal_sfx: AudioStreamPlayer3D = null
var _knock_t: float = 0.0
var _reveal_t: float = 0.0
var _locked: bool = false
var _shook: bool = false
var _fired: bool = false
# When true this instance is the scripted DEMONSTRATION: it walks its path, can be
# sparked, and cannot hurt anybody. teach=true, the apparition.gd contract.
var teaching: bool = false
var _teach_path: PackedVector3Array = PackedVector3Array()
var _teach_i: int = 0
var _reveal_anchor: Vector3 = Vector3.INF


func _ready() -> void:
	_build_figure()
	_build_audio()
	_knock_t = randf_range(KNOCK_MIN_GAP, KNOCK_MAX_GAP)


func _build_figure() -> void:
	_fig = MeshInstance3D.new()
	_fig.name = "HollowFigure"
	var qm := QuadMesh.new()
	qm.size = FIG_SIZE
	_fig.mesh = qm

	_fig_mat = StandardMaterial3D.new()
	# ⚠️ UNSHADED. A lit material would be invisible in a level whose whole premise
	# is that there is no light — and the reveal has to read at full strength from a
	# 0.25 s spark. Unshaded also means the spark's own OmniLight cannot brighten it,
	# which is correct: what is driven here is ALPHA, not illumination.
	_fig_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fig_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fig_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_fig_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# ⚠️ The texture MUST be a real RGBA cutout. A .jpg, or a .png with a fake
	# checkerboard "transparency" baked into RGB, billboards as a solid rectangle —
	# the apparition_figure.jpg bug. Verified: dn_hollow_figure.png is RGBA with
	# alpha extrema (0, 255).
	if ResourceLoader.exists(FIG_TEX):
		var tex: Texture2D = load(FIG_TEX)
		if tex != null:
			_fig_mat.albedo_texture = tex
	_fig_mat.albedo_color = Color(1, 1, 1, 0.0)
	_fig.material_override = _fig_mat
	_fig.position = Vector3(0, FIG_SIZE.y * 0.5, 0)
	_fig.visible = false
	add_child(_fig)


func _build_audio() -> void:
	_knock = AudioStreamPlayer3D.new()
	_knock.name = "HollowKnock"
	var s := GameState.load_audio("hollow_knock")
	if s:
		_knock.stream = s
	_knock.unit_size = KNOCK_UNIT
	_knock.volume_db = KNOCK_DB
	_knock.max_db = 0.0
	add_child(_knock)

	_reveal_sfx = AudioStreamPlayer3D.new()
	_reveal_sfx.name = "HollowReveal"
	var r := GameState.load_audio("hollow_reveal")
	if r:
		_reveal_sfx.stream = r
	_reveal_sfx.unit_size = 12.0
	_reveal_sfx.volume_db = -6.0
	add_child(_reveal_sfx)


func activate(player: CharacterBody3D) -> void:
	_player = player
	active = true


func deactivate() -> void:
	active = false
	_locked = false


# The scripted demonstration (§B4.3, §B9): the knock crosses a SEALED side-chamber
# the player cannot enter, a caption prompts a spark, the silhouette shows through
# the grate, and it walks away. Zero risk — it cannot lock on and cannot contact.
#
# `reveal_anchor` is where the SILHOUETTE is drawn on a spark, which for the
# demonstration is the grate rather than the creature's true position. ⚠️ This is a
# rendering choice for the teaching instance only, and it exists because the alcove
# is genuinely sealed: there is 0.2 m of solid CSG between the corridor and the
# creature, so a figure drawn at its real position would be inside a wall and
# invisible. Drawing it at the grate reads exactly as "it showed through the bars",
# which is the beat the player needs. The REAL Hollow One never does this.
func begin_teaching(path: PackedVector3Array, reveal_anchor := Vector3.INF) -> void:
	teaching = true
	active = true
	_teach_path = path
	_teach_i = 0
	_reveal_anchor = reveal_anchor
	if path.size() > 0:
		global_position = path[0]


func _process(delta: float) -> void:
	if not active:
		return

	_tick_reveal(delta)
	_tick_knock(delta)

	if teaching:
		_tick_teach(delta)
		return

	if _player == null or not is_instance_valid(_player):
		return

	var to: Vector3 = _player.global_position - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var dist: float = flat.length()

	# It does not know where you are until it stumbles into your neighbourhood.
	# ⚠️ Deliberately NOT gated on hiding or on line of sight: it navigates by
	# proximity, not by seeing, which is what makes "walk quietly around it" the
	# answer rather than "break line of sight".
	if not _locked and dist <= LOCK_RANGE:
		_locked = true
	elif _locked and dist >= LOSE_RANGE:
		_locked = false

	if _locked and dist > 0.05:
		global_position += flat.normalized() * SPEED * delta

	# DN's last warning. Then you have about three tenths of a second.
	if dist <= SHAKE_DIST and not _shook:
		_shook = true
		if _player.has_method("jolt_camera"):
			_player.jolt_camera(0.6, 0.4)
	elif dist > SHAKE_DIST * 1.6:
		_shook = false

	if dist <= CONTACT_DIST and not _fired:
		_fired = true
		active = false
		contact.emit()
		Screamer.trigger()


func _tick_teach(delta: float) -> void:
	if _teach_path.size() < 2:
		return
	var target: Vector3 = _teach_path[_teach_i]
	var to: Vector3 = target - global_position
	if to.length() < 0.25:
		_teach_i += 1
		if _teach_i >= _teach_path.size():
			active = false
			return
		target = _teach_path[_teach_i]
		to = target - global_position
	global_position += to.normalized() * SPEED * delta


func _tick_knock(delta: float) -> void:
	_knock_t -= delta
	if _knock_t > 0.0:
		return
	# Irregular spacing: a metronome would be identifiable as a game sound, and the
	# whole design requires this to be confusable with a door settling.
	_knock_t = randf_range(KNOCK_MIN_GAP, KNOCK_MAX_GAP)
	if _knock and _knock.stream:
		_knock.pitch_scale = randf_range(0.94, 1.06)
		_knock.play()


func _tick_reveal(delta: float) -> void:
	if _reveal_t <= 0.0:
		return
	_reveal_t -= delta
	if _reveal_t <= 0.0:
		_fig.visible = false
		_fig_mat.albedo_color = Color(1, 1, 1, 0.0)
		return
	# Alpha 1 -> 0 across REVEAL_SECONDS. One frame of truth, then gone: now you
	# know the bearing, and that is all you needed.
	_fig_mat.albedo_color = Color(1, 1, 1, _reveal_t / REVEAL_SECONDS)


# Called by dungeon.gd when the player sparks. THE ONLY WAY TO SEE IT.
func reveal() -> void:
	if not active:
		return
	_reveal_t = REVEAL_SECONDS
	if _reveal_anchor != Vector3.INF:
		# Teaching instance: draw at the grate, not inside the sealed wall.
		_fig.global_position = _reveal_anchor + Vector3(0, FIG_SIZE.y * 0.5 - 0.6, 0)
		_fig.top_level = true
	_fig.visible = true
	_fig_mat.albedo_color = Color(1, 1, 1, 1.0)
	if _reveal_sfx and _reveal_sfx.stream:
		_reveal_sfx.play()
	revealed.emit()


func is_locked_on() -> bool:
	return _locked


# Sprinting masks the knock: the level calls this every frame. This is §B1 rule 3 —
# running makes you blind to the thing that would have made panic unnecessary.
func set_masked(masked: bool) -> void:
	if _knock:
		_knock.volume_db = KNOCK_DB - 18.0 if masked else KNOCK_DB
