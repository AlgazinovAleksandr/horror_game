extends Node3D
class_name Watcher

# SCARY.md P3 — a distant motionless figure with NO RULES.
#
# The project has five creature types and none of them does the cheapest, most-cited
# scare in the medium: stand still at 30 m and do nothing. `creature_shapechanger.gd` is
# the closest and it is a kill-radius trap with a 16 panic/s stare — a punishment, not an
# image.
#
# A Watcher is a PHOTOGRAPH. Deliberately, and load-bearingly, it has:
#   * no ScaryObject ancestor  → zero gaze panic
#   * no CollisionShape3D      → cannot be interacted with, cannot block a corridor,
#                                cannot be hit by the interact or gaze raycast
#   * no KILL_DIST, no Screamer, no fail state, no rule to learn
#
# ⚠️ The zero-panic part is the whole point (SCARY.md §0.2). A scare with a number
# attached can be optimised against, budgeted around, and will destabilise a tuned
# level; one without cannot. It is also the only kind of scare that is FREE to place in
# a DreadZone, where decay is cancelled and every point of panic is permanent.
#
# ⚠️ NO EMISSION (SCARY.md §8.8, Issues 21/27/33 — a three-time recurrence). At ~0.45
# light energy emission outweighs albedo, so an emissive "hidden" figure becomes the
# brightest object in the room. This reads because it is a dark shape OCCLUDING a lit
# surface, and because SHADING_MODE_UNSHADED makes its albedo its final colour. It is a
# silhouette or it is nothing.
#
# ⚠️ The texture must be a real RGBA cutout. A .jpg has no alpha and the billboard shows
# as a solid rectangle — the `apparition_figure.jpg` bug.

signal vanished

# Framing. The quad is deliberately the same size as the apparition's so both read as
# the same order of thing at the same distance.
const SIZE := Vector2(1.6, 2.4)
const QUAD_Y := 1.2                 # centre height, so the figure's feet sit at y ≈ 0

const MAX_LIFETIME := 25.0          # gone on its own even if never looked at
const REVEAL_ROLL := 0.5            # chance it is gone when you look back
const FADE_TIME := 0.15             # only used when it vanishes while in view
const SEEN_DOT := 0.55              # in the player's view cone (matches CreatureStalker's FOV_DOT)

# Clearance probes — rays only, copied from apparition.gd:_fits().
const FIT_RADIUS := 0.9             # half the billboard's width
const HEAD_ROOM := 2.34
const PROBE_LOW := 0.35
const PROBE_HIGH := 2.15
# 16, not 8. At 45° spacing every ray flies through a DOORWAY's opening and reports
# clear while the billboard's edges are buried in the jambs — measured in
# tests/check_apparition_clearance.gd, where the 8-ray version left five doorway
# placements failing.
const FIT_RAY_COUNT := 16
const FLOOR_DROP := 4.0

var despawn_dist: float = 10.0      # vanishes if the player gets this close

# When true, NONE of the despawn rules apply — no lifetime, no approach, no look-back roll —
# and the owner is expected to drive `relocate()` instead.
#
# ⚠️ This exists for exactly one caller, `congregation.gd`, and it is what keeps a field of
# these from being a second observation-dependent creature (SCARY.md §8.3). A persistent
# Watcher still has NO rules: looking at it, away from it, approaching it or shining a light
# on it has no consequence at all. What the Congregation adds is only that a figure you are
# not looking at may not be in the same place later — never that it moves toward you, and
# never that watching it does anything.
var persistent: bool = false

# See spawn(). False only for congregation.gd, and only because its candidate generator
# cannot produce a point inside geometry.
var require_los: bool = true

# Height in metres; the width follows the texture's aspect. See spawn().
var figure_height: float = SIZE.y

