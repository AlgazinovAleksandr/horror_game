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
# ⚠️ PROXIMITY-GATED. Each active mirror is a second full scene render. Two exist in the
# Corridor (90 m and 275 m, since 2026-08-16) and at most one renders at a time; the other
# sits at `UPDATE_DISABLED`, which costs nothing. Do not remove the gate to "simplify" this.
#
# ⚠️ `ACTIVE_DIST` IS ALSO AN AUDIBLE BEAT NOW. `corridor.gd:_tick_mirror_wake()` fires
# `mirror_wake` at exactly this distance, because the switch from UPDATE_DISABLED to
# UPDATE_ALWAYS is the moment a dark rectangle on the wall ahead becomes a live corridor —
# the "the mirror appears out of nowhere" the user asked to have a sound put on. Move this
# number and the cue moves with it, which is the intent.
#
# ⚠️ There is no visible player body in this game (first person, no mesh), so the reflection
# shows an EMPTY corridor. That is not a bug to fix — it is the most useful property the
# effect has.

# Visual layer reserved for things that exist only in reflections. Mirrored in player.gd,
# which clears this bit from the player camera's cull_mask for every level.
const MIRROR_ONLY_LAYER := 20

# ⚠️ THE VIEWPORT'S ASPECT IS DERIVED FROM THE GLASS, not fixed (2026-08-16). It was a flat
# 512x768 = 0.667 against a 1.40 x 1.95 = 0.718 quad, i.e. a further 7 % stretch on top of
# the framing error below. `_build()` sizes the width from the quad it is attached to; this
# is only the height budget and the clamp.
const VIEWPORT_H := 768
const VIEWPORT_W_MIN := 96
const VIEWPORT_W_MAX := 1536
# ⚠️ 14.0 -> 7.0 (2026-08-17), and the two halves of that decision are inseparable.
#
# The user, on the second Corridor replay: *"The same for mirror - let it appear when I'm much
# closer and much louder so that the player will be scared"* — captured at (32.8, 0, 145),
# **8.7 m** from the 275 m glass, i.e. the pane was already awake when they photographed it and
# asked for it to wake later.
#
# THE OPTION TAKEN was to move this constant rather than to decouple `mirror_wake` from it, so
# the sound stays married to the thing it is describing. Moving only the sound would fire a
# loud cue at a moment when nothing visible changes; adding a second, closer cue would put
# three beats (wake, second cue, the 2 m `glass_shatter` sting) inside one corner. Both were
# considered and both are worse — see `backlogs/03-corridor.md` §10.
#
# WHAT IT BUYS, measured. The pane is 1.40 x 1.95 m: at 14 m it stands 9.1 % of the screen's
# height when it comes alive, at 7 m **18.2 %** — the same reveal at 2x the linear size and 4x
# the area. The gate is still 5 m outside `TURN_MIRROR_SCARE_DIST` (2 m), so the wake and the
# sting remain two beats rather than one.
#
# WHAT IT COSTS: nothing — it is a saving. Each active mirror is a second full scene render,
# and the active radius is now half as wide. Measured by walking the level's own path at
# 0.25 m (`tests/probe_mirror_cost.gd`): **53.00 m of the 320 m walk had a mirror rendering
# at 14 m, 25.00 m at 7 m** — 16.5 % of the level down to 7.8 %, a 53 % reduction. Two
# mirrors are never active at once at any radius down to 5 m, in either build.
const ACTIVE_DIST := 7.0         # beyond this the mirror stops rendering entirely
const GLASS_TINT := Color(0.62, 0.66, 0.70)   # old silvered glass, never a clean white
# Far plane. The default 4000 m against a near plane that is often under a metre wastes the
# whole depth buffer on a 320 m level whose longest sightline is one 50 m segment.
const FAR := 200.0

