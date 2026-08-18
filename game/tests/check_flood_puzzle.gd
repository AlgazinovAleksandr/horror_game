extends SceneTree

# THE FLOOD'S PUZZLE — six fragments, one plate, and an exit that does not exist until the
# plate is whole (backlog 04 B-R1, the user's own design, 2026-08-17).
#
#   Godot --headless --path game --script res://tests/check_flood_puzzle.gd
#
# ⚠️ THIS TEST EXISTS BECAUSE THE CHANGE MADE THE ZONE GATED. Before it, the Flood could be
# cleared by walking into the Sump with the torch off; now six objects must be found in a
# near-black 28 m wing first. That is exactly the shape of an unwinnable level, and this
# project has shipped one — so what is asserted here is not "the feature is present" but:
#
#   1. THE ZONE IS COMPLETABLE FROM A COLD START, through `player.ai_interact()` and the
#      real raycast, with the seam entered by MOVING THE PLAYER INTO IT. Nothing here emits
#      `cleared`. (`walk_backrooms.gd` once passed for weeks on a level that could not be
#      finished, because it fired the signal.)
#   2. THE SAFETY NET HOLDS. An object whose fragment is still in it KNOCKS, indefinitely,
#      even after its lid has been hauled open — that intermittent call is the only thing
#      standing between "a search" and "stuck". Measured as rising edges on the emitter.
#   3. THE ASSEMBLY POINT ANNOUNCES ITSELF. "Assemble it in the middle of the level" is a
#      second thing to hunt for with no tell of its own unless one is built. Three channels
#      are measured: the far cue is compared against the water bed it must be heard through
#      IN EVERY ROOM, from the .wav files on disk; the table is inside the Basin lamp's
#      range; the written instruction exists and is not self-lit.
#   4. IT COSTS NOTHING. Panic is sampled every frame across the whole run; no step larger
#      than the zone's own 0.3/s drip may appear anywhere in it.
#
# ⚠️ THE `cleared` SIGNAL IS RE-POINTED, NOT EMITTED. `backrooms.gd` wires it to
# `GameState.advance_level()`, which changes scene out from under the probe mid-assertion.
# The connections are disconnected and replaced with a counter, so the SEAM's own Area3D
# still has to fire it through real physics — which is the half that matters. The wiring
# from `cleared` to the next level is asserted separately, in `walk_backrooms.gd`.

const SCENE := "res://scenes/backrooms.tscn"
const ORIGIN := Vector3(-200, 0, 0)
const REACH_DIST := 1.6
const OBLIQUE_DEG := 25.0
# The haul tween is 0.8 s; the fragment does not exist until it finishes.
const LID_WATCH := 1.3
# ⚠️ 24 s, AND THE COUNTER IS RESET WHEN THE WATCH OPENS. The knock cycle is 5-11 s, so
# two knocks inside 24 s is guaranteed rather than likely — no seed can make this flaky.
# The reset matters as much: without it the control run (gate back on `is_searched`) still
# scored 1, from a knock that happened BEFORE the object was hauled open, and a control
# that cannot reach zero is a control that cannot separate.
const NET_WATCH := 24.0

var _t := 0.0
var _stage := 0
var _stage_at := 0.0
var _scene: Node = null
var _player: Node3D = null
var _zone: Node = null
var _plate: Node = null
var _seam: Node = null
var _items: Array = []
var _rooms: Dictionary = {}

var _cleared := 0
var _idx := 0

var _net_item: Node = null
var _net_knocks := 0
var _net_was_playing := false
var _net_samples := 0
var _control_item: Node = null
var _control_knocks := 0
var _control_was_playing := false

var _panic_last := 0.0
var _panic_step := 0.0
var _panic_samples := 0
var _panic_start := 0.0

var _checks := 0
var _fails: Array[String] = []


func _initialize() -> void:
	change_scene_to_file(SCENE)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("  OK    ", label, ("  " + detail) if detail else "")
	else:
		print("  FAIL  ", label, ("  " + detail) if detail else "")
		_fails.append(label)


func _advance(n: int) -> void:
	_stage = n
	_stage_at = _t


