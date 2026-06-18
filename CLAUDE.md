# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Horror Game — Claude Context

## Project
3D first-person atmospheric horror prototype. Desktop macOS app (.app bundle).
No active enemy AI — horror through atmosphere, lighting, sound, and environment storytelling.

## Game Design

### Premise
The player wakes in a dark room as **Subject 47** — a participant in a psychological experiment testing their ability to conquer fear. A note explains: the entity they may encounter is a manifestation of their own mind, not real. Stay calm. Do not touch what you are not meant to touch.

### Structure
```
Intro room → Level 1 (The Lab) → Level 2 (The House) → Level 3 (The Corridor) → Level 4 (The Backrooms) → Level 5 (The Void) → Twist Ending
```

Each level: explore the environment, find clues/items, unlock the exit door. Fail = screamer + restart that level. Pass = enter the next door.

### Levels

**Intro Room**
Small dark room. Candle on a table with the opening note. Single glowing exit door.
Note text: *"You are Subject 47. This is a psychological experiment... Stay calm. Do not touch what you are not meant to touch. The door ahead is your first test. We are watching."*

**Level 1 — The Lab (institutional corridor)**
- Sterile hallway + 3 examination rooms, flickering fluorescent lights
- 3 safe notes (reveal keycard location), 2 trigger objects (surgical tray, monitor with face)
- **Guarded keycard**: the keycard sits on a cart in Room 1 *between* the tray and the monitor — retrieving it means navigating your own gaze. Taking it fires `on_keycard_taken()` in `level_1.gd`: 1.6 s light-blackout stutter + creak + 8 panic
- Win: collect keycard → use on exit door
- Fail: touch/stare at a trigger object for 3+ seconds → screamer → restart

**Level 2 — The House (abandoned domestic interior)**
- Hallway, living room, bedroom (geometry in `level_2_1.tscn`)
- 3 safe notes (each contains one digit of a 3-digit code), 2 trap notes
- Win: read 3 safe notes, enter code on combination lock on exit door
- Fail: read a trap note **fully** → screamer → restart. Read-to-die: trap notes open normally but feed +12 panic/s while open (`TRAP_PANIC_RATE` in `note.gd`, ticked by `note_ui.gd`); the text bleeds red as panic climbs; closing early saves you with a part-full bar
- Trap note cues: desperate tone, fragmented writing, red-tinted paper texture
- **The window + Forest scare** (`_spawn_window()` in `level_2.gd`): a moonlit forest (`forest.png`) sits behind the glass, faintly self-lit so it reads in the dark. Press up to it (≤1.5 m) and the **Forest scare** fires once — a SURVIVABLE `flash_scare(screamer_forest.png, "screamer_forest")` + camera jolt + 25 panic (`_forest_fired` guards it; re-arms on restart). No instant fail — only the panic spike can finish you
- **Pressure package** (built at runtime in `level_2.gd`): cursed props (bedroom painting 0.8, living-room mirror 1.2) feed gaze panic; 3 `CorridorEvent` triggers — front door slam (+8), footsteps overhead (+6, `footsteps_above.wav`), bedroom light dies (+6, bedroom becomes a `DarkZone`)
- **Lock penalty**: each wrong combination = harsh buzz (`lock_buzz.wav`) + 10 panic — brute-forcing the lock is itself a fail path

