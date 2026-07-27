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

# ⚠️ Was a single fixed 7.0, then a single fixed 4.0 after the 2026-07-26 playtest
# ("can we make it appear closer so that it would be more scary"). BACKLOG #10: a fixed
# distance is the problem — every appearance framed identically, so the second one is
# never a surprise. Now drawn per appearance. 2.5 m is "on top of you"; 7.0 m is a
# figure down the hall. FLEE_MARGIN is proportional to whatever is drawn (see below) so
# a close spawn stays survivable.
const APPEAR_DIST_MIN := 2.5
const APPEAR_DIST_MAX := 7.0
const HOLD_TIME := 6.0       # seconds of nerve (no flee) before it fades — long enough to read
const DREAD_RATE := 3.0      # panic/s while it stands there — the climb to endure
const FADE_IN := 0.6
const TEACH_PANIC := 18.0    # panic spike when the taught version "rushes"
const TELEGRAPH_TIME := 0.22 # the lurch-forward warning before the rush lands
const TELEGRAPH_LUNGE := 0.35 # metres the figure jerks toward you as the tell

const FIG_BASE := "res://assets/textures/screamers/shared_screamer_showing_up"  # the figure's look
const RUSH_BASE := "res://assets/textures/screamers/shared_screamer_2"          # its screamer image

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


const MIN_DIST := 1.6        # never closer than this — spawns a step nearer now
const WALL_MARGIN := 0.5     # stop short of a wall by this much
const FIG_HALF_WIDTH := 0.9  # the billboard is 1.6 m wide; probe its corners, not its centre
const PROBE_LOW := 0.35      # the quad spans y 0..2.4 — probe near both ends, not just the eye
const PROBE_HIGH := 2.15
const FLOOR_DROP := 4.0      # how far down to look for a floor under the chosen spot

# Headings tried, in order, measured from where the player is looking. Forward first
# (the figure should be where you are already looking); the wider fans exist so a
# player standing in a doorway or facing a wall still gets an apparition somewhere
# legible instead of one embedded in the geometry. Same fan idea as
# level_1.gd:_place_nook_figure(), which solved this for the BreakerNook figure.
const HEADINGS_DEG: Array[float] = [
	0.0, 22.0, -22.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0,
]

# Sideways slack, tried in order, for each heading. 0 first — dead ahead is always the
# best frame. At the 2.5 m minimum spawn distance a 1.0 m nudge is ~22° off centre,
# comfortably inside the camera's view.
const LATERAL_NUDGES: Array[float] = [0.0, 0.4, -0.4, 0.8, -0.8, 1.2, -1.2, 1.6, -1.6]

# The volume the figure must have to itself, as a CYLINDER rather than a box: the quad
# is BILLBOARD_ENABLED, so it swivels to face the player and its 1.6 m width sweeps
# every horizontal direction as they walk around it. A box would only reserve the space
# the figure happens to occupy at the instant it spawns. Height is trimmed a sliver at
# each end because it stands ON the floor and under the ceiling, and a shape of its
# exact 2.4 m height overlaps the very slab it is correctly standing on.
# 0.9, not the quad's exact 0.8 half-width: the billboard is a rectangle, so its
# corners sit sqrt(0.8² + 0.125²) ≈ 0.81 from the centre, and probing to exactly the
# half-width leaves the corners free to clip a bench or a door frame.
const FIG_FIT_RADIUS := 0.9
const FIG_HEAD_ROOM := 2.34   # it is 2.4 m tall; refuse spots with something overhead
# 16, not 8. At 45° spacing the fan misses a DOORWAY's jambs entirely: standing in an
# opening the same width as the figure, every 45° ray flies straight through the gap
# and reports clear, while the billboard's edges are buried in the frame either side.
# 22.5° spacing catches the jamb. Measured, not guessed — the 8-ray version left five
# doorway placements failing in tests/check_apparition_clearance.gd.
const FIT_RAY_COUNT := 16

# Distances tried per heading, as fractions of the clear distance available. One
# attempt per heading was not enough: the spot furthest from the player is also the one
# nearest the far wall, so it fails the elbow-room check most often — and refusing the
# heading outright made the apparition abort in a quarter of ordinary, open-floor
# placements. Pulling it in a little is far better than not appearing at all.
const DIST_FRACTIONS: Array[float] = [1.0, 0.8, 0.6]

