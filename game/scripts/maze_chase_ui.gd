extends CanvasLayer
class_name MazeChaseUI

# The House map-and-chase minigame (new feature). A fresh braided maze (randomized DFS,
# never memorizable) is generated for every genuine ATTEMPT — i.e. on a win or a catch, not
# on a close-and-reopen; see `_instance_live` for the measurement behind that. The player
# drags their icon around the map with the mouse while a monster icon hunts them.
#
# ⭐ THE OBJECTIVE IS TWO-STAGE (2026-08-16, the user's own redesign, approved after a
# brainstorm): COLLECT every fragment, THEN escape to the mark. The mark is inert — visibly
# sealed — until the last fragment is in hand. Getting caught ends the attempt exactly as it
# always did, and fragments already collected are lost with it: there is deliberately NO
# partial-progress carry-over, because the brief was harder, not gentler.
#
# ⚠️ WHY, and it is not "because a longer maze is a harder maze". The measurement is in
# `backlogs/02-house.md` §7 P4, 200 seeds: **the median winning run was 9.8 s** (p90 14.4 s).
# The user asked for a maze "more packed with actions", and there is no room in ten seconds
# for a roster of a hunter, a patroller and five snares to *matter* — most of those runs ended
# before the patroller was ever met. Packing more into ten seconds would only have raised the
# density of the coin flip. The fragments buy TIME ON THE BOARD, which is what turns the
# existing roster into decisions. Not one difficulty constant moved to achieve it — see the
# protected list at MONSTER_SPEED.
#
# house_map_prop.gd owns the fail consequence. Panic rises the whole time it's open — a flat
# drip plus a proximity term — via the same "a paused UI's own _process still calls
# player.add_panic() every frame" idiom note_ui.gd already uses for trap notes.
#
# Pause convention matches combination_lock.gd/note_ui.gd exactly: get_tree().paused
# = true while open, MOUSE_MODE_VISIBLE, reversed on close — this freezes the whole
# 3D game for free, no changes needed to player.gd or any creature script. Because
# this UI's own add_panic() call can itself push panic to PANIC_MAX and trigger a
# fatal Screamer.trigger() mid-minigame, the Issue-9 pause-race guard below is not
# optional — copied verbatim from the same lesson in note_ui.gd/combination_lock.gd.

signal won
signal caught

const TEX := "res://assets/textures/level_2_house/"

# ---------------------------------------------------------------- maze grid
#
# ⭐ 10x8 → 16x9 (2026-08-16, the user's call), and this is where the run's LENGTH comes from.
#
# ⚠️ It is the one change on this board that buys duration for free, and the measurement is
# the whole argument. With the one-stage objective, on 10x8 the bot won 82 % at a median of
# 10.9 s; on 16x9 it won 80/100 at **16.9 s** — a 55 % longer run at the same win rate, with
# the hunter taking 4 catches in 100 either way. Compare that with buying length from
# WAYPOINTS, which cost 82 % → 14 % for a 60 % longer run (see `fragment_count`). The reason
# is the same one in both directions: a longer route is still monotone flight from the spawn,
# and monotone flight is the only posture in which the player out-paces the hunter at all.
#
# ⚠️ **The size is bounded by the SCREEN, not by taste.** At 96 px the playfield is
# 16*96 = 1536 wide by 9*96 = 864 tall, and `_root` is anchored at the viewport centre, so the
# overlay needs `864/2 + 46` above the middle for the caption and `864/2 + 54 + 22` below it
# for the counter and the pips — 478 up, 508 down, against 540 either way at 1080p. **Nine
# rows is the last row that fits.** Ten would be 528/558 and would push the pips off screen.
# Verified in the real overlay by `screenshot_maze_ui.gd`, not on paper: this file has already
# put a caption across the middle of the parchment once by trusting arithmetic.
const GRID_COLS := 16
const GRID_ROWS := 9
const CELL_SIZE := 96.0
const WALL_THICKNESS := 8.0
const PLAYFIELD_SIZE := Vector2(GRID_COLS * CELL_SIZE, GRID_ROWS * CELL_SIZE)  # 1536x864

# ---------------------------------------------------------------- icons
const ICON_DISPLAY_SIZE := 64.0  # was 40 — playtest asked for bigger, more legible marks
const ICON_HALF_EXTENT := 14.0
const WIN_RADIUS := 28.0
const CATCH_RADIUS := 20.0

# ---------------------------------------------------------------- the fragments
#
# ⭐ Stage one of the two-stage objective. N torn pieces of the map, scattered so that
# collecting them forces genuine DETOURS off the direct line and genuine RE-CROSSINGS of the
# maze — not a slightly longer walk to the same place.
#
# ⚠️ "Off the route" is measured as DETOUR COST, not as raw distance from the route cells.
#     detour(c) = d(start,c) + d(c,mark) - d(start,mark)
# i.e. exactly how many extra cells of walking this fragment costs, which is the quantity the
# feature is actually about. The obvious alternative — "at least K cells from the nearest
# route cell" — is unusable here and it is worth recording why: the direct route already has a
# MEDIAN LENGTH OF 28 CELLS in an 80-cell grid (P4), so a set of cells 3+ steps from it is
# routinely EMPTY. A constraint that is usually unsatisfiable degrades to "place them
# anywhere", silently, which is the shape of Issue 34's stub.
#
# ⚠️ Fragments carry NO panic and NO fail state. Collecting one is pure objective. The brief
# for this project is "stop adding panic terms, start adding channels"; the pressure this
# feature adds is time spent in front of the existing roster, which is a channel.
const FRAGMENT_PICKUP_RADIUS := 26.0
const FRAGMENT_MIN_DETOUR := 6        # cells of extra walking each fragment must be worth
const FRAGMENT_MIN_SEPARATION := 5    # cells between fragments, so they are not one pocket
const FRAGMENT_PLACE_ATTEMPTS := 20   # validate-and-reject, then accept the best seen
# How wide the slot band is, as a fraction of the route length. Fragment k must sit within
# this of `k/(N+1)` of the way out from the start — see _sample_fragments() for why the tour
# has to be monotone outward, and what it measured when it was not.
const SLOT_HALF_WIDTH := 0.20

# The band the whole TOUR (start -> every fragment -> mark, in the order a sensible player
# would take them) is validated into. This is the determinism fix for capture A1 — *"the
# difficulty level is very random"* — and it is a far stronger one than banding the direct
# route would have been, because tour length is what run TIME is made of.
#
# Keyed by fragment count. The probe sweeps N; the shipped value is `fragment_count` below.
#
# ⚠️ THE NUMBERS ARE MEASURED, and the measurement is the most important thing in this file.
# `probe_maze_variance.gd`, 400 seeds, bot at 200 px/s, everything else shipped:
#
#     win rate by TOUR length, N=1 on the 16x9 board, UNBANDED
#        0-41   n=34   91 %   mean win 15.2 s
#        42-47  n=63   78 %             17.6
#        48-53  n=84   64 %             19.5
#        54-59  n=52   48 %             21.8
#        60-65  n=52   56 %             24.3
#        66-71  n=42   52 %             26.8
#        72+    n=73   27 %             30.2
#
# **A 91 % → 27 % swing decided by tour length alone**, and it is the largest single source of
# the user's *"the difficulty level is very random"*. Banding to 50…64 measured
# **232/400 = 58 %, median run 21.7 s**, with the tour's p10-p90 spread cut from 42-77 to
# 48-69.
#
# ⚠️ Tighter is NOT better, in either direction: 54…70 measured 51.8 % and 52…66 measured
# 54.0 %, both under `check_maze_chase.gd`'s asserted 0.55 floor, while 46…60 measured 63 %,
# above the "at or below the previous 59 %" ceiling the user set. The usable window is about
# four points wide and these numbers sit in the middle of it.
#
# ⚠️ **The band is board-specific.** On the old 10x8 grid this row read `Vector2i(34, 45)`, and
# it has to be re-measured — never rescaled — if the grid ever moves again. The 2 and 3 rows
# are stale 10x8 sweep values kept only so the probe can reproduce that frontier; they are not
# playable at any size. See `fragment_count`.
const TOUR_BAND := {
	1: Vector2i(50, 64),
	2: Vector2i(46, 58),
	3: Vector2i(56, 70),
}

# ⚠️ A `var` rather than a `const` for ONE reason: tests/probe_maze_variance.gd sweeps N on a
# single build, and the shipped value was chosen from that sweep rather than from taste.
# Nothing in the game ever writes it. **N=0 is the control** and reproduces the one-stage
# build exactly, which is how the baselines below were measured through the same code path.
#
# ⚠️⚠️ WHY ONE, WHEN THE BRIEF ASKED FOR 2 OR 3. Because 2 and 3 are not playable with this
# roster at any board size, and the reason is arithmetic rather than tuning. Measured,
# 200-400 seeds per point:
#
#     board   N   win rate   median run   caught by the hunter
#     10x8    0     82 %       10.9 s        7 / 200     <- control, one-stage
#     10x8    1     57 %       14.1 s       54 / 200
#     10x8    2     21 %       17.0 s      133 / 200
#     10x8    3     14 %       17.5 s      143 / 200
#     16x9    0     80 %       16.9 s        4 / 100     <- control, one-stage
#     16x9    1     58 %       21.7 s                    <- SHIPPED
#     16x9    2     20 %       28.2 s
#
# The hunter's kill rate goes 3.5 % → 70 % between N=0 and N=3 while the run only gets 60 %
# longer. That is not "more time on the board is more risk"; it is one specific mechanism:
#
#   ⭐ THE HEAD START IS A ONE-OFF BUDGET, AND EVERY WAYPOINT SPENDS IT. `MONSTER_START_DELAY`
#     buys ~600 px (six cells) of lead, once. After that the player nets only
#     240 − 172 = 68 px/s, and ONLY while running directly away. A waypoint forces a heading
#     change, during which the hunter — a pure corridor-following pursuit curve that never
#     tires, never loses interest and never resets — closes at its full speed. One six-cell
#     excursion costs about one head start. Three of them cannot be paid for.
#
# ⚠️ **So run length must be bought from the ROUTE, not from the OBJECTIVE**, and that is
# exactly what the 10x8 → 16x9 change at the top of this file does: the same two rows of the
# table show 82 % at 10.9 s and 80 % at 16.9 s. Both halves of the shipped design follow from
# that one asymmetry, and it is the finding to keep if everything else here is rewritten.
#
# ⚠️ The original brief asked for a 30-45 s winning run. **It is not reachable at an acceptable
# win rate** — 16x9 with N=2 gets to 28 s at 20 %. The user was shown this frontier and chose
# 16x9 with N=1 (58 % at 21.7 s), accepting that the 30-45 s target was probably wrong.
var fragment_count: int = 1
# ⚠️ Same reason, same rule: a var only so `probe_maze_variance.gd` can sweep the detour
# budget on one build. The shipped value is FRAGMENT_MIN_DETOUR and nothing in the game
# writes this. See §9 of backlogs/02-house.md for the frontier it was chosen from.
var min_detour_override: int = -1

