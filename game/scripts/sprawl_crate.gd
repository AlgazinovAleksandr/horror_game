extends StaticBody3D
class_name SprawlCrate

# THE BOX IN THE DARK — the Sprawl's one interactable, and the first half of the user's own
# design for zone 2 (backlog 04 B-R3, 2026-08-17): *"the first whisper would lead to that
# box hidden in the dark"*, and opening it is what starts everything else.
#
# It replaces one of the four featureless `AlcProp` boxes — the one the player photographed
# on capture 004 and read as scenery, which is what it was: a 1.1 x 0.75 x 0.6 CSG cube with
# a flat brown tint. Issue 35 in its purest form.
#
# ⚠️ ZERO PANIC IN THIS FILE. The scare it fires is `Screamer.flash_scare()` — a survivable
# image and a sound, with no `add_panic()` behind it and no fail state — and the level, not
# the prop, owns whatever consequence it has. Whether that scare should cost anything at all
# is a question this pass returned to the user rather than answered: the standing rule is
# `GAME_MECHANICS_IDEAS.md` §0.2, stop adding panic terms and start adding channels.
#
# ⚠️⚠️ THE WHISPER IS PERMANENT WHILE THE BOX IS SHUT, AND SINCE 2026-08-18 THAT IS A
# COMPLETABILITY GUARANTEE RATHER THAN A MOOD CHOICE. The crate is now the GATE — the real
# glitch wall is sealed until the thing inside runs through it — so a player who never finds
# this box cannot leave the zone. The two loops therefore have **no timer, no one-shot, no
# distance gate and no stop path**: they start in `_build_voice()` and the only thing that
# ever moves them is `SprawlDweller.adopt_voice()`, which runs on the frame the box opens.
# It is the Flood's rule in a second place (`sunken_item.gd:_process` is gated on `is_taken`
# and never on `is_searched`, so an object you abandoned keeps calling), and
# `check_sprawl_crate.gd` asserts it by running the level for real seconds and requiring
# both players still playing.
#
# In the two-layer far-cue / near-confirm form this project has now solved the same problem
# in four other places (`level_1.gd`'s dark wing, `backrooms.gd`'s seam,
# `backrooms_zone2.gd`'s real wall, `flood_plate.gd`).
#
# ⚠️ MASTER BUS, NEVER `"Backrooms"`. A `SilenceZone` ducks that bus — it is how the zone's
# own real-wall tell works — so a cue routed through it mutes itself exactly when the player
# walks into the pocket. `backrooms_zone2.gd`'s header is a post-mortem of that mistake, and
# this is a second cue in the same room.
#
# ⚠️ AND IT MUST NOT SOUND LIKE THE REAL WALL. The wall speaks `water` + `whisper`; this
# speaks `sprawl_call_far` + `sprawl_call_near`, which are formant-shaped breath with no
# tone in them at all (`tools/make_sfx_backrooms_puzzle.py` says why). Two cues in one room
# that sound alike is one cue pointing at two places.

signal opened

const FAR_AUDIO := "sprawl_call_far"
const NEAR_AUDIO := "sprawl_call_near"
# ⚠️⚠️ RETUNED 2026-08-18, AND THE OLD VALUES WERE INAUDIBLE EVERYWHERE. This block used to
# read "gains from the files' measured RMS" and stop there — the files were measured and the
# BED THEY PLAY OVER WAS NOT. Measured now: the Sprawl's competing bed is the score at
# `backrooms.gd:MUSIC_VOLUME_DB` -4 on a -18 dBFS file = **-22.0 dBFS effective** (the
# fluorescent hum lands -24.3), and the old far cue reached **-25.2 dBFS with your nose
# against the box** — 3.2 dB UNDER the music at the one place it was loudest, falling to
# -13.2 dB of margin at the far corner. The call that is supposed to lead the player into
# the dark could not be heard from anywhere in the room.
#
# That was survivable while the crate was an optional aid. It is not survivable now: the
# crate is the GATE (`backrooms_zone2.gd`), so this loop is the only thing standing between
# the design and an unwinnable zone. ISSUES_SOLUTIONS Issue 131.
#
# ⚠️ AND THE STANDARD IT IS TUNED TO IS "AUDIBLE EVERYWHERE", NOT "A LEVEL GRADIENT
# EVERYWHERE" — one emitter cannot do both, and the arithmetic says so rather than the
# taste: `level(d) = min(max_db, volume_db + 20log10(unit/d))`, so the dB of gradient
# available between two distances is fixed by their RATIO. Spanning 3 m to 48 m with a
# usable slope needs 24 dB of range, which would put the cue at +4 dBFS on top of you.
# So the FAR cue carries the hall almost flat and gives its bearing by PANNING (Godot pans
# an `AudioStreamPlayer3D` by angle, which is a direction a flat level still has), and the
# NEAR confirm supplies the last-stretch gradient. This is the same two-layer split the
# Flood's plate uses, stated as a rule rather than rediscovered.
#
# Measured, against a -22.0 dBFS bed, at the worst standable point (48.3 m, the opposite
# recess): far cue **-18.0 dBFS, margin +4.0**; at the crate **-12.2, margin +9.8**. The
# near confirm is +10.1 at 2 m, +3.1 at 10 m and **below the bed past ~18 m**, which is
# what makes the pair two layers rather than two copies.
const FAR_DB := 6.0
const NEAR_DB := 6.0
const FAR_UNIT := 22.0
const NEAR_UNIT := 4.0
const FAR_MAX_DB := 5.0
const NEAR_MAX_DB := 5.0
const TELL_BUS := "Master"

const SIZE := Vector3(1.05, 0.78, 0.72)
const LID_TIME := 0.45

