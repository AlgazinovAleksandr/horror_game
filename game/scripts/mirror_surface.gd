extends Node3D
class_name MirrorSurface

# A mirror that actually reflects — the first one in this project.
#
# Until now nothing here reflected anything. The Corridor's turn mirrors were a PNG of a
# creature on a `QuadMesh` at roughness 0.9 (`corridor.gd:_make_cursed_panel_at`), and
# `living_mirror.gd`'s `metallic 0.9 / roughness 0.12` sampled an environment that does not
# exist: no ReflectionProbe, no SSR, no SubViewport anywhere in the tree. The user's report
# was simply "it does not really look like a mirror." It wasn't one.
#
# HOW IT WORKS
#   A `SubViewport` holds a second `Camera3D` placed at the player camera REFLECTED through
#   the mirror plane. The viewport's texture becomes the quad's albedo. That gives real
#   parallax — the reflection slides as you move, the torchlight sweeps across it — which
#   is the whole difference between a mirror and a picture of one.
#
# ⭐ THE FIGURE IS REAL, AND IT LIVES ONLY IN THE GLASS.
#   A `Watcher` is placed in the corridor on visual layer `MIRROR_ONLY_LAYER`. The player's
#   camera has that bit cleared (`player.gd:_ready`), the reflection camera keeps it. So the
#   corridor behind you is empty, and the mirror disagrees — and unlike the old painted
#   creature it moves correctly with your own movement, because it is genuinely standing
#   there. Turning round to check costs nothing and finds nothing, which is the beat.
#
# ⚠️ PROXIMITY-GATED. Each active mirror is a second full scene render. Three exist in the
# Corridor and at most one renders at a time; the rest sit at `UPDATE_DISABLED`, which
# costs nothing. Do not remove the gate to "simplify" this.
#
# ⚠️ There is no visible player body in this game (first person, no mesh), so the reflection
# shows an EMPTY corridor. That is not a bug to fix — it is the most useful property the
# effect has.

# Visual layer reserved for things that exist only in reflections. Mirrored in player.gd,
# which clears this bit from the player camera's cull_mask for every level.
const MIRROR_ONLY_LAYER := 20

const VIEWPORT_SIZE := Vector2i(512, 768)
const ACTIVE_DIST := 14.0        # beyond this the mirror stops rendering entirely
const GLASS_TINT := Color(0.62, 0.66, 0.70)   # old silvered glass, never a clean white

var _viewport: SubViewport
var _cam: Camera3D
var _quad: MeshInstance3D
var _player_cam: Camera3D
var _active: bool = false


# Turn an existing quad into a mirror. Takes the quad rather than building one so the
# caller keeps its own hierarchy — in the Corridor that is `ScaryObject -> StaticBody3D ->
# QuadMesh`, and the ScaryObject MUST stay an ancestor of the collider or gaze panic
# silently stops working (corridor.gd:611-616).
static func attach(quad: MeshInstance3D) -> MirrorSurface:
	var m := MirrorSurface.new()
	m.name = "MirrorSurface"
	quad.add_child(m)
	m._quad = quad
	m._build()
	return m


func _build() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "SubViewport"   # named so tests and tooling can find it by path
	_viewport.size = VIEWPORT_SIZE
	_viewport.transparent_bg = false
	# Only render when we ask. The default (ALWAYS) would render all three Corridor
	# mirrors every frame, for the whole 320 m walk.
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# The reflection needs its own copy of the world or it renders nothing.
	_viewport.world_3d = get_viewport().world_3d
	_viewport.own_world_3d = false
	add_child(_viewport)

	_cam = Camera3D.new()
	_cam.name = "Camera3D"
	_cam.current = true
	# Keep every layer INCLUDING the mirror-only one — that is the entire trick.
	_cam.cull_mask = 0xFFFFF
	_viewport.add_child(_cam)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _viewport.get_texture()
	mat.albedo_color = GLASS_TINT
	# ⚠️ Unshaded. The reflection is already a lit render; letting the corridor's lights
	# shade it again would darken the glass toward black in exactly the dark stretch where
	# these mirrors live. Emission would be the wrong tool too — Issue 21, no glow and no
	# tonemapping, so anything above 1.0 clamps to flat white.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# The viewport is rendered from the mirror's own side, so the image arrives already
	# handed correctly; flipping it here would undo that.
	_quad.set_surface_override_material(0, mat)


func _resolve_player_cam() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p:
		_player_cam = p.get_node_or_null("Camera3D") as Camera3D


func _process(_delta: float) -> void:
	if _player_cam == null or not is_instance_valid(_player_cam):
		_resolve_player_cam()
		if _player_cam == null:
			return

	var dist: float = _quad.global_position.distance_to(_player_cam.global_position)
	var want: bool = dist <= ACTIVE_DIST
	if want != _active:
		_active = want
		_viewport.render_target_update_mode = \
			SubViewport.UPDATE_ALWAYS if want else SubViewport.UPDATE_DISABLED
	if not want:
		return

	# REFLECT THE CAMERA THROUGH THE MIRROR PLANE.
	#
	# Done in the mirror's own local space, where the plane is simply z = 0 with the normal
	# along +z, because that turns the reflection into a sign flip and removes any need to
	# reason about world-space plane equations.
	#
	# ⚠️ Two things are negated, not one. Negating the position and the basis' z axis alone
	# leaves a basis with determinant -1 — an improper, mirrored frame, which Godot renders
	# inside out. Negating the x axis as well restores a proper rotation while keeping the
	# image handed the way a mirror hands it.
	var mirror_inv := global_transform.affine_inverse()
	var local := mirror_inv * _player_cam.global_transform
	local.origin.z = -local.origin.z
	var b := local.basis
	b.z = -b.z
	b.x = -b.x
	local.basis = b
	_cam.global_transform = global_transform * local
	_cam.fov = _player_cam.fov

	# ⚠️ THE NEAR PLANE IS DOING REAL WORK — without it the mirror renders BLACK.
	#
	# The virtual camera sits as far BEHIND the glass as the player stands in front of it,
	# which puts it inside (and behind) the wall the mirror is hung on. Looking back toward
	# the corridor, the first thing it meets is that wall, so the reflection is the inside
	# of the masonry: a black rectangle with a strip of sky over the top where the geometry
	# runs out. That is exactly what the first screenshot showed.
	#
	# Pushing `near` out to the distance from the virtual camera to the mirror PLANE clips
	# away everything between the two — the wall included — and leaves precisely the half of
	# the world the glass should be showing. `absf(local.origin.z)` is that distance, because
	# in mirror-local space the plane is z = 0.
	_cam.near = maxf(0.05, absf(local.origin.z))