# ---------------------------------------------------------------- drag physics
# Both the ease rate AND the speed cap degrade together as panic rises — that
# combination is what sells "harder to steer under pressure," not just "slower."
const SPRING_K_BASE := 9.0
const SPRING_K_PANIC := 3.0
const PLAYER_MAX_SPEED := 240.0
const PLAYER_MIN_SPEED := 100.0

# ---------------------------------------------------------------- monster
# Still under the player's worst-case (panic-1.0) speed floor of 100, so a player who
# keeps moving can always outpace it — but it no longer wastes that speed walking into
# walls. See _tick_monster(): it follows the actual corridor route now.
#
# ⚠️ BACKLOG #14: "the monster in the maze is too stupid. It can basically kill the
# player only at the beginning." It was not a speed problem. It steered by a raw
# Euclidean beeline toward the player, and the maze is a randomized-DFS spanning tree —
# a PERFECT maze, no loops — where the corridor route between two cells is routinely
# 5-15x the straight-line distance. So the beeline pointed into a wall most of the
# time, the per-axis wall-slide sent it sideways down whatever dead end the tangent
# happened to face, and once the player left the starting neighbourhood it could never
# close again. The anti-stuck dodge never fired either: sliding along a wall still
# counts as "moving", so _stuck_timer reset on every sample.
#
# The fix is not more speed. _bfs_distances() — exact, and already written — was being
# used only at generation time to pick the target and the monster's spawn cell. Running
# it from the PLAYER's cell gives a perfect distance field over the whole maze, and
# stepping downhill through it is optimal pursuit for a fraction of a millisecond per
# recompute (80 cells).
# ⚠️ 88 -> 132 -> 172, both raises on the user's call across two playtests. For scale, the
# dragged icon runs at PLAYER_MAX_SPEED 240 with full nerve and degrades to PLAYER_MIN_SPEED
# 100 at high panic — so at 172 the monster is comfortably faster than a panicking player,
# which is the point: hesitating is what kills you.
#
# Measured each time with tests/check_maze_chase.gd (40 seeds), and the numbers are the reason
# it was safe to go this far:
#     88  — stationary player caught 40/40; moving player wins 37/40
#     132 — caught in 3.6 s; hunted down 9.4 s after stopping; still 37/40
#     172 — caught in 3.5 s; hunted down 5.2 s after stopping; still 37/40
# The escape rate has not moved at all; what changed is how quickly a mistake is punished.
# ⚠️ Do not raise it again without re-running that test. This minigame once killed 12 players
# in 40 for an unrelated reason.
#
# ⚠️ 37/40 WAS the line that said it is still a game; it is 26/40 now, and deliberately so.
# The 2026-08-15 pass braided the maze, added the patroller below and added snares, and the
# user chose to let the level get harder rather than hold the old rate. The isolation
# numbers behind that figure are in check_maze_chase.gd, next to the asserted floor. This
# speed was NOT touched as part of it.
#
# ⚠️ NOR BY THE 2026-08-16 TWO-STAGE REDESIGN. That pass made the minigame materially harder
# and roughly three times longer, and it moved NONE of the following, every one of which the
# user has already ruled on (some twice):
#     MONSTER_SPEED · PATROL_SPEED · PATROL_AGGRO · PATROL_CALM
#     SNARE_COUNT · SNARE_RADIUS · SNARE_HOLD · SNARE_PANIC · HouseMap.CATCH_PANIC
#     MAZE_DRIP_RATE · PROXIMITY_RANGE · PROXIMITY_MAX_RATE
#     SPRING_K_BASE/PANIC · PLAYER_MAX/MIN_SPEED · BRAID_FRACTION
# The difficulty came from STRUCTURE — a two-stage objective and a patroller that no longer
# starts on your artery. If a future session finds itself reaching for one of these dials,
# that is the user's call and it needs a measurement first, not a nudge.
const MONSTER_SPEED := 172.0
const MONSTER_START_DELAY := 3.0  # frozen this long after open() before it hunts

# ---------------------------------------------------------------- panic
# Cut hard after playtest ("give me more time to pass the map minigame") —
# repeated deaths, on top of the head-start bug fixed above. Original values
# (0.9 / 260 / 5.0) were calibrated for a monster that started well away from
# the player; now that it spawns adjacent (per request), the average distance
# through a whole run is much smaller, so the same rates were far more punishing
# in practice than intended.
const MAZE_DRIP_RATE := 0.4
const PROXIMITY_RANGE := 160.0
const PROXIMITY_MAX_RATE := 2.5

var _ui_open: bool = false
var _focus_lost_clear: bool = false

var _cells: Array = []               # flat GRID_COLS*GRID_ROWS array of {n,e,s,w:bool}
var _wall_rects: Array[Rect2] = []
var _start_cell: Vector2i
var _target_cell: Vector2i

# ---- the two-stage objective ------------------------------------------------------------
var _fragment_cells: Array[Vector2i] = []
var _fragments: Array[Vector2] = []          # live, in playfield px; emptied as they are taken
var _fragments_initial: Array[Vector2] = []  # as generated, so a reopen re-arms them
# The order a sensible player takes them in (nearest-neighbour from the start), with the mark
# appended. `_tour[0]` is the first place the player actually walks toward, which is what
# _place_monster() must avoid blocking — the mark is no longer that place.
var _tour: Array[Vector2i] = []
var _tour_length: int = 0                    # corridor cells over the whole tour
var _patrol_route_gap: int = -1              # what _place_patroller() achieved, for the tests
var _bfs_cache: Dictionary = {}              # cell -> distance field, cleared per generation

var _player_pos: Vector2
var _monster_pos: Vector2
var _monster_start: Vector2          # where _place_monster() put it, for a reopen
var _target_pos: Vector2

var _monster_start_timer: float = 0.0

# Corridor-distance field from the player's current cell, and the cell it was built
# for. Rebuilt only when the player crosses into a new cell — see _pursuit_direction().
var _flow: Dictionary = {}
var _flow_origin: Vector2i = Vector2i(-1, -1)

var _root: Control
var _playfield: Control
var _wall_nodes: Array[ColorRect] = []
var _walls_container: Control
var _player_icon: Control
var _monster_icon: Control
var _patrol_icon: Control
var _target_icon: Control
var _target_seal: Control
var _caption: Label
var _counter_label: Label
var _fragment_nodes: Array[Control] = []
var _pip_nodes: Array[Panel] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 65  # above combination_lock's 60 and note_ui's 50
	_build_ui()


# ---------------------------------------------------------------- open/close

# ⭐ THE INSTANCE PERSISTS ACROSS A CLOSE-AND-REOPEN (2026-08-16, the user's call).
#
# `_unhandled_input` closes this overlay on ESC at zero cost and `HouseMap.interact()` reopens
# it — and `open()` used to call `_generate_maze()` unconditionally, so ESC was a free re-roll.
# Measured on two human sessions of the SAME puzzle: 134 s with one catch, versus 13 s. The
# 134 s session logged exactly one catch, so almost all of it was spent closing and reopening
# rather than dying: the optimal play was to shop for an easy layout, and the player correctly
# described the result as *"the difficulty level is very random"*.
#
# So a maze now lives until it is WON or you are CAUGHT. Closing it puts the map down; picking
# it up again resumes the same maze from the start cell.
#
# ⚠️ This is STRICTLY HARDER, and was chosen knowing that. It removes an escape hatch and adds
# none. It also narrows the design line "a fresh braided maze every attempt (never
# memorizable)" to *every genuine attempt* — a catch still costs CATCH_PANIC and still hands
# out a brand-new maze, so nothing is memorizable across attempts, only within one.
#
# ⚠️ Positions are still reset on every open. Persisting the icon's position instead would make
# ESC a panic button that teleports the hunter off your back, which is the opposite of the
# intent.
var _instance_live: bool = false


func open() -> void:
	if not _instance_live:
		_generate_maze()
		_instance_live = true
	_reset_positions()
	_rebuild_wall_visuals()
	_rebuild_snare_visuals()
	_rebuild_fragment_visuals()
	_refresh_objective_ui()
	_update_visual_positions()
	_start_chase_audio()
	_ui_open = true
	_focus_lost_clear = false
	_root.visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close() -> void:
	_ui_open = false
	_root.visible = false
	_stop_chase_audio()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# A screamer firing while we're open unpauses/reloads the scene out from under
# this UI — self-clear silently rather than trying to resume (Issue 9).
func _hide_after_external_unpause() -> void:
	_ui_open = false
	_root.visible = false
	# ⚠️ Stop the music HERE too, not only in _close(). This path is the one a screamer
	# takes, and a chase loop left running would play on over the reloaded scene.
	_stop_chase_audio()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focus_lost_clear = true


func _unhandled_input(event: InputEvent) -> void:
	if not _ui_open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


# ---------------------------------------------------------------- main loop

