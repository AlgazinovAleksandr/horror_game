# SCARY.md — the fear document

**Status:** design specification. Nothing here is implemented yet.
**Written:** 2026-07-27.
**Supersedes** `drafts/REPORT.md` for everything to do with *fear craft* (see §0.3).

> **⚠️ 2026-07-27 — read `GAME_MECHANICS_IDEAS.md` first.** `REPORT.md` has since been archived to
> `drafts/` and its live backlog absorbed into `GAME_MECHANICS_IDEAS.md`, which is now the entry
> point for *what to build next* and carries the audited build status of everything below.
> **This file remains authoritative for the fear-craft design itself** — the specs in §3–§5 are not
> superseded, only re-indexed.

This file exists because of a specific complaint: *the game is good mechanically, but it is not
scary.* That is a solvable problem, and this document is the plan to solve it. It is deliberately
opinionated — every proposal carries a verdict, a cost, a placement, and the project gotchas it
must respect.

---

## Table of contents

- §0 — The brief, the diagnosis, and the governing finding
- §1 — What the game already does well (so we do not rebuild it)
- §2 — The audit: what is actually missing, with `file:line` evidence
- §3 — The eleven retrofits (P1–P11)
- §4 — The two global systems: audio architecture, and shadows
- §5 — The three new levels
- §6 — The escalating-unreality pillar
- §7 — Assets: what to generate, what to source, and the prompts
- §8 — Anti-patterns: do not build these
- §9 — Phased roadmap
- §10 — Sources

---

## §0 — The brief, the diagnosis, and the governing finding

### 0.1 The three failures we are fixing

Confirmed with the user, 2026-07-27. These are the *only* things this document optimises for. A
proposal that does not serve one of them does not belong here.

**F1 — Predictable / habituating.**
Nearly every scare payload in the game is the same shape: a fullscreen image plus a loud burst
(`Screamer.trigger()` or `Screamer.flash_scare()`). And nearly every scare fires on a fixed timer or
a fixed walked distance, blind to what the player is doing. After ten minutes the player has learned
the *conditions* under which a scare occurs, and once the conditions are legible the fear is gone.

**F2 — No dread between scares.**
The gaps between events are just walking. The panic bar supplies *pressure*, but pressure is not
dread — dread is anticipation, and anticipation requires a build. The longest telegraph anywhere in
this game is **0.22 seconds** (`apparition.gd:39`). Everything else is a hard cut.

**F3 — The world feels inert / unaware of the player.**
Rooms never change. Nothing moves behind your back. The game never appears to notice what you did.
Nothing in the 3D world responds to panic at all.