func _report() -> bool:
	print("--------------------------------------------------")
	print("  %d checks, %d failed" % [_checks, _fails.size()])
	for f in _fails:
		print("    - ", f)
	print("RESULT: ", "FAIL" if _fails.size() > 0 else "PASS")
	print("--------------------------------------------------")
	quit(1 if _fails.size() > 0 else 0)
	return true


# ------------------------------------------------------------------------ main loop

func _process(delta: float) -> bool:
	_t += delta

	# ⚠️ A DEAD SCENE MUST FAIL LOUDLY, not skip the rest (Issue 45): a screamer reloads the
	# level and every later get_node_or_null then raises, aborting the calling function.
	if _stage > 0 and (not is_instance_valid(_scene) or not is_instance_valid(_player)):
		_ok("the level survived the run", false, "the scene reloaded at t=%.1f s" % _t)
		return _report()

	if _stage > 0:
		# This probe stands still on purpose and the maze charges +3/s for that.
		_player.call("set_smiler_active", true)
		_sample_panic()
		_sample_net()
		# Dismiss every page on the frame it opens: NoteUI pauses the tree, which stops
		# every Tween — including the haul tweens this probe is waiting on.
		var ui := root.get_node_or_null("/root/NoteUI")
		if ui != null and bool(ui.get("is_open")):
			ui.call("_close")

	match _stage:
		0:
			if _t < 1.0:
				return false
			return _setup()
		1:
			return _before_anything()
		2:
			if _t - _stage_at < LID_WATCH:
				return false
			return _safety_net_open()
		3:
			if _t - _stage_at < NET_WATCH:
				return false
			return _safety_net_measure()
		4:
			return _collect_step()
		5:
			if _t - _stage_at < LID_WATCH:
				return false
			return _collect_step()
		6:
			return _at_the_plate()
		7:
			if _t - _stage_at < 2.6:
				return false
			return _the_exit()

	if _t > 180.0:
		_ok("the probe finished inside its budget", false, "timed out at stage %d" % _stage)
		return _report()
	return false


# --------------------------------------------------------------------------- stage 0

func _setup() -> bool:
	_scene = current_scene
	_player = _scene.get_node_or_null("Player") as Node3D
	_ok("the Player exists", _player != null)
	if _player == null:
		return _report()
	_player.call("set_smiler_active", true)
	_panic_last = float(_player.call("get_panic_ratio"))
	_panic_start = _panic_last

	_zone = _scene.get_node_or_null("ZoneFlood")
	_ok("zone 3 (the Flood) is built", _zone != null)
	if _zone == null:
		return _report()

	# Disarm the fatal furniture: this probe teleports between rooms, and a teleport away
	# from an armed HOLD apparition reads as FLEEING — a screamer and a scene reload.
	var disarmed := 0
	var appar_script: GDScript = load("res://scripts/apparition.gd")
	var trap_script: GDScript = load("res://scripts/beartrap.gd")
	for n in _all(_zone, []):
		if n.get_script() == appar_script or n.get_script() == trap_script \
				or String(n.name).ends_with("Event"):
			n.queue_free()
			disarmed += 1
	_ok("the Flood's fatal props were disarmed for this probe", disarmed >= 4,
		"%d nodes freed" % disarmed)

	_rooms = {}
	for r in _zone.get("ROOMS"):
		_rooms[String(r["name"])] = {"pos": r["pos"], "size": r["size"]}
	_ok("the room table was read from the level script", _rooms.size() == 8,
		"%d rooms" % _rooms.size())

	var item_script: GDScript = load("res://scripts/sunken_item.gd")
	for n in _all(_zone, []):
		if n.get_script() == item_script:
			_items.append(n)
	_ok("six drowned objects, each holding a fragment", _items.size() == 6,
		"%d found" % _items.size())
	if _items.size() != 6:
		return _report()

	_plate = _zone.get_node_or_null("FloodPlate")
	_seam = _zone.get_node_or_null("FloodSeam")
	_ok("the plate table exists", _plate != null)
	_ok("the real seam exists", _seam != null)
	if _plate == null or _seam == null:
		return _report()

	# ⚠️ Re-point `cleared` (see the header): the seam's own physics still has to fire it.
	for c in _zone.cleared.get_connections():
		_zone.cleared.disconnect(c["callable"])
	_zone.cleared.connect(func() -> void: _cleared += 1)

	# Wake the wing so the knock timers run (the level does this from the footprint test).
	_player.global_position = _zone.get("spawn_point")
	_player.call("force_update_transform")
	_advance(1)
	return false


