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
| A textured surface reads as **one flat colour**, art invisible underneath | `emission` set with NO `emission_texture` — a sheet of paint over the picture, not a glow on it | Set `emission_texture`, or go `SHADING_MODE_UNSHADED` if the art is already dark and self-lit (Issue 48) |

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
rendered salmon pink. It is now **0.08** (`door.gd:84`; this entry said 0.18 for a long time and was
wrong). ⚠️ And the trap bit a third time — see **Issue 48**, where the same convention applied to a
near-black artwork produced a flat red panel, and the fix was to leave the emissive path entirely.

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

---

## Issue 27 — A prop's placeholder glow outlives the art it was standing in for

**Symptom.** The Lab keycard, the Lab face-monitor and the KONTUR bait card all "looked weird" even
after real art was generated for them. The keycard read as a green bar on the cart, the monitor as a
glowing green box with a small face inset in it, and the bait card as a featureless pale-blue lozenge.

**Cause.** Each of these props was built long before its texture existed, so each was given a bright
`emission` on its *slab* purely as a findability affordance in a dark room — green for the keycard
(`0.2, 0.8, 0.3` at 0.9), green for the monitor casing (`0.1, 0.25, 0.15`), blue for the bait card
(at 0.9). When the art landed on a quad on top, the slab underneath did not stop glowing. Per
Issue 21, emission is most of a surface's colour in this project, so the placeholder out-shone the
artwork it was supposed to be replaced by.

**Fix.** Once a prop has a lit face, its body goes back to being an ordinary unlit object and the
**art quad carries the glow**:

| Prop | Slab before | Slab after | Quad emission |
|---|---|---|---|
| Lab keycard | green, emission 0.9 | card stock `0.55,0.56,0.54`, unlit | 0.55 → 0.7 |
| Lab monitor | green, emission 0.4 | CRT plastic `0.17,0.165,0.15`, unlit | 0.85 |
| KONTUR bait card | blue, emission 0.9 | same blue, emission 0.25 (edge only) | 0.7 |

The bait card keeps a little emission because its `OmniLight3D` and glow are load-bearing for the
gate — it has to look worth taking.

**General lesson.** A placeholder affordance is a debt. When you texture a prop that had a
stand-in glow, tint or colour, delete the stand-in in the same change — otherwise it competes with
the asset it was a placeholder for, and the symptom ("the new texture looks wrong") points at the
art rather than at the code.

---

## Issue 28 — A single-sided art quad was on the face the player never sees

**Symptom.** The KONTUR bait card rendered as a blank blue lozenge with no artwork, even though the
texture had imported cleanly (real PNG, `.ctex` present) and the guard was passing.

**Cause.** `offering_pedestal.gd` put the card art on one `QuadMesh` at local `+Z`. The KONTUR spine
is walked from low z to high z, so the face the player actually sees is `-Z`. The art was on the
back of the card the whole time.

**Fix.** Build the art on **both** faces, mirroring the `-Z` copy with `rotation.y = PI` so its
normal points outward. A pedestal is an object the player can circle, so committing to one viewing
direction is the wrong shape of fix even when you guess the direction correctly.

**How to spot it.** Identical symptom to a failed texture import (Issues 1 / 25), so check in this
order: (1) `file` the PNG, (2) confirm the `.ctex` exists in `game/.godot/imported/`, (3) *then*
suspect orientation. If the import is sound and the prop is still blank, you are looking at the
untextured back of something.

**General lesson.** Art on a quad has a facing. Any prop the player can walk around needs the art on
every face they can reach, or an explicit reason in a comment why one face is enough.

---

## Issue 29 — Level 6's win condition disabled the threat only AFTER it had time to kill you

**Symptom.** A scripted end-to-end test (`tests/walk_level6_breach.gd`) placed the player just past
the Purge Chamber and the creature just behind it, let the creature detect and chase for real, and
sealed the door the instant its body entered the trap AABB — the exact sequence a player who
correctly solves the level would produce. Result: a real `Screamer.trigger()` fired and the level
reloaded before `_creature_defeated` ever became true. Doing everything right still got you killed.

**Cause.** `purge_chamber.gd:interact()` slammed the door, then waited `CLOSE_TO_CONFIRM_DELAY`
(1.2s) to confirm the creature was inside, then another `PURGE_SEQUENCE_DELAY` (2.5s) for the audio
cue, and only *then* called `creature.lure_into_trap()` — the only thing that stops the creature
from moving or killing. `CHASE_SPEED` (5.0) closes a few metres in well under a second, so across
that ~3.7s gap between "player commits to sealing the door" and "creature is actually disabled," a
creature that had just been lured within arm's reach had more than enough time to land the kill.

**Fix.** Split "stop the creature from being able to hurt you" from "confirm whether the trap
worked." `creature_object12.gd` gained `freeze_for_purge()` / `unfreeze_for_purge()` (thin wrappers
around the same `_block_t` pause `force_block()` already uses — all ticking, including the contact
check, stops). `purge_chamber.gd:interact()` now calls `freeze_for_purge()` **immediately**, before
either delay; `_confirm_trap()` either proceeds to the permanent `lure_into_trap()` (success) or
calls `unfreeze_for_purge()` before reopening the door (a failed lure resumes the chase, it doesn't
leave the creature inexplicably frozen forever).

**General lesson.** A win condition that depends on a fast, lethal AI being "not dangerous anymore"
must make that true at the moment the player commits the winning action, not at the moment the game
finishes confirming it. Any gap between the two is a window where correct play still loses — and
because the fail state (a screamer + reload) looks identical to any other death, this class of bug
is invisible unless something drives the *exact* winning sequence and checks that the game agrees
it won. Regular play-testing might report "I keep dying near the end" without ever landing on this
as the mechanical cause; a scripted, physics-driven win-path test (never one that reaches the win
condition by calling the signal directly) is what actually catches it.

---

## Issue 30 — `E` never worked on either Level 6 door: a disabled collider is invisible to raycasts too

**Symptom.** Two real players independently reported the same thing across several sessions: "I lured
it into the last room but pressing E did nothing" / "I think the button doesn't work." The level was
**completely unwinnable for everyone, always** — not a difficulty problem, a total mechanical dead
end. The fix for Issue 29 above didn't help, because the player could never get far enough to trigger
it: `interact()` itself never fired.

**Cause.** `slam_door.gd` and `purge_chamber.gd` both built a single `CollisionShape3D`, set
`disabled = true` at `_ready()` (meant to represent "door is open, not physically blocking"), and
only flipped it to `disabled = false` from *inside* `_set_closed()` — which is only ever called from
inside `interact()`. But Godot's raycasts **never report a hit against a disabled
`CollisionShape3D`** — it's excluded from physics queries entirely, not just from movement collision.
`player.gd`'s interact ray (`_get_raycast_target()`) could therefore never find either body in the
first place: no hit → `_interact_target` stays null → the "Press E" prompt never even appears →
`interact()` can never run → the collider that was supposed to enable itself never gets the chance. A
closed loop with no way in.

