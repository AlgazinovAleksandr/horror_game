# INTRO.md — Opening Sequence Redesign

Technical spec for the new game-opening beat: a cold-open jumpscare on **START**, then a
rebuilt Intro Room where Subject 47 wakes in the dark, in a large asylum ward, and must find
a light switch before the room — and the opening note — are revealed. This document is the
implementation brief for whoever builds this (developer instructions) **and** the image
prompts for whoever generates the new textures (you, via nano-banana-pro).

Nothing in this document has been implemented yet. It is the spec to build against.

## 1. Design decisions (resolved via grill-me, 2026-07-21)

| Question | Decision |
|---|---|
| Is the START jumpscare the same event as the "nightmare" reveal? | **Yes.** One scare, reused: cold-open jumpscare = the nightmare itself. Cut to black, then the red text confirms it was a dream. |
| Player's starting pose | **Lying on a gurney/asylum bed.** Camera starts low, auto sit-up tween (~1.8s), then full control. |
| Flashlight before the switch is found | **Locked off.** New reversible `lock_flashlight()`/`unlock_flashlight()` API on `player.gd` — F does a dead click, distinct from the existing permanent `kill_flashlight()`. |
| Room scope | **Single big open asylum ward**, hand-placed `CSGBox3D` (same style as the original `intro_room.tscn`, just scaled up) — not `RoomBuilder` (that's for multi-room graphs, this is one room). |
| Dark navigation | **Faint glow marks the path** — a short row of dim, low-mounted emergency-light points from the gurney toward the switch. Not audio-only, not fully blind. |
| Ending-room consistency | **Out of scope for this pass.** `intro_room.gd:_corrupt_room()` still assumes the OLD 5.6×5.6 room and will look wrong (mis-placed planks/spotlight) against the new geometry. Tracked as a required follow-up — see §7. |
| Jumpscare art | **Bespoke image**, user-generated via the prompt in §5. |
| Dark-walk scare beat | **One small non-fatal jolt** partway to the switch — reuses the same nightmare image as a quick survivable flash, implying the nightmare hasn't fully let go. No panic added (see §4.4 — the intro stays non-failable). |
| Wake-up control | **Automatic** sit-up tween, no player input required to trigger it. |
| Note/door/controls-hint | **Unchanged.** `OPENING_NOTE` text, the blood-red `ExitDoor` convention, and the WASD/E/F/Shift hint stay exactly as they are today. |
| New audio | **Mixed.** Simple, short SFX (switch clunk, fluorescent buzz-on, dead-air hum, gurney creak) generated procedurally by a new `tools/make_sfx_intro.py`, matching the project's existing stdlib-only synth convention. The jumpscare scream and any ambient bed are sourced/found by you — see §6. |

## 2. Beat-by-beat flow

```
Main Menu
   │  press START
   ▼
Cold-open jumpscare (fullscreen, ~0.8s) ── THE NIGHTMARE
   │  cut to black
   ▼
Load intro_room.tscn — total darkness, silence except a faint hum
   │
   ▼
Player lying on a gurney. Auto camera tween: lying → sitting → standing (~1.8s, input frozen)
   │
   ▼
Red scrawled text, center screen: "IT WAS ONLY A DREAM." (ScreenText.scrawl, ~4s)
   │  flashlight is LOCKED — F does a dead click
   ▼
Player has control. Total darkness except 3-4 faint low emergency-glow points
leading toward the switch (the only readable path through the room)
   │
   ├─ ~50-60% of the way: ONE scripted jolt — nightmare image flashes again for
   │  ~0.35s + camera jolt + a clang/scream sting. Survivable, no panic added.
   ▼
Player finds and interacts with the wall switch (E)
   │  switch_clunk SFX
   ▼
Ceiling fluorescents flicker on (fluorescent_buzz_on SFX), path-glow lights fade out,
CandleLight fades in over the note table — the note now visibly "shines"
   │
   ▼
Room fully revealed: big asylum ward, gurney, switch, cabinets, note table
   │  (EXISTING, unchanged from here on)
   ▼
Player reads the note (OPENING_NOTE) → walks to ExitDoor (blood-red, unlock NONE)
   ▼
GameState.advance_level() → Level 1 (The Lab)
```

## 3. File-by-file implementation plan

### 3.1 `game/scripts/main_menu.gd`
- In `_on_start()`: disable `start_btn` (and `quit_btn`, to prevent a stray click) immediately,
  then `await Screamer.flash_scare(NIGHTMARE_IMAGE, "nightmare_scream", 0.8)`, then
  `get_tree().change_scene_to_file(GameState.SCENE_INTRO)`.
- `Screamer` is an autoload, already in the tree at the main menu — `flash_scare()` doesn't
  touch the player (there isn't one yet) so it's safe to call from here directly. No new
  Screamer API needed.
- `flash_scare()`'s internal `await get_tree().create_timer(hold).timeout` means the outer
  `await Screamer.flash_scare(...)` call in `_on_start()` correctly waits for the whole flash
  to finish before the scene change — Godot chains awaits through a called function that
  itself awaits.
- Constant: `const NIGHTMARE_IMAGE := "res://assets/textures/intro/nightmare_face.png"`.

### 3.2 `game/scripts/player.gd` — two small reversible opt-ins
Both default OFF, following the project's existing "Backrooms-only opt-ins" pattern
(`enable_standstill_panic()` etc.) — these are Intro-only, and touching nothing else changes
behavior for any other level.

```gdscript
var _flashlight_locked: bool = false   # reversible; distinct from _flashlight_dead
var _input_frozen: bool = false        # blocks movement + look during the sit-up tween

func lock_flashlight() -> void:
    _flashlight_locked = true
    flashlight.visible = false

func unlock_flashlight() -> void:
    _flashlight_locked = false

func freeze_input() -> void:
    _input_frozen = true

func unfreeze_input() -> void:
    _input_frozen = false
```

- `_unhandled_input`: add `if _input_frozen: return` as the very first line (blocks look,
  interact, and flashlight toggle during the tween — a short forced beat, matches how
  `NoteUI.is_open` is already guarded at the top of the same function).
- In the existing `toggle_flashlight` branch, add `_flashlight_locked` to the same condition
  that currently gates on `_flashlight_dead`, and call `_play_dead_click()` on that path too
  (reuse the existing dead-battery click — the read "nothing happens" is correct either way).
- `_apply_movement()`: add `if _input_frozen: return` as the first line so `velocity.x/z`
  aren't touched while frozen (gravity/`is_on_floor()` still apply as normal, which is fine —
  the player is standing/sitting on the gurney's solid top surface).
- Because `camera.rotation.x` is only ever written inside `_rotate_camera()` (called from
  `_unhandled_input` on mouse motion), freezing input also means `intro_room.gd` can safely
  tween `player.camera.position` / `player.camera.rotation.x` directly during the sit-up beat
  without fighting per-frame code.

### 3.3 New script: `game/scripts/light_switch.gd`
Small self-contained prop, same shape as `key_item.gd` / `breaker.gd`:

```gdscript
extends StaticBody3D
class_name LightSwitch

signal flipped

var _used: bool = false

func interact() -> void:
    if _used:
        return
    _used = true
    flipped.emit()
```

Builds its own mesh in `_ready()` (small wall-mounted plate `BoxMesh` ~0.12×0.2×0.04, dark
metal `StandardMaterial3D`) plus a small emissive quad — the "LED"/lever-glow that acts as the
brightest, final point on the faint-glow path. `intro_room.gd` positions it and connects
`flipped` to `_on_switch_flipped()`.

### 3.4 `game/scripts/intro_room.gd` — rewrite

**Room geometry** (hand-placed `CSGBox3D`, same pattern as the current `.tscn`, scaled up):

| Element | Size | Position (center) |
|---|---|---|
| Floor | `Vector3(12, 0.3, 18)` | `(0, -0.15, 0)` |
| Ceiling | `Vector3(12, 0.3, 18)` | `(0, 3.75, 0)` |
| WallBack (exit side) | `Vector3(12, 3.6, 0.3)` | `(0, 1.8, -9)` |
| WallFront (gurney side) | `Vector3(12, 3.6, 0.3)` | `(0, 1.8, 9)` |
| WallLeft | `Vector3(0.3, 3.6, 18)` | `(-6, 1.8, 0)` |
| WallRight | `Vector3(0.3, 3.6, 18)` | `(6, 1.8, 0)` |

Ceiling height rises from the current 3.0 m to 3.6 m — taller, more institutional, more
Outlast-ward than the old cellar-sized room. Reuse the existing `wall_intro.png` /
`floor_intro.png` / `ceiling_intro.png` (already read as damp, grimy concrete — a good match
for asylum decay) but raise `uv1_scale` from `2.0` to about `4.0` so texel density holds at
the bigger footprint — check in-editor and tune.

**Set pieces:**
- **Gurney** (`CSGBox3D` frame + thin mattress box), near `WallFront`, at roughly `(0, *, 7.0)`.
  Player spawns here, lying down.
- **Note table + Note + CandleLight** — keep exactly as they are today, just relocated near
  `WallBack`/the exit, e.g. table at `(0, 0.4, -7.6)`, so reaching them means crossing the
  whole room after the lights come on.
- **ExitDoor** — same script/material convention, centered on `WallBack`, e.g.
  `(0, 1.1, -8.5)`.
- **LightSwitch** — mounted on `WallLeft`, off to the side rather than straight ahead, e.g.
  `(-5.6, 1.3, -1.0)`. Putting it off-axis (not a straight line from the gurney) is
  deliberate — the path-glow points (below) are what make it findable, not room geometry.
- **2-3 rusted cabinets / a medical cart** along the side walls (`CSGBox3D` primitives, dark
  metal material) — background dressing only, no interaction, no new texture required.

⚠️ Per the project-wide CSG rule in `CLAUDE.md` — run `tests/check_wall_overlap.gd` against
this scene once built. A single hand-placed room is low-risk for the coincident-surface bug
class, but the rule still applies to any prop box placed flush against a wall panel.

**Darkness / reveal sequencing** — `_ready()`:
1. `GameState.current_level = 0` (unchanged).
2. Set all room lights to zero: no `CandleLight` energy, no ceiling fixtures lit. The shared
   `Environment` needs its ambient near-zero for this scene specifically — duplicate it as
   `level_1.gd`'s `_boost_ambient()` already does for a *different* direction (that one raises
   ambient; here it should be lowered close to 0 for the opening beat, then raised back to the
   scene's normal ambient once the switch flips).
3. `player.lock_flashlight()`, `player.freeze_input()`.
4. Position `player` at the gurney; tween `player.camera.position.y` from a lying height
   (~1.0) to standing (1.65) and `player.camera.rotation.x` from a slight upward tilt (~-0.25
   rad) to 0, over ~1.8s. On tween finish: `player.unfreeze_input()`.
5. `ScreenText.scrawl(get_tree(), "IT WAS ONLY A DREAM.", 4.0)` — reuses the existing blood-red
   scrawl helper (`screen_text.gd`), which already reads as "the game speaking to the player"
   rather than in-fiction text — correct register for this line.
6. Spawn 3-4 low-energy `OmniLight3D` "path glow" points (see constants below) tracing a rough
   line from the gurney toward the switch.
7. Spawn one `CorridorEvent` (reused as-is from `corridor_event.gd` — it's generic, not
   corridor-specific) around the 55% mark of that path. Connect `fired` →
   `Screamer.flash_scare(NIGHTMARE_IMAGE, "nightmare_scream", 0.35)` + `player.jolt_camera(0.08,
   0.4)`. Deliberately **no `add_panic()` call** — the intro has never had a fail state and
   this pass shouldn't add one; the beat is pure atmosphere.
8. Instantiate `LightSwitch`, position it, connect `flipped` → `_on_switch_flipped()`.

`_on_switch_flipped()`:
1. Play `switch_clunk` (via `GameState.load_audio` + a one-shot `AudioStreamPlayer3D` at the
   switch position).
2. `player.unlock_flashlight()`.
3. Fade out the path-glow lights (short tween to energy 0, then `queue_free`).
4. Tween the ceiling fixtures and `CandleLight` up to their normal energy, with a brief
   flicker-up stutter on the ceiling lights (reuse the sine-based flicker approach already in
   `_process()` for `CandleLight`, or the "lamps stutter up" beat pattern from
   `level_1.gd:_restore_power()`) + play `fluorescent_buzz_on`.
5. Tween the scene's (duplicated) `Environment` ambient back up to its normal intro-room value.
6. Everything from here down is **unchanged existing behavior**: `_show_controls_hint()`,
   note interaction, `ExitDoor`.

`_corrupt_room()` (the twist-ending path) is **not touched in this pass** — see §7.

### 3.5 `game/scenes/intro_room.tscn`
Given the scope of the geometry change, it's cleaner to rebuild this scene's non-player nodes
at runtime the way `level_1.tscn`/`level_2_1.tscn`/`kontur.tscn` already do, rather than
hand-editing dozens of `CSGBox3D` transforms in the `.tscn` text. Recommendation: trim the
`.tscn` down to `IntroRoom (root, script) / Environment / Player`, and have `intro_room.gd`
build the room, gurney, table/note/candle, switch, and door in `_ready()` — same
`.tscn`-minimal pattern already documented in `CLAUDE.md` for Levels 1/2/5, just without
`RoomBuilder` (one room, no doorway graph needed). This also sidesteps hand-computing wall
transforms for the bigger footprint by mistake (the exact class of bug `wall_point()` exists
to prevent elsewhere — here there's no `RoomBuilder` room graph, so the discipline is just:
compute each wall center from the room's `SIZE_X`/`SIZE_Z`/`HEIGHT` constants, never a literal).

## 4. Constants to add (`intro_room.gd`)

```gdscript
const ROOM_SIZE := Vector2(12.0, 18.0)
const ROOM_HEIGHT := 3.6
const WAKEUP_TWEEN_TIME := 1.8
const NIGHTMARE_TEXT := "IT WAS ONLY A DREAM."
const NIGHTMARE_IMAGE := "res://assets/textures/intro/nightmare_face.png"
const PATH_GLOW_ENERGY := 0.12      # OmniLight3D, ankle-height waypoints
const PATH_GLOW_RANGE := 1.4
const FUMBLE_JOLT_PROGRESS := 0.55  # fraction of gurney->switch distance
```

## 5. Image assets — generate with nano-banana-pro

Output path convention matches the existing `intro/` folder. Run:
```
nano-banana-pro/.venv/bin/python3 nano-banana-pro/generate_image.py "<prompt>" -o game/assets/textures/intro/<file>.png
sips -s format png game/assets/textures/intro/<file>.png --out game/assets/textures/intro/<file>.png
```
(the `sips` conversion step is mandatory — see `CLAUDE.md` / `ISSUES_SOLUTIONS.md` Issue 1;
skip it and the texture silently fails to import).

| file_name | prompt | where_used | status |
|---|---|---|---|
| `intro/nightmare_face.png` | "Extreme close-up horror jumpscare — a gaunt, pale, distorted human face lunging at camera out of total darkness, mouth open mid-scream, eyes black hollow sockets, skin stretched and wrong, harsh single-source underlighting, photographic horror-film still, no text, fullscreen 16:9" | The cold-open jumpscare on START (`main_menu.gd`) **and** the mid-fumble survivable flash (`intro_room.gd`, reused deliberately — same nightmare glimpsed twice) | to_be_added |

That's the only **required** new image for this pass — the existing `wall_intro.png`,
`floor_intro.png`, `ceiling_intro.png` are reused as-is (already read as damp asylum concrete;
see the CLAUDE.md gate on not trusting a clean screenshot — check them in-editor at the new
`uv1_scale` before deciding they're sufficient). Two more are optional polish, not required to
ship the beat:

| file_name | prompt | where_used | status |
|---|---|---|---|
| `intro/gurney_intro.png` *(optional)* | "Old rusted hospital gurney mattress, top-down flat elevation — stained grey-white vinyl, torn corners, dark water stains, one leather restraint strap hanging loose, cold clinical lighting, seamless-ish texture for a game prop" | Gurney mattress top face, if the bare `StandardMaterial3D` grey reads too flat in-editor | to_be_added |
| `intro/cabinet_intro.png` *(optional)* | "Rusted metal medical cabinet, front elevation — dented steel doors, peeling asylum-green paint, small wire-glass window, grime streaks, dim institutional lighting" | Background dressing cabinets along the side walls, if plain tinted boxes read too bare | to_be_added |

Add the required row (and any optional ones you generate) to `TEXTURES.md` under `intro/`
once done, per the existing registry convention.

## 6. Audio assets

**Generated procedurally** (new `tools/make_sfx_intro.py`, stdlib-only `wave`/`math`/`random`,
same `write_wav`/`OnePole` conventions as `tools/make_sfx_extra.py` — copy that file's helpers
rather than re-deriving them) → `game/assets/audio/intro/`:

| file | description |
|---|---|
| `switch_clunk.wav` | Heavy old wall-switch/breaker throw — low mechanical clunk + a short spark crackle tail. Can start from `make_sfx_extra.py`'s `make_breaker_throw()` and detune/lengthen it so it doesn't read as an exact duplicate of the Lab's `breaker_throw.wav`. |
| `fluorescent_buzz_on.wav` | Fluorescent tube flicker-up: 2-3 short buzzy stutters (noise burst through a narrow band-pass, like the existing `tv_static`/`pipe_groan` synths) rising to a steady hum tail, ~1.2s. |
| `emergency_hum.wav` | Very quiet, low-frequency electrical hum loop (sine + slight noise, <200 Hz) for the path-glow lights — barely audible, sits under everything during the blind fumble. |
| `gurney_creak.wav` | Short metal-on-metal creak/groan, ~0.6s, plays once as the sit-up tween starts. |

**Sourced by you** (found audio — music-grade or scream-grade content, outside the procedural
synth's reach) → `game/assets/audio/intro/`:

| file | description | fallback if not yet present |
|---|---|---|
| `nightmare_scream.ogg` (or `.wav`/`.mp3`) | The cold-open jumpscare scream — sharp, loud, ideally distinct from `all_levels_screamer.mp3` (that's the game's actual-death sting; reusing it here would teach the player to associate the "real" death sound with something survivable, which undercuts it everywhere else) | Code should guard with `GameState.load_audio("nightmare_scream")` and fall back to the existing `jumpscare.wav` in `shared/` if the new file isn't present yet, so the beat is playable before you've sourced anything |
| `ambient_asylum.ogg` *(optional)* | A continuous low dread bed for the room once lit — distant institutional ambience | Reuse the existing `shared/whispers` (already used by the corrupted ending) at low volume, or skip entirely — the room has no ambient bed today and that's an acceptable starting point |

`GameState.AUDIO_SUBDIRS` needs `"intro"` added to its list so `load_audio()` finds the new
folder — currently it only searches `shared`, `level_1_lab`, `level_2_house`,
`level_3_corridor`, `level_backrooms`, `level_5_kontur`, `level_4_void`.

## 7. Explicitly out of scope for this pass

`intro_room.gd:_corrupt_room()` (the twist-ending corruption of this same scene) hard-codes
plank positions, the red light position, and the spotlight position against the *current*
5.6×5.6 m room. Once this redesign ships, the ending will load into the new 12×18 m room and
the corruption dressing will be wrong (planks floating in open space, spotlight missing the
table). This was a deliberate scope call — **do not fix it as a drive-by in this pass**; it
needs its own short follow-up once the new room's final dimensions are locked, so the
plank/light/spotlight positions can be recomputed against the real geometry rather than
guessed ahead of time.

## 8. Verification checklist

- [ ] `/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import` after
      adding new textures/audio.
- [ ] `tests/check_wall_overlap.gd` against `intro_room.tscn` (per the project-wide CSG rule).
- [ ] In-editor playtest: confirm total darkness reads as navigable-but-tense with only the
      path-glow points lit — this is a judgment call that needs eyes-on tuning
      (`PATH_GLOW_ENERGY`/`PATH_GLOW_RANGE`), not something to get right on paper.
- [ ] Confirm F does a dead click (not silence, not a real toggle) before the switch is found.
- [ ] Confirm the mid-fumble jolt fires once, doesn't re-trigger, and doesn't touch the panic
      bar (the intro must stay non-failable, matching every other design note about this room).
- [ ] Confirm `GameState.load_audio("nightmare_scream")` falls back cleanly to `jumpscare.wav`
      if the sourced file isn't present yet.
