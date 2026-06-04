# TEXTURES.md — Texture Registry

Single-source inventory of every texture in the project.

Columns:
- `file_name` — exact filename as it must appear in `game/assets/textures/`
- `texture_description` — visual/generation prompt summary
- `where_used` — level + node type(s)
- `status` — `done` / `to_be_added` / `requires_review`

| file_name | texture_description | where_used | status |
|-----------|---------------------|------------|--------|
| `wall_lab.png` | Sterile institutional tile — pale grey/green, grime lines, institutional gloss | Level 1 (The Lab) — all wall + ceiling CSGBox3D nodes | done |
| `floor_lab.png` | Clinical linoleum — grey with faint grid seams, scuff marks | Level 1 (The Lab) — all floor CSGBox3D nodes | done |
| `wall_house.png` | Peeling domestic wallpaper — muted brown/beige, floral pattern, torn edges | Level 2 (The House) — all wall + ceiling CSGBox3D nodes | done |
| `floor_house.png` | Worn wooden floorboards — dark oak, visible grain, gapped planks | Level 2 (The House) — all floor CSGBox3D nodes | done |
| `screamer.png` | Distorted human face — high contrast, wide mouth, horror screamer | Screamer overlay (all levels, on fail) | done |
| `wall_intro.png` | Cold dark concrete/stone — damp, rough, minimally detailed; small dark room feel | Intro Room — all 4 wall CSGBox3D nodes | to_be_added |
| `floor_intro.png` | Dark stone slab — faint cracks, slightly uneven; candlelit cellar feel | Intro Room — floor CSGBox3D node | to_be_added |
| `ceiling_intro.png` | Rough concrete ceiling — darker than walls, slight water stain | Intro Room — ceiling CSGBox3D node | to_be_added |
| `painting_intro.png` | Abstract unsettling painting — dark blurred figures, gold frame suggestion; hung on intro back wall | Intro Room — MeshInstance3D quad on back wall | to_be_added |
| `cobweb_intro.png` | Spider web — semi-transparent PNG, detailed silk strands with spider silhouette | Intro Room — MeshInstance3D quads in top corners | to_be_added |
| `ceiling_lab.png` | Fluorescent drop-ceiling tiles — rectangular grid, yellowed, one tile displaced | Level 1 (The Lab) — ceiling CSGBox3D nodes (currently shares wall_lab) | to_be_added |
| `poster_lab.png` | Medical anatomy diagram — torso cross-section with handwritten annotations in red; unnerving scrawl | Level 1 (The Lab) — MeshInstance3D quad on exam room wall | to_be_added |
| `blood_lab.png` | Dried blood smear — dark brownish-red, irregular shape, worn at edges | Level 1 (The Lab) — MeshInstance3D quad near exam table / floor | to_be_added |
| `ceiling_house.png` | Yellowed domestic ceiling — faint water damage ring stain, flaking paint patches | Level 2 (The House) — ceiling CSGBox3D nodes (currently shares wall_house) | to_be_added |
| `painting_house.png` | Unnerving portrait — formal Victorian-style figure, eyes slightly wrong, dark background | Level 2 (The House) — MeshInstance3D quad on living room wall | to_be_added |
| `wall_void.png` | Cracked dark matter — deep black with jagged fracture lines, faint purple glow at cracks | Level 3 (The Void) — all wall CSGBox3D nodes | to_be_added |
| `floor_void.png` | Dark abyss floor — near-black with faint chalked symbols and fragmented handwritten words | Level 3 (The Void) — all floor CSGBox3D nodes | to_be_added |

## Notes

### Ceiling textures
`ceiling_lab` and `ceiling_house` are separate from their wall textures. The current `_apply_textures()` in `level_1.gd` and `level_2.gd` applies `wall_tex` to nodes matching `"wall"` OR `"ceiling"` in their name. Once ceiling textures are ready, add a third branch:
```gdscript
if "ceiling" in name.to_lower():
    mesh.material_override = ceiling_mat
```

### Decal-type textures
`painting_intro`, `cobweb_intro`, `poster_lab`, `blood_lab`, `painting_house` are flat MeshInstance3D quads placed against surfaces. They require both a texture file AND a MeshInstance3D node added to the scene. The Texture Audit Rule in CLAUDE.md covers both checks.

### Level 3 ceiling
Intentionally omitted — the Void's extreme vignette (strength 2.0, blue-purple) makes ceilings nearly invisible. Add if visibility is confirmed in testing.

### Note paper textures
Excluded — `note.gd` applies colour tints procedurally. A paper texture would require updating `note.gd`'s `_style_mesh()` and is a separate task.
