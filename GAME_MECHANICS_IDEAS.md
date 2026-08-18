# GAME_MECHANICS_IDEAS.md — the live idea backlog

**Written:** 2026-07-27. **Supersedes** `REPORT.md` and `IDEA_HISTORY.md`, both now in `drafts/`.

**The two numbers that should drive every decision in here:**
- **37 accepted ideas across four design documents. Two are built.** (6 partial, 25 untouched, plus
  6 known defects unfixed — §2, §3.)
- **The game is already playable end to end.** Nine scenes, intro through ending, all completable.

So the bottleneck is not ideas. §6 cuts the 25 unbuilt rows down to **9**, and §4 adds only **5** new
ones out of 26 researched. ⚠️ **§6.2 and §7.1 contain a recommendation to cut three of the four new
levels you accepted on 2026-07-27 — that is your decision, not this document's.**

---

## §1 — How to read this file

This is the **single entry point** for "what should we build next." It exists because the project had
accumulated four overlapping idea documents written at different times, each partially superseding the
others, with no one place recording what was actually *built*.

| Document | Status | Role |
|---|---|---|
| **`GAME_MECHANICS_IDEAS.md`** (this file) | **LIVE** | Build status, priority, new ideas, the rejection ledger. Start here. |
| `SCARY.md` | **LIVE — authoritative** | The deep spec for fear craft: P1–P11, the audio overhaul, three new levels, eleven anti-patterns. This file *points into* it and never summarises it away. |
| `DUNGEON_NIGHTMARES.md` | **LIVE — authoritative** | The deep spec for one new level (THE NIGHTMARE). Same relationship. |
| `BACKLOG.md` | **LIVE** | Shipped work + the six live defects reproduced in §3. |
| `backlogs/NN-<level>.md` | **LIVE — evidence** | The level-by-level improvement run, opened 2026-08-16. One file per level: what the user did with their hands on the controls, what it measured, and the costed items that came out of it. See §1a. |
| `drafts/REPORT.md` | **ARCHIVED** | The old accepted-not-built menu. Absorbed into §2. Do not edit. |
| `drafts/IDEA_HISTORY.md` | **ARCHIVED** | The old verdict ledger. Absorbed into §5. Do not edit. |

**The rule that keeps this file honest:** every status claim in §2 and §3 carries a `file:line` from
an audit of the code at commit `559514e`, **not** from what a design document claims about itself.
That distinction is not pedantry — it is how the shadow error in §2.0 was found.

⚠️ **`drafts/KONTUR.md` is the cautionary tale.** It is a stale doc that silently contradicts the
shipped game. Four overlapping idea files was that failure mode in slow motion. If you add a fifth
design document, say here what it supersedes.

### §1a — `backlogs/`, and what it supersedes (nothing)

Opened **2026-08-16**. It is **not** a fifth design document and it supersedes nothing. This file
stays the single entry point for *what to build next*; `backlogs/` is the **evidence layer beneath
it** — the record of a human playing each level and saying what was wrong, one file per level.

The distinction that keeps them from drifting:

- An idea that arrives from **design reasoning** belongs here (§4), and always has.
- An item that arrives from **someone playing the game** belongs in `backlogs/NN-<level>.md`, with
  the screenshot and the log line that produced it. Those never move here — only their *verdicts*
  do.
- **Deferred** items cross-post to §2 so they survive the level pass. **Rejected** items cross-post
  to §5 with the user's own words, so no future session re-pitches them. That is the whole contract.

| File | Level | Status |
|---|---|---|
| `backlogs/00-cross-level.md` | — | open (parking lot; **never acted on during the run**) — X1…X21 |
| `backlogs/captures/` | — | downscaled J-capture screenshots + session logs for levels whose pass has not run yet, so the evidence outlives the session-scoped temp dir it was captured into |
| `backlogs/00-intro.md` | Intro + twist ending | **verified** — 13 items, 2 rounds. Twist ending deliberately deferred |
| `backlogs/01-lab.md` | 1 The Lab | **verified** — 3 revision rounds |
| `backlogs/02-house.md` | 2 The House | **verified** — 18 items + the maze redesign |
| `backlogs/00-test-hardening.md` | — | **H1+H2 built** 2026-08-17 (coverage by construction; a live positive control in every guard). H3 (build-time invariants) and H4 (completion bots) not started |
| `backlogs/03-corridor.md` | 3 The Corridor | **verified** — 3 revision rounds. ⚠️ Built from banked evidence with **no playtest before the pass** (the user's call); the final replay produced zero captures at peak panic 49 %, down from 97 % |
| `backlogs/04-backrooms.md` | 4 The Backrooms | **verified** — 4 revision rounds. Eight sealed alcoves opened, the Flood made a six-fragment puzzle, the Sprawl's real wall gated behind a crate in the dark. Final replay: zero captures, cleared all three zones |
| `backlogs/05-kontur.md` | 5 KONTUR | **in progress** — never playtested this run; carries 6 machine findings from the hardening sweep, incl. a real defect (`_restore_progress()` never restores `_dark_x`, so a back-door return re-rolls the Blackout answer while the ledger says the gate was passed) |
| `backlogs/06-breach.md` | 6 The Breach | not started — 4 machine findings filed. Every hiding place is stretched, and hiding is that level's entire counter-play |
| `backlogs/07-nightmare.md` | 7 THE NIGHTMARE | not started — 5 machine findings filed. Both cots stretched 3.194× |
| `backlogs/08-void.md` | 8 The Void | not started — 7 machine findings filed. ⚠️ **The Void has no shell (142 escaping rays from 48 standable points)**, two interactables sit in a pocket no route reaches, and until 2026-08-17 nothing had ever walked that level |

The run is **strictly serial** — a level is played, backlogged, approved, built, tested and
re-played before the next one opens. `.claude/agents/level-improver.md` is the agent that does it
and carries the authority boundaries.

⚠️ **This run is deliberately the counterweight to this file's own headline number** (*37 accepted
ideas, two built*). The bottleneck was never ideas. Every item in `backlogs/` has a person and a
screenshot behind it, which is the one thing the 37 do not.

---

## §2 — Build status of the existing corpus

### 2.0 Three findings that change recommendations, not just status

**(a) ⚠️ The flashlight casts shadows. It always has. `SCARY.md` and `CLAUDE.md` both say otherwise.**

`SCARY.md` §2.5 states *"Nothing casts shadows"* and §4.2 builds on it, claiming three scares are
*"currently impossible"* — a moving shadow, a shape resolving out of darkness, and a figure
silhouetted in a doorway. `CLAUDE.md` repeats the claim, inherited from `level_1.gd:1319`
(*"nothing in this project casts shadows anyway"*).

**All three of those scares are available today.** The player's `Flashlight` is a
`SpotLight3D` with `shadow_enabled = true` in **every level scene**: `level_1.tscn:374`,
`level_2.tscn:339`, `level_2_1.tscn:312`, `level_3.tscn:421`, `corridor.tscn:32`,
`backrooms.tscn:31`, `kontur.tscn:31`, `level_6_breach.tscn:31`, `intro_room.tscn:32` — plus four
runtime lights in `intro_room.gd:142,381,703,734`.

Verified visually, not just by grep: a screenshot run of the Lab
(`tests/screenshot_level.gd`, shot `13_records_locker`) shows the steel locker throwing a hard cast
shadow onto the wall behind it, with lit pools either side. It renders. It is working now.

**What *is* true, and is load-bearing:** no **static level light** (the `OmniLight3D` room lamps)
casts shadows. `level_1.gd:173-175` depends on this deliberately — Records' lamp has
`omni_range = 11` and *is not blocked by walls*, so the Lab's dark wing is dark by **distance**, not
by occlusion. Enabling shadows on static lamps would change that room's darkness model and must be
re-verified against the wing's design.

→ **Re-scope.** `SCARY.md` §4.2 is not "enable shadows"; it is **"the flashlight already silhouettes
— go use it,"** plus an optional, riskier "extend to static lamps." The first half is a *zero-cost*
unlock of the three scares §4.2 wanted, available before any code is written. ⚠️ Note the interaction:
many creature billboards are `SHADING_MODE_UNSHADED` (`apparition.gd:101`, `creature_smiler.gd:36`,
`creature_shapechanger.gd:55`, `living_mirror.gd:70`), and an unshaded flat quad still *casts* — check
that a billboard's shadow does not read as a floating rectangle.

**(b) ⚠️ `carried_item` is destroyed on every level transition — this blocks two accepted ideas
architecturally.** `GameState.reset_level_state()` clears it (`game_state.gd:46-50`) and is called
first thing in `start_current_level()` (`:129`). `door.gd:126-139` accepts only same-level unlock
flags (`NONE / KEYCARD / CODE_ENTERED / TWIST_READ`). So the inventory idea and the cross-level half
of the backtracking idea are not merely unbuilt — they need a `GameState` change first. Budget it.

**(c) `CLAUDE.md`'s "No active enemy AI" pillar is factually stale.** `creature_object12.gd` is a
five-state pursuit AI with search memory, shipped in Level 6, and `DUNGEON_NIGHTMARES.md` §B4.2 specs
a second (the Matron). `drafts/REPORT.md:175` flagged this as *"the first real departure from the
project's stated 'no active enemy AI' design pillar"* — hypothetically. It already happened. The
honest restatement is `SCARY.md` §8.4's actual argument: **AI is rationed — one chase level in
twelve.**

Smaller corrections carried from the audit:
- `vignette.gd`'s no-op `spawn()` has **five** dead callers, not the one `BACKLOG.md` lists:
  `level_1.gd:122`, `level_2.gd:83`, `level_3.gd:29`, `corridor.gd:113`, `backrooms.gd:115`.
- The pacing coordination that exists runs **the wrong way**: `ApparitionDirector` defers to
  `RandomAmbient` (`apparition_director.gd:115-118`), never the reverse. P9 is exactly the missing
  return path, which is why it is cheap.