# Multiplied into the cutout's albedo. ⚠️ ADDITIVE, DEFAULT 1.0 — every existing caller
# (the Corridor doorway, the House cellar) renders byte-identically to before this existed.
#
# It exists because the header's stated premise above — "a dark shape OCCLUDING a lit
# surface" — is a CONSTANT ALBEDO against a VARIABLE BACKGROUND, and it inverts wherever
# the ground is darker than the cutout. Measured in the Backrooms Sprawl (2026-08-17):
#
#   figure at  2 m .................. 43.7 lum   (44,44,44)
#   figure at 25 m .................. 42.4 lum   — flat, no falloff: the material is
#                                                 SHADING_MODE_UNSHADED, so albedo IS
#                                                 the final colour at every distance
#   Sprawl floor behind it .......... 29.5 - 36.3 lum
#   Sprawl ceiling behind it ........ 28.8 lum
#   watcher_figure.png, opaque px ... mean 43.6
#
# i.e. over most of the frame the "shadow" was a LIGHTER patch than its ground, and
# achromatic in a room that is uniformly yellow. Two lit placements are fine and the one
# dark placement was upside down. Cross-level item X36.
#
# ⚠️ This is a tint, NOT an emission and NOT a light. Never give a Watcher emission — see
# the header, and Issues 21/27/33.
var figure_tint: Color = Color(1, 1, 1, 1)

var _player: CharacterBody3D = null
var _camera: Camera3D = null
var _quad: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _age: float = 0.0
var _was_unseen: bool = false
var _going: bool = false


# Place a Watcher at `pos`, or return null if it would not fit there.
#
# Returning null rather than nudging is deliberate: a skipped Watcher costs nothing (it
# has no mechanical role at all), whereas one embedded in a wall is BACKLOG #8 all over
# again. Callers are expected to try a couple of candidate spots and accept a miss.
#
# ⚠️ Placement doctrine (GAME_MECHANICS_IDEAS N1): behind, beside or above the player —
# never centred down the sightline they are already walking. An industry that measures
# throughput concluded front-scares stall people while side and rear scares propel them.
# `require_los` — must the figure be VISIBLE from where the player is standing right now?
#
# True is right for a lone Watcher whose whole job is to be seen down a sightline (the
# Corridor doorway, the House cellar corner): if it spawns behind a wall it is wasted.
#
# ⚠️ The Congregation passes FALSE, and it has to. Its figures stand among 36 pillars in a
# 40 m hall, so most candidate spots are occluded from any given viewpoint — with the check
# on, five of six figures silently failed to place and every later `add_one()` returned
# false. They are meant to be discovered by moving, not handed over on arrival.
#
# ⚠️ The LOS ray has a SECOND job — it is what catches "pos is inside a wall", because a ray
# cast outward from inside a solid reports nothing while a segment from outside must cross
# the near face. Turning it off is only safe for a caller whose candidates cannot be inside
# geometry by construction. congregation.gd qualifies: it offsets at most PILLAR_SPREAD
# (2.7 m) from a pillar centre, and the outermost pillars sit 5 m from the perimeter, so no
# candidate can land in a wall — and the top-down column ray below still catches pillars.
# Do not pass false from a caller without that argument.
# `height` is the figure's height in metres. It exists because the same script stands in for
# an adult at 30 m and a child in a hallway, and a 2.4 m child is not a child. The WIDTH is
# never passed — it is derived from the texture's own aspect (see _build_figure), per
# SCARY.md §7.1(4): a portrait cutout on a fixed 1.6x2.4 quad renders visibly stretched.
#
# `tint` multiplies the cutout's albedo — see figure_tint. LAST parameter and defaulted to
# white on purpose, so no existing positional call site changes at all.
static func spawn(parent: Node, pos: Vector3, tex_path: String,
		vanish_within: float = 10.0, require_los: bool = true,
		height: float = SIZE.y, tint: Color = Color(1, 1, 1, 1)) -> Watcher:
	var player := parent.get_tree().get_first_node_in_group("player") as CharacterBody3D
	if not player:
		return null

	var w := Watcher.new()
	w.despawn_dist = vanish_within
	w.require_los = require_los
	w.figure_height = height
	w.figure_tint = tint
	w.name = "Watcher"
	parent.add_child(w)

	var grounded := w._snap_to_floor(player, pos)
	if not w._fits(player, grounded):
		w.queue_free()
		return null

	w.global_position = grounded
	w._build_figure(tex_path)
	return w


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player:
		_camera = _player.get_node_or_null("Camera3D") as Camera3D


