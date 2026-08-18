extends SceneTree

# The covered body on the Intro Room's gurneys — that it is a BODY, and that it is SMOOTH.
#
# WHY THIS EXISTS. This prop has now been rejected on a playtest replay twice:
#
#   v1  two axis-aligned boxes  -> "Is it a human on the bed? Or a pillow and a blanket?"
#   v2  eleven axis-aligned boxes, more detailed and WORSE — a stack of blocks with hard
#       corners and coplanar tops -> "This still does not look realistic."
#
# Both versions passed every test in the suite. `check_wall_overlap.gd` had nothing to say
# (the boxes did not overlap), `check_intro_beats.gd` counted the forms and was satisfied,
# and `check_art_aspect.gd` skips it because it carries no flat quad. So the thing the user
# actually rejected — the SHAPE — was the one property nothing measured. This measures it.
#
# ⚠️ Everything below is read off the BUILT MESH ARRAYS, never off the generator's own
# height function. Testing `_sheet_height()` against itself would prove nothing; the failure
# mode both previous versions had was that the code did exactly what it said and the result
# was wrong. What is asserted is the shape that actually reached the vertex buffer.
#
# ⚠️ It asserts its own SAMPLE SIZE. "0 forms checked ... PASS" has happened twice in this
# project (count_apparitions.gd, check_apparition_clearance.gd).
#
#   Godot --headless --path game --script res://tests/check_intro_sheet.gd

const SETTLE := 2.6
const MIN_FORMS := 2          # both occupied gurneys, before the reveal frees one
const MIN_VERTS := 2000       # a box has 24; v2's eleven boxes had 264
const MAX_CREASE_DEG := 82.0  # the largest angle between two normals of ONE triangle.
                              # ⚠️ This is a CORNER bound, not a curvature bound, and the
                              # difference is the whole reason it is 82 and not 30. A sheet
                              # legitimately folds: the hem turning over the edge of the
                              # mattress measures 69 degrees and the valley between the legs
                              # 71, and both are cloth doing what cloth does. What must NEVER
                              # appear is a right angle — a box corner is 90 and two
                              # coincident faces are 180. Measured worst on the shipped
                              # build: 71.5 degrees.
const MAX_FLAT_TRI_FRAC := 0.05  # …and the assertion that actually separates this build from
                              # the rejected one. A box-built prop is FLAT-SHADED: all three
                              # of a triangle's vertex normals are identical, for 100 % of
                              # its triangles. ⚠️ Measured ON THE MOUND ONLY (see MOUND_Y):
                              # the flat gutter of sheet either side of the body is genuinely
                              # flat, and counting it read 30 % on a perfectly smooth build.
const MOUND_Y := 0.060        # above this, the sheet is over the body, not lying on the bed
const MIN_LANDMARKS := 3      # head / chest / hips-or-feet: peaks separated by real troughs
const TROUGH_DROP := 0.030    # a dip only counts if the sheet drops 3 cm into it
const MIN_HEM := 0.070        # the sheet must hang BELOW the mattress line, i.e. drape
const FRAME_TOP_GAP := 0.100  # the mattress top is 0.10 above the gurney frame's top face

var _t := 0.0
var _done := false
var _fails: Array[String] = []
var _checks := 0
var _forms := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/intro_room.tscn")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail else ""))
	if not cond:
		_fails.append(label)


