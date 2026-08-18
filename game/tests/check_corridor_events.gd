extends SceneTree

# The Corridor's two scripted PROP events, driven through their real code paths.
#
#   Godot --headless --path game --script res://tests/check_corridor_events.gd
#
# Both exist because of the 2026-08-17 playtest, and both are things a smoke test, a
# screenshot and every geometry sweep in the project are structurally blind to:
#
#   A. THE RUNNING SILHOUETTE (`_ev_silhouette`). The user: *"it is too far away from me. Can
#      we make it run when I'm much closer so that I can actually see it."* "Can I see it" is
#      an APPARENT SIZE question, and nothing in this project had ever measured one. So this
#      unprojects the real figure through the real player camera and reports the number — with
#      a control that rebuilds the OLD placement and requires it to measure small, because a
#      threshold nothing has ever failed is not a threshold.
#
#   C. THE ENTRANCE NOTE'S FACING (2026-08-18). A page lying flat has a right way up, and it
#      shipped 180° out — the first document in the level, upside down to the only person who
#      can read it. Nothing measured it: the two guards that look at wall props ask "is there
#      something behind this" and "is the artwork stretched", and a page rotated about its own
#      normal answers both correctly.
#
#   D. THE FALSE DOOR'S PAYLOAD (2026-08-18). Which sting it plays, and how bright the picture
#      is. Both are asserted against something the game already declares — `Screamer`'s own
#      shared/fatal table, and this level's own fatal screamer image — rather than against a
#      constant typed in here.
#
#   B. THE FALSE ROOM 217 (`FalseExitDoor`). A brand-new interactable that swings a COLLIDER
#      into a 3 m corridor at a corner the player must turn. This project has shipped that
#      exact defect three times in one week (Issues 65, 67, 76). It is also a one-shot, and a
#      one-shot that re-arms or that keeps offering a prompt after it has fired is invisible
#      until someone presses E twice.
#
# ⚠️ THE WIN PATH IS NEVER SHORT-CIRCUITED. `opened` is never emitted by this test; the door is
# opened by driving `player.ai_interact()` so the real raycast, `can_interact()` and prompt
# path all run (the project's standing rule, learned from a test that drove `cleared.emit()`
# and passed for weeks on an uncompletable level).

const SCENE := "res://scenes/corridor.tscn"
const W := 3.0
const MIN_FREE_WIDTH := 1.2      # a player capsule is ~0.8 m across
const MIN_APPARENT := 0.10       # the runner must stand >= 10 % of the screen's height
const OLD_APPARENT_MAX := 0.06   # ...and the placement it replaced must measure under 6 %

var _t := 0.0
var _stage := 0
var _fails: Array[String] = []
var _checks := 0
var _scene: Node = null
var _player: CharacterBody3D = null
var _door: Node3D = null
var _panic_before := 0.0
var _panic_gain := 0.0
var _spawn_xf := Transform3D.IDENTITY


func _initialize() -> void:
	change_scene_to_file(SCENE)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


# ---------------------------------------------------------------- helpers

func _cam() -> Camera3D:
	return _player.get_node_or_null("Camera3D") as Camera3D


# Point the player at a world position (yaw only — the camera child carries pitch).
func _face(from: Vector3, target: Vector3) -> void:
	var d := target - from
	d.y = 0.0
	d = d.normalized()
	_player.global_position = from
	_player.rotation.y = atan2(-d.x, -d.z)


# The fraction of the VIEWPORT'S HEIGHT a node's world-space bounds occupy, measured by
# unprojecting the eight corners of its aggregate AABB through the live camera. Resolution
# independent on purpose: headless runs at the project's default size and a pixel count would
# mean something different on the user's machine.
func _apparent_height(root: Node3D) -> float:
	var cam := _cam()
	if cam == null:
		return 0.0
	var pts: Array[Vector3] = []
	for n in _descendants(root):
		if not (n is VisualInstance3D):
			continue
		var aabb: AABB = (n as VisualInstance3D).get_aabb()
		for c in 8:
			pts.append((n as Node3D).global_transform * aabb.get_endpoint(c))
	if pts.is_empty():
		return 0.0
	var lo := INF
	var hi := -INF
	for p in pts:
		# ⚠️ Anything behind the eye unprojects to nonsense; drop it rather than clamp it.
		if cam.is_position_behind(p):
			continue
		var s := cam.unproject_position(p)
		lo = minf(lo, s.y)
		hi = maxf(hi, s.y)
	if not is_finite(lo) or not is_finite(hi):
		return 0.0
	return (hi - lo) / float(cam.get_viewport().get_visible_rect().size.y)


