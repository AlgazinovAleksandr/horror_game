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
- **"The ward is occupied" (2026-07-28, reworked 2026-08-16).** The room previously had *no scares
  whatsoever* — 60–120 s of nothing. Now: the **light switch sticks on the first press**
  (`LightSwitch.presses_needed = 2`) — it clunks, the plate blips, and one fluorescent stutters
  alight for 0.4 s, showing the ward you have been crossing blind, then dies. The two spare gurneys
  carry **sheeted forms**. Breathing (`nook_breath`) near `WallFront`, cut the instant the lights
  come on
  - ⚠️ **The glimpse uses the MIDDLE tube (z=0), not the far one** (2026-08-16). It was the far
    tube (z=−6) on the sound grounds that the flash should show somewhere the player has *not*
    been — and that lost to a measurement: with `omni_range` 9 from z=−6, both sheeted beds and
    both IV stands sat at z=+5…+6.5, **11 m away and completely out of reach**, so the best beat in
    the room lit bare floor. One occupied bed was moved to `GLIMPSE_GURNEY_POS (3.6, 0, 1.8)`. The
    middle tube specifically, because `_on_switch_flipped()` leaves it dead forever: the 0.4 s
    flash is the only time the centre of the ward is ever lit from above, and afterwards that spot
    is a permanent hole in the ceiling light. `check_intro_beats.gd` asserts the lit tube's range
    reaches an occupied bed — the old "and it is the FAR end" assertion was true and useless
  - ⭐ **One bed is EMPTY afterwards** (2026-08-16). The bed the glimpse showed loses its covered
    form the instant the switch throws, while the room is still pitch black. No sound, no panic, no
    camera move, no acknowledgement, nothing looks at you — `MovedProp`'s register (SCARY P6)
    applied to a state change, and unwitnessable by construction. It is what gives the glimpse a
    purpose: the flash stops being a mood beat and becomes the only evidence the room used to be
    different. A player who did not look during it loses nothing and never knows. ⚠️ It is
    `queue_free()`, never `visible = false` — CSG collision is not inherited from a hidden parent
  - ⚠️ **The sheeted forms are ONE SMOOTH SURFACE, not boxes — and specifically not MORE boxes**
    (rebuilt 2026-08-16, second revision). This prop has been rejected on a replay twice:
    | version | what it was | the user's verdict |
    |---|---|---|
    | v1 | two axis-aligned boxes — a mound and a head bump 6 cm proud of it | *"Is it a human on the bed? Or a pillow and a blanket?"* |
    | v2 | eleven axis-aligned boxes — head, shoulders, chest, abdomen, hips, thighs, knees, shins, two feet, on a slab drape | *"This still does not look realistic."* — it read as a **stack of blocks**: every part legible as a discrete rectangular step, hard 90° corners, top faces coplanar and taking identical light |
    The lesson is structural, not a tuning miss: **axis-aligned boxes cannot make a draped organic
    mass**, and more parts made the wrong silhouette more detailed. v3 is a `SurfaceTool`
    heightfield — an indexed, welded grid sampled from a soft union of ellipsoidal blobs (head /
    neck / shoulders / chest / waist / hips / two thighs / two knees / two shins / one foot tent),
    blended with a polynomial smooth-max, with **analytic central-difference normals** so the
    shading is a gradient and there is not one flat facet on it. The same field carries the drape:
    past a rounded-rectangle boundary the height plunges to a hem below the mattress line
    - ⚠️ **The body must be narrow enough to leave a GUTTER.** The first draft of v3 gave the
      shoulders `rx` 0.37 against a mattress half-width of 0.425 and rendered as *a mattress with a
      slight bulge* — the v1 complaint again. The sheet is back down to 0.02 m by |x| = 0.24 at
      every station, and that flat gutter is what says the mound is a body lying ON the bed
    - ⚠️ **Nothing may be taller than it is wide** — a blob whose height exceeds its radius renders
      as a cone, and one render had two of them at the foot of the bed. There is **one** foot tent
      spanning both feet, not two: that single peak at the end of the bed is the whole morgue image
    - ⚠️ **Cloth BRIDGES concavities.** Two leg blobs alone put a 55°-per-side crevasse down the
      middle of the legs (measured: adjacent normals 110° apart). A wide low blob at (−0.004,
      0.605) *is* the sheet spanning between the legs; worst normal split on the shipped build is
      **71.5°**, against a box corner's 90° and a coincident pair's 180°
    - The texture (`sheet_linen.png`, generated) went on **last, on a silhouette that already
      worked** — it is not the fix, and `check_intro_sheet.gd` passes with the file deleted. Its
      tint is DERIVED so the mean colour lands on the `(0.44, 0.43, 0.40)` v2 shipped with
    - Silhouette, crown to sole: head 0.203 · neck 0.104 · shoulders 0.228 · chest 0.253 · waist
      0.172 · hips 0.221 · thighs 0.175 · knees 0.140 · shins 0.108 · foot tent 0.164
    - **`tests/check_intro_sheet.gd`** exists because the property the user rejected — the SHAPE —
      was the one thing nothing measured: `check_wall_overlap` had no opinion, `check_intro_beats`
      only counted the forms, and `check_art_aspect` skips it for carrying no flat quad. It asserts
      off the BUILT MESH ARRAYS (never the generator's own height function): no right angles, the
      mound is smooth-shaded not faceted, it is one welded surface, the side silhouette has ≥3
      landmarks separated by real troughs, it drapes below the mattress, and **no hem vertex is
      inside the gurney frame's AABB**. Verified red against a faithful rebuild of v2
  - ⚠️ **The mattress decal is only on the EMPTY bed.** A covered bed shows a sheet, and the decal
    plane physically intersected the old sheet boxes
  - ⚠️ Each gurney's `GurneyFrame_*` / `GurneyMattress_*` / `SheetedForm_*` carries a **position
    tag** in its node name. All three gurneys used the bare name `GurneyFrame`, so Godot silently
    renamed two of them and anything looking one up by name found only the first — Issue 17, the
    fourth instance in this one file
  - ⚠️ **NO jumpscare in this room.** `INTRO.md` §2 specced a mid-fumble nightmare flash; it was
    built and then cut on the first playtest (*"the screamer at the intro level is not needed"*).
    The cold open on START already spends that image, and firing it again in the one room with no
    fail state teaches the player the image is free. `check_intro_beats.gd` asserts its ABSENCE
  - **The wheelchair turns to face the table** once the note is read — on **proximity + looking**
    (within `WHEELCHAIR_TURN_DIST` 3.2 m, dot > 0.55), with a caster creak, over 1.1 s. ⚠️ This
    deliberately INVERTS `MovedProp`'s happens-off-screen rule: an anomaly nobody witnesses is
    worth less than an event they certainly see, in a 90-second tutorial room. See the same call in
    the House
    - ⚠️ **Both tests are HORIZONTAL-ONLY, and the chair sits at x = 2.4** (2026-08-16). The facing
      test was already horizontal; the DISTANCE test was not, and the camera is 1.65 m above the
      chair's floor anchor — so a 3.2 m 3D radius was really **2.741 m of floor**, and the walk
      from the note to the exit door passes at 3.0 m. **The beat could not fire at any yaw**, and
      the 2026-08-16 playtest is the log of it not firing. The chair also moved x 3.0 → 2.4 so the
      clearance is ~0.8 m rather than a knife-edge 0.2: a beat that only fires on a perfect line is
      worse than one that never fires, because nobody can tell it is broken. `WHEELCHAIR_TURN_DIST`
      is unchanged
    - ⚠️ **The sound is `intro/wheelchair.wav`** (user-supplied, 2026-08-16), replacing the
      `gurney_creak` fallback the beat had used for its whole life because `wheelchair_turn` never
      existed. Measured: 2.009 s, mono 44.1 kHz, −2.3 dBFS RMS — **9.6 dB hotter than
      `gurney_creak`**, so the gain is `WHEELCHAIR_SFX_DB = −7.6` (the old call played the creak at
      +2.0), set from the file's level rather than from a plausible number. And the file **does not
      decay** — its last 0.1 s is still at −1.3 dBFS — so it is played at full level for the whole
      1.1 s turn and then faded over 0.5 s (`WHEELCHAIR_SFX_FADE_START` / `_FADE_TIME`), because
      the alternatives are a creak that stops dead with the chair or a hard cut at full amplitude
      0.9 s after it. `check_intro_beats.gd` asserts the STREAM, not just that something plays — a
      working fallback is exactly what hides a missing asset
  - ⚠️ **The breathing is CLOSE, not far.** `FarBreath` sits 1.61 m from where the player wakes,
    inside its own `unit_size`, so it plays at full volume into the ear at the moment of sitting up
    and recedes as they cross the ward. This file described it as "at the far wall" for months; it
    never was. Keep it — something breathing behind you as you wake, which quietens as you walk
    away, beats a distant sound you could go and inspect, and the lights coming on delete it before
    you ever can. The node name is kept only because `check_intro_beats.gd` looks it up
- ⚠️ **The exit door is SEATED INTO `WallBack` and wears a jamb + lintel casing** (2026-08-16).
  `EXIT_DOOR_POS` was a literal and the leaf floated **0.275 m clear of the wall**, full height,
  full width, with open air behind it — playtest capture: *"the door is not connected to the
  wall"*. It is now derived from `WALL_BACK_FACE_Z` + `DOOR_SIZE` (back face 20 mm inside the wall,
  the same convention `level_1/2/kontur/dungeon` already use), and `_build_door_casing()` adds two
  jambs and a lintel so the leaf reads as recessed. ⚠️ The casing is **siblings of `ExitDoor`, never
  children** (the ending frees the door and needs the frame), and has **no colliders** (a collider
  on the only doorway wall is how this project seals a room by accident)
- ⚠️ `_corrupt_room()`'s planks/red light are derived from `EXIT_DOOR_POS` + `DOOR_SIZE`. They were
  literals from the OLD 5.6 m room and floated in open space 6 m from the door — the game's final
  beat, visibly broken, for the life of the bigger ward. ⚠️ **The derivation was right and the
  anchor was wrong**: until the door was seated (above) the planks still hung 0.485 m in front of
  blank concrete. Both are now asserted, in the normal room and under `GameState.is_ending`, by
  `tests/check_intro_geometry.gd`
- ⚠️ **There is a real candle now, and its light is `visible`** (2026-08-16). `_darken_scene()` hides
  the candle light for the blind fumble and nothing ever un-hid it, so it tweened to a healthy 1.97
  energy on a hidden node — **a hidden `Node3D` light emits nothing** — and there was no candle mesh
  at all, only an `OmniLight3D` hanging 2.2 m above the table. With the tube above the table
  deliberately dead, the note the player is *required* to read had no light on it whatsoever.
  ISSUES_SOLUTIONS **Issue 55**; the flame is the room's only emissive surface and is hidden during
  the fumble with the light
- ⚠️ **Every textured quad is sized from its own artwork.** Four of five were stretched, worst 3.97×
  (`gurney_intro.png` was a 1672×941 landscape photo of a whole gurney — frame, rails and the floor
  around it — squashed onto a portrait mattress quad; it is now a plain stained pad at the quad's
  aspect). The cabinets were rebuilt to match their art too: a wide two-door medical cabinet on a
  `QuadMesh`, not a landscape photo cropped onto a tall narrow box face (Issue 24).
  `tests/check_art_aspect.gd` asserts mesh aspect against **effective** texture aspect (pixel aspect
  × `uv1_scale`, because the note deliberately UV-crops a square, black-backed source)

