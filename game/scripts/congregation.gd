extends Node
class_name Congregation

# THE CONGREGATION — Backrooms Zone 2's occupants.
#
# The Sprawl was the emptiest space in the game: 1600 m², ~10 authored objects, no creatures,
# no notes, no events, no per-frame logic at all, five of its eight alcoves literally empty,
# 36 purely decorative pillars — and it was over in 20-40 seconds if you heard the water
# tell. A 40x40 m pillar hall with a deliberately wrong 4.5 m ceiling is one of the best
# horror spaces in the project and almost nothing used it.
#
# So: 6-8 motionless silhouettes standing among the pillars.
#
# ⚠️ THEY HAVE NO RULES. This is the entire design and it is what keeps the feature legal
# under SCARY.md §8.3 ("no second observation-dependent creature") and §0.2 ("stop adding
# panic terms, start adding channels"):
#   * zero panic — no ScaryObject ancestor, so staring at one costs nothing
#   * no kill radius, no contact, no Screamer, no fail state of any kind
#   * looking at one, looking away, approaching it, or shining a light on it does NOTHING
#
# What they do is simply never be where you left them: a figure that leaves your view while
# more than RELOCATE_MIN_DIST away may be somewhere else when you look back. It never
# approaches, never pursues, never acknowledges you. §8.3's subject is a creature whose FAIL
# CONDITION depends on gaze; there is no fail condition here to depend on anything.
#
# ⚠️ And the count GROWS with the player's own mistakes — `add_one()` is called on each wrong
# wall. Their failures populate the room, which costs no panic on top of the 12 the mistake
# already charges.

const RELOCATE_MIN_DIST := 15.0     # never relocate one that is close enough to be studied
const POLL_INTERVAL := 0.2          # 5 Hz. 36 pillars x 8 figures per frame is not free.
const PILLAR_CLEAR := 1.6           # min distance from a pillar centre (pillar is 0.9 sq)
const PILLAR_SPREAD := 2.7          # max offset from a pillar
const SPAWN_MIN_FROM_PLAYER := 12.0
const PLACE_TRIES := 20
const MAX_FIGURES := 12             # a hard ceiling, however many mistakes are made

# ---------------------------------------------------------------- the contract, enforced
#
# ⚠️ THE DESTINATION IS GATED, NOT JUST THE SOURCE (fixed 2026-08-17, backlog 04 B-A1).
#
# CLAUDE.md states this feature's contract in as many words, and cites it as the reason
# the feature is legal under SCARY.md §8.3: "A figure relocates only when it is BOTH out
# of view and >=15 m away, so it NEVER MOVES ON SCREEN and never pops at arm's length."
#
# Only the first half was ever implemented. `_process` gated the SOURCE; `_pick_spot()`
# asked nothing about the player's view at all and only required 12 m. Measured over a
# 90 s circuit of the Sprawl with six figures:
#
#   relocations ......................... 633   (422/min; ~1.2 per figure per second)
#   mean distance moved ................. 20.0 m
#   landed IN THE PLAYER'S VIEW CONE
#   WITH LINE OF SIGHT .................. 65 of 633  (10.3 %)
#
# So one relocation in ten was a figure materialising on screen, and nothing tested it —
# check_backrooms_occupants.gd asserted "a watched figure does not move", i.e. the half
# that was already right.
#
# The second number is the other half of the same finding: a figure that has teleported
# 20 m five times since you last looked cannot support the memory "there was one by that
# pillar", which is the entire product. SETTLE is what buys that memory.
#
# ⚠️ ZERO PANIC, no collider, no kill radius, no gaze cost — unchanged, and none of the
# constants below is a difficulty constant. They are a legibility budget: how long a thing
# with no rules stays where you left it.
const SETTLE_MIN := 8.0             # a figure holds its ground at least this long...
const SETTLE_MAX := 16.0            # ...and at most this, so they never move in lockstep

# ⚠️ Silhouette, not cutout. See watcher.gd's `figure_tint` for the measurements: the raw
# art is 43.6 lum and the Sprawl's floor is 29.5-36.3, so an untinted figure was a LIGHTER
# patch than the ground it was supposed to be occluding. Slightly cool rather than neutral
# grey, because the hall is uniformly yellow and a warm shadow disappears into it.
const FIGURE_TINT := Color(0.42, 0.42, 0.48, 1.0)

var _origin: Vector3 = Vector3.ZERO
var _pillars: Array[Vector3] = []
var _keep_out: Array[Vector3] = []  # the calm island, mainly — see build()
var _keep_out_radius := 7.0
var _figures: Array[Watcher] = []
var _settle_until: Array[float] = []   # parallel to _figures; seconds on the same clock
var _clock := 0.0
var _tex := "res://assets/textures/shared/watcher_figure.png"
var _poll := 0.0
var _player: CharacterBody3D = null
var _camera: Camera3D = null

# Measurement surface for tests (see check_backrooms_occupants.gd). Counting is free and
# a relocation counter is the only way to assert "the sample was not zero".
var relocations: int = 0
var relocations_rejected: int = 0


# `pillars` are WORLD positions of the hall's pillars; figures stand in their shadows rather
# than in the open, so the hall's own geometry does the framing.
static func build(parent: Node, origin: Vector3, pillars: Array[Vector3],
		count: int, keep_out: Array[Vector3] = [], keep_out_radius: float = 7.0) -> Congregation:
	var c := Congregation.new()
	c.name = "Congregation"
	c._origin = origin
	c._pillars = pillars
	c._keep_out = keep_out
	c._keep_out_radius = keep_out_radius
	parent.add_child(c)
	for _i in count:
		c.add_one()
	return c