# --------------------------------------------------------------------------- stage 1

func _before_anything() -> bool:
	print("\n--- before anything: the exit does not exist, and the plate is silent ---")
	_ok("the real seam is DORMANT before the plate is assembled",
		not bool(_seam.call("is_armed")))
	# ...and dormant means untouchable, not merely unlit. Ask the trigger, not the flag.
	var trig := _seam.get_node_or_null("GlitchTrigger") as Area3D
	_ok("...and its walk-into trigger is not monitoring",
		trig != null and not trig.monitoring)
	_ok("...and it is not visible even with the torch off", not (_seam as Node3D).visible)

	# The tell is armed by the first FRAGMENT, not by entering the zone: a permanent drone
	# would bury the knocks that are how the six objects are found.
	_ok("the plate's tell is silent before the first fragment",
		not bool(_plate.call("is_calling")))
	_ok("the plate is inert while you are carrying nothing",
		not bool(_plate.call("can_interact")))

	_announcement_channels()
	_zero_panic_props()
	_restore_is_consistent()

	# --- THE SAFETY NET: haul one open and leave the fragment in it ---
	_net_item = _items[0]
	_haul(_net_item)
	_ok("an object can be hauled open by pressing E", bool(_net_item.get("is_searched")))
	# A control that must stay silent: an object taken all the way must never knock again.
	_control_item = _items[1]
	_haul(_control_item)
	_advance(2)
	return false


# --------------------------------------------------------------------------- stage 2

func _safety_net_open() -> bool:
	_take(_control_item)
	_ok("the control object is emptied", bool(_control_item.get("is_taken")))
	_ok("the safety-net object is open but NOT emptied",
		bool(_net_item.get("is_searched")) and not bool(_net_item.get("is_taken")))
	# Only knocks from HERE on count: see NET_WATCH.
	_net_knocks = 0
	_control_knocks = 0
	# Stand between the two so both emitters are in range of nothing in particular; the
	# sampling reads the AudioStreamPlayer3D directly, so position is irrelevant to it.
	_advance(3)
	return false


func _safety_net_measure() -> bool:
	print("\n--- the safety net: an outstanding fragment never stops calling ---")
	_ok("the knock watch sampled enough frames", _net_samples > 200,
		"%d frames over %.0f s" % [_net_samples, NET_WATCH])
	_ok("an OPENED object whose fragment is still in it keeps knocking",
		_net_knocks >= 2,
		"%d knocks in %.0f s (5-11 s cycle)" % [_net_knocks, NET_WATCH])
	_ok("...while an EMPTIED one is silent for ever", _control_knocks == 0,
		"%d knocks from the emptied control" % _control_knocks)
	_advance(4)
	return false


# --------------------------------------------------------------------------- stages 4/5
#
# Collect all six the way a player does: haul, wait for the lid, take. `_idx` walks the
# list; stage 4 hauls and stage 5 takes, so every take is at least LID_WATCH after its own
# haul rather than in the same frame (a same-frame second press would pass while measuring
# a fragment that does not exist yet — the item forwards the press either way).

func _collect_step() -> bool:
	if _stage == 4:
		if _idx >= _items.size():
			return _collected()
		if not bool(_items[_idx].get("is_searched")):
			_haul(_items[_idx])
		_advance(5)
		return false
	# stage 5 — take it
	if not bool(_items[_idx].get("is_taken")):
		_take(_items[_idx])
	if not bool(_items[_idx].get("is_taken")):
		_ok("fragment %d was taken by pressing E" % _idx, false,
			"%s still holds it" % _items[_idx].name)
	_idx += 1
	_advance(4)
	return false