**Level 3 — The Corridor (haunted hotel hallway)** — inspired by *The Corridor* (2012)
- ~320 m zigzag hallway built **procedurally** in `corridor.gd` from `PATH_2D` (7 segments, 90° turns, 3 m wide). Three zones: A "Hotel" 0–90 m (intact, lit torches every 12 m, paintings, grandfather clock), B "Decay" 90–230 m (blood smears, lights shatter, beartraps in the dark stretch), C "Nightmare" 230–320 m (dead torch panels, the mirror, constant whispers, near-black)
- **No fetch quest** — exit door (room 217, `door.png`) has `unlock_condition = NONE`; walking the corridor without panicking IS the test
- Panic pressure: `CorridorEvent` triggers add panic directly (entry door slam +10, clock chime +10, silhouette crossing the far junction +20, floor crack +10); `DarkZone`s add +3/s while flashlight is off; `Torch3D` calm zones decay panic ×2.5; cursed gaze panels (paintings 0.8/1.2, clock 1.0, side-wall `mirror.png` 2.0/2.5); 5 beartraps = snap + 15 panic + **escape mechanic** (see Beartrap below)
- **Turn mirrors** (`_spawn_turn_mirror` in `corridor.gd`): `mirror_with_creature.png` set flush on the wall you face at the 90/230/275 m corners — miss the turn and you walk into the creature head-on. Gaze panel (intensity 1.5–2.2) **plus** a one-shot close-up `flash_scare(mirror_with_creature.png, "glass_shatter")` + jolt + 12 panic when you come within 2 m (`_turn_mirrors` proximity-tested in `_process`)
- **The Manager** (`_ev_manager`): a SURVIVABLE scare that strikes once at a random mid-hall point. A `CorridorEvent` is dropped at `randf_range(80, 180)` m (distance-triggered, not wall-time, so it always fires regardless of walk/run speed) → `flash_scare(screamer_manager.png, "screamer_manager")` + jolt + 25 panic
- **Zone C dread** (230–320 m, `DreadZone` spawned by `_spawn_dread_zone()`): decay weakens 15→6/s and a constant +1.5/s pressure accrues regardless of anything else — panic from the silhouette/floor-crack/mirror no longer fully drains, making the last 90 m an endurance gauntlet
- One framing note at the entrance ("Hotel Vesper — The Management"); 3 fake locked doors (`fake_door.gd`) that knock back (+8 panic, first try only) + 6 non-interactive decor doors. All non-final doors use `ordinary_hotel_door.png`; **only the exit (room 217) keeps `door.png`**
- Corridor-exclusive screamer: `screamer_hotel.png` — kept OUT of `screamers/`; `screamer.gd` selects it when `GameState.current_level == 3`
- Prop textures (`door/clock/mirror/torch.png`) share the same baked wallpaper+wainscot background as `wall.png`, so they're applied as full-height wall panels that blend into the wall texture

**Level 4 — The Backrooms (liminal mono-yellow maze)** — `backrooms.gd` + `backrooms.tscn`
- **Entry = the noclip** (`_spawn_noclip()` in `corridor.gd`): the player never reaches room 217. Ten metres out, every torch dies and `player.kill_flashlight()` force-kills the light (F now only plays a dead-battery click). A floor `CorridorEvent` at the door fades to black + 2 s drop → `advance_level()` → wake on the carpet
- **Cyclic maze, no seamless portals** (design Q1): a 4-way intersection hub with three choice arms (N/E/W) built from `CSGBox3D`, triplanar `backrooms_wallpaper_albedo` walls + `backrooms_carpet_albedo` floor, recessed flickering fluorescents. The E/W arms dead-end in a `LoopBack` trigger that teleports you to an identical re-randomised hub — so it reads as an endless series of intersections without any continuous-portal seams
- **Win — three down-turns** (`_assign_round`, `_on_arm_entered`): `arrow_decal.png` on the hub columns marks exactly one arm with a DOWN arrow each round. Take it to advance the loop counter; the E/W arms loop back, and on the 3rd correct turn the win arm (N) is forced and opens into the exit utility room. The **glitch wall** there runs a screen-space vertex-jitter shader (`glitch_wall.gdshader`); walking into its `ExitTrigger` Area3D → `advance_level()` → The Void
- **Fail — wrong turn**: entering a non-down-arrow arm = `light_pop` + 15 panic + counter reset + teleport to the start (`_wrong_turn`). **Standing still** > 4 s raises panic (`player.enable_standstill_panic()`, +3/s) — the maze forbids rest. Plus the usual panic-bar-fills death
- **Dynamic dark zones**: one (always-wrong) arm goes black each round (`_apply_dark_arm` → lights off + `DarkZone`)
- **The Smiler** (`creature_smiler.gd`, ~50% per dark arm): a glowing `screamer_smiler.png` billboard at the dark arm's end. Its logic INVERTS the maze (design Q2): shine your flashlight on it **or** sprint → rush → `Screamer.trigger()` (fatal — the smiler image fills the screen via `LEVEL_SCREAMERS[4]`). Turn the light OFF and hold still (don't sprint) and it fades after 4 s. While engaged it calls `player.set_smiler_active(true)` to suspend the standstill + dark ticks and drives its own slow dread (+2.5/s) — freezing to survive is tense but fair
- **Footstep echo** (`player.enable_footstep_echo()`): every step replays at half-volume 0.4 s later, two paces behind you
- **Mirage doors** (`mirage_door.gd`): blood-red doors identical to the back doors; opening one swings onto blank wallpaper + 10 panic, mocking the hope of retreat
- **The rotary phone** (`rotary_phone.gd`): a 1970s phone on the carpet that rings (`rotary_ring`); answering (E) plays `phone_whisper` and opens a read-to-die trap note via `NoteUI.show_note(text, 11.0)` — hang up (close) to survive
- Win: three down-turns → walk into the glitch wall. Fail: wrong turns/standing still/the Smiler/a read-to-end phone call → panic bar fills

