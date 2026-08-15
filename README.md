# Let's vibe code a video game

A 3D first-person atmospheric horror game built in Godot 4. You are **Subject 47**. This is a psychological experiment. Stay calm.

## Premise

You wake in a dark room. A note on the table tells you that you are part of an experiment — and that the entity you may encounter is a product of your own mind. Eight levels stand between you and the truth. Touch the wrong things and the experiment ends badly.

## Design pillar — escalating unreality

**The game starts with something ordinary and human, and gets further from reality the deeper the
player goes.** Every level should be stranger and more frightening than the one before it: a lit room
with a table and a candle → an institutional lab → a house → a hotel corridor → impossible space → a
sealed Soviet facility → a containment breach with something hunting you → a dream you cannot
wake from → broken geometry → a loop back to where you began. Locations, rules, and the player's own
senses all degrade along that curve.

This is a hard constraint on new content, not a mood note. A new level must know where it sits on the
curve, and it must be weirder than its predecessor. See `SCARY.md` §6 for the full ordering (and for
the one place the curve is currently flagged as broken).

## Gameplay

- **First-person exploration** — walk through 8 escalating environments
- **Trigger objects** — specific objects are traps. Interact with them (press E) or stare for 3 continuous seconds → screamer → level restarts
- **Trap notes (read-to-die)** — trap notes open like any other note, but panic climbs fast while the page is open and the text bleeds red. Close it in time and you escape shaken; read to the end and the screamer takes you
- **Panic system** — staring at any object tagged as `ScaryObject` fills a panic bar. The bar rises **~5.7× faster than it falls** (20/s while staring, 3.5/s decay), so fear accumulates far faster than it clears. Hit the limit → screamer. Visual feedback: blur + red-tint overlay. Audio feedback: heartbeat whose pitch and volume rise with panic
- **Sprint at a cost** — Shift runs ×1.6 faster but feeds panic ~6/s and blocks recovery. The corridor's note warns you: *Walk. Do not run.* It means it
- **Flashlight with a battery** — toggle with **F**. Each level's charge lasts ~4 minutes of ON time; the bulb stutters as a warning, then dies for the rest of the level. It's on by default — manage it or lose it in the dark stretches
- **Scripted scares** (Levels 2–3) — one-shot events spike panic directly: door slams, footsteps overhead, lights dying as you enter a room; darkness makes panic creep unless the flashlight is on; torchlight calms it 2.5× faster; beartraps snap, hurt and slow you; the corridor's final stretch is a dread zone where panic barely drains
- **Survivable jump-scares** — some scares flash and shock but don't kill: press up to the House window and a moonlit **forest** lunges (`screamer_forest`); a hotel **Manager** strikes once mid-corridor; the corridor's **turn mirrors** show a creature when you miss a corner. Each spikes panic but lets you recover — only the bar filling is fatal
- **The apparition** (the Lab, the House, the Corridor, KONTUR and the flooded Backrooms) — a pale figure that materialises ahead of you at a randomised moment. **Hold your nerve**: keep walking and it fades; *sprint* and it rushes you → screamer. The first encounter (the Lab) is survivable so you learn the tell before it can kill
- **Stalking creatures** (Level 8 — The Void) — tall red-eyed figures that freeze while you watch them and advance the instant you look away (Weeping-Angel logic). Let one reach you and it lunges → screamer. Staring also feeds panic, so you can't just watch one forever
- **Notes** — find and read notes to collect clues, codes, and keycards needed to unlock each exit door
- **Combination lock** — Level 2's exit needs a 3-digit code from the safe notes. Every wrong guess buzzes and spikes panic: brute-forcing the lock is itself a way to die
- **KONTUR's cross-level gates** (Level 5) — this level's answers aren't inside it. Each of its eight gates was hinted somewhere earlier: a note in the Lab, a TV test card in the House, a door plate in the Corridor, a phone in the Backrooms. A player who explored reads straight through; one who rushed is guessing, and guesses here cost panic that never drains
- **A pursuer you cannot fight** (Level 6 — The Breach) — Object 12 roams the whole wing on a five-state hunt. It is faster than your walk and slower than your sprint, so escaping always costs panic. Your torch blinds it only while it is actually chasing you, doors bought you seconds, lockers hide you — and the only permanent answer is luring it into the incinerator and sealing the door
- **A level you win by standing still** (Level 7 — The Nightmare) — the flashlight is gone; you carry four candles that burn sixty seconds each. Light seven sconces in the dark and the way out appears. Sprinting deafens you to the one thing that would have told you where the danger was, and the flagship horror is invisible unless you strike a spark
- **The map minigame** (Level 2) — the cellar key is behind a hand-drawn maze you drag your marker through while something hunts you along the actual corridors. A different maze every attempt, with loops you can use to slip past, two pursuers and snares that hold you where you stand
- **Back doors** — each level has a back door (blood-red glow) that returns you to the previous level. Collected items (keycard, code) are cleared on re-entry
- **No combat** — horror through atmosphere, sound, lighting, and restraint

## Controls

