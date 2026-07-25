extends StaticBody3D
class_name LabLocker

# The Lab's Records breaker used to advertise itself with a spark tell — a crackle
# and a light flash every 8-12 s (BUG_FIX.md 4.1). Playtest: that doesn't hide it,
# it points at it. "Search the room" collapsed into "walk toward the crackle".
#
# This is the replacement. A steel locker stands flush against the breaker, so the
# panel is not merely hard to see, it is physically unreachable — the interaction
# ray hits this collider first. Moving it is gated twice:
#
#   1. `unlocked` — set by the level when the player reads the maintenance note in
#      the Observation room, on the far side of the lab. Before that, interacting
#      only prints a refusal. The gate is deliberately HARD and there is deliberately
#      NO pointer toward the note (confirmed with the user): a player who never
#      searches Observation does not finish the level.
#   2. The push itself — a tug-of-war bar fed by mashing TAB and drained by time.
#
# The push does NOT pause the tree, unlike maze_chase_ui.gd / combination_lock.gd.
# The player is frozen facing a wall while the Lab's blackouts, pipe groans and
# ambience keep running behind them; that is the whole point. beartrap.gd is the
# closer relative — a real-time QTE inside the running game, polling Input in
# _process rather than consuming InputEvents.

signal moved   # the locker has finished sliding; the breaker is now reachable

# Set true by the level when the Observation maintenance note is read.
@export var unlocked: bool = false

const TEX := "res://assets/textures/level_1_lab/lab_locker.png"

const SIZE := Vector3(1.0, 2.0, 0.5)
const ART_INSET := 0.04          # art quad is this much smaller than the front face
const ART_PROUD := 0.01          # and this far proud of it

const PUSH_PER_PRESS := 0.10     # bar gain per SPACE press
const PUSH_DECAY := 0.18         # bar loss per second
const PUSH_PANIC := 1.2          # panic per second while braced against it
const PUSH_START := 0.15         # bar starts here, so one missed beat isn't fatal

# ⚠️ It takes THREE full bars, not one (playtest 2026-07-26: "probably we need to
# require more effort from the player — currently too simple"). Filling the bar once
# lurches the locker SHOVE_DIST and resets it; three lurches clear the panel.
#
# Staged rather than one longer bar on purpose: the note the player just read says it
# "moves in fits", and a single 10-second bar with no intermediate feedback reads as
# broken rather than as heavy. Each lurch is visible, audible progress. The per-press
# and decay rates are UNCHANGED — the difficulty is length, not a steeper curve, so
# the mash rate that works still works.
const SHOVES_NEEDED := 3
const SHOVE_DIST := 0.45         # metres per lurch, along the locker's local +X
const SHOVE_TIME := 0.35         # the lurch itself; input is ignored during it
const SLIDE_TIME := 1.1
const BRACE_DIST := 0.9          # how far in front of the face the player is planted
const BRACE_TIME := 0.25

# ⚠️ Load-bearing. The push is STARTED by an `interact` press, and _process polls
# `Input.is_action_just_pressed("interact")` to cancel — without this the very press
# that opens the QTE also closes it on frame one. note_ui.gd's `_block_close` guard
# exists for exactly this collision.
const ARM_DELAY := 0.25

var _done: bool = false
var _pushing: bool = false
var _lurching: bool = false      # mid-lurch; input is ignored so a press can't be eaten
var _effort: float = 0.0
var _shoves: int = 0
var _armed: float = 0.0
var _player: CharacterBody3D = null

var _ui: CanvasLayer = null
var _bar: ColorRect = null
var _label: Label = null
var _shove_player: AudioStreamPlayer3D = null
var _settle_player: AudioStreamPlayer3D = null


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build()
	_build_audio()


# ---------------------------------------------------------------- construction

