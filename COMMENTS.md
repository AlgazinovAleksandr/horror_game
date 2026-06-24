# COMMENTS.md — Observations, Design Decisions, Technical Notes

Developer retrospective. Useful for a technical report or just remembering why things are the way they are.

---

## Horror Design Philosophy

### Atmosphere over AI (and the one exception)
The most deliberate early decision: no active enemy AI for most of the game. The creatures exist but, in Levels 1–3, never move on their own — horror comes from atmosphere, lighting, sound, and scripted screamer triggers, not a nav-mesh chase. This was partly pragmatic (no time to build a full chase system) but it turned out to be an interesting constraint. Static horror — something that is *there* but doesn't acknowledge you — is often more unsettling than something that chases you. You can outrun a monster; you can't outrun the feeling that it already knows where you are.

The **one exception** (added later) is The Void's stalking creatures (`creature_stalker.gd`): Weeping-Angel logic — they freeze while in your view and line-of-sight, and advance only the moment you look away. It's still not a real-time chase AI (no pathfinding, no pursuit when unseen-but-out-of-grace handling beyond a straight-line step), but it's the first creature that *moves toward the player* under its own logic. Crucially it preserves the original philosophy: the threat is tied to the player's own gaze. Looking at the danger is what stops it; the instinct to watch it is exactly what the experiment tests. See Phase 5 below.

The earlier prototype leaned hard on the static version: multiple motionless creature instances visible at once. You're never alone, but nothing moves — until the Void.

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

### Aesthetic progression: sterile → domestic → hotel → void
The level sequence tracks a psychological descent. The Lab is institutional and ordered (fluorescent lights, linoleum). The House is personal and decayed (wallpaper, wooden floors, a bedroom). The Corridor (added later as Level 3) is a haunted-hotel hallway — still architecturally coherent but stretched into an endurance gauntlet. The Void has no coherent geometry at all — corridors loop, tiles float. Each step removes one more layer of the familiar. By the time you reach the Void (Level 4), spatial logic has broken down entirely, which is meant to mirror what the experiment is supposedly doing to the subject.

The texture work reflects this: Lab textures are clinical pale grey-green; House textures are warm but deteriorating; the Corridor is Victorian damask over dark wainscot; the Void's walls are deep black with glowing purple cracks. Each level has a different vignette tint applied at scene load (grey-green, sepia, blue-purple) — a cheap but effective way to make the colour grade feel physically present rather than just a post-process overlay.

### The Intro Room as a compression chamber
The intro room is tiny and has nothing to interact with except one note and one door. This was deliberate: before the player has any mechanics explained, they need to feel *small* and watched. The note text ends with "We are watching." The room design enforces this — low ceiling, single candle, no exits except the door you're supposed to take. The lack of anything to do is itself atmospheric.

### The Void's looping corridors
The Void (Level 4) uses repeated geometry to create the impression that corridors loop back on themselves. This is purely visual — no actual portal/teleportation magic. But because the CSGBox3D rooms look similar, players lose their mental map quickly. This maps onto a known psychological response: spatial disorientation as anxiety induction, used in real-world sensory deprivation research (which fits the Subject 47 framing).

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

---

## Phase 3: Double Screamer, Asset Organisation, Level 3 Tables

### The double-screamer race condition

`Screamer.trigger()` is a coroutine — it uses `await` to sequence the flash, face display, and audio burst before reloading the scene. If the player presses E a second time before the first `await` resolves (or if input repeats), a second coroutine starts on the same node. Two screamer sequences run concurrently, and both eventually call `GameState.restart_current_level()`. The scene reloads twice in quick succession, which can cause the wrong scene to load or crash the scene tree mid-transition.

The fix is a single boolean flag `_is_triggering` at the top of the function. Both `trigger()` and `trigger_to_menu()` return immediately if it's already `true`. The flag resets to `false` just before the scene change call so a fresh trigger would be valid after the reload.

The broader pattern: any `await`-based sequence in an autoload that must not re-enter needs a guard bool at the function level, not at the call site. Guarding at the call site (e.g. disabling the interact key in `player.gd`) creates coupling and is easy to miss — callers outside `player.gd` would also need the guard. Owning the re-entry protection inside the function itself is robust regardless of how many call sites exist.

### Screamer subfolder as a drop-in asset system