### 2.1 The table

Deduplicated across all four sources — where `SCARY.md` re-specs a `REPORT.md` item, that is **one
row**. Cost scale is `SCARY.md` §3's: **XS** = one script < ~80 lines, no assets · **S** = script +
1–2 procedural SFX · **M** = script + assets + level integration · **L** = a level or a system.

| Item | Source | Status | Evidence | Cost |
|---|---|---|---|---|
| **Nemesis pursuit level (Level 6, THE BREACH)** | REPORT #18 (+#14, #17 folded in) | **BUILT** | `level_6_breach.gd`, `level_6_breach.tscn`, wired at `game_state.gd:40,:138`; tests `check_level6_breach.gd`, `walk_level6_breach.gd` | — |
| **Cross-level navigation backtracking** (back doors + per-level snapshots) | REPORT #13 (half) | **BUILT** | `go_back()` `game_state.gd:161-165`; `entered_from_ahead` `:111`; `level_progress` `:105`, `:114-125`; six implementors incl. `level_1.gd:303`, `kontur.gd:350` | — |
| **Adaptive director pacing** → scoped to the *relief valve* | REPORT #1 → SCARY P9 | **PARTIAL** | `ApparitionDirector` exists and gates well (`apparition_director.gd:97,102,107,113,115-118`; `MAX_PANIC_RATIO 0.6` `:65`). **`RandomAmbient` has no panic gate at all** — `random_ambient.gd:42-70` never reads panic. No `director.gd`. | XS |
| **Chase & evasion system** (hide / slam doors / vault) | REPORT #14 | **PARTIAL** | `hiding_spot.gd`, `slam_door.gd` exist but are instantiated **only** by Level 6 (`level_6_breach.gd:98-99,351-357,377-381`). The agreed **House pilot never happened**. No `Vaultable` anywhere. | M |
| **Persistent progress save** | REPORT #3 | **PARTIAL** | `level_progress` is a plain in-memory `Dictionary` (`game_state.gd:105`), never serialised; no `user://save.dat`; `main_menu.gd:76-84` has START and QUIT only — **no Continue**. Does not survive an app restart. | M |
| **Stop-delayed footstep echo** | SCARY P2 | **PARTIAL** | `enable_footstep_echo()` `player.gd:423-432` fires exactly one phantom step (`:244-246`, `:251-253`); no `trail_steps`, nothing on `_is_moving` going false. One caller: `backrooms.gd:111`. | XS |
| **Sanity-effect suite (diegetic UI)** | REPORT #2 → SCARY P8 | **PARTIAL** | Panic feedback exists (blur/tint `panic_hud.gd:92-97`, heartbeat `player.gd:588-602`, `jolt_camera` `:384`) but **nothing lies**. No `set_deceptive_mode`, no `sanity` anywhere. ⚠️ Gated by defect §3(d). | S |
| **Shadows as an atmospheric tool** | SCARY §4.2 | **PARTIAL — better than documented** | Flashlight casts in all 9 scenes (see §2.0a). Static lamps do not, deliberately (`level_1.gd:173-175`). | XS→M |
| **`RoomToneZone` — runtime reverb buses** ⭐ | SCARY P1 | **NOT BUILT** | Zero `AudioEffect*` project-wide. Two buses total: `Master` + a runtime `"Backrooms"` (`backrooms.gd:39,:782-787`). | XS |
| **Audio architecture overhaul** (bus layout, occlusion, reactive stems, audible creatures) | SCARY §4.1 | **NOT BUILT** | No `default_bus_layout.tres`. Object 12 is silent while patrolling/chasing; `creature_growl_near.wav` sits unused on disk. | L |
| **`HoldBreath` — pre-scare silence dip** ⭐ | REPORT #7 → SCARY P5 | **NOT BUILT** | Only ducking is `silence_zone.gd:35-53`. `Screamer.flash_scare()` `screamer.gd:167-182` cuts straight to audio with no silence beat. | XS |
| **`Watcher` — distant motionless figure, zero panic** ⭐ | SCARY P3 | **NOT BUILT** | No `watcher` anywhere in `scripts/` or `tests/`. Needs 1 texture. | XS |
| **The False Ceiling — telegraphs that mean nothing** ⭐ | REPORT #5 → SCARY P4 | **NOT BUILT** | Corridor's event schedule (`corridor.gd:627-650`) is 11 events, every one of which delivers. No misdirection, no `misdirect.gd`. | XS |
| **`MovedProp` — the object that changed** ⭐ | REPORT #4 → SCARY P6 | **NOT BUILT** | No `MovedProp`. (REPORT #4's physics `FallingProp` was superseded by this; no `RigidBody3D` exists anywhere either.) | XS |
| **Death-degradation** ⭐ | SCARY P7 | **NOT BUILT** | No `deaths_this_level` in `game_state.gd`. Deaths counted for instrumentation only (`debug_log.gd:31,81-82`), explicitly never affecting behaviour. | S |
| **The unseen thing in the Flood** | SCARY P10 | **NOT BUILT** | `backrooms_zone3.gd` spawns two HOLD apparitions (`:354,:371`) and four water loops (`:126-131`) — no audio-only entity. | S |
| **Room-tone-masked geometry mutation** | REPORT #20 → SCARY P11 | **NOT BUILT** | Depends on P1. Nearest is `GlitchWall.go_solid()` (`glitch_wall.gd:76`) — solidity, not layout. | M |
| **Sequence fuse/valve puzzle** (replace the Lab breakers) | REPORT #12 | **NOT BUILT** | Still flip-once ×3: `breaker.gd:103-106` one-shot, counted at `level_1.gd:57,318-323`. No ordering, no fuses, no sockets. | M |
| **Item combination / 2–4 slot inventory** | REPORT #10 | **NOT BUILT** ⚠️ blocked | `carried_item` is **one slot** (`game_state.gd:8`, setter `:59-61`), enforced in KONTUR (`kontur.gd:704`). No combine verb. See §2.0b. | M+ |
| **Cipher puzzles** (code derived from two clues) | REPORT #11 | **NOT BUILT** | Zero `cipher` hits. `combination_lock.gd:13,145-148` takes one literal answer. | M |
| **Cross-level backtracking** (item found later opens an earlier door) | REPORT #13 (other half) | **NOT BUILT** ⚠️ blocked | See §2.0b — `reset_level_state()` destroys the carried item at every boundary. | S+ |
| **Hidden passages** | REPORT #15 | **NOT BUILT** | No `secret_passage.gd`. Nearest analogues are the Lab locker (`level_1.gd:516-523`) and `GlitchWall` seams. | M |
| **Optional lore collectibles + end-of-game count** | REPORT #16 | **NOT BUILT** | Journal archives notes (`game_state.gd:71-79`) but has no completion count; `ending.gd` never reads it. | S |
| **TTS-narrated notes** | REPORT #8 | **NOT BUILT** | No `tools/make_tts_notes.py`, no `voice_path`, no `assets/audio/notes/`. (`tools/make_pa_voice.py` is one baked PA line, not per-note.) | M |
| **Wall-maze minigame** | REPORT #9 | **NOT BUILT** | No `wall_maze`. `maze_chase_ui.gd` is the House map chase — a different mechanic. Placement was never decided. | M |
| **Investigation / deduction level** | REPORT #19 | **NOT BUILT** | No evidence terminal, no answer/verdict system. | L |
| **OBSERVATION — anomaly level (new level 2)** | SCARY §5.2 | **NOT BUILT** | `Observation` is a *room* in Level 1 (`level_1.gd:169`), not a level. | L |
| **THE ANECHOIC CHAMBER — silence level (new level 5)** | SCARY §5.3 | **NOT BUILT** | Zero hits. Depends on §4.1. | L |
| **THE NIGHTMARE — Dungeon Nightmares level (new level 9)** | DUNGEON_NIGHTMARES.md | **NOT BUILT** | Zero hits. The largest single build in the corpus. | L+ |
| **THE RETURN — P.T. loop level (new level 11)** | SCARY §5.1 | **NOT BUILT** | Zero hits. Documented as the cheapest level in the game. | M |
| **The 12-level renumbering commit** | CLAUDE.md / SCARY §6 | **NOT BUILT** | Current map is 9 entries (`game_state.gd:10`, constants `:34-43`, dispatch `:131-141`). Note the pre-existing oddity: `SCENE_LEVEL_3` is the *Void* at index **7**. | M |
| **Volumetric / depth fog** | SCARY §4.3 | **NOT BUILT — deliberately deferred** | Zero fog hits project-wide. Flagged EXPERIMENT, Nightmare level only. | — |

**Totals: 2 built · 6 partial · 25 not built.**

⚠️ **Two rows above are stale and are corrected here rather than silently edited, because the
totals line is quoted elsewhere.** *The unseen thing in the Flood* (SCARY P10) reads NOT BUILT; it
**is** built — `unseen_wader.gd`, instantiated by `backrooms_zone3.gd:_build_wader()`, asserted by
`check_backrooms_occupants.gd` (no mesh, no collider, no gaze panic, ≥12 m, two-strides-and-stop).
*`HoldBreath`*, *`Watcher`* and *`MovedProp`* likewise exist as scripts. Re-audit before quoting
"2 built".

---

### 2026-08-17 — THE FLOOD gets content, and it adds no panic (backlog `04-backrooms.md` §14)

⭐ **A worked example of §0.2 — *stop adding panic terms, start adding channels*, with the numbers.**

J-capture #5: *"the flood sublevel even though looks very cool feels very empty."* What shipped is
**six searchable half-submerged objects and three events**, and the whole of it costs **zero panic,
zero fail states, zero new rules**. The channel it adds is **the audio to-do list**: each unsearched
object knocks every 5–11 s at `unit_size 6`, searching one silences it forever, and the wing gets
audibly emptier as it is worked. That is the only progress readout in the level and it is diegetic,
which §5.2(2) requires of any readout at all.

