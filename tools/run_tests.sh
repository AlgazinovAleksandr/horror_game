#!/usr/bin/env bash
# Run the whole headless test suite and print one summary table.
#
#   tools/run_tests.sh              # everything
#   tools/run_tests.sh -q           # quiet: only the summary and failing output
#   tools/run_tests.sh maze         # only tests whose name matches "maze"
#
# Exit code is the number of failing tests, so CI and the game-tester agent can branch
# on it. Each test is a separate Godot process on purpose: several of them change the
# scene, raise Engine.time_scale, or quit() mid-run, and a shared SceneTree would let
# one test's state leak into the next.
#
# ⚠️ A TEST IS RED IF IT PRINTS `SCRIPT ERROR`, EVEN WHEN IT EXITS 0 (added 2026-08-16).
# A GDScript runtime error aborts one function call and carries on; it is not a crash and it
# does not touch the exit code, so a test can run, throw on every iteration, and report PASS.
# What this caught: `maze_chase_ui.gd:_rebuild_snare_visuals()` calling `add_child` on a null
# container in every headless harness — **nine errors per run of check_maze_chase**, for as
# long as the snares had existed, inside a test that had always been green (Issue 78). The
# suite was swept before the check landed and had zero occurrences, so it turned nothing red
# that should have been green; it exists to catch the next one. Parse errors mean "the test
# never ran"; these mean "the test ran on fire". Both are failures.
#
# ⚠️ AND A TEST THAT NEVER CALLS quit() CANNOT FAIL (Issue 97, 2026-08-17). Returning true from
# SceneTree._process ends the loop and exits 0, whatever the test printed. SIX entries in this list
# were in that state: four diagnostic printers (check_fixtures, check_window, check_morgue_props,
# check_spawn_blocked), check_doorways (which printed BLOCKED and then quit(0) unconditionally), and
# walk_level6_breach — the only end-to-end completability proof Level 6 has, on a level that once
# shipped uncompletable. All fixed or demoted. The audit is `grep -L "quit(" game/tests/*.gd`.
#
# ⚠️ The --import pass is NOT optional after adding a `class_name` or an asset. Godot
# caches class names in .godot/global_script_class_cache.cfg, and until it is rescanned
# a brand-new class_name is "not declared in the current scope" — which makes every
# level script that references it fail to PARSE, which in turn makes tests report zero
# findings and pass. That exact sequence produced a green "0 apparitions in 400 s".

set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
QUIET=0
FILTER=""
for arg in "$@"; do
  case "$arg" in
    -q|--quiet) QUIET=1 ;;
    *) FILTER="$arg" ;;
  esac
done

if [ ! -x "$GODOT" ]; then
  echo "Godot not found at $GODOT — set GODOT=/path/to/Godot" >&2
  exit 127
fi