var _opened := false
var _lid: Node3D = null
var _far: AudioStreamPlayer3D = null
var _near: AudioStreamPlayer3D = null


static func build(parent: Node, crate_name: String, pos: Vector3,
		yaw: float) -> SprawlCrate:
	var c := SprawlCrate.new()
	c.name = crate_name
	parent.add_child(c)
	c.position = pos
	c.rotation.y = yaw
	return c


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build()
	_build_collider()
	_build_voice()


# ---------------------------------------------------------------- construction
#
# ⚠️ BUILT FROM PARTS (Issue 35). A shipping crate is corner posts, slats with gaps between
# them, banding, and a lid that stands proud — the thing it replaced was one brown box, and
# the player's note on it was *"There were so many objects I had to interact with for
# nothing"* about its neighbours and nothing at all about this, because there was nothing
# to say. Flat-tinted, untextured, NO emission: this must be findable by EAR, not by glow.

func _flat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _part(parent: Node3D, part_name: String, size: Vector3, pos: Vector3,
		mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build() -> void:
	var wood := _flat(Color(0.20, 0.15, 0.10), 0.95)
	var pale := _flat(Color(0.29, 0.23, 0.15), 0.9)
	var iron := _flat(Color(0.13, 0.13, 0.14), 0.7)

	# Four corner posts, so the silhouette has vertical structure at every angle.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_part(self, "Post%d%d" % [int(sx), int(sz)],
				Vector3(0.10, SIZE.y - 0.08, 0.10),
				Vector3(sx * (SIZE.x / 2.0 - 0.05), (SIZE.y - 0.08) / 2.0,
					sz * (SIZE.z / 2.0 - 0.05)), wood)
	# Slats with gaps between them — the gaps are what stop it reading as a box.
	for i in range(3):
		var y: float = 0.14 + float(i) * 0.22
		_part(self, "SlatFront%d" % i, Vector3(SIZE.x - 0.06, 0.15, 0.04),
			Vector3(0, y, -SIZE.z / 2.0 + 0.02), pale)
		_part(self, "SlatBack%d" % i, Vector3(SIZE.x - 0.06, 0.15, 0.04),
			Vector3(0, y, SIZE.z / 2.0 - 0.02), pale)
		_part(self, "SlatLeft%d" % i, Vector3(0.04, 0.15, SIZE.z - 0.06),
			Vector3(-SIZE.x / 2.0 + 0.02, y, 0), pale)
		_part(self, "SlatRight%d" % i, Vector3(0.04, 0.15, SIZE.z - 0.06),
			Vector3(SIZE.x / 2.0 - 0.02, y, 0), pale)
	_part(self, "Band", Vector3(SIZE.x + 0.02, 0.035, 0.05),
		Vector3(0, 0.47, -SIZE.z / 2.0 - 0.01), iron)

	# The lid, hinged along the far edge so it opens TOWARD the player.
	_lid = Node3D.new()
	_lid.name = "CrateLid"
	_lid.position = Vector3(0, SIZE.y - 0.05, SIZE.z / 2.0)
	add_child(_lid)
	_part(_lid, "LidSlab", Vector3(SIZE.x + 0.04, 0.06, SIZE.z + 0.04),
		Vector3(0, 0.03, -SIZE.z / 2.0), wood)
	_part(_lid, "LidRib", Vector3(SIZE.x + 0.06, 0.04, 0.06),
		Vector3(0, 0.06, -SIZE.z + 0.04), iron)

	# The inside, seen once the lid goes: an empty crate with straw and one handprint's
	# worth of dark. There is nothing to take — the thing that was in it leaves on its own.
	var inner := _part(self, "CrateFloor", Vector3(SIZE.x - 0.14, 0.05, SIZE.z - 0.14),
		Vector3(0, 0.10, 0), _flat(Color(0.07, 0.06, 0.05), 1.0))
	inner.name = "CrateFloor"
	_part(self, "Straw", Vector3(SIZE.x - 0.26, 0.06, SIZE.z - 0.30),
		Vector3(0.05, 0.15, -0.04), _flat(Color(0.16, 0.14, 0.09), 1.0))


func _build_collider() -> void:
	var col := CollisionShape3D.new()
	col.name = "CrateCollision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE.x, SIZE.y, SIZE.z)
	col.shape = shape
	col.position = Vector3(0, SIZE.y / 2.0, 0)
	add_child(col)


func _build_voice() -> void:
	_far = _make_loop("CrateCallFar", FAR_AUDIO, FAR_DB, FAR_UNIT, FAR_MAX_DB)
	_near = _make_loop("CrateCallNear", NEAR_AUDIO, NEAR_DB, NEAR_UNIT, NEAR_MAX_DB)


func _make_loop(loop_name: String, base: String, db: float, unit: float,
		ceiling: float) -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.name = loop_name
	a.volume_db = db
	a.unit_size = unit
	a.max_db = ceiling
	a.bus = TELL_BUS
	add_child(a)
	a.position = Vector3(0, SIZE.y * 0.7, 0)
	var s := GameState.load_audio(base)
	if not s:
		push_warning("SprawlCrate: '%s' has no audio — the box cannot be found" % base)
		return a
	a.stream = s
	# ⚠️ Every .wav.import here is loop_mode=0, so the node restarts itself.
	a.finished.connect(a.play)
	a.play()
	return a


func voice_players() -> Array:
	return [_far, _near]


# ---------------------------------------------------------------- interaction

func is_opened() -> bool:
	return _opened


func can_interact() -> bool:
	return not _opened


func interact() -> void:
	if _opened:
		return
	_opened = true
	# The lid goes first and fast — the level fires the scare on the same frame, so the
	# order the player perceives is: the box opens, and then it is on top of them.
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_lid, "rotation:x", -2.1, LID_TIME)
	opened.emit()