func _descendants(n: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(n)
	for c in n.get_children():
		_descendants(c, out)
	return out


func _find(root: Node, prefix: String) -> Node:
	for n in _descendants(root):
		if String(n.name).begins_with(prefix):
			return n
	return null


# The widest contiguous run of empty floor across a corridor line, measured with POINT
# QUERIES. ⚠️ Never `intersect_shape`: a capsule wholly inside a CSG slab comes back CLEAR
# (Issue 40), which is exactly the case being tested for.
func _free_width(centre: Vector3, lateral: Vector3, y: float) -> float:
	var space := _player.get_world_3d().direct_space_state
	var step := 0.05
	var best := 0.0
	var run := 0.0
	var i := -int(W / 2.0 / step)
	while i <= int(W / 2.0 / step):
		var p: Vector3 = centre + lateral * (i * step) + Vector3(0, y, 0)
		var q := PhysicsPointQueryParameters3D.new()
		q.position = p
		q.collide_with_areas = false
		q.collide_with_bodies = true
		# ⚠️ EXCLUDE THE PLAYER. They are standing 2.4 m from the door because this test just
		# walked them there to press E, and their own capsule chopped the free run from 2.20 m
		# to 1.15 m — a failure that looked exactly like the door sealing the corner.
		q.exclude = [_player.get_rid()]
		if space.intersect_point(q, 4).is_empty():
			run += step
			best = maxf(best, run)
		else:
			run = 0.0
		i += 1
	return best


# ---------------------------------------------------------------- the run

func _process(delta: float) -> bool:
	_t += delta
	match _stage:
		0:
			if _t < 1.0:
				return false
			_scene = current_scene
			_player = _scene.get_node_or_null("Player") as CharacterBody3D
			_ok("the player exists", _player != null)
			_ok("the camera exists", _cam() != null)
			if _player == null or _cam() == null:
				return _report()
			# ⚠️ SAMPLED BEFORE ANYTHING MOVES THE PLAYER. `_silhouette()` teleports them 219 m
			# down the level, so the spawn pose has to be captured on the frame the scene is
			# handed over — this is the only reference the note-facing check has that is not
			# the same table the level built the note from.
			_spawn_xf = _player.global_transform
			_silhouette()
			_false_door_static()
			_false_door_payload()
			_entrance_note()
			_stage = 1
			_t = 0.0
		1:
			# ⚠️ POSITION AND PRESS E ARE TWO FRAMES APART, deliberately. `_interact_target` is
			# recomputed in the player's own `_process` from a raycast, so asking for it in the
			# same frame the player was teleported reads the target from where they USED to be
			# — which is null, and which would have made this look like a broken door.
			if _t < 0.2:
				return false
			_false_door_place()
			_stage = 2
			_t = 0.0
		2:
			if _t < 0.4:
				return false
			_false_door_open()
			_stage = 3
			_t = 0.0
		3:
			# FALSE_DOOR_HOLD 0.9 + FALSE_DOOR_SCRAWL_DELAY 0.45, plus slack.
			if _t < 1.9:
				return false
			_false_door_after()
			_stage = 4
			_t = 0.0
		4:
			# ⚠️ A PHYSICS FRAME, not a process frame. `intersect_point` reads the physics
			# server's state, so a body added and positioned in the previous call is simply not
			# there yet — the first version of this control reported 3.05 m of free floor with
			# a 2.4 m block standing in it.
			if _t < 0.3:
				return false
			_free_width_control()
			return _report()
	return false


# ---- A. THE RUNNING SILHOUETTE ------------------------------------------------------------

func _silhouette() -> void:
	var cs: GDScript = _scene.get_script()
	var trig: float = float(cs.get("SILHOUETTE_TRIGGER"))
	var cross: float = float(cs.get("SILHOUETTE_CROSS"))
	var side_off: float = float(cs.get("SILHOUETTE_SIDE"))
	var db: float = float(cs.get("SILHOUETTE_DB"))
	var max_db: float = float(cs.get("SILHOUETTE_MAX_DB"))

	# ⚠️ The one number that must NOT have moved. The brief was explicit: the beat gets closer
	# and louder, and the panic it costs is the user's call and was not compounded.
	_ok("SILHOUETTE_PANIC is still 20", is_equal_approx(float(cs.get("SILHOUETTE_PANIC")), 20.0),
		"%.1f" % float(cs.get("SILHOUETTE_PANIC")))
	_ok("the figure runs across AHEAD of the trigger, not behind it", cross > trig,
		"trigger %.0f m, crossing %.0f m -> %.1f m ahead" % [trig, cross, cross - trig])
	# ⚠️ The start and end must be BEHIND the walls. The corridor's inner faces are at W/2 and
	# the slabs are 0.3 m thick, so anything past 1.5 is out of sight and past 1.8 is outside
	# the building. At 8 m the old ±1.2 (inside the hall) would have the figure blinking into
	# existence in mid-air.
	_ok("it enters and leaves from BEHIND the walls", side_off > W / 2.0 + 0.3,
		"±%.2f m against a wall face at %.2f m" % [side_off, W / 2.0])

	# Stand the player at the trigger, facing along the corridor, and fire the REAL event.
	var here := _scene.call("_path_point", trig) as Dictionary
	var there := _scene.call("_path_point", cross) as Dictionary
	_face(here.pos as Vector3, there.pos as Vector3)
	_panic_before = _player.get_panic_ratio()
	_scene.call("_ev_silhouette")

	var fig := _find(_scene, "SilhouetteRunner") as Node3D
	_ok("the figure was spawned", fig != null)
	if fig == null:
		return

	# ---- IS IT A FIGURE, or a pill? Issue 35: bringing a capsule closer makes it a bigger
	# capsule. Parts, and dark parts — this thing must OCCLUDE the lit wall, not glow.
	var meshes: Array[Node] = []
	for n in _descendants(fig):
		if n is MeshInstance3D:
			meshes.append(n)
	_ok("it is built from PARTS, not one capsule", meshes.size() >= 6,
		"%d meshes" % meshes.size())
	var brightest := 0.0
	var worst_emission := 0.0
	for m in meshes:
		var mat := (m as MeshInstance3D).material_override as StandardMaterial3D
		if mat == null:
			continue
		var a: Color = mat.albedo_color
		brightest = maxf(brightest, (a.r + a.g + a.b) / 3.0)
		if mat.emission_enabled:
			worst_emission = maxf(worst_emission, mat.emission_energy_multiplier)
	_ok("it is a dark silhouette, not a lit prop", brightest < 0.08 and worst_emission <= 0.5,
		"albedo %.3f, emission x%.2f" % [brightest, worst_emission])

	# ---- APPARENT SIZE, the actual complaint.
	var now := _apparent_height(fig)
	_ok("the figure is big enough on screen to read as a figure", now >= MIN_APPARENT,
		"%.1f %% of the screen's height at %.1f m"
			% [now * 100.0, (fig.global_position - _player.global_position).length()])

	# ---- THE CONTROL, and it is what makes the number above mean anything: rebuild the OLD
	# placement — a 1.75 m capsule at d=228.5 seen from d=205 — and require it to be small.
	var old_fig := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.75
	old_fig.mesh = cap
	_scene.add_child(old_fig)
	var old_here := _scene.call("_path_point", 205.0) as Dictionary
	var old_there := _scene.call("_path_point", 228.5) as Dictionary
	old_fig.global_position = (old_there.pos as Vector3) + Vector3(0, 0.9, 0)
	var keep := _player.global_transform
	_face(old_here.pos as Vector3, old_there.pos as Vector3)
	var before := _apparent_height(old_fig)
	_ok("CONTROL: the placement this replaced measures SMALL", before <= OLD_APPARENT_MAX,
		"%.1f %% at 23.5 m -> the new one is %.1fx larger" % [before * 100.0, now / maxf(before, 1e-6)])
	old_fig.queue_free()
	_player.global_transform = keep

	# ---- THE SOUND RIDES THE FIGURE. `_play_at` parents to the level; this one must not.
	var emitter: AudioStreamPlayer3D = null
	for n in _descendants(fig):
		if n is AudioStreamPlayer3D:
			emitter = n
	_ok("the scream is a CHILD of the runner, so it travels with it", emitter != null)
	if emitter != null:
		_ok("...and it is the right sample", emitter.stream != null
			and emitter.stream.resource_path.get_file().get_basename() == "jumpscare",
			emitter.stream.resource_path if emitter.stream else "null")
		_ok("...at the gain the constant declares", is_equal_approx(emitter.volume_db, db),
			"%.1f dB" % emitter.volume_db)
		# ⚠️ `shared/jumpscare.wav` peaks at 0.0 dBFS, so the default max_db 6.0 would let a
		# SPRINTING player who closes to 4 m add another 6 dB and clip the master.
		_ok("...with max_db pinned so a close pass cannot clip",
			is_equal_approx(emitter.max_db, max_db), "%.1f dB" % emitter.max_db)

	_ok("the event still costs exactly SILHOUETTE_PANIC",
		is_equal_approx((_player.get_panic_ratio() - _panic_before) * 50.0,
			float(cs.get("SILHOUETTE_PANIC"))),
		"+%.1f" % ((_player.get_panic_ratio() - _panic_before) * 50.0))
	_player.set("_panic", 0.0)


# ---- B. THE FALSE ROOM 217 ----------------------------------------------------------------

func _false_door_static() -> void:
	var cs: GDScript = _scene.get_script()
	_door = _find(_scene, "FalseExitDoor") as Node3D
	_ok("the false exit door exists", _door != null)
	if _door == null:
		return

	var dist: float = float(cs.get("FALSE_DOOR_DIST"))
	var total: float = float(_scene.get("_total_len"))
	_ok("it is nowhere near the real exit", total - dist >= 100.0,
		"%.0f m from the door at %.0f m" % [total - dist, total])
	# ⚠️ Not on a mirror corner — those two are spoken for and already carry two beats each.
	var clash := false
	for m in (cs.get("TURN_MIRRORS") as Array):
		if absf(float(m[0]) - dist) < 5.0:
			clash = true
	_ok("it is not on a turn-mirror corner", not clash, "d=%.0f m" % dist)

	# It has to look like an exit from FAR AWAY or the deception never starts. Measured the
	# same way the silhouette is: from the far end of the approach leg.
	var far := _scene.call("_path_point", dist - 44.0) as Dictionary
	var keep := _player.global_transform
	_face(far.pos as Vector3, _door.global_position)
	var frame := _find(_scene, "FalseExitFrame") as Node3D
	_ok("the blood-red frame exists", frame != null)
	if frame != null:
		var lit := false
		var energy := 0.0
		for n in _descendants(frame):
			var mi := n as MeshInstance3D
			if mi == null:
				continue
			var mat := mi.material_override as StandardMaterial3D
			if mat != null and mat.emission_enabled:
				lit = true
				energy = maxf(energy, mat.emission_energy_multiplier)
		_ok("the frame is emissive — the exit livery", lit, "energy x%.2f" % energy)
		# ⚠️ Issue 21: above 1.0 this renderer clamps to flat white with no detail.
		_ok("...and not above the 1.0 clamp", energy <= 1.0, "x%.2f" % energy)
		_ok("it is visible from the far end of the approach",
			_apparent_height(frame) > 0.02,
			"%.2f %% of screen height at 44 m" % (_apparent_height(frame) * 100.0))
	var glow := _find(_scene, "FalseExitGlow") as OmniLight3D
	_ok("there is a real red light, not only emission", glow != null,
		"range %.1f m" % (glow.omni_range if glow != null else 0.0))
	# The dark beartrap stretch must stay dark: DARK_ZONES ends at 172.
	if glow != null:
		var zones: Array = cs.get("DARK_ZONES")
		var nearest := INF
		for z in zones:
			nearest = minf(nearest, absf(dist - float((z as Vector2).y)))
		_ok("its light cannot reach the dark beartrap stretch", glow.omni_range < nearest,
			"range %.1f m vs %.1f m away" % [glow.omni_range, nearest])

	_ok("it advertises a prompt before it has been used", _door.call("can_interact"))
	# The leaf must be the 217 art. If this ever silently falls back, the whole trap is a
	# generic hotel door and nothing about the beat works.
	var face := _find(_door, "Face_front") as MeshInstance3D
	_ok("the leaf wears the 217 artwork", face != null
		and (face.material_override as StandardMaterial3D) != null
		and (face.material_override as StandardMaterial3D).albedo_texture != null
		and (face.material_override as StandardMaterial3D).albedo_texture.resource_path
			.get_file() == "hotel_door_217.png",
		String((face.material_override as StandardMaterial3D).albedo_texture.resource_path)
			if face != null else "no face")
	_player.global_transform = keep


func _false_door_place() -> void:
	if _door == null:
		return
	# Stand where a player walking up to it would, and aim at the MESH, never at the collider —
	# aiming at the collider is what let a previous version of `check_interact_reach.gd` pass
	# against volumes a player could not actually hit.
	var cs: GDScript = _scene.get_script()
	var dist: float = float(cs.get("FALSE_DOOR_DIST"))
	var approach := _scene.call("_path_point", dist - 0.9) as Dictionary
	var leaf := _find(_door, "Leaf") as MeshInstance3D
	var aim: Vector3 = leaf.global_position if leaf != null else _door.global_position
	_face(approach.pos as Vector3, aim)
	_cam().rotation.x = 0.0
	_player.set("ai_active", true)


func _false_door_open() -> void:
	if _door == null:
		return
	_panic_before = _player.get_panic_ratio()
	_ok("the shipping raycast finds it", _player.call("ai_interact_target") == _door,
		"%.2f m away, target %s"
			% [_player.global_position.distance_to(_door.global_position),
				str(_player.call("ai_interact_target"))])
	_player.call("ai_interact")
	# ⚠️ SAMPLED HERE, NOT IN THE NEXT STAGE. Panic decays at 3.5/s, and the scrawl this test
	# also has to wait for lands 1.35 s later — so measuring the spike after the wait reported
	# +8.4 for a +15 event and looked like a real defect. Measure a spike where it happens.
	_panic_gain = (_player.get_panic_ratio() - _panic_before) * 50.0


func _false_door_after() -> void:
	if _door == null:
		return
	var cs: GDScript = _scene.get_script()
	_ok("opening it costs FALSE_DOOR_PANIC and nothing else",
		is_equal_approx(_panic_gain, float(cs.get("FALSE_DOOR_PANIC"))), "+%.1f" % _panic_gain)
	_ok("the leaf actually swung", not is_zero_approx(_door.rotation.y - _door_rest_y()),
		"%.1f deg" % rad_to_deg(absf(_door.rotation.y - _door_rest_y())))

	# ---- THE SCRAWL. The user asked for "the title written with red that It was an illusion",
	# and `ScreenText.scrawl` parents to the TREE ROOT, not to the level.
	var want: String = String(cs.get("FALSE_DOOR_SCRAWL"))
	var found := ""
	for n in _descendants(root):
		if n is Label and String((n as Label).text) == want:
			found = want
	_ok("the blood-red scrawl says it was an illusion", found == want,
		"looked for %s" % want)

	# ---- ONE-SHOT.
	_ok("it goes inert once it has fired", not _door.call("can_interact"))
	var p2: float = _player.get_panic_ratio()
	_door.call("interact")
	_ok("...and a second press costs nothing", is_equal_approx(_player.get_panic_ratio(), p2))

	# ---- IT MUST NOT SEAL THE CORNER. The leaf's collider swings with it, into a 3 m hall,
	# at a corner the player is required to turn. Issues 65/67/76 are three shipped instances
	# of an interactable narrowing a route by being used.
	var dist: float = float(cs.get("FALSE_DOOR_DIST"))
	var worst := 99.0
	var worst_at := 0.0
	for off in [0.1, 0.2, 0.4, 0.8, 1.2, 1.8, 2.4]:
		var pt := _scene.call("_path_point", dist + off) as Dictionary
		var free: float = _free_width(pt.pos as Vector3, pt.side as Vector3, 1.0)
		if free < worst:
			worst = free
			worst_at = off
	_ok("the OPEN door still leaves a walkable corner", worst >= MIN_FREE_WIDTH,
		"narrowest %.2f m of %.1f, %.1f m past the corner" % [worst, W, worst_at])

	_spawn_free_width_control(dist)


# ---- C. THE ENTRANCE NOTE READS FROM THE APPROACH ------------------------------------------
#
# 2026-08-18 capture 001: *"Turn it 180 degrees, it is currently the wrong side from the place
# I enter the room"*. A page lying flat has a right way up and nothing in this project had ever
# measured one — `check_note_mounting.gd` asks whether there is something BEHIND a prop and
# `check_art_aspect.gd` asks whether its artwork is stretched; both are perfectly happy with a
# document rotated 180° about its own normal.
#
# ⚠️ THE REFERENCE IS THE SPAWN, NOT THE PATH TABLE. `corridor.gd` now yaws the note from
# `pt.dir`, so asserting against `_path_point()` would only prove the level agrees with itself.
# `_spawn_xf` is read out of `corridor.tscn` before anything in this test moves the player.
const NOTE_FACE_DOT := 0.85     # the text's up vs. the walking direction
const NOTE_FLAT_DOT := 0.99     # the page's normal vs. world up
const NOTE_TABLE_GAP := 0.35    # how far under the page the table may be before it is floating

func _entrance_note() -> void:
	var note := _find(_scene, "IntroNote") as Node3D
	_ok("the entrance note exists", note != null)
	if note == null:
		return
	var page := _find(note, "NotePage") as MeshInstance3D
	_ok("...and it carries a real page quad", page != null)
	if page == null:
		return

	# Two independent readings of "which way is the player coming from", so the assertion
	# cannot be satisfied by the level's own bookkeeping alone.
	var spawn_pos: Vector3 = _spawn_xf.origin
	var spawn_fwd: Vector3 = -_spawn_xf.basis.z
	spawn_fwd.y = 0.0
	spawn_fwd = spawn_fwd.normalized()
	var to_note: Vector3 = page.global_position - spawn_pos
	to_note.y = 0.0
	to_note = to_note.normalized()
	_ok("the note is ahead of the spawn, along the way the player is facing",
		spawn_fwd.dot(to_note) > 0.7,
		"spawn %s facing %s, note %s" % [str(spawn_pos.round()), str(spawn_fwd), str(page.global_position.round())])
	# ⚠️ THE APPROACH IS THE SPAWN'S FACING, not the spawn->note vector. The table stands 1.05 m
	# off the centreline, so spawn->note is a 28° diagonal (dot 0.885) and a threshold set
	# against it would be within 0.035 of passing a page turned 90°. The player walks PAST this
	# table, they do not walk AT it. Sound only while the note is still on the level's first
	# straight, which is what the next line requires.
	var path_dir: Vector3 = ((_scene.call("_path_point", 4.0) as Dictionary).dir as Vector3).normalized()
	_ok("the spawn faces straight down the segment the note is on",
		spawn_fwd.dot(path_dir) > 0.99, "dot %+.4f" % spawn_fwd.dot(path_dir))

	var normal: Vector3 = page.global_basis.z.normalized()
	var text_up: Vector3 = page.global_basis.y.normalized()
	_ok("the page lies flat, artwork upward", normal.dot(Vector3.UP) > NOTE_FLAT_DOT,
		"normal %s (dot %.4f)" % [str(normal), normal.dot(Vector3.UP)])
	# THE ACTUAL COMPLAINT. On a page lying flat, the top of the lettering must point AWAY
	# from the reader — a reader standing where the player arrives from reads "up the page"
	# as "further along the corridor". Pointing it back at them is upside-down text.
	_ok("the lettering reads right way up to a player arriving from the spawn",
		text_up.dot(spawn_fwd) > NOTE_FACE_DOT,
		"text-up %s vs the spawn's heading %s -> dot %+.3f"
			% [str(text_up), str(spawn_fwd), text_up.dot(spawn_fwd)])

	# ⚠️ THE ROTATION MUST NOT HAVE LIFTED IT OFF THE TABLE. Turning a prop is exactly how a
	# mounted thing becomes a floating thing, and the table is a CSG box that this page is
	# meant to be lying ON.
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		page.global_position + Vector3(0, 0.02, 0),
		page.global_position - Vector3(0, NOTE_TABLE_GAP, 0))
	q.collide_with_areas = false
	q.exclude = [_player.get_rid(), (note as StaticBody3D).get_rid()]
	var hit := space.intersect_ray(q)
	_ok("the page is still resting on something solid, not floating",
		not hit.is_empty(),
		"table %.3f m below" % ((page.global_position.y - (hit.position as Vector3).y) if not hit.is_empty() else -1.0))


