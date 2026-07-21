# Issues & Solutions

Hard-to-diagnose bugs encountered during development. Each entry: **Symptom → Root Cause → Fix → Files Changed**.

---

## Issue 1 — Textures invisible in-game (nano-banana-pro outputs JPEG as .png)

**Symptom:** Wall and floor textures are missing in-game despite PNG files existing in `game/assets/textures/`. `_apply_textures()` exits early. In `.godot/imported/` only `.md5` files are created — no `.ctex`.

**Root cause:** The Gemini API (used by nano-banana-pro) returns JPEG-encoded image data even when the output filename ends in `.png`. Godot's PNG importer rejects the file silently: the `.import` file is written with `valid=false` and no `path=` entry, so `ResourceLoader.exists()` returns `false` and `load()` fails.

**Diagnosis:**
```bash
# First 4 bytes of a valid PNG are: 89 50 4e 47
python3 -c "
with open('game/assets/textures/wall_lab.png', 'rb') as f:
    print(f.read(4).hex())
# ffd8ffe0 = JPEG. 89504e47 = PNG.
"
```

**Fix:**
```bash
# Convert in-place (macOS built-in, no deps)
sips -s format png path/to/file.png --out path/to/file.png

# Batch convert all textures after a generation session
for f in game/assets/textures/*.png; do sips -s format png "$f" --out "$f"; done

# Then delete stale .import files and reload project in Godot editor
rm game/assets/textures/*.import
# Project → Reload Current Project
```

**Godot import success check:** `.godot/imported/` must contain both `.md5` AND `.ctex` for each texture. Only `.md5` = import failed.

**Files changed:** `CLAUDE.md`, `README.md`, `MEMORY.md` (documentation); no code changes needed.

---

## Issue 2 — "Press E" prompt never appears near notes (notes lying flat)

**Symptom:** Walking up to a note shows no interaction prompt. The door works but notes are completely unresponsive. No errors in output.

**Root cause:** Notes were placed with identity rotation (flat, lying on table surface at y ≈ 0.8m). The player camera sits at y = 1.65m and the raycast fires horizontally. A horizontal ray at y = 1.65 never intersects a flat object at y = 0.8 — the ray passes entirely over it. The exit door works because it is 2.2m tall and the ray hits it at mid-height.

**Fix:** Rotate all notes upright (-90° on X axis) and raise their centre to y = 1.2m so they stand like a paper pinned to a board. Enlarge the collision box to `Vector3(0.35, 0.35, 0.8)` — after the -90° X rotation, the local Z dimension maps to world Y, giving the note 0.8m of vertical hit area centred at y = 1.2 (spans y = 0.8 – 1.6).

**Transform for an upright note facing +Z (toward player approaching from corridor):**
```
Transform3D(1, 0, 0,  0, 0, -1,  0, 1, 0,  x, 1.2, z)
```

**Code fix in `note.gd` `_enlarge_collision()`:**
```gdscript
box.size = Vector3(0.35, 0.35, 0.8)  # was (0.21, 0.005, 0.297) — the original mesh size
```

**Files changed:** `game/scripts/note.gd`, all `.tscn` files containing Note nodes.

---

## Issue 3 — Note overlay opens and immediately closes (E key double-fires)

**Symptom:** Pressing E near a note causes the overlay to flash for one frame then disappear, or nothing visible happens at all. Mouse cursor briefly releases then recaptures.

**Root cause:** In Godot 4, `_unhandled_input` dispatches to nodes in scene-tree order. For the same E keypress:
1. `Player._unhandled_input` fires → `is_open=false` → calls `_try_interact()` → note opens → `is_open=true`
2. `NoteUI._unhandled_input` fires (same frame, same event) → `is_open=true` and `event.is_action_pressed("interact")` → closes the note

Net result: note opens and closes within a single frame.

**Fix (two-layer defence):**

**Layer 1 — `game/scripts/player.gd`:** Mark the event as handled immediately after `_try_interact()` so NoteUI never sees the same keypress:
```gdscript
if event.is_action_pressed("interact"):
    _try_interact()
    get_viewport().set_input_as_handled()  # added
```

**Layer 2 — `game/scripts/note_ui.gd`:** Add `_block_close` bool that is `true` during the frame `show_note()` is called, reset to `false` on the next frame via `set_deferred`:
```gdscript
var _block_close: bool = false

func show_note(text: String) -> void:
    ...
    is_open = true
    _block_close = true
    ...
    set_deferred("_block_close", false)  # unblocks next frame

func _unhandled_input(event: InputEvent) -> void:
    if is_open and not _block_close and (...):
        _close()
```

**Files changed:** `game/scripts/player.gd`, `game/scripts/note_ui.gd`.

---

## Issue 5 — Level 2 bedroom inaccessible; player falls into void at room boundary

**Symptom:** Walking rightward through the living room the player hits an invisible wall and cannot reach the bedroom. `NoteC` (containing the third lock digit) is unreachable — the level is unbeatable. At the boundary between living room and bedroom, falling through the floor into the void is also possible.

**Root cause (two separate geometry errors):**

1. `LivWallR` was a single CSGBox3D spanning the full z-extent of the living room (z: 3.0 – 8.0, size.z=5.0). There was no doorway cut into it — no opening to the bedroom existed at all.

2. `LivFloor` ends at x=4.5 (centre 2.0, size.x=5.0 → right edge at 4.5). `BedFloor` starts at x=5.5 (centre 7.5, size.x=4.0 → left edge at 5.5). The 1.0m strip between x=4.5 and x=5.5 had no floor geometry — players walking through the new doorway immediately fell through.