func _process(delta: float) -> void:
	if _ui_open and not get_tree().paused:
		_hide_after_external_unpause()
		return
	if not _ui_open:
		return

	var p := _player()
	var panic_ratio: float = p.get_panic_ratio() if p and p.has_method("get_panic_ratio") else 0.0

	var mouse_down: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _focus_lost_clear
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_focus_lost_clear = false  # a genuine release clears the focus-loss override
	if mouse_down:
		var cursor_local: Vector2 = get_viewport().get_mouse_position() - _playfield.global_position
		var k: float = lerpf(SPRING_K_BASE, SPRING_K_PANIC, panic_ratio)
		var ease_t: float = 1.0 - exp(-k * delta)
		var step: Vector2 = (cursor_local - _player_pos) * ease_t
		var max_step: float = lerpf(PLAYER_MAX_SPEED, PLAYER_MIN_SPEED, panic_ratio) * delta
		if step.length() > max_step and step.length() > 0.0:
			step = step.normalized() * max_step
		_player_pos = _resolve_wall_slide(_player_pos, _player_pos + step, ICON_HALF_EXTENT)

	# A snare holds you where you are. Movement above still ran, so the position is
	# rolled back — the drag keeps fighting and simply achieves nothing, which reads as
	# being caught on something rather than as the controls dying.
	if _snare_hold > 0.0:
		_snare_hold -= delta
		_player_pos = _snared_at

	var in_grace: bool = _monster_start_timer > 0.0
	if in_grace:
		_monster_start_timer -= delta
	else:
		_tick_monster(delta)
		_tick_patroller(delta)

	_check_snares(p)
	_check_fragments()

	var dist_to_monster: float = _monster_pos.distance_to(_player_pos)
	dist_to_monster = minf(dist_to_monster, _patrol_pos.distance_to(_player_pos))

	# Playtest: moving the monster to spawn right next to the player (per your
	# request) meant the proximity term was already near its max from frame one
	# — the "head start" froze the monster's movement but panic climbed the whole
	# time anyway, defeating the point of a grace period. No panic at all (drip
	# OR proximity) while the monster is still frozen — a real head start now.
	if not in_grace:
		var proximity_rate := 0.0
		if dist_to_monster < PROXIMITY_RANGE:
			var ratio: float = 1.0 - dist_to_monster / PROXIMITY_RANGE
			proximity_rate = PROXIMITY_MAX_RATE * ratio * ratio
		if p and p.has_method("add_panic"):
			p.add_panic(delta * (MAZE_DRIP_RATE + proximity_rate))

	_update_visual_positions()

	# Winning and being caught are the ONLY two things that retire a maze — see _instance_live.
	if _is_won():
		_instance_live = false
		_close()
		won.emit()
		return
	if dist_to_monster <= CATCH_RADIUS:
		_instance_live = false
		_close()
		caught.emit()
		return


func _player() -> CharacterBody3D:
	return get_tree().current_scene.get_node_or_null("Player") as CharacterBody3D


# ---------------------------------------------------------------- the patroller
#
# ⭐ The SECOND monster, and deliberately not a second copy of the first (2026-08-15).
#
# Two identical hunters would double the pressure without adding a decision. This one
# walks a circuit and only gives chase when you come near it, which is what makes ROUTE
# CHOICE matter — and route choice is the entire reason the maze is now braided. The
# hunter punishes standing still; the patroller punishes taking the obvious line.
#
# It is slower than the hunter on purpose: meeting it should be a mistake you can still
# walk out of, not a second unavoidable death.
const PATROL_SPEED := 86.0
const PATROL_AGGRO := 112.0     # px; inside this it drops the circuit and comes for you
const PATROL_CALM := 240.0      # px; outside this it gives up and resumes patrolling
const PATROL_MIN_START := 7     # cells of BFS distance from the player's start
# ⚠️ NOT a difficulty dial in the sense the others here are — it does not change how the
# patroller behaves, only how often it happens to begin standing on the line the player has
# to walk. See the measurement quoted in _place_patroller().
#
# ⚠️ **3 on the 10x8 board, 5 on this one, and the difference is measured rather than scaled.**
# 400 seeds, everything else shipped, win rate bucketed by how far off the route it started:
#
#     gap >= 3, tour band 46..62 ....  58 %   spread across buckets  40 / 55 / 59 / 73  = 33 pts
#     gap >= 5, tour band 50..64 ....  58 %   spread across buckets       52 / 56 / 64  = 12 pts
#
# Identical mean difficulty, and the run is 1 s LONGER — but the spread the player actually
# feels is a third of what it was. Raising the bar on its own overshoots to 63 %, so the
# headroom it frees is spent on a longer tour band rather than banked; the two constants were
# chosen together and must be re-measured together. `check_maze_gen.gd` reports 200/200 seeds
# satisfying this on the 16x9 board (it was 199/200 at gap 3 on the smaller one, where the
# board simply ran out of cells).
const PATROL_MIN_ROUTE_GAP := 5   # cells of BFS distance from the player's ROUTE
const PATROL_PLACE_ATTEMPTS := 20 # bounded; then take the best candidate seen

var _patrol_pos := Vector2.ZERO
var _patrol_start := Vector2.ZERO    # where _place_patroller() put it, for a reopen
var _patrol_target := Vector2i.ZERO
var _patrol_chasing := false
var _patrol_flow: Dictionary = {}
var _patrol_flow_origin := Vector2i(-99, -99)


func _place_patroller(dist: Dictionary) -> void:
	# Somewhere genuinely elsewhere — a patroller that starts on top of the player is
	# just a second hunter with extra steps.
	var far: Array[Vector2i] = []
	for cell in dist.keys():
		if int(dist[cell]) >= PATROL_MIN_START and cell != _target_cell:
			far.append(cell)

	# ⭐ BANDED OFF THE ARTERY (2026-08-16). THE variance fix, and it is worth stating the
	# measurement in full because it is the single largest source of the user's *"the
	# difficulty level is very random"* (backlog `02-house.md` §7 P4, 200 seeds):
	#
	#     win rate by patroller-start distance from the route
	#        0 steps   n=80   28%      <-- FORTY PER CENT of all instances
	#        1-2       n=30   57%
	#        3-4       n=29   83%
	#        5-6       n=18   83%
	#        7-9       n=25   88%
	#        10+       n=18  100%
	#
	# A 3x swing in survival, decided by a placement nobody chose. The cause is a one-line
	# omission: this function required only `PATROL_MIN_START` steps from the player's START
	# CELL and never consulted `_route_cells` — which `_generate_maze()` has already computed
	# by the time it runs. `_pick_patrol_target()` has avoided route cells since the day the
	# patroller shipped; only the START did not.
	#
	# The cliff on the 10x8 board was entirely between 0-2 and 3+; on the shipped 16x9 board it
	# sits between 4 and 5, and the constant moved with it — see PATROL_MIN_ROUTE_GAP for the
	# two measurements. Bounded sampling with an
	# accept-the-best fallback, never a `while` — in a maze whose artery happens to cover most
	# of the grid there may BE no cell 3 steps clear, and this code runs inside a paused
	# overlay where a hang cannot be distinguished from a crash.
	var gap: Dictionary = _route_gap_field()
	var start: Vector2i = _target_cell
	_patrol_route_gap = -1
	for _attempt in range(PATROL_PLACE_ATTEMPTS):
		if far.is_empty():
			break
		var c: Vector2i = far[randi() % far.size()]
		var g: int = int(gap.get(c, 0))
		if g > _patrol_route_gap:
			_patrol_route_gap = g
			start = c
		if g >= PATROL_MIN_ROUTE_GAP:
			break
	# ⚠️ AND THEN A DETERMINISTIC SWEEP IF THE SAMPLING MISSED (measured: it did, on 1 seed in
	# 200 — `check_maze_gen.gd` caught seed 71 taking a cell 2 off the route while a cell 4 off
	# was free). 20 random draws is a probabilistic guarantee, and a probabilistic fix to a
	# variance complaint is not a fix. One pass over the eligible cells costs at most 80 O(1)
	# lookups against a field that is already built, so there is no reason to accept the miss.
	# Still bounded, still no `while`.
	if _patrol_route_gap < PATROL_MIN_ROUTE_GAP:
		for c in far:
			var g: int = int(gap.get(c, 0))
			if g > _patrol_route_gap:
				_patrol_route_gap = g
				start = c
	_patrol_pos = _cell_center(start)
	_patrol_start = _patrol_pos          # so a reopened instance puts it back (see open())
	_patrol_chasing = false
	_patrol_flow.clear()
	_patrol_flow_origin = Vector2i(-99, -99)
	_pick_patrol_target()


# ⚠️ The circuit avoids the player's likely route (2026-08-15). Measured across 40 seeds:
# a patroller wandering to uniformly-random cells dropped the escape rate from 34/40 to
# 25/40 on its own, BEFORE it ever gave chase — it was simply standing in the corridor the
# player had to walk. That is not a second threat, it is a roadblock, and it is the exact
# failure `_place_monster()` already guards against for the hunter.
#
# Off the artery, the patroller is something you MEET by choosing a greedy line or a wrong
# turn — which is the decision the braiding exists to offer.
func _pick_patrol_target() -> void:
	var options: Array[Vector2i] = []
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var c := Vector2i(col, row)
			if not _route_cells.has(c):
				options.append(c)
	if options.is_empty():
		_patrol_target = Vector2i(randi() % GRID_COLS, randi() % GRID_ROWS)
		return
	_patrol_target = options[randi() % options.size()]


func _tick_patroller(delta: float) -> void:
	var to_player: float = _patrol_pos.distance_to(_player_pos)
	# Hysteresis, or it flickers between states on the aggro boundary and jitters in place.
	if _patrol_chasing:
		if to_player > PATROL_CALM:
			_patrol_chasing = false
			_pick_patrol_target()
	elif to_player <= PATROL_AGGRO:
		_patrol_chasing = true

	var goal: Vector2i = _cell_at(_player_pos) if _patrol_chasing else _patrol_target
	if not _patrol_chasing and _cell_at(_patrol_pos) == _patrol_target:
		_pick_patrol_target()
		goal = _patrol_target

	# Same BFS-downhill steering the hunter uses — walking the ACTUAL corridors. A beeline
	# in a maze points into a wall most of the time (BACKLOG #14, measured).
	if goal != _patrol_flow_origin:
		_patrol_flow = _bfs_distances(goal)
		_patrol_flow_origin = goal
	var here: Vector2i = _cell_at(_patrol_pos)
	var best: Vector2i = here
	var best_d: int = int(_patrol_flow.get(here, 9999))
	for n in _open_neighbours(here):
		var nd: int = int(_patrol_flow.get(n, 9999))
		if nd < best_d:
			best_d = nd
			best = n
	var aim: Vector2 = _cell_center(best) if best != here else _player_pos
	var dir: Vector2 = (aim - _patrol_pos)
	if dir.length() < 0.01:
		return
	var speed: float = PATROL_SPEED * (1.05 if _patrol_chasing else 1.0)
	_patrol_pos = _resolve_wall_slide(
		_patrol_pos, _patrol_pos + dir.normalized() * speed * delta, ICON_HALF_EXTENT)