func _build() -> void:
	# Body. Flat, unlit steel — no emission. A prop that must be found in a dim room
	# is still not allowed to light itself (Issue 33): the room's lamp does that work.
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = SIZE
	body.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.33, 0.31)
	mat.metallic = 0.35
	mat.roughness = 0.7
	body.set_surface_override_material(0, mat)
	add_child(body)

	# Artwork rides on its own QuadMesh, never on the BoxMesh face — a textured box
	# renders a magnified crop of its own art rather than mapping the whole texture
	# per face (Issue 24; door.gd:build_visual is the reference pattern).
	if ResourceLoader.exists(TEX):
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(SIZE.x - ART_INSET, SIZE.y - ART_INSET)
		quad.mesh = qm
		var qmat := StandardMaterial3D.new()
		qmat.albedo_texture = load(TEX)
		qmat.roughness = 0.7
		quad.set_surface_override_material(0, qmat)
		quad.position = Vector3(0, 0, SIZE.z / 2.0 + ART_PROUD)
		add_child(quad)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = SIZE
	col.shape = shape
	add_child(col)


func _build_audio() -> void:
	_shove_player = _make_player("locker_shove", -3.0)
	_settle_player = _make_player("locker_settle", 0.0)


func _make_player(base_name: String, vol: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	var s := GameState.load_audio(base_name)
	if s:
		p.stream = s
	p.volume_db = vol
	p.unit_size = 6.0
	add_child(p)
	return p


# ---------------------------------------------------------------- interaction

# player.gd calls this before showing "Press E" and before setting its interact
# target. Returning false makes the locker COMPLETELY inert: no prompt, no target, and
# E does nothing at all — not even a refusal (playtest 2026-07-26: "the locker must be
# completely inactive until I find the note — press E should not even appear"). Until
# the Observation note is read it is scenery. The note names it explicitly ("Records…
# the steel locker went flat against the sub-panel"), so nobody is left without a lead
# once they have it.
func can_interact() -> bool:
	return unlocked and not _done


func interact() -> void:
	if _done or not unlocked:
		return
	if _pushing:
		# The QTE is open and ARM_DELAY has passed — this is the give-up press.
		if _armed >= ARM_DELAY:
			_abort("You let go. The locker settles back.")
		return
	_start_push()


func is_pushing() -> bool:
	return _pushing


func _start_push() -> void:
	_player = _find_player()
	if not _player:
		return
	_pushing = true
	_lurching = false
	_effort = PUSH_START
	_shoves = 0
	_armed = 0.0

	# Plant the player squarely in front of the locker. This is not framing polish:
	# it is what guarantees the slide can never pass through them, since freeze_input()
	# holds them exactly where this tween leaves them.
	var front: Vector3 = global_transform.basis.z.normalized()
	var brace := global_position + front * BRACE_DIST
	brace.y = _player.global_position.y
	# Face the locker (player forward is -basis.z), taking the short way round. Pitch
	# is deliberately untouched — player.gd owns `_pitch` privately and re-applies it
	# on the next mouse motion, so writing camera.rotation.x here would snap back.
	var target_yaw: float = atan2(front.x, front.z)
	var yaw := _player.rotation.y + angle_difference(_player.rotation.y, target_yaw)

	var t := create_tween().set_parallel(true)
	t.tween_property(_player, "global_position", brace, BRACE_TIME)
	t.tween_property(_player, "rotation:y", yaw, BRACE_TIME)

	# freeze_input() blocks BOTH movement (_apply_movement early-returns) and look
	# (_unhandled_input early-returns) with no player.gd change at all — that is the
	# "camera pinned at the locker" behaviour, for free.
	_player.freeze_input()
	_build_ui()


func _process(delta: float) -> void:
	if not _pushing:
		return

	# A screamer firing mid-push (this QTE's own panic drip can reach PANIC_MAX)
	# disables the player node and reloads the scene out from under us. Drop the UI
	# silently rather than trying to resume — the same lesson as the Issue-9 guard in
	# note_ui.gd / maze_chase_ui.gd, in the un-paused flavour.
	if not is_instance_valid(_player) or _player.process_mode == Node.PROCESS_MODE_DISABLED:
		_pushing = false
		_drop_ui()
		return

	_armed += delta
	# The panic drip keeps running through a lurch — you are still braced against it.
	_player.add_panic(PUSH_PANIC * delta)
	if _lurching:
		return

	_effort -= PUSH_DECAY * delta

	if Input.is_action_just_pressed("push_effort"):
		_effort += PUSH_PER_PRESS
		if _shove_player.stream:
			_shove_player.pitch_scale = randf_range(0.92, 1.08)
			_shove_player.play()

	if _armed >= ARM_DELAY and Input.is_action_just_pressed("interact"):
		_abort("You let go. The locker settles back.")
		return

	if _effort >= 1.0:
		_lurch()
		return
	if _effort <= 0.0:
		_abort("You can't shift it. Get your breath back.")
		return

	_update_ui()


func _abort(message: String) -> void:
	_pushing = false
	_drop_ui()
	if is_instance_valid(_player):
		_player.unfreeze_input()
	ScreenText.toast(get_tree(), message, Color(0.8, 0.78, 0.7), 2.2)


# One bar's worth of effort: the locker jerks SHOVE_DIST and the bar resets. The third
# one is the last, and hands off to _slide() for the final travel + settle.
func _lurch() -> void:
	_shoves += 1
	if _shoves >= SHOVES_NEEDED:
		_slide()
		return

	_lurching = true
	_effort = PUSH_START
	if _shove_player.stream:
		_shove_player.pitch_scale = randf_range(0.86, 0.96)   # heavier than a single press
		_shove_player.play()
	if _player and _player.has_method("jolt_camera"):
		_player.jolt_camera(0.045, SHOVE_TIME)

	var target: Vector3 = global_position + global_transform.basis.x.normalized() * SHOVE_DIST
	var t := create_tween()
	t.tween_property(self, "global_position", target, SHOVE_TIME) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	t.finished.connect(func() -> void:
		_lurching = false
		_update_ui()
	)
	_update_ui()


func _slide() -> void:
	_pushing = false
	_lurching = false
	_done = true
	_drop_ui()
	if _settle_player.stream:
		_settle_player.play()

	var target: Vector3 = global_position + global_transform.basis.x.normalized() * SHOVE_DIST
	var t := create_tween()
	t.tween_property(self, "global_position", target, SLIDE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Connected, never awaited — an awaited timer dies with the node that started it
	# (Issue 6). The player stays frozen until it has finished moving, so they watch it.
	t.finished.connect(func() -> void:
		if is_instance_valid(_player):
			_player.unfreeze_input()
		moved.emit()
	)


func _find_player() -> CharacterBody3D:
	var nodes := get_tree().get_nodes_in_group("player")
	if nodes.size() > 0:
		return nodes[0] as CharacterBody3D
	return get_tree().current_scene.get_node_or_null("Player") as CharacterBody3D


# ---------------------------------------------------------------- push HUD

# Structurally beartrap.gd:_build_escape_ui() — a CanvasLayer parented to the LEVEL
# (so it dies with the scene rather than outliving it), a bg ColorRect at
# PRESET_CENTER_BOTTOM and a fill ColorRect driven by `anchor_right`, never `size`.
# Steel/amber rather than the beartrap's blood-red: this is exertion, not a death timer.
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	get_parent().add_child(_ui)

	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.06, 0.06, 0.05, 0.85)
	bar_bg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar_bg.offset_top = -95
	bar_bg.offset_bottom = -65
	bar_bg.offset_left = -205
	bar_bg.offset_right = 205
	_ui.add_child(bar_bg)

	_bar = ColorRect.new()
	_bar.color = Color(0.85, 0.66, 0.22, 1.0)
	_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.add_child(_bar)

	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_font_size_override("font_size", 22)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_label.offset_top = -140
	_label.offset_bottom = -98
	_label.offset_left = -350
	_label.offset_right = 350
	_ui.add_child(_label)
	_update_ui()


func _update_ui() -> void:
	if not _bar or not _label:
		return
	_bar.anchor_right = clampf(_effort, 0.0, 1.0)
	# The shove counter is the whole point of staging this — it turns a long bar that
	# looks stuck into three short bars that visibly progress.
	_label.text = "BRACE — MASH [SPACE] TO PUSH   (shove %d / %d)" % \
		[mini(_shoves + 1, SHOVES_NEEDED), SHOVES_NEEDED]


func _drop_ui() -> void:
	if _ui:
		_ui.queue_free()
		_ui = null
		_bar = null
		_label = null