**Fix:**

Split `LivWallR` into two segments with a 1.3m gap:
```
LivWallR_A: pos=(4.65, 1.35, 3.95), size=(0.3, 3.0, 1.9)  # spans z=3.0–4.85
LivWallR_B: pos=(4.65, 1.35, 7.05), size=(0.3, 3.0, 1.9)  # spans z=6.15–8.0
```

Add `DoorwayFloor` to bridge the floor gap:
```
DoorwayFloor: pos=(5.0, -0.15, 5.5), size=(1.0, 0.3, 5.0)
```

**Files changed:** `game/scenes/level_2.tscn`.

---

## Issue 6 — "Keycard collected" label never disappears

**Symptom:** After picking up the keycard in Level 1, the green "Keycard collected" label stays on screen permanently, overlaying all subsequent gameplay.

**Root cause:** `keycard.gd.interact()` calls `_show_feedback()` (not awaited), then awaits the pickup audio. When audio finishes, `queue_free()` is called on the Keycard node. This destroys the node and cancels all pending coroutines on it — including the `await get_tree().create_timer(2.0).timeout` inside `_show_feedback()`. Since that await is cancelled, `canvas.queue_free()` never runs. The `CanvasLayer` (and its Label child) was added to `get_tree().root`, not to the keycard node, so it survives the node's destruction — orphaned and permanent.

**Fix:** Replace the `await`-based timer with a signal connection. Signal connections are not cancelled when the source node is freed:
```gdscript
# Before (broken — await is cancelled when node is freed):
await get_tree().create_timer(2.0).timeout
canvas.queue_free()

# After (correct — signal fires regardless of source node state):
get_tree().create_timer(2.0).timeout.connect(canvas.queue_free)
```

**Files changed:** `game/scripts/keycard.gd`.

---

## Issue 7 — Double screamer on rapid E press

**Symptom:** Triggering a trap note and immediately pressing E again (or if input auto-repeats) causes the screamer to play twice. After the second screamer finishes, the scene reloads twice in quick succession — sometimes loading the wrong scene or crashing the scene tree.

**Root cause:** `Screamer.trigger()` is a coroutine (`await get_tree().create_timer(...)`). Calling it twice before the first `await` resolves creates two concurrent coroutine instances on the same autoload node. Both complete independently and both call `GameState.restart_current_level()`.

**Fix:** Add `_is_triggering: bool = false` to `screamer.gd`. Both `trigger()` and `trigger_to_menu()` return immediately if `_is_triggering` is `true`. Set it `true` on entry; reset to `false` just before the scene change call.

```gdscript
var _is_triggering: bool = false

func trigger() -> void:
    if _is_triggering:
        return
    _is_triggering = true
    # ... flash, screamer image, audio await ...
    _is_triggering = false
    GameState.restart_current_level()
```

**Files changed:** `game/scripts/screamer.gd`.

---

## Issue 4 — Note overlay invisible despite interaction working (NoteUI layout off-screen)

**Symptom:** Pressing E near a note freezes the player (game tree pauses) and releases the mouse cursor, but no dark overlay or text is visible. The note IS opening — but the UI panel renders off-screen.

**Root cause:** `PanelContainer` used `PRESET_CENTER` — which in Godot 4 anchors the **top-left corner** of the control to the screen centre, not the centre of the control itself. The panel rendered in the bottom-right quadrant, partially or fully off-screen.

**Fix:** Build the layout correctly in `note_ui.gd`:
1. `Control` root node — `PRESET_FULL_RECT` (fills the CanvasLayer)
2. `ColorRect` child — `PRESET_FULL_RECT`, semi-transparent black backdrop
3. `CenterContainer` sibling — `PRESET_FULL_RECT`, auto-centres its child using the layout engine
4. `PanelContainer` child of CenterContainer — `custom_minimum_size = Vector2(680, 480)`, will be centred by the container

```gdscript
var center := CenterContainer.new()
center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
_root.add_child(center)

var panel := PanelContainer.new()
panel.custom_minimum_size = Vector2(680, 480)
center.add_child(panel)  # CenterContainer handles centering
```

**Files changed:** `game/scripts/note_ui.gd`.

---

## Issue 8 — Scene-load parse errors / broken materials after texture folder reorganisation

**Symptom:** Headless scene runs print `Parse Error: [ext_resource] referenced non-existent resource at: res://assets/textures/wall_house.png` and `Failed loading resource: .../wall_2.tres`. In-game the breakage is **masked** in Levels 1–2 because `_apply_textures()` overrides CSG materials at runtime — so the scenes look fine while every editor-assigned `.tres` material silently fails to load. The intro room (which relies on scene materials) shows untextured surfaces.

**Root cause:** Textures were reorganised from flat `assets/textures/*.png` into per-level subfolders (`level_2_house/house_wall.png` etc.), and renamed in the process (`wall_house` → `house_wall`). The `.tres` materials in `assets/materials/level_layout/` and `assets/materials/objects/` kept their old `ext_resource` paths **and** stale UIDs. Godot first tries the UID; when that misses it falls back to the text path — which also no longer exists. 13 material files were affected (`wall_1/2/3`, `floor_1/2`, `roof_1/2`, `*_intro`, `objects/table.tres`, `objects/note.tres`, `objects/trap_note.tres`).