Three things worth carrying to other levels:

1. **Found by EAR, in the one zone whose puzzle is about light.** A glinting object would have
   argued with the Flood's own tell (the exit seam is visible only with the torch OFF) and a
   self-illuminated one is §5.2(8). Sound was the only channel left, and it turned out to be the
   better one: it works whether or not the seam mechanic ever engages — which matters, because
   across three logged sessions **it never has** (the player entered with the torch already off).
2. **THE SURFACING is `SCARY.md` P10's stated anchor, finally paid off.** At the third search,
   something else in the wing hauls something out of the water, once, 5–13 m away — **the same
   sound the player has just made three times**. P10 asks for *"what you hear in the distance to be
   audibly the same ACT you are performing"*, and this is the only place in the game where the
   player performs an act distinctive enough to be echoed. No entity, no mesh, no repeat.
3. **The measured cost, for the difficulty ledger.** Driving the real player (`ai_*`) from the
   entry cap: a **beeline** is 16.5 s and +2.9 of `PANIC_MAX` 50; a **full six-object search** is
   36.7 s and **−9.3** (the route crosses the Basin `CalmZone` four times). Worst case, a route that
   never touched the anchor, **+11.0 of the 37.5 points of headroom**. Reading is free — `NoteUI`
   pauses the tree, so the zone's drip does not tick behind a page. **Nothing was tuned.**

---

### Reachability — the guard the corpus was missing (2026-08-17)

`tests/check_reachable.gd` — **all nine levels, 26 s, in the suite.** Every other geometry guard in
this project inspects a relationship between two objects; none of them asks whether a player can
*get* to one. That is how the Backrooms Sprawl kept eight sealed alcoves and ten unreachable objects
through two playtests and four scene-parameterised checks (ISSUES_SOLUTIONS Issue 90). It flood-fills
the standable space from the spawn with each level's own capsule and then drives the shipping
interact ray, aiming at the mesh.

Result of the first full sweep: **one further real finding** — two of The Void's ten interactables
(`NoteVoid2`, `TrapVoid1`) are in a pocket no route reaches, nearest reachable cell 4.79 m and
3.25 m; the level stays winnable and the finding is filed as cross-level **X44** for Level 8's own
pass. Everything else in Intro / Lab / House / Corridor / KONTUR / Breach / Nightmare is reachable.

⚠️ The interesting half is the **false positives it had to be taught to stop reporting**, because
each of them made a healthy level look broken: a 1.01 m lane against an 0.80 m capsule (grid
resolution), the Intro seeding its fill on the gurney the player wakes up on, and a **6 mm**
capsule-vs-ramp clip that hid the entire House cellar. A guard that cries wolf gets ignored, and the
taxonomy — reachable / inert / contained / dormant, plus gates that get opened — is what buys the
right to trust the red.

---

## §3 — Live defects

All six from `BACKLOG.md`'s 2026-07-27 audit, **re-verified against HEAD and all still present.**
These are the cheapest items in the corpus and one of them gates a whole retrofit.

| # | Defect | Evidence | Note |
|---|---|---|---|
| a | Ships a debug value: `FAMILIARIZATION_TIME := 10.0`, comment says *"⚠️ TEMPORARY — lowered from 50.0 … Revert before ship."* | `level_6_breach.gd:25`, consumed `:290` | The Mr.X familiarization window — the entire point of Level 6's pacing — is effectively off. |
| b | The escort breathing is in the wrong place. `BREATH_OFFSET` is world-space `(0, 1.2, 1.6)`, applied with no basis term, so it sits at world +Z rather than behind the player's facing. | `escort_gate.gd:26`, applied `:97`; live at `kontur.gd:1202-1203` | KONTUR Gate 4's best audio beat has never worked as designed. Blocks SCARY P2's best placement. |
| c | ~~`Vignette.spawn()` is `pass`~~ — **CLOSED, and this row was stale for three weeks.** `vignette.gd` was restored 2026-07-28; all five callers render it, and the framing darkening is visible in every Corridor screenshot taken during the 2026-08-16 pass. | `vignette.gd`; callers `level_1.gd:122`, `level_2.gd:83`, `level_3.gd:29`, `corridor.gd:113`, `backrooms.gd:115` | Recorded as cross-level **X27**. ⚠️ Two of this table's six "live" defects — (c) and (e) — are now historical; re-verify the other four before quoting the number. |
| d | Panic red tint capped at 10 %. Scene overrides the script default of 0.5. | `hud_canvas.tscn:10` vs `panic_hud.gd:4`; applied `:97` | ⚠️ **Gates SCARY P8** — the panic-spike lie needs the tint to actually register. Fix first. |
| e | Documented beartrap double-jeopardy protection does not exist. `apparition_director.gd:107-108` claims `is_input_frozen()` covers the beartrap QTE; `beartrap.gd` never calls `freeze_input()` — only `apply_slow()`. | `beartrap.gd:244-245`, QTE loop `:263-282`; real `freeze_input()` callers are `intro_room.gd:81`, `lab_locker.gd:196`, `player.gd:549` | A HOLD apparition can spawn onto a player clamped at 45 % speed mashing E. Issue-18 shape. |
| f | Dead code. | `creature_static.gd` (zero references, no `class_name`); `player.gd:368 relieve_panic()` (zero callers) | Delete both. |

---

## §4 — New ideas (2026-07-27 session)

26 candidates researched across 2023–26 indie horror, Japanese/Korean indie horror, analog horror,
haunted-attraction design, board-game horror, and academic work on fear and attention. **Five kept,
three deferred, eighteen cut.** The cuts are in §5.4 with their reasons — they are the majority of
the session's value, because most of them were cut for reasons that will recur.

Deliberately steered *away* from the already-mined sources (Amnesia, Alien: Isolation, P.T., Layers
of Fear, Eternal Darkness, The Exit 8, Condemned, Anatomy, Iron Lung, Outlast, SOMA, Dungeon
Nightmares, Obra Dinn, Alan Wake, RE/Mr.X, F.E.A.R.). Two categories yielded **nothing** worth
pitching and that is recorded rather than padded: immersive-sim/systemic horror (every route needs
interacting simulation systems — the same cost profile as the already-rejected Bunker AI), and
multiplayer/social horror (the best mechanics are co-op-dependent).

---