**Level 1 — The Lab (institutional wing)** — rebuilt procedurally (Session 10)
- Built at runtime in `level_1.gd` via `RoomBuilder` from a 10-room graph (`ROOMS`/`DOORS`): reception → main corridor with 2 exam rooms → a cross-junction onto the records room and a **sealed morgue** → observation room → exit vestibule. The `.tscn` keeps only `Player`/`Environment`/audio/`HUDCanvas`; `_clear_old_scene()` frees the old hand-built nodes via a `PRESERVE` whitelist
- **Power-restore quest**: 3 `Breaker`s (`breaker.gd`) — Exam1, Records, and BreakerNook (see below). Each `flipped` → `_on_breaker_flipped()`; the third → `_restore_power()` lifts the lamps to full and drops the `MorgueShutter` (a `CSGBox3D` gating the morgue doorway). Three tiers, and **each tier is a different verb — see it / read for it / hear it**. Exam1 stays lit-and-obvious on its wall centre. ⚠️ **No breaker self-illuminates** — the panel used to wear its own art as an `emission_texture` (0.25) and the lever glowed at 0.7, which made even the deliberately-hidden Records one the brightest object in the level (playtest capture #1; ISSUES_SOLUTIONS Issue 33, an Issue-27 recurrence). `glows` now gates only the lever *indicator* at `INDICATOR_EMISSION = 0.12`, because red-vs-green is state feedback rather than an affordance. Records' note and warning sign live on its previously-unused north wall (their old spot became the DarkCorridor doorway)
  - ⚠️ **`_restore_power()` must skip the rooms spawned dark.** `_spawn_lights()` gives EVERY room in `ROOMS` a lamp and hands the eleven `NO_LAMP_ROOMS` one at energy 0.0 — dark because the lamp is off, not because there is no lamp. `_restore_power()` used to raise all of them unconditionally, floodlighting the Morgue (whose whole design is `DarkZone` + beartrap + don't-look triggers) and the entire navigate-by-ear wing. It now carries the same `if entry[1] > 0.0` guard `_on_breaker_flipped()` always had. ISSUES_SOLUTIONS **Issue 36**; regression-locked by `tests/check_lab_locker.gd`
- **Records breaker — the locker** (`lab_locker.gd`, 2026-07-26): the panel isn't merely hidden, it is **physically sealed** behind a steel locker standing flush against it, so the interaction ray hits the locker first. ⚠️ **The locker is a COVER; the GATE is `Breaker.blocked` (2026-08-16).** Occlusion degrades continuously and a three-stage push therefore opened at stage two: measured, one shove leaves the panel unreachable but two clears it entirely and the player found that on the first playtest (*"Even though I did not pull the case till the end, I still could flip the breaker"*). `breaker.gd` now has `blocked` / `unblock()` / `can_interact()`; `level_1.gd` sets it on the Records breaker and clears it **only** from `LabLocker.moved` — after the third bar and the settle tween — and again in `_restore_progress()`, because `move_aside_instantly()` deliberately does not emit `moved`. While blocked the breaker is completely inert: no prompt, no interact target, E does nothing. ISSUES_SOLUTIONS **Issue 57**; `tests/check_lab_breaker_gate.gd` drives the real `ai_interact()` path at 1 and 2 shoves and carries a positive control. Two gates: (1) `unlocked` flips only when the player reads the **maintenance note on Observation's south wall**, the opposite corner of the floor — before that, `interact()` prints a flat refusal toast; (2) the push itself, a tug-of-war bar fed by mashing **SPACE** (`push_effort`, a new `project.godot` action on `KEY_SPACE`) at `PUSH_PER_PRESS 0.10` against `PUSH_DECAY 0.18`/s. It takes **`SHOVES_NEEDED = 3` full bars**, not one — each fill lurches the locker and resets the bar (playtest 2026-07-26: *"probably we need to require more effort — currently too simple"*). ⚠️ **The travel is FRONT-LOADED onto the last bar (2026-08-16), and the locker is 1.4 m wide, not 1.0.** The flag above held, and the same player filed the prop as broken anyway on the next replay — *"I did 2 out of 3 rounds. Even though I cannot flip the breaker, I can see it very well. I should not see it fully once I do all 3 out of 3"* — because **a panel in plain sight that refuses to answer E reads as a bug, not as a locked door**. So the two intermediate lurches are now `SHOVE_DIST 0.14 m`, inside the 0.35 m the wider carcass overhangs the panel by, and the third bar slides the remaining 0.82 m of `TOTAL_TRAVEL 1.10` and is the one that actually reveals it. Measured by ray-sampling the panel's front face on a 13x17 grid from six eye positions (`check_lab_breaker_gate.gd`, 5304 rays): **0.0 % visible after 1 and after 2 shoves, 100 % front-on after 3**, against 15.4 % / 84.6 % / 100 % for the old uniform profile. ⚠️ **No difficulty constant moved** — `SHOVES_NEEDED`, `PUSH_PER_PRESS`, `PUSH_DECAY` and `PUSH_PANIC` are the user's call and are untouched; only what you can SEE at each stage changed. ISSUES_SOLUTIONS **Issue 57's amendment**. Staged rather than one longer bar on purpose: the note says it "moves in fits", and a single 10 s bar with no intermediate feedback reads as broken rather than as heavy. Failing just aborts and is retryable; `PUSH_PANIC 1.2`/s is the only cost. ⚠️ **Letting go keeps the shoves you have already made** — only the bar resets. The toast used to say *"the locker settles back"* and the maintenance note said *"it slides back the moment you stop"*; both were false, and both are what made the partial-shove bypass read as intended behaviour. Both were rewritten (2026-08-16). ⚠️ **The gate is HARD and there is deliberately NO pointer to the note** (confirmed with the user) — a player who never searches Observation cannot restore power. Don't soften it without asking
  - ⚠️ **Before the note it is COMPLETELY inert**, not merely refusing (playtest: *"press E should not even appear"*). `LabLocker.can_interact()` returns false, and `player.gd:_update_interact_prompt()` now consults an **optional `can_interact()`** on any prop before showing "Press E" *or* setting `_interact_target` — so E does literally nothing. Props without the method behave exactly as before; this is the general opt-out the project lacked
  - The push **does not pause the tree** (unlike `maze_chase_ui.gd`/`combination_lock.gd`) — `beartrap.gd` is the closer relative. `player.freeze_input()` blocks movement *and* look for free (`_apply_movement` and `_unhandled_input` both early-return on `_input_frozen`), which is the camera pin; the world keeps running behind you. The player is tweened onto a brace mark 0.9 m in front first — not framing polish, it is what stops the slide passing through them. ⚠️ `ARM_DELAY` is load-bearing: `interact` both *starts* the push and *cancels* it, and `_process` polls `Input.is_action_just_pressed`, so without it the opening press closes it on frame one (`note_ui.gd`'s `_block_close` exists for the same collision)
  - ⚠️ **The old spark/flicker tell is DELETED** (`_tick_breaker_spark` + its light, `BUG_FIX.md 4.1`). It did not hide the breaker, it pointed at it: the tell was the loudest and brightest thing in Records, so "search the room" collapsed into "walk toward the crackle". Do not re-add an ambient tell here. `breaker_spark.wav` and `BREAKER_SPARK_MIN/MAX` survive — `_tick_dark_breaker_tell` still uses them for the nook's flavour transient. The Records filing-cabinet bank was trimmed 3 → 2 units and shifted west to clear the locker's footprint
- **The dark wing — navigate-by-ear maze (rebuilt, playtest 2026-07-25)**: Exam2's breaker lives in **`BreakerNook`** at the far end of a **10-room lightless maze** off Records' west wall. Previous passes had 4 rooms and exactly one binary choice, which playtest called out as "too simple… make the geometry harder, and probably add some real audio so we can navigate based on that" (capture #2). Layout — `DarkCorridor` → `Junction` (**decision 1**, three ways) → *west* `WestCorridor`→`Plant` **(dead)** / *north* `NorthSpur`→`NorthVault` **(dead)** / *south* `SouthSpur`→`SouthHall` (**decision 3**) → `PumpRoom` **(dead)** or `BreakerNook`. Three decision points, three dead ends, ~50 m of walking; the terminus is ~28 m from Records' lamp, four times its 11 m range. ⚠️ Rooms are kept in three disjoint z-bands (north ≥14.5, middle 10.5–14.5, south ≤10.5) so limbs can't collide as the graph grows; a doorway only cuts walls its **span** overlaps (`room_builder.gd:199`), so planes are safely reused between bands. All ten rooms are in `NO_LAMP_ROOMS` and share **one** flashlight-lock `Area3D` (`_spawn_breaker_nook_zone()`, bounds x −37..−12 / z 4.2..24 — re-derive it whenever `ROOMS` changes) that calls `player.lock_flashlight()` on entry and symmetrically `unlock_flashlight()` on exit; leaving is always the safety valve. It must stay **one** zone — adjacent Area3Ds fire `body_exited` before `body_entered` and would strobe the lock. **No `DarkZone`** anywhere in the wing (would double-tax the exact posture the premise requires — Issue 18)
  - **The tell is a real two-layer positional beacon** (`_spawn_dark_beacon`): a far cue (`breaker_hum`, `unit_size 16`) that carries the length of the wing and gives a **bearing**, plus a near confirm (`breaker_buzz`, `unit_size 9`) that only resolves in the last room or two and distinguishes "right branch" from merely "right direction". Both are continuous loops at the breaker, self-restarting via `finished → play` (every `.wav.import` here is `loop_mode=0`); both generated by `tools/make_sfx_extra.py`. Pattern lifted from `backrooms_zone2.gd`, whose header comment is a post-mortem of this same mistake. The 8–12 s `breaker_spark` transient stays on top as flavour only
  - ⚠️ **DELIBERATE (2026-08-16) — there IS a meter again, and it is not the old one.** `lab_wing_meter.gd` (`LabWingMeter`), a bottom-of-screen "PANEL HUM" scale shown only inside the wing and freed the instant the breaker is thrown. Added on the user's **explicit call**, made after being shown ISSUES_SOLUTIONS Issue 34 *and* `GAME_MECHANICS_IDEAS` §5.2(2), both of which name this widget as a thing the project does not build (*"finding your way through sounds only in the complete dark is hard for the unexperienced user"*). **Do not re-litigate it and do not delete it as a regression.** ⚠️ **The condition attached to it is that it may not LIE.** The deleted `panic_hud.set_breaker_proximity()` measured straight-line distance and read a warm ~0.43 from inside a dead end — it pointed at a wall, and it also masked the fact that `_spawn_dark_breaker_tell()` was a one-line stub that spawned nothing (Issue 34). This one runs **Dijkstra over the wing's own doorway graph** (`setup(ROOMS, DOORS, WING_ROOMS, breaker_pos, "BreakerNook")`) and normalises against the furthest room's path distance, so the scale is derived from the geometry rather than typed in. Measured on the shipped layout: **Plant reads 0.04** — 30.0 m of walking against 6.6 m of straight line, a 4.6× lie the old bar would have reported as 0.79 — while the real route reads 0.15 → 0.31 → 0.37 → 0.46 → 0.65 → 0.80 → 0.96, and outside the wing it reports **no reading at all**. Locked down by `tests/check_wing_meter.gd`. It is a scalar: the two-layer beacon still owns BEARING, which is the half of a maze a number cannot answer
  - ⚠️ **The panel DID leak, and the measurement that said otherwise was wrong (2026-08-16).** The user reported it twice — *"I can see this breaker visually - it should appear only when I am very close to it"*, then, from 9.4 m with the torch off, *"I am standing far away from the breaker and I see it. Should be darker"* with a screenshot of a black frame containing a legible pale rectangle. The first probe reported *"peak ~1.5 of 255, wall 0.0000, does not leak"* and that conclusion is **retracted**: it compared an ABSOLUTE level against a background of zero (against 0.0000, 1.5/255 is not dim, it is the only thing in the frame), it averaged an 11x11 box at the panel's CENTRE when the leak was the panel's bright BORDER, and it sampled un-scaled `unproject_position()` coordinates into a HiDPI image so it was reading the wall, not the panel. See ISSUES_SOLUTIONS **Issue 62** — *a measurement that is physically correct and perceptually wrong*.
  - **The real cause was the ART.** `lab_breaker_panel.png` shipped as an opaque RGB PNG whose background was a **baked alpha checkerboard** — 20.05 % of its texels above 0.90 sRGB, border ring 0.974 — and near-white albedo is the brightest thing obtainable in a level with no glow, no fog and no tonemapping. `tools/flatten_alpha_checker.py` flood-fills that background dark from the image border and crops; the original is kept at `assets_src/textures/level_1_lab/lab_breaker_panel_raw.png`. On top of that, `Breaker` now tints a `glows = false` panel with `PANEL_TINT_DIM` (0.28) instead of `PANEL_TINT` (0.6). Re-measured as CONTRAST against the wall around it, torch locked off — panel max / p99.5 / pixels brighter than the surrounding wall: **4.1 · 4.1 · 856-of-9153 (9.4 %) before → 1.0 · 0.0 · 0-of-9153 after**, at 6, 10, 15 m and at the player's own capture pose alike. The panel is now DARKER than its wall. ISSUES_SOLUTIONS **Issue 63**; guarded headlessly by `tests/check_nook_dark.gd` and re-measurable on a display with `tests/screenshot_nook_panel.gd`. ⚠️ **The beacon and the meter remain the only ways to find it.**
  - **The payoff — the breathing, then a scripted reveal you are TURNED to face** (`_on_nook_breaker_flipped`, hooked to *that breaker's own* `flipped`, never to the shared 3/3 counter: the player picks the order, so "the third one flipped" needn't be the one standing in the dark). Beat: the beacons **stop and free** the instant the lever throws (the hum you navigated 50 m by dies with the equipment) → `nook_breath` starts, repositioned every frame to 1.1 m behind the player's head (`unit_size 3.0`) so it follows if they walk → after the unchanged `NOOK_SCARE_DELAY = 5 s` a **watch arms** (`_tick_nook_watch`) → it fires as soon as the player is `NOOK_TRIGGER_DIST = 3 m` from the figure's mark, with `NOOK_WATCH_TIMEOUT = 6 s` as the backstop for someone who never moves → t+0.00 the positional `nook_scream` at the mark **leads**, horizontal velocity is zeroed, `freeze_input()`, and `player.turn_to_face()` swings the camera over `NOOK_TURN_TIME = 0.45 s` → t+0.45 the arc-flare + the `lab_nook_figure.png` billboard alpha-tweened 0→1, held `NOOK_REVEAL_TIME = 0.15` → t+0.75 `Screamer.flash_scare(lab_nook_face.png, "dark_jumpscare", 1.6)` + `NOOK_SCARE_PANIC = 20`, and control comes back with the picture. The documented 0.30 s *it moved* → *it's on you* gap is preserved, now measured from the moment the figure becomes VISIBLE rather than from the scream; `flash_scare` never stops its audio, so `dark_jumpscare`'s 3.5 s tail deliberately keeps ringing after the picture drops
  - ⚠️ **The position trigger and the camera turn are the USER'S OWN DESIGN** (2026-08-16, capture #6: *"sometimes I cannot see the creature which gives the jumpscare… it must appear at the place the player is looking at"*, and their proposal, *"you need to pass 3 metres away from the breaker - the camera turns exactly at the needed position and then this creature… appears"*). It replaced a four-heading fan off the camera whose **fallback was unvalidated**: with no heading clear it placed a 1.5 m billboard 1.5 m directly behind the player's head having checked nothing, and two of its four headings were outside the FOV by construction. Measured across 100 poses in BreakerNook/SouthHall/SouthSpur, only **27 %** of placements were already in frustum — that is the lottery the turn removes. `_place_nook_figure()` now tries a short list of KNOWN marks (the designed spot on BreakerNook's centre line, mid-room, then points back along the route the player walked, each pulled clear of its room's walls by `_clamp_into_room()`), validates with **rays only** (Issue 40) including the eye→chest line of sight — which is the member of the set that catches "inside a wall", because an outward fan cannot: CSG backfaces do not collide (**Issue 59**) — and, if nothing fits, **skips the figure and keeps the sting** rather than burying it. `tests/check_nook_figure.gd`
  - **The wing lights up afterwards** (`_light_the_wing()`, called from `_nook_cleanup`): the flashlight-lock `Area3D` is freed, `unlock_flashlight()` is called, and the **ten wing rooms** fade to `WING_LIT_ENERGY 0.5`. Playtest 2026-07-26: *"after the jumpscare we need to turn on the light — because very hard to escape the place"* — the log showed 110 s of wandering afterwards, ending in a dead end. Partly this feature's own doing: throwing the breaker kills the beacons, so the scare removed the only landmark and then asked for a 50 m walk back in the dark. The darkness was never the point in itself; it was the cost of the navigate-by-ear puzzle, and that puzzle is *solved* the moment the breaker is thrown. ⚠️ This is a deliberate, narrow exception to Issue 36 covering `WING_ROOMS` **only** — the Morgue is in `NO_LAMP_ROOMS` too and must stay pitch black, because its `DarkZone`, beartrap and two don't-look triggers all assume a room searched by torchlight ⚠️ The toast now also says the torch works again (**[F]**) — `unlock_flashlight()` only clears the flag, and while the lock was on, F answered with the same dead-battery click a flat battery gives. The 2026-08-16 player pressed F once on the way in and never again: 306 s afterwards, including the whole DarkZone morgue, and a death in it. See `player.gd`'s locked-vs-dead split. ⚠️ **Deliberately SURVIVABLE** — no rule, no fail state. Flipping this breaker is mandatory, and an unavoidable event must never coin-flip a death; a player who can't SEE a figure materialise also can't judge "hold still or flee" (the KONTUR Gate 7 / Backrooms Flood mistake). The cost is real anyway: 20 of `PANIC_MAX` 50, then ~50 m back through the maze, where sprinting is +6/s with decay suppressed
  - ⚠️ The figure is **unshaded**, so the flare cannot light it — unshaded materials ignore lights entirely. (⚠️ 2026-07-27: the rest of this sentence used to claim *"nothing in this project casts shadows"* — that is **false**. The player's flashlight is a `shadow_enabled` `SpotLight3D` in all nine level scenes and renders real cast shadows; only the static `OmniLight3D` room lamps don't cast, which `level_1.gd:173-175` deliberately relies on. See `GAME_MECHANICS_IDEAS.md` §2.0a.) Its **alpha** is what's driven; the flare only throws the walls into relief. And `lab_nook_figure.png` must stay a real RGBA cutout or it billboards as a solid rectangle (the `apparition_figure.jpg` bug). `_place_nook_figure()` fans raycasts — ahead, ±90°, then behind — and takes the first direction with ≥1.8 m clearance, because the breaker is on the west wall and a naive forward spawn lands *inside* it; in practice it lands behind the player, between them and the way out
  - Verified by `tests/walk_lab_wing.gd` — drives a `CharacterBody3D` the whole route under gravity and proves each dead end dead with raycasts against the built CSG, never against the `DOORS` array that produced it — and by `tests/screenshot_nook_scare.gd`, which polls for the figure's alpha and for Screamer's panel to photograph both moments (a frame counter can't catch a 0.2 s window)
  - The Lab's `DEBUG_APPARITION` fatal-apparition timer is suppressed for the whole wing (`_in_breaker_nook` flag checked in `_tick_debug_apparition`) — a player who can't see the apparition materialise has no fair way to judge "hold still or flee," the same double-jeopardy mistake KONTUR Gate 7 and the Backrooms Flood already made once each
- **Guarded keycard** in the dark morgue (a `DarkZone` + a `Beartrap`): the card sits on a cart *between* the surgical tray and the face-monitor (both `trigger_object.gd` — instant fail on E or 3 s gaze), with a cursed poster (`poster_lab.png`, gaze panic) on the wall. Taking it fires `on_keycard_taken()`: 1.6 s light-blackout stutter + creak + 8 panic. **BUG_FIX.md 4.2**: the monitor trigger moved off the cart onto the morgue's east wall (`wall_point("Morgue", Vector2(1,0), …)`, `y_rot=PI/2` so its -z-facing screen quad turns to face -x into the room) — the wall directly opposite the only doorway (west, x=6), so it's the first thing visible on entry instead of something found at an angle on the cart. The tray is unaffected
- **Observation room**: a one-way mirror (`living_mirror.gd`) — a figure appears in the glass only when you are NOT looking head-on. The north wall carries the Backrooms whiteboard and, since 2026-08-16, **a printed transcript of the PA line pinned beside it** (`PA_NOTE_TEXT`, offset `WHITEBOARD_NOTE_OFFSET` off the same `wall_point`). The tannoy fires once, 1.4 s after the power returns, on top of the "Power restored" objective — and it is not a `Note`, so it never reached the journal. `_announce_trial_four()` now calls `GameState.record_note()` with the identical text, so the spoken and printed halves collapse to one TAB entry (playtest capture #2: *"shall we put another note next to this image, and this image remains untouched?"* — the artwork is untouched; what the diagram lacked was a sentence)
- **Records — the filing cabinets are real furniture, and the bank is a search** (`lab_cabinet.gd` + `lab_cabinet_drawer.gd`, 2026-08-16, capture #4: *"These object look way too useless"*). Two units, the same 0.7 × 1.3 × 0.6 footprint as the flat boxes they replace so all the clearance arithmetic above still holds, now built from plinth / carcass / top overhang / four proud drawer faces / handles / card holders, **flat-tinted and untextured** (Issue 35's answer in `kontur_mailbox.gd` and `intro_room.gd:_build_wheelchair()`). ⚠️ **The bank is a SEARCH, and the page must be TAKEN (2026-08-16, second revision).** It used to be one openable drawer on one unit, opening straight into the note; the player asked for the obvious better thing — *"Maybe we can do it in a way I could open all the boxes and only one would contain the note? Also I need to take it to start reading, now it reads automatically"*. So the cabinet itself no longer interacts at all: it is a carcass, and each of its four drawers is its own `LabCabinetDrawer` with its own interact volume. **Eight drawers across the bank, exactly one holding the page.** Opening an empty one slides it out and shows you the wrong paperwork — **no panic, no penalty, no fail state, nothing gated behind it**; the price of looking in the wrong place is the looking. ⚠️ **And it says NOTHING** (2026-08-16, verification replay): an empty drawer used to print a line of flavour, and the user cut it — *"What for to write these messages? They are not needed, the player will see there is nothing in there"*. The drawer sliding out with folders and no page IS the message; do not re-add a caption over something already on screen. The page in the right one lies in the tray as an OBJECT, and a **second, separate E** takes and reads it (`kontur_mailbox.gd`'s open-then-read beat, one step further). Opening stays **ONE effortless press** — the stiffness is KONTUR's mailbox only, confirmed with the user. ⚠️ **E CLOSES AN OPEN DRAWER AGAIN — the drawers are a TOGGLE (2026-08-16, third revision).** A drawer stands 0.34 m into the room while open, so it both hides and *shadows* every slot beneath it, and the bank used to seal itself as you searched it top-down (*"I cannot see what is under the top storages. I need to be able to close them by pressing the E button"*). Measured by ray from a standing eye position: with one drawer open **6 of 8** drawers in the bank answer E; with them shut, **8 of 8**. Issue 67. Closing is one effortless press too, and uses the same `metal_creak` pitched down and eased IN. ⚠️ **Which of the two nested props answers the ray is decided by STATE, never by aim** (`_refresh_layer()`): shut → the drawer (E opens); open with the page inside → the page (E takes it, the drawer goes inert); open and empty → the drawer (E shuts it). A single ray cannot reliably choose between a drawer face and a page lying 0.10 m behind and below it in a 0.26 m slot. The one consequence: **the drawer holding the page cannot be shut until the page is out of it**, which costs a press the player wanted to make anyway. ⚠️ **Closing resets nothing** — a page already taken never comes back. (There was a `_searched` flag and a `drawers_searched` snapshot key here; both existed only to stop the flavour line repeating, so both went with it rather than staying as a field nobody reads.) ⚠️ **Which drawer holds it is randomised per run** and captured in `save_progress()` (`hint_cab` / `hint_slot` / `hint_taken` / `drawers_opened`), never re-rolled on a back-door return — KONTUR's `_dark_x` rule. ⚠️ A drawer's interact volume is **0.08 m deep, not 0.20**: a volume proud of the face intercepts the downward rays aimed at the drawers BELOW it, which made 6 of 8 unreachable (Issue 65). ⚠️ And the page's own grab volume is **`disabled` until its drawer opens and disabled again the moment it starts closing**, not merely refusing — `can_interact()` false makes a prop inert, not transparent, so a page protruding 1 cm past its shut drawer's volume made **the one drawer holding the hint un-openable** (Issue 66). The close path disables it FIRST, before the tween starts, or the toggle reintroduces that bug on the return trip. Measured by `tests/check_lab_cabinet.gd` (8 of 8 answer E at 1.1 m and 25° off-axis; exactly one page; zero panic; the placement moves between runs and survives a snapshot; **the whole toggle cycle — close, reopen, the page collider in both directions, and taken-state surviving a close — and that an empty drawer puts NO text on the screen, counted as root-parented `Label`s across the open**) and `tests/check_open_then_read.gd` (opening shows nothing; the second press finds the PAGE, not the drawer). ⚠️ **The note is the Backrooms FLOOD's missing cross-level hint**: *some things are only there when the light is off*, stated as a RULE and never as a place (`kitchen_drawer.gd`'s rule, for the same reason), with a second paragraph that also covers the Smiler. The Flood's darkness tell was the one puzzle tell in the game with no earlier-level hint at all. Archived via `GameState.record_note()` on being taken, and the page is removed from the drawer once it is in your hands. ⚠️ **Both units are identical in every respect** — same parts, same four drawers, same faces and card holders. Nothing about the bank may hint at which drawer is the one, which is why the empty drawers have folders in them too
- **Scares**: random blackouts (all lamps stutter dark ~1.5 s) and pipe groans (`pipe_groan.wav`) on timers; a taught **HOLD apparition** (`apparition.gd`, `teach=true`) armed by a `CorridorEvent` in the main corridor
- **Notes (2026-08-16 pass)**: every note now goes on a wall through `wall_point()`. ⚠️ The **TRIAL 7** page (NIGHTMARE hint 1/3) hung **in the morgue's doorway** for the life of the feature — `wall_point("Morgue", (-1,0))` returns the west wall's CENTRE and the morgue's only door is at exactly that centre, so there was no wall behind it (capture #7, *"the note is floating in the air"*); it moved to the morgue's **NORTH wall**, offset east of the cursed poster by `MORGUE_TRIAL7_OFFSET` (2.4 m), and was **trimmed 97 → 50 words** (capture #8) keeping both load-bearing facts verbatim in meaning — they hold while watched, and THE LIGHT ATTRACTS THEM. The **Reception briefing** note was hand-typed at (2.4, 1.4, −2.6) with the wall face at x = 2.90 — the first note in the game after the intro, floating 0.50 m out in the room — and is now `wall_point("Reception", (1,0), …)`. The **Records warning sign** was raised 1.8 → 2.05 m: at 1.8 it overlapped the night-log note beneath it by 11 cm with its layer-1 body 3 cm in front. ⚠️ **TRIAL 7 moved TWICE.** Its first destination was the south wall **1.6 m from the KONTUR circular**, which fixed the doorway and put both pages in one frame — *"These two notes at the morgue are at the same place. Let's at least put them into different parts of the room"*, with two `NOTE READ` events 1.7 s apart in the log (Issue 68). Separation is now **6.19 m and on opposite walls**; neither page leaves the morgue, because both are cross-level hints filed behind the beartrap and the instant-fail triggers on purpose. All of it is regression-locked by `tests/check_note_mounting.gd`, which fires a ray backwards along each prop's own normal and requires solid geometry within 0.35 m — ⚠️ a direction `check_wall_overlap.gd` structurally cannot see, since it only asserts MINIMUM clearances (cross-level item X1) — and which now also groups notes by room and refuses any same-room pair closer than `MIN_NOTE_SEPARATION` (2.5 m) **or** sharing a wall plane. ⚠️ That second guard is general and worth knowing about in every level: `wall_point(room, side) + a lateral offset` is the obvious way to place a second wall prop and it is exactly the move that produces this defect
- Win: restore power → take keycard from the morgue → exit door (`KEYCARD`). Fail: trigger object, apparition rush (if you sprint), or panic bar fills

**Level 2 — The House (abandoned domestic interior)** — rebuilt procedurally (Session 10)
- Built at runtime in `level_2.gd` via `RoomBuilder` from an 8-room ground floor (entry hall, hallway, living room, kitchen, landing, bedroom, bathroom, child's room) **plus a gently-lowered CELLAR** (`_build_cellar()`, floor at y=−1.5) reached by a walkable ramp. Same `.tscn`-minimal / `PRESERVE`-whitelist pattern as the Lab
- **Cellar key sub-quest**: a glowing `KeyItem` (`key_item.gd`) → `picked_up` → the player is now
  *carrying* the key (`GameState.set_carried`, shown on the HUD); the `CellarGate` (`cellar_gate.gd`)
  only opens when they walk down and press **E** on it. ⚠️ `picked_up` used to be wired straight to
  `_open_cellar_gate()`, so winning the Bathroom minigame flung the cellar open from the other end of
  the house and the key was a formality (BACKLOG #16). ⚠️ The ramp/shaft/ceiling use `rotation.x = -angle` (a +angle inverts the slope and drops the ceiling to knee height); the key sits clear of its (collision-less) stand so the interaction ray reaches it. **Session 11 fix (two parts):** (1) the ramp's TOP SURFACE is now continuous with the floors at both ends — it starts at z=1.7 where `RoomBuilder`'s doorway floor-bridge ends (both at y=0) and the bottom is extended 0.6 m under the cellar floor — so there's no end-lip to climb (`move_and_slide` can't step up; a tilted box poking ~0.14 m above the floor was the real "can't enter the cellar" block, *not* headroom). (2) The sloped ceiling is offset a constant 2.6 m along the ramp normal (~2.45 m vertical clearance) and a flat `CellarShaftCap` at y=3 seals the top; the ramp wears `house_wood_stairs.png`. Verified walkable BOTH ways by `tests/walk_cellar.gd`. **BUG_FIX.md 4.3** first moved the key into a 2-drawer search in the Landing; a later session **replaced that entirely** with a bigger quest, so Landing is empty again (a deliberate trade). **Current feature**: a folded paper map (`HouseMap`, `house_map_prop.gd`) on a stand in the **Bathroom** (`_spawn_bathroom_map()` — it moved Landing → Kitchen counter → Bathroom; the objective string has now been wrong THREE times, so re-check it whenever the quest moves — the four lines live together as `OBJ_*` consts at the top of `level_2.gd` now, because the fresh-level path and `_restore_progress()` had drifted apart twice. ⚠️ It is `The cellar is locked. Find the key.`: it used to read *"Find the folded map — it hides the cellar key"*, and the objective HUD was the ONLY thing anywhere in the level that named either the map or the key, so the one puzzle was solved on screen before the player entered a room (playtest 2026-08-16). ⚠️ **Replaced, not deleted** — the map is the only route to the key and nothing else in the game names it, so an empty objective would strand a player who never walks into the Bathroom) opens a full-screen, paused 2D maze-chase minigame (`MazeChaseUI`, `maze_chase_ui.gd`) — a fresh **16×9** **braided** randomized-DFS maze for every genuine **attempt**, i.e. on a win or a catch.
  - ⚠️⚠️ **THE OBJECTIVE IS TWO-STAGE SINCE 2026-08-16 (a user-requested redesign, approved after a brainstorm): COLLECT the torn fragment(s) of the map, THEN escape to the mark.** Shipped at **`fragment_count = 1`** — see the frontier below, and `backlogs/02-house.md` §9 P6 for all of it. The mark is genuinely **inert** — and visibly sealed, `TargetSeal` — until the last fragment is in hand; `_is_won()` is the single win predicate and it checks both halves. Fragments carry **no panic and no fail state**; a catch ends the attempt exactly as before (`CATCH_PANIC` 18, ejected to 3D, retryable, brand-new maze) and **fragments already collected are lost with it — there is deliberately no partial-progress carry-over**, and they also **re-arm on a close-and-reopen** exactly as the snares do, so ESC cannot become a checkpoint.
    - **Why, and it is not "a longer maze is a harder maze".** The user asked for a maze "more packed with actions"; the measurement (`backlogs/02-house.md` §7 P4, 200 seeds) said **the median winning run was 9.8 s**, p90 14.4 s. There is no room in ten seconds for a hunter, a patroller and five snares to *matter* — most runs ended before the patroller was ever met. The fragments buy **time on the board**, which is what turns the roster that already exists into decisions.
    - **Measured outcome: 232/400 = 58 % win rate, median run 21.7 s** (p10/p90 18.2/27.4 s; `check_maze_chase.gd` reports 28/40 and prints the duration every run). For scale: the build before this pass was 59 % at 9.8 s, and the one-stage control on this board is 80 % at 16.9 s.
    - ⚠️⚠️ **THE ONE FINDING TO KEEP IF EVERYTHING ELSE HERE IS REWRITTEN: length bought from the ROUTE is free, length bought from WAYPOINTS is not.** Measured, 200–400 seeds per point — 10×8: N=0 82 % at 10.9 s · N=1 57 % at 14.1 s · N=2 21 % at 17.0 s · N=3 14 % at 17.5 s, the hunter's kill rate going **3.5 % → 70 %** for a run only 60 % longer. Against that, simply making the board bigger left the one-stage control at **80 % and 16.9 s**. **The head start is a one-off budget and every waypoint spends it**: `MONSTER_START_DELAY` buys ~600 px of lead once, after which the player nets 240 − 172 = 68 px/s *and only while running directly away*; a heading change hands it back to a pursuer that never tires or resets. A longer route is still monotone flight; a waypoint is not. This is why the shipped design takes its duration from **`GRID_COLS`/`GRID_ROWS` and its structure from ONE fragment.**
    - ⚠️ **The original 30–45 s target is NOT met and was retired by the user (2026-08-16), who accepted that the target was probably wrong.** 16×9 with N=2 reaches 28 s but at 20 %. Going further needs `MONSTER_SPEED`/`MONSTER_START_DELAY` or a counter-play that gives the lead back — both the user's call, neither taken.
    - **`fragment_count`** is the shipped N; **`TOUR_BAND`** is the validate-and-reject band the whole tour (start → every fragment → mark) is generated into, ≤ `FRAGMENT_PLACE_ATTEMPTS` tries and then the best candidate — never a `while`, because this runs inside a **paused** overlay where a hang is indistinguishable from a crash (Cogmind's map-validation loop; Spelunky guarantees its solution path after generation rather than hoping for one). ⚠️ **The band is the second lottery fix and a bigger one than the patroller's**: unbanded on the shipped 16×9 board the win rate ran **91 % at a 41-cell tour down to 27 % at 72+**. Banding to **50…64** cuts the tour's p10–p90 spread from 42–77 to 48–69 while moving the mean barely at all (56.3 % unbanded → 58.0 % banded) — **it is a variance instrument, not a difficulty one, and that is the point.** ⚠️ **The window is about four points wide in both directions** — 54…70 measured 51.8 % and 52…66 measured 54.0 % (both under `check_maze_chase.gd`'s asserted 0.55 floor), while 46…60 measured 63 % (over the user's 59 % ceiling). ⚠️ **The band is board-specific**: it read `34…45` on the old 10×8 grid and must be **re-measured, never rescaled**, if the grid moves again.
    - ⚠️⚠️ **THE TOUR IS MONOTONE OUTWARD, and that is the difference between the feature working and not.** Fragment k is drawn from a band around `k/(N+1)` of the way along the route, so every waypoint is further from the spawn than the last. The first build placed them anywhere off the line and ordered them nearest-neighbour: **10/200 escapes, median catch at 5.6 s** — nearest-neighbour makes the first waypoint the one *closest to the hunter*, so the head start is spent walking out and back. **Detours yes, backtracking no.** ⚠️ And a fragment may never sit in a **dead end** (`_braid()` opens only 55 % of them): worth a measured 4 points, and asserted by `check_maze_gen.gd`.
    - ⚠️ **`_route_cells` means the whole TOUR now, not the direct line.** While it still meant the direct line, **39 % of all deaths were the patroller** — fragments are chosen for being off the direct line and the patroller was banded for being off the direct line, so the two were pushed into the same space by construction. Pointing `_compute_route()` at the tour put it back to 20 %.
    - ⚠️ **"Off the route" is measured as DETOUR COST**, `d(start,c) + d(c,mark) − d(start,mark)`, not as raw distance from the route cells. The obvious alternative is unusable here and the reason is worth keeping: the direct route already has a **median length of 28 cells in an 80-cell grid**, so "3+ cells clear of the route" is routinely an EMPTY set — a constraint that is usually unsatisfiable degrades silently to "place them anywhere", which is the shape of Issue 34's stub.
    - ⚠️ **`_place_monster()` now guards the first step toward `_tour[0]`, not toward the mark** — the player's opening move is toward the nearest fragment, and the mark is inert for the first half-minute. Same rule, corrected destination; `check_maze_gen.gd` moved with it.
  - ⚠️ **The patroller no longer starts on your artery (2026-08-16)** — the single largest source of the reported randomness, and a one-line omission: `_place_patroller()` required only `PATROL_MIN_START` cells from the player's *start cell* and never consulted `_route_cells`, which `_generate_maze()` has already computed by the time it runs (`_pick_patrol_target()` has avoided route cells since the day it shipped; only the START did not). Measured over 200 seeds: **40 % of instances began it ON the route, and those seeds won 28 % against 83–100 % once it was 3+ steps off** — a 3× swing in survival decided by a placement nobody chose. It is now banded to `PATROL_MIN_ROUTE_GAP` by bounded sampling with an accept-the-best fallback, then a deterministic sweep (there may genuinely be no such cell); `check_maze_gen.gd` asserts the band against an independent BFS, failing only when a *better* candidate existed and was not taken — **200/200 seeds on the shipped board**. ⚠️ **The constant is 5 here and was 3 on the 10×8 board: the cliff moves with the grid.** Measured at 400 seeds, gap ≥ 3 with band 46…62 gives 58 % at 20.7 s with a **33-point** spread across patroller-distance buckets; gap ≥ 5 with band 50…64 gives **the same 58 %, one second longer, with a 12-point spread**. Raising the bar alone overshoots to 63 %, so the headroom it frees is spent on a longer tour band — **the two constants were chosen together and must be re-measured together.** ⚠️ `PATROL_SPEED` / `PATROL_AGGRO` / `PATROL_CALM` / `PATROL_MIN_START` were **not** touched.
  - ⚠️⚠️ **THE BOARD IS 16×9 SINCE 2026-08-16 (was 10×8), and this is where the run's LENGTH comes from.** The user's call, taken on the frontier above: a longer route is still monotone flight from the spawn, so it buys duration at no cost in win rate (one-stage control: 82 % at 10.9 s on 10×8, **80 % at 16.9 s on 16×9**), whereas buying the same duration from waypoints cost 82 % → 14 %. ⚠️ **The size is bounded by the SCREEN, not by taste**: at `CELL_SIZE` 96 the playfield is 1536×864, and `_root` is anchored at the viewport centre, so the overlay needs 478 px above it for the caption and 508 px below for the counter and pips against 540 either way at 1080p — **nine rows is the last row that fits.** Verified in the real overlay by `screenshot_maze_ui.gd`, never on paper; this file has already put a caption across the middle of the parchment once by trusting arithmetic. ⚠️ **`TOUR_BAND` and `PATROL_MIN_ROUTE_GAP` are board-specific and were re-measured, not rescaled** (34…45 → 50…64 and 3 → 5); `FRAGMENT_MIN_DETOUR` was re-swept and stays 6. ⚠️ **`SNARE_COUNT` 5 is a much thinner scatter in 144 cells than in 80, so it was isolated rather than assumed: 232/400 with five snares, 232/400 with none — identical to the seed.** Reported, not retuned. (Caveat: the harness bot walks the route and `_place_snares()` excludes route cells, so that number bounds the snares' effect on route-walking, not on greedy corner-cutting.)
  - ⚠️ **The 2026-08-16 redesign moved ZERO difficulty constants.** `MONSTER_SPEED` 172, the patroller's three, all four `SNARE_*`, `CATCH_PANIC`, `MAZE_DRIP_RATE`, `PROXIMITY_*`, the spring/speed panic degradation and the 55 % braid floor are all untouched — the list is repeated at `MONSTER_SPEED` in the script. The difficulty came from **structure**.
  - **CURRENT MEASURED DIFFICULTY — quote these and nothing else:** `check_maze_chase.gd` **28/40**; the wider probe **232/400 = 58 %**; median run **21.7 s**; asserted floor **0.55 (22/40)**. ⚠️ **The old 37/40 and 26/40 figures are DEAD.** They predate both the two-stage objective and the patroller band, and the harness that produced them could not see either. Read the isolation table in `backlogs/02-house.md` §9 P6 before quoting any of it — the patroller band is a difficulty *reduction* of 23 points and the fragment spends all of it, so the net is 59 % → 57 % with a 45 % longer run and two lotteries closed.
  - ⚠️ **The panic drip is charged per second, so a longer run costs LIFE as well as time** — checked rather than assumed. Over 400 winning runs on the shipped board: median **7.9** of `PANIC_MAX` 50, p90 10.6, worst 15.8, against the one-stage control's 3.5 / 5.7 / 9.8. Per second that is 0.36 vs 0.32 — **proportional to time, not compounding**, across a board that doubled in area. A *caught* run is still the more expensive outcome (≈3.9 of drip plus `CATCH_PANIC` 18), so the longer board did not change which failure hurts most. `MAZE_DRIP_RATE` did not need to move and did not.
  - ⚠️ **Closing the map no longer re-rolls it** (2026-08-16, the user's call). `ui_cancel` closes for free and `HouseMap.interact()` reopens; `open()` used to regenerate unconditionally, so ESC was a free re-roll and the optimal play was shopping for an easy layout — measured, 134 s with ONE catch versus 13 s for the same puzzle. A maze now lives until it is won or you are caught (`_instance_live`); reopening resumes it from the start cell with every snare re-armed. **Strictly harder, chosen knowing that.** Nothing is memorizable across attempts, only within one.
  - ⚠️ **BRAIDED since 2026-08-15** — `_braid()` opens 55 % of dead ends into loops, because the user asked to "make more space so that you can actually bypass the monster" and in a PERFECT maze that is topologically impossible, not merely hard. `dungeon_gen.gd` already carried the same lesson.
  - **The roster:** a **patroller** (a second monster walking a circuit *off* the player's likely route, giving chase only within `PATROL_AGGRO`, slower than the hunter — measured, one wandering to random cells cost 9 seeds in 40 by standing in a corridor, which is a roadblock rather than a threat); **snares** (`SNARE_COUNT` 5, off-route, pinning the icon 1.2 s for 3 panic — never a second fail state; ⚠️ drawn at their TRUE `SNARE_RADIUS` in ice blue with a frost glyph since 2026-08-16, the disc having been `SNARE_RADIUS * 1.6` in diameter — radius 20.8 against a 26 px trigger, understating the hazard by 36 % of its area, in near-black brown on sepia parchment. Issue 74; the numbers themselves untouched); and a looping **chase track** (`chase.wav`, trimmed and crossfaded by `tools/make_loop.py`, on an `AudioStreamPlayer` child of the CanvasLayer so it survives the tree pause; Master bus, matching `combination_lock.gd`; stopped in `_close()` **and** `_hide_after_external_unpause()`).
  - ⚠️ **`MONSTER_SPEED` 172, raised 88 → 132 → 172** across two playtests on the user's call. The escape rate never moved at any of the three speeds; what changed is how fast a mistake is punished — hunted down 9.4 s after stopping at 132, **5.2 s at 172**. ⚠️ **Do not raise it again without re-running `check_maze_chase.gd`.**
  - ⚠️ **The hunter follows CORRIDORS, not a beeline.** It steers by a BFS distance field from the player's cell, recomputed when they change cell. It used to use a raw Euclidean beeline, which in a randomized-DFS *perfect* maze points into a wall most of the time — the corridor route is routinely 5–15× the straight line — so it jammed and could never close once the player left the start (BACKLOG #14: *"it can basically kill the player only at the beginning"*).
  - ⚠️ **`_place_monster()` avoids the FIRST STEP of the only route to its target.** In a spanning tree that cell is a roadblock the player cannot walk around — harmless while the monster drifted into walls, a measured 12-in-40 instant death once it followed corridors. Since the two-stage objective it guards the first step toward `_tour[0]` (a fragment), not toward the mark, which is inert for the first half-minute.
  - **Drag physics:** the icon eases toward the cursor on an exponential spring rather than snapping, and both the ease rate and the speed cap degrade as panic rises (`SPRING_K_BASE=9.0→SPRING_K_PANIC=3.0`, `PLAYER_MAX_SPEED=240→PLAYER_MIN_SPEED=100`). Releasing the mouse freezes the icon instantly, no glide, so letting go never costs an unwanted catch.
  - **Panic climbs the whole time it is open:** a flat `MAZE_DRIP_RATE=0.9`/s plus a squared proximity term up to `PROXIMITY_MAX_RATE=5.0`/s, via the same "a paused UI's own `_process` still calls `player.add_panic()`" idiom `note_ui.gd` uses for trap notes — which means the UI **must** self-clear if a screamer fires and unpauses the tree out from under it (Issue 9 guard, copied verbatim from `combination_lock.gd`/`note_ui.gd`). Winning calls the unchanged `_build_cellar_key()` at the counter's other end for a real 3D pickup; getting caught (`CATCH_RADIUS=20px`) ejects back to 3D with a jolt + `CATCH_PANIC=18` (bracketed between `beartrap.gd`'s own 15/40 spring-vs-fail values) and the map is retryable. `house_drawer.gd` (the superseded Landing search) was deleted as dead code.
  - ⚠️ **Legibility (playtest 2026-07-25, capture #3)**: the caption was added as a second child of the `CenterContainer`, which overwrites every child's anchors/offsets — so it landed stacked dead-centre ON the parchment in a cream that matched it. It now hangs off `_root` with a black outline (`ScreenText._outline()` convention). The three icons are 1024×1024 PNGs whose ink fills only ~30–40 % of the canvas, in the same sepia as both the parchment and the wall rects, so each rendered as ~28 px of near-invisible scribble; `modulate` cannot fix that (it multiplies — no multiplier turns brown into saturated blue), so `_make_icon()` stacks a dark halo disc + a bright identity disc sized to `ICON_HALF_EXTENT` + the ink on top. See ISSUES_SOLUTIONS Issue 32.
  - **Test coverage:** `tests/screenshot_maze_ui.gd` drives the real `interact()` path — `screenshot_scene.gd` structurally cannot reach a UI behind a prop. Maze generation is stress-tested independently of any scene by `tests/check_maze_gen.gd` (200 seeds: connectivity, non-trivial target distance, valid monster and patroller placement), because the minigame is only ever opened by player interaction and a normal scene smoke test never exercises `_generate_maze()` at all.
- **THE GUEST (2026-07-28/29) — the house rearranges itself, one step per quest milestone.** The
  House is the only level with genuine backtracking pressure (Bathroom map → key → Kitchen → cellar
  → ChildRoom lock crosses the ground floor repeatedly), and this is what that traffic is for:
  | milestone | what changes |
  |---|---|
  | map solved | **arms** the child's-room painting; it comes off the wall **beside the exit lock** when you are within 4.5 m, facing it, **and can actually see it**, with `painting_fall` at +8 dB and a camera jolt |
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
  - ⚠️ **The falling painting moved BEDROOM → CHILD'S ROOM (2026-08-16, the user's proposal).** Stage 1
    fires when the map is solved, and after that the Bedroom is off every remaining route — map → key
    → Kitchen → cellar → the exit lock never re-enters it — so the level's most expensive scripted
    beat was staged in a room the player had already finished with. The ChildRoom holds the exit lock
    and cannot be skipped. `painting_house.png` and the child's crayon drawing simply **swapped
    walls**; the drawing took the Bedroom's south wall. ⚠️ `_drop_painting()`'s landing offset now
    runs along the panel's **own forward** (`basis.z`) instead of the hard-coded `p.z + 0.55`, which
    was correct only for a panel facing +z and would have slid this one a metre sideways into the
    plaster
  - ⚠️ **…and then, one replay later, EAST WALL → NORTH WALL, BESIDE THE EXIT DOOR** (2026-08-16:
    *"let it be next to the door so once you approach the lock it falls"*). The right ROOM was not
    enough — on the east wall the beat merely happened somewhere in the same room. It now hangs at
    `PAINTING_X = 0.85` on the north wall; the exit door occupies x −1.33…−0.08, so there is ~0.5 m
    of wall between them and the panel is in the frame you are looking at while you work the lock.
    ⚠️ Not on a doorway — ChildRoom's only `RoomBuilder` doorway is SOUTH at (0, 14); the exit door
    in the north wall is a prop. The 0.55 m landing slide puts it at (0.85, 0.06, 18.29), clear of
    the small bed and clear of the walking line to the lock at x = −0.7
  - ⚠️ **The drop needs LINE OF SIGHT, not just range and a facing dot** (Issue 77). Distance +
    facing alone is a test for *pointing at*, and in a house it is satisfied through walls: the
    2026-08-16 log has the painting falling **1.5 s after the key was taken and ~130 s before the
    player entered the room**, through the Landing's south wall, to nobody. `_painting_in_sight()`
    is one ray from the eye, excluding the panel's own body and the player
  - ⚠️ **The fallen panel goes to `collision_layer = 2`** (`note.gd`'s raycast-hittable /
    movement-invisible convention). Pitched flat it is a 0.8 × 1.0 footprint standing 11 cm proud of
    the boards and `move_and_slide` cannot step up; measured, it split the north end of the room —
    the end the lock is on — from one free lane into two. Gaze panic is unaffected, because the gaze
    ray uses the default all-layers mask
  - ⚠️ The music-box wind is two streams that must both come back: the recording plays at `LOUD_DB`
    while the room-tone bed **ducks to `BED_DUCK_DB` rather than stopping**, and both return after
    `PLAY_TIME`. A duck with no restore is Issue 50's shape; `tests/check_music_box.gd` waits past
    the wind-down in real time and asserts the bed is back
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
  - ⚠️ **IT IS POSTPONED, NEVER FIRED BLIND (2026-08-16).** `_cellar_child_appear()` re-arms itself on
    a 0.25 s timer while `NoteUI.is_open`, `get_tree().paused` **or** `player.is_input_frozen()` — the
    same three conditions `apparition_director.gd` refuses on, and the level's own set-piece checked
    none of them. It measurably needed to: the 2026-08-16 log has the child spawning at t=206.98
    *inside* a beartrap QTE that started at 205.48, with a countdown UI over the screen. And
    `SceneTreeTimer` defaults to `process_always = true`, so the old bare `create_timer()` fired
    straight through a tree pause as well. ⚠️ `CHILD_POSTPONE_MAX` (45 s) is the safety valve: the
    blackout's END is armed by the appearance, so a beat that postponed for ever would strand the
    player with no lamps and no torch. Past it, the figure is given up and the lights come back
  - ⚠️ **`require_los = true` on every `Watcher.spawn` here.** It was `false`, which `watcher.gd`
    restricts to `congregation.gd`, and the LOS ray is the ONLY probe that catches "inside a wall"
    (Issues 40/59) — so the `[3.2, 2.4, 1.8]` ladder below it was dead code. Measured with the flag
    off, a player facing the cellar's south wall from 0.7 m got the figure at z = −11.9, **2.5 m
    beyond the wall.** With it on, the ladder is refused and the room-centre fallback runs
  - ⚠️ **DELIBERATE (2026-08-16): the cellar beartrap STAYS on the forced-blind entry line.** It sits
    1.6 m past the blackout trigger on the only heading in, inside an 8.5 s window with no lamp and
    no torch, and it fired in both playtest sessions. The user was shown that measurement and chose
    to leave it. That is what makes the postponement guard above load-bearing rather than tidy —
    the collision will keep happening
- **The Kitchen** (42 m², previously ONE prop): sink, table and chairs built from real parts, plus
  a **fridge** (`house_fridge.gd`) — it hums, and on E the scream fires FIRST, the door swings 0.28 s
  later, and a head is revealed on the shelf as it clears. **10 panic, the only new panic term in the
  whole atmosphere pass**; voluntary, optional, off the quest path, one-shot, and inert afterwards
  - ⚠️ The carcass is an **open-fronted shell of five slabs**, not a solid box — see Issue 46
  - ⚠️ **The door is hinged on the +X edge and swings +105° OUT (fixed 2026-08-16, Issue 69).** The
    hinge used to sit on −X, and rotating that free edge by +105° carried it toward local −Z, i.e.
    *backwards through the shell* — the playtest capture of an "open" fridge contains no door and no
    handle at all, because both were inside the box. The hinge moved rather than the angle flipping,
    on the user's call: it is also the edge furthest along the approach from the Hallway doorway, so
    the panel uncovers the cavity toward the player instead of sweeping across the kitchen table
  - ⚠️ `REVEAL_DELAY = 0.62` was **NOT** retimed. The second half of that same report ("the head
    appears not immediately") is a symptom of the door: the head is meant to be revealed *as the door
    clears it*, and with nothing clearing, 0.62 s reads as a pause in front of an open box
  - ⚠️ The lower wire shelf is `SIZE.y * 0.34`, not 0.40 — at 0.40 it drew straight across the bottom
    7 cm of the face, which is the same capture. The head now RESTS on that shelf, clear of both
- **The kitchen drawer** (`kitchen_drawer.gd`) carries a second, independent hint for **KONTUR Gate 1**
  ("the black door is the way out, the red one is not a door" — the rule, never a position, since the
  colours swap per run). Gate 1's only other hint is in the Lab morgue behind a beartrap and two
  instant-fail objects, and getting it wrong BANISHES rather than costs a strike
  - ⚠️ **It opens BEFORE the note, and it opens OUTWARD (both fixed 2026-08-16, Issue 73).** It was
    Issue 58 verbatim — the slide Tween started and `NoteUI.show_note()` was called two statements
    later, and `show_note()` pauses the tree, so the drawer only moved once the page was dismissed.
    The note is now fired from the tween's `finished`. And `SLIDE` is **−0.34**: it was +0.34, which
    drove the panel 34 cm into the counter it is set into, so the corrected ordering would still have
    revealed nothing. `tests/check_open_then_read.gd` measures the slide at the moment the note
    appears **and** asserts the opened drawer is inside no CSG box
  - ⚠️ **ONLY THE VISUALS SLIDE — the collider never leaves the counter face (2026-08-16, Issue 76).**
    The tween moved `self`, a `StaticBody3D` whose child is the `CollisionShape3D`, so an open drawer
    put a 0.62 × 0.26 × 0.14 solid 34 cm out into the room. Measured with the player's own capsule:
    the free lane across the Kitchen at z = 7.40 went from **ONE 5.10 m span to two of 1.30 m and
    2.50 m**, and that lane was the only way past the counter — the playtester was carrying the cellar
    key. Everything visible now hangs off a `DrawerSlide` child; the body is fixed. **An interactable
    in this game may never move a collider into a walkway.** Guarded by `tests/autoplay_house_route.gd`
  - ⚠️ **And it is a DRAWER, not a panel.** It was a single 2 cm board with nothing behind it, so a
    34 cm slide out of a featureless counter rendered as a pale plank hanging in mid-air, which is what
    the user photographed and read as fallen debris. Two sides, a bottom and a back run back into the
    counter (invisible while shut); the handle moved to the **−z** face, having been on the one buried
    in the worktop
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
- Panic pressure: `CorridorEvent` triggers add panic directly (entry door slam +10, clock chime +10, **the running creature crossing 8 m ahead** +20, floor crack +10); `DarkZone`s add +3/s while flashlight is off; `Torch3D` calm zones decay panic ×2.5; cursed gaze panels (paintings 0.8/1.2, clock 1.0, side-wall `mirror.png` 2.0/2.5); 5 beartraps = snap + 15 panic + **escape mechanic** (see Beartrap below)
- ⭐ **THE RUNNING CREATURE** (`_ev_silhouette`) — a figure sprinting across the hall ahead of you, **rebuilt 2026-08-17** after the playtest (*"it is too far away from me. Can we make it run when I'm much closer so that I can actually see it ... can we make the sounds of this jumpscare much louder?"*). It triggered at d=205 and crossed at d=228.5, i.e. **23.5 m** down a hall whose last torch is at 214, and measured **4.9 % of the screen's height**. Now: trigger `SILHOUETTE_TRIGGER` **219**, crossing `SILHOUETTE_CROSS` **227** — **8 m**, measured **13.2 %** (2.7x linear, 7.3x area, unprojected through the real camera by `check_corridor_events.gd` against a control that rebuilds the old placement). It is **8 parts in a stride** rather than one capsule (bringing a pill closer only makes a bigger pill — Issue 35), it enters and leaves **behind the walls** at ±2.0 m rather than blinking into existence in mid-air at ±1.2, and the scream is a **child of the figure** so it travels with it: `jumpscare` at −3 dB and 8 m instead of −14 dB at 23.5 m, **+19.4 dB**, with `max_db` pinned to 0 because that file already peaks at 0.0 dBFS and a sprinting player can be 4 m away. ⚠️ **`SILHOUETTE_PANIC` 20 is UNCHANGED and asserted** — closer and louder both raise impact on their own and the number was deliberately not compounded. ⚠️ A Node3D's forward is **−Z**, so the yaw is `atan2(side.x, side.z)`; the natural-looking negation is π out and renders a figure sprinting backwards (Issue 102)
- **Turn mirrors** (`_spawn_turn_mirror` in `corridor.gd`): a real, reflecting mirror (`MirrorSurface`) set flush on the wall you face at a corner — miss the turn and you walk into the thing in the glass head-on. Gaze panel (intensity 1.5 / 2.2) **plus** a one-shot close-up `flash_scare(mirror_with_creature.png, "glass_shatter")` + jolt + 12 panic when you come within 2 m (`_turn_mirrors` proximity-tested in `_process`)
  - ⚠️ **TWO OF THEM, at 90 m and 275 m** (`TURN_MIRRORS`, 2026-08-16 — the user's call: *"the mirror appears too often - can we make it two time, once at the exact place it shows up for the first time, and the second time is when it appears last"*). The middle one at **230 m is gone**, frame, figure and gaze panel with it; that corner is now an ordinary corner. **The level's flash panic is unchanged at 24 per run** — `_pick_silent_mirror()` used to mute exactly one of three, so it was always 2 x 12, and it is still 2 x 12. What is removed is one gaze panel worth 40 panic/s if stared at, which neither logged traversal ever stopped for
  - ⚠️ **`_pick_silent_mirror()` is now gated on `SILENT_MIRROR_MIN = 3` and is a no-op at two.** It is an anti-habituation roll: muting one of three is a third of the corners, muting one of two is half, and could leave a run with a single mirror beat. It is kept rather than deleted so restoring a third mirror restores the roll. `check_corridor_doors.gd` asserts the RULE, not the count
  - ⭐ **`mirror_wake` — the glass coming alive is AUDIBLE** (2026-08-16, the user: *"The mirror appears out of nowhere. I think it is good, generate a noisy sound for it so that it would scary the player"*). Fired by `_tick_mirror_wake()` at **`MirrorSurface.ACTIVE_DIST`, which is 7 m since 2026-08-17** — the same constant that switches the `SubViewport` from `UPDATE_DISABLED` to `UPDATE_ALWAYS`, i.e. the moment a dark rectangle on the wall ahead becomes a live corridor. Deliberately **not** a second layer on the existing 2 m `glass_shatter` sting; they are 5 m apart, and `check_mirror_wake.gd` asserts that GAP rather than a ratio. One-shot per mirror, positional, gated on facing (`MIRROR_WAKE_FACING` 0.35, and a failed facing check does **not** consume the one-shot), and **zero panic** — a channel, not a term.
    - ⚠️ **14 → 7 m and +6.0 → −1.5 dB, and the two are one decision** (2026-08-17, the user: *"let it appear when I'm much closer and much louder"*, captured 8.7 m from the 275 m glass, i.e. with the pane already awake). Moving ONLY the sound was rejected — the cue exists to describe the render pop, and firing it where nothing changes is a noise with no referent; a second closer cue was rejected as three beats in one corner. Moving the gate also *is* the ask: the pane stands **9.1 % of the screen's height at 14 m and 18.2 % at 7 m**. It is a saving, not a cost — measured by walking the path at 0.25 m (`tests/probe_mirror_cost.gd`), a mirror renders over **53.00 m of the 320 m walk at 14 m and 25.00 m at 7 m**, and two are never active at once.
    - ⚠️ **The gain had to come out of the FILE.** At +6.0 dB and 14 m with `unit_size` 8 the cue's −1.01 dBFS peak was landing at **+0.13 dBFS at the listener** — already clipping, with no headroom left to turn up. `tools/make_sfx_mirror.py` (stdlib, seeded, byte-reproducible) gained a compressor and a `tanh` drive: loudest-300 ms **−14.03 → −5.69 dBFS** at an unchanged peak. Delivered at the trigger: **−12.89 → −6.03 dBFS, +6.9 dB, and no longer clipping**. `MIRROR_WAKE_MAX_DB` 1.5 pins the ceiling for a player still walking during the 1.45 s one-shot. Compression alone was swept over six settings and bought 2 dB — see ISSUES_SOLUTIONS **Issue 101** for why that is physics rather than a tuning miss. Asserted by `check_mirror_wake.gd`
  - ⭐ **`mirror_stare` — THE GLASS ANSWERS A STARE** (2026-08-17). The 2026-08-17 playtest DIED at the 275 m mirror: 36 % → 73 % → 97 % in ~15 s of standing still, which is that mirror's own `ScaryObject` at `scare_intensity` 2.2 = **44 panic/s**. The user's ruling was verbatim *"Leave it - staring should be dangerous - but I guess adding heartbeat is a good idea."* ⚠️ **So the cost is UNCHANGED — `TURN_MIRRORS`'s 1.5 and 2.2 are byte-identical and this adds ZERO panic.** The heartbeat was measured first and is not broken (`heartbeat.ogg` is −18.4 dBFS mean, lerped −20 → 0 dB with panic on the never-ducked `BODY` bus, so ≈ −24 dBFS at the 72 % this player passed through); what it cannot do is ATTRIBUTE, because panic here also comes from a dread zone, a dark zone, sprinting and five scripted events. This can: a seamless 3.0 s loop on a per-mirror emitter **at the glass**, rising only while the player is inside `MIRROR_STARE_RANGE` **3.0 m — a deliberate copy of `player.gd:GAZE_RANGE`, the exact volume the panel charges in** — and inside a 26° cone, since the panel charges off a single centre-screen raycast. Volume −26 → −3 dB and pitch 0.72 → 1.35 over 2.4 s; the loop carries a 2 Hz amplitude pulse so the pitch ride is also a RATE, **1.44 → 2.70 Hz**, and an accelerating pulse is what reads as a countdown rather than as atmosphere. It stops the moment you look away and is **not** a one-shot — the 90 m mirror teaches it, the 275 m one kills
  - ⭐ **THE FIGURE STANDS OFF THE MIRROR'S AXIS** (`MIRROR_FIGURE_SIDE` 0.0 → **0.45 m**, 2026-08-16). This is the whole answer to *"can we make it move again?"*, and it is geometric. The player walks the **centreline**, the mirror hangs on that axis, and the figure stood exactly on it — and a point on a mirror's own normal is a **fixed point of the projection under axial motion**. Measured in-engine, unprojected through the real reflection camera over a 12 m → 1 m approach: **0.0 px of lateral travel at offset 0.00 m** (zero, exactly, at every distance) against **89.8 px, 16.3 % of the pane, at 0.45 m** — which matches the analytic prediction of 89.7 px to 0.1 px. ⚠️ It is a **ladder** (`MIRROR_FIGURE_SIDE_LADDER`), not a constant: `Watcher.spawn()` returns null when a spot is refused and the old loop swallowed that with a bare `continue`, so `_spawn_mirror_figures()` takes the largest offset that fits at each mirror, records it in `_mirror_figure_offsets`, warns loudly if none does, and **0.0 is deliberately not on the ladder** (`MIRROR_FIGURE_SIDE_MIN` 0.25 is the floor). Both mirrors take the full 0.45 m. ⚠️ The old comment blaming the walls for this was **wrong**: `Watcher.FIT_RADIUS` is a flat 0.9 m and is not scaled by the billboard, and the wall face is at W/2 = 1.5 m, so the walls permit 0.6 m — what refused the earlier 0.55 m try was a **wall prop's collider** at d=268 spanning 1.43–1.53 m. Asserted by `check_mirror_figure.gd`, which measures the travel in pixels and carries an on-axis control that must NOT move
  - ⚠️ **THE REFLECTION DOES NOT MOVE WHEN YOU TURN YOUR HEAD, AND THAT IS CORRECT.** Reported on the 2026-08-16 replay as *"It used to be ... the reflection in the mirror moves, now it is static."* It is not frozen: the viewport is at `UPDATE_ALWAYS` inside `ACTIVE_DIST` and `_aim()` runs every frame (`check_mirror_frustum.gd:_liveness()` drives the real player across the gate, requires a fixed world point's projection to MOVE when the eye moves and NOT when it does not, and both halves were watched going red with the fix disabled). What changed is that the OLD camera inherited the player's **heading**, so the image panned with the mouse — measured, **0.022 U per degree of yaw**, leaving the pane entirely past ~26°. A mirror is a fixed window and cannot do that; `player.gd:_rotate_camera()` yaws the player about the axis the camera sits on, so the eye does not move at all. Everything done with the FEET moves the image **more** than before: the figure's height goes 0.599 → 0.119 of the glass between 12 m and 1 m (was 0.063 → 0.151), and strafing 0.5 m is **5.1×** the parallax. Pixel-measured at the glass (`probe_mirror_motion.gd`): standing still gives a frame-to-frame delta of 0.00009 at 90 m and **exactly 0.00000** at 275 m (Zone C's torches are dead; Zone A's flicker), turning the head 0.00066 (the flashlight is a world light and sweeps the reflected corridor), **walking 0.00528 — 59× standing still**. ⚠️ **Not dark, either**, and that was measured rather than assumed: reflection mean luminance **0.0244 vs the corridor's own 0.0231** at 90 m and **0.0107 vs 0.0119** at 275 m, with a brighter peak pixel than the direct view at both. Nothing was lit. **Do not settle this by reverting the frustum.** See ISSUES_SOLUTIONS Issue 84

- **Zone C dread** (260–320 m, `DreadZone` spawned by `_spawn_dread_zone()`): decay weakens to `DREAD_DECAY_RATE` (2.0/s) and a constant `DREAD_PANIC_RATE` (2.0/s) pressure accrues regardless of anything else — the two cancel exactly, so panic just holds flat rather than draining, making the last 60 m an endurance stretch. **Shortened from 230 m (Session — difficulty fix)**: the old 230–320 m dread zone left no room to decay off the silhouette/floor-crack panic before the flat stretch began. ⚠️ **Don't re-add a `DarkZone` over any part of the dread zone** — `player.gd` stacks dark-zone tax (+3/s) additively on top of dread pressure, and the noclip ending force-kills the flashlight for the final ~10 m with zero player agency to avoid it, so a `DarkZone` there was a guaranteed +5/s with no way out (also reachable by simple battery attrition — 240 s max, easily burned by beartrap QTEs earlier). This is what made the level read as "impossible" — fixed by dropping `DARK_ZONES`'s old second entry (240–318 m) entirely
- One framing note at the entrance ("Hotel Vesper — The Management"). ⚠️ **The PAGE is real artwork since 2026-08-17** (playtest: *"The note looks boring. Can we generate an image that will make it look more like haunted-hotel style?"*). It was a `BoxMesh` with **no texture at all** — albedo (0.05,0.05,0.04), emission (0.55,0.50,0.35) × 0.6, i.e. a flat olive slab, and the first thing the level asks the player to touch. Now a thin paper box carrying the edge with an art `QuadMesh` 1 mm proud of it (art on a quad, never a box face — Issue 24), sized from the artwork's own aspect. `tools/make_vesper_note.py`: the PAPER is flux (foxing, damp blooms, a torn deckle edge, the creases of a sheet folded in four) and the WORDS are Pillow — `HOTEL VESPER / NIGHT AUDIT`, the first paragraph and the sign-off, **verbatim from `NOTE_TEXT`, which is unchanged**. ⚠️ Darkened to 0.66 (mean luma 88/255) because near-white albedo is the brightest paint this renderer has (Issue 63), and cut out with a **flood fill from the centre of the sheet** rather than a brightness threshold — the generation has the candle that lit it in one corner, and only connectivity tells a candle from paper. ⚠️ **AND IT LAY UPSIDE DOWN FOR THE WHOLE LIFE OF THAT REBUILD** (fixed 2026-08-18, capture 001: *"Turn it 180 degrees, it is currently the wrong side from the place I enter the room"*). The page quad's `rotation_degrees.x = -90` lays it flat correctly and then sends its local +Y — the top of the artwork — to world **−Z**, straight back down the corridor into the face of the arriving player. `IntroNote` is now yawed onto `pt.dir`, the walking direction taken from `PATH_2D` itself, and the quad carries an **explicit `Basis`** rather than a second euler term (Godot composes `rotation_degrees` in YXZ, so which axis carries the flip is not readable and the failure is silent — the page still lies flat and still renders). ⚠️ Nothing else measured this: `check_note_mounting.gd` asks whether there is geometry BEHIND a prop and `check_art_aspect.gd` asks whether its artwork is stretched, and **a page rotated 180° about its own normal answers both correctly**. `check_corridor_events.gd` now asserts the text's up-vector against the SPAWN's heading, read out of `corridor.tscn` before anything moves the player, plus a downward ray proving the rotation did not lift it off the table. Issue 121. Also on this level: 3 fake locked doors (`fake_door.gd`) that knock back (+8 panic, first try only) + 6 hinged `AjarDoor`s that open behind you. **Only the exit (room 217) keeps `door.png`**
- ⭐ **THE FALSE ROOM 217** (`false_exit_door.gd`, 2026-08-17) — a trap dressed as the way out, at the corner at **d = 185 m**. The user's brief: *"the door ... would look like a real exit door but opening it would result in an immediate jumpscare which will be loud and panic spike and the title written with red that It was an illusion"*, then *"it would look like the image I generated for the exit and it would have the correct number"*.
  - **What the lie is: not "a red door lied" but "the NUMBER lied".** This level's objective line is `Find room 217 — keep walking, do not run`. ⚠️ **217 appears on no prop anywhere in the level** — the nine ordinary hotel doors all read **307** (`hotel_door_leaf.png`) and the real exit wears `backrooms_tear_door.png`, which carries no number at all. So the first legible 217 in the game is the one on the trap. That is reported rather than fixed; re-dressing the real exit is a design call
  - **The art needed no generation.** `door.png` — the ORIGINAL room-217 exit door, dark panelled wood with a legible brass 217 — has been unused since d=320 was re-dressed. `tools/make_false_door.py` crops it to the leaf (492 × 1136 = 0.4331, rendered 1.000×) and redraws only the number plate, **1.55× larger and crisp**, in Pillow because the text IS the payload, then ages it back with a light gradient and a 0.62 multiply (the clean first draft read as a modern sticker on a hundred-year-old door)
  - **Placement, against the constraints**: head-on down the whole 45 m of segment 4; not a mirror corner (90/275 are spoken for, 230 was emptied in round 2 and is 8 m from the running creature, 140 is inside the Manager's telegraph window); **135 m from the real exit**, so it cannot read as a near-miss. And the argument: 185 is the FIRST corner after the lights-out event and the four beartraps in the 145–172 m dark stretch — **the promise is what pulls the player through the traps**
  - The beat: **E → `flash_scare` immediately** (`screamer_false_door.png` + `FALSE_DOOR_SCREAM`) + jolt + panic; the 0.34 s swing happens **behind the covering image** so the picture drops onto a door standing open on blank wallpaper; 0.45 s later `ScreenText.scrawl` in BLOOD: **IT WAS AN ILLUSION**. ⚠️ That order is `house_fridge.gd`'s documented mistake inverted — there a fullscreen image landed on top of the reveal it was announcing
  - ⚠️ **THE STING IS THE SHARED SCREAMER, `all_levels_screamer` (2026-08-18, the user's call:** *"Use the sounds for shared screamers and make it louder"***).** It was `false_door_scream`, purpose-made because every other candidate was already something else's voice. ⚠️ **The choice of file IS the volume control** — `flash_scare` plays the stream at 0 dB on `Screamer`'s own player and takes no gain argument, and `screamer.gd` is a shared file. Measured, decoded and clamped to ±1.0 as the mixer will: `false_door_scream.wav` peak −1.01 / loudest-300 ms **−3.79 dBFS** → `all_levels_screamer.mp3` peak +0.00 / loudest-300 ms **−0.16 dBFS**, i.e. **+3.63 dB and essentially all the headroom that exists**. Nothing was added on top, because there is nothing to add without shipping distortion; what the switch really buys is density (1.85 s of near-brickwalled scream against 1.6 s) and **recognition** — it is the sting `_apply_level_av()` pairs with the shared `screamers/` pool. ⚠️ It is deliberately **not** this level's FATAL sting: the Corridor dies to `screamer_corridor`, so a survivable trap borrowing the shared scream does not teach that the death sound is free (the objection `INTRO.md` raises). `check_corridor_events.gd` asserts both halves. `false_door_scream.wav` is **deleted** and `tools/make_sfx_false_door.py` carries the verdict in its header — an orphan asset is the `sprawl_wall_hum` trap
  - ⚠️ **AND THE PICTURE IS DARK NOW** (2026-08-18, the same capture: *"Make the image more dark and aggressive"*). v1 measured **mean luminance 57.97 of 255 with 1.97 % of its pixels above 0.90 sRGB** — against this level's own FATAL screamer at 15.04, the Manager at 10.82 and the shared pool at 8.48, i.e. **4× brighter than anything else the level can show and the only screamer in the game with blown-out pixels in it.** Fullscreen, in a renderer with no tonemapping, that is a flashbang with a face in it, which is why *dark* and *aggressive* arrived in one sentence: it had no shadow to be aggressive in. v2 is a new flux generation — a lunge out of a doorway with the frame either side, so it cannot be mistaken for `screamer_hotel.png`'s static head-on portrait — graded by `tools/make_false_door_screamer.py` (vignette + 0.78 exposure + 1.16 gamma + a rust cast) to **mean 11.35, 0.00 % hot, p99 114.4**. ⚠️ **"Dark" must not become "a black rectangle"**: the picture is on screen for 0.9 s, so the guard asserts a p99 FLOOR as well as a mean ceiling, and the ceiling is `screamer_hotel.png`'s own mean rather than a typed number
  - ⚠️ **Deliberately NOT a `FakeDoor`** (the level's three of those are locked doors that knock back for +8 — a different promise) and **not `door.gd`** (its unlock machinery is baggage); built on `ajar_door.gd`'s skeleton, hinge on the leaf's BACK FACE. Prop emits, LEVEL decides. **One-shot** — `can_interact()` false afterwards so E does nothing, the leaf stays open on bare wallpaper, and `save_progress()` records it so a back-door return does not re-arm it
  - ⚠️ **It does not narrow the corridor**: fully open, the narrowest free run through the corner measures **2.15 m of 3.0** (point queries, player excluded). That assertion is unfalsifiable by this door — a 0.909 m leaf cannot seal a 3 m hall at any angle — so `check_corridor_events.gd` carries a permanent control that puts a real obstruction there and requires the sweep to see it (Issue 105)
  - ⚠️⚠️ **`FALSE_DOOR_PANIC` is 15 and is CONFIRMED BY THE USER (2026-08-18)** — they were shown the alternatives (25 to match the Manager, 20 the silhouette, 10 a pure shock) and the worst-case arithmetic, and chose 15. Do not re-tune it without asking. Reasoning in `backlogs/03-corridor.md` §10: the level's one-shot spikes now total **104** of a 50-point bar (10 + 25 + 20 + 10 + 24 + 15), the beat is effectively mandatory because it is dressed to be opened, and it lands right after the beartrap stretch. ⚠️ The 2026-08-18 round made this beat land harder in two channels — a louder sting and a darker picture — and **moved no number at all**
  - ⚠️ **The doors are DOOR-SHAPED now (2026-08-16).** `ordinary_hotel_door.png` was a door *plus its architrave plus the wallpaper either side* — Issue 35, hung as a picture of a wall on a wall — and it was squashed 1.29× onto a 1.3 × 2.1 leaf. `tools/crop_corridor_art.py` crops it to `hotel_door_leaf.png` (616 × 1334), `AjarDoor.WIDTH` is **derived from that aspect at 0.97 m**, and the casing is real geometry: `_spawn_door_frame()` → `_spawn_frame_bars()` puts two jambs and a head standing `FRAME_PROUD` 0.085 off the wall with the leaf recessed inside them. The `FakeDoor`s get the same crop and the same frame. ⚠️ The frame is **not** a child of the `AjarDoor` — the leaf rotates, and a frame that swings with the door is the one thing a door frame may never do; and it has **no collider**, so `check_corridor_doors.gd`'s soft-lock measurement is unaffected (a narrower leaf can only improve it: measured 2.29 m of free hall, up from 2.02 m)
  - ⚠️ `AjarDoor` **hinges on its own BACK FACE** (`mesh.position.z = THICK / 2`), so the whole leaf lives in front of the hinge plane and the closed door seats at the level's ordinary `WALL_INSET`. With the old centre hinge the rear corner swept 6.4 cm behind the plane, which is why the doors used to be held **0.090 m off the wall** — Issue 79, and playtest capture C2
- **WALL MOUNTING IS ONE CONVENTION**: `corridor.gd:WALL_INSET = 0.03` (and `FLOOR_DECAL_Y = 0.03`). It was 0.02, which is *exactly* `check_wall_overlap.gd`'s `MIN_CLEAR`, and `AABB.has_point()` includes its own boundary — so every flat decal in the level was reported the first time that guard was ever pointed at this scene. `check_prop_mounting.gd` is the **maximum**-clearance half nothing had (cross-level X1): 30 props here, each required to sit 0.005–0.045 m off its wall, with scene-derived controls in both directions — and since 2026-08-17 it sweeps all nine levels, the Corridor keeping its own tight band while every other level is measured against the `wall_point()` convention
- Corridor-exclusive screamer: `screamer_hotel.png` — kept OUT of `screamers/`; `screamer.gd` selects it when `GameState.current_level == 3`
- **The two plates.** Both are wall props whose art used to be a picture of the wall behind them:
  - **KONTUR Gate 3's hint** at d=172 (`_spawn_kontur_hint`) — *"RECOVERED ITEMS ARE BAIT. LEAVE THEM."* It was the raw `kontur_plate.png` (a plate on damask wallpaper above a wainscot) on a 2.0 × 3.0 full-height panel: a 1.333 landscape source on a 0.667 portrait mesh, **stretched 2.00×**, the worst distortion in the level, on the one prop whose entire payload is four words the player must READ. Now cropped and alpha-masked to the plate's ogee outline (`kontur_plate_crop.png`), hung at **1.15 m** at eye height, undistorted and legible from the centreline
  - **THE NIGHTMARE's hint** at d=250 (`_spawn_nightmare_plate`) — the note `DUNGEON_NIGHTMARES.md` §B2 calls *"the single most important hint in the game"*. It was an **untextured `BoxMesh`** (a flat olive rectangle; playtest capture C3: *"this note does not match the level vibe"*). Now built from parts — backing plate, a four-bar bead frame, four corner screws, and a recessed art `QuadMesh` carrying `vesper_plate.png` (`tools/make_vesper_plate.py`, Pillow, deterministic). ⚠️ **The art carries the HEADING ONLY** and `note_text` is unchanged: the body is the thing that teaches the silence mechanic and it must stay re-readable in the TAB journal
  - ⚠️ Both use `emission_operator = EMISSION_OP_MULTIPLY`. Godot's default is **ADD**, so an emission colour beside an emission texture lays a flat wash over the whole surface — measured, it rendered a near-black plate as a pale cream slab with the lettering knocked out (Issue 81)
- ⚠️ **`_ev_painting_fall` validates its spawn** (2026-08-16). It used to place the painting at `player + Vector3(randf_range(-2,2), 1.8, randf_range(-2,2))` in a 3 m corridor with walls at ±1.5 m, unvalidated — measured **199 of 200** sampled placements put a corner outside the corridor or through a wall (Issue 77's second head). It now walks outward from the player's own path distance, prefers the wall they are facing less, and probes three rays that must hit **CSG** rather than another prop; if nothing fits it plays the sound and withholds the picture. `check_painting_fall.gd` keeps the old rule as a live control
- Prop textures (`clock/mirror/torch/carpet.png`) share the same baked wallpaper+wainscot background as `wall.png` and are applied as full-height wall panels. ⚠️ Five of them are still stretched 1.20–1.67× and that is a **deferred art pass**, listed by name with its reason in `check_art_aspect.gd`'s Corridor row — which asserts its own size, so a new stretch cannot hide behind an entry written for a different one

**Level 4 — The Backrooms (liminal mono-yellow maze)** — `backrooms.gd` + `backrooms.tscn`
- **Entry = the noclip** (`_spawn_noclip()` in `corridor.gd`): the player never reaches room 217 — which now wears `backrooms_tear_door.png`, a black-wood door torn open on a red-lit void, sized from the artwork's own aspect. **Fifteen** metres out every torch dies and `player.kill_flashlight()` force-kills the light (F now only plays a dead-battery click), and the floor gives way **5 m short of the door** (user's call, 2026-08-15 — you see it, you never touch it). ⚠️ **It is a REAL fall (2026-08-15)**: `_ev_noclip_fall()` zeroes the player's `collision_mask`, so gravity takes them straight through the floor (measured 6.96 m in 1.2 s); input is frozen, the screen fades at −3 m and the Backrooms takes over at −9 m. It used to fade to black and wait 2 s with the player standing still, which is not a fall. No hole is cut: the corridor floor is one CSGBox3D per 45 m segment, and the blackout killed every light 10 m earlier so nobody could see one. ⚠️ **Three constants move together** — `NOCLIP_FALL_BEFORE_DOOR`, `NOCLIP_ONSET_BEFORE_END` and `RETURN_MARGIN` (14 → **18**). Re-entry from the Backrooms must land clear of BOTH trigger boxes or arriving re-fires the blackout, or the fall bounces the player straight back. `tests/check_noclip_fall.gd` asserts the relationships rather than the numbers, so any one of them can be retuned but not alone
- **Cyclic maze, no seamless portals** (design Q1): a 4-way intersection hub with three choice arms (N/E/W) built from `CSGBox3D`, triplanar `backrooms_wallpaper_albedo` walls + `backrooms_carpet_albedo` floor, recessed flickering fluorescents. The E/W arms dead-end in a `LoopBack` trigger that teleports you to an identical re-randomised hub — so it reads as an endless series of intersections without any continuous-portal seams
- **Win — three down-turns** (`_assign_round`, `_on_arm_entered`): an arrow decal on the hub columns marks exactly one arm with a DOWN arrow each round. Take it to advance the loop counter; the E/W arms loop back, and on the 3rd correct turn the win arm (N) is forced and opens into the exit utility room. The **glitch wall** there runs a screen-space vertex-jitter shader (`glitch_wall.gdshader`); walking into its `ExitTrigger` Area3D → `advance_level()` → The Void
  - ⚠️ **The counter now actually reaches (3/3)** (2026-08-17). `_on_exit_reached()` accepted at
    `_counter >= TURNS_TO_WIN - 1` and never incremented for the final walk, so the HUD printed
    (1/3) and (2/3) and then cut straight to the zone card — both playtest logs show the objective
    stuck at (2/3) at the moment `THE SPRAWL` appears. A progress meter that never completes reads
    as a bug rather than as a reward. The zone card is held back `ZONE_CARD_DELAY` = `CARD_LENGTH`
    (2.5 s, a full card) so the (3/3) gets its moment. ⚠️ Two tweens driving one
    `theme_override_colors/font_color` fight and the failure is SILENT — the loser's `.a = 0` lands
    on the winner's fade-in. So `_show_progress_text()` kills only for an **immediate** message
    (which pre-empts) and never for a **queued** card, because the thing a queued card waits for is
    exactly the message it would otherwise kill
  - ⚠️ **THE ARROW IS THE WHOLE PUZZLE AND IT WAS ILLEGIBLE** (rebuilt 2026-08-17, Issue 88).
    `arrow_decal.png` was a photograph of yellow wallpaper with a slightly darker arrow on it:
    measured from real frames, **2.2 % glyph-vs-panel contrast** while the panel carried 22 %
    against the column — every part of the sign with no information in it was ten times louder than
    the part that did. It was also RGB **with no alpha** on a `TRANSPARENCY_ALPHA` material, a
    square source stretched 1.556× onto a 0.45×0.70 quad, 0.45 m wide on a **0.28 m post** (38 % of
    it hanging in mid-air), 0.02 m clear of that post, and **emissive at 0.25**, i.e. self-lighting
    its own wallpaper background. A misread costs `WRONG_TURN_PANIC` 18 = 36 % of `PANIC_MAX`.
    Now: `backrooms_arrow_glyph.png`, a real RGBA cutout with **no background of its own** drawn by
    `tools/make_arrow_decal.py` (seeded, deterministic — an arrow is a geometric primitive and
    nothing generative should be asked for one), sized from its own aspect, **no emission at all**,
    on a post widened 0.28 → `ARROW_POST` 0.68 with `ARROW_CLEAR` 0.06. Measured contrast **89 %**.
    ⚠️ Widening the POST rather than shrinking the SIGN is the point: the sign is the thing that has
    to be readable at 15 m. `arrow_decal.png` is retired to `assets_src/textures/superseded/`
  - ⚠️ **THE HUB IS A 4-WAY INTERSECTION AGAIN, AND YOU CAN WALK THROUGH IT** (2026-08-17,
    Issue 93). The player photographed the hub: *"The scapes between columns to walk into are too
    small."* Measured with their own capsule, the only way into the E arm was a **1.01 m slot for an
    0.80 m capsule** — a 0.21 m band, which is also why `check_reachable.gd`'s 0.25 m grid had
    reported both zone-1 mirage doors unreachable and that finding had been filed as a false
    positive. Two causes, and the post was the smaller one:
    1. `_build_entry_arm()` centred the entry arm at `(lo - HALF) / 2`, i.e. the WHOLE ARM 1.5 m
       (= `HALF`) south of where its own comment said it was. Its two side walls therefore ran to
       `z = +0.15` — **1.65 m into the hub**, standing across the southern half of both the E and W
       mouths. It also produced the 3 × 1.5 m coincident floor/ceiling patch that
       the wall-overlap guard had **waived as deliberate**, and 1.35 m of sealed floor
       behind `EntryCap`. Now `span_mid = (-HALF + lo) / 2`, `span_len = (-HALF - lo) + T` — the same
       form `_build_choice_arm()` has always used, one `T/2` into the hub corner. The waiver is gone
       and `_min_allow` is 0, so any coincident pair at all now fails.
    2. the three arrow posts stood on the arm CENTRELINE, splitting whatever opening was left. Each
       now stands against the jamb **clockwise** from its arm (`jamb = Vector3(axis.z, 0, -axis.x)`:
       N→NE, E→SE, W→NW — three different corners, so no arrow can be mistaken for its neighbour's),
       buried `ARROW_BURY` 0.10 into that wall so no two faces are coplanar.
    Measured lane, widest contiguous run at the mouth plane plus a capsule diameter: **N 2.02 m ·
    E 2.04 m · W 2.38 m**, against 1.01 m before. ⚠️ **Both halves are load-bearing** — post back on
    the centreline gives 1.14 m everywhere; the old entry arm alone gives E 1.10 m and W 0.88 m.
    ⚠️ **The arrow art did not change at all** (same cutout, size, clearance, zero emission, 92.7 %
    contrast), and `check_backrooms_seam.gd` now also asserts, per arm, that the wrong-turn sensor
    spans at least the full lane and sits DEEPER into the arm than the arrow — the sign is read
    before the turn is scored, and nobody can slip past a mouth. ⚠️ Measure a lane with **rays and a
    point query, never `intersect_shape`**: a capsule centred on a CSG post comes back CLEAR
    (Issue 40)
  - ⚠️ **The scene now sets a BLACK BACKGROUND** (`_black_background()`, 2026-08-17). `backrooms.tscn`
    instances the shared `assets/elements/environment.tscn`, which is `BG_SKY` over a
    `ProceduralSkyMaterial` — so when the Sprawl turned out to have holes in it, the player
    photographed a **daylit horizon** inside the Backrooms. The Lab, House and Corridor all switched
    to black long ago for exactly this reason. ⚠️ It is a SECOND LAYER, never a substitute for
    closing the hole, and it is **not** a lighting pass: `ambient_light_color` and energy are
    untouched and only `ambient_light_source` is pinned to COLOR, dropping the 8 % sky contribution
    (0.0026 in linear ambient luminance)
- **Fail — wrong turn**: entering a non-down-arrow arm = `light_pop` + 15 panic + counter reset + teleport to the start (`_wrong_turn`). **Standing still** > 4 s raises panic (`player.enable_standstill_panic()`, +3/s) — the maze forbids rest. Plus the usual panic-bar-fills death
- **Dynamic dark zones**: one (always-wrong) arm goes black each round (`_apply_dark_arm` → lights off + `DarkZone`)
- **The Smiler** (`creature_smiler.gd`, ~50% per dark arm): a glowing `screamer_smiler.png` billboard at the dark arm's end. Its logic INVERTS the maze (design Q2): shine your flashlight on it **or** sprint → rush → `Screamer.trigger()` (fatal — the smiler image fills the screen via `LEVEL_SCREAMERS[4]`). Turn the light OFF and hold still (don't sprint) and it fades after 4 s. While engaged it calls `player.set_smiler_active(true)` to suspend the standstill + dark ticks and drives its own slow dread (+2.5/s) — freezing to survive is tense but fair
- **Footstep echo** (`player.enable_footstep_echo()`): every step replays at half-volume 0.4 s later, two paces behind you
- **Mirage doors** (`mirage_door.gd`): blood-red doors identical to the back doors; opening one swings onto blank wallpaper + 10 panic, mocking the hope of retreat
- **The rotary phone** (`rotary_phone.gd`): a 1970s phone on the carpet that rings (`rotary_ring`); answering (E) plays `phone_whisper` and opens a read-to-die trap note via `NoteUI.show_note(text, 11.0)` — hang up (close) to survive
- **The entry note** (`_spawn_intro_note()`, `ClueNote`): the first thing the level asks you to touch. ⭐ **It is a document since 2026-08-18** (`backrooms_note.png`, `tools/make_backrooms_note.py` — paper from flux, words from Pillow, `make_vesper_note.py`'s recipe in the Backrooms' register). It was an **untextured `BoxMesh`** at albedo (0.85, 0.82, 0.60) with ADD emission — a near-white self-lit card, photographed as the brightest object in its frame (capture 003, *"Again, make the note more like the backrooms atmosphere"*; the "again" is because the Corridor's entrance note was rebuilt for this the day before). ⚠️ **`NOTE_TEXT` is unchanged** — the artwork letters its opening paragraph verbatim, and carries **no invented letterhead**, because this page is signed *"— someone who is still in here"*. ⚠️ **Darker than the wallpaper is MEASURED, not a taste call**: paper **98.9/255** against the wallpaper's **171.9**, and `check_backrooms_seam.gd` asserts it against the wallpaper *file* so a re-skin cannot silently break it. Art on a `QuadMesh` sized from its own aspect, on a dark `NotePad` box that carries the sheet's edge; emission through `EMISSION_OP_MULTIPLY` at 0.45 (Issues 81 and 21)
- **THREE ZONES (Session 14).** One scene, three world-space offsets; each zone ends in a glitch
  wall that teleports you to the next. `backrooms.gd` orchestrates (`_enter_zone`, `_on_zone_mistake`)
  - **Zone 1 — THE LOBBY** (origin 0): the original hub + N/E/W arms. Three down-turns → its glitch
    wall now calls `_enter_zone(2)` instead of `advance_level()`. `WRONG_TURN_PANIC` 15 → 18
  - ⭐ **THE SEAM HAS A VOICE (2026-08-17).** The level's win verb is *walk into a blank wall*, and
    zone 1 demands it **three times before anything teaches it** — twice at the E/W loop-back caps,
    once at the utility room. The caps are the worse half: they are built from `_wall_mat`,
    identical to every other wall, and `LoopBack{E,W}` sits **0.30 m from the cap's inner face**, so
    the turn only counts once you are a foot from a plain wallpapered dead end. The playtester stood
    still for **86 seconds, 6.2 m down the CORRECT arm**, writing *"many players might get confused
    that you need to go through the wall"* — while looking at a **loop-back cap**, not at the glitch
    wall. Three channels answer it, none of them brightness and none of them panic:
    1. a **two-layer positional tell** — `seam_draw` (far cue, `unit_size 16`, `SEAM_FAR_DB` −15) for
       a bearing from the arm mouth, and `seam_rip` (near confirm, `unit_size 5`, −6) that only
       resolves in the last few metres. `tools/make_sfx_seam.py`, gains set from the files' measured
       levels (−12.7 / −20.8 dBFS RMS), both **under** `MUSIC_VOLUME_DB`;
    2. a **`Label3D` scrawl** reading `NO DOOR. / WALK INTO IT.` — quoting the Lab Observation
       whiteboard's `NO DOOR` verbatim, which is the hint the user asked twice to be made clearer.
    - ⚠️ **A THIRD CHANNEL WAS CUT ON THE VERIFICATION REPLAY (2026-08-17) — do not re-add it.**
      Twelve dark floor **drag marks** ran into each seam surface. The player judged them TWICE on
      one playthrough: *"These stripes look weird - remove them"* (utility room) and *"Yeah, remove
      the stripes. The hints on the walls are sufficient"* (an E-arm loop-back cap). `DRAG_Y`,
      `DRAG_SPEC` and `_spawn_seam_marks()` are gone; the function is now `_spawn_seam_scrawls()`.
      `check_backrooms_seam.gd` asserts the ABSENCE of any `DragMark*` node anywhere in the scene
      and asserts it measured all three scrawls, so removing them did not shrink the test.
      `GAME_MECHANICS_IDEAS.md` §5.1 carries the verdict in the user's own words
    - ⚠️ **ONE emitter pair, moved by `_assign_round()`** to whichever surface the round wants. Three
      permanent beacons would be noise rather than a bearing, and the wrong arms are unreachable
      anyway (their mouth sensor ejects you first).
    - ⚠️ **It must serve the CAPS, not only the glitch wall.** That is the specific reason this was
      chosen over the alternative below; `check_backrooms_seam.gd` asserts the cap case explicitly.
    - ⚠️ **THE TIMED GLOW WAS OFFERED AND DECLINED — do not re-pitch it.** The user's capture asked
      for *"the wall to shine one minute in"*. Measured, the glitch wall is **already the brightest
      surface in its room by 2.3×** (132.7 lum against side walls 56.9/58.9, ceiling 55.8, floor
      51.9) and a 10 % step from the decision point 15 m back. Luminance was never the missing
      channel, and a glow on the glitch wall would not have helped at all where the capture was
      actually taken.
    - ⚠️ **And it must not make zone 2 redundant.** Zone 2's whole puzzle is *find the wall by
      sound*, so zone 1's cue is deliberately **unmissable and singular** — what it teaches is the
      VERB. Zone 2 keeps its difficulty in **discrimination between four**, a different skill, and
      keeps its own two-layer `water`+`whisper` tell. Both are on **Master**, never the `"Backrooms"`
      bus, because a `SilenceZone` ducks that bus and a tell routed through it mutes itself.
    - **Zero panic.** The beacons are bare `AudioStreamPlayer3D`s with no script, no children and no
      Area3D; `check_backrooms_seam.gd` asserts that structurally
  - **Zone 2 — THE SPRAWL** (`backrooms_zone2.gd`, origin `(200,0,0)`): a 40×40 m pillar hall with a
    **4.5 m** ceiling — deliberately wrong-scale against zone 1's 3 m corridors. Four *identical*
    glitch walls, one real, randomised. Touching a
    fake = `go_solid()` + **12** panic (`backrooms.gd:WRONG_WALL_PANIC`) + teleport + re-randomise.
    ⭐⭐ **THE BOX IN THE DARK IS THE GATE** (`sprawl_crate.gd` + `sprawl_dweller.gd`, the user's own
    design, backlog 04 §16.4 and §18.3). A two-layer whisper (`sprawl_call_far`/`_near`, on
    **Master**) leads to a slatted crate standing in ONE recess chosen per run; E on it fires a
    survivable `flash_scare` and the thing that was inside **runs across the hall and out through
    the real wall** — and the real wall does not work until it does.
    ⚠️⚠️ **THIS FILE SAID THE OPPOSITE UNTIL 2026-08-18** — that the crate was a redundant second
    route and "must never become the only one" — and the user overturned it, having been told the
    fallback existed: *"it should run and go through the real wall which would not be active until
    it runs through."* Asked for twice, explicitly. The real wall is now **`GlitchWall.set_sealed()`**
    until the runner arrives: it looks exactly like its three neighbours and walking into it does
    **nothing**. ⚠️ Sealed is a COLLIDER, not a hidden node — `_side_runs()` cuts a 7 m gap in the
    perimeter for each wall, so in this zone the wall IS the shell and hiding it is a hole in the
    world. ⚠️ **The gate follows a re-roll** (`_apply_gate()` recomputes all four from `_real_side`;
    `revive()` rebuilds triggers from scratch, which is where a seal would silently drop), and it
    does **not** come back once the runner has been through.
    ⚠️⚠️ **WHICH MAKES THE WHISPER A COMPLETABILITY GUARANTEE**, and it was **inaudible everywhere**
    until this pass — Issue 131: the gains were set from the files' RMS and never against the bed
    they play over (the score is −22.0 dBFS effective; the far cue reached **−25.2 dBFS at the box**).
    Now +9.8 dB of margin at the crate and **+3.6 dB at the worst standable point in the zone**,
    measured on a 1593-point grid, and the loop has **no timer, no one-shot and no stop path** — the
    Flood's knock rule in a second place. ⚠️ The far cue carries the hall nearly **flat** and gives
    its bearing by PANNING; the near confirm owns the gradient. One emitter cannot do both across
    45 m and the arithmetic says so (Issue 112's other half).
    ⭐ **The camera is pinned to the run** (`backrooms.gd:_tick_crate_watch`, the user's *"Force my
    camera to see that action"*). `player.turn_to_face()`, `level_1.gd`'s nook reveal as the
    precedent. ⚠️ The run is **deferred by one `flash_scare` hold** — a run started on the press is
    watched through a fullscreen image — and the aim is **re-targeted every 0.18 s** because the
    thing moves, then held 1.1 s past the arrival aimed at the wall. `WATCH_MAX` 12 s is a safety
    valve, not a difficulty number.
    `check_sprawl_crate.gd` drives the whole thing cold — spawn → whisper → box → run → wall → out —
    through the real interact ray and the real `Area3D`, and asserts the gate in **both** directions.
    ⚠️ The runner is a **dedicated one-shot
    object, never a Congregation `Watcher`**: those are ruleless by construction and that is why the
    Congregation is legal beside a Smiler that kills you for looking. ⚠️ The mark is **motion**
    (`GlitchWall.set_agitated()`, tear 0.12 → 0.34), not brightness — the glitch wall is already the
    brightest surface in its room by 2.3× — and it **follows a re-roll**, because a mark left on a
    wall that is no longer real is worse than no mark. ⚠️ The crate's recess has its ceiling light
    **cut** (`_build_lights()` skips every strip within 11 m), so "hidden in the dark" is measured.
    ⚠️ **Zero panic**: the scare is `flash_scare` + a camera jolt and nothing else; whether it should
    cost anything is an open question (backlog 04 §16.5 / D31), not an omission. It IS **+14.6 dB
    louder** since 2026-08-18 (`crate_shriek.wav` −20.0 → **−5.4 dBFS RMS**, peak unchanged at −1.01,
    zero samples at full scale) — the user asked for it, and `flash_scare()` takes no gain, so the
    only lever was the file's average level.
    ⚠️ **The objective line is `Four walls tear. Something in here knows which one`.** It used to say
    *"Only one is thin — listen for it"*, which described the pre-gate zone: listening to the wall's
    own tell no longer opens anything, so the line named a verb that does not work.
    **The `SilenceZone` and the wall's own cue are FLAVOUR AND CONFIRMATION now, not the route**
    (2026-08-18). A `SilenceZone` around the real wall still ducks the whole `"Backrooms"` bus to
    −30 dB, and `_randomise_real_wall()` still spawns a positive cue AT that wall, deliberately kept
    off that bus so the pocket cannot duck the very tell it provides (**BUG_FIX.md 3.5**, added when
    playtest read pure silence as too subtle). ⚠️ Measured while making the crate the gate: outside
    the pocket that cue sits ~14 dB **under** the score, and inside it the bus ducks 30 dB and it
    emerges — so it has always worked by CONTRAST WITHIN THE POCKET rather than as a bearing across
    the hall, which is exactly the job it now has. **Do not delete it**: without it the real wall is
    silent until the runner arrives, and the run is the only cue there is.
    ⚠️ **That cue is `water` (`unit_size 16`) + `whisper` (`unit_size 9`), NOT `sprawl_wall_hum`.**
    This file described the hum as the tell for several sessions; the hum was a first pass at
    `unit_size 4.5`, audible only once you were already at the correct wall in a 40×40 m room with
    four identical ones, and it was replaced by the two-layer far-cue/near-confirm pattern
    (`backrooms_zone2.gd:187-225`). **`sprawl_wall_hum.wav` is still generated by
    `tools/make_sfx_backrooms.py:97` and is referenced by no `.gd` file at all** — it is an orphan.
    Do not "restore" it without re-reading that comment; the wide range is the whole point
    - ⚠️ **THE EIGHT ALCOVES WERE SEALED FOR THE WHOLE LIFE OF THE ZONE, AND ARE NOW OPEN**
      (2026-08-17, `backlogs/04-backrooms.md` §9, ISSUES_SOLUTIONS **Issue 90**).
      `_build_alcoves()` builds each recess as a floor, a back wall and two side walls OUTSIDE the
      perimeter, and nothing ever removed the perimeter in front of it — a ray from 3 m inside the
      hall was blocked at exactly the 3.00 m mouth plane on **all eight**. Behind that wall sat
      `SprawlNote` (the only readable object in 1600 m², and the page that states the zone's own
      tell), the off-hook `SprawlPhone`, the `LivingMirror`, two `MirageDoor`s and five props —
      every authored object in the zone except the pillars, the lights and the four glitch walls.
      `_side_runs()` now derives each side's solid runs by subtracting the openings (the 7 m
      glitch-wall gap + one 4.0 m **mouth** per alcove) from its full extent: **four segments per
      side, not two.** ⚠️ A mouth is `ALCOVE_W` **plus a wall thickness at each end**, so the
      perimeter stops at the OUTER face of the alcove's own side walls and the two boxes ABUT —
      cutting to the interior width instead leaves two end caps coplanar and both facing into the
      mouth. ⚠️ `ALCOVE_AT` replaced the literal `11.0` that had been repeated in four places, and
      `_side_runs()` reads it, so the mouths cannot drift away from the recesses. Measured:
      **+3 241 standing cells (+50.6 m²)**, interactables reachable **8/12 → 12/12**, route to the
      four glitch walls unchanged. Locked down by `tests/check_sprawl_alcoves.gd`, which re-seals
      one mouth every run to prove it can fail
    - ⚠️⚠️ **AND THEN FOUR OF THEM TURNED OUT TO BE OPEN AT THE BACK** (2026-08-17, verification
      replay, ISSUES_SOLUTIONS **Issue 92**). `_build_alcoves()` built the BACK wall of every E/W
      (`is_x`) recess with the SIDE wall's ternary — `(ALCOVE_D, h, T)`, a 3 m blade lying ALONG the
      depth axis and half sticking out of the building, where `(T, h, ALCOVE_W)` across it belonged.
      All four E/W recesses were **3.40 m wide × 4.50 m tall of open world**, and with `BG_SKY` still
      set the player photographed a daylit horizon from inside the Sprawl. The blade also stood
      across the walking line to that alcove's own `MirageDoor`, which is the red object in the
      capture. N and S were correct, which is why it read as a working feature.
      ⚠️ **It survived `check_sprawl_alcoves.gd`, written the same day for this exact zone**: its
      "shell closed" probe fires ONE ray outward from each recess's CENTRE, and the blade sits
      exactly on that line — the ray hit it at 0.15 m and reported the wall present. **One ray is a
      test of a point, not of a surface.** `tests/check_shell_sealed.gd` is the guard now: a 0.25 m
      lateral perimeter sweep at six heights, an outward-hemisphere fan from five points in each of
      the eight recesses, and a 1.5 m interior floor grid across **all three zones** — ~66 000 rays,
      with two permanent controls that punch this hole back open and require both sweeps to go red.
      A `GlitchWall` is a hole on purpose, so a ray that hits nothing is forgiven only if it crosses
      one; that exemption list is counted (exactly 8) like `check_wall_overlap.gd`'s `_allow`
    - ⚠️ **`SprawlDread` is `SIZE + 2 × (ALCOVE_D + T)` square, not `SIZE`** — widened with the cut
      so the eight recesses stay inside the no-decay zone. Outside a `DreadZone` decay runs at the
      full 3.5/s, so leaving it at the hall's own footprint would have handed the zone eight
      recovery pockets in a design that has exactly one anchor. This preserves the sealed build's
      pressure profile exactly; it is a decision, not a detail
    - ⚠️ **Three panic sources went live with the cut and none of them was tuned**: two
      `MirageDoor`s at `PANIC = 10` each (voluntary, one-shot) and `SprawlMirror`'s
      `GAZE_INTENSITY = 0.7` (**14 panic/s** while stared at, in a zone where decay is cancelled).
      `SprawlPhone` is zero — `open_note = false` and `rings = false`, asserted. The zone's
      `WRONG_WALL_PANIC` 12 was measured with all of this unreachable; treat the next playtest as
      the first real reading
    - ⚠️⚠️ **THE EIGHT ALCOVES ARE SEALED, AND EVERYTHING IN THEM IS UNREACHABLE** (measured
      2026-08-17, NOT fixed — it needs a decision). `_build_alcoves()` builds each recess as a
      floor, a back wall and two side walls OUTSIDE the perimeter, and nothing ever removes the
      run of perimeter wall in front of it: `_build_shell()`'s two runs span 3.5…20 and −20…−3.5
      and the alcoves are at **±11**. A ray from 3 m inside the hall is blocked at exactly the
      3.00 m mouth plane on all eight. Behind that wall: `SprawlNote` (the only readable object
      in 1600 m², and the page that states this zone's own tell), `SprawlPhone`, the
      `LivingMirror`, two `MirageDoor`s and five props. ⚠️ **This re-reads the playtest finding
      "SprawlNote was not read in either session"** — that was never a placement problem.
      Opening them adds ~10 reachable objects and eight rooms to a zone tuned without them, and a
      mis-cut hole in this shell is why `_catch_out_of_world()` exists. See
      `backlogs/04-backrooms.md` F1 and the ⚠️ block at `_build_alcoves()`
    - **THE CONGREGATION** (`congregation.gd`): 6–8 persistent `Watcher`s among the 36 pillars,
      growing by one per wrong wall (capped at 12). Zero panic, no collider, no kill radius, no
      fail state — unchanged, and it is what keeps the feature legal under `SCARY.md` §8.3.
      ⚠️ **Two defects fixed 2026-08-17, both of them the reason it read as inert** (Issue 85):
      - **The destination was never gated.** `CLAUDE.md` states the contract — *"a figure relocates
        only when it is BOTH out of view and ≥15 m away, so it never moves on screen"* — and only
        the SOURCE half was implemented. Measured over 90 s: **633 relocations, 20 m each, 65 of
        them landing in the player's view cone with line of sight** (10.3 %). `_pick_spot()` now
        takes `min_from_player` + `unseen_only`, and `would_be_seen()` re-implements
        `Watcher._is_seen()` for a candidate point.
      - **They never held still.** `SETTLE_MIN`/`SETTLE_MAX` (8–16 s, randomised per figure). A
        figure that has teleported five times since you last looked cannot support "there was one
        by that pillar", which is the entire product.
      - **And they were LIGHTER than the floor.** `watcher.gd`'s premise is "a dark shape OCCLUDING
        a lit surface"; measured here the figure was 43.7 lum at 2 m and 42.4 at 25 m (unshaded, so
        no falloff) against a floor at 29.5–36.3 and a ceiling at 28.8. `Congregation.FIGURE_TINT`
        (0.42, 0.42, 0.48) via `watcher.gd`'s new additive `figure_tint` → **18.5 rendered**
      - ⚠️ The **chorus** (a shared vocal bed scaling with how many are behind you) and **heads
        turning** were both offered this pass and **declined** — see `GAME_MECHANICS_IDEAS.md` §5
  - **Zone 3 — THE FLOOD** (`backrooms_zone3.gd`, origin `(-200,0,0)`): an 8-room flooded wing built
    with `RoomBuilder`, ankle-deep water (`apply_slow` refreshed per frame), near-black.
    ⚠️ **THE ROOMS ABUT; THEY USED TO OVERLAP** (fixed 2026-08-17, Issue 86). `Sump` and `Cistern`
    each overlapped `Basin` by 1×2 m, which — because `RoomBuilder` builds each room's walls on its
    own boundary — left **2 m wall stubs standing inside the Basin at x −5.10 and +4.90 and inside
    the Sump at x −6.10**, boxed both of the Basin's north corners into 1×2 m dead pockets, and
    coincided four floor/ceiling slab pairs. The Basin is the zone's largest room and holds the
    `DryPlatform` `CalmZone`, its only recovery anchor. Fixed by moving both chambers 1 m outward
    (`Sump (-9,21)→(-10,21)`, `Cistern (9,21)→(10,21)`) **with their doorways** (`(∓9,17)→(∓10,17)`
    — move a room, move its doors). Regression-locked by `check_wall_overlap.gd`, which sweeps this scene at 5x5 quad sampling.
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
      the water it wades through is now the thing you can actually hear
    - **The tell is DARKNESS, and since 2026-08-17 the exit must first be EARNED**: six fragments
      out of the six drowned objects, set into the plate table in the Basin, and only then does the
      Sump seam exist at all (`flood_plate.gd`, the user's own design, backlog 04 §16.2). Until the
      plate is whole the seam is `set_armed(false)` — hidden **and not monitoring**, so wandering
      into the Sump early cannot clear the zone. Once armed the rule is unchanged: the real seam is
      visible only with the flashlight OFF, two decoys glow only with it ON. Clearing it →
      `advance_level()` → KONTUR.
      ⚠️⚠️ **THE SAFETY NET IS WHAT MAKES A MANDATORY SEARCH LEGAL**: an object with its fragment
      still in it **knocks every 5–11 s for ever**, so `sunken_item.gd:_process` is gated on
      `is_taken`, **never** on `is_searched` — hauling a lid and walking away must not silence the
      one object you still need. `check_flood_puzzle.gd` asserts it with a control.
      ⚠️ **The plate announces itself on three channels** — it stands 4.1 m from the wing's only
      lamp, it carries `SIX PIECES. / SET THEM HERE.` in dark lettering on a pale board (never a
      bright `Label3D`: unshaded means self-lit, §5.2(8)), and it runs a two-layer tell
      (`plate_hum`/`plate_ring`, **Master**) armed by the FIRST fragment rather than on entry.
      Measured over the water bed in all eight rooms (+8.3 dB worst), under the `flood_knock` at
      the table, and falling 7.6 dB across the wing. ⚠️ That gradient comes from `unit_size`, not
      `volume_db`: Godot clamps `volume_db + attenuation` to `max_db`, and the first build was flat
      to 0.4 dB (**Issue 112**).
      ⚠️ **The objective is one function** (`objective_text()`), it names a RULE and never the room,
      and since 2026-08-18 it names **no task either**: `Something in this wing is unfinished` until
      the plate is whole, then the unchanged `The way out does not show itself in the light`. It
      used to read `Six pieces are sunk in this wing (n/6)` — quantity, verb and score, before the
      player had found anything (playtest capture 005: *"The message should not be that obvious…
      do not write that hint"*).
      ⚠️⚠️ **REMOVING THE COUNTER IS SAFE BECAUSE THE KNOCKS ARE THE COUNTER** — an object still
      knocking is a piece outstanding, and that channel is permanent, positional and asserted, which
      the HUD number never was. Do not "restore" the counter believing the progress feedback was
      lost with it. The consequence is that the plate's three announcement channels (the only lit
      room · `SIX PIECES. / SET THEM HERE.` on its own board · the two-layer tell) now carry all of
      the discoverability weight, so they were re-measured rather than assumed.
      ⚠️ **`save_progress()` carries `flood_set` and `flood_held` as well as the emptied objects** —
      restoring one without the others manufactures an unwinnable wing through a back door.
      ⚠️ **There is NO `DarkZone` here, and this line used to say there was** (corrected
      2026-08-17, Issue 96 — the false version cost an analysis pass its framing). One was removed
      deliberately: a room solved by turning the light off must not also charge +3/s for the light
      being off, which through `player.gd`'s if/elif chain *also* suppresses decay — measured at
      +5/s with no way down, and three playtest deaths inside 10 s without the mechanic ever being
      attempted. Issue 18. The only pressure here is the floor-wide `DreadZone` (decay and pressure
      cancel exactly) plus the zone's own `DREAD_DRIP` **0.3/s while wading**, and the Basin's
      `DryPlatform` `CalmZone` nets about **−2.7/s** standing in it. `check_flood_drowned.gd`
      asserts the absence, because a deliberate omission with no test gets re-added by the next
      person who reads a doc
    - ⭐ **THE DROWNED (2026-08-17)** — the zone's searchable content, added after J-capture #5
      (*"the flood sublevel even though looks very cool feels very empty"*). **Six half-submerged
      objects** (`sunken_item.gd`), one per room, each a different silhouette built from parts —
      footlocker · ward gurney under a sheet · drawer bank · suitcase · tool chest · wheelchair.
      Each **knocks** while its fragment is still outstanding (`flood_knock`, `unit_size 6`, every
      5–11 s) and is **silent forever** once emptied: a to-do list you clear by ear, so the wing
      gets audibly emptier as you work it. ⚠️ **TWO PRESSES since 2026-08-17** (playtest capture
      005: *"Why the note appears just after I open the cabinet - I need to collect this note"*).
      E hauls it open (`flood_haul`) and reveals a **fragment lying in it** — no page, no journal
      entry, nothing else; a second, separate E lifts the fragment, and the page arrives then.
      `lab_cabinet_drawer.gd`'s beat. ⚠️ Which of the two nested bodies answers the ray is decided
      by STATE, never by aim — and because this body is on layer 1 (it is furniture) it cannot be
      made transparent to the ray, so while a fragment is present **both** targets take it. ⚠️ **Found by EAR, not by light** — a glinting object would
      argue with the zone's own tell, and a self-lit one is anti-pattern §5.2(8). ⚠️ **ZERO panic,
      no fail state, no new rule**; measured, a full six-object search costs **+11 of `PANIC_MAX`
      at worst** (36.7 s of wading × 0.3) against 37.5 points of headroom, and reading is free
      because `NoteUI` pauses the tree. ⚠️ **Nothing in the Sump** (it holds the real seam — a
      knock there would be a bearing to the exit) and **nothing in the Cistern** (it holds the
      beartrap — anti-pattern §5.2(11)); both asserted. The **Basin** object stands 2.7 m from the
      Basin decoy seam on purpose: lighting the room to look at what you hauled out shows you the
      decoy coming on and the real seam going out, in the same second, with nothing said
    - **Three events on the FRAGMENT count** (they keyed on the lid until 2026-08-17; an object
      standing open with its fragment still in it is not done), all channels rather than numbers:
      **1/6** every
      remaining object answers with one knock (the invitation — otherwise a player who searches the
      first thing they trip over never learns there is a set); **3/6** THE SURFACING — `flood_haul`
      once, 5–13 m away, *the same sound the player has just made three times*, which is `SCARY.md`
      P10's stated anchor and the only place in the game where the player performs an act
      distinctive enough to be echoed (no entity, no mesh, no repeat, and **not** the `UnseenWader`,
      which is untouched); **6/6** the wing is emptied — drips halve permanently, all eight water
      beds settle −3 dB for good, and one last knock lands ~3.5 m behind you from a wing with
      nothing left in it to knock. Emptied objects are recorded in `save_progress()`, so a
      back-door return does not re-fill the wing with knocking
    - Two non-teach HOLD apparitions (`Apparition.spawn`, `Rule.HOLD`, `teach=false`): one in the Throat,
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
  - ⭐ **…AND SINCE 2026-08-18 THE LEVEL SAYS SO, ONCE, IN THE SPAWN ROOM** (`_spawn_briefing_notice()`,
    the user's call on backlog H5). That premise used to be stated **nowhere in the game**: the only
    place the principle appeared was the banishment scrawl, which fires *after* a wrong door — i.e.
    only to the players who have already lost a level to it. `NoticeBriefing` hangs on the Landing's
    north wall, east of the doorway, facing back at the player as they materialise, and reads
    **YOU WERE BRIEFED ELSEWHERE.** over *NO COPY IS HELD ON THESE PREMISES.*
    - ⚠️ **A PRINCIPLE, NEVER A PLACE, and it is asserted rather than intended.** It names no gate,
      no answer, no earlier level and no room — `check_kontur_signs.gd` scans its text against every
      gate's operative word plus the room names read out of the scene's own `ROOMS` table, with
      three positive controls (a colour, a number, and a room name taken from the scene). This is
      `kitchen_drawer.gd`'s rule-not-a-position discipline applied to the whole level
    - ⚠️ **Nothing gets easier.** Zero panic, no rule, no gate, no trigger volume. What changes is a
      stuck player's *reading*: "I am missing something in this room" becomes "I should have read
      more", which are opposite behaviours in a level with no decay
    - ⚠️ **It is BOTH a wall notice and a `note.gd` page, and both halves are load-bearing.** The
      target reader is the one who rushed, and a statement they must walk up to and press E on is a
      statement they will skip — so the ART carries the principle, measured legible at **17.1 px of
      cap height from the player's own spawn 7.10 m away** (floor 15). The note body carries the
      full memo and archives it via `GameState.record_note()`, because the principle is worth
      re-reading two gates later. `corridor.gd:_spawn_nightmare_plate()` is the same pairing
    - ⚠️ **It is NOT a ninth gate sign.** It carries **no censor bar** (asserted, the mirror of the
      eight signs' own assertion), a different form series (1-А) and a different shape
      (1500×1300 against the signs' 1500×1000), so it cannot read as a rule the player failed to
      decode. `tools/make_kontur_notice.py` generates it; `check_kontur_signs.gd` still asserts
      there are exactly **eight** redacted signs, so it cannot quietly join them
    - ⚠️ **The hero line is three words because of arithmetic, not taste.** For a plate of fixed
      width the achievable cap height is ≈ `1.06 × width_m / longest_line_chars` — the aspect is
      irrelevant, only the width and the character count bind. At 1.70 m wide, "ELSEWHERE." (10)
      gives 17.1 px at the spawn; "YOU WERE BRIEFED" (16) would have given 12.6 and been unreadable
      from exactly where it is meant to be read
- **Visual arc = the story**: peeling Soviet wallpaper (`kontur_wallpaper_soviet`) → raw infected
  concrete (`kontur_concrete_infected`, the `CONCRETE_ROOMS`) → clinical KONTUR tile
  (`kontur_facility_wall`, the `FACILITY_ROOMS`, which reuse `lab_floor`/`lab_ceiling`). Done entirely
  with `RoomBuilder`'s per-room `wall_mat`/`floor_mat`/`ceil_mat` overrides in `_rooms_with_skins()`
- **Gate 1 — THE TWO DOORS** (`choice_door.gd`, *choose*): a black and a red door in the vestibule.
  Which side is black is **randomised per run**, so the answer is the colour, never a position. The two
  doors open into **two separate antechambers**, and `_open_the_void()` deletes the floor behind the red
  one — the wrong door is a **hole**, not a decoration. Hint: hidden note in the **Lab morgue**
  - ⚠️ **BOTH LEAVES WERE 1.571× SQUASHED AND BOTH TEXTURES WERE A PICTURE OF THE CONCRETE WALL AROUND
    THEM** (K-T1, fixed 2026-08-18) — Issue 35 / X24's sixth recurrence, on the one prop in the game
    whose entire task is telling two things apart, and where a wrong answer does not cost a strike but
    drops the player through the floor and demotes them a level. `tools/crop_kontur_art.py` crops both
    to the leaf (`door_{black,red}_leaf.png`); the originals stay as the crop's only input.
    ⚠️ `ChoiceDoor.HEIGHT` is now **DERIVED**: `WIDTH` 1.4 is fixed by the doorway, `LEAF_ASPECT`
    0.7485 is the mean of the two crops, and `HEIGHT` = 1.87. ⚠️ **Both doors must stay the same size**
    or the SHAPE becomes a second tell alongside the colour, so a single constant serves both and
    `_build()` warns if a texture drifts more than 8 % from it
- **BANISHMENT** (`_check_void_fall` → `_banish`, threshold `y < −4`): falling out of the world does not
  kill you, it **demotes** you. `GameState.kontur_banished` is set (it survives the transition because
  `reset_level_state()` deliberately doesn't clear it, the same trick `is_ending` uses), `current_level`
  drops to 4, and `backrooms.gd:_check_banishment()` greets you with a blood-red scrawl — *"YOU DIDN'T
  READ. THE COLOUR WAS WRITTEN DOWN SOMEWHERE YOU DIDN'T LOOK."* — then clears the flag so it shows once
- **Gate 2 — THE SHELF** (`bottle_item.gd` + `fungal_barrier.gd`, *use*): three bottles (vinegar /
  bleach / water) on the kitchen shelf, and a fungal mass sealing the way on. Vinegar dissolves it
  (canon: acetic acid retards O-41); a wrong bottle is **consumed**, so a bad guess costs a walk back
  as well as a strike. Hint: the **House TV** static resolves into a KONTUR test card every ~16–26 s
  - ⚠️ **THE THREE BOTTLES WERE THE SAME CYLINDER WITH A 1.733× SQUASHED WORD ON AN OPAQUE BACKDROP**
    (K-T2, fixed 2026-08-18). All three labels shipped as 8-bit **RGB** on a `TRANSPARENCY_ALPHA`
    material, i.e. each bottle wore an opaque rectangle of the generator's studio background — the
    vinegar bottle was carrying a bright yellow flag. `tools/crop_kontur_art.py` keys those backdrops
    into real alpha (`label_*_paper.png`) and the label quad is sized from the artwork, with a floor on
    its width because scaling purely off the body radius gave the slim flask — the RIGHT bottle — the
    smallest word on the shelf. ⚠️ The bottles also gained distinct silhouettes via
    `BottleItem.PROFILES`: **flask** (tall, slim, corked, dark green) / **jug** (squat, shouldered,
    handled, opaque) / **carboy** (short, wide, wide-mouthed). Issue 35 applies to a shelf as much as
    to a bed — three identical cylinders read as three identical cylinders at any distance where the
    words are not yet legible. ⚠️ **This changes nothing about the answer**: shape says nothing about
    which agent retards O-41, and a player who never found the House hint still guesses and still pays
    a strike. ⚠️ `BottleItem.build_visual()` is `static` and excludes the collider, because the
    Perëkozhnik wears one of these as a disguise and a mimic must be built from the SAME geometry as
    the thing it imitates
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
  answer. ⚠️ **There are exactly EIGHT of them, and the Landing's briefing notice is deliberately not
  one** — it carries no censor bar and its own artwork name, and `check_kontur_signs.gd` asserts both
  the count and the difference. ⚠️ **They are REAL PRINTED DOCUMENTS since 2026-08-18** — eight generated notices
  (`tools/make_kontur_signs.py`, Pillow, deterministic) with an oxblood `К.О.Н.Т.У.Р.` head band, a
  form number, the rule set in type, a censor bar **struck into the image** and a Russian
  counter-signature. The old `Label3D`-over-`kontur_sign_blank.png` and the separate black bar quad are
  gone. **The redaction being baked is the strongest form of it**: the operative word is never rendered,
  so there is no layer to peel and nothing that can drift out of alignment with the bar.
  ⚠️ **THEY WERE UNREADABLE AND NOBODY HAD MEASURED IT.** These are the level's only in-level help, and
  from the line a player actually walks the rule's cap height was **5.1 px on the gate-1 sign and under
  9 px on five more** at 1080p. Three things fixed it, all driven by the measurement: the gate TITLE
  dropped to a kicker and the RULE became the hero; the line break is chosen by trying 1, 2 and 3
  balanced splits and keeping whichever yields the largest type that still fits its leading (a
  word-count rule left "APPROVED AGENT: DOMESTIC" on one 24-character line at 13.3 px); and the plate is
  **1.4 × 2.1 m**, sized from the artwork's own 1.5 aspect. Worst sign now **15.7 px**, best 63.2, floor
  15. `check_kontur_signs.gd` finds the ink by thresholding rows of the imported texture — never a
  constant shared with the generator, which would agree by construction — and converts through the quad
  size, the camera's own FOV and the reading distance; its control stamps the rule back at a quarter
  height and requires the same measurement to call it unreadable. ISSUES_SOLUTIONS **145**,
  cross-level **X55**. ⚠️ Emission is **0.40 with `EMISSION_OP_MULTIPLY`**, not 0.55 with Godot's
  default ADD — an emission colour beside an emission texture lays a flat wash over the artwork
  (Issue 81 / X30), and the card is a mid-tone printed sheet now rather than a near-blank plate.
  ⚠️ `wall_point()`'s inset is measured from the room's NOMINAL boundary, but the wall's inner face
  is `T/2` (0.1 m) in from that — so clearance = `inset − 0.1`. An inset of **0.10 is exactly
  coplanar** and z-fights (it sliced the morgue poster apart); below that the plate is buried
  (Issue 11). `wall_point()` now clamps to a 3 cm minimum clearance itself (Issue 26), so 0.16 is
  still the house style but no call site can get it wrong. Props needing depth behind them —
  `LivingMirror` hangs its figure 0.05 behind the glass — need **0.22**
- ⭐ **The Perëkozhnik** (`creature_shapechanger.gd` + `mimic_shell.gd`): a billboard mimic that
  **wears an ordinary prop until you touch it** (2026-08-18). It never moves or chases and is **not** a
  gate — it feeds gaze panic and kills only within `KILL_DIST=2 m`. Its 16 panic/s stare is
  **deliberately** faster than the three-strike budget (see the `⚠️ DELIBERATE` note on
  `GAZE_INTENSITY`); it exists to punish the one instinct this level otherwise rewards: walking up to
  something for a better look
  - ⚠️ **THE DISGUISE ADDED NO RULES AND CHANGED NONE.** `GAZE_INTENSITY` 0.8, `KILL_DIST` 2.0, "never
    moves", "not a gate" — all untouched. Its name means *shapechanger* and for its whole life it was a
    static billboard in the Passage's west corner that a player who never swept a torch there simply
    never met. It now stands at one of `MIMIC_SITES` — **a fourth bottle on the kitchen shelf** or **a
    second phone on the switchboard desk** — drawn per run and **restored, never re-rolled**, on a
    back-door return (K-T6's rule applied to the level's third randomisation)
  - ⚠️ **THE TELL IS A COUNT, and it stays wrong for as long as you care to look.** The kitchen has
    three shelf slots and four bottles, two of them wearing the same label, and the fourth stands off
    the three-slot rhythm at z=21.9. The switchboard has two phones and **only one of them is
    ringing** — and the ringing one is the gate. A mimic with no tell is a coin flip
  - ⚠️ **LOOKING AT THE DISGUISE COSTS NOTHING.** `MimicShell` is a **sibling** of the `ScaryObject`,
    never a child (`player.gd:_find_scary_object()` walks UP from the collider it hit), and the
    figure's gaze collider is `disabled` while disguised. In the one level with no decay at all,
    charging 16/s for reading four labels would be indefensible
  - ⚠️ **IT CANNOT COST A GATE AND CANNOT KILL YOU WITH THE TOUCH THAT REVEALED IT.** The shell is not
    a `BottleItem` and not a `RotaryPhone`: E consumes no bottle, spends no strike, answers nothing and
    smashes nothing. You interact from ~1 m and `KILL_DIST` is 2 m, so the figure is revealed at a MARK
    ≥ `REVEAL_MIN_DIST` 3 m away with line of sight — it does not walk there, the disguise simply stops
    being true, and from that moment it stands still forever exactly as before. The mark is validated
    by **rays only** (floor, headroom, a 16-ray fan at the figure's own half-width, and the LOS ray,
    which is the member of the set that catches "inside a wall" — Issues 40/59), and if nothing fits
    the figure is **skipped** and the disguise just vanishes. ⚠️ That validation runs 0.6 s after
    `_ready()`, not inside it: CSG colliders are not registered during `_ready()` (Issue 52), so rays
    fired there hit nothing and approve everything
  - ⚠️ **ZERO panic on the reveal** — a sound (`perekozhnik_shed`, gain +10.2 dB derived from its
    measured −21.88 dBFS RMS against `door_seal`'s −11.67) and a 0.08 camera jolt. No `add_panic`, no
    `flash_scare`, no strike
  - ⚠️ Its billboard is **sized from the cutout** now (K-T4). The canvas was 1024×1536 on a 0.9×1.9
    quad — a 1.407× squash — and measured on the alpha channel the FIGURE inside it was a man 1.64 m
    tall and **0.38 m wide**. The quad is sized so the figure lands at `FIGURE_H` 1.78 m and dropped by
    the transparent margin under its boots; the gaze collider wraps the figure, not two thirds of empty
    canvas
- ⭐ **OBJECT 12, CONTAINED** (`containment_cell.gd`, 2026-08-18): the level is named after it and the
  player never saw it, while the very next level is *Object 12, loose*. A steel-and-glass isolation
  booth stands in the **Passage** at `CELL_POS (2.75, 0, 16.9)` with the Breach's own
  `Void_creature.glb` inside it, wearing `creature_object12.gd`'s palette — that is the feature, not a
  shortcut: meeting it here and being hunted by it one level later have to be recognisably the same
  thing
  - ⚠️⚠️ **HUE SHARED, LEVEL SCALED (revised 2026-08-18) — it used to be "retinted EXACTLY", and the
    picture that produced was a pale beige smiling man in a suit.** `SPECIMEN_ALBEDO` and
    `SPECIMEN_EMISSION_COLOR` are still that script's colours verbatim and are marked not to be
    re-picked; `SPECIMEN_DIM` (0.45), `SPECIMEN_EMISSION` (0.16) and `SPECIMEN_SPECULAR` (0) are
    this level's. ⚠️ **`material_override` was reaching every mesh** — one `MeshInstance3D`, override
    set, no `AnimationPlayer` — so CLAUDE.md's own standing Mixamo warning was the wrong hypothesis
    and is disproved in writing. **The same material is not the same picture**: the Breach meets this
    creature across a lit facility, KONTUR meets it at 1.5 m with a 1.2-energy torch on it in a room
    lit at 0.45. Measured, the shipped material rendered **1.8–2.8× brighter than what was behind it
    and 4.1–4.5× brighter than the booth's own steel**, with a hotspot clipping to 0.98. Setting the
    three constants back to `1.0 / 0.35 / 0.5` makes it byte-equivalent to the Breach's again.
    ISSUES_SOLUTIONS **Issue 147**
  - ⚠️ **DARKENING ALONE CANNOT WORK, AND THAT IS THE GENERAL LESSON.** Sweeping the albedo down, the
    occupant reaches parity with its background at ~0.30 and passes under it at ~0.22 — but the
    measured contrast there is **0.006–0.09**: it goes invisible before it goes dark. `watcher.gd`'s
    premise is *a dark shape OCCLUDING A LIT SURFACE* and this booth had no lit surface in it. The
    three interior faces the player can never reach are now **backlit liners** — `LinerEast` (an
    opaque panel replacing the east pane, which stands 0.15 m from the Passage wall and is
    unreachable) plus one-sided `QuadMesh` panels `LinerNorth` and `LinerSouth`. ⚠️ Emission
    illuminates nothing in this project (no GI, no glow), so a liner raises the BACKGROUND without
    touching the figure, which is the whole reason it works
    - ⚠️ **The north/south panels are ONE-SIDED (`CULL_BACK`) and both obvious builds failed.** A
      *frosted backlit pane* lays its emission over everything behind it, so from the north the same
      veil landed on the figure and on the wall alike — contrast 1–3 %, i.e. it made the occupant
      invisible from four headings it had been fine at, and lifted the whole frame 0.05 → 0.25. A
      *four-slab inner door liner carrying the same port opening* backed the figure everywhere except
      behind the figure, because the occupant stands at exactly the height the hole is. One full
      panel facing +z, drawn from the north and culled at the port, solves both
  - ⚠️ **THE DOOR HAS AN OBSERVATION PORT, AND UNTIL 2026-08-18 IT DID NOT.** Three faces are glazed
    and the fourth (−z) is a steel leaf which `_spawn_containment_cell()` deliberately turns to face
    the spine — so the level's one look at its own title creature was staged to face the direction it
    could not be seen from. Measured over 23 reachable poses, **six rendered ZERO pixels of the
    occupant** (the whole 165°–210° arc, at 2.0 m and 3.2 m). The leaf is now four slabs around a
    1.32 × 0.95 m glazed opening (`PORT_W`/`PORT_Y0`/`PORT_Y1`) with a bead frame and two glazing
    bars; the wheel, mid-rail, chevron band and placard all moved, having every one of them been
    sitting inside what is now the opening. ⚠️ It also fixes the *"flat luminous white panel"* the
    same capture shows — that was the torch on the only large untextured flat plane in a corridor
    whose walls carry texture, and the port is what breaks the plane. ISSUES_SOLUTIONS **Issue 148**
  - ⚠️ **The glass is `roughness` 0.22, not 0.08.** At 0.08 the pane is a mirror and the torch put a
    near-pinpoint glare on it which, because the player faces the booth head-on, landed **on the
    occupant's chest** at 0.90 luminance. It was diagnosed as a highlight on the creature twice; it
    survives `metallic_specular = 0`, an albedo of pure black, emission off, and the flashlight
    switched off entirely
  - **Measured after the pass, 23 reachable headings, occupant against what is directly behind it over
    one identical eroded pixel mask:** every heading shows it (7 097–67 169 px, was 0 at six of them);
    occ/bg **0.52–0.77** (was 0.36–2.79, brighter at seven); contrast **0.231–0.483**; whole-frame mean
    0.048–0.104 against 0.043–0.058 before, so the backlighting did not turn the booth into a lantern
  - ⚠️ **`tests/check_kontur_entities.gd` now asserts that it can be SEEN**, which is the gap that let
    all of the above ship: 143 assertions about what the prop does *not* do and not one about the
    picture. Headless half — every renderable carries the published `occupant_material()`, albedo,
    emission and specular under documented ceilings, no `AnimationPlayer` playing, and line of sight
    from **every** reachable heading (12 body points, ≥3 clear, segment/AABB against the booth's
    opaque solids), with a live control that plugs the port and requires ≥4 headings to go blind.
    Photometric half — **`tests/screenshot_cell_visibility.gd`**, which needs a display and is
    therefore outside `run_tests.sh` like every `screenshot_*`. ⚠️ Its mask is built with the glass
    HIDDEN and the levels read with it back: an alpha-blended pane perturbs on every pixel when the
    occupant is hidden, so a naive diff mask picks up the whole pane including the ceiling fixtures
    seen through it
  - ⚠️ **NO RULES AT ALL** — the `watcher.gd` contract verbatim: no `ScaryObject`, no gaze panic, no
    kill radius, no `Screamer`, no trigger volume, no `interact()`, **zero panic**. The occupant has no
    collider; the booth has one. It turns its head to follow you at `TRACK_RATE` 0.9 rad/s and that is
    the whole thing
  - ⚠️ **IT MUST NEVER BECOME A PURSUER.** `SCARY.md` §8.4 is one chase level in twelve and that level
    is 6. If a future session wants this to open, it is a new level, not an edit
  - ⚠️ **IN THE PASSAGE BECAUSE THAT IS THE THINNEST ROOM ON THE SPINE**, and deliberately not in a
    gate room: gate 1 is at z=10 and gate 2 at z=27, so the seven metres between them were the longest
    stretch of the level with nothing in it. It is something you come upon, never something a puzzle
    points at. The Perëkozhnik used to stand in this room's west corner and now wears a disguise
    elsewhere, so the Passage is exchanging a billboard nobody reliably saw for something on the
    walking line
  - A positional field hum (`object12_cell`, `HUM_DB` −18 derived from the file's measured −10.87 dBFS
    RMS, `unit_size` 7) gives it a bearing before it is seen. The glass is dark and **not emissive** —
    a lit pane hides what is behind it, which is the prop
- ⭐ **THE RECOVERY ARCHIVE** (`_spawn_recovery_archive`, 2026-08-18). The Archive's own objective line
  is *"RECOVERY ARCHIVE — DO NOT DISTURB THE INVENTORY"* and its wall sign says *"ITEMS RECOVERED FROM
  AN OBJECT ARE: ▮"*, and it was a 9 × 9 m room containing one black box. Two aisle racks and **six
  numbered lots**, five holding something from a level the player has already crossed — ward bedding,
  a defeated isolator handle, a wound music box, room plate **217**, a handset with the cord cut — and
  **the sixth EMPTY, with the player's own subject number on the card** (`LOT 23-Z · SUBJECT 47 —
  PENDING`). Plus an inventory ledger, a real `note.gd` page on the west wall
  - ⚠️ **ZERO RULES**: no `interact()` on any lot, no `ScaryObject`, no panic, no sound, nothing to
    take. Nothing about it may become a gate — gate 3's whole test is walking past a recovered item
  - ⚠️ **FREE-STANDING AISLE RACKS, not wall racks.** The Archive's two long walls already carry the
    poster and the redacted sign at their centres; a wall rack would simply hide both. The measured
    narrowest lane in the room is **4.00 m** against a 0.80 m capsule (`check_kontur.gd` measures it
    with rays and a point query, never `intersect_shape` — a capsule centred on a CSG box comes back
    clear, Issue 40 — and drops a full-width slab in to prove the probe can report a blocked room)
  - ⚠️ It is what closes **K-T5**: `check_note_mounting.gd` collected **0 props, 0 notes** on the level
    with the most wall text in the game, and the fix was a page the room wanted rather than widening
    the collector (which would have made all eight redacted signs "notes" for the same-room separation
    pass). ⚠️ **This item was built before the user's design direction for this pass arrived** and is
    flagged for their call in `backlogs/05-kontur.md` §3 A1; removing it is one call site, and it
    re-opens K-T5
  - ⚠️ Every lot card is `LotCard_<kind>`, not `LotCard` — six siblings with one literal name and Godot
    renames five of them (Issue 17, third time in this file). And the cards use the LOT's rotation, not
    its negation: `Label3D` is double-sided, so a card facing into its own rack still renders, mirrored
    and unreadable
- **Cyrillic signage and hazard stencils** (`_spawn_stencils`, `_spawn_floor_markings`, 2026-08-18):
  every room on the spine carries a stencilled Russian designation high on a wall (`Л-1 ЛЕСТНИЦА`,
  `У-5 УЧЁТ`, `Ш-9 ШЛЮЗ` …) and the three thresholds where the protocol changes its mind about you
  carry painted hazard bands on the floor. ⚠️ **Paint, not signs** — dark-tinted `Label3D`s and unlit
  ochre quads, so they cannot be confused with the eight NOTICES, which are the level's only actual
  help. ⚠️ `FLOOR_MARK_Y` is **0.03**, the Corridor's own `FLOOR_DECAL_Y`: 0.02 sits exactly on
  `check_wall_overlap.gd`'s 2 cm minimum and `AABB.has_point()` includes its boundary, which is how
  every flat decal in the Corridor got reported the first time that guard was pointed at it.
  ⚠️ **Not one of them says anything about a gate** — a stencil that hinted would put an answer inside
  a level whose whole premise is that the answers are somewhere else
- **Objectives never state an answer** — `GameState.set_objective()` runs in protocol register
  ("PROTOCOL 4-B — PROCEED TO THE MARKED EXIT", "DECONTAMINATION REQUIRED", …)
- ⚠️ **THE LEVEL'S RANDOMISATIONS ARE RESTORED, NEVER RE-ROLLED — AND SO IS THE WORLD THE LEDGER
  DESCRIBES** (K-T6 + K-B1, fixed 2026-08-18, ISSUES_SOLUTIONS **141**/**142**). `save_progress()` had
  written `"dark_x"` since the day the snapshot was added and **nothing ever read it back**, while the
  gate-1 colour was not saved at all — so a back-door return restored the eight-gate ledger and
  re-rolled the answers underneath it, which is the exact failure this file already warned about.
  `_preload_snapshot()` now runs as the FIRST line of `_ready()`, before `_build_geometry()` and
  `_spawn_gate1_doors()` consume the dice; it restores `dark_x`, `gate1_black_east` and `mimic_site`,
  and warns rather than silently re-rolling if it meets an older snapshot
  - ⚠️ **AND `_reopen_passed_gates()` IS THE HALF THAT MATTERED MORE.** `_ready()` rebuilds every
    physical seal on every load and `_restore_progress()` restored only the ledger. Three of those
    seals stand across the spine, and `AirlockSeal` is **unrecoverable by construction**:
    `_tick_airlock()` opens with `if _gates["airlock"] … return`, so the one path that can free it is
    switched off by the flag the restore just set. A player who cleared gate 8, walked back for a note
    and returned was **walled in at z=66 with the exit 32 m beyond it** — a soft-lock reachable by
    using a door the game provides. The restore now opens the black door
    (`ChoiceDoor.open_instantly()`), dissolves the barrier, frees the roster seal, frees the airlock
    seal and its whole marker widget, and silences the phone (`RotaryPhone.mark_smashed()` — both
    methods additive and default-preserving; the Backrooms' two phones never call it)
  - ⚠️ The general rule this encodes: **a ledger and the world it describes must be restored together**,
    and the test is not "does the flag come back" but "having come back, can the player still finish".
    `check_kontur_resume.gd` drives a real advance→go_back cycle with a DIFFERENT seed pinned before
    the return, passes gates 1 and 2 through the shipping `ai_interact()` ray, and carries two
    permanent controls. With the fix disabled it goes red ten ways
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
- ⭐ **Waking is a video since 2026-08-17** (`dungeon_wake.ogv`, played by `_after_blackout()`): a
  slow crane up out of darkness into the Antechamber's firelight and heavy studded door — the
  reward for seven sconces. ⚠️ **The two directions are no longer symmetric and that is accepted,
  not unfinished.** `dungeon_sleep` was never generated, so going under keeps its 1.6 s fade; going
  under is a choice the player makes and should not be taken off them for ten seconds, while waking
  is the payoff and is worth the screen. The `into_dungeon` branch of `_after_blackout()` is
  byte-for-byte the old behaviour and is where a sleep clip would go
  - ⚠️ `_finish_transition()` gained an `unfreeze := true` parameter and the wake path passes
    **false** — it hands control back on its last line, which would leave the player walking around
    behind ten seconds of video. The teleport still happens under full black, before anything shows
  - ⚠️ **The clip opens AND closes on black, and BOTH fades are added in post** — the raw clip opens
    lit and ends lit (`assets_src/README.md`). The in-fade is what lets it cut from the level's
    fade-to-black. The **out-fade is the one that was not predicted, and a hard cut was built and
    measured wrong first**: the reasoning was "the clip's last frame IS the Antechamber, so there is
    nothing to hide", and `tests/screenshot_wake_cutscene.gd` photographed both sides of the join
    and returned **0.171 mean luminance against the live room's 0.008 — a 21× snap**. A generator
    lights a stone interior like a film set; this level runs at ambient 0.045 with no flashlight and
    an unlit candle, so the Antechamber at that moment is a black room with a red door in it.
    Handing over ON BLACK, onto the level's own black `ColorRect`, then lifting it, is what works
  - ⚠️ **The lesson generalises to every remaining clip in `VIDEO_PROMPTS.md`:** match the join's
    LUMINANCE, and measure it — a cutscene's last frame and the live frame behind it are lit by two
    completely different systems, and the discontinuity is invisible while reasoning about it
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
Final door loads back to the intro room — **corrupted** (`_corrupt_room()` in `intro_room.gd`, fires when `GameState.is_ending`): candle dead, slow blood-red throb light, exit door replaced by planks (no way forward), harsh cold spotlight pinning the new note to the table, extra cobwebs, low whisper loop. Closing the note → **1 s in the corrupted room → `ending_scene.ogv` → `Screamer.trigger_to_menu()`**.
- ⭐ **The reveal is a video since 2026-08-17** (`_on_ending_note_closed()`): a slow pull back off a wall of CRT monitors showing every empty room in the institution, with motionless figures in lab coats watching them, one of whom turns to look at the camera. It closes the loop the Lab's Observation tape opens, and it replaces what was previously *a bare two-second pause*. The whole payoff of eight levels used to be a note and a still JPEG
- ⚠️ **The 1 s beat before it is deliberate.** The note overlay covers the screen, so the red throb and the planked door are all the player has actually seen of the corrupted room; cutting straight to video spends a room nobody looked at. The no-video fallback path restores the original 2 s exactly
- ⚠️ **The clip ends on black by construction**, because `trigger_to_menu()` fires the instant it finishes. Veo delivered only 0.70 s of black; the shipped `.ogv` pads it with `tpad` (`assets_src/README.md`). ⚠️ **The pad buys less than the arithmetic says**: the cloned frames are identical, Theora run-length-codes duplicates, and **Godot stops at the last decoded frame rather than the container duration** — 1.3 s of padding bought 0.26 s, for **0.96 s of black actually on screen** against `ffprobe`'s nominal 1.46. That clears the real requirement (do not end on a lit frame). If it is ever regenerated, re-measure with `signalstats` — the tail is invisible by eye — and never compute a cutscene's playback length from a container field
- Both cutscene paths have a harness: `tests/screenshot_ending_cutscene.gd` and `tests/screenshot_wake_cutscene.gd`. ⚠️ They run **without `--headless`** (`CutscenePlayer.play()` returns null there by design, which is what keeps the suite green) and so are not in `tools/run_tests.sh`. ⚠️ Both key their samples to `VideoStreamPlayer.get_stream_position()`, never to a wall clock — the ending one photographed the *screamer* and reported it as "the clip's last frame" twice before that was fixed
- ⚠️ `player.freeze_input()` is not cosmetic: the mouse is captured and `CutscenePlayer` is opaque, so without it the player walks blind around the ward for ten seconds with footsteps playing

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
| 1 Lab | which breakers (by node name), power, locker unlocked/moved, keycard, scare one-shots, **and the Records bank's randomised hint slot + which drawers were left open** |
| 2 House | map solved, key carried, cellar open, code entered, scare one-shots |
| 3 Corridor | furthest path distance reached (there is no puzzle state — the level IS the walk) |
| 4 Backrooms | which of the three zones, the loop counter, which of the Flood's six searchable objects have been emptied, **and the plate's state — fragments set and fragments still in hand** (restoring one without the others strands the player in a wing with silent objects and an empty frame) |
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

## Code Architecture

### Autoloads (global singletons, survive scene transitions)
Registered in `game/project.godot`. Access directly by name from any script.

| Autoload | File | What it owns |
|----------|------|-------------|
| `GameState` | `scripts/game_state.gd` | Level state (`current_level`: 0=intro, 1=lab, 2=house, **3=corridor, 4=backrooms, 5=kontur, 6=breach, 7=nightmare, 8=void, 9=ending**), `has_keycard`, `level2_code_correct`, `twist_read`, `is_ending`, `intro_note_read`, `apparition_taught`; `advance_level()` / `go_back()` / `restart_current_level()`; `go_to_main_menu()`; `load_audio(base_name)`. **Also owns the two cross-level systems added for BACKLOG #30:** `level_progress` (per-level snapshots — see below) and `journal` + `record_note()`. `set_objective()` / `set_carried()` drive the two HUD lines. |
| `Screamer` | `scripts/screamer.gd` | `trigger()` — black flash → screamer image → audio burst → scene reload. `process_mode = PROCESS_MODE_ALWAYS` (must not freeze during tree pause). `_is_triggering` / `_is_flashing` bools guard `trigger()`, `trigger_to_menu()` and `flash_scare()` against re-entry. **Per-level fatal AV**: `_apply_level_av()` picks the image + scream by `GameState.current_level` from `LEVEL_SCREAMERS` (1 lab `screamer_lab`, 2 house `screamer_house`, 3 corridor `screamer_hotel`/`screamer_corridor`, 4 backrooms `screamer_smiler`/`jumpscare`, 5 kontur `screamer_kontur`, 6 breach `level_6_jumpscare` — image **and** audio, user-supplied 2026-07-27, replacing the generated `screamer_breach` pair; the `.jpg` is real JPEG data so it imports fine, unlike the Issue-25 JPEG-named-`.png` trap — 7 nightmare `screamer_dungeon`, 8 void `screamer_void`); intro/ending fall back to a random `screamers/` `.png` (DirAccess scan at startup) + the shared `jumpscare`. **`flash_scare(image_path, audio_base, hold)`** — a SURVIVABLE scare: fullscreen image + sound for `hold` s, no pause/restart (the caller adds its own panic). Used by the House forest scare, the Corridor Manager, and the Corridor turn mirrors. |
| `NoteUI` | `scripts/note_ui.gd` | Fullscreen note overlay. `show_note(text, trap_rate := 0.0)` / `is_open` bool. ⚠️ Its footer reads **`[ Press E to close  ·  TAB anywhere — recovered documents ]`** (2026-08-16) on an IMMUTABLE label of its own — nothing writes to it, per `combination_lock.gd`'s lesson that a feedback line must never double as the instruction line. `JournalUI` had shipped for several sessions with **no mention anywhere in the game**, and the 2026-08-16 playtester asked for a notes journal as a NEW FEATURE while standing in front of an open note with the feature running. "anywhere" is load-bearing: TAB is refused while a note is open, so an instruction to press it *here* would be a lie. Built entirely in GDScript — no .tscn. Guard `is_open` in player before any interaction logic. While `trap_rate > 0` and the note is open, feeds `player.add_panic()` per frame and tints the text toward red; auto-drops the overlay if the tree unpauses (= a screamer fired) |
| `JournalUI` | `scripts/journal_ui.gd` | **TAB** — re-read any note already found. ⚠️ **The list takes keyboard focus on open (`focus_mode = FOCUS_ALL` + `grab_focus()` AFTER `_root.visible = true`), and the TAB/ESC close handler lives in `_input()` with `set_input_as_handled()`, not in `_unhandled_input()`** (2026-08-16, Issue 70, reported in two consecutive playtests). `ItemList.select()` neither emits `item_selected` nor takes focus, and `focus_mode` defaults to `FOCUS_NONE`, so the arrows did nothing until a click. And the fix has a trap: TAB is `ui_focus_next`, which the GUI layer consumes before `_unhandled_input` the moment ANY Control has focus — `grab_focus()` alone would have made the journal impossible to close. Two-pane overlay (level-grouped list + text), built entirely in GDScript like `note_ui.gd`, `PROCESS_MODE_ALWAYS`, pauses the tree, carries the Issue-9 self-drop guard. `can_open()` refuses while `NoteUI.is_open`, while the tree is already paused, or while `player.is_input_frozen()` (a free pause mid-QTE). ⚠️ **Trap notes are never archived** — `note.gd` only calls `GameState.record_note()` when `not is_trap`, because a safely re-readable copy would let the player learn a read-to-die note's text at no cost. |

### Key scripts
| Script | Responsibility |
|--------|---------------|
| `player.gd` | `CharacterBody3D` movement, raycast interaction, gaze timer (3s stare → fail), **panic system** (`_panic` float, `PANIC_MAX=50`, `PANIC_BASE_RATE=20/s`, `PANIC_DECAY_RATE=3.5/s`, `GAZE_RANGE=3.0m`, `INTERACT_RANGE=3.0m` — raised from 2.5 on 2026-08-15 alongside five collider fixes; the two now match, and reach equals the distance an instant-fail trigger object already gazes from), flashlight toggle (`toggle_flashlight` action, F), heartbeat audio tied to panic ratio. **Sprint** (`sprint` action, Shift): ×1.6 speed, +6 panic/s while sprinting (suppresses decay), faster footsteps. **Flashlight battery**: 240 s per scene (`BATTERY_MAX`), dying-bulb stutter below 48 s, dead = can't re-enable. Zone API: `add_panic(amount)` (instant spike, screamer at max), `apply_slow(duration)` (speed ×0.45), `cancel_slow()` (clears limp instantly — used by beartrap escape), `jolt_camera(strength, duration)`, `enter/exit_calm_zone()` (decay ×2.5), `enter/exit_dark_zone()` (+3 panic/s with flashlight off), `enter/exit_dread_zone()` (decay 2/s + constant 2/s pressure), `get_panic_ratio()`. **Backrooms-only opt-ins** (off by default everywhere else): `enable_standstill_panic()` (+3/s after 4 s still), `enable_footstep_echo()` (phantom step 0.4 s behind), `kill_flashlight()` (force off; F only clicks), `set_smiler_active(bool)` (suspends standstill + dark ticks for the Smiler), `is_flashlight_on()` / `is_sprinting()`. **Input actions** (`project.godot`): `interact` E · `move_*` WASD · `toggle_flashlight` F · `sprint` Shift · `debug_capture` J · `push_effort` **Space** (the Lab locker's mash) · `journal` **TAB** (the notes journal). ⚠️ `player.gd` also exposes a small **test-only** control surface — `ai_active` / `ai_move_dir` / `ai_sprint` / `ai_look_at()` / `ai_interact()` / `ai_interact_target()` — because Godot's `Input.parse_input_event()` does not work headless, so an automated test cannot press a key. `_apply_movement()` and the sprint check are the only two places that read `Input`, and both take their value from here when `ai_active`; everything downstream (gravity, collision, the interact RAYCAST, `can_interact()`, panic) is the shipping path. ⚠️ The interact ray sets **`hit_from_inside = true`** (2026-08-15): layer-2 interact volumes are non-solid so the player walks through them, and the moment those volumes were given real depth, standing in a doorway put the camera inside the box and the prompt vanished at the closest range. ⚠️ `_update_interact_prompt()` consults an optional **`can_interact()`** on the raycast hit before showing "Press E" or setting `_interact_target`, so a prop can be completely inert rather than merely refusing (see `LabLocker`). ⚠️ `freeze_input()` blocks movement **and** look — `_apply_movement` and `_unhandled_input` both early-return on `_input_frozen` — so anything polling `Input` directly during a freeze must do so from its own `_process`. ⚠️ A freeze does **not** stop the body: `_physics_process` still calls `move_and_slide()`, so a caller that freezes a walking player must zero `velocity.x/z` itself or they coast (Issue 49; `level_1.gd`'s nook reveal does). ⚠️ **`turn_to_face(target, time)`** (2026-08-16) is the production camera-aim: it tweens yaw AND writes `_pitch`, which is why `ai_look_at()` cannot be used for a scripted beat — that one sets `camera.rotation.x` only, and `_rotate_camera()` re-applies `_pitch` on the next mouse motion, snapping the view back. ⚠️ **A LOCKED torch and a DEAD torch no longer make the same sound**: F on a locked-but-charged light plays `switch_clunk` via `_play_locked_click()`, not the flat-battery `light_pop`. The Lab's wing locks the torch for ~100 s and the 2026-08-16 player, hearing the dead-battery pop once, walked the remaining 306 s of the level without it — through the DarkZone morgue, where they died. ⚠️ `begin_qte()` / `end_qte()` / `_qte_active` are the MOVEMENT-ONLY pin (`beartrap.gd` is the only caller): `_apply_movement()` zeroes `velocity.x/z` and returns, while look stays free — see the beartrap row for why zeroing rather than returning is the whole fix. ⚠️ `_ready()` also clears `MIRROR_ONLY_LAYER` (20) from `camera.cull_mask` for EVERY level, which is what keeps `mirror_surface.gd`'s figures visible only in reflections |
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
| `rotary_phone.gd` | `class_name RotaryPhone` — rings (`rotary_ring`) on a timer; `interact()` answers → `phone_whisper` + a read-to-die trap note via `NoteUI.show_note(text, 11.0)`. Self-building primitive mesh. **BUG_FIX.md 4.6**: gained `@export smashable`/`signal smashed`/`_smash()` — when `smashable` (KONTUR only, default off), `interact()` smashes instead of answering, stopping the ring for good; Backrooms' own phone is unaffected. `build_visual()` is `static` and collider-free so the Perëkozhnik can wear a phone as a disguise; `mark_smashed()` is the silent resume path |
| `maze_kit.gd` | `class_name MazeKit` (Session 14) — static geometry primitives shared by the three Backrooms zones: `box/slab/wall/light_strip/zone_box` + the wall/floor/ceiling materials. Extracted from `backrooms.gd`. ⚠️ Keep `make_material`'s **negative V** uv scale — a positive `uv1_scale.y` renders wallpaper upside-down |
| `glitch_wall.gd` | `class_name GlitchWall` (Session 14) — the walk-through exit surface. `setup(size, height, is_real, tex)`, `signal touched(is_real)`, `go_solid()` (an outed fake becomes ordinary wall), `revive()`, `set_seam_visible()` (hides the **whole node**, not just the mesh — Node3D visibility is inherited and the Area3D keeps monitoring regardless). ⚠️ **`set_armed(false)` is a different thing from invisible** (2026-08-17): it stops the trigger monitoring as well, which is what lets the Flood withhold its exit until the plate is assembled — an unearned seam must be untouchable, not merely unlit. ⚠️ `set_agitated(true)` raises the shader's own `tear_amount` 0.12 → 0.34: the Sprawl's mark, chosen because it is MOTION and brightness was never available on a surface already 2.3× brighter than its room. ⚠️ **`set_sealed(true)` is a THIRD state and not `set_armed(false)`** (2026-08-18, the Sprawl's crate gate): the wall keeps its mesh, its shader and its tearing, stops monitoring, and gains a `SealBody` collider — so it looks exactly like its neighbours and walking into it does nothing. It has to be a collider rather than a hidden node because `backrooms_zone2.gd:_side_runs()` cuts a 7 m gap in the perimeter for each wall, i.e. **in that zone the wall IS the shell**, and hiding it is a hole in the world with no floor behind it |
| `silence_zone.gd` | `class_name SilenceZone` (Session 14) — Zone 2's tell. Ducks the `"Backrooms"` audio bus to −30 dB while the player is inside. Restores the bus in `_exit_tree()` so a teleport-out never leaves the level permanently silent |
| `backrooms_zone2.gd` / `backrooms_zone3.gd` | `class_name BackroomsZone2` / `BackroomsZone3` (Session 14) — the Sprawl and the Flood. `build(origin)` / `build(origin, player)`, `signal cleared` + `signal mistake`; the level owns the consequences |
| `room_builder.gd` | `class_name RoomBuilder` (Session 10) — procedural room-graph: `build(rooms, doorways)` where room=`{name,pos:Vector2,size:Vector2,h?, wall_mat?/floor_mat?/ceil_mat?}` and doorway=`{pos,width,dir:"x"\|"z",h?}` → CSG floor/ceiling/walls, **floors auto-bridged under every doorway** (kills the Issue-5 void-fall class). Applies its own materials; the optional per-room `*_mat` keys (Session 11) override them so a Morgue/Kitchen/Bathroom reads as a distinct place (`level_*.gd:_rooms_with_skins()`). Helpers: `room_center/size/height`, `wall_point(room,side,y,inset)`, static `make_material()`. Doorways open EVERY wall on their plane, so connected rooms must ABUT (share a wall plane). Used by `level_1.gd`, `level_2.gd` + `kontur.gd`. ⚠️ `make_material()` **negates V itself** (`Vector3(x, -absf(y), x)`) — callers pass a positive scale. A positive `uv1_scale.y` renders walls upside-down: the wainscot lands at mid-wall and the lower half reads as a mirrored duplicate (Issue 19). ⚠️ Floor bridges are sunk by `BRIDGE_SINK` (4 mm) because their top face is otherwise coplanar with every room floor — the doorway z-fighting/flicker of Issue 20. ⚠️ Wall dedup subtracts **intervals** per (axis, plane, height), not exact spans: abutting rooms of different depths emit walls on the same plane with different spans, and building both put two coincident slabs in the same place — one room's texture bleeding through another's, the "merging textures" bug (Issue 23). ⚠️ Rooms in a `ROOMS` table must ABUT, never OVERLAP, or their floor/ceiling slabs coincide too. `tests/check_wall_overlap.gd` asserts all of this |
| `mirror_surface.gd` | `class_name MirrorSurface` (2026-08-15) — **the first thing in this project that actually reflects.** A `SubViewport` + a `Camera3D` placed at the player camera reflected through the mirror plane; the viewport texture becomes the quad's albedo. `attach(quad)` converts an existing quad, so the Corridor keeps its `ScaryObject → StaticBody3D → QuadMesh` hierarchy (the ScaryObject must stay an ANCESTOR of the collider or gaze panic dies). ⚠️ **OFF-AXIS FRUSTUM since 2026-08-16** (`_aim()`): the camera points along the mirror NORMAL, never along the mirrored player heading, and `set_frustum(quad_height, offset, near, far)` makes the near-plane window the quad's own rectangle — a mirror is a WINDOW, and its frustum is the pyramid from the virtual eye through the glass's four corners. It previously inherited the player's symmetric 75° fov and stretched the result onto the pane, minifying the reflection **1.93×–3.34×** at the two positions the player photographed, and by a factor that *moved with distance*. ⚠️ **The near plane is load-bearing**: the virtual camera sits behind the glass, inside the wall, so without clipping at the mirror plane the reflection renders as black masonry with a strip of sky — with `set_frustum` the window plane IS the near plane, so that is structural rather than maintained by hand. ⚠️ The `SubViewport` is sized from the quad's aspect (it was a fixed 512×768 against a 0.718 pane) and the material flips U, because a proper camera basis hands the image the wrong way round and a real mirror does not swap sides. ⚠️ Proximity-gated (`UPDATE_DISABLED` beyond `ACTIVE_DIST`, **7 m since 2026-08-17**, was 14) — each active mirror is a second scene render, and that distance is also an **audible** beat: `corridor.gd:_tick_mirror_wake()` fires `mirror_wake` at exactly `ACTIVE_DIST`, because the switch to `UPDATE_ALWAYS` is the moment the glass comes alive. The user asked for the mirror to appear much closer; moving the gate rather than the sound keeps the two married, doubles the pane's on-screen size at the moment it wakes, and **halves** the render cost (53.00 m of the walk → 25.00 m, `probe_mirror_cost.gd`). ⚠️ **`_aim()` takes the eye POSITION only, never its heading** — a mirror is a fixed window, so turning your head must not move the image. That is the answer to the *"it used to move, now it is static"* report: the old code passed the whole player transform through the plane and the reflection panned with the mouse at 0.022 U per degree. See the ⚠️ block above `_aim()`, which carries the full before/after table. ⚠️ Reserves `MIRROR_ONLY_LAYER` (20); `player.gd:_ready()` clears that bit from the player camera for EVERY level, so a `Watcher` on that layer appears only in the glass — the corridor behind you is empty and the mirror disagrees. The Corridor also switched to a **black background** (`_black_background()`), the same fix the Lab and House already use, because a mirror is the only thing that could ever see the procedural sky |
| `apparition_director.gd` | `class_name ApparitionDirector` (BACKLOG #6) — decides WHEN the shared apparition appears, for every level that wants one. Randomised gap + fairness suppression + the global teach ledger; `static arm()` is the single entry point for making a HOLD apparition materialise. See the Random Apparition section |
| `cellar_gate.gd` | `class_name CellarGate` (BACKLOG #16) — the House's boarded cellar door. Self-building planks/lock/slab, `interact()` emits `used`, and `level_2.gd` decides whether the player is carrying the key. Same prop-emits / level-decides split as `fungal_barrier.gd`. One body on layer 1: it must both block movement and answer the interact ray, and the ray uses the default mask, so the two-body Issue-30 split is unnecessary here |
| `journal_ui.gd` | `class_name`-less autoload — the notes journal. See the autoload table |
| `apparition.gd` | `class_name Apparition` (Session 10) — the random monster. `Apparition.spawn(parent, rule, pos, teach)`; `RULE_HOLD` = appear-ahead, survive by not sprinting; `RULE_STARE`/`RULE_LOOKAWAY` reuse stalker/smiler. See "Random Apparition" above |
| `lab_locker.gd` | `class_name LabLocker` — the steel locker sealing Level 1's Records breaker. Self-building `BoxMesh` body + art `QuadMesh` + collider; `@export unlocked` (set by the Observation note's `read` signal) gates `interact()`, which otherwise only toasts a refusal. Opens a SPACE-mash tug-of-war that does **not** pause the tree (`beartrap.gd`'s idiom: poll `Input` in `_process`, HUD `CanvasLayer` parented to the level), plants the player on a brace mark, and travels `TOTAL_TRAVEL 1.10 m` in three stages — two 0.14 m lurches that keep the panel covered, then one 0.82 m slide that reveals it → `signal moved`. See the Level 1 write-up for the two gates and the `ARM_DELAY` gotcha |
| `lab_cabinet.gd` | `class_name LabCabinet` (2026-08-16) — a Records filing cabinet built from PARTS (plinth, carcass, top overhang, four drawers, handles, card holders), flat-tinted and untextured per Issue 35. **The cabinet has no `interact()` of its own** — it is a carcass that hosts four `LabCabinetDrawer`s. `assign_note(text, slot)` / `note_slot()` / `open_slots()` / `open_slot_instantly()` / **`close_slot()`** / `mark_note_taken()` are the level's handles, used by `level_1.gd:_place_flood_hint()` and by `save_progress()` |
| `lab_cabinet_drawer.gd` | `class_name LabCabinetDrawer` (2026-08-16) — one drawer, and the reason the bank is a search. Layer **2** / mask 0 (`note.gd`'s convention) so a drawer sliding 0.34 m into the room can never shove or trap the player. One press opens it and one press **closes it again** (Issue 67 — an open drawer shadows every slot below it); an empty one costs nothing and **says nothing at all** — the empty tray is the message (2026-08-16). The page inside the one that matters is a nested `NotePaper` body with its own `interact()` — open, see, then take. ⚠️ `_refresh_layer()` is the single source of truth for which of the two answers the ray, and it is decided by state rather than by aim. ⚠️ Its interact volume is 0.08 m deep: see Issue 65 |
| `lab_wing_meter.gd` | `class_name LabWingMeter` (2026-08-16) — ⚠️ **DELIBERATE exception to `GAME_MECHANICS_IDEAS` §5.2(2)**, on the user's explicit call. The Lab dark wing's "PANEL HUM" scale. `setup(rooms, doors, wing_room_names, target, target_room)` builds a doorway graph and runs Dijkstra; `path_distance()` / `signal_strength()` are public so tests assert the numbers rather than pixels. ⚠️ **Path distance, never Euclidean** — that is the whole difference from the widget Issue 34 deleted |
| `note.gd` | …also emits `signal read` on `interact()` — the generic "this note was opened" hook the project lacked (the only prior per-note state was the bespoke `GameState.twist_read`). Fires on OPEN, not on `NoteUI.closed`: reading-to-the-end is a mechanic reserved for trap notes. `level_1.gd` uses it to unlock `LabLocker` |
| `breaker.gd` | `class_name Breaker` (Session 10) — Lab power switch; `interact()` flips once + emits `flipped` + clunk (`breaker_throw`). The panel is **never** emissive (Issue 33); `@export var glows: bool = true` now gates only the lever indicator at `INDICATOR_EMISSION = 0.12` — set `false` for BreakerNook's breaker so it stays genuinely invisible in the dark. **2026-08-16:** the state colour moved off the handle onto a **recessed pilot lamp** (a dark bezel standing proud with the lens sunk ~2 cm inside it, so it only shows its colour to someone roughly in front of it) and the handle became dark moulded plastic with a collar — captures #3/#4 photographed a saturated red block glued onto a photographic panel. Also gained `@export blocked` + `unblock()` + `can_interact()`: while blocked the breaker is COMPLETELY inert, and that — not the locker standing in front of it — is what gates the Records panel (Issue 57) |
| `living_mirror.gd` | `class_name LivingMirror` (Session 10) — one-way mirror; a figure shows in the glass only when the player is NOT looking head-on (`LOOK_DOT=0.8`) + gaze panic (ScaryObject). **Seeds `body.global_transform = global_transform`** — without it the ScaryObject-chained collider sits at the world origin (an invisible wall; the bug fixed in Session 10). ⚠️ **`fit_to_art` (2026-08-17) sizes both quads from their own artwork and DEFAULTS TO FALSE.** The glass art is a 1.250-aspect landscape observation window and the mesh was a 0.667 portrait quad — a **1.874× stretch**, in all three levels that use this prop, plus 1.141× on the figure. Only `backrooms_zone2.gd` opts in: turning it on is a visible change (portrait → landscape at the same diagonal, 1.2000×1.8000 → 1.7994×1.4400) and the Lab and House are closed levels. Their halves are D11 in `backlogs/04-backrooms.md`; each is one line. ⚠️ Do not make it the default without taking that decision — the fix is correct in all three, the question is when |
| `kontur.gd` | Level 5 — KONTUR. Builds the 13-room spine via `RoomBuilder`, the Soviet→facility skins, the level-wide `DreadZone` (the no-decay economy), all **eight** gates + their printed redacted signs, the Perëkozhnik's disguise, Object 12's containment cell, the Recovery Archive, the Cyrillic stencils, props and doors. Owns the strike counter (`_strike()`), the `_gates` ledger + `_refresh_exit()` (the exit stays sealed until all eight pass), `_forfeit()`, `_open_the_void()`/`_check_void_fall()`/`_banish()` (the wrong door drops you a level), and — since 2026-08-18 — `_preload_snapshot()` / `_reopen_passed_gates()`, which are what stop a back-door return re-rolling the answers or rebuilding a seal that can never be opened again (Issues 141/142) |
| `screen_text.gd` | `class_name ScreenText` — shared transient on-screen text: `toast()` / `caption()` / `scrawl()` (blood-red, slightly rotated — the project has no handwriting font, so the tilt does the work). Replaces five hand-rolled CanvasLayer+Label helpers. ⚠️ Always parents to the tree root and cleans up via a **connected**, never awaited, tween — an awaited timer dies with the node that started it (Issue 6) |
| `audio_buses.gd` | ⚠️ **`reset_all()` runs on EVERY level load** (`GameState.start_current_level()`, 2026-08-15). AudioServer buses are process-global and survive `change_scene_to_file`; `ensure()` early-returns without touching a volume; and every per-level bed nests under `Ambience`. So one level that ducks a bus and forgets to restore it silences **every level after it for the rest of the session**. That is not hypothetical: `corridor.gd:_tick_hush()` pulled `Ambience` to −40 dB at 296 m with no restore, which is why the Backrooms had no music when entered from the Corridor but did when loaded directly. `check_bus_leak.gd` drives the real transition and asserts the arrival. `ensure_music_bus()` is the escape hatch for a SCORE that must survive a duck — sent to Master, not nested. `class_name AudioBuses` (2026-07-28) — the minimal runtime bus layout: `Master → Ambience` (duckable) and `Master → Body` (heartbeat + footsteps, **NEVER ducked**). `ensure_core()` is called from `GameState._ready()`, so both exist before any scene. ⚠️ **Per-level bed buses NEST under `Ambience`** (`backrooms.gd`, `dungeon.gd`), so a level's own `SilenceZone` duck and a global `HoldBreath` dip compose instead of competing. Deliberately NOT `SCARY.md` §4.1's five-bus `.tres` — the project has never had bus config in `project.godot` and this follows the existing runtime pattern |
| `hold_breath.gd` | `class_name HoldBreath` (SCARY.md P5) — `HoldBreath.dip(tree, hold)` ducks `Ambience` to −30 dB, holds, restores. Wired as a **0.6 s pre-duck inside `screamer.gd:flash_scare()`**, which improves every survivable scare in the game at once. ⚠️ Fire-and-forget, never awaited — awaiting would delay the image by the whole dip. One dip per bus at a time (`static _active`), `PROCESS_MODE_ALWAYS`, and restores in `_exit_tree()` |
| `watcher.gd` | `class_name Watcher` (SCARY.md P3) — a distant motionless figure with **no rules at all**: no `ScaryObject`, no collider, no kill radius, no `Screamer`, no fail state, **no emission**. `spawn(parent, pos, tex, vanish_within, require_los, height, tint)`. Used by the Corridor doorway, the House cellar and the Sprawl's Congregation. ⚠️ Clearance by **rays only** (Issue 40). ⚠️ `require_los=false` is for `congregation.gd` ONLY — the LOS ray is also what catches "inside a wall", so it may only be dropped by a caller whose candidates cannot be inside geometry. ⚠️ **`figure_tint` (2026-08-17) is ADDITIVE and defaults to white**, i.e. every existing caller renders byte-identically. It exists because the header's own premise — "a dark shape OCCLUDING a lit surface" — is a **constant albedo against a variable background** and inverts wherever the ground is darker than 44/255; measured in the Sprawl the "shadow" was lighter than the floor (cross-level X36). It is a tint, never an emission |
| `moved_prop.gd` | `class_name MovedProp` (SCARY.md P6) — wraps any `Node3D` and applies a stored delta once, while the player is >6 m away and facing elsewhere. No sound, no event, no panic, no acknowledgement. `arm()` / `apply_now()` (the restore path) / `is_applied()`. ⚠️ Register applied moves in `save_progress()` or a back-door return un-moves them. ⚠️ Only `_advance_guest()`-style tracked callers may attach: attaching twice for one stage DOUBLE-APPLIES the delta (it put the House chair outside the building) |
| `congregation.gd` | `class_name Congregation` (2026-07-28) — Backrooms Zone 2's occupants: 6–8 persistent `Watcher`s among the 36 pillars, growing by one per wrong wall (capped at 12). **Zero panic, no rules.** A figure relocates only when it is BOTH out of view and ≥15 m away **and lands somewhere out of view and ≥15 m away**, so it never moves on screen and never pops at arm's length; `SETTLE_MIN`/`SETTLE_MAX` then hold it there 8–16 s so the field has a state worth remembering. ⚠️ The destination half was **missing until 2026-08-17** and 10.3 % of 633 measured relocations landed on screen (Issue 85) — read that entry before touching `_pick_spot()`. ⚠️ Legal under §8.3 because there is no fail condition for gaze to depend on — looking at one does literally nothing |
| `sunken_item.gd` | `class_name SunkenItem` (2026-08-17) — THE DROWNED, the Flood's searchable content. Six different silhouettes built from parts, half-submerged, **dark and never emissive**; each knocks (`flood_knock`) **while its fragment is still in it** and is silent forever once emptied, so the wing is emptied by ear. ⚠️ **TWO PRESSES**: E hauls it open and reveals a fragment; a second, separate E takes it and the page arrives then. ⚠️ The knock gate is `is_taken`, **never** `is_searched` — that one word is the safety net that makes the Flood's mandatory six-fragment search legal. ⚠️ **Zero panic, no fail state.** ⚠️ The visuals move, the collider never does (Issue 76), and the reveal fires from the lid tween's `finished`, never two statements after `create_tween()` (Issue 58) |
| `flood_plate.gd` | `class_name FloodPlate` (2026-08-17) — the Flood's assembly point: a trestle table with a six-recess frame in the Basin, where the six fragments become the exit. `set_carried()` / `seat()` / `restore()`; `signal set_requested` + `completed`, and the ZONE owns the consequence. ⚠️ It must **announce itself** — the lit room, a written instruction on a pale board, and a two-layer tell armed by the first fragment — or "the middle of the level" is a second thing to hunt for. ⚠️ **`max_db` is the near-field ceiling and `unit_size` is the gradient** (Issue 112). ⚠️ Zero panic, no fail state, no timer, and it is genuinely INERT while you carry nothing |
| `sprawl_crate.gd` | `class_name SprawlCrate` (2026-08-17) — the Sprawl's box in the dark, replacing one featureless `AlcProp` cube (Issue 35; the player photographed the cube). Slats, corner posts, banding and a lid, flat-tinted and **never emissive**: it is found by EAR. Carries the two-layer `sprawl_call_far`/`_near` whisper on **Master** until it is opened, then hands both emitters to `SprawlDweller`. ⚠️⚠️ **Since 2026-08-18 that whisper is a COMPLETABILITY GUARANTEE** — the crate is the gate, so the loop has no timer, no one-shot, no distance gate and no stop path, and its six gain constants were re-derived against the level's own bed after they measured **3.2 dB UNDER the score with the player's nose against the box** (Issue 131). ⚠️ Zero panic in the file — the level fires a survivable `flash_scare` and adds nothing |
| `sprawl_dweller.gd` | `class_name SprawlDweller` (2026-08-17) — the one-shot runner: it comes out of the crate, crosses the hall and goes **through the real glitch wall**, which is how the player learns which of the four is real. ⚠️ **NOT a `Watcher` and never a Congregation figure** — those are ruleless by construction and that is what keeps the Congregation legal beside a Smiler. ⚠️ No collider, no `ScaryObject`, no kill radius, no `Screamer.trigger()`; it cannot touch you. ⚠️ Unshaded billboard sized from `sprawl_dweller.png`'s own aspect, and that file must stay a real RGBA cutout. ⚠️ **The run starts one `flash_scare` hold AFTER the crate opens** and announces itself (`BackroomsZone2.dweller_running`), because `backrooms.gd` pins the player's camera to it with `turn_to_face()` and a run started under a fullscreen image is one nobody sees |
| `unseen_wader.gd` | `class_name UnseenWader` (SCARY.md P10) — the Flood's threat that is **never instantiated**: no mesh, no collider, no `ScaryObject`, no kill radius. A `wade_distant` loop on a `Tween`, always ≥12 m away, patrolling the room graph's centres. ⚠️ **When the player stops wading it stops too — after two more, decelerating strides.** The zone drives `set_player_wading()`; it never samples the player itself, so the two cannot disagree about when the player halted |
| `house_fridge.gd` | `class_name HouseFridge` (2026-07-28) — the House kitchen's fridge and the **only new panic term** in the atmosphere pass (10, voluntary, one-shot). Hums to earn the approach; on `interact()` the scream fires first, the door swings `DOOR_DELAY` later, the head is revealed as it clears. `can_interact()` returns false once used, so it never advertises a prompt that does nothing. ⚠️ Carcass is an open-fronted **shell of five slabs** — a solid `BoxMesh` hides everything inside it (Issue 46). ⚠️ No `flash_scare`: a fullscreen image fired over the reveal it was announcing |
| `kitchen_drawer.gd` | `class_name KitchenDrawer` (2026-07-28) — a searchable counter drawer holding a **second, independent hint for KONTUR Gate 1**. Slides open on E, then shows its note and archives it via `GameState.record_note()` so TAB can re-read it two levels later. ⚠️ States the RULE (black is the way out), never a position — `choice_door.gd` randomises the colours per run. ⚠️ **Only the `DrawerSlide` child moves; the `CollisionShape3D` stays flush with the counter** (Issue 76 — tweening `self` put a solid 34 cm into the Kitchen and closed the only lane past the counter). Built from a front, two sides, a bottom, a back and a handle, or a 34 cm slide out of a flat counter reads as a plank in mid-air |
| `music_box.gd` | `class_name MusicBoxProp` (2026-07-29) — the child's music box, windable with E: the crank turns and the tune swells out of the room tone for ~22 s, then settles back rather than stopping dead. Re-windable, no resource, no fail state. ⚠️ The `AudioStreamPlayer3D` is a CHILD of the box body — that is the only reason THE GUEST's last stage works, because the sound travels with the object |
| `false_exit_door.gd` | `class_name FalseExitDoor` (2026-08-17) — the Corridor's fake room 217, at the d=185 corner. Self-building leaf on `ajar_door.gd`'s skeleton (hinge on the BACK FACE, art on `QuadMesh` faces), wearing `hotel_door_217.png` — the level's ORIGINAL exit art, cropped to the leaf with its brass plate redrawn 1.55x. `interact()` swings it and emits `opened`; `corridor.gd` owns the flash, the panic and the `IT WAS AN ILLUSION` scrawl. ⚠️ One-shot: `can_interact()` false afterwards, and the leaf stays open on bare wallpaper as the only lasting record. ⚠️ Not a `FakeDoor` and not `door.gd` — see the Level 3 write-up |
| `ajar_door.gd` | `class_name AjarDoor` (2026-07-28) — the Corridor's six former decal doors as real hinged bodies. `swing_ajar(deg, time)` opens **silently** (a creak would make it an event instead of a discrepancy); `slam()` is the one that is heard. No `interact()` — the player cannot open these, which is what makes an ajar one evidence. Built on `choice_door.gd`'s skeleton (hinge at origin, art on `QuadMesh` per Issue 24) rather than `door.gd`. ⚠️ **`WIDTH` 0.97 is DERIVED from `hotel_door_leaf.png`'s aspect** and moves with it; ⚠️ the hinge is on the leaf's **back face**, so swinging can only move wood into the corridor — with the old centre hinge the rear corner swept 6.4 cm behind the plane and the level had to hold every door 9 cm off the wall to make room (Issue 79). The architrave is built by the LEVEL, not here: a frame parented to a rotating leaf swings with it |
| `choice_door.gd` | `class_name ChoiceDoor` — KONTUR Gate 1. Self-building hinged door panel; `@export is_correct/texture_path`, `signal chosen(correct)`, swings open on `interact()`; `open_instantly()` is the resume path (no tween, no signal, marks `_used`). The level owns the consequence. **ISSUES_SOLUTIONS Issue 31**: art lives on `QuadMesh` faces front/back of the hinge box, not on the box itself — the box direct-texture version rendered a magnified crop (Issue 24 recurrence). ⚠️ `HEIGHT` is **derived** from `LEAF_ASPECT`, which is the mean of the two cropped leaf artworks, and both doors share it so the shape cannot become a second tell (K-T1) |
| `kontur_mailbox.gd` | `class_name KonturMailbox` — KONTUR Landing's mailbox. **Rebuilt 2026-07-25** (capture #4) from one box + a photo decal into a real 12-slot bank: the old art had the wallpaper baked into its background, so the prop's own texture depicted the wall behind it and could never read as 3D (Issue 35). `kontur.gd:_spawn_mailbox()` now builds carcass/plinth/top-overhang, a divider+shelf grid and twelve numbered slot doors with handles and card holders, all flat-tinted and untextured — the `intro_room.gd:_build_wheelchair()` precedent. **Only slot 12 opens**: the level hands the script a `door_hinge`, and the first `interact()` swings it before `NoteUI.show_note(hint_text)`, so the note reads as having come out of the box. ⚠️ **That was false until 2026-08-16** — the tween was started and the note shown on the next line, and `show_note()` PAUSES THE TREE, so the Tween never got a frame and the door swung only once the player closed the note (measured: hinge at **0.0°** when the note appeared; **105° of 105** after the fix). The note now fires from the tween's `finished`. ISSUES_SOLUTIONS **Issue 58**. ⚠️ The slot is also **STIFF** now (the user's call): `PRESSES_NEEDED = 3` — two tugs that groan and shift the door a few degrees before it springs back, then one that gives. No bar, no timer, **no fail state**; `LightSwitch.presses_needed`'s idiom, not `lab_locker.gd`'s tug-of-war. A rapid second press must COUNT, so the stick tween is killed and restarted rather than the input being swallowed |
| `house_map_prop.gd` | `class_name HouseMap` — the Bathroom's folded map prop, on a stool built from parts (`_build_stool`, 2026-08-16 — it was one flat grey cube, and it is the frame the "Collect the key." payoff is delivered in; Issue 35); `interact()` opens its child `MazeChaseUI`, `signal won`, owns the catch consequence (`jolt_camera` + `add_panic(CATCH_PANIC)`) and a `_solved` one-shot guard, same division of labor as `key_item.gd`/`kontur_mailbox.gd` |
| `maze_chase_ui.gd` | `class_name MazeChaseUI` — the House map-and-chase minigame itself (**16×9 BRAIDED** randomized-DFS maze, BFS target/monster placement, drag physics, wall-slide collision, panic drip, two monsters, snares, a looping chase track). ⚠️ **TWO-STAGE since 2026-08-16**: collect the fragment(s), then reach the mark, which is inert until then — `_place_fragments()` places them on a **monotone-outward** tour (never backtracking, never in a dead end) and validates its length into `TOUR_BAND`, and `_place_patroller()` bands the second monster off `_route_cells`, which now means the whole tour; `_is_won()` is the only win predicate. `CanvasLayer` + `PROCESS_MODE_ALWAYS` + `get_tree().paused`, same convention as `combination_lock.gd`/`note_ui.gd`; `signal won` / `signal caught`. See the House level write-up above for full mechanics |
| `RandomAmbient` | `scripts/random_ambient.gd` | ⚠️ **`set_once_per_type(true)` caps each event to once per level — OPT-IN, and only the Corridor uses it** (2026-08-15). At ~300 m the Corridor is the longest walk in the game, so an 18-35 s metronome cycled the same three sounds many times over ("too many repeating sounds… falling painting"). Opt-in because this autoload is global and the other levels are balanced against the repeat. **Global ambient-scare metronome, and a real part of every level's panic budget.** `register_player(p)` (each level calls it in `_ready()`), then every `MIN_INTERVAL`-`MAX_INTERVAL` seconds it plays one of `floor_creak`/`painting_fall`/`half_scream` at a random point within 4 m of the player and adds **5 / 8 / 12 panic** respectively. ⚠️ Was **5-10 s** until 2026-07-26 — a scare every ~7 s forever, in all eight levels, with `half_scream` alone worth 24% of `PANIC_MAX`. Two playtest logs were wall-to-wall with the resulting spikes and the player read it as a creature repeatedly appearing beside them. Now **18-35 s**. It is GLOBAL: retuning it changes ambient pressure everywhere at once, so check here first when a level's difficulty shifts for no local reason |
| `DebugLog` | `scripts/debug_log.gd` | Playtest instrumentation. Writes `user://playtest_log.txt`; polls position/panic/flashlight every `POLL` (0.5 s) and logs panic only when it moves more than 18 points between samples — so a slow ramp never appears and every logged jump is a real spike. `J` (`debug_capture`) saves a screenshot plus a typed note. `record_death()` is called directly from `Screamer.trigger()` || `bottle_item.gd` | `class_name BottleItem` — KONTUR Gate 2. Self-building glass bottle + label quad; `@export kind/label_path`, `signal taken(kind)`. Layer 2 / mask 0 like `note.gd` so the shelf line isn't walkable-into |
| `fungal_barrier.gd` | `class_name FungalBarrier` — KONTUR Gate 2. The O-41 mass sealing a doorway; `setup(size, tex)`, `signal sprayed`, `dissolve()` (drops the collider FIRST, then tweens, so the player is never trapped mid-tween) |
| `offering_pedestal.gd` | `class_name OfferingPedestal` — KONTUR Gate 3. Lit pedestal with a hovering bait keycard; `signal taken` on `interact()`. Abstaining is scored by the level's exit sensor, not here |
| `escort_gate.gd` | `class_name EscortGate` — KONTUR Gate 4. `Area3D`; per-frame check of the camera heading against `forward`, `LOOK_LIMIT_DEG=100`, `COOLDOWN=3.0`, `signal broken`. Drives the `breathing_behind` player pinned just behind the player's head |
| `creature_shapechanger.gd` | `class_name CreatureShapechanger` — the Perëkozhnik. Y-billboard mimic that never moves; gaze panic via the `ScaryObject → StaticBody3D` chain (world transform seeded on the BODY — Issue 10), `Screamer.trigger()` within `KILL_DIST=2 m`. ⭐ **It wears a disguise now** (2026-08-18): `set_disguise()` / `reveal()` / `reveal_mark`, with the shell a SIBLING of the `ScaryObject` and the gaze collider `disabled` while disguised, so looking at a bottle costs nothing. ⚠️ Its rules are unchanged — the four fairness conditions are written out at the top of the file, and the KONTUR section above says why each one is load-bearing. Its quad is sized from the cutout's own FIGURE (K-T4) |
| `mimic_shell.gd` | `class_name MimicShell` (2026-08-18) — the outside of the Perëkozhnik's lie: the geometry of an ordinary prop plus `interact()` → `touched`. ⚠️ Deliberately NOT under the `ScaryObject` (`player.gd:_find_scary_object()` walks UP from the collider it hit), and deliberately WITHOUT a `can_interact()` — a mimic that refused E would be identifiable without touching it |
| `containment_cell.gd` | `class_name ContainmentCell` (2026-08-18) — Object 12, behind glass, in KONTUR's Passage. A steel-and-glass booth holding `Void_creature.glb` in `creature_object12.gd`'s palette. ⚠️ **No rules at all** — the `watcher.gd` contract: no `ScaryObject`, no kill radius, no `Screamer`, no `interact()`, zero panic; the occupant has no collider. It yaws to follow the player at 0.9 rad/s and does nothing else, ever. ⚠️ It must never become a pursuer (§8.4). ⚠️ **HUE shared with the Breach, LEVEL scaled** (`SPECIMEN_DIM`/`SPECIMEN_EMISSION`/`SPECIMEN_SPECULAR`, Issue 147) — the same material under a 1.2-energy torch at 1.5 m is not the same picture. ⚠️ The `-z` face is a steel leaf with an **observation port** in it, because that face is the one the player arrives on and without the port the occupant was invisible from a 45° arc (Issue 148). ⚠️ Three unreachable interior faces are **backlit liners**, two of them one-sided `CULL_BACK` quads — the figure needs a lit surface to be dark against, and darkening it far enough to beat an unlit background makes it invisible first |
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
| `main_menu.tscn` | — | Game entry point; START loads `intro_room.tscn`. **Background is a looping video since 2026-08-17** (`menu_loop.ogv`, a static-camera corridor with one flickering tube) sitting between the still and the 0.78 dark overlay, so the title / blood notes / buttons land on top of it unchanged. ⚠️ `main_menu_bg.png` is NOT dead — it is the fallback layer, shown headless, if the `.ogv` is missing, or if playback silently fails to start (`main_menu.gd` copies `cutscene_player.gd`'s one-frame did-it-start guard). ⚠️ The `.ogv` is a **palindrome** (forward + reversed, `assets_src/README.md`), which is the whole reason `loop = true` is seamless: the last frame IS the first frame. ⚠️ The overlay alpha did not move, and that was measured — the clip's mean luminance is ~60/255 against the still's ~51, i.e. brighter. ⚠️ `_on_start()` frees the player: the START blackout is layer 85 over a layer-1 canvas, so the loop is hidden but would otherwise keep decoding under the whole intro cutscene |
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

**Run this before calling any procedurally-built level done** — it sweeps EVERY level in the game
since 2026-08-17, so the bare command is the whole check; the argument only narrows it:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
  --script res://tests/check_wall_overlap.gd            # all nine scenes, 12 scene-runs
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
  --script res://tests/check_wall_overlap.gd -- Corridor   # …or one, by label or by path
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

### ⚠️ A baked transparency checkerboard is PAINT, and near-white is the brightest paint there is
A supplied cutout that is not RGBA is carrying its background as opaque pixel data. `lab_breaker_panel.png`
shipped as an 8-bit **RGB** PNG whose background was the light two-tone checkerboard an editor draws to
*represent* transparency — 20 % of its texels above 0.90 sRGB — on the one prop in the game whose whole
design is that it cannot be seen. It read as a pale rectangle with a lighter outline from 9.4 m in a
pitch-black room. `tools/flatten_alpha_checker.py` flood-fills that background dark from the image border
(reachability-limited, so it cannot eat a cream label inside the art) and crops. Issue 63; the shape-side
twin of "a billboard texture must be a real RGBA cutout". **Look at a new texture's histogram, not just at
`file`.**

### ⚠️ Measure DARKNESS as contrast, never as an absolute level
"Peak 1.5 of 255, therefore invisible" was wrong twice on the same prop: against a background of literally
0.0000 that patch is the only thing in the frame. Sample the panel's whole screen bounding box, take the
**max** (a thin bright border averages away to nothing), and compare against a ring of the surface around
it. Issue 62. And ⚠️ `unproject_position()` returns **viewport** coordinates while `get_image()` returns the
**rendered** image — 1152×648 against 3024×1701 on this machine — so any probe that mixes them must scale,
or it measures the wrong part of the frame and reports it confidently.

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
│                          ⚠️ PARTLY GITIGNORED since 2026-08-19, and the rule is "does an
│                            automated step read it": the 7 files a tools/ script or a test
│                            takes as INPUT are committed (three make_*.py hard-code their
│                            SRC into this folder, so ignoring them breaks a fresh clone).
│                            Local-only: ALL FIVE video originals (two of them untracked on
│                            2026-08-19 — an ignore rule does nothing to an already-tracked
│                            file, it takes `git rm --cached`), the Veo seeds, reference/,
│                            and every orphan `*_raw.*`. Still tracked: the retired assets in
│                            textures/superseded/ that are not `_raw`.
│                          ⚠️ With VIDEO_PROMPTS.md gitignored too, the five cutscenes are
│                            UNRECOVERABLE from a fresh clone — no source, no prompts, only
│                            the finished .ogv. Deliberate; do not re-derive a clip from one.
│                            Nothing here is loaded by the game at runtime —
│                            every assets_src mention inside game/ is a comment. The table
│                            lives in .gitignore AND assets_src/README.md; keep them in sync
├── backlogs/              ← ⚠️ GITIGNORED ON PURPOSE — local development material, not for
│                            viewers of the public repo (the user's call, 2026-08-19). It is
│                            documented here anyway because a session needs to know it
│                            exists. The level-by-level improvement run (2026-08-16): one
│                            NN-<level>.md per level holding playtest evidence, diagnosis
│                            and costed items, plus 00-cross-level.md (the parking lot for
│                            whole-game issues, written to but never acted on). Indexed
│                            from GAME_MECHANICS_IDEAS.md; rejections cross-post to its §5
├── drafts/                ← superseded docs, annotated rather than deleted (REPORT.md,
│                            IDEA_HISTORY.md, and the KONTUR set archived 2026-08-15)
├── game/                  ← Godot project root (scenes/ scripts/ assets/{audio,elements,
│                            models,textures,materials} — `ls` for the rest)
├── tools/                 ← 23 dev scripts, stdlib-only unless noted: procedural SFX synths
│                         (make_sfx*.py), audio post (make_loop.py), image post
│                         (cutout_alpha.py, restencil_door.py, flatten_alpha_checker.py,
│                         make_arrow_decal.py, crop_kontur_art.py, make_kontur_signs.py —
│                         these need Pillow, so run them with the image pack's venv, see
│                         Image Generation), run_tests.sh
│                         ⚠️ make_arrow_decal.py DRAWS rather than generates: an arrow is a
│                         geometric primitive whose one job is being unambiguous at 15 m, and
│                         no diffusion model can be asked for an exact chevron
├── nano-banana-pro/       ← ⚠️ DEAD (2026-08-15) — the Gemini skill no longer works. Kept only
│                            so old `.md` references resolve. Do not call it. See Image Generation
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

New `.wav`/`.ogg` files need a Godot import pass before `ResourceLoader` sees them: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import` (or open the editor and let the scan run). Corridor SFX (`clock_chime`, `glass_shatter`, `beartrap_snap`, `door_slam`, `whispers`) are generated by `tools/make_sfx.py` (seeded, reproducible); `ghost_house.wav` is the corridor ambience. House SFX (`lock_buzz`, `footsteps_above`) are generated by `tools/make_sfx_house.py` (same stdlib-only conventions). Backrooms SFX (`fluorescent_hum` looping ambience, `light_pop`, `rotary_ring`, `phone_whisper`) are generated by `tools/make_sfx_backrooms.py` into `game/assets/audio/level_backrooms/`. ⚠️ **The seam tell (`seam_draw` far cue + `seam_rip` near confirm) has its OWN generator, `tools/make_sfx_seam.py`** — `make_sfx_backrooms.py` calls `random.uniform` without seeding, so re-running it to add one sound silently rewrites `light_pop`/`rotary_ring`/`phone_whisper` with different noise. `make_sfx_seam.py` is seeded, prints each file's measured RMS dBFS (which is where `backrooms.gd`'s `SEAM_FAR_DB`/`SEAM_NEAR_DB` come from — set a gain from the file, never from a plausible number), and builds both loops seamless by construction: every modulation frequency completes a whole number of cycles in the loop length and the noise beds are generated as circular buffers. ⚠️ **The two Backrooms PUZZLE tells have their own generator too, `tools/make_sfx_backrooms_puzzle.py`** (2026-08-17, seeded, stdlib): `plate_hum`/`plate_ring`/`plate_set`/`plate_done`/`piece_lift` for the Flood's plate table, and `sprawl_call_far`/`sprawl_call_near`/`crate_shriek` for the Sprawl's box in the dark. It prints each file's measured RMS, which is where `flood_plate.gd`'s and `sprawl_crate.gd`'s gains come from. ⚠️ `crate_shriek` is its own file rather than a borrowed scream on purpose: every candidate already in the project belongs to another beat, and reusing a FATAL screamer for a survivable scare teaches the player the fatal sound is free. ⚠️ It was made **+14.6 dB louder on 2026-08-18** (−20.0 → **−5.4 dBFS RMS**, peak unchanged at −1.01 and zero samples at full scale) on the user's call: the file was already peak-normalised and `flash_scare()` takes no gain, so the only lever is the AVERAGE level — sustained envelopes plus a `tanh` soft-clip, which is bounded by construction rather than by a tuned number. Duration deliberately unchanged, because the sting must not outlive the 0.9 s image. **KONTUR SFX** are generated by `tools/make_sfx_kontur.py` into `game/assets/audio/level_5_kontur/` (`ambient_kontur` looping bed, `breathing_behind`, `door_seal`, `acid_hiss`, `pedestal_alarm`, `kontur_flash`, `screamer_kontur`). ⚠️ **KONTUR's 2026-08-18 additions have their OWN generator, `tools/make_sfx_kontur_extra.py`** (`perekozhnik_shed`, the disguise coming off; `object12_cell`, the containment field's seamless loop) — for the reason `make_sfx_seam.py`'s header gives: `make_sfx_kontur.py` seeds once at module scope and writes seven files in order, so appending an eighth changes the RNG stream every later call sees. It prints each file's measured peak and RMS dBFS, which is where `MIMIC_SHED_DB` (+10.2) and `ContainmentCell.HUM_DB` (−18.0) come from. **Corridor mirror SFX** are generated by `tools/make_sfx_mirror.py` — `mirror_wake` (the glass coming alive) **and, since 2026-08-17, `mirror_stare`** (the seamless loop that rises while you stare into it). ⚠️ That file also owns the project's `compress` + `saturate` pipeline: a peak-normalised transient cannot be made louder with a gain, only denser (Issue 101). **The Corridor's false-door scream** is `tools/make_sfx_false_door.py`. **Session 10 SFX** are generated by `tools/make_sfx_extra.py` (uv-venv-friendly, still stdlib-only): `pipe_groan` + `apparition_drone` → `shared/`, `breaker_throw` → `level_1_lab/`, and `tv_static` + `music_box` + `water_drip` → `level_2_house/`. **Level 6 (THE BREACH) SFX** are generated by `tools/make_sfx_level6.py` into `game/assets/audio/level_6_breach/` (`ambient_breach` looping bed, `door_slam`/`door_batter`/`door_break`/`blast_door_slam`, `shield_stagger`/`shield_drain_loop`, `screamer_breach`, `creature_growl_near`); the level's `acid_hiss` reuses KONTUR's file directly via `GameState.load_audio()`'s subdir scan. The user-provided `mystical_sound.mp3` lives here too, as `ambient_breach_layer.mp3` — a secondary ambience layer, never the primary bed (see the Level 6 write-up).

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

## Skills and agents — the parts their own descriptions DON'T say

Skills live in `.agents/skills/`, agents in `.claude/agents/`; both are listed with their
descriptions in every session, so what follows is **only** the rules and history that are not in
that listing.

- ⚠️ ~~`nano-banana-pro`~~ is **DEAD** (2026-08-15) — the Gemini API path no longer works, and the
  skill is now disabled. Use the image pack instead: see **Image Generation**
- ⚠️ `idea-generator` must **not** recreate `REPORT.md` / `IDEA_HISTORY.md` at the repo root; both
  were consolidated into `GAME_MECHANICS_IDEAS.md` on 2026-07-27 and archived to `drafts/`. It
  writes accepted items into §4 and verdicts into §5, and **never implements anything itself**
- ⚠️ `game-tester`, `maze-tester` and `dungeon-tester` are **forbidden from changing difficulty
  constants** — that is always the user's call
- ⚠️ `level-improver` carries the same forbidden list **plus**: no new fail states, no shared files,
  no level renumbering. It cannot talk to the user — it returns `## OPEN QUESTIONS` and the parent
  session relays them
- ⚠️ `tools/run_tests.sh` deliberately routes `autoplay_dungeon` to the `dungeon-tester` agent
  rather than into the suite (it is a difficulty instrument, not a regression guard), which is what
  makes that agent load-bearing rather than optional
- `game-testing` (the SKILL, distinct from the `game-tester` AGENT) holds the log-signature tables
  (panic % → constants), the known false positives, and the verification rules

## Asset Pipeline
- **3D models:** Blender → File > Export > glTF 2.0 (.glb) → `game/assets/models/`
- **Textures:** PolyHaven / AmbientCG (CC0 PBR) or Stable Diffusion → `game/assets/textures/<subfolder>/` (see TEXTURES.md for the per-level subfolder layout)
- **Audio:** Freesound.org (CC0) or MusicGen (HuggingFace) → export as .ogg → `game/assets/audio/<subfolder>/` (`shared/`, `intro/`, `level_1_lab/`, `level_2_house/`, `level_3_corridor/`, `level_backrooms/`, `level_5_kontur/`, `level_6_breach/`, `level_9_dungeon/`, `level_4_void/`) — the full list, and the only list that matters, is `GameState.AUDIO_SUBDIRS`

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
- **Image gen:** the image pack — see **Image Generation** below. Prefer PolyHaven/AmbientCG for standard PBR textures; reserve generation for unique horror imagery (wall art, notes, posters, UI backgrounds) that can't be sourced free elsewhere.
- **Narrative/story:** OpenRouter — `nvidia/nemotron-3-super-120b-a12b:free` via `https://openrouter.ai/api/v1`

## Image Generation

⚠️ **`nano-banana-pro/` is DEAD** (2026-08-15) and its Gemini calls no longer work. The replacement
is Hasan Aboul Hasan's MIT-licensed skill pack at
`~/Downloads/claude-image-generation-main` — kept **outside** the repo (and
named in `.gitignore`) so Godot never imports it and it can't be committed. Security-audited
2026-08-15; the only network calls are Cloudflare and fal.

Provision once (~20 s, Python only — do **not** pass `--with-3d`, the Three.js renderer is
irrelevant here and costs ~500 MB):

```bash
bash ~/Downloads/claude-image-generation-main/setup.sh
```

Two engines, and picking the wrong one is the usual mistake:

| Need | Skill | Why |
|---|---|---|
| Horror imagery — textures, creatures, wall art, screamers, posters **with no words on them** | `level-3-image-generator` — Cloudflare `flux-1-schnell` | One call, free tier, on-theme output. **Unreliable at rendering text** — never ask it to letter a sign |
| Anything with **legible text** — notes, signs, plates, redacted documents, UI | `level-1-image-generator` — Pillow, code-based | The only one that renders readable words. Free and deterministic. Cannot draw a creature; it constructs one from shapes |

```bash
PACK="$HOME/Downloads/claude-image-generation-main"
$PACK/.venv/bin/python3 $PACK/.claude/skills/level-3-image-generator/generate.py \
  "<vivid prompt: subject, medium, composition, lighting, palette>" -o out.jpg
```

Keys come from **this repo's `.env`** (`CF_ACCOUNT_ID`, `CF_API_TOKEN`) — the script walks up from
the working directory and loads the project's `.env` before the pack's own.

### ⚠️ Always convert generated output to a real PNG before importing into Godot
```bash
sips -s format png <file> --out game/assets/textures/<subfolder>/<name>.png
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import
```
A JPEG named `.png` imports with `valid=false` and no `.ctex`, while `ResourceLoader.exists()` still
returns **true** — so the guard passes and the prop renders blank. If a texture silently doesn't
appear, run `file` on it before debugging any code. See `ISSUES_SOLUTIONS.md` Issues 1 and 25.

## Testing

```bash
tools/run_tests.sh          # the whole headless suite, one summary table
tools/run_tests.sh -q       # summary + failing output only
tools/run_tests.sh maze     # only tests matching a substring
```

Exit code is the number of failing tests. The `TESTS` array in that script is the only index of
what the suite actually covers — keep the one-line comment beside each name accurate.

### ⚠️ Coverage by construction — the scene list is DERIVED (2026-08-17)

`game/tests/lib/scenes.gd` reads the `SCENE_*` constants straight out of `game_state.gd` and is the
**one scene list**. Nine guards iterate it — `check_wall_overlap`, `check_note_mounting`,
`check_art_aspect`, `check_prop_mounting`, `check_doorways`, `check_shell_sealed`, `check_fixtures`,
`check_spawn_blocked`, `check_reachable` — so **adding a level enrols it in all nine with nothing to
remember**, and a `SCENE_*` constant that is neither classified as a level (`META`) nor excluded by
name (`NOT_A_LEVEL`, currently the menu and the ending redirector) turns every one of them red.

This replaces eight hand-written wrappers, which are **deleted rather than left alongside** — two
ways to run one guard is how they drift. Enrolling a level used to mean remembering to write one,
and that was forgotten every single time it was possible to forget it: `check_wall_overlap.gd` and
`check_note_mounting.gd` ran on **one level out of nine** for their whole lives, and the first run
against the Corridor found 32 things and against the Backrooms 23.

A guard's per-scene row is an **override, not an enrolment** — waivers, sample-size floors and RNG
seeds. Reproduce one finding with a label filter or a raw path:

```bash
Godot --headless --path game --script res://tests/check_wall_overlap.gd -- Corridor
Godot --headless --path game --script res://tests/check_art_aspect.gd -- res://scenes/kontur.tscn
```

⚠️ **Randomised scenes are pinned by seeding the ENGINE RNG** (`Scenes.pin_rng(n)` -> `seed(n)`
before `change_scene_to_file`), not by a command-line argument — `run_tests.sh` has no per-test
argument mechanism, and needing one is exactly what kept six levels outside every geometry guard.
Nothing in `game/scripts` calls `randomize()`, so one seed fixes KONTUR's `_dark_x` **and** its
gate-1 colour, the Backrooms' arm assignment and the whole dungeon layout at once. Measured: seed 7
-> `_dark_x` +3.0, seed 3 -> -3.0, seed 11 -> 0.0 with the colours swapped. **Geometry sweeps run
several seeds; prop sweeps run one**, because which props a dungeon spawns varies with the seed and
a deferral list that only holds on some dungeons is worse than none.

### ⚠️ A `check_*` that never calls `quit(1)` is a PRINTER, and the runner cannot tell

**Five entries in the suite asserted nothing** until 2026-08-17 (cross-level X50): `check_fixtures`,
`check_window`, `check_morgue_props` and `check_spawn_blocked` walked the scene, printed what they
found and returned — exiting 0 whatever they saw — while `check_doorways` printed `BLOCKED <name>`
and then called `quit(0)` unconditionally. The runner listed all five as guarantees
("nothing seals a doorway", "ceiling fittings are not blown out", …) that the suite could not make.
Four are real guards now; `check_morgue_props` is `probe_morgue_props` and out of the list, its
claim being covered by `check_reachable`.

⚠️ **And a sixth, worse: `walk_level6_breach.gd` never called `quit()` at all** — every terminal
path printed `RESULT: FAIL (...)` and then `return true`, which ends the SceneTree loop and exits
**0**. That is the only end-to-end completability proof THE BREACH has, and it exists *because* that
level once shipped uncompletable. Fixed. **`grep -L "quit(" game/tests/*.gd` before trusting a green
column** — a test that cannot fail occupies a row in the coverage table and reports nothing.

### ⚠️ An ABSENCE assertion is trivially true of a level that failed to build

`check_dungeon_entities.gd` asserts eleven absences per seed — no `DarkZone`, no `DreadZone`, no
`ApparitionDirector` — and had nothing asserting the dungeon existed, so a `dungeon.gd` that threw
on its first line would have printed eleven comfortable OKs. It now asserts >= 9 rooms and exactly 7
sconces **first**, and plants a real `DarkZone` every run to prove the counter still counts. Every
ban-shaped guard in the project reads the same way (cross-level X51).

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
now greps for `Parse Error` / `Failed to load script` and forces a failure. ⚠️ **And since
2026-08-16 it fails any test that prints `SCRIPT ERROR` at all** (Issue 78): a GDScript *runtime*
error aborts one call and carries on, so it changes neither the exit code nor the assertions after
it — a test can run, throw on every iteration, and report PASS. It caught three on the day it
landed, in three different files, all of them long-standing: `add_child` on a null container nine
times per run of `check_maze_chase`, a headless `save_png` on a null viewport texture in
`check_lab_hint` (whose debug screenshots had therefore **never** been written by the suite), and
a stale `current_scene` in `count_apparitions` on every scene reload. Parse errors mean *the test
never ran*; these mean *the test ran on fire*. ⚠️ When sweeping for them yourself, redirect
`> file 2>&1` and **not** `2>&1 > file` — the latter sends stderr to the terminal and greps a
stream that cannot contain the error. ⚠️ And never write
`bool(node.get("flag"))` in a test: a missing property throws, the throw aborts `_process` before
the stage counter AND before the timeout check, and the test loops forever (Issue 45 — one run hung
28 minutes on a 30-second timeout).

⚠️ **Two guards were pinned to ONE SCENE and nobody noticed (2026-08-16, Issue 71).**
`check_note_mounting.gd` hard-coded `level_1.tscn` and `check_wall_overlap.gd` defaults to it while
`run_tests.sh` invokes it bare — so the two checks that exist for "is this prop actually on a wall"
and "do two surfaces coincide" had run on **one level out of nine** since they were written. The
House's third note was found floating 1.40 m in mid-air by hand, in a playtest, with both green.
⚠️ **RESOLVED PROPERLY ON 2026-08-17**: both are now **sweeps over every scene in the game**, and
the wrappers that used to enrol a level one at a time are deleted. See "Coverage by construction"
at the top of this section. A level's peculiarities live in the guard's own per-scene row — the House's cellar is not in
`ROOMS`, and it has one note per room so the same-room separation pass legitimately finds zero
pairs.
⚠️ And a positive control built from one scene's literal coordinates **degrades into a no-op
everywhere else while still printing PASS** — `check_note_mounting.gd`'s controls are now derived
from the scene under test.

⚠️ **The Backrooms was wired on 2026-08-17 and produced 10 + 8 + 5 findings on the first run** —
the third level in a row where the first run of an existing guard found double digits, which is
the whole argument for the wrappers costing three lines each. Wiring it also fixed two faults in
the guards themselves, both of which mattered game-wide:
- **`check_note_mounting.gd` was not world-space** (cross-level X32). `_room_of()` / `_in_doorway()`
  compared a WORLD position against the level script's LOCAL `ROOMS`/`DOORS` table. Every level
  built at the origin got away with it; the Backrooms builds three zones in ONE SCENE at 0, +200 x
  and −200 x, so all four of its notes read as "not inside a room". `_origin` / `_zones` fix it.
  ⚠️ `check_wall_overlap.gd` never had this bug — everything in it is `global_position` — and the
  two sibling guards differing, with neither saying so, is the trap.
- **It also assumed every prop faces +Z.** A note LYING ON A TABLE is thin in Y, and the entry-arm
  clue note (the first thing read in that level) correctly reported "NOTHING behind it" and
  uselessly: there is nothing behind it, there is something UNDER it. `_front()` now takes the
  prop's own mesh's thin axis. Everything that passed before is thin in Z and measures identically.
- **`check_wall_overlap.gd` probed a flat prop at its CENTRE POINT ONLY** (X34) — meaningless for
  the Flood's 60 × 60 m water sheet, i.e. 3600 m² tested at one pixel. `_quad_grid` (default **1**,
  i.e. unchanged) samples N × N points, `_quad_ignore` waives documented cases with an asserted
  size, and `_self_test_quad_grid()` proves the mode catches something grid 1 misses, on the scene
  under test, every run.

**Four levels still have no `check_wall_overlap` wrapper** — KONTUR, Breach, Nightmare, Void.

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

⚠️ **`check_reachable.gd` (2026-08-17) is the guard nobody had: CAN THE PLAYER STAND WHERE THIS
OBJECT IS?** Every other geometry check in this project inspects a relationship between two objects
— `check_wall_overlap` asks *do two surfaces coincide*, `check_note_mounting` asks *is this prop on
a wall*, `check_doorways` asks *is a doorway sealed* (and only for `RoomBuilder` levels). A room no
route reaches is invisible to all of them, which is how the Backrooms Sprawl kept **eight sealed
alcoves and ten unreachable objects** through two playtests and four scene-parameterised guards
(Issue 90). It flood-fills the standable space from the spawn with the level's own capsule (0.125 m
grid, lazy BFS) and then drives the SHIPPING interact ray from up to 20 reachable cells per prop,
aiming at the **mesh**. **All nine scenes, 26 s.** Four verdicts, not two — `REACHABLE` / `INERT`
(the ray reaches it, the prop is refusing: `LabLocker` before its note) / `CONTAINED` (an ancestor
interactable is reachable: a page inside a drawer) / `DORMANT` (`visible == false` or
`PROCESS_MODE_DISABLED`, read from the node) — plus gates that open are opened for the fill and put
back before probing. That taxonomy is the whole difference between a guard and a nuisance.
⚠️ Its permanent control re-seals the Sprawl alcove that holds `SprawlNote` and requires the note to
be reachable BEFORE and unreachable AFTER; the first version asserted only the second half and was
green while measuring nothing. ⚠️ Its fill capsule is **2 cm narrower than the player's**, because a
grid of static placements is strictly harsher than a `move_and_slide` body — at full width a 6 mm
clip against the House cellar ramp hid the entire cellar. Companion: `check_sprawl_alcoves.gd`,
which asserts the Backrooms cut itself (8 mouths, capsule fit, 504 floor-continuity samples, shell
closure, dread coverage, the note's readability at ±25°, and the phone's freeze/pause guards).

⚠️ **`check_shell_sealed.gd` (2026-08-17) is the guard for the OTHER half of that idea: CAN THE
PLAYER SEE OUT OF THE LEVEL?** `check_reachable` asks whether a space can be entered; nothing asked
whether the shell around it is closed, which is why the `fix-void` skill exists as a manual
protocol. The Sprawl shipped with four 3.40 × 4.50 m holes in it and the player photographed the
sky (Issue 92). ⚠️ **Its interior sweep runs on ALL NINE LEVELS since 2026-08-17** — the perimeter
and alcove passes are Sprawl-specific, but "from everywhere a player can stand, is every horizontal
ray stopped, is there floor under them and ceiling over them" is a question every level has an
answer to and only one had ever been asked. Bounds and FLOOR LEVELS are derived from the level's own
CSG (the House has three storeys: ground, ramp, cellar), and every non-Backrooms scene gets a
control that deletes a real outside wall in front of a standable point and requires the sweep to see
daylight. Result: 0 escaping rays everywhere except **THE VOID, which has no shell at all — 142 rays
from 48 standable points, filed as an exact count in `backlogs/08-void.md`.** It fires ~66 000 rays
over all three Backrooms zones — a 0.25 m lateral perimeter
sweep at six heights, an outward-hemisphere fan from five points in each of the eight recesses, and
a 1.5 m interior floor grid filtered to places a 0.4 m capsule could stand — and every ray must be
stopped. ⚠️ A `GlitchWall` is walk-through **on purpose**, so a ray that hits nothing is forgiven
only if it crosses one's visible mesh AABB; that exemption list is COUNTED (exactly 8: 1 Lobby, 4
Sprawl, 3 Flood) with the same discipline `check_wall_overlap.gd` puts on `_allow`. ⚠️ **Two
permanent controls**, because the perimeter one proves nothing about the interior sweep's filters:
`AlcBackE1` is freed and both sweeps must go red. ⚠️ **Read its constants before believing a red.**
Three quarters of its first day's findings were its own sampling — a sample buried in a 0.2 m wall
slab (from inside a shape, every ray reports clear, and `hit_from_inside` does NOT help because CSG
collides as a concave trimesh; `intersect_point` is the query that answers it), a 45° ray threading
a room corner, and an eye 0.6 m above a 2.6 m ceiling because it stood on a 0.4 m platform. Each
lesson is written at the constant that removed it (Issue 94).

⚠️ **Five more added 2026-08-16, all for the Corridor, and four of them are the SAME missing idea:
is this flat thing the right size, in the right place, and shown undistorted?** Between cross-level
X1, X2 and Issue 35 that question had been re-derived by hand in every level pass and asserted
nowhere.
- `check_wall_overlap.gd` pointed at the Corridor — the longest procedural level in the game,
  which it had **never been run against**. First run: 32 findings. Carries the project's first
  documented **waiver list** — the six corners' floor/ceiling slabs, which `_build_geometry()`
  overlaps on purpose — and the waiver asserts its own size and refuses any pair whose two boxes
  stop sharing one material instance.
- `check_prop_mounting.gd` (`check_corridor_mounting.gd` until 2026-08-17) — the
  **maximum**-clearance half X1 has always been missing. A minimum-only check cannot see a prop that
  has drifted away from its wall, which is exactly what the player photographed.
- `check_art_aspect.gd` (`check_intro_art.gd` until 2026-08-17) — the aspect check written for the
  Intro, finally run somewhere else. It found 22 of 39 surfaces stretched here.
- `check_mirror_frustum.gd` — the framing of a reflection, which *can* be asserted even though the
  reflection cannot.
- `check_painting_fall.gd` — 200 positions along the path; the only prop in the game that was
  spawned at an unvalidated random offset.
⚠️ **`check_wall_overlap.gd` also stopped being blind to `BoxMesh`.** Its prop check collected
`QuadMesh` only, so the Corridor's doors and plate, the House's furniture and `intro_room.gd`'s
wheelchair were invisible to it in *both* directions. Solid props are now compared by FACE PLANE
(the same `_faces_fight` rule the geometry uses) — not by the centre-point test the quads use, which
produced 28 false positives across the Lab and the House, because a fixture flush to a ceiling and a
closed drawer in a counter are both legitimately "inside" something.

⚠️ **And one added 2026-08-16, for the bug class that had bitten three times in a week** (Lab Issues
65/67, House Issue 76): `autoplay_house_route.gd` — **can an interactable SEAL A ROUTE by being
used?** `autoplay_exit_reachable.gd` walks every level's exit with the world in its *pristine* state,
so nothing in the project had ever opened a prop and then asked whether you could still get past it.
Two halves, and **measurably neither subsumes the other**: a capsule flood fill of the whole ground
floor from a FIXED anchor (no previously-reachable free floor may become unreachable; every room in
`ROOMS` must still have reachable floor) catches **isolation**, and a real `ai_*` walk from the
kitchen counter to the cellar gate to the exit lock catches **narrowing**. Restoring the broken
drawer reddens the walk hard and leaves the flood fill entirely green.

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

## API Keys
All keys live in `.env` at the project root. Never commit `.env`.
See `.env.example` for required keys.
