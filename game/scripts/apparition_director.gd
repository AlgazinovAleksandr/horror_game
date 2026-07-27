extends Node
class_name ApparitionDirector

# Decides WHEN the shared apparition shows up. One node, added as a child by any level
# that wants random apparitions:
#
#     var d := ApparitionDirector.new()
#     d.suppress = func() -> bool: return _in_breaker_nook   # optional, level-specific
#     add_child(d)
#
# ─────────────────────────────────────────────────────────────────────────────────
# BACKLOG #6: "the monster appears too often. Make it more rare."
#
# What it replaced: level_1.gd, level_2.gd and kontur.gd each carried an identical
# `_tick_debug_apparition()` with `DEBUG_APPAR_INTERVAL = 60.0` — a bare countdown that
# fired a FATAL apparition every 60 seconds no matter what the player was doing. Three
# copies of the same twelve lines, so any retune had to be made three times and could
# be forgotten in one.
#
# Rarity was only half the problem, and the smaller half. A metronome has no sense of
# occasion: it would fire while a note was open, while the player was clamped in a
# beartrap escape QTE, seconds after RandomAmbient had already startled them, or in the
# first few seconds of a level before they had oriented. The beartrap case is the worst
# of these and is not a difficulty question but a fairness one — the HOLD apparition
# kills you for fleeing, and a player whose input is frozen cannot demonstrate that
# they are standing their ground. That is the same double-jeopardy shape as KONTUR's
# Blackout and the Backrooms Flood, both of which this project has already had to undo
# (ISSUES_SOLUTIONS Issue 18).
#
# So: a longer randomised gap, plus the conditions under which an appearance would be
# incoherent or unfair. Anything blocked is simply retried on the next tick — the
# director never "owes" the player an apparition.

# Randomised, not fixed: a constant interval is learnable, and the point of this
# creature is that you don't know when it is coming.
const MIN_GAP := 90.0
const MAX_GAP := 180.0

# No apparition in the opening moments of a level. The player is still working out
# where they are, several levels open with their own scripted beat, and an apparition
# landing on top of that reads as noise.
const LEVEL_GRACE := 45.0

# Keep clear of RandomAmbient's own scares (floor_creak / painting_fall / half_scream,
# worth 5-12 panic each). Two unrelated scares in the same breath read as one confusing
# event, and the player attributes the sound to the figure.
#
# ⚠️ MUST stay well below RandomAmbient's MIN_INTERVAL (18 s) or this rule can never be
# satisfied. Measured, not reasoned: at 30 s it produced ZERO apparitions in a 400 s
# run of tests/count_apparitions.gd, because RandomAmbient fires every 18-35 s and the
# "at least 30 s since the last one" window barely exists. A suppression condition
# tuned against a period comparable to its own is a deadlock, and this one would have
# silently deleted the game's flagship monster — exactly the shape of Issue 34.
const MIN_GAP_AFTER_AMBIENT := 8.0

# How long the soft conditions (ambient spacing, panic level) may hold an appearance
# back before they are ignored. The hard fairness conditions — paused tree, open note,
# frozen input, a level's own veto — are never relaxed. This exists so that no
# combination of tuning can make the apparition quietly stop happening: it can be
# delayed, never cancelled.
const OVERDUE_AFTER := 60.0

# Not while the player is already close to the edge. Panic-max fires the screamer on its
# own, so an apparition here isn't a test of nerve — it is a coin flip already resolved.
const MAX_PANIC_RATIO := 0.6

# Optional level-supplied veto, e.g. level_1.gd's `_in_breaker_nook`.
var suppress: Callable = Callable()

var _elapsed: float = 0.0
var _next_at: float = 0.0
var _player: CharacterBody3D = null


func _ready() -> void:
	_next_at = LEVEL_GRACE + randf_range(MIN_GAP, MAX_GAP) * 0.5


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < _next_at:
		return
	if not _can_fire(_elapsed - _next_at >= OVERDUE_AFTER):
		return          # retried next frame; the gap only resets on an actual spawn
	_fire()


func _resolve_player() -> CharacterBody3D:
	if _player and is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	return _player


func _can_fire(overdue: bool) -> bool:
	# --- hard conditions: never relaxed, however overdue ---
	if suppress.is_valid() and suppress.call():
		return false
	# A paused tree means a note, a lock, the maze minigame or a screamer owns the
	# screen. NoteUI is checked separately because it is the one that most often sits
	# open for a long time.
	if get_tree().paused or NoteUI.is_open:
		return false
	var p := _resolve_player()
	if not p:
		return false
	if p.is_input_frozen():
		return false          # beartrap QTE / locker push / hiding — see the header

	# --- soft conditions: pacing preferences, dropped once OVERDUE_AFTER has passed ---
	if overdue:
		return true
	if p.get_panic_ratio() >= MAX_PANIC_RATIO:
		return false
	var ra := get_node_or_null("/root/RandomAmbient")
	if ra and ra.has_method("seconds_since_last_scare"):
		if float(ra.call("seconds_since_last_scare")) < MIN_GAP_AFTER_AMBIENT:
			return false
	return true


func _fire() -> void:
	_elapsed = 0.0
	_next_at = randf_range(MIN_GAP, MAX_GAP)
	var a := Apparition.spawn(get_parent(), Apparition.Rule.HOLD, Vector3.ZERO, false) as Apparition
	var taught := arm(a)
	var dbg := get_node_or_null("/root/DebugLog")
	if dbg:
		dbg.call("note", "APPARITION (director, teach=%s)" % taught)


# ⚠️ THE global teach ledger — every path that makes a HOLD apparition materialise goes
# through here, including the four scripted, trigger-armed encounters in level_1.gd,
# level_2.gd and backrooms_zone3.gd.
#
# The FIRST HOLD apparition in a run is always survivable, wherever it happens. The
# rule ("do not run") is only fair once it has been taught, and the ledger used to be
# implicit and per-level: the Lab's scripted encounter passed teach=true and everything
# else passed teach=false, hard-coded at BUILD time. So a player who reached the House
# cellar or the Backrooms Flood without ever tripping the Lab's corridor trigger met a
# lethal one first and died to a rule nothing had stated.
#
# `force_teach` is for the Lab's designed teaching beat, which should stay survivable
# even in the rare case the director got in first.
# Returns whether this one ended up being the taught one.
static func arm(a: Apparition, force_teach: bool = false) -> bool:
	if not a:
		return false
	var teach: bool = force_teach or not GameState.apparition_taught
	a.teach = teach
	GameState.apparition_taught = true
	a.appear()
	return teach