func _collected() -> bool:
	print("\n--- six fragments, taken through the real interact path ---")
	var taken := 0
	for it in _items:
		if bool(it.get("is_taken")):
			taken += 1
	_ok("all six fragments were taken by pressing E", taken == 6, "%d of 6" % taken)
	_ok("the player is carrying six", int(_zone.call("pieces_held")) == 6,
		"%d in hand" % int(_zone.call("pieces_held")))
	_ok("the plate is calling now that there is something to carry to it",
		bool(_plate.call("is_calling")))
	_ok("the exit STILL does not exist with the fragments merely in hand",
		not bool(_seam.call("is_armed")))
	_ok("the objective names the rule, not the room",
		not String(_zone.call("objective_text")).to_lower().contains("basin"),
		"\"%s\"" % String(_zone.call("objective_text")))
	# ⚠️ AND IT NAMES NO TASK EITHER (2026-08-18, B-S3). Playtest capture 005: *"The message
	# should not be that obvious. It should be like 'Solve the mystery' ... do not write that
	# hint."* The line was `Six pieces are sunk in this wing (n/6)`, which stated the
	# quantity, the verb and the score. The counter is safe to remove BECAUSE THE KNOCKS ARE
	# THE COUNTER — an object still knocking is a piece outstanding — and that channel is
	# asserted separately, below and in `check_flood_drowned.gd`.
	var obj: String = String(_zone.call("objective_text")).to_lower()
	var leaks: Array[String] = []
	for word in ["six", "6", "piece", "collect", "set them", "sunk", "/"]:
		if obj.contains(word):
			leaks.append(word)
	_ok("...and it is a mystery, not an instruction: no count, no verb, no quantity",
		leaks.is_empty(), "\"%s\" leaks %s" % [obj, str(leaks)])
	_advance(6)
	return false


# --------------------------------------------------------------------------- stage 6

func _at_the_plate() -> bool:
	print("\n--- the plate ---")
	# The shipping prompt must find it, square on and 25 degrees either side.
	var seen_ok := 0
	for off in [0.0, OBLIQUE_DEG, -OBLIQUE_DEG]:
		var hit := _reads(_plate, 1.7, off)
		if hit == _plate or (hit != null and _plate.is_ancestor_of(hit)):
			seen_ok += 1
	_ok("the plate answers the shipping prompt square on and 25° either side",
		seen_ok == 3, "%d of 3 poses" % seen_ok)

	_reads(_plate, 1.7, 0.0)
	_player.call("ai_interact")
	_ok("pressing E sets every fragment you are carrying into the frame",
		int(_plate.call("pieces_set")) == 6, "%d of 6" % int(_plate.call("pieces_set")))
	_ok("...and your hands are empty afterwards", int(_zone.call("pieces_held")) == 0)
	_advance(7)
	return false


# --------------------------------------------------------------------------- stage 7

func _the_exit() -> bool:
	print("\n--- the exit, and it is still found in the dark ---")
	_ok("assembling the plate arms the real seam", bool(_seam.call("is_armed")))
	var trig := _seam.get_node_or_null("GlitchTrigger") as Area3D
	_ok("...and its walk-into trigger is monitoring again",
		trig != null and trig.monitoring)
	_ok("the plate stops calling once it is whole", not bool(_plate.call("is_calling")))
	_ok("the plate is inert once it is whole", not bool(_plate.call("can_interact")))

	# THE DARKNESS RULE IS UNCHANGED and is still the last step.
	var flash: Node3D = _player.get_node_or_null("Camera3D/Flashlight")
	if flash != null:
		flash.visible = true
		_zone.call("_process", 0.016)
		_ok("armed or not, the seam stays hidden while the torch is ON",
			not (_seam as Node3D).visible)
		flash.visible = false
		_zone.call("_process", 0.016)
		_ok("...and shows with it OFF", (_seam as Node3D).visible)

	# WALK INTO IT. The Area3D has to see a real body enter — nothing here emits `cleared`.
	var seam3: Node3D = _seam
	var stand: Vector3 = seam3.global_position + Vector3(0, -1.25, -1.4)
	_player.global_position = stand
	_player.call("force_update_transform")
	_advance(8)
	# Physics needs a few frames to deliver body_entered; _sample_net() finishes the run.
	return false