# ⚠️ PROPORTIONAL, not absolute (BACKLOG #10). Fleeing is measured as "you are further
# from it than where it spawned, by this much". A flat 0.7 m is a 10% allowance on a
# 7 m spawn and a 28% allowance on a 2.5 m one — so with the distance now randomised,
# a fixed margin would make close spawns kill you for an instinctive half-step back
# while far ones let you stroll away. `_flee_margin()` scales it and keeps the 0.7 m
# floor. Sprinting is still an unconditional fail at any distance, so "Walk. Do not
# run." is untouched; this only ever forgives the flinch.
const FLEE_MARGIN := 0.7          # absolute floor
const FLEE_MARGIN_FRACTION := 0.2 # …or a fifth of however far away it actually landed


# Materialise in front of the player, where they're already looking.
#
# ⚠️ BACKLOG #8 — "sometimes the monster appears in the textures". The old version cast
# ONE ray from eye height and then did
#     dist = clampf(hit_distance - WALL_MARGIN, MIN_DIST, APPEAR_DIST)
# The `MIN_DIST` floor OVERRODE the wall hit: facing a wall 1.0 m away yielded
# clampf(0.5, 1.6, 4.0) = 1.6, i.e. the figure was placed a metre PAST the wall it had
# just detected. On top of that, a single zero-width line says nothing about a 1.6 m
# wide billboard, so door jambs, pillars and shelving sliced it even when the centre
# line was clear.
#
# Now: probe six rays per heading (both edges and the centre, at two heights), fan over
# headings until one has real clearance, snap to the floor, and ABORT if nothing fits.
# A skipped apparition is strictly better than one embedded in a wall.
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

	var desired := randf_range(APPEAR_DIST_MIN, APPEAR_DIST_MAX)
	var spot: Variant = _find_spot(fwd, desired)
	if spot == null:
		# Nowhere legible to stand — a corner, a stairwell, a closed doorway. Say
		# nothing and get out of the way; the director will try again later.
		queue_free()
		return

	global_position = spot
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


# Walk the heading fan and, for each heading that has room, try a few lateral offsets
# until the figure's actual VOLUME fits. Returns a world position, or null.
#
# ⚠️ Both halves are load-bearing and neither is sufficient alone:
#   * The rays find how far it can stand without walking through a wall — but a ray
#     that STARTS inside a collider reports nothing (Godot's hit_from_inside defaults
#     to false), so a player hugging a wall makes the ±0.9 m edge probes lie.
#   * The shape query catches exactly that, and also catches the case the rays can
#     never see: a 1.6 m wide billboard placed 0.5 m from a wall clips it no matter
#     how much clear distance lies AHEAD. Hence the lateral nudges — without them a
#     player standing near any wall would abort every single time.
func _find_spot(fwd: Vector3, desired: float) -> Variant:
	var base := _player.global_position
	for deg in HEADINGS_DEG:
		var dir := fwd.rotated(Vector3.UP, deg_to_rad(deg))
		var usable := _clearance_along(dir, desired + WALL_MARGIN) - WALL_MARGIN
		if usable < MIN_DIST:
			continue
		var reach: float = minf(desired, usable)
		var right := Vector3.UP.cross(dir).normalized()
		for frac in DIST_FRACTIONS:
			var dist: float = maxf(reach * frac, MIN_DIST)
			for lateral in LATERAL_NUDGES:
				var cand := _snap_to_floor(base + dir * dist + right * lateral)
				if _fits(cand):
					return cand
	return null


