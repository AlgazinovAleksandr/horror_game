extends StaticBody3D
class_name KonturMailbox

# KONTUR Landing's mailbox. The level (kontur.gd:_spawn_mailbox) builds the mesh and
# collider as children and sets `hint_text` — this script only owns the interaction,
# the same division of labor as key_item.gd and offering_pedestal.gd.
#
# Rebuilt 2026-07-25 from a flat photo-decal into a real 12-slot bank (playtest
# capture #4). Only SLOT 12 opens: `door_hinge` is handed over by the builder, and
# the first interact() swings it before the note appears, so the note reads as having
# come OUT of the box rather than off the wall. Re-reading afterwards leaves the door
# open — the box has already been opened; closing it again would be a lie.
#
# ⚠️ THE SWING USED TO BE INVISIBLE (fixed 2026-08-16). interact() started the Tween and
# then called NoteUI.show_note() on the very next line — and show_note() PAUSES THE TREE. A
# Tween does not advance until the following frame, and while the tree is paused that frame
# never arrives, so the door sat shut behind the fullscreen note and only swung after the
# player closed it. Four lines below a header that describes the opposite behaviour. The
# note is now fired from the tween's `finished`: open, then see, then read.
#
# ⚠️ THE SLOT IS STIFF, and deliberately not a minigame. `PRESSES_NEEDED` presses on E, each
# one groaning and shifting the door a couple of degrees before it springs back, then it
# gives. No bar, no timer, no failure — this is the `LightSwitch.presses_needed` idiom the
# Intro ward established (a stuck switch is frightening at zero mechanical cost), NOT
# lab_locker.gd's tug-of-war. There is nothing to lose here and nothing to be good at; the
# resistance exists so that a mailbox nobody has opened in thirty years opens like one.

@export var hint_text: String = ""

const OPEN_ANGLE_DEG := -105.0
const SWING_TIME := 0.35

# Total presses to open. Two that stick, one that gives.
const PRESSES_NEEDED := 3
const STICK_ANGLE_DEG := -7.0     # how far the jammed door shifts before springing back
const STICK_TIME := 0.13

# Set by the builder, not exported — it is a node from the mesh this script does not
# construct, so there is nothing sensible to point an inspector path at.
var door_hinge: Node3D = null

var _opened: bool = false
var _presses: int = 0
var _shift: Tween = null      # the stuck-press wobble; kept only so a new press can kill it


func interact() -> void:
	if _opened:
		# Already open: the page is just a page now, no swing, no wait.
		NoteUI.show_note(hint_text)
		return
	_presses += 1
	if _presses < PRESSES_NEEDED:
		_stick()
		return
	_opened = true
	_swing_open()


# It moves, and it does not open. The shift is what stops a stuck slot reading as a broken
# game: the press unambiguously registered, and only the RESULT failed to arrive —
# light_switch.gd's plate-blip, in metal.
func _stick() -> void:
	_play_creak(1.35, -5.0)
	if not is_instance_valid(door_hinge):
		return
	# ⚠️ A rapid second press must COUNT, not be swallowed. Killing the running tween and
	# starting a new one is what makes mashing feel like tugging at a jammed door; an
	# `if _busy: return` guard here reads as the game ignoring you, which is the one thing a
	# deliberately-stiff prop cannot afford (light_switch.gd's blip exists for the same
	# reason). The tween handle is kept solely so it can be killed.
	if _shift and _shift.is_valid():
		_shift.kill()
	_shift = create_tween()
	_shift.set_trans(Tween.TRANS_QUAD)
	_shift.tween_property(door_hinge, "rotation_degrees:y", STICK_ANGLE_DEG, STICK_TIME)
	_shift.tween_property(door_hinge, "rotation_degrees:y", 0.0, STICK_TIME * 1.6)


func _swing_open() -> void:
	_play_creak(1.0, -2.0)
	if not is_instance_valid(door_hinge):
		# No hinge to watch (a stripped test rig): don't strand the note behind a tween
		# that will never run.
		NoteUI.show_note(hint_text)
		return
	var t := create_tween()
	t.set_trans(Tween.TRANS_QUAD)
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(door_hinge, "rotation_degrees:y", OPEN_ANGLE_DEG, SWING_TIME)
	# ⚠️ Connected, not awaited, and NOT called on the next line — see the header.
	t.finished.connect(_reveal)


func _reveal() -> void:
	if not is_inside_tree():
		return
	NoteUI.show_note(hint_text)


func is_open() -> bool:
	return _opened


func presses_made() -> int:
	return _presses


# `metal_creak` (sourced, converted from FLAC 2026-08-16) if it is there, otherwise the
# generic door creak this prop used before it existed.
func _play_creak(pitch: float, vol: float) -> void:
	var s := GameState.load_audio("metal_creak")
	if not s:
		s = GameState.load_audio("creak")
	if not s:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.unit_size = 5.0
	p.volume_db = vol
	p.pitch_scale = pitch
	add_child(p)
	if is_instance_valid(door_hinge):
		p.position = door_hinge.position
	p.finished.connect(p.queue_free)
	p.play()
