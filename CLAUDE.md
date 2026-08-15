# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Horror Game — Claude Context

## Project
3D first-person atmospheric horror prototype. Desktop macOS app (.app bundle).
Horror through atmosphere, lighting, sound, and environment storytelling.

⚠️ **The pillar is "AI is rationed", not "no AI".** This line used to read *"No active enemy AI"*;
that stopped being true when Level 6 shipped `creature_object12.gd`, a five-state pursuit AI with
search memory, and `DUNGEON_NIGHTMARES.md` §B4.2 specs a second (the Matron). The correct constraint
is `SCARY.md` §8.4's: **one chase level in twelve.** Outlast's chase-or-nothing binary is the failure
state of chase-led design. Do not add a third pursuer.

## Commands

Godot lives at `/Applications/Godot.app/Contents/MacOS/Godot`; every test/tool honours a `GODOT`
env override. The Godot project root is `game/` — all commands take `--path game`. There is no
build, lint or package step: the game runs from source, and `--import` is the only "build".

```bash
# Run the game (starts at main_menu.tscn, per project.godot)
/Applications/Godot.app/Contents/MacOS/Godot --path game

# Run ONE level directly (skip the run-up) — see the Level scenes table for the list
/Applications/Godot.app/Contents/MacOS/Godot --path game res://scenes/kontur.tscn
/Applications/Godot.app/Contents/MacOS/Godot --path game res://scenes/dungeon.tscn -- --dungeon-seed 404

# Re-import after ANY new class_name, .wav/.ogg or texture (see the ⚠️ in Testing)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import

# Tests
tools/run_tests.sh                 # whole headless suite, one summary table; exit code = #failures
tools/run_tests.sh -q              # summary + failing output only
tools/run_tests.sh maze            # only tests whose NAME matches a substring

# One test, directly (this is all run_tests.sh does per row)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
  --script res://tests/check_kontur.gd

# Args go after a bare `--` (OS.get_cmdline_user_args)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
  --script res://tests/check_wall_overlap.gd -- res://scenes/dungeon.tscn --dungeon-seed 404

# screenshot_* tests need a render target — run them WITHOUT --headless
/Applications/Godot.app/Contents/MacOS/Godot --path game --script res://tests/screenshot_kontur.gd

# Procedural SFX (stdlib-only Python; re-run to regenerate, then --import)
python3 tools/make_sfx_dungeon.py
```

Playtest logs from `DebugLog` land at
`~/Library/Application Support/Godot/app_userdata/horror_game/playtest_log.txt`.

## Game Design

### Premise
The player wakes in a dark room as **Subject 47** — a participant in a psychological experiment testing their ability to conquer fear. A note explains: the entity they may encounter is a manifestation of their own mind, not real. Stay calm. Do not touch what you are not meant to touch.

### ⚠️ DESIGN PILLAR — ESCALATING UNREALITY
**The game starts with something ordinary and human, and gets further from reality the deeper the
player goes.** Every level must be stranger and more frightening than the one before it. Locations,
rules, and the player's own senses all degrade along that curve.

This is a **hard constraint on new content**, not a mood note. Any new level must know where it sits
on the curve and must be weirder than its predecessor; any change to an existing level should push it
further along the curve, never back. `SCARY.md` §6 holds the full ordering.

⚠️ **The curve is currently non-monotonic and that is a known, deliberately-unresolved issue.** The
Backrooms is fully unreal (impossible space, loops, mono-yellow void), and then KONTUR and The Breach
drop back to *coherent, real-world* Soviet facility interiors before the Void goes unreal again. The
user's call (2026-07-27) is **note it, decide later** — the options are degrading 5–6 in place,
accepting it as a deliberate breather, or reordering (expensive: KONTUR's eight gates are answered by
hints planted in the Lab, House, Corridor and Backrooms, and the Flood holds its roster-code digits).
**Do not resolve this silently in an implementation session.**

### Structure
```
Intro room → Level 1 (The Lab) → Level 2 (The House) → Level 3 (The Corridor) → Level 4 (The Backrooms) → Level 5 (KONTUR) → Level 6 (The Breach) → Level 7 (THE NIGHTMARE) → Level 8 (The Void) → Twist Ending
```

Each level: explore the environment, find clues/items, unlock the exit door. Fail = screamer + restart that level. Pass = enter the next door.

⚠️ **Four new levels are specified but not yet built** — see `SCARY.md` (OBSERVATION, THE ANECHOIC
CHAMBER, THE RETURN) and `DUNGEON_NIGHTMARES.md` (THE NIGHTMARE). The agreed target order is:
```
0 Intro · 1 Lab · 2 OBSERVATION · 3 House · 4 Corridor · 5 ANECHOIC CHAMBER · 6 Backrooms
· 7 KONTUR · 8 THE BREACH · 9 THE NIGHTMARE · 10 The Void · 11 THE RETURN · Twist Ending
```
The renumbering must land as **one commit** (`GameState`'s level map + scene constants,
`Screamer.LEVEL_SCREAMERS`, the `level_progress` rows, `level_3.gd`'s `current_level`, the back-door
chain), with `tests/check_level_resume.gd` extended to assert the full chain both directions.

### Making the game scarier — read `SCARY.md`
`SCARY.md` is the authoritative fear document: the diagnosis (predictable/habituating · no dread
between scares · an inert world), eleven costed retrofits, the audio-architecture overhaul, the
shadow rollout, the three new levels, the anti-patterns, and a phased roadmap.

⚠️ **`GAME_MECHANICS_IDEAS.md` is the entry point for *what to build next*.** It carries the audited
build status of every accepted idea (2 built · 6 partial · 25 not built), the six live defects, the
rejection ledger, and the build order. It absorbed and replaced `REPORT.md` and `IDEA_HISTORY.md`,
which are now archived in `drafts/` and must not be built from. `SCARY.md` and
`DUNGEON_NIGHTMARES.md` remain authoritative for the *design* of what they spec.
Its governing finding, which constrains every new scare: **stop adding panic terms, start adding
channels** — nine of its eleven proposals add zero panic, because a scare with a number attached can
be optimised against and one without cannot.

### Levels

**Intro Room** — a 12×18 m asylum ward, built at runtime by `intro_room.gd` (see `INTRO.md`)
Note text: *"You are Subject 47. This is a psychological experiment... Stay calm. Do not touch what you are not meant to touch. If something calls out to you — a voice, a ringing, anything that asks for an answer — do not answer it. You are not meant to speak to anyone but us. The door ahead is your first test. We are watching."* (the "do not answer" paragraph is **BUG_FIX.md 2.1** — plants a hint against the Backrooms rotary phone before the player ever meets it)
- ⚠️ **UNLOSEABLE, and it must stay that way.** Nothing here calls `add_panic()`; `RandomAmbient`
  is deliberately NOT registered (it carries 5/8/12 panic per event) and a level-local, zero-panic
  timer plays `floor_creak`/`pipe_groan`/`gurney_creak` instead. `tests/check_intro_beats.gd`
  samples peak panic through every beat and fails if it moves at all
- **"The ward is occupied" (2026-07-28).** The room previously had *no scares whatsoever* — 60–120 s
  of nothing. Now: the **light switch sticks on the first press** (`LightSwitch.presses_needed = 2`)
  — it clunks, the plate blips, and one fluorescent at the FAR end stutters alight for 0.4 s,
  showing the ward you have been crossing blind, then dies. The two spare gurneys carry **sheeted
  forms**. The tube over the table stays dead after the reveal, so the note is lit by candle alone.
  Breathing (`nook_breath`) at the bare `WallFront`, cut the instant the lights come on
  - ⚠️ **NO jumpscare in this room.** `INTRO.md` §2 specced a mid-fumble nightmare flash; it was
    built and then cut on the first playtest (*"the screamer at the intro level is not needed"*).
    The cold open on START already spends that image, and firing it again in the one room with no
    fail state teaches the player the image is free. `check_intro_beats.gd` asserts its ABSENCE
  - **The wheelchair turns to face the table** once the note is read — on **proximity + looking**
    (within 3.2 m, dot > 0.55), with a metal creak, over 1.1 s. ⚠️ This deliberately INVERTS
    `MovedProp`'s happens-off-screen rule: an anomaly nobody witnesses is worth less than an event
    they certainly see, in a 90-second tutorial room. See the same call in the House
- ⚠️ `_corrupt_room()`'s planks/red light are now derived from `EXIT_DOOR_POS` + `DOOR_SIZE`. They
  were literals from the OLD 5.6 m room and floated in open space 6 m from the door — the game's
  final beat, visibly broken, for the life of the bigger ward