Originally the screamer textures were referenced by hardcoded filenames: `screamer.png`, then `screamer_2.png` as a second variant. Every new variant required editing `screamer.gd` to add it to the probe list. Moving to a `DirAccess` scan of `res://assets/textures/screamers/` at startup changes the contract: any `.png` dropped in is automatically picked up with no code changes.

The trade-off is that discovery order is filesystem-dependent and non-deterministic. For random selection of horror faces this is completely fine — the whole point is unpredictability. If order of play ever mattered (e.g., a specific screamer reserved for the ending) the scan approach would need to be supplemented with a naming convention or manifest file.

This is a small example of a broader principle: prefer convention over configuration for asset pipelines. Making the folder itself the registry removes an entire class of "I added the file but forgot to register it" bugs.

### Level 3 note tables: parity fix

Levels 1 and 2 both call `_spawn_note_tables()` in `_ready()`, which dynamically spawns a CSGBox3D pedestal under each note child. Level 3 never got this — an oversight from when Level 3 was built after the function already existed in the other level scripts.

The practical effect was noticeable in the Void's environment specifically. The dark, nearly featureless corridors meant floating note cards had no visual context — nothing nearby for the eye to anchor them to. The tables give players a target to orient toward when scanning a room, and make the notes look like intentionally placed objects rather than floating UI artefacts. In a brighter level you might not notice; in the Void, the absence was jarring once seen.

+ Use references not only as images, but as other horror-games also

+ Use 2d references to anchor 3d objects in a scene

---

## Phase 4: The Difficulty Overhaul (Session 8)

### Auditing the design against the code — and finding fiction

The session started as a brainstorm ("the game is too easy, the corridor can't be failed") and turned into an audit. Three things the design docs *described* turned out not to exist in code: trap notes were supposed to fail you for *reading them fully* (the code screamered instantly on E, before any text rendered — the carefully written trap-note prose had never been seen by a player); Level 2 was supposed to have a creature glimpsed through a window (never built — and there was no window); and the corridor note's "Walk. Do not run." referred to a run button that didn't exist. Design docs drift into fiction quietly. The fix for all three was the same: make the documentation true.

### Read-to-die: making the fail state a choice, not a gotcha

The trap-note rework (panic +12/s while the note is open, text bleeding red, close early to survive) is the session's best mechanic-per-line-of-code ratio. The old instant-fail punished a decision the player had already committed to before any information arrived. Read-to-die punishes *continuing* — every line read is a fresh decision to stay. It also finally makes the trap-note prose load-bearing: the desperate, fragmented writing IS the warning, and greed is the failure. Implementation rides entirely on existing systems: NoteUI is `PROCESS_MODE_ALWAYS`, so it can feed `player.add_panic()` during the tree pause it created itself.

### The panic budget: why the corridor couldn't kill you

Doing the arithmetic exposed the problem precisely: PANIC_MAX 50, decay 15/s, and scripted spikes of +10/+20 spaced 40–60 m apart — every event fully drained before the next. Darkness creep (+3/s) was a fifth of decay, and the flashlight was free. The fixes attack the *decay*, not the spikes: the Zone C dread zone (decay 15→6/s plus a constant +1.5/s floor) means the last 90 m accumulates instead of resetting; sprint (+6/s, suppresses decay) converts the player's flight instinct into the failure mechanism; the battery (240 s/scene, on by default) makes light a spent resource exactly when the dark zones get long. Lesson: in any pressure system, the recovery rate is the real difficulty knob — spike sizes are theatre.

### One fail philosophy, stated and kept

The brainstorm settled it explicitly: panic is the ambient pressure everywhere; instant-fail is reserved for trigger objects only. Everything new feeds the bar — wrong lock codes (+10 + buzz, so brute-forcing 1000 combinations is now a death sentence rather than a free strategy), the keycard blackout, the House's scripted events. The combination lock is a nice microcosm: the original design assumed players would politely find three notes; the penalty makes the lock itself enforce that intent.

### The pause-ownership bug class

Making trap notes and the lock raise panic surfaced a latent invariant violation: these UIs pause the tree, but a screamer can now fire *during* the pause, unpause, and reload the scene — leaving an autoload overlay open over the new level. The fix (each pause-owning UI watches for "open but tree unpaused" and silently drops) is documented as Issue 9. The general rule joins Issue 7's: any system that pauses the tree must also handle the tree being unpaused out from under it.

### The corrupted ending: same room, hostile light