func _sample_net() -> void:
	if _net_item != null and is_instance_valid(_net_item):
		var k := _net_item.get_node_or_null("Knock") as AudioStreamPlayer3D
		if k != null:
			var now: bool = k.playing
			if now and not _net_was_playing:
				_net_knocks += 1
			_net_was_playing = now
			if _stage == 3:
				_net_samples += 1
	if _control_item != null and is_instance_valid(_control_item):
		var c := _control_item.get_node_or_null("Knock") as AudioStreamPlayer3D
		if c != null:
			var now2: bool = c.playing
			if now2 and not _control_was_playing and _stage >= 3:
				_control_knocks += 1
			_control_was_playing = now2
	# Stage 8 is the walk-into-the-seam settle: give physics a few frames, then finish.
	if _stage == 8 and _t - _stage_at > 0.6:
		_stage = 9
		_ok("walking into the armed seam clears the zone (real Area3D, not an emit)",
			_cleared == 1, "cleared fired %d time(s)" % _cleared)
		_ok("nothing in the whole puzzle added panic", _panic_step < 0.02,
			"largest single-frame panic step %.4f of the bar (the zone's own 0.3/s drip "
			% _panic_step + "produces ~0.0001)")
		_ok("the panic audit sampled the whole run", _panic_samples > 500,
			"%d frames" % _panic_samples)
		print("      panic across the whole probe: %.1f%% -> %.1f%% of PANIC_MAX over %.0f s"
			% [_panic_start * 100.0, float(_player.call("get_panic_ratio")) * 100.0, _t])
		_report()


# --------------------------------------------------- the assembly point announces itself

