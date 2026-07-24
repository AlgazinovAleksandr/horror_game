---
name: game-testing
description: 'Launch the horror game in Godot from any level, capture a playtest log while the user plays, then diagnose anomalies — bugs, dead features, difficulty spikes, unwinnable states — and propose fixes. ALWAYS confirms findings with the user before changing anything. Triggers on: test the game, playtest, launch the game, let me play, run the game from level N, help me find bugs, is this a bug, the level feels wrong.'
---

# Game Testing: Playtest & Diagnose Protocol

A human plays; you observe, measure, and hypothesise. **You do not fix anything until the user
agrees the finding is real.**

## The rule that outranks everything else in this skill

You will be wrong sometimes. A level that feels punishing may be punishing *on purpose*; a creature
that kills in two seconds may be the intended lesson; a room that seems empty may be pacing. Session
2026-07-21 is the canonical example — a creature killed the player twice in one run, the analysis
was correct in every measured detail, and the user's answer was still **"leave it as is."**

Therefore:

- **Never edit game logic before the user confirms the finding.** Present, recommend, wait.
- **Separate what you measured from what you inferred.** "Panic rose 16/s at a fixed position" is a
  measurement. "The creature is too lethal" is a hypothesis. Label them differently.
- Two exceptions you may fix without asking, because they are never design: **(a)** something is
  provably unreachable/unwinnable (proven by a physics query, not by reading code), and **(b)** the
  instrumentation itself is lying. Say clearly which exception you invoked.
- When a finding is rejected, **write the reasoning into the code** as a `⚠️ DELIBERATE` comment
  with the date, so a future session doesn't re-file it as a bug.
- Ask as many questions as you need. This is hypothesis testing, not a repair job.

---

## Step 1 — Establish the start point

Ask the user where to start if they haven't said. Scenes:

| Level | Scene | Notes |
|---|---|---|
| Intro | `res://scenes/intro_room.tscn` | Full run starts here |
| 1 Lab | `res://scenes/level_1.tscn` | |
| 2 House | `res://scenes/level_2_1.tscn` | ⚠️ not `level_2.tscn` |
| 3 Corridor | `res://scenes/corridor.tscn` | |
| 4 Backrooms | `res://scenes/backrooms.tscn` | 3 zones in one scene |
| 5 KONTUR | `res://scenes/kontur.tscn` | |
| 6 The Breach | `res://scenes/level_6_breach.tscn` | Object 12 pursuit level |
| 7 The Void | `res://scenes/level_3.tscn` | ⚠️ name does not match the level number |
| Menu | `res://scenes/main_menu.tscn` | |

Starting mid-game means the player has **none** of the earlier levels' context. KONTUR in particular
plants all four of its answers in levels 1–4, so a cold start there is expected to be brutal — that
is not a finding. Say so up front, and brief the user on what the level expects.

**Tell the user about the debug-capture hotkey before they start playing.** Pressing **J** at any
point takes a screenshot immediately, then pauses and opens a one-line note box (Enter to save,
Esc to skip — the screenshot is kept either way). This is the highest-signal input you'll get: it's
the user pointing at the exact frame and moment something looked or felt wrong, in their own words,
instead of a post-session recap from memory. Encourage them to use it liberally.

## Step 2 — Launch

```bash
# 1. If any asset (.wav/.png/.gd class_name) changed since last run:
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import

# 2. Clear the previous log AND any stale debug-capture screenshots, so you don't
#    diagnose a prior session's findings as if they were this one's:
rm -f "$HOME/Library/Application Support/Godot/app_userdata/horror_game/playtest_log.txt"
rm -rf "$HOME/Library/Application Support/Godot/app_userdata/horror_game/debug_captures"

# 3. Launch WINDOWED, in the background, filtering to log lines:
/Applications/Godot.app/Contents/MacOS/Godot --path game res://scenes/<SCENE>.tscn 2>&1 \
  | grep -E "^LOG|SCRIPT ERROR"
```

Run it with `run_in_background: true`. **Do not poll the output file** — you are re-invoked when the
user closes the window. Use the wait to brief them: the level's win condition, its fail paths, and
what you'll be watching for.

Instrumentation is the `DebugLog` autoload (`game/scripts/debug_log.gd`), polling at 0.5 s. Game code
may call `DebugLog.note("...")` for events the poller can't infer — always behind
`get_node_or_null("/root/DebugLog")` so removing the autoload strips it. Add a `note()` call before
launching if a level's failures are otherwise indistinguishable (this is how KONTUR's four gates
became separable).

## Step 3 — Read the log

```bash
grep -E "^LOG|SCRIPT ERROR" <output-file>
```

**Triage `DEBUG CAPTURE` lines first.** These are the user pressing J — user-flagged, not inferred,
and paired with an exact screenshot:

```bash
grep "DEBUG CAPTURE" "$HOME/Library/Application Support/Godot/app_userdata/horror_game/playtest_log.txt"
```

Each line has the form `DEBUG CAPTURE #N -> user://debug_captures/00N.png | scene=... pos=... |
note: "..."`. Resolve the `user://` path with `ProjectSettings.globalize_path()`'s printed
equivalent — in practice that's always
`$HOME/Library/Application Support/Godot/app_userdata/horror_game/debug_captures/00N.png` — and
`Read` the PNG directly alongside the note text before looking at anything else in the log. A
`(screamer interrupted)` suffix means a real death cut the note short; the screenshot and whatever
was typed are both still valid signal.