The twist room (dead candle, blood-red throb, planked-over door, one harsh spotlight on the note) cost ~60 lines and answers a real playtest confusion — players thought the loop back to the intro was a bug. The design insight: the room doesn't need new geometry to read as "wrong", it needs *hostile lighting*. Removing the door matters most — with no way forward, the spotlit note is the only affordance left, so the player walks to the twist instead of hunting for an exit that doesn't exist.

---

## Phase 5: The Scare Bug-Fix Round

### A plain `Node` silently severs the transform chain — and zeroes gaze panic
The biggest bug this round was invisible because it failed *quietly*. Gaze panic is detected by `player.gd:_find_scary_object()` walking **up** the parent chain from the ray-hit collider to a `ScaryObject` ancestor. Several props (the House paintings/mirror, the corridor paintings/clock/side-mirrors) had been built with the `ScaryObject` nested *below* the `StaticBody3D` — so the upward walk never found it and those props registered **zero** panic. They looked cursed; they did nothing. Fixed by inverting the nesting everywhere (`ScaryObject → StaticBody3D → collider`).

Inverting it exposed a second, deeper Godot fact. `ScaryObject extends Node` (not `Node3D` — it has no transform). A plain `Node` placed *between* two `Node3D`s **breaks the spatial chain**: Godot's `get_parent_node_3d()` returns null for a non-spatial parent, so the child body's *local* transform becomes its *global* transform. Verified empirically with a throwaway test (the body stayed at the origin no matter where its `Node3D` ancestor sat). Consequence: the world transform must live on the `StaticBody3D` itself, and for a *moving* gaze prop (the Void creatures) you move the inner body, not the outer node. This one fact explained both the dead cursed props and why the Void creatures weren't reacting.

### Survivable scares need their own primitive
Three new scares (House forest, corridor Manager, corridor turn mirrors) should shock without killing. Reusing `Screamer.trigger()` would have restarted the level; instead they call `Screamer.flash_scare(image, audio, hold)` — a fullscreen flash + sound with **no tree pause and no reload**, leaving the caller to add a survivable panic spike. Separating "shock" from "fail" turned the screamer into two primitives: the fatal `trigger()` and the survivable `flash_scare()`. The House window dropping its old instant-fail capsule glimpse in favour of only the forest flash is the clearest win — the moment is now a jolt you walk away from, not a coin-flip death.

### Distance triggers beat wall-clock triggers in a level you can sprint
The corridor Manager originally fired on a wall-time delay, but the corridor can be walked in ~60 s or sprinted in ~50 s, so a high roll lost the race to the exit and the scare often never happened. Rebuilding it on the existing `_spawn_event(distance, callback)` (an `Area3D` trigger placed at a path distance) makes it fire at a random *position* (80–180 m) regardless of speed — guaranteed mid-hall. Lesson: in a space the player traverses at variable speed, trigger on **where they are**, not **how long it's been**.

### Teaching "don't look" without an instakill
The Void creatures were invisible (bare untextured capsules, no material) *and* one stood 2 m from spawn with no grace period — so the first glance awakened it and it lunged within a second, reading as a random screamer with no cause. The fix is a teaching beat: build a visibly tall, dark, red-eyed silhouette; place one creature dead ahead at a safe distance facing the player; add a 5 s `START_GRACE` before anything can hunt. Now the player *sees* the figure, feels the gaze panic climb while staring, looks away, watches it step closer — and learns the rule before it can cost them. A mechanic the player can't see isn't a mechanic; it's a bug.

---

## Phase 6: Bigger Lab/House + the Apparition (Session 10)

### Procedural room-graphs retire hand-built CSG
The Lab and House felt cramped (~30 s end to end) and, worse, their geometry was the hand-authored CSG that had caused the Issue-5 "unbeatable level" / void-fall bug. Rather than hand-place more rooms, both levels were rebuilt around a reusable `RoomBuilder` (`build(rooms, doorways)`): a data table of rooms (`{name, pos, size}`) and connecting doorways emits floor/ceiling/walls, and — the key invariant — **auto-bridges the floor under every doorway**, so the floor-gap class of bug *cannot* recur by construction. The Lab went from a corridor + two rooms to a 10-room wing; the House to 8 ground-floor rooms plus a lowered cellar. The `.tscn` files shrank to just `Player`/`Environment`/audio/`HUDCanvas`; a `_clear_old_scene()` with a `PRESERVE` whitelist frees the old hand-built nodes at `_ready()`. This is the same "build it in `_ready()` from a data table" pattern the corridor already proved — moving geometry out of the scene file and into reviewable, testable code.