**Level 5 — The Void (surreal broken geometry)**
- Corridors loop, geometry distorted, floating tiles, floor text
- 8 notes total (5 safe, 3 trap). One safe note is the **twist note** (`is_twist_note = true`)
- **Stalking creatures** (`creature_stalker.gd`, 4 of them, Weeping-Angel logic): each is a Mixamo GLB figure (`Void_creature.glb`) rendered as a dark shadow with blue eye glow via `material_override`. It freezes while in your FOV + line-of-sight (`ENGAGE_DIST=8m`, `FOV_DOT=0.55`), advances at 1.25 m/s the moment you look away, and lunges → `Screamer.trigger()` on contact. Staring also feeds gaze panic (`GAZE_INTENSITY=0.6`, ~12/s at full) — you can't just watch one forever. `START_GRACE=5s` keeps the opening safe; `CreatureA` stands dead ahead of spawn as a teaching beat. **Stare-off mechanic**: watch any creature continuously for `STARE_OFF_TIME=4s` and it backs off 3m, resets to dormant — costs ~48 panic; demands nerve. Falls back to procedural capsule silhouette if GLB missing. **⚠️ GLB requirements**: the GLB must have **no embedded textures** (export with "No Textures" in Blender) and **no animations** (or disable the AnimationPlayer in the scene after instantiate). Mixamo's default export embeds a skin texture and auto-plays animations, which breaks the dark-material override and causes erratic movement.
- **Void-fall = fatal**: Room C's floor is broken open around a 1.6 m hole (`_break_room_c_floor()`); `player.global_position.y < -4` → `Screamer.trigger()` (`_check_void_fall`)
- **Ambient pressure** (`_spawn_void_zones()`): Rooms C+D are a `DreadZone` (decay weakened to 2/s + constant +2/s pressure); far rooms are `DarkZone`s. Room A has two warm candles + `CalmZone`s — the only recovery anchor in the level (decay ×2.5 here)
- Win: read the twist note → exit door unlocks → walk through
- Fail: a creature reaches you, you fall into the void, or the panic bar fills

**Twist Ending**
Final door loads back to the intro room — **corrupted** (`_corrupt_room()` in `intro_room.gd`, fires when `GameState.is_ending`): candle dead, slow blood-red throb light, exit door replaced by planks (no way forward), harsh cold spotlight pinning the new note to the table, extra cobwebs, low whisper loop. Reading the note → 2 s → `Screamer.trigger_to_menu()`.

