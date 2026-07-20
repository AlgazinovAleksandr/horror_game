# TEXTURES.md — Texture Registry

Single-source inventory of every texture in the project.

Columns:
- `file_name` — path relative to `game/assets/textures/`
- `texture_description` — visual/generation prompt summary
- `where_used` — level + node type(s)
- `status` — `done` / `to_be_added` / `requires_review`

### intro/
| file_name | texture_description | where_used | status |
|-----------|---------------------|------------|--------|
| `intro/wall_intro.png` | Cold dark concrete/stone — damp, rough, minimally detailed; small dark room feel | Intro Room — all 4 wall CSGBox3D nodes | done |
| `intro/floor_intro.png` | Dark stone slab — faint cracks, slightly uneven; candlelit cellar feel | Intro Room — floor CSGBox3D node | done |
| `intro/ceiling_intro.png` | Rough concrete ceiling — darker than walls, slight water stain | Intro Room — ceiling CSGBox3D node | done |
| `intro/painting_intro.png` | Abstract unsettling painting — dark blurred figures, gold frame suggestion; hung on intro back wall | Intro Room — MeshInstance3D quad on back wall | done |
| `intro/cobweb_intro.png` | Spider web — semi-transparent PNG, detailed silk strands with spider silhouette | Intro Room — MeshInstance3D quads in top corners | done |

### level_1_lab/
| file_name | texture_description | where_used | status |
|-----------|---------------------|------------|--------|
| `level_1_lab/lab_wall.png` | Sterile institutional tile — pale grey/green, grime lines, institutional gloss | Level 1 (The Lab) — all wall CSGBox3D nodes | done |
| `level_1_lab/lab_floor.png` | Clinical linoleum — grey with faint grid seams, scuff marks | Level 1 (The Lab) — all floor CSGBox3D nodes | done |
| `level_1_lab/lab_ceiling.png` | Fluorescent drop-ceiling tiles — rectangular grid, yellowed, one tile displaced | Level 1 (The Lab) — ceiling CSGBox3D nodes | done |
| `level_1_lab/poster_lab.png` | Medical anatomy diagram — torso cross-section with handwritten annotations in red; unnerving scrawl | Level 1 (The Lab) — cursed poster (gaze panic) on the morgue wall, built in `level_1.gd` | done |
| `level_1_lab/blood_lab.png` | Dried blood smear — dark brownish-red, irregular shape, worn at edges | Level 1 (The Lab) — decal quad (on disk; not currently wired into the procedural build) | requires_review |
| `level_1_lab/lab_morgue_wall.png` | Cold-storage stainless-steel lockers, scuffed; seamless | Level 1 (The Lab) — the Morgue room's walls (per-room `wall_mat` override in `level_1.gd:_rooms_with_skins()`) | done |
| `level_1_lab/lab_floor_wet.png` | Institutional tile with a dark water sheen; seamless | Level 1 (The Lab) — the Morgue room's floor (per-room `floor_mat` override) | done |
| `level_1_lab/lab_oneway_mirror.png` | Dark observation glass with a faint reflection; panel | Level 1 (The Lab) — observation room mirror. **Note:** `living_mirror.gd` builds its glass from a `StandardMaterial3D` (metallic dark), not this texture; on disk, **not yet wired** | requires_review |
| `level_1_lab/lab_breaker_panel.png` | Grey electrical fuse box, open; panel/decal | Level 1 (The Lab) — applied to the 3 `Breaker` panel meshes (`breaker.gd` `PANEL_TEX`) so switches read as real load-centres | done |
| `level_1_lab/lab_warning_sign.png` | Faded "QUARANTINE / DO NOT ENTER" sign; decal | Level 1 (The Lab) — decal panel on the Records room wall (`level_1.gd:_spawn_room_props()`) | done |
| `level_1_lab/apparition_figure.png` | Tall pale gaunt skeletal wraith, front-on, on a TRANSPARENT background (billboard cutout) | Levels 1–2 — the `Apparition` figure (`apparition.gd`) AND the `LivingMirror` figure. 1024×1536 RGBA, real alpha (corners α=0); renders as a clean cutout in-game. The old white-background `.jpg` is superseded (`Apparition._resolve_tex` prefers `.png`) | done |
| `level_1_lab/screamer_apparition.jpg` | Close-up screaming face for the apparition's fatal rush (fullscreen) | Levels 1–2 — `Apparition._rush()` fatal `Screamer.trigger()` AV (`RUSH_BASE`). Fullscreen overlay (no alpha needed); a `.png` is still preferred for consistency | done |
| `level_1_lab/screamer_lab.png` | Lab-specific fatal screamer face | Level 1 (The Lab) — fatal screamer; `screamer.gd` `LEVEL_SCREAMERS[1]` | done |