func _announcement_channels() -> void:
	print("\n--- the assembly point announces itself ---")
	var far := _plate.get_node_or_null("PlateFar") as AudioStreamPlayer3D
	var near := _plate.get_node_or_null("PlateNear") as AudioStreamPlayer3D
	_ok("it has a two-layer positional tell", far != null and near != null)
	if far == null or near == null:
		return
	_ok("the far cue carries further than the near confirm",
		far.unit_size > near.unit_size,
		"unit_size %.0f vs %.0f" % [far.unit_size, near.unit_size])
	# ⚠️ MASTER, never the level's own bus: a SilenceZone ducks "Backrooms", and a tell
	# routed through the bus a silence pocket ducks is a tell that mutes itself.
	_ok("both layers are on Master, not the duckable level bus",
		far.bus == "Master" and near.bus == "Master",
		"%s / %s" % [far.bus, near.bus])
	_ok("both loops restart themselves (every .wav.import here is loop_mode=0)",
		far.finished.is_connected(far.play) and near.finished.is_connected(near.play))

	# --- the measurement that matters: can it be heard over the water, in every room? ---
	var hum := _rms_dbfs(_stream_path(far))
	var bed_rms := -999.0
	var beds: Array = []
	for c in _zone.get_children():
		if c is AudioStreamPlayer3D and String(c.name).begins_with("WaterBed_"):
			beds.append(c)
			bed_rms = _rms_dbfs(_stream_path(c))
	_ok("the water beds and the plate's far cue both have real sample data",
		hum > -900.0 and bed_rms > -900.0 and beds.size() == 8,
		"hum %.1f dBFS, bed %.1f dBFS, %d beds" % [hum, bed_rms, beds.size()])
	if hum < -900.0 or bed_rms < -900.0:
		return
	var worst := 999.0
	var worst_room := ""
	var rooms_checked := 0
	for room in _rooms.keys():
		var p: Vector2 = _rooms[room]["pos"]
		var at: Vector3 = ORIGIN + Vector3(p.x, 1.6, p.y)
		var cue: float = hum + _level_at(far, at)
		var bed := -999.0
		for b in beds:
			bed = maxf(bed, bed_rms + _level_at(b, at))
		rooms_checked += 1
		var margin: float = cue - bed
		if margin < worst:
			worst = margin
			worst_room = room
		print("      %-8s cue %6.1f dBFS   water %6.1f dBFS   margin %+5.1f dB"
			% [room, cue, bed, margin])
	_ok("the far cue was measured in every room", rooms_checked == 8,
		"%d rooms" % rooms_checked)
	# A bearing you cannot hear over the room you are standing in is not a bearing.
	_ok("the far cue clears the water bed everywhere in the wing", worst >= 3.0,
		"worst margin %+.1f dB, in the %s" % [worst, worst_room])

	# ⚠️ AND IT IS BRACKETED FROM ABOVE. A continuous loop that out-shouts the one-shots
	# buries the `flood_knock` that is how the six objects are found — the mistake this
	# level's HUM_VOLUME_DB was retuned for. Compare against the `flood_haul` an object
	# makes when it is opened, measured the same way.
	var haul_near := -999.0
	for it in _items:
		var k := it.get_node_or_null("Knock") as AudioStreamPlayer3D
		if k != null:
			# The knock is the quieter of the two item sounds and the one that must survive.
			haul_near = _rms_dbfs(_stream_path(k)) + minf(k.max_db, k.volume_db + 20.0)
			break
	var at_plate: float = hum + _level_at(far, (_plate as Node3D).global_position
		+ Vector3(0, 1.6, -1.6))
	_ok("...and stays under the knock a player is listening for", at_plate < haul_near,
		"cue at the table %.1f dBFS vs a near knock at %.1f dBFS" % [at_plate, haul_near])

	# ⚠️ A BEARING NEEDS A GRADIENT, and the gradient comes from unit_size, not volume_db:
	# Godot clamps volume_db + attenuation to max_db, so an emitter whose unit_size covers
	# the whole wing is at exactly max_db everywhere in it. At unit 18 this cue measured
	# FLAT TO 0.4 dB across 8 rooms and still passed every assertion above.
	var basin: Vector2 = _rooms["Basin"]["pos"]
	var near_level: float = hum + _level_at(far, ORIGIN + Vector3(basin.x, 1.6, basin.y))
	var far_level := 999.0
	for room in _rooms.keys():
		var q: Vector2 = _rooms[room]["pos"]
		far_level = minf(far_level, hum + _level_at(far, ORIGIN + Vector3(q.x, 1.6, q.y)))
	_ok("the far cue falls off across the wing, so it is a bearing and not a wash",
		near_level - far_level >= 3.0,
		"%.1f dBFS in the Basin, %.1f dBFS at the far end (%+.1f dB)"
		% [near_level, far_level, near_level - far_level])

	# ⚠️ TWO LAYERS, NOT TWO COPIES. The near confirm exists to say "you are here" and must
	# be gone by the far end of the wing, or the pair is one cue played twice — the exact
	# fault `backrooms_zone2.gd`'s header records about `sprawl_wall_hum`.
	var ring := _rms_dbfs(_stream_path(near))
	var ring_far := 999.0
	for room in _rooms.keys():
		var r: Vector2 = _rooms[room]["pos"]
		ring_far = minf(ring_far, ring + _level_at(near, ORIGIN + Vector3(r.x, 1.6, r.y)))
	_ok("the near confirm dies away before the far end, so it means \"you are here\"",
		ring_far < far_level - 6.0,
		"near confirm %.1f dBFS vs far cue %.1f dBFS at the far end" % [ring_far, far_level])

	# --- and it is in the only lit room, which is the second channel ---
	var lamp: OmniLight3D = null
	for c in _zone.get_children():
		if c is OmniLight3D and (c as OmniLight3D).omni_range > 5.0:
			lamp = c
			break
	_ok("the Flood has exactly one room lamp to stand under", lamp != null)
	if lamp != null:
		var d := (lamp as Node3D).global_position.distance_to((_plate as Node3D).global_position)
		_ok("the plate stands inside that lamp's range", d < lamp.omni_range,
			"%.1f m from a %.1f m lamp" % [d, lamp.omni_range])

	# --- and it says what it is for, in writing, without lighting itself ---
	var lbl: Label3D = _plate.get_node_or_null("PlateScrawl") as Label3D
	_ok("the plate carries a written instruction", lbl != null and lbl.text.length() > 8,
		"\"%s\"" % ("" if lbl == null else lbl.text.replace("\n", " / ")))
	if lbl != null:
		# Label3D is unshaded: a pale modulate IS a self-lit object (§5.2(8)). The board
		# behind it takes the lamp; the lettering takes its contrast from the board.
		var v: float = maxf(lbl.modulate.r, maxf(lbl.modulate.g, lbl.modulate.b))
		_ok("...in dark lettering, not as a self-lit label", v < 0.25,
			"brightest channel %.2f" % v)