# Is there room for the figure at `pos`, and can the player actually see it?
#
# ⚠️ Deliberately RAYS, not intersect_shape(). Measured on the built level: a shape
# query against the CSG walls reports the overlap when the shape straddles a face, but
# reports NOTHING when it sits inside the slab — CSG collision is a concave trimesh and
# a query fully inside one intersects no triangles. So a shape test silently approves
# exactly the case this function exists to reject. (tests/probe_shape_vs_csg.gd, kept
# as the evidence.) Rays are what the rest of this project asserts with, for the same
# reason.
#
# Layer 1 only: notes, bottles and door interact-markers live on layer 2 and are
# walk-through, so treating them as obstructions would reject perfectly good spots.
func _fits(pos: Vector3) -> bool:
	var space := _player.get_world_3d().direct_space_state

	# 1. Line of sight. This is also what catches "pos is INSIDE a wall": rays cast
	#    outward FROM inside a solid report nothing, but the segment from the player's
	#    eye must still cross that wall's near face to get there.
	var q := PhysicsRayQueryParameters3D.create(
		_player.global_position + Vector3(0, 1.2, 0), pos + Vector3(0, 1.2, 0))
	q.exclude = [_player.get_rid()]
	q.collision_mask = 1
	if not space.intersect_ray(q).is_empty():
		return false

	# 2. Head room. Without this the figure can stand under a low fitting — or, worse,
	#    on top of a bench that _snap_to_floor found, with its head through the ceiling.
	var up := PhysicsRayQueryParameters3D.create(
		pos + Vector3(0, 0.1, 0), pos + Vector3(0, FIG_HEAD_ROOM, 0))
	up.exclude = [_player.get_rid()]
	up.collision_mask = 1
	if not space.intersect_ray(up).is_empty():
		return false

	# 3. Its own column, top-down. The outward fan below cannot see a low prop the
	#    figure is standing INSIDE — an exam bench, a cart, a crate — because those rays
	#    start within the prop and a ray originating inside a concave collider reports
	#    nothing. Looking down from above head height finds it, because that ray starts
	#    in open air. (Three Exam1 placements failed on exactly this.)
	var down := PhysicsRayQueryParameters3D.create(
		pos + Vector3(0, FIG_HEAD_ROOM, 0), pos + Vector3(0, 0.05, 0))
	down.exclude = [_player.get_rid()]
	down.collision_mask = 1
	if not space.intersect_ray(down).is_empty():
		return false

	# 4. Elbow room, all round, at both ends of the figure — it is a billboard, so its
	#    1.6 m width sweeps every horizontal direction as the player walks around it.
	for i in FIT_RAY_COUNT:
		var a := TAU * float(i) / float(FIT_RAY_COUNT)
		var out := Vector3(sin(a), 0.0, cos(a))
		for h in [PROBE_LOW, PROBE_HIGH]:
			var from: Vector3 = pos + Vector3(0, h, 0)
			var qq := PhysicsRayQueryParameters3D.create(from, from + out * FIG_FIT_RADIUS)
			qq.exclude = [_player.get_rid()]
			qq.collision_mask = 1
			if not space.intersect_ray(qq).is_empty():
				return false
	return true


# Shortest unobstructed distance along `dir` for a body as wide and as tall as the
# figure — six parallel rays (left edge / centre / right edge, at two heights), take
# the minimum. `max_dist` bounds the work; an unobstructed probe returns it unchanged.
func _clearance_along(dir: Vector3, max_dist: float) -> float:
	var space := _player.get_world_3d().direct_space_state
	var right := Vector3.UP.cross(dir).normalized()
	var base := _player.global_position
	var nearest := max_dist
	for lateral in [-FIG_HALF_WIDTH, 0.0, FIG_HALF_WIDTH]:
		for height in [PROBE_LOW, PROBE_HIGH]:
			var from: Vector3 = base + right * lateral + Vector3(0, height, 0)
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_dist)
			q.exclude = [_player.get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				nearest = minf(nearest, from.distance_to(hit.position))
	return nearest


# Put its feet on whatever floor is actually there. Without this the figure inherits
# the PLAYER's y, so on the House cellar ramp or in the flooded Backrooms it sinks into
# the floor or hovers above it.
#
# ⚠️ The downcast starts only 0.35 m up, deliberately BELOW bench/desk height. Starting
# higher makes it find the top of the nearest exam bed and stand the figure on the
# furniture — which the head-room check in _fits() then rejects, so the apparition just
# silently gave up in every room with a table in it.
func _snap_to_floor(pos: Vector3) -> Vector3:
	var space := _player.get_world_3d().direct_space_state
	var from := pos + Vector3(0, 0.35, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -FLOOR_DROP, 0))
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return pos
	return Vector3(pos.x, hit.position.y, pos.z)


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
	return _horiz_dist_to_player() > _spawn_dist + _flee_margin()


func _flee_margin() -> float:
	return maxf(FLEE_MARGIN, _spawn_dist * FLEE_MARGIN_FRACTION)


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
	var img := _resolve_tex(RUSH_BASE)
	if img == "":
		img = _resolve_tex(FIG_BASE)
	if teach:
		# A survivable lesson: it lunges, you flinch, you live — learn not to run.
		Screamer.flash_scare(img, "all_levels_screamer", 0.7)
		if _player:
			_player.jolt_camera(0.1, 0.4)
			_player.add_panic(TEACH_PANIC)
		_fade_out()
	else:
		if _player:
			_player.jolt_camera(0.12, 0.4)
		Screamer.trigger(img)  # fatal — the apparition's own screamer image


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


# BUG_FIX.md 3.3, corrected after playtest: the scary-sound gap was here, at the
# moment it first appears — not at the rush (below). Plays a purpose-made snarl
# instead of the old generic drone, falling back to the drone if it's ever missing.
func _play_drone() -> void:
	var stream := GameState.load_audio("apparition_snarl")
	if not stream:
		stream = GameState.load_audio("apparition_drone")
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
# Reuses the generic door "creak" pitched up, unchanged (the fatal Screamer.trigger()
# scream that follows is the "screamer" proper, and stays untouched too).
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