### level_2_house/
| file_name | texture_description | where_used | status |
|-----------|---------------------|------------|--------|
| `level_2_house/house_wall.png` | Peeling domestic wallpaper — muted brown/beige, floral pattern, torn edges | Level 2 (The House) — all wall CSGBox3D nodes | done |
| `level_2_house/house_floor.png` | Worn wooden floorboards — dark oak, visible grain, gapped planks | Level 2 (The House) — all floor CSGBox3D nodes | done |
| `level_2_house/house_ceiling.png` | Yellowed domestic ceiling — faint water damage ring stain, flaking paint patches | Level 2 (The House) — ceiling CSGBox3D nodes | done |
| `level_2_house/painting_house.png` | Unnerving portrait — formal Victorian-style figure, eyes slightly wrong, dark background | Level 2 (The House) — cursed bedroom painting (gaze panic), built in `level_2.gd` | done |
| `level_2_house/house_basement_concrete.png` | Damp stained concrete wall; seamless | Level 2 (The House) — the lowered cellar walls (`_build_cellar()` in `level_2.gd`) | done |
| `level_2_house/tv_static_face.jpg` | CRT static with a faint face emerging; panel/emissive | Level 2 (The House) — living-room TV-static gaze panel, built in `level_2.gd:_spawn_tv()` (resolved via `Apparition._resolve_tex` — the `.png`/`.jpg` path fix) | done |
| `level_2_house/house_kitchen_wall.png` | Greasy floral-tile kitchen wall; seamless | Level 2 (The House) — the Kitchen room's walls (per-room `wall_mat` override in `level_2.gd:_rooms_with_skins()`) | done |
| `level_2_house/house_bathroom_tile.png` | Cracked white bathroom tile, mildew; seamless | Level 2 (The House) — the Bathroom room's walls (per-room `wall_mat` override) | done |
| `level_2_house/house_wood_stairs.png` | Worn wooden staircase texture; seamless | Level 2 (The House) — the cellar ramp surface (`level_2.gd:_build_cellar()`) | done |
| `level_2_house/child_drawing.png` | Unsettling crayon child's drawing (a figure with too many limbs); decal | Level 2 (The House) — cursed decal on the child's-room east wall (`level_2.gd:_spawn_room_props()`) | done |
| `level_2_house/lock_face.png` | Combination lock face — digits/dial for the exit lock UI | Level 2 (The House) — combination lock mesh in `level_2_1.tscn` | done |
| `level_2_house/forest.png` | Moonlit treeline behind the window glass — faint, self-illuminated so it reads in the dark room | Level 2 (The House) — `WindowForest` quad built in `level_2.gd` `_spawn_window()` | done |
| `level_2_house/screamer_forest.png` | Forest-creature close-up (survivable Forest scare) | Level 2 (The House) — `flash_scare()` fired on close approach to the window (`level_2.gd`) | done |
| `level_2_house/screamer_house.png` | Baba-Yaga / hag face — house-specific fatal screamer | Level 2 (The House) — fatal screamer; `screamer.gd` `LEVEL_SCREAMERS[2]` | done |

