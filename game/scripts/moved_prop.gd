extends Node
class_name MovedProp

# SCARY.md P6 — the object that changed.
#
# A prop the player has already walked past sits in a slightly different position on the
# return leg. No sound. No event. No panic. The game never mentions it.
#
# Condemned's power came from being RETROACTIVE: "there are plenty of other mannequins
# around the store, so players nervously remember all of the ones they've already walked
# past." One moved prop makes every previous prop suspect. That asymmetry — **if the
# player never notices, nothing happens** — is the entire mechanic, and it is why this
# script has no feedback channel of any kind.
#
# Attach it to any Node3D:
#     MovedProp.attach(chair, "landing_chair", Vector3(0, 0, -0.9), deg_to_rad(35.0))
#
# ⚠️ ONE-SHOT PER PROP PER RUN. A prop that keeps moving is a mechanic; this must stay an
# anomaly. Once applied it does nothing forever.
#
# ⚠️ Constrain deltas to >= 2 cm off every existing plane, or tests/check_wall_overlap.gd
# will flag the moved prop as a coincident surface (the Issue 19/20/23 family).
#
# ⚠️ Register applied moves in the level's save_progress() so walking back through a door
# does not un-move them. `key` exists for exactly that: it is the serialisation name.
#
# ⚠️ This is deliberately NOT built on Bloober's "manufacture the look-away" method
# (SCARY.md P11). That one steers the camera with light and sound and then mutates
# geometry; this one just waits. Waiting is free and has no regression risk, which is why
# P6 is XS and P11 is "do this last".

signal moved

const DEFAULT_MIN_DIST := 6.0
# How far off "looking at it" the player has to be. -0.1 rather than 0.0 on purpose: a
# prop exactly at 90° to the heading is still in peripheral vision, and a prop that
# shifts at the edge of the frame reads as a rendering glitch rather than as an anomaly.
const FACING_AWAY_DOT := -0.1
const POLL_INTERVAL := 0.2      # 5 Hz. Nothing here needs a per-frame answer.

var key: String = ""            # stable name for save_progress()

var _target: Node3D = null
var _delta_pos: Vector3 = Vector3.ZERO
var _delta_rot: Vector3 = Vector3.ZERO
var _min_dist: float = DEFAULT_MIN_DIST
var _applied: bool = false
var _armed: bool = false
var _poll: float = 0.0
var _player: CharacterBody3D = null
var _camera: Camera3D = null


# `delta_rot` is a FULL euler delta in radians, not just a yaw.
#
# ⚠️ It used to be a single `delta_yaw: float`, which silently made "lay the painting
# face-down on the floor" impossible: yaw spins a picture about its vertical axis, so the
# painting dropped to floor height and stayed UPRIGHT — playtest 2026-07-28 photographed it
# standing on the floorboards and asked "why is the painting now on the wall?". Laying
# something flat is a PITCH (x), and there was no way to express one.
static func attach(target: Node3D, prop_key: String, delta_pos: Vector3,
		delta_rot: Vector3 = Vector3.ZERO, min_dist: float = DEFAULT_MIN_DIST) -> MovedProp:
	var m := MovedProp.new()
	m.name = "MovedProp"
	m.key = prop_key
	m._target = target
	m._delta_pos = delta_pos
	m._delta_rot = delta_rot
	m._min_dist = min_dist
	target.add_child(m)
	return m


# Not armed until the level says so. Without this the delta could fire during the level's
# own _ready(), before the player has ever seen the prop in its original place — and a
# prop that was never in position A cannot have moved from it.
func arm() -> void:
	_armed = true


func is_applied() -> bool:
	return _applied


# Force the move without waiting for a look-away. This is the restore path: the player
# already saw it moved before they walked back through the door, so it must still be
# moved when they return, and re-arming the wait would silently un-move it.
func apply_now() -> void:
	if _applied:
		return
	_apply()


func _process(delta: float) -> void:
	if _applied or not _armed:
		return
	if not _target or not is_instance_valid(_target):
		set_process(false)
		return

	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_INTERVAL

	if not _player or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		if not _player:
			return
		_camera = _player.get_node_or_null("Camera3D") as Camera3D
	if not _camera:
		return

	var to_prop := _target.global_position - _camera.global_position
	if to_prop.length() < _min_dist:
		return

	# Horizontal-only facing test — see the note in watcher.gd:_is_seen() for why mixing
	# in the vertical component produces false results at close range.
	var fwd := -_camera.global_basis.z
	fwd.y = 0.0
	to_prop.y = 0.0
	if fwd.length() < 0.01 or to_prop.length() < 0.01:
		return
	if fwd.normalized().dot(to_prop.normalized()) < FACING_AWAY_DOT:
		_apply()


func _apply() -> void:
	_applied = true
	_target.global_position += _delta_pos
	if _delta_rot != Vector3.ZERO:
		_target.rotation += _delta_rot
	moved.emit()
	set_process(false)