### Trigger Object Rules
- Trigger objects are **instant fail** on interaction (press E) OR after 3 continuous seconds of direct gaze; trap notes are **read-to-die** (panic +12/s while open — see Level 2)
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
- `go_back()` calls `start_current_level()` → `reset_level_state()` — keycard and code flags are cleared on back-navigation (matches current code; earlier design intended state preservation)

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
| `GameState` | `scripts/game_state.gd` | Level state (`current_level`: 0=intro, 1=lab, 2=house, **3=corridor, 4=backrooms, 5=void, 6=ending**), `has_keycard`, `level2_code_correct`, `twist_read`, `is_ending`; `advance_level()`; `go_back()` (both call `start_current_level()` → `reset_level_state()`); `restart_current_level()`; `go_to_main_menu()`; `load_audio(base_name)` (audio subdirs include `level_backrooms`) |
| `Screamer` | `scripts/screamer.gd` | `trigger()` — black flash → screamer image → audio burst → scene reload. `process_mode = PROCESS_MODE_ALWAYS` (must not freeze during tree pause). `_is_triggering` / `_is_flashing` bools guard `trigger()`, `trigger_to_menu()` and `flash_scare()` against re-entry. **Per-level fatal AV**: `_apply_level_av()` picks the image + scream by `GameState.current_level` from `LEVEL_SCREAMERS` (1 lab `screamer_lab`, 2 house `screamer_house`, 3 corridor `screamer_hotel`/`screamer_corridor`, 4 backrooms `screamer_smiler`/`jumpscare`, 5 void `screamer_void`); intro/ending fall back to a random `screamers/` `.png` (DirAccess scan at startup) + the shared `jumpscare`. **`flash_scare(image_path, audio_base, hold)`** — a SURVIVABLE scare: fullscreen image + sound for `hold` s, no pause/restart (the caller adds its own panic). Used by the House forest scare, the Corridor Manager, and the Corridor turn mirrors. |
| `NoteUI` | `scripts/note_ui.gd` | Fullscreen note overlay. `show_note(text, trap_rate := 0.0)` / `is_open` bool. Built entirely in GDScript — no .tscn. Guard `is_open` in player before any interaction logic. While `trap_rate > 0` and the note is open, feeds `player.add_panic()` per frame and tints the text toward red; auto-drops the overlay if the tree unpauses (= a screamer fired) |