# Ordered fastest-first so an obvious break surfaces before the slow behavioural runs.
# The comment after each name is what it protects; keep it accurate, it is the only
# index of what this suite actually covers.
TESTS=(
  check_audio_buses           # the silence architecture: Body survives a dip, beds nest
  check_intro_beats           # the Intro's dread beats, and that it stays UNLOSEABLE
  check_intro_geometry        # Intro wall props are ON their wall (door gap, planks, switch)
  check_art_aspect            # ALL NINE levels: every texture is shown at its own aspect
  check_intro_sheet           # the covered body is a BODY and is smooth — rejected twice
  check_house_guest           # THE GUEST rearranges the House off-screen; the fridge is 10, once
  check_corridor_doors        # ajar doors never block the hall; a non-payoff telegraph is free
  check_corridor_events       # runner's apparent size; the false 217 door; note facing; flash payload
  check_prop_mounting         # ALL NINE levels: every flush wall prop is SEATED — the maximum
  check_mirror_frustum        # the glass frames itself: near-plane window == the quad, 1.00x
  check_mirror_wake           # the 14 m appearance cue: one shot, in front of you, no panic
  check_mirror_figure         # the figure is OFF the mirror's axis, and that buys real motion
  check_painting_fall         # the falling painting lands on a wall, from anywhere on the path
  check_noclip_fall           # the fall, the blackout and the re-entry cap stay in formation
  check_bus_leak              # one level's audio duck must not follow you into the next
  check_corridor_repeats      # no sound in the Corridor is a loop; the score survives the hush
  check_turn_mirror           # the turn mirrors reflect, and the figure is ONLY in the glass
  check_backrooms_seam        # zone 1 teaches its own verb: the seam's voice + a legible arrow
  check_sprawl_alcoves        # the Sprawl's 8 alcoves are OPEN and the shell has no hole
  check_flood_drowned         # THE DROWNED — 6 searchables found by ear, 3 events, zero panic
  check_flood_puzzle          # the Flood is a puzzle: 6 fragments, the plate, an earned exit
  check_sprawl_crate          # the box in the dark: both routes to the real wall, independently
  check_shell_sealed          # ALL NINE levels: you cannot see out, and every point has a ceiling
  check_backrooms_occupants   # the Congregation has NO rules and never lands in your view
  check_backrooms_audio       # the score leads the mix; the Flood's drips stay in the Flood
  check_wall_overlap          # ALL NINE levels: coincident surfaces, the "merging textures" family
  check_doorways              # ALL NINE levels: nothing seals a doorway (tables read, not typed)
  test_room_builder           # the procedural room graph itself
  check_maze_gen              # House maze generation, 200 seeds
  check_dungeon_gen           # THE NIGHTMARE's dungeon layout, 200 seeds
  check_maze_chase            # House maze monster: catches you, still beatable
  check_maze_traps            # House maze snares + fragments drawn true-size; the mark is
                              # inert until every fragment is collected; ESC is not a re-roll
  check_music_box             # the wind ducks the bed AND puts it back (Issue 50's shape)
  check_intro_gate            # BACKLOG #12 — no Level 1 without reading the note
  check_kontur_bottles        # BACKLOG #22 — the vinegar softlock
  check_flood_notes           # BACKLOG #24 — the roster digits are findable
  check_cellar_key            # BACKLOG #16 — the key must be used, not just found
  check_journal               # the notes journal, and that trap notes stay out of it
  check_lock_input            # the lock takes typed digits, and keeps its Esc hint on a miss
  check_level_resume          # BACKLOG #30 — going back keeps your progress
  check_level6_breach         # BACKLOG #28 — SlamDoor type crash + doorway clearance
  check_purge_interact        # Level 6 win path is reachable by a real E press
  check_interact_reach        # L6/L7 props answer E from a real distance, aiming at the ART
  check_lab_locker            # Lab locker gate + NO_LAMP_ROOMS stay dark
  check_lab_breaker_gate      # a partly-shoved locker must not SHOW or hand over the breaker
  check_nook_dark             # the nook breaker panel is no brighter than its wall
  check_lab_cabinet           # the Records bank is a search: 8 drawers, 1 page, no penalty
  check_lab_hint              # the Lab's hint props are actually visible
  check_note_mounting         # ALL NINE levels: every note/panel is on a wall, not in a doorway
  check_nook_figure           # the nook figure is clear of geometry AND in frame
  check_wing_meter            # the dark-wing meter measures PATH distance, not a beeline
  check_open_then_read        # a prop opens BEFORE its note pauses the tree
  check_window                # the House window exists, is visible and faces the room
  check_fixtures              # ALL NINE levels: no fitting is over the 1.0 emission clamp
  check_spawn_blocked         # ALL NINE levels: the real player spawn is clear and floored
  check_backrooms_death       # Backrooms fail paths
  check_death_freeze          # a dead player stops accruing panic (Issue 15)
  check_beartrap_hold         # trapped means trapped: movement pinned, look still free
  check_kontur                # KONTUR structure + exit lock
  check_kontur_resume         # KONTUR's randomisations survive a resume; no passed gate comes back as a wall
  check_kontur_signs          # the eight redacted signs are readable from the walking line AND still redacted
  check_kontur_entities       # Object 12 is inert; the mimic costs nothing to look at and can spend nothing
  test_apparition             # HOLD rule: hold still lives, flee dies
  check_apparition_clearance  # BACKLOG #8 — never materialises inside geometry
  test_creature_object12      # BACKLOG #26 — blind is chase-only, 5-7 s
  check_dungeon_entities      # THE NIGHTMARE's §B10 bans: no DarkZone/DreadZone/etc
  walk_cellar                 # the House cellar ramp is walkable both ways
  walk_lab_wing               # the dark wing is navigable and its dead ends are dead
  walk_wing_escape            # you can get back out of the wing after the scare
  walk_backrooms              # all three Backrooms zones are completable
  walk_kontur                 # KONTUR is completable and its gates are load-bearing
  walk_level6_breach          # Level 6 is winnable through the real interact path
  walk_dungeon                # THE NIGHTMARE: 7 sconces + the bed are reachable
  check_reachable             # ALL NINE levels: can the player STAND where each prop is
  autoplay_exit_reachable     # every level's exit can be WALKED to and E'd on
  autoplay_house_route        # …and no House prop can SEAL a route by being opened
  count_apparitions           # BACKLOG #6 — apparitions are rare, and still happen
)