# ---------------------------------------------------------------- snares
#
# ⭐ Traps that HOLD you, never kill you (2026-08-15, user's choice).
#
# The danger is where being held leaves you, not the trap itself — the same logic the real
# beartrap uses (`beartrap.gd`: 15 panic and an escape, not a death). The maze already has
# one fail state; stacking a second on a minigame you can only retry by walking back across
# the House would be a lot of punishment for one wrong pixel.
#
# ⚠️ Placed OFF the start-to-target route. A snare on the only line is a tax every player
# pays; a snare beside it is a decision about how greedy a corner to cut. The braiding is
# what makes "beside it" exist at all.
const SNARE_COUNT := 5
const SNARE_RADIUS := 26.0
const SNARE_HOLD := 1.2
const SNARE_PANIC := 3.0

# ---- how a snare is DRAWN (2026-08-16; capture A2: *"the traps are not properly drawn —
# shall we make them like freezers with blue color and the snow label?"*)
#
# ⚠️ TWO separate defects, and the first one is the serious one.
#
# 1. IT WAS DRAWN SMALLER THAN IT WAS. `_rebuild_snare_visuals()` drew a disc of diameter
#    `SNARE_RADIUS * 1.6` = 41.6 px, i.e. radius 20.8 against a trigger radius of 26 — the
#    visible footprint understated the hazard by 20 % in radius and 36 % in AREA, so you
#    could be snared five pixels outside the only thing you had been shown. A trap you
#    cannot see the edge of is a dice roll, not a decision (SCARY.md §8.11).
# 2. IT WAS INVISIBLE. `Color(0.12, 0.05, 0.03)` — near-black brown — on sepia parchment
#    beside `Color(0.32, 0.22, 0.12)` walls: the same hue family as both. This is Issue 32
#    exactly, and the same fix applies: the colour has to come from geometry, because
#    `modulate` MULTIPLIES and no multiplier turns brown into saturated blue.
#
# So: a disc at the TRUE radius, in ice blue, over a dark rim that separates it from the
# parchment, with a frost star drawn from three ColorRects. Never a generated texture — at
# ~52 px a detailed image is invisible scribble (Issue 32 again).
#
# ⚠️ SNARE_RADIUS, SNARE_HOLD and SNARE_PANIC are UNTOUCHED. This is a legibility change and
# nothing here may move the difficulty.
const SNARE_FILL := Color(0.16, 0.60, 0.95, 0.95)
const SNARE_RIM := Color(0.02, 0.07, 0.14, 0.92)
const SNARE_GLYPH := Color(0.93, 0.98, 1.0, 0.95)
const SNARE_RIM_PAD := 5.0
const SNARE_GLYPH_BARS := 3
const SNARE_GLYPH_T := 3.0

# ---- how a FRAGMENT is drawn -------------------------------------------------------------
#
# Same two rules the snares had to be taught, applied on the way in rather than after a
# playtest photographed them:
#   1. THE DRAWN FOOTPRINT IS THE TRIGGER FOOTPRINT. The dark rim's radius is
#      FRAGMENT_PICKUP_RADIUS, asserted by tests/check_maze_traps.gd.
#   2. THE COLOUR COMES FROM GEOMETRY. Saturated green over a dark rim, on sepia parchment,
#      beside brown walls, ice-blue snares, gold mark, cyan player, red/amber monsters —
#      every one of those was checked as an RGB distance, not eyeballed (Issue 32).
# And the SILHOUETTE is a DIAMOND, not a disc: everything else on this board is round, so
# shape alone separates "pick this up" from "do not touch this" before colour is even read.
# Silhouette carries a prop; art does not (Issue 35).
const FRAGMENT_FILL := Color(0.24, 0.95, 0.42, 0.97)
const FRAGMENT_RIM := Color(0.01, 0.13, 0.04, 0.92)
const FRAGMENT_RIM_PAD := 4.0
const FRAGMENT_NOTCH := Color(0.02, 0.16, 0.05, 0.95)
# The mark, while it is still shut.
const TARGET_SEAL_COLOR := Color(0.05, 0.04, 0.06, 0.95)
const SEAL_BAR_T := 5.0
# ⚠️ Barely dimmed. The mark must still be FINDABLE while it is shut — see the seal in
# _build_ui() for the screenshot that forced this from 0.55.
const TARGET_LOCKED_TINT := Color(0.82, 0.82, 0.82)
const PIP_SIZE := 22.0
const PIP_GAP := 10.0

var _snares: Array[Vector2] = []
var _snares_initial: Array[Vector2] = []   # as generated, so a reopen re-arms the sprung ones
var _snare_hold: float = 0.0
var _snared_at := Vector2.ZERO
var _snare_nodes: Array[Control] = []
var _route_cells: Dictionary = {}   # cells on a shortest start->mark path


# Every cell the player is most likely to walk. The snares, the patroller's circuit and (since
# 2026-08-16) the patroller's START are all placed relative to it.
#
# ⚠️ IT IS THE WHOLE TOUR NOW, not the direct start->mark line. Measured, 200 seeds: with the
# two-stage objective and `_route_cells` still meaning the direct line, **39 % of all deaths
# were the PATROLLER** (69 of 176) against ~20 % before the redesign. The cause is that the
# two placements were pushed into the same space by construction — fragments are chosen for
# being OFF the direct line, and the patroller was banded for being OFF the direct line, so
# "off the direct line" became the one place the player was guaranteed to have to go and the
# patroller was guaranteed to be waiting. Avoiding the route only helps if "the route" means
# the route the player actually walks.
func _compute_route(dist: Dictionary) -> void:
	_route_cells.clear()
	var legs: Array[Vector2i] = _tour.duplicate()
	if legs.is_empty():
		legs.append(_target_cell)
	var from: Vector2i = _start_cell
	for leg_end in legs:
		var field: Dictionary = _bfs_cached(from)
		var walk: Vector2i = leg_end
		var guard := 0
		while walk != from and guard < GRID_COLS * GRID_ROWS:
			guard += 1
			_route_cells[walk] = true
			var here: int = int(field.get(walk, 0))
			for n in _open_neighbours(walk):
				if int(field.get(n, 9999)) == here - 1:
					walk = n
					break
		from = leg_end
	_route_cells[_start_cell] = true


func _place_snares(dist: Dictionary) -> void:
	_snares.clear()
	_snare_hold = 0.0
	var on_route: Dictionary = _route_cells

	var candidates: Array[Vector2i] = []
	for cell in dist.keys():
		if on_route.has(cell) or cell == _target_cell or cell == _start_cell:
			continue
		if int(dist[cell]) >= 2:
			candidates.append(cell)
	candidates.shuffle()
	for i in range(min(SNARE_COUNT, candidates.size())):
		_snares.append(_cell_center(candidates[i]))
	# ⚠️ Kept so a reopened instance re-arms every snare. Without this, closing and reopening
	# would be a way to walk a maze whose traps you had already spent — a free re-roll by
	# another route, which is the exact thing _instance_live exists to close.
	_snares_initial = _snares.duplicate()


func _check_snares(p: Node) -> void:
	if _snare_hold > 0.0:
		return
	for s in _snares:
		if s.distance_to(_player_pos) <= SNARE_RADIUS:
			_snares.erase(s)          # one-shot: a snare you already sprang is spent
			_snare_hold = SNARE_HOLD
			_snared_at = _player_pos
			if p and p.has_method("add_panic"):
				p.add_panic(SNARE_PANIC)
			_rebuild_snare_visuals()
			return


# ---------------------------------------------------------------- the fragments

# ⚠️ THE ONLY win predicate. `_process()` calls this, and so do all three test harnesses —
# nothing anywhere reaches the win by emitting `won`, which is a mistake this repo has shipped
# before (a test drove `cleared.emit()` and passed for weeks on an uncompletable level).
func _is_won() -> bool:
	return _fragments.is_empty() and _player_pos.distance_to(_target_pos) <= WIN_RADIUS


# No panic, no jolt, no fail state — see the FRAGMENT_* block for why this deliberately adds
# nothing to the panic economy.
func _check_fragments() -> void:
	if _fragments.is_empty():
		return
	for f in _fragments:
		if f.distance_to(_player_pos) <= FRAGMENT_PICKUP_RADIUS:
			_fragments.erase(f)
			_rebuild_fragment_visuals()
			_refresh_objective_ui()
			return


# ---------------------------------------------------------------- monster AI

func _tick_monster(delta: float) -> void:
	var dir := _pursuit_direction()
	if dir.length() > 0.01:
		var candidate: Vector2 = _monster_pos + dir * MONSTER_SPEED * delta
		# Kept as a safety net only. With corridor following the monster should never
		# be driving into a wall, but a diagonal cut across a junction can still clip a
		# corner, and sliding is nicer there than stopping dead.
		_monster_pos = _resolve_wall_slide(_monster_pos, candidate, ICON_HALF_EXTENT)


# Steer along the maze's actual corridors instead of straight at the player.
#
# Recomputes the BFS distance field from the PLAYER's cell whenever the player changes
# cell (not every frame — 80 cells is cheap, but there is no reason to burn it), then
# walks downhill: of the neighbours reachable from the monster's own cell, head for the
# one strictly closer to the player. Aim at that cell's CENTRE, which keeps the icon off
# the walls through corners without any special-casing.
#
# In the player's own cell, fall back to the beeline — that is the one place where
# straight-line and corridor distance agree, and it is what makes the final approach
# feel like a lunge rather than a grid step.
func _pursuit_direction() -> Vector2:
	var monster_cell := _cell_at(_monster_pos)
	var player_cell := _cell_at(_player_pos)
	if monster_cell == player_cell:
		return (_player_pos - _monster_pos).normalized()

	if player_cell != _flow_origin or _flow.is_empty():
		_flow_origin = player_cell
		_flow = _bfs_distances(player_cell)

	if not _flow.has(monster_cell):
		# Off the grid (shouldn't happen) — beeline rather than freeze.
		return (_player_pos - _monster_pos).normalized()

	var best_cell := monster_cell
	var best_dist: int = _flow[monster_cell]
	for step in _open_neighbours(monster_cell):
		if _flow.has(step) and int(_flow[step]) < best_dist:
			best_dist = int(_flow[step])
			best_cell = step
	if best_cell == monster_cell:
		return (_player_pos - _monster_pos).normalized()
	return (_cell_center(best_cell) - _monster_pos).normalized()


func _cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(pos.x / CELL_SIZE), 0, GRID_COLS - 1),
		clampi(int(pos.y / CELL_SIZE), 0, GRID_ROWS - 1))