### Key scripts
| Script | Responsibility |
|--------|---------------|
| `player.gd` | `CharacterBody3D` movement, raycast interaction, gaze timer (3s stare → fail), **panic system** (`_panic` float, `PANIC_MAX=50`, `PANIC_BASE_RATE=20/s`, `PANIC_DECAY_RATE=3.5/s`, `GAZE_RANGE=3.0m` separate from `INTERACT_RANGE=2.5m`), flashlight toggle (`toggle_flashlight` action, F), heartbeat audio tied to panic ratio. **Sprint** (`sprint` action, Shift): ×1.6 speed, +6 panic/s while sprinting (suppresses decay), faster footsteps. **Flashlight battery**: 240 s per scene (`BATTERY_MAX`), dying-bulb stutter below 48 s, dead = can't re-enable. Zone API: `add_panic(amount)` (instant spike, screamer at max), `apply_slow(duration)` (speed ×0.45), `cancel_slow()` (clears limp instantly — used by beartrap escape), `jolt_camera(strength, duration)`, `enter/exit_calm_zone()` (decay ×2.5), `enter/exit_dark_zone()` (+3 panic/s with flashlight off), `enter/exit_dread_zone()` (decay 2/s + constant 2/s pressure), `get_panic_ratio()`. **Backrooms-only opt-ins** (off by default everywhere else): `enable_standstill_panic()` (+3/s after 4 s still), `enable_footstep_echo()` (phantom step 0.4 s behind), `kill_flashlight()` (force off; F only clicks), `set_smiler_active(bool)` (suspends standstill + dark ticks for the Smiler), `is_flashlight_on()` / `is_sprinting()` |
| `door.gd` | Unlock modes: `NONE` · `KEYCARD` · `CODE_ENTERED` · `TWIST_READ`; `@export var goes_back: bool` for back doors |
| `note.gd` | Note interact, `is_trap` / `is_twist_note` flags. Trap notes open via `NoteUI.show_note(text, TRAP_PANIC_RATE)` — read-to-die, no instant fail |
| `combination_lock.gd` | 3-digit spinner UI for Level 2 exit (code: **472**). Wrong code = buzz + 10 panic (`WRONG_CODE_PANIC`); UI auto-drops if a screamer fires while open |
| `creature_stalker.gd` | `class_name CreatureStalker` — the Void's creatures. Weeping-Angel stalk (move when unobserved, freeze when watched), LOS-gated, `START_GRACE` opening, lunge → `Screamer.trigger()` on contact. Builds its own visible red-eyed figure + gaze collider in `_ready()`. **Moves the inner `StaticBody3D` (not `self`)** — see the ScaryObject transform-chain gotcha below |
| `creature_static.gd` | Older static-creature variant; `rush_camera()` on trigger. The Void now uses `creature_stalker.gd` instead |
| `vignette.gd` | `class_name Vignette` — `Vignette.spawn(parent, color, strength)` adds per-level overlay |
| `keycard.gd` | Pickup → sets `GameState.has_keycard`; auto-hides on reload if already collected |
| `main_menu.gd` | Main menu: background image (`main_menu_bg.png`), "SUBJECT 47" title, blood-red START/QUIT buttons; START loads `intro_room.tscn`; QUIT calls `get_tree().quit()` |
| `scary_object.gd` | `class_name ScaryObject` — attach to any prop that should build panic. `@export var scare_intensity: float = 1.0`. `player.gd:_find_scary_object()` walks the parent chain UP from the ray-hit collider to find it. **Gotcha:** `ScaryObject extends Node` (no transform) and breaks the Node3D spatial chain — see below. |
| `trigger_object.gd` | `StaticBody3D` trap prop — instant screamer on `interact()` OR on `on_gaze_trigger()` (3s gaze). Attach `ScaryObject` as a child to additionally feed the panic bar. |
| `panic_hud.gd` | `PanicHUD` node (loaded from `assets/elements/hud_canvas.tscn`). `set_panic_ratio(ratio)` drives blur (`BlurRect`) and red-tint (`TintRect`) shader overlays. Spawned by `player.gd` in `_ready()`. |
| `ending.gd` | Waits 1 s, sets `GameState.is_ending = true`, then changes scene to `SCENE_INTRO` (triggers twist ending flow). |
| `corridor.gd` | Level 3 script — builds the entire 320 m corridor procedurally from `PATH_2D`: geometry (overlapping CSG segments with corner openings), triplanar materials, torches, wall panels, beartraps, zones, doors, intro note, events. Walls use `uv1_triplanar` with **y-scale −1/3** (negative flips V so the wainscot sits at the floor; positive renders the wall texture upside-down) |
| `corridor_event.gd` | `CorridorEvent` Area3D — one-shot trigger volume; emits `fired` on player entry. `corridor.gd` connects each to an event callback (`_ev_*`) |
| `beartrap.gd` | `Beartrap` Area3D — self-building base+jaw meshes with faint emissive glint (keep emission ≤0.12 or it reads as white paper in the dark); on step: snap SFX + `add_panic(15)` + jaw-close tween + **7-second escape mechanic** (mash E 7 times → `cancel_slow()`, success; timeout → `add_panic(40)`, total 55 > PANIC_MAX → screamer). Builds a CanvasLayer escape UI with countdown bar + press counter. One-shot |
| `calm_zone.gd` / `dark_zone.gd` / `dread_zone.gd` | `CalmZone` / `DarkZone` / `DreadZone` Area3D — call the matching `player.enter/exit_*_zone()` on body enter/exit |
| `torch_3d.gd` | `Torch3D` Node3D — self-building wall torch (bracket + cup + emissive flame + flickering OmniLight + CalmZone child). `extinguish()` kills flame/light + frees the CalmZone — used by the lights-out event |
| `fake_door.gd` | `FakeDoor` StaticBody3D — locked hotel door panel; interact → door_slam answers from the other side, +8 panic first try only |
| `backrooms.gd` | Level 4 — builds the whole mono-yellow maze procedurally: 4-way hub + N/E/W choice arms (`CSGBox3D` + triplanar wallpaper/carpet), recessed flickering fluorescents, arrow columns, the navigation state machine (`_assign_round` / `_on_arm_entered` / `_wrong_turn` / loop-back teleports), dynamic dark zones, the exit utility room + glitch wall, ambience, and the mirage-door/phone/Smiler spawns. Calls `player.enable_standstill_panic()` + `enable_footstep_echo()` |
| `creature_smiler.gd` | `class_name CreatureSmiler` — the Backrooms darkness entity. Billboard `screamer_smiler.png` at a dark arm's end. Flashlight-on-it or sprint → `Screamer.trigger()`; light off + hold still → fades. Suspends the maze's standstill/dark ticks (`player.set_smiler_active`) and drives its own +2.5/s dread |
| `mirage_door.gd` | `class_name MirageDoor` — blood-red back-door lookalike; `interact()` swings it open onto blank wallpaper + 10 panic. Self-building mesh |
| `rotary_phone.gd` | `class_name RotaryPhone` — rings (`rotary_ring`) on a timer; `interact()` answers → `phone_whisper` + a read-to-die trap note via `NoteUI.show_note(text, 11.0)`. Self-building primitive mesh |

