---
name: fix-void
description: 'Diagnose and fix black void / open-space holes in Godot CSGBox3D levels. Use when the user reports a black rectangle, visible void, missing wall, floor gap, or sees "outside the level" through geometry. Triggers on: black void, open space, missing wall, I can see outside, black rectangle, can fall through, floor gap.'
---

# Fix-Void: Geometry Void Diagnosis Protocol

This game uses axis-aligned CSGBox3D nodes for all geometry (no BSP). Every void is caused by a **missing box** — there is no geometry covering some rectangular region that the camera can see into.

## Step 1 — Localise the void

Ask these questions one at a time, using screenshots if available:

1. **Which level?** (intro_room / level_1 / level_2 / level_3)
2. **Which room or corridor is the player standing in when they see it?**
3. **What direction are they facing?** (roughly: toward back wall, toward entrance, left, right, up)
4. **Is there a nearby landmark?** (door, note, table, light source) — get its name or position from the .tscn.
5. **Does the void look like:** (a) a thin sliver/crack, (b) a large rectangle, (c) a hole in the floor/ceiling, or (d) an entire wall face missing?

If a screenshot is available, identify the void's approximate world position by cross-referencing visible landmarks against node transforms in the .tscn file. Read the relevant .tscn fully before diagnosing.

---

## Step 2 — Map the boundary

Read the level's .tscn and build a mental (or written) coverage map:

For each axis, list where geometry **ends** and where the **next piece starts**:

```
X gaps:  list all CSGBox3D nodes sorted by transform.x, note inner-face positions
Z gaps:  list all CSGBox3D nodes sorted by transform.z, note inner-face positions
Y gaps:  floor top faces and ceiling bottom faces (should be y=0 and y=2.7)
```

Inner face formula for a CSGBox3D:
```
inner_face_min_x = transform.x - size.x / 2
inner_face_max_x = transform.x + size.x / 2
```

**Junction rule**: when two rooms of different widths share a boundary (e.g. a narrow hallway opening into a wider room), the wider room needs a **front wall** covering the extra width at the boundary z. This is the single most common void cause in this project.

---

## Step 3 — Identify the void type

| Symptom | Root cause | Fix |
|---------|-----------|-----|
| Black rectangle at a wall junction where two rooms meet | Missing front/side wall covering width difference at boundary | Add CSGBox3D wall segment at the boundary z/x |
| Black hole at a room corner (step in wall) | Two walls at different x/z on the same boundary — no cap face | Add a small cap wall perpendicular to the step |
| Black rectangle at the back of a room | Back wall not covering full width — gap between two back-wall pieces | Add a CSGBox3D back wall segment to close the gap |
| Dark strip along ceiling or floor at a junction | Ceiling/floor pieces don't share the same boundary edge | Extend one of the pieces OR add a bridge piece |
| Large black area visible through a doorway | Doorway strip (floor/ceiling/walls) is missing one face on the far side | Add back-wall, side-wall, or ceiling piece for the doorway strip |

---

## Step 4 — Compute the fix node

For a **missing front wall** (most common):
```
gap_width  = far_wall_inner_face_x - near_hallway_inner_face_x
center_x   = near_hallway_inner_face_x + gap_width / 2
center_z   = boundary_z + 0.15          # 0.3m thick wall, centered just inside boundary
center_y   = 1.35                        # standard: floor at 0, ceiling at 2.7, wall center = 1.35
size       = Vector3(gap_width, 3.0, 0.3)
```

For a **corner cap** (step junction):
```
gap_width  = abs(wall_A_inner_x - wall_B_outer_x)
center_x   = (wall_A_inner_x + wall_B_outer_x) / 2
center_z   = boundary_z + 0.15
size       = Vector3(gap_width, 3.0, 0.3)
```

For a **back wall gap**:
```
gap_width  = wall_B_outer_x - wall_A_outer_x   # gap between two back-wall pieces
center_x   = (wall_A_outer_x + wall_B_outer_x) / 2
center_z   = back_wall_z                         # same z as the other back walls
size       = Vector3(gap_width, 3.0, 0.3)
```

---

## Step 5 — Verify before writing

Before adding the fix node, answer:

- **Does this wall block any required player path?** (doors, corridors, room transitions)
  - If yes: the wall needs a doorway gap, OR re-examine whether this is actually the right z position.
- **Does it align flush with adjacent geometry?** (inner face of new wall = outer face of neighboring piece)
- **Is the height (size.y = 3.0) correct?** Confirm the level's wall height from existing nodes.
- **Does the floor/ceiling also have a gap at this location?** If yes, add floor/ceiling bridge pieces too (same x/z, y adjusted).

---

## Step 6 — Write the fix

Add the node to the .tscn **in the relevant section** (grouped near similar geometry, before the lights section). Use `use_collision = true`.

```
[node name="<DescriptiveName>" type="CSGBox3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, <cx>, <cy>, <cz>)
size = Vector3(<sx>, <sy>, <sz>)
use_collision = true
```

---

## Known void locations fixed in this project (do not re-introduce)

| Level | Void | Fix node |
|-------|------|----------|
| level_2 | Back wall gap between LivWallBack (x=4.5) and BedWallBack (x=5.5) | `DoorwayBackWall` at (5.0, 1.35, 8.15), size (1.0, 3.0, 0.3) |
| level_2 | Living room entrance: hallway (2.4m wide) opens into living room (5m wide) — right side gap x=1.2–4.5 | `LivWallFront` at (2.85, 1.35, 3.15), size (3.3, 3.0, 0.3) |
| level_2 | Left-corner step at living room entrance x=−1.2 to −0.8 | `LivCornerL` at (−1.0, 1.35, 3.15), size (0.4, 3.0, 0.3) |
| level_2 | Ceiling gap above doorway strip x=4.5–5.5 | `DoorwayCeiling` at (5.0, 2.85, 5.5), size (1.0, 0.3, 5.0) |
