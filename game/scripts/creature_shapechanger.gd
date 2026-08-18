extends Node3D
class_name CreatureShapechanger

# The Perëkozhnik ("shapechanger") — KONTUR's mimic. It stands motionless in a
# corner, looking almost like an ordinary resident, and it NEVER moves or chases.
# It is not a gate: it exists to make the infected half of the level feel occupied,
# and to punish the one instinct this level otherwise rewards — walking up to
# something to get a better look.
#
# Staring feeds gaze panic (ScaryObject). Closing to KILL_DIST is fatal.
#
# Built like living_mirror.gd: ScaryObject -> StaticBody3D -> collider, with the
# world transform seeded onto the BODY, because ScaryObject is a plain Node and
# breaks the Node3D transform chain (ISSUES_SOLUTIONS.md Issue 10).

const TEX_PATH := "res://assets/textures/level_5_kontur/creature_shapechanger.png"

# ⚠️ DELIBERATE, do not "balance" this down.
#
# 0.8 x PANIC_BASE_RATE (20) = 16 panic/s, and KONTUR is the one level with no decay
# at all (its floor-wide DreadZone cancels decay exactly), so a stare kills in ~3 s
# from an empty bar and ~2 s after a single strike. That is faster than the level's
# stated three-strike budget, and it was raised in playtest (2026-07-21, two deaths
# here in one session) and kept on purpose: in KONTUR, looking at things costs you.
# The creature sits 3.2 m off the walking line, so every second of eye contact is a
# choice the player made.
const GAZE_INTENSITY := 0.8
const KILL_DIST := 2.0

# ⚠️ SIZED FROM THE CUTOUT, not from a guess (2026-08-18, K-T4).
#
# `creature_shapechanger.png` is 1024x1536 (0.6667) and the quad was 0.9 x 1.9 (0.4737):
# a **1.407x** horizontal squash. Measured on the alpha channel, the FIGURE occupies a
# 435 x 1328 box inside that canvas, so what was actually standing in the corner was a
# man 1.64 m tall and **0.38 m wide** — narrower across the shoulders than his own head
# is tall. A mimic whose whole job is to pass for an ordinary resident cannot be the one
# silhouette in the level that is visibly wrong.
#
# The canvas is now sized so the FIGURE lands at FIGURE_H, and the quad is dropped by the
# transparent margin under his boots so he stands ON the floor rather than 0.17 m above
# it. Both fractions are measured constants, not tuning.
const FIGURE_H := 1.78            # crown to sole, in metres
const TEX_ASPECT := 0.66667       # 1024 / 1536
const FIG_H_FRAC := 0.86458       # 1328 / 1536 — figure height as a share of the canvas
const FIG_FOOT_FRAC := 0.08203    # 126 / 1536 — transparent margin below his boots
const SIZE := Vector2(FIGURE_H / FIG_H_FRAC * TEX_ASPECT, FIGURE_H / FIG_H_FRAC)

# ⭐ THE DISGUISE (2026-08-18). ⚠️ ITS RULES DID NOT CHANGE.
#
# Its name means *shapechanger* and for its whole life it was a static billboard standing
# in a corner. It now spends most of a run WEARING SOMETHING — a fourth bottle on the
# kitchen shelf, a second phone on the switchboard desk — and only becomes a figure if
# the player touches it. `GAZE_INTENSITY`, `KILL_DIST`, "never moves" and "is not a gate"
# are all untouched; this is a costume, not a behaviour.
#
# THE FOUR RULES THIS HAD TO SATISFY, because a mimic is very easy to build unfairly:
#
#  1. LOOKING AT THE DISGUISE MUST COST NOTHING. The shell is a `MimicShell` sibling of
#     the `ScaryObject`, not a child of it, and the figure's own gaze collider is
#     DISABLED while disguised — so a player reading four labels pays nothing. In a level
#     with no decay at all, 16 panic/s for inspecting a shelf would be indefensible.
#  2. IT MUST NEVER SILENTLY COST A GATE. The shell is not a `BottleItem` and not a
#     `RotaryPhone`; touching it consumes no bottle, spends no strike, and cannot answer
#     or smash anything. The whole price of being fooled is that you now know.
#  3. IT MUST NOT KILL YOU WITH THE TOUCH THAT REVEALED IT. `KILL_DIST` is 2 m and you
#     interact from about one — so the figure is revealed at a MARK the level validates by
#     ray, at least `REVEAL_MIN_DIST` away and in line of sight. It does not walk there;
#     the disguise simply stops being true. Nothing about "it never moves" changes: from
#     the moment it is real, it stands still forever, exactly as before.
#  4. IT MUST BE FAIR IN HINDSIGHT. Every disguise is placed so that something about it is
#     WRONG and stays wrong for as long as you care to look: the kitchen has three shelf
#     slots and four bottles, two of them wearing the same label; the switchboard has two
#     phones and only one of them is ringing. See `kontur.gd:_spawn_creature()`.
const REVEAL_MIN_DIST := 3.0
const REVEAL_FADE := 0.35

