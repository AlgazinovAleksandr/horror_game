# Let's vibe code a f*cking video game

A 3D first-person atmospheric horror game built in Godot 4. You are **Subject 47**. This is a psychological experiment. Stay calm.

## Premise

You wake in a dark room. A note on the table tells you that you are part of an experiment — and that the entity you may encounter is a product of your own mind. Four levels stand between you and the truth. Touch the wrong things and the experiment ends badly.

## Gameplay

- **First-person exploration** — walk through 4 escalating environments
- **Trigger objects & trap notes** — specific objects and notes are traps. Interact with them (press E) or stare for 3 continuous seconds → screamer → level restarts
- **Panic system** — staring at any object tagged as `ScaryObject` fills a panic bar. The bar rises ~1.3× faster than it falls. Hit the limit → screamer. Visual feedback: blur + red-tint overlay. Audio feedback: heartbeat whose pitch and volume rise with panic
- **Corridor survival** (Level 3) — scripted scares spike panic directly; darkness makes it creep up unless the flashlight is on; standing in torchlight calms it 2.5× faster; beartraps snap, hurt and slow you. Walking the hallway calm is the whole test
- **Notes** — find and read notes to collect clues, codes, and keycards needed to unlock each exit door
- **Flashlight** — toggle with **F** (bound to `toggle_flashlight` action)
- **Back doors** — each level has a back door (blood-red glow) that returns you to the previous level. Collected items (keycard, code) are cleared on re-entry
- **No combat** — horror through atmosphere, sound, lighting, and restraint

## Controls

| Key | Action |
|-----|--------|
| WASD | Move |
| Mouse | Look |
| E | Interact (notes, doors, keycard, lock) |
| F | Toggle flashlight |
| Esc | Release mouse cursor |

## Levels

The game opens on a **Main Menu** (`main_menu.tscn`). Pressing START loads the Intro Room.

| Level | Environment | Win Condition | Fail Condition |
|-------|-------------|---------------|----------------|
| Main Menu | Atmospheric background, title screen | Press START | — |
| Intro | Dark room with candle | Walk through the glowing door | — |
| 1 — The Lab | Sterile corridor + 3 examination rooms | Find keycard, use on exit door | Interact with or stare 3 s at a trigger object; or panic bar fills |
| 2 — The House | Abandoned domestic interior | Read 3 safe notes, enter 3-digit code on lock | Read a trap note (fully) |
| 3 — The Corridor | ~320 m haunted-hotel hallway (inspired by *The Corridor*, 2012) | Reach room 217 at the far end | Panic bar fills (events, darkness, beartraps, cursed mirror/clock/paintings) |
| 4 — The Void | Surreal broken geometry, looping corridors | Find the twist note, walk through exit | Interact with or stare at trap note / trigger object; panic bar fills |
| Ending | Returns to intro room | Credits fade | — |

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
| [`TEXTURES.md`](TEXTURES.md) | Registry of all 20 textures — filename, visual description, which level/nodes it applies to, and generation status (`done` / `to_be_added`). Reference before any texture generation session. |

## Known Gotchas

**nano-banana-pro outputs JPEG data with `.png` extension.** After generating any image, convert it to a real PNG or Godot will silently fail to import it:
```bash
sips -s format png path/to/image.png --out path/to/image.png
```

**Screamer images are loaded from `game/assets/textures/screamers/` at startup.** Any `.png` file dropped into that folder is picked up automatically via `DirAccess` scan in `screamer.gd` — no code change needed to add new screamer variants.

**New audio files need a Godot import pass.** If a `.wav`/`.ogg` file has no matching `.import` file in the same directory, Godot won't load it. Open the editor and let the filesystem scan complete (or run `Godot --headless --path game --import`) after adding audio assets.

**Corridor SFX are procedurally generated.** `tools/make_sfx.py` (pure stdlib Python) synthesizes `clock_chime.wav`, `glass_shatter.wav`, `beartrap_snap.wav`, `door_slam.wav` and `whispers.wav` into `game/assets/audio/`. Re-run it to regenerate; replace any file with a Freesound CC0 recording for higher fidelity.
