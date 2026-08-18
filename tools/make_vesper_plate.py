#!/usr/bin/env python3
"""The face of the Corridor's NOTICE TO NIGHT STAFF plate at d = 250 m.

WHY THIS EXISTS
---------------
`corridor.gd:_spawn_nightmare_plate()` built the single most important cross-level hint in
the game (`DUNGEON_NIGHTMARES.md` §B2 — the one that teaches THE NIGHTMARE's silence, a
mechanic made of an ABSENCE which cannot teach itself) as an **untextured `BoxMesh`**:
`albedo_color = (0.20, 0.17, 0.09)`, emission 0.3, nothing else. The playtest capture of it
reads *"This note does not match the level vibe. Can we generate it in a more weird and old
way?"* — which is what a flat olive rectangle looks like from two metres away.

⚠️ HEADING ONLY, and this is a decision, not an omission (2026-08-16). The plate art carries
"HOTEL VESPER / NOTICE TO NIGHT STAFF / LOWER FLOORS" and nothing else. **The note text in
`corridor.gd` is unchanged** — not paraphrased, not shortened, not partially duplicated here
— because it is the only place in the game that explains why the music stopping is a signal,
and it is archived in the TAB journal so a player can re-read it four levels later.

⚠️ Drawn with the CODE-BASED generator (Pillow), never with flux. The whole point of this
image is legible words, and a diffusion model cannot letter a sign — every other note-like
asset in this project that tried came back with dream-alphabet.

USAGE
    bash <pack>/.claude/skills/level-1-image-generator/scripts/run.sh tools/make_vesper_plate.py
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import

where <pack> is the image-generation skill pack. The script imports `render` from that
pack's venv; it will not run under a bare python3.

⚠️ 900x600 = 3:2, and `corridor.gd` sizes the art quad from that aspect (0.44 x 0.293 m). If
this ratio changes, the mesh must change with it or `check_corridor_art.gd` goes red.
"""

from render import Design

OUT = "game/assets/textures/level_3_corridor/vesper_plate.png"

BRONZE_DK = (24, 20, 14)
BRASS = (150, 124, 66)
GOLD = (198, 172, 104)
RUST = (78, 52, 30)

d = Design("900x600", background=BRONZE_DK)
d.linear_gradient([(0.0, (38, 32, 21)), (0.45, (28, 24, 16)), (1.0, (18, 15, 10))], angle=100)

# Foxing and water staining, kept low-contrast so the type stays the loudest thing on it.
d.overlay_glow((0.22, 0.72), RUST, 0.34, strength=0.30, mode="blend")
d.overlay_glow((0.81, 0.24), RUST, 0.28, strength=0.24, mode="blend")
d.overlay_glow((0.52, 0.40), (70, 62, 42), 0.55, strength=0.18, mode="screen")

# ⚠️ NO painted bezel and NO painted screws. Both were tried and both are now REAL GEOMETRY
# in `_spawn_nightmare_plate()` — a bead frame of four thin boxes and four corner screws
# standing proud of the backing plate. Issue 35's lesson in its general form: the silhouette
# is what makes a prop read as an object, and a border painted onto a flat quad is exactly
# the "picture of a thing" this rebuild exists to stop being.

d.write(0.5, 0.245, "HOTEL VESPER", role="serif_display", weight="bold",
        size=52, color=BRASS, align="center", tracking=14)
d.line(0.30, 0.305, 0.70, 0.305, 3, (104, 86, 48))

d.write(0.5, 0.505, "NOTICE TO", role="serif_display", weight="bold",
        size=78, color=GOLD, align="center", tracking=6)
d.write(0.5, 0.675, "NIGHT STAFF", role="serif_display", weight="bold",
        size=78, color=GOLD, align="center", tracking=6)

d.write(0.5, 0.845, "LOWER FLOORS", role="mono", size=26,
        color=(120, 102, 62), align="center", tracking=10)

d.vignette(strength=0.22, radius=1.05, power=1.4)
d.save(OUT, grain=6, chroma=2, saturation=0.95, contrast=1.05)
print("wrote " + OUT)
