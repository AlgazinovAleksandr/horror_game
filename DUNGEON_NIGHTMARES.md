# DUNGEON_NIGHTMARES.md — Level 9: THE NIGHTMARE

**Status:** ⭐ **BUILT AND SHIPPED, 2026-07-28.** This document remains the authoritative
design; the sections below describe what was intended, and every place the build
deviates from them is listed in "Deviations from this document" immediately after this
header. `CLAUDE.md`'s Level 7 section is the shipped summary.
**Written:** 2026-07-27. **Implemented:** 2026-07-28.

---

## Deviations from this document

Seven, all forced by measurement rather than preference. Each is commented at the site.

| § | Spec said | Shipped | Why |
|---|---|---|---|
| B2 | "Level 9" | **Level 7** (Void 7→8, ending 8→9) | Three of the levels ahead of it are unbuilt. Files are named `dungeon.*`, unnumbered like `corridor`/`backrooms`/`kontur`, so the future renumber renames nothing. Asset folders stay `level_9_dungeon/`. |
| B6 §1 | `K = 9` chambers | **12, floor of 9** | Seven sconces must fit in seven distinct non-bed chambers. Pure rejection sampling at K=9 produced 7 chambers on 2 seeds in 200 — one **unwinnable** dungeon per ~100 restarts. |
| B6 §6 | `h = 3.2` chambers, `h = 2.6` corridors | **uniform height + corridor drop-ceilings** | `RoomBuilder` keys wall dedup on `(axis, plane, HEIGHT)`, so mixed heights emit two coincident slabs per shared plane. Measured in `tests/probe_mixed_height.gd`; ISSUES_SOLUTIONS **Issue 41**. |
| B5 | candle energy 1.0, attenuation 2.4 | **2.2 / 1.4** | At the spec values with ambient 0.02, a chamber renders as pure black with a lit patch of floor — not "you cannot see the far wall" but "you cannot see the room". **The 4.5 m RANGE is untouched**, and range is what enforces §B7. |
| B7 | ambient ~0.02 | **0.045** | Same measurement. Still ~5× darker than any other level. |
| B12 | `dn_child_smear` and `dungeon_grate` as RGBA cutouts | **opaque** | The generation pipeline cannot produce alpha at all — it returns JPEG bytes whatever the filename says. ISSUES_SOLUTIONS **Issue 42**. The smear is a fullscreen `flash_scare` payload and needs none; the grate became a panel, with the teaching silhouette drawn AT it via `begin_teaching()`'s `reveal_anchor`. |
| B12 | `dn_sconce` / `dn_sconce_lit` on a quad | **real geometry, art unused** | The generated art has its own pale background baked in and rendered as a framed picture bolted to the wall — **Issue 35** verbatim, resolved the documented way. |

**Not deviations, but worth recording:** `dungeon_wall_ash` was never generated because
`level_6_breach/breach_incinerator_wall.png` already matches its brief exactly; and
`RoomBuilder`'s floor bridges z-fight with *each other* on a 3 m lattice, which needed a
level-local stagger (**Issue 43**).
**Companion to** `SCARY.md`, which holds the game-wide fear work. This file is one level.

A level dedicated to **Dungeon Nightmares** (KMonkey / Joey To, 2014) and **Dungeon Nightmares II:
The Memory** (2015), adapted to this project's "do not panic" philosophy.

---

## Table of contents

**Part A — the dossier** (what Dungeon Nightmares actually is)
- A1 Premise and framing · A2 Core loop · A3 Procedural generation · A4 The candle system
- A5 Entities · A6 The rules · A7 No sanity system · A8 Audio · A9 Jumpscare craft
- A10 Night escalation · A11 DN2 vs DN1 · A12 Visual style · A13 Open source (negative result)

**Part B — the level**
- B1 The central design problem, resolved · B2 Placement and fiction · B3 Structure
- B4 Entities · B5 The candle · B6 Procedural layout · B7 Darkness without fog
- B8 Panic economy · B9 Fairness and teaching · B10 Hard constraints · B11 What to drop
- B12 Assets · B13 Files touched · B14 Verification · B15 The one-paragraph pitch

---
---

# PART A — THE DOSSIER

## A1 · Premise and framing

**Developer:** KMonkey — **Joey To**, a solo developer in London who worked at PlayStation on
*VR Worlds*. **Engine:** Unity 3D, both games. Series: DN1 (2014) → DN2 (2015) →
*Ergastulum: DN III* (2017, on hiatus) → a Switch "Remastered" collection (2021).

The player character suffers from **pavor nocturnus** — night terrors.

- **DN1:** an unnamed male, later called *"The Explorer with Unknown Motives."* Official blurb:
  *"Every night you go to bed, you find yourself in an endless nightmare that you must escape from.
  The dungeon is littered with items for you to collect, including Candles that help light up your
  path. But be warned, you will not be alone in there."*
- **DN2:** the player is **Lisa Berstch**. The framing is upgraded from an implicit bed to a **hub
  world: the Hotel, Room 307.** Wake there, walk the corridor, ride the elevator **down** into the
  night, and on success wake back in 307 with the hotel slightly changed.

> **The single most transferable structural idea in the series:** the fail state and the
> level-transition are *the same fiction*. Waking up is both "you failed" and "next chapter."

Backstory is delivered through **28 dated diary notes**. The explorer finds a girl named Mary trapped
with him; she starves and changes; *"Day 18: I killed her... I killed her... I killed her..."*; Day 28
is corrupted glyphs. DN2 reveals he **burned her to death**, which is why every entity in DN2 is
charred and why paintings catch fire when stared at.

## A2 · Core loop

**DN1:** find the **Artifact** (a blue glowing book, visible from a distance *unless* it is in a
chest) → find the **Exit** (a ceiling hole with a ladder, floodlit from above) → the exit does not
work until the Artifact is collected. Score screen: time taken, % items collected.

**DN2** — a strictly better three-step design:
1. Find the **room key** (unlocks a Hotel room in the hub — the narrative reward).
2. Find and flip the **Elevator Switch** — a small **red light** on one of four faces of a stone
   pillar, always inside a chamber, never a hallway. Flipping turns it green.
3. Find the **Exit Elevator** — there are always exactly two; the exit's wheel glows **red when
   unpowered, green after the switch**.

Plus one **Optional Newspaper** per night and **film reels** on Nights 4–5. **All 7 newspapers and
both reels are required for the true ending.**

**What resets on death: everything.** DN1 is straight permadeath back to Night 1. DN2 softened it to a
**50/50 coin flip** — a black room, two doors, each hiding a pit; one continues the night, one ends
the run.

## A3 · Procedural generation

DN2 advertises **"100% procedural-generated maps"** and **permadeath** as its two headline features,
explicitly framed as tension mechanics.

**The layout vocabulary is exactly two things: HALLWAYS and CHAMBERS.** *"Any place that is narrow is
a hallway, any place wider than a hallway is considered a chamber, no matter how big or small."* This
distinction is load-bearing, not cosmetic:
- **Items only spawn in chambers.**
- **The elevator switch only spawns in chambers**, usually on a pillar face.
- **Mary only spawns in chambers, never hallways.**
- **Skeletons cannot spawn in a room smaller than 2×3 cells** — Nights 4–5 have almost none because
  every room there is 2×2.

Rooms are measured in **integer cells** ("2×2", "2×3", "3×2"), so the generator is a **cell lattice**
of axis-aligned rectangles. Size scales per night and re-randomises **every attempt**.

**The generator is buggy and they shipped it anyway** — props spawn blocking chests, two chests spawn
blocking each other, a prop can spawn in front of a door so you can open it but not walk through. The
official workaround on the wiki is *"restart the level."* Worth knowing: this is the failure mode our
`check_dungeon_gen.gd` exists to prevent.

**Why it feels confusing rather than merely random** — three reproducible reasons:
1. **Uniform skin per night.** Every chamber uses the same wall texture. No landmarks.
2. **The sight radius is smaller than a room.** *"You can never quite pierce the darkness more than a
   hand or two in front of your face."* You navigate a room you cannot see the far wall of.
3. **The map is a GPS, not a map** — it shows where you have *been*, as a trail. In DN1 it paused the
   game; in DN2 it does **not**, and you cannot walk while looking at it.

The critical trade-off, and the cost we inherit: procedural generation *"sacrifices the ability to
give players some intense, carefully crafted and interesting level design"* — but *"you will be
constantly contending with the unknown… those searches for keys and switches will be that much more
intense when you can't memorise their locations."*

## A4 · The candle system — the best-designed thing in the series

**Two distinct light actions:**

| Action | Cost | Effect |
|---|---|---|
| **Light a candle** | one candle | Sustained small light radius |
| **Spark** | free, unlimited | A flash of a few hundred milliseconds, then vision is *darker than before* until your eyes readjust |
| **Blow the candle** | wastes the remainder | Extinguish early |

**Economics.** DN2: a candle burns **exactly 60 seconds**, dimming the whole time; max carry 6;
**unused candles are deleted between nights.** DN1: max 9, and duration *shrinks every night*; the
Switch Remaster cut the cap to 3.

**Why "blow" exists at all — light is double-edged, because entities respond in opposite directions:**

| Entity | Candle lit | Spark |
|---|---|---|
| Ghost Girl | jumpscares **suppressed** | — |
| Mary | sees you from **further away** | can trigger an ambush |
| Skeletons | advance toward you; lighting **directly in front of one is an instant kill** | each spark advances every nearby skeleton one step |
| Tortured Soul | turns **invisible but keeps following** — reappears in front of you when it burns out | — |
| Dark Skeletons | — | stuns; **3 sparks kills one** |
| Fire Babies | move **much faster**, gain an **exploding** attack | — |
| **Asmodeus / The Ghost** | **still invisible** — the candle does nothing | **the only way to see him at all** |
| Shadow Corpse | he vanishes | — |

**There is no globally correct light posture.** By Nights 6–7 the wiki's advice is literally *"it is
probably better not to use candles at all — don't even collect them."* A light system that inverts
itself across a campaign. This is the thing most worth stealing.

## A5 · Entities

### DN1 — three real threats plus one harmless unit