signal revealed

@export var disguised: bool = false
## Where the figure is standing once the disguise drops. Set by the level, validated by
## the level with rays (Issue 40 — an outward fan cannot detect "inside a wall").
@export var reveal_mark: Vector3 = Vector3.ZERO

var _player: CharacterBody3D
var _body: StaticBody3D
var _fig: MeshInstance3D
var _gaze_col: CollisionShape3D
var _shell: MimicShell
var _fired: bool = false


func _ready() -> void:
	_build()


func _build() -> void:
	var scary := ScaryObject.new()
	scary.scare_intensity = GAZE_INTENSITY
	add_child(scary)

	_body = StaticBody3D.new()
	scary.add_child(_body)
	_body.global_transform = global_transform

	var fig := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = SIZE
	fig.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Y-billboard: it always faces the player, but stays planted upright — a figure
	# that turns to track you without ever moving its feet.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	if ResourceLoader.exists(TEX_PATH):
		var tex := load(TEX_PATH)
		mat.albedo_texture = tex
		# A little self-illumination so it reads in a dark corner without a lamp.
		mat.emission_enabled = true
		mat.emission_texture = tex
		mat.emission_energy_multiplier = 0.25
	else:
		mat.albedo_color = Color(0.3, 0.3, 0.32)
	fig.set_surface_override_material(0, mat)
	# Sunk by the canvas's own empty margin, so his boots meet the floor.
	fig.position = Vector3(0, SIZE.y / 2.0 - SIZE.y * FIG_FOOT_FRAC, 0)
	_body.add_child(fig)
	_fig = fig

	# ⚠️ The gaze collider wraps the FIGURE, not the canvas. Two thirds of that canvas is
	# transparent margin, and a collider out there is an invisible wall the player can
	# walk into in a dark room — and it would report a gaze hit on empty air.
	var fig_w: float = SIZE.x * 0.4248     # 435 / 1024
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(fig_w, FIGURE_H, 0.3)
	col.shape = shape
	col.position = Vector3(0, FIGURE_H / 2.0, 0)
	_body.add_child(col)
	_gaze_col = col


# ---------------------------------------------------------------- the disguise

## The level hands in the geometry of whatever ordinary prop this is pretending to be,
## plus a collider generous enough that the interact ray reaches it (Issue 2). Everything
## in `shell` is parented under a `MimicShell`, which is a SIBLING of the `ScaryObject`.
func set_disguise(shell: MimicShell) -> void:
	_shell = shell
	disguised = true
	add_child(shell)
	shell.touched.connect(reveal)
	# ⚠️ Here, not in `_ready()`. The level builds the shell AFTER add_child(), so at
	# `_ready()` time `disguised` is still false and an `_enter_disguise()` there would
	# never run — the creature would stand fully visible next to its own disguise.
	_enter_disguise()


func _enter_disguise() -> void:
	if _fig:
		_fig.visible = false
	if _gaze_col:
		# ⚠️ `disabled`, not merely invisible. A `visible = false` MeshInstance3D leaves
		# its sibling collider answering the gaze ray, and the ray does not care what it
		# can see — the player would have been charged 16 panic/s for looking at a bottle.
		_gaze_col.set_deferred("disabled", true)


## Drop it. Called from the shell's `touched`; also safe to call directly.
func reveal() -> void:
	if not disguised:
		return
	disguised = false
	if is_instance_valid(_shell):
		_shell.queue_free()
	# The figure was never where the disguise was. It is standing at the mark.
	if reveal_mark != Vector3.ZERO:
		global_position = reveal_mark
		# The disguise may have been yawed to face a room (a bottle label wants to point
		# into the kitchen); the figure is a Y-billboard and does not, and its box collider
		# is 0.57 wide by 0.30 deep — carried at 90 deg that is a 0.30 m target for the
		# gaze ray instead of a 0.57 m one.
		rotation = Vector3.ZERO
		if is_instance_valid(_body):
			_body.global_transform = global_transform
	if _gaze_col:
		_gaze_col.set_deferred("disabled", false)
	if _fig:
		_fig.visible = true
		# A short fade, so the eye is drawn to where it now is rather than to a pop.
		var mat: StandardMaterial3D = _fig.get_surface_override_material(0)
		if mat:
			mat.albedo_color.a = 0.0
			var tw := create_tween()
			tw.tween_method(func(a: float) -> void: mat.albedo_color.a = a,
				0.0, 1.0, REVEAL_FADE)
	revealed.emit()


func _process(_delta: float) -> void:
	if _fired or disguised:
		return
	if not _player or not is_instance_valid(_player):
		_player = get_node_or_null("../Player") as CharacterBody3D
		if not _player:
			return
	if _player.global_position.distance_to(global_position) < KILL_DIST:
		_fired = true
		Screamer.trigger()