**Diagnosis:**
```bash
# Run any scene headless and grep for parse errors:
Godot --headless --path game res://scenes/level_2_1.tscn --quit-after 30 2>&1 | grep -i error
# List every texture path referenced by materials and check each exists:
grep -H 'path="res://' game/assets/materials/*/*.tres | grep png
```

**Fix:** Update both the `path` **and** the `uid` in each `.tres` `ext_resource` line. The correct UID for a texture is in its `.png.import` file (`uid="uid://..."` on the first line). Fixing only the path leaves a stale-UID warning on every load; fixing only the UID is not possible by hand-editing reliably. Then run a headless `--import` pass.

**Lesson:** when moving/renaming textures, grep `assets/materials/` for references before committing. Runtime `_apply_textures()` masking means a broken material can hide for multiple sessions.

**Files changed:** all 10 `.tres` in `game/assets/materials/level_layout/`, 3 `.tres` in `game/assets/materials/objects/`.

---

## Issue 9 — Pause-built UI survives a screamer that fires while it is open

**Symptom:** (Latent until trap notes became read-to-die.) If `Screamer.trigger()` fires while the note overlay or the combination-lock UI is open — e.g. the panic bar maxes out *while reading a trap note*, or after enough wrong lock codes — the scene reloads with the old overlay still on screen and `NoteUI.is_open` still `true`, blocking all interaction in the freshly loaded level.

**Root cause:** `NoteUI.show_note()` and `combination_lock.interact()` pause the tree and set their own open flags. `Screamer.trigger()` unpauses the tree and reloads the scene, but knows nothing about whichever UI initiated the pause. `NoteUI` is an autoload (survives the reload) holding `is_open = true`; the lock's `CanvasLayer` belongs to the old scene but its panel is visible during the screamer sequence.

**Fix — a tree-pause invariant instead of per-caller cleanup:** both UIs poll in `_process()` (they run during pause via `PROCESS_MODE_ALWAYS`): *if my UI is open but the tree is not paused, a screamer must have fired — drop the overlay silently* (hide panel, clear flags, do **not** re-capture the mouse or emit `closed`).

```gdscript
func _process(_delta: float) -> void:
    if is_open and not get_tree().paused:
        _root.visible = false
        is_open = false  # screamer owns the tree now
```

This covers every present and future "screamer during paused UI" path without coupling `screamer.gd` to any UI. Same family as Issue 7's lesson: own the guard inside the affected system, not at the call sites.

**Files changed:** `game/scripts/note_ui.gd`, `game/scripts/combination_lock.gd`.

---

## Issue 10 — Cursed props build zero gaze panic; a plain `Node` breaks the transform chain

**Symptom:** Two separate-looking failures, one root cause. (a) Several "cursed" props — the House paintings/mirror, the corridor paintings, clock and side-mirrors — never raised the panic bar no matter how long you stared. (b) The Void's stalking creatures didn't react to being looked at, and their gaze collider behaved as if it were stuck at the world origin. No errors in either case.

**Root cause (two layers):**

1. **Detection only walks *up*.** Gaze panic is found by `player.gd:_find_scary_object()`, which walks the parent chain **upward** from the ray-hit collider looking for a `ScaryObject` ancestor. The dead props were built with the `ScaryObject` nested *below* the `StaticBody3D` (`StaticBody3D → ScaryObject → …`), so the upward walk passed straight over it and found nothing. A `ScaryObject` that is a **child** of the hit body is never detected.

