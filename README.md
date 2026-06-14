# Let's vibe code a f*cking video game

A 3D first-person atmospheric horror game built in Godot 4. You are **Subject 47**. This is a psychological experiment. Stay calm.

## Premise

You wake in a dark room. A note on the table tells you that you are part of an experiment — and that the entity you may encounter is a product of your own mind. Four levels stand between you and the truth. Touch the wrong things and the experiment ends badly.

## Gameplay

- **First-person exploration** — walk through 4 escalating environments
- **Trigger objects** — specific objects are traps. Interact with them (press E) or stare for 3 continuous seconds → screamer → level restarts
- **Trap notes (read-to-die)** — trap notes open like any other note, but panic climbs fast while the page is open and the text bleeds red. Close it in time and you escape shaken; read to the end and the screamer takes you
- **Panic system** — staring at any object tagged as `ScaryObject` fills a panic bar. The bar rises ~1.3× faster than it falls. Hit the limit → screamer. Visual feedback: blur + red-tint overlay. Audio feedback: heartbeat whose pitch and volume rise with panic
- **Sprint at a cost** — Shift runs ×1.6 faster but feeds panic ~6/s and blocks recovery. The corridor's note warns you: *Walk. Do not run.* It means it
- **Flashlight with a battery** — toggle with **F**. Each level's charge lasts ~4 minutes of ON time; the bulb stutters as a warning, then dies for the rest of the level. It's on by default — manage it or lose it in the dark stretches
- **Scripted scares** (Levels 2–3) — one-shot events spike panic directly: door slams, footsteps overhead, lights dying as you enter a room; darkness makes panic creep unless the flashlight is on; torchlight calms it 2.5× faster; beartraps snap, hurt and slow you; the corridor's final stretch is a dread zone where panic barely drains
- **Survivable jump-scares** — some scares flash and shock but don't kill: press up to the House window and a moonlit **forest** lunges (`screamer_forest`); a hotel **Manager** strikes once mid-corridor; the corridor's **turn mirrors** show a creature when you miss a corner. Each spikes panic but lets you recover — only the bar filling is fatal
- **Stalking creatures** (Level 4 — The Void) — tall red-eyed figures that freeze while you watch them and advance the instant you look away (Weeping-Angel logic). Let one reach you and it lunges → screamer. Staring also feeds panic, so you can't just watch one forever
- **Notes** — find and read notes to collect clues, codes, and keycards needed to unlock each exit door
- **Combination lock** — Level 2's exit needs a 3-digit code from the safe notes. Every wrong guess buzzes and spikes panic: brute-forcing the lock is itself a way to die
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
| Esc | Release mouse cursor |

A fading hint with these controls is shown in the intro room.

## Levels

The game opens on a **Main Menu** (`main_menu.tscn`). Pressing START loads the Intro Room.

| Level | Environment | Win Condition | Fail Condition |
|-------|-------------|---------------|----------------|
| Main Menu | Atmospheric background, title screen | Press START | — |
| Intro | Dark room with candle | Walk through the glowing door | — |
| 1 — The Lab | Sterile corridor + 3 examination rooms | Take the keycard from the cart between the tray and the monitor (the lights die as you grab it), use on exit door | Interact with or stare 3 s at a trigger object; or panic bar fills |
| 2 — The House | Abandoned domestic interior (door slams, footsteps overhead, a moonlit forest behind the window) | Read 3 safe notes, enter 3-digit code on lock | Read a trap note to the end; panic bar fills (scares, cursed props, dark bedroom, wrong lock codes) |
| 3 — The Corridor | ~320 m haunted-hotel hallway (inspired by *The Corridor*, 2012); the Manager and creature-filled turn mirrors strike along the way | Reach room 217 at the far end | Panic bar fills (events, darkness, beartraps, cursed mirror/clock/paintings, sprinting, the final dread zone) |
| 4 — The Void | Surreal broken geometry, looping corridors, stalking red-eyed creatures, a floor broken open over the abyss | Find the twist note, walk through exit | A creature reaches you; you fall into the void; read a trap note to the end; or the panic bar fills |
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
| [`COMMENTS.md`](COMMENTS.md) | Developer retrospective — design decisions, technical choices, and observations made throughout the build. Covers horror philosophy, level architecture, Godot patterns used, and what worked unexpectedly well. Starting point for a technical report. |
| [`ISSUES_SOLUTIONS.md`](ISSUES_SOLUTIONS.md) | Hard-to-diagnose bugs with full root cause analysis. Each entry: symptom → root cause → fix → files changed. Covers the Godot input event double-fire, UI anchor footguns, raycasting geometry edge cases, and the Gemini API JPEG-as-PNG issue. |
| [`TEXTURES.md`](TEXTURES.md) | Registry of every texture — filename, visual description, which level/nodes it applies to, and generation status (`done` / `to_be_added`). Reference before any texture generation session. |

## Known Gotchas

**nano-banana-pro outputs JPEG data with `.png` extension.** After generating any image, convert it to a real PNG or Godot will silently fail to import it:
```bash
sips -s format png path/to/image.png --out path/to/image.png
```

**Screamer images are loaded from `game/assets/textures/screamers/` at startup.** Any `.png` file dropped into that folder is picked up automatically via `DirAccess` scan in `screamer.gd` — no code change needed to add new screamer variants.

**New audio files need a Godot import pass.** If a `.wav`/`.ogg` file has no matching `.import` file in the same directory, Godot won't load it. Open the editor and let the filesystem scan complete (or run `Godot --headless --path game --import`) after adding audio assets.

**Corridor and House SFX are procedurally generated.** `tools/make_sfx.py` (pure stdlib Python) synthesizes `clock_chime.wav`, `glass_shatter.wav`, `beartrap_snap.wav`, `door_slam.wav` and `whispers.wav` into `game/assets/audio/level_3_corridor/`; `tools/make_sfx_house.py` synthesizes `lock_buzz.wav` and `footsteps_above.wav` into `game/assets/audio/level_2_house/`. Re-run to regenerate; replace any file with a Freesound CC0 recording for higher fidelity.
