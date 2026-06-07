# Horror Game — Claude Context

## Project
3D first-person atmospheric horror prototype. Desktop macOS app (.app bundle).
No active enemy AI — horror through atmosphere, lighting, sound, and environment storytelling.

## Game Design

### Premise
The player wakes in a dark room as **Subject 47** — a participant in a psychological experiment testing their ability to conquer fear. A note explains: the entity they may encounter is a manifestation of their own mind, not real. Stay calm. Do not touch what you are not meant to touch.

### Structure
```
Intro room → Level 1 (The Lab) → Level 2 (The House) → Level 3 (The Void) → Twist Ending
```

Each level: explore the environment, find clues/items, unlock the exit door. Fail = screamer + restart that level. Pass = enter the next door.

### Levels

**Intro Room**
Small dark room. Candle on a table with the opening note. Single glowing exit door.
Note text: *"You are Subject 47. This is a psychological experiment... Stay calm. Do not touch what you are not meant to touch. The door ahead is your first test. We are watching."*

**Level 1 — The Lab (institutional corridor)**
- Sterile hallway + 3 examination rooms, flickering fluorescent lights
- 3 safe notes (reveal keycard location), 2 trigger objects (surgical tray, monitor with face)
- Win: collect keycard → use on exit door
- Fail: touch/stare at a trigger object for 3+ seconds → screamer → restart

**Level 2 — The House (abandoned domestic interior)**
- Hallway, living room, kitchen, staircase, bedroom
- 3 safe notes (each contains one digit of a 3-digit code), 2 trap notes
- Win: read 3 safe notes, enter code on combination lock on exit door
- Fail: read a trap note fully → screamer → restart
- Trap note cues: desperate tone, fragmented writing, slightly different visual texture
- Creature glimpsed once through a window (static, no behaviour)

**Level 3 — The Void (surreal broken geometry)**
- Corridors loop, geometry distorted, floating tiles, floor text
- 8 notes total (5 safe, 3 trap). One safe note is the **twist note** (`is_twist_note = true`)
- Static creature instances visible in every room — motionless unless triggered
- Win: read the twist note → exit door unlocks → walk through
- Fail: touch a trap note or trigger object → creature rushes camera → screamer → restart

**Twist Ending**
Final door loads back to the intro room. New note on the table: *"Very good, Subject 47. Beginning trial 2."* Screen fades → credits.

### Trigger Object Rules
- Trigger objects and trap notes are **instant fail** on interaction (press E) OR after 3 continuous seconds of direct gaze
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
- `go_back()` does NOT call `reset_level_state()` — keycard/code flags persist across back-navigation

## Stack
- **Engine:** Godot 4 (Forward+ renderer)
- **Language:** GDScript (snake_case everywhere)
- **3D tools:** Blender (model/rig) → export .glb → import into Godot
- **Platform:** macOS native .app (Apple Silicon M3)

## Code Architecture

### Autoloads (global singletons, survive scene transitions)
Registered in `game/project.godot`. Access directly by name from any script.

| Autoload | File | What it owns |
|----------|------|-------------|
| `GameState` | `scripts/game_state.gd` | Level state, `has_keycard`, `code_entered`, `twist_read`; `advance_level()`; `go_back()` (no state reset); `load_audio(base_name)` |
| `Screamer` | `scripts/screamer.gd` | `trigger()` — black flash → screamer image → audio burst → scene reload. `process_mode = PROCESS_MODE_ALWAYS` (must not freeze during tree pause). `_is_triggering` bool guards both `trigger()` and `trigger_to_menu()` against re-entry. Textures loaded via `DirAccess` scan of `res://assets/textures/screamers/` at startup — drop any `.png` there to add it to the rotation. |
| `NoteUI` | `scripts/note_ui.gd` | Fullscreen note overlay. `show_note(text)` / `is_open` bool. Built entirely in GDScript — no .tscn. Guard `is_open` in player before any interaction logic |

### Key scripts
| Script | Responsibility |
|--------|---------------|
| `player.gd` | `CharacterBody3D` movement, raycast interaction, gaze timer (3s stare → fail) |
| `door.gd` | Unlock modes: `NONE` · `KEYCARD` · `CODE_ENTERED` · `TWIST_READ`; `@export var goes_back: bool` for back doors |
| `note.gd` | Note interact, `is_trap` / `is_twist_note` flags, red tint on trap notes |
| `combination_lock.gd` | 3-digit spinner UI for Level 2 exit (code: **472**) |
| `creature_static.gd` | Level 3 static creature; `rush_camera()` fires on trigger |
| `vignette.gd` | `class_name Vignette` — `Vignette.spawn(parent, color, strength)` adds per-level overlay |
| `keycard.gd` | Pickup → sets `GameState.has_keycard`; auto-hides on reload if already collected |
| `main_menu.gd` | Main menu: background image (`main_menu_bg.png`), "SUBJECT 47" title, blood-red START/QUIT buttons; START loads `intro_room.tscn`; QUIT calls `get_tree().quit()` |