**Why the automated win-path test (`walk_level6_breach.gd`) didn't catch it initially.** That test
called `_purge.call("interact")` directly — the exact method the bug prevented the player from ever
reaching — so it validated the internal confirm/freeze/purge *logic* perfectly while never once
exercising the actual input path a real E-press uses. It passed cleanly while the game was, in
practice, unwinnable. Same shape of gap as Issue 16 (KONTUR's exit having no unlock condition): the
mechanic *worked*, and nobody had asked whether it was *reachable*.

**Fix.** Split each door into two bodies, since `collision_layer`/`collision_mask` apply to a whole
`CollisionObject3D`, not per-shape — one body can't be "always raycastable, sometimes physically
solid" on its own:
- The door's own body keeps an **always-enabled** `CollisionShape3D` on `collision_layer = 2`
  (`note.gd`'s existing "pass-through interactable" convention — raycast-hittable, invisible to
  normal movement collision) so `E` can find it in any state.
- A **new child `StaticBody3D`** holds the actual physical blocker, on the default layer (1), with
  its `disabled` flag toggled by `_set_closed()` exactly as before — this is what stops the player/
  creature from walking through a *closed* door.

**A second-order bug this exposed.** Making the interact collider *always* enabled means it also
always answers raycasts — including the creature's own line-of-sight check and the light-weapon
beam check, which would now treat an *open* door as an opaque wall (it never used to, since the
always-disabled collider never blocked anything). Fixed by adding `query.collision_mask = 1` to
`creature_object12.gd:_has_los()` and `level_6_breach.gd:_has_clear_los()`, so detection/light only
care about genuinely solid (layer 1) geometry — a locker or cabinet still correctly blocks sight
(it's real opaque furniture, deliberately layer 1), but a door's interact marker doesn't.
`tests/check_level6_breach.gd`'s doorway-clearance probe needed the identical mask fix for the same
reason — it started (correctly!) flagging the new always-there interact colliders as "something is
in the doorway," which is true but no longer the failure mode that check exists to catch.

**How this was actually found.** Not by reasoning about the code — by a scripted test
(`tests/walk_level6_breach.gd`) driving the *real* `player._try_interact()` path instead of calling
`interact()` directly, after two live players independently reported the symptom. The very first
attempt at that harder test failed with a THIRD, unrelated bug in the test itself (positioning the
player parallel to, but 0.5m outside, the door's 0.15m-thick collision slab, so the ray geometrically
could never cross it regardless of range or facing) — worth remembering when a "should clearly work"
raycast test keeps returning null: check the query geometry against the *actual* collider bounds
before suspecting the game code.

**General lesson.** `disabled = true` on a `CollisionShape3D` is not "invisible to physics but still
visible to queries" — it is invisible to *everything*, raycasts included. Any pattern of "start
disabled, enable from inside the handler that a raycast is supposed to trigger" is a deadlock by
construction. If a collider's enabled-state needs to differ between "can this be interacted with"
and "does this physically block movement," those are two different bodies, because layer/mask (the
tool that would otherwise let one shape serve both purposes) is a body-level property, not a
shape-level one.

## Issue 31 — Issue 24 recurred: KONTUR's ChoiceDoors put art directly on a BoxMesh

**Symptom.** A full playtest (`game-testing` skill, session covering Intro through all of KONTUR)
flagged both Gate 1 doors — the black one and the red one — as "texture looks corrupted" via two
separate `J` debug captures, one per door. In-game they read as flat, mostly-featureless panels: no
visible window, no hinge detail, nothing recognisable as `door_black.png` / `door_red.png`.

**Cause.** `choice_door.gd:_build()` applied `texture_path` directly to a `BoxMesh` sized
`WIDTH x HEIGHT x THICK` — the exact fault Issue 24 already named and fixed once in `door.gd`, just
never generalised to this second, independently-written door script. A BoxMesh does not map a whole
texture per face, so the art rendered as a magnified sub-rect instead of the full image.

**Fix.** Same pattern as `door.gd:build_visual()`, adapted for `ChoiceDoor`'s hinge-at-origin layout
(the panel is offset `WIDTH/2` from the body, not centred on it): the `BoxMesh` keeps a plain dark
unlit material for edge/depth only; two `QuadMesh` children — one at local `z = THICK/2 + 0.004`
facing +z, one at `z = -THICK/2 - 0.004` facing -z (`rotation.y = PI`) — carry the actual
`texture_path` art, so the door reads correctly from either side of the swing.

**General lesson.** A documented fix in one prop script does not protect a second, independently
built prop script that happens to share the same "art on a box" shortcut. `CLAUDE.md`'s own
"artwork goes on a QuadMesh, never a BoxMesh face" rule is stated once at the top level for exactly
this reason — grep for `BoxMesh` + `albedo_texture` co-occurring in the same function across the
whole `scripts/` directory before trusting that a fixed bug can't reappear elsewhere.

---

## Issue 32 — A Label added to a CenterContainer had its anchors silently discarded

**Symptom.** The House map-and-chase minigame's instruction line was flagged in playtest
(2026-07-25, capture #3: *"the text is not clearly visible"*). The screenshot showed
"Drag to the mark. Don't get caught." printed **across the middle of the parchment**, on top of the
maze it was supposed to explain, in a colour barely separable from the paper.

**Cause.** Two faults stacked, and only the second looked like a styling problem.

`maze_chase_ui.gd:_build_ui()` created a `CenterContainer` to centre the 960x768 playfield, then
added the caption as a **second child of that same container**:

```gdscript
caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
caption.position.y = -48.0
center.add_child(caption)          # <- `center` is a CenterContainer
```

A `Container` calls `fit_child_in_rect()` on **every** child during layout and overwrites its
anchors, offsets, position and size. Both lines above were therefore dead on the first layout pass,
and `CenterContainer` centres each child *independently*, so the label was placed concentric with
the playfield rather than above it. The code read as if it positioned the label; it never did.

Only then did the colour matter: `Color(0.85, 0.8, 0.7)` is a light cream, chosen against the
intended 75%-black backdrop. Stacked onto cream parchment instead, it had almost no contrast — and
it was the only overlay text in the entire project with no outline, no shadow and no panel behind
it (`note_ui.gd`, `combination_lock.gd`, `screen_text.gd` and `panic_hud.gd` all have at least one).

**Fix.** Reparent the caption onto `_root` — a plain `Control`, where presets survive — and anchor it
off the vertical centre by half the playfield height so it clears the map at any viewport size. Then
give it the project's standard treatment: black `font_outline_color` + `outline_size`, matching
`ScreenText._outline()`.

**Why existing tests missed it.** There were none that could: `screenshot_scene.gd` can only teleport
the player and aim a camera, and this UI lives behind an `interact()` call on a prop. Added
`tests/screenshot_maze_ui.gd`, which drives the real interaction path and dumps the result.

**General lesson.** Setting anchors or `position` on a direct child of any `Container` is a no-op —
the container owns that child's rect. If a node must be positioned by hand, it needs a non-container
parent. And when text "looks wrong", check *where the layout actually put it* before adjusting its
colour: here the colour was a real second bug, but it was invisible as one until the placement was
fixed.

---

## Issue 33 — Issue 27 recurred twice: findability glows outliving the art they stood in for

**Symptom.** Two unrelated playtest captures in the same session (2026-07-25). Capture #1, on the
Lab's deliberately-hidden Records breaker: *"the way the light switch is hidden here is very
obvious."* The screenshot showed a near-white panel with a saturated red lever, plainly the
brightest object anywhere in the frame. Capture #5, on KONTUR's roster lock: *"the lock should be a
3d version of the 2d texture — now it is the 2d texture on top of a 3d random cube"* — a glowing
mint-green box with a picture stuck to one face.

**Cause.** Both props were built before they had art, and both were given emission purely so they
could be found in a dark room. `breaker.gd` applied its own `lab_breaker_panel.png` as an
**`emission_texture`** at 0.25 *and* gave the lever `emission_energy_multiplier = 0.7`;
`kontur.gd:_spawn_gate5_roster()` gave the casing green emission at 0.4 over a pale albedo. Per
Issue 21 emission is most of a surface's colour in this project (Linear tonemap, exposure 1.0, no
glow, scene light ~0.45), so in both cases the stand-in out-shone everything around it. A breaker
whose whole design premise is "hidden" was, literally, a lamp.

This is Issue 27 exactly — already written up for the Lab keycard, the Lab monitor and the KONTUR
bait card — recurring on three further props that were simply not in that sweep.

**Fix.** The rule Issue 27 already states: once a prop has a lit face, its **body** goes back to
being an ordinary unlit object, and any remaining affordance moves onto the **art**.
- `breaker.gd`: panel emission deleted outright (albedo texture tinted down to 0.6 so the bright
  source photo stops out-reading the walls); `glows` now gates only the lever *indicator*, at
  `INDICATOR_EMISSION = 0.12` — red-vs-green is genuine state feedback ("did I already flip this?"),
  not an affordance. That 0.12 matches the ceiling `beartrap.gd` documents for the same reason.
- `kontur.gd`: casing emission deleted; the plate `QuadMesh` carries `0.35` instead. The lock is
  still a gate the player must locate on a dark wall, so the affordance is kept — just moved onto
  the lit face, the same trade `door.gd` makes at 0.08.

**General lesson.** A placeholder glow is a debt, and paying it off on the props you happen to be
looking at does not pay it off project-wide. When a prop gains real art, grep the *whole* directory
for `emission_enabled` on prop bodies rather than fixing the instance in front of you — Issue 27
fixed three props and left at least three more, and the symptom always points at the art ("this
texture looks wrong") rather than at the code.

---

## Issue 34 — A core mechanic was a one-line stub, and a HUD crutch hid that for a whole level

**Symptom.** Playtest capture #2 on the Lab's pitch-black breaker wing: *"So far it is too simple to
find this light switch hidden in the dark. We need to make the geometry of this level harder, and
probably add some real audio so that we can navigate based on that."* The level was described in
`CLAUDE.md` as an audio-only navigation mini-game.

**Cause.** There was no audio navigation to speak of. `level_1.gd:_spawn_dark_breaker_tell()` was:

```gdscript
func _spawn_dark_breaker_tell(pos: Vector3) -> void:
	_dark_breaker_pos = pos
```

It recorded a coordinate and spawned nothing. The entire "tell" was a **0.45 s non-looping**
`breaker_spark.wav` fired every **8-12 s** through the level's generic one-shot helper — `unit_size
8`, no `max_distance`, no `attenuation_model`, Master bus. A ~4% duty cycle carrying almost no
distance information: not steerable even in principle.

What made this survive was the crutch built next to it. A hot/cold HUD bar
(`_tick_breaker_meter()` + `panic_hud.set_breaker_proximity()`) reported straight-line distance to
the breaker, so the wing was always solvable — by the bar, never by the sound. The bar also *lied*,
being distance-only through walls: from inside the dead-end stub it read a warm ~0.43 while being
nowhere near the breaker in walking terms.

**Fix.** Delete the meter (both call site and HUD widget), and build the mechanic that was being
stood in for: a **continuous two-layer positional beacon** at the breaker, lifted from
`backrooms_zone2.gd`, whose own header comment is a post-mortem of this identical mistake. A far cue
(`unit_size 16`) carries the length of the wing and gives a bearing; a near confirm (`unit_size 9`)
only resolves in the last room or two and distinguishes "right branch" from merely "right
direction". Two new seamless loops in `tools/make_sfx_extra.py` supply them (every `.wav.import` in
this project is `loop_mode=0`, so the players self-restart via `finished -> play`). The wing itself
grew from 4 rooms and one binary choice to 10 rooms, three decision points and three dead ends.

**Why existing tests missed it.** Nothing asserted the wing was *navigable*, only that it existed.
Added `tests/walk_lab_wing.gd`, which drives a `CharacterBody3D` the whole route under gravity and
proves each dead end dead with raycasts against the built CSG — never against the `DOORS` array that
produced it. It was verified to fail: sealing one doorway makes the walker stall against the wall
and the run go red.

**General lesson.** Two of them. First, a function whose body is a single assignment is worth reading
before trusting a design document that describes it as a feature — `CLAUDE.md` described this tell in
detail for several sessions while the code did nothing. Second, and more costly: **an assist that
solves a puzzle outright will mask the fact that the intended solution was never implemented.** The
meter was added to make audio navigation feel like an active mini-game; instead it replaced it, and
removed the only pressure that would have revealed the stub.

### ⚠️ AMENDMENT (2026-08-16) — a meter is back, on the user's explicit call, and it is not this one

Playtest capture #5: *"Finding your way through sounds only in the complete dark is hard for the
unexperienced user. Let's make the visual noise indicator also - like a continuous scale. The noise
would get noisier the closer we are to the flip breaker."* The user was shown this issue and
`GAME_MECHANICS_IDEAS` §5.2(2) — the anti-pattern that names this widget — and chose to build it
anyway. That is a design call and it is theirs; it is recorded here so nobody re-deletes it as a
regression, and so the anti-pattern's own entry can point at its exception.

**What is engineered, rather than merely re-litigated, is the half of this issue that was not about
taste.** The deleted bar measured **straight-line distance** and therefore LIED: from a dead end it
read a warm ~0.43 while being nowhere near the breaker in walking terms, pointing the player at a
wall. `lab_wing_meter.gd` runs **Dijkstra over the wing's own doorway graph** — the same
"route, not beeline" correction `maze_chase_ui.gd`'s monster needed — and normalises against the
furthest room's path distance rather than a typed-in constant. Measured by `tests/check_wing_meter.gd`
on the shipped geometry:

| position | walking | straight line | the old bar would read | the new one reads |
|---|---|---|---|---|
| Plant (dead end, west limb) | 30.0 m | 6.6 m (a 4.6× lie) | 0.79 — *nearly there* | **0.04** |
| NorthVault (dead end) | 31.2 m | 18.9 m | 0.39 | **0.00** |
| PumpRoom (dead end) | 13.1 m | 12.1 m | 0.61 | **0.58** |
| the real route, in order | — | — | — | 0.15 → 0.31 → 0.37 → 0.46 → 0.65 → 0.80 → 0.96 |

It reports **no reading at all** outside the wing, it is shown only inside it, and it dies with the
beacon the instant the breaker is thrown. It is a scalar: the two-layer positional beacon still owns
BEARING, which is the half of a maze a number cannot answer.

The *other* half of that capture — *"I can see this breaker visually - it should appear only when I am
very close to it"* — was measured before acting on it (`tests/screenshot_nook_panel.gd`, torch locked
off, rendered luminance of the panel against the wall beside it):

| distance | panel | wall beside it |
|---|---|---|
| 2.0 m | 0.0006 | 0.0000 |
| 3.5 m | 0.0042 | 0.0000 |
| 6.0 m | 0.0060 | 0.0000 |
| 10.0 m | 0.0000 | 0.0000 |
| 15.0 m | 0.0000 | 0.0000 |

Peak 0.006 — about **1.5 of 255** — and literally zero beyond 6 m, which is the terminal room's own
doorway. Nothing was changed: there is no emission left to remove (this issue's own fix, plus Issue
33), and dropping the remaining albedo tint would make the panel unreadable at the range where the
player has to find it to throw it. **The wing is solved by the beacon, exactly as designed.**

---

## Issue 35 — A wall prop's own artwork contained a picture of the wall behind it

**Symptom.** Playtest capture #4 on KONTUR's Landing mailbox: *"Need to make these objects 3d, and
probably only one of them should open and keep the note."* It read as a poster taped to the wall
rather than as an object — despite `kontur_mailbox.gd`'s header claiming it had already been
"upgraded from a flat wall decal into a real shallow interactable".

**Cause.** The interaction was real; the *object* never was. `kontur.gd:_spawn_mailbox()` built one
`BoxMesh` plus one `QuadMesh` decal, and the decal was `kontur_panel_mailboxes.png` — described in
TEXTURES.md as *"Battered Soviet mailboxes **on matching wallpaper background**"*. So the prop's own
texture included a photograph of the surface it was mounted on. There is no lighting or geometry
that can make that read as three-dimensional: the flat region surrounding the depicted boxes is
painted-on wall, and it moves with the prop. Two lesser faults rode along — `TRANSPARENCY_ALPHA` was
set on an image with **no alpha channel** (inert, and it bought a transparent-pass sort for nothing),
and a 1.333 source was stretched onto a 1.143 quad.

**Fix.** Rebuilt as real geometry with **flat-tinted materials and no texture at all**, the way
`intro_room.gd:_build_wheelchair()` was rebuilt after the identical complaint (TEXTURES.md records
that texture as retired). Carcass, plinth and top overhang, a divider/shelf grid, and twelve
numbered slot doors each with a pull handle and a card holder. Only slot 12 hangs on a hinge and
swings open — the note's own header already read "MAILBOX — SLOT 12", so numbering every slot makes
the hint name its own address.

**General lesson.** When a prop is meant to sit on a surface, art whose background *is* that surface
guarantees it reads as flat, no matter how the mesh is built — the giveaway is a texture description
containing the word "background". Check what a decal's non-subject pixels actually depict before
concluding the geometry is at fault. And note the parallel with Issue 33: the fix in both cases was
to stop asking a texture to do a mesh's job, and `rotary_phone.gd` remains the proof that in this
project silhouette carries a prop while art does not.

## Issue 36 — A "restore" pass raised state its "increment" pass had always known to skip

**Symptom.** Found while adding the BreakerNook payoff scare, not by a playtest: throwing the third
Lab breaker floodlit the entire ten-room lightless wing *and* the Morgue. The Morgue's whole design
is a `DarkZone` plus a beartrap plus two don't-look triggers, all staged in a room the player is
supposed to search by flashlight — and it had been rendering fully lit at the exact moment the
shutter opened, for the life of the feature. Nobody noticed because you only ever see it after the
quest that causes it.

**Cause.** `level_1.gd:_spawn_lights()` gives **every** room in `ROOMS` a lamp, handing the eleven
`NO_LAMP_ROOMS` one at `light_energy = 0.0` — the room is dark because its lamp is off, not because
it has no lamp. Two functions then drive those lamps, and only one of them knew that:

```gdscript
func _on_breaker_flipped() -> void:
    for entry in _lights:
        if entry[1] > 0.0:              # <- correct
            entry[1] = minf(RESTORED_ENERGY, entry[1] + 0.18)

func _restore_power() -> void:
    for entry in _lights:
        entry[1] = RESTORED_ENERGY      # <- unconditional
```

The per-breaker *increment* had the guard from the start. The *restore* never did. Both loops walk
the same array and mean the same thing by it; the guard is the only place that knowledge lives, and
it was written down once instead of twice.

**Fix.** The same `if entry[1] <= 0.0: continue` in `_restore_power()`, with the reasoning in a
comment beside it. Locked down by `tests/check_lab_locker.gd`, which calls `_restore_power()` and
asserts every `NO_LAMP_ROOMS` lamp is still at 0 — a plain assertion, because "is this room dark"
is a property of the lamp, not of the table that spawned it.

**General lesson.** When a "sentinel" value carries meaning (here `0.0` = *deliberately unlit*), every
loop over that collection has to honour it, and a partial/incremental writer is not evidence the
final writer is safe — it is a hint to go read the final writer. Grep for all mutators of a
collection before trusting any single one of them. The tell that this had never been checked: the
guard existed verbatim eleven lines above the function that lacked it.

---

## Issue 37 — `AABB.intersects_segment()` returns a Variant, and a `-> bool` signature turns that into a crash

**Symptom.** Reported as a gameplay bug: *"in level 6 the first and last doors work fine.
However, if you try to use at least some of the other doors, you get kicked out of the game."*
Nothing about the doors themselves looked different.

**Cause.** Found in the user's own Godot logs
(`~/Library/Application Support/Godot/app_userdata/horror_game/logs/godot2026-07-26T19.46.01.log`),
as the last line of the session:

```
SCRIPT ERROR: Trying to return value of type "Vector3" from a function whose return type is "bool".
   at: SlamDoor.check_blocks_path (res://scripts/slam_door.gd:189)
   GDScript backtrace (most recent call first):
       [0] check_blocks_path (res://scripts/slam_door.gd:189)
       [1] _tick_slam_doors (res://scripts/level_6_breach.gd:352)
       [2] _process (res://scripts/level_6_breach.gd:565)
```

`AABB.intersects_segment()` does **not** return a bool. It returns a Variant: the
intersection **point** (a `Vector3`) on a hit, and **`null`** on a miss. `slam_door.gd`
declared `-> bool` and returned it directly, so *every* outcome was a hard runtime type
error — the second log variant is the `Nil` case.

**Why "first and last work".** Those are `BackDoor` and `ExitDoor`, built from `door.gd`,
which has no `check_blocks_path` and is never touched by `_tick_slam_doors()`. All four
`SlamDoor`s crashed. It only *looked* door-specific because the call site is guarded twice:
the door must be `_closed` (so the player has to have slammed one) **and** Object 12 must
have left `PATROL` (so the familiarization window must have elapsed). A run where you never
slam a door never crashes.

**Fix.** `return aabb.intersects_segment(local_from, local_to) != null`.

**Why existing tests missed it.** `check_level6_breach.gd` never closed a door;
`walk_level6_breach.gd` teleports player and creature to the Incinerator and never touches
a `SlamDoor` at all. The whole code path was untested. `check_level6_breach.gd` now closes
each door through the real `interact()` and asserts both the return **type** and both
answers; verified to reproduce the exact `SCRIPT ERROR` above with the fix removed.

**General lesson.** Godot's Variant-returning geometry helpers (`intersects_segment`,
`intersects_ray`, `intersect_ray` on a space state) are a trap under GDScript's static
typing: the annotation is checked at *runtime*, so the mistake ships silently and then
takes the whole game down mid-frame. Grep for these by name whenever one appears in a
typed function. Also: **read the engine's own logs before reading the code** — this was a
five-minute find there and would have been a long hunt from the source.

---

## Issue 38 — A `queue_free()`d node keeps its NAME for the rest of the frame, so every replacement got renamed

**Symptom.** `get_node("ExitDoor")` returned null in the Lab and the House. Probing the
built level showed the doors as `@StaticBody3D@332` and `@StaticBody3D@334`.

**Cause.** All five procedurally-built levels start with

```gdscript
func _clear_old_scene() -> void:
    for child in get_children():
        if not PRESERVE.has(child.name):
            child.queue_free()
```

`queue_free()` is **deferred to the end of the frame**. The old `.tscn` nodes are therefore
still children — and still holding their names — for the whole of `_ready()`, which is when
the replacement level is built. Godot renames a colliding sibling using the **class** name
(the same mechanism as Issue 17), so the new `ExitDoor` became `@StaticBody3D@332`.

**Fix.** `remove_child(child)` before `child.queue_free()`. `remove_child` detaches
immediately, so the name is free by the time the new node is added.

**Why nobody noticed.** Nothing in the shipping game looked a door up by name — doors are
reached by raycast. It surfaced the moment the new autoplay harness tried to assert "can
the player reach the exit", and it would have surfaced next as a mysterious null in any
future save/restore or scripted-sequence code.

**General lesson.** `queue_free()` is not `free()`. If you are rebuilding a scene in
`_ready()` and any name matters — for lookup, for tests, for a later `get_node` — detach
the old nodes explicitly. The same shape bit KONTUR's bottle shelf in the same session:
`BottleItem.interact()` emits `taken` *before* its own `queue_free()`, so a respawn in that
handler collided with the corpse and every later `get_node("Bottle_vinegar")` resolved to
the dead one, whose `_taken` guard was already true.

---

## Issue 39 — A suppression rule tuned against a period comparable to its own is a deadlock

**Symptom.** `tests/count_apparitions.gd` reported **0 apparitions in 400 seconds** after
the apparition's pacing was moved from a bare 60 s countdown into `ApparitionDirector`. The
game's flagship monster had been switched off, and the test — informational at the time —
reported it as a tidy "0 in 400 s".

**Cause.** The director refuses to fire within `MIN_GAP_AFTER_AMBIENT` of a `RandomAmbient`
scare, so the two scare systems stop landing in the same breath. It was set to **30 s**.
`RandomAmbient` fires every **18–35 s**. The window in which the condition can be satisfied
barely exists.

**Fix.** Three things, and the second two matter more than the first:
1. `MIN_GAP_AFTER_AMBIENT` → 8.0, well under `RandomAmbient.MIN_INTERVAL` (18).
2. `OVERDUE_AFTER` — the *soft* conditions (ambient spacing, panic level) are dropped once
   an appearance has been held back that long. The hard fairness conditions (paused tree,
   open note, frozen input, a level's own veto) are never relaxed. An appearance can now be
   delayed but never cancelled.
3. `count_apparitions.gd` **asserts** instead of printing: a minimum count, and a minimum
   gap. It also counts *appearances* (`visible`) rather than instantiations, because
   Apparition nodes exist dormant from level build and one was being logged as a phantom
   sighting at t=2.1 s.

**General lesson.** Two of them. When adding a gate on "time since some other system did
X", check X's own period first — a condition whose window is the same order as the thing it
waits for is a deadlock, not a preference. And any feature that can be silently suppressed
to zero needs a test that fails at zero; this is Issue 34 restated, where an assist masked
a mechanic that had never been implemented at all.

---

## Issue 40 — A shape query against CSG reports nothing when it is fully INSIDE the solid

**Symptom.** `Apparition._fits()` approved a spawn point 0.8 m inside a wall. The test's own
independently-written shape query at the same coordinates flagged it correctly, so the two
disagreed about identical geometry.

**Diagnosis.** `tests/probe_shape_vs_csg.gd`, kept in the repo as the evidence. Cylinder,
box and sphere all behave the same way against the CSG walls:

```
--- at (-31.0, 0.0, 14.4)  (0.8 m inside the Plant north wall) ---
  cylinder   -> 2 hits  @CSGBox3D@118, @CSGBox3D@118
--- at (-31.0, 0.0, 14.5)  (dead centre of the wall slab) ---
  cylinder   -> 0 hits
```

CSG collision is a **concave trimesh**. A shape that straddles a face intersects triangles
and is reported; a shape sitting wholly within the slab intersects none and comes back
clean. So `intersect_shape` silently approves exactly the case a clearance check exists to
reject.

**Fix.** `_fits()` uses **rays**, which is what the rest of this project asserts with:
line-of-sight from the player's eye (which also catches "the point is inside a wall",
because the segment must cross that wall's near face to reach it), a head-room ray, a
top-down ray through the figure's own column, and a 16-ray horizontal fan for elbow room.

**General lesson.** Do not use `intersect_shape` as a containment test against CSG or any
concave collider. And when an implementation and its test disagree about the same
coordinates, write the throwaway probe — the argument from first principles had been
confidently wrong for three rounds before the probe settled it in one run.

---

## Issue 41 — RoomBuilder emits COINCIDENT wall slabs when abutting rooms have different heights

**Symptom.** Would have been the "merging textures" bug again, at scale, in every
corridor-to-chamber doorway of THE NIGHTMARE. Caught before it shipped.

**Where it came from.** `DUNGEON_NIGHTMARES.md` §B6 step 6 asks for `h = 3.2`
chambers and `h = 2.6` corridors, on the reasoning that "the height change alone
makes chambers feel like rooms". `RoomBuilder` has supported a per-room `"h"` key
for its whole life, so this looked free.

**Root cause.** `RoomBuilder._emit_wall_segment()` tracks which stretches of a wall
plane are already built in `_built_walls`, keyed:

```gdscript
var key := "%s|%.2f|%.2f" % [axis, fixed, h]     # room_builder.gd:228
```

The key includes the HEIGHT. Two abutting rooms share a wall plane, so with equal
heights the second room's wall is correctly subtracted away by the first's. With
different heights they get **different keys**, both rooms build, and the shared
stretch ends up with a 3.2 m slab and a 2.6 m slab occupying the same space.

**Why nobody had hit it.** ⚠️ **No shipped level uses per-room `h` at all.** Every
`ROOMS` table in the project is uniform, so the interval dedup had only ever been
exercised in the one case where the height component of the key is constant.

**How it was measured** (`tests/probe_mixed_height.gd`, kept as the evidence):
a two-room fixture, a 3.2 chamber abutting a 2.6 corridor on `z = 4`.

```
MIXED-HEIGHT slabs on the shared plane z=4: 4   (1 = deduped, 2 = both emitted)
MIXED-HEIGHT result: 2 coincident-face pair(s)
MIXED-HEIGHT CONFLICT CONFIRMED
```

**Fix.** Every room in the dungeon is ONE height. The chamber/corridor contrast is
delivered instead by a separate drop-ceiling `CSGBox3D` hung over each corridor at
2.6 m (`dungeon.gd:_add_corridor_drop_ceilings()`) — 0.6 m clear of the builder's
own ceiling, so nothing is coplanar and the read is the same.

**General lesson.** A builder option that no level has ever used is not a supported
feature, it is an untested one. Before designing around a key you have not seen in a
`ROOMS` table, build the two-room fixture and look.

---

## Issue 42 — The image-generation pipeline cannot produce an alpha channel at all

**Symptom.** Two textures generated explicitly as cutouts — a blood smear on glass
and an iron grate, both prompted with "fully transparent background, clean alpha
channel" — came back fully opaque, with the background painted in.

**Root cause.** The Gemini endpoint behind `nano-banana-pro/generate_image.py`
returns **JPEG bytes whatever the output filename says** (this is Issue 1, still
true). JPEG has no alpha channel, so a transparent background is not something the
prompt can ask for — it is not representable in the format that comes back. Running
`sips -s format png` fixes the CONTAINER, which is what makes Godot import the file
at all, but it cannot invent transparency that was never in the data.

Confirmed across all 14 images generated for THE NIGHTMARE: every one arrived as
`JFIF standard 1.01 ... components 3`, i.e. RGB with no alpha.

**Consequences to plan around.**
- Any RGBA cutout — billboards especially — must be **hand-authored or
  post-processed**, never expected from generation. The two RGBA files in
  `level_9_dungeon/` that DO have real alpha (`dn_hollow_figure.png`,
  `dn_tally_wall.png`, both verified `alpha_extrema == (0, 255)`) were supplied by
  the user, not generated.
- A prop designed around see-through-ness needs a fallback that does not need it.
  The dungeon's grate became an opaque panel, and the teaching silhouette is drawn
  AT the grate rather than behind it (`creature_hollow.gd:begin_teaching()`'s
  `reveal_anchor`).

**RULE.** Verify alpha, do not assume it:
```bash
file game/assets/textures/<f>.png        # "PNG image data ... RGBA" is necessary
python3 -c "from PIL import Image; im=Image.open('<f>'); \
  print(im.mode, im.getchannel('A').getextrema() if 'A' in im.mode else None)"
# real alpha == mode contains A AND extrema != (255, 255)
```
A `.png` that is really a JPEG has no alpha and `ResourceLoader.exists()` still
returns true for it (Issue 25) — so neither the extension nor the guard tells you
anything.

### ✅ RESOLVED 2026-07-29 — `tools/cutout_alpha.py`

The diagnosis above is exactly right and the conclusion ("must be hand-authored") is
now too pessimistic: generated cutouts ARE usable, they just have to be **keyed**
after the fact, the way a green-screen plate is. Five images were put through this
for the House and all five verified `alpha_extrema == (0, 255)`.

Ask the generator for a **saturated chroma background the subject cannot contain**
(`#00FF00` in a JSON `environment.background`), then:

```bash
sips -s format png <f> --out <f>                       # container first (Issue 1/25)
nano-banana-pro/.venv/bin/python3 tools/cutout_alpha.py <f> --chroma auto
```

Three things that tool does which a naive key does not, each learned the hard way:

- **`--chroma auto` samples the border rather than trusting the prompt.** A spec
  demanding "perfectly flat uniform solid `#00FF00`" came back as `(30, 143, 74)` —
  green, but 137 units away in RGB, which sailed past a fixed tolerance and left the
  whole image opaque (`alpha_extrema == (127, 255)`).
- **It de-spills.** Alpha 0 hides the background, but the RGB underneath is still
  green and every soft edge blends it back in — visible as a green rim under
  `TRANSPARENCY_ALPHA`. Every pixel is capped at `g <= max(r, b) + 12`.
- **It crops to the alpha bbox**, which also fixes the generator returning 16:9
  however loudly the prompt asks for portrait (§7.1(4): the texture aspect must match
  the mesh, or the figure renders stretched).

⚠️ A **luminance** key (the default, no `--chroma`) only works for a dark subject on
a pale ground. For anything bright or multi-coloured it deletes the subject.

⚠️ Some prompts are **refused outright** rather than returned badly: an "emaciated
screaming child" came back as `TypeError: 'NoneType' object is not iterable`, which is
the safety filter, not a bug. Reframe (that one shipped as an antique porcelain doll)
rather than retrying the same words.

---

## Issue 44 — A script that fails to PARSE exits 0, so the test runner reported PASS

**Symptom.** `check_house_guest.gd` was rewritten, had two undeclared identifiers, and
`tools/run_tests.sh` printed **PASS** for it. The level it tests was meanwhile
completely broken.

**Root cause.** Godot prints `SCRIPT ERROR: Parse Error: ...` / `Failed to load script`
and then **quits cleanly with status 0**. The runner branches on the exit code, so a
test that never ran at all is indistinguishable from a test that passed.

This is the same family as the header warning in `run_tests.sh` about `--import` and
`class_name` — that one makes level scripts fail to parse and tests find nothing. This
is its mirror image: the TEST fails to parse and the runner finds nothing wrong.

**Fix.** `run_tests.sh` now greps the captured output and forces a failure:

```bash
if echo "$out" | grep -qE "Parse Error|Failed to load script|SCRIPT ERROR: .*Compile"; then
  code=1
fi
```

It earned its keep within the hour: a stray `var t := 0.05` colliding with a
`var t: Texture2D` in `house_fridge.gd` took `level_2.gd` down with it and surfaced as
**9 failing tests** instead of a green run on a broken House.

⚠️ `--import` does NOT report these. It re-imports assets; it does not compile scripts.

---

## Issue 45 — `bool(node.get("missing_property"))` hangs a test forever

**Symptom.** A suite run sat on one test for **28 minutes**. That test's own timeout is
30 seconds. Its log held **21,265 assertion lines** — the same four, repeating.

**Root cause.** `Object.get()` returns `null` for a property that does not exist, and
`bool(null)` is not a valid GDScript constructor — it **throws**. The throw happened
inside `_process()`, which aborted the frame *before* the line that advances the stage
counter and *before* the timeout check at the bottom of the function. So the test
re-ran the same stage every frame, forever, printing as it went.

The property had simply been renamed in the level under test (`_child_armed` was
deleted when the beat moved rooms). Nothing about the failure pointed at that.

**Fix.** Never call `bool()` on a `.get()` result in a test. Use a null-safe helper:

```gdscript
func _flag(name: String) -> bool:
    var v: Variant = _scene.get(name)
    return v != null and v == true
```

⚠️ Note what makes this dangerous rather than merely annoying: an exception thrown
from `_process` in a `SceneTree` script does not stop the run, and **any** work below
the throwing line — including the test's own watchdog — silently stops happening.
Put the timeout check FIRST if a test does anything reflective.

---

## Issue 46 — A solid `BoxMesh` has no interior; anything inside it is invisible

**Symptom.** The House fridge was built as one `BoxMesh` of the full carcass size, with
a "recess" drawn as a second solid box inside it and a horror prop on a shelf inside
that. Opening the door revealed a blank panel. Playtest: *"when the fridge opens —
there is no head inside of it."*

**Root cause.** A box is a closed surface. The prop was not failing to spawn; the
carcass's own front face was drawing over it. No amount of moving the prop backwards
helps — every position inside the box is behind a face.

**Fix.** Build anything the player is meant to see INTO as an open-fronted shell of
five slabs (back, two sides, top, base) plus a separate interior back panel. Keep the
collider as a single box — colliders never render, so the cheap shape is still correct.

⚠️ Same class as Issue 28 (a single-sided art quad on the face the player never sees):
in both cases the geometry was right and the *facing* was wrong. When something is
invisible but provably present, suspect an occluding or back-facing surface before
suspecting the spawn.

---

## Issue 47 — A stale `GEMINI_API_KEY` in the shell shadows the one in `.env`

**Symptom.** Image generation failed with `400 INVALID_ARGUMENT ... API key not valid`,
while `.env` held a perfectly good key that had worked the day before.

**Root cause.** `generate_image.py` reads the **environment variable**, and
`load_dotenv()` does **not** override a variable that is already set. The shell profile
exported an old 39-character key; `.env` held the current 53-character one. The old one
won every time.

**Fix.** Export from `.env` explicitly for the command:

```bash
export GEMINI_API_KEY=$(grep -E '^GEMINI_API_KEY=' .env | head -1 | cut -d= -f2- | tr -d '"'"'" \r')
```

⚠️ Compare lengths, never print keys, when diagnosing this. And distinguish the error:
`400 INVALID_ARGUMENT` is auth (this issue); `503 UNAVAILABLE` is real server load and
deserves a retry with backoff; a `TypeError: 'NoneType' object is not iterable` is the
safety filter refusing the prompt.

---

## Issue 43 — Doorway floor-bridges z-fight with EACH OTHER on a fine room lattice

**Symptom.** `check_wall_overlap.gd` on the dungeon reported up to 19 coincident-face
pairs, every one of them `+y faces coincide` between two boxes of size
`2.2 x 0.2 x 2.6` or `2.6 x 0.2 x 2.2` — i.e. between two floor bridges.

**Root cause.** `RoomBuilder._emit_floor_bridge()` extends each bridge `BRIDGE_PAD`
(1.3 m) either side of its doorway plane, and sinks every one of them by the same
`BRIDGE_SINK` (4 mm). `BRIDGE_SINK` exists to stop a bridge fighting the ROOM FLOOR
(Issue 20) and does that correctly — but it gives every bridge in the level an
identical y, so any two bridges that overlap in plan are exactly coplanar.

Two bridges overlap in plan whenever two doorways are within 2.6 m of each other.
In a hand-authored level that never happens; in a 3 m cell lattice a corner junction
is a 1×1 room with doorways on two perpendicular walls **3 m apart**, so it happens
at every single corner.

**Fix** (`dungeon.gd:_stagger_bridge_overlaps()`), level-local so the four levels
that share `RoomBuilder` are untouched: after `build()`, give each bridge that
overlaps an already-placed one the lowest 3 mm step that clears every bridge it
overlaps. Result: 0 pairs on all five test seeds.

**Two mistakes worth recording, both caught by measuring:**

1. **Counting collisions is not enough.** The first version offset a bridge by
   `3 mm × (number of bridges it overlapped)`. Two bridges that both overlap the
   same third one then get the SAME offset and are coplanar with each other. It has
   to be a conflict-free assignment against the y-values already taken.
2. ⚠️ **Stagger DOWN, not up.** Raising bridges closes the 4 mm `BRIDGE_SINK` gap
   and starts a NEW fight against the room floor at y=0 — measured, bridges raised
   to −0.101 / −0.098 put their top faces within 1–2 mm of the floor plane, which is
   exactly what `BRIDGE_SINK` exists to prevent. Going down keeps every bridge at
   least 4 mm clear; the cost is a sub-centimetre dip in the doorway, which is a
   DROP rather than a step and is two orders of magnitude below the 140 mm lip that
   once made the House cellar unenterable.

**⚠️ Do not identify the bridges by NAME.** `RoomBuilder` names every one of them
`"DoorFloor"`, and Godot renames name-colliding siblings to `@CSGBox3D@N` — so
`name.begins_with("DoorFloor")` matches exactly one bridge out of forty and silently
does nothing, which is what the first implementation did. Identify by geometry: a
bridge is `BRIDGE_PAD * 2 = 2.6 m` along one horizontal axis, and every room
dimension on the lattice is a multiple of `CELL = 3.0`.

**General lesson.** A shared builder's constants encode assumptions about the SCALE
of the levels built with it. `BRIDGE_PAD` of 1.3 m is invisible at hand-authored
room spacing and pathological at 3 m. When a new level changes the scale by an order
of magnitude, re-derive the constants rather than inheriting them.

---

## Issue 48 — Issue 21 recurred: an untextured `emission` wash hides the art it is meant to light

**Symptom.** The Corridor's exit door was given new artwork — a black-wood door torn open on a
red-lit void — and rendered as a plain red rectangle. The texture was demonstrably loaded:
`check_noclip_fall.gd` asserted `albedo_texture` was assigned and passed. Reported twice
(2026-08-15: *"in the corridor level the door still looks just red, not like [the file]"*).

**Root cause.** `corridor.gd:_dress_exit_door()` is the one door in the game that hand-rolls its
material instead of calling `door.gd:door_material()`. It set `emission = Color(0.35, 0.02, 0.02)`
at `emission_energy_multiplier = 0.6` **with no `emission_texture`**. A flat emission colour is
added to every pixel equally, so it is a sheet of red paint laid over the picture — and in a level
lit at ~0.45 energy with no tonemapping, emission is most of the final colour (Issue 21). The
albedo underneath never had a chance.

**Fix.** Two stages, and the second is the interesting one:

1. Switching to `door_material()` fixed the wash — it sets `emission_texture` so the tint is
   modulated BY the art — but the door then read as uniformly red. That tint exists for the Lab's
   pale steel and the House's timber; this artwork measures **22/255 mean luma**, so a red tint is
   the only thing that survives it.
2. A neutral tint blew out instead: white at 0.42 and again at 0.14 both rendered a flat light-grey
   slab, and at 0.0 the door went black (sampled 16,12,12) — the emission was behaving as its flat
   colour rather than as the texture.

The door is now `SHADING_MODE_UNSHADED`. The quad draws the artwork exactly as authored, which is
already a black door with a glowing tear in it, and is self-lit by definition — so it survives the
blackout that force-kills the flashlight 10 m earlier. That is the only thing the blood-red door
convention was ever for.

⚠️ **Issue 21 is stale where it says the textured-door emission "is now 0.18"** — `door.gd:84` has
been **0.08** for some time, and this door has now left that path entirely.

**General lesson.** `emission` without `emission_texture` is not "a glow on the object", it is an
opaque colour laid over it. And a convention tuned for pale surfaces inverts on dark ones: when the
art is already near-black and already contains its own light source, the correct amount of help is
none. ⚠️ The assertion that would have caught this is not "is a texture assigned" but "is anything
washed flat over it" — see the note in `check_noclip_fall.gd`.

---

## Issue 49 — An early `return` from `_apply_movement()` leaves velocity for `move_and_slide()` to spend

**Symptom.** Stepping into a beartrap was supposed to pin the player until they mashed free. The
UI read `TRAPPED — PRESS [E] TO ESCAPE` and the player kept moving anyway, reported twice
(2026-08-15: *"I am still not trapped in the beartrap once I get into there. I can still move even
though in the weird way"* — the *weird way* is the tell).

**Root cause.** The pin was implemented as an early return:

```gdscript
func _apply_movement() -> void:
	if _input_frozen or _qte_active:
		return          # ← looks like "do not move"
	...
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)   # the branch that STOPS you
		velocity.z = move_toward(velocity.z, 0, SPEED)
```

`_physics_process` calls `move_and_slide()` on the next line **regardless**, and `velocity` is
persistent state on the `CharacterBody3D`. Returning early skips the only code that ever zeroes it,
so the body coasts forever at whatever the last un-pinned frame set — which is why it read as
drifting rather than as walking. Measured by walking in at 6.40 m/s: **9.16 m of travel in 1.5 s**
while pinned.

**Fix.** Zero the horizontal velocity and then return. Gravity is left alone so a pinned player
still rests on the floor rather than hanging in the air.

**Why the existing test passed.** `check_beartrap_hold.gd` teleported the player onto the trap and
called `_on_body_entered` by hand, so velocity was already zero at the moment of the snap — it was
asserting that a *stationary* player stays stationary. It now walks in under `ai_move_dir` and
asserts the speed at the moment of the snap as well.

**General lesson.** In a physics loop, "skip the input handling" and "stop the body" are different
statements. Any early return in a function that writes `velocity` leaves the previous frame's value
live for whatever runs after it.

---

## Issue 50 — An audio-bus duck survives `change_scene_to_file`, so one level silences every level after it

**Symptom.** The Backrooms had no music when entered from the Corridor, but played normally when
its scene was loaded directly (2026-08-15: *"the music in the backroom disappeared after I got
there from the corridor. But when I started the backrooms scene from scratch, the music was
there"*).

**Root cause.** `corridor.gd:_tick_hush()` tweens the global `Ambience` bus to **−40 dB** at 296 m —
the deliberate silence before the ending — and never restores it. `AudioServer` buses are
**process-global**: `change_scene_to_file()` frees the scene and leaves every bus volume exactly
where the last level left it. `AudioBuses.ensure()` early-returns on an existing bus without
touching its volume, and every per-level bed bus is routed INTO `Ambience`, so the Backrooms' score
arrived already attenuated by 40 dB.

⚠️ **The reported symptom understated it.** Nothing restores that bus, so this silenced the ambience
of *every* level for the rest of the process — KONTUR, the dungeon, the Lab on a revisit. It was
only noticed at the very next transition.

**Fix.** Two layers, deliberately:

1. `AudioBuses.reset_all()` — called from `GameState.start_current_level()`, so every level starts
   with the mixer at unity no matter which ducking path leaked. This is the guarantee, and it also
   covers the same latent shape in `dungeon.gd:_duck_bus()` (no `_exit_tree` guard).
2. `corridor.gd:_exit_tree()` restores `Ambience` itself, so the level cleans up after itself
   rather than relying on the guarantee. `silence_zone.gd` already used this belt-and-braces shape.

**Why no existing test could see it.** Every audio test loads ONE scene and asserts within it. This
fault exists only in the seam BETWEEN two scenes, so `check_bus_leak.gd` drives a real level
transition and asserts the arrival: without the fix it reports `Ambience −40.0 dB` and the music at
−44 dB through the chain.

**General lesson.** Anything that lives on a server rather than in the scene tree — audio buses,
physics parameters, `Engine.time_scale`, `Input` mouse mode — outlives the scene that set it. If a
level mutates global state, either restore it in `_exit_tree()` or reset it centrally on load; and
prefer both, because the level that forgets is the one that will not have a test.

---

## Issue 51 — `hit_from_inside` defaults to false: a ray that STARTS inside a shape reports nothing

**Symptom.** After widening several interact colliders so they could be hit from an angle, the
prompt vanished at the CLOSEST range — standing in a doorway with a slam door, E did nothing, while
stepping back a metre made it work again. `check_purge_interact.gd` began failing on the very fix
that was supposed to make interaction easier.

**Root cause.** `PhysicsRayQueryParameters3D.hit_from_inside` defaults to **false**, so a ray whose
ORIGIN lies inside a shape does not report that shape at all. Interact volumes here are deliberately
non-solid (layer 2, mask 0 — `note.gd`'s convention: raycast-hittable, invisible to movement), so
the player walks straight through them. The moment those volumes were given real depth, standing in
a doorway put the camera inside the box.

⚠️ Thin colliders hid this by being too thin to stand in — the same defect from the other side. Deep
volumes fix oblique approach and break point-blank; the two symptoms have one cause.

**Fix.** `query.hit_from_inside = true` in `player.gd:_get_raycast_target()`.

**General lesson.** ⚠️ This is the exact complement of **Issue 40** (a *shape* query reports nothing
when it is wholly inside a solid). Godot's containment defaults are consistently "inside means no
hit", and that is a silent answer, not an error. When a query starts somewhere the player can stand,
decide explicitly what containment should mean.

---

## Issue 52 — CSG colliders are not registered during `_ready()`, so clearance raycasts answer against an empty world

**Symptom.** Three mirror figures were spawned in `corridor.gd:_ready()` by the same call with the
same clearance rules; exactly one appeared. No error, no warning — `Watcher.spawn()` simply returned
`null` for two of them.

**Root cause.** `Watcher.spawn()` validates a placement with raycasts (`_fits()`). The Corridor
builds its geometry from `CSGBox3D` in the same `_ready()`, and CSG colliders are not registered
with the physics server until the next physics frame — so the probes were querying a world with no
geometry in it and returning arbitrary results. Calling the identical spawn from a test probe at
t = 1 s placed all three every time, which is what pointed at timing rather than at placement.

**Fix.** Queue the positions during `_ready()` and spawn them from the first `_process` tick, once
physics knows about the level.

⚠️ A second, unrelated cause was hiding behind the first: `Watcher` is an apparition by default — it
expires at `MAX_LIFETIME` and rolls to vanish whenever the player looks away and back. These are
fixtures, so they need `persistent = true`. Both had to be fixed before three figures survived.

**General lesson.** ⚠️ Same family as **Issue 40** — the `_fits()` clearance machinery again, a
different failure mode. A physics query made in the same frame as the geometry it is asking about is
not wrong, it is *early*, and an empty world answers every question cheerfully. If a spawn validates
against level geometry, run it after a physics frame.

---

## Issue 53 — A SubViewport mirror renders the wall it is mounted on unless `near` is pushed to the mirror plane

**Symptom.** The project's first real mirror — a `SubViewport` with a reflected camera, replacing a
painted PNG — rendered as a black rectangle with a strip of blue sky across the top.

**Root cause.** The virtual camera sits as far BEHIND the glass as the player stands in front of it,
which puts it inside and behind the wall the mirror is hung on. Looking back toward the corridor,
the first thing it meets is that wall, so the reflection was the inside of the masonry; the sky came
through where the ceiling slab ran out.

**Fix.** Push the reflection camera's `near` plane out to the distance from the virtual camera to
the mirror PLANE — `absf(local.origin.z)` in the mirror's own local space, where the plane is z = 0.
That clips away everything between the camera and the glass, wall included, leaving exactly the half
of the world the mirror should show.

⚠️ Clipping the wall also clips the ceiling, so the sky leaked through the gap. The fix for that was
the one the Lab and House already use: a **black background** on the environment, so any geometry
gap reads as darkness. A mirror is simply the first thing in this project that could ever see out.

⚠️ Two further traps in the same build, both silent: the reflected basis needs **two** axes negated
(negating z alone leaves an improper, inside-out frame), and a `SubViewport` child left at its
default `UPDATE_ALWAYS` renders a second full scene pass every frame for every mirror.

**General lesson.** Playbook diagnostic step 4 — *suspect the camera before the geometry* — applies
to cameras you placed yourself. When a render is black, ask what is between the camera and the
subject before asking what is wrong with the subject.

---

## Issue 54 — `Object.get()` reads properties, not `const`s, so a test predicate matched nothing and passed

**Symptom.** A test that walked the scene tree looking for mirrors reported `0 found` against three
mirrors that provably existed and were rendering.

**Root cause.** The predicate was `n.get("MIRROR_ONLY_LAYER") != null`, and `MIRROR_ONLY_LAYER` is a
GDScript **`const`**. `Object.get()` reads *properties*; constants are not properties, so it returns
`null` for every node — including the ones that define it. The predicate could never be true.

**Fix.** Match on something that exists at runtime (the node name and its child structure), and read
the constant from the script rather than the instance: `node.get_script().get("MIRROR_ONLY_LAYER")`.

**General lesson.** ⚠️ Same reflection family as **Issue 45** (`bool(node.get("missing_property"))`
hangs a test forever). `get()` fails *quietly* for a const and *loudly* for a missing property, and
the quiet one is worse: a duck-type predicate that matches nothing does not error, it simply reports
that the thing you are looking for is not there. **A test whose search returns zero should assert
its own sample size** — several tests in this project now do exactly that.

---

## Issue 55 — A hidden `Node3D` light emits nothing, so a beat "lit by the candle alone" had no light at all

**Symptom.** The Intro Room's note table — the one place the player is *required* to stand still and
read, and the only half of the exit lock they can fail to satisfy — was unlit after the light-switch
reveal. Nobody reported it as a bug, because "the room is dark" is what a horror game looks like.

**Root cause.** Two independent faults on the same object, and each hid the other.

1. `_darken_scene(0.0)` sets `candle_light.visible = false` for the blind fumble. `_on_switch_flipped()`
   tweened `light_energy` back up to `BASE_ENERGY` — and never restored `visible`. **A `Node3D` light
   with `visible == false` contributes nothing to the scene no matter what its energy is.** A driven
   probe measured `visible=false, energy=1.972`: a perfectly well-lit light that was switched off.
2. There was no candle. `_build_table_note_candle()` created a `Table`, a `Note` and an `OmniLight3D`
   named `CandleLight` — and no mesh. The light hung 2.2 m above the table, a metre under the ceiling.
   The hand-built `.tscn` had a candle before the room was rebuilt procedurally; the rebuild kept the
   light and dropped the emitter.

Compounding it, `_on_switch_flipped()` deliberately leaves the ceiling tube above the table dead, on
the documented grounds that "the note is lit by the candle alone". With the candle dark, that comment
described a design that had never once run.

**Fix.** Restore `visible` alongside the energy tween; build a real candle (collar, stub, wick, flame)
and put the light AT the flame. The flame is the room's only emissive surface, so it is hidden by
`_darken_scene()` too — otherwise a lit-looking candle throwing no light would give the blind fumble
a landmark it must not have, and would contradict the twist ending's dead candle.

**Why existing tests missed it.** This is the instructive part. `tests/check_intro_beats.gd`'s own
header states the beat as *"the tube over the table stays dead, so the note is lit by the candle
alone"* — and it asserted **the dead tube** and never **the lit candle**. It encoded the absence half
of its own sentence and skipped the presence half, so it passed 19/19 for the entire life of the bug.

**General lesson.** ⚠️ **When a design sentence has the shape "X is off SO THAT Y is on", the test
must assert Y.** Asserting X alone is strictly easier to write and proves nothing about the beat —
switching Y off entirely still passes. The same shape is worth grepping for elsewhere: any comment
containing "so that", "which means" or "alone" is a claim with two halves and probably one assertion.
⚠️ Secondary: `visible` and `light_energy` are independent, and only one of them is obvious from a
property dump that shows a healthy number.

---

## Issue 56 — `check_wall_overlap.gd` asserts a minimum clearance and no maximum, so a door 27.5 cm off its wall passed

**Symptom.** Playtest capture, in the user's words: *"The door is not connected to the wall."* Seen at
a grazing angle, the Intro Room's exit door stood free of the wall with a black slot and a red
emissive edge beside it, and floor visible at the slot's base.

**Root cause.** `EXIT_DOOR_POS` was a hand-written literal (`z = -8.5`) rather than being derived from
the wall it hangs on. `WallBack`'s inner face is at z = −8.85, and with `DOOR_SIZE.z` 0.15 the leaf's
back face landed at −8.575 — **0.275 m of open air, full height, full width**. Sideways rays fired
through that strip at y = 0.30 / 1.10 / 2.00 / 2.30 all returned *clear*. Every other level derives
its door position from a `RoomBuilder` wall face and seats the leaf ~25 mm INTO the wall; this room is
hand-built and had no such derivation.

It also silently broke the game's **final beat**: `_corrupt_room()`'s planks are computed from
`EXIT_DOOR_POS` — correctly, and that derivation was itself a 2026-07-27 bug fix — so they inherited
the error and hung 0.485 m in front of blank concrete, boarding over a doorway that was not there.

**Fix.** Derive `EXIT_DOOR_POS` from `WALL_BACK_FACE_Z` and `DOOR_SIZE`, and add a jamb/lintel casing
so the leaf reads as recessed rather than merely flush. Both the door and the planks now measure
correct without either constant being written down.

**Why existing tests missed it.** `check_wall_overlap.gd` — the project's dedicated guard for exactly
this bug family — passed the scene with 27 boxes and 0 problems. It asserts that a `QuadMesh` clears
every CSG box by **at least** 2 cm and that no two CSG faces are **within** 2 mm. Both are *minimum*
clearances. There is no *maximum*, so a prop that has drifted away from its wall is invisible to it:
the check is built for "these two surfaces are fighting" and this is the opposite failure.

**General lesson.** ⚠️ **A wall prop has two ways to be wrong and the suite only checked one.** Too
close z-fights; too far floats. `tests/check_intro_geometry.gd` is the other direction and asserts
with rays, not transforms — the transform said the door was fine for the life of the bug, whereas a
ray fired across the strip between the wall face and the leaf reports "clear" and cannot be argued
with. ⚠️ Corollary, and the reason this shipped: **never hand-write a coordinate that describes a
relationship.** `RoomBuilder.wall_point()` exists so the graph levels cannot make this mistake; the
two hand-built rooms had no equivalent and one of them made it.

---

## Issue 57 — A three-stage gate opened at stage one, because the "gate" was a cover

**Symptom.** Playtest 2026-08-16, capture #3, in the user's words: *"Even though I did not pull the
case till the end, I still could flip the breaker."* The Lab's Records breaker is supposed to be
earned twice — read a note in the opposite corner of the floor, then fill a mash bar **three times**
(`LabLocker.SHOVES_NEEDED = 3`, deliberately staged after a previous playtest called one bar "too
simple"). The player got it after two.

**Root cause.** Nothing anywhere checked that the push had FINISHED. The locker was the only thing
standing between the interaction ray and the panel, so the gate was made of **occlusion**, and
occlusion degrades continuously:

| state | locker spans x | breaker collider spans x | exposed |
|---|---|---|---|
| at rest | −9.50 … −8.50 | −9.40 … −8.60 | none |
| after 1 of 3 shoves (+0.45) | −9.05 … −8.05 | −9.40 … −8.60 | 0.35 m (44 %) |
| after 2 of 3 shoves (+0.90) | −8.60 … −7.60 | −9.40 … −8.60 | all of it |

Measured in the engine afterwards (`tests/check_lab_breaker_gate.gd`, three standing positions in
Records' west half × two aim points): after **one** shove the panel answers a ray from **0/3**
positions — the locker is 2.0 m tall and the breaker sits at y = 1.1, so at eye height the edge still
occludes it. After **two** it answers from **2/3** aiming at the panel centre and **3/3** aiming at
the strip the shove uncovered. So the shipped bypass was two bars of three, not one.

`_abort()` then made it worse by lying about it: it toasted *"You let go. The locker settles back."*
while moving nothing, and the maintenance note said the same false thing (*"it slides back the moment
you stop"*). A player who stopped after two shoves was told the cover had closed while the panel
behind it was fully clear.

**Fix.** `breaker.gd` gained `blocked` + `unblock()` + `can_interact()`, and `level_1.gd` sets
`blocked = true` on the Records breaker, clearing it only from `LabLocker.moved` — which fires after
the third bar and the settle tween. `player.gd:_update_interact_prompt()` has consulted an optional
`can_interact()` since the locker itself needed it, so the breaker is now *completely inert*: no
prompt, no interact target, E does nothing. The restore path (`move_aside_instantly()`, which
deliberately does not emit `moved`) calls `unblock()` explicitly. Both toast and note were rewritten
to describe what actually happens: progress is kept, only the brace is lost.

**Why existing tests missed it.** `check_lab_locker.gd` drove the mash to COMPLETION and then asserted
the breaker was reachable. Every intermediate state was untested, and the one number it did check —
"three shoves slid the locker fully aside, travelled ≥ 1.2 m" — is about the locker, not about the
breaker. The new test drives `player.ai_interact()` at 1 and 2 shoves and carries a positive control
that clears `blocked` and proves the identical drive DOES throw the breaker.

**General lesson.** ⚠️ **Occlusion is not a permission system.** Anything whose difficulty is "you
cannot reach it yet" needs a flag that flips at the moment the gate is satisfied; a physical object in
the way is a *depiction* of that flag, and it degrades gradually while the flag does not. And
⚠️ **when a QTE keeps partial progress, do not print a message saying it was lost** — the false toast
is what turned a discoverable exploit into an invited one.

### AMENDMENT (2026-08-16, the very next replay) — a flag alone is not enough either

The fix above shipped, and the same player hit the **opposite** complaint at the same prop:
*"I did 2 out of 3 rounds. Even though I cannot flip the breaker, I can see it very well. I should
not see it fully once I do all 3 out of 3."* The gate held — they confirmed they could not throw it —
and they still filed it as broken, because **a prop in plain sight that refuses to answer E reads as a
bug, not as a locked door**. The lesson above is right about permission and wrong about presentation:
the flag is what *decides*, but the player only ever sees the occlusion, so the occlusion has to agree
with the flag at every stage.

So the locker's travel was **front-loaded onto the last bar**: two intermediate lurches of 0.14 m
(inside the 0.35 m the carcass now overhangs the panel by — the locker went 1.0 m → 1.4 m wide to buy
that budget), then the third bar slides the remaining 0.82 m and actually reveals the thing. Measured
by ray-sampling the panel's front face on a 13×17 grid from six realistic eye positions
(`check_lab_breaker_gate.gd`, 5304 rays):

| | uniform 0.45 m lurches | front-loaded |
|---|---|---|
| after 1 shove | 15.4 % of the panel visible | **0.0 %** |
| after 2 shoves | 84.6 % visible | **0.0 %** |
| after 3 (the slide) | 100 % | **100 %** front-on |

⚠️ **None of the difficulty constants moved.** `SHOVES_NEEDED`, `PUSH_PER_PRESS`, `PUSH_DECAY` and
`PUSH_PANIC` are the user's call and are untouched; the same three bars at the same mash rate cost the
same panic. Only what is *visible* at each stage changed. ⚠️ **Amended lesson: a staged gate must
stage its APPEARANCE, not just its permission.** If progress is shown by a moving object, the object's
motion profile is UI, and uniform steps are the wrong profile whenever the final step is the one that
means something.

---

## Issue 58 — A Tween started in the same frame as `NoteUI.show_note()` never runs: the reveal played to an empty room

**Symptom.** `kontur_mailbox.gd`'s own header has said, since it was written: *"the first interact()
swings it before the note appears, so the note reads as having come OUT of the box rather than off the
wall."* It never did. The slot-12 door was still shut behind the fullscreen note and swung open only
after the player closed it — i.e. the beat played to nobody, every time, for the prop's whole life.

**Root cause.** Four lines:

```gdscript
var t := create_tween()
t.tween_property(door_hinge, "rotation_degrees:y", OPEN_ANGLE_DEG, SWING_TIME)
...
NoteUI.show_note(hint_text)      # <- pauses the tree, in the SAME frame
```

A `Tween` does not advance until the next frame, and `show_note()` sets `get_tree().paused = true`,
so that frame never arrives. Measured: the hinge is at **0.0°** in the frame the note appears with the
old ordering, and at **105.0° of 105** with the fix (`tests/check_open_then_read.gd`, verified by
temporarily restoring the old two-liner and watching the check go red).

**Fix.** Fire the note from the tween's `finished` signal. Connected, never awaited (Issue 6). The
already-open path skips the tween entirely so a re-read is instant rather than waiting on a tween that
will not run again, and a missing hinge falls straight through to the note rather than stranding it.

**Why existing tests missed it.** Nothing had ever asserted the ORDER of two things that both
"happen". `check_kontur.gd` asserts the mailbox exists and yields its hint; the hint arrived, so it
passed. This is the same shape as the door-clearance check that measured un-swung doors because it
read the transform in the frame it requested the swing — **a test that asks a question in the same
frame it causes the answer is measuring the past.**

**General lesson.** ⚠️ **Anything that pauses the tree is a hard barrier to every Tween in flight.**
`NoteUI`, `JournalUI`, `CombinationLock` and `MazeChaseUI` all pause. If a prop is meant to be SEEN
doing something before a paused UI appears, the UI call belongs in the tween's `finished`, not on the
next line. `lab_cabinet.gd` (written in the same pass) is built that way from the start, and
`kitchen_drawer.gd` still has the original bug — recorded in `backlogs/00-cross-level.md`, since it is
a House file.

---

## Issue 59 — An outward ray fan cannot detect "inside a wall": CSG backfaces do not collide

**Symptom.** While writing an independent clearance check for the Lab's nook figure, a probe spot
**1 m beyond SouthHall's north wall** — outside every room, through solid masonry — was reported
CLEAR by a 12-ray horizontal fan cast outward from that spot.

**Root cause.** Godot's concave (trimesh) collision, which is what CSG produces, has
`backface_collision = false` by default. A ray that STARTS inside or beyond a slab and travels
outward crosses that slab's triangles **from behind**, and backfaces do not report. So an
outward-only fan happily approves exactly the case a clearance check exists to reject. It is Issue
40's neighbour: there, a shape query wholly inside a slab reported nothing; here, a ray from inside a
slab reports nothing.

**Fix.** The **line-of-sight ray from the player's eye to the figure's chest is not optional** — it is
the member of the set that catches this, because that segment must cross the slab's near face from the
FRONT. `apparition.gd:_fits()` has always had it and `CLAUDE.md` says so in passing; the new
`level_1.gd:_figure_fits()` and `tests/check_nook_figure.gd` both lead with it, and the test carries a
positive control at the exact coordinates above so the omission cannot come back quietly.

**Why existing tests missed it.** There was no clearance test for this figure at all — its placement
had an unvalidated fallback (see the Lab notes) and nothing measured it.

**General lesson.** ⚠️ **"No ray hit anything" means "nothing is in the way" only if the ray started
somewhere legal.** Clearance checks must include at least one ray that begins at a point known to be
in open space — the player's eye is the one always available.

---

## Issue 60 — Three gurneys shared one node name, so two of them were silently renamed

**Symptom.** A new test tried to find the gurney frame under a covered body with
`name == "GurneyFrame"` and matched exactly one of three beds. The other two had become
`GurneyFrame2` and `GurneyFrame3` without any warning, message or error.

**Root cause.** `intro_room.gd:_build_gurney()` set `frame.name = "GurneyFrame"` (and
`"GurneyMattress"` / `"GurneyMattressArt"`) for every bed it built. `Node.add_child()` guarantees
sibling names are unique and resolves a clash by appending a number — quietly. This is **Issue 17,
the fourth instance in this one file**: the ceiling tubes, the cobwebs and the sheeted forms had all
been given position-derived tags for exactly this reason, and the gurneys underneath them had not.

**Fix.** All three now carry the same `"%.0f_%.0f"` position tag the sheeted forms use
(`GurneyFrame_45_60`, …). The test looks up by `begins_with("GurneyFrame")` **and** takes the
nearest, so it does not depend on the tag scheme either.

**Why existing tests missed it.** Nothing had ever looked a gurney up by name. The renaming has no
runtime effect until something does — which is precisely why it survives so long, and why it is
worth fixing at the moment the first lookup appears rather than after the lookup silently measures
the wrong bed.

**General lesson.** ⚠️ **A procedural builder called in a loop must derive the node name from the
loop variable.** A constant literal name inside a builder is a latent Issue 17 the moment that
builder is called twice, and the failure mode is not an error — it is a name-based lookup finding
one of N and reporting success.

---

## Issue 61 — `surface_get_arrays()[ARRAY_INDEX]` is null for an unindexed mesh, and the throw ate the rest of the test

**Symptom.** Proving that `check_intro_sheet.gd` could fail — by rebuilding the rejected
box-based prop and re-running it — produced this and then nothing:

```
SCRIPT ERROR: Trying to assign value of type 'Nil' to a variable of type 'PackedInt32Array'.
      at: _check_form (res://tests/check_intro_sheet.gd:109)
```

One `OK` line, one error, and **every remaining assertion for that form never ran**. The test still
printed a summary and still returned an exit code, so from the runner's point of view it had
"checked" the build.

**Root cause.** `ArrayMesh.surface_get_arrays()` returns `null` in the `ARRAY_INDEX` slot for a
surface committed without indices. Assigning that to a typed `var idx: PackedInt32Array` throws, and
a throw inside `_process` aborts the rest of the call — including the assertions that would have
reported the problem.

**Fix.** Type-check the slot and fall back to sequential indices, so the mesh is still walked and
the "it is ONE welded surface" assertion is what reports it. Same shape as the standing rule against
`bool(node.get("flag"))` in a test.

**Why existing tests missed it.** It was found by *deliberately breaking the build to prove the new
test could go red* — which is the only reason it was found at all. A test that is only ever run
against a passing build never exercises its own error paths.

**General lesson.** ⚠️ **Proving a check can fail is not a formality; it is where the check's own
bugs live.** Run every new assertion against a deliberately broken build before trusting a green
one — and inside a test, treat any engine call that can return `null` as a value to be checked
rather than assigned to a typed local (Issue 45's neighbour).

---

## Issue 62 — A measurement that was physically correct and perceptually wrong: absolute luminance instead of contrast

**Symptom.** The Lab's BreakerNook panel is the one prop in the game whose entire design is
*you cannot see it* — the wing force-locks the flashlight and the breaker is found by an audio
beacon. A probe was written to check it (`tests/screenshot_nook_panel.gd`), it reported

```
peak ≈ 1.5 of 255 · wall 0.0000 · "does not leak"
```

and the backlog closed the item with no change. The player then replayed the level, stood
**9.4 m** away in a room with the torch off, took a screenshot and wrote: *"I am standing far
away from the breaker and I see it. Should be darker."* The frame is essentially pure black with
a legible pale rectangle and a lighter outline in the middle of it.

**Root cause.** Three independent faults in the measurement, none of which made the numbers look
wrong:

1. **ABSOLUTE instead of CONTRAST.** 1.5/255 is negligible *against a lit room*. Against a
   background of literally `0.0000` it is the only thing in the frame, and a dark-adapted eye on
   a real display finds it instantly. Re-measured properly, the panel's brightest pixels were
   **4.1/255 against a wall averaging 0.3/255** — Michelson contrast **0.86**, and **856 of 9153
   panel pixels (9.4 %) brighter than anything in the wall around it**, at 6, 10 and 15 m alike.
2. **MEAN of an 11×11 box at the CENTRE.** The leak was the panel's bright *border*. The sample
   box was positioned exactly where the leak was not, and averaging would have buried it anyway.
3. **HiDPI pixel coordinates.** `Camera3D.unproject_position()` returns **viewport** coordinates
   (1152×648 here) while `get_texture().get_image()` returns the **rendered** image (3024×1701) —
   a factor of 2.625. The un-scaled sample landed a third of the way in from the top-left corner
   of where the panel actually was, i.e. on plain wall. This is why fault 1 was never even
   reached: the probe was reporting the wall's luminance and calling it the panel's.

A fourth, smaller one showed up while fixing it: the crosshair is a **pure white dot at the exact
aim point**, so the first corrected run reported `panel max 1.0000` — the reticle, not the prop.
Every `CanvasLayer` is now hidden before the capture.

**Fix.** The probe was rewritten to project the panel's own front face, sample its **whole**
screen bounding box, report **max** and the 99.5th percentile rather than the mean, and compare
against a **ring of wall pixels around it** instead of an absolute floor. It also prints the count
of panel pixels exceeding the ring's own maximum — the "is there anything here an eye can latch
onto" question, in pixels — and re-measures at the player's exact capture pose, not only on its
own convenient sightline. `tests/check_nook_dark.gd` is its headless companion.

**Why existing tests missed it.** There was no test; there was a probe, and the probe was the
thing that was wrong. Nobody had ever run it against a deliberately-visible panel to see it go
red — the number it printed was small, and small numbers read as success.

**General lesson.** ⚠️ **Perception is differential. Measure a difference from the local
background, never a level.** Any assertion of the form "this is dark enough / quiet enough /
small enough" that names an absolute threshold is measuring the wrong quantity, and it will pass
most reliably in exactly the conditions where the fault is most visible — because that is where
the background is lowest. ⚠️ And **sample the MAX, not the mean**: a thin bright border averages
away to nothing, and it is the border the eye finds. ⚠️ Finally, in any probe that mixes
`unproject_position()` with `get_image()`, **convert the coordinates** — the two do not use the
same pixel space on a HiDPI display, and the failure mode is silently measuring the wrong part of
the frame.

---

## Issue 63 — A baked alpha checkerboard shipped as opaque near-white pixels, and near-white is the brightest thing this renderer can make

**Symptom.** The cause behind Issue 62. `lab_breaker_panel.png` — the fuse-box art on all three
Lab breakers — rendered with a distinctly pale outline around it, visible as a rectangle-with-a-
border in a pitch-black room from 9.4 m, and as an obvious white frame around the panel in a lit
one (playtest capture 002).

**Root cause.** The file was an **8-bit RGB PNG with no alpha channel** whose background was the
light two-tone **transparency checkerboard** an image editor draws to *represent* transparency.
Nothing in an engine can know that is meant to be nothing: it is opaque pixel data at
(254,254,254)/(243,243,243). Measured, **20.05 % of its texels were above 0.90 sRGB luminance**
and the outer 2 % border ring averaged **0.974** — i.e. the prop was mostly white paint.

That matters more here than it would elsewhere. This project has **no glow, no fog and no
tonemapping**, and light energy is ~0.45, so a surface's rendered brightness is very nearly
`albedo × ambient`. Near-white albedo is the maximum achievable brightness in the game, and it
was applied to the one object designed to be invisible.

**Fix.** `tools/flatten_alpha_checker.py` — flood-fills the background inward **from the image
border**, over near-neutral near-white pixels only, repaints it dark and crops to content. The
flood fill is reachability-limited rather than threshold-limited, so it cannot eat a cream label
or a specular highlight inside the artwork (the LOAD CENTER card survives intact). The original
is preserved at `assets_src/textures/level_1_lab/lab_breaker_panel_raw.png`, per that folder's
rule that a destructive pipeline's input must survive.

Measured, torch locked off in BreakerNook, panel vs the wall beside it:

| | panel max | panel p99.5 | wall max | px brighter than the wall |
|---|---|---|---|---|
| shipped | 4.1/255 | 4.1/255 | 3.0/255 | 856 of 9153 (9.4 %) |
| checkerboard flattened | 3.1/255 | 2.0/255 | 3.0/255 | 0 |
| + dim albedo tint on the `glows = false` breaker | 1.0/255 | 0.0/255 | 3.0/255 | 0 |

**Why existing tests missed it.** Nothing had ever looked at a texture's *content*. The project's
existing texture guards check that a file imports (`ResourceLoader.exists`, Issues 1 and 25) —
i.e. that it is a real PNG — never what is in it. `check_nook_dark.gd` now measures the shipped
texture's near-white fraction and its border ring, and compares the panel's effective linear
albedo against the wall's.

**General lesson.** ⚠️ **A transparency checkerboard is data, not metadata.** Any supplied cutout
that is not RGBA is carrying its background as paint. The existing rule "a billboard texture must
be a real RGBA cutout, or it renders as a solid rectangle" is the same fault seen from the shape
side; this is the same fault seen from the *brightness* side, and it is easier to miss because
the prop still looks broadly correct. ⚠️ Run `file` on new art (Issue 25) **and** look at its
histogram.

---

## Issue 64 — A `StaticBody3D` teleported from `_process` is still at its old position for that frame's raycasts

**Symptom.** `check_lab_breaker_gate.gd` moved the Records locker to simulate 1 and 2 completed
shoves and immediately cast rays at the breaker behind it. Every number it printed was plausible,
and its headline finding — *"after two shoves the panel answers a ray from 3/3 positions"* — was
really the **one**-shove state. A new visibility probe written in the same style reported 0.0 %
of the panel visible with the locker parked a metre clear of it, which is what exposed it.

**Root cause.** The physics server is updated between frames. A `StaticBody3D` whose
`global_position` is written from `_process` (or from a `SceneTree` script's `_process`) does not
reach the physics world until the next physics tick, so `intersect_ray` in the same frame answers
against the **previous** transform. The phase machine advanced one stage per frame, so every
stage measured the stage before it — an off-by-one that is invisible because each stage's numbers
individually look reasonable.

**Fix.** Every stage is now two frames: one to move the locker, one to measure. Named phases
(`set0`/`zero`, `set1`/`one`, …) so the split is impossible to collapse by accident.

**Why existing tests missed it.** This *was* the test. It is the mirror image of Issue 58 and of
the door-clearance check: **a test that asks a question in the same frame it causes the answer is
measuring the past.** Issue 58 was a Tween, this is the physics server; the shape is identical.

**General lesson.** ⚠️ **Teleport, then wait a frame, then query.** If a test moves a body and
asserts anything physics-derived — raycast, overlap, `move_and_slide` — the move and the
assertion must be in different frames. ⚠️ And when a set of staged measurements all look
individually plausible, check that stage *n* is not reporting stage *n−1*: add a stage whose
answer you already know (here, "0 shoves must be fully occluded") at the start of the sequence.

---

## Issue 65 — A proud interact volume intercepted the rays aimed at the drawer below it: 6 of 8 drawers were unreachable

**Symptom.** The Records filing bank was rebuilt as a search — eight drawers, one holding the
Flood hint. Its reach check reported **2 of 8** drawers answering E from a realistic pose (1.1 m
back, 25° off-axis, aiming at the drawer's own face mesh). Aiming at drawer 3 returned drawer 2;
aiming at drawer 1 returned drawer 0.

**Root cause.** Each drawer's interact volume was 0.20 m deep, positioned `front_z + 0.10`, so it
stood **0.18 m proud of the drawer face, out into the room**. A standing player aims *down* at the
lower drawers of a 1.3 m cabinet — about 50° at the bottom slot — and on the way down that ray
passes through the volume of every drawer above the one being aimed at. The depth that was meant
to make an oblique approach register is exactly what made a downward approach hit the wrong thing.

**Fix.** Depth 0.20 → **0.08**, position `front_z + 0.02`, so the volume's front face is within
~5 cm of the drawer face and still in front of the carcass collider. Measured: 8 of 8.

**Why existing tests missed it.** It was caught on the first run of the check written alongside
the feature, because that check asserts a **count with a denominator** (`8 of 8`) rather than
"a drawer answered". A test that found *one* interactable drawer and stopped would have passed on
a bank where three-quarters of the prop was dead.

**General lesson.** ⚠️ **An interact volume is a solid, and it occludes its neighbours.** For any
vertically stacked rack of interactables — drawers, lockers, shelves, buttons — keep the volumes
shallow, because the player's aim at a low element passes through the space in front of the high
ones. ⚠️ And when a prop has N identical interactive parts, assert **N of N**, never "at least
one": the useful failure here was not "it does not work", it was "it works twice out of eight".

---

## Issue 66 — A child's grab volume shadowed its parent, and an inert child does not fall through: the one drawer holding the note could not be opened

**Symptom.** `check_lab_cabinet.gd` reported **7 of 8** drawers answering E, then 8 of 8, then 7 of 8 —
flaky across runs, and the failing drawer was always a different one. In game this is worse than it
sounds: the drawer that would not open was **the one holding the level's only Backrooms-Flood hint**,
because the page is what caused it.

**Root cause.** Two facts that are individually reasonable:

1. The hint page is a nested `StaticBody3D` *inside* the drawer, with a deliberately generous
   0.52 × 0.20 × **0.30** grab volume so a player can reach into an open drawer from above at an angle.
   At `front_z − 0.08` that volume's front face sat at 0.37 — **1 cm in front of the drawer's own
   0.08 m-deep interact volume at 0.36**. So on a shut drawer the ray hit the page first.
2. `player.gd:_update_interact_prompt()` does this:

```gdscript
_interact_target = _get_raycast_target()
if not _is_interactable(_interact_target):
    _interact_target = null
```

The page's `can_interact()` is false while its drawer is shut — correctly — but the target is then set
to **null**, not to whatever is behind it. A prop that opts out with `can_interact()` still **consumes**
the ray. It is invisible to the prompt and opaque to the search.

Which slot the page occupies is randomised per run, so the fault moved between builds and looked like
flakiness rather than a defect.

**Fix.** The page's collider is `disabled` until the drawer actually opens (`set_active()`, driven from
the slide tween's `finished` and from the restore path), so it is not merely inert but **absent**. Its
depth was also cut 0.30 → 0.22 so the geometry agrees with the flag rather than relying on it. Five
consecutive runs: 8 of 8, 15 of 15 checks green.

**Why existing tests missed it.** They did not — this was found on the second full-suite run, by a
check that asserts **N of N with a denominator**. What nearly hid it is that it is *intermittent*: a
single green run means nothing about a randomised feature, and the first three runs of this test were
green. Anything with a per-run random placement needs to be run repeatedly before it is believed.

**General lesson.** ⚠️ **`can_interact()` returning false makes a prop inert, NOT transparent.** The
optional opt-out was built so a prop could refuse silently; it does not hand the ray on to the thing
behind it. So any interactable nested inside another interactable must be **physically out of the
way** — disabled collider, or geometry that cannot be the nearest hit — for as long as it is not the
intended target. ⚠️ And **run a randomised feature's test several times.** One green run on a feature
that rolls a die is one sample.

---

## Issue 67 — A prop that opens and cannot close: the searchable bank of drawers that blinded itself

**Symptom.** Playtest 2026-08-16 (third replay), J-capture in the Lab's Records room at
(−10.00, 0.00, 11.30): *"There is a bug - I cannot see what is under the top storages. I need to be
able to close them by pressing the E button"*. The screenshot shows two of the eight filing-cabinet
drawers hanging out over the four beneath them.

**Root cause.** `LabCabinetDrawer.interact()` was a **one-shot**, not a toggle:

```gdscript
func can_interact() -> bool:
    return not _open and not _sliding      # once open, gone from the game forever
```

An open drawer slides `SLIDE = 0.34 m` into the room and stands there permanently. That does two
things, and the second is the one that matters:

1. it **hides** the drawer faces below it; and
2. it **shadows** them — a standing player aims *down* at the lower slots, and the descending ray
   crosses the open drawer's own interact volume, which is now 0.34 m nearer the camera.

Measured by ray, from a standing eye position aiming at each drawer's own face mesh: with **one**
drawer open, **6 of 8** drawers in the bank answered E (5 of 8 on another run — it depends which slot
the run rolled the page into). With every drawer shut, 8 of 8. So a bank searched top-down, which is
how anybody searches a filing cabinet, progressively sealed itself, and nothing the player could do
reversed it.

This is the same geometry as **Issue 65** wearing different clothes. There the shadow came from an
interact volume that was too deep; here it comes from a drawer that had no way back in. The lesson
generalises past both: *any prop that moves toward the player on interaction has to be able to move
back*.

**Fix.** `interact()` is a toggle — `close()` runs the slide in reverse (same `metal_creak`, pitched
0.80–0.88 and eased IN rather than OUT), one effortless press in each direction. Three things had to
come with it, and each was a separate way to get this wrong:

- **Which of the two nested props answers the ray is now decided by state, never by aim**
  (`_refresh_layer()`). A single raycast cannot reliably choose between a drawer face and a page lying
  0.10 m behind and below it inside a 0.26 m slot: from the pose a standing player actually uses, a
  ray descending toward the page crosses the face's volume first. So they take turns — shut, the
  drawer answers; open with the page inside, the page answers and the drawer goes inert; open and
  empty, the drawer answers again and E shuts it. The one visible consequence is that the drawer
  holding the page cannot be shut until the page is out of it, which costs a press the player wanted
  to make anyway.
- **The page's grab collider had to follow the drawer in BOTH directions.** Issue 66 disabled it until
  the drawer opened; a drawer that can close again needs the return trip, and `close()` disables it
  *first*, before the tween starts, not at the end. Left live, this is Issue 66 verbatim: a live grab
  volume inside a shut drawer makes that drawer unopenable, and `can_interact()` cannot save it
  because an inert prop consumes the ray rather than handing it on.
- **Closing resets nothing.** `_searched` survives it (so a drawer you have already emptied does not
  re-print its flavour line as if it were a discovery), and the level's snapshot gained
  `drawers_searched` alongside `drawers_opened` — since the toggle, a searched drawer is no longer
  necessarily an open one, and a back-door return that restored only the open ones would hand the
  player back a bank that had forgotten where they had looked.
  - ⚠️ **AMENDMENT 2026-08-16 (verification replay).** The flavour lines were deleted on the user's
    call — *"they are not needed, the player will see there is nothing in there"* — and that removed
    the only consumer of searched-state. `_searched`, `is_searched()`, `mark_searched()`,
    `searched_slots()`, `mark_slot_searched()` and the `drawers_searched` snapshot key are all gone.
    The bullet above is kept because the *reasoning* is still correct for any future prop that does
    behave differently once searched; what is no longer true is that this prop does.

**Why existing tests missed it.** `check_lab_cabinet.gd` asserted that every drawer opens — from a
build in which every drawer was shut. It never opened two. The reachability check that would have
caught this is the one that already existed for Issue 65; it was simply never run against a bank with
a drawer hanging out of it. **A test that only ever measures the rest state cannot see a state the
prop can get stuck in.**

**General lesson.** ⚠️ **Every prop that moves has a second state, and the second state needs its own
reachability measurement.** The question to ask of any new interactable is not "does it work?" but
"what does the world look like afterwards, and can the player undo it?" A one-shot that leaves
geometry in the player's way is a trap they built themselves and cannot dismantle — and in a dark room
it does not read as a mechanic, it reads as the bug the user called it.

---

## Issue 68 — A fix that satisfied its own constraint and broke an unstated one: two notes moved into the same glance

**Symptom.** Playtest 2026-08-16 (verification replay), J-capture in the Lab morgue: *"These two
notes at the morgue are at the same place. Let's at least put them into different parts of the
room"*. The log agrees — two `NOTE READ` events **1.7 s apart** (`@StaticBody3D@212` at t=177.08,
`@StaticBody3D@346` at t=178.78). One frame contained both pages, side by side, at the same height,
in the same light.

**Cause.** A regression created by the *previous* round's fix, in the same file, two hours earlier.
The TRIAL 7 note had been hanging in the morgue's only doorway (`wall_point("Morgue", (-1,0))`
returns the west wall's centre, which is exactly where the shutter is). The constraint handed to
that fix was "not the doorway wall", and the destination chosen was the south wall **1.6 m from the
note already on it** — deliberately, and the code comment said so: *"the two pages read as one filed
pair, which is what they are"*. The stated constraint was satisfied perfectly. The unstated one —
*two notes in a room have to be two discoveries* — was not, and nothing in the codebase held it.

This is the general shape and it is worth naming: **`wall_point(room, side) + a lateral offset` is
the obvious way to place a second wall prop, and it is the move that produces this defect.** It is
available in every level in this game, and it looks correct in code — a named constant, a derived
position, no hand-computed coordinates, the house style followed to the letter.

**Fix.** The circular keeps the morgue's south wall centre; TRIAL 7 moves to the **north** wall,
offset east of the cursed poster (`MORGUE_TRIAL7_OFFSET = 2.4`, still `wall_point()` plus an offset,
never hand-computed). Measured separation **1.60 m → 6.19 m**, on opposite wall planes. Neither page
left the morgue: both are cross-level hints (KONTUR Gate 1, THE NIGHTMARE's Still Ones) filed behind
the beartrap and the two instant-fail gaze objects on purpose, and that cost is the point.

**Why existing tests missed it.** `check_note_mounting.gd` was written *by* the previous round, and
it asserted exactly the constraint that round was given: a wall behind every prop, and no prop inside
a doorway aperture. The new position passes both — it is a perfectly mounted note 1.6 m from another
perfectly mounted note. **A checker written from the ticket it was born from tests the fix, not the
requirement.**

**Fix to the checker.** It now groups notes by room (reading the level's own `ROOMS` constant map,
the same way it already reads `DOORS`) and asserts, for every same-room pair, both a minimum
separation (`MIN_NOTE_SEPARATION = 2.5 m`) **and** that they are not on the same wall plane —
near-parallel facings with less than 0.5 m of depth between them. Distance alone is the weaker half:
2.5 m along one wall is still one glance. It asserts its own pair count (2 in the Lab), and it
carries the offending pair as a permanent positive control, so "just nudge it along the wall" goes
red for ever. Proved to fail by restoring the shipped position: **2 red**, both halves of the rule.

**General lesson.** ⚠️ **When you fix a placement, check what you have moved it NEXT TO.** A
constraint list is not a specification: satisfying "not there" says nothing about whether "here" is
good. And when a fix is accompanied by a comment explaining why the new arrangement is *nice* — "they
read as one filed pair" — that comment is the tell. It is arguing for an aesthetic nobody asked for,
in the same breath as a repair, and it is the part that came back.

---

## Issue 69 — A door hinged on the wrong edge: +105° swung the fridge door *into* its own carcass

**Symptom.** Playtest 2026-08-16, J-capture in the House kitchen at `(6.10, 0, 7.10)`, 21 s after the
fridge was opened (the log's `+10` panic spike at t=51.49 is `FRIDGE_PANIC` at that exact position):
*"The fridge opens the wrong side — and the head appears not immediately."* **The frame contains no
door and no handle at all.** An open-fronted pale carcass with two shelves and a head in it, reading
as a bookcase.

**Cause.** Arithmetic, and it is worth doing in full because reading the code does not reveal it.
`house_fridge.gd` put the hinge at fridge-local `(−SIZE.x/2, 0, +SIZE.z/2 + 0.01)` = `(−0.39, 0, 0.37)`
and hung the door panel at hinge-local `(+SIZE.x/2, …, 0)`. `interact()` tweens `rotation:y` to
**+105°**. Rotating the free-edge vector `(0.39, 0, 0)` by +105° about +Y gives
`(0.39·cos105, 0, −0.39·sin105)` = `(−0.101, 0, −0.377)` — the leading edge travels toward local **−Z**,
i.e. straight back through the shell, finishing at local `(−0.49, 0, −0.007)`, behind the front face at
`+0.36`. The door and its handle were inside the box, which is exactly why the capture has neither.

An outward swing needed either `−105°` or the hinge on the opposite edge. The hinge moved (the user's
call), because it fixes the swing *and* puts the pivot on the edge furthest along the approach from the
Hallway doorway, so the opening panel uncovers the cavity toward the player instead of sweeping across
the kitchen table.

**And the second complaint was a symptom of the first.** `REVEAL_DELAY = 0.62` is 62 % through a swing
that starts at `DOOR_DELAY = 0.28` and lasts `DOOR_OPEN_TIME = 0.55` — the head is meant to be revealed
*as the door clears it*, and that ordering is a `⚠️ DELIBERATE` decision taken twice on this user's own
feedback. With nothing to clear, 0.62 s reads as an arbitrary pause in front of an already-open box.
The constant was **not** touched.

**Fix.** Hinge at `+SIZE.x/2`, panel and handle at hinge-local `−X`, angle unchanged. The free edge now
sweeps to local `(+0.101, 0, +0.377)`, out through the front face into open air. Also: the lower wire
shelf moved `SIZE.y * 0.40 → 0.34` and the head now rests on it with a stated clearance, because at 0.40
the shelf plane passed through the bottom 7 cm of a `HEAD_HEIGHT = 0.46` face sitting at the same depth
(z 0.06…0.32) — the face read as a decal cut off at the chin, also visible in the capture.

**Why existing tests missed it.** `check_house_guest.gd` asserted that the fridge reports itself open,
that it charges ~10 panic once, and that `FridgeThing.visible` flips. Every one of those is true of a
door that opens backwards. **It measured the state machine and never once measured a position.**

**General lesson.** ⚠️ **A hinge has a sign and an edge, and getting either wrong renders identically
in code review.** For anything that swings, assert the moved part's position **in the parent's own
frame** after the tween has run — "the door's centre is in front of the carcass's front face" is one
line and it cannot be satisfied by a door that folded into the box. The same class already bit
`beartrap.gd` (jaws hinged at the rim and rotating the wrong way rendered as a trap with no visible
jaws) and `choice_door.gd`.

---

## Issue 70 — An `ItemList` nobody could steer: `select()` neither emits nor focuses, and the obvious fix breaks TAB

**Symptom.** Reported in two consecutive playtests, 2026-08-16: *"When I press the tab I cannot navigate
between notes using arrows on my keyboard. I need to click first and only after that arrows are
available"*, and the next session, tersely: *"Still cannot navigate between the notes."*

**Cause.** Two independent facts about Godot that compose into a dead control.
`journal_ui.gd:open_journal()` called `_list.select(0)`. **`ItemList.select()` does not emit
`item_selected` and does not take focus**, and nothing anywhere set `focus_mode` — which on `ItemList`
defaults to `FOCUS_NONE`, so it could not have taken focus even if asked. With no focused Control the
viewport has nowhere to route `ui_up`/`ui_down`, and the keys went nowhere. A mouse click gave the list
focus, which is why clicking "fixed" it.

**⚠️ And the obvious repair breaks something else, silently.** Godot's input order is
`Node._input` → GUI (Control focus, `ui_focus_next`) → shortcuts → `Node._unhandled_input`. TAB is
`ui_focus_next`'s default binding, so the moment *any* Control has focus the GUI layer eats TAB before
`_unhandled_input` runs — and `_unhandled_input` was where this overlay handled TAB-to-close. A bare
`grab_focus()` would have fixed the arrows and made the journal impossible to close in the same commit.
The old code only worked *because* nothing was ever focused.

**Fix.** `focus_mode = FOCUS_ALL`; `grab_focus()` in `open_journal()` — **after** `_root.visible = true`,
since a Control cannot take focus while it is not visible in the tree, which would have been the same
bug in a new disguise. Close handling moved from `_unhandled_input` into `_input()` with
`set_input_as_handled()`, which gets in front of the focus machinery. Focus is released in `_close()`
and in the Issue-9 self-drop path.

**Why existing tests missed it.** `check_journal.gd` drove the overlay entirely through method calls —
`open_journal()`, `_close()` — and asserted `is_open`, the pause state and the archive contents. **It
never pressed a key.** It now pushes real `InputEventKey`s through `root.push_input()` (the only way to
press a key headless; `Input.parse_input_event()` needs a display server) and asserts the selection
index moved, the page text changed with it, and that TAB still closes the panel with the list focused.
Proved to fail both ways: removing `grab_focus()` reddens the arrow checks, and moving the close
handler back to `_unhandled_input` reddens the TAB check.

**General lesson.** ⚠️ **A UI test that never sends an input event is testing your API, not your UI.**
And when adding focus to a previously focus-free overlay, audit every key the overlay already owned:
focus does not merely enable keys, it *re-routes* them, and the ones it steals are the ones the panel
was using.

---

## Issue 71 — A guard pinned to one scene: the note-mounting checker had never run on eight of nine levels

**Symptom.** Playtest 2026-08-16, J-capture in the House cellar: *"This note is floating in the air"* —
the third digit note, seen from ~30° off its normal, with visible air between the page and the wall
behind it.

**Cause.** Two layers.

*The defect:* `level_2.gd` hand-typed the position —
`Vector3(CELLAR_CENTER.x − 1.5, CELLAR_Y + 1.4, CELLAR_CENTER.y − 2.0)` = `(3.5, −0.1, −8.0)`, `y_rot = 0`.
The cellar's south wall inner face is at z = **−9.40**, so the page hung **1.40 m** from the wall it
faced, 1.40 m above the floor, supported by nothing. It was the only note in the level not placed by a
`wall_point()` helper — and the cellar had no such helper, because it is built by hand in
`_build_cellar()` rather than by `RoomBuilder`.

*The reason nobody caught it:* `check_note_mounting.gd` hard-coded `const SCENE = level_1.tscn`, and
`check_wall_overlap.gd` defaults to `level_1.tscn` while `tools/run_tests.sh` invokes it with no
argument. **The two guards that exist for exactly this class of fault had only ever run on one level
out of nine.** The runner has no per-test argument mechanism, which is why nobody had extended them.

**Fix.** A `_cellar_wall_point()` helper in `level_2.gd` with the same contract as
`RoomBuilder.wall_point()` (clearance measured from the wall's *inner* face, 3 cm floor), and the note
hung on the south wall through it. Both guards made scene-parameterised, with the Lab as the default so
the existing suite entries are unchanged, plus two thin wrapper tests
(`check_wall_overlap_house.gd`, `check_note_mounting_house.gd`) registered in `run_tests.sh`. The
wrapper is also the only place the House's two peculiarities can be stated: its cellar is not in
`ROOMS`, and it has exactly one note per room so the same-room separation pass legitimately finds zero
pairs.

**⚠️ And the checker's positive control was itself vacuous off-Lab.** `_self_test()` re-created the two
shipped Lab faults at their real former coordinates — which is a fine control on the Lab and proves
nothing anywhere else, because in another level those two points are in open space and "REJECTED" is
true for the wrong reason. The controls are now *derived from the scene under test*: take a prop this
run just certified as mounted, float a copy 1 m off the same wall along the same facing, and require
the checker to reject it; and take the level's own first `DOORS` entry and require `_in_doorway()` to
name it.

**Why existing tests missed it.** They were pointed somewhere else. That is the whole issue.

**General lesson.** ⚠️ **A guard with a hard-coded scene is a guard for one scene, and the file name
will not say so.** When a check encodes a *rule* rather than a fact about one level, parameterise it on
day one and give every level a wrapper — and when you do, re-read the positive control, because a
control built from one scene's coordinates degrades into a no-op everywhere else while still printing
PASS.

---

## Issue 72 — A scripted set-piece that played to a player who could not look: `SceneTreeTimer` fires through a pause, and `require_los = false` disabled the only embed detector

**Symptom.** Playtest 2026-08-16, J-capture in the House cellar: *"Please double check that I will
always see that doll. This time I saw it from the angle but maybe I just spin the camera in that way,
not sure."*

**Cause.** Two faults, in the same twenty lines, both of which the log settles.

*(a) It fired while the player was pinned in a beartrap.* The log's `+15` spike at t=205.48 is
`Beartrap.ESCAPE_INITIAL_PANIC` exactly, logged 0.63 m from the cellar trap; `beartrap.gd` then calls
`begin_qte()` and opens a 7-second countdown UI. The child spawned at **t=206.98** and was freed at
**209.98** — the entire appearance sat inside that QTE, with a UI over the screen and the player unable
to move. The placement code did what it was told: 3.20 m dead ahead, exactly `CHILD_DIST`. What it was
not told is that the player was pinned. `_begin_cellar_blackout()` armed a bare
`get_tree().create_timer(...)`, and **`SceneTreeTimer` defaults to `process_always = true`, so it fires
straight through a tree pause too** — an open note or the journal would have done the same thing.
`apparition_director.gd` refuses to fire on all three of `NoteUI.is_open`, `get_tree().paused` and
`player.is_input_frozen()`, and was the only thing in the project that did.

*(b) The clearance ladder below it was dead code.* `_cellar_child_appear()` called
`Watcher.spawn(..., require_los = **false**, ...)`. `watcher.gd`'s own header restricts that argument to
`congregation.gd`, because **the line-of-sight ray is the only probe that catches "this point is inside
a wall"**: `_fits()`'s other three tests (head room, top-down column, 16-ray fan) all originate *inside*
the slab for an embedded candidate and, against a concave CSG trimesh, cross no faces and report clear
(Issues 40 and 59). So the first candidate at 3.2 m essentially always passed, the `[3.2, 2.4, 1.8]`
ladder and the room-centre fallback never ran, and a player facing a wall from a metre got a figure
buried in it with the scream still playing.

**Fix.** `_cellar_child_appear()` re-arms itself on a 0.25 s timer while any of the three conditions
holds, and `require_los = true` on every spawn attempt. ⚠️ It also has a `CHILD_POSTPONE_MAX = 45 s`
safety valve that gives up on the figure and hands the lights back, because the end of the blackout is
armed *by* the appearance — a beat that postpones for ever would leave the player with no lamps and no
torch, which is worse than the bug being fixed.

⚠️ This guard is now **load-bearing**, not belt-and-braces: the user was shown the measurement for the
cellar beartrap (1.6 m past the blackout trigger, on the only heading in, inside an 8.5 s window with no
lamp and no torch, and it fired in both sessions) and chose to leave the trap exactly where it is. The
collision will keep happening; the postponement is the only thing preventing the original complaint.

**Why existing tests missed it.** `check_house_guest.gd` asserted
`child.global_position.distance_to(player) < 5.0`. **That is a distance test, and a figure standing
directly behind the player at 3.2 m passes it.** There was no facing test and no occlusion test, so the
guard written for this beat was structurally incapable of seeing the exact failure the user
photographed. It now asserts the horizontal view-cone dot against `Watcher.SEEN_DOT`,
`is_visible_to_player()`, and — independently of the spawn's own probe, to avoid circularity — that the
figure stands inside the cellar's interior with `FIT_RADIUS` of floor around it.

**General lesson.** ⚠️ **A scripted beat needs the same fairness gate a random one has.** If a director
in your codebase refuses to fire under conditions X, Y and Z, every hand-rolled `create_timer(...)`
set-piece needs the same three checks — and `SceneTreeTimer`'s `process_always` default means a tree
pause will not supply them for you. And: **`distance < n` is not "in front of me".** When the
requirement is that the player *sees* something, assert the view cone and the occlusion, or you have
tested that the object exists somewhere nearby.

---

## Issue 73 — Issue 58, again, in a second prop — plus a drawer that slid into the counter it lives in

**Symptom.** None reported directly; found by auditing `kitchen_drawer.gd` against the fix that had
already been applied to `kontur_mailbox.gd`. The House's KONTUR Gate 1 hint drawer opened *after* its
note was dismissed, every time.

**Cause.** Verbatim Issue 58: `create_tween()` started the slide and `NoteUI.show_note()` was called two
statements later. `show_note()` pauses the tree; a Tween does not advance until the following frame and
does not process while paused. Measured on the identical construction in the mailbox, the hinge read
**0.0° of 105** at the moment the note appeared. The file's own header had said "Opens on E, then shows
its note" since the day it was written.

**And a second fault, found only by looking at the geometry.** `SLIDE` was `+0.34`, i.e. `+z`. The
drawer is set into the kitchen counter's **south** face — `level_2.gd` places it at `kc.z + 2.4 − 0.36`
= 8.04, and the counter box spans z 8.05…8.75 — and the player stands south of it. So the panel slid
34 cm straight into the carcass and out of sight: the ordering fix alone would have produced an
"open, then read" beat with nothing to see.

**Fix.** The note is fired from the slide tween's `finished`, and `SLIDE` is `−0.34`.

**Why existing tests missed it.** `check_open_then_read.gd` existed *for this exact fault* and covered
the KONTUR mailbox and the Lab cabinet — not this prop. `check_house_guest.gd` touched the drawer, but
only to assert that its note reaches the journal and that the prop goes inert, both of which are true of
a drawer that never moves. The test now has a House phase that measures the slide distance in the frame
the note first appears (time-based, never frame-counted — a headless run is uncapped) **and** asserts
the opened drawer's origin is inside no CSG box in the scene, which is the only assertion that could
have caught the direction.

**General lesson.** ⚠️ **A known bug class is a grep, not a memory.** When Issue 58 was diagnosed, the
fix went into one file and the test covered two; nobody searched for the other seven props built on the
same idiom. And ⚠️ **assert the outcome, not the mechanism**: "the tween had progressed 60 %" was true
of a drawer disappearing into a worktop. "The drawer is not inside any solid" is the thing the player
actually needs.

---

## Issue 74 — A trap drawn smaller than it is: 26 px of hitbox behind 20.8 px of paint

**Symptom.** Playtest 2026-08-16, J-capture of the House map minigame: *"the traps are not properly
drawn — shall we make them like freezers with blue color and the snow label?"*

**Cause.** Two measurements, both against the same object. `maze_chase_ui.gd`'s snare triggers at
`SNARE_RADIUS = 26.0` px, and `_rebuild_snare_visuals()` drew `_disc(SNARE_RADIUS * 1.6, …)` — a
diameter of 41.6 px, i.e. **radius 20.8**. The visible footprint understated the hazard by 20 % in
radius and **36 % in area**: the player could be snared five pixels outside the only thing they had
been shown. Separately, the disc was `Color(0.12, 0.05, 0.03, 0.85)` — near-black brown — on sepia
parchment beside `Color(0.32, 0.22, 0.12)` walls, the same hue family as both. That half is Issue 32
repeating: `modulate` cannot rescue it, because modulate MULTIPLIES and no multiplier turns brown into
saturated blue.

**Fix.** A dark rim, an ice-blue disc **at `SNARE_RADIUS`**, and a frost star drawn from three rotated
`ColorRect`s — all geometry, never a generated texture, because at ~52 px a detailed image is invisible
scribble (Issue 32 again). `SNARE_RADIUS`, `SNARE_HOLD` and `SNARE_PANIC` are untouched: this is a
legibility change and must not move the difficulty.

**Why existing tests missed it.** `check_maze_gen.gd` and `check_maze_chase.gd` both instantiate
`MazeChaseUI` **outside any scene**, so `_ready()` never runs, `_build_ui()` never runs, and no visual
node in this file has ever existed during a test. The minigame is only reachable through a prop's
`interact()`, so no scene smoke test opens it either. A new test (`check_maze_traps.gd`) opens it
through the real prop and reads the drawn node's size back.

**General lesson.** ⚠️ **Where a hitbox and its art are two numbers, one of them will drift.** Derive
the drawing from the trigger constant, or assert that they are equal — never both hand-written. And
note the second-order failure: a whole file's worth of view code was untested because every test
instantiated the class headlessly and only ever called its model functions. **"We test that class" and
"we test that file" are not the same claim.**

---

## Issue 75 — A rule applied to a patroller's *route* and never to its *start*: a 3× difficulty swing nobody chose

**Symptom.** Playtest 2026-08-16, J-capture of the House map minigame: *"In this mini game the
difficulty level is very random — need to make it more determenistic."* Two human sessions of the same
puzzle measured 134 s with one catch against 13 s.

**Cause.** Two independent causes, and only the first was found on the first pass.

The first was the free re-roll: `ui_cancel` closed the overlay at zero cost and `HouseMap.interact()`
re-opened it with an unconditional `_generate_maze()`, so ESC was a layout shop. That was fixed by
`_instance_live` (a maze now lives until it is won or you are caught).

The second was **in the generator, and it is a one-line omission**. `maze_chase_ui.gd:_place_patroller()`
chose the second monster's start from any cell at least `PATROL_MIN_START` (7) corridor steps from the
**player's start cell** — and never consulted `_route_cells`, even though `_generate_maze()` has
already computed it by the time that function runs, and even though the sibling function
`_pick_patrol_target()` had avoided route cells since the day the patroller shipped, with a comment
explaining exactly why (*"that is not a second threat, it is a roadblock"*). The rule existed. It was
applied to where the patroller **walks** and not to where it **stands at t=0**.

Measured over 200 seeds (`tests/probe_maze_variance.gd`, `backlogs/02-house.md` §7 P4):

```
win rate by patroller-start BFS distance from the player's route
   0 steps  n=80   22/80  =  28%     <-- 40 % of ALL instances
   1-2      n=30   17/30  =  57%
   3-4      n=29   24/29  =  83%
   5-6      n=18   15/18  =  83%
   7-9      n=25   22/25  =  88%
   10+      n=18   18/18  = 100%
```

A **3× swing in survival**, decided entirely by a placement, in 40 % of runs. That is not difficulty;
it is a lottery wearing difficulty's clothes, and it is precisely what the player's word "random" meant.

**Fix.** A multi-source BFS out from `_route_cells` gives every cell its distance from the artery in
one pass; `_place_patroller()` then samples eligible cells against `PATROL_MIN_ROUTE_GAP = 3` — the
cliff in the table above is entirely between 0-2 and 3+ — with a **bounded** loop that accepts the best
candidate seen rather than spinning. ⚠️ The bound is not defensive programming for its own sake: this
code runs inside a **paused** full-screen overlay, where a hang is indistinguishable from a crash, and
in a maze whose artery happens to cover most of the grid there may be no cell 3 steps clear at all.
`PATROL_SPEED`, `PATROL_AGGRO` and `PATROL_CALM` were not touched.

**Why existing tests missed it.** `check_maze_gen.gd` asserted a great deal about the **hunter's**
placement — that it is exactly one cell from the start, not on the mark, and not on the first step of
the only route — and **nothing whatsoever** about the patroller's. The patroller had been added later,
and the test grew assertions for the thing that was there when it was written. `check_maze_chase.gd`
could not see it either: it reports one aggregate escape rate over 40 seeds, and an aggregate is
exactly the statistic a bimodal distribution hides inside. 26/40 is the average of "28 % of the time"
and "83-100 % of the time", and it looks like a perfectly reasonable difficulty number.

**General lesson.** ⚠️ **An aggregate pass rate cannot detect variance. It is the statistic that
averages a lottery away.** If a system is randomised, a test that reports one number over N seeds tells
you the mean and hides the shape; the cross-tab — pass rate *bucketed by the random quantity you
suspect* — is what finds the lottery, and it is cheap. `probe_maze_variance.gd` exists for that and
nothing else.
⚠️ And the structural half: **when you add a rule to a system, grep for every place that system makes
the same decision.** The route-avoidance rule was written, commented and correct — and applied at one
of the two sites that needed it. The comment at the site that had it did not help the site that did
not.

---

## Issue 76 — A fix that made a route impassable: the drawer whose collider went with the visuals

**Symptom.** Verification replay 2026-08-16, J-capture at `(5.80, 0.00, 7.20)` in the House kitchen,
t=205, while carrying the cellar key with the objective `Unlock the cellar door under the kitchen
stairs`: *"When I read this note it fell and blocked my way, I cannot pass by."* The frame shows the
counter filling the left of the shot and a thin pale plank standing on the floorboards in front of it.

**Cause.** Two faults on the same prop, both introduced by the *previous* round's fix.

`kitchen_drawer.gd:interact()` tweened `self` — a `StaticBody3D` whose direct child is the
`CollisionShape3D`. Sliding the drawer therefore slid a `0.62 x 0.26 x 0.14` solid 34 cm out into the
room. Measured by sweeping the player's own capsule (r 0.4, h 1.8) across the Kitchen:

```
free x-spans across the Kitchen, z = 7.40
  drawer shut  [2.05 .. 7.15]                  = ONE span, 5.10 m
  drawer open  [2.05 .. 3.35] [4.65 .. 7.15]   = TWO spans, 1.30 m and 2.50 m
```

The drawer's new blocked strip (x 3.29..4.71, z 7.23..7.65) adjoins the dining table's (which ends at
z 7.275) and the counter's (which starts at z 7.65), so the three together made a continuous barrier
and z = 7.40 had been the only lane through it. The route was not *sealed* — you could still go the
long way round the south of the room — but the lane in front of the counter, where the player was
standing when they pressed E, closed in their face.

The second fault is why they read it as debris rather than as a drawer. The prop was a single 2 cm
board with **nothing behind it**, so a 34 cm slide out of a featureless counter produced a pale plank
hanging in mid-air. Reproduced in-engine at the reported coordinates before touching anything: the
repro screenshot is the capture. (Its handle was also on `+SIZE.z/2`, the face buried in the worktop —
the same sign error as the slide it was added alongside in Issue 73.)

**Fix.** Everything visible moved onto a `DrawerSlide: Node3D` child and only that is tweened; the
`CollisionShape3D` stays a direct child of the body and never leaves the counter face. Free spans
before and after opening are now byte-identical. The sliding assembly gained two sides, a bottom and
a back, so it reads as a drawer; the handle moved to the `-z` face. The same pass moved the House's
falling painting to `collision_layer = 2` on landing (`note.gd`'s "raycast-hittable, invisible to
movement" convention) after the same capsule sweep showed the flat panel splitting the north end of
the child's room in two.

**Why existing tests missed it.** `check_open_then_read.gd` asserted the two things the previous
round had been asked for — that the drawer opens *before* the note pauses the tree, and that the open
drawer is not inside a CSG box — and both were true of a drawer that had just walled the player in. It
measured the prop. Nothing in the project measured the *floor*: `autoplay_exit_reachable.gd` walks
every level's exit route, but with the world in its **pristine** state, so no test had ever opened
anything and then asked whether you could still get past it. That is the whole gap, and it is why this
is the third bug of its family in one week (Issues 65 and 67 were the Lab's interact volumes).

**General lesson.** ⚠️ **An interactable must never move a collider into a walkway. The visual opens;
the collision does not.** Doors elsewhere in this project already work that way (`house_fridge.gd`'s
door is a mesh under a hinge with no collider at all, which is why the fridge was innocent here).
⚠️ And the testing half, which is the durable part: **a prop test measures the prop, and the bug is
in the room.** `tests/autoplay_house_route.gd` now opens every openable thing in the House and asks
two questions the prop cannot answer — a capsule flood fill of the whole ground floor from a fixed
anchor (does any previously-reachable free floor become unreachable?) and a real `ai_*` walk from the
kitchen counter to the cellar gate to the exit lock. ⚠️ **Neither half subsumes the other**, and that
was measured rather than assumed: restoring the broken drawer reddens the walk (the player jams at
`(3.65, 7.23)` and never reaches the gate) and leaves the flood fill entirely green, because the
drawer narrowed a lane without isolating a single cell.

---

## Issue 77 — A scripted beat with a facing check and no line of sight: the painting that fell through a wall

**Symptom.** The House's falling painting is the level's most expensive scripted beat and its whole
premise is that it happens *while you watch* — it was moved off `MovedProp`'s happens-off-screen rule
for exactly that reason. The 2026-08-16 replay log:

```
t=146.8   GUEST stage 2 (key taken)   -- player at the Bathroom map stand
t=148.26  GUEST painting fell
t≈278     player first enters the child's room
```

It went down 130 seconds before anyone was in the room, and the player's only experience of it was a
bang from somewhere else in the house.

**Cause.** `_tick_painting()` gated on **distance** (`PAINTING_TRIGGER_DIST` 4.5 m) and on a **facing
dot** (0.45) and on nothing else. Walls do not appear in either term. The Landing's north wall is the
child's room's south wall, so a player crossing the Landing toward the Bathroom passes within 4.5 m of
a panel in the next room, roughly facing it, and both conditions are satisfied through 20 cm of
plaster. The `⚠️` comment above the function said *"it requires BOTH proximity and a facing check, so
it cannot happen behind your back"* — which is true, and is not the same claim as "the player can see
it".

**Fix.** One ray. `_painting_in_sight()` casts eye → panel, excluding the panel's own body (it is on
layer 1, so without the exclusion the ray always stops on the thing being asked about) and the
player, and any other solid hit refuses the drop. The same pass moved the panel to the child's room's
NORTH wall beside the exit door, so approaching the combination lock is what stages it.

**Why existing tests missed it.** `check_house_guest.gd` drove `_force_guest_stages(1)`, which calls
`_drop_painting(false)` directly, and then asserted the landing geometry beautifully — flat, face-up,
inside the room, slid along its own forward. Every one of those was true. The test never went through
`_tick_painting()` at all, so it verified *what happens when the painting falls* and never *when it
falls*. It now stands the real player in three places and lets the level's own `_process` decide: in
the Landing (out of range, through a wall), 0.9 m from the panel on the far side of the north wall
(in range, facing it, occluded — the LOS case in isolation), and at the lock. Deleting the ray turns
exactly one of those three red.

**General lesson.** ⚠️ **"In front of the player" is three conditions, not two: near, facing, and
UNOCCLUDED.** A distance-plus-dot test is a test for *pointing at*, and in a building it is satisfied
through walls constantly. Every other spawn path in this project already knew this —
`watcher.gd:_fits()`, `apparition.gd`'s clearance fan, `creature_object12.gd`'s detection — but they
are all *spawners*, and the rule had never been carried across to a *trigger*.
⚠️ Second lesson, cheaper and just as costly here: **a test that reaches a beat through its own
back door verifies the beat's consequences and none of its conditions.** `_force_guest_stages()` is
the restore path, not the play path.

**Postscript (2026-08-16) — the same fault, unfixed, in a second level.** `corridor.gd:_ev_painting_fall()`
spawned the Corridor's falling painting at

```gdscript
var pt := _path_point(_player.global_position.length())        # dead: |v| != path distance
var painting_pos := _player.global_position \
    + Vector3(randf_range(-2.0, 2.0), 1.8, randf_range(-2.0, 2.0))
```

with no raycast, no `wall_point()` and no clearance probe, in a corridor **3 m wide** whose walls are
at ±1.5 m — so one of those two axes was always the lateral one, drawn U(−2, 2) against a wall 1.5 m
away. The 1.5 m quad was then yawed `randf_range(-PI, PI)` for good measure. Measured on the shipped
code across 200 sampled player positions: **199 of 200** placements put at least one corner of the
picture outside the corridor or through a wall.

It now walks outward from the player's own path distance, tries both sides, and validates each
candidate with three rays that must all hit **CSG** — not another prop, or it hangs the painting on
the door at d=210 (measured: 14 of 200 did exactly that before the collider-class check was added).
If nothing fits it plays the sound and withholds the picture, which is `apparition.gd:appear()`'s
"a skipped apparition beats an embedded one" rule. `tests/check_painting_fall.gd` asserts 0 of 200
bad and keeps the old rule as a permanent control at 199 of 200.

⚠️ **The general lesson generalises further than the original write-up did:** the House's version was
a *trigger* missing a line-of-sight test; this one is a *spawner* with no validation at all. The
common factor is that both were the only place in their file that put something into the world
without asking the world whether there was room.

---

## Issue 78 — Nine script errors a run, in a green test, for as long as the snares have existed

**Symptom.** None visible. `tools/run_tests.sh` reported `check_maze_chase` PASS, every seed, every
run. Found only because the two-stage maze work added a second `_rebuild_*_visuals()` and the same
crash had to be reasoned about before it could be written.

**Cause.** `maze_chase_ui.gd:_rebuild_snare_visuals()` ends with `_walls_container.add_child(mark)`.
`_walls_container` is built in `_build_ui()`, which runs from `_ready()` — and **all three headless
harnesses instantiate this class outside the tree**, so `_ready()` never fires and the container is
null. `_check_snares()` calls the rebuild every time a snare springs, which in a 40-seed run happens
about nine times. Measured, by removing the guard and counting:

```
=== guard removed (the state this file shipped in) ===
   9  SCRIPT ERROR: Cannot call method 'add_child' on a null value.
=== guard restored ===
   0
```

**Fix.** An early `if _walls_container == null: return` in both `_rebuild_snare_visuals()` and the
new `_rebuild_fragment_visuals()`, with the reason written at the call site rather than left as a
bare null check.

**Why existing tests missed it.** Two independent reasons, and the second is the one worth keeping.

1. A GDScript runtime error **aborts the current function call and continues** — it is not a crash.
   `_check_snares()` had already done its real work (spring the snare, hold the player, add the
   panic) before it reached the drawing call, so every assertion downstream still measured the
   correct thing. The test was right; it was just also on fire.
2. ⚠️ **`run_tests.sh` greps for `Parse Error` and `Failed to load script` — not for
   `SCRIPT ERROR`.** That grep was added for Issue 44, where a test that failed to parse exited 0
   and was counted as a pass. This is the same family one step further along: a test that *runs*,
   throws repeatedly, and exits 0. The runner's only other signal is the exit code, and a GDScript
   runtime error does not change it.

**General lesson.** ⚠️ **A test harness that instantiates a UI class outside the tree is running half
an object, and the half that is missing will be entered by any code path that touches the view.**
Model functions can be driven bare; anything that draws needs either a real tree or an explicit
guard. Issue 74 already recorded the *coverage* half of this ("we test that class" ≠ "we test that
file"); this is the *correctness* half — the untested half is not merely unverified, it is actively
throwing inside the tests that do run.
⚠️ And the runner-level one: **grep the log for `SCRIPT ERROR`, not only for parse failures.** A
green suite that prints nine stack traces is a suite nobody is reading.

**Postscript (2026-08-16, approved and landed).** `tools/run_tests.sh` now fails any test that
prints `SCRIPT ERROR`, exactly as it already did for `Parse Error`. It immediately went red on
**two more tests that had always been green**, in files unrelated to this one:

- `check_lab_hint` — `Cannot call method 'save_png' on a null value`. `--headless` has no render
  target, so `get_viewport().get_texture()` is null: its debug screenshots had **never once been
  written** by the suite. It now says so and skips.
- `count_apparitions` — `Cannot call method 'get_children' on a null value`. `current_scene` is
  null for a frame or two on every `change_scene_to_file`, and that test deliberately watches
  across scene *reloads*, so its cached reference went stale precisely when a reload landed.

⚠️ **And it falsified my own evidence for the change.** I had reported the suite as having zero
occurrences. It had two. The sweep was `run_tests.sh 2>&1 > file`, which redirects **left to
right**: `2>&1` duplicates the *old* stdout (the terminal), and only then is stdout sent to the
file — so stderr never reached the grep. The correct form is `> file 2>&1`. **A grep of the wrong
stream is indistinguishable from a clean result**, which is the same shape of vacuous-green this
whole issue is about, committed while writing it up.

---

## Issue 79 — Six doors floating 9 cm off the wall, past a guard that could not see them in either direction

**Symptom.** Playtest capture, the Corridor at d≈207: *"Some of the doors in the corridor are not
linked to the walls — the same issue we had with the intro level."* The six `AjarDoor` leaves and the
brass note plate stood visibly proud of the wallpaper with a gap of air behind them.

**Cause.** Two faults, and the second is why the first survived.

1. `corridor.gd` passed `depth_inset = 0.14` to `_panel_transform()` for the door loop, and its own
   comment explained why: an `AjarDoor` hinged through the CENTRE of its leaf, so swinging it 40°
   swept the rear corner `THICK * sin(40°)` = 6.4 cm *behind* the hinge plane, and the door had to be
   held clear of the wall to make room. The arithmetic answering that constraint is 0.074; 0.14 is
   roughly double it. Measured back-face gap: **0.090 m**, against **0.020 m** for every flat decal in
   the level. `_spawn_nightmare_plate()` had the same shape at `W/2 - 0.12` → **0.110 m**.
2. `check_wall_overlap.gd` — the file `CLAUDE.md` calls *"run this before calling any procedurally
   built level done"* — could not catch either one, for two independent reasons:
   * its prop check tests `box.grow(MIN_CLEAR).has_point(q)`, a **minimum** only. A prop that has
     drifted AWAY from its wall, or that has no wall at all, passes trivially. (Cross-level item X1.)
   * `_collect_quads()` collected **`QuadMesh` only**. Both offenders are `BoxMesh`, so they were
     invisible to it in *both* directions — as are the House's entire furniture set and
     `intro_room.gd`'s wheelchair.
   And it had **never been run on this scene at all**: `tools/run_tests.sh` ran it bare (the Lab) and
   via one House wrapper, and nothing else. Run for the first time on 2026-08-16 it reported 32
   findings.

**Fix.**
* `ajar_door.gd` hinges on the leaf's **back face** (`mesh.position.z = THICK / 2`), so every part of
  the panel lives at local z ≥ 0 and swinging it can only move wood into the corridor. The door then
  seats at the level's ordinary `WALL_INSET`.
* One mounting convention for the whole level, `WALL_INSET = 0.03`. It was 0.02 — *exactly*
  `MIN_CLEAR`, and `AABB.has_point()` includes its own boundary, which is why twenty perfectly
  ordinary decals were also being reported.
* `check_wall_overlap.gd` gained `_check_solid_props()`: `BoxMesh` props are now compared to the
  level's CSG by **face plane**, the same `_faces_fight` rule used for the geometry itself. ⚠️ Not by
  the centre-point test the quads use — a fixture mounted flush to a ceiling legitimately has its
  centre within half its own thickness of it, and a closed drawer legitimately lives inside its
  counter; measured, the point test produced 28 false positives across the Lab and the House.
* `check_corridor_mounting.gd` is the missing **maximum**: per prop, ray from the back-most mesh's
  back plane into the wall, and require `0.005 ≤ gap ≤ 0.045`.

**Why existing tests missed it.** The guard for this exact class of fault existed, and it was
*structurally* blind (minimum only), *categorically* blind (`QuadMesh` only) and *not wired up*
(no Corridor entry) — three independent failures stacked on one file. `check_corridor_doors.gd`
measured the doors too, but only for the soft-lock question ("does a swung panel still leave a
walkable hall"), which a door that is 7 cm further into the corridor passes even more comfortably.

**General lesson.** ⚠️ **A clearance check with only a minimum is half a check.** "Not z-fighting"
and "actually mounted" are different properties and neither implies the other; the second is the one
a player photographs. ⚠️ And an over-correction leaves a comment behind that reads like a
justification: the 0.14 shipped *with* the arithmetic that disproves it written above it. When a
constant's own comment states a constraint, evaluate the constraint.

---

## Issue 80 — The mirror that was a whole 75° room squeezed onto a 1.95 m pane

**Symptom.** Playtest capture, the Corridor's 90 m turn mirror: *"The reflection in the mirror looks
weird."* Re-flagged **unprompted** a session later: *"Still the weird image in the mirror, remember
what I wrote earlier about it."* The glass showed a tiny, distant-looking corridor in a black
surround, and the image visibly zoomed as the player walked toward it.

**Cause.** `mirror_surface.gd` gave the reflection camera the PLAYER's **symmetric** perspective —
`_cam.fov = _player_cam.fov` (75°) with `near` pushed out to the mirror plane — and then mapped the
result onto the quad. A symmetric frustum's near-plane window is `2·near·tan(fov/2)` tall; the quad
is 1.95 m. Measured minification (window ÷ glass), at the player's own capture positions:

```
  1.00 m from the glass   window 1.02 x 1.53 m   0.79x
  2.45 m (capture C1b)    window 2.51 x 3.76 m   1.93x
  4.25 m (capture C1)     window 4.35 x 6.52 m   3.34x
  8.00 m                  window 8.19 x 12.28 m  6.30x
```

A figure genuinely 7 m behind the player rendered as if it were 23 m away. And because the factor is
a function of distance, the reflection *zoomed* on approach at a rate no reflection has. A second,
smaller error compounded it: the `SubViewport` was a fixed 512×768 = 0.667 against a 0.718 quad, a
further 7 % stretch.

**Fix.** A planar mirror is a **window**, and its frustum is the pyramid from the virtual eye through
the quad's four corners — asymmetric in general. `_aim()` now points the reflection camera along the
mirror NORMAL (never along the mirrored player heading: the window is fixed by the glass, not by
where you are looking) and calls `Camera3D.set_frustum(quad_height, offset, near, far)` with the
offset placing the window exactly over the quad. The viewport is sized from the quad's aspect.
⚠️ The near plane is still load-bearing — it is what clips away the wall the mirror hangs on, without
which the glass renders the inside of the masonry with a strip of sky over the top — but with
`set_frustum` the window plane **is** the near plane, so that property is structural rather than
maintained by hand.

The image is also flipped in U now. The reflection camera must be a proper frame (Godot renders a
determinant-negative one inside out), which makes its screen-right the glass's local −X; a real
mirror does not swap sides. That was wrong before this change too, and invisible, because a straight
corridor is nearly symmetric about its own centreline.

**Why existing tests missed it.** `check_turn_mirror.gd` asserts the wiring — shared world, layer 20
kept by the reflection camera and cleared by the player camera, the `UPDATE_DISABLED` proximity gate,
one figure per mirror, no colliders — and every one of those was **correct** the whole time. Its own
header says why it stops there: *"A reflection cannot be ASSERTED."* True of the picture; false of
the **framing**. `check_mirror_frustum.gd` now unprojects the glass's four corners through the real
camera into the real viewport and requires them to land on the viewport's corners, at 36 eye
positions per run; it keeps the old projection as a permanent positive control, which reproduces the
1.93× and 3.34× above to two decimal places.

**General lesson.** ⚠️ **"This cannot be asserted" is usually true of an appearance and false of a
geometry.** When a visual defect is reported, look for the measurable invariant underneath it — here
"the near-plane window is the quad" — rather than concluding that only a human can judge it. ⚠️ And
a corollary: when the user asks for **new art** to fix something, check first whether the old art was
being displayed correctly. The request here was *"can we generate a creepier image"*; a new image
rendered through the same camera would have been minified 1.9–3.3× and surrounded by black, and the
report would have come back a third time.

---

## Issue 81 — `emission_texture` is ADDED to `emission`, so a dark brass plate rendered as a cream slab

**Symptom.** The Corridor's rebuilt KONTUR hint plate — a near-black plate with gold lettering,
source mean RGB (59, 59, 50) — rendered in game as a **pale cream slab with the text knocked out of
it**, photographed in `tests/screenshot_corridor.gd`'s shot 15.

**Cause.** `BaseMaterial3D.emission_operator` defaults to **`EMISSION_OP_ADD`**. Godot's shader is
`EMISSION = (emission.rgb + emission_tex) * emission_energy`, so setting an emission COLOUR alongside
an emission TEXTURE lays a flat wash over the whole surface instead of tinting the artwork. With
`emission = (1.0, 0.92, 0.70)` at energy 0.34 that is +0.34 of cream on every texel, against a plate
whose own texels are 0.06 — so the plate's body glowed exactly as hard as its lettering.

**Fix.** `emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY` on both new plate materials, and
the energy raised to compensate. The brass bead and the gold letters are then what glow, which is
also what a torch-lit plate does.

**Why existing tests missed it.** Nothing in the suite measures rendered colour, and no assertion
could have: the material was internally consistent and the aspect check (`check_corridor_art.gd`)
passed happily. It was found by *looking at the screenshot* the harness had just written — which is
the argument for shot 15 and the newly-added shot 16 existing at all.

**General lesson.** ⚠️ **Emission colour and emission texture are ADDITIVE by default in Godot, not
multiplicative.** This project has hit the symptom at least twice before without naming the cause —
`corridor.gd`'s exit door carries a four-line comment ending *"the emission was reading as its flat
colour rather than modulating the texture"*, and solved it by going unshaded instead. If a textured
prop washes out to a flat colour, check `emission_operator` before touching the energy.

---

## Issue 82 — Naming a `class_name` in a `--script` tool compiled it before the autoloads existed, and silently deleted the beartraps from the scene under test

**Symptom.** A new headless test printed, then passed:

```
SCRIPT ERROR: Compile Error: Identifier not found: GameState
          at: GDScript::reload (res://scripts/beartrap.gd:43)
SCRIPT ERROR: Invalid call. Nonexistent function 'new' in base 'GDScript'.
          at: _spawn_beartraps (res://scripts/corridor.gd:982)
```

**Cause.** The test filtered props with `if child is Torch3D or child is Beartrap or child is
Watcher`. Naming `Beartrap` makes Godot resolve and compile `beartrap.gd` **while loading the test
script**, i.e. before `GameState` and the other autoloads are registered — and `beartrap.gd`
references `GameState` at class scope. The compile fails, `Beartrap` stays an uninstantiable
`GDScript`, and `corridor.gd:_spawn_beartraps()` then throws once per trap. **The level under test
was built without any beartraps, and the test still passed**, because it was not measuring beartraps.

**Fix.** Filter by SCRIPT FILE — `node.get_script().resource_path.get_file()` against a list of file
names — which needs no compile-time identifier at all. It also fixed a second, unrelated hole: the
16 `Torch3D`s are never given names (`Torch3D.new()`), so Godot calls them all `@Node3D@NN` and a
name-based filter misses every one.

**Why existing tests missed it.** It was a brand-new test, and it was caught only because
`run_tests.sh` had been taught the day before to fail on `SCRIPT ERROR` (Issue 78). Under the old
runner this would have been a green test running against a silently mutilated level.

**General lesson.** ⚠️ **In a `--script` SceneTree tool, referring to a `class_name` is not free —
it drags that script's whole dependency chain into a compile that happens before the autoloads
exist.** Any game script that touches an autoload at class scope will fail there, and the failure
lands in the SCENE, not in the test. Prefer `get_script().resource_path`, node groups, or duck-typed
`has_method()` checks when a test needs to identify a class.

---

## Issue 83 — A prop whose front faced into the wall: invisible while it was a symmetric box, blank the moment it got artwork

**Symptom.** None, for the life of the prop — and then a blank rectangle would have appeared the
first time it was given a one-sided face. Caught while rebuilding it.

**Cause.** `_spawn_nightmare_plate()` placed the Corridor's brass plate by hand:

```gdscript
plate.position = pt.pos + (pt.side) * (W / 2.0 - 0.12) + Vector3(0, 1.55, 0)
plate.rotation.y = atan2((pt.side).x, (pt.side).z)
```

That rotation points the body's local +Z along **+side** — the same direction it was just translated
in, i.e. **into the wall**. The level's own `_panel_transform()` helper exists to get this right and
faces `-side * side` inward. The error was undetectable because the prop was a `BoxMesh` with the
same material on all six faces.

**Fix.** `plate.transform = _panel_transform(D, 1.0, 1.55)`, like every other wall prop in the level.

**Why existing tests missed it.** Nothing asserts which way a prop faces, and until the rebuild
nothing depended on it. `check_note_mounting.gd`'s `_backing()` is deliberately bidirectional — it
tries both directions and takes the nearer hit — precisely because `LivingMirror` faces its local −Z,
so even that check would have called this plate correctly mounted.

**General lesson.** ⚠️ **Never hand-compute a wall prop's position or facing when the level has a
`wall_point()`/`_panel_transform()` helper** — `CLAUDE.md` already states the position half of this
rule ("the morgue poster's hand-rolled `c.z + 2.9` landed exactly on the face and got sliced apart").
The facing half is worse, because it is *latent*: a symmetric prop hides it until the day someone
adds a front.

---

## Issue 84 — NOT A BUG: the mirror that stopped moving because it started being a mirror

**Read this immediately after Issue 80.** It is the sequel, and it is here to stop the next person
reverting that fix.

**Symptom.** The verification replay after Issue 80 shipped: *"It used to be in a way that the
reflection in the mirror moves, now it is static. can we make it move again?"* The reflection had
been live and parallaxing before; now it read as a photograph glued to the wall.

**First hypothesis, and it was wrong.** A `SubViewport` left at `UPDATE_ONCE`/`UPDATE_DISABLED`
renders one frame and then shows that frame forever — which looks exactly like a working mirror in
a screenshot and exactly like this report in motion. Checked and rejected: the viewport is at
`UPDATE_ALWAYS` inside `ACTIVE_DIST` and `_aim()` runs every frame.

**Actual cause.** Issue 80 replaced a reflection camera that was the player's whole TRANSFORM
mirrored through the glass with one that points along the mirror NORMAL and takes only the eye's
POSITION. The old one inherited the player's **heading**, so the image panned with the mouse. A
mirror cannot do that — the glass is a fixed window; turning your head changes which part of it you
look at, not what it reflects. And `player.gd:_rotate_camera()` yaws the player about its own Y axis
with the camera sitting **on** that axis, so looking around does not move the eye by a millimetre.

Measured (analytic replication of both projections; figure on the centreline 7 m out, eye 2.45 m
from the glass; U is across the pane):

| head yaw | 0° | 10° | 20° | 30° | 45° |
|---|---|---|---|---|---|
| OLD figure U | 0.500 | 0.672 | 0.856 | 1.064 | 1.477 |
| NEW figure U | 0.500 | 0.500 | 0.500 | 0.500 | 0.500 |

0.022 U per degree, off the pane entirely past ~26°. Every one of those frames was wrong, and every
one of them was motion. Meanwhile everything done with the FEET moves *more* than before: the
figure's height goes 0.599 → 0.119 of the glass between 12 m and 1 m (was 0.063 → 0.151), and
strafing 0.5 m is **5.1× the parallax it used to be**.

**Fix — geometric, and it is in the LEVEL, not the renderer.** Nothing in `mirror_surface.gd`
changed. `corridor.gd`'s `MIRROR_FIGURE_SIDE` went **0.0 → 0.45 m**, because of a second measurement
that turned out to matter more than the first: the player walks the corridor's centreline, the mirror
hangs on that axis, and the figure stood exactly on it — and **a point on a mirror's own normal is a
fixed point of the projection under axial motion.** Measured in-engine, unprojected through the real
reflection camera into the real SubViewport, over a 12 m → 1 m approach:

| figure offset | lateral travel across the pane |
|---|---|
| 0.00 m (shipped) | **0.0 px** — zero, exactly, at every distance |
| 0.45 m (now) | **89.8 px**, 16.3 % of the pane |

So the one thing the player looks at was the one thing that mathematically could not move as they
walked toward it. It is a **ladder**, not a constant (`MIRROR_FIGURE_SIDE_LADDER`): `Watcher.spawn()`
returns null when a spot is refused and the old loop swallowed that with a bare `continue`, so the
level takes the largest offset that fits at each mirror, records it, and **0.0 is deliberately not on
the ladder** — a silent fallback to the axis is the failure this change exists to remove.

⚠️ While re-deriving it, the comment that had justified the centreline turned out to be **wrong**. It
blamed the walls: *"the billboard is 1.6 m wide, so at 0.55 off-centre its edge came within 0.15 m of
the wall."* `Watcher.FIT_RADIUS` is a flat **0.9 m** and is not scaled by the billboard's width, and
the corridor's wall face is at W/2 = **1.5 m**, so the walls alone permit 0.6 m. What refused those
placements was a **wall prop** — the fan's 0.9 m reach at 0.55 m offset extends to 1.45 m, and a
cursed panel's collider at d=268 spans 1.43–1.53 m. A plausible-sounding cause was recorded for two
sessions in place of the real one.

**Also added — the assertion that should have existed with Issue 80:** `check_mirror_frustum.gd:_liveness()` drives the real player past
`ACTIVE_DIST` and back, requires the viewport to switch `DISABLED`↔`ALWAYS`, requires the projection
of a fixed world point to MOVE when the eye moves, and carries the control that it does NOT move when
the eye does not. Plus `probe_mirror_motion.gd`, which reads the rendered pixels back (no
`--headless`) and reports mean luminance and per-frame delta, because a live render of a black
corridor is indistinguishable from a frozen one.

**Why existing tests missed it.** They asserted the picture was *correct* and never that it was
*live*. `check_turn_mirror.gd` checks the wiring, `check_mirror_frustum.gd` checked the projection —
both would have passed with a viewport frozen on frame one.

**Two general lessons, and the second is the expensive one.**

1. ⚠️ **A liveness assertion is not implied by a correctness assertion.** Anything driven by a
   `SubViewport`, a `Tween` or a timer needs one test that says *this changed between two moments*,
   with a control that says *and it did not change when nothing happened*.
2. ⚠️ **A correctness fix can delete a perceptual cue, and "physically correct" is not an answer to
   "it reads as dead."** The old mirror was wrong in every measurable way and still communicated
   something true — that the glass was alive. Two further measurements say the level's own geometry
   is now working against it: the player walks the **centreline**, the mirror is on that axis, and
   `MIRROR_FIGURE_SIDE` is deliberately 0.0 — and a point on the axis is a **fixed point of the
   projection under axial motion**, so walking 0.5 m straight at the glass moves an on-axis point by
   **0.73 px** against 14.7 px for one a metre to the side. The same trap bit the test: an on-axis
   probe point would have made the liveness check report a frozen mirror on a perfectly live one.
   Restoring the cue meant moving something in the REFLECTED WORLD. The user was shown the
   measurement and chose the cheapest correct version — move the figure off the axis — over the two
   richer ones (an animated Corridor-local figure; a moving non-figure object in the glass), both
   **declined for now**. `watcher.gd` was not touched and its no-motion contract stands. ⚠️ **None of
   this is a licence to revert Issue 80.**
3. ⚠️ **"It is too dark" is not measurable without a reference, and the reference is the level.**
   The corrected framing shows only the 1.40 × 1.95 m column straight down the corridor where the old
   one crammed 2.51 × 3.76 m, so the obvious next theory was that the glass had gone black. Measured
   by reading the rendered pixels back (`probe_mirror_motion.gd`, no `--headless`) and comparing
   against the MAIN viewport from the same spot on the same frame: reflection mean luminance
   **0.0244 vs the corridor's 0.0231** at the 90 m mirror, **0.0107 vs 0.0119** at 275 m — within a
   tenth of the level's own darkness at both, with a brighter peak pixel (0.888 vs 0.634) than the
   direct view. Nothing was changed. The theory was reasonable, cost one probe, and was wrong.

---

## Issue 85 — Half a contract: the Congregation gated where a figure moved FROM and never where it moved TO

**Symptom.** *"These human shadows do not do anything"* (playtest capture, the Sprawl). A field of
six silhouettes among 36 pillars read as scenery — and occasionally one appeared out of nothing a
few metres in front of the player.

**Cause.** `CLAUDE.md` states the feature's contract in as many words, and cites it as the reason the
feature is legal under `SCARY.md` §8.3: *"A figure relocates only when it is BOTH out of view and
≥15 m away, so it **never moves on screen** and never pops at arm's length."*

Only the first half existed. `congregation.gd:_process()` gated the **source** correctly
(`is_visible_to_player()` and `distance_to_player() < RELOCATE_MIN_DIST`), and then called
`_pick_spot()`, which asked nothing at all about the player's view and required only 12 m.

Measured over a 90 s circuit of the Sprawl with six figures:

| | |
|---|---|
| relocations | **633** (422/min, ~1.2 per figure per second) |
| mean distance moved | 20.0 m |
| player distance at relocation | mean 23.8 m, **min 12.0 m** |
| **landed in the player's view cone with line of sight** | **65 of 633 — 10.3 %** |

One relocation in ten was a figure materialising on screen. And the *rate* is the second half of the
same bug: a figure that has teleported 20 m five times since you last looked cannot support the
memory "there was one by that pillar", which is the entire product. The feature was not inert
because it did too little; it was inert because it never stopped moving.

**Fix.** Three changes in `congregation.gd`, none of them a difficulty constant (this thing has no
panic, no collider and no fail state, and still does not):

* `_pick_spot()` takes `min_from_player` and `unseen_only`. A relocation destination must be ≥ the
  same `RELOCATE_MIN_DIST` the source is, and must not be visible.
* `would_be_seen(pos)` re-implements `Watcher._is_seen()` for a candidate POINT — horizontal-only
  facing dot against `SEEN_DOT`, then a layer-1 ray to the figure's centre.
* `SETTLE_MIN`/`SETTLE_MAX` (8–16 s, randomised per figure) hold a figure still after it moves, so
  the field has a state long enough to be remembered.

**Why existing tests missed it.** `check_backrooms_occupants.gd` asserted *"a watched figure does not
move"* and *"nor does one standing right next to you"* — i.e. it tested the half that was already
implemented, twice. There was no assertion anywhere about where a figure ARRIVES. It now drives a
34 s circuit of the hall, counts every relocation, computes visibility independently of the code
under test, asserts **zero** land in view, asserts the settle interval, asserts the sample was not
empty, and carries a control proving its own visibility probe can return TRUE.

**General lesson.** ⚠️ **When a documented contract has two clauses, write two assertions.** A test
that covers the clause someone remembered to implement is indistinguishable from a test that covers
the feature. This one had been green for the whole life of the defect, and the defect was written
down, in `CLAUDE.md`, in the sentence that justifies the feature's existence.

---

## Issue 86 — Two rooms that overlapped by 1 m, and the 2 m walls that left standing inside them

**Symptom.** None reported — the Flood is entered near-black and was traversed once, in 54 seconds.
Found by pointing `check_wall_overlap.gd` at `backrooms.tscn` for the first time.

**Cause.** `backrooms_zone3.gd`'s `ROOMS` table put `Sump` at x −13…−5 and `Cistern` at x +5…+13
while `Basin` spans x −6…+6, z 11…19 — so each outer chamber overlapped the Basin by 1 m × 2 m.
`CLAUDE.md` states the rule: *"Rooms in a `ROOMS` table must ABUT, never OVERLAP."*

The four coincident floor/ceiling pairs the guard reports are the least of it. `RoomBuilder` builds
each room's walls on its own boundary, so an overlap leaves those walls standing **inside** the
neighbour. Proved by ray sweep at eye height rather than by reading the table:

```
Basin west->east @ z=17.5 / 18.0 / 18.5   2 hits:  wall @ x=-5.10  ·  wall @ x=+4.90
Basin west->east @ z=13.0 / 16.0          0 hits   (as it should be)
Sump  west->east @ z=18.0                 1 hit:   wall @ x=-6.10
x=-5.5 / x=+5.5 south->north              2 hits:  wall @ z=16.90  ·  wall @ z=18.90
```

That is a 2 m wall stub standing in the Flood's largest room (the one holding the `DryPlatform`
`CalmZone`, the zone's only recovery anchor), a matching stub inside the Sump, and both of the
Basin's north corners boxed into 1 × 2 m dead pockets in a near-black room the player is searching
by torchlight.

**Fix.** Move the two outer chambers 1 m outward — `Sump (-9,21) → (-10,21)`,
`Cistern (9,21) → (10,21)` — and their doorways with them, `(∓9,17) → (∓10,17)`. Every boundary is
now a shared plane, which is what `RoomBuilder`'s interval dedup exists for. The seams, the beartrap
and the wader waypoints are all derived from room centres and followed automatically.

⚠️ **The doorways had to move too, and for a reason that is not obvious.** They sit in the z = 17
plane shared by `WestRun`/`EastRun` (x ∓12…∓6) and the chambers. Left at ∓9 with the chamber at
∓14…∓6, a 2.2 m opening would have spanned ∓10.1…∓7.9 — still inside both — but the geometry either
side of it changes, and a doorway whose span leaves the side run opens a hole into solid ground.
Move a room, move its doors.

**Why existing tests missed it.** `check_wall_overlap.gd` had **never been pointed at this scene**.
It takes a scene argument, `tools/run_tests.sh` has no per-test argument mechanism, and the only
wrappers that existed were the Lab, the House and the Corridor. `walk_backrooms.gd` drop-probes the
Flood's floor at five points and reaches its seams — none of which a 2 m wall stub in a corner
interferes with.

**General lesson.** ⚠️ **A scene-parameterised guard with no wrapper is a guard that does not run.**
This is the third level in a row where the first run of an existing check produced double-digit
findings (Corridor 32, Backrooms 10 + 8 + 5). The wrappers cost three lines each.

---

## Issue 87 — A one-way mirror facing the wall it was hung on, 0.70 m away from it

**Symptom.** The Sprawl's alcove contained nothing visible where a mirror was built. Not reported —
the zone is 1600 m² and was crossed twice.

**Cause.** `LivingMirror` faces its **local −Z**; `level_1.gd:1222` and `level_2.gd:866/921` all
orient by that and all say so in a comment. `backrooms_zone2.gd` set `rotation.y = PI` on a mirror in
an alcove on the hall's **N** side — whose back wall is at +z and whose open side faces −z. So the
glass turned to face the wall behind it. A `QuadMesh` is single-sided, so from the hall the panel
rendered as **nothing at all**, and the figure — which lives 0.05 m off the glass along the same
local axis, and is the entire mechanic — sat between the glass and the plaster.

It was also 0.70 m off that wall, hand-placed with `HALF + ALCOVE_D - 0.2` rather than derived from
the recess.

**Fix.** `rotation.y = 0.0`, and the position derived from the alcove's own geometry at
`MIRROR_INSET` 0.22 — 0.22 rather than the usual 0.16 for the reason `level_1.gd` gives, that this
prop hangs a second quad off its face and needs clearance for both.

**Why existing tests missed it.** Nothing asserted which way a prop faces (Issue 83, same week), and
`check_note_mounting.gd` — the one guard that would have caught the 0.70 m — had never been pointed
at this scene. It has a wrapper now.

**General lesson.** Issue 83's lesson holds and gains a corollary: ⚠️ **a facing convention stated
only in comments is a convention that will be broken by the third caller.** Three call sites
independently wrote `rotation.y = 0`, `PI` and `-PI/2` with a comment each; the fourth got it wrong
and nothing noticed for the life of the zone.

---

## Issue 88 — The navigational sign whose background was ten times louder than its glyph

**Symptom.** *"Despite all our notes — many players might get confused that you need to go through
the wall"*, and 86 seconds of standing still in the arm the arrows had correctly sent them down.

**Cause.** `arrow_decal.png` was a **1254×1254 photograph of yellow wallpaper with a slightly darker
arrow sprayed on it**. Measured from real frames at the reading distance:

| surface | luminance | contrast |
|---|---|---|
| the arrow glyph | 120.7 | — |
| its own baked panel background | 126.3 | **2.2 %** |
| the column the panel is stuck to | 153.9 | 22 % |

Every part of the sign that contained no information was ten times louder than the part that did.
Four more faults compounded it: the file was **RGB with no alpha channel** on a material set to
`TRANSPARENCY_ALPHA` (so it rendered as an opaque rectangle and there was nothing for the cutout to
cut); a square source on a 0.45 × 0.70 quad, a 1.556× stretch; a 0.45 m sign on a **0.28 m post**, so
38 % of it hung in mid-air; and `emission_energy_multiplier = 0.25`, which in a project with no
tonemapping is most of a surface's colour — it was **lighting the wallpaper background**.

This is the level's only navigational signal, and a misread costs `WRONG_TURN_PANIC` 18, i.e. 36 % of
`PANIC_MAX`, plus a reset of the turn counter.

**Fix.** `tools/make_arrow_decal.py` draws a real RGBA cutout with **no background of its own** — the
post is the background — in near-black stencil paint with eroded edges. `_spawn_arrow_columns()`
sizes the quad from the artwork's aspect, drops the emission entirely, widens the **post** from 0.28
to 0.68 (the sign is the thing that must be readable; shrink the sign and you have solved the wrong
problem), and raises the clearance from 0.02 — `check_wall_overlap.gd`'s bare minimum — to 0.06.
Measured contrast, glyph texture vs wallpaper texture under the same light: **89 %**.

**Why existing tests missed it.** `check_intro_art.gd` (the aspect guard) had never been pointed at
this scene, and nothing in the project measured *contrast* at all. `check_backrooms_seam.gd` now
asserts the glyph reads against its post by comparing the two textures' mean luminance — both
surfaces leave `albedo_color` white and take the same light, so the texture ratio IS the rendered
ratio, and no frame is needed.

**General lesson.** ⚠️ **X24 is an asset-intake rule, not a per-prop bug: a wall prop's texture may
not contain a picture of the surface it is mounted on.** This is the fifth time it has been fixed
one prop at a time (`ordinary_hotel_door.png`, `kontur_plate.png`, `kontur_panel_mailboxes.png`, the
intro wheelchair, and now the only signpost in a level). And the second half: ⚠️ **a sign is measured
by the contrast of its glyph against what it is mounted on, not by whether the artwork looks good in
a file browser.**

---

## Issue 89 — A screenshot harness that photographed its own death and kept going

**Symptom.** Twenty files in `/tmp/backrooms_shots/`, all plausible, eighteen of them of the wrong
place.

**Cause.** `screenshot_backrooms.gd` shot `04_north_arm` from `(0, 1.6, 5)` looking down the N arm
with the flashlight on. When N is that round's dark arm — a coin flip — that position is inside
`CreatureSmiler.ENGAGE_DIST` with `looking == true`, which is `_rush()` → `Screamer.trigger()` →
scene reload. Shots 04 and 05 came back as the fullscreen Smiler face. Then `_place()` kept a stale
`Player` reference from the freed scene, so every subsequent call did nothing at all and the camera
sat at the spawn point for the remaining sixteen shots — including all six of the Sprawl and all six
of the Flood, each saved under a filename claiming to be somewhere else.

**Fix.** Three changes, and the third is the one that matters. (1) `_disarm()` removes the Smiler,
the beartraps and the apparitions before shooting, and suppresses the standstill tick — this is a
photographer, not a difficulty instrument. (2) The scene and the player are re-fetched on every
shot. (3) If the scene reloads anyway, the run **prints `RESULT: FAIL` and exits 1**.

**Why existing tests missed it.** `screenshot_*` tools are not in `tools/run_tests.sh` (they need a
render target) and they asserted nothing, by design — they are for a human to look at. That is
exactly why a silent failure in one is expensive: it is the only instrument in the project that can
judge the things a headless assertion cannot, and its output degrades into something that still
looks like a result.

**General lesson.** ⚠️ **A tool whose output a human will eyeball must still be able to fail
loudly.** X31 named the accumulated-state version of this (the Corridor's escape HUD sitting over
every later frame); this is the harder one, because the harness kept running and kept producing
files. Every `screenshot_*` that teleports a camera through a level containing a fatal creature is a
candidate.

---

## Issue 90 — Eight rooms nobody could enter: a "recess" is not a recess until something is removed

**Symptom.** *"SprawlNote was not read in either session."* Read, at first, as a placement problem —
the page was floating 1.20 m off its wall, so it was re-mounted. It still could not be read, and
neither could the phone beside it, the one-way mirror, two mirage doors or five furniture props:
**every authored object in the Backrooms Sprawl's 1600 m², except the pillars, the lights and the
four glitch walls.**

**Cause.** `backrooms_zone2.gd:_build_alcoves()` builds each recess as a floor, a back wall and two
side walls **outside** the perimeter — and nothing ever removed the length of perimeter wall in
front of it. `_build_shell()` split each side into two unbroken runs of `(SIZE - GLITCH_GAP) / 2 =
16.5 m` spanning 3.5…20 and −20…−3.5; the alcoves sit at ±11. The comment in that function said the
recesses were "punched into the perimeter". They never were.

Proved by ray query rather than by reading the table (`tests/probe_alcove_reach.gd`) — a ray from
3 m inside the hall toward each alcove centre was **blocked at exactly 3.00 m, the mouth plane, on
all eight**.

**Fix.** `_side_runs()` now derives the solid runs of each side by subtracting the openings — the
central glitch-wall gap and one **mouth** per alcove — from the side's full extent, giving four wall
segments per side instead of two. ⚠️ A mouth is the alcove's interior width **plus a wall thickness
at each end**, so the perimeter stops at the OUTER face of the alcove's own side walls and the two
boxes ABUT. Ending it at the interior width instead leaves the perimeter's end cap and the side
wall's end cap coplanar and both facing into the mouth — this project's most expensive bug class
(Issues 19/20/23/24/25/26). The magic `11.0` that had been repeated in four places became
`ALCOVE_AT`, so the mouths and the recesses cannot drift apart.

**Why existing tests missed it.** Because none of them asks the question. `check_wall_overlap`
asks *do two surfaces coincide*; `check_note_mounting` asks *is this prop on a wall* — and a sealed
alcove's back wall is still a wall, so `SprawlNote` passed at 0.16 m of backing while nobody could
see it; `check_doorways` asks *is a doorway sealed*, for `RoomBuilder` levels only, and an alcove
has no doorway to seal; `walk_backrooms` walks the route somebody thought to walk. **Nothing
anywhere asked whether a player can stand where an object is.**

`tests/check_reachable.gd` now does, for all nine levels: a flood fill of the standable space with
the level's own player capsule, seeded at the spawn, then the shipping interact ray from every
reachable cell in range. It carries a control that seals this very alcove back up. Alongside it,
`tests/check_sprawl_alcoves.gd` asserts the cut itself — all eight mouths open, the capsule fits,
504 samples of floor continuity across the thresholds, the shell still closed beside every mouth,
and the `DreadZone` still covering the recesses.

**General lesson.** ⚠️ **Geometry guards ask about surfaces; add one that asks about SPACE.** Every
existing check in this project inspects the relationship between two objects. A room that no route
reaches is invisible to all of them, and the failure is silent, permanent and total — eight rooms
and ten objects, through two playtests and four scene-parameterised guards, without a single red.
And the corollary for builders: ⚠️ **subtractive geometry has to be subtracted.** A recess built as
four walls outside a shell is a sealed box until the shell is cut, and the word "punched" in a
comment is not a cut.

---

## Issue 91 — A control made of a runtime `CSGBox3D` answered rays and was invisible to shape queries

**Symptom.** `check_sprawl_alcoves.gd`'s control seals one alcove mouth and requires both halves of
the test to go red. The ray half went red correctly (`blocked by AlcoveControlSeal`); the capsule
half stayed green — the player's capsule "still fitted" at a mouth that had a 4.4 × 4.5 × 0.3 m slab
straddling it. The same shape had already made `check_reachable.gd`'s control half-vacuous.

**Cause.** A `CSGBox3D` created and added to the tree **after the level has built** generates a
collider that answers `intersect_ray` and is not seen by `intersect_shape`. Reproduced in isolation
by `tests/probe_csg_shapequery.gd`, which builds one `CSGBox3D` and one `StaticBody3D + BoxShape3D`
of identical size, seconds apart from any `_ready()`, and queries both the same way:

```
CSG         ray=ProbeCSG   shape_hits=[]
StaticBody  ray=ProbeSB    shape_hits=[ProbeSB]
```

Not an ordering problem: setting `use_collision` before or after `add_child`, setting `size` before
or after, and waiting 2.5 s all behave identically. The levels' own `_ready()`-time CSG boxes are
unaffected — `ArrowColE`, `EntryWallR` and `CellarRamp` all block capsule queries normally, which is
what makes this so easy to trust.

**Fix.** Both controls build their seal from a `StaticBody3D` with a `BoxShape3D`. Nothing in the
shipped game changed.

**Why existing tests missed it.** It is a property of a **test's own scaffolding**, and both affected
controls were written the same day. The tell was that one control asserted two things and only one of
them moved — which is only visible because both were asserted separately.

**General lesson.** ⚠️ **Build a control out of the simplest primitive that exists, not out of the
same class as the thing under test.** A control's job is to be unambiguously solid; a `CSGBox3D`
carries a whole CSG rebuild pipeline for no benefit here. And the sharper half: ⚠️ **a control that
tests two mechanisms must assert them separately**, or the half that works hides the half that does
not — the same shape as Issue 85's half-a-contract.

---

## Issue 92 — Four holes in the world, on one mistyped axis, behind a guard written for that exact zone

**Symptom.** On the 2026-08-17 verification replay the player stood in the Sprawl at zone-local
`(-17.30, -12.20)`, took a J-capture, and wrote *"What is that for?"*. The frame shows a gap in the
wall opening onto the **procedural sky** — a blue-grey daylit horizon — split down the middle by a
tall dark blade, with a blood-red `MirageDoor` silhouetted against it.

**Cause.** One ternary in `backrooms_zone2.gd:_build_alcoves()`. A recess's BACK wall is thin across
the alcove's depth axis and long across its width; a SIDE wall is the opposite. Both lines carried
the same expression:

```gdscript
# back wall — WRONG for the E/W sides
MazeKit.wall(self, "AlcBack%s%d" % [s, k], back,
    Vector3(ALCOVE_D, 0, T) if is_x else Vector3(ALCOVE_W, 0, T), HEIGHT, _wall_mat)
# side wall — correct
MazeKit.wall(self, "AlcSide%s%d%s" % [s, k, side_sign], centre + lat,
    Vector3(ALCOVE_D, 0, T) if is_x else Vector3(T, 0, ALCOVE_D), HEIGHT, _wall_mat)
```

On N and S (`is_x == false`) the back branch is right and the fault is invisible. On E and W the back
wall was built `(3.0, 4.5, 0.3)` — a 3 m blade lying ALONG the depth axis, centred on the back plane,
half inside the recess and half outside — instead of `(0.3, 4.5, 3.4)` across it. Measured from the
built scene: `AlcBackE1 pos (23.15, 2.25, 11.00) size (3.000, 4.500, 0.300)`. All four E/W recesses
were open to the world, **3.40 m wide × 4.50 m tall each**, and the blade is the dark vertical in the
capture. It also stood across the walking line to the alcove's own mirage door.

**Fix.** `Vector3(T, 0, ALCOVE_W) if is_x else Vector3(ALCOVE_W, 0, T)`. And, as a second layer,
`backrooms.gd:_black_background()` — the level was still on `assets/elements/environment.tscn`'s
`BG_SKY` while the Lab, House and Corridor had all switched to a black background years earlier for
precisely this reason, so the next pinhole is a black rectangle rather than a window onto an empty
plane.

**Why existing tests missed it.** ⚠️ This is the interesting half. `check_sprawl_alcoves.gd` had been
written **the same day**, for this exact zone, and contains a check literally named "the shell is
still closed around every mouth". It fires ONE ray outward from each recess's CENTRE — and the blade
sits exactly on that line. The ray hit it at 0.15 m and reported the wall present. A single centred
ray cannot see a hole shaped like a doorway. `check_wall_overlap_backrooms.gd` was equally blind by
construction: it asks whether two surfaces are coincident, never whether a surface is missing.

**General lesson.** ⚠️ **One ray is not a test of a surface, it is a test of a point.**
`apparition.gd:_fits()` fans 16 rays and its comment says why; `check_sprawl_alcoves.gd` had that
lesson three functions away and did not apply it. Any check of the form "is there a wall here" must
sweep. And the corollary that generalises past geometry: ⚠️ **when a mis-built object is the thing
your probe hits, the probe reports health.** The blade was not merely undetected — it was the
detector's answer.

`tests/check_shell_sealed.gd` is the guard: a 0.25 m lateral perimeter sweep at six heights, an
outward-hemisphere fan from five points in each of the eight recesses, and a 1.5 m interior floor
grid across all three zones, ~66,000 rays, with two permanent controls that punch this exact hole
back open and require both sweeps to go red.

---

## Issue 93 — An arm displaced by exactly half a corridor width, and the allowlist entry that certified it

**Symptom.** J-capture at the Backrooms hub: *"The scapes between columns to walk into are too
small."* Independently, `check_reachable.gd` had reported both of zone 1's arm mirage doors as
UNREACHABLE and that finding had been dismissed as a false positive of its 0.25 m grid.

**Cause.** `backrooms.gd:_build_entry_arm()` centred the entry arm's slab and side walls at
`(lo - HALF) / 2` with length `HALF - lo`, i.e. spanning `z = -8.5 .. 0`, where the arm runs from the
hub's south edge `-HALF` out to `lo = -7`. The whole arm sat **1.5 m (= HALF) south** of where it
belonged. Consequences, in order of how visible they were:

* the two side walls ran to `z = +0.15` — 1.65 m INTO the hub, past its centre — standing across the
  southern half of both the E and W arm mouths. Measured with the player's own capsule, the only way
  into the E arm was a **1.01 m slot against an 0.80 m capsule**: a 0.21 m band of legal standing
  positions, which is what the 0.25 m reachability grid could not thread;
* the floor and ceiling overlapped the hub's slab over a 3 × 1.5 m patch — the coincident-face class;
* and the floor ran 1.35 m PAST `EntryCap` into a sealed dead box, which is why nobody ever saw it.

**Fix.** `span_mid = (-HALF + lo) / 2`, `span_len = (-HALF - lo) + T` — the same form
`_build_choice_arm()` has always used, one `T/2` of overlap into the hub corner. Separately, the
three arrow posts moved off the arm centreline onto the jamb clockwise from their arm
(`jamb = Vector3(axis.z, 0, -axis.x)`), buried `ARROW_BURY = 0.10` into it so no two faces are
coplanar. Measured lanes: **1.01 m → 2.02 / 2.04 / 2.38 m** (N / E / W), margins 1.22–1.58 m. Both
halves proved load-bearing by reverting each alone: post back on the centreline gives 1.14 m
everywhere; old entry arm alone gives E 1.10 m and W 0.88 m.

**Why existing tests missed it.** ⚠️ It was not missed. `check_wall_overlap_backrooms.gd` found the
floor and ceiling pair on 2026-08-17 and **waived** it, as *"the entry arm's slab deliberately
overlaps the hub's"* — and the only evidence offered for that claim of intent was a comment
(*"overlapping the hub corner"*) inside the function that had the bug in it. `check_reachable.gd`
found the 1.01 m lane the same day and recorded it as its own false positive. Two guards hit the
same defect, and each was talked out of it by a different story.

**General lesson.** ⚠️ **An allowlist entry is a claim about INTENT, and a comment in the buggy
function is not evidence of intent.** Before waiving a coincident pair, derive what the geometry
SHOULD be from a sibling that is known good — here `_build_choice_arm()` was three functions away and
overlaps its hub corner by 0.15 m, not 1.65 m. And the second half, which cost as much: ⚠️ **when an
automated guard and a human disagree about whether a space is passable, MEASURE THE GAP.** Do not
loosen the grid until the complaint goes away — the grid was right.

---

## Issue 94 — Three ways to make a ray-sweep report a hole that is not there

**Symptom.** `check_shell_sealed.gd`, written to catch Issue 92, reported 1020 escaping rays on its
first run, then 199, then 128, then 20 — in zones that are demonstrably sealed. Every round looked
like a serious new defect in a different part of the level, including a set of apparent holes at
every room width-step in the Flood, a zone that had been declared out of scope.

**Cause.** Three independent degeneracies in the SAMPLING, none of them in the level:

1. **A sample dead on a wall face.** Every wall here sits at a round coordinate, and the grid started
   at a round coordinate, so samples landed exactly on faces — `x = -13.00` is the W arm cap's inner
   face to the centimetre. `intersect_ray` ignores any shape whose origin is inside it, so from there
   every ray reports clear. Fixed by an irregular phase (`PHASE_X 0.13`, `PHASE_Z 0.07`) plus a
   `_unstandable()` filter.
2. **A 45° ray threading a corner.** A fan of 16 bearings contains 45° exactly, which can pass
   through the seam where an alcove's back wall meets its side wall — a measure-zero line, not a hole.
   A 1.5 m square grid puts ~50 samples on that same diagonal, so one seam produced 199 findings.
   Fixed by 18 bearings offset 3.7°, so no ray is ever parallel to or diagonal across a wall.
3. **An eye above the ceiling.** The Flood's rooms are 2.6 m high and its `DryPlatform` stands 0.4 m
   proud of the floor, so a 2.8 m sample height put the ray at 3.2 m — outside the building, where of
   course nothing stops it. Fixed by clamping ray heights to the ceiling the up-ray actually found.

⚠️ And one non-fix worth recording, because it is the obvious one: **`hit_from_inside = true` does
not rescue case 1 here.** CSG geometry collides as a `ConcavePolygonShape3D`, and that flag only
means anything for a convex shape. Measured on one buried sample: `hit_from_inside` true and false
both returned NOTHING in all three directions tried, while `intersect_point` at the same position
returned 1 collider. `intersect_point` is the query that answers "am I inside geometry" against CSG —
`intersect_shape` is the one that does not (Issue 40), and `intersect_ray` is the one that quietly
says "clear".

**Fix.** All three above; the level needed no change for any of them. Every constant carries the
measurement that produced it, at the constant.

**Why existing tests missed it.** Nothing missed it — this is a new test's own scaffolding. It is
here because the failure mode is expensive in a specific way: **a sampling artifact looks exactly
like a serious defect in a part of the level you were not looking at**, and the temptation is to
"fix" the level. Three quarters of a day's findings in that file were the test's geometry.

**General lesson.** ⚠️ **A sampling scheme must not be commensurate with the thing it samples.** A
square grid over axis-aligned architecture, at round coordinates, with compass-point bearings, is
three coincidences waiting to happen. Phase the positions, phase the angles, and clamp to the volume
a player can actually occupy. And: ⚠️ **before believing a new guard's first red, check whether the
probe could be standing inside the wall it is accusing.**

---

## Issue 95 — A visibility audit that moved the player first, and then asked what it could see

**Symptom.** `check_backrooms_occupants.gd` failed roughly **1 run in 12**, always with the same
line — *"1 of N relocations landed in the player's view"* — and always passed when re-run. It had
been filed twice as a deferred item (backlog 04 D13, then D19) and was starting to be read as noise,
which is the worst thing an assertion can become.

**Cause.** `_audit_sample()` did two things in this order:

```gdscript
func _audit_sample() -> void:
    _audit_walk(_t - _stage_at)          # teleport + re-aim the player along a circuit
    for f in _cong.get_children():       # ...THEN detect which figures moved
        ...
        if _sees(now):                   # ...and judge visibility from the NEW pose
```

`Congregation._process()` approves a destination with `would_be_seen()` **against the player's pose
at the moment it decides**. The audit then observed that move one sample later and scored it from a
pose the harness itself had just changed. The walk is a continuous circle, so the two poses are never
identical, and a destination that was legitimately behind the player when it was chosen could be in
front of them a few milliseconds later. The feature was correct; the ruler was moving.

**Fix.** Judge with an explicit pose, and require the destination to be invisible from **both** the
pose in effect when the move was seen and the one before it — `_sees_from(cam_pos, forward, pos)`,
with `_audit_walk()` moved to the END of the sample.

⚠️ **A conjunction rather than a one-frame rewind, deliberately.** Whether a `SceneTree` script's
`_process` runs before or after the scene's node `_process` is an engine detail no test should
depend on; the true decision pose is one of those two, so requiring both removes the ambiguity
without weakening the count that must be zero.

**Measured after the fix: 12 consecutive runs, 12 passes, 0 of 177 relocations in view.** And proved
still to bite: with `congregation.gd`'s destination gate disabled the audit reports **3 of 15 landed
on screen** and goes red.

**Why existing tests missed it.** It *was* the test. Nothing above a test tests a test — the only
signals available were the failure rate and the fact that the reported violations were always
exactly one, at the edge of the view cone, and never reproducible.

**General lesson.** ⚠️ **When a harness both drives the world and judges it, the two must be ordered
explicitly, and the judgement must use the state the SUBJECT acted on — not the state the harness
has since moved to.** This is `walk_dungeon`'s "a frame count is not a clock" from the other side:
there the harness measured the machine, here it measured its own hand.

⚠️ **A sibling, found while fixing this and NOT fixed (out of scope, shared harness).**
`tests/autoplay/autoplayer.gd`'s stuck detector is frame-based — `STUCK_SAMPLES 45` frames in which
the body moved less than `STUCK_DIST 0.05 m`. A headless run reaches ~145 fps, where a body walking
at the Flood's waded 1.8 m/s covers **0.012 m per frame**, so `stuck` reads **true for the whole of a
perfectly healthy walk**. Measured directly: a walker crossing the Landing in a straight line at
full speed reported `stuck=true` on every sample. Any caller that acts on that flag is acting on
noise — `probe_flood_search.gd` uses a wall-clock leg timeout instead and never reads it. Filed in
`backlogs/04-backrooms.md` §15 for whoever owns the autoplay harness.

---

## Issue 96 — `CLAUDE.md` said the Flood was a `DarkZone`. It has not been one for a long time.

**Symptom.** The brief for a Flood content pass repeated, as an established fact to be measured,
*"the zone is a `DarkZone` (+3/s with the torch off) **and** its puzzle requires the torch off — the
Issue 18 double-jeopardy shape."* It came straight from `CLAUDE.md`'s Backrooms section, which said
in as many words: *"The zone is a `DarkZone`, so searching costs +3/s."*

**Cause.** The `DarkZone` was removed from zone 3 when exactly that double-jeopardy was diagnosed —
`backrooms_zone3.gd:_build_pressure()` still carries the post-mortem (*"light off was +5/s with no
way down, light on was a frozen bar and an invisible exit... three playtest deaths inside 10 s,
without the mechanic ever being attempted"*) — and `CLAUDE.md` was never updated. The file's own
header had already been corrected once for the same claim and carries a ⚠️ saying so.

**Fix.** The sentence in `CLAUDE.md` is now the true one, edited in place rather than annotated
underneath. And because a doc is not a measurement, it is **asserted**:
`check_flood_drowned.gd:_no_dark_zone()` scans the live scene for any `DarkZone` within 40 m of the
Flood's origin and requires none, with a control proving the scan can find the one zone 1 still has.

**Why existing tests missed it.** Nothing asserted the ABSENCE of a zone. Every guard in the project
checks that something exists or is placed correctly; the Issue-18 decisions are all "we deliberately
did not add X", and an omission has no node to assert against unless a test goes looking for it.

**General lesson.** ⚠️ **A deliberate omission needs a test, or it will be re-added by someone
reading the documentation.** This one cost a whole analysis pass its framing: the measurement it was
told to make (what does searching cost, given the double tax) had no double tax in it. The general
form: when a ⚠️ DELIBERATE comment says "we removed X", write the assertion that X is still gone.

---

## Issue 97 — Five entries in the test suite asserted nothing at all

**Symptom.** `tools/run_tests.sh` listed, among 71 guarantees, "nothing seals a doorway", "ceiling
fittings are not blown out", "nothing invisible blocks either spawn", "the House window exists and
faces the room" and "morgue trigger objects are not buried". All five columns were green. None of
the five claims was being made.

**Cause.** Four of the files (`check_fixtures`, `check_window`, `check_morgue_props`,
`check_spawn_blocked`) were diagnostic PRINTERS: they walked the scene, printed what they found, and
`return true`d out of `_process` without ever calling `quit()` — so the process exited 0 whatever
they saw. The fifth, `check_doorways`, printed `BLOCKED <name> <- <collider>` for a sealed doorway
and then called `quit(0)` **unconditionally**. They were written as diagnosis tools during earlier
bug hunts, added to the runner because they were `check_*`-shaped, and never revisited.

Two of them were also wrong in the way they measured. `check_spawn_blocked` used `intersect_shape`,
which is the one query type that reports NOTHING when it lies wholly inside a CSG slab (Issue 40) —
the exact case it existed to detect — against six coordinates hand-typed out of a House layout that
has since moved. `check_doorways` carried a hand-copied duplicate of `level_2.gd`'s `DOORS` table,
so it described the House of whenever it was last edited, and it ran on the House alone.

**Fix.** Four are now real guards: they assert, they call `quit(1)`, they assert their own sample
size, and each carries a control that is injected into the scene under test on every run — a slab
dropped in a doorway, a fitting pushed to 5.0, a `StaticBody3D` on the spawn, a window face turned
around. Three of them sweep all nine levels off the derived scene list. `check_morgue_props` is
renamed `probe_morgue_props`, removed from the runner, and its header now says which guards do make
its claim (`check_reachable` reaches both morgue triggers; `check_wall_overlap` and
`check_prop_mounting` cover the geometry).

**Why existing tests missed it.** Nothing tests the tests. The runner's only signals are the exit
code and a grep for parse/script errors, and a printer produces a clean exit code by construction.
The three vacuity guards this project already had — assert a sample size, assert a minimum count,
prove the check can fail — are all things a test must do to ITSELF, and a file that does none of
them looks identical from outside to one that does all three.

**And a SIXTH, found by the same grep and worse than the other five.**
`walk_level6_breach.gd` — the only end-to-end completability proof THE BREACH has, the one that
drives the win through `player._try_interact()` because an earlier version *"passed cleanly while
the actual game was unwinnable"* — **never called `quit()` at all.** Every terminal path printed
`RESULT: FAIL (...)` and then `return true`, which ends the SceneTree loop and exits **0**. So the
test that exists because this level once shipped uncompletable would have reported PASS if the
creature never chased, never entered the trap, or never flipped the win flag. Fixed: every path now
carries an exit code, proved by forcing `HARD_TIMEOUT_MS` to 900 ms (exit 1 with the timeout
message) and restoring it (exit 0, "win sequence confirmed end-to-end").

**General lesson.** ⚠️ **A test that never calls `quit(1)` cannot fail, and `run_tests.sh` cannot
tell the difference.** `grep -L "quit(" game/tests/*.gd` is a five-second audit and it found six —
five printers and one behavioural proof. A test that cannot fail is worse than a missing test: the
missing one is visible in the coverage table, and this one occupies its row.
⚠️ Note the second half of the `walk_level6_breach` case: `return true` from `SceneTree._process`
looks like a deliberate ending. It is, and the exit code it produces is 0.


---

## Issue 98 — A freed Object compares EQUAL TO NULL, so a control reported that it had done nothing

**Symptom.** `check_shell_sealed.gd`'s new per-level control deletes a wall in front of a standable
point and requires the sweep to see daylight. It reported *"CONTROL: found a wall to delete in front
of a standable point — FAIL"* on all eight non-Backrooms levels, i.e. it claimed it had found no
wall to delete — immediately after deleting one. Adding a debug print showed the punch loop hitting
a `CSGBox3D` on its first ray and returning.

**Cause.** The control stored the node it had just freed (`_punched = node; node.queue_free()`), and
then checked `_punched != null`. In GDScript a **freed Object compares equal to null**, so the guard
that was supposed to say "the control could not run" fired on a control that had run perfectly. The
failure was indistinguishable from the thing the check exists to report.

**Fix.** Remember the NAME (`_punched_name := String(node.name)`) before freeing, and assert on
that. `is_instance_valid()` is the other correct answer; a string is better here because the report
should name the wall it deleted.

**Why existing tests missed it.** It was new code, and it failed in the direction that looks like a
finding rather than like a bug — the sweep printed a red line saying the level had no wall to
delete, which reads as a plausible statement about a level.

**General lesson.** ⚠️ **Never `!= null` a reference you may have freed.** Use `is_instance_valid()`
or keep a scalar. This is Issue 45's family — the wrong kind of nil check, silently — and it is
worse in a test, because a test's failure output is the only thing anyone reads.


---

## Issue 99 — A runtime `CSGBox3D` is invisible to `intersect_point` as well as `intersect_shape`

**Symptom.** `check_spawn_blocked.gd`'s control drops a solid box on the player's spawn and requires
the probe to see it. Across nine scenes it reported "a box dropped on the spawn IS detected — FAIL,
[]": the probe found nothing, on a probe that works.

**Cause.** The control was built as a `CSGBox3D` with `use_collision = true`, created at runtime.
Cross-level X45 / Issue 91 already record that a runtime CSG box answers `intersect_ray` and is
invisible to `intersect_shape`; it is invisible to `intersect_point` too, and the short ray fan in
this probe starts INSIDE the control box, where a concave CSG collider stops nothing either. So the
control was undetectable by every query the guard uses.

**Fix.** Build the control from a `StaticBody3D` + `BoxShape3D`. Nine scenes went green immediately.
`check_doorways.gd`'s control is a `CSGBox3D` and works — because it is measured by a RAY that
starts outside it, which is the one query CSG answers.

**Why existing tests missed it.** X45 was written about `intersect_shape` and its lesson ("build a
control out of the simplest primitive that exists") had not been applied to `intersect_point`.

**General lesson.** ⚠️ **A test control must be built from a primitive whose collision behaviour is
boring.** `StaticBody3D` + a shape is boring; a runtime CSG node has three different answers
depending on which query you ask and where the query starts. The half that works hides the half that
does not.


---

## Issue 100 — Eleven "no X anywhere" assertions, and nothing asserting the level existed

**Symptom.** None yet — this is the one that was found by reading rather than by paying for it.
`check_dungeon_entities.gd` asserts DUNGEON_NIGHTMARES §B10's bans across three seeds: no
`DarkZone`, no `DreadZone`, no `ApparitionDirector`, no standstill panic, no `RandomAmbient`, no
entity in the spawn chamber, no beartrap by a Matron spawn. Eleven absences per seed, thirty-three
assertions, all green.

**Cause.** Every one of them is trivially TRUE of an empty scene. The file did guard against
`dungeon.tscn` failing to load (`has_method("get_gen")`), but not against the dungeon building
badly: a generator that returned three chambers, a content pass that spawned nothing, a rename that
made `_count_script()` match nothing, would each leave every ban satisfied and the suite green.

**Fix.** Assert the level FIRST — `>= 9 rooms and exactly 7 sconces`, which is `MIN_CHAMBERS` and
the win condition — and then plant a real `DarkZone` in the scene every run and require the same
counter to find it. Measured: 29 / 28 / 28 rooms and 7 sconces at seeds 101 / 404 / 707, control
caught at all three. ⚠️ And a smaller trap inside the fix: `gen.get("chambers")` returns null (the
generator's property is `rooms`; `_chambers` is private) and `null as Array` THROWS, which aborted
`_audit()` before every ban in the file — a thrown test still exits 0 (Issue 45). Read the property
name off the script, and type-check with `is Array` rather than casting.

**Why existing tests missed it.** This IS the existing test. Nothing in the project asserts that a
guard measured anything before it started reporting absences.

**General lesson.** ⚠️ **An absence assertion needs an existence assertion beside it, and a live
control above it.** "No X anywhere" is the cheapest thing in the world to satisfy: build nothing.
Every ban-shaped guard in this project reads the same way, and the pattern to copy is the two lines
added here.


---

## Issue 101 — A sound that could not be turned up, and was already clipping

**Symptom.** The user asked for the Corridor's `mirror_wake` cue to be *"much louder"*. It was
being played at `volume_db = +6.0` from an `AudioStreamPlayer3D` with `unit_size 8` at a 14 m
trigger. There is no bigger number available: at that distance the attenuation is
20·log₁₀(8/14) = −4.86 dB, so the file's own −1.01 dBFS peak was already landing at **+0.13 dBFS at
the listener** — fractionally clipping the master on every play, silently, for its whole life.

**Cause.** The file's CREST FACTOR, not its level. `make_sfx_mirror.py` peak-normalises to 0.89
like every generator here, and the material is one transient plus a long decay: measured **peak
−1.01, RMS −20.5, loudest-300 ms −14.03 dBFS**, i.e. 13 dB of headroom that is all silence.
Perceived loudness follows the RMS, and no gain changes the ratio between the two.

**Fix.** Buy the loudness from the FILE. A compressor was tried first and swept over six settings:
loudest-300 ms went **−14.6 (worse) to −12.0 (best)** — about 2 dB, and the reason is physical
rather than a tuning miss. Limiting an *envelope* does not raise a waveform's RMS toward its peak;
filtered noise and ringing partials sit 10–12 dB below peak by construction. What does is
**saturation**: `tanh` drive after the compressor, swept 3 → −5.69, 6 → −3.33, 16 → −1.82. Shipped
at drive 3 for **−5.69 dBFS**, +8.3 dB, and the call-site gain was then re-derived from the new
measurement: −1.5 dB at a 7 m trigger delivers loudest-300 ms **−6.03 dBFS with the peak at
−1.35** — 6.9 dB louder than before AND no longer clipping. For reference, `shared/jumpscare.wav`,
the densest asset in the project, has a crest factor of **2.1 dB**; that is only reachable with
saturation, which is why it sounds twice as loud as everything else at the same peak.

**Why existing tests missed it.** `check_mirror_wake.gd` asserts that the sound resolves, that its
base name is unique, that it is a one-shot and that it costs no panic. Nothing in the project
measures a delivered level, and nothing computes distance attenuation against a file's own peak.

**General lesson.** ⚠️ **"Set the gain from the file's measured level" is only half a rule — measure
the DELIVERED peak, which is `file peak + volume_db + 20·log₁₀(unit_size / distance)`, and check it
against 0 dBFS.** And when a sound needs to be louder and already has no headroom, the answer is a
denser file, never a bigger number: RMS is loudness, peak is only headroom. ⚠️ `max_db` is the other
half — a one-shot fired at 7 m keeps playing while the player walks to 2 m, where the default
`max_db 6.0` adds another 6 dB. Both new cues here pin it.

---

## Issue 102 — A Node3D's forward is −Z, so the obvious yaw is π out

**Symptom.** The Corridor's running silhouette, rebuilt from parts in a stride pose, sprinted across
the corridor **backwards** — leading arm and leading leg trailing. Invisible in every headless
assertion (its position, size, panic and audio were all correct) and obvious in the first
screenshot.

**Cause.** `fig.rotation.y = atan2(-side.x, -side.z)`. It reads as "face the direction of travel",
because travel is `-side`. But `Basis(UP, θ)` maps a node's **−Z** — its forward — to
`(-sin θ, 0, -cos θ)`. Setting `θ = atan2(-v.x, -v.z)` points **+Z** along `v`, i.e. the node faces
`-v`. The correct yaw to face along `v` is `atan2(v.x, v.z)`.

**Fix.** `atan2(side.x, side.z)`, with the derivation written at the call site.

**Why existing tests missed it.** Facing is not geometry any guard in this project measures, and
apparent size — which `check_corridor_events.gd` does measure — is identical either way for a
symmetric figure.

**General lesson.** ⚠️ **The two yaw idioms in this codebase are not interchangeable and both are in
use.** `atan2(v.x, v.z)` points a **node's forward** (−Z) along `v`; `atan2(v.x, v.z)` applied to an
*inward* vector is also what `_panel_transform()` uses to point a **QuadMesh's +Z** into a room,
because a quad faces +Z while a node faces −Z. When a prop is built from a mesh whose facing matters,
photograph it — a wrong yaw is one character and no assertion.

---

## Issue 103 — A textured quad with no material: invisible in game, and invisible to the guard

**Symptom.** The Corridor's rebuilt entrance note rendered as a plain grey quad, and
`check_art_aspect.gd` — which sweeps every scene and asserts that no textured surface is stretched —
reported the same count of measured surfaces as before it existed. Both green.

**Cause.** The material was built and configured (`albedo_texture`, `TRANSPARENCY_ALPHA`, emission
texture, `EMISSION_OP_MULTIPLY`) and never attached: the `page.set_surface_override_material(0, mat)`
line was missing. The mesh therefore had Godot's default material.

**Fix.** One line. What matters is the second half: `check_art_aspect.gd` collects surfaces **by
their material's `albedo_texture`**, so a mesh with no material is not "a surface with a wrong
aspect", it is not a surface at all — the guard walked straight past it.

**Why existing tests missed it.** They did not miss it, they *could not see it*. Every art guard in
this project is keyed off the material.

**General lesson.** ⚠️ **When a guard's population is derived from the thing being tested, forgetting
to wire the thing up removes it from the test rather than failing it.** The cheap defence is what
these guards already do elsewhere and what this one does now: assert the SAMPLE SIZE, and assert it
went UP when a surface was added. `check_art_aspect.gd`'s "44 measured" is what caught this, by
being 43 for one run.

---

## Issue 104 — Three ways to measure a live scene at the wrong moment

**Symptom.** `check_corridor_events.gd`, driving a brand-new interactable through the real player
path, reported in one run: the shipping raycast finds nothing, the event costs +8.4 panic instead of
+15, and an open door has sealed the corridor to 1.15 m. All three were the test.

**Cause,** and they are three different clocks:
1. **`_interact_target` is one frame behind a teleport.** It is recomputed in `player.gd`'s own
   `_process` from a raycast, so asking for it in the frame that moved the player reads the target
   from where they used to be — null.
2. **A panic spike measured after a wait is a decayed spike.** The test also had to wait 1.35 s for
   a delayed scrawl; `PANIC_DECAY_RATE` is 3.5/s, so 15 − 1.9 × 3.5 = 8.4, exactly what it printed.
3. **The player's own capsule is a body.** A free-width sweep using `intersect_point` counted the
   player — standing 2.4 m away because the test had just walked them there to press E — as an
   obstruction, and chopped a 2.20 m clear run into 1.15 m.

**Fix.** Split the position and the press into two frames; sample a spike where it happens and carry
the value forward; `q.exclude = [player.get_rid()]`. A fourth of the same family was found while
adding a control: a `StaticBody3D` added and positioned in one call is **not in the physics server
yet**, so a 2.4 m block reported 3.05 m of free floor until the measurement was moved a frame later.

**Why existing tests missed it.** No existing test drives an interactable and then measures the
world it changed. `check_interact_reach.gd` presses E; `check_corridor_doors.gd` measures geometry.
This is the first that does both.

**General lesson.** ⚠️ **Every one of these looked exactly like a defect in the feature.** When a new
guard goes red on its first run against code you just wrote, the prior should be that the guard is
wrong: it is younger than the feature. Three specific clocks to check before believing it — the
target raycast (one frame), the physics server (one frame), and anything that decays (measure at the
event).

---

## Issue 105 — A clearance assertion the prop it guards cannot fail

**Symptom.** `check_corridor_events.gd` asserts that the new false exit door, swung open, leaves a
walkable corner. To prove the check could fail, `OPEN_DEG` was pushed 62° → 150°. It stayed green at
**2.55 m of 3.0**.

**Cause.** Arithmetic. The leaf is 0.909 m wide and hinged on a wall of a 3.0 m corridor, so its
maximum possible intrusion is 0.909 m at 90° and the free run can never drop below 2.09 m — a full
metre above the 1.2 m threshold. The assertion was true by construction and therefore worth nothing,
in a project that has shipped an interactable narrowing a route three times in one week (Issues 65,
67, 76).

**Fix.** A permanent positive control inside the test: a 2.4 m `StaticBody3D` is placed in the same
corner, the same `_free_width()` sweep is run against it, and the result must be **below** the
threshold. Measured 0.65 m. The door assertion keeps its value for the case it is really for — a
future re-placement onto a side wall, a wider leaf, a second door — and the control is what proves
the instrument still works.

**Why existing tests missed it.** It is a new test. The point is that it passed, first time, with no
sign that it was measuring nothing.

**General lesson.** ⚠️ **"Prove the check can fail" means proving it with the mechanism it is meant
to catch, and when that is impossible, say so and control for it separately.** A threshold whose
subject cannot reach it is the same failure as `check_apparition_clearance.gd`'s "0 spawns checked …
PASS": the number is fine, the population is empty.

---

## Issue 111 — An `await` inside a frame-scheduled `SceneTree` test drops every assertion after it, silently, and still prints PASS

**Symptom.** `walk_backrooms.gd` gained five assertions about the Flood's new plate gate. The run
printed `39 checks, 0 failed` — the same count it printed *before* the assertions were added. No
error, no warning, no missing-output complaint.

**Cause.** The test is a `SceneTree` script whose stages are dispatched from `_process()` on a frame
ladder (`if _frame == 32: _zone3_logic()`). The new code did `await create_timer(2.2).timeout` to
wait out a completion tween, which **suspends the calling function and returns to `_process`** — and
the quit condition is `_frame > 200`. Headless runs uncapped at ~145 fps, so 200 frames is **1.4 s**:
the tree quit 0.8 s before the continuation was due, taking the five unrun assertions with it. They
were never counted, so the total was indistinguishable from a run in which they all passed.

Two separate traps in one line, and the second is the older one: **a frame count is not a clock**
(D20, Issue 95, and the door-swing measurement of 2026-07-28 are the same family).

**Fix.** No `await` in the stage machine at all. The stage that starts the tween records
`Time.get_ticks_msec()`, `_process` polls `if _zone3_stage == 1 and now - _seat_t > 2.4`, and the
quit condition became `_frame > 200 **and** _zone3_stage >= 2` — so the run cannot end before the
deferred stage has actually happened. The count went 39 → 43.

**Why existing tests missed it.** Nothing checks a test's own check count against a previous run,
and there is no mechanism that can: a suspended coroutine is not an error condition. The only signal
was the arithmetic — five assertions added, zero appeared.

**General lesson.** ⚠️ **In a `SceneTree` test, `await` and a frame-scheduled stage machine are
mutually exclusive.** If a stage must wait, poll a wall clock and make the quit condition depend on
the stage having run. And when you add N assertions to an existing test, **read the total** — the
project's standing rule that "a test that samples nothing must fail loudly" has a quieter sibling: a
test that skips assertions reports exactly the same number as one that never had them.

---

## Issue 112 — A positional "bearing" that was flat to 0.4 dB across the whole level, because `max_db` clamps `volume_db` too

**Symptom.** The Flood's new plate table got the project's standard two-layer tell: a far cue for a
bearing, a near confirm for "you are here". Measured in every room from the `.wav` files on disk, the
far cue read **-20.7 dBFS in the Basin and -20.7 dBFS in the Sump, the Throat, WestRun and the
Descent** — identical, 8 m and 20 m from the emitter alike. It was audible everywhere and pointed
nowhere.

**Cause.** Godot 4's `AudioStreamPlayer3D::_get_attenuation_db()` computes the distance attenuation,
**adds `volume_db`, and only then clamps the sum to `max_db`**. `max_db` defaults to **+3**. With
`unit_size 18` covering a 28 m wing, every listening position was inside the near field, where the
inverse-distance term is large and positive — so the sum was above +3 everywhere and every position
returned exactly `max_db`. The emitter had no gradient at all, and `volume_db` was not controlling
the level either.

The first two attempts were both fixes to the wrong constant: lowering `volume_db` (-12 → -10 → -4)
changed nothing that was audible, because the clamp was doing the work.

**Fix.** Two constants with two different jobs, stated at both call sites: **`max_db` is the
near-field ceiling** and **`unit_size` is the gradient**. `FloodPlate` uses `FAR_MAX_DB = -6.0` with
`FAR_UNIT = 5.0` (measured: -20.7 dBFS at the table, -28.3 dBFS in the far corner, a 7.6 dB fall
across the wing) and `NEAR_MAX_DB = -3.0` with `NEAR_UNIT = 3.0` (which drops *below* the water bed
by the far end, which is what makes the pair two layers rather than two copies).
`check_flood_puzzle.gd` measures all three properties — over the bed everywhere, under the
`flood_knock` at the table, and a ≥3 dB fall across the rooms.

**Why existing tests missed it.** `check_backrooms_audio.gd` asserts that self-starting emitters near
the player stay under `MUSIC_VOLUME_DB` — a ceiling, which the clamp guarantees. Nothing had ever
asserted that a *bearing* cue actually varies with position, because until now every one of them was
tuned by ear.

**General lesson.** ⚠️ **A far cue's job is a gradient, and a gradient is an assertion.** "Loud enough
to hear" and "quieter as you walk away" are different claims and only the first was ever checked. And
when a gain change makes no measurable difference, suspect a clamp before suspecting the measurement:
in this engine `max_db` silently swallows `volume_db` for every emitter you are standing near.

---

## Issue 113 — A state assertion sampled in the same frame as the press, on a feature whose state changes one tween later

**Symptom.** `check_flood_drowned.gd` was updated for the two-press search (open, then take). The new
assertion *"opening TAKES NOTHING: no page, no journal entry"* was written immediately after
`ai_interact()`. It passed. It also passed with the defect deliberately restored — the page shown on
open, exactly the behaviour the player had filed on capture 005.

**Cause.** `SunkenItem` opens on a `Tween` and fires its reveal from the tween's `finished`
(`LID_TIME` 0.8 s), which is the correct ordering and the whole of Issue 58. So the journal snapshot
taken one statement after the press is a snapshot of a world where the reveal has not happened yet —
in the fixed build *and* in the broken one. The assertion was measuring the press, not the outcome.

**Fix.** Move the comparison to the stage that already waits out the lid (`LID_WATCH` 1.3 s), and
compare against the journal size captured **before** the haul rather than before the take. Verified
by restoring the defect: red, `journal 0 -> 1 across the whole haul`.

**Why existing tests missed it.** It *is* the test. The point is that it was green in both
directions, which is the failure mode that costs weeks.

**General lesson.** ⚠️ **Sample a deferred effect where it lands, not where it is triggered.** This is
the third head of the same beast — Issue 58 (a note shown before the tween it describes), the
2026-07-28 door-clearance check (measured in the frame `swing_ajar()` was called), and now an
assertion that a deferred thing did NOT happen. If the feature's own correctness depends on an
ordering, the test must span that ordering; anything inside one frame proves nothing about it.


---

## Issue 121 — A page lying flat has a right way up, and nothing in the project could see it

**Symptom.** Playtest capture 001, 2026-08-18, at (0.90, 0.00, 3.30) in the Corridor: *"Turn it 180
degrees, it is currently the wrong side from the place I enter the room"*. The screenshot is
`HOTEL VESPER` printed upside down on the first document in the level — the one the objective line
sends the player to, 4 m from the spawn.

**Cause.** `_spawn_intro_note()` laid the artwork quad flat with `page.rotation_degrees.x = -90.0`.
That is correct as far as it goes: rotating a `QuadMesh` −90° about X sends its normal (local +Z) to
world +Y, so the page faces up. But the same rotation sends its local **+Y — the top of the artwork —
to world −Z**, i.e. straight back down the corridor into the face of the player walking toward it.
The player enters at (0, 0, 2) facing +z; a reader looking down at a page reads "up the page" as
"further away", so the lettering has to point along the walk, not against it.

**Fix.** Two halves, and both matter.
1. `IntroNote` (the body) is yawed onto `pt.dir` — the direction a player walking `PATH_2D` is
   travelling when they reach the table — so "away from the reader" becomes the body's own local +Z
   rather than an assumption about which way the level happens to start.
2. The page quad carries an **explicit `Basis(Vector3(-1,0,0), Vector3(0,0,1), Vector3(0,1,0))`**
   instead of a second euler term. `rotation_degrees` composes in YXZ, so which of x/y/z carries the
   180° flip is not readable from the source, and the failure is silent: the page still lies flat and
   still renders, it is just unreadable.

**Why existing tests missed it.** This is the interesting half. The Corridor is swept by four flat-prop
guards and **all four are structurally blind to a rotation about the prop's own normal**:

| guard | what it asks | what it says about an upside-down page |
|---|---|---|
| `check_note_mounting.gd` | is there solid geometry BEHIND the prop, along its thin axis? | yes — the table is still under it |
| `check_art_aspect.gd` | is the mesh's aspect the texture's aspect? | yes — 1.000×, rotating does not stretch |
| `check_prop_mounting.gd` | is the gap to the wall in band? | not a wall prop; skipped |
| `check_wall_overlap.gd` | do two surfaces coincide? | no |

A 180° roll changes no distance, no aspect and no clearance. Every measurement in the project was of
a *relationship between two objects*; nobody had ever asserted a prop's own **orientation relative to
the player**.

**Fix to the tests.** `check_corridor_events.gd` gained section C: the page's normal must be world up,
and its text-up vector must dot > 0.85 with the SPAWN'S HEADING — read out of `corridor.tscn` on the
frame the scene is handed over, before anything in the test moves the player, so the assertion cannot
be satisfied by the level agreeing with its own path table. Plus a downward ray requiring the page
still to be resting on the table, because turning a prop is exactly how a mounted thing becomes a
floating one. ⚠️ The reference is the spawn's **facing**, not the spawn→note vector: the table stands
1.05 m off the centreline, so spawn→note is a 28° diagonal (dot 0.885) and a threshold set against it
would have been within 0.035 of passing a page turned 90°. Verified red both ways — restoring
`rotation_degrees.x = -90` gives dot **−1.000**, and lifting the page 0.5 m reddens the resting ray.

**General lesson.** ⚠️ **A prop has a facing, and "it is mounted correctly" is not the same question as
"it is oriented correctly".** Any prop with legible content on it — a page, a plate, a sign, a
screen — needs its up-vector asserted against where the player will be standing, and the player's
position has to come from somewhere the level did not generate. The whole family of geometry guards
here measures object-to-object relationships and can never catch this class on its own.


---

## Issue 122 — A fullscreen scare image that was 4× brighter than every other screamer in the game

**Symptom.** Playtest capture 002, 2026-08-18, on the Corridor's false room 217: *"Make the image more
dark and aggressive"*. The two adjectives arriving in one sentence is the tell.

**Cause, measured.** `Screamer.flash_scare()` puts the image FULLSCREEN over a black panel for 0.9 s,
and this project has no tonemapping, no glow and no exposure control — the file is what hits the eye.
Mean luminance of every screamer the Corridor can show, 0–255:

| image | mean | pixels above 0.90 sRGB |
|---|---|---|
| `screamer_false_door.png` (v1) | **57.97** | **1.97 %** |
| `screamer_hotel.png` — the level's FATAL screamer | 15.04 | 0.00 % |
| `screamer_manager.png` | 10.82 | 0.00 % |
| `screamers/shared_screamer.png` | 8.48 | 0.00 % |

v1 was a pale, evenly-lit cream face on a lit background: **the only screamer in the game with
blown-out pixels in it**, shown to a player whose eye has spent 185 m in a hall lit at ~0.45 energy.
"Aggressive" failed for the same reason "dark" did — the image had no shadow to be aggressive in.

**Fix.** A new flux generation (a lunge out of a doorway with the frame either side, deliberately not
a head-on portrait, so it cannot be confused with the fatal screamer), graded by
`tools/make_false_door_screamer.py` — radial vignette to crush the surround, 0.78 exposure, 1.16
gamma, a rust cast — to **mean 11.35, 0.00 % hot, p99 114.4**.

**Why existing tests missed it.** Nothing in the project had ever measured a texture's BRIGHTNESS
except at prop scale: Issue 63 measured a wall panel as *contrast against the wall around it*, which
is the right question for a thing in the world and the wrong one for a thing that fills the screen.
A fullscreen image has no surround to be contrasted against; the black panel behind it is 0.

**Fix to the tests.** `check_corridor_events.gd` section D stride-samples the shipped texture and
asserts its mean against **`Screamer.LEVEL_SCREAMERS[3]`'s own image** rather than a typed number, so
the bar moves if the level's art direction does. ⚠️ Three details that are the whole value of it:
(1) **stride, never `Image.resize`** — a bilinear downsample averages, which is exactly how a small
blown-out highlight vanishes from the statistic that exists to find it; (2) the sample size is
asserted (116 964 pixels), because a stride that silently collapsed would report a comfortable mean
of 0 and pass; (3) there is a **p99 FLOOR as well as a mean ceiling** — the picture is on screen for
0.9 s and "dark" must not be allowed to become "a black rectangle".

**General lesson.** ⚠️ **Measure a fullscreen image as an absolute level; measure a prop as contrast.**
They are opposite questions and using the wrong one has now cost this project a finding in both
directions (Issue 63 was an absolute measurement of a prop; this was no measurement at all of a
fullscreen image). And ⚠️ **compare art against the game's own reference art, not against a constant**
— `screamer_hotel.png` was already the right answer sitting in the same folder.


---

## Issue 123 — "Louder" when there is no gain to turn up

**Symptom.** Playtest capture 002, 2026-08-18: *"Use the sounds for shared screamers and make it
louder"*, about the Corridor false door's `flash_scare`.

**Cause.** There is nowhere to put a gain. `Screamer.flash_scare(image, audio_base, hold)` loads the
stream by base name onto `Screamer`'s own `AudioStreamPlayer` and plays it at 0 dB; it takes no volume
argument, and `screamer.gd` is a shared file. The level cannot turn its own sting up. Worse, the
purpose-made `false_door_scream.wav` was already built dense — peak −1.01 dBFS — so even if a gain
existed, ~1 dB of it was real and the rest would have been clipping.

**Fix.** The *choice of file is the volume control*. Decoded and clamped to ±1.0 as the mixer will:

| | peak | RMS | loudest 300 ms |
|---|---|---|---|
| `false_door_scream.wav` | −1.01 | −6.37 | **−3.79 dBFS** |
| `all_levels_screamer.mp3` | +0.00 | −4.69 | **−0.16 dBFS** |

**+3.63 dB, and that is essentially all the headroom there is** — the shared sting lands 0.16 dB off
full scale. Nothing was added on top. What the switch actually buys beyond the 3.6 dB is density
(1.85 s of near-brickwalled scream against 1.6 s) and recognition: it is the sting `_apply_level_av()`
pairs with the shared `screamers/` image pool, i.e. the one the player already flinches at.

⚠️ **A measurement trap on the way.** `all_levels_screamer.mp3` decodes in ffmpeg to a **peak of
+34.56 dBFS**, with 30 % of its samples over 1.0 — LAME will happily encode a signal fed to it above
full scale. CoreAudio reports +0.00 because it clamps. Either number quoted on its own is a lie about
what the player hears: the honest figure is the ffmpeg decode **clamped in software the way the mixer
clamps it**, which is where −0.16 comes from. `ffmpeg -af volumedetect` on the raw file would have
reported "max_volume: 0.0 dB" and hidden the whole thing.

⚠️ **And it is deliberately not the level's FATAL sting.** `INTRO.md` records the rule — reusing the
death sound for a survivable beat teaches that the death sound is free. The Corridor dies to
`screamer_corridor`, not to the shared sting, so this particular borrow is legal; `check_corridor_events.gd`
asserts the survivable and fatal base names stay different, which is the part that would silently rot.

**Why existing tests missed it.** Nothing asserted which sound a `flash_scare` plays anywhere in the
game — the base name was a string literal at the call site in every one of them.

**General lesson.** ⚠️ **When a subsystem gives you no gain, the asset IS the mix.** Set it from the
file's measured, CLAMPED level, and say what the ceiling is — "make it louder" has a hard stop and the
honest answer is sometimes "this is the loudest sound that is not distortion". ⚠️ And retire the file
you replaced rather than leaving it on disk: `false_door_scream.wav` is deleted and its generator
carries the verdict in its header, because an orphan asset nobody references is the `sprawl_wall_hum`
trap.

---

## Issue 131 — A gain set from the file and never from the room: the Sprawl's whisper was inaudible everywhere, and it later became the thing the level could not be finished without

**Symptom.** The Sprawl's crate (THE BOX IN THE DARK, 2026-08-17) is found by a two-layer whisper —
`sprawl_call_far` for a bearing, `sprawl_call_near` to confirm. On the 2026-08-18 playtest the player
walked past it and photographed the crate only after being led to it by a marker in a capture note.
Measured from the shipped constants, the reason is not subtle: the far cue reached **−25.2 dBFS with
the player's nose against the box**, falling to **−35.2 dBFS at the far corner** of a 40 × 40 m hall.

**Cause.** The gains were set correctly by the project's own stated rule — *"set a gain from the
file's measured level, not from a plausible-looking number"* — and the two files really do measure
−17.2 and −16.9 dBFS. What nobody measured was **the bed they play over**. `backrooms.gd` runs the
score at `MUSIC_VOLUME_DB` −4 on a −18 dBFS file, i.e. **−22.0 dBFS effective**, plus the fluorescent
hum at −24.3. So the loudest the cue ever got was **3.2 dB UNDER the music**, and 13.2 dB under it
where the player was standing when they needed it. The file rule is only half a rule.

It was survivable while the crate was an optional aid — the `water` + `whisper` tell at the real wall
was still a route out. On 2026-08-18 the user made the crate the **gate** (the real glitch wall is
sealed until the thing inside runs through it), which turned this loop into the only thing standing
between the design and an unwinnable zone.

**Fix.** `sprawl_crate.gd`'s six constants, re-derived against the measured bed:
`FAR_DB 6.0 / FAR_UNIT 22 / FAR_MAX_DB 5.0` and `NEAR_DB 6.0 / NEAR_UNIT 4 / NEAR_MAX_DB 5.0`.
Measured at the worst standable point in the zone (50.9 m, the opposite recess): **+3.6 dB of margin**;
at the crate **+9.8 dB**; the near confirm runs +10.1 dB at 2 m and **below the bed past ~18 m**.

⚠️ And the standard it is tuned to had to change with it. One emitter **cannot** be audible across
45 m *and* carry a level gradient across 45 m: `level(d) = min(max_db, volume_db + 20log10(unit/d))`,
so the dB of slope available between two distances is fixed by their **ratio** — spanning 3 m to 48 m
usefully needs ~24 dB of range, which puts the cue at +4 dBFS on top of the player. So the far cue
carries the hall nearly flat and gives its bearing by **panning** (Godot pans an
`AudioStreamPlayer3D` by angle, which is a direction a flat level still has), and the near confirm
owns the last-stretch gradient. That is the same split Issue 112 arrived at from the other side.

**Why existing tests missed it.** `check_sprawl_crate.gd` asserted the cue's *structure* — two
layers, `unit_size` ordering, the Master bus, self-looping, a different file from the wall's tell —
every one of which was true of a sound nobody could hear. `check_backrooms_audio.gd` asserts emitters
stay **under** `MUSIC_VOLUME_DB`, i.e. a ceiling, which an inaudible cue passes trivially. The test
now derives the bed from the scene's own non-positional players (falling back to `backrooms.gd`'s
documented −22.0 for the score, which is an `.mp3` and cannot be read by the RIFF reader) and samples
the cue at **1593 points on a 1 m grid over the whole hall and all eight recesses**, asserting the
worst one still clears it. Restoring the old six constants turns it red at −14.2 dB.

**General lesson.** ⚠️ **"Set the gain from the file" is half the rule; the other half is "and then
measure it against the bed it plays over, at the worst place the player can be standing."** A level
number is meaningless on its own — Issue 62 says the same thing about brightness, and this is its
audio twin. ⚠️ And when a cue stops being optional, its audibility stops being a mix note and becomes
a **completability assertion**: the moment the crate became a gate, this loop needed the same
treatment as the Flood's knocks (`sunken_item.gd:_process` gated on `is_taken`, never on
`is_searched`) — permanent, positional, and asserted rather than assumed.

---

## Issue 132 — `Object.get()` cannot read a `const`, and the `null` it returns silently becomes 0.0

**Symptom.** The new whisper-audibility sweep in `check_sprawl_crate.gd` builds its sample grid from
the zone's own dimensions — `_zone.get("HALF")`, `_zone.get("ALCOVE_D")`, `_zone.get("ALCOVE_AT")`,
`_zone.get("SIDE_AXIS")`. Written that way it produced **one point** and reported a comfortable pass,
because the assertion under it had not been written yet. Caught before it shipped only because the
sample-size floor (`sampled >= 1500`) was added in the same edit.

**Cause.** `HALF`, `ALCOVE_D` and the rest are `const`, and **constants are not properties**.
`Object.get("HALF")` returns `null`, and `float(null)` is **0.0** with no error and no warning. So
the grid loop `while x <= half - 1.0` ran from −1.0 to −1.0: one iteration, one point, and a
`SIDE_AXIS` lookup on `null` that a `Dictionary`-typed local quietly accepted as empty.

**Fix.** `(_zone.get_script() as GDScript).get_script_constant_map()`, which is what every other test
in this project that reads a level's constants already uses (`check_backrooms_seam.gd`,
`check_noclip_fall.gd`). And the sample-size assertion stays, because it is the only thing that could
ever have caught it.

**Why existing tests missed it.** They did not: this is a test's own bug, and it is the exact shape of
the failures `CLAUDE.md`'s testing section already catalogues — *"0 spawns checked … PASS"*,
*"0 apparitions in 400 s"*. A guard whose sample collapses to nothing reports the same word as a guard
that measured everything.

**General lesson.** ⚠️ **`get()` reaches vars, never consts** — and the difference does not throw, it
returns 0. ⚠️ And the durable defence is not remembering that: it is **asserting your own sample size
next to every sweep**, so a grid that collapses fails loudly instead of passing quietly.

---

## Issue 141 — A level snapshot that saved a randomisation and never read it back, and the ledger it restored on top

**Symptom.** Walk out of KONTUR through its back door and walk in again, and the level comes back with
its **eight-gate ledger intact** and its **answers re-rolled**. Gate 7's real door seam is on a
different wall than the one the player found; gate 1's black door may be on the other side, with the
hole in the floor now under the antechamber they walked through safely on the previous visit.

**Cause.** `kontur.gd:save_progress()` had written `"dark_x"` since the day the snapshot was added and
**nothing anywhere read it back**; `_gate1_black_east` was not saved at all. `_restore_progress()`
restored the ledger, the strikes, the forfeit flag, the hammer and the carried bottle — everything
except the two dice. `CLAUDE.md` states the exact rule this breaks, in this level's own section:
*"KONTUR must restore its randomisations too … Restoring the gate ledger while re-rolling the answers
would mark gates passed whose puzzles now have different solutions."*

**Fix.** `_preload_snapshot()`, called as the FIRST line of `_ready()` — before `_build_geometry()` and
`_spawn_gate1_doors()`, which are what consume the dice. `_restore_progress()` runs LAST on purpose so
it can re-apply the ledger over finished props, and that is far too late for this half. Both values
plus the new `mimic_site` are saved and restored; an older snapshot with no randomisation keys warns
rather than silently re-rolling.

**Why existing tests missed it.** Nothing anywhere asserted that a level's randomisations survive a
resume. `check_level_resume.gd` proves the Lab's breaker state comes back and that a death wipes it —
i.e. it tests the *ledger*, which is the half that already worked. The new `check_kontur_resume.gd`
drives a real forward-and-back transition with a DIFFERENT seed pinned before the return, so a level
that re-rolled lands somewhere demonstrably else: with the fix disabled it goes red 10 ways.

**General lesson.** ⚠️ **A snapshot key with no reader is worse than no key**, because the presence of
the write is what stops anyone asking. Grep the restore path for every key the save path emits — it is
a two-minute check and it found a shipped defect here. ⚠️ And the order matters as much as the
content: **anything that seeds GEOMETRY must be restored before the geometry is built**, which is a
different phase from restoring puzzle state.

---

## Issue 142 — Restoring a ledger without restoring the world it describes: KONTUR's airlock walled the player in permanently

**Symptom.** Clear KONTUR's gate 8, walk back through the back door for a note, and return. The
Airlock→Escort doorway is **solid again**, the marker minigame does not run, E does nothing, and there
is no way past. The exit door is 32 m beyond it and the player spawns on the far side of the wall from
the back door. The run cannot be finished and cannot be left.

**Cause.** `_ready()` rebuilds every physical gate seal from scratch on every load, and
`_restore_progress()` restored only the eight-gate **ledger**. Three of those seals stand across the
spine — `FungalBarrier` (z=27), `RosterSeal` (z=35), `AirlockSeal` (z=66) — and the airlock one is
unrecoverable by construction: `_tick_airlock()` opens with `if _gates["airlock"] … return`, so the
one code path that can free `AirlockSeal` is switched off by the very flag the restore just set. The
black `ChoiceDoor` was rebuilt shut on a gate that cannot be re-taken, for the same reason.

**Fix.** `_reopen_passed_gates()`, called from `_restore_progress()`: open the black door instantly
(`ChoiceDoor.open_instantly()`, additive), dissolve the barrier, free the roster seal, free the airlock
seal **and its whole marker widget**, and silence the phone (`RotaryPhone.mark_smashed()`, additive and
default-preserving — the Backrooms' two phones never call it). `_tick_airlock()`'s success branch was
extracted to `_pass_airlock()` so a headless test can drive the shipping path.

**Why existing tests missed it.** `walk_kontur.gd` and `check_kontur.gd` both build the level once,
from scratch, with an empty snapshot — the state in which this defect cannot exist. Nothing in the
project had ever loaded KONTUR **twice in one run** with progress between the two.
`check_kontur_resume.gd` does, and probes the doorway with a ray plus a node check: the ray alone
passed on the broken build for the wrong reason, because with the spine re-rolled (Issue 141) there
was no wall at the remembered offset either.

**General lesson.** ⚠️ **A ledger and the world it describes must be restored together, or the two
disagree and the door reads the ledger.** The general test is not "does the flag come back" but
"having come back, can the player still finish". ⚠️ And a probe aimed at a REMEMBERED coordinate on a
level that may have moved can pass while measuring open air — probe the live geometry, and pair a
physics query with a structural one.

---

## Issue 143 — A test's doorway table copied from the level, and three of its eight rows were pointed at rooms that no longer existed

**Symptom.** `check_kontur.gd` printed eight comfortable `OK`s for doorway clearance on a level whose
room graph had grown from 8 rooms to 13. Rows named "Archive<->Airlock", "Airlock<->Escort" and
"Escort<->Terminus" described doorways at z=36, z=41 and z=67 that are not there — the real ones are at
35, 66 and 92. Each fired its ray through empty floor, found nothing, and reported clear.

**Cause.** The table was a hand-written mirror of `kontur.gd:DOORS`, taken at a moment when it was
correct. The last row is the sharpest instance: it probed **x = 0**, while the whole facility tail is
built at one of three randomised x offsets — so two runs in three it was measuring a different room
entirely. The floor sweep had the same rot, stopping at z=72.5 on a spine that runs to z=98, i.e. never
looking at the Escort corridor, the Terminus, or the floor under the exit door.

**Fix.** The table is DERIVED: `current_scene.get("DOORS") + current_scene.call("_tail_doors")`, with a
local map supplying only the human labels, plus a `MIN_DOORWAYS` floor so a table that fails to read
comes back red instead of empty. Coverage went 8 rows (5 real) → 13 rows, and the floor sweep to 97.5.

**Why existing tests missed it.** It *is* the test. Nothing checks a test's own coordinates against the
thing it is testing, and a probe that hits nothing is indistinguishable from a probe that hit nothing
*because the doorway is clear* — the two produce the same word.

**General lesson.** ⚠️ **A copied table is a dated table.** If the thing under test owns the data,
read it from the thing under test; if that is impossible, assert the SIZE of what you collected.
⚠️ This is the same family as the vacuity audit that found five suite entries asserting nothing
(cross-level X50): the failure mode is not a wrong answer, it is a confident answer about nothing.

---

## Issue 144 — Eight signs identified by "has a `Label3D` child", on a level that had just stopped using `Label3D`

**Symptom.** Two collectors in `walk_kontur.gd` broke in opposite directions within one day. First they
picked up a prop that is not a sign — the Recovery Archive's room-number plate, a `BoxMesh` ornament
with a `Label3D` reading "217" — fired a 1.2 m ray at it from inside a shelving rack and reported it as
a sign buried in a wall. Then, once the eight real signs became generated printed documents with the
text struck into the artwork, the same collector found **zero** signs and the escort-rule placement
assertion silently stopped testing anything.

**Cause.** "A `Node3D` with a `Label3D` child" is a description of an implementation detail, not of a
sign. Both the false positive and the false negative follow from that one choice.

**Fix.** Identify by the ARTWORK: a root holding a `QuadMesh` whose material's `albedo_texture`
resource path begins `kontur_sign_`. That is the structural fact — it cannot be renamed by a sibling
collision (Issue 17) and it is the thing that makes the prop a sign. The count assertion went from
`>= 7` (a floor a stray prop could satisfy, and did) to `== 8`, the number of `_make_sign()` calls.

**General lesson.** ⚠️ **Collect by the property that MAKES the thing what it is**, not by whatever
node type it happens to be built from today — the node types are exactly what a content pass changes.
⚠️ And a population floor of "at least most of them" cannot tell a missing member from an extra one;
where the count is knowable, assert the count.

---

## Issue 145 — A legibility claim nobody had measured: six of the eight signs were 5–9 screen pixels tall

**Symptom.** KONTUR's eight redacted plates are the level's only in-level help. Rebuilt as printed
notices, they looked right in a texture viewer and right in a close-up screenshot. Measured from the
line a player actually walks, the rule's cap height was **5.1 px on the gate-1 sign and under 9 px on
five more**, at 1080p.

**Cause.** The type hierarchy was a document's, not a wall notice's: the gate title got the big size
and the RULE — the only part with information in it — was set at 58 px on a 1000 px card, then hung on
a 1.0 m plate read from up to 5.85 m away. Nothing anywhere converted those numbers into the one unit
that matters, which is *pixels on the player's screen at the distance they read it from*.

**Fix.** Three changes, all driven by the measurement: the title dropped to a kicker and the rule
became the hero; the line break is now chosen by trying 1, 2 and 3 balanced splits and keeping whichever
yields the LARGEST type that still fits its own leading (a word-count rule left
"APPROVED AGENT: DOMESTIC" on one 24-character line at 13.3 px); and the plate grew to 1.4 × 2.1 m.
Re-measured: worst sign **15.7 px**, best 63.2 px, against a 15 px floor.

**Why existing tests missed it.** `check_art_aspect.gd` asks whether a texture is DISTORTED and
`check_prop_mounting.gd` asks whether it is on a wall; neither asks whether it can be READ, and no
guard in the project did. `check_kontur_signs.gd` finds the ink by thresholding rows of the actual
imported texture — never a constant shared with the generator, which would agree by construction — and
converts through the quad size, the camera's own FOV and the reading distance. Its control stamps the
rule band back at a quarter height and requires the same measurement to report it unreadable.

**General lesson.** ⚠️ **"Legible" is a number, and the number is angular.** Texture resolution, font
size and plate size are all inputs to it and none of them is it. ⚠️ The corollary for wall text
anywhere in this game: a notice read while walking is a couple of large words, and the way to find out
whether yours is one is to measure it rather than to open the PNG.

---

## Issue 146 — Four wheel spokes rotated about the wrong axis, all landing in the same place

**Symptom.** The containment cell's blast-door wheel rendered as a "Ø" — a torus with one bar through
it — instead of a four-spoke handwheel.

**Cause.** Each spoke was a box 0.028 × 0.028 × 0.26 (long axis Z) given `rotation = Vector3(PI/2, 0,
a)` for a in 0°, 90°, 180°, 270°. Godot composes Euler angles **YXZ**, so the Z rotation is applied
first, in the box's own frame, where it spins a square cross-section about its own long axis and does
nothing visible; the X rotation then stands all four up in the same plane. Four spokes, one silhouette.

**Fix.** Two crossed bars whose long axis already lies in the door's plane (0.30 × 0.026 × 0.030),
rotated only about Z.

**General lesson.** ⚠️ **A rotation that "does nothing" usually means it was applied in the wrong
frame, not that the value was wrong.** Build radial arrangements so the varying angle is the LAST
rotation in the compose order, or place the parts by position instead of by rotation.

---

## Issue 147 — A "pale man in a suit" behind glass: the retint was applied, and the material was still the bug

**Symptom.** KONTUR's containment cell shipped 2026-08-18 and the first screenshots of it show the
occupant as a **pale beige smiling man in a jacket and bow tie**, brighter than every other surface in
the Passage — not Object 12. The obvious reading, and the one the analysis started from, was
CLAUDE.md's own standing warning about this exact asset: *"Mixamo's default export embeds a skin
texture… which breaks the dark-material override."* So the hypothesis was that `material_override` was
not reaching every mesh.

**Cause.** It was reaching every mesh. `Void_creature.glb` instantiates **one** `MeshInstance3D`
(`Armature/Skeleton3D/WhiteClown`), it carried the override, and there was no `AnimationPlayer` at all.
The bug was the numbers, which were `creature_object12.gd`'s verbatim and deliberately so — albedo
(0.35, 0.4, 0.32), emission (0.4, 0.05, 0.05) at 0.35. **The same material is not the same picture.**
The Breach meets that creature across a lit facility; KONTUR meets it at 1.5–2 m with a 1.2-energy
flashlight on it, in a room lit at 0.45. Rendered from every reachable heading and measured against
what is directly behind it: occupant **0.21–0.23** mean luminance, background **0.08–0.12**, the
booth's own steel **0.048–0.057** — i.e. **1.8–2.8× brighter than what it stood in front of and
4.1–4.5× brighter than the cell around it**. The warm cast is arithmetic, not a texture: the red
emission adds ~0.14 to R and nothing to G or B, so a grey-green albedo renders as beige.

**Fix.** Three things, and the third is the one that mattered.
1. `SPECIMEN_DIM` (albedo × 0.45) and `SPECIMEN_EMISSION` (energy 0.16). The palette COLOURS are still
   the Breach's verbatim; only the level is this level's.
2. `metallic_specular = 0`. A dielectric's specular lobe is not scaled by albedo, so darkening alone
   leaves the hotspot exactly where it was — measured, at an albedo scale of 0.10 the mean had fallen
   56 % and the peak was still 0.98.
3. **Backlit liners, because darkening alone cannot work.** Sweeping the albedo down, the occupant
   reaches parity with its background at ~0.30 and passes under it at ~0.22 — but the measured contrast
   at those points is **0.006–0.09**: *it becomes invisible before it becomes dark*. `watcher.gd`'s
   premise is "a dark shape OCCLUDING A LIT SURFACE" and the booth had no lit surface in it. The three
   interior faces the player can never reach are now emissive liners. ⚠️ Emission illuminates nothing
   in this project (no GI, no glow), so a liner raises the BACKGROUND without touching the figure —
   which is the entire reason it works.
Result, over 23 reachable headings: occupant **0.10–0.19** against a background of **0.18–0.27**,
occ/bg **0.52–0.77**, contrast **0.23–0.48**, frame mean 0.05–0.10 (it did not become a lantern).

**Why existing tests missed it.** `check_kontur_entities.gd` had 143 assertions about this prop and
every one of them was about what it does NOT do — no `ScaryObject`, no collider on the occupant,
nothing interactable, zero panic, the eye ray stopped by the booth. **Nothing anywhere asked whether
the thing could be seen, or what it looked like.** It now asserts that every renderable carries the
published material, that the albedo, emission and specular are under documented ceilings, and that no
`AnimationPlayer` is running; `tests/screenshot_cell_visibility.gd` carries the photometric half.

**General lesson.** ⚠️ **"Same material as X" is a claim about a picture, and a picture is material ×
lighting.** A palette shared for identity has to be re-measured wherever the lighting differs, and a
1.2-energy torch at 2 m against a 0.45-energy room is a different order of magnitude. ⚠️ And the
second, more useful half: **you cannot make a lit object read as a silhouette by darkening it** past
the point where it matches its background — at that point it has no contrast at all. Raise the
background instead. The Congregation fix (Issue 85) got away with darkening because those figures are
unshaded billboards against an already-lit floor.

---

## Issue 148 — The one look at the level's title creature, staged to face the door it could not be seen through

**Symptom.** From the heading the containment cell is deliberately turned to face — a player walking
up the KONTUR spine from the antechambers — the cell renders as **a flat luminous white panel with a
bright radial falloff and no creature at all.**

**Cause.** Two independent things, and the loud one was the harmless one.
1. **The occupant genuinely could not be seen.** Three faces of the booth are glazed and the fourth,
   `-z`, is a solid steel leaf 1.74 × 2.36 m — and `_spawn_containment_cell()` turns that leaf to look
   back down the spine on purpose, so the door faces the approach. Measured over 23 reachable poses,
   **six rendered ZERO pixels of the occupant**: the whole 165°–210° arc, at 2.0 m and at 3.2 m.
2. **The "luminous white panel" was the flashlight.** The leaf is albedo 0.115 and it is the only
   large *untextured, perfectly flat* surface in a corridor whose walls carry concrete texture, so the
   torch's spot painted an unbroken radial gradient on it. Nothing was emissive and nothing was wrong
   with the material; a flat plane with a spotlight on it simply looks like a light.

**Fix.** An observation port: the leaf became four slabs around a 1.32 × 0.95 m glazed opening, with a
bead frame, two glazing bars, and the wheel, mid-rail, chevron band and placard all moved clear —
every one of them had been sitting inside what is now the opening. The port fixes both halves at once,
because it is also what breaks the flat plane the hotspot needed. All 23 headings now show 7 000–67 000
px of silhouette.

**Why existing tests missed it.** `check_reachable.gd` asks whether a prop can be *reached*, not
whether it can be *seen* past its own housing; `check_wall_overlap.gd` and `check_prop_mounting.gd`
both passed on a working steel door. The cell's own guard proved the eye ray **is** stopped by the
booth — which is true, correct, and precisely the wrong question.

**General lesson.** ⚠️ **A prop built to be looked at needs an assertion that it can be looked at, from
everywhere the player can look at it from.** Both new guards sample *headings*, not one camera pose,
and the photometric one measures the occupant against what is directly behind it over the same pixels
— never an absolute level (Issue 62).
⚠️ Three sampling traps were hit while measuring this, all of them worth knowing:
- **`intersect_point` cannot filter reachable poses.** CSG collides as a concave trimesh, so the query
  returns nothing inside one and every candidate — including the ones buried in the east wall — came
  back "reachable". Bounds arithmetic instead (Issue 40 / 94).
- **A difference mask includes the silhouette's antialiased rim**, where the pixel is a blend of figure
  and background, so a dark figure in front of the torch's hotspot reports a "peak" belonging to the
  wall behind it. Erode by one sample.
- **A difference mask through ALPHA-BLENDED GLASS is not the object.** Hiding the occupant perturbs
  every pane pixel slightly, so the mask picks up the whole pane, including the ceiling fixtures seen
  through it. A "0.90-luminance specular highlight on the creature's chest" was measured three times
  and finally disproved by painting the occupant pure black, switching its emission off and turning
  the flashlight off — the pixel was still there. It was a glare on the **pane** (roughness 0.08, i.e.
  a mirror), now 0.22. The permanent harness builds its mask with the glass HIDDEN and reads the
  levels with it back.

---

## Issue 156 — A guard that failed *because the feature worked*, and the same line was also too weak to catch the feature being deleted

**Symptom.** `tests/check_flood_drowned.gd` — THE DROWNED's guard, in the suite since 2026-08-17 —
failed **2 runs in 10**, always on the same line: *"...and the emptied one stayed silent"*. Nothing in
the working tree touched the Backrooms between a red run and a green one; re-running it usually made
it go away. Cross-level **X60**.

**Cause.** The assertion marked the first object's knock count at the **haul** (stage 3, one press,
lid open) and compared it after the **take** (stage 5, second press, fragment removed) — but the
object spends the whole of stage 4 in the state *opened and not yet emptied*, and
`sunken_item.gd:_process()` deliberately keeps such an object knocking:

```gdscript
# The gate used to be `is_searched`. That was correct while opening WAS taking; the
# moment the two split, a player who hauled a lid and walked away without the fragment
# would have silenced the one object they still needed.
if is_taken or not _zone_active or _knock == null:
	return
```

That gate is the only thing keeping the Flood's mandatory six-object search winnable. So the object's
own 5–11 s timer firing anywhere inside the ~1.3 s `LID_WATCH` window incremented the counter and
reddened the assertion — **the guard was able to fail precisely when the feature was correct**, and
the failure rate was just the probability of a legal knock landing in that window.

**Fix.** Move the mark to the moment the rule actually starts applying: re-read it immediately after
`is_taken` goes true, and rename it `_knocks_at_take` so the variable's name states which of the two
state changes it brackets. The old name, `_knocks_at_search`, described the wrong one and is what
made the comparison look right.

**…and fixing it exposed that the same line was vacuous in the other direction.** It watched ONE
object for `ANSWER_WATCH` = 2.0 s. Measured: a build with the `is_taken` gate **deleted outright**
still passed it, because the object's pending 5–11 s timer had not expired inside that window. The
rule is now *also* asserted run-wide with no mark and no window at all — `_sample_knocks()` treats a
rising edge on an already-emptied object as a violation, wherever and whenever it happens — and that
version reddened on **4 runs out of 4** with the gate deleted, against 27.6 object-seconds of watched
silence in a healthy run (the window size is asserted too, or "0 violations" would be trivially true
of a run that emptied nothing).

**Why existing tests missed it.** They *were* the test. The failure was intermittent and the guard
was three weeks old, which is exactly the window in which an intermittent red gets attributed to
machine load and re-run (X42, X46) rather than read. Nothing else in the project asserts the
knock gate, so the vacuous half had no second opinion either.

**General lesson.** ⚠️ **A mark and its assertion must bracket the state change they are about, and
nothing else.** If the object under test legitimately changes behaviour twice — opened, then emptied —
one mark cannot serve both, and the one that reads naturally in prose ("since we searched it") is the
wrong one. ⚠️ And the second half generalises further: **a flaky check and a vacuous check are often
the same check.** Both symptoms come from a window that does not match the rule — too wide and legal
behaviour leaks in, too narrow and the regression does not. Prefer a rule stated over the whole run
with its observation time asserted, over a rule stated inside a hand-timed window.