**Explicitly NOT a target:** "panic is arithmetic, not fear." The user considered and rejected this
framing. **The panic bar stays exactly as it is.** Its legibility is load-bearing — twelve levels of
fail economy are tuned against it (KONTUR's `3 × 18 = 54 > 50`; the Corridor's exactly-cancelling
2.0/2.0 dread rates; the Backrooms' one-`CalmZone`-per-zone survivability floor). See §8.6.

### 0.2 The governing finding

> **Stop adding panic terms. Start adding channels.**

The panic bar is a well-tuned, fully-legible arithmetic system. Every new mechanic that feeds it
makes the system *more solvable*, not more frightening — the player optimises against a number they
can feel. Meanwhile the two channels this engine is genuinely **best** at are almost entirely
unexplored:

- **Runtime audio buses.** Godot lets you add `AudioEffectReverb` / `AudioEffectLowPassFilter` to a
  bus at runtime. The project has done this exactly once (`silence_zone.gd`, ducking the
  `"Backrooms"` bus to −30 dB as a navigational tell) and it is the single best idea in the codebase.
  There are **zero** audio effects anywhere else in the project.
- **Procedurally-generated CSG.** Levels are built at runtime by `RoomBuilder` from a table of rooms
  and doorways. Freeing a node and adding a node is trivial here in a way it is not in a hand-authored
  scene. Geometry that mutates is nearly free.

And the channel the instinct reaches for — post-processing — is the one this engine is worst at
(no glow, no fog, no SSAO, Linear tonemap, emission above 1.0 clamps to flat white).

**Nine of the eleven retrofits in §3 add zero panic.** That is not timidity; it is the finding.
Frictional's Thomas Grip, after nine years of shipping horror, reports that *"spacing scares apart
made players much more scared than previously"* and that horror *"functions as seasoning, not the
entire dish."* This project already discovered that independently when it moved `RandomAmbient` from
a 5–10 s metronome to 18–35 s. The research says that retune was correct and probably still not far
enough.

### 0.3 Relationship to `drafts/REPORT.md`

`drafts/REPORT.md` (archived 2026-07-27) held twenty accepted-but-unbuilt ideas from two
`idea-generator` sessions. Six of them are fear-craft items and are **superseded by this file**,
which specs them properly rather than in one paragraph each:

| `REPORT.md` item | Superseded by |
|---|---|
| #1 Adaptive Director pacing | §3 P9 + §4.1 (scoped down to a relief valve — see the reasoning there) |
| #2 Hide the panic meter (KONTUR) | §3 P8 (reframed: lie about the *readout* for < 1 s, never about the *rules*) |
| #4 Falling/collapsing props | §3 P6 (`MovedProp` is the better version of the same instinct) |
| #5 Misdirection pairing | §3 P4 + P11 (misdirection is the *mechanism*, not the feature) |
| #7 Pre-scare silence dip | §3 P5 |
| #20 Shifting-architecture level | §3 P11 + §5.1 (as a retrofit and a level, not one or the other) |

Items #3, #8, #10, #11, #12, #13, #14, #15, #16, #19 are puzzle/agency/systems work, not fear craft,
and this file never claimed them. They now live — with audited build status — in
`GAME_MECHANICS_IDEAS.md` §2. `drafts/KONTUR.md` is already a cautionary tale in this repo about a stale doc
silently contradicting the shipped game, which is why the consolidation happened at all.

---

## §1 — What the game already does well

Listed so that no proposal here rebuilds something that exists. This is a genuinely strong horror
codebase and the problem is *not* a lack of mechanics.

1. **A unified fear meter with real economy.** One 50-point bar with named rates; every level's
   difficulty is expressible in it. Very few small horror projects have this arithmetic discipline.
2. **Four mutually-inverted creature rules with a teach-first fairness contract.** HOLD (don't run),
   STARE (don't look away), LOOKAWAY (don't shine light), DON'T-LOOK-BACK (the escort) — plus a
   *global* teach ledger (`GameState.apparition_taught`) so the first HOLD encounter in a run is
   survivable wherever it happens.
3. **Inversion of the player's learned safety heuristic.** The flashlight is safety for five levels,
   then the Backrooms Flood and KONTUR Gate 7 make light the thing that *hides* the answer, and the
   Smiler makes light lethal.
4. **Punishing the safe action.** Standing still costs panic (Backrooms); staring costs panic (every
   `ScaryObject`); sprinting costs panic (globally); reading costs panic (trap notes, the phone).
5. **Audio as navigation *and* threat.** The two-layer positional beacon (far cue at `unit_size 16`
   for bearing, near confirm at `unit_size 9` for distance) is a genuinely sophisticated technique.
6. **Silence as a signal.** `silence_zone.gd`. See §0.2.
7. **A persistent pursuer with search memory** (`creature_object12.gd`) that correctly implements the
   one Alien: Isolation lesson worth stealing — losing line of sight goes to SEARCH, not PATROL.
8. **Jumpscare craft**: the apparition telegraphs its lunge (a 0.22 s sting plus a 0.35 m lurch)
   before the kill, rather than cutting instantly.
9. **A complete light economy.** Light depletes (240 s battery), light repels (Level 6's shield
   drain), light attracts (the Smiler, KONTUR's painted seams). That is more complete than Amnesia,
   Outlast or Alan Wake individually. **Do not add a fourth light rule.**
10. **Structural dread**: no checkpoints. `restart_current_level()` erases the level snapshot on
    purpose.

---

## §2 — The audit: what is missing

Every claim below was verified in the code on 2026-07-27.

### 2.1 No audio occlusion, reverb, filtering, or environmental acoustics — at all
Grep for `AudioEffect|attenuation_model|attenuation_filter|area_mask|reverb|doppler` across
`scripts/*.gd` returns nothing but a comment. There is **one** runtime-created bus (`"Backrooms"`,
`backrooms.gd:782-786`) and it carries **no effects**. A scream through a concrete wall in KONTUR
sounds identical to one in the same room. `AudioStreamPlayer3D.unit_size` is the only spatial knob
used anywhere (40 call sites); `max_distance` and `attenuation_model` are never set.
→ **F2.** This is the biggest single gap in the project.

### 2.2 No dynamic or reactive music
Two music files exist (`kontur_music.mp3`, `backrooms_music.mp3`), each started once as a static
loop. Nothing reads `get_panic_ratio()` or a creature's state to change a stem, a tempo, or a layer.
The heartbeat (`player.gd:588-602`) is the **only** panic-reactive audio in the entire game, and it
is one file with `volume_db` and `pitch_scale`.
→ **F1, F2.**

### 2.3 No enemy that can be heard but not seen
The two attempts are one-shot set pieces (`escort_gate.gd`'s `breathing_behind`, `level_1.gd`'s
`nook_breath`) and **both are pinned to the player's own position every frame** — so there is nothing
to localise, nothing to flee from, and no reason to change route. Object 12, the only creature that
could support this, is **completely silent** while patrolling and chasing; it emits sound only on
stagger and recovery (`level_6_breach.gd:271-284`), despite `creature_growl_near.wav` sitting unused
on disk.
→ **F2, F3.**

### 2.4 Nothing in the 3D world responds to panic
`panic_hud.gd:92-97` is the complete list of panic's visual consequences: a screen blur, a red tint,
and heartbeat pitch. **And the red tint is capped at 10 % opacity** (`max_tint_blend` is overridden
to `0.1` in `hud_canvas.tscn:10`), so it barely registers even at death's door. No hallucinated
props, no geometry mutation, no corridor that lengthens, no doors that move. The one reality-tear
shader (`glitch_wall.gdshader`) runs at a *constant* `tear_amount 0.12` regardless of player state.
→ **F3.**

### 2.5 Nothing casts shadows; no fog, no glow, no SSAO

> ⚠️ **CORRECTION (2026-07-27) — this section's shadow claim is WRONG.** The player's `Flashlight`
> is a `SpotLight3D` with `shadow_enabled = true` in **every level scene** (`level_1.tscn:374`,
> `level_2.tscn:339`, `level_2_1.tscn:312`, `level_3.tscn:421`, `corridor.tscn:32`,
> `backrooms.tscn:31`, `kontur.tscn:31`, `level_6_breach.tscn:31`, `intro_room.tscn:32`) and it
> demonstrably renders — verified by screenshot. So the three scares called "impossible" below
> (a moving shadow, a shape resolving out of darkness, a doorway silhouette) are **available today**.
> What is true is narrower: no **static** `OmniLight3D` room lamp casts, which `level_1.gd:173-175`
> deliberately relies on. See `GAME_MECHANICS_IDEAS.md` §2.0(a) for the re-scope.

`environment.tscn` has no `glow_enabled`, no `fog_enabled`, no `ssao_enabled`, no volumetrics, no
tonemap override. `level_1.gd:1319` states it plainly: *"nothing in this project casts shadows
anyway."* Consequences: the flashlight can only brighten a surface — it can never throw a moving
shadow, resolve a shape out of darkness, or silhouette something in a doorway. Those are three of
the most reliable atmospheric scares in the medium and all three are currently impossible.
→ **F2, F3.**

### 2.6 No sustained anticipation before any scare
`TELEGRAPH_TIME = 0.22` (`apparition.gd:39`) is the only telegraph in the game. The Manager, the
forest window, the turn mirrors, the nook, the wrong wall — all hard cuts to a fullscreen image.
There is no "something is about to happen" bed, no build, no held silence before a stinger.
→ **F1, F2.**

### 2.7 `RandomAmbient` is a blind, ungated, uniform metronome
`_play_near_player()` (`random_ambient.gd:73-87`) spawns a throwaway `AudioStreamPlayer3D` at
`player_pos + (rand ±4, rand 0..2, rand ±4)` with **no line-of-sight test and no navmesh check** — so
its scares regularly originate *inside walls or inside the player's own head*. And there is **no
panic gate**: at 45/50 panic a `half_scream` (12 points) is a coin-flip death the player had no
agency over. `ApparitionDirector` has exactly this gate (`MAX_PANIC_RATIO 0.6`); the louder system
does not.
→ **F1**, and a live fairness bug.

### 2.8 No cross-system awareness
The *only* coordination between the two scare timers is `RandomAmbient.seconds_since_last_scare()`
(`random_ambient.gd:29`). There is no director that knows the player's recent history, no dry-spell
escalation, no adaptive pacing. `ApparitionDirector` can only *delay*; `RandomAmbient` is a pure
uniform-random metronome with a flat 18–35 s period, identical in all levels.
→ **F1.**

### 2.9 Death is a pure reset
`restart_current_level()` (`game_state.gd:102-104`) wipes the snapshot and rebuilds the level
identically. That teaches the player the level is a fixed puzzle, which is precisely the wrong lesson
for a horror game. Repetition should escalate, not reset.
→ **F1, F3.**

### 2.10 No unreliable UI, and no world that lies
Everything the game tells the player is true. The objective line is always correct, the journal
always accurate, the "Press E" prompt always real. The nearest thing to a lie is a `MirageDoor` or a
decoy `GlitchWall` — both honest diegetic props.
→ **F3.**

### 2.11 Six live defects found during the audit
Logged in `BACKLOG.md`; repeated here because two of them are actively degrading existing scares.

1. `level_6_breach.gd:25` — `FAMILIARIZATION_TIME := 10.0` carries an in-file *"⚠️ TEMPORARY —
   lowered from 50.0 for debugging (2026-07-24). Revert before ship."* The Mr.X window is off.
2. `escort_gate.gd:98` — `_breath.global_position = _player.global_position + BREATH_OFFSET` where
   `BREATH_OFFSET` is a **world-space** `(0, 1.2, 1.6)`. So the breathing is always to the world +z
   of the player, **not behind their facing**, despite the comment. KONTUR's best audio beat is
   broken.
3. ~~`vignette.gd` is entirely commented out (`Vignette.spawn()` is `pass`) but still called by
   `level_3.gd:29`. The Void has no vignette.~~ ✅ **FIXED 2026-07-28.** Restored, and two
   things had to change to make it safe: the layer was `-1`, i.e. BEHIND the 3D viewport
   where it drew nothing at all; and the shader alpha-blended its tint over the screen,
   but every caller passes a LIGHT colour (the Void's is `Color(0.65, 0.55, 1.0)`) because
   the tint is meant to colour the DARKENING — so it rendered as a bright purple halo
   round the edges. It is now `blend_mul` at layer 5, and screenshot-verified on the Lab,
   the House and the Void.
4. `hud_canvas.tscn:10` caps the panic red tint at 0.1 — see §2.4.
5. `apparition_director.gd:108` claims `is_input_frozen()` protects the player during a beartrap QTE,
   but `beartrap.gd` never calls `freeze_input()` — it only calls `apply_slow()`. The documented
   double-jeopardy protection **does not cover the beartrap.**
6. Dead code: `creature_static.gd` (zero callers), `player.gd:368 relieve_panic()` (zero callers).

---

## §3 — The eleven retrofits

Cost scale: **XS** = one script under ~80 lines, no assets · **S** = one script + 1–2 procedural SFX
· **M** = script + assets + level integration.

| # | Name | Fixes | Panic added | Cost |
|---|---|---|---|---|
| P1 | `RoomToneZone` — runtime reverb buses ⭐ | F2 | none | XS |
| P2 | Stop-delayed footstep echo | F2 | none | XS |
| P3 | `Watcher` — a distant figure with no rules ⭐ | F3 | none | XS |
| P4 | The False Ceiling — telegraphs that mean nothing ⭐ | F1 | none | XS |
| P5 | `HoldBreath` — the pre-scare silence dip ⭐ | F2 | none | XS |
| P6 | `MovedProp` — the object that changed ⭐ | F3 | none | XS |
| P7 | Death-degradation ⭐ | F1, F3 | none | S |
| P8 | Sanity-effect suite (diegetic UI only) ⭐ | F3 | none | S |
| P9 | Panic-gated ambient suppression | fairness | *removes* | XS |
| P10 | The unseen thing in the Flood | F2 | none | S |
| P11 | Room-tone-masked geometry mutation | F3 | none | M |

---

### P1 · `RoomToneZone` — runtime reverb buses ⭐ TOP PICK

**Mechanic:** environmental acoustics. **Exemplar:** essentially all modern AAA horror; the direct
in-project precedent is `silence_zone.gd`. **Cost:** XS. **Panic:** none.

**Why this first.** The engine has no fog, no SSAO, no glow, and casts no shadows — every *visual*
tool for implying unseen space is unavailable. Reverb is the substitute and it is free. A doorway
into a big dark space should *sound* big before it looks big. Players spatially model rooms from
reverb tail without noticing they are doing it, which per §0.2 is exactly the kind of channel we
want: one the player cannot audit and therefore cannot habituate to.

**Placement.**

- **The Lab dark wing** (`DarkCorridor` … `BreakerNook`). A tight, close, damped tone in the
  corridors; a long cold tail in `NorthVault` and `PumpRoom` so the two dead ends *sound* like dead
  ends before you walk them.
  ⚠️ This is legal under Issue 34 because it distinguishes **shape**, not **correctness** — the dead
  ends get the big tail, so it never points at the breaker. Contrast with the deleted Records spark
  tell, which pointed straight at the answer.
- **Backrooms Zone 2 (the Sprawl)** — a 40×40 m hall with a deliberately wrong 4.5 m ceiling. Give it
  a genuinely large room tone so the wrong scale is *audible*.
  ⚠️ **Must be a separate bus from `"Backrooms"`**, or `SilenceZone` will duck the reverb along with
  the bed and destroy the Zone 2 tell — the same reasoning that already routes
  `backrooms_zone2.gd`'s two tell-players to `"Master"`.
- **KONTUR** — swap the tone at each of the three skin transitions
  (`kontur_wallpaper_soviet` → `kontur_concrete_infected` → `kontur_facility_wall`). Soviet =
  domestic and soft; infected concrete = raw and slappy; facility tile = clinical, bright, ringing.
  The visual arc that already tells the story starts telling it in a second channel.
- **Level 6 Breach** — one distinct tone for the Incinerator, so `PurgeAnte → Incinerator` is
  audibly a threshold.

**Hook.**
```gdscript
class_name RoomToneZone extends Area3D
# Copy silence_zone.gd wholesale. On body_entered, tween this bus's
# AudioEffectReverb .room_size / .damping / .wet toward this zone's values;
# on body_exited, tween back.
# ⚠️ Restore defaults in _exit_tree() — the non-negotiable half of silence_zone.gd's
#    contract. A teleport out of a zone must never leave the level permanently wet.
```
Instantiate from `kontur.gd:_rooms_with_skins()` (which already iterates the rooms needing per-place
treatment) and from `level_1.gd`'s wing builder.

⚠️ **One zone per band, never adjacent zones.** Overlapping `Area3D`s fire `body_exited` before
`body_entered` — the exact reason the Lab's flashlight-lock had to be a single zone. Adjacent
`RoomToneZone`s would strobe the reverb.

---

### P2 · Stop-delayed footstep echo

**Mechanic:** the sound that lies about position. **Exemplar:** Alien: Isolation's motion tracker as
an audible liability. **Cost:** XS. **Panic:** none.

`player.enable_footstep_echo()` already exists (Backrooms-only): each real step replays at −11 dB,
0.4 s later, from a player at local `(0, 0, 1.4)` — two paces behind. The upgrade with the best
return is the **stop-delayed** variant: when the player halts, play **two more echo steps,
decelerating**, then stop.

The player stops. Something behind them takes two more steps, and stops too.

**Placement.**
- **KONTUR's Escort corridor (Gate 4).** The gate already fires `tempt(0)` = footsteps behind you at
  18 % progress, and the rule is "do not look back past 100°." Currently those footsteps are an
  *event*. Make them continuous and wrong for the whole 26 m. Then the blood-red **"LOOK BEHIND YOU"**
  scrawl at `TEMPT_AT 0.72` lands far harder, because by then the lie has physical evidence.
  ⚠️ Fix defect §2.11 #2 first, or the breathing is in the wrong place anyway.
- **Corridor Zone B** (90–230 m).

**Hook.** Generalise to `enable_footstep_echo(trail_steps := 0)`; on `_is_moving` going false,
schedule `trail_steps` more echo plays at increasing intervals. ~15 lines in `player.gd`.

**Why it is safe:** zero panic, so it cannot compound with KONTUR's floor-wide `DreadZone` (which
cancels decay exactly, making every point permanent). Diegetic-first, which the project explicitly
prefers — *"Diegetic first, text last."*

---

### P3 · `Watcher` — a distant motionless figure with no rules ⭐

**Mechanic:** the uncanny distant figure. **Cost:** XS. **Panic:** **none, deliberately.**

The project has five creature types and **none of them does the cheapest, most-cited scare in the
medium: stand still at 30 m and do nothing.** `creature_shapechanger.gd` is the closest, but it is a
kill-radius trap with a 16 panic/s stare — a punishment, not an image.

A `Watcher` is **a photograph**. No `ScaryObject` ancestor (so zero gaze panic), no `KILL_DIST`, no
`Screamer`, no rule to learn, no way to fail. It stands at 25–40 m, motionless, and then it is not
there. The research is unambiguous on why this works: *even if the object never actually moves, the
possibility alone creates tension* — motionlessness is not the absence of a threat behaviour, it **is**
the threat behaviour.

**Why the zero-panic part is load-bearing.** The project's instinct is to attach a panic value to
everything frightening, and that instinct is exactly what makes the bar solvable (§0.2). A scare with
no number attached cannot be optimised against, cannot be budgeted around, and cannot destabilise a
tuned level. It is also the only kind of scare that is *free* to place in KONTUR, where decay is
cancelled and every point of panic is permanent.

**Placement (three sites, one script).**
- **Corridor Zone A, ~55 m** — visible down the long straight before the first 90° turn, 40 m away,
  centred in the hall. Gone by 25 m. Zone A is the lit, intact, `CalmZone`-anchored stretch with
  nothing in it but paintings and a clock; it is the one place that can carry an image without
  touching a budget.
- **Backrooms Zone 3 (the Flood)** — standing in the water at the far end of `WestRun`, a side run
  deliberately off the Descent→Sump route. Rewards the searching the roster-code digit notes already
  demand.
- **The Void, Room A** — the candle/`CalmZone` recovery anchor. A figure standing *outside* the
  candlelight, in the dark, not entering it.

**Despawn:** on approach within `despawn_dist`, on look-away-then-look-back (50 %), or after 25 s.

**Hook.**
```gdscript
class_name Watcher extends Node3D
static func spawn(parent: Node, pos: Vector3, tex_path: String, despawn_dist := 25.0) -> Watcher
```
Copy the clearance fan from `apparition.gd:_fits()` and `level_1.gd:_place_nook_figure()`.
⚠️ **Rays only — never `intersect_shape`** (Issue 40: a shape query against CSG reports *nothing*
when wholly inside the slab, i.e. it silently approves exactly the embedded case being rejected).
⚠️ Unshaded material, and the texture must be a **real RGBA cutout** or it billboards as a solid
rectangle (the `apparition_figure.jpg` bug).
⚠️ **No emission.** Issues 21/27/33 — a hidden thing must not glow, and at 0.45 light energy emission
outweighs albedo. It is a dark silhouette or it is nothing.

---

### P4 · The False Ceiling — telegraphs that usually mean nothing ⭐

**Mechanic:** anti-habituation by broken prediction. **Exemplar:** F.E.A.R., whose music *"builds to
a terrifying crescendo before cutting off without a corresponding event, only to later have the
silence shattered by Alma when players least expect it."* **Cost:** XS. **Panic:** none of its own.

This is the **only durable answer to habituation** in the research corpus. Scares die when their
trigger conditions become legible; the fix is a telegraph the player learns to *dismiss*.

Build one telegraph — a three-note descending groan (`telegraph_groan.wav`) plus a 1.2 s duck of the
ambient bus (P5) — and fire it at **five randomised points** across Corridor Zone B (90–230 m). Four
are followed by **nothing at all**. The fifth, chosen at random per run, is followed 0.9 s later by
the Manager's existing `flash_scare(screamer_manager.png)`.

Currently `_ev_manager` drops one `CorridorEvent` at `randf_range(80, 180)` m and fires cold. Hanging
it off the fifth instance of a telegraph the player has already learned to ignore converts a 25-panic
startle into a **90-metre-long dread structure at zero additional panic cost.**

**Also place in:** Level 6's bypass loops (`WardA`, `ArchiveA/B`), where the payoff is Object 12
actually arriving.

**Hook.** An array of `CorridorEvent`s using `corridor.gd`'s existing `_ev_*` pattern, plus a
`_telegraph(payload: Callable)` helper. Pick the payoff index with `randi_range` at build time and
**store it in the level-progress snapshot** alongside `furthest path distance`, so a back-door return
does not re-roll it.

**Fairness:** a non-event cannot be unfair. This is the cheapest legal scare in the document.

---

### P5 · `HoldBreath` — the non-spatial silence dip ⭐

**Mechanic:** silence as an event. **Exemplar:** F.E.A.R.; in-project, `silence_zone.gd`.
**Cost:** XS. **Panic:** none.

`SilenceZone` proves the bus duck works, but it is *spatial* — you have to walk into it. The
untapped form is the **event** version: duck a named bus to −30 dB over 0.15 s, hold, restore over
0.4 s. Static helper, `ScreenText`-shaped.

**Placement — three, in ascending order of value:**
1. **Inside `Screamer.flash_scare()`, as a 0.6 s pre-duck.** Two lines. It improves **every existing
   survivable scare in the game at once** — the House forest window, the Corridor Manager, the three
   turn mirrors, the Lab nook payoff, all eight KONTUR strike flashes. F.E.A.R.'s entire audio thesis
   is that the silence before the hit is what makes the hit.
2. Attached to P4's telegraph.
3. On the KONTUR Perëkozhnik's engage radius.

⚠️ Parent to the tree root and clean up via a **connected, never awaited** tween — Issue 6, which
`screen_text.gd` documents: an awaited timer dies with the node that started it.

---

### P6 · `MovedProp` — the object that changed ⭐

**Mechanic:** the "wrong detail." **Exemplar:** Condemned's mannequins; Anatomy's furniture.
**Cost:** XS. **Panic:** none. No audio, no texture, no HUD, no acknowledgement.

A prop the player has already walked past sits in a slightly different position on the return leg.
No sound. No event. The game never mentions it.

Condemned's power came from being **retroactive**: *"there are plenty of other mannequins around the
store, so players nervously remember all of the ones they've already walked past."* One moved prop
makes every previous prop suspect. That asymmetry — if the player never notices, nothing happens — is
the whole mechanic.

**Placement.**
- **The House** — the best fit in the game, because it is the only level with genuine backtracking
  pressure (the third safe note is in the cellar; the Bathroom map → Kitchen key → Cellar gate chain
  crosses the ground floor repeatedly). Candidates: living-room chairs rotated 30° to face the
  doorway; a bedroom drawer open that was shut; the child's-room music box moved from the shelf to
  the floor, **closer to the door**.
- **KONTUR's Landing** — the 12-slot mailbox bank has exactly one openable slot (12). On a return
  visit, slot 7 is open too. Nothing is in it.
- **Level 6** — the player traverses `Atrium`/`Junction2` repeatedly routing around Object 12. One
  `HidingSpot` door standing open that they closed.

**Hook.**
```gdscript
class_name MovedProp extends Node
# Wraps any Node3D. In _process: if (player_eye_dir dot to_prop) < -0.1
# and distance > 6 m and not _done: apply the stored delta; _done = true.
```
⚠️ Constrain the delta to **≥ 2 cm off every existing plane** or `check_wall_overlap.gd` will flag
it. ⚠️ Register moved props in `save_progress()` so a back-door return does not un-move them.
⚠️ One-shot per prop per run — a prop that keeps moving is a mechanic, and this must stay an anomaly.

---

### P7 · Death-degradation ⭐

**Mechanic:** repetition escalates instead of resetting. **Exemplar:** Anatomy, whose tapes hiss more
and whose house gets wronger each time you reopen it. **Cost:** S. **Panic:** none — **cosmetic
only.**

Right now death is pure cost: you lose the snapshot and repeat an identical level. That teaches the
player the level is a fixed puzzle. Anatomy's answer is to punish repetition *narratively*, which is
exactly the shape a no-checkpoint game wants.

**Mechanism.** `GameState.deaths_this_level: int`, incremented in `restart_current_level()` and
**deliberately not cleared by `reset_level_state()`** — the identical trick `kontur_banished` and
`is_ending` already use, so both the precedent and the gotcha are documented. Reset on
`advance_level()`. Cap the escalation at **3 tiers**.

**Two halves, both agreed with the user:**

**(a) Re-randomise what is safe to re-randomise.** On restart, re-roll the level's existing random
elements so the level cannot be memorised: apparition timing, which arm/door/seam is real, prop
placement. Several levels already do this per-attempt (the House maze, KONTUR's `_dark_x`), which is
the precedent.
⚠️ **Never re-roll in a way that can make the level unwinnable**, and never change a *rule* — only
which instance of a rule is where.

**(b) Escalate, atmospherically only.** Consumers:
- **Corridor** — at `deaths ≥ 1`, two extra Zone-A torches are dead on arrival. At `≥ 2`, the entry
  note has a second paragraph that was not there. (The `.gd` builds the note text; this is a string
  branch.)
- **Backrooms** — at `deaths ≥ 2`, `fluorescent_hum` is pitched down 8 % and the wallpaper albedo is
  tinted 6 % toward green. `MazeKit.make_material()` is the single choke point.
- **Lab** — at `deaths ≥ 2`, one extra `Watcher` (P3) stands in `NorthVault`, a dead end nobody needs
  to enter. It does nothing.
- **Intro room** — at *total* deaths ≥ 6, one extra cobweb and the candle burns visibly shorter.
  `_corrupt_room()` already proves the intro room can be conditionally re-dressed.

**Why it is safe:** none of these change a rule, a rate, a code, or a fail condition. No level's
arithmetic moves; `check_level_resume.gd` and every difficulty constant are untouched.

⚠️ This does **not** soften the no-checkpoint philosophy. A death still wipes the level snapshot.
This is about what the level *looks and sounds like* on attempt 3.

---

### P8 · Sanity-effect suite — diegetic UI only ⭐

**Mechanic:** perceptual unreliability. **Exemplar:** Eternal Darkness' Sanity Effects — still the
gold standard, with ~50 discrete effects. **Cost:** S per effect. **Panic:** none.

Eternal Darkness' effects are (a) numerous, (b) self-reverting, and (c) untimed. Properties (b) and
(c) make the whole system **natively fairness-compliant**: nothing that happens can kill you, so the
"first encounter must be survivable" rule is satisfied by construction. Property (a) is what defeats
habituation.

**The hard constraint, decided with the user: diegetic only.** The *world* lies. The *game* never
does. Eternal Darkness' famous fake save-deletion and fake BSOD are exactly the ones this project
must not copy — see §8.1.

**The legal surface is the game's own in-fiction instrumentation.** `PanicHUD`, `ScreenText`, the
objective line, `NoteUI`, `JournalUI` are, in the fiction, *the experiment talking to Subject 47.*
"We are watching" is established in the first minute. An unrequested message from the observers is
**more** diegetic, not less.

**Firing rules** — modelled on `ApparitionDirector`, which already does this correctly:
- only when `player.get_panic_ratio() > 0.55`
- max one per 120 s
- never while `NoteUI.is_open`, `get_tree().paused`, or `player.is_input_frozen()`
- all self-revert within ≤ 3 s

**The six effects:**

1. **Panic spike lie ⭐.** `PanicHUD.set_panic_ratio()` is driven to 0.98 for 0.8 s, then snaps back.
   The blur and tint shaders sell it. **Real `_panic` never moves.** The game's most-read UI element
   briefly reports your death. This is the crown jewel and it is why §2.11 #4 (the 10 % tint cap)
   should be fixed first — the effect needs the tint to actually register.
2. **Objective corruption.** `set_objective()` shows `PROTOCOL 4-B — SUBJECT 47 IS NOT RESPONDING`
   for 1.5 s, then reverts to the true string. Fits KONTUR's protocol register exactly.
3. **Phantom carried item.** `set_carried()` shows `SUBJECT 46'S KEYCARD` for 2 s.
4. **The journal entry that is not yours.** `JournalUI` (TAB) lists one extra note titled
   `— (recovered)`; opening it shows three lines of the note the player is *standing next to*, in
   second person, past tense. It is gone from the list on close.
   ⚠️ Legal because trap notes are **never** archived, so this cannot leak a read-to-die text.
5. **Flashlight lie.** The flashlight visually dims to ~20 % for 1.0 s and recovers. Battery
   untouched. Under Linear tonemap with no glow this reads cleanly as a light-energy tween.
6. **Caption from the observers.** `ScreenText.caption("SUBJECT 47 — HEART RATE 190. CONTINUE.")`
   for 2 s.

⚠️ Copy `note_ui.gd`'s Issue-9 guard into anything that pauses: *if open and the tree is no longer
paused, drop silently* — a screamer unpauses and reloads out from under you.

---

### P9 · Panic-gated ambient suppression — the relief valve

**Mechanic:** director-style pressure relief. **Exemplar:** Alien: Isolation's Director, which routes
the alien *away* at peak menace. **Cost:** XS. **Panic:** it *removes* panic.

In `random_ambient.gd`, before firing:
```gdscript
if _player.get_panic_ratio() > 0.75:
    _reschedule(20.0)
    return
```

`ApparitionDirector` already has this (`MAX_PANIC_RATIO 0.6`). `RandomAmbient` does not — and it is
the louder system (5/8/12 panic, global, every level). At 45/50 panic a `half_scream` is a coin-flip
death with zero agency, which is precisely the shape this project has already catalogued twice
(KONTUR Gate 7, the Backrooms Flood).

**Also fix while in there:** `_play_near_player()` should raycast from the player to the chosen point
and pull the emitter in to the first hit, so ambient scares stop originating inside walls and inside
the player's head (§2.7). ~6 lines.

**Note on the Adaptive Director idea** (`drafts/REPORT.md` #1). A full Alien: Isolation menace gauge would duplicate
`ApparitionDirector`, which already does the hard half correctly. What was actually missing is the
*relief* half. Build P9; do not build a second director. If a dry-spell escalation is wanted later,
`OVERDUE_AFTER` is the existing hook.

---

### P10 · The unseen thing in the Flood

**Mechanic:** the threat that is never instantiated. **Exemplar:** Iron Lung; Amnesia's water
monster. **Cost:** S. **Panic:** none.

**Every creature in this game is rendered.** The Smiler, the Perëkozhnik, the stalkers, Object 12,
the apparition. There is no entity that exists only as sound and consequence — which is the cheapest
and most-praised horror asset in the corpus, and in *this* engine it dodges the two hardest
constraints simultaneously (no shadows to sell it with, no glow to give it eyes). It also cannot
glitch: a monster you never draw can never be caught clipping through a wall.

**Placement:** Backrooms Zone 3 (the Flood) — an 8-room flooded wing, near-black, ankle-deep water.

**What to add:** nothing visible. A **wade sound that is not the player's**, from an
`AudioStreamPlayer3D` that moves along the room graph on its own tweened path, always ≥ 12 m away,
`unit_size 14`, never entering the player's room, never approaching, never resolving. No collider, no
`ScaryObject`, no kill radius. It is a `.wav` with a `Tween` on its position.

The Flood already has two HOLD apparitions and a darkness tell. It does not need a third *thing*. It
needs the two it has to feel like part of a population.

---

### P11 · Room-tone-masked geometry mutation

**Mechanic:** the world changes behind you. **Exemplar:** Layers of Fear; P.T. **Cost:** M.
**Panic:** none. **Do this last** — it is the only proposal with real regression risk.

Bloober's method is explicit and is the important part: *they do not detect "not looking" — they
**manufacture** it.* *"The trick lies in creating a setting in which the player will trigger an
effect of changing, either by walking over a specific spot or by looking in the right direction,"*
using light and sound to guide attention away.

This engine has no shadows and no glow, so **light cannot steer the gaze here** — but the audio
toolkit is excellent, and there is precedent for positional audio bait (the two-layer beacon; the
escort's `tempt()`).

**Placement:** the **House hallway**, on the return leg from the cellar.
A positional sound in the *living room* (a `music_box.wav` one-shot, or a `MovedProp` chair scrape)
pulls the camera. While the dot product to the hallway's far wall is negative, `queue_free()` the
doorway plug and `add_child()` a short 2 m dead-end alcove containing nothing.

⚠️ **Constraints, all non-negotiable:**
- Mutation must be **free-a-node**, **hide-a-node**, or **add-a-node in previously empty space**.
  **Never resize a room in place** — that is the coincident-surface family (Issues 19/20/23) and
  `check_wall_overlap.gd` will fail.
- Added geometry must **abut, never overlap**; floor bridges sunk by `BRIDGE_SINK`.
- The mutation must **never remove the player's route to an objective**. One-shot, on a dead wall,
  reverting on the next look-away.
- Verify with a `walk_*` test driving a body along the House cellar→exit route before and after.

---

## §4 — The two global systems

### 4.1 The audio architecture overhaul

Agreed scope: full overhaul. This is the single largest fix for **F2**, because dread is almost
entirely an audio phenomenon.

**(a) A real bus layout.** Replace the ad-hoc runtime `"Backrooms"` bus with a project-wide layout:
```
Master
├── Music        (reactive stems)
├── Ambience     (beds, room tone)   ← reverb lives here
├── Creature     (footsteps, breath, growls)
├── SFX          (props, doors, stingers)
└── Body         (heartbeat, footsteps, breathing)   ← NEVER ducked
```
`Body` staying un-duckable is what makes the silence work: when the world goes quiet, your own pulse
is the only thing left. That is Dungeon Nightmares' signature effect and it is free once the routing
exists.

**(b) Per-level reverb** — P1.

**(c) Raycast occlusion.** For any looping positional emitter, cast one ray per ~0.2 s from the
emitter to the player's ear; on a miss, tween an `AudioEffectLowPassFilter` cutoff down (≈900 Hz) and
volume down ~6 dB; on a hit, back up. This is what makes a sound behind a wall *sound* behind a wall,
and it is the difference between a creature that is somewhere and a creature that is nowhere.
⚠️ Poll at 5 Hz, not per-frame — 40 emitters × 60 fps of raycasts is not free.

**(d) Reactive music.** Two to four stems per level (bed / tension / threat / sting), cross-faded
from `get_panic_ratio()` and from creature state. The heartbeat is currently the *only* panic-reactive
audio in the game.
⚠️ Do **not** make music a *tell* — a stem that reliably rises when a creature spawns is a HUD readout
by another name (Issue 34). It should follow panic, which the player already knows about.
**Exception:** the deliberate, taught, level-specific case (the Nightmare level's silence — see
`DUNGEON_NIGHTMARES.md`), where the tell *is* the mechanic and is hinted a level earlier.

**(e) Audible creatures.** Object 12 is silent while patrolling and chasing. Give it footsteps
(distance-scaled, `unit_size ~12`), a low proximity growl loop (`creature_growl_near.wav` already
exists on disk, unused), and a distinct chase layer. Same for the Nightmare level's Matron.
⚠️ This makes Level 6 *easier* (you can hear it coming) and *much* scarier. That is the right trade
and it matches the Alien: Isolation lesson — the alien is loud on purpose.

**(f) Fix `RandomAmbient`'s placement** — P9.

**Also worth adding, near-free: an infrasound bed.** A 19 Hz sine at −26 dBFS under the existing
ambient beds. The Vic Tandy laboratory case traced a persistent sense of "presence" and cold dread to
a 19 Hz fan; ~19 Hz sits near the eyeball's resonance (smearing peripheral vision) and the chest
cavity's (producing breathing difficulty read as dread). It is ~15 lines in a `make_sfx` script.
⚠️ It only reaches the player through headphones or a subwoofer, so it **must be a bonus layer,
never a tell** — a mechanic inaudible on laptop speakers would be a fairness violation.

### 4.2 Shadows — approved, staged

> ⚠️ **RE-SCOPED (2026-07-27).** The flashlight **already** casts shadows in all nine level scenes and
> already renders them (see the §2.5 correction). Half of this proposal is therefore *done*, and the
> free half is the valuable one: **go use the silhouette you already have.** What remains genuinely
> unbuilt is shadow casting on **static `OmniLight3D` room lamps** — and that is the risky half,
> because `level_1.gd:173-175` deliberately depends on lamps *not* being occluded (the Lab dark wing
> is dark by distance, not by shadow). ⚠️ Also check unshaded billboards
> (`apparition.gd:101`, `creature_smiler.gd:36`, `creature_shapechanger.gd:55`,
> `living_mirror.gd:70`): an unshaded flat quad still casts, and may read as a floating rectangle.

**Approved:** enable shadow casting on the flashlight and a small number of key lights, rolled out
**one level at a time**, screenshot-verified, with an emission re-audit per level.

This is the highest-leverage *visual* change available: it converts every existing prop and creature
into a potential silhouette scare for near-zero content cost, and it unlocks three scares that are
currently impossible (a moving shadow, a shape resolving out of darkness, a figure silhouetted in a
doorway).

⚠️ **Risks to check per level:**
- Shadow-casting makes occluded areas genuinely darker. Findability of notes, keycards and breakers
  must be re-verified — these levels are lit at ~0.45 energy with very little margin.
- Performance: cap shadow-casters. The flashlight plus 2–3 lights per level, not every lamp.
- Shadows do **not** change emission values (they change light falloff), so the Issue 21/27/33
  tuning survives. That is why shadows are approved and fog is not.

### 4.3 Fog — a flagged EXPERIMENT, not a decision

The user's initial instinct was shadows **and** fog. The research pushed back hard, and the pushback
is sound: the no-fog / no-glow / no-SSAO configuration is load-bearing for **every material's
emission tuning across every level**, and fog would recolour all of it at once. Silent Hill's fog is
the most famous atmosphere tool in the genre — and it originated as a PS1 draw-distance workaround,
which is a seductive parallel that does not transfer to a project with eight levels of already-tuned
emission.

**Agreed landing:** try fog on the **Nightmare level only** — a brand-new level with no legacy
emission tuning to break — measure it, and only then consider a retrofit. Nothing retrofits until
that experiment reports.

**The substitutes to use meanwhile**, and they are genuinely good:
- **Light radius** — a steep `omni_attenuation` plus a black `Environment.background` and very low
  ambient gives you "you cannot see the far wall" for free, and it is physically motivated.
- **Geometry occlusion** — CSG is free here. Never align two doorways across a room; cap straight
  sightlines. This is the real source of claustrophobia in every game people credit fog for.
- **Dark albedo** (≤ 0.30 value). At 0.45 light energy, albedo contributes far less than emission, so
  a dark wall falls off to black inside the light radius on its own.
- **Reverb** (P1) — the audio substitute for atmospheric depth.

⚠️ Do **not** fake fog with a depth-fade `ColorRect` shader. It would fight `PanicHUD`'s
`BlurRect`/`TintRect` stack and it is fog by another name.

---

## §5 — The three new levels

All three accepted by the user. Placed in the agreed order (§6).

### 5.1 THE RETURN — the P.T. loop (new level 11, after The Void)

**Core mechanic:** the loop that is never quite the same. **Exemplar:** P.T. **Cost:** one script
(~350 lines), 2 textures, 3 SFX. **The cheapest level in the game to build.**

**Premise.** The player opens the Void's exit door and steps into **the intro room**. Candle, table,
note, single exit door. Reading the note gives the original text. The exit door opens onto… the intro
room. Again.

**Eight passes.** Each pass, exactly one thing is different:

| Pass | Change |
|---|---|
| 1 | Nothing. (Establishes the loop; the first pass teaches.) |
| 2 | The note's last line: `We are watching.` → `We were watching.` |
| 3 | The candle is out. A `Watcher` (P3) stands where the wheelchair was. |
| 4 | The room is 20 % larger. (A full `RoomBuilder` rebuild at a new size — legal because the whole room is rebuilt, never resized in place.) |
| 5 | The exit door is on the opposite wall. |
| 6 | Two tables. Two notes. They disagree. |
| 7 | Silence — the ambient bed is gone for the whole pass (P5, held). Footstep echo on, with trail steps (P2). |
| 8 | The note is signed **SUBJECT 46**, and the wheelchair is occupied. |

**One verb: walk to the door.** No panic pressure beyond ambient decay. No fail state except the
panic bar, which will not fill because nothing raises it. This is the game's only unloseable level,
which is exactly why it can afford to be its most upsetting — Grip's Lesson 4 is that *"fun gameplay
is just too fun"*, and engaging mechanics consume the attention that would otherwise be spent being
afraid.

**Why it belongs.** The twist ending is *already* a loop back to the intro room. This level is the
twist's setup: it teaches that the intro room is a place you return to, so that when `_corrupt_room()`
fires for real it reads as the ninth pass rather than as an ending screen.

**Reuses:** `intro_room.tscn`, `_corrupt_room()`'s conditional re-dressing, `RoomBuilder`, `Watcher`,
P2, P5.

---

### 5.2 OBSERVATION — the anomaly level (new level 2, between the Lab and the House)

**Core mechanic:** anomaly spotting. **Exemplar:** The Exit 8; I'm on Observation Duty. **Cost:** one
script (~500 lines), 4 textures, 4 SFX.

**Why early.** It teaches the perceptual habit that `MovedProp` (P6) then exploits for the remaining
nine levels. Put it late and P6 has no grammar to lean on.

**Premise.** Subject 47 is put on the *other* side of the glass. A monitoring station with a bank of
CRTs showing four rooms of the facility — and one corridor the player must walk. The instruction, in
protocol register via `NoteUI`: *"Compare. If the corridor is as recorded, proceed. If it is not,
return to this room."*

**Loop.** A ~25 m `RoomBuilder` corridor, walked end to end. At the far end, a door; behind it, the
monitoring station again. Eight passes, `randf() < 0.45` chance of an anomaly per pass, ~20 anomalies
authored, **never repeated within a run**.

**Anomaly catalogue** (all XS, all one-liners):
a ceiling fitting missing (`queue_free` one lamp) · the wall poster mirrored (`uv1_scale.x *= -1`) ·
7 doors instead of 6 (add a `fake_door.gd`) · the corridor 3 m longer · the player's own footstep
sound a half-tone lower · a `Watcher` at the far end · the floor material is the *Lab's* floor · the
CRTs in the station show the corridor **with the player still in it** · a door open that was closed ·
the wainscot band at the wrong height · one torch burning blue · **no anomaly, but the ambient bed is
silent** (a false positive the player will report — and being wrong costs a strike).

**Fail:** a wrong call = `flash_scare` + 15 panic + the pass repeats. Three wrong calls = the panic
bar does the rest. This is KONTUR's exact `3 × 18 = 54 > 50` arithmetic and it needs no new fail math.

**Fairness:** pass 1 is guaranteed anomaly-free and the note states the rule. Pass 2 is a guaranteed
*obvious* anomaly (the missing lamp), so the verb is taught before it can kill.

⚠️ **Do NOT retrofit this onto the Backrooms hub.** Tempting — Zone 1 is literally "an identical
re-randomised hub" — but the hub already carries the down-arrow puzzle, and requiring a second
perceptual audit of the same geometry at the same 18-panic failure cost is Issue 18 in its purest
form. See §8.10.

---

### 5.3 THE ANECHOIC CHAMBER — the silence level (new level 5, between the Corridor and the Backrooms)

**Core mechanic:** silence, room tone, and the body. **Cost:** one script (~450 lines), 3 textures,
6 SFX. **Showcases the §4.1 audio overhaul.**

**Premise.** A sound-testing suite: three chambers off a control room. Chamber 1's ambient bed is
normal. Chamber 2 is ducted −18 dB and heavily damped. Chamber 3 — the anechoic room, wedge-foam
walls — sits at **−60 dB**, and the player's own footsteps and heartbeat become the only audio in the
game. Real anechoic chambers famously make people hear their own body; that is the level's thesis.

**Puzzle.** Three tone generators, three chambers. From the control room, identify which chamber a
tone is *actually* being emitted in — by ear alone. The room tones (P1) are the only discriminator,
and one chamber's tone is piped in from another (P2's "the sound that lies about position").
**No HUD, no meter, no readout.** Legal under Issue 34 because the *audio* is the puzzle, exactly as
the Lab dark wing's beacon is the puzzle rather than a solver for it.

**The horror.** In the anechoic chamber, `player.gd`'s existing panic-driven heartbeat becomes the
loudest thing in the game. Panic rises → heartbeat rises → the player hears their own panic → panic
rises. **The level's dread mechanic is a feedback loop the player is already carrying.** Add the 19 Hz
bed (§4.1) beneath the silence and the sensation has no attributable source at all.

**Fail:** panic bar only. No creature, no trap, no strike.

⚠️ **No `DarkZone`.** The chambers are lit; the deprivation is auditory. Taxing darkness *and* silence
is Issue 18.
⚠️ The heartbeat must route to the un-duckable `Body` bus (§4.1) or the whole level does not work.

---

## §6 — The escalating-unreality pillar

**Stated by the user, 2026-07-27, and now a design rule:**

> The game starts with something ordinary and human. The further the player goes, the further from
> reality they get. Locations must become progressively weirder and scarier.

This is also recorded in `CLAUDE.md` and `README.md`.

**The agreed order (8 → 12 playable levels):**

```
0   Intro room          ordinary
1   The Lab             institutional, real
2   OBSERVATION         real, but you are being watched      ← new (§5.2)
3   The House           domestic, haunted
4   The Corridor        hotel, decaying
5   ANECHOIC CHAMBER    sensory deprivation                  ← new (§5.3)
6   The Backrooms       impossible space
7   KONTUR              (realism dip — flagged)
8   THE BREACH          (realism dip — flagged)
9   THE NIGHTMARE       dream                                ← new (DUNGEON_NIGHTMARES.md)
10  The Void            broken geometry
11  THE RETURN          the loop                             ← new (§5.1)
--  Twist ending
```

### ⚠️ The flagged dip — an open question, deliberately not resolved

The curve is currently **non-monotonic**. The Backrooms (6) is fully unreal — impossible space,
loops, mono-yellow void — and then KONTUR (7) and The Breach (8) drop back to *coherent, real-world*
Soviet facility interiors before the Nightmare and the Void go unreal again.

Three options were put to the user, who chose to **note it and decide later**, possibly doing both:

1. **Degrade 5 and 6 in place** (recommended). Keep the order — reordering breaks every cross-level
   hint gate KONTUR depends on. Instead make KONTUR and The Breach *lose their coherence as you walk
   through them*: corridors longer coming back, rooms that repeat, geometry that stops obeying the
   floorplan. And reframe it: **after the Backrooms, "reality" returning is itself wrong** — the
   experiment is showing you a facility because you want one. P11 is the tool.
2. **Accept it as a deliberate breather** — a Resident-Evil-style safe-room contrast that makes the
   Void hit harder.
3. **Reorder.** Cleanest on paper, expensive in practice: KONTUR's eight gates are answered by hints
   planted in the Lab, House, Corridor and Backrooms, and the Backrooms Flood holds the digits for
   KONTUR's roster code. Reordering means re-planting every hint.

**Do not resolve this silently in an implementation session.** It is the user's call.

---

## §7 — Assets

**Budget:** effectively lifted for this work, with a MUST/NICE split so generation can stop early.
Prefer **PolyHaven / AmbientCG (CC0)** for anything that is a standard tiling PBR surface. Reserve
generation for unique horror imagery.

**Note the ratio, because it is the point: P1–P11 need ZERO new textures.** Every one of the eleven
retrofits is script, audio, or bus work. Textures are only needed for the new levels.

### 7.1 Format gotchas — read before generating anything

1. **JPEG data inside a `.png`.** The nano-banana-pro / Gemini pipeline does this. Godot imports with
   `valid=false`, produces no `.ctex`, `load()` fails — but **`ResourceLoader.exists()` still returns
   `true`**, so the guard passes and the prop renders **blank with no error** (Issues 1 and 25).
   ```bash
   file <path>.png                            # must say "PNG image data"
   sips -s format png <path> --out <path>
   # then delete the stale .import AND game/.godot/imported/<name>-*
   ```
2. **Fake transparency.** A generator asked for "transparent background" may paint a **checkerboard
   onto opaque RGB**. A checkerboard in a preview is not proof of alpha. Verify:
   `Image.open(p).mode` must include `'A'` **and** `getchannel('A').getextrema() != (255,255)`.
   Billboard cutouts render as a solid rectangle otherwise — the `apparition_figure.jpg` bug.
3. **Art on a `QuadMesh`, never a `BoxMesh` face.** A box renders a magnified *crop* of its own art
   (Issue 24, recurred as 31). `door.gd:build_visual()` is the pattern: box for edge/depth, quad for
   art.
4. **Aspect ratio must match the mesh**, and size the quad from the source aspect (the KONTUR roster
   plate lesson).
5. **`RoomBuilder.make_material()` negates V itself** — callers pass a *positive* `uv1_scale.y`. A
   positive scale on a raw material renders walls upside-down (Issue 19).
6. **Wall props need `inset ≥ 0.16`**, or **0.22** if anything hangs behind them.
7. Every new asset needs `/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import`.
8. ⚠️ **Asset folder names already drift from level numbers and that is fine — do not rename them.**
   `level_4_void/` holds the assets for what is currently level 7; `level_3_corridor/` happens to still
   match. The folders are named for the level's *identity*, not its index, and renaming would break
   every `.import` UID and every `.tres` `ext_resource` path. New folders in this document follow the
   **target** order (`level_2_observation/`, `level_5_anechoic/`, `level_9_dungeon/`) and should not be
   renamed later either. Note `level_5_anechoic/` sits alongside the existing `level_5_kontur/` — they
   are distinct folders and the collision is cosmetic; **audio *base names* are what must stay
   globally unique**, not folder names.

### 7.2 Prompt conventions

Every prompt must carry the rendering constraints, because the engine has **no glow, no bloom, no
fog, no SSAO**, Linear tonemap, and emission > 1.0 clamps to flat white:

> *flat orthographic elevation, filling the frame edge to edge, evenly lit, no cast shadows, no
> perspective, no background around the object, no glow, no bloom, no rim light, no lens flare*

And for props specifically: **no wall or environment baked into the art.** Issue 35 — the old KONTUR
mailbox depicted its own wall and could therefore never read as 3D.

### 7.3 The list

**MUST (6 images):**

| File | Prompt |
|---|---|
| `shared/watcher_figure.png` — 1024×2048, **real RGBA alpha** | *"Full-body silhouette of a motionless standing human figure seen from 30 metres, front-on, arms at sides, head slightly tilted. Almost entirely dark grey-black with only the faintest edge separation; no facial features at all, no eyes, no highlights. Flat matte rendering, NO glow, NO bloom, NO rim light. Completely transparent background — alpha cutout, no backdrop, no floor, no shadow. Slightly wrong proportions: arms 10% too long, shoulders 5% too narrow. Deliberately low contrast."* |
| `shared/watcher_figure_close.png` — same, framed for a 6 m read | The silhouette resolves into a hospital gown and a shaved head. **Still no face.** Void and THE RETURN only. |
| `level_2_observation/observation_crt_frame.png` — 2048×1024 landscape | *"A bank of four 1970s Soviet CRT security monitors in a dark steel rack, powered off, dead grey-green screens, dusty. Straight-on orthographic product view, evenly lit, flat matte. NO glow, NO screen emission, NO bloom, NO reflections. Isolated on pure black background with no wall, no floor, no environment behind the rack. Photographic realism, muted desaturated palette."* |
| `level_2_observation/observation_poster.png` — 1024×1024 | *"Soviet institutional safety poster, faded ink on aged paper, a stylised figure and Cyrillic caption, front elevation, evenly lit, flat matte, no background beyond the paper edge."* **Generate once**; produce `observation_poster_mirror.png` with `sips` — do not spend a second generation on a flip. |
| `level_5_anechoic/anechoic_foam.png` — 1024×1024 **tileable** | *"Seamless tileable texture of grey acoustic anechoic-chamber wedge foam, regular pyramid array, seen straight on. Evenly lit flat matte, no cast shadows between wedges beyond faint form shading, NO ambient occlusion darkening, NO glow. Desaturated cold grey, slightly dusty and aged. Perfectly tiling on all four edges."* |
| `level_5_anechoic/anechoic_wall.png` — 1024×1024 tileable | Painted steel test-chamber wall with a wainscot band at the bottom (project convention: wall textures carry the wainscot at floor level). |

**NICE:** THE RETURN's mutating note. **If `NoteUI` renders text, generate nothing** — a string
branch is free.

**Sourced, not generated:** every tiling surface for OBSERVATION's corridor (institutional wall,
floor, ceiling) — reuse the Lab's, which is thematically correct since it *is* the same facility.

### 7.4 Audio — `tools/make_sfx_atmos.py` (new)

Seeded (`random.seed(1701)`), stdlib-only, 16-bit mono 44.1 kHz, header in the style of
`tools/make_sfx_level6.py`. Output → `game/assets/audio/shared/`.
⚠️ **Base names must be globally unique** — `GameState.load_audio()` resolves across every subdir, and
`door_slam` already collides in two folders with the `level_3_corridor` copy silently winning.

| File | Spec |
|---|---|
| `subsonic_bed.wav` | 30 s seamless loop. 19.0 Hz sine at −26 dBFS + 21.5 Hz at −30 dBFS (slow beat), plus pink noise at −42 dBFS so the file is not literally silent to a compressor. §4.1. |
| `telegraph_groan.wav` | 3.2 s. Three descending detuned sawtooth partials (110 → 82 → 61 Hz), each with a 0.4 s exponential attack and a 1.1 s tail; band-passed 60–400 Hz. **P4's false-ceiling telegraph.** |
| `wade_distant.wav` | 4.8 s loop. Filtered noise bursts at irregular 0.7–1.3 s intervals, low-passed 900 Hz, with a 180 ms slap delay. **P10.** |
| `footstep_trail.wav` | 0.35 s. Re-synthesised 3 semitones below the existing footstep with a 250 ms tail — the *decelerating* trail step. **P2.** Purpose-made rather than a pitch-shift, following the `apparition_snarl` precedent. |

`HoldBreath` (P5) is a **bus operation, not an asset** — no file needed. Listed so nobody generates one.

Plus `tools/make_sfx_anechoic.py` and `tools/make_sfx_observation.py` for the two new levels
(`ambient_anechoic`, `tone_a/b/c`, `foam_brush`, `chamber_door_seal`; `ambient_observation`,
`crt_switch`, `verdict_correct`, `verdict_wrong`).

---

## §8 — Anti-patterns: do not build these

### 8.1 Fake crashes, fake BSODs, fake save-corruption, fake OS dialogs, fake volume drops
Eternal Darkness' most-cited effects, and wrong for **this** project specifically. It is a macOS
`.app` under active development with a `user://playtest_log.txt`, a `JournalUI` archive, and
per-level progress snapshots. A fake "SAVE DATA CORRUPTED" during a `DebugLog` session produces a real
bug report and poisons the playtest data the whole `game-testing` protocol depends on. It also breaks
the fiction: the observers are watching Subject 47, not the person holding the mouse.
**Use P8's diegetic suite instead** — same fourth-wall frisson, inside the fiction.

### 8.2 Any HUD readout that indicates progress toward, or proximity to, a solution
Issue 34 documented this precisely once: `set_breaker_proximity()` *"solved the wing outright — and
being straight-line-distance-only it also lied, reading a warm ~0.43 from inside a dead end. Worse,
it masked the fact that `_spawn_dark_breaker_tell()` was a one-line stub"* for several sessions. The
failure mode has two halves and both recur: the readout removes the puzzle, **and** it hides the fact
that the real tell was never built. A compass, a warmer/colder, an anomaly counter, a "3 of 8 gates"
bar, a creature-proximity indicator — all the same mistake.

### 8.3 A second observation-dependent creature
`creature_stalker.gd` is at its ceiling, with both known cheeses already patched (gaze panic at 0.6,
`STARE_OFF_TIME` costing ~48 panic). The documented player complaint about SCP-173-style mechanics is
that they force constant look-backs, causing disorientation and cornering — and the Void already
stacks that against a broken floor with a fatal hole and two `DreadZone` rooms.

### 8.4 A second chase level
Level 6 is the chase level. Outlast's binary — *"you're either being chased or not, with no middle
ground"* — is the failure state of chase-led design, and SOMA's monster-free Safe Mode (whose "Wuss
Mode" precursor became its most-subscribed Workshop mod) is what happens when monster encounters
crowd out the atmosphere a game is actually good at. `CLAUDE.md`'s own line — *"horror comes from
atmosphere/sound/environment, historically NOT from enemy AI"* — is the correct self-assessment. One
chase level in twelve is the right ratio.

### 8.5 A breath-holding mechanic
New input action + new HUD affordance to teach it + a new detection system to punish it — and it
**double-taxes stillness**, which the Smiler and the HOLD apparition already tax. Issue 18. Its
punishment in Alien: Isolation is *a delay*, not a death, which this project's instant-fatal creature
contract cannot accommodate anyway.

### 8.6 Making the panic *rules* ambiguous or unreliable
P8 lies about the **readout** for under a second and reverts. That is legal. Making the bar's actual
behaviour non-deterministic is not: twelve levels of fail economy are tuned arithmetic. Amnesia could
afford a placebo sanity meter because Amnesia's meter *did nothing*; this one does everything.
The "hide the panic meter" idea (`drafts/REPORT.md` #2) is superseded by P8 for exactly this reason.

### 8.7 More `RandomAmbient` variety at the current rate
The instinct after "habituation kills fear" is to add a fourth and fifth ambient sound. The research
says the opposite: **the problem was never variety, it was rate.** Two playtest logs were wall-to-wall
with spikes and the player read the metronome as a creature repeatedly appearing beside them; the
18–35 s retune was the fix. Adding sounds without adding gap re-creates the bug at higher fidelity.
If anything, add P9's gate and consider 25–50 s.

### 8.8 Emissive scary props
Issues 21 / 27 / 33 are a three-time recurrence. Emission is most of a surface's colour at 0.45 light
energy; above 1.0 it clamps to flat white; and the practical result is that the thing you wanted
**hidden and frightening** becomes the brightest object in the room. **No glowing monsters, no glowing
eyes, no glowing anomalies.** The engine's answer to "make it stand out in the dark" is **silhouette**
(Issue 35 — *"the SILHOUETTE carries a prop here and art does not"*) and **audio**.

### 8.9 A depth-fade "fog" shader
See §4.3. Fog is a flagged experiment on one new level only; faking it with a full-screen shader
would fight `PanicHUD`'s existing `BlurRect`/`TintRect` stack and is fog by another name.

### 8.10 Anomaly-spotting layered onto the Backrooms hub
The strongest single Issue-18 trap available. The hub already carries the down-arrow puzzle;
requiring a *second* perceptual audit of the same geometry, with the same 18-panic failure cost, taxes
exactly the posture the existing puzzle demands. Build §5.2 as its own level.

### 8.11 Punishing the player for a scare they could not have seen coming
Named twice in this repo already (KONTUR Gate 7, the Backrooms Flood), and once resolved correctly —
the Lab nook payoff is *"deliberately SURVIVABLE — no rule, no fail state,"* because *"an unavoidable
event must never coin-flip a death."* Every proposal in §3 that adds a scare adds it with **zero
panic and no fail state.** That is the finding, not caution: Isolation's Director routes the alien
*away* at peak menace, and The Bunker scripts two or three encounters in an entire game. Fear survives
on the *possibility* of consequence, not its frequency.

---

## §9 — Phased roadmap

Ordered by value per unit of risk. Each phase is independently shippable.

### Phase 1 — the XS wins (fixes F1 and F2 for almost nothing)
1. Fix the six defects from §2.11 (they are blocking, and #4 gates P8).
2. **P5** `HoldBreath`, wired into `flash_scare()` — improves every existing survivable scare at once.
3. **P9** panic gate + LOS fix on `RandomAmbient`.
4. **P1** `RoomToneZone` — start with the Lab dark wing and Backrooms Zone 2.
5. **P2** stop-delayed footstep echo in KONTUR's escort.
6. **P4** the False Ceiling in Corridor Zone B.

*Nothing in Phase 1 touches a difficulty constant, a puzzle, or a texture.*

### Phase 2 — the world starts to notice you (fixes F3)
7. **Shadows**, one level at a time (§4.2), Lab first.
8. **P3** `Watcher` (needs one texture).
9. **P6** `MovedProp` in the House.
10. **P7** death-degradation.

### Phase 3 — the deeper systems
11. **§4.1** the full audio architecture: bus layout, occlusion, reactive stems, audible Object 12.
12. **P8** the sanity-effect suite.
13. **P10** the unseen thing in the Flood.
14. **P11** geometry mutation in the House (last; only proposal with real regression risk).

### Phase 4 — the new levels
15. **THE NIGHTMARE** (`DUNGEON_NIGHTMARES.md`) — the largest build, and the fog experiment's venue.
16. **THE RETURN** (§5.1) — cheapest, highest thematic payoff.
17. **OBSERVATION** (§5.2).
18. **THE ANECHOIC CHAMBER** (§5.3) — best after §4.1 ships, since it showcases it.
19. The level renumbering, as **one commit**, with `check_level_resume.gd` extended to assert the
    full chain in both directions.

### Verification discipline
Every phase follows the project's existing rule: **a green test run is not a good build — read the
numbers.** New assertions go in at the same time as the feature, not after (that is the explicit
lesson from Issue 18's same-day recurrence). And **do not trust a clean screenshot run as evidence
that geometry is sound** — run `tests/check_wall_overlap.gd`.

---

## §10 — Sources

Design and post-mortem
- [Frictional Games — 9 Years, 9 Lessons on Horror](https://frictionalgames.com/2019-10-9-years-9-lessons-on-horror/)
- [Game Developer — Game Design Deep Dive: Amnesia's Sanity Meter](https://www.gamedeveloper.com/design/game-design-deep-dive-i-amnesia-i-s-sanity-meter-)
- [Game Developer — The Perfect Organism: The AI of Alien: Isolation](https://www.gamedeveloper.com/design/the-perfect-organism-the-ai-of-alien-isolation)
- [AI and Games — How the Beast Works in Amnesia: The Bunker](https://www.aiandgames.com/p/how-the-beast-works-in-amnesia-the)
- [Game Developer — A Lack of Fright: Examining Jump Scare Horror Game Design](https://www.gamedeveloper.com/design/a-lack-of-fright-examining-jump-scare-horror-game-design)
- [Game Developer — The Balancing Act of Tension in Horror Game Design](https://www.gamedeveloper.com/design/the-balancing-act-of-tension-in-horror-game-design)
- [Game Developer — Terrifying players with unstable level design in Layers of Fear](https://www.gamedeveloper.com/audio/terrifying-players-with-unstable-level-design-in-i-layers-of-fear-i-)
- [PC Gamer — Frictional on designing SOMA's monster-free Safe Mode](https://www.pcgamer.com/frictional-on-designing-somas-new-monster-free-safe-mode/)

Audio
- [GameSpot — F.E.A.R. Designer Diary #2: Audio and Music](https://www.gamespot.com/articles/fear-designer-diary-2-audio-and-music/1100-6134936/)
- [Game Informer — Noises In The Dark: Exploring The Sounds Of Dead Space](https://gameinformer.com/b/features/archive/2009/12/11/feature-noises-in-the-dark-exploring-the-sounds-of-dead-space.aspx)
- [gamesounddesign.com — Silence In Sound Design](https://gamesounddesign.com/Silence-In-Sound-Design.html)
- [Frontiers in Virtual Reality — Diegetic and object-based spatial audio: a systematic review](https://www.frontiersin.org/journals/virtual-reality/articles/10.3389/frvir.2026.1696677/full)
- [Higgs Centre — The Haunted Frequency (19 Hz infrasound)](https://higgs.ph.ed.ac.uk/outreach/higgshalloween-2021/haunted-frequency)

Perception and anomaly
- [Eternal Darkness Wiki — Sanity Effects](https://eternaldarkness.fandom.com/wiki/Sanity_Effects)
- [TheGamer — Every Game Would Be Better With The Eternal Darkness Sanity System](https://www.thegamer.com/eternal-darkness-switch-2-gamecube-sanity-effects/)
- [Ludonode Studios — The Art of the Loop: What The Exit 8 Teaches Us](https://ludonodestudios.medium.com/the-art-of-the-loop-what-the-exit-8-teaches-us-about-liminal-horror-and-anomaly-design-a52b5c4f1385)
- [Game Informer — Moments: The Stalking Mannequins Of Condemned](https://gameinformer.com/b/features/archive/2012/11/02/moments-the-stalking-mannequins-of-condemned.aspx)
- [Game Studies — Gothic Gaming: Kitty Horrorshow's Anatomy](https://gamestudies.org/2403/articles/leblanc)
- [Game Developer — P.T. (Silent Hills teaser) game analysis](https://www.gamedeveloper.com/design/p-t-silent-hills-teaser-game-analysis)
- [Third Coast Review — Iron Lung Masters the Unseen](https://thirdcoastreview.com/2022/03/14/review-iron-lung)
- [Psychology Today — Why the Uncanny Valley Phenomenon Creeps You Out](https://www.psychologytoday.com/us/blog/social-instincts/202311/why-the-uncanny-valley-phenomenon-creeps-you-out)

In-repo
`ISSUES_SOLUTIONS.md` (Issues 1, 6, 9, 18, 19, 20, 21, 23, 24, 25, 27, 31, 33, 34, 35, 40) ·
`COMMENTS.md` (the fail philosophy) · `BUG_FIX.md` · `GAME_MECHANICS_IDEAS.md` (the live backlog;
absorbs the archived `drafts/REPORT.md` + `drafts/IDEA_HISTORY.md`) · `TEXTURES.md`