2. **`ScaryObject extends Node`, not `Node3D` — so it severs the spatial chain.** Once the nesting was inverted to `ScaryObject → StaticBody3D → collider`, a subtler bug surfaced: `ScaryObject` is a plain `Node` with no transform. In Godot, a `Node3D` whose parent is **not** a `Node3D` gets `get_parent_node_3d() == null`, so its **local transform is used as its global transform** — the non-spatial parent is treated as the world root. Any position you set on the outer `ScaryObject` (you can't — it has no `position`) or expect to inherit is silently dropped; the body sits wherever its *own* local transform puts it (the origin, if unset).

**Diagnosis:** A throwaway test confirmed layer 2 empirically — a `StaticBody3D` under a `ScaryObject` under a positioned `Node3D` reported `global_position == (0,0,0)` regardless of where the `Node3D` ancestor was placed.

**Fix:** Build cursed props as `ScaryObject (Node) → StaticBody3D → CollisionShape3D (+ mesh)`, and **put the world transform on the `StaticBody3D` itself** (its non-spatial parent makes local == global). For a *moving* gaze prop (the Void creatures) seed `_body.global_transform = global_transform` in `_ready()` and then move the **inner body**, not the outer node.

```gdscript
var scary := ScaryObject.new()
scary.scare_intensity = intensity
add_child(scary)
var body := StaticBody3D.new()
body.position = pos          # world transform lives here, not on `scary`
scary.add_child(body)
body.add_child(col)          # collider + mesh under the body
```

**Lesson:** `_find_scary_object` walks **up**, so a `ScaryObject` must be an *ancestor* of the collider, never a child — and because it's a plain `Node`, the body it parents owns its own world transform. Both halves are documented in CLAUDE.md's Panic System section.

**Files changed:** `game/scripts/level_2.gd` (`_make_cursed_body`), `game/scripts/corridor.gd` (`_make_cursed_panel_at`), `game/scripts/creature_stalker.gd`.

---

## Issue 11 — Wall panels invisible: `wall_point()` inset buries them inside the wall

**Symptom.** A `_make_cursed_panel()` / decal quad placed with
`_builder.wall_point(room, side, y, 0.06)` renders as *nothing at all*. The node exists, `visible`
is true, the texture imports fine and has a valid `.ctex`. The wall is simply bare.

**Diagnosis.** `RoomBuilder.wall_point()` measures from the room's **nominal boundary**, not from
the wall's **inner face**. Walls are `T = 0.2` thick and centred on the boundary, so the inner face
sits `0.1` inside the room. Any inset below `0.1` places the panel *within the wall solid*, where
the wall's inner surface occludes it.

Concretely, for Observation (centre z=17, depth 5 → boundary z=19.5):
```
wall inner face   z = 19.400
inset 0.06  ->    z = 19.440   BURIED (0.04 behind the face)
inset 0.16  ->    z = 19.340   visible, 0.06 proud
```

**Fix.** Use an inset **greater than half the wall thickness** — `0.16` gives a clean 0.06 clearance.

**Gotcha when diagnosing this.** A raycast toward the panel will report the panel's *own* collider
as the first hit — `_make_cursed_panel` gives it a 0.1 m-deep `BoxShape3D`. Exclude the panel's own
body (`rq.exclude = [body.get_rid()]`) or you will measure the panel against itself and conclude
nothing is wrong. `tests/check_lab_hint.gd` does this and asserts on it.

**Also fixed by this.** The Records room warning sign (`lab_warning_sign.png`, inset 0.06) had the
same bug and had *never actually been visible in game*.

---

## Issue 12 — The player belonged to no group, so group-based lookups silently did nothing

**Symptom.** Any prop that resolves the player via `is_in_group("player")` never fires. Area3D
triggers appear dead.

**Diagnosis.** `add_to_group` appeared **nowhere** in the project. `living_mirror.gd` documents and
uses a "falls back to group `player`" path — that fallback had always been dead code. Everything
else reached the player through `get_node("../Player")`, which only works for nodes parented
directly to the level root.

**Fix.** `player.gd:_ready()` now calls `add_to_group("player")`.

**Why it matters going forward.** `CreatureSmiler` and `FakeDoor` still use `"../Player"` and so
must remain **direct children of the level root** — they break if parented under a zone/builder
node. New props should prefer the group lookup.

---

## Issue 13 — Walking through an "outed" glitch wall drops the player out of the world

**Symptom.** In the Backrooms Sprawl (zone 2), the player walks into a wall they have already
touched once and falls forever. Logged in playtest at `(200.69, -6.30, 21.78)` — local
`(0.69, 21.78)`, i.e. past the north perimeter.

**Diagnosis.** `GlitchWall.go_solid()` marked the wall solid, swapped its material and freed the
walk-into trigger `Area3D` — but **never added a collider**. The zone's perimeter has a deliberate
7 m gap at each wall (that is what makes the wall walk-through-able), and there is no floor beyond
the shell. So an outed wall was a 7 m hole into the void that merely *looked* solid.

Flag-level tests could not see this: `is_solid()` returned true and the visuals were correct. Only
a physics query reveals it.

**Fix.**
1. `go_solid()` now builds a `StaticBody3D` + `BoxShape3D` sized from the wall's trigger extents;
   `revive()` frees it again.
2. `backrooms.gd:_catch_out_of_world()` (called each frame) returns the player to the current
   zone's spawn if `global_position.y < -5`. This is a **bug backstop, not a designed death** — no
   panic, no screamer — so any future geometry gap degrades into a hiccup rather than a soft-lock.

**Regression test.** `tests/walk_backrooms.gd:_solid_walls_block()` outs every wall, then casts a
ray outward through each one and asserts it is stopped. Verified to genuinely fail (4 leaks) with
the fix disabled.

**General lesson.** For procedural geometry, assert with **physics queries**, not object state. The
whole class of "looks right, isn't solid" bugs is invisible to flag checks. The drop probes in the
same test only sampled the hall interior and never the perimeter gaps, which is why they passed.

---

## Issue 14 — A yaw of PI on a wall-mounted trigger swings it behind the wall (unwinnable Flood)

**Symptom.** The Backrooms zone 3 (The Flood) could not be completed. The real seam in the Sump
rendered correctly, inverted with the flashlight exactly as designed, and did nothing when walked
into. The only seam in the zone that responded to the player was a decoy.

**Cause.** `GlitchWall.setup()` places its walk-into `Area3D` at local `(0, 0, -0.9)` — in front of
the surface. `backrooms_zone3.gd` set `rotation.y = PI` on all three seams, reading as "turn it to
face the room". That yaw also rotates the trigger, moving it to world `+Z`: through the room's north
wall and into solid geometry. Measured trigger position was `z = 25.75` against a wall face at
`z = 25.10`.

`backrooms_zone2.gd` has the correct convention and a comment stating it —
`rotation.y = atan2(axis.x, axis.z)` with `axis` pointing **outward** from the room centre, which is
**0** for a north wall, not PI. Zone 3 didn't follow it.

**Fix.** `NORTH_YAW := 0.0` for all three Flood seams. Separately, the Basin decoy was centred on the
Basin's north wall, which carries the Throat doorway — a 3.6 m trigger there scored a mistake for
merely walking down the corridor. Offset it +4 m in x, clear of the opening.

**Why every existing test passed.** `tests/walk_backrooms.gd` drove progression through
`cleared.emit()` and `_on_seam_touched()` directly. The wiring was never broken; the geometry was.
The suite now has `_seams_reachable()`, which raycasts toward each trigger from the side the player
approaches from and fails if a wall intervenes. `tests/flood_reach.gd` is the standalone probe.

**General lesson (a second helping of Issue 13's).** When a node bundles a *visual* and a
*trigger volume*, a transform meant for one silently applies to the other. Assert the trigger's
world position, not the mesh's appearance — and never let a test reach the win condition by calling
the signal.

---

## Issue 15 — Death doesn't stop the player; panic keeps accruing behind the screamer

**Symptom.** KONTUR playtest log, immediately after a death: panic resets to 0 as expected, then
climbs `5% → 23% → 41% → 59% → 78%` over the next two seconds, at a fixed position, before the
level reloads. The player was dead, the black panel was up, and the bar was still filling.

**Cause.** `Screamer.trigger()` does `get_tree().paused = false` and never pauses anything. For the
whole `RESTART_DELAY` the player node keeps processing: movement, the gaze raycast, and
`_update_panic`. The corpse was still staring at the Perëkozhnik at 16 panic/s.

**Why not just pause the tree.** `NoteUI` pauses while a note is open and detects the *unpause* to
drop its overlay — that unpause is exactly what tells it a screamer fired. Pausing in `trigger()`
would strand a trap note on screen through the death sequence.

**Fix.** `Screamer._freeze_player()` — sets `process_mode = PROCESS_MODE_DISABLED` on the node in
the `"player"` group, called from both `trigger()` and `trigger_to_menu()`. The node is freed by the
reload moments later, so this only has to hold for `RESTART_DELAY`. Depends on Issue 12's fix
(the player was in no group at all until then).

**Also fixed alongside (instrumentation).** `debug_log.gd` detects death by the panic *collapse*, so
a restart — which reloads the SAME scene, leaving `scene_file_path` unchanged — logged every death
twice: once for the real collapse, once when the fresh player's zero panic was compared against the
dead player's last reading. It now rebases `_last_panic` on whoever just spawned. A level
*advance* on high panic was miscounted the same way; guarded with `_scene_changed`.

**General lesson.** "Fires a screamer" is not the same as "the run is over". Any state the player
can still accumulate between the trigger and the reload is live state — check what keeps ticking.

---

## Issue 16 — A level whose puzzles gate nothing (KONTUR's exit had no unlock condition)

**Symptom.** KONTUR was measured clearing in **32 seconds** across two playtests, and felt "too
simple". It was not a pacing problem.

**Cause.** `kontur.gd:_spawn_level_doors()` built the exit with `_make_door("ExitDoor", true, false)`
and never set `unlock_condition`, so it defaulted to `UnlockCondition.NONE` (`door.gd`), which
`_is_unlocked()` answers `true` for unconditionally. The player could walk Landing → Terminus having
failed or ignored all four gates. The gates cost panic and nothing else — they were decoration.

**Why nobody noticed.** Every gate *worked*: each fired its strike, logged its message, and cost its
18 panic. Testing confirmed the gates behaved correctly and never asked the separate question of
whether they were *load-bearing*.

**Fix.** `door.gd` gained `@export var extra_lock: bool` (checked first in `_is_unlocked()`) and
`@export var locked_message: String`. `kontur.gd` keeps a `_gates` ledger of all eight gates and
`_refresh_exit()` holds the door until every one is passed. `walk_kontur.gd` now asserts the door
refuses to open with gates outstanding — and that check was verified to fail when the lock is removed.

**General lesson.** "Does the mechanic work?" and "does the mechanic matter?" are different tests.
For any puzzle, assert that **failing it changes the outcome**, not just that it fires.

---

## Issue 17 — Godot renames colliding sibling nodes using the CLASS name, so name lookups silently miss

**Symptom.** KONTUR's wrong door was supposed to open onto a hole. A build-time guard reported
`the void behind the red door is incomplete (freed 1 of 2)` — the room floor was removed but the
doorway floor bridge was not, leaving a 0.4 m gap the player steps straight over.

**Cause.** `RoomBuilder._box()` names every doorway bridge `"DoorFloor"`. When `add_child()` hits a
name collision, Godot 4 renames the newcomer using the **class** name, not the requested one:

```
DoorFloor          pos=(0, -0.1, 4)      <- only the FIRST keeps the name
@CSGBox3D@19       pos=(-2, -0.1, 10)
@CSGBox3D@20       pos=(2, -0.1, 10)
@CSGBox3D@21       pos=(-2, -0.1, 13)
```

So `name == "DoorFloor"` finds exactly one node per scene, and `name.begins_with("DoorFloor")` is no
better — the rest share no prefix with what was asked for. Room floors were unaffected only because
their names (`Passage_Floor`, `Archive_Floor`) happen to be unique.

**Fix.** Match generated geometry on **position**, never on name:

```gdscript
var bridge_at := Vector3(red_x, -RoomBuilder.T / 2.0, 13.0)
...
elif child.position.distance_to(bridge_at) < 0.25:
```

**General lesson.** Any node built in a loop with a fixed `name` is unfindable by name after the
first one. Either give each a unique name at build time, or identify it by geometry. The guard that
caught this (`if killed != 2: push_warning(...)`) cost two lines and found the bug before the level
was ever run — assert the *count* whenever you delete or mutate a set of generated nodes.

---

## Issue 18 — A "flashlight off" puzzle inside a DarkZone (the same conflict, a second time)

**Symptom.** KONTUR's Blackout room (Gate 7) is solved by turning the flashlight OFF to see the real
door seam. Playtest: `FLASHLIGHT OFF` at 28.0 s, dead at 34.1 s — **45% of the panic bar in four
seconds** of doing exactly what the room asks. The only survivable strategy was to flick the light
off for one second, glance, and flick it back on.

**Cause.** The room was a `DarkZone`, which adds `DARK_PANIC_RATE` (+3/s) while the flashlight is
off *and*, because `player.gd:_update_panic` is an **if/elif chain**, takes the branch that would
otherwise apply decay. Stacked with KONTUR's level-wide `DreadZone` (+2/s, additive) that is **+5/s
with no decay at all**. The puzzle and the panic system were fighting, and the puzzle lost.

**This is the second occurrence.** The Backrooms Flood (`backrooms_zone3.gd`) had the identical
conflict earlier the same day, was diagnosed, and had its blanket `DarkZone` removed — and the
`game-testing` skill carries a "Standing caution" paragraph describing this exact trap. It was
reintroduced anyway, in a new room, by the author of that warning.

**Fix.** Remove the `DarkZone`. Neither room has a lamp, so both are pitch black on their own; the
zone only ever supplied the tax. `walk_kontur.gd` now asserts no `DarkZone` overlaps the Blackout,
and the check was verified to fail when one is re-added.

**General lesson.** Whenever a puzzle's solution is *"turn the flashlight off"*, *"stand still"*, or
*"stop sprinting"*, check whether a zone already charges panic for that exact posture. Write the
assertion into the level's test at the same time as the puzzle — a documented gotcha did not stop
this happening twice in one day, but a failing test would have.

## Playbook — "textures are merging / flickering / lagging" (the coincident-surface family)

Issues 19, 20, 23, 24, 25 and 26 are all ONE bug class wearing different hats: **two visible surfaces
in the same plane**, or **a texture that never loaded**. They were reported by the user three separate
times because each round of fixes only caught one variant. Use this table before diagnosing from
scratch.

| What you see | Almost certainly | Fix |
|---|---|---|
| One room's texture bleeding through another's along a **jagged/stippled contour**, flickering as you walk | Two coincident WALL slabs — abutting rooms of different depths emitting the same plane twice | Interval-subtract wall dedup (Issue 23) |
| **Patchwork rectangles** on hallway floors at doorways | Floor bridge coplanar with room floors | `BRIDGE_SINK` (Issue 20) |
| A wall poster/sign **sliced apart** by the wall behind it | Prop sitting exactly ON the wall face — `wall_point()` inset of 0.10 | `inset ≥ 0.16` (Issue 26) |
| A wall prop **invisible** although the code runs | Prop buried INSIDE the 0.2 m wall — inset < 0.1, or something hanging behind the prop | `inset 0.22` for props with depth (Issue 26) |
| Wainscot at mid-wall; lower half a **mirrored duplicate** | Positive `uv1_scale.y` on a triplanar material | Negate V (Issue 19) |
| A prop shows a **magnified crop** of its own texture | Art applied to a `BoxMesh` face | Move art to a `QuadMesh` (Issue 24) |
| A prop renders **blank/untextured**, no error visible | `.png` that is really JPEG — `load()` fails while `ResourceLoader.exists()` returns TRUE | `file` it, then `sips -s format png` (Issues 1, 25) |
| A whole emissive surface reads as **flat pure white** | `emission_energy_multiplier > 1.0` with Linear tonemap and no glow | Keep emission below 1.0 (Issue 21) |

### Diagnostic order (learned the hard way)
1. **Run the assertion first** — `tests/check_wall_overlap.gd` names the offending nodes in one run
   and covers most of the table above.
2. **Probe the scene, don't reason about it.** Dump the actual node positions, AABBs, materials and
   textures (`tests/check_fixtures.gd`, `check_morgue_props.gd`, `check_window.gd`,
   `check_spawn_blocked.gd` are all one-purpose probes written for exactly this). A probe surfaced the
   `_load` error behind the blank monitor that no amount of looking at screenshots would have.
3. **Bisect before theorising.** When ceiling fittings blew out white, three hypotheses were argued
   in a row — including an FOV calculation that "proved" the fitting could not be on screen. It was
   wrong. Disabling the fixture and re-shooting found the cause in ONE run.
4. **Suspect the camera before the geometry.** When a probe says the geometry is fine but the picture
   is black, the camera is somewhere unexpected (Issue 22).

### Why screenshots are not sufficient evidence
A depth fight resolves differently per camera position, so `tests/screenshot_level.gd` can come back
clean while the level is visibly broken in play. Every round of this bug family was found by the
*user*, walking around, not by the harness. Static captures verify art and layout; only the
assertion verifies geometry.

## Issue 19 — RoomBuilder rendered every Lab/House wall upside-down (the "textures merging" bug)

**Symptom.** Levels 1 and 2 looked visibly worse than 3–6. Walls appeared to have "two textures
merging into each other": the wainscot/baseboard band sat at mid-wall height and the lower half of
every wall read as a mirrored duplicate of the upper half.

**Cause.** `RoomBuilder.make_material()` passed `uv1_scale` straight through, and `level_1.gd` /
`level_2.gd` both pass an all-positive scale. A positive `uv1_scale.y` on a triplanar material
renders the texture flipped vertically. `MazeKit.make_material()` (Backrooms) and `corridor.gd`
already force a **negative V**; `RoomBuilder` — used only by the Lab, the House and KONTUR — never
received the fix, which is exactly why only those levels looked wrong.

**Fix.** `make_material()` now negates V itself (`Vector3(x, -absf(y), x)`) so no call site has to
remember. Z reuses the X component to keep horizontal tiling square.

**General lesson.** When a gotcha is documented for one builder, grep for the other builders that do
the same job. Three of them had the fix and one didn't, and the one that didn't owned two levels.

## Issue 20 — Floor bridges z-fought with room floors at every doorway

**Symptom.** Hallway floors flickered and showed a patchwork of rectangles while walking.

**Cause.** `RoomBuilder._emit_floor_bridge()` placed the `DoorFloor` box's top face at exactly
`y = 0` — coplanar with every room floor — and `BRIDGE_PAD = 1.3` guarantees it overlaps into the
rooms on both sides. Nine doorways in the Lab, ten in the House. The file header actively asserted
this was safe: *"coplanar box faces are accepted; the game is dark, seam z-fighting is invisible at
these scales."* It is not; darkness does not resolve a depth fight.

**Fix.** `BRIDGE_SINK = 0.004` drops the bridge below the floors, so the room floor always wins the
depth test and the bridge only shows through the gap it exists to fill. 4 mm is far under
`move_and_slide`'s step tolerance — `tests/walk_cellar.gd` confirms the ramp is still walkable both
ways. The false comment was corrected in place.

## Issue 21 — Emissive ceiling fittings rendered as blown-out white slabs

**Symptom.** Adding visible light fittings to the Lab covered a large part of the ceiling in flat
pure white. A hand-computed FOV argument "proved" the fitting could not even be in frame; it was
wrong (the harness camera is pitched up). **Bisecting — disabling the fixture and re-shooting —
found the culprit in one run, after three wrong guesses.**

**Two stacked causes.**
1. **Bright albedo next to its own light.** The fitting sits ~0.25 m from the point light it
   represents, so a light albedo receives enormous irradiance and blows out. Fixture albedo must be
   **dark**; the glow belongs to emission, which nearby lights don't affect — and that also lets a
   blackout drive the fitting visibly dead, which a lit albedo never could.
2. **Emission above 1.0 with no tonemapping.** The project renders with **Linear tonemap, exposure
   1.0 and no glow** (`assets/elements/environment.tscn`), so any `emission_energy_multiplier > 1.0`
   clamps to flat white with zero detail. `MazeKit` uses 1.6 and gets away with it only because
   Backrooms strips are seen down a corridor, never overhead.

**Fix.** `FIXTURE_EMISSION` is 0.55 (Lab) / 0.6 (House), both **below 1.0**, with dark albedos.

**The same trap bit the doors.** `door.gd:door_material()` tints a textured door's emission red to
keep the blood-red convention. At `emission_energy_multiplier = 0.5` the red swamped the pale steel
texture — in a level lit at 0.45 energy, albedo contributes far less than emission — and the door
rendered salmon pink. It is now 0.18.

**General lesson.** In a project with no tonemapping and very low light energy, emission is not a
finishing touch — it is most of a surface's final colour. Treat any value near or above 1.0 as
"this will be pure white", and bisect before theorising.

## Issue 22 — The screenshot harness captured before gravity settled, from above the ceiling

**Symptom.** `tests/screenshot_level.gd` shots of the House living-room window came back near-black
with a stray light pool, while a scene probe confirmed the window, its forest quad and all four
frame bars existed, were positioned correctly and were `visible_in_tree`.

**Cause.** `_place()` drops the player at `y = 1.6` and `_capture()` fired **12 frames (~0.2 s)**
later. Falling from 1.6 to the rest height takes ~0.35 s, so some shots settled and some did not.
The `Camera3D` sits **1.65 m above the player**, so an unsettled capture shoots from `y ≈ 3.25` —
*above the 3.0 m ceiling*, looking into the ceiling slab.

Worse, this was silent: shots that happened to settle rendered from ~1.65 m and shots that didn't
rendered from ~3.25 m, so eye height varied per shot with no error and no warning. Every visual
judgement made from those captures — including "the ceiling fixture dominates the frame" — was made
from a camera near the ceiling.

**Fix.** `SETTLE = 32` frames (~0.53 s) before capture, `CYCLE = 36`. Player now settles to `y ≈ 0`
consistently and the camera sits at a correct 1.65 m eye height.

**General lesson.** A visual test harness that teleports a physics body must wait for the body to
come to rest, and should assert the resulting height rather than trusting it. When a probe says the
geometry is fine but the picture says otherwise, **suspect the camera before the geometry.**

## Issue 23 — Abutting rooms built TWO coincident walls (the real "merging textures" bug)

**Symptom.** In game, one room's wall texture bled through another's along a jagged, stippled
contour — the bathroom's tile showing through the hallway's dark panelling, the morgue's lockers
through the corridor concrete. It flickered while walking. Static screenshots from the test harness
mostly did not reproduce it, because a depth fight resolves differently per camera position.

**Cause.** `RoomBuilder._emit_wall_segment()` deduped wall segments on an **exact span match**
(`axis|fixed|a|b|h`). Rooms that abut share a wall plane, but only rooms of *identical depth* produce
identical spans. The Lab's CrossHall emits x=6 over z 11..14 while the Morgue emits x=6 over
z 9.5..15.5 — different keys, so BOTH were built, occupying the same 0.2 m slab on the same plane.
Because the two rooms carry different skins, the z-fight showed as one room's texture inside the
other, which reads as "textures merging" rather than as a depth artifact.

**This was NOT the earlier floor-bridge fix (Issue 20).** That one was real and did remove the floor
patchwork, but it addressed floors only, and the walls are what the player actually notices.

**Fix.** Dedup now subtracts INTERVALS instead of matching keys: coverage is tracked per
(axis, plane, height) and only the not-yet-walled part of a new segment is emitted. Whichever room
builds first owns the shared stretch — already the documented behaviour for shared interior walls.

**Also found by the same check:** the Lab's `Observation` room *overlapped* the Morgue and the
ExitVestibule by 0.5 m in the `ROOMS` table, so their floor and ceiling slabs were coincident too;
and the House's `CellarWallW` shared a plane with a ground-floor wall. Both fixed.

**Regression test.** `tests/check_wall_overlap.gd` asserts no two CSG boxes have parallel faces
within 2 mm while overlapping substantially in the other two axes. It deliberately tolerates the
floor bridges (sunk 4 mm by `BRIDGE_SINK`) and the 0.2 x 0.2 stubs where perpendicular walls cross
at a corner. Levels 1, 2 and 5 (KONTUR — which had the same bug) all pass.

## Issue 24 — A texture on a BoxMesh renders a magnified CROP of itself

**Symptom.** The exit doors showed one hinge and a blank panel — no observation window, no push bar,
no serial number — as if the art were zoomed ~3x. The tray and monitor in the same level, using the
same material and the same textures, rendered their full images correctly.

**Cause.** The doors were `BoxMesh`; the tray and monitor were `QuadMesh`. A BoxMesh does not map
the whole texture onto each face, so a texture applied directly to the box shows only a sub-rect.

**Fix.** `door.gd:build_visual()` keeps the box as the dark edge/depth of the door and puts the
artwork on a `QuadMesh` on each face (so the door reads from either side without every caller having
to reason about its yaw). Doors were also enlarged 1.0 x 2.2 -> 1.25 x 2.45 and lifted to rest on the
floor rather than sinking 0.125 m into it.

**General lesson.** If two props share a material and a texture but only one renders correctly,
compare their MESH types before suspecting the material.

## Issue 25 — Issue 1 recurred: a .png that was really a JPEG

`lab_monitor_face.png` was JPEG data with a `.png` extension (`file` reported *JPEG image data*),
so its `.import` carried `valid=false`, no `.ctex` was produced, and `load()` failed **even though
`ResourceLoader.exists()` returned true** — which is why the guard in `_add_face_quad` did not catch
it and the monitor silently rendered as a blank box.

Two things made it findable: the file was 287 KB while its siblings were ~3 MB, and a scene probe
surfaced the actual `_load` error at `level_1.gd:_add_face_quad`. `sips -s format png` plus deleting
the stale `.import`/`.godot/imported` entry fixed it.

**Guarding with `ResourceLoader.exists()` is not sufficient** — it returns true for a file whose
import FAILED. When a texture silently doesn't appear, run `file` on it first.

## Issue 26 — `wall_point()`'s inset is measured from the wrong reference, so decals sat IN the wall

**Symptom.** Wall-mounted art was sliced apart by the wall behind it — the morgue's anatomical poster
was cut by a jagged diagonal tear with the drawer texture showing through it. Same class as Issue 23,
but for props rather than for walls.

**Cause.** `RoomBuilder.wall_point()` returns `pos + side * (half - inset)`, where `half` is half the
room's NOMINAL size. But walls straddle that boundary with thickness `T = 0.2`, so the wall's inner
FACE is at `half - 0.1`. The usable clearance is therefore `inset - T/2`, which means:

| inset | clearance | result |
|-------|-----------|--------|
| 0.06, 0.08 | negative | prop buried inside the wall (Issue 11) |
| **0.10** | **0.00** | **exactly coplanar — z-fights, slices the art** |
| 0.15, 0.16 | 0.05–0.06 | correct |

Callers had used all of these. Both levels' notes used 0.10; the House's bedroom painting used 0.08
and the child's drawing 0.06; the morgue poster bypassed `wall_point` entirely with a hand-computed
`c.z + 2.9` that happened to equal `half - 0.1`.

**Fix.** `wall_point()` now clamps to a minimum of `T/2 + MIN_FACE_CLEAR` (0.13), guaranteeing every
wall prop sits at least 3 cm proud of the face regardless of what the caller passes. The morgue
poster was switched to `wall_point`. Insets of 0.15+ are unaffected.

**A latent bug fell out of this.** `LivingMirror` hangs its figure 0.05 BEHIND the glass, so the glass
needs clearance for the figure too. At inset 0.1 the glass sat on the wall face and the figure was
0.05 *inside* the wall, occluded — the one-way mirror's figure could never have been visible in
either the Lab or the House. Both call sites now use 0.22.

**Regression test.** `tests/check_wall_overlap.gd` also asserts that every `QuadMesh` in the level is
at least 2 cm clear of every CSG box. Because door art is now a single front-facing quad (the buried
back quad was removed), this doubles as a check that no door is built facing into its wall.

**General lesson.** When a helper takes an offset, be explicit in its name or docs about what the
offset is measured FROM. "Inset from the room boundary" and "clearance from the wall face" differ by
exactly the amount that turns a decal into a z-fight.