func _build_figure(tex_path: String) -> void:
	_quad = MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(SIZE.x * (figure_height / SIZE.y), figure_height)
	_quad.mesh = mesh

	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# ⚠️ No emission_enabled anywhere in this function. See the header.
	if tex_path != "" and ResourceLoader.exists(tex_path):
		var tex: Texture2D = load(tex_path)
		_mat.albedo_texture = tex
		# figure_tint defaults to white, so this is the literal Color(1,1,1,1) it replaced.
		_mat.albedo_color = figure_tint
		# ⚠️ Size the quad from the SOURCE ASPECT, keeping the requested height. The
		# generator returns whatever crop it likes (the child came back 586x1489, the adult
		# 757x1474), and a portrait cutout stretched across a fixed 1.6-wide quad reads as a
		# fat, wrong figure — SCARY.md §7.1(4), the same lesson as KONTUR's roster plate.
		if tex and tex.get_height() > 0:
			var aspect := float(tex.get_width()) / float(tex.get_height())
			mesh.size = Vector2(figure_height * aspect, figure_height)
	else:
		# Procedural fallback: a flat dark shape. Still legible, because unshaded albedo
		# is the final colour and the walls behind it are lit. (× white = unchanged.)
		_mat.albedo_color = Color(0.06, 0.06, 0.08, 1) * figure_tint
	_quad.set_surface_override_material(0, _mat)
	# ⚠️ Half the ACTUAL height, not the constant. QUAD_Y is 1.2 because the default figure is
	# 2.4 m; with `figure_height` variable, a fixed 1.2 would leave a 1.25 m child hovering
	# half a metre off the floor.
	_quad.position.y = _centre_y()
	add_child(_quad)


func _process(delta: float) -> void:
	if _going:
		return
	if not _player or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		if not _player:
			return
		_camera = _player.get_node_or_null("Camera3D") as Camera3D

	_age += delta
	if persistent:
		return                      # the owner drives relocate(); nothing here applies

	if _age >= MAX_LIFETIME:
		_vanish(false)
		return

	if _player.global_position.distance_to(global_position) <= despawn_dist:
		# You walked up to it. It was not there.
		_vanish(true)
		return

	# The look-away-then-look-back roll. The uncertainty is the product: sometimes it is
	# still there, which is what makes the next glance cost something.
	var seen := _is_seen()
	if not seen:
		_was_unseen = true
	elif _was_unseen:
		_was_unseen = false
		if randf() < REVEAL_ROLL:
			_vanish(true)


# Move to `pos` if it fits there. Returns false and stays put otherwise — a figure that
# fails its clearance check must not be forced somewhere it would be embedded (BACKLOG #8).
func relocate(pos: Vector3) -> bool:
	if not _player or not is_instance_valid(_player):
		return false
	var grounded := _snap_to_floor(_player, pos)
	if not _fits(_player, grounded):
		return false
	global_position = grounded
	return true


# Is the player currently able to see this figure? Public so an owner can gate a relocation
# on it — the whole point is that nothing ever changes while it is in view.
func is_visible_to_player() -> bool:
	return _is_seen()


func distance_to_player() -> float:
	if not _player or not is_instance_valid(_player):
		return INF
	return _player.global_position.distance_to(global_position)


func _centre_y() -> float:
	return figure_height / 2.0


func _is_seen() -> bool:
	if not _camera:
		return false
	var to_me := global_position + Vector3(0, _centre_y(), 0) - _camera.global_position
	if to_me.length() < 0.01:
		return true
	# Horizontal-only facing test. Dotting a horizontal facing against the FULL 3D
	# direction mixes in the eye-height-vs-figure-centre gap, which can fail the test
	# regardless of where the player is actually looking once that gap is a large
	# fraction of the distance — the exact false-blind result
	# tests/test_creature_object12.gd found in the creature's FOV check.
	var fwd := -_camera.global_basis.z
	fwd.y = 0.0
	var flat := to_me
	flat.y = 0.0
	if fwd.length() < 0.01 or flat.length() < 0.01:
		return false
	if fwd.normalized().dot(flat.normalized()) < SEEN_DOT:
		return false
	# In the cone, but is there a wall in the way?
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		_camera.global_position, global_position + Vector3(0, _centre_y(), 0))
	q.exclude = [_player.get_rid()]
	q.collision_mask = 1
	return space.intersect_ray(q).is_empty()


