1) Fix the fix-void skill so that the YAML part shows correctly - Sasha

2) Think about the plot improvements to make the game better

3) Implement the panic scale. The panic increases x (~5) times faster than decreases

4) Think about the ways to remove the panic besides just waiting until it gets back to the normal condition

5) Think about random noises / half-screamers at the random moments in the game to keep the tension. Examples: floor crack, painting falls. TODO: create sounds, textures, falling logic in case of paintings

6) Think about the audio text that the player will hear and make it through TTS. Leave notes but add some audio features

7) Think about another level: long corridor (absolute dark but the player has the torch) with traps: bear traps, screamers, visual effects, weird noises, good vibe sound track (like in the corridor game). The level idea: pass the long corridor without panicking and without the creature kill you. At least 2-minute walk

8) Think about the checkpoints - the game starts from the beginning / or at the beginning of the level

9) Somewhere at the end of the game we can create a maze on the wall - the player needs to use the mouse to pass the maze somehow (think about the logic)

### How we identify that the player is triggered / panicking / it is the time to fail the game

1) The user goes into the dark place to collect a key (or another object). The longer the player stays in the dark - the higher is the panic on the panic scale. Once the user escapes the dark the panic decreases. If the panic reaches a certain level - the user dies

2) There is a 3D model of a monster. At the random moment it starts running towards the player. If the player runs away / stops watching at the creature - it means the player is panicking and fails the game. If the player stares at the creature for say 5 seconds without running away / stopping staring at it - it means the player passed the test and the creature disappears. No panic scale included, the player dies immediately after failing

3) There are some trigger objects (weird paintings / knife / blood on the floor). The difference between the creature from 2) is that the player MUST NOT stare at these objects. The panic scale increases - the longer the players stares at them.

4) You hear a sound telling to not turn back / you hear the somebody is breathing just behind you - and the goal is not to turn back