var _viewport: SubViewport
var _cam: Camera3D
var _quad: MeshInstance3D
var _player_cam: Camera3D
var _active: bool = false
var _quad_size := Vector2(1.0, 1.0)


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
	if _quad.mesh is QuadMesh:
		_quad_size = (_quad.mesh as QuadMesh).size
	if _quad_size.x <= 0.0 or _quad_size.y <= 0.0:
		_quad_size = Vector2(1.0, 1.0)

	_viewport = SubViewport.new()
	_viewport.name = "SubViewport"   # named so tests and tooling can find it by path
	_viewport.size = Vector2i(
		clampi(int(round(VIEWPORT_H * _quad_size.x / _quad_size.y)),
			VIEWPORT_W_MIN, VIEWPORT_W_MAX),
		VIEWPORT_H)
	_viewport.transparent_bg = false
	# Only render when we ask. The default (ALWAYS) would render every Corridor mirror
	# every frame, for the whole 320 m walk.
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
	# ⚠️ THE IMAGE IS FLIPPED IN U, and it has to be (2026-08-16). The reflection camera is a
	# PROPER frame (determinant +1) — Godot renders an improper one inside out — which means
	# its screen-right is the glass's local -X. A real mirror does NOT swap sides: raise your
	# right hand and the image raises the hand on the same side of the glass. Take a post
	# 2 m to the player's right and 5 m behind them, reflect it through the plane, and the
	# sightline crosses the glass at local x = +0.75 — the RIGHT of the quad. The proper
	# camera puts it on the left of the render, so the sampled U is reversed here instead.
	#
	# The previous comment claimed "the image arrives already handed correctly"; it did not.
	# It was invisible because a straight corridor is very nearly symmetric about its own
	# centreline, which is also why the figure is deliberately spawned ON that centreline.
	mat.uv1_scale = Vector3(-1.0, 1.0, 1.0)
	mat.uv1_offset = Vector3(1.0, 0.0, 0.0)
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

	_aim(_player_cam.global_position)