### Level scenes
| Scene | Unlock condition | Notes |
|-------|-----------------|-------|
| `main_menu.tscn` | — | Game entry point; background image (`main_menu_bg.png`), START loads `intro_room.tscn` |
| `intro_room.tscn` | NONE | Player spawn z=+1.5; table centered; ambient 0.15; walls size.y=3.0 |
| `level_1.tscn` | KEYCARD | Player spawn z=−5.5; `_apply_textures()` + `_spawn_note_tables()` in `level_1.gd`; BackDoor at z=−6.05 |
| `level_2.tscn` | CODE_ENTERED | Player spawn z=−2.5; LivWallR split for bedroom doorway; DoorwayFloor bridges floor gap; BackDoor at z=−3.05 |
| `level_3.tscn` | TWIST_READ | Player spawn z=−2.0; vignette strength 2.0; BackDoor at z=−3.05; `_spawn_note_tables()` called in `_ready()` (all 8 notes) |
| `ending.tscn` | — | Reloads intro_room, credits fade |

## Folder Layout
```
horror_game/
├── game/                  ← Godot project root
│   ├── project.godot
│   ├── scenes/            ← .tscn scene files
│   ├── scripts/           ← .gd GDScript files
│   └── assets/
│       ├── audio/         ← .ogg files (ambient, SFX, music)
│       ├── models/        ← .glb 3D models
│       ├── textures/      ← .png/.jpg texture maps
│       └── materials/     ← .tres Godot material files
├── nano-banana-pro/       ← image generation skill (Gemini)
├── .agents/skills/        ← Claude skills
└── .env                   ← API keys (never commit)
```

## Skills Installed (in .agents/skills/)
| Skill | When to invoke |
|-------|----------------|
| `game-developer` | Godot scene setup, GDScript patterns, performance |
| `shader-techniques` | GLSL shaders, horror post-processing, fog/dissolve effects |
| `3d-modeling` | Blender topology, UV unwrapping, export settings for Godot |
| `nano-banana-pro` | Generate concept art, texture references, UI mockups |
| `grill-me` | Stress-test a design or plan decision |
| `fix-void` | Diagnose and fix black void / open-space holes in CSGBox3D levels. Use whenever a user reports a black rectangle, missing wall, floor gap, or visible void. The skill contains the full diagnostic protocol: localise → map coverage → identify void type → compute fix node → verify → write. Also contains a table of all voids already fixed in this project. |

## Asset Pipeline
- **3D models:** Blender → File > Export > glTF 2.0 (.glb) → `game/assets/models/`
- **Textures:** PolyHaven / AmbientCG (CC0 PBR) or Stable Diffusion → `game/assets/textures/`
- **Audio:** Freesound.org (CC0) or MusicGen (HuggingFace) → export as .ogg → `game/assets/audio/`
- **Characters/animations:** Mixamo (free) → download as .fbx → open in Blender → export as .glb

### Texture audit rule (run at the start of every level content session)
1. Read `TEXTURES.md`
2. For each row with `status: done`, check the relevant level script (`level_1.gd`, `level_2.gd`, etc.) to confirm the texture is loaded inside `_apply_textures()` (or equivalent)
3. If a `done` texture is **not** referenced in its level script, add the load + apply code before doing any other work
4. For decal-type textures (painting, cobweb, poster, blood — applied via MeshInstance3D quads), check the corresponding `.tscn` for the MeshInstance3D node; add it to the scene if missing

## Free AI Asset Tools
- **3D gen:** TripoSR, Shap-E (HuggingFace Spaces, free)
- **Audio gen:** MusicGen by Meta, Bark (HuggingFace Spaces, free)
- **Image gen:** nano-banana-pro skill (Gemini API) — budget is ~20 images total, use sparingly. Prefer PolyHaven/AmbientCG for standard PBR textures. Reserve nano-banana for unique horror imagery (wall art, notes, posters, UI backgrounds) that can't be sourced free elsewhere.
- **Narrative/story:** OpenRouter — `nvidia/nemotron-3-super-120b-a12b:free` via `https://openrouter.ai/api/v1`

## nano-banana-pro Python Environment
Deps are installed in a venv at `nano-banana-pro/.venv/`.
Always invoke the script with the venv Python:
```bash
nano-banana-pro/.venv/bin/python3 nano-banana-pro/generate_image.py "prompt" -o path/to/output.png
```

### ⚠️ Always convert nano-banana-pro output to real PNG before importing into Godot
See `ISSUES_SOLUTIONS.md` — Issue 1 for diagnosis steps and the `sips` fix.

## Debugging
Before diagnosing any bug, read `ISSUES_SOLUTIONS.md`. It documents the hardest bugs encountered so far — Godot input event double-fire, UI anchor off-screen rendering, raycast geometry misses on flat objects, the Gemini JPEG-as-PNG import failure, and double-screamer re-entry on rapid keypresses. Re-solving a known issue wastes time.

## Code Conventions
- GDScript snake_case for variables and functions, PascalCase for class names
- One script per scene node where possible
- Signals preferred over direct node references for decoupling
- No magic numbers — use named constants or exported variables

## API Keys
All keys live in `.env` at the project root. Never commit `.env`.
See `.env.example` for required keys.