func _process(delta: float) -> bool:
	_t += delta
	if _done:
		return true
	if _t < SETTLE:
		return false
	_done = true

	var scene := current_scene
	for c in scene.get_children():
		if String(c.name).begins_with("SheetedForm_"):
			_check_form(c as Node3D)
			_forms += 1

	_ok("both occupied gurneys carry a covered body", _forms >= MIN_FORMS,
		"%d found, minimum %d" % [_forms, MIN_FORMS])

	print("")
	print("%d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		for f in _fails:
			print("  FAIL: " + f)
		print("RESULT: FAIL")
		quit(1)
	return true


func _check_form(form: Node3D) -> void:
	var tag := String(form.name)
	print("--- %s ---" % tag)
	var mi := form.get_node_or_null("SheetSurface") as MeshInstance3D
	_ok("%s has a sheet surface" % tag, mi != null and mi.mesh != null)
	if not mi or not mi.mesh:
		return

	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	# ⚠️ An UNINDEXED surface returns null here, and assigning null to a typed
	# PackedInt32Array throws — which aborts this function mid-run and takes the remaining
	# assertions with it, silently. That is exactly the Issue-45 shape (a throw inside a
	# test loop). Fall back to sequential indices so the checks below still run and the
	# weld assertion is what reports it.
	var idx := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		idx = arrays[Mesh.ARRAY_INDEX]
	else:
		for i in range(verts.size()):
			idx.append(i)

	_ok("%s: the sheet is a real surface, not a handful of slabs" % tag,
		verts.size() >= MIN_VERTS, "%d vertices, minimum %d" % [verts.size(), MIN_VERTS])
	_ok("%s: the surface carries per-vertex normals" % tag,
		norms.size() == verts.size(), "%d normals for %d vertices" % [norms.size(), verts.size()])
	if norms.size() != verts.size() or idx.size() < 3:
		return

	# --- 1. NO HARD CORNERS, AND IT IS SMOOTH-SHADED --------------------------------------
	# The v2 failure in two numbers. `worst` bounds CORNERS (see MAX_CREASE_DEG for why a
	# fold is not a corner); `flat` is the one that separates a curved surface from a
	# faceted one, because a box-built prop has every triangle flat-shaded.
	var worst := 0.0
	var tris := 0
	var flat := 0
	var mound_tris := 0
	for i in range(0, idx.size(), 3):
		var a: Vector3 = norms[idx[i]]
		var b: Vector3 = norms[idx[i + 1]]
		var c: Vector3 = norms[idx[i + 2]]
		var m: float = maxf(rad_to_deg(a.angle_to(b)),
			maxf(rad_to_deg(b.angle_to(c)), rad_to_deg(a.angle_to(c))))
		worst = maxf(worst, m)
		tris += 1
		if verts[idx[i]].y > MOUND_Y and verts[idx[i + 1]].y > MOUND_Y \
				and verts[idx[i + 2]].y > MOUND_Y:
			mound_tris += 1
			if m < 0.5:
				flat += 1
	_ok("%s: no right angles anywhere on the sheet" % tag, worst <= MAX_CREASE_DEG,
		"worst normal split within a triangle %.1f deg over %d triangles (limit %.0f, a box corner is 90)"
			% [worst, tris, MAX_CREASE_DEG])
	# ⚠️ Its own sample size again: if MOUND_Y ever selects nothing, this must not pass.
	_ok("%s: the mound is big enough to measure" % tag, mound_tris >= 500,
		"%d triangles above %.0f mm" % [mound_tris, MOUND_Y * 1000.0])
	var frac: float = float(flat) / float(maxi(mound_tris, 1))
	_ok("%s: the body's surface is smooth-shaded, not faceted" % tag,
		frac <= MAX_FLAT_TRI_FRAC,
		"%.1f%% of the %d mound triangles are flat-shaded (limit %.0f%%; a box-built prop is 100%%)"
			% [frac * 100.0, mound_tris, MAX_FLAT_TRI_FRAC * 100.0])

	# --- 1b. ONE WELDED SURFACE -----------------------------------------------------------
	# A prop built from boxes repeats every corner position once per face, each copy with a
	# different normal — that is what a hard edge IS. A welded heightfield has each position
	# exactly once, so normals are shared and continuity is structural rather than tuned.
	var seen := {}
	var dupes := 0
	for v in verts:
		var key := "%.4f_%.4f_%.4f" % [v.x, v.y, v.z]
		if seen.has(key):
			dupes += 1
		seen[key] = true
	_ok("%s: it is ONE welded surface, not a pile of separate faces" % tag, dupes == 0,
		"%d duplicated vertex positions" % dupes)

	# --- 2. IT HAS A BODY'S PROFILE -------------------------------------------------------
	# Slice along the long axis and take the highest point of each slice: the silhouette a
	# player sees from the side. A slab is monotone; a body has a head, a neck dip, a chest,
	# a waist dip and hips. Peaks only count when separated by a real trough.
	const SLICES := 40
	var zmin := 1e9
	var zmax := -1e9
	for v in verts:
		zmin = minf(zmin, v.z)
		zmax = maxf(zmax, v.z)
	var prof: Array[float] = []
	for i in range(SLICES):
		prof.append(-1e9)
	for v in verts:
		var s: int = clampi(int((v.z - zmin) / (zmax - zmin) * float(SLICES)), 0, SLICES - 1)
		prof[s] = maxf(prof[s], v.y)

	var landmarks := 0
	var last_peak := -1e9
	var trough := 1e9
	var rising := true
	for s in range(SLICES):
		var h: float = prof[s]
		if rising:
			if h > last_peak:
				last_peak = h
			elif last_peak - h > TROUGH_DROP:
				landmarks += 1
				rising = false
				trough = h
		else:
			trough = minf(trough, h)
			if h - trough > TROUGH_DROP:
				rising = true
				last_peak = h
	if rising and last_peak > trough + TROUGH_DROP:
		landmarks += 1
	_ok("%s: the silhouette has a body's landmarks, not one mound" % tag,
		landmarks >= MIN_LANDMARKS,
		"%d peaks separated by >= %.0f mm troughs (minimum %d)"
			% [landmarks, TROUGH_DROP * 1000.0, MIN_LANDMARKS])

	var peak := -1e9
	var floor_y := 1e9
	for v in verts:
		peak = maxf(peak, v.y)
		floor_y = minf(floor_y, v.y)
	_ok("%s: the body stands proud of the bed" % tag, peak > 0.18,
		"highest point %.3f m above the mattress" % peak)

	# --- 3. IT DRAPES ---------------------------------------------------------------------
	_ok("%s: the sheet hangs over the edge of the mattress" % tag, floor_y < -MIN_HEM,
		"lowest hem point %.3f m (must be below -%.3f)" % [floor_y, MIN_HEM])

	# --- 4. …AND THE HEM DOES NOT CUT THROUGH THE GURNEY FRAME ----------------------------
	# Measured against the frame that was actually BUILT, not against the constants that
	# produced it. The frame's top face is FRAME_TOP_GAP below the form's origin.
	# ⚠️ In WORLD space, then into the frame's own space. The form carries a small yaw, so
	# comparing its local x/z against the frame's half-extents would be quietly wrong by a
	# few centimetres — which is the same size as the clearance being asserted.
	var frame: CSGBox3D = null
	var best := 1e9
	for c in form.get_parent().get_children():
		if c is CSGBox3D and String(c.name).begins_with("GurneyFrame"):
			var d: float = (c as Node3D).global_position.distance_to(form.global_position)
			if d < best:
				best = d
				frame = c as CSGBox3D
	_ok("%s: found the gurney frame to measure against" % tag,
		frame != null and best < 1.2, "nearest frame %.2f m away" % best)
	if frame and best < 1.2:
		var half: Vector3 = frame.size * 0.5
		var to_frame := frame.global_transform.affine_inverse() * form.global_transform
		var inside := 0
		var deepest := 0.0
		for v in verts:
			var f: Vector3 = to_frame * v
			if absf(f.x) <= half.x and absf(f.z) <= half.z and f.y < half.y:
				inside += 1
				deepest = minf(deepest, f.y - half.y)
		_ok("%s: no part of the hem is buried in the frame" % tag, inside == 0,
			"%d vertices below the frame's top face (deepest %.3f m)" % [inside, deepest])
