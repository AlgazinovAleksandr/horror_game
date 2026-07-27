extends Node
class_name HoldBreath

# SCARY.md P5 — silence as an event.
#
# `silence_zone.gd` proved the bus duck works, but it is SPATIAL: you have to walk into
# it. This is the EVENT form — duck a bus hard, hold, restore — and its most valuable
# placement is inside `Screamer.flash_scare()` as a pre-duck, which improves every
# survivable scare in the game at once: the House forest window, the Corridor Manager,
# the three turn mirrors, the Lab nook payoff, all eight KONTUR strike flashes.
#
# F.E.A.R.'s entire audio thesis is that the silence before the hit is what makes the hit.
# The game's longest telegraph before this was 0.22 s (`apparition.gd:TELEGRAPH_TIME`);
# everything else was a hard cut to a fullscreen image.
#
# ⚠️ Ducks `AudioBuses.AMBIENCE`, never `Master`. See audio_buses.gd for why — ducking
# Master would take the heartbeat with it, which is the one sound that must survive.
#
# ⚠️ Parents to the TREE ROOT and cleans up via a CONNECTED tween, never an awaited one
# (Issue 6 — an awaited timer dies with the node that started it, and the node that starts
# this one is frequently a level that is about to reload).
#
# ⚠️ PROCESS_MODE_ALWAYS. A note, a lock UI or a maze UI can pause the tree mid-dip, and a
# paused tween would leave the world permanently silent — the same failure `SilenceZone`
# guards with its `_exit_tree()` restore, which this also has.

const DUCK_DB := -30.0
const FADE_DOWN := 0.15
const FADE_UP := 0.4
const DEFAULT_HOLD := 0.6

# One dip at a time per bus. Two overlapping dips would race their tweens and could
# restore to the ducked value — the loudest possible bug, since it leaves the level mute.
static var _active: Dictionary = {}


# Duck `bus_name` for `hold` seconds, then restore. Returns false if a dip is already
# running on that bus (the caller does not need to care; a scare that lands during another
# scare's silence is already silent).
static func dip(tree: SceneTree, hold: float = DEFAULT_HOLD,
		bus_name: String = AudioBuses.AMBIENCE) -> bool:
	if _active.get(bus_name, false):
		return false
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return false   # the bus was never created; silently do nothing

	var node := HoldBreath.new()
	node.name = "HoldBreath"
	node._bus_name = bus_name
	node._bus_idx = idx
	node._restore_db = AudioServer.get_bus_volume_db(idx)
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(node)
	_active[bus_name] = true
	node._run(hold)
	return true


var _bus_name: String = ""
var _bus_idx: int = -1
var _restore_db: float = 0.0


func _run(hold: float) -> void:
	# AudioServer bus volume is not a node property, so it cannot be tweened directly —
	# tween a scalar and mirror it onto the bus each step (silence_zone.gd:42-45).
	var tw := create_tween()
	tw.tween_method(_set_db, _restore_db, DUCK_DB, FADE_DOWN)
	tw.tween_interval(hold)
	tw.tween_method(_set_db, DUCK_DB, _restore_db, FADE_UP)
	tw.finished.connect(queue_free)


func _set_db(v: float) -> void:
	if _bus_idx != -1:
		AudioServer.set_bus_volume_db(_bus_idx, v)


# The non-negotiable half of silence_zone.gd's contract: the bus must never be left
# ducked, however this node dies.
func _exit_tree() -> void:
	if _bus_idx != -1:
		AudioServer.set_bus_volume_db(_bus_idx, _restore_db)
	_active.erase(_bus_name)