### A doorway opens *every* wall on its plane
The sharpest gotcha in `RoomBuilder`: a doorway cut is applied to every wall lying on its plane, so two rooms only connect if they **abut** (share a wall plane). My first throwaway test layout left a gap between two rooms and the doorway "opened" into a void instead of joining them. The rule — *connected rooms must share a wall plane* — is now documented at the builder and is the single thing to check when a new room won't connect. It also means the room table reads almost like a floor plan: positions and sizes have to tessellate, which is a feature, not a constraint.

### The apparition: a fail tied to an *enforceable* signal
The user wanted a monster that appears at random and tests the *correct response*. The trap was obvious from the corridor work: three different fatal "correct responses" at random moments, with no per-encounter telegraph, is an unfair-death generator — you die to a coin-flip. The flagship `RULE_HOLD` apparition resolves this by tying survival to a signal the player controls and the game can read fairly: `is_sprinting()`. It fades in ahead where you're already looking, adds steady dread, and **survival is simply "don't sprint for 4 s."** Sprint and it rushes → screamer. Crucially the fail condition is never "did you turn your head," which is impossible to telegraph and breaks by accident — it's the one input the player is unambiguously choosing. The other two response types reuse the proven `creature_stalker` (stare-to-freeze) and `creature_smiler` (don't-light/don't-run) rather than inventing two more fatal mechanics. And as with the Void's `CreatureA`, each rule's **first encounter is `teach=true`** (survivable flash, not fatal) so the tell is learned before it can kill — the Lab hosts the taught one, the House reuses a non-teach copy in the cellar.

### The invisible wall at spawn: a transform-chain relapse
A user playtest reported being unable to walk past an invisible object right at both level entrances. The cause was the *same* `ScaryObject` transform-chain fact from Phase 5, surfacing in a new place: `LivingMirror` builds `ScaryObject → StaticBody3D → collider`, and because `ScaryObject` is a plain `Node` with no transform, the body's *local* transform became its *global* transform — so the mirror's collider sat at the **world origin** (a 1.2×1.8 box right where the player spawns), an invisible wall blocking the doorway. The fix is one line — `body.global_transform = global_transform` after parenting — the identical seed the Void creatures already needed. Lesson re-learned: any time a positioned prop hangs a collider under a non-`Node3D`, that collider needs its world transform set explicitly, or it teleports to the origin. A ray-probe diagnostic (`diagnose_entrance.gd`) that prints what each forward ray hits made it a five-minute find instead of a hunt.

### The cellar ramp and the sign of a rotation
Two House bugs shared a root: a box's local axes don't tilt the way intuition says. The cellar descent uses a ramp, side walls and a shaft ceiling all rotated about X — and built with `rotation.x = +angle` they came out *inverted*: the ramp rose toward the cellar instead of descending, and the shaft ceiling dropped to knee height at the entrance, sealing the descent. `rotation.x = -angle` (verified by re-probing the ramp surface from kitchen floor `y=0` down to cellar floor `y=−1.5` with ~2 m headroom) fixed all three. Likewise the living-room window had gone missing because its quads were built without `rotation.y = PI`, so they faced *into* the wall and were back-face culled, then buried by too small an inset; `rotation.y = PI` + a 0.25 inset + `cull_mode = CULL_DISABLED` + a wooden frame brought it back. Both are the same lesson: when geometry is missing or inverted, suspect the *sign/orientation* of a rotation before adding more nodes.

### Two more "it built fine but doesn't play" misses
The headless smoke test passes (no parse/script errors) on geometry that is still unplayable, so two bugs only a human (or an interaction probe) catches slipped through to playtest. First: the rebuilt exit doors were created with `advances_level = false`, and `door.gd` only acts when `goes_back` **or** `advances_level` is true — so collecting the keycard and pressing E on the lit door did *nothing*. Second: the morgue trigger objects (surgical tray, face-monitor) were placed at y-offsets that buried them *inside* the cart they sit on, so the "objects you mustn't look at" were invisible. Both are reminders that a clean compile says nothing about reachability or whether a prop is where you can see it — the Issue-5 lesson, restated: blockout-walk (or ray-probe) the actual play path, every objective, before trusting a level.