### level_3_corridor/
| file_name | texture_description | where_used | status |
|-----------|---------------------|------------|--------|
| `level_3_corridor/wall.png` | Victorian hotel wall — peeling damask wallpaper above dark wood wainscoting | Level 3 (The Corridor) — all wall CSGBox3D nodes (triplanar, y-scale −1/3 so wainscot sits at floor) | done |
| `level_3_corridor/carpet.png` | Ornate hotel carpet — dark green/mustard diamond pattern, aged | Level 3 (The Corridor) — floor CSGBox3D nodes + one wall-hung carpet quad in Zone C | done |
| `level_3_corridor/door.png` | Old hotel room door (room 217) on matching wallpaper/wainscot background | Level 3 (The Corridor) — **exit door (room 217) only** | done |
| `level_3_corridor/ordinary_hotel_door.png` | Plain hotel room door on matching wallpaper/wainscot background | Level 3 (The Corridor) — all non-final doors: 3 fake locked panels (`fake_door.gd`) + 6 decor doors | done |
| `level_3_corridor/clock.png` | Grandfather clock on matching wallpaper/wainscot background | Level 3 (The Corridor) — full-height cursed panel at d=48 m (ScaryObject 1.0, chime event) | done |
| `level_3_corridor/mirror.png` | Ornate oval mirror reflecting a torch-lit corridor, matching background | Level 3 (The Corridor) — side-wall cursed panel(s) (ScaryObject 2.0/2.5) | done |
| `level_3_corridor/mirror_with_creature.png` | Mirror with a creature standing in the reflection | Level 3 (The Corridor) — turn mirrors set flush on the wall you face at the 90/230/275 m corners (`_spawn_turn_mirror`); gaze panel + proximity `flash_scare()` | done |
| `level_3_corridor/painting.png` | Dark landscape oil painting in ornate frame | Level 3 (The Corridor) — 4 painting quads (2 cursed, 2 plain decor) | done |
| `level_3_corridor/torch.png` | Wall sconce torch (lit) on matching wallpaper/wainscot background | Level 3 (The Corridor) — *dead torch* panels in Zone C (lit torches are 3D `torch_3d.gd`) | done |
| `level_3_corridor/screamer_hotel.png` | Victorian woman, hollow eyes, screaming — hotel-ghost screamer | Level 3 (The Corridor) ONLY — fatal screamer; `screamer.gd` `LEVEL_SCREAMERS[3]`, deliberately NOT in `screamers/` | done |
| `level_3_corridor/screamer_manager.png` | The Manager — hotel-clerk figure (survivable Manager scare) | Level 3 (The Corridor) — `flash_scare()` fired once mid-hall by the distance-triggered Manager event (`_ev_manager`) | done |
| `level_3_corridor/kontur_plate.png` | Brass door plate: "RECOVERED ITEMS ARE BAIT. LEAVE THEM." on matching hotel wallpaper+wainscot | Level 3 — **KONTUR hint 3/4** (answers KONTUR Gate 3). Full-height decor panel at d=172 m, side −1 (`corridor.gd:_spawn_panels()`) | done |
| `level_3_corridor/blood_corridor.png` | Dried blood hand-drag smear on the hotel wallpaper (style-matched to `wall.png`) | Level 3 (The Corridor) — 6 wall quads in Zones B/C | done |
| `level_3_corridor/floor_crack.png` | Carpet torn open over splintered floorboards, black void beneath | Level 3 (The Corridor) — 2 static floor decals + spawned under player by floor-crack event | done |

### level_backrooms/  (Level 4 — The Backrooms)
| file_name | texture_description | where_used | status |
|-----------|---------------------|------------|--------|
| `level_backrooms/backrooms_wallpaper_albedo.png` | Pale, repeating, retro mono-yellow wallpaper | Level 4 (The Backrooms) — all wall CSGBox3D nodes + arrow columns (triplanar, negative-V like the corridor) | done |
| `level_backrooms/backrooms_carpet_albedo.png` | Dirty, water-stained low-pile commercial carpet | Level 4 (The Backrooms) — all floor CSGBox3D nodes | done |
| `level_backrooms/arrow_decal.png` | Faded stencilled industrial arrow (up/down navigation cue) | Level 4 (The Backrooms) — quad on each hub arrow column; rotated 180° = the down arrow marking the correct arm | done |
| `level_backrooms/screamer_smiler.png` | Glowing wide-toothed smile + unblinking eyes on alpha | Level 4 (The Backrooms) — the Smiler billboard (`creature_smiler.gd`) AND the fatal screamer; `screamer.gd` `LEVEL_SCREAMERS[4]` | done |

Shader (not a texture): `assets/materials/backrooms/glitch_wall.gdshader` — the exit utility room's seam-tearing wall (screen-space vertex jitter + RGB split), built in `backrooms.gd` `_build_glitch_wall()`.