### Level scenes
| Scene | Unlock condition | Notes |
|-------|-----------------|-------|
| `main_menu.tscn` | — | Game entry point; background image (`main_menu_bg.png`), START loads `intro_room.tscn` |
| `intro_room.tscn` | NONE | Player spawn z=+1.5; table centered; ambient 0.15; walls size.y=3.0 |
| `level_1.tscn` | KEYCARD | Player spawn z=−5.5; `_apply_textures()` + `_spawn_note_tables()` in `level_1.gd`; BackDoor at z=−6.05 |
| `level_2_1.tscn` | CODE_ENTERED | Player spawn z=−2.5; LivWallR split for bedroom doorway; DoorwayFloor bridges floor gap; BackDoor at z=−3.05. **Note:** `GameState.SCENE_LEVEL_2` points to `level_2_1.tscn` (not `level_2.tscn`). |
| `corridor.tscn` | NONE (reach the door) | Minimal scene: root + Environment + AmbientPlayer + Player at (0,0,2) facing +z — everything else built by `corridor.gd` in `_ready()`. Exit door 217 at d=320 m; BackDoor at the start returns to The House |
| `backrooms.tscn` | NONE (three down-turns → glitch wall) | Level 4. Minimal scene: root + Environment + AmbientPlayer + Player at (0,0,−5) facing +z — the cyclic maze, lights, arrows, zones, props all built by `backrooms.gd` in `_ready()`. Sets `current_level = 4` |
| `level_3.tscn` | TWIST_READ | The Void (level 5). Player spawn z=−2.0; vignette strength 2.0; BackDoor at z=−3.05; `_spawn_note_tables()` called in `_ready()` (all 8 notes). Sets `current_level = 5` |
| `ending.tscn` | — | Reloads intro_room, credits fade |

## Panic System

`player.gd` maintains a `_panic` float (0–50). It rises while the player gazes at any node whose scene tree contains a `ScaryObject` ancestor, at a rate of `scare_intensity × PANIC_BASE_RATE (20/s)`. **Gaze detection uses `GAZE_RANGE=3.0m`** (wider than `INTERACT_RANGE=2.5m` for doors/notes — the two raycasts are separate). It decays at `PANIC_DECAY_RATE (3.5/s)` — a full bar takes ~14 s to drain idle. Hitting `PANIC_MAX (50)` fires `Screamer.trigger()` and resets panic to 0.

The heartbeat `AudioStreamPlayer` (loaded via `GameState.load_audio("heartbeat")`) adjusts volume and pitch in proportion to max(`_panic / PANIC_MAX`, `_gaze_timer / GAZE_TRIGGER_TIME`).

Visual feedback is provided by `hud_canvas.tscn` (at `game/assets/elements/hud_canvas.tscn`) — a `PanicHUD` node with two shader-driven `ColorRect`s: `BlurRect` and `TintRect`. Driven by `set_panic_ratio(ratio)`.

To make a prop raise panic: the `ScaryObject` must be an **ancestor** of the `StaticBody3D` whose collider the gaze ray hits — `player.gd:_find_scary_object()` walks UP from the hit body. Build it as `ScaryObject (Node) → StaticBody3D → CollisionShape3D (+ mesh)`. Because `ScaryObject extends Node` (no transform) it **breaks the Node3D spatial chain**, so put the world transform on the `StaticBody3D` itself — its non-Node3D parent makes the body's local transform == its global transform. For a *moving* gaze prop (the void creatures), move that inner body, not the outer node. Set `scare_intensity` (default 1.0). ⚠️ Nesting `ScaryObject` *under* the body (the old pattern) silently registers **zero** panic — this was the bug behind the dead corridor/house cursed props and the non-reactive void creatures (fixed 2026-06).

