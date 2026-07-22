# Idea Backlog — accepted, not-yet-built

Produced by the `idea-generator` protocol (`.agents/skills/idea-generator/SKILL.md`), run manually
since this project's `.agents/skills/*` entries aren't wired into the harness's Skill tool. This
file is the **implementation-ready menu of everything accepted across all sessions and not yet
built** — sessions are appended as dated sections below, not overwritten (see Step 5 of the skill
file). Once an item ships, remove its entry here and record the implementation date on its row in
`IDEA_HISTORY.md` instead. Full accept/reject reasoning for every idea lives in `IDEA_HISTORY.md`,
not here.

---

## Session 1 — 2026-07-22 — Foundational scares & pacing

### Mechanics reviewed
Already shipped (do not re-implement): gaze-panic props (`ScaryObject`), instant-fail
`trigger_object.gd`, read-to-die trap notes, fatal vs. survivable scares (`Screamer.trigger()` vs.
`flash_scare()`), the 3-rule `Apparition` system (HOLD/STARE/LOOKAWAY), `CreatureStalker`'s
Weeping-Angel LOS logic, `CreatureSmiler`'s inverted rule, zone-based panic modifiers
(`CalmZone`/`DarkZone`/`DreadZone`), and per-level sensory tells (Backrooms' sound-ducking +
darkness tells, KONTUR's 8 cross-level hint gates). Conspicuously absent: any *reactive* pacing
(every scare fires on a fixed timer/distance, blind to how the player is doing); no save/persist
system beyond "restart the current level"; no spoken audio; no physics-based prop scares; no
mini-game beat.

### Research consulted
Amnesia's sanity-meter-as-lie; Alien: Isolation's Director AI (ramps tension after a lull, eases
off after a scare); Iron Lung's constraint-only dread; sound-design surveys on pre-scare silence and
misdirection; Mouthwashing/Signalis's helplessness-over-jump-scares; the 2025-2026 indie horror
landscape (mostly co-op/investigation games, not directly portable here).

### Accepted (still pending)

- **1. Adaptive Director pacing.** Every scripted-random scare (blackout timers, pipe groans,
  `DEBUG_APPAR_INTERVAL`, the Corridor Manager) fires on a fixed timer/distance regardless of player
  state. Add a small autoload `scripts/director.gd` (`class_name Director`) tracking time-since-
  last-scare + panic ratio; expose `Director.calm_time() -> float` for timer-driven spawners to
  query before firing, and `Director.notify_scare()` (called from `Screamer.trigger()`/
  `flash_scare()` and `Apparition.appear()`) to reset the clock + enforce a cooldown. Touches: new
  autoload + hook edits in `level_1.gd`, `level_2.gd`, `corridor.gd`, `backrooms.gd`'s timer sites,
  plus one `notify_scare()` call each in `screamer.gd`/`apparition.gd`. Cost: M.
  *Open: roll out to all four levels at once, or pilot on the Lab first?*

- **2. Hide the panic "meter" — KONTUR only.** No literal numeric gauge exists today
  (`panic_hud.gd` drives blur/tint intensity from `set_panic_ratio()`), but that intensity is
  currently a precise 1:1 readout. Add `set_deceptive_mode(bool)` to `panic_hud.gd`, blending true
  ratio with slow-moving noise/lag before it reaches the shader uniforms; `kontur.gd` enables it in
  `_ready()`. Fits KONTUR specifically because its `DreadZone` cancels decay exactly, so every
  strike point is permanent and a precise readout is exploitable. Cost: S-M.

- **3. Persistent progress save.** Scoped to: remember the furthest level reached across app
  restarts (not mid-level state — `reset_level_state()` stays as-is). New `scripts/save_system.gd`
  (or folded into `GameState`) writes furthest `current_level` to `user://save.dat` on
  `advance_level()`; read on boot. `main_menu.tscn`/`main_menu.gd` gain a "Continue" button next to
  START, loading the scene for the saved level via a `GameState` scene-lookup table. Cost: M-L.
  *Open: does "Continue" resume the exact scene quit from, or always the start of the furthest
  level (simpler, consistent with existing per-level reset)?*

- **4. Falling/collapsing props.** A third ambient-jolt category beyond gaze-panic and instant-fail.
  New `scripts/falling_prop.gd` (`class_name FallingProp`): a `RigidBody3D` spawned frozen, a
  proximity trigger calls `topple()` — unfreezes, applies impulse/torque, plays a crash SFX, calls
  `player.add_panic()`/`jolt_camera()` directly (skip `ScaryObject`'s gaze path — this is ambient,
  not gaze-driven). Swap a few existing wall-decor pieces (House bedroom painting, Corridor
  paintings) for `FallingProp`-wrapped versions. Needs one new crash/creak SFX via
  `tools/make_sfx*.py`. Cost: M.

- **5. Misdirection pairing.** A static utility `scripts/misdirect.gd`
  (`Misdirect.fire(parent, decoy_pos, decoy_sfx, delay, real_callable)`), same pattern as
  `ScreenText`/`Vignette`. Plays a loud harmless decoy off to one side, then invokes the real scare
  elsewhere after ~0.3-0.5s, instead of always cueing dead-ahead. Wrap 3-4 existing
  `CorridorEvent`/`Apparition` call sites in it first. Cost: S-M.

- **6. ~~Hide-and-search interlude~~ — SUPERSEDED.** Session 1 originally proposed this as a new,
  standalone interlude. Session 2 (below) merged it into the broader **Unified chase & evasion
  system** — see that entry instead. Do not build this as a separate one-off; `IDEA_HISTORY.md`'s
  row for this idea has been annotated accordingly.

- **7. Pre-scare silence dip.** Generalize the Backrooms zone-2 bus-ducking trick
  (`silence_zone.gd`) into a one-shot static helper `AudioDuck.pulse(bus_name, db, duration)` (tween
  down, then restore), called from `Screamer.trigger()`/`flash_scare()` and `CorridorEvent` handlers
  ~1.5s before the payload fires. Cost: S.

- **8. TTS-narrated notes.** New offline tool `tools/make_tts_notes.py` (venv-based), running an
  offline TTS voice over each note's text, then a whisper/lo-fi filter (bandpass + noise), matching
  `make_sfx*.py`'s procedural-audio style. Output per-note `.ogg` into `game/assets/audio/notes/`.
  `note.gd`/`note_ui.gd` gain an optional `voice_path` played alongside the fullscreen text — works
  for both safe and read-to-die trap notes. ~15+ notes need audio; KONTUR's redacted signs are out
  of scope (not notes). Cost: M.

- **9. Wall-maze mini-game.** Self-contained UI mini-game `scripts/wall_maze.gd` + a
  `CanvasLayer`-based maze (mirrors `Beartrap`'s self-building escape-UI pattern) — trace a mouse
  path from start to goal without crossing walls. Framed as "prove your mind is still yours." Cost:
  M. *Open: placement — Void's Room C/D `DreadZone` climax proposed but not confirmed; Session 2's
  new investigation/deduction level (below) may also be a candidate venue — worth deciding together.*

---

## Session 2 — 2026-07-22 — Action density: puzzles, chase, mystery, defeat

User's framing: existing levels lean too heavily on **avoidance-as-the-only-agency** (don't flee,
don't stare, don't look back). This session's ideas are explicitly about giving the player more
things to actively *do* — combine, decode, reroute, chase-and-be-chased, uncover, overcome — both
retrofit into existing levels and as new levels built around a single strong verb.

### Research consulted
Resident Evil's "every door is a question, every key is an answer" map design + deliberate
backtracking (a design Frictional Games itself calls essential, not a chore); Amnesia's
physics-manipulation puzzles; Mr. X/Nemesis's persistent-roaming-stalker design (a safe
familiarization window, then some counter-play, not pure flee-or-die); Alan Wake's light-as-weapon
combat (sustained aim strips a shield before the "kill" lands); Little Nightmares' chase design
(break line-of-sight, improvise — vault/duck/slam — rather than pure outrun); fuse-box/sequence
puzzles in Song of Horror/Fear the Spotlight/MOLE (insert N fuses, dial to N — quantity-and-sequence
logic vs. flip-once switches); environmental-storytelling research on optional, lore-only secrets
that reward curiosity without gating flow.

