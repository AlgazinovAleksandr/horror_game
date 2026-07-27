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
const PLACE_TRIES := 12
const MAX_FIGURES := 12             # a hard ceiling, however many mistakes are made

var _origin: Vector3 = Vector3.ZERO
var _pillars: Array[Vector3] = []
var _keep_out: Array[Vector3] = []  # the calm island, mainly — see build()
var _keep_out_radius := 7.0
var _figures: Array[Watcher] = []
var _tex := "res://assets/textures/shared/watcher_figure.png"
var _poll := 0.0
var _player: CharacterBody3D = null


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
	var pos := _pick_spot()
	if pos == Vector3.INF:
		return false
	# require_los = false: most spots in a 36-pillar hall are occluded from wherever the
	# player happens to be standing, and these are meant to be found by moving rather than
	# handed over on arrival. Safe here because `_pick_spot()` cannot generate a point inside
	# geometry — see the ⚠️ on Watcher.spawn().
	var w := Watcher.spawn(self, pos, _tex, 0.0, false)
	if not w:
		return false
	w.persistent = true
	_figures.append(w)
	return true


# A spot in some pillar's shadow that is clear, off the calm island, and not on top of the
# player. Returns Vector3.INF if none of PLACE_TRIES candidates works — the caller treats
# that as "not this time", never as an error, exactly as Watcher.spawn() does.
func _pick_spot() -> Vector3:
	if _pillars.is_empty():
		return Vector3.INF
	_ensure_player()
	for _i in PLACE_TRIES:
		var base: Vector3 = _pillars.pick_random()
		var a := randf() * TAU
		var r := randf_range(PILLAR_CLEAR, PILLAR_SPREAD)
		var cand := base + Vector3(sin(a) * r, 0.0, cos(a) * r)
		if _player and cand.distance_to(_player.global_position) < SPAWN_MIN_FROM_PLAYER:
			continue
		var blocked := false
		for k in _keep_out:
			if cand.distance_to(k) < _keep_out_radius:
				blocked = true
				break
		if blocked:
			continue
		return cand
	return Vector3.INF


func _ensure_player() -> void:
	if not _player or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D


func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_INTERVAL
	_ensure_player()
	if not _player:
		return

	for f in _figures:
		if not is_instance_valid(f):
			continue
		# ⚠️ Both conditions, and the distance one is not optional. Relocating a figure the
		# player is merely facing away from but standing next to would be audible as a pop in
		# the shadows and, worse, could drop one on top of them. Fifteen metres is beyond the
		# range at which a dark silhouette in this hall reads as anything but a shape.
		if f.is_visible_to_player():
			continue
		if f.distance_to_player() < RELOCATE_MIN_DIST:
			continue
		var pos := _pick_spot()
		if pos != Vector3.INF:
			f.relocate(pos)      # keeps its own require_los setting; may decline and stay put