# Neighbouring cells this one is NOT walled off from. Mirrors the wall bookkeeping in
# _bfs_distances(), so the monster can only use openings the player can also use.
func _open_neighbours(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c: Dictionary = _cells[_idx(cell)]
	if not c["n"]:
		out.append(cell + Vector2i(0, -1))
	if not c["s"]:
		out.append(cell + Vector2i(0, 1))
	if not c["e"]:
		out.append(cell + Vector2i(1, 0))
	if not c["w"]:
		out.append(cell + Vector2i(-1, 0))
	return out


# ---------------------------------------------------------------- collision

func _resolve_wall_slide(from: Vector2, to: Vector2, half_extent: float) -> Vector2:
	var pos := from
	var try_x := Vector2(to.x, pos.y)
	if not _rect_hits_wall(try_x, half_extent):
		pos.x = to.x
	var try_y := Vector2(pos.x, to.y)
	if not _rect_hits_wall(try_y, half_extent):
		pos.y = to.y
	return pos


func _rect_hits_wall(center: Vector2, half_extent: float) -> bool:
	var r := Rect2(center - Vector2(half_extent, half_extent), Vector2(half_extent, half_extent) * 2.0)
	for wr in _wall_rects:
		if r.intersects(wr):
			return true
	return false


# ---------------------------------------------------------------- maze generation

func _idx(cell: Vector2i) -> int:
	return cell.y * GRID_COLS + cell.x


func _generate_maze() -> void:
	_bfs_cache.clear()
	_cells.clear()
	for i in range(GRID_COLS * GRID_ROWS):
		_cells.append({"n": true, "e": true, "s": true, "w": true, "visited": false})

	var stack: Array[Vector2i] = []
	var origin := Vector2i(0, 0)
	_cells[_idx(origin)]["visited"] = true
	stack.append(origin)
	while not stack.is_empty():
		var cur: Vector2i = stack[-1]
		var neighbors := _unvisited_neighbors(cur)
		if neighbors.is_empty():
			stack.pop_back()
			continue
		var next: Vector2i = neighbors[randi() % neighbors.size()]
		_remove_wall(cur, next)
		_cells[_idx(next)]["visited"] = true
		stack.append(next)

	_braid()

	_start_cell = Vector2i(0, GRID_ROWS / 2)
	var dist := _bfs_distances(_start_cell)

	_target_cell = _start_cell
	var max_d := -1
	for cell in dist.keys():
		if dist[cell] > max_d:
			max_d = dist[cell]
			_target_cell = cell

	_wall_rects.clear()
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var cell: Dictionary = _cells[_idx(Vector2i(col, row))]
			var cx: float = col * CELL_SIZE
			var cy: float = row * CELL_SIZE
			if cell["n"]:
				_wall_rects.append(Rect2(cx - WALL_THICKNESS / 2.0, cy - WALL_THICKNESS / 2.0,
					CELL_SIZE + WALL_THICKNESS, WALL_THICKNESS))
			if cell["w"]:
				_wall_rects.append(Rect2(cx - WALL_THICKNESS / 2.0, cy - WALL_THICKNESS / 2.0,
					WALL_THICKNESS, CELL_SIZE + WALL_THICKNESS))
			if row == GRID_ROWS - 1 and cell["s"]:
				_wall_rects.append(Rect2(cx - WALL_THICKNESS / 2.0, cy + CELL_SIZE - WALL_THICKNESS / 2.0,
					CELL_SIZE + WALL_THICKNESS, WALL_THICKNESS))
			if col == GRID_COLS - 1 and cell["e"]:
				_wall_rects.append(Rect2(cx + CELL_SIZE - WALL_THICKNESS / 2.0, cy - WALL_THICKNESS / 2.0,
					WALL_THICKNESS, CELL_SIZE + WALL_THICKNESS))

	# ⚠️ ORDER MATTERS, and every step below reads something the step above produced:
	#   fragments need the DIRECT route (they are placed off it) and produce `_tour`;
	#   `_compute_route` is unchanged and still describes the direct start->mark line;
	#   the monster must not block the first step toward `_tour[0]`, which is a FRAGMENT now,
	#   not the mark; the patroller and the snares are both placed relative to `_route_cells`.
	_place_fragments(dist)
	_compute_route(dist)
	_place_monster(dist)
	_place_patroller(dist)
	_place_snares(dist)


# ⭐ BRAID THE MAZE — knock extra walls out so it has LOOPS (2026-08-15).
#
# User report: "make more space so that you can actually bypass the monster when it is
# running towards you." In a randomized-DFS maze there is exactly ONE route between any two
# cells, so a monster coming down a corridor at you cannot be passed — not because it is
# fast, but because the topology forbids it. Widening corridors or enlarging the grid does
# not fix that; only cycles do.
#
# ⚠️ This project has already paid to learn it once. `dungeon_gen.gd` adds `ceil(0.25 * K)`
# extra edges to its spanning tree with the note: "The extra edges are NOT optional. A
# spanning tree is a perfect maze, and in one a corridor-following pursuer is unbeatable.
# `maze_chase_ui.gd` already cost this project 12 instant deaths in 40 to learn that." That
# was about monster PLACEMENT; this is the same lesson applied to the maze itself.
#
# Dead ends are the target: removing a wall from a dead end is what turns a trap into a
# through-route, which is exactly the space the player was asking for.
const BRAID_FRACTION := 0.55   # share of dead ends opened into loops

func _braid() -> void:
	var dead_ends: Array[Vector2i] = []
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var c := Vector2i(col, row)
			if _open_neighbours(c).size() <= 1:
				dead_ends.append(c)
	dead_ends.shuffle()
	var quota := int(ceil(dead_ends.size() * BRAID_FRACTION))
	for i in range(min(quota, dead_ends.size())):
		var cell: Vector2i = dead_ends[i]
		# Candidate walls that lead to a real neighbour and are still closed.
		var options: Array[Vector2i] = []
		var open_now: Array[Vector2i] = _open_neighbours(cell)
		for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var n: Vector2i = cell + d
			if n.x < 0 or n.y < 0 or n.x >= GRID_COLS or n.y >= GRID_ROWS:
				continue
			if not open_now.has(n):
				options.append(n)
		if options.is_empty():
			continue
		_remove_wall(cell, options[randi() % options.size()])


func _unvisited_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var n: Vector2i = cell + d
		if n.x >= 0 and n.x < GRID_COLS and n.y >= 0 and n.y < GRID_ROWS:
			if not _cells[_idx(n)]["visited"]:
				result.append(n)
	return result


func _remove_wall(a: Vector2i, b: Vector2i) -> void:
	var d := b - a
	if d == Vector2i(0, -1):
		_cells[_idx(a)]["n"] = false
		_cells[_idx(b)]["s"] = false
	elif d == Vector2i(0, 1):
		_cells[_idx(a)]["s"] = false
		_cells[_idx(b)]["n"] = false
	elif d == Vector2i(1, 0):
		_cells[_idx(a)]["e"] = false
		_cells[_idx(b)]["w"] = false
	elif d == Vector2i(-1, 0):
		_cells[_idx(a)]["w"] = false
		_cells[_idx(b)]["e"] = false


func _bfs_distances(start: Vector2i) -> Dictionary:
	var dist := {start: 0}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var cd: int = dist[cur]
		var cell: Dictionary = _cells[_idx(cur)]
		var moves: Array[Vector2i] = []
		if not cell["n"]:
			moves.append(Vector2i(0, -1))
		if not cell["s"]:
			moves.append(Vector2i(0, 1))
		if not cell["e"]:
			moves.append(Vector2i(1, 0))
		if not cell["w"]:
			moves.append(Vector2i(-1, 0))
		for d in moves:
			var n: Vector2i = cur + d
			if not dist.has(n):
				dist[n] = cd + 1
				queue.append(n)
	return dist


# A memo over _bfs_distances for one generation. Placing N fragments with a
# validate-and-reject loop asks for the same distance fields dozens of times; 80 cells is
# cheap but there is no reason to pay for it twice. Cleared at the top of _generate_maze().
func _bfs_cached(from: Vector2i) -> Dictionary:
	if not _bfs_cache.has(from):
		_bfs_cache[from] = _bfs_distances(from)
	return _bfs_cache[from]


# ---------------------------------------------------------------- fragment placement

# The corridor length of a tour that visits `order` in the given order and ends at the mark.
# ⚠️ The order is NOT re-optimised here. See `_sample_fragments()` — the order is the whole
# safety property of this feature, and a "better" TSP order would be a lethal one.
func _order_tour(order: Array[Vector2i]) -> Dictionary:
	var full: Array[Vector2i] = order.duplicate()
	full.append(_target_cell)
	var cur: Vector2i = _start_cell
	var total: int = 0
	for w in full:
		total += int(_bfs_cached(cur).get(w, 1 << 20))
		cur = w
	return {"order": full, "length": total}


# One candidate SET, in the order the player will walk it.
#
# ⭐⭐ THE TOUR IS MONOTONE OUTWARD, AND THAT IS THE WHOLE DIFFERENCE BETWEEN THIS FEATURE
# WORKING AND NOT WORKING. Fragment k is drawn from a band around `k/(N+1)` of the way along
# the route, so every waypoint is FURTHER from the spawn than the last. The player walks the
# route they always walked, with N lateral excursions off it — never back past the spawn.
#
# ⚠️ The first version placed fragments anywhere off the direct line and ordered them
# nearest-neighbour. Measured, 200 seeds: **10/200 escapes, median catch at 5.6 s with a
# median of ONE fragment collected**, i.e. runs died almost immediately rather than being worn
# down. The cause is geometric and it is worth writing down, because it is not obvious and it
# will recur the next time anyone lengthens an objective in this minigame:
#
#   * The hunter spawns ONE CELL from the player and pursues along the actual corridors,
#     forever, at 172 against a player who tops out at 240. The only thing that keeps you
#     alive is `MONSTER_START_DELAY` — 3 s during which you move and it does not, worth about
#     six cells of lead — plus the fact that in the one-stage design the mark was the
#     FARTHEST cell in the maze, so "walk to the objective" and "walk away from the hunter"
#     were the same instruction for the whole run.
#   * Nearest-neighbour ordering makes the first waypoint the fragment CLOSEST to the start —
#     which is to say, closest to where the hunter is standing. The head start is spent
#     walking a few cells and coming back. At t = 3 s the hunter begins moving and is already
#     on top of you.
#   * And every subsequent leg could point backwards. A persistent corridor-following chaser
#     makes turning round fatal by construction; the margin over a whole run is a few cells,
#     so there is no slack to spend on doubling back.
#
# So: detours, yes — backtracking, no. The user asked for "harder and more packed with
# actions"; walking back into a chaser is not an action, it is a coin flip, and this project
# has a standing rule against those (SCARY.md §8.11).
func _sample_fragments(dist: Dictionary, min_detour: int, min_sep: int, widen: float) -> Array[Vector2i]:
	var to_target: Dictionary = _bfs_cached(_target_cell)
	var route_len: int = int(dist.get(_target_cell, 0))
	var chosen: Array[Vector2i] = []
	var slots: int = fragment_count + 1
	for k in range(1, fragment_count + 1):
		var centre: float = float(route_len) * float(k) / float(slots)
		var half: float = maxf(float(route_len) * (SLOT_HALF_WIDTH + widen), 2.0)
		var pool: Array[Vector2i] = []
		for row in range(GRID_ROWS):
			for col in range(GRID_COLS):
				var c := Vector2i(col, row)
				if c == _start_cell or c == _target_cell or chosen.has(c):
					continue
				var d_start: int = int(dist.get(c, 1 << 20))
				if absf(float(d_start) - centre) > half:
					continue
				var detour: int = d_start + int(to_target.get(c, 1 << 20)) - route_len
				if detour < min_detour:
					continue
				# ⚠️ NEVER IN A DEAD END. `_braid()` opens only 55 % of them, so the rest are
				# real culs-de-sac — and a mandatory objective at the bottom of one is a trap,
				# not a detour: you walk in, the hunter follows you in, and there is no second
				# exit. That is the same topological argument the braiding itself was built on
				# (`dungeon_gen.gd`: "in a perfect maze a corridor-following pursuer is
				# unbeatable"), applied to the one cell the player is now REQUIRED to stand on.
				if _open_neighbours(c).size() < 2:
					continue
				var ok := true
				for other in chosen:
					if int(_bfs_cached(other).get(c, 1 << 20)) < min_sep:
						ok = false
						break
				if ok:
					pool.append(c)
		if pool.is_empty():
			return chosen        # short — the caller relaxes and tries again
		chosen.append(pool[randi() % pool.size()])
	return chosen


# ⭐ VALIDATE AND REJECT INTO A TOUR-LENGTH BAND (2026-08-16) — capture A1's *"the difficulty
# level is very random"*, answered at the level of the objective rather than the layout.
#
# The standard technique: generate, measure, reject, retry, and after a BOUNDED number of
# attempts accept the best candidate rather than looping forever (Cogmind runs exactly this
# loop on every map; Spelunky guarantees its solution path after generation rather than
# hoping for one). ⚠️ The bound is what stops a pathological maze hanging the game inside a
# PAUSED overlay, where a hang is indistinguishable from a crash.
#
# Tour length is banded rather than direct-route length because tour length is what run TIME
# is made of, and because banding the direct route was measured (backlog §7 P4) to be a
# difficulty *reduction* dressed as a variance fix.
func _place_fragments(dist: Dictionary) -> void:
	_fragment_cells.clear()
	_fragments.clear()
	_tour.clear()
	_tour_length = 0

	var band: Vector2i = TOUR_BAND.get(fragment_count, Vector2i(0, 1 << 20))
	var best_pick: Array[Vector2i] = []
	var best_order: Array[Vector2i] = []
	var best_len: int = 0
	var best_err: int = 1 << 30

	# ⚠️ The relaxation ladder advances ONLY on genuine infeasibility — when the constraints
	# could not yield `fragment_count` cells at all — never on a schedule. A schedule would
	# loosen the constraints on later attempts, which produces SHORTER tours, which is the
	# wrong direction whenever the reason for retrying was that the tour was too short.
	var relax: int = 0
	for _attempt in range(FRAGMENT_PLACE_ATTEMPTS):
		var base_detour: int = min_detour_override if min_detour_override >= 0 else FRAGMENT_MIN_DETOUR
		# ⚠️ The ladder never relaxes below 1 on the shipped path. A fragment worth ZERO extra
		# cells lies on a shortest route to the mark and is therefore collected for free — the
		# two-stage objective silently becoming one-stage, which `check_maze_gen.gd` asserts
		# against. Only the probe's explicit sweep may go to 0, and only to measure it.
		var floor_detour: int = 0 if min_detour_override >= 0 else 1
		var min_detour: int = maxi(floor_detour, base_detour - relax * 2)
		var min_sep: int = maxi(2, FRAGMENT_MIN_SEPARATION - relax)
		var pick: Array[Vector2i] = _sample_fragments(dist, min_detour, min_sep, float(relax) * 0.08)
		if pick.size() < fragment_count:
			relax += 1
			continue
		var t: Dictionary = _order_tour(pick)
		var length: int = int(t["length"])
		var err: int = 0
		if length < band.x:
			err = band.x - length
		elif length > band.y:
			err = length - band.y
		if err < best_err:
			best_err = err
			best_pick = pick
			# ⚠️ `.assign()`, not `=`: `t["order"]` comes back through a Dictionary as a
			# Variant, and assigning a Variant straight into a TYPED array is a runtime check
			# that can only fail at play time. `.assign()` is the documented safe path.
			best_order.assign(t["order"])
			best_len = length
		if err == 0:
			break

	if best_pick.is_empty():
		# Nothing satisfied even the loosest ladder rung (a maze this small should never do
		# this, but a two-stage objective that silently becomes one-stage is exactly the kind
		# of vacuous state this repo has shipped before, so it is handled explicitly).
		# ⚠️ `.append()` rather than an array literal: `_tour` and `_fragments_initial` are
		# TYPED arrays, and assigning an untyped literal to one is a runtime type error, not
		# a compile-time one — it would fail only on the rare seed that reaches this branch.
		_tour.append(_target_cell)
		_fragments_initial.clear()
		return

	_fragment_cells = best_pick
	_tour = best_order
	_tour_length = best_len
	for c in _fragment_cells:
		_fragments.append(_cell_center(c))
	_fragments_initial = _fragments.duplicate()


# Multi-source BFS out from every route cell: "how many corridor steps is this cell off the
# player's artery". One pass for the whole grid, so the patroller's placement loop below can
# ask the question 20 times for free.
func _route_gap_field() -> Dictionary:
	var d: Dictionary = {}
	var queue: Array[Vector2i] = []
	for c in _route_cells.keys():
		d[c] = 0
		queue.append(c)
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var cd: int = int(d[cur])
		for n in _open_neighbours(cur):
			if not d.has(n):
				d[n] = cd + 1
				queue.append(n)
	return d


# Playtest redesign: the monster now starts right next to the player (not
# roaming elsewhere in the maze) and holds still for MONSTER_START_DELAY before
# it begins hunting — "catches you if you get stuck," not "avoid its territory."
# Prefer a cell exactly 1 step from start; widen the search if the maze's
# branching happens to leave none (rare but possible in a small maze).
func _place_monster(dist: Dictionary) -> void:
	# ⚠️ Never on the FIRST STEP of the route to the target, if that can be avoided.
	# The maze is a spanning tree, so there is exactly ONE route from start to target
	# and exactly one neighbour of the start cell that lies on it. Parking the monster
	# there turns a 1.6-cell-wide corridor into a roadblock the player cannot go round
	# — and it went unnoticed for as long as the monster jammed itself on walls and
	# drifted off harmlessly. With corridor following (BACKLOG #14) it stands its
	# ground, and a measured 12 of 40 seeds became a walk-straight-into-it death.
	# Adjacency is the point of this placement; sitting in the doorway is not.
	#
	# ⚠️ 2026-08-16: the cell to protect is the first step toward **`_tour[0]`**, not toward
	# the mark. With the two-stage objective the player's opening move is toward the nearest
	# FRAGMENT, and the mark is inert until the last one is in hand — so guarding the route to
	# the mark would have guarded a corridor nobody walks for the first thirty seconds while
	# leaving the one they do walk unguarded. Same rule, correct destination.
	var first_goal: Vector2i = _tour[0] if not _tour.is_empty() else _target_cell
	var to_target := _bfs_distances(first_goal)
	var start_to_target: int = int(to_target.get(_start_cell, 1 << 30))

	var off_path: Array[Vector2i] = []
	var on_path: Array[Vector2i] = []
	for cell in dist.keys():
		if cell == _target_cell or cell == first_goal or dist[cell] != 1:
			continue
		if int(to_target.get(cell, 1 << 30)) < start_to_target:
			on_path.append(cell)
		else:
			off_path.append(cell)

	var candidates := off_path
	if candidates.is_empty():
		candidates = on_path          # start is a dead end — nowhere else to stand
	if candidates.is_empty():
		for cell in dist.keys():
			if cell != _target_cell and dist[cell] >= 1 and dist[cell] <= 2:
				candidates.append(cell)
	var monster_cell: Vector2i = candidates[randi() % candidates.size()] if not candidates.is_empty() else _start_cell
	_monster_pos = _cell_center(monster_cell)
	_monster_start = _monster_pos        # so a reopened instance puts it back (see open())


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL_SIZE + CELL_SIZE / 2.0, cell.y * CELL_SIZE + CELL_SIZE / 2.0)