func figure_count() -> int:
	var n := 0
	for f in _figures:
		if is_instance_valid(f):
			n += 1
	return n


# One more of them. Called by the level on every wrong wall.
func add_one() -> bool:
	if figure_count() >= MAX_FIGURES:
		return false
	# The destination gate applies here too: `add_one()` is called on every wrong wall, and a
	# figure blinking into existence in front of the player is the same fault as one blinking
	# across the room. At BUILD time it is a no-op — the player is still 200 m away in zone 1,
	# so the facing test short-circuits before any ray is cast.
	var pos := _pick_spot(SPAWN_MIN_FROM_PLAYER, true)
	if pos == Vector3.INF:
		return false
	# require_los = false: most spots in a 36-pillar hall are occluded from wherever the
	# player happens to be standing, and these are meant to be found by moving rather than
	# handed over on arrival. Safe here because `_pick_spot()` cannot generate a point inside
	# geometry — see the ⚠️ on Watcher.spawn().
	var w := Watcher.spawn(self, pos, _tex, 0.0, false, Watcher.SIZE.y, FIGURE_TINT)
	if not w:
		return false
	w.persistent = true
	_figures.append(w)
	_settle_until.append(_clock + randf_range(SETTLE_MIN, SETTLE_MAX))
	return true


# A spot in some pillar's shadow that is clear, off the calm island, and not on top of the
# player. Returns Vector3.INF if none of PLACE_TRIES candidates works — the caller treats
# that as "not this time", never as an error, exactly as Watcher.spawn() does.
#
# `min_from_player` is SPAWN_MIN_FROM_PLAYER for the initial field and RELOCATE_MIN_DIST
# for a relocation: the source rule and the destination rule are the same 15 m, which is
# what "never pops at arm's length" actually requires.
#
# `unseen_only` is the destination gate, and every caller passes true. At BUILD time it is a
# no-op rather than a cost — the player is 200 m away in zone 1, so the horizontal facing dot
# fails and `would_be_seen()` returns before casting anything. It is defaulted to false only
# so that a future caller has to opt IN to a stricter rule rather than silently out of it.
func _pick_spot(min_from_player: float = SPAWN_MIN_FROM_PLAYER,
		unseen_only: bool = false) -> Vector3:
	if _pillars.is_empty():
		return Vector3.INF
	_ensure_player()
	for _i in PLACE_TRIES:
		var base: Vector3 = _pillars.pick_random()
		var a := randf() * TAU
		var r := randf_range(PILLAR_CLEAR, PILLAR_SPREAD)
		var cand := base + Vector3(sin(a) * r, 0.0, cos(a) * r)
		if _player and cand.distance_to(_player.global_position) < min_from_player:
			continue
		var blocked := false
		for k in _keep_out:
			if cand.distance_to(k) < _keep_out_radius:
				blocked = true
				break
		if blocked:
			continue
		if unseen_only and would_be_seen(cand):
			relocations_rejected += 1
			continue
		return cand
	return Vector3.INF


# Would a figure standing at `pos` be visible to the player right now? Public so a test can
# assert the gate rather than infer it.
#
# ⚠️ Deliberately the SAME test Watcher._is_seen() runs — horizontal-only facing dot against
# Watcher.SEEN_DOT, then a line-of-sight ray on layer 1 to the figure's centre. If the two
# ever drift apart, a destination this function approves could be one the figure itself
# reports as visible the instant it lands, which is precisely the bug being fixed.
func would_be_seen(pos: Vector3) -> bool:
	_ensure_player()
	if not _player or not _camera:
		return false
	var centre := pos + Vector3(0, Watcher.SIZE.y / 2.0, 0)
	var to_it := centre - _camera.global_position
	var fwd := -_camera.global_basis.z
	fwd.y = 0.0
	var flat := to_it
	flat.y = 0.0
	if fwd.length() < 0.01 or flat.length() < 0.01:
		return false
	if fwd.normalized().dot(flat.normalized()) < Watcher.SEEN_DOT:
		return false
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(_camera.global_position, centre)
	q.exclude = [_player.get_rid()]
	q.collision_mask = 1
	return space.intersect_ray(q).is_empty()


func _ensure_player() -> void:
	if not _player or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		_camera = null
	if _player and not _camera:
		_camera = _player.get_node_or_null("Camera3D") as Camera3D


func _process(delta: float) -> void:
	_clock += delta
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_INTERVAL
	_ensure_player()
	if not _player:
		return

	for i in range(_figures.size()):
		var f: Watcher = _figures[i]
		if not is_instance_valid(f):
			continue
		# 1. SETTLE. A figure that moved recently stays put, however unobserved it is. This
		#    is what makes "there was one by that pillar" a memory worth having, and it is
		#    what took the measured rate from 633 relocations in 90 s down to a handful.
		if _clock < _settle_until[i]:
			continue
		# 2. SOURCE. Both conditions, and the distance one is not optional. Relocating a
		#    figure the player is merely facing away from but standing next to would be
		#    audible as a pop in the shadows and, worse, could drop one on top of them.
		#    Fifteen metres is beyond the range at which a dark silhouette in this hall
		#    reads as anything but a shape.
		if f.is_visible_to_player():
			continue
		if f.distance_to_player() < RELOCATE_MIN_DIST:
			continue
		# 3. DESTINATION — the half that was missing. Same 15 m, same view test.
		var pos := _pick_spot(RELOCATE_MIN_DIST, true)
		if pos == Vector3.INF:
			continue
		# keeps its own require_los setting; may decline and stay put
		if f.relocate(pos):
			relocations += 1
			_settle_until[i] = _clock + randf_range(SETTLE_MIN, SETTLE_MAX)
