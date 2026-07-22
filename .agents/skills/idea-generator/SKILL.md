---
name: idea-generator
description: 'Research well-rated horror/indie games, study this game''s current mechanics, and run a discussion session with the user to decide what to add next — new mechanics, scare-delivery tricks, atmosphere/audio, pacing/engagement. Writes REPORT.md with the session''s conclusions and appends to IDEA_HISTORY.md (persistent, cross-session record of accepted/rejected ideas + reasoning) so future sessions do not re-pitch rejected ideas and build on accepted threads. Does NOT implement anything itself — that is a separate, later request. Triggers on: generate ideas, brainstorm, what should we add next, idea session, new mechanics, scare ideas, look at other horror games for inspiration, what are other horror games doing.'
---

# Idea Generation: Research → Brainstorm → Decide → Report

You are a creative-direction discussion partner, not an implementer. This session ends with a
written report and an updated history file — never with code changes. If the user asks you to
*implement* something from a past REPORT.md, that is a different task; say so and hand off rather
than quietly starting to write GDScript mid-session.

## The rule that outranks everything else in this skill

The point of this skill is a **good conversation**, grounded in two things read fresh every time:
what this specific game already does, and what the user has already said yes/no to before. An idea
pitched without checking both is either a duplicate of an existing system or a rehash of something
already rejected — both waste the user's time.

- **Never re-pitch a rejected idea silently.** If you want to revive one, say explicitly "we
  rejected X in [session] because [reason] — here's why I think it's worth reconsidering," and let
  the user decide.
- **Never pitch something that already exists.** Cross-check every candidate idea against the
  mechanics inventory (Step 1) before it reaches the shortlist.
- **Label sources.** Every idea should trace to either a specific game/technique you found, or to
  a gap you noticed in this game's own design — never present a bare assertion as research.
- **Discuss, don't dump.** A wall of 20 ideas gets a shallow yes/no pass. A shortlist of 6-10,
  presented with your own recommendation, gets a real conversation.

---

## Step 0 — Load memory first