### Accepted

- **10. Item combination puzzles.** A minimal 2-4 slot inventory (nothing like this exists today —
  current pickups are single-purpose: keycard, key items, bottles). Some barriers need two related
  items combined (a broken fuse + a spare, acid + a rag) rather than one pickup solving it outright.
  Extends the `key_item.gd`/`bottle_item.gd` pattern with a lightweight "combine" verb (no full
  RE-style grid inventory). Cost: M.

- **11. Cipher puzzles.** A lock's code is *derived* from two separate clues (a symbol key found in
  one room, raw symbols carved/painted in another) instead of handed outright in a single note —
  generalizes KONTUR's roster gate (currently a bare "47" from the intro note) into a repeatable
  puzzle type. Pairs directly with the existing `combination_lock.gd` — no changes needed there,
  just a new `cipher_note.gd`-style clue pair feeding it. Cost: M.

- **12. Sequence fuse/valve puzzle — replaces the Lab's breaker quest.** User confirmed: upgrade
  `breaker.gd`'s flip-once-times-three quest into an actual sequence/quantity puzzle (insert N fuses
  into the right sockets, dial to match N — Song of Horror/MOLE pattern), hinted by a wall-mounted
  schematic prop. Keeps the existing narrative beat (solving it still drops `MorgueShutter` via
  `_restore_power()`) but the solve itself requires reading + deduction, not three walk-up
  interactions. Cost: M.