# ⭐ OFF-AXIS FRUSTUM — THE MIRROR IS NOW FRAMED ON THE GLASS INSTEAD OF SQUEEZED ONTO IT.
#
# WHAT WAS WRONG (measured 2026-08-16, and it is capture C1's root cause). The reflection
# camera was given the PLAYER's symmetric perspective: `fov = player.fov` (75°) with `near`
# pushed out to the mirror plane. A symmetric frustum's near-plane window is
# `2·near·tan(fov/2)` tall — at 4.25 m from the glass that is 6.52 m — and the whole of it
# was then stretched onto a 1.95 m quad. Minification, quad ÷ window:
#
#     player 1.00 m from the glass   window 1.02 x 1.53 m   0.79x
#     player 2.45 m (capture C1b)    window 2.51 x 3.76 m   1.93x
#     player 4.25 m (capture C1)     window 4.35 x 6.52 m   3.34x
#     player 8.00 m                  window 8.19 x 12.28 m  6.30x
#
# A figure genuinely 7 m behind the player therefore rendered as if it were 23 m away in C1,
# in a black surround — and because the factor moves with distance, the image ZOOMED as you
# walked toward the glass at a rate no reflection has. The user flagged it twice, the second
# time unprompted. A correct mirror is 1.00x at EVERY distance.
#
# WHAT A MIRROR ACTUALLY IS. The glass is a WINDOW onto the reflected world. Its frustum is
# the pyramid from the virtual eye through the quad's four corners — asymmetric in general,
# because the eye is rarely on the quad's axis. So: point the camera along the mirror NORMAL
# (never along the mirrored player heading — the window is fixed by the glass, not by where
# you are looking), and build the projection from the quad's own rectangle.
#
# ⚠️ THE NEAR PLANE IS STILL DOING REAL WORK, and now it is structural rather than
# maintained by hand. The virtual camera sits as far behind the glass as the player stands
# in front of it, i.e. inside the wall the mirror hangs on; without clipping everything
# between camera and glass the reflection is the inside of the masonry with a strip of sky
# over it, which is exactly what the first screenshot of this feature showed. With
# `set_frustum` the window plane IS the near plane, so that clip cannot be lost by accident.
#
# ⚠️ `set_frustum(size, offset, near, far)` on a Camera3D with the default KEEP_HEIGHT means
# `size` is the near-plane HEIGHT and the width is `size * viewport_aspect` — which is why
# `_build()` sizes the SubViewport from the quad's aspect. Get that wrong and the fix
# reintroduces a stretch of exactly the ratio it forgot.
#
# ⚠️ WHAT MOVES IN THE GLASS AND WHAT DOES NOT — READ THIS BEFORE "FIXING" IT AGAIN.
#
# User report on the verification replay, 2026-08-16: *"It used to be in a way that the
# reflection in the mirror moves, now it is static. can we make it move again?"* The
# reflection is NOT frozen — the SubViewport is at UPDATE_ALWAYS inside ACTIVE_DIST and this
# function runs every frame (`check_mirror_frustum.gd` asserts both). What changed is which
# player action moves the image, and the honest answer is that the old one was an artefact.
#
# `_aim()` takes ONE input: the eye POSITION. It cannot take the eye's orientation, because
# a mirror is a fixed window — turning your head does not change what a pane of glass on a
# wall reflects, only which part of it you happen to be looking at.
#
# The old code passed the player's whole TRANSFORM through the mirror plane, so the
# reflection camera inherited the player's HEADING and the image panned with the mouse.
# Measured (analytic replication of both projections, figure on the centreline 7 m out,
# player 2.45 m from the glass, U = across the glass):
#
#   head yaw     0 deg  10 deg  20 deg  30 deg  45 deg
#   OLD  fig U   0.500   0.672   0.856   1.064   1.477   <- 0.022 U per degree; off the
#   NEW  fig U   0.500   0.500   0.500   0.500   0.500      glass entirely past ~26 deg
#
# NEW is 0.0000 to four decimals at every yaw, and it cannot be otherwise:
# `player.gd:_rotate_camera()` yaws the PLAYER about its own Y axis and the camera node sits
# on that axis at local (0, 1.65, 0), so looking around does not move the eye by a
# millimetre. A player who stops in front of a mirror and looks around — which is exactly
# what both playtest logs show, 10 s and 28 s standing at the 90 m corner — now sees a still
# photograph, where before they saw the whole corridor swing past.
#
# Everything the player does with their FEET moves the image MORE than it used to:
#
#   walking 12 m -> 1 m   the figure's height as a fraction of the glass:
#                         OLD 0.063 -> 0.151 (2.4x, and it GREW as you closed in)
#                         NEW 0.599 -> 0.119 (5.0x, and it SHRINKS — correct: walking at
#                                             the glass is walking AWAY from the figure)
#   strafing 0.5 m        figure U: OLD 0.500 -> 0.552 (0.052)
#                                   NEW 0.500 -> 0.235 (0.265, i.e. 5.1x the parallax)
#
# So there is no defect here to fix, and reverting reinstates capture C1/C1b (the 1.93x and
# 3.34x minification the user flagged twice). Making the glass move while the player stands
# still requires something in the REFLECTED WORLD to move — the figure, a light, a torch —
# and `watcher.gd`'s entire contract is that it does not move. That is a design decision and
# it is open; do not settle it inside this file.
#
# Split out from `_process` so a test can drive it from an arbitrary eye position and read
# the resulting projection back, without moving the player.
func _aim(eye_world: Vector3) -> void:
	var local: Vector3 = global_transform.affine_inverse() * eye_world
	# Distance from the glass along its own normal. In mirror-local space the plane is z = 0.
	var dist: float = absf(local.z)
	# The virtual eye: the player's, reflected. Looking back along +z_local at the glass.
	var cam_local := Vector3(local.x, local.y, -local.z)
	# Proper (determinant +1) frame looking along +z_local with +y_local up: X = -x, Z = -z.
	# The lateral flip that leaves behind is undone in the material's UV (see `_build`).
	var basis := global_transform.basis * Basis(
		Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
	_cam.global_transform = Transform3D(basis, global_transform * cam_local)

	# The window is the quad. In the camera's own space the quad's centre sits at
	# (local.x, -local.y) — the offset — and it is `dist` away along -Z.
	var near: float = maxf(0.05, dist)
	# If the eye is closer to the glass than the minimum near plane, the SAME pyramid is
	# expressed at the clamped plane by scaling the window with it.
	var k: float = near / maxf(dist, 0.0001)
	_cam.projection = Camera3D.PROJECTION_FRUSTUM
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.set_frustum(_quad_size.y * k, Vector2(local.x * k, -local.y * k), near, FAR)
