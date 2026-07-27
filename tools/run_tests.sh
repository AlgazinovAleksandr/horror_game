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
  check_house_guest           # THE GUEST rearranges the House off-screen; the fridge is 10, once
  check_corridor_doors        # ajar doors never block the hall; 4 of 5 telegraphs are free
  check_backrooms_occupants   # the Congregation has NO rules; the wader is never rendered
  check_wall_overlap          # coincident surfaces — the "merging textures" family
  check_doorways              # nothing seals a doorway
  test_room_builder           # the procedural room graph itself
  check_maze_gen              # House maze generation, 200 seeds
  check_dungeon_gen           # THE NIGHTMARE's dungeon layout, 200 seeds
  check_maze_chase            # House maze monster: catches you, still beatable
  check_intro_gate            # BACKLOG #12 — no Level 1 without reading the note
  check_kontur_bottles        # BACKLOG #22 — the vinegar softlock
  check_flood_notes           # BACKLOG #24 — the roster digits are findable
  check_cellar_key            # BACKLOG #16 — the key must be used, not just found
  check_journal               # the notes journal, and that trap notes stay out of it
  check_level_resume          # BACKLOG #30 — going back keeps your progress
  check_level6_breach         # BACKLOG #28 — SlamDoor type crash + doorway clearance
  check_purge_interact        # Level 6 win path is reachable by a real E press
  check_lab_locker            # Lab locker gate + NO_LAMP_ROOMS stay dark
  check_lab_hint              # the Lab's hint props are actually visible
  check_morgue_props          # morgue trigger objects are not buried
  check_window                # the House window exists and faces the room
  check_fixtures              # ceiling fittings are not blown out
  check_spawn_blocked         # nothing invisible blocks either spawn
  check_backrooms_death       # Backrooms fail paths
  check_death_freeze          # a dead player stops accruing panic (Issue 15)
  check_kontur                # KONTUR structure + exit lock
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
  autoplay_exit_reachable     # every level's exit can be WALKED to and E'd on
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
#   check_wall_overlap on a specific scene   takes a scene argument; the entry above
#                               runs it on level_1 only. For the dungeon:
#                                 ... --script res://tests/check_wall_overlap.gd -- \
#                                     res://scenes/dungeon.tscn --dungeon-seed 404

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