| Key | Action |
|-----|--------|
| WASD | Move |
| Mouse | Look |
| Shift | Sprint (×1.6 speed — builds panic while held) |
| E | Interact (notes, doors, keycard, lock) |
| F | Toggle flashlight (battery: ~4 min per level) |
| TAB | Notes journal — re-read anything you have already found |
| Space | Shove (the Lab's locker) |
| C | Strike a spark (Level 7 only — free, and the only way to see the Hollow One) |
| J | Debug capture — screenshot + a typed note into the playtest log |
| Esc | Release mouse cursor |

A fading hint is shown in the intro room, covering the four you need to start: WASD, E, F and Shift.

## Levels

The game opens on a **Main Menu** (`main_menu.tscn`). Pressing START loads the Intro Room.

| Level | Environment | Win Condition | Fail Condition |
|-------|-------------|---------------|----------------|
| Main Menu | Atmospheric background, title screen | Press START | — |
| Intro | Dark room with candle | Walk through the glowing door | — |
| 1 — The Lab | Sprawling institutional wing — 10 rooms: reception, exam rooms, records, a sealed morgue, a one-way-mirror observation room | **Restore power** (flip 3 breakers) to drop the morgue shutter, take the guarded keycard from the dark morgue, use on exit door | Interact with or stare 3 s at a trigger object; the apparition rushes you if you sprint; or panic bar fills |
| 2 — The House | Abandoned domestic interior — 8 ground-floor rooms + a descent into the cellar (door slams, footsteps overhead, a moonlit forest behind the window, TV static, a music box) | Solve the folded map's maze minigame to earn the cellar key, read 3 safe notes (the third is down in the cellar), enter the 3-digit code on the lock | Read a trap note to the end; panic bar fills (scares, cursed props, dark cellar, wrong lock codes) |
| 3 — The Corridor | ~320 m haunted-hotel hallway (inspired by *The Corridor*, 2012); the Manager and creature-filled turn mirrors strike along the way | Never reach room 217 — fifteen metres out the corridor goes black and your light dies for good, and five metres short of the door the floor gives way and drops you into the Backrooms | Panic bar fills (events, darkness, beartraps, cursed mirror/clock/paintings, sprinting, the final dread zone) |
| 4 — The Backrooms | Liminal mono-yellow maze in three zones — the Lobby (looping intersections, buzzing fluorescents, a ringing rotary phone, mirage back-doors, the Smiler in the dark), the Sprawl (an oversized pillar hall where sound, not sight, marks the real exit), and the Flood (an ankle-deep flooded wing where the exit only shows with the flashlight off) | Clear all three zones — each ends in a glitch wall that reveals the way to the next | Wrong turn/wrong wall in the Lobby/Sprawl; standing still too long; light the Smiler or sprint near it; answer the phone to the end; or the panic bar fills |
| 5 — KONTUR | A decaying Soviet stairwell that sterilises room by room into a clinical containment wing — eight gates, each a different verb (choose, use, recall, abstain, ignore, unlight, wait, don't look), each one's answer hidden somewhere in an earlier level | Pass all eight gates, then reach the exit — it stays sealed until every gate is cleared | Three wrong-answer strikes, the motionless mimic in the passage, forfeiting one of the three no-take-backs gates (the offering, the phone, the escort), or the panic bar fills. The wrong door at Gate 1 doesn't kill you — it drops you back a level, into the Backrooms |
| 6 — The Breach | A deeper containment wing of the same facility, rupturing into organic decay | Object 12 is loose and hunts you across the whole wing. Lure it into the incinerator and seal the blast door — the only permanent answer | Contact with the creature, or the panic bar fills. Your torch only blinds it while it is chasing; hiding spots and slam doors buy seconds, not safety |
| 7 — The Nightmare | A lightless procedural dungeon, different every time you sleep | Light all seven wall sconces by candlelight, then sleep in the bed at the far end | Creature contact, a Weeping Frame you stared at too long, or the panic bar fills. ⭐ The level's thesis inverts every earlier one: standing still and listening is the winning move |
| 8 — The Void | Surreal broken geometry, looping corridors, stalking red-eyed creatures, a floor broken open over the abyss | Find the twist note, walk through exit | A creature reaches you; you fall into the void; read a trap note to the end; or the panic bar fills |
| Ending | Returns to the intro room — corrupted: dead candle, blood-red throb, the way out boarded over, one spotlit note | Read the note | — |

## Stack

- **Engine:** Godot 4.6 (Forward+ renderer)
- **Language:** GDScript
- **3D tools:** Blender → `.glb` → Godot
- **Platform:** macOS native `.app` (Apple Silicon M3)

## Running the Game

1. Open Godot 4
2. Import the project: `File > Open Project` → select `game/`
3. Press **F5** to run

## Asset Sources

- **Textures:** PolyHaven, AmbientCG (CC0 PBR)
- **Audio:** Freesound.org (CC0), MusicGen by Meta (HuggingFace)
- **3D models:** Blender, Mixamo (free characters/animations)
- **Images:** Gemini via nano-banana-pro skill

## Project Documentation

| File | What's in it |
|------|-------------|
| [`GAME_MECHANICS_IDEAS.md`](GAME_MECHANICS_IDEAS.md) | **The live idea backlog — start here for "what should we build next."** Audited build status of every accepted idea (with `file:line` evidence), the live defects, new ideas with implementation sketches, the rejection ledger, and the build order. Consolidates and replaces the archived `drafts/REPORT.md` + `drafts/IDEA_HISTORY.md`. |
| [`SCARY.md`](SCARY.md) | The authoritative fear-craft specification: the diagnosis, eleven costed retrofits (P1–P11), the audio-architecture overhaul, three new levels, eleven anti-patterns, and a phased roadmap. |
| [`DUNGEON_NIGHTMARES.md`](DUNGEON_NIGHTMARES.md) | Full design spec for one new level (THE NIGHTMARE), plus a dossier on the *Dungeon Nightmares* games it adapts. |
| [`COMMENTS.md`](COMMENTS.md) | Developer retrospective — design decisions, technical choices, and observations made throughout the build. Covers horror philosophy, level architecture, Godot patterns used, and what worked unexpectedly well. Starting point for a technical report. |
| [`ISSUES_SOLUTIONS.md`](ISSUES_SOLUTIONS.md) | Hard-to-diagnose bugs with full root cause analysis. Each entry: symptom → root cause → fix → files changed. Covers the Godot input event double-fire, UI anchor footguns, raycasting geometry edge cases, and the Gemini API JPEG-as-PNG issue. |
| [`CLAUDE.md`](CLAUDE.md) | The working spec — every level's mechanics, the panic system, the code architecture, and the ⚠️ notes that record why a thing is the way it is. The longest and most actively maintained document here. |
| [`BACKLOG.md`](BACKLOG.md) | Reported issues and code-audit findings, with what was fixed and what is still open. |
| [`BUG_FIX.md`](BUG_FIX.md) | A closed playtest triage plan from July. Superseded — kept because other docs cite its section numbers as provenance for design decisions. |
| [`INTRO.md`](INTRO.md) · [`BACKROOMS.md`](BACKROOMS.md) | Per-level design notes. |
| [`drafts/`](drafts/) | Superseded documents, annotated rather than deleted: `REPORT.md`, `IDEA_HISTORY.md`, and the KONTUR set (`KONTUR.md` plus `KONTUR/`) archived 2026-08-15. `KONTUR.md` is kept deliberately — other docs cite it as the cautionary tale about a stale design doc that contradicts the shipped level. |
| [`assets_src/`](assets_src/) | Unprocessed originals of supplied assets, with the exact commands that turn each one into its shipped counterpart. Outside `game/` so Godot never imports them. |
| [`TODO.md`](TODO.md) · [`TODO_sounds.md`](TODO_sounds.md) | Outstanding work, and audio/textures the game is already wired for but that do not exist yet (each has a working fallback). |
| [`ARTICLE.md`](ARTICLE.md) | Write-up notes. |
| [`TEXTURES.md`](TEXTURES.md) | Registry of every texture — filename, visual description, which level/nodes it applies to, and generation status (`done` / `to_be_added`). Reference before any texture generation session. |

## Known Gotchas

**nano-banana-pro outputs JPEG data with `.png` extension.** After generating any image, convert it to a real PNG or Godot will silently fail to import it:
```bash
sips -s format png path/to/image.png --out path/to/image.png
```

**Screamer images are loaded from `game/assets/textures/screamers/` at startup.** Any `.png` file dropped into that folder is picked up automatically via `DirAccess` scan in `screamer.gd` — no code change needed to add new screamer variants.

**New audio files need a Godot import pass.** If a `.wav`/`.ogg` file has no matching `.import` file in the same directory, Godot won't load it. Open the editor and let the filesystem scan complete (or run `Godot --headless --path game --import`) after adding audio assets.

**Back doors keep your progress.** Every level has a blood-red back door to the previous one, and walking back now RESTORES what you had done there — breakers flipped, notes read, gates passed. Dying still wipes that level's progress; the no-checkpoint fail philosophy is deliberate.

**Most SFX are procedurally generated, stdlib-only.** Nine generators live in `tools/`, one per area — `make_sfx.py` (Corridor), `make_sfx_house.py`, `make_sfx_backrooms.py`, `make_sfx_kontur.py`, `make_sfx_level6.py`, `make_sfx_dungeon.py`, `make_sfx_intro.py`, `make_sfx_atmos.py` and `make_sfx_extra.py`. Re-run any of them to regenerate its files, then `--import`; replace any output with a Freesound CC0 recording for higher fidelity.

Three more tools post-process supplied assets rather than synthesising: `make_loop.py` (trims a fade-out and crossfades the seam so a one-shot can loop — every `.wav.import` here is `loop_mode=0`, so loops are restarted in code and a mismatched seam ticks once per cycle), `cutout_alpha.py` (keys a generated image's background to real alpha) and `restencil_door.py` (crops a door to its leaf and repaints its sign). The last two need Pillow — run them with `nano-banana-pro/.venv/bin/python3`.