# ⚠️ This restores the ACTORS as well as the player, because `open()` no longer regenerates
# the maze on a reopen (see _instance_live). Everything here is idempotent against a maze that
# was just generated — _place_monster/_place_patroller/_place_snares set the same three
# `*_start` values this reads back — so `_generate_maze()` followed by `_reset_positions()`,
# which is what check_maze_chase.gd and check_maze_gen.gd do, is unchanged.
func _reset_positions() -> void:
	_player_pos = _cell_center(_start_cell)
	_target_pos = _cell_center(_target_cell)
	_monster_pos = _monster_start
	_patrol_pos = _patrol_start
	_patrol_chasing = false
	_patrol_flow.clear()
	_patrol_flow_origin = Vector2i(-99, -99)
	if not _cells.is_empty():
		_pick_patrol_target()
	_snares = _snares_initial.duplicate()
	# ⚠️ The fragments RE-ARM on a reopen, exactly like the snares, and this is deliberate:
	# ESC must not become a checkpoint. `_instance_live` already makes closing the map keep
	# the same maze; letting collected fragments survive the close would turn "put the map
	# down" into a free reset of the hunter's position with your progress banked, which is
	# the opposite of what killing the re-roll was for. A catch loses them too — there is no
	# partial-progress carry-over anywhere in this minigame.
	_fragments = _fragments_initial.duplicate()
	_monster_start_timer = MONSTER_START_DELAY
	_flow.clear()
	_flow_origin = Vector2i(-1, -1)
	_snare_hold = 0.0