# ---- D. THE FALSE DOOR'S PAYLOAD -----------------------------------------------------------
#
# 2026-08-18 capture 002: *"Use the sounds for shared screamers and make it louder. Make the
# image more dark and aggressive"*. Both halves are properties of the ASSET, not of the
# mechanism, and the mechanism is what every other check in this file measures.
func _false_door_payload() -> void:
	var cs: GDScript = _scene.get_script()

	# ---- THE SOUND. `Screamer.FALLBACK_AUDIO` is the shared screamer sting — the one
	# `_apply_level_av()` pairs with the shared `screamers/` image pool — so "the sounds for
	# shared screamers" is a name this test can read rather than a string it has to trust.
	# ⚠️ THROUGH THE NODE, never the bare identifier — an autoload's name is not in scope when
	# a `--script` SceneTree compiles (check_bus_leak.gd carries the same note).
	var screamer := root.get_node_or_null("/root/Screamer")
	var gs := root.get_node_or_null("/root/GameState")
	_ok("the Screamer and GameState autoloads are present", screamer != null and gs != null)
	if screamer == null or gs == null:
		return
	var shared: String = String(screamer.get("FALLBACK_AUDIO"))
	var base: String = String(cs.get("FALSE_DOOR_SCREAM"))
	_ok("the flash uses the SHARED screamer sting", base == shared,
		"%s vs Screamer.FALLBACK_AUDIO %s" % [base, shared])
	_ok("...and it actually resolves to a stream", gs.call("load_audio", base) != null, base)
	# ⚠️ AND IT IS NOT THIS LEVEL'S DEATH SOUND. The Corridor dies to `screamer_corridor`
	# (`Screamer.LEVEL_SCREAMERS[3]`); a SURVIVABLE trap that plays the level's fatal sting
	# teaches the player that the death sound is free, which is the objection INTRO.md §301
	# raises against reusing it. The shared sting is heard nowhere else in this level.
	var level_av: Dictionary = screamer.get("LEVEL_SCREAMERS")
	var fatal: String = String((level_av.get(3) as Array)[1])
	_ok("...and it is NOT the sound the player dies to in this level", base != fatal,
		"survivable %s vs fatal %s" % [base, fatal])

	# ---- THE IMAGE. Fullscreen, in a renderer with no tonemapping: a pale screamer is a
	# white flashbang. The reference is the level's OWN fatal screamer rather than a magic
	# number, so the bar moves if the level's art direction ever does.
	var ours := _image_stats(String(cs.get("FALSE_DOOR_SCARE_PATH")))
	var ref := _image_stats(String((level_av.get(3) as Array)[0]))
	_ok("both screamer images loaded", ours.n > 0 and ref.n > 0,
		"%d and %d pixels sampled" % [ours.n, ref.n])
	if ours.n == 0 or ref.n == 0:
		return
	# ⚠️ ASSERT THE SAMPLE SIZE. A stride sample that silently collapsed to nothing would
	# report a comfortable mean of 0 and pass.
	_ok("...and the sample is big enough to mean anything", ours.n >= 10000 and ref.n >= 10000,
		"%d / %d" % [ours.n, ref.n])
	_ok("the false-door screamer is no brighter than the level's own screamer",
		ours.mean <= ref.mean * 1.25,
		"mean %.1f vs screamer_hotel %.1f" % [ours.mean, ref.mean])
	_ok("...and it has essentially no blown-out pixels", ours.hot <= 0.25,
		"%.2f %% above 0.90 sRGB (was 1.97 %% before this pass)" % ours.hot)
	# It still has to READ in 0.9 s — "dark" must not become "a black rectangle".
	_ok("...but the subject is still legible against the black panel", ours.p99 >= 40.0,
		"p99 luminance %.1f of 255" % ours.p99)


