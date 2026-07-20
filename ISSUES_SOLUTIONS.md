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