# ---------------------------------------------------------------- UI construction

# Skeleton avoids Issue 4 (PRESET_CENTER anchors a node's top-left corner to
# screen centre, not the node's own centre): Control full-rect -> ColorRect
# backdrop + CenterContainer full-rect siblings -> fixed-size playfield as the
# CenterContainer's child. Anything that MOVES (icons) is positioned via raw
# .position on the playfield, never anchors.
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.75)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_playfield = Control.new()
	_playfield.custom_minimum_size = PLAYFIELD_SIZE
	_playfield.size = PLAYFIELD_SIZE
	_playfield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_playfield)

	var bg_path := TEX + "house_map_maze_bg.png"
	if ResourceLoader.exists(bg_path):
		var bg := TextureRect.new()
		bg.texture = load(bg_path)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.size = PLAYFIELD_SIZE
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_playfield.add_child(bg)
	else:
		var bg_fallback := ColorRect.new()
		bg_fallback.color = Color(0.78, 0.7, 0.55)
		bg_fallback.size = PLAYFIELD_SIZE
		bg_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_playfield.add_child(bg_fallback)

	# Own container for the wall rects, added ONCE here — _rebuild_wall_visuals()
	# only ever adds/removes children INSIDE this container, never directly to
	# _playfield. Control nodes paint in child order (later = on top); walls used
	# to be rebuilt (and re-added) on every open(), landing AFTER the icons below
	# and painting over them every single attempt — the confirmed cause of the
	# target being completely invisible in playtest.
	_walls_container = Control.new()
	_walls_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_playfield.add_child(_walls_container)

	# ⚠️ The caption goes on _root, NOT on `center`. A CenterContainer centres EVERY
	# child independently and overwrites its anchors/offsets/position during layout,
	# so a Label added here used to have both its PRESET_CENTER_TOP and its
	# position.y = -48 silently discarded — it landed stacked dead-centre ON the
	# parchment, over the maze (playtest capture #3). _root is a plain Control, so
	# presets survive. Anchored off the vertical centre by half the playfield so it
	# sits just above the map at any viewport size.
	# ⚠️ THE OFFSETS ARE MEASURED FROM THE MAP'S EDGE, NOT FROM THE SCREEN CENTRE. `_root` is
	# anchored at 0.5, and the playfield is 768 px tall, so its top edge is already 384 px above
	# that anchor — a bare `-46` puts the caption INSIDE the maze, dead centre, over the
	# parchment. That is playtest capture #3 verbatim, and it was reintroduced for exactly one
	# screenshot when this label was refactored into `_banner_label()` and the
	# `-PLAYFIELD_SIZE.y / 2.0` term was dropped. Caught by `screenshot_maze_ui.gd`; no
	# assertion in this project can see it.
	_caption = _banner_label(-PLAYFIELD_SIZE.y / 2.0 - 46.0, -PLAYFIELD_SIZE.y / 2.0 - 12.0, 24)
	_caption.text = "Drag to the mark. Don't get caught."
	_root.add_child(_caption)

	# The objective readout, BELOW the map so it cannot be confused with the caption above it.
	# ⚠️ Text, not art: at the ~28-42 px these overlay marks occupy, a drawn glyph is invisible
	# scribble and `modulate` cannot rescue it (Issue 32). An outlined 26 px label IS the fix
	# that Issue 32 landed on for the caption, so this follows it rather than re-litigating it.
	_counter_label = _banner_label(PLAYFIELD_SIZE.y / 2.0 + 10.0, PLAYFIELD_SIZE.y / 2.0 + 44.0, 26)
	_counter_label.text = ""
	_root.add_child(_counter_label)

	_target_icon = _make_icon(TEX + "house_map_target_icon.png", Color(1.0, 0.85, 0.25))
	# The seal — a dark X struck ACROSS the mark, not a lid over it.
	#
	# ⚠️ It was a filled disc at 78 % alpha over an icon dimmed to 0.55, and the screenshot is
	# unambiguous: the mark rendered as a near-black blot on sepia parchment, indistinguishable
	# from the map's own ink stains. The player could not see where they were going. A
	# destination you cannot find is a worse problem than a destination you cannot use yet —
	# "shut" has to be legible AS the mark, which means striking it through rather than
	# covering it. Same rule the snares and fragments already follow: geometry, real contrast,
	# and a silhouette that says what the state is.
	_target_seal = Control.new()
	_target_seal.name = "TargetSeal"
	_target_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_seal.size = Vector2(ICON_DISPLAY_SIZE, ICON_DISPLAY_SIZE)
	for i in 2:
		var bar := ColorRect.new()
		bar.color = TARGET_SEAL_COLOR
		bar.size = Vector2(ICON_HALF_EXTENT * 2.2, SEAL_BAR_T)
		bar.pivot_offset = bar.size / 2.0
		bar.position = Vector2(ICON_DISPLAY_SIZE, ICON_DISPLAY_SIZE) / 2.0 - bar.size / 2.0
		bar.rotation = deg_to_rad(45.0 + 90.0 * float(i))
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_target_seal.add_child(bar)
	_target_icon.add_child(_target_seal)
	_player_icon = _make_icon(TEX + "house_map_player_icon.png", Color(0.45, 0.85, 1.0))
	_monster_icon = _make_icon(TEX + "house_map_monster_icon.png", Color(1.0, 0.25, 0.18))
	# The patroller wears the same art in a different colour — it must read as "another one
	# of those", not as a new species, because the thing the player has to learn is its
	# BEHAVIOUR. Amber against the hunter's red.
	_patrol_icon = _make_icon(TEX + "house_map_monster_icon.png", Color(1.0, 0.60, 0.12))


# The project's universal legibility trick, same as ScreenText._outline(): this is
# the ONLY overlay text in the game that had neither an outline, a shadow, nor a
# dark panel behind it — over cream parchment that reads as no text at all.
func _outline(lbl: Label, size: int) -> void:
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", size)


# A flat rounded disc. Godot has no circle primitive for Control nodes, but a Panel
# with a StyleBoxFlat whose corner radius is half its size is one.
func _disc(diameter: float, color: Color) -> Panel:
	var p := _circle(diameter, color)
	p.position = Vector2(ICON_DISPLAY_SIZE - diameter, ICON_DISPLAY_SIZE - diameter) / 2.0
	return p


# The same rounded Panel with no opinion about where it goes — the snares centre theirs on a
# different box size, and a wrong ICON_DISPLAY_SIZE offset there is a silent 16 px error.
func _circle(diameter: float, color: Color) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size = Vector2(diameter, diameter)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	var r := int(diameter / 2.0)
	sb.corner_radius_top_left = r
	sb.corner_radius_top_right = r
	sb.corner_radius_bottom_left = r
	sb.corner_radius_bottom_right = r
	p.add_theme_stylebox_override("panel", sb)
	return p


# Three layers, because the source art alone cannot carry this. Each icon PNG is a
# 1024x1024 canvas whose visible ink fills only ~30-40% of it, so at ICON_DISPLAY_SIZE
# the actual mark is ~28 px of mid-brown (#6b4a2a-#8a5c30) sitting on cream parchment,
# beside wall rects of Color(0.32,0.22,0.12) — same hue family as both. Tinting via
# `modulate` cannot fix it either: modulate MULTIPLIES, and no multiplier turns brown
# into saturated blue. So the colour comes from a solid disc underneath and the art
# rides on top as dark detail:
#   1. dark halo   — separates the marker from the parchment
#   2. bright disc — the identity colour, sized to ICON_HALF_EXTENT so the marker is
#                    honest about its own hitbox (the 64 px art visually engulfs the
#                    player long before CATCH_RADIUS fires)
#   3. the ink     — modulated near-black so it reads as line work over the disc
func _make_icon(tex_path: String, marker_color: Color) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(ICON_DISPLAY_SIZE, ICON_DISPLAY_SIZE)

	holder.add_child(_disc(ICON_HALF_EXTENT * 2.0 + 8.0, Color(0.04, 0.03, 0.02, 0.9)))
	holder.add_child(_disc(ICON_HALF_EXTENT * 2.0, marker_color))

	if ResourceLoader.exists(tex_path):
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size = Vector2(ICON_DISPLAY_SIZE, ICON_DISPLAY_SIZE)
		icon.texture = load(tex_path)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.modulate = Color(0.16, 0.11, 0.06)
		holder.add_child(icon)

	_playfield.add_child(holder)
	return holder


# A full-width centred label pinned a fixed distance above or below the map, in the one way
# that survives layout: on `_root` (a plain Control) with anchors, never inside the
# CenterContainer — which overwrites every child's anchors and offsets and is what put the
# original caption stacked on top of the parchment (playtest capture #3).
func _banner_label(top: float, bottom: float, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	_outline(lbl, 6)
	lbl.anchor_left = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_top = 0.5
	lbl.anchor_bottom = 0.5
	lbl.offset_left = 0.0
	lbl.offset_right = 0.0
	lbl.offset_top = top
	lbl.offset_bottom = bottom
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _rebuild_fragment_visuals() -> void:
	# ⚠️ Null-guarded: check_maze_gen.gd / check_maze_chase.gd / probe_maze_variance.gd all
	# instantiate this script OUTSIDE the tree, so `_ready()` never runs and there is no UI to
	# draw into. They still drive the real pickup path, which calls this.
	for n in _fragment_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_fragment_nodes.clear()
	if _walls_container == null:
		return
	for f in _fragments:
		var mark := _make_fragment_visual(f)
		# Into the WALLS container, like the snares — adding to the playfield would place them
		# after the icons in the draw order and paint over them.
		_walls_container.add_child(mark)
		_fragment_nodes.append(mark)


# Dark rim disc AT the pickup radius, a green diamond inside it, a dark notch through the
# middle so it never reads as a solid blob at a glance.
func _make_fragment_visual(centre: Vector2) -> Control:
	var holder := Control.new()
	holder.name = "Fragment"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(FRAGMENT_PICKUP_RADIUS, FRAGMENT_PICKUP_RADIUS) * 2.0
	holder.position = centre - Vector2(FRAGMENT_PICKUP_RADIUS, FRAGMENT_PICKUP_RADIUS)
	var mid := Vector2(FRAGMENT_PICKUP_RADIUS, FRAGMENT_PICKUP_RADIUS)

	# ⚠️ THE ASSERTED ONE — its radius IS the pickup radius.
	var rim := _circle((FRAGMENT_PICKUP_RADIUS + FRAGMENT_RIM_PAD) * 2.0, FRAGMENT_RIM)
	rim.name = "FragRim"
	rim.position = mid - rim.size / 2.0
	holder.add_child(rim)

	# A square rotated 45° is a diamond whose half-DIAGONAL is the pickup radius, so the
	# drawn shape touches the trigger circle rather than floating inside it.
	var side: float = FRAGMENT_PICKUP_RADIUS * sqrt(2.0)
	var fill := ColorRect.new()
	fill.name = "FragFill"
	fill.color = FRAGMENT_FILL
	fill.size = Vector2(side, side)
	fill.pivot_offset = fill.size / 2.0
	fill.position = mid - fill.size / 2.0
	fill.rotation = deg_to_rad(45.0)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fill)

	var notch := ColorRect.new()
	notch.name = "FragNotch"
	notch.color = FRAGMENT_NOTCH
	notch.size = Vector2(side * 0.62, 4.0)
	notch.pivot_offset = notch.size / 2.0
	notch.position = mid - notch.size / 2.0
	notch.rotation = deg_to_rad(45.0)
	notch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(notch)
	return holder