Panic source priority per frame (`_update_panic`): gaze at ScaryObject > sprinting (+6/s) > dark-zone creep (+3/s, flashlight off) > decay. Dread-zone pressure (+1.5/s) is added **on top** regardless of branch.

### Zone & movement modifiers
- `add_panic(amount)` — instant spike from scripted events/traps; fires the screamer at max like gaze panic
- **Sprint** (Shift): ×1.6 speed, +6 panic/s, suppresses decay while held — "Walk. Do not run." is a real rule
- **Calm zones** (torchlight): while inside ≥1 `CalmZone`, decay runs at ×2.5 (`CALM_DECAY_MULT`)
- **Dark zones**: while inside ≥1 `DarkZone` with the flashlight OFF, panic creeps +3/s (`DARK_PANIC_RATE`); gaze panic takes priority over dark-creep
- **Dread zones** (corridor Zone C, Void Rooms C+D): decay weakens to 2/s (`DREAD_DECAY_RATE`) and +2/s (`DREAD_PANIC_RATE`) accrues constantly — net idle rate barely negative
- **Flashlight battery**: 240 s of ON time per scene (player re-instances each level, so it resets); stutters below 48 s, then dies for the rest of the level. ON by default at spawn — a player who never toggles it loses it near the corridor's final dark zone
- `apply_slow(duration)` — beartrap limp, speed ×0.45 (`SLOW_MULTIPLIER`); timers don't stack, longest wins. `cancel_slow()` clears the limp immediately (used by beartrap escape success)
- **Read-to-die trap notes**: `NoteUI` feeds `player.add_panic(TRAP_PANIC_RATE × delta)` while a trap note is open (works during tree pause — NoteUI is `PROCESS_MODE_ALWAYS`)

## Folder Layout
```
horror_game/
├── game/                  ← Godot project root
│   ├── project.godot
│   ├── scenes/            ← .tscn scene files
│   ├── scripts/           ← .gd GDScript files
│   └── assets/
│       ├── audio/         ← .wav/.ogg files (ambient, SFX, music)
│       ├── elements/      ← reusable scene fragments (hud_canvas.tscn, environment.tscn)
│       ├── models/        ← .glb 3D models
│       ├── textures/      ← .png/.jpg texture maps
│       └── materials/     ← .tres Godot material files
├── game/tests/            ← dev tools (screenshot_corridor.gd — SceneTree script that dumps corridor screenshots to /tmp/corridor_shots/)
├── tools/                 ← make_sfx.py (stdlib-only procedural SFX synth → game/assets/audio/)
├── nano-banana-pro/       ← image generation skill (Gemini)
├── .agents/skills/        ← Claude skills
└── .env                   ← API keys (never commit)
```

### Audio import
New `.wav`/`.ogg` files need a Godot import pass before `ResourceLoader` sees them: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import` (or open the editor and let the scan run). Corridor SFX (`clock_chime`, `glass_shatter`, `beartrap_snap`, `door_slam`, `whispers`) are generated by `tools/make_sfx.py` (seeded, reproducible); `ghost_house.wav` is the corridor ambience. House SFX (`lock_buzz`, `footsteps_above`) are generated by `tools/make_sfx_house.py` (same stdlib-only conventions). Backrooms SFX (`fluorescent_hum` looping ambience, `light_pop`, `rotary_ring`, `phone_whisper`) are generated by `tools/make_sfx_backrooms.py` into `game/assets/audio/level_backrooms/`.

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
- **Textures:** PolyHaven / AmbientCG (CC0 PBR) or Stable Diffusion → `game/assets/textures/<subfolder>/` (see TEXTURES.md for the per-level subfolder layout)
- **Audio:** Freesound.org (CC0) or MusicGen (HuggingFace) → export as .ogg → `game/assets/audio/<subfolder>/` (`shared/`, `level_1/`, `level_2/`, `level_3_corridor/`, `level_4_void/`)
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
