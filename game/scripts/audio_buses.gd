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


# ⭐ A bus for a level's SCORE, sent to Master rather than nested under `Ambience`.
#
# `ensure()` deliberately nests every level bed under `Ambience` so a global dip reaches it.
# That is right for room tone and wrong for music: the Corridor ducks `Ambience` by 40 dB
# for its last 25 m (`_tick_hush`), which is meant to take the WORLD away — the whispers,
# the ambient one-shots — and used to take the score with it, leaving the walk to the fall
# in silence. The user's call on 2026-08-15 was that the music plays for the whole level.
#
# ⚠️ Music on this bus is therefore NOT duckable by `HoldBreath` or a `SilenceZone` either.
# That is the trade and it is the same one `kontur.gd` already makes by leaving
# `kontur_music` on Master. If a level ever wants its score ducked, put it on `Ambience`.
static func ensure_music_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		return idx
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	return idx


# ⭐ Put every bus back to 0 dB. Called by `GameState.start_current_level()` on EVERY level
# load, and it is a guarantee rather than a tidy-up.
#
# ⚠️ AudioServer buses are GLOBAL and survive `change_scene_to_file`. Nothing about a scene
# change resets a volume, `ensure()` early-returns without touching one, and every per-level
# bed bus nests under `Ambience` — so a single level that ducks a bus and forgets to restore
# it silences every level that follows, for the rest of the process.
#
# That is not hypothetical. `corridor.gd:_tick_hush()` tweened `Ambience` to -40 dB at 296 m
# with no restore of any kind, which is why the Backrooms music was missing on arrival from
# the Corridor but present when the Backrooms was loaded directly (reported 2026-08-15). The
# same shape is latent in `dungeon.gd:_duck_bus()`, which has no `_exit_tree` guard.
#
# A level that wants a duck should still restore it itself; this is the floor under that.
static func reset_all() -> void:
	for i in range(AudioServer.bus_count):
		AudioServer.set_bus_volume_db(i, 0.0)
		AudioServer.set_bus_mute(i, false)