**Mary (Bloody Mary).** A heavily charred mummy.
- **She is not always in the level.** The game *"initially makes players believe Mary is always
  somewhere in the map, wandering… but this is in fact not the case."* She **spawns**, hunts for a
  **Search Time**, **despawns**, and later **respawns**. Always in a chamber, preferentially near you.
- Night 1: spawns at 3:00–4:00, searches 20 s, 2 hits to kill. Night 7: spawns at **0:20–0:40**,
  searches 50 s, **one-hit kill**, running-aggro after 5 s.
- **Her walk speed equals yours** — but *"if the player fails to escape Mary for too long (around a
  minute), she throws a low-frequency roar and starts running non-stop at a speed almost as fast as
  the player's sprint."*
- **Closing a door on her slows her.** Doors *you* closed must be pounded open over several seconds.
- Carrying a lit candle **extends her detection range.**

**Skeletons** — the weeping-angel unit, and the smartest low-budget enemy in the game. Approach one
and exactly one of three things happens:
1. **Nothing.** It is a statue.
2. **It loses balance and falls over** with a loud crash. Pure jumpscare — and *this is the good
   outcome*, because a fallen skeleton can never stand up again.
3. **It follows you when you are not looking.** Turn away briefly → it is a step closer and **its
   stance has changed**. Turn away too long → it hits you from behind.
- **The audio tell is a dry wooden scraping drag on the floor.** The wiki FAQ: *"I hear a scratching
  sound as I'm walking, like there's something wooden scratching the floor, what is it?" → "It's a
  skeleton following you."*
- Once a skeleton has moved, **you can physically push it** — used to shove one through a doorway so
  you can close the door on it.

**Paintings.** Wall art that kills you for staring. Two exist: *Mary* (elongated neck, **eyes
closed** — on the death sequence **the eyes open**) and *The Explorer*. They emit a proximity sound —
Mary's painting **cries**. **In Night 1 they are purely decorative; from Night 2 they kill.**

**The Ghost Girl.** A charred girl in a yellow-beige dress, appears **only in the dark**. Hit-and-run
sprints past leaving a blood smear, peek-a-boos, a bloody skull flash. **She deals no damage.** Her
entire function is to burn your nerve and mask real threats. **Suppressed by a lit candle.**

### DN2 — the full roster

**The classification is itself a mechanic.** *"Primary Monsters are the main chasers… **The presence
of a primary monster is characterized by the absence of the BGM.** When a Primary Monster spawns, the
BGM stops playing."*

**Primary:**
- **Mary** — as DN1, but now **breaks walls** as well as doors. She can be **idle**, standing still in
  a chamber; observe her without approaching and she eventually vanishes and relocates — and *"facing
  the direction she is in while observing her seems to make her take longer to disappear."*
- **The Ghost / "Asmodeus"** — the best enemy in the series. A small charred boy-shadow with red eyes.
  **Permanently invisible. A lit candle does nothing.** He walks through closed doors. He does not
  know where you are until he finds you. **Contact is an instant kill.** He is **slow**, so escaping
  is trivial *once you know he is there*. **The only tell is audio** — footsteps *"more like a door
  knocking, but with the hits coming at a low frequency… easily mistaken for a knocking sound coming
  from a chest nearby. It isn't loud."* **The only way to see him is to SPARK.** At 1–2 m, screen
  shake is the last warning. On Nights 4–5 he must first be **released from a chest** — and **once
  released he stays released for every subsequent night**, a permanent, player-caused difficulty
  increase.
- **The Mist / "Flying Skull"** — a fast hovering skull in a red aura that does not know where you
  are. Its tell is **visible**: its red light spills around corners before you see it.

**Secondary:** **Skeletons** (plus: sparking near one that is already close is an instant kill) ·
**Dark Skeletons** (from Night 4; open closed doors instantly; **a spark stuns, three sparks kills** —
the only killable enemy) · **The Tortured Soul** ("Ghost Lady", an explicit P.T./Lisa homage — once
she sees you she follows for the rest of the level and never loses you; **lighting a candle makes her
invisible, not gone**, and she reappears directly in front of you when it burns out) · **Ghost Girl**
· **Fire Babies** (candle out: crawl slowly; candle lit: much faster, and they gain a
suicide-explosion) · **Shadow Corpse** (damage **0** — the only harmless monster; **he is the game's
whisperer**).

The Shadow Corpse's phrase list is a masterclass in cheap menace: *"Are you ready?" · "Don't stare at
me." · "Every room feels alive. I hear it breathing." · "I can hear every footstep you make." ·
**"Look behind you."** · "I wouldn't look in the mirror." · "No one ever leaves this place." · "So
scared, so scared, so scared…" · "Wake up." · "YOU SHOULD NOT HAVE COME HERE!"*

**Traps (DN2 only):** guillotines, a fan over a bottomless pit, trap floors, iron grating that erupts
with fire on Nights 6–7, swinging blades, chewing doors — and the **Spinning Cog**, whose stated
function is that *"it is loud enough to cover other important sounds, such as Mary's footsteps."* A
deliberate **anti-tell**, and a genuinely great idea.

## A6 · The rules — what is punished and what is rewarded

**Punished:** standing in one chamber too long (Mary can spawn *in the room you are in*) · sparking or
lighting a candle inside an unscanned chamber (correct practice: *"light a candle when you are in a
hallway and keep it lit when you enter the chamber"*) · turning your back on an upright skeleton ·
staring at a painting · opening chests after you already have the objective (Asmodeus risk) · running
when not being chased (stamina) · **carrying a lit candle at all on Nights 6–7.**

**Rewarded:** **listening** — the BGM cutting out is the single most valuable piece of information in
the game, and it is free · **door discipline** — open every door once, then close it behind you, so
Mary must batter it (announcing her position) and any door you later find open was opened by *her* ·
keeping a skeleton in view while backing away · **deliberately approaching an idle skeleton** so that
if it is going to fall, it falls while you are watching · in DN2, **letting Mary chase you on purpose
to deny Asmodeus a spawn slot.**

**"Don't look / don't run / hide" analogues that literally exist:** don't look away (skeletons),
don't stare (paintings; and Mary when idle), don't run (stamina), don't light (Asmodeus, skeletons,
Fire Babies), don't open (chests). **There is no hiding mechanic** — no lockers, no wardrobes. Doors
are the only defensive verb.

## A7 · Sanity / fear system

**There is none.** This matters for the adaptation. DN has a **health pool that regenerates**
(signalled by blood at the screen edges), a **heartbeat** that *"plays at a constant rate, regardless
of whether Mary is near or not"* — deliberately uninformative — and stamina (DN2 only).

The "sanity" is entirely in the player's head. There is no meter to game. **That is the biggest
structural difference from this project**, and §B1 is about resolving it.

Note the one detail worth stealing verbatim: **when the ambience drops out, the heartbeat is the only
thing left audible.**

## A8 · Audio

DN is, by near-universal agreement, an audio game with pictures. *"The sound design is where Dungeon
Nightmares really shines. Headphones are highly recommended."*

**The layer stack:**
1. **BGM / ambience** — mostly wind, always present. **Its absence is the game's most important signal.**
2. **Heartbeat** — constant, never informative, and the *only* sound left when the ambience ducks.
3. **Chase theme** — a screechy repetitive metallic sound that starts when Mary spots you and **fades
   as she loses you.** You navigate the chase by the volume envelope.
4. **Positional footsteps** — Mary's are recognisably hers; **Asmodeus's are deliberately confusable
   with a chest sound**; Dark Skeletons' are near-identical to Asmodeus's *on purpose*.
5. **The bone-scrape** behind you = a skeleton is following.
6. **Flies** — over harmless corpse props *and* over inactive Dark Skeletons. They can also mask the
   absence of BGM.
7. **The cog trap** — a machine whose function is to **drown out Mary's footsteps.**
8. **Painting proximity sounds** — Mary's *cries*.
9. **Whispers** — the Shadow Corpse's lines, delivered as ambient one-shots so you cannot tell threat
   from flavour.

**Silence is the primary instrument.** Everything else is built around the fact that the game can take
the soundtrack away from you.

## A9 · Jumpscare craft

**Environmental stingers (zero stakes, high frequency):** steam bursting from ceiling pipes; a door
that flies open, screams steam and slams itself; a skeleton losing its balance.

**Black Screen Hallucinations:** the screen goes fully black for a beat, then one of — nothing at all;
Mary in front of you making slow arm movements; the Ghost Girl staring; a door opening plus footsteps
plus a scream; a whisper of *"I'll always be with you. ALWAYS!"*
⚠️ In DN2 these fire **every 240–360 s, but only while no Primary Monster is present.** The game
**never stacks a fake scare on top of a real threat.** That is the fairness rule that makes the whole
economy legible, and it is the one we must copy.

**Flash-Picture Hallucinations:** sub-second full-screen flashes with screaming. *"Before the player
knows what they saw, everything goes back to normal."*