### N1 · Scare geometry — never scare from the front ⭐
**Mechanic:** a placement law, not a script. **Exemplar:** haunted-attraction design —
*"Scare from the back, the top, the bottom, and from both sides, but never, ever from the front"*;
scares should *"scare forward."*
[hauntedattractionnetwork.com](https://hauntedattractionnetwork.com/haunted-attraction-designing/)
**Cost:** XS (a spec clause). **Panic:** none.

F1's diagnosis is verbatim that *"nearly every scare payload is the same shape: a fullscreen image
plus a loud burst"* — and almost every one of them arrives **dead ahead**. An industry that measures
throughput concluded front-scares stall people while side and rear scares propel them, and propulsion
is exactly what a 320 m corridor and three Backrooms zones want.

**Implementation sketch.** Not a new script — a **placement clause added to the specs of the three
accepted zero-panic scares** in `SCARY.md` §3: `Watcher` (P3), `MovedProp` (P6), and the Flood wader
(P10). Each should land behind, beside or above the player rather than centred down a sightline.
⚠️ **It must never become a rule that a payoff is gated on facing a particular way** — no
`flash_scare` withheld, no fail state hinging on heading. Placement guidance only; the moment it
gates a consequence it becomes a scare the player can miss by looking the wrong way.

---

### N2 · Ambient-bed pitch drift — the cheapest thing in the world that responds to panic ⭐
**Mechanic:** diegetic reactive audio with zero new assets. **Exemplar:** Winifred Phillips,
GDC 2024, *"Dial Up the Diegetics: Musical Sound Effects."*
[gamedeveloper.com](https://www.gamedeveloper.com/audio/dial-up-the-diegetics-musical-sound-effects-for-the-video-game-composer-gdc-2024-)
**Cost:** XS (~10 lines). **Panic:** none.

`SCARY.md` §2.4 is blunt: *"Nothing in the 3D world responds to panic at all."* The heartbeat is the
only panic-reactive audio in the entire game. This is the cheapest possible answer: drive
`pitch_scale` on each level's single `AmbientPlayer` bed off `get_panic_ratio()` above 0.5, drifting
**≤ 4 % flat**. The world sours as you lose your nerve and there is no file to author.

**Implementation sketch.** A per-level `_process` tick on the existing `AmbientPlayer` node, or one
helper called from the five levels that register `RandomAmbient`. `SCARY.md` §4.1(d) explicitly
permits audio that *follows panic* (which the player already knows about) while banning audio that
*tells*.

⚠️ **Never touch a tell emitter.** Not `breaker_hum` / `breaker_buzz` (the Lab wing's navigation
beacon), not `sprawl_wall_hum` (Backrooms Zone 2's exit tell), and nothing on the `"Backrooms"` bus
that `silence_zone.gd` ducks. Pitch-drifting a tell turns a puzzle into a lie.
⚠️ The original pitch also proposed regenerating every world emitter on a shared harmonic pitch set.
**That half is cut** — asset churn across four `make_sfx` scripts for an effect the drift already
delivers.

---

### N3 · Announced uncertainty — the declared, unbounded threat window ⭐
**Mechanic:** sustained hypervigilance instead of phasic startle. **Exemplar:** the neuroscience
underneath F2 — *"When the timing of threat encounters is uncertain, a sustained state of heightened
reactivity is evident"* (BNST-mediated), versus a phasic burst for certain, imminent threat.
[Nature Neuropsychopharmacology](https://www.nature.com/articles/npp2009109)
**Cost:** XS. **Panic:** none.

The machinery already exists — `ApparitionDirector` owns a randomised 90–180 s gap with an
`OVERDUE_AFTER` guarantee. The only new thing is **telling the player the window exists**, which
converts an interval of nothing into an interval of hypervigilance for the price of a string.

**Implementation sketch.** Place it in the **Corridor**, whose entry note is already signed *"Hotel
Vesper — The Management"*. Extend that note (a string branch in `corridor.gd`) to announce that
something will happen between the clock and the far junction, and refuse to say when. Hang the payoff
on **P4's fifth telegraph** so it costs zero new panic and zero new assets. Build in the same edit as
P4.

⚠️ **It must not invent a payload** — the promise is kept by the Manager's existing
`flash_scare(screamer_manager.png)`.
⚠️ **It must never announce a window it can fail to fill.** The observers may lie about the *world*;
an observer who lies about *mechanics* is §8.6.

---

### N4 · The PA channel — narrative that arrives without stopping the game ⭐
**Mechanic:** systematise the facility tannoy into a recurring, degrading narrative channel.
**Exemplar:** analog horror's core move — once-trusted broadcast systems portrayed as corrupted.
[Analog horror](https://en.wikipedia.org/wiki/Analog_horror)
**Cost:** S. **Panic:** none.

Every note in this game **pauses the tree**, which means the storytelling channel and the threat
channel are mutually exclusive by construction. The PA is the only channel that isn't — and the
asset and the fiction are already here. *"We are watching"* is established in the first minute, and
`pa_trial4` sits on disk **used exactly once** (`level_1.gd:665`).

**Implementation sketch.** 6–10 authored lines through `tools/make_pa_voice.py` **unchanged** — a
working, stdlib-only `say` + ffmpeg 1970s-tannoy pipeline that already shipped `pa_trial4.ogg`.
Place them across the three facility levels (Lab, KONTUR, the Breach), degrading in register from
clinical to fragmentary. Also the natural carrier for N3's announcement and P8's observer captions.

⚠️ **Why this is not `REPORT.md` #8 (TTS notes, cut in §6.2).** The pipeline's trick is that
band-limiting to 300–3000 Hz plus overdrive **hides the synthesis**. That cover exists for a
degraded institutional tannoy and does not exist for a clean voice reading fifteen first-person
notes. Same tool, opposite outcome.
⚠️ It must **not** carry a puzzle answer, a proximity cue, or an actionable instruction —
`pa_trial4`'s own convention is to describe the Backrooms exit as *"the surface that will not hold
still"* and then cut off mid-sentence.

---

### N5 · Scares triggered by voluntary acts, not trigger volumes ⭐
**Mechanic:** anti-habituation by changing the **trigger class** rather than the payload.
**Exemplar:** haunt design — build anticipation rather than firing on entry.
**Cost:** XS (the signals already exist and nothing listens). **Panic:** none new.

This is the most direct answer to F1 on the list, because F1's diagnosis names the problem exactly:
*"every scare fires on a fixed timer or a fixed walked distance, blind to what the player is doing."*
Every trigger condition in this game is spatial or temporal. Move a handful onto things the player
**chose** to do.

**Implementation sketch.** Pure rewiring — connect signals that are already emitted and currently
unlistened-to: `note.gd:17 read`, `note_ui.gd:6 closed`, `slam_door.gd:12 slammed`,
`key_item.gd:9 picked_up`, `breaker.gd:9 flipped`. (Only two `read` consumers exist today, both
non-scare: `intro_room.gd:439`, `level_1.gd:457`.) Sequence it **after** P3 and P6, because it is a
trigger doctrine with no payloads of its own — and note that P3 and P6 are currently specced with no
firing rules at all, which is the gap this fills.

⚠️ **Fire on `NoteUI.closed`, never on note *open*.** The information has already been delivered, so
nothing the game needs is discouraged.
⚠️ **The payload must be zero-panic** — a `Watcher`, a `MovedProp`, a `HoldBreath` dip. Never a
`flash_scare`, never a spike. A free image cannot train avoidance; a 15-panic hit teaches players to
stop reading notes and stop slamming doors, and the game *needs* both (three levels gate on notes,
and `slam_door.gd` is Level 6's only counter-play).

---

### Deferred — live, but blocked

| # | Idea | Condition to revisit |
|---|---|---|
| **N6** | **Progress-triggered ambience** — fire ambient scares on distance walked, not wall-clock, so slow and fast players get the same count in the same places. | The premise is weaker than it looks: outside a `DreadZone`, `PANIC_DECAY_RATE 3.5`/s clears an 8-point `painting_fall` in 2.3 s against an 18–35 s gap (`random_ambient.gd:16-17`), so a slow player's extra spikes do **not** accumulate. And `RandomAmbient` isn't registered in KONTUR, the Backrooms or Level 6 at all (only `level_1.gd:123`, `level_2.gd:84`, `level_3.gd:30`, `corridor.gd:114`). **Revisit after P9 ships:** run one `DebugLog` Corridor traversal and count events; if a single 320 m walk logs more than ~6 ambient spikes, convert **the Corridor only**. ⚠️ Never add a per-level mode to the global autoload — that divergence is what hid Issue 34's stub. |
| **N7** | **Sightline lint** — a `check_sightlines.gd` asserting no two doorways are collinear across a room and flagging long straight sightlines. | `SCARY.md` §4.3 already adopts the *rule* as the primary fog substitute (*"Never align two doorways across a room; cap straight sightlines"*), so the test encodes accepted doctrine. But as a retrofit it would flag the Lab dark wing and KONTUR's escort, which need long axes **by design**. **Revisit** when a new `RoomBuilder` level exists: build it as a guard on that level only, with an explicit exempt list, never as a pass/fail gate on the eight shipped levels. |
| **N8** | **The haunt turn** — at a threshold, a level's *existing* props change behaviour and a diegetic source states the new rules; nothing new spawns. (Betrayal at House on the Hill's Haunt.) | It is the natural mechanism for `SCARY.md` §6 option 1 — *"make KONTUR and The Breach lose their coherence as you walk through them"* — which is **§7 question 1**, a decision the user explicitly reserved. **Revisit** once that question is answered in favour of degrading levels 5–6 in place; then build it as the mechanism with P11 as the geometry half. |

---

## §5 — Rejected, superseded and deferred (the absorbed ledger)

Absorbed from `drafts/IDEA_HISTORY.md`. **Never re-pitch anything here without saying so explicitly
and supplying new evidence.** The reasoning column is the entire value of this table.

### 5.1 Rejected

| Date | Idea | Reason |
|---|---|---|
| 2026-07-27 | **Make the panic bar ambiguous / unreliable as a *rule*** | Amnesia could afford a placebo sanity meter because its meter *did nothing*; this one carries twelve levels of tuned fail economy. Lying about the *readout* for < 1 s (P8) is legal; changing the *rules* is not. `SCARY.md` §8.6. |
| 2026-07-27 | **Breath-holding mechanic** (Alien: Isolation) | New input + new HUD teach + new punishment, and it double-taxes stillness, which the Smiler and the HOLD apparition already tax (Issue 18). Its punishment in Isolation is a *delay*, which this project's instant-fatal creature contract cannot accommodate. `SCARY.md` §8.5. |
| 2026-07-27 | **A second chase level / a second observation-dependent creature** | One chase level in twelve is the correct ratio. Outlast's chase-or-nothing binary is the failure state of chase-led design; SOMA's Safe Mode is what happens when monsters crowd out the atmosphere. `creature_stalker.gd` is at its ceiling with both cheeses already patched. `SCARY.md` §8.3, §8.4. |
| 2026-07-27 | **Emergent sound-attracts / light-repels AI** (Amnesia: The Bunker) | Needs a nav-point graph, a sensory model, an interest system, an escalation gauge and randomised per-run resource placement — a project, not a feature. The two existing creature levels already spend the entire AI budget. `SCARY.md` §2. |
| 2026-07-27 | **Save-point dread** (RE ink ribbons) | Ink ribbons work because saving exists. This game has no saves and `restart_current_level()` deliberately erases the level snapshot. A save currency in a game with no saves is a contradiction; the nearest legal analogue (scarce light) is already the flashlight battery. `SCARY.md` §2. |
| 2026-07-27 | **More `RandomAmbient` sound variety** | The problem was never variety, it was **rate** — the 5–10 s → 18–35 s retune was the fix. Adding sounds without adding gap re-creates the bug at higher fidelity. Add the panic gate (P9) instead. `SCARY.md` §8.7. |

**2026-08-16 — THE HOUSE (backlog `02-house.md`)**

| Date | Idea | Reason |
|---|---|---|
| 2026-08-16 | **Move the House cellar beartrap off the forced-blind entry line** | ⚠️ **REJECTED BY THE USER, and this is a standing example worth reading.** The analysis was correct in every measured detail — the trap sits 1.6 m past the cellar blackout trigger on the only heading into the room, inside an 8.5 s window in which `_begin_cellar_blackout()` kills every lamp *and* calls `force_flashlight_off()`, with no counter-play; it fired in **both** logged sessions, at `(6.30, -1.50, -4.90)` and `(6.20, -1.50, -4.30)`, each a clean `ESCAPE_INITIAL_PANIC` 15. It reads exactly like §5.2(11), *punishing the player for a scare they could not have seen coming*. The user was shown all of it and chose to leave the trap where it is. A `⚠️ DELIBERATE (2026-08-16)` comment now sits at its placement. **Correct measurement, rejected recommendation, legitimate outcome.** The knock-on is recorded in the same commit: it makes `_cellar_child_appear()`'s postponement guard load-bearing rather than belt-and-braces. |
| 2026-08-16 | **Retime the House fridge's `REVEAL_DELAY`** ("the head appears not immediately") | The ordering — scream, then door, then head, no `flash_scare` — is a `⚠️ DELIBERATE` decision taken **twice** on this user's own feedback. The complaint was a symptom of Issue 69: the door was swinging *into* its own carcass, so 0.62 s had nothing to clear and read as a pause in front of an already-open box. Fix the hinge, re-ask on the replay, do not touch the constant. |

**2026-08-17 — THE BACKROOMS (backlog `04-backrooms.md`)**

| Date | Idea | Reason |
|---|---|---|
| 2026-08-17 | **Make the zone-1 glitch wall GLOW a minute into the level** (the user's own proposal, capture B1: *"maybe we can make the wall shine let's say 1 minute after the player started playing… like a small hint"*) | ⚠️ **DECLINED BY THE USER AFTER BEING SHOWN THE MEASUREMENTS — do not re-pitch it.** The glitch wall is **already the brightest surface in its room by 2.3×** — 132.7 lum against side walls at 56.9/58.9, ceiling 55.8, floor 51.9 — and still a 10 % step from the decision point 15 m back. Brightness was never the missing channel; a *statement of the verb* was. Decisively: the capture was taken **6.2 m down the CORRECT arm at a loop-back cap**, 5 m short of the dead end they needed to walk into — a place no glow on the glitch wall would ever have reached. Two of the three times this level demands "walk into a wall" are at those caps. The user chose the two-layer positional audio tell (BS1) instead, precisely because it serves the caps too. |
| 2026-08-17 | **Give the Congregation a chorus** — one shared, quiet, synchronised vocal bed whose density scales with how many figures are behind the player (*Control*'s Hiss-corrupted personnel, non-hostile and chanting) | **Offered and declined this pass.** It remains a good idea and it is still legal — zero panic, zero rules, on the `"Backrooms"` bus so the `SilenceZone` mutes it along with everything else, which would have strengthened zone 2's sound puzzle rather than competing with it. It was declined on **budget**: the pass's two big-swing slots went to BS1 and to fixing the Congregation's contract violation (Issue 85), and the honest sequence is to land those, replay, and re-ask. ⚠️ If it is ever built, `check_backrooms_audio.gd` must assert the chorus sits **under** the `water`/`whisper` tell measured from the files — the Sprawl's mix already carries a score at −4 dB, a hum at −16 and the tell on Master. |
| 2026-08-17 | **Make the Congregation's heads turn to follow the player** | **Offered and declined this pass**, and the risk note is the reason to keep it declined. It is the single cheapest way to make a field of silhouettes feel alive, and it is also the shortest path to making them read as a *creature with a rule*. `SCARY.md` §8.3 bans a second observation-dependent creature; these are legal only because looking at one does **literally nothing**, and a head that tracks you is an acknowledgement — the player will immediately start testing what happens if they approach, which is a rule they will have to be taught the absence of. If it is ever revisited it should be a one-shot per figure, off-screen, so it is discovered rather than demonstrated. |
| 2026-08-17 | **Floor DRAG MARKS running into each seam surface** (four dark scuffs on the carpet at every loop-back cap and at the exit glitch wall — "something was dragged through here", shipped as the third channel of BS1) | ⚠️ **CUT BY THE PLAYER, TWICE IN ONE PLAYTHROUGH — do not re-add them.** Capture 001, standing in the utility room: *"These stripes look weird - remove them"*. Capture 003, at an E-arm loop-back cap: *"Yeah, remove the stripes. The hints on the walls are sufficient"*. They were removed on 2026-08-17 (backlog 04 R3). ⚠️ Note precisely WHAT was kept, because the verdict was about this channel and not about the feature: the `NO DOOR. / WALK INTO IT.` scrawl on the side wall stays, and so does the two-layer positional seam audio, which is the tell the user themselves chose over making the glitch wall glow. The player named the wall hints as sufficient. `check_backrooms_seam.gd` now asserts the ABSENCE of any `DragMark*` node anywhere in the scene, so a re-add fails the suite and lands here.

### 5.2 Anti-patterns — do not build (from `SCARY.md` §8, reproduced so this file is self-sufficient)

1. **Fake crashes, BSODs, save-corruption, OS dialogs, volume drops.** A macOS `.app` under active development with a `DebugLog` playtest protocol: a fake "SAVE DATA CORRUPTED" produces a real bug report and poisons real data. Use P8's diegetic suite.
2. **Any HUD readout indicating progress toward or proximity to a solution.** Issue 34: `set_breaker_proximity()` solved the wing outright, lied from inside dead ends, *and* masked the fact that the real tell had never been built.
   - ⚠️ **ONE STANDING EXCEPTION (2026-08-16), on the user's explicit call**, made after being shown this line and Issue 34: the Lab dark wing has a signal meter again (`lab_wing_meter.gd`). Their reason was accessibility — *"finding your way through sounds only in the complete dark is hard for the unexperienced user"*. The engineering condition attached to it is that **it may not lie**: it measures Dijkstra path distance through the wing's doorway graph, never a beeline, so a dead end reads cold (Plant: 30.0 m of walking against 6.6 m of straight line — 0.04, where the old bar read 0.79). See the AMENDMENT under Issue 34 for the measurements. This does **not** re-open the anti-pattern for other levels: a second one needs its own decision, and any that ships must be path-based.
3. **A second observation-dependent creature.** §8.3.
4. **A second chase level.** §8.4.
5. **A breath-holding mechanic.** §8.5.
6. **Making the panic *rules* ambiguous.** §8.6.
7. **More `RandomAmbient` variety at the current rate.** §8.7.
8. **Emissive scary props.** Issues 21/27/33, a three-time recurrence. The engine's answer to "make it stand out in the dark" is **silhouette** and **audio**. No glowing monsters, eyes, or anomalies.
9. **A depth-fade "fog" shader.** Would fight `PanicHUD`'s existing `BlurRect`/`TintRect` stack. Fog is a flagged experiment on one new level only.
10. **Anomaly-spotting layered onto the Backrooms hub.** The hub already carries the down-arrow puzzle; a second perceptual audit of the same geometry at the same 18-panic cost is Issue 18 in its purest form. §8.10.
11. **Punishing the player for a scare they could not have seen coming.** Named twice already (KONTUR Gate 7, the Backrooms Flood) and resolved correctly once (the Lab nook payoff is deliberately survivable). §8.11.

### 5.3 Superseded (kept so the trail is followable)

| Idea | Folded into |
|---|---|
| Hide-and-search set-piece (REPORT #6) | The unified chase & evasion system (#14), then shipped inside Level 6. |
| Light-as-weapon repel | Level 6 (`creature_object12.gd`'s `apply_light_damage()`). **Built.** |
| Environmental takedown | Level 6 (`purge_chamber.gd`). **Built.** |
| Falling/collapsing props (#4) | `MovedProp` (SCARY P6) — no physics, no sound, no acknowledgement, and it works *retroactively*. |
| Misdirection pairing (#5) | SCARY P4 + P11 — misdirection is the *mechanism*, not the feature. |
| Hide the panic meter (#2) | SCARY P8, reframed: lie about the readout for < 1 s, never about the rules. |
| Adaptive Director (#1) | SCARY P9 — build the *relief valve*, not a second director. |
| Shifting-architecture level (#20) | SCARY P11 (House retrofit) **and** §5.1 THE RETURN (level). |
| Pre-scare silence dip (#7) | SCARY P5, plus the key placement: inside `flash_scare()` itself. |

### 5.4 Rejected — 2026-07-27 research session (18 of 26 candidates)

Recorded in full because most were cut for reasons that will recur. Ranked roughly by how tempting
they are, so the strongest traps are at the top.

| Idea | Exemplar | Why it was cut |
|---|---|---|
| **Mark the walls** — chalk `Decal`s the player leaves to navigate | The Backrooms 1998 | It is `set_breaker_proximity()` (Issue 34) rebuilt **by the player's own hand**, in the one wing that exists to be navigated by ear — and it dissolves the Backrooms' identical-re-randomised-hub thesis. No scoping saves it. |
| **The viewfinder** — a scope through which certain figures are visible | Fatal Frame; Cursed Digicam | Textbook Issue 18: a device whose entire purpose is *sustained direct looking*, in a game where sustained direct looking at anything with a `ScaryObject` ancestor is +20/s. It is also a fourth light/vision rule, against `SCARY.md` §1.9's explicit *"Do not add a fourth light rule."* |
| **LISTEN verb** — hold a key to open the mix and hear distant emitters | Althera audio-layering | The only three places with audio worth listening to are the Lab dark wing (where it solves the navigate-by-ear puzzle outright — Issue 34), Backrooms Zone 2 (where standing still costs +3/s — Issue 18), and the unbuilt Anechoic Chamber (where identifying a chamber by ear *is* the puzzle). Scoped away from all three it has nothing to hear. |
| **The field manual** — a diegetic entity-tell reference in `JournalUI` | Home Safety Hotline; No, I'm Not a Human | `journal_ui.gd:138-144` pauses the tree, and `can_open()` refuses only during `NoteUI`, an existing pause, or `is_input_frozen()` — a HOLD apparition does **none** of those. It is a free pause button aimed at the exact encounter the teach-first contract (`GameState.apparition_taught`) already solves. |
| **Harmless twins** — a visually identical harmless instance of every lethal class | Dungeon Nightmares' dud skeletons | Already specced where it is legal (`DUNGEON_NIGHTMARES.md` §B4.1's 35 % dud Still Ones, §B4.4/§B4.5's two harmless entities) — and as a *general law* against instant-fatal, no-HP contact, "you cannot tell them apart" is a coin flip: §8.11 verbatim. |
| **Panic as a key** — one gate that opens only while panic is HIGH | CHI PLAY emotional-puzzle taxonomy | Makes the bar a resource to *spend* rather than a cost to avoid, inverting the game's thesis — and it deliberately parks the player at 40+/50, where one `half_scream` (12) is a death with no agency. §8.11 by construction. |
| **The sacrifice gate** — surrender the flashlight permanently to proceed | Signalis' carry limit | With no checkpoints and `restart_current_level()` wiping the snapshot, a player who gives up the torch and then meets a `DarkZone` has bought a **soft-lock** whose only exit is replaying the level. The battery already *is* the scarce-light mechanic (§1.9). |
| **Restricted control** — remove a verb outright (sprint disabled, not taxed) | Mouthwashing | The user already ruled the opposite way on this exact question: `DUNGEON_NIGHTMARES.md` §B1 records *"the sprint tax stays at +6/s, unchanged, with no special-casing for this level. No rule the player has to unlearn."* Removing the verb is the same special-case, harder. Also: removed input reads as broken input, and sprint has no feedback channel to say "you can't run here." |
| **Wrong silence (body)** — the player's own footsteps go silent for 6–10 s | Althera's "wrong silence" | Contradicts an agreed architecture decision, not merely an anti-pattern: `SCARY.md` §4.1(a) makes the `Body` bus **"NEVER ducked"**, and un-duckability is what makes every other silence effect work. This ducks exactly that bus. |
| **Displaced heartbeat** — the heartbeat plays from 4 m away at high panic | — | Contradicts two accepted specs at once: §4.1(a) routes the heartbeat to the un-duckable `Body` bus precisely so it stays with you, and §5.3's Anechoic Chamber's entire thesis is that your own pulse becomes the only audio in the game. |
| **The photograph in your hand** — a carried reference image to compare against a room | Cursed Digicam; escape-room clue theory | A fairness fix for a mechanic that needs none — P6 `MovedProp` is zero-panic with no fail state, and *"if the player never notices, nothing happens"* **is** the mechanic. It also converts a perceptual anomaly into exhaustive spot-the-difference, and it is the only per-instance art cost on the sheet. |
| **The procedure** — a multi-step diegetic checklist performed under interruption | The Mortuary Assistant | Same shape as the already-accepted, already-unbuilt sequence fuse/valve puzzle — which is itself cut in §6.2. Building a second version of a cut item is the worst trade available. Also Grip's *"fun gameplay is just too fun"*: an engaging task consumes the attention that would be spent being afraid. |
| **Notes that disagree** — two archived notes describe one event incompatibly | Silent Hill 2's unreliable narrator | Already exists, correctly scoped, in the one place notes carry no puzzle load: `SCARY.md` §5.1, THE RETURN pass 6. As a *general practice* it attacks the Flood-digits → KONTUR-roster dependency and the Observation-note → Lab-locker gate. |
| **Live feed monitor** — a `SubViewport` showing another room in real time | Chilla's Art; Voices of the Void | `SCARY.md` §5.2 already claims the CRT bank for OBSERVATION, and a `SubViewport` doubles the render for one prop. (The emissive objection is the *weakest* part of the case — the House TV static panel already works — but the duplication is decisive.) |
| **Non-pausing audio notes** — narrative audio that doesn't pause the tree | Amanda the Adventurer | Falls with TTS-narrated notes (§6.2). The working `make_pa_voice.py` pipeline produces a *degraded institutional tannoy*, whose trick is that band-limiting hides the synthesis; a clean voice reading fifteen first-person notes has no such cover. See **N4**, which salvages the good half. |
| **Sightline lint as a retrofit** | haunt design | Deferred rather than dead — see **N7**. Cut only in its "gate the eight shipped levels" form, which would fail working levels by design. |
| **Relief beats** — authored harmless mundane events between scares | haunt design; Frictional | P9 and §8.7 restated with no delta. And *"authored nothing"* is behaviourally identical to the walking that F2 already names as the problem. |
| **The instrument that names but never points** | Phasmophobia | See the ruling below — cut, but **not** on §8.2 grounds. |

#### ⚠️ Two re-pitch rulings — recorded because the *reasons* matter more than the verdicts

Both were flagged as re-pitches of standing rejections. In both cases **the standing rejection turned
out not to cover the proposal**, and both were still cut — on new grounds. Recording the distinction
so a future session doesn't cite the wrong rule.

**Noise-budget placement** (place `RandomAmbient`'s emitter at the player's noisiest recent location)
— re-pitch of *"emergent sound-attracts AI"*. **The original rejection does not apply.** That verdict
was costed against *"a nav-point graph, a sensory model, an interest system, an escalation gauge and
randomised resource placement — a project, not a feature,"* and this needs none of them: nothing
spawns, nothing pursues. **Cut anyway, on three new grounds:**
1. **Geometrically inert.** `_play_near_player()` places the emitter within **4 m** at `unit_size 10`.
   In every level except the 320 m Corridor, the player's noisiest recent spot is *already* within a
   few metres — so the reposition changes nothing audible. Push it far enough to be a different place
   and a `unit_size 10` emitter is inaudible. **There is no radius at which this both reads and pays.**
2. **It collides head-on with P9**, which specs the opposite edit to the same six-line function: P9
   pulls the emitter **toward** the player (raycast to the first hit, so scares stop originating inside
   walls); this pushes it **away**. Two accepted edits to one function pulling in opposite directions
   is how Issue 34's stub went undetected.
3. **Asymmetric behavioural risk.** The verbs it would suppress are ones the game *requires*:
   `push_effort` mashing is mandatory to restore Lab power, and `slam_door.gd` is Level 6's only
   counter-play to Object 12.

**The classifying instrument** (audible-only, reports a threat *category*, never a direction) —
re-pitch of *"any HUD readout showing proximity to a solution."* **§8.2 does not actually cover it.**
§8.2's subject is a *visual* readout of *distance to the answer* — Issue 34's `set_breaker_proximity()`
bar, which also lied from inside dead ends. This is audio-only, gives no direction and no distance,
and names a category rather than a solution state. Enforcing §8.2 here would be enforcing the letter
of a rule against something outside its subject. **Cut on the real ground: ambiguity is the product.**
The Perëkozhnik works *because it is a mimic* — an instrument announcing "shapechanger" deletes the
mechanic, and its 16 panic/s stare is tuned on the assumption that walking up for a better look is the
mistake. It would likewise delete the accepted 35 %-dud Still Ones, whose whole design is *"you cannot
tell a dud from a killer without walking up to one."*
→ **For the ledger: not a HUD violation; an ambiguity violation.** That is a distinct rule this
project had not previously written down.

### 5.5 Accepted and adopted as design rules (not build items)

| Idea | Where it now lives |
|---|---|
| **The escalating-unreality pillar** (2026-07-27) — *the game starts ordinary and human, and gets further from reality the deeper the player goes; every new level must be stranger than its predecessor.* Raised by the user unprompted, mid-session. | A hard constraint on new content, recorded in `CLAUDE.md` and `README.md`, with the full 12-level ordering in `SCARY.md` §6. ⚠️ The curve is currently **non-monotonic** and that is a known, deliberately-unresolved issue — see §7.2 Q2. |
| **Diegetic-only perceptual unreliability** (2026-07-27) — the *world* lies; the *game* never does. | Scopes SCARY P8. The rejected half (fake crashes, BSODs, save-corruption, OS dialogs) is anti-pattern §5.2(1). |

### 5.6 Deferred

| Idea | Condition to revisit |
|---|---|
| **A second key behind a locked door inside the House maze minigame — "or maybe to find a shotgun to shoot the glass"** (playtest 2026-08-16, capture A2; the user's own words end *"we can discuss"*, and their call on 2026-08-16 was **defer**) | ⚠️ **The interesting version is NOT a second key — it is a SECOND VERB.** As pitched it is a key-behind-a-gate nested inside a minigame whose containing level is already a key-behind-a-gate (Bathroom map → key → cellar gate), so it adds a step to a chain rather than a decision. What the House actually lacks is a **destructive** verb: nothing in this level, or in the eight before it, lets the player break anything. KONTUR's Gate 6 hammer is the only destructive act in the game and it arrives at level 5. Revisit as "the House gets one thing you can smash", not as "the maze gets a second key" — and note it would be a new fail-adjacent mechanic inside a paused 2D overlay, so it needs its own decision either way. |
| **A test harness's stuck detector counted FRAMES, not seconds** (`tests/autoplay/autoplayer.gd`, found 2026-08-17) | `STUCK_SAMPLES 45` frames in which the body moved less than `STUCK_DIST 0.05 m`. A headless run reaches ~145 fps, where a body walking at the Backrooms Flood's waded 1.8 m/s covers **0.012 m per frame** — so `stuck` reads **true for the whole of a perfectly healthy walk**. Measured directly on a straight-line crossing. Not fixed: it is shared infrastructure and changing it changes what every `walk_*`/`autoplay_*` caller measures. Revisit with whoever owns the autoplay harness; the third recurrence of "a frame count is not a clock" (Issues 95, X42). |
| **Volumetric / depth fog** | Try it on THE NIGHTMARE only — the one level with no legacy emission tuning to break — measure, then discuss retrofitting. The no-fog config is load-bearing for every material's emission across every existing level. ⚠️ Do not fake it with a shader. |

**2026-08-16 — THE CORRIDOR (backlog `03-corridor.md`, deferred at build time).** All eight approved
items were built; these are what the pass deliberately did not do. `backlogs/03-corridor.md` §5 is
authoritative and carries the measurements.

| Idea | Condition to revisit |
|---|---|
| **D1 — the 1.20×–1.67× stretch family**: `mirror.png` ×2, `torch.png` ×3 and the wall-hung `carpet.png`, all hung as full-height wall panels whose dimensions were chosen to match the WALL rather than the picture, and all baking their own wallpaper into the art (Issue 35). | An **art pass**, not a level pass — each needs its source re-cropped. Pulled forward this run only for the two props that are *hints the player must read*. ⚠️ They are listed by name with their reasons in `check_corridor_art.gd`'s `_deferred` map, which asserts its own size, so this deferral is visible in a test rather than only in a document. |
| **D2 — nobody read the framing note (0 of 2 traversals), and the game's most important cross-level hint 1 of 2.** The d=250 plate sits 36 m past the last lit torch, inside the DreadZone, under an objective that says "keep walking". | **Needs a playtest.** One sample of 0-of-2 on a note nobody was asked to find is not evidence, and *lighting a hint* is exactly the kind of legibility change that must be argued from a real session. The plate is now a legible, self-lit object, which may be the whole fix. |
| **D3 — 0 of 5 beartraps fired in two traversals.** Each covers ~65 % of the 2.2 m walkable band; the four in the dark stretch can be threaded by weaving. | **Needs a playtest**, and the offsets and radius are **difficulty constants** — measure and report only. |
| **D4 — zero apparitions in 324 s across two runs.** The legal window in the longer session was ~30 s wide; the shorter one never reached it. | **Needs a playtest** plus `count_apparitions.gd` pointed at this scene. Probably correct behaviour rather than a defect. |
| **D5 — the dread stretch (260–320 m) is structurally unobservable in the log**, because `DREAD_PANIC_RATE` and `DREAD_DECAY_RATE` cancel exactly. | **Needs a playtest**; both are difficulty constants. |
| **D6 — `AjarDoor`s open onto solid wallpaper.** There is no aperture behind any of them; the wall is one continuous 45 m `CSGBox3D` per segment. | Needs a recessed niche (a CSG subtraction on a 45 m wall box) and a collision rebuild. The architrave built this run makes the door read correctly **closed**, which is the state the player almost always sees. |
| **The turn mirrors' gaze intensity (30 panic/s at the 90 m corner)** | ⚠️ Not deferred — **decided**. The user's call on 2026-08-16 was to leave it and re-judge in play now that the glass reflects, and the reasoning is recorded as a `⚠️ DELIBERATE` comment at `corridor.gd:_spawn_panels()`. Do not re-file it as a defect. |

**2026-08-17 — THE BACKROOMS (backlog `04-backrooms.md`, deferred at build time).**
`backlogs/04-backrooms.md` §5 is authoritative and carries the measurements.

| Idea | Condition to revisit |
|---|---|
| ✅ **F1 — THE SPRAWL'S EIGHT ALCOVES WERE SEALED. CUT OPEN 2026-08-17.** They were behind an unbroken perimeter — a ray from 3 m inside the hall was blocked at exactly the 3.00 m mouth plane on all eight — and behind them sat the zone's ONLY note (the page that states its own tell), its phone, its one-way mirror, two mirage doors and five props: every authored object in 1600 m² bar the pillars, the lights and the four glitch walls. | ✅ **BUILT, on the user's call**, framed as *connecting content that was designed and then never reachable* rather than as new content. `_side_runs()` now subtracts the openings from each side's extent (4 wall segments per side, not 2); a mouth is the recess width plus a wall thickness at each end so the boxes ABUT rather than leaving two end caps coplanar. Measured: **+3 241 standing cells (+50.6 m²)**, interactables reachable **8/12 → 12/12**, route to the four glitch walls unchanged, `check_wall_overlap` still 0 findings. ⚠️ Three panic sources went live and **none was tuned** — 2 × `MirageDoor` at 10, and `SprawlMirror` at 14 panic/s of gaze — and `SprawlDread` was widened to keep the recesses inside the no-decay zone rather than silently adding eight recovery pockets. See `backlogs/04-backrooms.md` §9 and ISSUES_SOLUTIONS Issue 90. |
| **D1/D2 — the Flood's flagship inversion can be bypassed by never switching the torch on**, and `is_flashlight_on()` is also false for a *dead* battery, so both the player who never used the light and the player who wasted it get the finale's puzzle free, while the one who managed it makes their own exit invisible. Logged: flashlight OFF at t=542, the Flood entered at t=765, never touched again, cleared in **54.6 s**. | ⚠️ **WAIT — the user's explicit call, 2026-08-17.** One 54-second traversal is not evidence, and every available remedy is a **difficulty constant**, a **new rule**, or a change to the game-wide 240 s battery. Needs a real playtest of the Flood, with a mistake in it. |
| **D3 — zone 1 may be ~20 seconds of content once the arrows are readable.** The returning-player traversal cleared it in 20.5 s. | Cannot be told from "was never readable" until the rebuilt arrow (Issue 88) has been played. Re-measure on the verification replay. |
| **D4 — zone 2's four-wall audio tell has never been tested against a wrong guess.** Both sessions solved it first try. | Needs a playtest with a mistake in it. Either the two-layer `water`+`whisper` cue works exactly as designed or the user guessed right twice, and nothing in the logs separates those. |
| **D5 — `glitch_wall.gdshader` samples the zone-1 wallpaper in all three zones**, so the Flood's decoys and real seam render as mono-yellow Backrooms wallpaper in a wet-grey concrete wing — the most saturated object in the zone is a decoy. | A design call with no evidence either way: arguably correct (the seam is a hole *into* the Backrooms) and arguably a leftover. |
| **D7 — the mirage doors are the most saturated objects in zone 1 and are no-ops.** | Measured only by eye. Needs a proper frame; `screenshot_backrooms.gd` can now produce one (Issue 89). |
| **D8 — `check_backrooms_occupants.gd` still uses `bool(node.get("_standstill_suspended"))`**, the construction `CLAUDE.md` bans in tests. | Works today because the property exists; it is a trap for the next edit, and the fix belongs with whoever sweeps the suite for it rather than with one level's pass. |
| **D9 — `_enter_zone`'s panic cap is guarded on `has_method("set_panic_ratio")`.** | `player.gd:543` defines it, so the cap works — but a rename would silently disable the mechanism that keeps three no-decay zones survivable, with no test. |
| **D10 — `sprawl_wall_hum.wav` is generated by `tools/make_sfx_backrooms.py:97` and referenced by no `.gd` file.** | A documented orphan. Deleting it is a `tools/` change; leaving it risks a future session "restoring the hum" against the comment that says not to. |
| **The loop-back trigger's 0.30 m demand.** `LoopBack{E,W}` sits 0.30 m from the cap's inner face, so a correct turn only counts once you are a foot from a blank wall. | ⚠️ Not touched this pass. BS1 answers it by TEACHING the verb rather than by relaxing the demand; whether the demand itself is too tight is a **difficulty** question and needs the replay. |

---

## §6 — Recommended build order and cut list

### 6.0 The premise this section rests on

**The game is already playable end to end.** Nine scenes, intro through ending, all completable.
So "playable game first" does **not** mean more content — it means *finishing the eight levels that
exist*. Judged that way, most of §2.1 is scope rather than product.

Against that standard: **25 unbuilt rows → 9 survive.**

> ### ⚠️ §6.2 CONTAINS DECISIONS THAT ARE NOT MINE TO MAKE
>
> The cut list below recommends dropping **all four new levels** — including **THE NIGHTMARE** and
> **OBSERVATION**, which you personally accepted on 2026-07-27 and for which `DUNGEON_NIGHTMARES.md`
> is a 1,151-line spec. That is a recommendation from a "playable game first" reading, **not a
> settled decision.** Nothing in §6.2 marked ⚠️ should be treated as agreed until you say so.
>
> The honest tension: you accepted those levels when the framing was "what would make this game
> better," and you chose "playable game first" today. Those two answers point in opposite
> directions and only you can resolve it.

### 6.1 Build order for what survives

**Phase 0 — the six defects.** Cheapest items in the corpus; roughly one session. All still live
(§3), none reported by a player, all read out of the code.
1. **Defect (d)** — panic tint cap `hud_canvas.tscn:10` 0.1 → the script default 0.5. **First: it
   gates P8**, and combined with the blur it is currently the *entire* visual consequence of being
   about to die.
2. **Defect (a)** — `level_6_breach.gd:25` `FAMILIARIZATION_TIME` 10.0 → 50.0. A shipped debug value
   that switches off Level 6's whole pacing design.
3. **Defect (e)** — either have `beartrap.gd` call `freeze_input()`, or fix
   `apparition_director.gd:107-108`'s comment. Right now the documented double-jeopardy protection
   does not exist.
4. **Defect (b)** — `escort_gate.gd:26` `BREATH_OFFSET` through the player's basis. **Blocks P2's
   best placement**, so it must precede Phase 1.
5. **Defect (c)** — delete `vignette.gd` and its five callers (see §6.2: don't restore it).
6. **Defect (f)** — delete `creature_static.gd` and `player.gd:368 relieve_panic()`.

**Phase 1 — XS, no new content, no difficulty constant touched.**

7. **`SCARY.md` §4.1(a) — the bus layout.** ⚠️ **This is a deliberate departure from `SCARY.md` §9,
   which puts P5 and P1 first.** There is no `default_bus_layout.tres` and no bus config in
   `project.godot`; the only buses are `Master` and the runtime `"Backrooms"`
   (`backrooms.gd:39,782-787`). **P5 as specced could therefore only duck `Master` — which would duck
   the heartbeat too and destroy the very effect it exists to create.** The layout must go first, and
   it is a hard dependency of four separate accepted items (P1, P5, N2, N4).
8. **P5 `HoldBreath`**, wired inside `screamer.gd:167 flash_scare()` as a 0.6 s pre-duck. Two lines;
   improves every survivable scare in the game at once.
9. **P9** — panic gate + the LOS pull-in on `random_ambient.gd:71`. Also closes a live fairness bug.
10. **P1 `RoomToneZone`** — Lab dark wing and Backrooms Sprawl only.
11. **P4 The False Ceiling** (Corridor Zone B) **+ N3 Announced uncertainty** in the same edit — N3's
    payoff *is* P4's fifth telegraph.
12. **P2 stop-delayed footstep echo**, KONTUR escort (after Phase 0 item 4).
13. **N2 ambient-bed pitch drift** — ~10 lines, the cheapest answer to §2.4.

**Phase 2 — the world starts to notice you.**

14. **Flashlight-silhouette pass**, one level at a time. **Zero code.** §2.0(a) established the
    shadows already render; this is a placement review, and it is the highest-value free item in the
    entire corpus.
15. **P3 `Watcher`** (one texture) — with **N1's placement clause** written into its spec.
16. **P6 `MovedProp`**, House.
17. **N5 voluntary-act triggers** — payloads restricted to `Watcher` / `MovedProp` / `HoldBreath`.
    Sequenced *after* P3 and P6 because it is a trigger doctrine with no payloads of its own; note
    that P3 and P6 are currently specced with **no firing rules at all**, which is the gap it fills.
18. **P7(b)** cosmetic death-degradation only (see the split in §6.2).

**Phase 3 — the remaining systems.**

19. **`SCARY.md` §4.1(e) — audible Object 12.** `creature_growl_near.wav` is already on disk, unused.
    A silent pursuer is the largest single fairness hole in the shipped game.
20. **N4 the PA channel** — 6–10 lines through `tools/make_pa_voice.py`, unchanged.
21. **P10** the unseen thing in the Flood.
22. **P8 effects 1 and 6 only** (see the split in §6.2).
23. **Persistent save** — Continue = the start of the furthest level reached.

**Phase 4 — deleted.** `SCARY.md` §9's Phase 4 (four new levels + the renumbering commit) is cut,
except THE RETURN, deferred until Phases 0–3 ship. ⚠️ Subject to §6.0's warning.

**Blocked, do not start:** N8 and P11 both wait on §7 question 1 (the unreality curve). N7 waits on a
new `RoomBuilder` level existing.

### 6.2 The cut list

**Cut down, not out — four splits that matter more than the cuts:**

| Item | Keep | Cut |
|---|---|---|
| **`SCARY.md` §4.1 audio overhaul** (L) | **(a) the bus layout** — XS and a hard dependency of four items. **(e) audible Object 12** — S, asset already on disk. The 19 Hz infrasound bed — ~15 lines, bonus layer only. | **(c) raycast occlusion** — per-emitter polling across eight levels. **(d) reactive music stems** — 2–4 authored stems *per level*, and §4.1(d) then spends a paragraph on how to stop them becoming a tell. Both L-shaped; nothing else depends on either. |
| **P7 death-degradation** (S) | **(b) cosmetic escalation** — safe by construction: *"none of these change a rule, a rate, a code, or a fail condition."* | **(a) re-randomisation** — carries the *"never re-roll in a way that can make the level unwinnable"* warning, which means per-level test coverage. |
| **P8 sanity suite** (S × 6) | **Effect 1** (the panic-spike lie — the crown jewel, and why defect (d) is fixed first) and **effect 6** (the observers' caption, which N3 and N4 both want anyway). | **Effects 2–5** — five separate builds for diminishing returns. |
| **Persistent save** (M) | **Deferred, not cut** — the only unbuilt row genuinely about *playability*. Quitting currently loses everything. | — |

**Cut indefinitely.** Grouped by why, since the reasons repeat.

*⚠️ Four new levels on top of eight existing ones — these are the §6.0 decisions:*
- ⚠️ **THE NIGHTMARE** (L+) — the largest build in the corpus, and the file says so. Five entities, a
  candle system, `dungeon_gen.gd`, ~14 textures, ~20 SFX, a bespoke panic ledger, and explicit
  *"do NOT register `RandomAmbient`" / "do NOT add an `ApparitionDirector`"* carve-outs — i.e. a
  second game with its own rules. Nothing in it is required for the game to be finishable.
- ⚠️ **OBSERVATION** (L) — ~500 lines, 4 textures, 4 SFX, 20 authored anomalies, a new 3-strike loop.
  Its stated justification is that it *"teaches the perceptual habit that `MovedProp` (P6) then
  exploits"* — but P6 is XS, zero-panic, and works fine untaught, which is the mechanic. **Building
  an L level to prime an XS one is inverted.**
- ⚠️ **THE ANECHOIC CHAMBER** (L) — explicitly *"depends on §4.1"*, an L system now split down. A
  level whose premise is a bus architecture that doesn't exist.
- ⚠️ **THE RETURN** (M) — **deferred, not cut.** The one new level worth keeping: reuses
  `intro_room.tscn` wholesale, 2 textures, 3 SFX, no fail state, and it is the twist ending's setup.
  Cheaper than several of the retrofits. **Condition:** Phases 0–3 ship first.
- ⚠️ **The 12-level renumbering commit** (M) — falls with the levels. Pure churn against a working
  9-entry map if no new level lands.
- **Investigation / deduction level** (L) — a twelfth level plus an evidence terminal and a verdict
  system, with nothing existing to build on.

*Already built under another name:*
- **Cipher puzzles** — KONTUR's `ROSTER_CODE` is *already* derived from two digit notes planted a
  level earlier (`backrooms_zone3.gd:_build_digit_notes`). That **is** the cipher, and it is the
  game's best puzzle.
- **Hidden passages** — the niche is occupied twice, by the Lab locker (`level_1.gd:516-523`) and
  `GlitchWall`'s seams, both better because they are gated on *knowledge* rather than on searching.
- **Chase & evasion "House pilot"** — piloting hiding/slam-doors in the House requires giving the
  House something to hide *from*, which is a second chase level by the back door (§8.4).
  **`hiding_spot.gd`/`slam_door.gd` shipping only in Level 6 is the correct outcome, not a partial
  one** — reclassify that §2.1 row as BUILT (scoped).

*Churn against work that was just done:*
- **Sequence fuse/valve puzzle** — it replaces the three Lab breakers, which were **just** rebuilt
  (the locker gate, the 10-room navigate-by-ear wing, the nook payoff, the Issue-33/34/36 fixes).
- **Static-lamp shadows** — the valuable half is free and already available (§2.0a). The remaining
  half would change the Lab dark wing's darkness model, which `level_1.gd:173-175` deliberately
  depends on. **Answer §7 question 3 with "no."**
- **P11 geometry mutation** — `SCARY.md` labels it *"the only proposal with real regression risk"* and
  *"do this last."* Last means not now, and its main justification is an unresolved user question.

*Blocked by architecture, for a benefit nobody asked for:*
- **Item combination / inventory** — blocked by §2.0(b), so it costs a `GameState` change first. It is
  an adventure-game verb this horror game has never wanted; KONTUR's single slot has proven
  sufficient across eight levels.
- **Cross-level backtracking with items** — same blocker. The half the user actually complained about
  (*"the level always starts from the beginning"*) is **BUILT**. Don't re-open `reset_level_state()`
  for the half nobody asked for.

*Wrong tool, or wrong register:*
- **TTS-narrated notes** — 15+ notes need voice, and the register the working pipeline produces
  (degraded institutional tannoy) is wrong for first-person notes. **Salvaged as N4**, 6–10 PA lines.
- **Wall-maze minigame** — placement was *never decided* (§7 question 4), the surest sign an idea has
  no home. The House already ships a 2D minigame with its own generator stress test.
- **Optional lore collectibles + end-of-game count** — a completion counter is a progress readout
  (§8.2's family), and it converts notes — load-bearing puzzle infrastructure in three levels — into
  checkboxes.
- **Volumetric fog** — already deferred, and its only sanctioned venue was THE NIGHTMARE.
- **Restoring `Vignette`** — don't. **Delete** the file and all five callers. It has been a no-op for
  the project's entire life and nobody noticed; that is the verdict.

---

## §7 — Open questions for the user

Decisions the project has deliberately **not** made. Do not resolve any of them silently in an
implementation session.

### 7.1 — The one that blocks everything else

⚠️ **Q1. Do the four new levels survive?** §6.2 recommends cutting THE NIGHTMARE, OBSERVATION and
THE ANECHOIC CHAMBER, and deferring THE RETURN. You accepted all four on 2026-07-27 and
`DUNGEON_NIGHTMARES.md` is a full 1,151-line spec for one of them. The recommendation follows from
today's *"playable game first"* answer and from the fact that the game is **already completable end
to end** — but the two answers genuinely conflict and this is your call, not the document's.
Everything in §6.1 Phase 4 and the renumbering commit hangs off it.

### 7.2 — Still open, unchanged

**Q2. The non-monotonic unreality curve.** The Backrooms is fully unreal, then KONTUR and The Breach
drop back to coherent real-world Soviet interiors before the Void goes unreal again. Three options
were put to you and you chose *"note it, decide later"*: degrade 5–6 in place (recommended by
`SCARY.md` §6, and **N8** is the mechanism for it); accept it as a deliberate breather; or reorder
(expensive — KONTUR's eight gates are answered by hints planted in four earlier levels, and the Flood
holds its roster-code digits). **N8 and P11 are both blocked on this.**

**Q3. The renumbering commit** — one commit touching `GameState`'s level map and scene constants,
`Screamer.LEVEL_SCREAMERS`, the `level_progress` rows, `level_3.gd`'s `current_level` and the
back-door chain, with `check_level_resume.gd` extended both directions. **Moot if Q1 cuts the levels.**

### 7.3 — Questions this session proposes answers to

These were open; §6 takes a position. Overrule any of them freely — they are recorded here so the
answer is visible rather than buried in a table.

| Question | Proposed answer |
|---|---|
| **Q4. Static-lamp shadows** — worth enabling on `OmniLight3D` room lamps? | **No.** §2.0(a) established the valuable half is already free (the flashlight casts in all nine scenes). The remaining half would change the Lab dark wing's distance-based darkness model, which `level_1.gd:173-175` deliberately depends on. |
| **Q5. Wall-maze minigame placement** — Void climax, or inside the investigation level? | **Neither — cut it.** Placement being undecided across two sessions is the signal; the House already ships a 2D minigame with its own generator stress test. |
| **Q6. Which existing level pilots chase & evasion?** | **None.** Giving the House something to hide *from* is a second chase level by the back door (§8.4). `hiding_spot.gd`/`slam_door.gd` living only in Level 6 is the correct scope. |
| **Q7. Persistent save semantics** — resume the exact scene, or the start of the furthest level? | **The start of the furthest level reached.** One serialised int, adds no checkpoint *inside* a level, and therefore leaves the no-checkpoint pillar and `restart_current_level()`'s snapshot wipe completely untouched. |
