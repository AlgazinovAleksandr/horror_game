# Level X — The Backrooms

A liminal, non-Euclidean nightmare labyrinth representing the absolute breakdown of Subject 47's psychological baseline. 

## Entry Condition: The Noclip

The player never actually reaches the safety of Room 217 in **Level 3 — The Corridor**. 
1. As the player enters the final stretch (~10 meters from the red door of Room 217), the environment plunges into pitch-black darkness.
2. The flashlight forcefully toggles off. Pressing **F** plays a dead battery clicking sound—it cannot be turned back on.
3. As the player blindly approaches the red door and presses **E** to interact, the floor collision transforms into a trigger zone (`Area3D`). 
4. The player falls vertically into a seamless black void for 2 seconds before instantly waking up face-down on a damp, yellow carpet.

---

## Visuals & Architecture

### The Player's Perspective
An endless, repeating maze of sterile, mono-yellow wallpaper, stained ceiling tiles, and damp, industrial carpeting. The lighting is an aggressive, uniform, overhead yellow glow. There are no windows, no natural shadows, and an oppressive, low-frequency fluorescent hum dominates the entire soundscape, masking the player's panic heartbeat.

### The Developer's Perspective (Godot Implementation)
To achieve an "infinite" feel without performance degradation on the M3 Mac, the level relies on a **seamless looping zone** rather than a massive, handcrafted layout:
* **The Loop Module:** A compact, interconnected set of modular corridors containing 4 critical intersections.
* **Seamless Portals:** Crossing specific thresholds triggers an invisible `Area3D` teleportation script that offsets the player's global transform back to the start of the module, creating the perfect illusion of an infinite, looping maze.
* **Dynamic Dark Zones:** Random segments of the modular grid dynamically disable their overhead `OmniLight3D` nodes when the player is two turns away, forcing the player to manage their remaining flashlight battery or confront the dark.

---

## Win & Fail Conditions

### Win Condition: Breaking the Seam
To escape, the player must locate a navigation clue and execute a precise tracking sequence to break the loop geometry.

1. **Find the Clue:** Locate a non-trap note on the floor stating: *"The hum lies. Follow the arrows pointing down. Three down turns will tear the seam."*
2. **Navigate the Intersections:** Subtle, low-resolution arrow decals are placed on columns at intersections. The player must choose the path with the downward-pointing arrow 3 times consecutively.
   * *Correct Turn:* Increments an internal loop counter.
   * *Incorrect Turn:* Plays a loud fluorescent pop SFX, inflicts $+15$ panic instantly, resets the counter, and teleports the player back to the maze origin.
3. **The Exit Flaw:** Upon the 3rd correct turn, the corridor transforms. It opens into a small, dead-end utility room where the back wall features a heavy screen-space vertex tearing/jitter shader. Walking directly into this glitchy mesh triggers `get_tree().change_scene_to_file()` to transition to the next level.

### Fail Conditions
* **The Standing Panic:** Standing completely still for more than 4 seconds causes the panic bar to rise automatically ($+3/\text{s}$). The level forces constant, agonizing movement.
* **The Smiler (Darkness Entity):** In the pitch-black zones, a glowing, wide-toothed smile (`screamer_smiler`) can appear at the end of a hallway. 
  * *The Trap:* Shining the flashlight on it or sprinting away triggers an instant rush $\rightarrow$ screamer. 
  * *The Counter:* The player must turn *off* their flashlight and stand completely still, letting panic climb naturally from the darkness until the eyes fade away.
* **The Panic Limit:** Running out of flashlight battery in the dark zones or hitting the maximum threshold on the panic bar triggers the standard fatal screamer.

---

## Asset Generation Registry

### Textures
To be added to `TEXTURES.md`:
* `backrooms_wallpaper_albedo.png`: Pale, repeating, retro-monoyellow wallpaper pattern.
* `backrooms_carpet_albedo.png`: Dirty, water-stained, low-pile commercial carpet texture.
* `arrow_decal.png`: A faded, industrial stenciled arrow (used for up/down navigation cues).
* `screamer_smiler.png`: High-contrast, glowing white teeth and wide unblinking eyes surrounded by pure alpha channels.

### Audio
To be synthesized via pure Python stdlib in `tools/make_sfx_backrooms.py`:
* `fluorescent_hum.wav`: A continuous, annoying, high-pitched $60\text{ Hz}$ electrical drone (looping background track).
* `light_pop.wav`: A sharp, metallic electrical snap indicating a failed turn or an unlinking loop.
* `rotary_ring.wav`: A distant, piercing old-school telephone bell ringing through the walls.
* `phone_whisper.wav`: A compressed, low-fidelity audio file of distorted, overlapping voices reading a trap note script.

### 3D Models (Blender $\rightarrow$ `.glb`)
* `wall_segment_modular.glb`: A standard $3\text{m} \times 3\text{m}$ flat wall layout with a baseboard.
* `ceiling_light_fluorescent.glb`: A recessed $2\text{x}4$ office light fixture with a translucent, flickering plastic mesh.
* `rotary_phone.glb`: A standalone, grimy black 1970s rotary desk phone placed directly on the carpet.

---

## Mechanics & Polish Ideas

* **The Footstep Echo:** Introduce a subtle script that records the player's footstep audio timestamps and plays them back at half-volume with a $0.4$-second delay, creating the auditory illusion that someone is walking exactly two paces behind them.
* **The Mirage Doors:** Place a few blood-red doors identical to the "Back Doors" of previous levels. When interacted with, they open up to expose a solid, blank yellow wallpaper wall, instantly spiking panic by $+10$ for mocking the player's hope of retreat.
* **The Carpet Squeak:** Walking over darker, stained patches of carpet switches the footstep audio variant from a dry thud to a heavy, squelching wet squeak, confirming the "damp carpet" lore physically through gameplay.