# KONTUR_level.md

## 1. Concept and Universe Integration
The K.O.N.T.U.R. universe fits perfectly into the existing game's psychological experiment framing. 
* The K.O.N.T.U.R. organization is a secret Soviet-era agency designed to research and contain anomalous objects[cite: 1].
* The core anomaly is Spore Fungus O-41, an agent that invades concrete and rebuilds familiar spaces into illogical, endless dimensions[cite: 1]. 
* This mirrors the game's premise of Subject 47 navigating a psychological experiment where the mind manifests entities[cite: 2, 4]. 
* The narrative twist here is that the "experiment" is actually a K.O.N.T.U.R. containment test inside a Class-level Object, blending bureaucratic thriller elements with cosmic horror[cite: 1].

## 2. Level Overview: "The Object"
The level takes place in a corrupted Soviet-era Khrushchyovka apartment block that seamlessly transitions into a sterile, bureaucratic K.O.N.T.U.R. observation facility[cite: 1]. 

* **The Trigger/Atmosphere:** The environment is deeply claustrophobic. The walls are made of porous concrete heavily infected with O-41 mold and moss[cite: 1]. Conventional mechanics like the flashlight will flicker heavily due to anomalous interference.
* **Winning Condition:** The player must navigate the anomalous stairwells, synthesize or find a bottle of household vinegar, and use it to melt a fungal barrier blocking the exit door to "Barkhan-9"[cite: 1].
* **Losing Condition:** The player's panic bar fills from prolonged exposure to infected dread zones, or they trigger one of the localized entities (Gabar or Perëkozhnik)[cite: 1, 4].

## 3. Puzzle-Like Mechanics and Choices
To advance without failing, the player must make specific behavioral choices that contrast with previous levels.

### A. The Gabar Gauntlet (Movement Puzzle)
* **Mechanic:** In a specific long, toy-scattered hallway, the player enters the territory of Gabar[cite: 1]. 
* **The Rule:** Gabar pursues anyone who stops moving; even a brief pause draws its attention[cite: 1]. 
* **Implementation:** When entering this `DreadZone`, a hidden `StandstillTimer` activates. If the player's velocity is zero for more than 1.5 seconds, panic spikes at a massive rate (+25/s) and a childlike, tentacled entity appears at the edge of the screen[cite: 1, 2]. 
* **The Choice:** The player must continuously walk (but *not* sprint, as sprinting still raises base panic)[cite: 4]. Stopping to look at the environment will cause instant failure[cite: 1, 4].

### B. The Perëkozhnik Standoff (Gaze Puzzle)
* **Mechanic:** The player must cross a communal kitchen to retrieve the cellar key or vinegar. Standing unnaturally still in the corner is a shapechanger (Perëkozhnik) mimicking an ordinary resident[cite: 1].
* **The Rule:** It lunges if you approach it, or if you look away after noticing it[cite: 1]. 
* **Implementation:** This inverts the Void's `CreatureStalker` logic. Once the player looks at the Perëkozhnik, a `ScaryObject` raycast registers the lock[cite: 2]. 
* **The Choice:** The player must slowly walk backward out of the room while keeping the entity dead-center in their crosshairs. Breaking line-of-sight after establishing it triggers a fatal `Screamer.trigger()`[cite: 2, 4]. Moving closer than 2 meters also triggers instant death[cite: 1].

### C. The Vinegar Defense (Interaction Puzzle)
* **Mechanic:** Medical science in K.O.N.T.U.R. dictates that common household vinegar slows down the O-41 spore's spread[cite: 1]. 
* **The Choice:** The player finds a spray bottle of vinegar. They can choose to spray it on mirrors (which normally cause massive disorientation and panic spikes) to neutralize them[cite: 1]. 
* **The Trap:** A highly official K.O.N.T.U.R. archival log sits on a desk. It is a read-to-die trap note[cite: 2, 4]. Reading it provides fascinating lore about the 1988 Kanalotvar sewer leak, but the text bleeds red and panic rises at +12/s while open[cite: 1, 2]. The player must choose to close it early to survive[cite: 4].

## 4. Required Textures (Prompts for nano-banana-pro)

To bring this level to life, you will need to generate the following textures using your AI pipeline:

1.  **`kontur_concrete_infected.png`**
    *   *Prompt:* "Seamless texture of porous, brutalist Soviet-era concrete covered in patches of dark, unnerving organic moss and mold. The mold should look slightly parasitic and dimensional. High contrast, low lighting, photorealistic, suitable for PBR material."
2.  **`soviet_wallpaper_peeling.png`**
    *   *Prompt:* "Seamless texture of 1970s Soviet apartment wallpaper, faded yellow and green geometric patterns, heavily peeling and water-damaged. Grimy and depressing atmosphere, photorealistic."
3.  **`kontur_bureaucratic_note.png`**
    *   *Prompt:* "A top-down view of an aged, typewritten Soviet bureaucratic document on cheap yellowed paper. It features a red faded 'K.O.N.T.U.R.' stamp and heavily redacted black censor bars over Russian Cyrillic text."
4.  **`screamer_gabar.png`**
    *   *Prompt:* "A terrifying, distorted close-up of a childlike plush toy face with hollow eyes, surrounded by fleshy, dangling tentacles. Analog horror style, high contrast, black background, deeply unsettling and uncanny."
5.  **`screamer_shapechanger.png`**
    *   *Prompt:* "A terrifying close-up of an uncanny humanoid face that looks almost like an ordinary person but structurally wrong. Expressionless, pale, standing in a dark communal kitchen. Analog horror screamer, high contrast."

## 5. Implementation Algorithm (Godot Architecture)

1.  **Level Setup:** Create `level_6_kontur.tscn` using the `RoomBuilder` script to procedurally generate a layout combining tight Khrushchyovka corridors and a sterile observation deck[cite: 2].
2.  **Zone Creation:** 
    *   Apply `DreadZone` logic to the main corridors where O-41 infection is heaviest[cite: 2]. 
    *   Create a specialized `MovementZone` Area3D for Gabar's hallway. Connect the `body_entered` signal to start tracking `player.velocity.length()`. If velocity equals 0 for > 1.5s, call `player.add_panic(50)` to trigger the screamer[cite: 2].
3.  **Entity Scripting (`creature_shapechanger.gd`):**
    *   Extend `StaticBody3D`. 
    *   Track the player's `_gaze_timer` from `player.gd`[cite: 2]. 
    *   Set a boolean `has_been_seen = true` once the player's raycast hits the entity. 
    *   In `_process`, if `has_been_seen` is true AND the player's camera dot product facing the entity falls below a threshold (meaning they looked away), trigger `Screamer.trigger()`[cite: 2].
4.  **Item Logic (`vinegar_item.gd`):**
    *   Extend `KeyItem`[cite: 2]. 
    *   Upon interaction, set `GameState.has_vinegar = true`. 
    *   Modify `TriggerObject` mirrors to check this flag; if true, the mirror's `ScaryObject` component is disabled (neutralized), and a melting sound effect plays.
5.  **Screamer Integration:** Map the new screamers into `screamer.gd` under `LEVEL_SCREAMERS[6]` to ensure the correct imagery flashes upon failure[cite: 2, 3].