# ⚠️ THE BACK-DOOR RETURN IS THE OTHER WAY TO MANUFACTURE AN UNWINNABLE WING, and it does not
# need a bug in the puzzle to do it: the objects are silenced by being emptied, so a snapshot
# that remembered THEM and not the plate would restore a wing with nothing knocking and an empty
# frame. Built here on a SECOND, throwaway zone (the live one is mid-run and its state is the
# subject of every other assertion), restored to "all six emptied, six set, none in hand", and
# required to come back armed. Freed immediately — it is 8 rooms of CSG.
func _restore_is_consistent() -> void:
	print("\n--- a back-door return restores the puzzle, not half of it ---")
	var z = load("res://scripts/backrooms_zone3.gd").new()
	z.name = "RestoreProbeZone"
	_scene.add_child(z)
	z.call("build", Vector3(-600, 0, 0), _player)
	var names: Array = []
	for n in _all(z, []):
		if n.get_script() == load("res://scripts/sunken_item.gd"):
			names.append(n.name)
	_ok("the restore probe built its own six objects", names.size() == 6,
		"%d" % names.size())
	z.call("restore_searched", names, 6, 0)
	var seam = z.get_node_or_null("FloodSeam")
	_ok("restoring six-set arms the seam", seam != null and bool(seam.call("is_armed")))
	_ok("...and the plate comes back whole",
		int(z.call("pieces_set")) == 6 and bool(z.call("plate_done")))
	_ok("...and the objective is the final line, not a counter",
		String(z.call("objective_text")).contains("does not show itself"),
		"\"%s\"" % String(z.call("objective_text")))

	# ...and the half-way case: three emptied, two set, one still in hand.
	var z2 = load("res://scripts/backrooms_zone3.gd").new()
	z2.name = "RestoreProbeZone2"
	_scene.add_child(z2)
	z2.call("build", Vector3(-700, 0, 0), _player)
	var names2: Array = []
	for n in _all(z2, []):
		if n.get_script() == load("res://scripts/sunken_item.gd"):
			names2.append(n.name)
	z2.call("restore_searched", names2.slice(0, 3), 2, 1)
	var seam2 = z2.get_node_or_null("FloodSeam")
	_ok("a partial restore leaves the seam dormant",
		seam2 != null and not bool(seam2.call("is_armed")))
	_ok("...with the fragments split correctly between frame and hand",
		int(z2.call("pieces_set")) == 2 and int(z2.call("pieces_held")) == 1,
		"%d set, %d held" % [int(z2.call("pieces_set")), int(z2.call("pieces_held"))])
	# ⚠️ AND THE THREE OBJECTS IT DID NOT RESTORE MUST STILL BE ABLE TO CALL. That is the
	# safety net surviving a back-door return, which is the case it is least likely to be
	# tested in and the one where being stuck is least recoverable.
	var still_callable := 0
	for n in _all(z2, []):
		if n.get_script() == load("res://scripts/sunken_item.gd") \
				and not bool(n.get("is_taken")):
			still_callable += 1
	_ok("the three outstanding objects can still knock after a restore",
		still_callable == 3, "%d of 3" % still_callable)
	z.queue_free()
	z2.queue_free()


# Nothing in this feature may carry a panic term, a gaze term or a fail state.
func _zero_panic_props() -> void:
	var scary: GDScript = load("res://scripts/scary_object.gd")
	var bad: Array[String] = []
	for n in _all(_plate, []):
		if n.get_script() == scary or n is Area3D:
			bad.append(String(n.name))
	for it in _items:
		for n in _all(it, []):
			if n.get_script() == scary or n is Area3D:
				bad.append(String(n.name))
	_ok("no ScaryObject and no Area3D anywhere in the plate or the six objects",
		bad.is_empty(), "found: %s" % ", ".join(bad))


# ------------------------------------------------------------------------- helpers

func _haul(it: Node3D) -> void:
	_reads(it, REACH_DIST, 0.0)
	_player.call("ai_interact")


func _take(it: Node3D) -> void:
	var frag := it.get_node_or_null("Fragment") as Node3D
	_reads(frag if frag != null and frag.visible else it, REACH_DIST, 0.0)
	_player.call("ai_interact")