Read `IDEA_HISTORY.md` at the repo root (create it from the template at the bottom of this file if
it doesn't exist yet). Build a quick mental table: idea → verdict → reason → session date. This is
the single most important read in the whole workflow — it's what makes session N+1 smarter than
session N instead of just repeating it.

Also skim `TODO.md` at the repo root — it's the team's own pre-Claude brainstorm (Russian/English
mixed, informal). Many entries there are **already implemented** (e.g. the "stare at the creature /
don't run" idea became `apparition.gd`'s `RULE_HOLD`; the panic-scale-too-fast complaint is now
tuned constants in `player.gd`). Treat it as a source of half-finished threads to check against
current code, not a list of open work — verify each item against the mechanics inventory below
before treating it as a live gap (checkpoints-several-levels-back, TTS'd note audio, and the
end-game mouse-maze read as still-unimplemented as of the last session that touched this file).

## Step 1 — Study the current game (fresh, every time — CLAUDE.md changes across sessions)

Read `CLAUDE.md` in full. Build an explicit inventory before doing anything else:

- **Panic economy**: `PANIC_MAX`, base rate, decay, sprint/dark/dread/calm modifiers, gaze vs.
  instant-spike sources, the if/elif priority chain in `_update_panic` (only one source fires per
  frame — additive only for `DreadZone` and standstill).
- **Scare delivery primitives already built**: `ScaryObject` (ambient gaze panic), `trigger_object.gd`
  (instant fail), `Screamer.trigger()` (fatal) vs `flash_scare()` (survivable), `Apparition` and its
  three rules (HOLD / STARE / LOOKAWAY), `CreatureStalker` (Weeping-Angel LOS logic), `CreatureSmiler`
  (inverted rule — light/sprint triggers it, stillness+dark survives it), `Beartrap` (escape-mash
  mechanic), zones (`CalmZone`/`DarkZone`/`DreadZone`).
- **Level-specific gimmicks** already shipped: procedural `RoomBuilder` levels, KONTUR's 8
  cross-level hint gates, Backrooms' 3-zone sensory tells (sound/darkness), the Corridor's
  distance-triggered Manager scare and turn mirrors, the Void's stare-off mechanic.
- **What's conspicuously absent**: no active enemy AI (per CLAUDE.md header), no dynamic music
  system beyond ambient beds, no branching narrative/multiple endings, no player inventory beyond
  single-purpose keycards/keys, no replayability hooks (seeds are randomised per-run but the content
  itself is fixed).

Optionally grep for `class_name` across `game/scripts/` to confirm a mechanic is real and not just
described in stale docs — CLAUDE.md is well-maintained here but treat it as a lead, not gospel, the
same way the rest of this project's tooling does.

## Step 2 — Research external games

Use `WebSearch`/`WebFetch`. Cast a wide net across both current-best-rated and classic influential
indie horror — don't fixate on one title. Useful angles:

- "best rated indie horror games [current year] mechanics" / "why is [game] scary game design"
- Specific titles worth checking for a distinct, nameable mechanic (not an exhaustive list, a
  starting point): *Amnesia* (sanity/no-combat), *SOMA* (body horror + philosophical dread), *Alien:
  Isolation* (single relentless AI stalker, no scripted safety), *Outlast* (camera battery as
  resource + can't-fight framing), *Visage* (haunted-house sanity + multiple interwoven stories),
  *Fears to Fathom* / *Iron Lung* (minimalist first-person dread, tiny scope), *Mouthwashing*
  (nonlinear narrative dread), *Devotion* (environmental storytelling, cultural specificity),
  *Signalis* / *Cry of Fear* (survival-horror resource tension), *Still Wakes the Deep* (walking-sim
  pacing), *Content Warning* / *Buckshot Roulette* (co-op or push-your-luck twists — likely not
  applicable to this single-player game, note that explicitly rather than forcing a fit).
- Look specifically for: scare-delivery mechanics that aren't jump-scares, tension-pacing patterns
  (how long calm before a spike, how spikes get telegraphed or don't), sound-design tricks, moments
  that trade player agency for dread, meta/twist techniques, and anything about *why* a mechanic
  reads as scary rather than just startling — that reasoning is what makes an idea portable to this
  codebase rather than a surface reskin.

Keep informal notes as you go: idea → source game → one line on *why it works there*. You'll refine
these into the shortlist in Step 3, not use them verbatim.

## Step 3 — Filter through feasibility

For every candidate that survives Step 2, before it can reach the shortlist, note:

1. **Which existing system it extends** (`ScaryObject`, `DreadZone`, `Apparition`, `RoomBuilder`,
   a new zone type) — a genuinely new primitive costs more and should be flagged as such.
2. **Rough cost**: small (config/tuning), medium (new script following an existing pattern), large
   (new subsystem, e.g. real enemy AI pathfinding, a save/checkpoint system, branching narrative).
3. **Collision risk with known engine gotchas** in CLAUDE.md's "building a level without
   coincident-surface bugs" section and the `ScaryObject`/emission/QuadMesh gotchas — a new prop or
   room type inherits every one of these.

Discard or downgrade ideas that don't survive this pass; don't bring them to the user just to
demonstrate research volume.

## Step 4 — Present and discuss

Group the survivors by category (Mechanics / Scare delivery / Atmosphere & audio / Engagement &
pacing / Meta & narrative). Lead with a shortlist of roughly 6-10, each as:

> **[Name]** — one-line pitch. *Inspired by [game].* Extends `[system]`. Cost: [S/M/L]. [Your
> one-line take — worth it / risky / niche.]

Then go through it with `AskUserQuestion` (or open conversation if the user wants to riff rather
than tick boxes) — Accept / Reject / Modify / Defer, per idea, and **capture the why** the user
gives for each verdict. That reasoning is the entire value of `IDEA_HISTORY.md`; a verdict without
a reason is nearly useless to a future session. Let the conversation wander — combining two ideas,
asking about technical feasibility, pushing back on your read of a reference game — and answer from
the codebase, not just the pitch.

## Step 5 — Write REPORT.md

`REPORT.md` at the repo root is the **implementation-ready menu of everything accepted and not yet
built** — not a single-session snapshot. Before writing, check whether a `REPORT.md` already exists:
if it does, keep any prior session's accepted items that haven't been implemented yet (carry their
full implementation sketches forward under their own dated section) and add this session's under a
new section — do not silently discard un-implemented work just because a new session ran. Once an
item is actually implemented, prune it from `REPORT.md` (it no longer needs a sketch) but leave its
row in `IDEA_HISTORY.md` intact, noting the implementation date/commit there instead. If this
session's discussion supersedes or merges an earlier session's still-pending item (as opposed to
implementing it), say so explicitly in both files — update the old item's `IDEA_HISTORY.md` row to
note what it was folded into, rather than leaving two contradictory entries. Structure each
session's section:

```markdown
# Idea Session — YYYY-MM-DD

## Mechanics reviewed
(brief inventory from Step 1 — what already exists, what's conspicuously absent)

## Research consulted
(games/techniques looked at, with one line each on what was relevant)

## Shortlist & verdicts
### Accepted
- **[Name]** — pitch, source, why accepted, cost estimate.
  **Implementation sketch:** which script(s) to touch or create, which existing pattern to follow
  (e.g. "new ScaryObject-chained StaticBody3D per the LivingMirror pattern"), which level(s).

### Rejected
- **[Name]** — pitch, source, why rejected (in the user's words where possible).

### Deferred
- **[Name]** — pitch, source, why deferred / what would need to be true to revisit it.

## Open questions
(anything still needing user input before implementation could start)
```

The "Implementation sketch" lines matter most — they're what lets a *later* Claude Code session
implement directly from this file without re-deriving design intent from scratch.

## Step 6 — Update IDEA_HISTORY.md

Append (never overwrite/never delete past entries) one row per idea discussed this session, using
the template at the bottom of this file. This is the persistent memory re-read at Step 0 of every
future run — keep entries terse; the reasoning is the only column worth spending words on.

## Step 7 — Handoff

Tell the user both files are written and where. Make explicit that implementation is a separate,
later step — "call me again and point me at REPORT.md to implement the accepted ideas" — rather
than starting to edit `.gd` files in the same breath.

---

## `IDEA_HISTORY.md` template (create with this skeleton if the file doesn't exist)

```markdown
# Idea History

Persistent record of every idea raised in an idea-generator session, its verdict, and why. Read
this before every new session — never re-pitch a rejected idea without saying so explicitly.

| Date | Idea | Verdict | Reason | Session report |
|------|------|---------|--------|-----------------|
```

Each new session appends rows to this table (one idea per row; keep "Reason" to a sentence — the
*why*, not a repeat of the pitch). If an idea gets implemented later, edit its row's Reason to add
"— implemented [date], see [commit/script]" rather than creating a duplicate row.
