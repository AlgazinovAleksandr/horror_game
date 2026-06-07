# COMMENTS.md — Observations, Design Decisions, Technical Notes

Developer retrospective. Useful for a technical report or just remembering why things are the way they are.

---

## Horror Design Philosophy

### Atmosphere over AI
The most deliberate early decision: no active enemy AI. The creature exists in the game but never moves on its own — it only "rushes" the camera as a scripted screamer trigger. This was partly pragmatic (no time to build a nav-mesh chase system) but it turned out to be an interesting constraint. Static horror — something that is *there* but doesn't acknowledge you — is often more unsettling than something that chases you. You can outrun a monster; you can't outrun the feeling that it already knows where you are.

The Level 3 design leans into this: multiple static creature instances visible in every room simultaneously. You're never alone, but nothing moves.

### The "psychological experiment" frame as a meta-trick
Framing the game as a clinical trial ("Subject 47") does two things. First, it gives the player a plausible reason to keep walking into obviously dangerous rooms — they signed up for this, they're being tested. Second, it sets up the twist: the final door leads back to the intro room with "Beginning trial 2." The horror isn't the creature; it's the loop. The experiment doesn't end.

This kind of loop ending is extremely cheap to implement (just load `intro_room.tscn`) but lands differently than a monster kill screen. The player's choices throughout the game are recontextualised as data collection. The game wasn't trying to scare you — it was observing whether it could.

### Fail state design: screamer + full restart, no checkpoint
A conscious choice not to use checkpoints. The cost of failure is high on purpose — you replay the whole level. This creates genuine caution when reading notes or staring at objects, especially in Level 3 where the trap/safe distinction is ambiguous. If there were checkpoints, players would scan everything recklessly.

The screamer itself is a two-phase shock: black flash first (cuts all visual context), then the face. The flash is actually the more disorienting part — it triggers an involuntary flinch before the image even appears.

### Trap notes: the design of a readable warning signal
Level 2 trap notes are supposed to be identifiable by a careful player — desperate tone, fragmented writing, slightly different texture. But they can't be *obviously* different or there's no tension. The implementation uses a red tint (`Color(0.9, 0.55, 0.55)`) in `note.gd` — subtle enough that you might not notice until you're already reading. The trap isn't the note itself; it's reading it fully. Stopping halfway through doesn't trigger the fail. This rewards attentiveness.

---

## Level Architecture Decisions

### Three-level aesthetic progression: sterile → domestic → void
The level sequence tracks a psychological descent. The Lab is institutional and ordered (fluorescent lights, linoleum). The House is personal and decayed (wallpaper, wooden floors, a bedroom). The Void has no coherent geometry at all — corridors loop, tiles float. Each step removes one more layer of the familiar. By the time you reach Level 3, spatial logic has broken down, which is meant to mirror what the experiment is supposedly doing to the subject.

The texture work reflects this: Lab textures are clinical pale grey-green; House textures are warm but deteriorating; the Void's walls are deep black with glowing purple cracks. Each level has a different vignette tint applied at scene load (grey-green, sepia, blue-purple) — a cheap but effective way to make the colour grade feel physically present rather than just a post-process overlay.

### The Intro Room as a compression chamber
The intro room is tiny and has nothing to interact with except one note and one door. This was deliberate: before the player has any mechanics explained, they need to feel *small* and watched. The note text ends with "We are watching." The room design enforces this — low ceiling, single candle, no exits except the door you're supposed to take. The lack of anything to do is itself atmospheric.

### Level 3's looping corridors
The Void uses repeated geometry to create the impression that corridors loop back on themselves. This is purely visual — no actual portal/teleportation magic. But because the CSGBox3D rooms look similar, players lose their mental map quickly. This maps onto a known psychological response: spatial disorientation as anxiety induction, used in real-world sensory deprivation research (which fits the Subject 47 framing).

---

## Technical Architecture Decisions