# ⚠️ NOT in the list, on purpose, and each for a stated reason:
#   screenshot_*                need a render target — run them WITHOUT --headless
#   autoplay_dungeon            ~4 min on its own (it plays THE NIGHTMARE end to end
#                               with every entity live across 2 seeds), which would
#                               roughly double this suite. It is a DIFFICULTY
#                               instrument rather than a regression guard — run it
#                               via .claude/agents/dungeon-tester.md, or directly:
#                                 Godot --headless --path game \
#                                   --script res://tests/autoplay/autoplay_dungeon.gd
#
# ⚠️ THE SCENE-PARAMETERISED GUARDS ARE SWEEPS NOW (2026-08-17, workstream H1), not one
# level plus whichever wrappers somebody remembered to write. `check_wall_overlap`,
# `check_note_mounting`, `check_art_aspect`, `check_prop_mounting`, `check_reachable` and
# `check_shell_sealed` each iterate `game/tests/lib/scenes.gd`, which is DERIVED from
# `GameState`'s own SCENE_* constants — so adding a level enrols it in all six with no
# wrapper to remember, and a SCENE_* constant that is neither classified as a level nor
# excluded by name turns every one of them red. The eight wrappers they replaced
# (check_wall_overlap_{house,corridor,backrooms}, check_note_mounting_{house,backrooms},
# check_intro_art, check_corridor_art, check_backrooms_art) are deleted rather than left
# alongside: two ways to run one guard is how they drift.
#
# To reproduce ONE finding, filter by label or hand it a raw path:
#     ... --script res://tests/check_wall_overlap.gd -- Corridor
#     ... --script res://tests/check_wall_overlap.gd -- res://scenes/dungeon.tscn
#   probe_morgue_props          a PRINTER, not a guard: it dumps the morgue props' meshes and
#                               materials and asserts nothing. It was in this list as "morgue
#                               trigger objects are not buried" — a claim it could not make —
#                               until 2026-08-17. That claim is covered by check_reachable
#                               (both triggers are REACHABLE), check_wall_overlap and
#                               check_prop_mounting.
#   probe_maze_variance         a MEASUREMENT, not a guard: it asserts nothing and prints the
#                               distribution the House maze's difficulty band would be chosen
#                               from (backlog 02-house S1 Part 2). ~1 min for 200 seeds:
#                                 ... --script res://tests/probe_maze_variance.gd -- 200
#                               Args: `-- <seeds> <N> <bot px/s> <min detour>`; **N=0 is
#                               the control** (the one-stage build through the same code).

echo "== importing (required after any new class_name or asset) =="
"$GODOT" --headless --path game --import >/dev/null 2>&1

pass=0; fail=0; missing=0
declare -a FAILED=()
printf "\n%-28s %-8s %s\n" "TEST" "RESULT" "TIME"
printf -- "----------------------------------------------------\n"

for t in "${TESTS[@]}"; do
  [ -n "$FILTER" ] && [[ "$t" != *"$FILTER"* ]] && continue
  if [ ! -f "game/tests/$t.gd" ]; then
    printf "%-28s %-8s %s\n" "$t" "MISSING" "-"
    missing=$((missing+1)); continue
  fi
  start=$(date +%s)
  out=$("$GODOT" --headless --path game --script "res://tests/$t.gd" 2>&1)
  code=$?
  elapsed=$(( $(date +%s) - start ))
  # ⚠️ A script that fails to PARSE exits 0. Godot prints "Parse Error" / "Failed to load
  # script" and then quits cleanly, so exit status alone reports a broken test as a PASS —
  # which is exactly the vacuous green this file's header warns about, and it hid a
  # completely non-functional check_house_guest.gd on 2026-07-28. Treat it as a failure.
  #
  # ⚠️ AND ANY *RUNTIME* SCRIPT ERROR, added 2026-08-16 (Issue 78). A GDScript runtime error
  # aborts the current function call and CONTINUES — it is not a crash, it does not change the
  # exit code, and the assertions after it still measure the right thing. So a test can run,
  # throw on every iteration, and print PASS. Measured: `_rebuild_snare_visuals()` called
  # `add_child` on a null container in every headless harness, **nine times per run of
  # check_maze_chase**, and had done so for as long as the snares had existed. Nobody saw it,
  # because the only signals this runner had were the exit code and a parse-error grep.
  #
  # This is the same failure family as the parse check one step further along: parse errors
  # are "the test never ran", these are "the test ran on fire". Both must be red.
  # ⚠️ The suite was swept before this landed and had **0** occurrences, so this cannot be
  # turning a real red into a new one — it can only catch the next one.
  if echo "$out" | grep -qE "Parse Error|Failed to load script|SCRIPT ERROR"; then
    code=1
  fi
  if [ $code -eq 0 ]; then
    printf "%-28s %-8s %ss\n" "$t" "PASS" "$elapsed"
    pass=$((pass+1))
    [ $QUIET -eq 0 ] && echo "$out" | grep -E "^  (OK|--)|^RESULT|^ *[0-9]+ (checks|spawns)" | sed 's/^/      /'
  else
    printf "%-28s %-8s %ss\n" "$t" "FAIL" "$elapsed"
    fail=$((fail+1)); FAILED+=("$t")
    # Always show why, even in quiet mode — a silent failure is worthless.
    echo "$out" | grep -E "FAIL|SCRIPT ERROR|Parse Error|RESULT" | head -20 | sed 's/^/      /'
  fi
done

printf -- "----------------------------------------------------\n"
printf "%d passed, %d failed" "$pass" "$fail"
[ $missing -gt 0 ] && printf ", %d missing" "$missing"
printf "\n"
if [ ${#FAILED[@]} -gt 0 ]; then
  printf "failing: %s\n" "${FAILED[*]}"
fi
exit $fail