### level_5_kontur/  (Level 5 — KONTUR)
| file_name | texture_description | where_used | status |
|-----------|---------------------|------------|--------|
| `level_5_kontur/kontur_concrete_infected.png` | Porous brutalist concrete with dark parasitic mould patches; seamless | Level 5 — the `CONCRETE_ROOMS` (Passage, Archive) wall skin (`kontur.gd:_rooms_with_skins()`) | done |
| `level_5_kontur/kontur_wallpaper_soviet.png` | Peeling 1970s Soviet wallpaper, olive/yellow geometric; seamless | Level 5 — builder-wide wall material (the Soviet half) | done |
| `level_5_kontur/kontur_floor_tile.png` | Cracked Soviet mosaic floor, chipped beige/brown tiles; seamless | Level 5 — builder-wide floor material | done |
| `level_5_kontur/kontur_facility_wall.png` | Clinical mint-green institutional tile; seamless | Level 5 — the `FACILITY_ROOMS` (Airlock, Escort, Terminus) wall skin | done |
| `level_5_kontur/door_black.png` | Matte black steel industrial door, flat elevation | Level 5 — Gate 1's correct door (`choice_door.gd`, side randomised per run) | done |
| `level_5_kontur/door_red.png` | Blood-red steel door welded shut with an official stamp, flat elevation | Level 5 — Gate 1's wrong door | done |
| `level_5_kontur/kontur_sign_blank.png` | Blank enamel institutional sign plate with corner screws | Level 5 — all four redacted rule plates (`kontur.gd:_make_sign()`); text is `Label3D` over it, redaction is a black quad. Faintly emissive so it reads in the dark | done |
| `level_5_kontur/fungal_mass.png` | Wet grey-white mycelium blocking a doorway | Level 5 — Gate 1's red-door seal + Gate 2's `FungalBarrier` | done |
| `level_5_kontur/label_vinegar.png` | Soviet bottle label, typewriter text "VINEGAR" | Level 5 — Gate 2, the **correct** bottle (`bottle_item.gd`) | done |
| `level_5_kontur/label_bleach.png` | Soviet bottle label, "BLEACH" + hazard triangle | Level 5 — Gate 2, wrong bottle | done |
| `level_5_kontur/label_water.png` | Soviet bottle label, "DISTILLED WATER" | Level 5 — Gate 2, wrong bottle | done |
| `level_5_kontur/creature_shapechanger.png` | Gaunt almost-human figure in a grey Soviet coat, TRANSPARENT background | Level 5 — the Perëkozhnik billboard (`creature_shapechanger.gd`). Verified real alpha; renders as a clean cutout | done |
| `level_5_kontur/screamer_kontur.png` | Face erupting with fungal mycelium, screaming | Level 5 — fatal screamer; `screamer.gd` `LEVEL_SCREAMERS[5]` | done |
| `level_5_kontur/kontur_flash.png` | Spore burst with a half-formed screaming face | Level 5 — the wrong-answer `flash_scare()` on every gate (`kontur.gd:_strike()`) | done |
| `level_5_kontur/kontur_poster.png` | Soviet safety poster, "DO NOT TOUCH INFECTED SURFACES" | Level 5 — decal on the Archive's west wall | done |
| `level_5_kontur/kontur_panel_mailboxes.png` | Battered Soviet mailboxes on matching wallpaper background | Level 5 — full-height wall panel, Landing west wall | done |
| `level_5_kontur/kontur_panel_chute.png` | Rusted trash-chute hatch on matching concrete background | Level 5 — wall panel, Landing east wall | done |

### level_4_void/  (now Level 6 — The Void)
| file_name | texture_description | where_used | status |
|-----------|---------------------|------------|--------|
| `level_4_void/wall_void.png` | Cracked dark matter — deep black with jagged fracture lines, faint purple glow at cracks | Level 6 (The Void) — all wall CSGBox3D nodes | done |
| `level_4_void/floor_void.png` | Dark abyss floor — near-black with faint chalked symbols and fragmented handwritten words | Level 6 (The Void) — all floor CSGBox3D nodes | done |
| `level_4_void/screamer_void.png` | Void-specific fatal screamer face | Level 6 (The Void) — fatal screamer (creature lunge / void-fall / panic max); `screamer.gd` `LEVEL_SCREAMERS[6]` | done |

### screamers/
| file_name | texture_description | where_used | status |
|-----------|---------------------|------------|--------|
| `screamers/screamer.png` | Distorted human face — high contrast, wide mouth, horror screamer | Screamer overlay — **intro/ending fallback pool only** (random pick). Levels 1–4 use their own per-level screamer (`LEVEL_SCREAMERS` in `screamer.gd`) | done |
| `screamers/screamer_2.png` | Second distorted face variant — alternate horror expression | Screamer overlay — intro/ending fallback pool only (random pick) | done |

### shared/
| file_name | texture_description | where_used | status |
|-----------|---------------------|------------|--------|
| `shared/note_paper.png` | Aged cream paper — faint ruled lines, slight yellowing at edges | All notes (`note.gd` base material for both safe and trap notes) | done |

### ui/
| file_name | texture_description | where_used | status |
|-----------|---------------------|------------|--------|
| `ui/main_menu_bg.png` | Dark atmospheric corridor silhouette — deep shadows, minimal detail | Main menu scene (`main_menu.gd` background image) | done |

## Notes

### Ceiling textures
`lab_ceiling` and `house_ceiling` are separate from their wall textures. `_apply_textures()` in `level_1.gd` and `level_2.gd` already has a dedicated `"ceiling"` name branch that applies them.