### Autoloads for game-global systems
Three nodes are registered as Godot autoloads: `GameState`, `Screamer`, and `NoteUI`. This means they exist independently of any scene — they persist across level loads. The alternative (adding them to each scene as children) would require either complex inter-scene references or a lot of duplicated setup code.

The tradeoff: autoloads are global singletons, which makes them easy to overuse as a dumping ground for state. The rule here was that only systems that *need* to survive scene transitions go into autoloads. Level-specific logic stays in level scripts.

### `process_mode = PROCESS_MODE_ALWAYS` on the Screamer
When the screamer triggers, `get_tree().paused = true` halts all nodes whose `process_mode` is `INHERIT` or `PAUSABLE`. The screamer node itself was inheriting this, which meant the screamer animation froze immediately after triggering — the game paused before the screen could flash. Fix: explicitly set `process_mode = PROCESS_MODE_ALWAYS` on the Screamer autoload. This was not obvious because the pause happens inside the trigger sequence, and the visual result (frozen black screen) looked like a different class of bug.

### NoteUI built entirely in GDScript (no .tscn)
The note overlay — full-screen dimming backdrop, centred panel, scrollable text — is constructed entirely in `note_ui.gd` at runtime with no corresponding scene file. This was chosen because the NoteUI is an autoload (scene-tree independent) and attaching an autoload to a .tscn requires extra project config that can desync. Generating the node tree in `_ready()` keeps everything in one file and avoids editor-only state getting out of sync with runtime state.

### Raycasting for interaction, gaze timer on top
Player interaction works via a short raycast from the camera each physics frame. This is standard Godot practice. What's less standard is the gaze timer layered on top: if the raycast hits a trigger object for 3 consecutive seconds without the player looking away, the screamer fires automatically — no button press needed. This was added to close an exploit (players could stand near a trigger object indefinitely by never pressing E). The gaze timer also adds a mechanic: panic causes players to look around erratically, which resets the timer, but the *instinct* to look at something dangerous is exactly what the game is testing.

### CSGBox3D for rapid level geometry
All room geometry uses Godot's Constructive Solid Geometry primitives (CSGBox3D). This is not production-quality architecture — in a shipping game you'd use MeshInstance3D with proper UV-mapped models. CSG is slower to render and doesn't support lightmapping. But for rapid prototyping it's unbeatable: you can block out an entire level in minutes directly in the Godot editor without touching Blender.

