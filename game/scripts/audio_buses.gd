extends Node
class_name AudioBuses

# The minimal bus layout, created at runtime.
#
# SCARY.md §4.1(a) specs a five-bus project layout in a `default_bus_layout.tres`. This
# is deliberately NOT that: there is no bus configuration in `project.godot` at all today
# and the only buses that have ever existed here are `Master` and the runtime
# `"Backrooms"` bus (`backrooms.gd:_ensure_bus`). Following that existing runtime pattern
# keeps the change to one file and cannot break a level by a mis-pathed resource; the
# full layout can land later without contradicting anything here.
#
# Two buses, and the split exists for exactly one reason:
#
#   Master
#   ├── Ambience   beds, room tone, world loops   ← duckable
#   └── Body       heartbeat, footsteps           ← NEVER ducked
#
# ⚠️ `Body` staying un-duckable is what makes every silence effect work. When the world
# goes quiet your own pulse must be the only thing left — that is the entire payload of
# `HoldBreath` and of Backrooms Zone 2's `SilenceZone`. Ducking `Master` instead would
# duck the heartbeat too and destroy the effect it exists to create, which is why
# HoldBreath could not be built before this file existed.

const AMBIENCE := "Ambience"
const BODY := "Body"


# Create `bus_name` if it does not exist; return its index.
#
# ⚠️ Per-level beds NEST UNDER `Ambience` rather than hanging off Master. The Backrooms
# and THE NIGHTMARE each create their own bus so a `SilenceZone` can duck that level's bed
# alone — but if those buses sent straight to Master, a `HoldBreath` dip of `Ambience`
# would do NOTHING in the two levels that most need it (the Backrooms fires `flash_scare`
# on every wrong wall). Nesting gives both: the level ducks its own bus, the global effect
# ducks the parent, and the two compose instead of competing.
#
# Godot resolves a send by name and a bus may only send to one created BEFORE it, which is
# why the `Ambience`/`Body` pair is forced into existence first.
static func ensure(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		return idx
	# Core buses hang off Master; everything else nests under Ambience.
	var send := "Master"
	if bus_name != AMBIENCE and bus_name != BODY:
		ensure(AMBIENCE)
		send = AMBIENCE
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send)
	return idx


# Called once from GameState._ready(), which runs before any scene — so the two core
# buses always exist before a level or a player tries to route audio to them.
static func ensure_core() -> void:
	ensure(AMBIENCE)
	ensure(BODY)