# Stand `dist` from the prop's ART, `off_axis` degrees round, and ask the SHIPPING prompt
# path what it sees. Aims at the MESH, never at the collider.
func _reads(prop: Node3D, dist: float, off_axis: float) -> Node:
	var aabb := _world_aabb(prop)
	var aim: Vector3 = aabb.get_center()
	var radius: float = maxf(aabb.size.x, aabb.size.z) * 0.5
	var room := _room_of(prop.global_position)
	var toward := Vector3(0, 0, 1)
	if room != "":
		var p: Vector2 = _rooms[room]["pos"]
		toward = (ORIGIN + Vector3(p.x, 0, p.y)) - prop.global_position
		toward.y = 0.0
		if toward.length() < 0.2:
			toward = Vector3(0, 0, 1)
	toward = toward.normalized().rotated(Vector3.UP, deg_to_rad(off_axis))
	var stand: Vector3 = aim + toward * (dist + radius)
	_player.global_position = Vector3(stand.x, ORIGIN.y + 0.1, stand.z)
	_player.call("force_update_transform")
	_player.call("ai_look_at", aim)
	var cam := _player.get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.force_update_transform()
	return _player.call("ai_interact_target")


func _sample_panic() -> void:
	var now := float(_player.call("get_panic_ratio"))
	_panic_step = maxf(_panic_step, absf(now - _panic_last))
	_panic_last = now
	_panic_samples += 1


func _room_of(world: Vector3) -> String:
	var local: Vector3 = world - ORIGIN
	for room in _rooms.keys():
		var p: Vector2 = _rooms[room]["pos"]
		var sz: Vector2 = _rooms[room]["size"]
		if absf(local.x - p.x) <= sz.x / 2.0 and absf(local.z - p.y) <= sz.y / 2.0:
			return String(room)
	return ""


# Godot's inverse-distance attenuation, in dB, capped at the player's own max_db.
func _level_at(a: AudioStreamPlayer3D, listener: Vector3) -> float:
	var d: float = maxf(0.1, a.global_position.distance_to(listener))
	return minf(a.max_db, a.volume_db + 20.0 * (log(a.unit_size / d) / log(10.0)))


func _stream_path(a: AudioStreamPlayer3D) -> String:
	return "" if a.stream == null else String(a.stream.resource_path)


# RMS of the SOURCE .wav on disk, in dBFS — it must read the FILE, because this project
# imports .wav as QOA and the in-memory bytes are not PCM.
func _rms_dbfs(res_path: String) -> float:
	if res_path == "":
		return -999.0
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return -999.0
	var bytes: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return -999.0
	var pos := 12
	var data_at := -1
	var data_len := 0
	while pos + 8 <= bytes.size():
		var id: String = bytes.slice(pos, pos + 4).get_string_from_ascii()
		var sz: int = bytes.decode_u32(pos + 4)
		if id == "data":
			data_at = pos + 8
			data_len = sz
			break
		pos += 8 + sz + (sz & 1)
	if data_at < 0:
		return -999.0
	var n: int = mini(data_len, bytes.size() - data_at) / 2
	if n <= 0:
		return -999.0
	var acc := 0.0
	var step: int = maxi(1, n / 40000)
	var used := 0
	for i in range(0, n, step):
		var v: float = float(bytes.decode_s16(data_at + i * 2)) / 32768.0
		acc += v * v
		used += 1
	if used == 0:
		return -999.0
	return 20.0 * (log(sqrt(acc / float(used)) + 1e-12) / log(10.0))


func _world_aabb(root_node: Node) -> AABB:
	var out := AABB()
	var first := true
	for n in _all(root_node, []):
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as Node3D).visible:
			var mi := n as MeshInstance3D
			var box := mi.global_transform * mi.mesh.get_aabb()
			if first:
				out = box
				first = false
			else:
				out = out.merge(box)
	if first and root_node is Node3D:
		out = AABB((root_node as Node3D).global_position - Vector3(0.2, 0.2, 0.2),
			Vector3(0.4, 0.4, 0.4))
	return out


func _all(n: Node, acc: Array) -> Array:
	for c in n.get_children():
		acc.append(c)
		_all(c, acc)
	return acc