- **13. Deliberate backtracking.** A door encountered early in a level that only opens once an item
  found much later is carried back through now-changed (and scarier — lights dimmer, a new prop
  active) territory. Nearly free: reuses `door.gd`'s existing unlock-condition framework as-is; this
  is a level-*sequencing* change in `level_1.gd`/`level_2.gd`/`kontur.gd`, not a new system. Cost:
  S.

- **14. Unified chase & evasion system.** Merges Session 1's now-superseded hide-and-search
  interlude (#6 above) with this session's breakable-line-of-sight chase and persistent-roaming-
  stalker pitches into **one system**, per user decision. Turns "flee = scripted fail" (today's
  `Apparition`/`CreatureStalker` logic) into "flee *well* = survive": a `HidingSpot` interactable
  (Area3D, suppresses footstep audio + gaze-visibility while held), `door.gd` gaining a
  `slam_shut()` a fleeing player can trigger to briefly block a pursuer, and a `Vaultable` prop for
  obstacles a pursuer can't cross. The persistent-stalker half needs a new creature-state script with
  actual patrol + proximity "notice" logic (simple waypoint patrol, not full pathfinding) — this is
  the first real departure from the project's stated "no active enemy AI" design pillar, and is
  flagged as such rather than let slide in as a minor addition.
  **User decision: pilot this in an EXISTING level first** (directly answers the original "not
  enough action" complaint), then reuse the proven system in the new Nemesis-style pursuit level
  (#18 below). *Open: which existing level pilots it — House (multi-room, more route-planning
  surface) is proposed over Corridor (single linear path, less suited to hide/evade routing), but
  not yet confirmed.* Cost: L.

- **15. Hidden passages.** A bookshelf/wall panel that reads as ordinary `RoomBuilder` wall decor
  but is actually a `SecretPassage.gd` interactable, revealed by a found clue ("the third shelf,
  second row") or an environmental tell (a draft, a hairline seam). Optional, lore-only — holds a
  bonus note, does not gate the main win condition. Cost: M.

- **16. Optional lore collectibles.** Small hidden props (a photograph, an audio log) per level, no
  progression gate, accumulating toward a light end-of-game payoff (e.g. a "you found X/Y hidden
  truths" beat before credits, or an alternate coda fragment). Rewards exploration without stalling
  flow. Cost: S-M.

- **17. Environmental takedown.** Instead of direct combat: lure a threat into a trap the player
  set up — a rigged door, a valve that floods the room — rather than avoiding it or fighting it
  directly. Directly reuses Session 1's `FallingProp` mechanic (#4 above) as the literal "weapon."
  Cost: M. *Folded into the Nemesis pursuit level (#18) as one of its defeat paths — see there for
  the full sketch rather than building this standalone.*

- **18. Nemesis-style pursuit level — NEW LEVEL.** The single biggest pitch this session:
  productizes #14 (chase/evasion) + #17 (environmental takedown) + a **light-as-weapon repel
  mechanic** (Alan Wake-style — a new creature type with a weak point that sustained, aimed
  flashlight exposure visibly wounds/dissolves) into one coherent level. A persistent stalker roams
  the level's full map for its duration (after a safe familiarization window, matching Mr. X's
  design — give the player time to learn the layout before the threat appears); survive by
  route-planning, hiding, and slamming doors (#14); ultimately "defeat" it either by wounding it with
  sustained aimed light or by luring it into an environmental trap (#17), which opens the exit.
  **User decision: this new level is where the light-as-weapon creature lives** (not an existing
  level), specifically to avoid any contradiction with `CreatureSmiler`'s opposite rule (light
  triggers *it*) in Backrooms. This is a large, multi-system build — recommend a dedicated scoping
  pass (level placement in the sequence, exact map layout, how "familiarization window" is paced)
  before implementation starts, same caution as Session 1's #6 before it was folded in here. Cost:
  L (largest item in the backlog).

- **19. Investigation/deduction level — NEW LEVEL.** Obra Dinn-style: gather scattered evidence
  (photos, audio logs, note fragments) across the level, then answer a final "who/what/when" at a
  terminal. Wrong answers cost strikes — reuses KONTUR's exact strike-and-forfeit economy
  (`STRIKE_PANIC`, the `_gates` ledger pattern) rather than inventing new fail math. Leans hard into
  the project's existing strength (environmental storytelling, cross-level hints, redacted signs)
  while adding a genuinely new verb: active deduction from multiple pieces of evidence, as opposed
  to a code handed out by a single note. Cost: L.

- **20. Shifting-architecture level — NEW LEVEL, lower priority.** Layers of Fear-style: corridors
  extend, rooms rearrange behind the player, doors lead to impossible spaces — ties beautifully into
  the twist ending's "your mind, not real" framing. Flagged as more atmosphere/geometry than new
  action-density, so ranked below #18/#19 against the "more actions" ask, but worth keeping on the
  backlog for the narrative fit. Cost: L.

### Rejected / Deferred
None this session — all thirteen candidate ideas were accepted (with #17's light-as-weapon half and
#14's hide-and-search half folded into #18 and #14 respectively, rather than built standalone).

---

## Open questions (consolidated, both sessions)

1. **Session 1 #1 (Director pacing)** — roll out to all four levels at once, or pilot on the Lab
   first?
2. **Session 1 #3 (persistent save)** — resume the exact scene quit from, or always the start of
   the furthest level?
3. **Session 1 #9 (wall-maze) / Session 2 #19 (investigation level)** — placement not confirmed;
   candidates are the Void's Room C/D climax or a slot inside the new investigation/deduction level.
   Decide together rather than guessing.
4. **Session 2 #14 (unified chase system)** — which existing level pilots it: House (proposed,
   multi-room routing) or Corridor (single linear path)?
5. **Session 2 #18 (Nemesis pursuit level)** — needs a dedicated scoping pass before implementation:
   where it sits in the level sequence, map layout, and how the familiarization window is paced.