**Level 1 — The Lab (institutional wing)** — rebuilt procedurally (Session 10)
- Built at runtime in `level_1.gd` via `RoomBuilder` from a 10-room graph (`ROOMS`/`DOORS`): reception → main corridor with 2 exam rooms → a cross-junction onto the records room and a **sealed morgue** → observation room → exit vestibule. The `.tscn` keeps only `Player`/`Environment`/audio/`HUDCanvas`; `_clear_old_scene()` frees the old hand-built nodes via a `PRESERVE` whitelist
- **Power-restore quest**: 3 `Breaker`s (`breaker.gd`) — Exam1, Records, and BreakerNook (see below). Each `flipped` → `_on_breaker_flipped()`; the third → `_restore_power()` lifts the lamps to full and drops the `MorgueShutter` (a `CSGBox3D` gating the morgue doorway). Three tiers, and **each tier is a different verb — see it / read for it / hear it**. Exam1 stays lit-and-obvious on its wall centre. ⚠️ **No breaker self-illuminates** — the panel used to wear its own art as an `emission_texture` (0.25) and the lever glowed at 0.7, which made even the deliberately-hidden Records one the brightest object in the level (playtest capture #1; ISSUES_SOLUTIONS Issue 33, an Issue-27 recurrence). `glows` now gates only the lever *indicator* at `INDICATOR_EMISSION = 0.12`, because red-vs-green is state feedback rather than an affordance. Records' note and warning sign live on its previously-unused north wall (their old spot became the DarkCorridor doorway)
  - ⚠️ **`_restore_power()` must skip the rooms spawned dark.** `_spawn_lights()` gives EVERY room in `ROOMS` a lamp and hands the eleven `NO_LAMP_ROOMS` one at energy 0.0 — dark because the lamp is off, not because there is no lamp. `_restore_power()` used to raise all of them unconditionally, floodlighting the Morgue (whose whole design is `DarkZone` + beartrap + don't-look triggers) and the entire navigate-by-ear wing. It now carries the same `if entry[1] > 0.0` guard `_on_breaker_flipped()` always had. ISSUES_SOLUTIONS **Issue 36**; regression-locked by `tests/check_lab_locker.gd`
- **Records breaker — the locker** (`lab_locker.gd`, 2026-07-26): the panel isn't merely hidden, it is **physically sealed** behind a steel locker standing flush against it, so the interaction ray hits the locker first. Two gates: (1) `unlocked` flips only when the player reads the **maintenance note on Observation's south wall**, the opposite corner of the floor — before that, `interact()` prints a flat refusal toast; (2) the push itself, a tug-of-war bar fed by mashing **SPACE** (`push_effort`, a new `project.godot` action on `KEY_SPACE`) at `PUSH_PER_PRESS 0.10` against `PUSH_DECAY 0.18`/s. It takes **`SHOVES_NEEDED = 3` full bars**, not one — each fill lurches the locker `SHOVE_DIST 0.45 m` and resets the bar (playtest 2026-07-26: *"probably we need to require more effort — currently too simple"*). Staged rather than one longer bar on purpose: the note says it "moves in fits", and a single 10 s bar with no intermediate feedback reads as broken rather than as heavy. Failing just aborts and is retryable; `PUSH_PANIC 1.2`/s is the only cost. ⚠️ **The gate is HARD and there is deliberately NO pointer to the note** (confirmed with the user) — a player who never searches Observation cannot restore power. Don't soften it without asking
  - ⚠️ **Before the note it is COMPLETELY inert**, not merely refusing (playtest: *"press E should not even appear"*). `LabLocker.can_interact()` returns false, and `player.gd:_update_interact_prompt()` now consults an **optional `can_interact()`** on any prop before showing "Press E" *or* setting `_interact_target` — so E does literally nothing. Props without the method behave exactly as before; this is the general opt-out the project lacked
  - The push **does not pause the tree** (unlike `maze_chase_ui.gd`/`combination_lock.gd`) — `beartrap.gd` is the closer relative. `player.freeze_input()` blocks movement *and* look for free (`_apply_movement` and `_unhandled_input` both early-return on `_input_frozen`), which is the camera pin; the world keeps running behind you. The player is tweened onto a brace mark 0.9 m in front first — not framing polish, it is what stops the slide passing through them. ⚠️ `ARM_DELAY` is load-bearing: `interact` both *starts* the push and *cancels* it, and `_process` polls `Input.is_action_just_pressed`, so without it the opening press closes it on frame one (`note_ui.gd`'s `_block_close` exists for the same collision)
  - ⚠️ **The old spark/flicker tell is DELETED** (`_tick_breaker_spark` + its light, `BUG_FIX.md 4.1`). It did not hide the breaker, it pointed at it: the tell was the loudest and brightest thing in Records, so "search the room" collapsed into "walk toward the crackle". Do not re-add an ambient tell here. `breaker_spark.wav` and `BREAKER_SPARK_MIN/MAX` survive — `_tick_dark_breaker_tell` still uses them for the nook's flavour transient. The Records filing-cabinet bank was trimmed 3 → 2 units and shifted west to clear the locker's footprint
- **The dark wing — navigate-by-ear maze (rebuilt, playtest 2026-07-25)**: Exam2's breaker lives in **`BreakerNook`** at the far end of a **10-room lightless maze** off Records' west wall. Previous passes had 4 rooms and exactly one binary choice, which playtest called out as "too simple… make the geometry harder, and probably add some real audio so we can navigate based on that" (capture #2). Layout — `DarkCorridor` → `Junction` (**decision 1**, three ways) → *west* `WestCorridor`→`Plant` **(dead)** / *north* `NorthSpur`→`NorthVault` **(dead)** / *south* `SouthSpur`→`SouthHall` (**decision 3**) → `PumpRoom` **(dead)** or `BreakerNook`. Three decision points, three dead ends, ~50 m of walking; the terminus is ~28 m from Records' lamp, four times its 11 m range. ⚠️ Rooms are kept in three disjoint z-bands (north ≥14.5, middle 10.5–14.5, south ≤10.5) so limbs can't collide as the graph grows; a doorway only cuts walls its **span** overlaps (`room_builder.gd:199`), so planes are safely reused between bands. All ten rooms are in `NO_LAMP_ROOMS` and share **one** flashlight-lock `Area3D` (`_spawn_breaker_nook_zone()`, bounds x −37..−12 / z 4.2..24 — re-derive it whenever `ROOMS` changes) that calls `player.lock_flashlight()` on entry and symmetrically `unlock_flashlight()` on exit; leaving is always the safety valve. It must stay **one** zone — adjacent Area3Ds fire `body_exited` before `body_entered` and would strobe the lock. **No `DarkZone`** anywhere in the wing (would double-tax the exact posture the premise requires — Issue 18)
  - **The tell is a real two-layer positional beacon** (`_spawn_dark_beacon`): a far cue (`breaker_hum`, `unit_size 16`) that carries the length of the wing and gives a **bearing**, plus a near confirm (`breaker_buzz`, `unit_size 9`) that only resolves in the last room or two and distinguishes "right branch" from merely "right direction". Both are continuous loops at the breaker, self-restarting via `finished → play` (every `.wav.import` here is `loop_mode=0`); both generated by `tools/make_sfx_extra.py`. Pattern lifted from `backrooms_zone2.gd`, whose header comment is a post-mortem of this same mistake. The 8–12 s `breaker_spark` transient stays on top as flavour only
  - ⚠️ **Do not re-add a proximity meter.** The old `panic_hud.set_breaker_proximity()` hot/cold bar is **deleted**. It solved the wing outright — and being straight-line-distance-only it also lied, reading a warm ~0.43 from inside a dead end. Worse, it masked the fact that `_spawn_dark_breaker_tell()` was a **one-line stub** that spawned nothing at all, for several sessions (ISSUES_SOLUTIONS Issue 34)
  - **The payoff — a scare 5 s after the flip** (`_on_nook_breaker_flipped`, hooked to *that breaker's own* `flipped`, never to the shared 3/3 counter: the player picks the order, so "the third one flipped" needn't be the one standing in the dark). Beat: the beacons **stop and free** the instant the lever throws (the hum you navigated 50 m by dies with the equipment) → `nook_breath` starts, repositioned every frame to 1.1 m behind the player's head (`unit_size 3.0`) so it follows if they walk → at t+5 s an arc-flare `OmniLight3D` + `lab_nook_figure.png` billboard alpha-tweened 0→1 for 0.15 s → t+5.25 the short positional `nook_scream` + `jolt_camera` → t+5.55 `Screamer.flash_scare(lab_nook_face.png, "dark_jumpscare", 1.6)` + `NOOK_SCARE_PANIC = 20`. The two sounds are staggered 0.30 s (not 0.15) so the near one reads as *it moved* before the sting reads as *it's on you*; `flash_scare` never stops its audio, so `dark_jumpscare`'s 3.5 s tail deliberately keeps ringing after the picture drops.
  - **The wing lights up afterwards** (`_light_the_wing()`, called from `_nook_cleanup`): the flashlight-lock `Area3D` is freed, `unlock_flashlight()` is called, and the **ten wing rooms** fade to `WING_LIT_ENERGY 0.5`. Playtest 2026-07-26: *"after the jumpscare we need to turn on the light — because very hard to escape the place"* — the log showed 110 s of wandering afterwards, ending in a dead end. Partly this feature's own doing: throwing the breaker kills the beacons, so the scare removed the only landmark and then asked for a 50 m walk back in the dark. The darkness was never the point in itself; it was the cost of the navigate-by-ear puzzle, and that puzzle is *solved* the moment the breaker is thrown. ⚠️ This is a deliberate, narrow exception to Issue 36 covering `WING_ROOMS` **only** — the Morgue is in `NO_LAMP_ROOMS` too and must stay pitch black, because its `DarkZone`, beartrap and two don't-look triggers all assume a room searched by torchlight ⚠️ **Deliberately SURVIVABLE** — no rule, no fail state. Flipping this breaker is mandatory, and an unavoidable event must never coin-flip a death; a player who can't SEE a figure materialise also can't judge "hold still or flee" (the KONTUR Gate 7 / Backrooms Flood mistake). The cost is real anyway: 20 of `PANIC_MAX` 50, then ~50 m back through the maze, where sprinting is +6/s with decay suppressed
  - ⚠️ The figure is **unshaded**, so the flare cannot light it — unshaded materials ignore lights entirely. (⚠️ 2026-07-27: the rest of this sentence used to claim *"nothing in this project casts shadows"* — that is **false**. The player's flashlight is a `shadow_enabled` `SpotLight3D` in all nine level scenes and renders real cast shadows; only the static `OmniLight3D` room lamps don't cast, which `level_1.gd:173-175` deliberately relies on. See `GAME_MECHANICS_IDEAS.md` §2.0a.) Its **alpha** is what's driven; the flare only throws the walls into relief. And `lab_nook_figure.png` must stay a real RGBA cutout or it billboards as a solid rectangle (the `apparition_figure.jpg` bug). `_place_nook_figure()` fans raycasts — ahead, ±90°, then behind — and takes the first direction with ≥1.8 m clearance, because the breaker is on the west wall and a naive forward spawn lands *inside* it; in practice it lands behind the player, between them and the way out
  - Verified by `tests/walk_lab_wing.gd` — drives a `CharacterBody3D` the whole route under gravity and proves each dead end dead with raycasts against the built CSG, never against the `DOORS` array that produced it — and by `tests/screenshot_nook_scare.gd`, which polls for the figure's alpha and for Screamer's panel to photograph both moments (a frame counter can't catch a 0.2 s window)
  - The Lab's `DEBUG_APPARITION` fatal-apparition timer is suppressed for the whole wing (`_in_breaker_nook` flag checked in `_tick_debug_apparition`) — a player who can't see the apparition materialise has no fair way to judge "hold still or flee," the same double-jeopardy mistake KONTUR Gate 7 and the Backrooms Flood already made once each
- **Guarded keycard** in the dark morgue (a `DarkZone` + a `Beartrap`): the card sits on a cart *between* the surgical tray and the face-monitor (both `trigger_object.gd` — instant fail on E or 3 s gaze), with a cursed poster (`poster_lab.png`, gaze panic) on the wall. Taking it fires `on_keycard_taken()`: 1.6 s light-blackout stutter + creak + 8 panic. **BUG_FIX.md 4.2**: the monitor trigger moved off the cart onto the morgue's east wall (`wall_point("Morgue", Vector2(1,0), …)`, `y_rot=PI/2` so its -z-facing screen quad turns to face -x into the room) — the wall directly opposite the only doorway (west, x=6), so it's the first thing visible on entry instead of something found at an angle on the cart. The tray is unaffected
- **Observation room**: a one-way mirror (`living_mirror.gd`) — a figure appears in the glass only when you are NOT looking head-on
- **Scares**: random blackouts (all lamps stutter dark ~1.5 s) and pipe groans (`pipe_groan.wav`) on timers; a taught **HOLD apparition** (`apparition.gd`, `teach=true`) armed by a `CorridorEvent` in the main corridor
- Win: restore power → take keycard from the morgue → exit door (`KEYCARD`). Fail: trigger object, apparition rush (if you sprint), or panic bar fills

**Level 2 — The House (abandoned domestic interior)** — rebuilt procedurally (Session 10)
- Built at runtime in `level_2.gd` via `RoomBuilder` from an 8-room ground floor (entry hall, hallway, living room, kitchen, landing, bedroom, bathroom, child's room) **plus a gently-lowered CELLAR** (`_build_cellar()`, floor at y=−1.5) reached by a walkable ramp. Same `.tscn`-minimal / `PRESERVE`-whitelist pattern as the Lab
- **Cellar key sub-quest**: a glowing `KeyItem` (`key_item.gd`) → `picked_up` → the player is now
  *carrying* the key (`GameState.set_carried`, shown on the HUD); the `CellarGate` (`cellar_gate.gd`)
  only opens when they walk down and press **E** on it. ⚠️ `picked_up` used to be wired straight to
  `_open_cellar_gate()`, so winning the Bathroom minigame flung the cellar open from the other end of
  the house and the key was a formality (BACKLOG #16). ⚠️ The ramp/shaft/ceiling use `rotation.x = -angle` (a +angle inverts the slope and drops the ceiling to knee height); the key sits clear of its (collision-less) stand so the interaction ray reaches it. **Session 11 fix (two parts):** (1) the ramp's TOP SURFACE is now continuous with the floors at both ends — it starts at z=1.7 where `RoomBuilder`'s doorway floor-bridge ends (both at y=0) and the bottom is extended 0.6 m under the cellar floor — so there's no end-lip to climb (`move_and_slide` can't step up; a tilted box poking ~0.14 m above the floor was the real "can't enter the cellar" block, *not* headroom). (2) The sloped ceiling is offset a constant 2.6 m along the ramp normal (~2.45 m vertical clearance) and a flat `CellarShaftCap` at y=3 seals the top; the ramp wears `house_wood_stairs.png`. Verified walkable BOTH ways by `tests/walk_cellar.gd`. **BUG_FIX.md 4.3** first moved the key into a 2-drawer search in the Landing; a later session **replaced that entirely** with a bigger quest, so Landing is empty again (a deliberate trade). **Current feature**: a folded paper map (`HouseMap`, `house_map_prop.gd`) on a stand in the **Bathroom** (`_spawn_bathroom_map()` — it moved Landing → Kitchen counter → Bathroom; the objective string at `level_2.gd:88` has now been wrong twice, so re-check it whenever the quest moves) opens a full-screen, paused 2D maze-chase minigame (`MazeChaseUI`, `maze_chase_ui.gd`) — a fresh 10×8 **braided** randomized-DFS maze every attempt (never memorizable). ⚠️ **BRAIDED since 2026-08-15** — `_braid()` opens 55 % of dead ends into loops, because the user asked to "make more space so that you can actually bypass the monster" and in a PERFECT maze that is topologically impossible, not merely hard. `dungeon_gen.gd` already carried the same lesson. Also new: a **patroller** (a second monster that walks a circuit *off* the player's likely route and only gives chase within `PATROL_AGGRO`, slower than the hunter — measured, a patroller wandering to random cells cost 9 seeds in 40 by standing in the corridor, which is a roadblock, not a threat), **snares** (`SNARE_COUNT` 5, off-route, pin the icon 1.2 s for 3 panic — never a second fail state), and a looping **chase track** (`chase.wav`, trimmed and crossfaded by `tools/make_loop.py`, on an `AudioStreamPlayer` child of the CanvasLayer so it survives the tree pause; Master bus, matching `combination_lock.gd`; stopped in `_close()` **and** `_hide_after_external_unpause()`). ⚠️ **Escape rate is now 26/40, down from 37/40, deliberately** — asked whether to hold the old difficulty, the user chose harder. The isolation numbers and the lowered 55 % floor are recorded in `check_maze_chase.gd`; ⚠️ that harness drives `_tick_monster()` directly, so it had to be taught to tick the patroller and the snares too, and its bot had to be taught to walk AROUND a monster, or it measured the old build and reported no change at all, dragged toward a BFS-longest-path target with the mouse while a monster icon hunts along the ACTUAL CORRIDORS (BFS distance field from the player's cell,
recomputed when they change cell; `MONSTER_SPEED` **172**, raised from 88 → 132 → 172 across two
playtests on the user's call — measured each time with `tests/check_maze_chase.gd` (40 seeds), and
the escape rate never moved: 37/40 at all three speeds. What changed is how fast a mistake is
punished — hunted down 9.4 s after stopping at 132, **5.2 s at 172**. ⚠️ Do not raise it again
without re-running that test. ⚠️ **37/40 was the line while the hunter was alone; the roster is now hunter + patroller + snares and the measured rate is 26/40**, with the asserted floor at 0.55 (22/40) — see `check_maze_chase.gd`, which carries the isolation numbers. Do not read 37/40 as a current target). ⚠️ It used to steer by a raw Euclidean
beeline, which in a randomized-DFS *perfect* maze points into a wall most of the time — the corridor
route is routinely 5-15x the straight line — so it jammed and could never close once the player left
the start (BACKLOG #14: "it can basically kill the player only at the beginning"). ⚠️
`_place_monster()` now also avoids the FIRST STEP of the only route to the target: in a spanning tree
that cell is a roadblock the player cannot walk around — harmless while the monster drifted into
walls, a measured 12-in-40 instant death once it followed corridors. The drag eases toward the cursor on an exponential spring rather than snapping, and both the ease rate and the speed cap degrade as panic rises (`SPRING_K_BASE=9.0→SPRING_K_PANIC=3.0`, `PLAYER_MAX_SPEED=240→PLAYER_MIN_SPEED=100`) — releasing the mouse freezes the icon instantly, no glide, so letting go never costs an unwanted catch. Panic climbs the whole time it's open: a flat `MAZE_DRIP_RATE=0.9`/s plus a squared proximity term up to `PROXIMITY_MAX_RATE=5.0`/s, via the same "a paused UI's own `_process` still calls `player.add_panic()`" idiom `note_ui.gd` uses for trap notes — which means the UI **must** self-clear if a screamer fires and unpauses the tree out from under it (Issue 9 guard, copied verbatim from `combination_lock.gd`/`note_ui.gd`). Winning calls the unchanged `_build_cellar_key()` at the counter's other end for a real 3D pickup; getting caught (`CATCH_RADIUS=20px`) ejects back to 3D with a jolt + `CATCH_PANIC=18` (bracketed between beartrap.gd's own 15/40 spring-vs-fail values) and the map is retryable. `house_drawer.gd` (the superseded Landing search) was deleted as dead code. ⚠️ **Legibility (playtest 2026-07-25, capture #3)**: the caption was added as a second child of the `CenterContainer`, which overwrites every child's anchors/offsets — so it landed stacked dead-centre ON the parchment in a cream that matched it. It now hangs off `_root` with a black outline (`ScreenText._outline()` convention). The three icons are 1024x1024 PNGs whose ink fills only ~30-40% of the canvas, in the same sepia as both the parchment and the wall rects, so each renders as ~28 px of near-invisible scribble; `modulate` cannot fix that (it multiplies — no multiplier turns brown into saturated blue), so `_make_icon()` now stacks a dark halo disc + a bright identity disc sized to `ICON_HALF_EXTENT` + the ink on top. See ISSUES_SOLUTIONS Issue 32. Verified by `tests/screenshot_maze_ui.gd`, which drives the real `interact()` path — `screenshot_scene.gd` structurally cannot reach a UI behind a prop. Maze generation is stress-tested independently of any scene by `tests/check_maze_gen.gd` (200 random seeds: full connectivity, non-trivial target distance, valid monster placement) — the minigame is only ever opened via player interaction, so a normal scene smoke test never exercises `_generate_maze()` at all
- **THE GUEST (2026-07-28/29) — the house rearranges itself, one step per quest milestone.** The
  House is the only level with genuine backtracking pressure (Bathroom map → key → Kitchen → cellar
  → ChildRoom lock crosses the ground floor repeatedly), and this is what that traffic is for:
  | milestone | what changes |
  |---|---|
  | map solved | the bedroom **painting falls off the wall** — while you watch, within 4.5 m and facing it, with `painting_fall` at +8 dB and a camera jolt |
  | key taken | (nothing) |
  | cellar gate opened | arms **the cellar sequence** (below) |
  | third note read | the **music box** has moved to the Hallway, still playing, between you and the exit |
  - ⚠️ **The music box move is the ONE beat still on `MovedProp`'s off-screen rule.** The painting,
    the cellar child and the Intro wheelchair were all moved to happens-in-front-of-you on playtest
    feedback across two sessions. In rooms this dark an anomaly nobody witnesses is one nobody gets;
    the music box survives because it is meant to be *discovered* on the way out, not watched
  - The music box is a **real object** (`music_box.gd`) with the loop as its CHILD — that is the only
    reason the sound travels with it. It used to be a bare `_loop_audio` with no body at all. **E
    winds it**: the crank turns and the tune comes up out of the room tone for ~22 s, re-windable
- **THE CELLAR SEQUENCE** — three scripted beats on reaching the bottom of the ramp, timed to the
  user's spec: every lamp AND the torch die instantly → **5.5 s of nothing** → the child, screaming,
  ~3.2 m in front of wherever the player is facing → **3.0 s later** the lights return and it is gone
  - ⚠️ **The dark-zone and standstill taxes are SUSPENDED for the whole sequence**
    (`player.set_smiler_active(true)`). The cellar is a `DarkZone`, so forcing the torch off would
    otherwise charge +3/s for a scripted event with no counter-play — Issue 18, and the player died
    there at 99 % panic on the run that prompted this
  - The figure is a `Watcher` (zero panic, no collider, no rules) at **1.95 m** — deliberately taller
    than a child, because at child height it read as small and far away rather than on top of you.
    `childe_scream` at +18 dB with `max_db` raised to 24, or the gain is clamped away
  - ⚠️ Two earlier placements FAILED SILENTLY and both are worth remembering: spawning it on the
    milestone put it two rooms from the player, `Watcher.spawn()`'s line-of-sight check failed
    through the walls, it returned null and the one-shot flag was already set — no figure, no
    scream, no darkness, ever. Spawn a scripted beat where the player IS
  - ⚠️ **Only ONE figure down here.** The atmosphere pass also put a `Watcher` in the far corner;
    it was cut, because the mood piece arrived first and spent the surprise the event needed
- **The Kitchen** (42 m², previously ONE prop): sink, table and chairs built from real parts, plus
  a **fridge** (`house_fridge.gd`) — it hums, and on E the scream fires FIRST, the door swings 0.28 s
  later, and a head is revealed on the shelf as it clears. **10 panic, the only new panic term in the
  whole atmosphere pass**; voluntary, optional, off the quest path, one-shot, and inert afterwards
  - ⚠️ The carcass is an **open-fronted shell of five slabs**, not a solid box — see Issue 46
- **The kitchen drawer** (`kitchen_drawer.gd`) carries a second, independent hint for **KONTUR Gate 1**
  ("the black door is the way out, the red one is not a door" — the rule, never a position, since the
  colours swap per run). Gate 1's only other hint is in the Lab morgue behind a beartrap and two
  instant-fail objects, and getting it wrong BANISHES rather than costs a strike
- ⚠️ **Furniture is built from PARTS, never one flat box.** Two rounds of playtest photographed the
  beds, chairs, table and music box and called them "boxes that do not make any sense". What makes a
  bed legible is the headboard and a mattress proud of the frame; what makes a chair legible is the
  back. Issue 35 in furniture form. The cellar's shelving/boiler/crates and the kitchen sink slab
  were **deleted** rather than rebuilt — they sat in near-total darkness and read as nothing
- 3 safe notes (one digit each — **the third is in the cellar**, forcing the descent), 2 trap notes (`is_trap`, read-to-die)
- Win: read the 3 safe notes, enter code **472** on the combination lock by the child's-room exit (`CODE_ENTERED`)
- Fail: read a trap note **fully**; the apparition rush; or panic bar fills. Read-to-die: trap notes feed +12 panic/s while open (`TRAP_PANIC_RATE` in `note.gd`, ticked by `note_ui.gd`); text bleeds red; close early to survive
- **The window + Forest scare** (`_spawn_window()`): a moonlit forest (`forest.png`) behind glass on the living-room north wall (quads rotated PI to face the room, inset 0.25 to sit proud of the wall, culling disabled). Press up (≤1.5 m) → SURVIVABLE `flash_scare(screamer_forest.png)` + jolt + 25 panic
- **Scares**: cursed props (bedroom painting 0.8, living-room mirror 1.2) + a TV-static gaze panel (`tv_static_face.png`); a one-way mirror (`living_mirror.gd`) in the bathroom; a music box (`music_box.wav`) in the child's room; the cellar is a `DreadZone`+`DarkZone` with water drips, a beartrap, and a non-teach HOLD apparition; pipe groans + random blackouts on timers; 3 `CorridorEvent` triggers (door slam +8, footsteps overhead +6, bedroom light dies +6 → `DarkZone`)
- **Lock penalty**: each wrong combination = harsh buzz (`lock_buzz.wav`) + 10 panic — brute-forcing the lock is itself a fail path

**Level 3 — The Corridor (haunted hotel hallway)** — inspired by *The Corridor* (2012)
- ~320 m zigzag hallway built **procedurally** in `corridor.gd` from `PATH_2D` (7 segments, 90° turns, 3 m wide). Three zones: A "Hotel" 0–90 m (intact, lit torches every 12 m, paintings, grandfather clock), B "Decay" 90–230 m (blood smears, lights shatter, beartraps in the dark stretch), C "Nightmare" 230–320 m (dead torch panels, the mirror, constant whispers, near-black — geometry/lighting only; the `DreadZone` panic mechanic covers just the last 60 m, see below)
- **No fetch quest** — exit door (room 217, `door.png`) has `unlock_condition = NONE`; walking the corridor without panicking IS the test
- Panic pressure: `CorridorEvent` triggers add panic directly (entry door slam +10, clock chime +10, silhouette crossing the far junction +20, floor crack +10); `DarkZone`s add +3/s while flashlight is off; `Torch3D` calm zones decay panic ×2.5; cursed gaze panels (paintings 0.8/1.2, clock 1.0, side-wall `mirror.png` 2.0/2.5); 5 beartraps = snap + 15 panic + **escape mechanic** (see Beartrap below)
- **Turn mirrors** (`_spawn_turn_mirror` in `corridor.gd`): `mirror_with_creature.png` set flush on the wall you face at the 90/230/275 m corners — miss the turn and you walk into the creature head-on. Gaze panel (intensity 1.5–2.2) **plus** a one-shot close-up `flash_scare(mirror_with_creature.png, "glass_shatter")` + jolt + 12 panic when you come within 2 m (`_turn_mirrors` proximity-tested in `_process`)
- **The Manager** (`_ev_manager`): a SURVIVABLE scare that strikes once at a random mid-hall point. A `CorridorEvent` is dropped at `randf_range(80, 180)` m (distance-triggered, not wall-time, so it always fires regardless of walk/run speed) → `flash_scare(screamer_manager.png, "screamer_manager")` + jolt + 25 panic
- **Zone C dread** (260–320 m, `DreadZone` spawned by `_spawn_dread_zone()`): decay weakens to `DREAD_DECAY_RATE` (2.0/s) and a constant `DREAD_PANIC_RATE` (2.0/s) pressure accrues regardless of anything else — the two cancel exactly, so panic just holds flat rather than draining, making the last 60 m an endurance stretch. **Shortened from 230 m (Session — difficulty fix)**: the old 230–320 m dread zone left no room to decay off the silhouette/floor-crack panic before the flat stretch began. ⚠️ **Don't re-add a `DarkZone` over any part of the dread zone** — `player.gd` stacks dark-zone tax (+3/s) additively on top of dread pressure, and the noclip ending force-kills the flashlight for the final ~10 m with zero player agency to avoid it, so a `DarkZone` there was a guaranteed +5/s with no way out (also reachable by simple battery attrition — 240 s max, easily burned by beartrap QTEs earlier). This is what made the level read as "impossible" — fixed by dropping `DARK_ZONES`'s old second entry (240–318 m) entirely
- One framing note at the entrance ("Hotel Vesper — The Management"); 3 fake locked doors (`fake_door.gd`) that knock back (+8 panic, first try only) + 6 non-interactive decor doors. All non-final doors use `ordinary_hotel_door.png`; **only the exit (room 217) keeps `door.png`**
- Corridor-exclusive screamer: `screamer_hotel.png` — kept OUT of `screamers/`; `screamer.gd` selects it when `GameState.current_level == 3`
- Prop textures (`door/clock/mirror/torch.png`) share the same baked wallpaper+wainscot background as `wall.png`, so they're applied as full-height wall panels that blend into the wall texture

**Level 4 — The Backrooms (liminal mono-yellow maze)** — `backrooms.gd` + `backrooms.tscn`
- **Entry = the noclip** (`_spawn_noclip()` in `corridor.gd`): the player never reaches room 217 — which now wears `backrooms_tear_door.png`, a black-wood door torn open on a red-lit void, sized from the artwork's own aspect. **Fifteen** metres out every torch dies and `player.kill_flashlight()` force-kills the light (F now only plays a dead-battery click), and the floor gives way **5 m short of the door** (user's call, 2026-08-15 — you see it, you never touch it). ⚠️ **It is a REAL fall (2026-08-15)**: `_ev_noclip_fall()` zeroes the player's `collision_mask`, so gravity takes them straight through the floor (measured 6.96 m in 1.2 s); input is frozen, the screen fades at −3 m and the Backrooms takes over at −9 m. It used to fade to black and wait 2 s with the player standing still, which is not a fall. No hole is cut: the corridor floor is one CSGBox3D per 45 m segment, and the blackout killed every light 10 m earlier so nobody could see one. ⚠️ **Three constants move together** — `NOCLIP_FALL_BEFORE_DOOR`, `NOCLIP_ONSET_BEFORE_END` and `RETURN_MARGIN` (14 → **18**). Re-entry from the Backrooms must land clear of BOTH trigger boxes or arriving re-fires the blackout, or the fall bounces the player straight back. `tests/check_noclip_fall.gd` asserts the relationships rather than the numbers, so any one of them can be retuned but not alone
- **Cyclic maze, no seamless portals** (design Q1): a 4-way intersection hub with three choice arms (N/E/W) built from `CSGBox3D`, triplanar `backrooms_wallpaper_albedo` walls + `backrooms_carpet_albedo` floor, recessed flickering fluorescents. The E/W arms dead-end in a `LoopBack` trigger that teleports you to an identical re-randomised hub — so it reads as an endless series of intersections without any continuous-portal seams
- **Win — three down-turns** (`_assign_round`, `_on_arm_entered`): `arrow_decal.png` on the hub columns marks exactly one arm with a DOWN arrow each round. Take it to advance the loop counter; the E/W arms loop back, and on the 3rd correct turn the win arm (N) is forced and opens into the exit utility room. The **glitch wall** there runs a screen-space vertex-jitter shader (`glitch_wall.gdshader`); walking into its `ExitTrigger` Area3D → `advance_level()` → The Void
- **Fail — wrong turn**: entering a non-down-arrow arm = `light_pop` + 15 panic + counter reset + teleport to the start (`_wrong_turn`). **Standing still** > 4 s raises panic (`player.enable_standstill_panic()`, +3/s) — the maze forbids rest. Plus the usual panic-bar-fills death
- **Dynamic dark zones**: one (always-wrong) arm goes black each round (`_apply_dark_arm` → lights off + `DarkZone`)
- **The Smiler** (`creature_smiler.gd`, ~50% per dark arm): a glowing `screamer_smiler.png` billboard at the dark arm's end. Its logic INVERTS the maze (design Q2): shine your flashlight on it **or** sprint → rush → `Screamer.trigger()` (fatal — the smiler image fills the screen via `LEVEL_SCREAMERS[4]`). Turn the light OFF and hold still (don't sprint) and it fades after 4 s. While engaged it calls `player.set_smiler_active(true)` to suspend the standstill + dark ticks and drives its own slow dread (+2.5/s) — freezing to survive is tense but fair
- **Footstep echo** (`player.enable_footstep_echo()`): every step replays at half-volume 0.4 s later, two paces behind you
- **Mirage doors** (`mirage_door.gd`): blood-red doors identical to the back doors; opening one swings onto blank wallpaper + 10 panic, mocking the hope of retreat
- **The rotary phone** (`rotary_phone.gd`): a 1970s phone on the carpet that rings (`rotary_ring`); answering (E) plays `phone_whisper` and opens a read-to-die trap note via `NoteUI.show_note(text, 11.0)` — hang up (close) to survive
- **THREE ZONES (Session 14).** One scene, three world-space offsets; each zone ends in a glitch
  wall that teleports you to the next. `backrooms.gd` orchestrates (`_enter_zone`, `_on_zone_mistake`)
  - **Zone 1 — THE LOBBY** (origin 0): the original hub + N/E/W arms. Three down-turns → its glitch
    wall now calls `_enter_zone(2)` instead of `advance_level()`. `WRONG_TURN_PANIC` 15 → 18
  - **Zone 2 — THE SPRAWL** (`backrooms_zone2.gd`, origin `(200,0,0)`): a 40×40 m pillar hall with a
    **4.5 m** ceiling — deliberately wrong-scale against zone 1's 3 m corridors. Four *identical*
    glitch walls, one real, randomised. **The tell is SOUND**: a `SilenceZone` around the real wall
    ducks the whole `"Backrooms"` audio bus to −30 dB, so you find the exit by listening. Touching a
    fake = `go_solid()` + **12** panic (`backrooms.gd:WRONG_WALL_PANIC`) + teleport + re-randomise.
    **BUG_FIX.md 3.5**: playtest read pure silence as too subtle a tell, so `_randomise_real_wall()`
    also spawns a positive cue AT the real wall, deliberately kept off the `"Backrooms"` bus so
    `SilenceZone` can't duck the very tell it provides.
    ⚠️ **That cue is `water` (`unit_size 16`) + `whisper` (`unit_size 9`), NOT `sprawl_wall_hum`.**
    This file described the hum as the tell for several sessions; the hum was a first pass at
    `unit_size 4.5`, audible only once you were already at the correct wall in a 40×40 m room with
    four identical ones, and it was replaced by the two-layer far-cue/near-confirm pattern
    (`backrooms_zone2.gd:187-225`). **`sprawl_wall_hum.wav` is still generated by
    `tools/make_sfx_backrooms.py:97` and is referenced by no `.gd` file at all** — it is an orphan.
    Do not "restore" it without re-reading that comment; the wide range is the whole point
  - **Zone 3 — THE FLOOD** (`backrooms_zone3.gd`, origin `(-200,0,0)`): an 8-room flooded wing built
    with `RoomBuilder`, ankle-deep water (`apply_slow` refreshed per frame), near-black.
    ⚠️ **The water is a BED, never a per-step sound** (2026-08-15, user's call, twice). The zone
    used to swap the player's footstep sample for `wade_step` — a synthesized splash+thud at
    0 dB, at the ear, on the un-duckable `Body` bus, every 0.5 s — against a `water.wav` bed
    measuring **−39.6 dBFS RMS** that at its shipped −6 dB was inaudible. The zone announced
    wading twice a second and never sounded wet. Now: no footstep swap anywhere, and eight
    `WaterBed_*` loops (one per room, `WATER_BED_DB` **+14**, `max_db` 3.0, staggered start
    offsets so eight copies of one loop don't comb-filter). ⚠️ **Set a bed's gain from the
    FILE's measured level** — `water.wav` sits ~20 dB below every other asset here, so a
    volume_db that reads as sensible means nothing. `tests/check_backrooms_audio.gd` measures
    the source WAV and asserts the result clears an absolute floor
    - ⚠️ It also cost P10's stated anchor (*"what you hear in the distance has to be audibly
      the same ACT you are performing"*). `UnseenWader` is unchanged and still reads, because
      the water it wades through is now the thing you can actually hear **The tell is
    DARKNESS**: the real seam is visible only with the flashlight OFF; two decoys glow only with it
    ON. The zone is a `DarkZone`, so searching costs +3/s. Clearing it → `advance_level()` → KONTUR.
    Two non-teach HOLD apparitions (`Apparition.spawn`, `Rule.HOLD`, `teach=false`): one in the Throat,
    and (**BUG_FIX.md 4.4**) a second, identical in setup, in the Sump — the deepest, most remote room,
    which also holds the real seam — added after playtest read the zone as "nice vibe, not packed
    enough with action" despite the Throat encounter
  - Each new zone has exactly **one `CalmZone`** anchor (lit island / dry platform) — three
    net-positive-panic zones back to back is otherwise unsurvivable
- **Audio mix (Session 14)**: music −14 → **−4 dB**, hum −8 → **−12 dB** (the score now LEADS by
  8 dB); both routed through a runtime `"Backrooms"` bus so `SilenceZone` can duck them together;
  loop flags enabled in the `.import` files; `rotary_phone`/`mirage_door` emitters given explicit
  `volume_db` (they were an unset 0 dB, louder than everything else)
- Win: three zones, three glitch walls. Fail: wrong turns/wrong walls/standing still/the Smiler/a
  read-to-end phone call → panic bar fills

**Level 5 — KONTUR ("Object 12")** — `kontur.gd` + `kontur.tscn`
- **The level whose answers are not inside it.** **Eight** gates, each a *different verb*, each
  answered by a hint planted in an earlier level. A player who explored reads straight through; one
  who rushed must guess, and guesses cost panic they cannot get back. Built procedurally by
  `kontur.gd` via `RoomBuilder` from a 13-room spine (Landing → Vestibule → **AnteWest/AnteEast** →
  Passage → Kitchen → **Records** → Archive → **Switchboard** → **Blackout** → Airlock → Escort →
  Terminus, z −4…98), same `.tscn`-minimal / `PRESERVE`-whitelist pattern as the Lab and House
- **Visual arc = the story**: peeling Soviet wallpaper (`kontur_wallpaper_soviet`) → raw infected
  concrete (`kontur_concrete_infected`, the `CONCRETE_ROOMS`) → clinical KONTUR tile
  (`kontur_facility_wall`, the `FACILITY_ROOMS`, which reuse `lab_floor`/`lab_ceiling`). Done entirely
  with `RoomBuilder`'s per-room `wall_mat`/`floor_mat`/`ceil_mat` overrides in `_rooms_with_skins()`
- **Gate 1 — THE TWO DOORS** (`choice_door.gd`, *choose*): a black and a red door in the vestibule.
  Which side is black is **randomised per run**, so the answer is the colour, never a position. The two
  doors open into **two separate antechambers**, and `_open_the_void()` deletes the floor behind the red
  one — the wrong door is a **hole**, not a decoration. Hint: hidden note in the **Lab morgue**
- **BANISHMENT** (`_check_void_fall` → `_banish`, threshold `y < −4`): falling out of the world does not
  kill you, it **demotes** you. `GameState.kontur_banished` is set (it survives the transition because
  `reset_level_state()` deliberately doesn't clear it, the same trick `is_ending` uses), `current_level`
  drops to 4, and `backrooms.gd:_check_banishment()` greets you with a blood-red scrawl — *"YOU DIDN'T
  READ. THE COLOUR WAS WRITTEN DOWN SOMEWHERE YOU DIDN'T LOOK."* — then clears the flag so it shows once
- **Gate 2 — THE SHELF** (`bottle_item.gd` + `fungal_barrier.gd`, *use*): three bottles (vinegar /
  bleach / water) on the kitchen shelf, and a fungal mass sealing the way on. Vinegar dissolves it
  (canon: acetic acid retards O-41); a wrong bottle is **consumed**, so a bad guess costs a walk back
  as well as a strike. Hint: the **House TV** static resolves into a KONTUR test card every ~16–26 s
- **Gate 5 — THE ROSTER** (`combination_lock.gd`, *recall*): a personnel gate in Records welded shut
  until you enter **`ROSTER_CODE`, currently 63**. ⚠️ Was **47** ("You are Subject 47", the intro
  note) until BACKLOG #24 — which made the one gate designed to be answered from memory into the one
  gate nobody had to look for, since the answer had been on screen in the first minute and sat in the
  level's own objective text. The code now has **no other source anywhere in the game**: both digits
  are on two notes in the **Backrooms Flood**'s side runs (WestRun / EastRun,
  `backrooms_zone3.gd:_build_digit_notes`), deliberately off the route from the Descent to the Sump,
  so clearing KONTUR requires having actually searched the flooded wing a level earlier. That is a
  hard dependency; the notes journal and the level-progress snapshots are what keep it fair. Nothing
  in KONTUR states the number; the plate just leaves the field blank. The lock now **sizes itself from its answer**
  (`_digit_count()` in `combination_lock.gd`) — it used to be hard-coded to 3 dials, and "47" on a
  3-dial lock is ambiguous (047? 470?); a playtester who knew the answer still failed it twice. The
  lock gained `code` / `title_text` / `unlocked` / `wrong_code` so it can serve two levels without
  touching `GameState.level2_code`. **Rebuilt 2026-07-25** (capture #5, "the 2d texture on top of a 3d random cube"): the casing carried
  green emission at 0.4, which — emission being most of a surface's colour here — rendered it as a glowing
  mint box with a picture stuck to one face, and the art quad squashed a 1.5:1 landscape source onto a
  0.75:1 portrait mesh. It is now a **landscape** body with a four-bar bezel RIM (a solid bezel slab buried
  the plate — its face landed ~2 mm from the artwork), corner screws, a recessed `kontur_lock_roster.png`
  plate sized from the source aspect, and a real dial `CylinderMesh` laid on its side beside it. Body
  emission is gone; the **art quad** carries 0.35 instead, since this is still a gate that must be found on
  a dark wall (Issue 27's documented split, Issue 33). `combination_lock.gd`'s 2D dial UI is untouched
- **Gate 3 — THE OFFERING** (`offering_pedestal.gd`, *abstain*): a keycard glowing on a lit pedestal,
  deliberately identical in read to the Lab keycard the player has spent five levels being trained to
  grab. The exit is **already open**. Taking it **forfeits the run**; walking past is scored silently on
  entering the Switchboard. Hint: the **Corridor** door plate at d=172 m ("RECOVERED ITEMS ARE BAIT")
- **Gate 6 — THE PHONE** (`rotary_phone.gd`, *destroy* — was *ignore* until **BUG_FIX.md 4.6**): a
  phone rings for a whole room's length in the Switchboard. Answering still **forfeits the run**
  instantly, unchanged. What changed: simply not answering is no longer enough — while the phone
  rings unresolved, `_tick_phone_pressure()` drains `PHONE_PRESSURE_RATE=4.5`/s panic on anyone within
  `PHONE_PRESSURE_RANGE=7 m` of it, and KONTUR's floor-wide DreadZone cancels decay exactly everywhere,
  so that pressure only ever accumulates. The fix is a **Hammer** (`KeyItem`-pattern pickup, billboard
  QuadMesh from `kontur_hammer.png`) planted in Landing near the level entrance; carrying it flips
  `RotaryPhone.smashable = true`, and `interact()` then calls `_smash()` instead of answering — stops
  the ring for good and fires `smashed` → `_pass_gate("phone")`. A diegetic note by the desk
  ("THESE PHONES... IF YOU CAN'T ANSWER IT, BREAK IT") explains why a hammer is the answer. Hint: the
  **Backrooms** phone is a read-to-die trap. `RotaryPhone` gained `smashable`/`smashed`/`_smash()`,
  defaulting off so Backrooms' own phone (the only other caller) is unaffected
- **Gate 7 — THE BLACKOUT** (*unlight*): an unlit room with three door seams on the far wall. The real
  one is visible **only with the flashlight OFF**; the two that glow under the beam are painted on and
  cost a strike. ⚠️ **No `DarkZone` here** — a room solved by turning the light off must not also tax
  the light being off (+3/s *and* decay suppressed, +5/s with the level DreadZone). Issue 18. The Airlock/Escort/Terminus spine is **built at whichever of three x offsets was
  drawn**, so the answer moves every run. Hint: the **Backrooms Flood**, and (**BUG_FIX.md 3.2**) a
  second one inside KONTUR itself — the Landing mailbox, upgraded from a flat wall decal to a real
  interactable (`KonturMailbox`, `kontur_mailbox.gd`), opens on a note: *"I stopped switching them on.
  I am too afraid of what the light finds..."*
- **Gate 8 — THE AIRLOCK** (*catch* — was a 9 s stillness *wait* until **BUG_FIX.md 4.7**): playtest
  read the old hold-still cycle as "boring, you just stand and wait." Replaced with a catch minigame
  on the same wall meter: a marker oscillates across a fixed track (`AIRLOCK_MARKER_PERIOD=2 s` per
  full sweep) and pressing **E** while it's inside the lit target band (`AIRLOCK_TARGET_WIDTH=35%` of
  the track, centred) counts as a catch; `AIRLOCK_CATCHES_NEEDED=3` in a row passes the gate. A miss
  calls the level's normal `_strike()` — a full `STRIKE_PANIC=18` that counts toward the 3-strike
  limit — `⚠️ DELIBERATE`, confirmed with the user, who understood 3 mistimed catches alone could end
  the run before choosing this over a softer custom penalty. This still **inverts** the Backrooms rule
  that standing still raises panic, and no earlier level hints at any of it — so unlike every other
  gate it still has to **teach itself**, now via the visible track + marker instead of a fill bar
- **Gate 4 — THE ESCORT** (`escort_gate.gd`, *camera discipline*): 26 m with the lights dead behind you.
  Heading may not stray more than `LOOK_LIMIT_DEG=100°` from the corridor axis; `COOLDOWN=3 s`. The
  **first look is free** (`ARM_AT=0.16`) and emits `warned` instead — the lights dying behind you is
  itself an invitation to turn, and a playtester forfeited 1.5 m in, before the temptation or the sign.
  The rule's sign hangs in the **Airlock**, read while standing still for gate 8, not inside the
  corridor it governs. **The
  rule now has teeth**: a `tempt(stage)` signal paced on *distance* (`TEMPT_AT = [0.18, 0.45, 0.72]`,
  measured on progress so a cautious and a brisk player both get all three) fires footsteps behind you,
  then a whisper, then a blood-red **"LOOK BEHIND YOU"** on the screen. It is a lie, and obeying it
  forfeits the run. Diegetic first, text last — a UI that lies about something you can already *hear*
  reads as the level's voice rather than as a cheap trick. Hint: **Backrooms** east-arm dead-end scrawl
- **The exit actually locks** (Issue 16): `_make_door` used to leave `unlock_condition = NONE`, so the
  level was completable having failed or skipped every gate — it cleared in **32 seconds**. `door.gd`
  gained `extra_lock` + `locked_message`; `kontur.gd` holds a `_gates` ledger and `_refresh_exit()`
  keeps the door sealed until all eight pass, naming the shortfall on the door itself
- **FORFEIT**: the three *abstain* gates (offering / phone / escort) cannot be un-failed, so failing one
  voids the run — `_forfeit()` fires a scrawl, rewrites the objective **and** the exit door's locked
  message within a second. That loudness is load-bearing, not polish: a sealed door with no explanation
  reads as a bug rather than as a verdict
- **Fail economy (unique to this level)**: the whole floor is one `DreadZone` (sized to span z −4…98 —
  a short zone silently stops applying partway down the spine). `DREAD_DECAY_RATE` and
  `DREAD_PANIC_RATE` are both 2.0/s in `player.gd`, so they **cancel exactly** — panic never drains
  here. Each wrong answer is `flash_scare(kontur_flash.png)` + jolt + `STRIKE_PANIC=18`. Three strikes
  = 54 > `PANIC_MAX` (50), so `add_panic()` fires the fatal screamer on its own. **There is no bespoke
  death path in `kontur.gd`**, and no `player.gd` changes were needed for any of it
- **Redacted signs** (`_make_sign`): each gate's rule is stated on a wall plate with the operative word
  replaced by a censor bar, so a player who missed the hints gets the shape of the question but not the
  answer. Text is `Label3D` over `kontur_sign_blank.png` (faintly emissive so it reads in the dark);
  the redaction is a black quad on its own line, which needs no text measurement to place.
  ⚠️ `wall_point()`'s inset is measured from the room's NOMINAL boundary, but the wall's inner face
  is `T/2` (0.1 m) in from that — so clearance = `inset − 0.1`. An inset of **0.10 is exactly
  coplanar** and z-fights (it sliced the morgue poster apart); below that the plate is buried
  (Issue 11). `wall_point()` now clamps to a 3 cm minimum clearance itself (Issue 26), so 0.16 is
  still the house style but no call site can get it wrong. Props needing depth behind them —
  `LivingMirror` hangs its figure 0.05 behind the glass — need **0.22**
- **The Perëkozhnik** (`creature_shapechanger.gd`): a billboard mimic standing motionless in the
  passage's far corner. It never moves or chases and is **not** a gate — it feeds gaze panic and kills
  only within `KILL_DIST=2 m`. Its 16 panic/s stare is **deliberately** faster than the three-strike
  budget (see the `⚠️ DELIBERATE` note on `GAZE_INTENSITY`); it exists to punish the one instinct this
  level otherwise rewards: walking up to something for a better look
- **Objectives never state an answer** — `GameState.set_objective()` runs in protocol register
  ("PROTOCOL 4-B — PROCEED TO THE MARKED EXIT", "DECONTAMINATION REQUIRED", …)
- Win: **all eight** gates → exit door → The Breach. Fail: three strikes, the Perëkozhnik, a forfeited
  run, or the wrong door (which banishes rather than kills)

**Level 6 — THE BREACH (Object 12, Loose)** — `level_6_breach.gd` + `level_6_breach.tscn` — a
Nemesis/Mr.X-style pursuit level, direct continuation of KONTUR's facility: Object 12, the subject
KONTUR was built around, is now loose in a deeper containment wing. Built the same
`.tscn`-minimal / `PRESERVE`-whitelist / `RoomBuilder` pattern as `kontur.gd`, from a 13-room graph
(a main spine plus two bypass loops — WardA east of Atrium/Junction2, ArchiveA/B west of
Junction2/WardB — so route-planning and breaking line-of-sight actually mean something). Visual arc
extends KONTUR's two-tier skin system to three: facility → structural rupture → organic decay,
ending at a scorched-steel Incinerator.
- **Familiarization window** (level-owned): Object 12 stays dormant at its Junction1 spawn until the
  timer elapses (Mr.X pacing — learn the layout before the threat appears), then `activate()`s and
  roams the level for the rest of the run. The window is **`FAMILIARIZATION_FIRST = 30 s` on the
  first attempt and `FAMILIARIZATION_RETRY = 10 s` on every attempt after a death here**
  (2026-07-27) — the window buys *learning the layout*, which a player only has to do once, so
  after a death it collapses to just enough time to re-orient at the entrance. Which one applies is
  chosen in `_ready()` from `GameState.get_level_attempts(6)` (see **Level attempts** below), never
  from a level-script local: the level scene is rebuilt from `_ready()` on every restart
- **`creature_object12.gd`** (`class_name CreatureObject12`) — a five-state machine
  (`PATROL → INVESTIGATE → CHASE → SEARCH → STAGGERED`), structurally descended from
  `creature_stalker.gd`'s build pattern (`ScaryObject → StaticBody3D → CollisionShape3D`, GLB
  load/arm-pose) but reusing `Void_creature.glb` **retinted** via `material_override` (sickly
  grey-green + red vein emission) rather than a new 3D asset. **CHASE moves directly toward the
  player every frame, unconditionally** — the deliberate opposite of `creature_stalker.gd`'s
  "freeze while observed" rule, which would let a persistent chaser be cheesed by simply staring at
  it. Losing the player doesn't reset straight to PATROL: `SEARCH` walks to the last-seen position
  and scans there for `SEARCH_TIME=8s` first — the one Mr.X/Alien:Isolation lesson worth stealing,
  since it's what makes hiding feel tense rather than a free reset. `CHASE_SPEED=5.0` sits
  deliberately between the player's walk (4.0) and sprint (6.4) — beatable only by sprinting, which
  costs `SPRINT_PANIC_RATE`. Contact within `CONTACT_DIST=1.0` is **instant-fatal**
  (`Screamer.trigger()`), exactly like every other creature in the game — no grab/struggle QTE.
  ⚠️ The FOV/facing check is deliberately **horizontal-only**: dotting the creature's (horizontal)
  facing against the *full 3D* direction to the player mixes in the CHEST(0.9)-vs-eye-height(~1.65)
  vertical gap, which can fail the dot-product test regardless of facing once the gap is a large
  fraction of a close-range distance — found by `tests/test_creature_object12.gd`, where a SEARCH
  scan converging on the stub player produced exactly this false-blind result
- **Light-as-weapon** (`apply_light_damage()`, driven every frame by `level_6_breach.gd`'s
  `_tick_light_weapon()`, which owns the geometric "is the player aiming a lit flashlight at it
  within FOV+LOS" check — the creature script itself stays graph/geometry-agnostic): sustained aim
  drains a `SHIELD_MAX=100` pool at `SHIELD_DRAIN_RATE=40/s` (~2.5s to empty); hitting 0 drops it
  into `STAGGERED` for `randf_range(STAGGER_MIN 5, STAGGER_MAX 7)` s — a **temporary repel, not a
  kill** (shield fully regenerates on recovery). ⚠️ **Draining and staggering both require
  `State.CHASE`** (BACKLOG #26, confirmed with the user: you can only blind it while it is actually
  chasing you). Previously the drain happened in every state while the stagger could only fire from
  CHASE/INVESTIGATE, so lighting up a patrolling or searching creature emptied the whole pool for no
  effect — indistinguishable from a blind that lasted no time, which is exactly how it was reported.
  `recovered` is now connected (it never was), so the end of the stagger is announced.
  `creature_stalker.gd`-style FOV/raycast code, but the CHASE *behavior* is intentionally not
  reused (see above)
- **Hiding** (`hiding_spot.gd`, 6 lockers/cabinets/desks spread across the rooms, never two in the
  same room): walk up + press E to hide/unhide — the existing `_try_interact()` path, no new input
  action. `player.gd` gained `enter_hiding()`/`exit_hiding()`/`is_hidden()`: movement blocks via the
  existing `_input_frozen` flag, but look is exempted and clamped to a ±50° peek cone
  (`_rotate_camera`'s `_hidden` branch) instead of the full range. Footstep audio is silenced for
  free by the existing `_is_moving`-gated chain — no separate suppression flag needed. The
  creature's own `_detect_player()` short-circuits `false` whenever `is_hidden()` is true
- **Door-slam** (`slam_door.gd`, 4 interior doors at chokepoints, never on a dead-end): press E
  while passing through to slam it shut; `level_6_breach.gd::_tick_slam_doors()` scans every frame
  whether a closed door lies on the creature's path to its current CHASE/SEARCH/INVESTIGATE target
  (`check_blocks_path()`, a segment/AABB test) and calls `start_battering()`, which pauses the
  creature's movement (`force_block()`, any state, no state change) for `batter_time≈10s` while it
  "batters" the door down — a temporary delay, not a permanent block. Deliberately **not** built on
  `door.gd` — its `UnlockCondition`/`extra_lock` machinery is irrelevant baggage for a non-exit door
- **The Purge Chamber** (`purge_chamber.gd`, one-shot, at the PurgeAnte↔Incinerator threshold) — the
  **only permanent win condition**. A heavier blast-door escalation of `slam_door.gd`; `interact()`
  slams it shut, then confirms the creature's **actual** position against a world-space
  `trap_bounds` AABB (never a flag) before running the purge sequence (reuses `acid_hiss.wav` from
  `level_5_kontur` — `GameState.load_audio()` already scans every subdir, no file copy needed) and
  calling `creature.lure_into_trap()` (permanent). A mistimed lure just re-opens the door with a
  toast ("IT ISN'T IN THERE") — retryable, not a run-ender
- **Exit lock**: `_exit_door.extra_lock` stays true until `PurgeChamber.creature_trapped` flips a
  single `_creature_defeated` flag (this level needs one boolean, not KONTUR's eight-gate ledger),
  mirroring `kontur.gd`'s `_refresh_exit()` pattern
- **Fail economy**: deliberately **no** `DreadZone`/`DarkZone` and **no** additional trap props — the
  level's identity is the chase itself; the existing sprint-panic economy already supplies the
  "escape costs something" pressure. Fails: creature contact, panic bar fills (standard system)
- **Audio**: `ambient_breach.wav` (procedural, primary `AmbientPlayer` bed, `-8dB`) plus a secondary
  layer at `-14dB` mirroring `kontur.gd`'s optional `kontur_music` node — this is where the
  user-provided `mystical_sound.mp3` lives (as `ambient_breach_layer.mp3`), deliberately **never**
  the primary bed since an arbitrary sourced `.mp3` isn't guaranteed loop-clean. SFX generated by
  `tools/make_sfx_level6.py` into `game/assets/audio/level_6_breach/`
- Win: lure Object 12 into the Purge Chamber and seal it. Fail: creature contact, panic bar fills

**Level 7 — THE NIGHTMARE (the dungeon)** — `dungeon.gd` + `dungeon_gen.gd` + `dungeon.tscn`
A Dungeon-Nightmares tribute, and the only level whose thesis is the INVERSE of a
chase level: **standing still and listening is the winning move.** Full design in
`DUNGEON_NIGHTMARES.md`; that file is authoritative and this is the shipped summary.
- ⚠️ **Unnumbered file names on purpose.** The doc specs this as "level 9" in the
  eventual 12-level order; three of the levels ahead of it are unbuilt, so it is
  level **7** today and the Void moved 7→8, the ending 8→9. Naming the script and
  scene `dungeon` rather than `level_9_dungeon` means the future renumber renames
  nothing. The ASSET folders stay `level_9_dungeon/` — renaming those breaks every
  `.import` UID, and folder numbers already track identity not index
- **Structure**: a small hand-built **Antechamber** (always identical — cot, brazier,
  `CalmZone`, candle rack, the PROTOCOL 7 note, the "YOU CANNOT HEAR IT OVER
  YOURSELF" scrawl, both level doors) → `interact()` the cot to be put under → a
  **procedurally generated dungeon** → light **7 sconces** → the bed is revealed →
  wake → the exit door unlocks
- **`dungeon_gen.gd` is pure data** — no scene, no nodes, seeded, deterministic
  (verified). An 18×18 lattice of 3 m cells, 12 chambers placed by rejection
  sampling with a 1-cell gap, MST + `ceil(0.25K)` extra edges, L/Z corridors, then
  maximal straight runs coalesced into rooms. That separation is why 200 seeds can
  be asserted without loading a scene — the `check_maze_gen.gd` lesson
  - ⚠️ **The extra edges are NOT optional.** A spanning tree is a perfect maze, and
    in one a corridor-following pursuer is unbeatable. `maze_chase_ui.gd` already
    cost this project 12 instant deaths in 40 to learn that
  - ⚠️ **MIN_CHAMBERS = 9 is a hard floor, not a preference.** Seven sconces must fit
    in seven distinct non-bed chambers; a dungeon with fewer is UNWINNABLE, because
    7/7 is what reveals the exit. Pure rejection sampling produced 7 chambers on 2
    seeds in 200 — roughly one unwinnable dungeon per hundred restarts — so there is
    a bounded top-up pass. `check_dungeon_gen.gd` asserts **exactly 7 sconces, every
    seed, no tolerance**
  - ⚠️ **Every room is ONE height.** §B6 asks for 3.2 m chambers and 2.6 m corridors;
    `RoomBuilder`'s wall dedup is keyed on `(axis, plane, HEIGHT)`, so mixed heights
    make both rooms emit a slab on their shared plane (Issue 41, measured in
    `tests/probe_mixed_height.gd`). Corridors get a separate drop-ceiling instead
  - ⚠️ Sconces and Weeping Frames go on a wall with **no doorway** — `wall_point()`
    returns the wall CENTRE, which is exactly where a doorway sits, and a collider
    there silently seals the chamber (the Records warning sign did this in the Lab)
- **The candle replaces the flashlight** (`candle.gd`): `player.kill_flashlight()` at
  entry, so F only clicks. 60 s per candle, carry 4, `OmniLight3D` range 4.5.
  **F** lights / blows out — blowing **BANKS** the remaining seconds (§B11 cuts DN's
  waste-it rule as an unteachable gotcha), and the autoplay measured that banking is
  what makes the wax sufficient: burning continuously runs dry at ~8 minutes.
  **C** (new `spark` action) is free and unlimited, followed by a 1.2 s ambient dip
  BELOW baseline — the thing that makes a free action feel expensive
  - ⚠️ Energy/attenuation are **2.2 / 1.4**, not §B5's literal 1.0 / 2.4. At the spec
    values, with ambient 0.02, a chamber renders as pure black with a lit patch of
    floor — not "you cannot see the far wall" but "you cannot see the room". The
    RANGE (4.5 m) is what enforces §B7, and it is untouched
- **Darkness without fog** (§B7): black background, ambient 0.045, dark albedo, and a
  4.5 m light. ⚠️ **Do not add a depth-fade shader** — that is fog by another name,
  outside the rendering contract, and it fights `PanicHUD`. `Vignette.spawn()` at 2.2
  is the legitimate framing device
- **The escalation clock is the sconce count**, and the level gets physically SAFER
  (each sconce is a permanent `CalmZone` island) while the roster escalates:
  0–2 Still Ones only · 3 Weeping Frames become audible · 4 the Matron begins her
  spawn/hunt/despawn cycle · 5 the Frames become fatal at 3 s of gaze · 6 the Hollow
  One and the Kneeling Man arrive · 7 the bed is revealed
- **Entities**
  - **Still Ones** — `creature_stalker.gd` with three **additive `@export`s that
    default to OFF** so the Void's four creatures are untouched: a `bone_scrape` loop
    gated on advancing (a fairness upgrade worth back-porting), ~35 % **duds** that
    topple and are inert forever, and the spark reaction (a spark advances every one
    by a step; within 2 m of an active one it is fatal). Its `../Player` lookup gained
    a `"player"` group fallback — it lives under a builder graph here
  - **The Matron** — `creature_object12.gd` RETUNED, not forked: five of its
    constants became `@export` with **every default unchanged**. `chase_speed` **3.4
    — BELOW the player's 4.0 walk**, which is the whole resolution of the level's
    central problem (walking away always works; sprinting is never the answer). She
    cycles spawn → hunt → despawn rather than being permanent
  - **The Hollow One** (`creature_hollow.gd`) — the flagship. Permanently invisible,
    the candle does nothing, slow (2.2), and **the only way to see it is to SPARK**
    (0.30 s of alpha). Arrives at 6 sconces after a scripted zero-risk demonstration
    through a sealed alcove's grate. ⚠️ Never simultaneous with the Matron, never in
    a chamber with a Still One — sparking is mandatory for one and lethal near the other
  - **The Child** (`dn_child.gd`) — harmless, always, no exceptions. +6 panic. Only
    while the candle is out AND no primary is present
  - **The Kneeling Man** (`kneeling_man.gd`) — cannot harm you at all; gaze panic and
    the whisper bank. Says *"Look behind you"* — the exact lie KONTUR's escort gate
    tells, which retroactively makes that one read as the same voice
  - **The Weeping Frames** (`weeping_frame.gd`) — harmless → audible → fatal, tiered
    by sconce count. The teaching encounter is the IDENTICAL object, not a softened one
- ⭐ **The silence is the flagship tell.** On the Matron's spawn the runtime
  `"Dungeon"` bus ducks to −24 dB and `player.set_no_decay(true)` fires: panic HOLDS,
  it does not climb. Net panic change from her mere presence is **zero** — all the
  pressure is in what you choose to do about it. The heartbeat and footsteps are on
  `AudioBuses.BODY`, which is never ducked, so your own pulse is what is left
- ⭐ **Sprinting deafens you** — the creature emitters duck while `is_sprinting()`.
  Running makes you blind to the thing that would have made panic unnecessary
- ⚠️ **§B10's bans are hard, and `check_dungeon_entities.gd` asserts every one**: no
  `DarkZone` (the darkness is the medium, not the penalty — Issue 18), no
  `DreadZone`, no `enable_standstill_panic()` (the Hollow One's solution REQUIRES
  standing still), **no `RandomAmbient`** (its blind 4 m pops are indistinguishable
  from this level's real positional tells, which is the one skill being tested —
  opting out is a no-op omission), no `ApparitionDirector`, no time limit
- **Cross-level hints** (the KONTUR pattern): the **Lab morgue** holds a Trial 7 log
  about the light waking the still ones; the **House cellar** has a candle stub and
  "SIXTY SECONDS. COUNT THEM."; the **Corridor** at d=250 m has the Hotel Vesper
  plate — *"WE STOPPED PLAYING MUSIC ON THE LOWER FLOORS. THE SUBJECTS COMPLAINED
  THEY COULDN'T HEAR IT STOP."* That last one is the most important hint in the game:
  the silence is a mechanic made of an ABSENCE, and an absence cannot teach itself
- `save_progress()`: `layout_seed`, `content_seed`, `sconces_lit`, `candles_held`,
  `teach_beats_done`, `in_dungeon`. ⚠️ **The seeds are RESTORED, never re-rolled** —
  restoring "5 sconces lit" against a re-rolled layout would mark progress on a
  dungeon that no longer exists (KONTUR's `_dark_x` warning)
- Win: light all seven sconces, sleep in the bed, leave by the Antechamber door.
  Fail: creature contact, a fatal Weeping Frame, or the panic bar filling

**Level 8 — The Void (surreal broken geometry)**
- Corridors loop, geometry distorted, floating tiles, floor text
- 8 notes total (5 safe, 3 trap). One safe note is the **twist note** (`is_twist_note = true`)
- **Stalking creatures** (`creature_stalker.gd`, 4 of them, Weeping-Angel logic): each is a Mixamo GLB figure (`Void_creature.glb`) rendered as a dark shadow with blue eye glow via `material_override`. It freezes while in your FOV + line-of-sight (`ENGAGE_DIST=8m`, `FOV_DOT=0.55`), advances at 1.25 m/s the moment you look away, and lunges → `Screamer.trigger()` on contact. Staring also feeds gaze panic (`GAZE_INTENSITY=0.6`, ~12/s at full) — you can't just watch one forever. `START_GRACE=5s` keeps the opening safe; `CreatureA` stands dead ahead of spawn as a teaching beat. **Stare-off mechanic**: watch any creature continuously for `STARE_OFF_TIME=4s` and it backs off 3m, resets to dormant — costs ~48 panic; demands nerve. Falls back to procedural capsule silhouette if GLB missing. **⚠️ GLB requirements**: the GLB must have **no embedded textures** (export with "No Textures" in Blender) and **no animations** (or disable the AnimationPlayer in the scene after instantiate). Mixamo's default export embeds a skin texture and auto-plays animations, which breaks the dark-material override and causes erratic movement.
- **Void-fall = fatal**: Room C's floor is broken open around a 1.6 m hole (`_break_room_c_floor()`); `player.global_position.y < -4` → `Screamer.trigger()` (`_check_void_fall`)
- **Ambient pressure** (`_spawn_void_zones()`): Rooms C+D are a `DreadZone` (decay weakened to 2/s + constant +2/s pressure); far rooms are `DarkZone`s. Room A has two warm candles + `CalmZone`s — the only recovery anchor in the level (decay ×2.5 here)
- Win: read the twist note → exit door unlocks → walk through
- Fail: a creature reaches you, you fall into the void, or the panic bar fills

**Twist Ending**
Final door loads back to the intro room — **corrupted** (`_corrupt_room()` in `intro_room.gd`, fires when `GameState.is_ending`): candle dead, slow blood-red throb light, exit door replaced by planks (no way forward), harsh cold spotlight pinning the new note to the table, extra cobwebs, low whisper loop. Reading the note → 2 s → `Screamer.trigger_to_menu()`.

### Random Apparition (the "monster" — `apparition.gd`, Session 10)
A reusable figure that materialises at a scripted-but-randomised moment and tests the player's
**response**, not their reflexes. `Apparition.spawn(parent, rule, pos, teach)` returns the right
node for one of three rules:
- `RULE_HOLD` (the new flagship): on `appear()` it fades in ~7 m ahead, where the player is
  already looking, with a low drone, and adds steady dread. **Survive by NOT fleeing** for
  `HOLD_TIME` (4 s) → it fades; **flee and it rushes** → fatal `Screamer.trigger()` (or, in
  teach mode, a survivable `flash_scare`). Fleeing (`_is_fleeing()`, Session 11) = `is_sprinting()`
  **OR** backing away — the horizontal distance growing past `_spawn_dist + FLEE_MARGIN` (0.7 m).
  Turning the camera while holding your ground never trips it (fair; matches "stand still until it
  fades"). Enforces "Walk. Do not run." — the Lab briefing note states the rule.
  ⚠️ **Distance is RANDOMISED per appearance** (BACKLOG #10): `APPEAR_DIST_MIN 2.5` ..
    `APPEAR_DIST_MAX 7.0`, replacing a single fixed value (7.0, then 4.0). A fixed distance
    frames every appearance identically, so the second one is never a surprise.
    `FLEE_MARGIN` is therefore **proportional** — `maxf(0.7, _spawn_dist * 0.2)` — because a
    flat 0.7 m is a 10% allowance at 7 m and a 28% allowance at 2.5 m, and an instinctive
    half-step back from something that appeared on top of you would otherwise be a death.
    Sprinting is still an instant fail at any distance, so the rule itself is untouched; only
    the flinch is forgiven
- **BUG_FIX.md 3.3**: the telegraph/rush sting right before a fatal lunge (`_play_sting()`) used to
  reuse the generic door "creak" pitched up ×1.4 — playtest called this out as needing "a more violent
  and scary noise." Now plays a purpose-made `apparition_snarl` (`shared/`, sourced — no artificial
  pitch-shift needed), falling back to the old creak/drone chain if the file is ever missing
- `RULE_STARE` / `RULE_LOOKAWAY` just spawn the existing `CreatureStalker` / `CreatureSmiler`
- **Fairness rule:** each rule's first encounter is `teach=true` (survivable) so the player learns
  the tell before it can kill — same philosophy as the Void's `CreatureA` + `START_GRACE`. The Lab
  hosts the taught HOLD apparition; the House reuses a non-teach one in the cellar
- **Visible spawn.** ⚠️ The old one-ray version *created* BACKLOG #8 ("sometimes the monster
  appears in the textures"): `clampf(wall_hit - WALL_MARGIN, MIN_DIST, APPEAR_DIST)` let the
  `MIN_DIST` floor **override the wall it had just detected**, so facing a wall 1 m away placed
  the 1.6 m-wide billboard at 1.6 m — inside it. `appear()` now fans over 10 headings x 3
  distance fractions x 9 lateral nudges, validating each candidate with `_fits()`, and
  **aborts (`queue_free`, no figure) if nothing fits** — a skipped apparition beats an embedded
  one. `_fits()` uses **rays only**: line-of-sight from the player's eye (which also catches
  "the point is inside a wall", since the segment must cross its near face), a head-room ray, a
  top-down column ray (catches standing inside a bench), and a 16-ray horizontal fan at
  `FIG_FIT_RADIUS`. ⚠️ **Do not switch `_fits()` to `intersect_shape`** — a shape query against
  CSG reports NOTHING when wholly inside the slab, i.e. it silently approves exactly the case
  being rejected (Issue 40; `tests/probe_shape_vs_csg.gd` is the evidence). ⚠️ The fan is 16
  rays, not 8: at 45° spacing every ray flies through a DOORWAY's opening and reports clear
  while the billboard's edges are buried in the jambs. Locked down by
  `tests/check_apparition_clearance.gd`, which also asserts the fix did not make the apparition
  stop appearing.
- **`ApparitionDirector` (`apparition_director.gd`, BACKLOG #6):** one node, added as a child
  by `level_1.gd`/`level_2.gd`/`kontur.gd`, replacing the three identical `DEBUG_APPARITION` +
  `DEBUG_APPAR_INTERVAL = 60.0` countdowns they each used to carry. Levels now only say
  *whether* they want random apparitions (`const RANDOM_APPARITIONS`); the director owns
  **when**. Fires on a randomised `MIN_GAP..MAX_GAP` (90-180 s) after a `LEVEL_GRACE` of 45 s,
  and only when the appearance would be coherent and fair: no paused tree / open `NoteUI`,
  `player.is_input_frozen()` false (a HOLD apparition kills you for fleeing, and a player
  clamped in a beartrap escape or the locker push *cannot* demonstrate they are standing their
  ground — the Issue 18 double-jeopardy shape), panic below 60%, at least
  `MIN_GAP_AFTER_AMBIENT` since `RandomAmbient` last fired, and any level-supplied `suppress`
  callable false (the Lab passes `_in_breaker_nook`).
  ⚠️ `MIN_GAP_AFTER_AMBIENT` **must stay well under `RandomAmbient.MIN_INTERVAL` (18 s)** — at
  30 s the condition was effectively unsatisfiable and the feature silently produced ZERO
  apparitions in a 400 s run (ISSUES_SOLUTIONS Issue 39). `OVERDUE_AFTER` drops the soft
  conditions after 60 s of being held back, so an appearance can be delayed but never cancelled.
  ⚠️ **`ApparitionDirector.arm(apparition, force_teach)` is the ONLY way a HOLD apparition
  should be made to appear** — it owns the global `GameState.apparition_taught` ledger, so the
  first one in a run is survivable *wherever* it happens. All four scripted encounters (Lab
  corridor, House cellar, Backrooms Flood x2) go through it. Before this the teach flag was
  hard-coded per site, so a player who missed the Lab's trigger could meet a lethal one first.
  Measured by `tests/count_apparitions.gd`, which now **asserts** a minimum count and gap, and
  counts *appearances* (`visible`) rather than instantiations.
- ⚠️ **Don't hang a wall panel/prop on a room's only doorway wall.** `wall_point(room, side, …)`
  returns the wall *centre*, which is exactly where a doorway sits — a decal/mirror/desk collider
  there silently blocks the entrance (Session 11 bug: the Records warning sign sealed the third
  breaker room; the bathroom mirror, observation desk and kitchen counter were the same class).
  Check the `DOORS` table and place props on a wall without a doorway
- ⚠️ `apparition_figure` must be a **transparent PNG** (a `.jpg` has no alpha → the billboard shows
  as a solid rectangle). Code prefers `.png` then `.jpg` via `Apparition._resolve_tex`

### Trigger Object Rules
- Trigger objects are **instant fail** on interaction (press E) OR after 3 continuous seconds of direct gaze; trap notes are **read-to-die** (panic +12/s while open — see Level 2)
- Screamer sequence: black flash → screamer image fullscreen → loud audio burst → 1.5s delay → scene reloads
- Visual hint: trigger objects have a faint pulse glow or subtle audio cue when player is close

### Win/Loss Flow
```
Interact with trap → Screamer.trigger() → reload current scene
Reach exit with condition met → GameState.advance_level() → load next scene
Interact with back door (goes_back=true) → GameState.go_back() → load previous scene (state preserved)
```

### Door Conventions
- **Exit doors** and **back doors** both glow **blood-red** (`Color(0.35, 0.02, 0.02)`, emission ×1.5)
- Back doors have `goes_back = true`, `advances_level = false`, `unlock_condition = NONE`
- `go_back()` sets `GameState.entered_from_ahead = true`, captures the level you are leaving into
  `GameState.level_progress`, and restores the destination's snapshot on arrival (see **Level
  progress & backtracking** below). The Backrooms gained a back door for this — it had none

## Level progress & backtracking (BACKLOG #30)

Reported as *"the level always starts from the beginning ... I will need to pass all the levels
from the beginning, which is not how it should work."* It was literally true:
`advance_level()`, `go_back()` and `restart_current_level()` were the same function in three
coats — all called `start_current_level()`, which called `reset_level_state()` and reloaded the
scene, rebuilding it from `_ready()`. Every puzzle's state lived in a level-script local.

**The contract.** A level script MAY implement:

```gdscript
func save_progress() -> Dictionary      # called by GameState on the way OUT
func _restore_progress() -> void        # the level calls this itself, LAST in _ready()
```

`GameState._capture_progress()` calls the first via `has_method`, so a level that implements
neither simply behaves as it always did. `get_level_progress(n)` returns `{}` for an unvisited
level. What each stores:

| Level | Keys |
|---|---|
| 1 Lab | which breakers (by node name), power, locker unlocked/moved, keycard, scare one-shots |
| 2 House | map solved, key carried, cellar open, code entered, scare one-shots |
| 3 Corridor | furthest path distance reached (there is no puzzle state — the level IS the walk) |
| 4 Backrooms | which of the three zones, and the loop counter |
| 5 KONTUR | the 8-gate ledger, strikes, forfeit, hammer, held bottle, and `_dark_x` |
| 6 Breach | `creature_defeated` |

⚠️ **A DEATH still wipes the level.** `restart_current_level()` erases that level's snapshot on
purpose — the no-checkpoint fail philosophy in `COMMENTS.md` is deliberate, and this feature is
about *navigation*, not about softening failure. `tests/check_level_resume.gd` asserts both
directions.

**Level attempts** (`GameState.level_attempts` + `get_level_attempts(level)`, 2026-07-27) is the
deliberate counter-example: it records how many times you have *died* on a level and therefore
**survives** the wipe above, cleared only by `go_to_main_menu()` (i.e. per run). It is incremented
by `restart_current_level()`, so it counts deaths and nothing else — walking back and forth through
back doors never touches it. Level 6 is the only consumer so far (the 30 s → 10 s familiarization
window). ⚠️ It is **not** a difficulty-scaling system; adding one would need its own decision.

⚠️ **KONTUR must restore its randomisations too** (`_dark_x`, and which door is black).
Restoring the gate ledger while re-rolling the answers would mark gates passed whose puzzles now
have different solutions.

**Directional spawn.** `GameState.entered_from_ahead` is true when the player came back through
the NEXT level's back door. Each level then places them at its **exit** end rather than its
entrance — you came back through the exit, so that is where you should be standing. For the
320 m Corridor this is the whole difference between a walk and a re-run; it uses the saved
furthest distance, capped short of the noclip trigger so re-entry does not immediately fall
through again.

**The Backrooms back door.** ⚠️ A deliberate softening of "no way out behind you". The Backrooms
is entered by a one-way noclip fall and its entry arm was capped, so it was the only level with
no back door at all — and KONTUR's back door leads *there*, which meant walking back from KONTUR
stranded the player with no exit but re-clearing all three zones. There is now one blood-red
door in the entry cap, returning to the Corridor.

**The notes journal** is the cheaper half of the same problem — see the `JournalUI` autoload row.
Most players who want to go back want one sentence from one note, and TAB gives them that
without moving.

## Stack
- **Engine:** Godot 4 (Forward+ renderer)
- **Language:** GDScript (snake_case everywhere)
- **3D tools:** Blender (model/rig) → export .glb → import into Godot
- **Platform:** macOS native .app (Apple Silicon M3)

## Code Architecture

### Autoloads (global singletons, survive scene transitions)
Registered in `game/project.godot`. Access directly by name from any script.

| Autoload | File | What it owns |
|----------|------|-------------|
| `GameState` | `scripts/game_state.gd` | Level state (`current_level`: 0=intro, 1=lab, 2=house, **3=corridor, 4=backrooms, 5=kontur, 6=breach, 7=nightmare, 8=void, 9=ending**), `has_keycard`, `level2_code_correct`, `twist_read`, `is_ending`, `intro_note_read`, `apparition_taught`; `advance_level()` / `go_back()` / `restart_current_level()`; `go_to_main_menu()`; `load_audio(base_name)`. **Also owns the two cross-level systems added for BACKLOG #30:** `level_progress` (per-level snapshots — see below) and `journal` + `record_note()`. `set_objective()` / `set_carried()` drive the two HUD lines. |
| `Screamer` | `scripts/screamer.gd` | `trigger()` — black flash → screamer image → audio burst → scene reload. `process_mode = PROCESS_MODE_ALWAYS` (must not freeze during tree pause). `_is_triggering` / `_is_flashing` bools guard `trigger()`, `trigger_to_menu()` and `flash_scare()` against re-entry. **Per-level fatal AV**: `_apply_level_av()` picks the image + scream by `GameState.current_level` from `LEVEL_SCREAMERS` (1 lab `screamer_lab`, 2 house `screamer_house`, 3 corridor `screamer_hotel`/`screamer_corridor`, 4 backrooms `screamer_smiler`/`jumpscare`, 5 kontur `screamer_kontur`, 6 breach `level_6_jumpscare` — image **and** audio, user-supplied 2026-07-27, replacing the generated `screamer_breach` pair; the `.jpg` is real JPEG data so it imports fine, unlike the Issue-25 JPEG-named-`.png` trap — 7 nightmare `screamer_dungeon`, 8 void `screamer_void`); intro/ending fall back to a random `screamers/` `.png` (DirAccess scan at startup) + the shared `jumpscare`. **`flash_scare(image_path, audio_base, hold)`** — a SURVIVABLE scare: fullscreen image + sound for `hold` s, no pause/restart (the caller adds its own panic). Used by the House forest scare, the Corridor Manager, and the Corridor turn mirrors. |
| `NoteUI` | `scripts/note_ui.gd` | Fullscreen note overlay. `show_note(text, trap_rate := 0.0)` / `is_open` bool. Built entirely in GDScript — no .tscn. Guard `is_open` in player before any interaction logic. While `trap_rate > 0` and the note is open, feeds `player.add_panic()` per frame and tints the text toward red; auto-drops the overlay if the tree unpauses (= a screamer fired) |
| `JournalUI` | `scripts/journal_ui.gd` | **TAB** — re-read any note already found. Two-pane overlay (level-grouped list + text), built entirely in GDScript like `note_ui.gd`, `PROCESS_MODE_ALWAYS`, pauses the tree, carries the Issue-9 self-drop guard. `can_open()` refuses while `NoteUI.is_open`, while the tree is already paused, or while `player.is_input_frozen()` (a free pause mid-QTE). ⚠️ **Trap notes are never archived** — `note.gd` only calls `GameState.record_note()` when `not is_trap`, because a safely re-readable copy would let the player learn a read-to-die note's text at no cost. |

### Key scripts
| Script | Responsibility |
|--------|---------------|
| `player.gd` | `CharacterBody3D` movement, raycast interaction, gaze timer (3s stare → fail), **panic system** (`_panic` float, `PANIC_MAX=50`, `PANIC_BASE_RATE=20/s`, `PANIC_DECAY_RATE=3.5/s`, `GAZE_RANGE=3.0m`, `INTERACT_RANGE=3.0m` — raised from 2.5 on 2026-08-15 alongside five collider fixes; the two now match, and reach equals the distance an instant-fail trigger object already gazes from), flashlight toggle (`toggle_flashlight` action, F), heartbeat audio tied to panic ratio. **Sprint** (`sprint` action, Shift): ×1.6 speed, +6 panic/s while sprinting (suppresses decay), faster footsteps. **Flashlight battery**: 240 s per scene (`BATTERY_MAX`), dying-bulb stutter below 48 s, dead = can't re-enable. Zone API: `add_panic(amount)` (instant spike, screamer at max), `apply_slow(duration)` (speed ×0.45), `cancel_slow()` (clears limp instantly — used by beartrap escape), `jolt_camera(strength, duration)`, `enter/exit_calm_zone()` (decay ×2.5), `enter/exit_dark_zone()` (+3 panic/s with flashlight off), `enter/exit_dread_zone()` (decay 2/s + constant 2/s pressure), `get_panic_ratio()`. **Backrooms-only opt-ins** (off by default everywhere else): `enable_standstill_panic()` (+3/s after 4 s still), `enable_footstep_echo()` (phantom step 0.4 s behind), `kill_flashlight()` (force off; F only clicks), `set_smiler_active(bool)` (suspends standstill + dark ticks for the Smiler), `is_flashlight_on()` / `is_sprinting()`. **Input actions** (`project.godot`): `interact` E · `move_*` WASD · `toggle_flashlight` F · `sprint` Shift · `debug_capture` J · `push_effort` **Space** (the Lab locker's mash) · `journal` **TAB** (the notes journal). ⚠️ `player.gd` also exposes a small **test-only** control surface — `ai_active` / `ai_move_dir` / `ai_sprint` / `ai_look_at()` / `ai_interact()` / `ai_interact_target()` — because Godot's `Input.parse_input_event()` does not work headless, so an automated test cannot press a key. `_apply_movement()` and the sprint check are the only two places that read `Input`, and both take their value from here when `ai_active`; everything downstream (gravity, collision, the interact RAYCAST, `can_interact()`, panic) is the shipping path. ⚠️ The interact ray sets **`hit_from_inside = true`** (2026-08-15): layer-2 interact volumes are non-solid so the player walks through them, and the moment those volumes were given real depth, standing in a doorway put the camera inside the box and the prompt vanished at the closest range. ⚠️ `_update_interact_prompt()` consults an optional **`can_interact()`** on the raycast hit before showing "Press E" or setting `_interact_target`, so a prop can be completely inert rather than merely refusing (see `LabLocker`). ⚠️ `freeze_input()` blocks movement **and** look — `_apply_movement` and `_unhandled_input` both early-return on `_input_frozen` — so anything polling `Input` directly during a freeze must do so from its own `_process`. ⚠️ `begin_qte()` / `end_qte()` / `_qte_active` are the MOVEMENT-ONLY pin (`beartrap.gd` is the only caller): `_apply_movement()` zeroes `velocity.x/z` and returns, while look stays free — see the beartrap row for why zeroing rather than returning is the whole fix. ⚠️ `_ready()` also clears `MIRROR_ONLY_LAYER` (20) from `camera.cull_mask` for EVERY level, which is what keeps `mirror_surface.gd`'s figures visible only in reflections |
| `door.gd` | Unlock modes: `NONE` · `KEYCARD` · `CODE_ENTERED` · `TWIST_READ`; `@export var goes_back: bool` for back doors. Static `door_material(tex_path)` owns the blood-red convention for all levels — ⚠️ with a texture the red emission must stay **very** low (0.18); these levels are lit at ~0.45 energy, so emission outweighs albedo and a higher value renders the door salmon pink (Issue 21) |
| `note.gd` | Note interact, `is_trap` / `is_twist_note` flags. Trap notes open via `NoteUI.show_note(text, TRAP_PANIC_RATE)` — read-to-die, no instant fail |
| `combination_lock.gd` | **Type the digits** (2026-08-15): `0-9` (top row and keypad) write into the selected dial and advance, Backspace steps back and clears, Enter submits alongside E; the arrows still work. ⚠️ The controls now live on a **separate, immutable hint label** — `_feedback_label` doubled as the instruction line, so the first `INCORRECT` destroyed the "Esc cancel" text exactly when panic was ticking. `note_ui.gd:77` / `journal_ui.gd:125` are the convention it now matches. Dials also reset on every open. Spinner-dial UI, digit count sized from its answer (`_digit_count()`). Level 2 exit: 3 dials, code **472**, via `GameState.level2_code`. KONTUR's roster gate: 2 dials, code **63** (`kontur.gd:79`, `ROSTER_CODE` — 47 was the pre-BACKLOG-#24 value), via its own `code`/`title_text`/`unlocked`/`wrong_code` exports — no `GameState` coupling. Wrong code = buzz + 10 panic (`WRONG_CODE_PANIC`); UI auto-drops if a screamer fires while open |
| `creature_stalker.gd` | `class_name CreatureStalker` — the Void's creatures. Weeping-Angel stalk (move when unobserved, freeze when watched), LOS-gated, `START_GRACE` opening, lunge → `Screamer.trigger()` on contact. Builds its own visible red-eyed figure + gaze collider in `_ready()`. **Moves the inner `StaticBody3D` (not `self`)** — see the ScaryObject transform-chain gotcha below |
| `creature_static.gd` | Older static-creature variant; `rush_camera()` on trigger. The Void now uses `creature_stalker.gd` instead |
| `vignette.gd` | `class_name Vignette` — `Vignette.spawn(parent, color, strength)` adds per-level overlay |
| `keycard.gd` | Pickup → sets `GameState.has_keycard`; auto-hides on reload if already collected |
| `light_switch.gd` | `class_name LightSwitch` — the Intro ward's wall switch. `@export presses_needed` (2 in the Intro) makes the first press *stick*: it clunks, the plate blips, one far fluorescent stutters and dies. ⚠️ Zero panic — the Intro is UNLOSEABLE and `tests/check_intro_beats.gd` fails if any beat here moves the bar |
| `main_menu.gd` | Main menu: background image (`main_menu_bg.png`), "SUBJECT 47" title, blood-red START/QUIT buttons; START loads `intro_room.tscn`; QUIT calls `get_tree().quit()` |
| `scary_object.gd` | `class_name ScaryObject` — attach to any prop that should build panic. `@export var scare_intensity: float = 1.0`. `player.gd:_find_scary_object()` walks the parent chain UP from the ray-hit collider to find it. **Gotcha:** `ScaryObject extends Node` (no transform) and breaks the Node3D spatial chain — see below. |
| `trigger_object.gd` | `StaticBody3D` trap prop — instant screamer on `interact()` OR on `on_gaze_trigger()` (3s gaze). Attach `ScaryObject` as a child to additionally feed the panic bar. |
| `panic_hud.gd` | `PanicHUD` node (loaded from `assets/elements/hud_canvas.tscn`). `set_panic_ratio(ratio)` drives blur (`BlurRect`) and red-tint (`TintRect`) shader overlays. Spawned by `player.gd` in `_ready()`, reachable via `player.gd:get_panic_hud()`. Also self-builds an objective label (`_build_objective_label`). ⚠️ The Lab dark-wing `set_breaker_proximity()` hot/cold bar was **deleted** (Issue 34) — don't re-add a HUD readout that solves a level's puzzle outright. |
| `ending.gd` | Waits 1 s, sets `GameState.is_ending = true`, then changes scene to `SCENE_INTRO` (triggers twist ending flow). |
| `corridor.gd` | Level 3 script — builds the entire 320 m corridor procedurally from `PATH_2D`: geometry (overlapping CSG segments with corner openings), triplanar materials, torches, wall panels, beartraps, zones, doors, intro note, events. Walls use `uv1_triplanar` with **y-scale −1/3** (negative flips V so the wainscot sits at the floor; positive renders the wall texture upside-down) |
| `corridor_event.gd` | `CorridorEvent` Area3D — one-shot trigger volume; emits `fired` on player entry. `corridor.gd` connects each to an event callback (`_ev_*`) |
| `beartrap.gd` | ⚠️ **Being caught now PINS you (2026-08-15, user's call, reported TWICE).** `begin_qte()` stops movement dead while leaving LOOK free. ⚠️ The pin must **ZERO `velocity.x/z`**, not merely early-return from `_apply_movement()`: `_physics_process` calls `move_and_slide()` regardless, so an early return leaves the last un-pinned frame's velocity in place and the player coasts. Measured by WALKING into a trap at 6.40 m/s — **9.16 m of travel in 1.5 s** while the UI read "TRAPPED". The first fix looked correct only because `check_beartrap_hold.gd` TELEPORTED the player onto the trap, so there was no velocity to carry; the test now walks in. Also: the snap no longer replays on every escape keypress (it was the most-repeated sound in the Corridor). it used to call only `apply_slow()`, so "trapped" meant 45 % speed and you could walk — or sprint — out of a closed trap and still take the 40-panic timeout from across the level. Two ⚠️ DELIBERATE comments defended that and were rewritten. `beartrap.gd` is the only caller of `begin_qte()`, so `_apply_movement()`'s early-return on `_qte_active` affects nothing else. `Beartrap` Area3D — self-building geometry: base plate, raised rim, pressure pan, two arced jaws with interlocking teeth, coil springs, chain and ground stake, using `shared/rusted_iron.png` + `shared/beartrap_plate.png` for grain only (keep emission ≤0.12 or it reads as white paper in the dark). ⚠️ Was a 3 cm disc plus two flat rectangles (BACKLOG #18); per Issue 35 the SILHOUETTE carries a prop here and art does not. ⚠️ The jaw hinge sits at the trap's CENTRE and rotates by **-side * JAW_OPEN_DEG** — hinging at the rim makes the arc wrap the pivot so the jaws never rise, and a positive angle swings them down through the base plate; both rendered as a trap with no visible jaws; on step: snap SFX + `add_panic(15)` + jaw-close tween + **7-second escape mechanic** (mash E 7 times → `cancel_slow()`, success; timeout → `add_panic(40)`, total 55 > PANIC_MAX → screamer). Builds a CanvasLayer escape UI with countdown bar + press counter. One-shot |
| `calm_zone.gd` / `dark_zone.gd` / `dread_zone.gd` | `CalmZone` / `DarkZone` / `DreadZone` Area3D — call the matching `player.enter/exit_*_zone()` on body enter/exit |
| `torch_3d.gd` | `Torch3D` Node3D — self-building wall torch (bracket + cup + emissive flame + flickering OmniLight + CalmZone child). `extinguish()` kills flame/light + frees the CalmZone — used by the lights-out event |
| `fake_door.gd` | `FakeDoor` StaticBody3D — locked hotel door panel; interact → door_slam answers from the other side, +8 panic first try only |
| `backrooms.gd` | Level 4 — builds the whole mono-yellow maze procedurally: 4-way hub + N/E/W choice arms (`CSGBox3D` + triplanar wallpaper/carpet), recessed flickering fluorescents, arrow columns, the navigation state machine (`_assign_round` / `_on_arm_entered` / `_wrong_turn` / loop-back teleports), dynamic dark zones, the exit utility room + glitch wall, ambience, and the mirage-door/phone/Smiler spawns. Calls `player.enable_standstill_panic()` + `enable_footstep_echo()` |
| `creature_smiler.gd` | `class_name CreatureSmiler` — the Backrooms darkness entity. Billboard `screamer_smiler.png` at a dark arm's end. Flashlight-on-it or sprint → `Screamer.trigger()`; light off + hold still → fades. Suspends the maze's standstill/dark ticks (`player.set_smiler_active`) and drives its own +2.5/s dread |
| `mirage_door.gd` | `class_name MirageDoor` — blood-red back-door lookalike; `interact()` swings it open onto blank wallpaper + 10 panic. Self-building mesh |
| `rotary_phone.gd` | `class_name RotaryPhone` — rings (`rotary_ring`) on a timer; `interact()` answers → `phone_whisper` + a read-to-die trap note via `NoteUI.show_note(text, 11.0)`. Self-building primitive mesh. **BUG_FIX.md 4.6**: gained `@export smashable`/`signal smashed`/`_smash()` — when `smashable` (KONTUR only, default off), `interact()` smashes instead of answering, stopping the ring for good; Backrooms' own phone is unaffected |
| `maze_kit.gd` | `class_name MazeKit` (Session 14) — static geometry primitives shared by the three Backrooms zones: `box/slab/wall/light_strip/zone_box` + the wall/floor/ceiling materials. Extracted from `backrooms.gd`. ⚠️ Keep `make_material`'s **negative V** uv scale — a positive `uv1_scale.y` renders wallpaper upside-down |
| `glitch_wall.gd` | `class_name GlitchWall` (Session 14) — the walk-through exit surface. `setup(size, height, is_real, tex)`, `signal touched(is_real)`, `go_solid()` (an outed fake becomes ordinary wall), `revive()`, `set_seam_visible()` (hides the **whole node**, not just the mesh — Node3D visibility is inherited and the Area3D keeps monitoring regardless) |
| `silence_zone.gd` | `class_name SilenceZone` (Session 14) — Zone 2's tell. Ducks the `"Backrooms"` audio bus to −30 dB while the player is inside. Restores the bus in `_exit_tree()` so a teleport-out never leaves the level permanently silent |
| `backrooms_zone2.gd` / `backrooms_zone3.gd` | `class_name BackroomsZone2` / `BackroomsZone3` (Session 14) — the Sprawl and the Flood. `build(origin)` / `build(origin, player)`, `signal cleared` + `signal mistake`; the level owns the consequences |
| `room_builder.gd` | `class_name RoomBuilder` (Session 10) — procedural room-graph: `build(rooms, doorways)` where room=`{name,pos:Vector2,size:Vector2,h?, wall_mat?/floor_mat?/ceil_mat?}` and doorway=`{pos,width,dir:"x"\|"z",h?}` → CSG floor/ceiling/walls, **floors auto-bridged under every doorway** (kills the Issue-5 void-fall class). Applies its own materials; the optional per-room `*_mat` keys (Session 11) override them so a Morgue/Kitchen/Bathroom reads as a distinct place (`level_*.gd:_rooms_with_skins()`). Helpers: `room_center/size/height`, `wall_point(room,side,y,inset)`, static `make_material()`. Doorways open EVERY wall on their plane, so connected rooms must ABUT (share a wall plane). Used by `level_1.gd`, `level_2.gd` + `kontur.gd`. ⚠️ `make_material()` **negates V itself** (`Vector3(x, -absf(y), x)`) — callers pass a positive scale. A positive `uv1_scale.y` renders walls upside-down: the wainscot lands at mid-wall and the lower half reads as a mirrored duplicate (Issue 19). ⚠️ Floor bridges are sunk by `BRIDGE_SINK` (4 mm) because their top face is otherwise coplanar with every room floor — the doorway z-fighting/flicker of Issue 20. ⚠️ Wall dedup subtracts **intervals** per (axis, plane, height), not exact spans: abutting rooms of different depths emit walls on the same plane with different spans, and building both put two coincident slabs in the same place — one room's texture bleeding through another's, the "merging textures" bug (Issue 23). ⚠️ Rooms in a `ROOMS` table must ABUT, never OVERLAP, or their floor/ceiling slabs coincide too. `tests/check_wall_overlap.gd` asserts all of this |
| `mirror_surface.gd` | `class_name MirrorSurface` (2026-08-15) — **the first thing in this project that actually reflects.** A `SubViewport` + a `Camera3D` placed at the player camera reflected through the mirror plane; the viewport texture becomes the quad's albedo. `attach(quad)` converts an existing quad, so the Corridor keeps its `ScaryObject → StaticBody3D → QuadMesh` hierarchy (the ScaryObject must stay an ANCESTOR of the collider or gaze panic dies). ⚠️ **The near plane is load-bearing**: the virtual camera sits behind the glass, inside the wall, so without pushing `near` out to the mirror plane the reflection renders as black masonry with a strip of sky. ⚠️ Proximity-gated (`UPDATE_DISABLED` beyond 14 m) — each active mirror is a second scene render. ⚠️ Reserves `MIRROR_ONLY_LAYER` (20); `player.gd:_ready()` clears that bit from the player camera for EVERY level, so a `Watcher` on that layer appears only in the glass — the corridor behind you is empty and the mirror disagrees. The Corridor also switched to a **black background** (`_black_background()`), the same fix the Lab and House already use, because a mirror is the only thing that could ever see the procedural sky |
| `apparition_director.gd` | `class_name ApparitionDirector` (BACKLOG #6) — decides WHEN the shared apparition appears, for every level that wants one. Randomised gap + fairness suppression + the global teach ledger; `static arm()` is the single entry point for making a HOLD apparition materialise. See the Random Apparition section |
| `cellar_gate.gd` | `class_name CellarGate` (BACKLOG #16) — the House's boarded cellar door. Self-building planks/lock/slab, `interact()` emits `used`, and `level_2.gd` decides whether the player is carrying the key. Same prop-emits / level-decides split as `fungal_barrier.gd`. One body on layer 1: it must both block movement and answer the interact ray, and the ray uses the default mask, so the two-body Issue-30 split is unnecessary here |
| `journal_ui.gd` | `class_name`-less autoload — the notes journal. See the autoload table |
| `apparition.gd` | `class_name Apparition` (Session 10) — the random monster. `Apparition.spawn(parent, rule, pos, teach)`; `RULE_HOLD` = appear-ahead, survive by not sprinting; `RULE_STARE`/`RULE_LOOKAWAY` reuse stalker/smiler. See "Random Apparition" above |
| `lab_locker.gd` | `class_name LabLocker` — the steel locker sealing Level 1's Records breaker. Self-building `BoxMesh` body + art `QuadMesh` + collider; `@export unlocked` (set by the Observation note's `read` signal) gates `interact()`, which otherwise only toasts a refusal. Opens a TAB-mash tug-of-war that does **not** pause the tree (`beartrap.gd`'s idiom: poll `Input` in `_process`, HUD `CanvasLayer` parented to the level), plants the player on a brace mark, and slides 1.3 m on success → `signal moved`. See the Level 1 write-up for the two gates and the `ARM_DELAY` gotcha |
| `note.gd` | …also emits `signal read` on `interact()` — the generic "this note was opened" hook the project lacked (the only prior per-note state was the bespoke `GameState.twist_read`). Fires on OPEN, not on `NoteUI.closed`: reading-to-the-end is a mechanic reserved for trap notes. `level_1.gd` uses it to unlock `LabLocker` |
| `breaker.gd` | `class_name Breaker` (Session 10) — Lab power switch; `interact()` flips once + emits `flipped` + clunk (`breaker_throw`). The panel is **never** emissive (Issue 33); `@export var glows: bool = true` now gates only the lever indicator at `INDICATOR_EMISSION = 0.12` — set `false` for BreakerNook's breaker so it stays genuinely invisible in the dark |
| `living_mirror.gd` | `class_name LivingMirror` (Session 10) — one-way mirror; a figure shows in the glass only when the player is NOT looking head-on (`LOOK_DOT=0.8`) + gaze panic (ScaryObject). **Seeds `body.global_transform = global_transform`** — without it the ScaryObject-chained collider sits at the world origin (an invisible wall; the bug fixed in Session 10) |
| `kontur.gd` | Level 5 — KONTUR. Builds the 13-room spine via `RoomBuilder`, the Soviet→facility skins, the level-wide `DreadZone` (the no-decay economy), all **eight** gates + their redacted signs, the Perëkozhnik, props and doors. Owns the strike counter (`_strike()`), the `_gates` ledger + `_refresh_exit()` (the exit stays sealed until all eight pass), `_forfeit()`, and `_open_the_void()`/`_check_void_fall()`/`_banish()` (the wrong door drops you a level) |
| `screen_text.gd` | `class_name ScreenText` — shared transient on-screen text: `toast()` / `caption()` / `scrawl()` (blood-red, slightly rotated — the project has no handwriting font, so the tilt does the work). Replaces five hand-rolled CanvasLayer+Label helpers. ⚠️ Always parents to the tree root and cleans up via a **connected**, never awaited, tween — an awaited timer dies with the node that started it (Issue 6) |
| `audio_buses.gd` | ⚠️ **`reset_all()` runs on EVERY level load** (`GameState.start_current_level()`, 2026-08-15). AudioServer buses are process-global and survive `change_scene_to_file`; `ensure()` early-returns without touching a volume; and every per-level bed nests under `Ambience`. So one level that ducks a bus and forgets to restore it silences **every level after it for the rest of the session**. That is not hypothetical: `corridor.gd:_tick_hush()` pulled `Ambience` to −40 dB at 296 m with no restore, which is why the Backrooms had no music when entered from the Corridor but did when loaded directly. `check_bus_leak.gd` drives the real transition and asserts the arrival. `ensure_music_bus()` is the escape hatch for a SCORE that must survive a duck — sent to Master, not nested. `class_name AudioBuses` (2026-07-28) — the minimal runtime bus layout: `Master → Ambience` (duckable) and `Master → Body` (heartbeat + footsteps, **NEVER ducked**). `ensure_core()` is called from `GameState._ready()`, so both exist before any scene. ⚠️ **Per-level bed buses NEST under `Ambience`** (`backrooms.gd`, `dungeon.gd`), so a level's own `SilenceZone` duck and a global `HoldBreath` dip compose instead of competing. Deliberately NOT `SCARY.md` §4.1's five-bus `.tres` — the project has never had bus config in `project.godot` and this follows the existing runtime pattern |
| `hold_breath.gd` | `class_name HoldBreath` (SCARY.md P5) — `HoldBreath.dip(tree, hold)` ducks `Ambience` to −30 dB, holds, restores. Wired as a **0.6 s pre-duck inside `screamer.gd:flash_scare()`**, which improves every survivable scare in the game at once. ⚠️ Fire-and-forget, never awaited — awaiting would delay the image by the whole dip. One dip per bus at a time (`static _active`), `PROCESS_MODE_ALWAYS`, and restores in `_exit_tree()` |
| `watcher.gd` | `class_name Watcher` (SCARY.md P3) — a distant motionless figure with **no rules at all**: no `ScaryObject`, no collider, no kill radius, no `Screamer`, no fail state, **no emission**. `spawn(parent, pos, tex, vanish_within, require_los)`. Used by the Corridor doorway, the House cellar and the Sprawl's Congregation. ⚠️ Clearance by **rays only** (Issue 40). ⚠️ `require_los=false` is for `congregation.gd` ONLY — the LOS ray is also what catches "inside a wall", so it may only be dropped by a caller whose candidates cannot be inside geometry |
| `moved_prop.gd` | `class_name MovedProp` (SCARY.md P6) — wraps any `Node3D` and applies a stored delta once, while the player is >6 m away and facing elsewhere. No sound, no event, no panic, no acknowledgement. `arm()` / `apply_now()` (the restore path) / `is_applied()`. ⚠️ Register applied moves in `save_progress()` or a back-door return un-moves them. ⚠️ Only `_advance_guest()`-style tracked callers may attach: attaching twice for one stage DOUBLE-APPLIES the delta (it put the House chair outside the building) |
| `congregation.gd` | `class_name Congregation` (2026-07-28) — Backrooms Zone 2's occupants: 6–8 persistent `Watcher`s among the 36 pillars, growing by one per wrong wall (capped at 12). **Zero panic, no rules.** A figure relocates only when it is BOTH out of view and ≥15 m away, so it never moves on screen and never pops at arm's length. ⚠️ Legal under §8.3 because there is no fail condition for gaze to depend on — looking at one does literally nothing |
| `unseen_wader.gd` | `class_name UnseenWader` (SCARY.md P10) — the Flood's threat that is **never instantiated**: no mesh, no collider, no `ScaryObject`, no kill radius. A `wade_distant` loop on a `Tween`, always ≥12 m away, patrolling the room graph's centres. ⚠️ **When the player stops wading it stops too — after two more, decelerating strides.** The zone drives `set_player_wading()`; it never samples the player itself, so the two cannot disagree about when the player halted |
| `house_fridge.gd` | `class_name HouseFridge` (2026-07-28) — the House kitchen's fridge and the **only new panic term** in the atmosphere pass (10, voluntary, one-shot). Hums to earn the approach; on `interact()` the scream fires first, the door swings `DOOR_DELAY` later, the head is revealed as it clears. `can_interact()` returns false once used, so it never advertises a prompt that does nothing. ⚠️ Carcass is an open-fronted **shell of five slabs** — a solid `BoxMesh` hides everything inside it (Issue 46). ⚠️ No `flash_scare`: a fullscreen image fired over the reveal it was announcing |
| `kitchen_drawer.gd` | `class_name KitchenDrawer` (2026-07-28) — a searchable counter drawer holding a **second, independent hint for KONTUR Gate 1**. Slides open on E, then shows its note and archives it via `GameState.record_note()` so TAB can re-read it two levels later. ⚠️ States the RULE (black is the way out), never a position — `choice_door.gd` randomises the colours per run |
| `music_box.gd` | `class_name MusicBoxProp` (2026-07-29) — the child's music box, windable with E: the crank turns and the tune swells out of the room tone for ~22 s, then settles back rather than stopping dead. Re-windable, no resource, no fail state. ⚠️ The `AudioStreamPlayer3D` is a CHILD of the box body — that is the only reason THE GUEST's last stage works, because the sound travels with the object |
| `ajar_door.gd` | `class_name AjarDoor` (2026-07-28) — the Corridor's six former decal doors as real hinged bodies. `swing_ajar(deg, time)` opens **silently** (a creak would make it an event instead of a discrepancy); `slam()` is the one that is heard. No `interact()` — the player cannot open these, which is what makes an ajar one evidence. Built on `choice_door.gd`'s skeleton (hinge at origin, art on `QuadMesh` per Issue 24) rather than `door.gd` |
| `choice_door.gd` | `class_name ChoiceDoor` — KONTUR Gate 1. Self-building hinged door panel; `@export is_correct/texture_path`, `signal chosen(correct)`, swings open on `interact()`. The level owns the consequence. **ISSUES_SOLUTIONS Issue 31**: art lives on `QuadMesh` faces front/back of the hinge box, not on the box itself — the box direct-texture version rendered a magnified crop (Issue 24 recurrence) |
| `kontur_mailbox.gd` | `class_name KonturMailbox` — KONTUR Landing's mailbox. **Rebuilt 2026-07-25** (capture #4) from one box + a photo decal into a real 12-slot bank: the old art had the wallpaper baked into its background, so the prop's own texture depicted the wall behind it and could never read as 3D (Issue 35). `kontur.gd:_spawn_mailbox()` now builds carcass/plinth/top-overhang, a divider+shelf grid and twelve numbered slot doors with handles and card holders, all flat-tinted and untextured — the `intro_room.gd:_build_wheelchair()` precedent. **Only slot 12 opens**: the level hands the script a `door_hinge`, and the first `interact()` swings it before `NoteUI.show_note(hint_text)`, so the note reads as having come out of the box |
| `house_map_prop.gd` | `class_name HouseMap` — the Bathroom's folded map prop; `interact()` opens its child `MazeChaseUI`, `signal won`, owns the catch consequence (`jolt_camera` + `add_panic(CATCH_PANIC)`) and a `_solved` one-shot guard, same division of labor as `key_item.gd`/`kontur_mailbox.gd` |
| `maze_chase_ui.gd` | `class_name MazeChaseUI` — the House map-and-chase minigame itself (**BRAIDED** randomized-DFS maze, BFS target/monster placement, drag physics, wall-slide collision, panic drip, two monsters, snares, a looping chase track). `CanvasLayer` + `PROCESS_MODE_ALWAYS` + `get_tree().paused`, same convention as `combination_lock.gd`/`note_ui.gd`; `signal won` / `signal caught`. See the House level write-up above for full mechanics |
| `RandomAmbient` | `scripts/random_ambient.gd` | ⚠️ **`set_once_per_type(true)` caps each event to once per level — OPT-IN, and only the Corridor uses it** (2026-08-15). At ~300 m the Corridor is the longest walk in the game, so an 18-35 s metronome cycled the same three sounds many times over ("too many repeating sounds… falling painting"). Opt-in because this autoload is global and the other levels are balanced against the repeat. **Global ambient-scare metronome, and a real part of every level's panic budget.** `register_player(p)` (each level calls it in `_ready()`), then every `MIN_INTERVAL`-`MAX_INTERVAL` seconds it plays one of `floor_creak`/`painting_fall`/`half_scream` at a random point within 4 m of the player and adds **5 / 8 / 12 panic** respectively. ⚠️ Was **5-10 s** until 2026-07-26 — a scare every ~7 s forever, in all eight levels, with `half_scream` alone worth 24% of `PANIC_MAX`. Two playtest logs were wall-to-wall with the resulting spikes and the player read it as a creature repeatedly appearing beside them. Now **18-35 s**. It is GLOBAL: retuning it changes ambient pressure everywhere at once, so check here first when a level's difficulty shifts for no local reason |
| `DebugLog` | `scripts/debug_log.gd` | Playtest instrumentation. Writes `user://playtest_log.txt`; polls position/panic/flashlight every `POLL` (0.5 s) and logs panic only when it moves more than 18 points between samples — so a slow ramp never appears and every logged jump is a real spike. `J` (`debug_capture`) saves a screenshot plus a typed note. `record_death()` is called directly from `Screamer.trigger()` || `bottle_item.gd` | `class_name BottleItem` — KONTUR Gate 2. Self-building glass bottle + label quad; `@export kind/label_path`, `signal taken(kind)`. Layer 2 / mask 0 like `note.gd` so the shelf line isn't walkable-into |
| `fungal_barrier.gd` | `class_name FungalBarrier` — KONTUR Gate 2. The O-41 mass sealing a doorway; `setup(size, tex)`, `signal sprayed`, `dissolve()` (drops the collider FIRST, then tweens, so the player is never trapped mid-tween) |
| `offering_pedestal.gd` | `class_name OfferingPedestal` — KONTUR Gate 3. Lit pedestal with a hovering bait keycard; `signal taken` on `interact()`. Abstaining is scored by the level's exit sensor, not here |
| `escort_gate.gd` | `class_name EscortGate` — KONTUR Gate 4. `Area3D`; per-frame check of the camera heading against `forward`, `LOOK_LIMIT_DEG=100`, `COOLDOWN=3.0`, `signal broken`. Drives the `breathing_behind` player pinned just behind the player's head |
| `creature_shapechanger.gd` | `class_name CreatureShapechanger` — the Perëkozhnik. Y-billboard mimic that never moves; gaze panic via the `ScaryObject → StaticBody3D` chain (world transform seeded on the BODY — Issue 10), `Screamer.trigger()` within `KILL_DIST=2 m` |
| `key_item.gd` | `class_name KeyItem` (Session 10) — generic pickup; `interact()` emits `picked_up` + label + frees itself. House cellar gate uses it |
| `level_6_breach.gd` | Level 6 — THE BREACH. Builds the 13-room spine (main + two bypass loops) via `RoomBuilder`, the facility→rupture→organic three-tier skins, lights, the familiarization timer (`_tick_familiarization`), the creature/hiding-spot/slam-door/purge-chamber spawns, and the per-frame orchestration (`_tick_slam_doors`, `_tick_light_weapon`, `_tick_noise`) that keeps `creature_object12.gd` graph-agnostic. Owns the single `_creature_defeated` flag + `_refresh_exit()` |
| `creature_object12.gd` | `class_name CreatureObject12` (Session — Nemesis pursuit level) — Object 12's 5-state machine (`PATROL/INVESTIGATE/CHASE/SEARCH/STAGGERED`). Reuses `Void_creature.glb` retinted via `material_override`; CHASE closes distance unconditionally (does NOT reuse `creature_stalker.gd`'s freeze-while-watched behavior); `SEARCH` walks to the last-seen position and scans before giving up; `apply_light_damage()`/`force_block()`/`notify_noise()`/`lure_into_trap()` are the level's hooks into it. FOV check is horizontal-only (see Level 6 write-up for why) |
| `hiding_spot.gd` | `class_name HidingSpot` — Level 6 locker/cabinet/desk; `interact()` toggles `player.enter_hiding()/exit_hiding()`. Self-building mesh, same convention as `beartrap.gd`/`key_item.gd` |
| `slam_door.gd` | `class_name SlamDoor` — Level 6 interior chase door, deliberately not built on `door.gd`. `interact()` slams shut; `check_blocks_path()` + `start_battering()` let the level pause a pursuing creature's movement (`force_block()`) for a few seconds without changing its state |
| `dungeon_gen.gd` | `class_name DungeonGen` — THE NIGHTMARE's layout. **Pure data, no scene, seeded, deterministic**: an 18x18 lattice of 3 m cells, 12 rejection-sampled chambers with a 1-cell gap, MST + `ceil(0.25K)` extra edges (**cycles are mandatory** — a perfect maze makes a corridor-following pursuer unbeatable), L/Z corridors, maximal straight runs coalesced into rooms, then content placed on doorway-free walls. `MIN_CHAMBERS = 9` is a hard floor: fewer and the seven sconces do not fit and the level is unwinnable. ⚠️ Every room is ONE height — see Issue 41 |
| `dungeon.gd` | Level 7 — THE NIGHTMARE. Builds the Antechamber + the generated dungeon, owns the candle/spark input, the sconce escalation clock, the Matron's spawn/hunt/despawn cycle and its bus duck + `set_no_decay`, the sprint-deafness duck, the Hollow One's teaching beat, and the sleep/wake transitions. `get_gen()` / `get_sconces()` / `sconces_lit()` are its test surface; `--dungeon-seed N` pins the layout |
| `candle.gd` | `class_name Candle` — the light that replaces the flashlight. 60 s, carry 4, F lights/blows (blowing **banks** the remainder), C sparks free with a 1.2 s after-dip below baseline. ⚠️ Energy 2.2 / attenuation 1.4, retuned from the spec's 1.0 / 2.4 which rendered as a black screen; the 4.5 m RANGE is untouched and is what enforces "you cannot see the far wall" |
| `wall_sconce.gd` | `class_name WallSconce` — one of the seven. Needs a LIT candle (the level owns that check); lighting it adds a permanent `CalmZone` island. ⚠️ Built from GEOMETRY, not from `dn_sconce.png` — the art has its own background baked in and rendered as a framed picture on the wall (Issue 35) |
| `creature_hollow.gd` | `class_name CreatureHollow` — the Hollow One. Permanently invisible, unaffected by the candle, slow, contact-fatal; the ONLY way to see it is a spark (0.30 s of alpha). `begin_teaching(path, reveal_anchor)` runs the scripted zero-risk demonstration; `set_masked()` is the sprint-deafness hook |
| `dn_child.gd` | `class_name DnChild` — harmless, always, no exceptions. +6 panic, candle-suppressed, and never while a primary entity is present. Parked below the world between appearances so it cannot read as a buried wall prop |
| `kneeling_man.gd` | `class_name KneelingMan` — `creature_shapechanger.gd`'s pattern with `KILL_DIST` REMOVED. Cannot harm you; gaze panic and the whisper bank, including the "Look behind you" line that KONTUR's escort gate already tells |
| `weeping_frame.gd` | `class_name WeepingFrame` — harmless → audible → fatal, tiered by the sconce count. The fatal tier runs its own gaze clock so the ignition wind-up can ABORT when you look away. ⚠️ Ignition emission capped at 0.9 (Issue 21) |
| `dungeon_cot.gd` | `class_name DungeonCot` — the Antechamber cot and the bed at the far end, one script. `interact()`, never a trigger volume: the player CHOOSES to go under |
| `purge_chamber.gd` | `class_name PurgeChamber` — Level 6's one-shot permanent win trigger. `interact()` slams a heavy blast door, then confirms the creature's actual position against a `trap_bounds` AABB before purging (physics-driven, never a flag) |

### Level scenes
| Scene | Unlock condition | Notes |
|-------|-----------------|-------|
| `main_menu.tscn` | — | Game entry point; background image (`main_menu_bg.png`), START loads `intro_room.tscn` |
| `intro_room.tscn` | NONE | Player spawn z=+1.5; table centered; ambient 0.15; walls size.y=3.0 |
| `level_1.tscn` | KEYCARD | **Minimal scene** (Session 10): only `Player`/`Environment`/audio/`HUDCanvas` survive — the whole 10-room Lab is built at runtime by `level_1.gd` via `RoomBuilder` (`_clear_old_scene()` frees the old hand-built nodes via the `PRESERVE` whitelist). Player spawn (0,0.1,−1.5) facing +z; `ExitDoor` built with `advances_level=true`; BackDoor returns to House. **Session 11:** brighter lamps (emergency 0.45 / restored 1.0, range 11) + `_boost_ambient()` duplicates the SHARED env to raise ambient and switch the background to BLACK (no procedural-sky leaks) for this scene only |
| `level_2_1.tscn` | CODE_ENTERED | **Minimal scene** (Session 10): same `.tscn`-minimal / `PRESERVE`-whitelist pattern — the 8-room ground floor + lowered cellar are built at runtime by `level_2.gd` via `RoomBuilder` + `_build_cellar()`. Player spawn (0,0.1,−2.0) facing +z; `ExitDoor` built with `advances_level=true`; BackDoor returns to Lab. **Session 11:** brighter lamps (rooms 0.9, range 10) + `_boost_ambient()` (raised ambient + BLACK background per-scene); fixed cellar headroom + sky-cap. **Note:** `GameState.SCENE_LEVEL_2` points to `level_2_1.tscn` (not `level_2.tscn`). |
| `corridor.tscn` | NONE (reach the door) | Minimal scene: root + Environment + AmbientPlayer + Player at (0,0,2) facing +z — everything else built by `corridor.gd` in `_ready()`. Exit door 217 at d=320 m; BackDoor at the start returns to The House |
| `backrooms.tscn` | NONE (three down-turns → glitch wall) | Level 4. Minimal scene: root + Environment + AmbientPlayer + Player at (0,0,−5) facing +z — the cyclic maze, lights, arrows, zones, props all built by `backrooms.gd` in `_ready()`. Sets `current_level = 4` |
| `kontur.tscn` | `extra_lock` — all eight gates | Level 5 — KONTUR. Minimal scene: root + Environment + AmbientPlayer + Player at (0,0.1,−3) facing +z — the 8-room spine, gates, signs, creature and doors all built by `kontur.gd` in `_ready()`. Sets `current_level = 5`; BackDoor returns to the Backrooms |
| `level_6_breach.tscn` | `extra_lock` — creature defeated | Level 6 — THE BREACH. Minimal scene: root + Environment + AmbientPlayer + Player at (0,0.1,−2) facing +z — the 13-room spine + bypass loops, Object 12, hiding spots, slam doors and the purge chamber all built by `level_6_breach.gd` in `_ready()`. Sets `current_level = 6`; BackDoor returns to KONTUR |
| `dungeon.tscn` | `extra_lock` — seven sconces lit and the bed slept in | Level 7 — THE NIGHTMARE. Minimal scene: root + Environment + AmbientPlayer + Player at (0,0.1,−48) in the Antechamber — everything else built by `dungeon.gd` in `_ready()` from `dungeon_gen.gd`'s output. Sets `current_level = 7`; BackDoor returns to The Breach. ⚠️ The dungeon is DIFFERENT EVERY LOAD; pin it with `-- --dungeon-seed N` |
| `level_3.tscn` | TWIST_READ | The Void (level 8). Player spawn z=−2.0; vignette strength 2.0; BackDoor at z=−3.05; `_spawn_note_tables()` called in `_ready()` (all 8 notes). Sets `current_level = 8` (`level_3.gd:16`) |
| `ending.tscn` | — | Reloads intro_room, credits fade |

## ⚠️ Building a level without coincident-surface bugs (READ THIS FIRST)

Levels 1 and 2 shipped with a family of bugs the player described as *"textures merging into each
other"* / *"lagging textures"*. Every one of them was the same underlying fault — **two visible
surfaces occupying the same plane** — and the fix was never in the art. Session 15 fixed six
variants (Issues 19, 20, 23, 24, 25, 26). KONTUR had the same bug and nobody had noticed.

**Run this before calling any procedurally-built level done:**
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
  --script res://tests/check_wall_overlap.gd -- res://scenes/<level>.tscn
```
It asserts two things and prints `WALL-OVERLAP PASS` / `FAIL` with the offending node names:
1. no two CSG boxes have parallel faces within 2 mm while overlapping in the other two axes;
2. every `QuadMesh` sits at least 2 cm clear of every CSG box.

### The rules it encodes
| Rule | Why |
|---|---|
| Rooms in a `ROOMS` table must **ABUT, never overlap** | Overlapping rooms emit floor/ceiling slabs whose visible faces are both at y=0 / y=h → z-fight (the Lab's `Observation` poked 0.5 m into two neighbours) |
| Never hand-compute a wall-prop position; use `wall_point()` | Its inset is measured from the room's NOMINAL boundary, and the wall face is `T/2` in from that. The morgue poster's hand-rolled `c.z + 2.9` landed exactly on the face and got sliced apart |
| Wall props need `inset ≥ 0.16`; **0.22** if anything hangs behind them | `LivingMirror` puts its figure 0.05 behind the glass. At 0.1 the figure was *inside the wall* — invisible in both levels, for the whole project's life |
| Artwork goes on a **`QuadMesh`**, never on a `BoxMesh` face | A box doesn't map the whole texture per face; it renders a magnified crop. `door.gd:build_visual()` is the pattern — box for edge/depth, quad for art |
| Any deliberately overlapping slab must be **offset**, not coplanar | Floor bridges are sunk `BRIDGE_SINK` (4 mm) for exactly this reason |
| A new builder that emits walls must dedup by **interval**, not by exact span | Abutting rooms of different depths emit same-plane walls with different spans; exact-match dedup builds both |

### Why this was hard to catch
It is **camera-dependent**: a depth fight resolves differently per position and angle, so static
screenshots from `tests/screenshot_level.gd` mostly did *not* reproduce it while walking around in
game did. Three rounds of fixes were driven by the user's own in-game screenshots. **Do not trust a
clean screenshot run as evidence that geometry is sound — run the assertion.**

### ⚠️ Put artwork on a QuadMesh, never on a BoxMesh face
A `BoxMesh` does not map a whole texture onto each face, so a textured box renders a magnified CROP
of its own art (Issue 24 — the exit doors showed one hinge and no window, while the tray and monitor
beside them, on quads with the same material, were fine). `door.gd:build_visual()` is the pattern:
box for edge/depth, `QuadMesh` on each face for the art.

### ⚠️ `ResourceLoader.exists()` returns true for a texture whose IMPORT failed
A `.png` that is really JPEG data imports with `valid=false` and no `.ctex`, so `load()` fails while
`exists()` still says yes — the guard passes and the prop renders blank (Issue 25, a recurrence of
Issue 1). If a texture silently doesn't appear, run `file` on it before debugging the code.

### ⚠️ Emission is most of a surface's colour (no tonemapping, no glow)
The project has **no glow/bloom, no fog and no SSAO on any level**, and renders with Linear tonemap
at exposure 1.0. Two consequences that bit hard (Issue 21):
- Any `emission_energy_multiplier` **above 1.0 clamps to flat pure white** with no detail. Ceiling
  fittings use `FIXTURE_EMISSION` 0.55 (Lab) / 0.6 (House); `MazeKit`'s 1.6 only survives because
  Backrooms strips are seen down a corridor, never directly overhead.
- Because light energy is ~0.45, a surface's **albedo contributes far less than its emission**. A
  self-lit prop's albedo must be DARK or the point light beside it blows it out — and a dark albedo
  is also what lets a blackout drive the fitting visibly dead.

## Panic System

`player.gd` maintains a `_panic` float (0–50). It rises while the player gazes at any node whose scene tree contains a `ScaryObject` ancestor, at a rate of `scare_intensity × PANIC_BASE_RATE (20/s)`. **Gaze detection uses `GAZE_RANGE=3.0m`**, which since 2026-08-15 is the SAME as `INTERACT_RANGE` — the two raycasts remain separate calls, but the ranges now match deliberately, so nothing is reachable that was not already dangerous to look at. It decays at `PANIC_DECAY_RATE (3.5/s)` — a full bar takes ~14 s to drain idle. Hitting `PANIC_MAX (50)` fires `Screamer.trigger()` and resets panic to 0.

The heartbeat `AudioStreamPlayer` (loaded via `GameState.load_audio("heartbeat")`) adjusts volume and pitch in proportion to max(`_panic / PANIC_MAX`, `_gaze_timer / GAZE_TRIGGER_TIME`).

Visual feedback is provided by `hud_canvas.tscn` (at `game/assets/elements/hud_canvas.tscn`) — a `PanicHUD` node with two shader-driven `ColorRect`s: `BlurRect` and `TintRect`. Driven by `set_panic_ratio(ratio)`.

To make a prop raise panic: the `ScaryObject` must be an **ancestor** of the `StaticBody3D` whose collider the gaze ray hits — `player.gd:_find_scary_object()` walks UP from the hit body. Build it as `ScaryObject (Node) → StaticBody3D → CollisionShape3D (+ mesh)`. Because `ScaryObject extends Node` (no transform) it **breaks the Node3D spatial chain**, so put the world transform on the `StaticBody3D` itself — its non-Node3D parent makes the body's local transform == its global transform. For a *moving* gaze prop (the void creatures), move that inner body, not the outer node. Set `scare_intensity` (default 1.0). ⚠️ Nesting `ScaryObject` *under* the body (the old pattern) silently registers **zero** panic — this was the bug behind the dead corridor/house cursed props and the non-reactive void creatures (fixed 2026-06).

Panic source priority per frame (`_update_panic`): gaze at ScaryObject > sprinting (+6/s) > dark-zone creep (+3/s, flashlight off) > decay. Dread-zone pressure (`DREAD_PANIC_RATE` **2.0**/s) is added **on top** regardless of branch, and inside a dread zone decay drops to `DREAD_DECAY_RATE` 2.0/s — the two cancel exactly, which is what makes KONTUR a no-decay level.

### Zone & movement modifiers
- `add_panic(amount)` — instant spike from scripted events/traps; fires the screamer at max like gaze panic
- **Sprint** (Shift): ×1.6 speed, +6 panic/s, suppresses decay while held — "Walk. Do not run." is a real rule
- **Calm zones** (torchlight): while inside ≥1 `CalmZone`, decay runs at ×2.5 (`CALM_DECAY_MULT`)
- **Dark zones**: while inside ≥1 `DarkZone` with the flashlight OFF, panic creeps +3/s (`DARK_PANIC_RATE`); gaze panic takes priority over dark-creep
- **Dread zones** (corridor Zone C, Void Rooms C+D): decay weakens to 2/s (`DREAD_DECAY_RATE`) and +2/s (`DREAD_PANIC_RATE`) accrues constantly — net idle rate barely negative
- **Flashlight battery**: 240 s of ON time per scene (player re-instances each level, so it resets); stutters below 48 s, then dies for the rest of the level. ON by default at spawn — a player who never toggles it loses it near the corridor's final dark zone
- `apply_slow(duration)` — the beartrap LIMP, speed ×0.45 (`SLOW_MULTIPLIER`); timers don't stack, longest wins. `cancel_slow()` clears it immediately (beartrap escape success). ⚠️ Since 2026-08-15 this is only what happens AFTER you break free — being caught is a hard pin (`begin_qte()` → `_apply_movement()` zeroes `velocity.x/z`), not a slow
- **Read-to-die trap notes**: `NoteUI` feeds `player.add_panic(TRAP_PANIC_RATE × delta)` while a trap note is open (works during tree pause — NoteUI is `PROCESS_MODE_ALWAYS`)

## Folder Layout
```
horror_game/
├── assets_src/            ← ⚠️ UNPROCESSED originals of supplied assets, OUTSIDE game/ so
│                            Godot never imports them. The tools that consume these are
│                            destructive (restencil_door.py: "run it once, on a copy"), so
│                            the shipped file cannot regenerate itself — these are the only
│                            inputs the pipelines can be re-run from. See assets_src/README.md
├── drafts/                ← superseded docs, annotated rather than deleted (REPORT.md,
│                            IDEA_HISTORY.md, and the KONTUR set archived 2026-08-15)
├── game/                  ← Godot project root
│   ├── project.godot
│   ├── scenes/            ← .tscn scene files
│   ├── scripts/           ← .gd GDScript files
│   └── assets/
│       ├── audio/         ← .wav/.ogg files (ambient, SFX, music)
│       ├── elements/      ← reusable scene fragments (hud_canvas.tscn, environment.tscn)
│       ├── models/        ← .glb 3D models
│       ├── textures/      ← .png/.jpg texture maps
│       └── materials/     ← .tres Godot material files
├── game/tests/            ← dev tools (screenshot_corridor.gd — SceneTree script that dumps corridor screenshots to /tmp/corridor_shots/)
├── tools/                 ← 16 dev scripts, stdlib-only unless noted: procedural SFX synths
│                         (make_sfx*.py), audio post (make_loop.py), image post
│                         (cutout_alpha.py, restencil_door.py — these two need Pillow, so
│                         run them with nano-banana-pro/.venv/bin/python3), run_tests.sh
├── nano-banana-pro/       ← image generation skill (Gemini)
├── .agents/skills/        ← Claude skills
└── .env                   ← API keys (never commit)
```

### ⚠️ `*.import` and `*.uid` ARE committed — do not re-ignore them

`.gitignore` deliberately ignores **only `.godot/`** of Godot's generated data (2026-08-15),
matching Godot 4's own recommended ignore file.

Those two file types carry the stable `uid://` identifiers that `.tscn` and `.tres` files
reference — 51 resource refs and 36 script refs across this project. While they were ignored,
every fresh import regenerated them with NEW uids and the scenes kept pointing at the old ones:
measured, **26 stale references across 13 files**, producing 5 `invalid UID` warnings on every
single scene load. Godot falls back to the text path, so the game still ran — which is exactly
why it went unnoticed for so long.

The 26 references were repaired in place (uid values only; `path=` untouched) and the warnings
are now 0. They are portable — every path inside an `.import` is `res://`-relative and the cache
filename is derived from the source path, so the files are byte-identical on any machine.

⚠️ If you ever delete a script or asset, delete its `.uid`/`.import` sibling too. Four orphans
had accumulated and were removed in the same pass.

### Audio import

⚠️ **`tools/make_loop.py` turns a one-shot into a seamless loop** — it trims the fade-out and
crossfades the tail over the head with equal-power windows. Needed because every `.wav.import`
here is `loop_mode=0`, so loops are restarted in code by `finished -> play` and any level
mismatch at the seam ticks once per cycle. Built for the House's `chase.wav`, which arrived as
a 29 s composed piece fading to −25.5 dBFS: measured, the seam gap went 10.2 dB → 0.7 dB.

⚠️ **`tools/restencil_door.py`** is the image counterpart: it crops a generated door to its
leaf and repaints a stencilled sign. Its header records two dead ends worth not repeating (a
median-filter inpaint leaves readable ghosts; there is no clean donor patch on that door
because the sign plate is the brightest surface on it). Run it with the Pillow venv, and AFTER
`cutout_alpha.py`.

New `.wav`/`.ogg` files need a Godot import pass before `ResourceLoader` sees them: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import` (or open the editor and let the scan run). Corridor SFX (`clock_chime`, `glass_shatter`, `beartrap_snap`, `door_slam`, `whispers`) are generated by `tools/make_sfx.py` (seeded, reproducible); `ghost_house.wav` is the corridor ambience. House SFX (`lock_buzz`, `footsteps_above`) are generated by `tools/make_sfx_house.py` (same stdlib-only conventions). Backrooms SFX (`fluorescent_hum` looping ambience, `light_pop`, `rotary_ring`, `phone_whisper`) are generated by `tools/make_sfx_backrooms.py` into `game/assets/audio/level_backrooms/`. **KONTUR SFX** are generated by `tools/make_sfx_kontur.py` into `game/assets/audio/level_5_kontur/` (`ambient_kontur` looping bed, `breathing_behind`, `door_seal`, `acid_hiss`, `pedestal_alarm`, `kontur_flash`, `screamer_kontur`). **Session 10 SFX** are generated by `tools/make_sfx_extra.py` (uv-venv-friendly, still stdlib-only): `pipe_groan` + `apparition_drone` → `shared/`, `breaker_throw` → `level_1_lab/`, and `tv_static` + `music_box` + `water_drip` → `level_2_house/`. **Level 6 (THE BREACH) SFX** are generated by `tools/make_sfx_level6.py` into `game/assets/audio/level_6_breach/` (`ambient_breach` looping bed, `door_slam`/`door_batter`/`door_break`/`blast_door_slam`, `shield_stagger`/`shield_drain_loop`, `screamer_breach`, `creature_growl_near`); the level's `acid_hiss` reuses KONTUR's file directly via `GameState.load_audio()`'s subdir scan. The user-provided `mystical_sound.mp3` lives here too, as `ambient_breach_layer.mp3` — a secondary ambience layer, never the primary bed (see the Level 6 write-up).

**Level 1 locker + nook SFX (2026-07-26, sourced not generated)** live in `game/assets/audio/level_1_lab/`: `locker_shove` (one per TAB press, pitch-randomised), `locker_settle` (the final slide), `nook_breath` (⚠️ **seamless loop** — every `.wav.import` here is `loop_mode=0`, so `level_1.gd` restarts it via `finished → play` and any discontinuity ticks once per loop) and `nook_scream` (the `flash_scare` payload). `GameState.load_audio()` resolves by base name across every subdir, so new names must be **globally unique** — `door_slam` already exists in two folders and the `level_3_corridor` copy silently wins.

⚠️ **A SECOND conversion pass ran 2026-08-15**, by the same rule, freeing **31.9 MB**:
`ambient_asylum` (27.3 → 2.9 MB, 9.5×), `phone_ringing` (40.7×), `nightmare_scream`,
`fridge_scream` and `apparition_snarl`. All five were SOURCED, all five are loaded by base name
through `load_audio()`, and no `.tscn` references audio at all — so the extension change was
invisible to the code. ⚠️ **`chase.wav` was deliberately NOT converted**: it is the output of
`tools/make_loop.py`, whose whole job is a seam that matches to 0.7 dB, and Ogg Vorbis encoder
delay can reintroduce a gap in exactly the loop that tool exists to create. It is also the one
audio file referenced by a hardcoded path (`maze_chase_ui.gd:CHASE_PATH`) rather than by base
name. Both reasons put it on the "leave as `.wav`" side of the rule below.

**Large sourced audio was converted `.wav` → `.ogg` to keep the repo lightweight** (2026-07-21): the big ambient beds and long screamer/scream clips (`ambient_lab`, `ambient_house`, `ambient_void`, `ambient_kontur`, `ghost_house`, `pa_trial4`, `screamer_forest`, `footstep`, `heartbeat` — several were tens of MB as `.wav`) were re-encoded to `.ogg` and the `.wav` originals deleted; the `.ogg` versions are 10–40× smaller. `GameState.load_audio(base_name)` already tries `.wav`/`.ogg`/`.mp3` by extension, so no script changes were needed. The small procedurally-generated SFX from the `tools/make_sfx*.py` scripts (jump-scare stingers, door slams, drips, etc.) were **left as `.wav`** — they're already small (KBs, not MBs) and regenerating them re-emits `.wav`, so converting them would just be undone by the next `tools/make_sfx*.py` run.

## Skills Installed (in .agents/skills/)
| Skill | When to invoke |
|-------|----------------|
| `game-developer` | Godot scene setup, GDScript patterns, performance |
| `shader-techniques` | GLSL shaders, horror post-processing, fog/dissolve effects |
| `3d-modeling` | Blender topology, UV unwrapping, export settings for Godot |
| `nano-banana-pro` | Generate concept art, texture references, UI mockups |
| `grill-me` | Stress-test a design or plan decision |
| `game-tester` (agent) | `.claude/agents/game-tester.md` — runs the whole suite once before a hand playtest, reproduces every failure with a targeted probe, and reports what is broken versus merely suspicious. ⚠️ Forbidden from changing difficulty constants. Distinct from the `game-testing` SKILL below, which is the human-in-the-loop protocol |
| `dungeon-tester` (agent) | `.claude/agents/dungeon-tester.md` — hammers THE NIGHTMARE across seeds, because that level is different every load. `tools/run_tests.sh` deliberately routes `autoplay_dungeon` here rather than into the suite (it is a difficulty instrument, not a regression guard), so this agent is load-bearing rather than optional |
| `maze-tester` (agent) | `.claude/agents/maze-tester.md` — hammers the House map-and-chase minigame across seeds, because it builds a fresh maze on every open. Runs `check_maze_gen` (200 seeds) + `check_maze_chase` (40 seeds x 3 passes), quotes seeds with every failure, and never touches a difficulty constant. Distinct from `game-tester` (whole suite once) and `dungeon-tester` (level 7's generator) |
| `game-testing` | Playtest loop: launch the game from any level, capture a `DebugLog` session while the user plays, then diagnose anomalies (bugs, unwinnable states, difficulty spikes, puzzles being guessed rather than read) and propose fixes. **Confirms every finding with the user before changing game logic** — the agent's read can be wrong and "brutal on purpose" is a legitimate answer. Contains the log-signature tables (panic % → constants), known false positives, and the verification rules (assert with physics queries; never let a test reach the win condition by emitting the signal). |
| `fix-void` | Diagnose and fix black void / open-space holes in CSGBox3D levels. Use whenever a user reports a black rectangle, missing wall, floor gap, or visible void. The skill contains the full diagnostic protocol: localise → map coverage → identify void type → compute fix node → verify → write. Also contains a table of all voids already fixed in this project. |
| `idea-generator` | Discussion-only creative-direction session: reads the mechanics inventory (this file) + `GAME_MECHANICS_IDEAS.md` + `TODO.md`, researches well-rated horror/indie games, filters ideas through feasibility against existing systems, then runs an `AskUserQuestion` pass with the user to accept/reject/defer each one. Writes its results **into `GAME_MECHANICS_IDEAS.md`** — new accepted items with implementation sketches into §4, new verdicts appended to §5 (persistent, so future sessions don't re-pitch rejected ideas). ⚠️ It must **not** recreate `REPORT.md` / `IDEA_HISTORY.md` at the repo root; both were consolidated into `GAME_MECHANICS_IDEAS.md` on 2026-07-27 and archived to `drafts/`. **Never implements anything itself** — a separate later request does that, pointed at `GAME_MECHANICS_IDEAS.md`. |

## Asset Pipeline
- **3D models:** Blender → File > Export > glTF 2.0 (.glb) → `game/assets/models/`
- **Textures:** PolyHaven / AmbientCG (CC0 PBR) or Stable Diffusion → `game/assets/textures/<subfolder>/` (see TEXTURES.md for the per-level subfolder layout)
- **Audio:** Freesound.org (CC0) or MusicGen (HuggingFace) → export as .ogg → `game/assets/audio/<subfolder>/` (`shared/`, `level_1_lab/`, `level_2_house/`, `level_3_corridor/`, `level_backrooms/`, `level_5_kontur/`, `level_6_breach/`, `level_9_dungeon/`, `level_4_void/`)

⚠️ `GameState.AUDIO_SUBDIRS` is a HARDCODED list, not a filesystem scan — a new audio folder is invisible and `load_audio()` returns null for everything in it until the folder is added there.
- **Characters/animations:** Mixamo (free) → download as .fbx → open in Blender → export as .glb

### Texture audit rule (run at the start of every level content session)
1. Read `TEXTURES.md`
2. For each row with `status: done`, check the relevant level script (`level_1.gd`, `level_2.gd`, etc.) to confirm the texture is loaded inside `_apply_textures()` (or equivalent)
3. If a `done` texture is **not** referenced in its level script, add the load + apply code before doing any other work
4. For decal-type textures (painting, cobweb, poster, blood — applied via MeshInstance3D quads), check the corresponding `.tscn` for the MeshInstance3D node; add it to the scene if missing

## Free AI Asset Tools
- **3D gen:** TripoSR, Shap-E (HuggingFace Spaces, free)
- **Audio gen:** MusicGen by Meta, Bark (HuggingFace Spaces, free)
- **Image gen:** nano-banana-pro skill (Gemini API) — budget is ~20 images total, use sparingly. Prefer PolyHaven/AmbientCG for standard PBR textures. Reserve nano-banana for unique horror imagery (wall art, notes, posters, UI backgrounds) that can't be sourced free elsewhere.
- **Narrative/story:** OpenRouter — `nvidia/nemotron-3-super-120b-a12b:free` via `https://openrouter.ai/api/v1`

## nano-banana-pro Python Environment
Deps are installed in a venv at `nano-banana-pro/.venv/`.
Always invoke the script with the venv Python:
```bash
nano-banana-pro/.venv/bin/python3 nano-banana-pro/generate_image.py "prompt" -o path/to/output.png
```

### ⚠️ Always convert nano-banana-pro output to real PNG before importing into Godot
See `ISSUES_SOLUTIONS.md` — Issue 1 for diagnosis steps and the `sips` fix.

## Testing

```bash
tools/run_tests.sh          # the whole headless suite, one summary table
tools/run_tests.sh -q       # summary + failing output only
tools/run_tests.sh maze     # only tests matching a substring
```

Exit code is the number of failing tests. The `TESTS` array in that script is the only index of
what the suite actually covers — keep the one-line comment beside each name accurate.

⚠️ **`--import` is not optional after adding a `class_name` or an asset** (the runner does it for
you). Godot caches class names in `.godot/global_script_class_cache.cfg`; until it rescans, a new
`class_name` is "not declared in the current scope", which makes every level script that uses it
fail to **parse**, which makes tests find nothing and report PASS. That exact sequence produced a
green "0 apparitions in 400 s".

⚠️ **A green run is not a good build — read the numbers.** Several tests exist because a
*passing* result was meaningless: `count_apparitions.gd` now asserts a minimum count (it once
reported "0 in 400 s" as a tidy pass on a build with the monster switched off), and
`check_apparition_clearance.gd` asserts its own sample size (it reported "0 spawns checked …
PASS" when the script under test failed to compile).

⚠️ **Three more vacuous passes were found on 2026-07-28/29, all of them green.** Read them as a
set, because the shape repeats: *the assertion ran, and measured nothing.*
- A bus-restore check sampled at "frame 130" — headless runs uncapped, so a frame count is not a
  clock; it landed mid-tween and reported a false failure. **Time-based now.**
- A door-clearance check called `swing_ajar()` and measured in the SAME frame. A `Tween` does not
  run until the next one, so it measured un-swung doors and reported a comfortable 2.81 m for a
  panel that had not moved. The real figure is 2.02 m.
- A painting-position check asserted only `y < 0.3`. A painting teleported THROUGH the floor to the
  world origin satisfies that. It now asserts the room and the facing as well.

⚠️ **A test that fails to PARSE exits 0 and the runner counted it as PASS** — Issue 44. `run_tests.sh`
now greps for `Parse Error` / `Failed to load script` and forces a failure. ⚠️ And never write
`bool(node.get("flag"))` in a test: a missing property throws, the throw aborts `_process` before
the stage counter AND before the timeout check, and the test loops forever (Issue 45 — one run hung
28 minutes on a 30-second timeout).

⚠️ **Four guards added 2026-08-15 that nothing else names.** Each exists because the feature it
protects had already shipped broken once:
- `check_interact_reach.gd` — every interactable in Levels 6/7 answers E from a realistic
  distance AND from 25° off-axis, **aiming at the mesh, never at the collider**. Aiming at the
  collider is what let the previous version pass against colliders a player could not hit.
- `check_turn_mirror.gd` — the mirrors reflect, and the figure is on `MIRROR_ONLY_LAYER` so it
  is in the glass and NOT in the corridor. A reflection cannot be asserted; the wiring can.
- `check_lock_input.gd` — typed digits land, and the Esc hint survives a wrong guess.
- `check_corridor_repeats.gd` — no sound in the Corridor is a loop, and the score outlives the
  296 m hush.

Test naming: `check_*` assert, `walk_*` drive a physics body along a route, `autoplay_*` drive the
**real** player through `player.gd`'s `ai_*` surface (see `tests/autoplay/autoplayer.gd` for why
that exists rather than simulated key presses), `screenshot_*` need a render target so they run
**without** `--headless`, `probe_*` are throwaway diagnostics kept only when they document
something durable.

`.claude/agents/game-tester.md` is a subagent that runs the suite before a hand playtest,
reproduces failures with targeted probes and reports. It is explicitly forbidden from changing
difficulty constants — that is always the user's call. It is distinct from the `game-testing`
SKILL, which is the human-in-the-loop playtest protocol.

## Debugging
Before diagnosing any bug, read `ISSUES_SOLUTIONS.md`. It documents the hardest bugs encountered so far — Godot input event double-fire, UI anchor off-screen rendering, raycast geometry misses on flat objects, the Gemini JPEG-as-PNG import failure, and double-screamer re-entry on rapid keypresses. Re-solving a known issue wastes time.

## Code Conventions
- GDScript snake_case for variables and functions, PascalCase for class names
- One script per scene node where possible
- Signals preferred over direct node references for decoupling
- No magic numbers — use named constants or exported variables

## API Keys
All keys live in `.env` at the project root. Never commit `.env`.
See `.env.example` for required keys.