The texture-tiling issue this creates (CSGBox3D UVs don't tile the way a properly UV-unwrapped mesh would) was partially addressed by setting `uv1_scale = Vector3(2,2,2)` on materials at runtime.

### Signals over direct node references
Level scripts never call methods on child nodes directly by path — they emit signals or use exported variables. This matters because Godot scene trees are fragile: rename a node or restructure the hierarchy and `$ParentNode/ChildNode/GrandchildNode` calls silently fail at runtime. Signals let the scene structure change without breaking the script logic.

---

## Interesting Bugs and What They Taught Us

### The ray never hitting flat notes (Issue 2)
Notes were initially placed lying flat on surfaces (like paper on a table). The player camera sits at y = 1.65m and the raycast fires horizontally. A horizontal ray at camera height never intersects a flat object at y = 0.8m — the geometry is below the ray's plane entirely.

The lesson isn't that the code was wrong — it was exactly correct. The lesson is that 3D spatial reasoning requires you to mentally simulate the actual ray path, not just think "the player is near the note." The exit door worked because it's 2.2m tall and the ray clips it at mid-height. Notes had to be rotated upright and given a large collision box with its tall dimension mapped to world-Y.

### The E key opening and closing in the same frame (Issue 3)
Godot 4 dispatches `_unhandled_input` to all nodes that haven't explicitly consumed the event. For a single E keypress: the Player node saw it first and called `show_note()` on NoteUI (`is_open` → `true`). Then the NoteUI node saw the *same event* and immediately called `close_note()` because `is_open` was now `true`. The note opened and closed within one frame.

Fix: two layers. The Player marks the event as handled with `set_input_as_handled()` after triggering interaction. NoteUI also blocks close during the frame it opens (`_block_close = true`, reset via `set_deferred` on the next frame). Either fix alone would have been sufficient, but both together is more robust.

### PRESET_CENTER doesn't mean "centred on screen" (Issue 4)
`PRESET_CENTER` in Godot 4 anchors the **top-left corner** of the control to the screen centre — not the control's centre. So a 680×480 panel "centred" this way renders with its top-left at the middle of the screen, entirely in the bottom-right quadrant. The fix was to wrap it in a `CenterContainer` with `PRESET_FULL_RECT` anchors — the container's layout engine handles true centering. This is a known Godot footgun and worth remembering every time a UI panel seems to have vanished.

### The Gemini API returning JPEG labeled as PNG (Issue 1)
The nano-banana-pro script generates texture images via the Gemini API and saves them as `.png` files. Godot's importer checks the actual file header bytes (not the extension) and silently marks the import as `valid=false` when the bytes indicate JPEG. The symptom — textures invisible in-game, no error message — was hard to diagnose because Godot doesn't log "this PNG is actually a JPEG." The `.godot/imported/` directory only contained `.md5` files, no `.ctex`, which was the real tell.

Fix: `sips -s format png` (macOS built-in) converts in-place. Now a mandatory step after any nano-banana-pro generation run.

---

## AI-Assisted Asset Pipeline

### Using an LLM as a game developer collaborator
Most of the game code, scene setup, and bug diagnosis was done interactively with Claude (claude-sonnet-4-6). This workflow is genuinely different from using an IDE autocomplete. The agent can hold the whole game design in context, notice inconsistencies ("your gaze timer resets on frame, but your `_physics_process` fires at 60fps — you'll need a running float, not an int counter"), and fix bugs that span multiple files in a single pass.

The main failure mode: the agent can't *see* the Godot editor. Screenshots are essential when a visual bug is involved — describing "the UI is in the wrong place" takes many iterations without visual confirmation, while a single screenshot resolves it immediately. This matches the COMMENTS.md note already in the file.

### nano-banana-pro and the texture generation workflow
Generating game textures with an AI image model (Gemini via nano-banana-pro) is fast but requires a conversion step on macOS due to the JPEG-as-PNG issue above. The textures themselves are plausible — the Lab's pale grey-green institutional tile, the House's floral wallpaper — but they're flat (no normal map, no roughness/metallic data). For a PBR workflow you'd want a full texture set from PolyHaven or AmbientCG. For a horror prototype where most surfaces are dimly lit, albedo-only textures are acceptable.

The current budget is ~20 images. Used so far: wall_lab, floor_lab, wall_house, floor_house, screamer — 5 images. 15 remaining for the 12 `to_be_added` textures in TEXTURES.md (with some overlap since ceiling_lab and ceiling_house could share generation prompts with their wall counterparts).

---

## What Worked Unexpectedly Well

- **Vignette shader per level:** A single quad in the CanvasLayer with a radial darkening shader, tinted differently per level, changes the entire emotional register of a scene for nearly zero cost. The blue-purple void vignette at strength 2.0 makes the centre of the screen feel like a spotlight — everything peripheral is consumed by darkness.

- **The combination lock built in GDScript:** The Level 2 combination lock (three digit spinners) was built entirely in code with no scene file. Players interact with it the same way they interact with notes — press E, UI appears, arrow keys to change digits. The satisfaction of clicking the correct code after collecting all three note fragments works as a natural pacing beat.

- **Level 3's ambient audio design (by implication):** The void ambient audio combined with a near-black environment creates a strong dissociation from the earlier levels. No explicit gameplay tutorial for Level 3 — players figure out the "read the twist note" win condition by elimination, which feels more like discovery than instruction.

+ What people say on YouTube - like they vibecoded a good game from scratch in one hour - this does not make a lot of sense and does not seem real. They are either very experienced and know the basic mechanics, how to make 3d models, where to find textures, how to setup Godot, etc, or probably they are taking a well-known template like Slender or Minecraft that was studied long long time ago

---

## Phase 2: Bug Fixes and Polish

### Level 2 geometry: how a missing doorway breaks a whole level

After the first full playtest, Level 2 was completely unbeatable. The reason wasn't obscure — one wall (`LivWallR`) had no opening cut into it. But the geometry bug was paired with a floor gap, making the fix non-obvious: splitting the wall correctly placed a doorway, but players still fell into the void because the floor plans of the living room and bedroom didn't overlap at the boundary.

This is a category of error that's hard to catch without playtest or top-down spatial visualisation. The level *looked* complete from above in the editor — the rooms existed, the notes were placed, the combination lock was wired up. The unplayable state only revealed itself when a human tried to walk through it.

Lesson: blockout testing (walk every path from spawn to exit before placing any objects) should be step one of level construction, not something done after notes and enemies are placed.

### Coroutines and node lifetimes: a subtle GDScript footgun

The "Keycard collected" label staying on screen permanently (Issue 6) is a good example of how GDScript coroutines interact with node lifetimes in non-obvious ways. The label was created and attached to the scene tree root — independent of the keycard node. But the timer driving its removal was an `await` inside the keycard's own coroutine stack. When the keycard node was freed, the coroutine was cancelled. The label survived; its cleanup didn't.

The fix (`.timeout.connect(canvas.queue_free)`) decouples the cleanup trigger from the node's lifetime entirely. Signal connections from a dead source are harmless; the callback fires when the timer expires regardless. This pattern — connect a one-shot callback to a timer signal rather than awaiting it inside a potentially short-lived node — is worth using any time cleanup logic runs in a node that might be destroyed before the timer fires.

### Back door navigation: preserving state across backward traversal

Adding back doors (Levels 1, 2, 3 each get a door that loads the previous scene) required a deliberate design choice about state: should going back reset level flags?

The answer was no. `go_back()` in `GameState` does not call `reset_level_state()`. The reason: if you've already collected the keycard and walk back to the intro room, the keycard should still be collected when you return to Level 1. The keycard object handles this gracefully via `_ready()` — it checks `GameState.has_keycard` and calls `queue_free()` immediately if already collected, so the scene reloads cleanly without the item re-appearing.

This "re-entry grace" pattern (objects self-removing if their collected state is already set in GameState) is worth generalising if the game grows: any pickup that shouldn't respawn on scene reload should check its flag in `_ready()`.

### Note tables: spawn dynamically vs. place manually

Notes previously floated in mid-air — a visual incongruity that breaks immersion. The fix spawns a CSGBox3D table under each note at scene load. The `_spawn_note_tables()` function iterates all children and checks for the `note_text` property to identify notes — a form of duck-typing that avoids a hard node type check.

The tradeoff: dynamically spawned nodes don't appear in the Godot editor scene tree. Debugging a spawned table requires adding a breakpoint or print in `_ready()`. For a prototype this is acceptable — the tables are uniform and predictable. In a production context, you'd either make them explicit scene children or add a debug visualisation tool.

### Intro room: small details matter more in constrained spaces

The intro room is tiny. The table was 0.5m off-centre. The ambient light was bright enough that the candle felt unnecessary — the room was already legible without it. Two solid-colour quad cobwebs in the corners looked like flat black squares rather than cobwebs. Wall heights poked 0.15m into the ceiling, creating a shadow seam from the two overlapping surfaces.

None of these bugs would be noticed in a large open environment. In a 5.6m × 5.6m room with one object (a table) and one interaction (one note), they were impossible to miss. Small spaces require higher fidelity — there's nowhere for imprecision to hide.