### Reading panic numbers

Logged as a **percentage of `PANIC_MAX = 50`**. Convert before matching against constants:

| Jump | Points | Almost certainly |
|---|---|---|
| +24% | 12 | `WRONG_WALL_PANIC` (Backrooms zone 2/3 wrong seam) |
| +30% | 15 | `Beartrap` `ESCAPE_INITIAL_PANIC`, or `WRONG_TURN_PANIC` (old value) |
| +36% | 18 | KONTUR `STRIKE_PANIC`, or Backrooms `WRONG_TURN_PANIC` |
| +20% | 10 | `combination_lock` wrong code, `MirageDoor` |
| ~+18%/0.5 s sustained | 16/s | Gaze at a `ScaryObject` of intensity ~0.8 |

**Position is the other half of the diagnosis.** Cross-reference the logged coordinates against the
level script's room table or prop positions. Two deaths at coordinates matching beartrap spawns is
a placement problem; two deaths at the same coordinate as a creature is a lethality question.
Remember zone offsets: Backrooms zone 2 is `+200 x`, zone 3 is `−200 x`.

### Known false positives — check these before reporting

- **Death on level advance.** Advancing loads a new scene and a new player at 0 panic; the collapse
  looks identical to death. Guarded by `_scene_changed`, but verify against the surrounding lines.
- **Death on restart.** A restart reloads the *same* scene, so the scene-change guard doesn't fire.
  Guarded by rebasing `_last_panic` on the newly spawned player. A real death is a collapse followed
  ~2 s later by `PLAYER spawned`.
- **`?? STATIONARY`** while a note or lock UI is open is the player reading, not stuck.
- **`invalid UID` warnings** are cosmetic and pre-existing. Not a finding.

## Step 4 — Classify what you found

Sort every anomaly into one of these, and say which:

1. **Broken** — a feature does not work at all. Prove it with a measurement before saying so.
2. **Unreachable/unwinnable** — the player cannot complete the level. Highest severity; fixable
   without asking, but still report it fully.
3. **Difficulty** — completable but costly. **Always a question for the user, never a unilateral
   fix.** Give the numbers (deaths, time, panic rate, seconds-to-death) and a recommendation.
4. **Legibility** — the player solved it by guessing rather than by reading the intended cue. The
   log tells you this: a puzzle with N answers solved after ~N/2 wrong attempts is a coin-flip, not
   a deduction. This is the hardest class to see and the most valuable to raise.
5. **Instrumentation** — the log is wrong. Fix silently, then re-read the log with the fix in mind.

## Step 5 — Report, recommend, and WAIT

Structure: what the log shows → what you measured → what you think it means → what you'd change →
**what you want the user to decide.**

Use `AskUserQuestion` when the decision is genuinely theirs (difficulty, tone, how cruel a creature
should be). Put your recommendation first and label it. Accept the answer without relitigating.

## Step 6 — Only after confirmation: fix and verify

Verification rules this project learned the hard way:

- **Assert with physics queries, not object state.** A wall's `is_solid()` returned `true` for the
  entire time it was a hole in the world. A seam's `is_real` flag was correct while its trigger sat
  behind a wall, unreachable.
- **Never let a test reach the win condition by calling the signal.** `walk_backrooms.gd` drove
  `cleared.emit()` and passed for weeks while the level was literally uncompletable. If the player
  gets there by walking, the test must get there by geometry.
- **Prove the test can fail.** Disable the fix, confirm the new check goes red, re-enable.

Then:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/walk_backrooms.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game res://scenes/<SCENE>.tscn --quit-after 30
```

Finally, **write it up in `ISSUES_SOLUTIONS.md`** in the existing house style — symptom, cause, fix,
why existing tests missed it, general lesson. That file is the project's memory; a fix that isn't in
it will be re-debugged.

---

## Level-specific things worth watching

- **Backrooms** — three zones, one scene. Zone 2's tell is *sound* (the bus ducks near the real
  wall); zone 3's is *darkness* (the real seam shows only with the flashlight OFF). Watch
  `FLASHLIGHT` lines: a player toggling it in zone 3 has found the mechanic; one who never does
  hasn't. Whether the silence tell reads as a clue is a **long-standing open question** — ask.
- **KONTUR** — no panic decay anywhere (the floor-wide `DreadZone` cancels it exactly), so every
  point taken is permanent. Budget is three strikes at 18. All four gates are hinted in earlier
  levels; a cold start has none of that.
- **The Void / apparitions** — `RULE_HOLD` is survived by *not* fleeing. A death right after a
  sprint is the rule working, not a bug.
- **Trap notes** are read-to-die (+12 panic/s while open) — a panic climb during a `STATIONARY`
  stretch is probably a note, not a stuck player.

## Standing caution

`_update_panic` in `player.gd` is an **if/elif chain**: gaze → sprint → dark-zone → decay. Only one
fires per frame. `DreadZone` and standstill are the only genuinely additive sources. So "this room
has a DarkZone *and* scary props, it must be brutal" is usually false — and a `DarkZone` also
*suppresses decay*, which is how the Flood once reached +5/s with no way down.