**Set-piece hallucinations, night-locked:** the **Endless Hallway** (teleported to a corridor with a
giant Mary painting behind you that *follows you down the hall*; map and candles disabled) and
**Burning Alive** (fire erupts with layered human screaming — and in DN1, *"the skeletons in your room
may have moved"* while the screen was black).

**Why it works:**
- **Density is inversely proportional to potency, and DN2 knew it.** *"Jump scares don't occur as
  often as in the previous game and this is why they catch the player off-guard most times, hence they
  are more effective."*
- **Darkness does the work the budget can't.** *"The game works as a jump scare factory because it is
  so, so dark."* Low-poly Unity models read as terrifying at 3 m in a 4 m light radius.
- **Procedural generation removes the memorised beat.**
- **The harmless scares train you to distrust the harmful ones.** Ghost Girl, pipes, falling skeletons
  and blood pools are all free; the Fan, the paintings and Asmodeus are not. By Night 5 the player
  cannot tell which class they are in. That is the entire point.

Common criticism, worth heeding: *"a little too dark with not enough candles."*

## A10 · Night escalation

**DN1 — 7 nights.**

| Night | Walls | Skeletons | Paintings | Candles | Mary |
|---|---|---|---|---|---|
| 1 | Grey stone | Few, mostly inert | **Harmless, silent** | Last long | 2 hits; spawns ~3:30 |
| 2 | Grey stone | Few, low follow chance | **Now audible and lethal** | Last long | 2 hits |
| 3 | Red/green brick + foliage | Medium, high follow chance | Lethal | Shorter | **Endless Hallway** |
| 4 | + more foliage | High | Lethal | Shorter | **Burning Alive** |
| 5 | Transitional | **Highest** | Lethal | Short | **One hit kills** |
| 6 | Black/red "hell" | Highest | Lethal | Shortest | Very high respawn |
| 7 | Hell | Highest | Lethal | Shortest | Spawns in **20–40 s** |

> **The escalation is NOT "more enemies." It is the same enemies with different rules.** Night 1
> paintings are decoration; Night 2 paintings are a fail state. That is a teaching structure, and it
> is the single best thing to steal from the campaign design.

**DN2:** Night 0 is a pure tutorial (three chambers, no enemies, no lethal traps). N3 debuts the
Tortured Soul. N4–5 are a **total context switch** — a burning hotel floor, every door labelled "Room
307", all rooms exactly 2×2, a 10-minute time limit. N6–7 are hell dungeons with fire-erupting floor
grating where *"the corners are the main safe places."*

## A11 · DN2 vs DN1

| | DN1 | DN2 |
|---|---|---|
| Frame | Implicit bed | **Room 307 hub hotel** with per-night story rooms, a TV, a projector |
| Maps | 3 hand-authored, fully revealed | **100 % procedural**, fog-of-war |
| Map screen | **Pauses** | **Does not pause** |
| Objective | Artifact → exit | **Key + switch → exit elevator** |
| Death | Straight to Night 1 | **50/50 coin flip** |
| Movement | Walk/run | + jump, + **stamina** |
| Candles | Up to 9, duration shrinks | **Exactly 60 s**, max 6, deleted between nights |
| Enemies | Mary, Skeletons, Paintings, Ghost Girl | + Asmodeus, Mist, Tortured Soul, Dark Skeletons, Fire Babies, Shadow Corpse |
| Scare cadence | Very frequent | **Deliberately rarer, therefore more effective** |
| Stated design | — | *"Combat-less gameplay"* + *"Intelligent AI that changes based on the way you behave each night"* |

## A12 · Visual style

Low-fi Unity 3D; reviewers place it alongside *Slender* and *Amnesia* and note the atmosphere comes
*"primarily from environmental audio rather than visual complexity."*

Palette per night: grey stone → brown brick → red/green brick with foliage → burnt hotel → black/red
blood-slick hell. Props are few and repeated: barrels, tables + chairs, shelves, chests, stone
pillars (which carry the switch), skulls, corpse props, red ceiling pipes, wooden and iron doors,
braziers.

**DN1 uses fog** — the official feature list says *"visual effects including fog and particle
effects."* We do not have fog; §B7 is how to get the same three effects without it.

**The darkness is the art direction.** The wiki puts a brightness disclaimer on essentially every
screenshot on the site: *"the brightness was raised… the player is NOT supposed to be able to see this
well when playing."*

## A13 · Open source — a negative result, recorded so nobody re-searches

**There is no meaningful open-source DN clone, decompilation, or asset dump.**
- GitHub returns two repos, neither useful: `TonimatasDEV-Storage/NightmaresBite` (a Minecraft mod)
  and `Linc7991/DungeonNightmares` (a 4-commit, 0-star personal Unity project whose README is only an
  itch.io link — an unrelated student game that shares the name).
- No decompilation project, no ripped-asset repo, no Unity teardown.
- **The Fandom wiki is the de facto reverse-engineering effort and is unusually good** — it quotes
  **internal game-file names** (`Ghost Lady` = Tortured Soul, `Dead Skeletons` = Dark Skeletons,
  `Mist` = Flying Skull, `Shadow Corpse` = Crawling Demon), exact spawn/search/chase timers per night,
  exact damage values, and unit caps. Someone has been inside the assemblies. **Treat the wiki as the
  primary technical source.**
- ⚠️ **Research note:** the Fandom wiki blocks the standard fetch path (HTTP 402). Retrieve through
  the MediaWiki API (`action=parse&prop=wikitext`), which returns raw source including the per-night
  timing tables the rendered pages bury in templates.
- Generator reference class only (unrelated to DN): `vazgriz/DungeonGenerator` (Delaunay + MST + A*),
  `SolAnna7/TaurusDungeonGenerator`, `damarindra/Unity-Dungeon-Generator` (BSP).

---
---

# PART B — THE LEVEL

## B1 · The central design problem, resolved

**The tension, stated plainly.** Dungeon Nightmares is a game about **running away**. Mary walks at
your walk speed, so the correct answer to *"the music stopped and I hear footsteps"* is Shift. This
game charges **+6 panic/s for sprinting, with decay suppressed**, out of a 50-point bar. A four-second
sprint is 24 points — half your life — and the entire thesis is *"the player wins by keeping their
nerve."* Naively porting Mary produces a level where the correct play costs half your health bar. That
is the double-jeopardy shape this project has already documented three times.

**The resolution is not to remove the chase. It is to notice that running was never DN's skill.**

Read DN1's own Tips page: *"How do I increase my chances to survive Night 7? It's simple. **Don't
run, unless you are in a chase.** You may bump into Mary at any moment, so conserve your stamina and
**listen carefully to BGM**."* And: *"You are actually safer at the end of a chase than not in a
chase, because when the chase ends you never know when and where you will encounter her again."*

DN's real skill is **early detection and route discipline**. The BGM cut is a free, several-second
warning. Door discipline converts a chase into a delay. Running is what you do when you have *already
failed* to listen — the emergency brake, not the technique.

### The five rules that resolve it

**Decided with the user, 2026-07-27:** the sprint tax stays at +6/s, unchanged, with **no
special-casing for this level.** No rule the player has to unlearn.

1. **The pursuer's chase speed is 3.4 m/s — BELOW the player's 4.0 m/s walk.** Not between walk and
   sprint like `CreatureObject12`'s 5.0. **Below walk. Walking away always works.** Sprinting is a
   shortcut you *may* buy with panic; it is never the answer.
2. **The tell arrives 8–12 seconds before contact is possible**, is unmissable if you are listening,
   and is free to act on. A player who hears it and turns around loses nothing at all.
3. ⭐ **Sprinting deafens you.** Your own footsteps mask the pursuer's footsteps and the Hollow One's
   knock. **Running makes you blind to the thing that would have made panic unnecessary.** Diegetically
   true, mechanically vicious, and it needs no new economy — just a volume duck on the creature bus
   while `player.is_sprinting()`.
4. **The silence does not damage you — it stops you healing.** While a primary entity is present, the
   level ducks its ambient bus (`silence_zone.gd`'s mechanism, driven by entity state rather than an
   `Area3D`) **and** suppresses panic decay with **zero additive pressure**. Net panic change from the
   mere presence of a monster is **zero**. All the pressure is in what you choose to do about it.
   ⚠️ Implement as a new one-line `player.set_no_decay(bool)`, **not** by abusing `DreadZone` — that
   would add +2/s and re-create the Corridor Zone-C stacking problem.
5. **The flagship entity's correct answer is to STOP AND LISTEN.** See the Hollow One (§B4.3). A
   mechanic that literally rewards not panicking, inside a franchise about panicking. That is the
   thesis statement.

**Result:** DN's chase survives intact as a *feeling*. The player is hunted, hears it coming, closes
doors, backs down corridors, and never once has to touch Shift. If they do, it is a legible
self-inflicted cost — the same contract as every other level.

---

## B2 · Placement and fiction

**Level 9**, in the agreed 12-level order (`SCARY.md` §6):

```
… 7 KONTUR → 8 THE BREACH → 9 THE NIGHTMARE → 10 The Void → 11 THE RETURN → Twist ending
```

**Why here.**
- The Breach ends with Object 12 incinerated — a hard, clean, *earned* win. The Void is a dissolution
  level. Something has to sit between "you beat the monster" and "reality comes apart."
- The Void already owns "geometry is wrong." The Nightmare owns "**sleep** is wrong." Different
  failure of reality, adjacent on the arc, and it advances the escalating-unreality pillar cleanly:
  the last three levels are dream → broken geometry → the loop.
- The candle rule needs a level where losing the flashlight is a **premise**, not a punishment. Coming
  off the Breach — where the flashlight was a *weapon* — makes its confiscation land as an escalation.

**Fiction — why the experiment does this to Subject 47.** The intro note already establishes the
frame: *"This is a psychological experiment… Stay calm… We are watching."* Levels 1–8 were **waking**
trials. Trial 9 is the **sleep** trial, and the protocol note in the Antechamber says so:

> **PROTOCOL 7 — REM DEPRIVATION**
>
> *Subject 47 has demonstrated composure under observation. Composure under observation is not
> composure. We are now removing the observation.*
>
> *You will be put down. What you find below is not ours — it is yours, and it has been there since
> before we found you. You will be given a candle because we cannot give you anything that runs on
> our power down there.*
>
> *The trial will be repeated until the data is consistent. Do not be alarmed by the repetition.*
> ***You will not remember it as repetition.***

This does four things at once:
- **It makes death diegetic for the first time in the game.** The no-checkpoint rule stops being a
  design convention and becomes the *plot*: fail, wake in the cot, run the trial again. Every other
  level has to apologise for the restart; this one is *about* it.
- It justifies confiscating the flashlight without reading as an arbitrary nerf.
- **"You will not remember it as repetition"** is the in-fiction licence for procedural regeneration.
- It sets up the twist. A level where the observers **admit they are repeating the trial and admit the
  place is not theirs** is the strongest foreshadowing available for the intro-room ending.

**Cross-level hint plants** (the KONTUR pattern — the answers live in earlier levels):
- **Lab morgue**, alongside the existing hidden note: *"Trial 7 log — the light attracts the still
  ones. Hold your breath and hold your ground."*
- **House cellar**, a candle stub on a shelf with a scrawl: *"SIXTY SECONDS. COUNT THEM."*
- **Corridor door plate near d=250 m** — the single most important hint in the game, and it must exist
  somewhere the player has already walked: *"WE STOPPED PLAYING MUSIC ON THE LOWER FLOORS. THE
  SUBJECTS COMPLAINED THEY COULDN'T HEAR IT STOP."*

---

## B3 · Structure — one night, packed

**Decided with the user:** one night, dense — **not** DN's escalating multi-night campaign. Three
nights would be three thin levels; one packed night is one good one.

```
Antechamber (the cot) ──sleep──> THE DUNGEON ──light 7 sconces──> the bed ──> exit door → The Void
```

### The Antechamber
A small hand-built room, always identical, lit by one guttering brazier. It contains:
- **the cot** — the framing device made physical. `interact()` on it, not a trigger volume: the player
  chooses to go under. Fade to black, 2 s, wake standing in the dungeon's entrance chamber. That is
  DN2's elevator, minus the elevator.
- **a `CalmZone`** (decay ×2.5) — safe ground.
- **a candle rack** — you start with 4.
- **the protocol note** (§B2) and a wall scrawl: *"YOU CANNOT HEAR IT OVER YOURSELF."*
- **the exit door** — `door.gd` with `extra_lock = true` and a `locked_message` naming the shortfall,
  exactly `kontur.gd:_refresh_exit()`'s pattern.

### The night — seven sconces
The dungeon is pitch black. **Seven wall sconces** are scattered across the chambers. Light one with
your candle and it becomes a **permanent `CalmZone` island** (decay ×2.5) that stays lit for the rest
of the night. The bed — the exit — is only revealed once all seven burn.

**The seven sconces are the escalation clock.** The level physically gets *safer* as you progress
(more light, more calm islands) while the roster escalates to compensate. This is DN's *"same objects,
different rules"* teaching structure — the best thing in the source material — compressed into one
night:

| Sconces lit | What changes |
|---|---|
| **0–2** | Still Ones only. Weeping Frames are **silent and harmless**. No pursuer. This is the tutorial, and it is not signposted as one. |
| **3** | The Weeping Frames become **audible** and feed gaze panic. Still harmless to stare at. |
| **4** | **The Matron** begins her spawn/hunt/despawn cycle. The ambient bed starts cutting out. |
| **5** | The Weeping Frames become **fatal** at 3 s of gaze, and visibly ignite as the wind-up. |
| **6** | **The Hollow One** arrives — preceded by its scripted, zero-risk teaching beat. The Kneeling Man begins whispering. |
| **7** | The bed is revealed, ~40 m away, and every entity is active at once for the walk to it. |

**Target length: 12–15 minutes** for a clean run — comparable to the Backrooms' three zones. Death
restarts the level (standard); the dungeon re-generates, so a restart is never a re-run of something
already solved.

**`save_progress()` keys:** `sconces_lit`, `layout_seed`, `content_seed`, `candles_held`,
`teach_beats_done`.
⚠️ **Restore the seeds; never re-roll them.** Restoring "5 sconces lit" against a re-rolled layout
would mark progress on a dungeon that no longer exists — the exact warning already attached to
KONTUR's `_dark_x`.

---

## B4 · Entities

Mapped onto existing scripts wherever the behaviour genuinely matches; new scripts only where it does
not.

### B4.1 · The Still Ones (DN's Skeletons) — reuse `creature_stalker.gd`, near-verbatim

The luckiest fit in the whole proposal. `CreatureStalker` is **already** a weeping angel: freezes in
your FOV + LOS (`ENGAGE_DIST 8`, `FOV_DOT 0.55`), advances at 1.25 m/s when unobserved, lunges →
`Screamer.trigger()` on contact, feeds gaze panic at 0.6 intensity, has `START_GRACE`, and has the
**stare-off** (4 s of held gaze pushes it back 3 m, at ~48 panic).

DN's skeleton **is** this, with three additions worth porting:

- ⭐ **The scrape tell.** A positional `bone_scrape` loop parented to the creature, gated on
  `state == ADVANCING`, `unit_size ≈ 6`. This is a **fairness upgrade over the existing Void
  creatures**, where the only tell is looking. **Consider back-porting it to the Void.**
- ⭐ **The fall.** ~35 % of Still Ones are **duds**: approach within 3 m and they topple with a crash
  (`skeleton_fall`) and are inert forever. This is the teaching beat and the tension engine at the
  same time — **you cannot tell a dud from a killer without walking up to one.**
- **The light reaction.** A **spark** within 8 m advances every Still One by one step (~1.0 m)
  instantly. A spark **within 2.0 m of an active one is instantly fatal.** DN's exact rule, and the
  reason light is dangerous here.

**Placement:** chambers of ≥ 2×3 cells only, never corridors. DN's rule verbatim.
**Count:** 6 across the dungeon; more become active as sconces are lit.
**Keep:** the stare-off, and instant-fatal contact (project convention — no HP, no grabs).

⚠️ All three additions must be `@export`ed and default to **off**, so the Void's creatures are
untouched.

### B4.2 · The Matron (DN's Mary) — reuse `creature_object12.gd`, retuned

`CreatureObject12` already has PATROL / INVESTIGATE / **CHASE (closes unconditionally — never
cheeseable by staring)** / **SEARCH (walks to last-seen, scans 8 s)** / STAGGERED, plus `force_block()`
for door battering, `notify_noise()`, and a `_detect_player()` that short-circuits on
`player.is_hidden()`.

| Constant | Breach value | Nightmare value | Why |
|---|---|---|---|
| `CHASE_SPEED` | 5.0 | **3.4** | Below the player's 4.0 walk. §B1. |
| spawn model | permanent after a timer | **cyclic**: spawn → hunt `HUNT_TIME` → despawn → wait `SPAWN_GAP` | DN's actual model. She is *not* always there, and that uncertainty is the whole feeling. |
| spawn location | fixed | **a random chamber ≥ 12 m away, never a corridor** | DN's rule verbatim. |
| `CONTACT_DIST` | 1.0 → fatal | unchanged | Project convention. |
| light weapon | shield / stagger | **removed entirely** | You carry a candle, not a torch. "Combat-less" is the pillar. |

Cycle: first spawn at 4 sconces, `HUNT_TIME 50 s`, `SPAWN_GAP 35 s`, tightening to 65 s / 25 s at 6+.

**The tell — three layers, and this is the heart of the level:**

1. ⭐ **The silence.** On spawn, duck the runtime `"Dungeon"` bus to −24 dB. `silence_zone.gd` already
   proves the mechanism; here it is driven by entity state, not by an `Area3D`. **The heartbeat must
   be routed OFF that bus** (the `Body` bus from `SCARY.md` §4.1) so DN's signature effect reproduces
   exactly: the world goes quiet and your own pulse is the only thing left.
2. **The decay freeze.** While ducked, `player.set_no_decay(true)`. Panic **holds**; it does not climb.
   §B1 rule 4.
3. **Positional footsteps** (`matron_step`, `unit_size 14`) once she is within ~14 m, plus a
   `matron_theme` chase loop **whose volume envelope tracks her distance** — DN's "the music fades as
   she loses you." That envelope is the player's sonar, and it is free.

⚠️ All three are masked while `player.is_sprinting()` (§B1 rule 3).

**Counter-play is doors, exactly as in DN.** Every chamber↔corridor doorway gets a `SlamDoor`
(`slam_door.gd`, already shipped): press E while passing to slam it. `check_blocks_path()` +
`start_battering()` already pauses a pursuer for ~10 s on any door on its path. That is Mary's
door-pounding, already written and already tested — **and the battering thud is also a locator**, so
you learn exactly where she is. Reuse `door_batter.wav` from `level_6_breach/` directly.
⚠️ Do **not** create a second file with that base name — `GameState.load_audio()` resolves by base
name across every subdir, and `door_slam` already collides in two folders.

**Hiding:** **two** `hiding_spot.gd` units (a sarcophagus niche, a collapsed alcove), never in the
same chamber, never in a dead end. DN has no hiding, but `enter_hiding()` (movement frozen, ±50° peek
cone, footsteps auto-silenced, `_detect_player()` short-circuits) is already built and is a *better*
answer to a slow pursuer than sprinting. It is the mechanical embodiment of "do not panic." **Two** is
right: enough to be a real option, few enough that it isn't the default.

### B4.3 · The Hollow One (DN's Asmodeus) — new `creature_hollow.gd`. The flagship.

This is the mechanic that makes the level worth building, and it is the purest expression of the
project's philosophy anywhere in the game.

- **Completely invisible.** No mesh, no billboard, `visible = false` permanently.
- **The candle does nothing.** Explicitly. The player must learn this.
- **Slow** — 2.2 m/s, well below walk. Escaping is *trivial once you know where it is.*
- **Contact within 1.2 m = `Screamer.trigger()`.**
- **It does not know where you are** until it gets within ~5 m; then it locks on and follows.
- **The only tell is audio**: `hollow_knock`, a low-frequency, quiet, irregular knock at
  `unit_size 8`, `volume_db −12` — deliberately confusable with a chest lid or a settling door. Per
  DN, it should be **quiet enough that you have to stop moving to hear it clearly.** That is the point.
- ⭐ **The only way to see it is to SPARK.** A spark reveals a dark silhouette (an unshaded RGBA
  billboard) at `alpha 1.0 → 0` over **0.30 s**. One frame of truth, then gone. Now you know the
  bearing.
- **At 1.8 m: `jolt_camera(0.6, 0.4)`** — DN's screen-shake last warning. Then you have ~0.3 s.

**Why this resolves everything.** The correct play is: *hear something wrong → stop walking → listen →
spark once → identify the bearing → walk calmly around it.* **Stopping and listening is the winning
move.** Running is actively fatal, because your own footsteps mask a −12 dB knock — you cannot hear it
while sprinting, and you will walk into it. **A player who panics dies; a player who stands still in
the dark and thinks lives.**

**Fairness — non-negotiable:**
- Arrives at 6 sconces. Never before.
- ⭐ **First encounter is taught, loudly, at zero risk.** A scripted demonstration: the knock passes
  across a **sealed side-chamber the player cannot enter**, a `ScreenText.caption` prompts a spark, the
  silhouette shows through the grate, and it walks away. This is `apparition.gd`'s `teach=true`
  contract applied to a new entity.
- **One instance.** It is not a swarm.
- ⚠️ **Never simultaneous with the Matron.** DN's own rule (*"He never spawns when Mary is already
  around"*), and here it is a hard fairness requirement: two unseeable threats at once is a coin flip.
- ⚠️ **Never in a chamber with a Still One.** Sparking is *mandatory* to solve the Hollow One and
  *lethal* near a Still One. Textbook double jeopardy.

### B4.4 · The Child (DN's Ghost Girl) — new tiny script

- **Harmless. Always. No exceptions. Zero fail state, ever.**
- Fires on a randomised 45–90 s timer, **only while the candle is out**, and ⚠️ **only when no primary
  entity is present** — DN2's own rule that the game never stacks a fake scare onto a real threat.
  This is the rule that makes the whole scare economy legible.
- Variants: a peek around a doorway that is gone when you look again; a laugh plus a sprint-past
  silhouette leaving a blood smear (`flash_scare(dn_child_smear.png, "child_laugh", 0.5)`); a face in
  the dark 2 m ahead for 0.2 s.
- **Cost: `add_panic(6)`.** Real but small — about a third of the Lab nook scare.
- **Suppressed completely while a candle burns.** This is the candle's *upside*, and it is what makes
  the light/dark choice a genuine dilemma rather than a strict tax.

### B4.5 · The Kneeling Man (DN's Shadow Corpse) — `creature_shapechanger.gd` pattern, `KILL_DIST` removed

- A large crawling shadow in a corridor, moving toward you at 0.8 m/s. Knows where you are.
- **Cannot harm you at all.** Within 2.5 m he simply dissolves and relocates. A candle also dispels
  him. Pure `ScaryObject` gaze panic, `scare_intensity 0.7`. **A nerve tax with no fail state**, whose
  job is to make the *real* threats ambiguous.
- ⭐ **He is the whisperer.** The ambient whispers in this level come from him, positionally. Steal
  DN's phrase list nearly verbatim — and note that two lines are already load-bearing continuity:
  - ***"Look behind you."*** — the exact lie KONTUR's Gate 4 escort already tells. Here a harmless
    ghost says it, which retroactively makes KONTUR's version read as **the same voice**. Free
    narrative cohesion, and very good.
  - *"I wouldn't look in the mirror."* — points at the House and Corridor mirrors.
  - Plus: *"Every room feels alive. I hear it breathing." · "Don't stare at me." · "No one ever leaves
    this place." · "Wake up." · "So scared, so scared, so scared…"*
- Arrives at 6 sconces, **before** the Hollow One's teaching beat — so by the time the real invisible
  threat arrives, the player has already learned that a shape in the dark might be nothing.

### B4.6 · The Weeping Frames (DN's Paintings) — existing `ScaryObject` + `trigger_object.gd`

Already fully built. **Port DN's escalation, because it is the best teaching structure in the source
material**, and here it is driven by the sconce count instead of the night number:

| Sconces | Behaviour |
|---|---|
| **0–2** | Harmless. They hang there. They make no sound. Purely decorative. |
| **3–4** | Within 4 m they emit `frame_weep` (a woman crying) and feed gaze panic at 0.9 via `ScaryObject`. Still not fatal. |
| **5+** | Full `trigger_object.gd` — 3 s of continuous gaze = `Screamer.trigger()`, with the frame visibly igniting as the wind-up. |

> This is a **better** implementation of "a rule's first encounter must be survivable" than the usual
> one, because the teaching encounter is not a softened version of the trap — it is **the identical
> object**, and the player has already learned its silhouette and its position class before it can
> ever kill them. The sound arriving one tier before the danger is the tell arriving before the rule.

⚠️ The ignition tween must keep emission **≤ 0.9** (Issue 21) or it renders as a flat white rectangle.

### B4.7 · Explicitly cut

**Fire Babies** (fire VFX with no glow/bloom renders as flat white rectangles — Issue 21) · **the
Mist** (a chip-your-HP unit is meaningless without an HP pool) · **Dark Skeletons** (they exist to be
killed; "combat-less" is the pillar) · **the Tortured Soul** (see §B11 — the best idea being cut).

---

## B5 · The candle

**Decided with the user: the candle replaces the flashlight.**

At level entry, `player.kill_flashlight()`. F now only clicks. Zero new code — this is already
implemented and already used by the Backrooms noclip — and it is the correct read: *their equipment
does not work down here.*

| Verb | Key | Notes |
|---|---|---|
| **Light / blow** | **F** (`toggle_flashlight`) | Reuse the existing action. Lighting consumes a candle; blowing **banks the remaining time** (see §B11). |
| **Spark** | **C** (new `spark` action) | Free, unlimited, no cooldown. |
| Pick up | **E** | `key_item.gd` pattern. |

**The candle:** `OmniLight3D`, `omni_range 4.5`, `omni_attenuation 2.4`, warm `Color(1.0, 0.78,
0.45)`, `light_energy` tweening **1.0 → 0.35 over 60 s** (DN2's exact duration), then out with
`candle_die` — a distinct, learnable sound, plus a `ScreenText.toast` on the **first burnout only**.
Carry cap **4** (between DN2's 6 and the Remaster's 3). Caches are found in chambers.

**The spark:** a 0.25 s `OmniLight3D` at `range 9.0`, `energy 1.4`, then ⭐ **a 1.2 s dip of ambient
below baseline** — DN's *"after that, it gets darker than before, until your vision is back to
normal."* This after-dip is what makes sparking feel expensive without costing a resource, and it is
why DN players ration a free action.

### The double edge — every entity has a light polarity

| Entity | Candle lit | Spark |
|---|---|---|
| **The Child** | **Suppressed entirely** ✅ | — |
| **Weeping Frames** | Easier to see, therefore easier to avoid ✅ | — |
| **The Matron** | Detects you from **9 m instead of 5 m** ❌ | brief detection bump |
| **The Still Ones** | You can see them ✅ / they advance one step per spark ❌ | **fatal within 2.0 m** ❌❌ |
| **The Hollow One** | **No effect whatsoever** ⚠️ | **The only way to see it** ✅✅ |
| **The Kneeling Man** | Dispelled ✅ | — |

**There is no globally correct posture, and by 6 sconces it inverts** — exactly as in DN, where the
wiki ends up advising *"don't use candles at all."* **The player who learns "candle good" in the first
five minutes must unlearn it in the last five. That is the level's arc.**

---

## B6 · Procedural layout via `RoomBuilder`

`RoomBuilder` imposes hard constraints: rooms must **abut, never overlap**; wall dedup is by
**interval** per (axis, plane, height); doorways open **every** wall on their plane; floors
auto-bridge. A naive random-rectangle generator violates all of these and would reproduce Issues
19/20/23 at scale.

**The fix is to generate on a lattice — which is also exactly what DN does** (its rooms are literally
"2×2", "2×3", "3×2").

### `dungeon_gen.gd` — pure data, no scene dependency

```
CELL = 3.0 m              # one corridor width — DN's "hallway"
GRID = 18 x 18 cells      # ~54 x 54 m envelope
```

**Step 1 — place chambers.** Draw `K = 9` chambers, each `randi_range(2,3) × randi_range(2,4)` cells.
Reject any placement within **1 cell** of an already-placed chamber (the gap guarantees a corridor can
run between them, and guarantees `RoomBuilder`'s no-overlap rule). Reject placements touching the
border. ~40 rejection-sampling attempts per chamber, then give up and ship `K-1` — **never loop
forever.**

**Step 2 — connect.** Complete graph on chamber centres weighted by Manhattan distance → **minimum
spanning tree** (guarantees connectivity) → **add `ceil(0.25 * K)` extra edges** from the shortest
non-tree edges.

> ⚠️ **The extra edges are NOT optional.** A spanning tree is a *perfect maze*, and in a perfect maze
> a pursuer that follows corridors is unbeatable — every corridor is a dead end with extra steps. This
> project has already learned this exact lesson: `maze_chase_ui.gd`'s BFS monster became a 12-in-40
> instant death the moment it started following actual corridors, and `_place_monster()` had to be
> taught to avoid the roadblock cell. **A level with a chaser must have cycles.** DN's dungeons are
> loopy for precisely this reason, which is why closing a door on Mary and walking around the block
> works.

**Step 3 — carve corridors.** For each edge, carve an L-shaped Manhattan path between chamber edges,
random elbow order per edge. Mark cells `CORRIDOR`, skipping cells already `CHAMBER`.

**Step 4 — coalesce corridor cells into rooms.** Walk the corridor cells and merge each **maximal
straight run** into one `RoomBuilder` room, **splitting at every turn and every junction.** This keeps
the room count sane and — more importantly — stops you emitting a wall plane at every 3 m cell
boundary, which is the Issue-23 coincident-wall bug waiting to happen. Expect ~14–22 corridor rooms +
9 chambers = **23–31 rooms**, comparable to KONTUR's 13 and the Breach's 13.

**Step 5 — emit doorways.** For every pair of adjacent rooms, one doorway at the shared-edge midpoint,
`width = 2.2`, `dir` = the axis you walk through. Chamber↔corridor doorways get a `SlamDoor`;
corridor↔corridor turns get none.

**Step 6 — heights and skins.** `h = 3.2` for chambers, `h = 2.6` for corridors, via the per-room `h`
key. **The height change alone makes chambers feel like rooms**, and it is far cheaper than props.
Skins via the per-room `wall_mat`/`floor_mat`/`ceil_mat` overrides — `kontur.gd:_rooms_with_skins()`.

**Step 7 — place content.**
- **Spawn chamber:** the one with the highest total BFS distance to all others.
- **The seven sconces:** seven *different* chambers, one per chamber, on a wall **without a doorway**.
  ⚠️ `wall_point()` returns the wall *centre*, which is exactly where a doorway sits — a sconce
  collider there silently seals the room. **The generator must consult its own doorway list before
  choosing a wall.** This is a documented recurrence (the Records warning sign sealed a breaker room).
- **The bed:** the chamber with the greatest BFS distance from the spawn chamber. Hidden until 7/7.
- **Still Ones:** chambers ≥ 2×3 cells only.
- **Weeping Frames:** chamber walls without doorways only. Same warning as the sconces.
- **Candle caches:** chambers only, 4 caches of 1 candle each.
- **The Hollow One's teaching chamber:** a sealed alcove off a corridor at roughly the 6-sconce point
  of the expected route, with a grate the player can see through but not pass.

**Step 8 — sightline pass.** ⭐ For each chamber, if two doorways are collinear and directly opposite,
**nudge one by one cell.** Also cap straight corridor runs at 4 cells (12 m) by inserting a jog.
**This is the entire trick behind DN's claustrophobia and it costs one loop.**

---

## B7 · Darkness without fog

Our engine has **no glow, no fog, no SSAO, Linear tonemap**, and emission > 1.0 clamps to flat white.
DN1 uses fog, and its fog does **three separable jobs**. Each has a fog-free substitute:

1. **"You cannot see the far wall."** → **Light radius, not fog.** The carried candle at
   `omni_range 4.5` with steep `omni_attenuation`, plus `Environment.background = COLOR` set to **pure
   black** and ambient ~0.02 (the `_boost_ambient()` per-scene pattern, inverted — *lower* it here).
   Beyond the radius there is literally no light, so unlit geometry renders black. **That is fog, for
   free, and it is physically motivated.**
2. **"Silhouettes at the edge of visibility."** → **Geometry occlusion.** DN's chamber/hallway lattice
   means you almost never have a sightline longer than one room. Step 8 preserves that. **This is the
   real reason DN feels claustrophobic**, and it costs nothing to render.
3. **"Depth cue / atmospheric perspective."** → **Dark albedo.** At ~0.45 light energy, albedo
   contributes far less than emission (Issue 21), so a wall texture at value ≤ 0.30 falls off to black
   inside the light radius on its own.

⚠️ **Do not add a depth-fade `ColorRect` shader.** That is fog by another name; it is outside the
project's rendering contract and would fight `PanicHUD`'s `BlurRect`/`TintRect` stack. Use the
existing `Vignette.spawn()` at ~2.2 instead — a legitimate non-fog framing device.
*(Note: `vignette.gd` is currently a no-op — see `SCARY.md` §2.11 #3. Fix it first.)*

**This level is also the venue for the flagged fog EXPERIMENT** (`SCARY.md` §4.3): it is the only
level with no legacy emission tuning to break. Try `Environment.fog_enabled` here, measure, report,
and only then discuss retrofitting. **The level must be fully playable and correct without it.**

---

## B8 · Panic economy — the full ledger

| Source | Rate / amount | Notes |
|---|---|---|
| **Sprint** | **+6/s**, decay suppressed | **Unchanged from every other level.** Never required. Also **deafens you** — masks the Matron's footsteps and the Hollow One's knock. |
| Gaze at a Still One | 0.6 × 20 = **12/s** | Existing `CreatureStalker`. Stare-off costs ~48 — a real, nerve-demanding option. |
| Gaze at a Weeping Frame | 0 → **18/s** → fatal at 3 s | Tiered by sconce count (§B4.6). |
| Gaze at the Kneeling Man | 0.7 → **14/s** | Harmless otherwise. |
| The Child | **+6** per appearance | Harmless. Candle-suppressed. Never while a primary is present. |
| **Silence (Matron present)** | **decay → 0, additive → 0** | The signature mechanic. Costs nothing; prevents recovery. |
| Sconce `CalmZone` (×7, cumulative) | decay **×2.5** | The reward loop. The level gets physically safer. |
| The cot (Antechamber) | decay **×2.5** | Before and after. |
| `SlamDoor` battering | **+4** one-shot per door | It's working, it's terrifying, it should cost a little. |
| Candle burnout in the open | **+5** | Only if no primary is present and you are > 8 m from a lit sconce. The gut-drop as the light dies. |
| `Beartrap` | 15 + escape QTE | 2, corridors only. ⚠️ **Never in a corridor adjacent to a Matron spawn chamber** — a limp during a chase is the double-jeopardy shape. |

### ⚠️ Do NOT register `RandomAmbient` in this level

**The most important implementation note in this document.** `RandomAmbient` is global, fires every
18–35 s, plays `floor_creak` / `painting_fall` / `half_scream` at a random point **within 4 m of the
player** (with no LOS check), and adds **5 / 8 / 12** panic. In every other level that is atmosphere.

**Here it would destroy the level.** This level's entire skill expression is *"distinguish a real
positional audio tell from ambience."* A random `half_scream` 4 m away is indistinguishable from the
Matron; a random `floor_creak` is indistinguishable from the Hollow One's knock. The level supplies
its own **diegetic, positional, meaningful** ambient events.

Every level calls `RandomAmbient.register_player(self)` explicitly, so **opting out is a no-op
omission** — no engine change needed. Just don't call it.

### ⚠️ Do NOT add an `ApparitionDirector`

`RANDOM_APPARITIONS` stays false. A HOLD apparition that kills you for fleeing, dropped into a level
containing a slow pursuer you are supposed to *walk away from*, is a contradiction the player cannot
resolve.

---

## B9 · Fairness and teaching beats

| Rule | Taught where | Taught how |
|---|---|---|
| **Still Ones move when unwatched** | First chamber | One placed dead ahead of the spawn, in the brazier light, at 7 m. It is a **guaranteed dud** — walk up and it falls over with a crash. Free scare, and you have now learned the silhouette *and* that they can be inert. The second one in the level is real. (`CreatureA` in the Void, plus DN's own fall mechanic.) |
| **Sparking near a Still One kills you** | Scripted, on first lit candle | `ScreenText.caption("THE LIGHT WAKES THEM. NOT IN THE ROOMS.")`, plus the Lab morgue hint note. ⚠️ **Nothing in the first two sconces can actually kill you this way** — those Still Ones are all duds or dormant. **The rule is stated before it has teeth.** |
| **Frames kill** | The 0–2 / 3–4 / 5+ escalation | §B4.6. The best teaching beat in the design. |
| **Silence = something is here** | Matron's first spawn, scripted | The duck fires while the player is inside a lit sconce's `CalmZone`, with `ScreenText.scrawl("IT'S QUIET.")` — **once, ever.** The Corridor hint plate covers players who explored. |
| **Doors buy time** | Matron's first spawn | Her first spawn is deliberately placed **beyond a `SlamDoor` on the only route to her**, and a toast on first proximity says *"E — SHUT IT."* The battering sound then teaches itself. |
| **The Hollow One** | 6 sconces, fully scripted, zero risk | The sealed side-chamber demonstration (§B4.3). |
| **Candle ≠ safety** | Protocol note in the Antechamber | *"Trial 7c: the subject reports a fourth presence. The subject reports the candle does not help. We have instructed the subject to strike a spark and stand still. Compliance rate: 1 in 9."* |
| **Sprinting deafens you** | Antechamber wall scrawl | *"YOU CANNOT HEAR IT OVER YOURSELF."* |

---

## B10 · Hard constraints — the code-review checklist

Every one of these must hold. They are the double-jeopardy audit for this level.

- ⚠️ **No `DarkZone`, anywhere, for any reason.** The premise is that light is scarce and sometimes
  *wrong*; a `DarkZone` charges +3/s for having the light off and suppresses decay. That is a tax on
  the exact posture the level is built around — Issue 18, verbatim, and the same mistake the Lab dark
  wing and KONTUR Gate 7 both correctly avoid. **The darkness here is the medium, not the penalty.**
- ⚠️ **No standstill panic.** Never call `enable_standstill_panic()`. The Hollow One's solution
  *requires* standing still to listen.
- ⚠️ **No `DreadZone`.** The silence uses decay-suppression only (`set_no_decay`), with zero additive
  rate.
- ⚠️ **No `RandomAmbient`** (§B8).
- ⚠️ **No `ApparitionDirector`** (§B8).
- ⚠️ **No time limit.** DN's Nights 4–5 have one; a clock forces sprinting, sprinting taxes panic, so a
  clock is a panic tax on a mechanic the player cannot avoid.
- ⚠️ **The Hollow One never coexists with the Matron**, and **never shares a chamber with a Still
  One** (sparking is mandatory for one and lethal near the other).
- ⚠️ **No beartrap in a corridor adjacent to a Matron spawn chamber.**
- ⚠️ **The Antechamber, the bed chamber, and every lit-sconce chamber contain no entity of any kind.**
- ⚠️ **The heartbeat must route to the un-duckable `Body` bus** or the silence mechanic does not work.
- ⚠️ **Sconces and Frames must not be placed on a wall carrying a doorway** (§B6 step 7).
- ⚠️ **Cycles in the generator are mandatory** (§B6 step 2).

---

## B11 · What to drop from Dungeon Nightmares

| Drop | Why |
|---|---|
| **Permadeath, and DN2's 50/50 death door** | This game already restarts the level, which is harsher than DN2's coin flip and *more coherent*. A literal coin flip on whether your run ends is the exact unfairness the project rejects everywhere else — and the "death demotes you" idea is already owned, better executed, by KONTUR's banishment. |
| **The map / GPS minimap** | Issue 34 in the flesh — the deleted breaker-proximity bar, which *"solved the wing outright"* and *"masked the fact that the real tell was a stub."* A trail-drawing minimap solves this level's navigation outright. If navigation proves too hard, use positional audio beacons (the Lab's far-cue/near-confirm pattern) instead. |
| **The health pool, regeneration, and blood vignette** | One resource: panic. A second resource that also gates death would make every entity's damage number meaningless and fork the fail path. **All contact stays instant-fatal** — project convention across eight levels. |
| **The stamina bar** | Sprint panic already *is* the stamina system, and it is better because it is the same currency as everything else. |
| **The 10-minute time limit** | §B10. |
| **"Blowing a candle wastes it entirely"** | An unteachable gotcha — the punishment is silent, invisible, and arrives much later. **Let blowing it out bank the remaining seconds.** The cost of relighting is the 1.2 s spark-dip and the noise, not a deleted resource. |
| **Fire Babies** | Fire VFX in a renderer with no glow/bloom and emission clamping above 1.0 will look like white rectangles crawling at you (Issue 21). |
| **The Mist / Flying Skull** | It exists to chip an HP bar we don't have. ⭐ Its one great idea — *red light spilling around a corner as a visible tell* — should be **salvaged and given to the Matron instead**. |
| **Dark Skeletons** | Killable enemies. "Combat-less gameplay" is the pillar of both DN games *and* of this project; the wiki itself notes these *"somewhat negate KMonkey's statement."* |
| **Gold bars / score / % collected screens** | No scoring in this game. |
| **Seven nights, and the mobile "infinite nights"** | One packed night is the user's decision (§B3). Seven would be a game. |
| **The trap zoo** (guillotines, cogs, fans, blood pools, chewing doors, swinging axes, spike floors) | `Beartrap` already exists and is a better-built version of the only one that matters. ⭐ **One exception worth stealing post-v1: DN's Spinning Cog masks Mary's footsteps.** A brilliant anti-tell — but it must be **off the mandatory route** and never adjacent to a Hollow One chamber, or it is double jeopardy on the exact sense the level demands. |
| **The Tortured Soul** | ⭐ **The best idea being cut.** Her mechanic — lighting a candle makes her invisible but she keeps following, faster, and reappears in your face when it burns out — is the most creatively cruel idea in DN2 and maps beautifully onto a candle system. **But** it punishes the player for using the resource the level hands them, with a delayed consequence arriving up to 60 s later at an unpredictable location. That is **un-teachable**: the first encounter cannot be made both survivable *and* legible, because the whole point is that cause and effect are 60 seconds apart. **Revisit later** with a permanent, audible, positional hum that keeps playing while she is invisible — that fixes the fairness and only slightly dulls the trick. |
| **DN2's hub hotel with per-night story rooms** | The sequel's *best* structural feature, and a whole level's worth of hand-built content. **The Antechamber is the 5 % of it that earns 80 % of the feeling.** Don't build the hotel. |
| **A depth-fade "fog" shader** | §B7. |

---

## B12 · Assets

Conventions: textures at `game/assets/textures/level_9_dungeon/` with a level-name prefix; audio at
`game/assets/audio/level_9_dungeon/` generated by a seeded stdlib-only `tools/make_sfx_dungeon.py`
emitting 16-bit mono 44.1 kHz WAV. Register every texture in `TEXTURES.md`
(`file_name | texture_description | where_used | status`). ⚠️ Every nano-banana output needs the
`sips` PNG re-encode; RGBA cutouts need **real** alpha (see `SCARY.md` §7.1).

### Textures — SOURCED (PolyHaven / AmbientCG, CC0). Do not generate these.

| File | Note |
|---|---|
| `dungeon_wall_stone.png` | Damp grey castle stone block, tileable, **desaturated, value ≤ 0.30** |
| `dungeon_wall_brick.png` | Old brown brick, mossy mortar, tileable, value ≤ 0.30 |
| `dungeon_wall_ash.png` | Charred / blood-slicked masonry, tileable, value ≤ 0.25 |
| `dungeon_floor.png` | Worn flagstone, wet patches, tileable |
| `dungeon_ceiling.png` | Rough vaulted stone, tileable, darker than the walls |
| `dungeon_door.png` | Heavy banded oak, front elevation, iron studs |
| `dungeon_pillar.png` | Rough stone column, vertically tileable |
| `dungeon_grate.png` | Rusted iron grating — the Hollow One's teaching chamber |

⚠️ `RoomBuilder.make_material()` **negates V itself** — pass a *positive* `uv1_scale.y` (Issue 19).

### Textures — GENERATED (nano-banana-pro)

Every prompt carries: *flat orthographic elevation, filling the frame, evenly lit, no cast shadows,
no perspective, no background around the object, NO glow, NO bloom, NO rim light.*

| File | Prompt |
|---|---|
| `painting_matron.png` | *"Antique oil portrait in a cracked gilt frame: a gaunt burned woman with an unnaturally elongated neck, eyes closed, dried blood running from the frame's lower edge onto the canvas, cracked varnish. Front elevation, flat even lighting, no background — the canvas fills the image."* |
| `painting_matron_open.png` | *"The same antique burned-woman portrait, but the eyes are now wide open and bloodshot, whites yellowed, staring directly out of the frame; canvas edges beginning to blacken and smoulder. Front elevation, flat lighting."* — the 5-sconce kill-state swap |
| `painting_witness.png` | *"Antique oil portrait, half-human half-skeleton figure in an explorer's coat, one side of the face flesh and one side bare skull, cracked gilt frame. Front elevation, flat lighting."* |
| `dn_stillone_face.png` | *"Extreme close-up horror jumpscare: a fleshless skull with strips of dried grey skin still attached, jaw hanging open, empty sockets, harsh single-source underlighting, black background."* — `flash_scare` payload |
| `dn_hollow_figure.png` | *"Silhouette of a small child rendered as pure black shadow with two tiny points of dull red light where the eyes would be, standing still, full body. **Transparent background, clean alpha cutout**, no ground, no shadow."* ⚠️ **must be real RGBA** |
| `dn_child_smear.png` | *"Wet handprint and drag smear of blood across a pane of glass, seen from behind the glass. **Transparent background**, high contrast, red on nothing."* |
| `dn_sconce.png` | *"Wrought-iron wall sconce with a shallow oil cup, bolted to stone, unlit, heavy soot staining above it. Front elevation, flat matte, no background."* — plus `dn_sconce_lit.png` |
| `dn_cot.png` | *"Institutional iron-frame camp cot with a thin stained mattress and a grey wool blanket thrown back, seen from above. Worn canvas, rust on the frame, no background."* |
| `dn_note.png` | *"Aged handwritten diary page, brown ink, water-stained and torn at one edge, on a dark surface. Front elevation."* |
| `dn_tally_wall.png` | *"Deep scratch-mark tally strokes gouged into damp stone, close crop. **Transparent background.**"* |
| `screamer_dungeon.png` | *"Extreme close-up jumpscare of a charred screaming woman's face lunging out of pitch black: blistered skin, bloodshot eyes wide, mouth open mid-shriek, single harsh underlight."* — `LEVEL_SCREAMERS[9]` |

⚠️ `screamer_dungeon.png` lives in `level_9_dungeon/`, **not** in `screamers/` — that folder is
auto-scanned as the random fallback pool for intro and ending only (the `screamer_hotel.png`
precedent).

### Audio — `tools/make_sfx_dungeon.py`

New stdlib-only script structured exactly like `tools/make_sfx_level6.py`: module docstring listing
every file and its purpose, `random.seed(701)`, `OUT_DIR` computed from `__file__`, reproducible.
⚠️ **Base names must be globally unique** (`GameState.load_audio()` resolves across every subdir).

| File | Synthesis sketch |
|---|---|
| `ambient_dungeon.wav` | **Seamless loop — the file the whole level ducks.** Filtered pink-noise wind, a slow 0.08 Hz amplitude drift, plus a barely-audible 44 Hz drone. Deliberately **featureless** — its job is to be *missed*, not heard. |
| `matron_theme.wav` | Seamless loop. Screeching metallic partials — an inharmonic bell struck at 0.7 Hz through a resonant band-pass sweeping 900–2400 Hz. Ugly on purpose. The level drives `volume_db` from her distance. |
| `matron_step.wav` | Damped low thud + dry cloth rustle. Pitch-randomise ±8 % per play. |
| `matron_shriek.wav` | The spot-you sting: a formant-swept scream burst, 0.9 s, hard attack. |
| ⭐ `hollow_knock.wav` | **The most important file in the level.** A low, dry, *quiet* knuckle-on-wood knock at ~70 Hz fundamental, very short body, −12 dB, irregular spacing. **Must be genuinely confusable with a settling door.** Get this wrong and the finale is unfair. |
| `hollow_reveal.wav` | Sub-bass swell, 0.3 s, on the spark reveal. |
| `bone_scrape.wav` | Seamless loop. Filtered noise with a comb filter at 180 Hz, amplitude-gated at ~1.4 Hz — a dry wooden drag. DN's skeleton tell, and the fairness upgrade. |
| `skeleton_fall.wav` | 9 short pitched wood-block impacts scattered over 0.6 s with a decaying envelope. |
| `candle_light.wav` | Match strike: noise burst through a rising band-pass, then a soft flame whoosh. |
| `candle_blow.wav` | Short breath of filtered noise, 0.35 s. |
| ⭐ `candle_die.wav` | **Must be instantly learnable.** A tiny sputter, then a distinct 0.2 s descending sine sigh. The player has to know from across a room that they just went dark. |
| `spark_flint.wav` | Sharp 30 ms crackle burst, band-passed 2–6 kHz. |
| `sconce_light.wav` | A deep whoomph of oil catching, 1.4 s, with a warm crackle tail. **The level's reward sound.** |
| `child_laugh.wav` | A short girl's laugh — noise-excited formants. If that reads as cheap, a candidate for a sourced CC0 clip. |
| `child_peek.wav` | Very short high string glissando, 0.4 s. |
| `frame_weep.wav` | Seamless loop. Low sobbing — an amplitude-modulated formant pair around 300/900 Hz, breathy. `unit_size 4`. |
| `frame_ignite.wav` | Whoosh + crackle, 1.2 s, for the 5-sconce kill wind-up. |
| `whisper_dungeon.wav` | A **bank** of short whispered lines (§B4.5). Procedural whisper = noise through swept vowel formants; intelligibility is not required and is arguably worse — **except** *"Look behind you"* and *"Wake up"*, which should be intelligible and are worth sourcing. |
| `cot_sleep.wav` | Long breath out + a low descending drone, 2.5 s, under the fade-to-black. |
| `screamer_dungeon.wav` | `LEVEL_SCREAMERS[9]` fatal sting — 3.5 s, so the tail rings past the image (the nook-scare precedent). |

**Reused, no new files:** `heartbeat` (shared — ⚠️ must route **off** the `"Dungeon"` bus),
`footstep` (shared), `door_batter` / `door_break` / `blast_door_slam` (from `level_6_breach/`, reached
via `GameState.load_audio()`'s subdir scan — the trick the Breach already uses for KONTUR's
`acid_hiss`), `beartrap_snap`, `pipe_groan` (shared — DN's steam-pipe stinger, already written).

After generating: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import`.
⚠️ Loop flags must be set in the `.import` files for `ambient_dungeon`, `matron_theme`, `bone_scrape`
and `frame_weep` — or restart them via `finished → play`, as `level_1.gd` does for `nook_breath`,
since every `.wav.import` in this project defaults to `loop_mode=0`.

---

## B13 · Files touched

**New**
`game/scenes/level_9_dungeon.tscn` (minimal: root + Environment + AmbientPlayer + Player + HUDCanvas)
· `game/scripts/level_9_dungeon.gd` · `game/scripts/dungeon_gen.gd` · `game/scripts/creature_hollow.gd`
· `game/scripts/dn_child.gd` · `game/scripts/candle.gd` · `game/scripts/wall_sconce.gd` ·
`tools/make_sfx_dungeon.py` · `game/tests/check_dungeon_gen.gd` · `game/tests/walk_dungeon.gd` ·
`game/tests/screenshot_dungeon.gd`

**Modified**
`game_state.gd` (the `current_level` map, `SCENE_LEVEL_9`, the `AUDIO_SUBDIRS` list, a
`level_progress` row) · `screamer.gd` (`LEVEL_SCREAMERS[9]`) · `project.godot` (`spark` on **C**) ·
`player.gd` (`set_no_decay(bool)` ~6 lines; a `spark()` hook; the sprint-deafens duck) ·
`creature_object12.gd` (`@export` the speed/spawn constants so the Matron retunes without forking) ·
`creature_stalker.gd` (the `bone_scrape` loop, the dud-fall state, the spark reaction — **all
additive, all `@export`ed and defaulting to off**, so the Void is untouched) · `TEXTURES.md` ·
`CLAUDE.md` · `tools/run_tests.sh`

⚠️ **The renumbering is the real cost.** Inserting at 9 shifts the Void and the ending, and it touches
`GameState`, `Screamer.LEVEL_SCREAMERS`, the `level_progress` table, `level_3.gd`'s `current_level`
assignment, and the back-door chain. It is mechanical, but it is the kind of change where one missed
constant produces the wrong screamer image in the wrong level for a month. **Do it in one commit**,
with `tests/check_level_resume.gd` extended to assert the full chain in both directions. See
`SCARY.md` §9 step 19 — the three other new levels shift things too, so do all the renumbering at
once.

---

## B14 · Verification

Following the project's own testing conventions (`check_*` assert, `walk_*` drive a body,
`screenshot_*` need a render target so they run **without** `--headless`).

- **`tests/check_dungeon_gen.gd`** — 200 seeds, pure data, no scene. Asserts: all chambers reachable
  by BFS; chamber count in range; no two rooms overlap; every doorway lies on a genuinely shared edge;
  the seven sconces are in seven distinct chambers; the bed is above the distance floor from spawn;
  **at least one cycle exists**; no sconce or frame is on a wall carrying a doorway.
  Modelled on `check_maze_gen.gd`, which exists precisely because *"the minigame is only ever opened
  via player interaction, so a normal scene smoke test never exercises `_generate_maze()` at all."*
  **Same trap here.**
- **`tests/check_wall_overlap.gd`** on the built scene, for 5 fixed seeds. **Non-negotiable** — a
  procedural generator that *can* emit coplanar faces eventually *will*, and the bug is
  camera-dependent, so screenshots will not catch it.
- **`tests/walk_dungeon.gd`** — drive a `CharacterBody3D` from spawn to all seven sconces to the bed
  under gravity, over 20 seeds, asserting every objective is physically reachable. The
  `walk_lab_wing.gd` / `walk_cellar.gd` pattern, and the only thing that will catch a `SlamDoor`
  collider spawning inside a jamb or a chamber sealed by its own sconce.
- **`tests/screenshot_dungeon.gd`** (no `--headless`) — poll for the Hollow One's silhouette alpha and
  photograph the spark reveal. **A frame counter cannot catch a 0.30 s window** (the
  `screenshot_nook_scare.gd` precedent).
- ⚠️ **`--import` is not optional** after adding a `class_name` or an asset. Godot caches class names,
  and until it rescans a new `class_name` is "not declared in the current scope" — which makes the
  level script fail to **parse**, which makes tests find nothing and **report PASS**.

---

## B15 · The one-paragraph pitch

> You are put to sleep. There is no light down here but a candle that burns for sixty seconds, and
> you have four. The dungeon rearranges itself every time, so there is nothing to memorise and nothing
> to trust except your ears — which is fine, because the only thing you actually need to hear is the
> moment the wind stops. That is when something else is in here with you. It walks slower than you do.
> You will never have to run from it, and if you do run you will not hear the next one coming. Seven
> sconces, and each one you light makes the dark a little smaller and the dungeon a little more
> awake. By the sixth they have taken the wind away for good and given you something you cannot see
> at all, and the only way to find out where it is standing is to stop walking, hold still in the
> dark, and strike a spark.

---

## Sources

Primary technical source — the Fandom wiki (see §A13 on why, and how to fetch it):
[The Basics (DN1)](https://dungeon-nightmares-ultra.fandom.com/wiki/The_Basics_(DN1)) ·
[The Basics (DN2)](https://dungeon-nightmares-ultra.fandom.com/wiki/The_Basics) ·
[Tips and Strategies (DN1)](https://dungeon-nightmares-ultra.fandom.com/wiki/Tips_and_Strategies_(DN1)) ·
[Tips and Strategies (DN2)](https://dungeon-nightmares-ultra.fandom.com/wiki/Tips_and_Strategies) ·
[Story / Nights Guide](https://dungeon-nightmares-ultra.fandom.com/wiki/Story_/_Nights_Guide) ·
[Nights / Levels (DN1)](https://dungeon-nightmares-ultra.fandom.com/wiki/Nights_/_Levels_(DN1)) ·
[Mary (DN1)](https://dungeon-nightmares-ultra.fandom.com/wiki/Mary_(DN1)) ·
[Mary (DN2)](https://dungeon-nightmares-ultra.fandom.com/wiki/Mary_(DN2)) ·
[Ghost / Asmodeus](https://dungeon-nightmares-ultra.fandom.com/wiki/Ghost) ·
[Mist](https://dungeon-nightmares-ultra.fandom.com/wiki/Mist) ·
[Shadow Corpse](https://dungeon-nightmares-ultra.fandom.com/wiki/Shadow_Corpse) ·
[Skeletons (DN1)](https://dungeon-nightmares-ultra.fandom.com/wiki/Skeletons_(DN1)) ·
[Skeletons (DN2)](https://dungeon-nightmares-ultra.fandom.com/wiki/Skeletons_(DN2)) ·
[Dark Skeletons](https://dungeon-nightmares-ultra.fandom.com/wiki/Dark_Skeletons) ·
[Ghost Girl](https://dungeon-nightmares-ultra.fandom.com/wiki/Ghost_Girl) ·
[Tortured Soul](https://dungeon-nightmares-ultra.fandom.com/wiki/Tortured_Soul) ·
[Fire Babies](https://dungeon-nightmares-ultra.fandom.com/wiki/Fire_Babies) ·
[Candles (DN2)](https://dungeon-nightmares-ultra.fandom.com/wiki/Candles_(DN2)) ·
[Paintings and Pictures](https://dungeon-nightmares-ultra.fandom.com/wiki/Paintings_and_Pictures) ·
[Traps](https://dungeon-nightmares-ultra.fandom.com/wiki/Traps) ·
[Jumpscares and Hallucinations (DN1)](https://dungeon-nightmares-ultra.fandom.com/wiki/Jumpscares_and_Hallucinations_(DN1)) ·
[Jumpscares & Hallucinations (DN2)](https://dungeon-nightmares-ultra.fandom.com/wiki/Jumpscares_%26_Hallucinations_(DN2)) ·
[Notes (DN1) — all 28 diary entries](https://dungeon-nightmares-ultra.fandom.com/wiki/Notes_(DN1)) ·
[Optional Newspapers](https://dungeon-nightmares-ultra.fandom.com/wiki/Optional_Newspapers) ·
[Bugs & Glitches](https://dungeon-nightmares-ultra.fandom.com/wiki/Bugs_%26_Glitches) ·
[KMonkey / Joey To](https://dungeon-nightmares-ultra.fandom.com/wiki/KMonkey)

Official and press:
[kmonkeygames.com — Dungeon Nightmares](https://kmonkeygames.com/games/dungeon-nightmares/) ·
[kmonkeygames.com — DN2](http://kmonkeygames.com/games/dungeon-nightmares-ii-the-memory/) ·
[itch.io — DN1](https://kmonkey.itch.io/dungeon-nightmares) ·
[itch.io — DN2](https://kmonkey.itch.io/dungeon-nightmares-ii) ·
[JayIsGames review](https://jayisgames.com/review/dungeon-nightmares.php) ·
[Digitally Downloaded — DN 1+2 Collection review](https://www.digitallydownloaded.net/2021/01/review-dungeon-nightmares-1-2.html) ·
[148Apps review](https://www.148apps.com/dungeon-nightmares/dungeon-nightmares-review/) ·
[Steam — DN2 walkthrough](https://steamcommunity.com/sharedfiles/filedetails/?id=517732684)

Open-source search (negative — see §A13):
[Linc7991/DungeonNightmares](https://github.com/Linc7991/DungeonNightmares) (unrelated) ·
[TonimatasDEV-Storage/NightmaresBite](https://github.com/TonimatasDEV-Storage/NightmaresBite) (unrelated).
Generator reference class only: [vazgriz/DungeonGenerator](https://github.com/vazgriz/DungeonGenerator) ·
[SolAnna7/TaurusDungeonGenerator](https://github.com/SolAnna7/TaurusDungeonGenerator) ·
[damarindra/Unity-Dungeon-Generator](https://github.com/damarindra/Unity-Dungeon-Generator)

In-repo: `SCARY.md` · `CLAUDE.md` · `ISSUES_SOLUTIONS.md` (Issues 18, 19, 20, 21, 23, 24, 25, 34, 35) ·
`COMMENTS.md` · `TEXTURES.md`