# The two-stage objective's whole readout: the count, the pips, the state of the mark and the
# caption. Idempotent, null-guarded, and called on open and on every pickup.
func _refresh_objective_ui() -> void:
	var total: int = _fragments_initial.size()
	var left: int = _fragments.size()
	var got: int = total - left

	if _counter_label:
		if total == 0:
			_counter_label.text = ""
		elif left > 0:
			# ⚠️ The counter stays "n / N" even at N=1. It is the only thing on screen that says
			# the mark is gated at all, and "0 / 1" states the rule where "find the piece"
			# merely describes a task — the player has to understand that touching the mark
			# early does nothing, or the seal reads as a bug.
			_counter_label.text = "FRAGMENTS  %d / %d" % [got, total]
			_counter_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
		else:
			_counter_label.text = ("ALL %d RECOVERED — REACH THE MARK" % total) if total > 1 \
				else "PIECE RECOVERED — REACH THE MARK"
			_counter_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	if _caption:
		if total == 0:
			_caption.text = "Drag to the mark. Don't get caught."
		elif left > 0:
			_caption.text = ("The map is torn. Collect every piece, then reach the mark.") \
				if total > 1 else "The map is torn. Find the missing piece, then reach the mark."
		else:
			_caption.text = "The mark is open. Get out."

	# The mark is INERT until the last fragment is in hand, and it has to look it — a target
	# you can touch with no effect reads as a bug, not as a rule.
	if _target_seal:
		_target_seal.visible = left > 0
	if _target_icon:
		_target_icon.modulate = TARGET_LOCKED_TINT if left > 0 else Color.WHITE

	_rebuild_pips(total, got)


# Geometry, not text: a row of discs under the counter, filled as they are recovered. The
# label already carries the number; these carry it at a glance, without a read.
func _rebuild_pips(total: int, got: int) -> void:
	if _root == null:
		return
	if _pip_nodes.size() != total:
		for p in _pip_nodes:
			if is_instance_valid(p):
				p.queue_free()
		_pip_nodes.clear()
		for i in range(total):
			var pip := _circle(PIP_SIZE, FRAGMENT_RIM)
			pip.name = "FragPip%d" % i
			# Anchored to the viewport centre so no layout pass is needed to place it —
			# offsets from a 0.5/0.5 anchor are absolute pixels from the middle of the screen.
			var span: float = float(total) * PIP_SIZE + float(maxi(total - 1, 0)) * PIP_GAP
			var x: float = -span / 2.0 + float(i) * (PIP_SIZE + PIP_GAP)
			pip.anchor_left = 0.5
			pip.anchor_right = 0.5
			pip.anchor_top = 0.5
			pip.anchor_bottom = 0.5
			pip.offset_left = x
			pip.offset_right = x + PIP_SIZE
			pip.offset_top = PLAYFIELD_SIZE.y / 2.0 + 54.0
			pip.offset_bottom = PLAYFIELD_SIZE.y / 2.0 + 54.0 + PIP_SIZE
			_root.add_child(pip)
			_pip_nodes.append(pip)
	for i in _pip_nodes.size():
		var sb := StyleBoxFlat.new()
		sb.bg_color = FRAGMENT_FILL if i < got else Color(0.10, 0.12, 0.10, 0.85)
		sb.border_width_left = 3
		sb.border_width_right = 3
		sb.border_width_top = 3
		sb.border_width_bottom = 3
		sb.border_color = FRAGMENT_RIM
		var r := int(PIP_SIZE / 2.0)
		sb.corner_radius_top_left = r
		sb.corner_radius_top_right = r
		sb.corner_radius_bottom_left = r
		sb.corner_radius_bottom_right = r
		_pip_nodes[i].add_theme_stylebox_override("panel", sb)


func _rebuild_wall_visuals() -> void:
	for w in _wall_nodes:
		if is_instance_valid(w):
			w.queue_free()
	_wall_nodes.clear()
	for wr in _wall_rects:
		var rect := ColorRect.new()
		rect.color = Color(0.32, 0.22, 0.12, 0.85)
		rect.position = wr.position
		rect.size = wr.size
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_walls_container.add_child(rect)
		_wall_nodes.append(rect)


func _update_visual_positions() -> void:
	var half := Vector2(ICON_DISPLAY_SIZE, ICON_DISPLAY_SIZE) / 2.0
	_player_icon.position = _player_pos - half
	_monster_icon.position = _monster_pos - half
	_patrol_icon.position = _patrol_pos - half
	_target_icon.position = _target_pos - half


# Snares are drawn UNDER the icons, at their TRUE radius. See the SNARE_FILL block above for
# the two defects this replaces.
func _rebuild_snare_visuals() -> void:
	for n in _snare_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_snare_nodes.clear()
	# ⚠️ Null-guarded for the same reason _rebuild_fragment_visuals() is: the three headless
	# harnesses drive `_check_snares()` on an instance that was never added to the tree, so
	# `_ready()` — and therefore `_build_ui()` — never ran. This used to throw once per spring.
	if _walls_container == null:
		return
	for s in _snares:
		var mark := _make_snare_visual(s)
		# ⚠️ Into the WALLS container, which is added once in _build_ui(). Adding to the
		# playfield instead would place them after the icons in the draw order and paint
		# over them — the confirmed cause of the target being invisible in a past playtest.
		_walls_container.add_child(mark)
		_snare_nodes.append(mark)


# A frozen patch: dark rim, ice-blue disc AT SNARE_RADIUS, white frost star. All geometry.
func _make_snare_visual(centre: Vector2) -> Control:
	var holder := Control.new()
	holder.name = "Snare"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(SNARE_RADIUS, SNARE_RADIUS) * 2.0
	holder.position = centre - Vector2(SNARE_RADIUS, SNARE_RADIUS)
	var mid := Vector2(SNARE_RADIUS, SNARE_RADIUS)

	var rim := _circle((SNARE_RADIUS + SNARE_RIM_PAD) * 2.0, SNARE_RIM)
	rim.name = "SnareRim"
	rim.position = mid - rim.size / 2.0
	holder.add_child(rim)

	# ⚠️ THE ASSERTED ONE. Its radius IS the trigger radius — tests/check_maze_traps.gd reads
	# this node's size and fails if the two ever drift apart again.
	var fill := _circle(SNARE_RADIUS * 2.0, SNARE_FILL)
	fill.name = "SnareFill"
	fill.position = mid - fill.size / 2.0
	holder.add_child(fill)

	for i in SNARE_GLYPH_BARS:
		var bar := ColorRect.new()
		bar.name = "SnareGlyph%d" % i
		bar.color = SNARE_GLYPH
		bar.size = Vector2(SNARE_RADIUS * 1.4, SNARE_GLYPH_T)
		bar.pivot_offset = bar.size / 2.0
		bar.position = mid - bar.size / 2.0
		bar.rotation = deg_to_rad(180.0 * float(i) / float(SNARE_GLYPH_BARS))
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(bar)
	return holder


# ---------------------------------------------------------------- chase audio
#
# ⚠️ A plain AudioStreamPlayer (not 3D): this is a 2D overlay, there is nothing to pan
# around. Parented to this CanvasLayer so it inherits PROCESS_MODE_ALWAYS and keeps
# playing while the tree is paused — which it is, the whole time the map is open.
#
# ⚠️ Bus left unset, i.e. Master, matching `combination_lock.gd`'s buzz — the only other
# paused-UI sound in the game. A chase cue must not be duckable by a SilenceZone or a
# HoldBreath dip firing somewhere else.
#
# ⚠️ Looped in CODE. Every .wav.import in this project is loop_mode=0, so the stream never
# repeats itself; `finished -> play` is the house idiom. `tools/make_loop.py` trimmed the
# supplied file's fade-out and crossfaded the seam so the repeat is inaudible.
# ⚠️ Loaded BY PATH, not through `GameState.load_audio()`. `check_maze_gen.gd` instantiates
# this class by its class_name, which compiles this file before the autoloads are
# registered — so a bare `GameState` here is a COMPILE error that takes the test down with
# it, and the test then spins instead of failing. Same hazard `screenshot_maze_ui.gd`
# documents for naming game classes in a SceneTree script. The texture constants above are
# hardcoded for the same reason, so this matches the file's own convention.
const CHASE_PATH := "res://assets/audio/level_2_house/chase.wav"
const CHASE_VOLUME_DB := -6.0

var _chase_audio: AudioStreamPlayer


func _start_chase_audio() -> void:
	if _chase_audio == null:
		if not ResourceLoader.exists(CHASE_PATH):
			return
		var stream: AudioStream = load(CHASE_PATH)
		if stream == null:
			return
		_chase_audio = AudioStreamPlayer.new()
		_chase_audio.name = "ChaseAudio"
		_chase_audio.stream = stream
		_chase_audio.volume_db = CHASE_VOLUME_DB
		add_child(_chase_audio)
		_chase_audio.finished.connect(_chase_audio.play)
	_chase_audio.play()


func _stop_chase_audio() -> void:
	if _chase_audio and _chase_audio.playing:
		_chase_audio.stop()