# Mean / p99 / percentage-above-0.90 luminance of an imported texture, stride-sampled.
# ⚠️ Stride, never `Image.resize`: a bilinear downsample AVERAGES, which is exactly how a
# small blown-out highlight disappears from the statistic that exists to find it.
func _image_stats(path: String) -> Dictionary:
	var out := {"n": 0, "mean": 0.0, "p99": 0.0, "hot": 0.0}
	if not ResourceLoader.exists(path):
		return out
	var tex: Texture2D = load(path)
	if tex == null:
		return out
	var img: Image = tex.get_image()
	if img == null:
		return out
	if img.is_compressed():
		img.decompress()
	var lums: Array[float] = []
	var hot := 0
	var step := 3
	var y := 0
	while y < img.get_height():
		var x := 0
		while x < img.get_width():
			var c: Color = img.get_pixel(x, y)
			var l: float = (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0
			lums.append(l)
			if l > 0.90 * 255.0:
				hot += 1
			x += step
		y += step
	if lums.is_empty():
		return out
	lums.sort()
	var total := 0.0
	for l in lums:
		total += l
	out.n = lums.size()
	out.mean = total / float(lums.size())
	out.p99 = lums[int(float(lums.size()) * 0.99)]
	out.hot = float(hot) / float(lums.size()) * 100.0
	return out


# ⚠️ A PERMANENT POSITIVE CONTROL, and it is not optional here. Swinging this leaf to 150°
# was tried as a control and the measurement stayed green at 2.55 m — a 0.909 m panel
# CANNOT seal a 3 m hall from a wall at any angle, so the assertion above is unfalsifiable
# by the prop it is guarding. That makes it worth exactly nothing unless something proves
# it still measures. Its real value is a future re-placement (a wider leaf, a side wall, a
# second door), which is precisely the case this control simulates.
var _control_pt: Dictionary = {}

func _spawn_free_width_control(dist: float) -> void:
	var pt := _scene.call("_path_point", dist + 1.2) as Dictionary
	_control_pt = pt
	var blocker := StaticBody3D.new()
	blocker.name = "FreeWidthControl"
	var bcol := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(2.4, 2.0, 0.6)
	bcol.shape = bshape
	blocker.add_child(bcol)
	_scene.add_child(blocker)
	blocker.global_position = (pt.pos as Vector3) + (pt.side as Vector3) * 0.3 + Vector3(0, 1.0, 0)
	blocker.rotation.y = atan2((pt.side as Vector3).z, (pt.side as Vector3).x)


func _free_width_control() -> void:
	if _control_pt.is_empty():
		return
	var blocked: float = _free_width(_control_pt.pos as Vector3, _control_pt.side as Vector3, 1.0)
	_ok("CONTROL: a real obstruction in the same corner IS measured",
		blocked < MIN_FREE_WIDTH, "%.2f m free with the control block in place" % blocked)
	var b := _find(_scene, "FreeWidthControl")
	if b != null:
		b.queue_free()


# The rest angle, recovered from the frame that never rotates.
func _door_rest_y() -> float:
	var frame := _find(_scene, "FalseExitFrame") as Node3D
	return frame.rotation.y if frame != null else 0.0


func _report() -> bool:
	print("  %d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL — ", ", ".join(_fails))
		quit(1)
	return true
