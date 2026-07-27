# BUG_FIX.md — Full Playtest Triage (Intro → KONTUR)

Source: a full playtest run (Intro → all 8 KONTUR gates) using the `game-testing` skill's
`DebugLog` instrumentation — 15 `J`-triggered debug captures + 1 death, followed by targeted code
investigation (Explore subagents reading the actual scripts, not just the screenshots) and a
`grill-me` interview to resolve every ambiguous finding into a concrete technical decision.

This document is the agreed plan. Nothing here has been implemented yet — each section below is
written to be actionable directly from this text when we move to the implementation pass.

One playtest finding needs **no fix**, noted here so it isn't silently dropped: the Level 2 death
(non-teach cellar Apparition rush after the player fled/sprinted near the ramp exit, compounded by
the cellar's stacked DreadZone+DarkZone panic) is the documented "Walk. Do not run." rule working
exactly as designed. Not a bug, not on the list below.

---

## 1. Confirmed Bugs

### 1.1 KONTUR Gate 1 — ChoiceDoor texture renders as a magnified crop

**Symptom.** Both doors in the KONTUR two-doors gate (debug captures #10/#11) look "corrupted" —
flat, plain, missing detail.

**File.** `game/scripts/choice_door.gd`, `_build()` (~lines 33-45).

**Root cause.** Identical to the documented **Issue 24** (`ISSUES_SOLUTIONS.md:650-665`): the door
texture (`door_black.png` / `door_red.png`) is applied directly onto a `BoxMesh` sized
`WIDTH×HEIGHT×THICK` = 1.4×2.2×0.12. A BoxMesh does not map a full texture per face — it renders a
magnified sub-rect of the source image. This is the exact same bug that once hit the Lab's exit
doors.

**Fix.** Mirror `door.gd:build_visual()`'s established pattern (`door.gd:47-67`) — the box stays as
dark, untextured edge/depth; the artwork moves onto `QuadMesh` children.

1. Change the BoxMesh's material to a plain unlit dark color (e.g. `Color(0.08, 0.08, 0.09)`) — no
   texture.
2. Add two `QuadMesh` `MeshInstance3D` children, each `Vector2(WIDTH, HEIGHT)`:
   - one at local `z = THICK/2 + 0.004`, facing +z
   - one at local `z = -THICK/2 - 0.004`, `rotation.y = PI`, facing -z
   - each loading `texture_path` behind the existing `ResourceLoader.exists()` guard
3. Position both quads at local `(WIDTH/2, HEIGHT/2, ±…)` — the same offset the box mesh already
   uses (`_build()`'s existing `mesh.position`).

Keep this self-contained in `choice_door.gd` rather than importing `door.gd`'s static helper — that
helper assumes the body's own origin is the door's center, while `ChoiceDoor`'s origin is the hinge;
adapting it is more code than duplicating the ~10-line quad pattern.

**Verification.**
```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
  --script res://tests/check_wall_overlap.gd -- res://scenes/kontur.tscn
```
Plus an in-game look at both doors confirming full art (window, hinge, serial plate) renders
edge-to-edge, not cropped.

**Write-up.** Add this as a documented recurrence of Issue 24 in `ISSUES_SOLUTIONS.md` once fixed.

---

## 2. Legibility / Missing Hints

### 2.1 Backrooms rotary phone — no warning against answering

**Status check.** The ringing SFX is already fully implemented and working —
`rotary_phone.gd:44-59,112-119` has a real timer + `AudioStreamPlayer3D`, and both
`rotary_ring.wav`/`phone_whisper.wav` exist on disk. **Nothing broken here.** The actual gap: no
level anywhere plants a hint telling the player not to answer it.

**Decision.** Plant the hint in the **Intro Room** note (not the House, not the Corridor).

**File.** `game/scripts/intro_room.gd:3`, `OPENING_NOTE` constant. Current text:

> "You are Subject 47.
>
> This is a psychological experiment. Your fear response is being monitored.
>
> The entity you may encounter is a product of your own mind — it cannot harm you unless you
> believe it can.
>
> Stay calm. Do not touch what you are not meant to touch.
>
> The door ahead is your first test.
>
> We are watching."

**Fix.** Insert one new paragraph, same clinical/ominous voice, before "The door ahead...":

> "If something calls out to you — a voice, a ringing, anything that asks for an answer — do not
> answer it. You are not meant to speak to anyone but us."

Pure text edit to the constant. No logic changes. (Exact wording open to a final pass together
during implementation.)

### 2.2 Level 2 TV "vinegar" hint — visible duration too short

**File.** `game/scripts/level_2.gd:901-903`:
```gdscript
const TV_CARD_HOLD := 4.5
const TV_CARD_GAP_MIN := 16.0
const TV_CARD_GAP_MAX := 26.0
```
`_tick_tv_card()` (`level_2.gd:906+`) fades the last ~1s of the hold.

**Fix.** `TV_CARD_HOLD` 4.5 → **8.0**. Leave the 16–26s gap unchanged (confirmed).

---

## 3. Asset Gaps (new textures/audio, with generation prompts + destination paths)

### 3.1 KONTUR Roster Lock — currently a flat, untextured green BoxMesh

**File.** `kontur.gd:622-632`, `RosterLock` — plain `BoxMesh` (0.12×0.4×0.3), color/emission only,
no texture at all (confirmed via code read and debug capture #12).

⚠️ **Must not** apply the new texture directly to that box — same Issue 24 trap as section 1.1.
Reuse the pattern `level_2.gd`'s own lock already gets right (`level_2.gd:399-406`): box stays as
casing/depth, a separate `QuadMesh` child carries the art on the front face.

**Texture prompt:**
> "A corroded Soviet-era combination lock plate, rusted worn metal, stencilled number dials 0–9
> partly illegible, grime and rust streaks, flat front-on texture for a wall-mounted lock, dim
> institutional lighting, muted greys and browns, no modern branding, no text/branding overlays."

**Destination:** `game/assets/textures/level_5_kontur/kontur_lock_roster.png`

Run `sips -s format png kontur_lock_roster.png --out kontur_lock_roster.png` immediately after
generation (mandatory JPEG-as-PNG fix — see `ISSUES_SOLUTIONS.md` Issues 1/25) before the Godot
import pass.

### 3.2 KONTUR Landing Mailbox — upgrade to a real 3D interactable + hidden hint note

**Current.** `kontur.gd:1053-1054` — a flat `QuadMesh` decal (no collider) via `_wall_panel()`
(`kontur.gd:1067-1081`), using `kontur_panel_mailboxes.png`. Confirmed via debug capture #9: reads
as a flat framed photo, not a real object.

**Decision.** Upgrade **only the mailbox**; the chute panel stays a flat decal as-is.

**Fix.** Replace the mailbox's `_wall_panel()` call with a shallow interactable: `CSGBox3D` (~0.15m
deep) at the same wall position/rotation as today, reusing the **existing**
`kontur_panel_mailboxes.png` on its front face (no new texture needed) + a `CollisionShape3D` +
`interact()` calling `NoteUI.show_note(HINT_TEXT)` (plain safe note — not trap/read-to-die).

**Hint content** (Gate 7 / Blackout / "unlight" reinforcement, per the user's own steer: *"I am too
afraid of the light"*):

> "MAILBOX — SLOT 12
>
> I stopped switching them on. I am too afraid of what the light finds. If you want the way out,
> you will have to feel for it in the dark."

This becomes a **second**, earlier in-level hint for Gate 7, alongside the existing
Backrooms-Flood-only hint — rewards a player who explores KONTUR itself, not just earlier levels.

No new texture required; code-only change.

### 3.3 Shared Apparition rush-sting — generic reused "creak," needs a real snarl

**File.** `apparition.gd:259-274`, `_play_sting()` — plays the telegraph/rush-moment sting (the
scariest beat, right before a fatal lunge) by loading `"creak"` pitched ×1.4. Confirmed via
grill-me: this is "the creature shared across the levels" from debug capture #13.

**Decision.** Sourced/generated audio, not procedural synthesis.

**Prompt** (Freesound search phrase or text-to-audio generator):
> "Short guttural inhuman snarl/roar, aggressive and threatening, low distorted growl with a sharp
> attack, no words, 0.6–1.2 seconds, horror creature vocalization, dry — no reverb tail — so it
> layers cleanly over room ambience."

**Destination:** `game/assets/audio/shared/apparition_snarl.wav` (or `.ogg`/`.mp3` —
`GameState.load_audio` tries all three) — lives in `shared/` because the apparition spans Lab,
House, and KONTUR.

**Code change.** In `_play_sting()`: `GameState.load_audio("creak")` →
`GameState.load_audio("apparition_snarl")`. Keep `"creak"` as the fallback if the new file is
missing (existing defensive style). Consider dropping the artificial `p.pitch_scale = 1.4` once the
source audio is purpose-made — a judgment call for implementation time.

### 3.4 KONTUR Gate 6 — new hammer + phone-smash SFX

(Assets only — the mechanic itself is section 4.6.)

**Hammer.** No new texture required by default — build as an untextured CSG primitive (handle +
head boxes), consistent with how other pickups/props in this project go textureless. *Optional*, if
wanted later: prompt *"Old rusted claw hammer, wooden handle, worn metal head, isolated on
transparent background, 3/4 angle view"* → `game/assets/textures/level_5_kontur/kontur_hammer.png`.
Default to the untextured primitive.

**Phone-smash SFX.** Recommend **procedural** synthesis — matches this project's convention for
short mechanical SFX (snap/buzz/clunk sounds all live in `tools/make_sfx*.py`). Add a `phone_smash`
generator to `tools/make_sfx_kontur.py`: a noise burst + short metallic ring/clatter tail, under 1
second.

**Destination:** `game/assets/audio/level_5_kontur/phone_smash.wav`

If a sourced sound is preferred instead (matching the apparition-snarl decision above), prompt:
> "A single heavy hammer blow smashing brittle plastic and metal, bakelite phone shattering, sharp
> crack with a metallic clatter tail, dry, under 1 second."

Flag this choice for confirmation at implementation time.

### 3.5 Backrooms Zone 2 (the Sprawl) — new audible tell at the real wall

**File.** `backrooms_zone2.gd`, `_randomise_real_wall()` (~lines 157-183). Currently only a
`SilenceZone` ducks the `"Backrooms"` bus near the real wall — the tell is pure absence, which
tested as too subtle.

**Fix.** Alongside rebuilding `_silence`, free any prior hum player and spawn a new
`AudioStreamPlayer3D` positioned at `_walls[_real_side].position` (the real wall's own transform,
not the silence-pocket offset), small `unit_size` (~4-5m) for a tight, findable falloff. Loop via
`.finished.connect(a.play)` (matches `backrooms.gd:740`'s existing pattern).

⚠️ Set the player's `bus` to `"Master"` (anything but `"Backrooms"`) — routing it through the
ducked bus would have `SilenceZone` mute the very tell it's supposed to provide.

**Audio.** Recommend procedural (matches `fluorescent_hum`/`tv_static`/`water_drip` convention). Add
a `sprawl_wall_hum` generator: low, slightly irregular drone, distinct in timbre from
`fluorescent_hum` so it doesn't blend in.

**Destination:** `game/assets/audio/level_backrooms/sprawl_wall_hum.wav`

> ⚠️ **SUPERSEDED IN THE SHIPPED CODE (noted 2026-07-27).** The spec above was implemented and then
> replaced. `unit_size ~4-5 m` turned out to be audible only once you were already standing at the
> correct wall — in a 40×40 m hall with four identical candidates that is not a tell, it is a
> confirmation. `backrooms_zone2.gd:187-225` now spawns **two** layers at the real wall, both on
> `"Master"` as specced: `water` at `unit_size 16` as the far cue you can walk toward from across
> the hall, and `whisper` at `unit_size 9` as the near confirm. This is the same far-cue/near-confirm
> pattern as the Lab dark wing's `breaker_hum`/`breaker_buzz` beacon.
>
> **`sprawl_wall_hum.wav` is therefore an orphan** — still generated by
> `tools/make_sfx_backrooms.py:97,234`, referenced by no `.gd` file. Left on disk deliberately; if it
> is ever re-adopted it needs the wide `unit_size`, not the original 4.5.

---

## 4. Feature / Design Changes

### 4.1 Level 1 breaker — search, not puzzle

**Files.** `level_1.gd` (breaker spawn loop, ~lines 285-296), `breaker.gd` (visual, unchanged).

Pick **one** breaker (recommend the Records one) and:
1. Move it off the room's `wall_point` center to a dimmer corner/side position, away from the main
   light fixture.
2. Add a periodic spark/crackle tell — a brief, dim `OmniLight3D` flicker + spark sound every
   ~8-12s — so an attentive player finds it by ear/peripheral flicker rather than seeing it lit up
   like the other two.

No change to `breaker.gd`'s flip logic — placement + juice only.

**Audio.** Procedural. Add a `breaker_spark` generator to `tools/make_sfx_extra.py` (sibling to the
existing `breaker_throw`): brief electrical crackle/arc pop, under 0.5s.

**Destination:** `game/assets/audio/level_1_lab/breaker_spark.wav`

### 4.2 Level 1 morgue monitor — reposition to the wall opposite the entrance

**File.** `level_1.gd:419-462`, `_spawn_morgue_keycard()`.

Confirmed: Morgue room is `pos (9.5, 12.5)`, `size (7,6)` → x:[6,13], z:[9.5,15.5]. Its **only**
doorway is the west wall (`DOORS` entry `{pos Vector2(6, 12.5), width 1.4, dir "x"}`,
`level_1.gd:121`), matching the `MorgueShutter` at x=6. The **east wall (side `Vector2(1,0)`) has no
doorway** — confirmed clear, and doesn't collide with the existing note (south wall,
`Vector2(0,-1)`) or cursed poster (north wall, `Vector2(0,1)`).

**Fix.** Move the monitor's trigger + visual off the cart (currently `base + Vector3(0.95, 1.0,
0)`) to `_builder.wall_point("Morgue", Vector2(1, 0), ~1.4, 0.16)` — the wall directly facing a
player stepping through the west doorway. Keep the tray on the cart unchanged; only the monitor
moves. No change to the existing trigger_object instant-fail/gaze mechanic.

### 4.3 Level 2 cellar key — relocate to Landing + a small search puzzle

**Files.** `level_2.gd` — `_spawn_cellar_contents()` (~705-710), `ROOMS`/`DOORS`,
`_spawn_room_props()` (653-671).

Confirmed: the "useless" room is **Landing** (upstairs 4-way junction, bounds x:[-4,4] z:[11,14]),
currently holding only a ceiling lamp — no props/notes. It is **not** on the direct Kitchen→cellar
path (Kitchen connects to the ramp via its own door; Landing sits upstairs off Hallway) —
relocating the key here adds a genuine detour (Hallway → Landing → back down → Kitchen → cellar
ramp). That detour is the whole point of "give this room a reason to exist," flagged here since it
changes the critical path, not just adds a side room.

**Fix.**
1. Remove the current `KeyItem` spawn from Kitchen.
2. Build **2** candidate "hiding spot" props in Landing (not 3 — the room is tight, with doorways on
   all 4 sides per `DOORS`; only 2 wall segments have clearance): small wall-mounted
   cabinets/drawers, `CSGBox3D`, following the existing `_make_prop` pattern (`level_2.gd:635-650`).
3. Only one drawer's `interact()` reveals/spawns the `KeyItem` (its `picked_up` signal still wired
   to `_open_cellar_gate()`); the other plays a "nothing here" toast and does nothing further
   (retryable — a search, not a trap).
4. `key_item.gd` stays completely unchanged — just relocated and gated.

### 4.4 Backrooms Zone 3 (the Flood) — second stalking hazard at Sump

**File.** `backrooms_zone3.gd`. Zone 3 **already has** one non-teach HOLD apparition at the Throat
(~lines 205-216: `Apparition.spawn(self, Apparition.Rule.HOLD, pos, false)` + a
`CorridorEvent`-wrapped `MazeKit.zone_box()` trigger). The "not packed enough with action" note
likely means it was missed, or the zone genuinely needs a second encounter for density.

**Fix.** Add a **second** non-teach HOLD apparition at **Sump** (`Vector2(-9, 21)`, the deepest,
most remote water room, already holding the real glitch seam) — copy the Throat pattern verbatim.
No new assets needed.

**Flag for review:** confirm doubling the encounter count (rather than something else "packed with
action") is still the right read now that you know one already existed.

### 4.5 KONTUR Gate 6 — "ignore" → "destroy" (hammer/phone redesign)

**Files.** `kontur.gd` (`_spawn_gate6_phone()` 666-681, `_score_gate6()` 696-703, `_gates` ledger,
new hammer spawn), `rotary_phone.gd` (new `smashable`/`smashed`/`_smash()`).

**Design.** The phone keeps ringing, but no longer resolves by simply not answering. While
unresolved, it exerts a continuous, room-scoped panic drain — fatal if ignored, given KONTUR's
zero-decay economy (the level-wide DreadZone cancels decay exactly; any new additive pressure only
ever accumulates). The player must find a **Hammer** near the level entrance (Landing) and use it
on the phone to smash it — silencing the ring and passing the gate. Answering it still instantly
forfeits the run, unchanged.

**`rotary_phone.gd` changes.** Confirmed only 2 call sites exist (`backrooms.gd:672`,
`kontur.gd:667`) — the new export defaults to `false`, so Backrooms is unaffected:
- Add `@export var smashable: bool = false`, `signal smashed`, `var _smashed: bool = false`.
- `interact()` (currently `rotary_phone.gd:122-133`): at the top, `if smashable and not _smashed:
  _smash(); return` — skip the existing answer logic entirely.
- `_smash()`: `_smashed = true`; stop `_ring_player`; play
  `GameState.load_audio("phone_smash")`; emit `smashed`; visually indicate destruction
  (implementation-time judgment call — e.g. tint the mesh dark or hide the receiver).
- `_process()` (currently gates ringing on `not _answered`): also gate on `not _smashed`.

**`kontur.gd` changes.**
- New Hammer pickup at `Vector3(-1.8, 0.9, -1.5)` in Landing (confirmed clear of player spawn z=-3,
  the Landing↔Vestibule doorway at z=4/x±0.9, and the existing wall panels at z=0/x=∓2.84). Model on
  `key_item.gd`'s pattern (mesh + collider the caller builds, `picked_up` signal). On `picked_up`,
  set the stored phone reference's `smashable = true`.
- `_spawn_gate6_phone()`: connect `phone.smashed.connect(func(): _pass_gate("phone"))` (mirrors the
  existing `phone.answered.connect(...)` at lines 677-680).
- `_score_gate6()` / the room-exit trigger at line 693: **remove** the auto-pass-on-leaving-the-room
  behavior — leaving the Switchboard without smashing no longer passes the gate.
  (`_refresh_exit()` already names the shortfall on the exit door with zero new door code needed.)
- New `_tick_phone_pressure(delta)` (same per-gate-tick style as `_tick_airlock`): while the phone
  exists, is not smashed, and the player is within ~7m of it, `player.add_panic(PHONE_PRESSURE_RATE
  * delta)`. Recommend `PHONE_PRESSURE_RATE = 4.0–5.0`/s — strong enough that ~10-12s of dawdling
  near an un-smashed phone is fatal alone, survivable if the player beelines for the hammer and
  returns promptly. Tune at playtest time.
- Update the note/sign text near the phone with the diegetic line: *"THESE PHONES. I CAN'T MAKE
  THEM STOP. IF YOU CAN'T ANSWER IT, BREAK IT."* — exact wording finalized together at
  implementation time.

**Doc sync.** Update CLAUDE.md's KONTUR write-up — Gate 6's verb changes from *ignore* to
*destroy*.

### 4.6 KONTUR Gate 8 (Airlock) — replace the stillness-hold with a catch minigame

**File.** `kontur.gd` — `_spawn_gate8_airlock()` (~780-832, builds `_airlock_meter` as a
progress-bar QuadMesh), `_tick_airlock()` (~834+, currently: horizontal speed ≤ `STILL_SPEED` fills
toward `AIRLOCK_CYCLE = 9.0`s).

**Spec.** A marker oscillates across a track; press E when it's inside a target zone; 3 consecutive
catches = gate passed. **Miss penalty (confirmed): a full gate strike (`STRIKE_PANIC = 18`, counts
toward the level's 3-strike limit).** Flag this in-code as `⚠️ DELIBERATE` (per the game-testing
skill's convention) since 3 mistimed catches alone could end the run — chosen knowingly.

**Fix.**
1. Replace the progress-bar visual with a fixed track (`QuadMesh`) + a moving marker (small emissive
   quad) whose position oscillates via `sin(time * speed)` in `_tick_airlock`, plus a fixed,
   visually distinct target-zone sub-section on the track.
2. Reuse the existing interact key (E) as "catch": while inside the Airlock zone, E checks whether
   the marker is currently within the target range. Success → `_airlock_streak += 1`; on the 3rd
   consecutive success, take the same completion path `_tick_airlock` currently reaches at
   `AIRLOCK_CYCLE` (drop the seal, `_pass_gate("airlock")`).
3. Miss (E pressed outside the target range) → call the existing `_strike()` (applies
   `STRIKE_PANIC` + `flash_scare`), reset `_airlock_streak` to 0.
4. Remove the `STILL_SPEED`-based speed check for this gate (grep for other uses of `STILL_SPEED`
   before deleting the constant — confirm it's gate-8-only).
5. Tune for "simple, not hard": generous target zone (~30-40% of track width), moderate oscillation
   period (~1.5-2s full sweep) as a starting point, adjustable after a playtest.

No new assets required (reuse the existing emissive-quad material style); optional reuse of the
existing wrong-code buzz SFX (e.g. from `combination_lock.gd`) for a miss.

---

## Verification Plan (once implemented)

1. Re-import any new assets:
   ```
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import
   ```
   Run `sips -s format png <file> --out <file>` on any nano-banana-pro output first.

2. Geometry assertion for every level whose props/rooms changed:
   ```
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game \
     --script res://tests/check_wall_overlap.gd -- res://scenes/<level>.tscn
   ```
   for `kontur.tscn`, `level_1.tscn`, `level_2_1.tscn`, `backrooms.tscn`.

3. Full playtest re-run via the `game-testing` skill, confirming:
   - Both ChoiceDoors render full art, not cropped.
   - TV hint holds ~8s.
   - The hidden breaker is findable but not instant.
   - The morgue monitor is the first thing seen entering.
   - Landing's drawers correctly gate the cellar key.
   - Zone 2's hum is audible near the real wall and not near fakes.
   - Zone 3's second apparition triggers correctly at Sump.
   - KONTUR's hammer/phone-smash resolves Gate 6, and lingering un-smashed genuinely drains panic.
   - The Airlock minigame is catchable and a miss registers as a real strike.

4. Write up the ChoiceDoor bug in `ISSUES_SOLUTIONS.md` as a documented recurrence of Issue 24.

5. Update `CLAUDE.md`'s level write-ups for every level whose design changed (Lab breaker/monitor,
   House cellar quest, Backrooms zone2/zone3, KONTUR gate 6/gate 8) to keep the checked-in doc in
   sync with the code.

---

# Round 2 — Level 1 (2026-07-26)

User request, not playtest triage: *"the second light switcher is kind of hidden. In reality, it is
not"*, and *"the third switcher is located in the dark place… a perfect place to make the player
scared."* Both shipped; all decisions below were confirmed with the user before implementation.

## 5.1 Records breaker — sealed behind a locker, gated on a note

**Problem.** BUG_FIX 4.1's fix (dead-end wall + a periodic spark/flicker tell) did not hide the
breaker, it advertised it. The tell was the loudest and brightest thing in Records, so "search the
room" collapsed into "walk toward the crackle".

**Change.** New `game/scripts/lab_locker.gd` (`class_name LabLocker`). A steel locker stands flush
against the panel, so it is not merely hard to see — the interaction ray physically stops at the
locker. Two gates:

1. **Read for it.** `unlocked` flips only when the player reads a new maintenance note on
   **Observation's south wall** — the opposite corner of the floor, and the only wall there without
   a doorway, the whiteboard or the one-way mirror on it. `note.gd` gained `signal read` for this
   (the project had no generic "note was opened" hook, only the bespoke `GameState.twist_read`).
   Before that, `interact()` prints a flat refusal and nothing else.
2. **Push it.** A tug-of-war bar fed by mashing **TAB** (new `push_effort` action on `KEY_TAB`)
   against a constant drain: ~5 presses/s clears it in ~3 s, ~3/s in ~8 s, below ~1.8/s it drains
   back. Failure just aborts and is retryable; 1.2 panic/s is the only cost.

⚠️ **The gate is HARD and there is deliberately NO pointer to the note.** A player who never searches
Observation cannot restore power. The old spark tell is **deleted**, not relocated — do not re-add an
ambient tell to this breaker.

**Notable implementation points.** The push does *not* pause the tree (`beartrap.gd`'s idiom, not
`maze_chase_ui.gd`'s) — the Lab's blackouts and pipe groans keep running while you are pinned facing
a wall. `player.freeze_input()` blocks movement *and* look for free, which is the camera pin.
`ARM_DELAY` is load-bearing: `interact` both starts and cancels the push while `_process` polls
`Input.is_action_just_pressed`, so without it the opening press cancels on frame one. The player is
tweened onto a brace mark first, which is what stops the slide passing through them. The Records
filing-cabinet bank was trimmed 3 → 2 and shifted west to clear the locker's footprint.

## 5.2 BreakerNook — the payoff scare

**Problem.** The most atmospheric spot in the game (far end of a ten-room lightless maze, flashlight
force-locked) paid off with a lever clunk.

**Change.** Hooked to *that breaker's own* `flipped` — never the shared 3/3 counter, since the player
picks the order. Beat: the two navigation beacons stop and free the instant the lever throws (the hum
you walked 50 m by dies with the equipment) → close breathing starts, repositioned every frame to
1.1 m behind the player's head so it follows them → 5 s later an arc-flare reveals a figure for
0.15 s → snarl + camera jolt → fullscreen `flash_scare` + 20 panic.

⚠️ **Deliberately survivable.** No rule, no fail state. Flipping this breaker is mandatory and an
unavoidable event must never coin-flip a death — and a player who cannot *see* a figure materialise
has no fair way to judge "hold still or flee" (the KONTUR Gate 7 / Backrooms Flood mistake, already
made twice). The cost is still real: 20 of `PANIC_MAX` 50, then ~50 m back through the maze, where
panic-sprinting is +6/s with decay suppressed.

## 5.3 Blocking bug found on the way (ISSUES_SOLUTIONS Issue 36)

`_restore_power()` raised **every** lamp's base energy, including the eleven `NO_LAMP_ROOMS` spawned
at 0.0 — so restoring power floodlit the Morgue (whose entire design is `DarkZone` + beartrap +
don't-look triggers) and the whole navigate-by-ear wing. `_on_breaker_flipped()` had always carried
the correct `if entry[1] > 0.0` guard; only this function lacked it. Fixed, and regression-locked.

## 5.4 New assets

| file | destination |
|---|---|
| `lab_locker.png` (887x1774) | `game/assets/textures/level_1_lab/` |
| `lab_nook_figure.png` (1024x1536, **RGBA cutout**) | `game/assets/textures/level_1_lab/` |
| `lab_nook_face.png` (1672x941) | `game/assets/textures/level_1_lab/` |
| `locker_shove.wav`, `locker_settle.wav`, `nook_breath.wav` (loop), `nook_scream.wav` | `game/assets/audio/level_1_lab/` |

## 5.5 Verification

```
Godot --headless --path game --script res://tests/check_lab_locker.gd        # new, 15 checks
Godot --headless --path game --script res://tests/walk_lab_wing.gd
Godot --headless --path game --script res://tests/check_wall_overlap.gd -- res://scenes/level_1.tscn
Godot --path game --script res://tests/check_lab_hint.gd
Godot --path game --script res://tests/screenshot_nook_scare.gd              # new, renders both scare frames
```

`check_lab_locker.gd` drives the **real** `push_effort` action via `Input.action_press` rather than
poking the bar, so a broken keybinding fails it; and it answers "is the breaker behind the locker"
with a raycast against the built geometry, never with distance arithmetic against `ROOMS`.

⚠️ **Known pre-existing failure, unrelated:** `tests/check_kontur.gd` reports FAIL(3) — two gate
seals blocking their doorways while shut, and the floor holes Gate 1's `_open_the_void()`
deliberately makes. Confirmed identical with these changes reverted; not addressed here.

---

## Round 2b — playtest feedback on Round 2 (2026-07-26, same evening)

Eight-minute session, 4 debug captures, peak panic 54%, 0 deaths. Both new features worked
end to end; all four notes were tuning, not breakage. All four applied.

| # | Note | Change |
|---|---|---|
| 1 | *"the creature… spawns quite far away from me. Can we make it appear closer?"* | `apparition.gd`: `APPEAR_DIST` 7.0 → **4.0**, `MIN_DIST` 2.0 → **1.6**, and `FLEE_MARGIN` 0.4 → **0.7** in step (see below). Affects every level |
| 2 | *"the locker must be completely inactive until I find the note — press E should not even appear"* | New optional **`can_interact()`** hook: `player.gd:_update_interact_prompt()` consults it before showing the prompt *or* setting `_interact_target`, so E does literally nothing. `LabLocker.can_interact()` returns `unlocked and not _done`. The refusal toast is gone |
| 3 | *"replace the tab with the space… require more effort, currently too simple"* | `push_effort` rebound to **`KEY_SPACE`**. The push now takes **three** full bars (`SHOVES_NEEDED = 3`), each lurching the locker `SHOVE_DIST 0.45 m` and resetting. Per-press and decay rates unchanged — the difficulty is length, not a steeper curve |
| 4 | *"after the jumpscare we need to turn on the light — very hard to escape the place"* | New `_light_the_wing()`: frees the flashlight-lock zone, calls `unlock_flashlight()`, and fades the ten wing rooms to `WING_LIT_ENERGY 0.5`. The Morgue is explicitly excluded |

**⚠️ `APPEAR_DIST` and `FLEE_MARGIN` are coupled.** Fleeing is measured as *"you are further from
it than where it spawned, by FLEE_MARGIN"*, so the same margin is far harsher at 4 m than at 7 m.
An instinctive half-step back is a normal reaction to something appearing on top of you, and at
0.4 m that reflex alone was a death. Raised to 0.7 alongside the distance cut. Sprinting is still
an instant fail at any distance, so "Walk. Do not run." is untouched — only the flinch is forgiven.

**On #4 and Issue 36.** Lighting the wing is a deliberate, narrow exception to the rule that
`NO_LAMP_ROOMS` stay dark. It is justified because the darkness was never the point in itself — it
is the cost of the navigate-by-ear puzzle, and that puzzle is *solved* the moment the breaker is
thrown. Keeping the wing black afterwards charged the player twice for the same lock, and the scare
had made it worse by killing the beacons (their only landmark) at the flip. The Morgue is in the
same list and must **never** be caught by this exception; `check_lab_locker.gd` asserts both halves.

**Jumpscare audio.** The user supplied `dark_jumpscare.mp3` (3.5 s) for the fullscreen sting. The
short positional `nook_scream` moved from +0.40 to **+0.25** so the two are 0.30 s apart rather than
0.15 — the near one reads as *it moved*, the sting as *it's on you*. `NOOK_FLASH_HOLD` 1.0 → 1.6;
`flash_scare()` never stops its audio, so the tail keeps ringing over the dark room after the image
drops, and the wing lights come up under it.

`check_lab_locker.gd` grew to **21 checks**. Two of its own bugs were fixed in the process: it
waited on frame counts for `SceneTreeTimer` chains (headless runs uncapped, so "500 frames" was a
fraction of the 6.6 s being waited on) and its flashlight-unlock check passed vacuously because the
test player never entered the wing and so was never locked. Both now wait on elapsed time and set
up the precondition explicitly.

### Round 2c — scare frequency (2026-07-26)

Second session note: *"The creature spawns next to me but now it is too often. Let's stick to the
original once in 45 seconds"*, and later *"during this trial I saw apparition more often then each
45 seconds. Please check."*

**Checked, by measurement rather than by reading the constant.** New `tests/count_apparitions.gd`
watches the live scene tree for new `Apparition` instances over a 155 s run and prints the real gap:

```
apparition #2 at t=  45.2 s   (+44.6 s since the last)
apparition #3 at t=  90.2 s   (+45.0 s since the last)
apparition #4 at t= 135.2 s   (+45.0 s since the last)
gaps: min 44.6 s / mean 44.9 s / max 45.0 s
```

So the loop was firing at exactly its stated 45 s. Two things made it *feel* faster, and both are
real:

1. **It is not the only source.** The scripted teach encounter is armed by a trigger volume in the
   main corridor and fires whenever the player first walks in — early in the level it stacks with
   the timed loop and the two can land within seconds of each other.
2. **Cutting `APPEAR_DIST` to 4 m raised the *observed* rate without changing the spawn rate.** At
   7 m a large share of spawns were clamped into walls and never seen; at 4 m nearly all resolve in
   open view. The player is now seeing apparitions that were always being created.

Raised to **60 s** as requested (`level_1.gd`, `level_2.gd`, `kontur.gd` all carry the constant).

**The actual metronome was `RandomAmbient`.** An autoload that no design doc mentioned and that was
missing from CLAUDE.md's autoload table entirely: every **5-10 seconds**, in every level, it played
`floor_creak`/`painting_fall`/`half_scream` at a random point within 4 m of the player and added
**5 / 8 / 12 panic**. A `half_scream` alone is 24% of `PANIC_MAX`. Both playtest logs are wall-to-wall
with the resulting 21-24% spikes, and "it appeared right next to me again" describes it better than it
describes a 45 s timer. Now **18-35 s**. ⚠️ This is global — it retunes ambient pressure in all eight
levels at once.

### Round 2d — "I think I got stuck in the dark room"

**Not stuck — lost.** New `tests/walk_wing_escape.gd` drops a real `CharacterBody3D` at the exact
position the log last recorded (`-28.4, 22.7`, deep in NorthVault) and drives it back out under
gravity: every leg reached, no stall, ends at the Records doorway. The geometry is sound; the player
was in the north dead-end limb, the branch furthest from the breaker beacon.

**Deliberately left alone.** Offered a second "way home" beacon at the wing mouth, a light spill, or
dropping the north limb; the user chose *"Leave it — getting lost is the level."* Recorded here so a
future session does not re-litigate it as a bug. `walk_lab_wing.gd` proves the way in, and
`walk_wing_escape.gd` now proves the way out, so a genuine trap would still be caught.
