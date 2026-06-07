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