### Material .tres files must use per-level subfolder paths
The `.tres` materials in `assets/materials/level_layout/` and `assets/materials/objects/` reference textures by `ext_resource` path + UID. When textures were reorganised into per-level subfolders, all of these silently broke (e.g. `wall_2.tres` still pointed at `res://assets/textures/wall_house.png`). Fixed in session 8 — see ISSUES_SOLUTIONS.md Issue 8. When adding or moving a texture, update both the **path** and the **uid** in any `.tres` that references it (the correct uid is in the texture's `.png.import` file).

### Decal-type textures
`painting_intro`, `cobweb_intro`, `poster_lab`, `blood_lab`, `painting_house` are flat MeshInstance3D quads placed against surfaces. They require both a texture file AND a MeshInstance3D node added to the scene. The Texture Audit Rule in CLAUDE.md covers both checks.

### Level 3 ceiling
Intentionally omitted — the Void's extreme vignette (strength 2.0, blue-purple) makes ceilings nearly invisible. Add if visibility is confirmed in testing.

### Screamer subfolder & per-level screamers
Images in `game/assets/textures/screamers/` are auto-loaded at startup via `DirAccess` in `screamer.gd` — but they are now only the **fallback pool for the intro room and ending** (random pick). Levels 1–6 each have a dedicated fatal screamer mapped in `screamer.gd`'s `LEVEL_SCREAMERS` table (`level_1_lab/screamer_lab.png`, `level_2_house/screamer_house.png`, `level_3_corridor/screamer_hotel.png`, `level_backrooms/screamer_smiler.png`, `level_4_void/screamer_void.png`), each kept in its own level folder and deliberately out of `screamers/` so it only appears in its level. (The Backrooms reuses the shared `jumpscare` audio with the smiler image.)
Separately, **survivable** flash scares (`Screamer.flash_scare()`, no restart) use their own images: `level_2_house/screamer_forest.png` (House window), `level_3_corridor/screamer_manager.png` (corridor Manager), `level_3_corridor/mirror_with_creature.png` (corridor turn mirrors).

### Note paper textures
`note_paper.png` is referenced by the scene-level materials `assets/materials/objects/note.tres` (safe notes) and `trap_note.tres` (trap notes, red-tinted variant), assigned as `surface_material_override` in the `.tscn` files. The runtime styling in `note.gd` (`_style_mesh()`) is commented out — the `.tres` materials are the live path.

### Procedural (untextured) Level 2 props — candidates for future textures
The pressure package builds several props in `level_2.gd` from plain `StandardMaterial3D` colors, no texture files: the living-room **window** frame (dark glass + wooden crossbars — note the pane now shows `forest.png` behind it) and the **tarnished mirror** (dark metallic quad). If texture budget allows, a `mirror_house.png` would upgrade the mirror — add a row above when generated. (The old window-glimpse silhouette capsule was removed; only the Forest scare remains at the window.)

### Session 11 — most expansion textures now wired
The Session-10 surface/decal batch was wired in Session 11 via `RoomBuilder`'s new per-room
`wall_mat`/`floor_mat` overrides (`level_*.gd:_rooms_with_skins()`) plus `_spawn_room_props()` and
the `Breaker`/cellar-ramp builders: `lab_morgue_wall`, `lab_floor_wet`, `lab_breaker_panel`,
`lab_warning_sign`, `house_kitchen_wall`, `house_bathroom_tile`, `house_wood_stairs`, `child_drawing`,
and the `tv_static_face` path fix are all live now. **Still `requires_review`:** `lab_oneway_mirror`
(the `LivingMirror` glass is a metallic `StandardMaterial3D`, not this texture) and `blood_lab` (no
decal placed yet).

### ⚠️ `apparition_figure` must be a transparent PNG
`apparition.gd` and `living_mirror.gd` both billboard `apparition_figure`. The file on disk is a **`.jpg` (no alpha)**, so the cutout renders as a solid rectangle. Provide a transparent `level_1_lab/apparition_figure.png` — `Apparition._resolve_tex()` already prefers `.png` over `.jpg`, so dropping the PNG in is the only step. Same JPEG-as-cutout caveat applies to any future billboard art.

### Draft textures
`level_1_lab/draft/`, `level_2_house/draft/` hold earlier/lower-quality versions (`wall_lab`, `floor_lab`, `wall_house`, etc.) kept for reference; the live textures are the `*_wall.png` / `*_floor.png` files in the parent folders. Not referenced by any script.
