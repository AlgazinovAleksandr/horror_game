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
| `screamers/screamer.png` | Distorted human face — high contrast, wide mouth, horror screamer | Screamer overlay (random selection, all levels) | done |
| `screamers/screamer_2.png` | Second distorted face variant — alternate horror expression | Screamer overlay (random selection, all levels) | done |
| `wall_intro.png` | Cold dark concrete/stone — damp, rough, minimally detailed; small dark room feel | Intro Room — all 4 wall CSGBox3D nodes | done |
| `floor_intro.png` | Dark stone slab — faint cracks, slightly uneven; candlelit cellar feel | Intro Room — floor CSGBox3D node | done |
| `ceiling_intro.png` | Rough concrete ceiling — darker than walls, slight water stain | Intro Room — ceiling CSGBox3D node | done |
| `painting_intro.png` | Abstract unsettling painting — dark blurred figures, gold frame suggestion; hung on intro back wall | Intro Room — MeshInstance3D quad on back wall | done |
| `cobweb_intro.png` | Spider web — semi-transparent PNG, detailed silk strands with spider silhouette | Intro Room — MeshInstance3D quads in top corners | done |
| `ceiling_lab.png` | Fluorescent drop-ceiling tiles — rectangular grid, yellowed, one tile displaced | Level 1 (The Lab) — ceiling CSGBox3D nodes (currently shares wall_lab) | done |
| `poster_lab.png` | Medical anatomy diagram — torso cross-section with handwritten annotations in red; unnerving scrawl | Level 1 (The Lab) — MeshInstance3D quad on exam room wall | done |
| `blood_lab.png` | Dried blood smear — dark brownish-red, irregular shape, worn at edges | Level 1 (The Lab) — MeshInstance3D quad near exam table / floor | done |
| `ceiling_house.png` | Yellowed domestic ceiling — faint water damage ring stain, flaking paint patches | Level 2 (The House) — ceiling CSGBox3D nodes (currently shares wall_house) | done |
| `painting_house.png` | Unnerving portrait — formal Victorian-style figure, eyes slightly wrong, dark background | Level 2 (The House) — MeshInstance3D quad on living room wall | done |
| `wall_void.png` | Cracked dark matter — deep black with jagged fracture lines, faint purple glow at cracks | Level 3 (The Void) — all wall CSGBox3D nodes | done |
| `floor_void.png` | Dark abyss floor — near-black with faint chalked symbols and fragmented handwritten words | Level 3 (The Void) — all floor CSGBox3D nodes | done |
| `note_paper.png` | Aged cream paper — faint ruled lines, slight yellowing at edges | All notes (`note.gd` base material for both safe and trap notes) | done |
| `main_menu_bg.png` | Dark atmospheric corridor silhouette — deep shadows, minimal detail | Main menu scene (`main_menu.gd` background image) | done |
| `wall.png` | Victorian hotel wall — peeling damask wallpaper above dark wood wainscoting | Level 3 (The Corridor) — all wall CSGBox3D nodes (triplanar, y-scale −1/3 so wainscot sits at floor) | done |
| `carpet.png` | Ornate hotel carpet — dark green/mustard diamond pattern, aged | Level 3 (The Corridor) — floor CSGBox3D nodes + one wall-hung carpet quad in Zone C | done |
| `door.png` | Old hotel room door (room 217) on matching wallpaper/wainscot background | Level 3 (The Corridor) — exit door + 3 fake locked-door panels (`fake_door.gd`) | done |
| `clock.png` | Grandfather clock on matching wallpaper/wainscot background | Level 3 (The Corridor) — full-height cursed panel at d=48 m (ScaryObject 1.0, chime event) | done |
| `mirror.png` | Ornate oval mirror reflecting a torch-lit corridor, matching background | Level 3 (The Corridor) — full-height cursed panel at d=285 m (ScaryObject 2.5) | done |
| `painting.png` | Dark landscape oil painting in ornate frame | Level 3 (The Corridor) — 4 painting quads (2 cursed, 2 plain decor) | done |
| `torch.png` | Wall sconce torch (lit) on matching wallpaper/wainscot background | Level 3 (The Corridor) — *dead torch* panels in Zone C (lit torches are 3D `torch_3d.gd`) | done |
| `screamer_hotel.png` | Victorian woman, hollow eyes, screaming — hotel-ghost screamer | Level 3 (The Corridor) ONLY — referenced directly by `screamer.gd`; deliberately NOT in `screamers/` | done |
| `blood_corridor.png` | Dried blood hand-drag smear on the hotel wallpaper (style-matched to `wall.png`) | Level 3 (The Corridor) — 6 wall quads in Zones B/C | done |
| `floor_crack.png` | Carpet torn open over splintered floorboards, black void beneath | Level 3 (The Corridor) — 2 static floor decals + spawned under player by floor-crack event | done |

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

### Screamer subfolder
Screamer images live in `game/assets/textures/screamers/`. Any `.png` dropped in is auto-loaded at startup via `DirAccess` in `screamer.gd` — no code change needed to add new variants.

### Note paper textures
`note_paper.png` is applied in `note.gd`'s `_style_mesh()` as the base material for all note mesh instances. Trap notes then receive a `Color(0.9, 0.55, 0.55)` red tint on top.