func _vanish(in_view: bool) -> void:
	if _going:
		return
	_going = true
	vanished.emit()
	if not in_view or not _mat:
		# Nobody is looking. Do not animate — just stop existing.
		queue_free()
		return
	# ⚠️ Tween CONNECTED, never awaited (Issue 6): an awaited timer dies with the node
	# that started it, which is exactly the node being freed here.
	var tw := create_tween()
	tw.tween_property(_mat, "albedo_color:a", 0.0, FADE_TIME)
	tw.finished.connect(queue_free)


# ------------------------------------------------------------------ placement probes
#
# ⚠️ RAYS, NOT `intersect_shape()` (Issue 40, and tests/probe_shape_vs_csg.gd is the
# evidence). A shape query against CSG reports the overlap when the shape straddles a
# face but reports NOTHING when it sits wholly inside the slab — CSG collision is a
# concave trimesh and a query fully inside one intersects no triangles. So a shape test
# silently APPROVES exactly the embedded case this function exists to reject.
#
# Layer 1 only: notes and door interact-markers live on layer 2 and are walk-through, so
# treating them as obstructions would reject perfectly good spots.
func _fits(player: CharacterBody3D, pos: Vector3) -> bool:
	var space := player.get_world_3d().direct_space_state

	# 1. Line of sight from the player's eye. This is also what catches "pos is INSIDE a
	#    wall": rays cast outward from inside a solid report nothing, but the segment
	#    from the eye must still cross that wall's near face to reach it.
	if require_los:
		var los := PhysicsRayQueryParameters3D.create(
			player.global_position + Vector3(0, 1.2, 0), pos + Vector3(0, QUAD_Y, 0))
		los.exclude = [player.get_rid()]
		los.collision_mask = 1
		if not space.intersect_ray(los).is_empty():
			return false

	# 2. Head room — refuse spots with a fitting or a ceiling overhead.
	var up := PhysicsRayQueryParameters3D.create(
		pos + Vector3(0, 0.1, 0), pos + Vector3(0, HEAD_ROOM, 0))
	up.exclude = [player.get_rid()]
	up.collision_mask = 1
	if not space.intersect_ray(up).is_empty():
		return false

	# 3. Its own column, top-down. The outward fan below cannot see a low prop the figure
	#    is standing INSIDE, because those rays start within the prop. Looking down from
	#    above head height finds it, because that ray starts in open air.
	var down := PhysicsRayQueryParameters3D.create(
		pos + Vector3(0, HEAD_ROOM, 0), pos + Vector3(0, 0.05, 0))
	down.exclude = [player.get_rid()]
	down.collision_mask = 1
	if not space.intersect_ray(down).is_empty():
		return false

	# 4. Elbow room all round, at both ends — it is a billboard, so its 1.6 m width
	#    sweeps every horizontal direction as the player walks around it.
	for i in FIT_RAY_COUNT:
		var a := TAU * float(i) / float(FIT_RAY_COUNT)
		var out := Vector3(sin(a), 0.0, cos(a))
		for h in [PROBE_LOW, PROBE_HIGH]:
			var from: Vector3 = pos + Vector3(0, h, 0)
			var qq := PhysicsRayQueryParameters3D.create(from, from + out * FIT_RADIUS)
			qq.exclude = [player.get_rid()]
			qq.collision_mask = 1
			if not space.intersect_ray(qq).is_empty():
				return false
	return true


# Put its feet on whatever floor is actually there — a caller passing a room centre has
# no idea whether that room's floor is at y=0, on a ramp, or under water.
func _snap_to_floor(player: CharacterBody3D, pos: Vector3) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	var from := pos + Vector3(0, 0.35, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, FLOOR_DROP, 0))
	q.exclude = [player.get_rid()]
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return pos
	return Vector3(pos.x, (hit.position as Vector3).y, pos.z)
