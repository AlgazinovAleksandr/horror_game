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
| `intro/intro_lab_door.png` | Rusted steel asylum door — barred observation hatch, bolt and padlock, fungus and creeping roots, blood handprint, stencilled "PSYCHIATRIC WING / BLOCK D-7". User-supplied; background keyed off with `tools/cutout_alpha.py --chroma auto`, then cropped to the leaf and re-stencilled from Cyrillic to English by `tools/restencil_door.py` | Intro Room — `ExitDoor`, `intro_room.gd:_build_exit_door()`. The first door in the game, and the only one that had no art at all before this | done |
| `intro/wall_intro.png` | Cold dark concrete/stone — damp, rough, minimally detailed | Intro Room — **superseded by `intro_wall.png`** below; kept on disk, no longer referenced by `_apply_textures()` | to_be_added |
| `intro/intro_wall.png` | Cold dark concrete/stone, peeling institutional wallpaper over damp plaster — a sharper, more detailed replacement for `wall_intro.png` | Intro Room — all wall CSGBox3D nodes, `uv1_scale=4.0` (`intro_room.gd:_apply_textures()`) | done |
| `intro/floor_intro.png` | Dark stone slab — faint cracks, slightly uneven | Intro Room — floor CSGBox3D node | done |
| `intro/ceiling_intro.png` | Rough concrete ceiling — darker than walls, slight water stain | Intro Room — ceiling CSGBox3D node | done |
| `intro/painting_intro.png` | Abstract unsettling painting — dark blurred figures, gold frame suggestion | Intro Room — **currently unused.** Dropped when the room was rebuilt as a bigger asylum ward (INTRO.md); the old back-wall placement/rotation logic in `_apply_textures()` was tied to the small room's single Z-normal wall and wasn't worth carrying forward speculatively | to_be_added |
| `intro/cobweb_intro.png` | Spider web — semi-transparent PNG, detailed silk strands with spider silhouette | Intro Room — MeshInstance3D quads in top corners (`_spawn_cobwebs()`, corner anchors now derived from `ROOM_SIZE`/`ROOM_HEIGHT`) | done |
| `intro/nightmare_face.png` | Extreme close-up horror jumpscare — gaunt pale distorted face lunging out of darkness, mouth open mid-scream, hollow black eyes, harsh single-source underlighting | Main menu cold-open jumpscare on START (`main_menu.gd`) only — a follow-up pass removed the Intro Room's mid-walk "fumble jolt" flash so the level itself has no screamer, leaving this the sole use | done |
| `intro/gurney_intro.png` | Old rusted hospital gurney mattress, top-down — stained vinyl, torn corners, water stains, loose restraint strap | Intro Room — top-facing QuadMesh over 3 gurney mattresses (`intro_room.gd:_build_gurney(pos)`, one texture reused across the player's own bed + 2 scattered empty ones, same reuse trick `_spawn_cobwebs()` uses) | done |
| `intro/cabinet_intro.png` | Rusted metal medical cabinet, front elevation — dented steel, peeling green paint, wire-glass windows | Intro Room — background dressing cabinets along the side walls (`intro_room.gd:_build_cabinets()`), applied directly to the CSGBox3D (not a quad — optional decorative dressing, a magnified crop is an accepted tradeoff here) | done |
| `intro/wheelchair_intro.png` | Old rusted wheelchair, 3/4 side view, isolated on a transparent background, dusty worn fabric seat, rust on wheel spokes and frame, dim horror-game prop lighting, clean alpha cutout | Intro Room — **superseded.** The billboard cutout read as visibly 2D from an angle, so `_build_wheelchair()` was rebuilt as a full 3D CSG prop (seat/backrest/armrests/wheels/casters/footrest, same level of detail as `_build_gurney()`/`_build_cabinets()`) with flat-tinted materials; this texture is no longer loaded | to_be_added |
| `intro/wall_chart_intro.png` | "RAVENCROFT COUNTY ASYLUM — PATIENT OBSERVATION CHART" pinned to a wall, front elevation, handwritten vitals/notes, water-stained edges, torn corner | Intro Room — wall decal on WallBack (`intro_room.gd:_build_wall_chart()`), clear of the exit door. `PlaneMesh` tipped upright via `rotation_degrees.x = 90.0` (flipped from an initial `-90.0`, which rendered it upside down — see `_build_wall_chart()`) | done |
| `intro/intro_switch.png` | Rusted institutional wall light switch plate, front elevation, "WARD 4" stencil, peeling paint, grime | Intro Room — the `LightSwitch` prop the player must find in the dark (`light_switch.gd:_build()`), `PlaneMesh` face at `rotation_degrees.x = 90.0`, bright emission (`emission_energy_multiplier = 0.9`) so it's actually findable. The `LightSwitch` node itself gets `rotation.y = PI/2.0` in `intro_room.gd:_spawn_light_switch()` — without it the plate stood parallel to WallLeft (edge-on to the player) instead of flush against it | done |
| `intro/intro_note.png` | Aged handwritten note on lined paper — Subject 47 opening briefing, water stains, torn edge | Intro Room — the note prop on the table (`intro_room.gd:_build_table_note_candle()`). The note previously had **no texture at all**: `note.gd`'s `_style_mesh()` runs in `_ready()`, before the intro's mesh child exists (deliberate add-to-tree-before-children ordering), so it silently never applied one. Applied directly here instead of through the shared `note.gd:paper_material()` (which backs every other level's notes) | done |

### level_1_lab/
| file_name | texture_description | where_used | status |
|-----------|---------------------|------------|--------|
| `level_1_lab/lab_wall.png` | Sterile institutional tile — pale grey/green, grime lines, institutional gloss | Level 1 (The Lab) — all wall CSGBox3D nodes | done |
| `level_1_lab/lab_floor.png` | Clinical linoleum — grey with faint grid seams, scuff marks | Level 1 (The Lab) — all floor CSGBox3D nodes | done |
| `level_1_lab/lab_ceiling.png` | Fluorescent drop-ceiling tiles — rectangular grid, yellowed, one tile displaced | Level 1 (The Lab) — ceiling CSGBox3D nodes | done |
| `level_1_lab/poster_lab.png` | Medical anatomy diagram — torso cross-section with handwritten annotations in red; unnerving scrawl | Level 1 (The Lab) — cursed poster (gaze panic) on the morgue wall, built in `level_1.gd` | done |
| `level_1_lab/blood_lab.png` | Dried blood smear — dark brownish-red, irregular shape, worn at edges | Level 1 — **unused.** Its `Blood` node in `level_1.tscn` was freed by `_clear_old_scene()` on every load, so the texture was loaded and never drawn; the node + `ext_resource` were removed (Session 15). Re-add via `_make_cursed_panel`/`_make_prop` if wanted | to_be_added |
| `level_1_lab/lab_door.png` | Heavy institutional steel door, flat elevation — pale grey-green enamel, wire-glass observation window, push bar, three riveted hinges, stencilled serial | Level 1 — exit + back doors (`door.gd:build_visual()`). **On a QuadMesh, not the box** — see the BoxMesh rule below | done |
| `level_1_lab/lab_morgue_shutter.png` | Corrugated steel roller shutter, flat elevation — ribbed slats, rust, "MORTUARY — AUTHORISED ACCESS ONLY" stencil | Level 1 — the `MorgueShutter` CSGBox gating the morgue (`level_1.gd`). Applied with `uv1_scale.x = -1`: Godot mirrors box UVs across opposite faces and the lettering came out backwards on the side the player reads it from | done |
| `level_1_lab/lab_surgical_tray.png` | Stainless instrument tray seen top-down — scalpel, haemostats, bone saw, forceps, dried blood | Level 1 — the morgue **tray** trigger object (`_make_trigger` detail `"tray"`, on a top-facing quad + procedural lip bars). One of the two objects the morgue note names | done |
| `level_1_lab/lab_monitor_face.png` | Whole CRT monitor, front elevation — bezel, stand, dusty glass, a half-formed face in green phosphor static | Level 1 — the morgue **monitor** trigger object (`_make_trigger` detail `"monitor"`, full-face quad, emission 0.85). ⚠️ Shipped as JPEG-data-named-`.png` and silently failed to load — see the integrity rule below | done |
| `level_1_lab/lab_keycard.png` | Facility ID keycard, flat top-down elevation — pale plastic, KONTUR/facility branding, magnetic stripe, photo blacked out, grimy | Level 1 — the guarded morgue keycard (`level_1.gd:_spawn_morgue_keycard`), on a **top-facing quad** over the card-stock slab. 1586x992 (1.6:1) — the slab is `0.16 x 0.02 x 0.10` to match; a portrait slab renders the card a quarter-turn out | done |
| `level_1_lab/lab_light_fitting.png` | Recessed fluorescent ceiling fitting seen from below — twin tubes behind a yellowed prismatic diffuser, dead insects, one tube burnt out | Level 1 — the diffuser of every ceiling lamp (`level_1.gd:_add_fixture()`). Emission is driven from `_drive_lights()` so blackouts kill the fitting visibly | done |
| `level_1_lab/lab_morgue_wall.png` | Cold-storage stainless-steel lockers, scuffed; seamless | Level 1 (The Lab) — the Morgue room's walls (per-room `wall_mat` override in `level_1.gd:_rooms_with_skins()`) | done |
| `level_1_lab/lab_floor_wet.png` | Institutional tile with a dark water sheen; seamless | Level 1 (The Lab) — the Morgue room's floor (per-room `floor_mat` override) | done |
| `level_1_lab/lab_oneway_mirror.png` | Dark observation glass with a faint reflection; panel | Level 1 + Level 2 — the `LivingMirror` glass (`living_mirror.gd` `GLASS_TEX`, wired Session 15; previously a flat metallic `StandardMaterial3D`). ⚠️ Its call sites must use `wall_point(..., 0.22)`: the figure hangs 0.05 behind the glass, and at the old 0.1 it sat **inside the wall and was never visible** | done |
| `level_1_lab/lab_breaker_panel.png` | Grey electrical fuse box, open; panel/decal | Level 1 (The Lab) — applied to the 3 `Breaker` panel meshes (`breaker.gd` `PANEL_TEX`) so switches read as real load-centres | done |
| `level_1_lab/lab_warning_sign.png` | Faded "QUARANTINE / DO NOT ENTER" sign; decal | Level 1 (The Lab) — decal panel on the Records room wall (`level_1.gd:_spawn_room_props()`) | done |
| `level_1_lab/lab_locker.png` | Front face of a tall steel utility locker, dead-on and edge to edge — chipped pale grey-green enamel, louvre vent, card holder, dented latch handle; flat neutral lighting, no cast shadow | Level 1 (The Lab) — the locker sealing the Records breaker (`lab_locker.gd` `TEX`). On its own **QuadMesh** over a `BoxMesh` body, never on the box face (Issue 24). 887x1774 (1:2) matches the 1.0 x 2.0 x 0.5 body | done |
| `level_1_lab/lab_nook_figure.png` | Gaunt figure in a filthy hospital gown, arms down, face rim-lit by a single arc; **fully cut out on a transparent background** | Level 1 (The Lab) — the figure revealed by the flare 5 s after the BreakerNook breaker is thrown (`level_1.gd:_build_nook_figure()`), billboarded and alpha-tweened. ⚠️ **Must stay RGBA** — an opaque background billboards as a solid rectangle in the dark, the bug `apparition_figure.jpg` shipped once. Verified 1024x1536 RGBA, 75% transparent | done |
| `level_1_lab/lab_nook_face.png` | Extreme close-up screaming face filling the frame, hard blue-white flash from below-left, deep black background | Level 1 (The Lab) — the fullscreen payload of the BreakerNook `Screamer.flash_scare()`. 1672x941 (≈16:9); rendered `STRETCH_KEEP_ASPECT_CENTERED` on black | done |
| `level_1_lab/apparition_figure.png` / `.jpg` | Tall pale gaunt skeletal wraith, front-on, on a TRANSPARENT background (billboard cutout) | **Superseded by `screamers/shared_screamer_figure.png`** below — `apparition.gd`'s `FIG_BASE` and `living_mirror.gd`'s `FIG_BASE` were repointed at the new shared asset so the figure could be swapped project-wide from one place; kept on disk, no longer loaded | to_be_added |
| `level_1_lab/screamer_apparition.jpg` | Close-up screaming face for the apparition's fatal rush (fullscreen) | **Superseded by `screamers/shared_screamer.png`** below — `apparition.gd`'s `RUSH_BASE` repointed; kept on disk, no longer loaded | to_be_added |
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
| `level_2_house/lock_face.png` | Combination lock face — digits/dial for the exit lock UI | Level 2 (The House) — second-line fallback in `_spawn_lock_and_doors()`, behind `house_lock_transparent.png` and `house_lock.png` | done |
| `level_2_house/house_lock.png` | Rusted combination padlock mounted on a weathered metal backing plate, front elevation | Level 2 (The House) — **superseded by `house_lock_transparent.png`** below; kept as the fallback if that file is ever missing | done |
| `level_2_house/house_lock_transparent.png` | Rusted combination padlock, no background — real alpha (1024×1024 RGBA, verified via PIL: alpha extrema 0–255) | Level 2 (The House) — the exit combination lock, mounted as a **child of the exit door** (`level_2.gd:_spawn_lock_and_doors()`) instead of a separate panel 1.4 m away. `TRANSPARENCY_ALPHA_SCISSOR`, no backing plate needed since it's genuinely transparent — hangs directly against the door's own wood texture. Sized down to `0.36 x 0.45` (was `0.8 x 1.0` — read as too big against the door) | done |
| `level_2_house/house_cellar_key.png` | Old iron cellar key seen **top-down**, on a fully TRANSPARENT background (alpha cutout) — long shaft, ornate bow, worn warded bit, rust | Level 2 — the cellar key (`level_2.gd`), on a face-up quad with `ALPHA_SCISSOR`. ⚠️ Must have real alpha; a JPEG or flattened PNG renders as a rectangle. **Cropped to its own alpha bounds** (1435x381 = 3.77:1); the quad is `0.20 x 0.053` to match, and must move if the art is re-cropped | done |
| `level_2_house/house_door.png` | Old six-panel domestic interior door, flat elevation — yellowed cream paint flaking to bare wood, tarnished brass rim lock | Level 2 — exit + back doors (`door.gd:build_visual()`). **On a QuadMesh, not the box** | done |
| `level_2_house/forest.png` | Moonlit treeline behind the window glass — faint, self-illuminated so it reads in the dark room | Level 2 (The House) — `WindowForest` quad built in `level_2.gd` `_spawn_window()` | done |
| `level_2_house/screamer_forest.png` | Forest-creature close-up (survivable Forest scare) | Level 2 (The House) — `flash_scare()` fired on close approach to the window (`level_2.gd`) | done |
| `level_2_house/screamer_house.png` | Baba-Yaga / hag face — house-specific fatal screamer | Level 2 (The House) — fatal screamer; `screamer.gd` `LEVEL_SCREAMERS[2]` | done |

### level_3_corridor/
| file_name | texture_description | where_used | status |
|-----------|---------------------|------------|--------|
| `level_3_corridor/wall.png` | Victorian hotel wall — peeling damask wallpaper above dark wood wainscoting | Level 3 (The Corridor) — all wall CSGBox3D nodes (triplanar, y-scale −1/3 so wainscot sits at floor) | done |
| `level_3_corridor/carpet.png` | Ornate hotel carpet — dark green/mustard diamond pattern, aged | Level 3 (The Corridor) — floor CSGBox3D nodes + one wall-hung carpet quad in Zone C | done |
| `level_3_corridor/door.png` | Old hotel room door (room 217) on matching wallpaper/wainscot background | Level 3 — superseded as the exit by `backrooms_tear_door.png`, and **re-used 2026-08-17 as the SOURCE for the false room 217**: `tools/make_false_door.py` crops it to the leaf and redraws the number plate. Not referenced directly by any script | done |
| `level_3_corridor/hotel_door_217.png` | The false exit door's leaf — `door.png` cropped to the leaf (492 x 1136 = 0.4331) with its brass **217** plate redrawn 1.55x, crisp, and aged back down. Pillow, deterministic (`tools/make_false_door.py`) | Level 3 — `false_exit_door.gd` at d=185 m. ⚠️ The number IS the trap: nine ordinary doors in this level read 307 and the real exit carries no number at all | done |
| `level_3_corridor/screamer_false_door.png` | **v2, 2026-08-18** — a rotted screaming face lunging out of a black doorway, hands clawing at the frame. flux, then graded by `tools/make_false_door_screamer.py` (vignette + 0.78 exposure + 1.16 gamma + rust cast); raw at `assets_src/textures/level_3_corridor/screamer_false_door_raw.jpg`, v1's raw retired to `assets_src/textures/superseded/` | Level 3 — the false exit door's `flash_scare`. ⚠️ **v1 measured mean luminance 57.97 with 1.97 % of pixels above 0.90 sRGB — 4x the level's own fatal screamer (15.04) and the only screamer in the game with blown-out pixels.** Fullscreen in a renderer with no tonemapping, that is a flashbang. v2 is **mean 11.35, 0.00 % hot, p99 114.4**; `check_corridor_events.gd` asserts the mean against `screamer_hotel.png`'s and asserts a p99 FLOOR so "dark" cannot become a black rectangle (Issue 122). ⚠️ A LUNGE, not a portrait, so it cannot be confused with the fatal `screamer_hotel`/`screamer_corridor`, which must keep meaning "you are dead" | done |
| `level_3_corridor/vesper_note.png` | The entrance note's page — aged, foxed, water-stained hotel stationery, folded in four, lettered `HOTEL VESPER / NIGHT AUDIT` + the first paragraph + the sign-off. **RGBA cutout of the sheet itself.** flux paper + Pillow words (`tools/make_vesper_note.py`); raw at `assets_src/.../vesper_note_paper_raw.jpg` | Level 3 — `corridor.gd:_spawn_intro_note()`, on an art `QuadMesh` over the paper box. ⚠️ Darkened to 0.66 — near-white albedo is the brightest paint this renderer has (Issue 63). ⚠️ The QUAD, not the texture, shipped rotated 180° so the lettering faced back down the corridor at the arriving player — fixed 2026-08-18, Issue 121; the artwork itself is unchanged | done |
| `level_3_corridor/backrooms_tear_door.png` | Room 217 — a black-wood panelled door torn open down its middle, red-lit void and sinew inside. User-supplied, cropped to the architrave (the chroma key could not be used: a dark door on a black ground keys to nothing) | Level 3 (The Corridor) — exit door (room 217), `corridor.gd:_dress_exit_door()`. ⚠️ The player never reaches it — the noclip drops them 5 m short | done |
| `level_3_corridor/ordinary_hotel_door.png` | Plain hotel room door on matching wallpaper/wainscot background | Level 3 (The Corridor) — all non-final doors: 3 fake locked panels (`fake_door.gd`) + 6 decor doors | done |
| `level_3_corridor/clock.png` | Grandfather clock on matching wallpaper/wainscot background | Level 3 (The Corridor) — full-height cursed panel at d=48 m (ScaryObject 1.0, chime event) | done |
| `level_3_corridor/mirror.png` | Ornate oval mirror reflecting a torch-lit corridor, matching background | Level 3 (The Corridor) — side-wall cursed panel(s) (ScaryObject 2.0/2.5) | done |
| `level_3_corridor/mirror_with_creature.png` | Mirror with a creature standing in the reflection | Level 3 (The Corridor) — turn mirrors set flush on the wall you face at the 90 m and 275 m corners (`_spawn_turn_mirror`, `TURN_MIRRORS` — the 230 m one was removed 2026-08-16); gaze panel + proximity `flash_scare()`. ⚠️ Since `MirrorSurface` took over the glass, this texture is used **only** by that `flash_scare()`; the pane itself shows a live reflection | done |
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
| `level_backrooms/backrooms_arrow_glyph.png` | Near-black stencilled arrow on **transparent** background, 768×1024 RGBA, drawn by `tools/make_arrow_decal.py` (seeded, deterministic) | Level 4 (The Backrooms) — quad on each hub arrow column, `ArrowDecalN/E/W`; rotated 180° = the down arrow marking the correct arm. ⚠️ **No background of its own and NO emission** — the post is the background. Measured contrast against the wallpaper post: **89 %** | done |
| ~~`level_backrooms/arrow_decal.png`~~ | ⚠️ **RETIRED 2026-08-17 → `assets_src/textures/superseded/`.** A photograph of yellow wallpaper with a slightly darker arrow on it: **2.2 % glyph-vs-panel contrast**, RGB with no alpha on a `TRANSPARENCY_ALPHA` material, 1.556× stretch, emissive at 0.25 (i.e. lighting its own background). X24's fifth recurrence and the first on a *navigational sign* — Issue 88 | superseded |
| `level_backrooms/screamer_smiler.png` | Glowing wide-toothed smile + unblinking eyes on alpha | Level 4 (The Backrooms) — the Smiler billboard (`creature_smiler.gd`) AND the fatal screamer; `screamer.gd` `LEVEL_SCREAMERS[4]` | done |
| `level_backrooms/backrooms_note.png` | The **face of the entry note** — a damp, fluorescent-yellowed office memo sheet, tide-marked and torn-edged, lettered with the opening paragraph of `backrooms.gd:NOTE_TEXT` verbatim. 466×442 RGBA cutout, `tools/make_backrooms_note.py`: **paper from flux** (raw kept at `assets_src/textures/level_backrooms/backrooms_note_paper_raw.jpg`), **words from Pillow**. ⚠️ **DARKENED ON PURPOSE** — mean luma **98.9/255** against the wallpaper's 171.9, because a near-white page is the brightest paint obtainable in a level with no glow, no fog and light energy ~0.45 (Issue 63's shape). Lettering is wordless pre-printed form furniture + the note's own first paragraph; **no invented letterhead**, this page is signed *"— someone who is still in here"* | Level 4 — `ClueNote`'s `NotePage` `QuadMesh`, sized from this file's own aspect (1.0543), on a dark `NotePad` `BoxMesh` that carries the sheet's edge. Emission via `EMISSION_OP_MULTIPLY` at 0.45. Asserted by `check_backrooms_seam.gd` (quad, pad, MULTIPLY, and darker-than-wallpaper) and `check_art_aspect.gd` | done |

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
| `level_5_kontur/kontur_keycard.png` | KONTUR access card, flat front elevation — Soviet-era institutional card, Cyrillic header, subject number, punched corner, faint bloom | Level 5 — Gate 3's **bait** card on the offering pedestal (`offering_pedestal.gd` `CARD_TEX`), on a quad over the card slab. Should read as desirable — taking it forfeits the run. Art is on **both** faces — the spine is walked from low z, so a single +Z quad is invisible | done |
| `level_5_kontur/screamer_kontur.png` | Face erupting with fungal mycelium, screaming | Level 5 — fatal screamer; `screamer.gd` `LEVEL_SCREAMERS[5]` | done |
| `level_5_kontur/kontur_flash.png` | Spore burst with a half-formed screaming face | Level 5 — the wrong-answer `flash_scare()` on every gate (`kontur.gd:_strike()`) | done |
| `level_5_kontur/kontur_poster.png` | Soviet safety poster, "DO NOT TOUCH INFECTED SURFACES" | Level 5 — decal on the Archive's west wall | done |
| `level_5_kontur/kontur_panel_mailboxes.png` | Battered Soviet mailboxes on matching wallpaper background | Level 5 — **superseded / no longer loaded.** The baked-in wallpaper background meant the prop's own texture depicted the wall behind it, so it always read as a poster taped up rather than an object (playtest capture #4, ISSUES_SOLUTIONS Issue 35). `kontur.gd:_spawn_mailbox()` is now real flat-tinted geometry with no texture, the same resolution `intro/wheelchair_intro.png` got | to_be_added |
| `level_5_kontur/kontur_lock_roster.png` | Corroded personnel-gate lock plate, front elevation — engraved dials/digits (1536x1024, landscape 1.5:1) | Level 5 — the roster gate's recessed plate (`kontur.gd:_spawn_gate5_roster()`), on a `QuadMesh` sized FROM the source aspect and fitted into the bezel recess. ⚠️ Was previously forced onto a 0.3x0.4 portrait quad — a ~2x squash. Carries `emission_energy_multiplier = 0.35` so the gate is findable on a dark wall while the casing itself stays unlit (Issue 27 split) | done |
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
| `screamers/shared_screamer_figure.png` | Gaunt scarred humanoid wraith, front-on, standing — the shared `Apparition`/`LivingMirror` figure | Every level that uses the shared apparition (Lab, House, KONTUR) — `apparition.gd`'s `FIG_BASE` and `living_mirror.gd`'s `FIG_BASE`. ⚠️ Shipped with a **fake checkerboard "transparency" baked into opaque RGB pixels**, not a real alpha channel (`file`/PIL both showed no alpha) — a billboard needs real alpha or it renders as a solid checkered rectangle. Fixed in place with a color-threshold cutout (light/desaturated pixels → alpha 0, eroded 1px + blurred to kill the white fringe) rather than a border-flood-fill, since the gap between the figure's arm and torso is an *enclosed* background pocket, not one connected to the image edge. Also feeds the intro/ending random fallback pool (harmless there — see the `screamer.gd` note below) | done |
| `screamers/shared_screamer.png` | Close-up screaming face, mouth open, same figure as `shared_screamer_figure.png` — the apparition's rush/fatal look | `apparition.gd`'s `RUSH_BASE`, shown in `Apparition._rush()`'s teach-branch `flash_scare()`. Fullscreen overlay (no alpha needed) — also plain RGB but that's fine for this use | done |

### shared/
| file_name | texture_description | where_used | status |
|-----------|---------------------|------------|--------|
| `shared/note_paper.png` | Aged cream paper — faint ruled lines, slight yellowing at edges | All notes (`note.gd` base material for both safe and trap notes) | done |
| `shared/rusted_iron.png` | Corroded iron surface grain, seamless | `beartrap.gd:_metal_material()`; also the sconce brackets in THE NIGHTMARE (`wall_sconce.gd` `IRON_TEX`) — GRAIN only, never a picture of a sconce | done |
| `shared/beartrap_plate.png` | Corroded iron pressure plate, circular wear | `beartrap.gd:_metal_material()` | done |

### level_6_breach/  (Level 6 — THE BREACH)
| file_name | texture_description | where_used | status |
|-----------|---------------------|------------|--------|
| `level_6_breach/breach_wall_ruptured.png` | Facility wall torn open, structural rupture, exposed rebar; seamless | Level 6 — `RUPTURED_ROOMS` wall skin (`level_6_breach.gd:_rooms_with_skins()`) | done |
| `level_6_breach/breach_wall_organic.png` | Wall overtaken by organic growth, wet membrane; seamless | Level 6 — `ORGANIC_ROOMS` wall skin | done |
| `level_6_breach/breach_floor_scorched.png` | Scorched, blistered floor; seamless | Level 6 — organic-room floors | done |
| `level_6_breach/breach_incinerator_wall.png` | Charred, blood-slicked masonry, value ≤ 0.25; seamless | Level 6 — the Incinerator skin. **Also THE NIGHTMARE's deepest wall tier** (`dungeon.gd:_rooms_with_skins()`), which is why `dungeon_wall_ash` was never generated — this file already matches that brief exactly | done |
| `level_6_breach/hiding_locker_front.png` | Steel locker front elevation | `hiding_spot.gd` (`prop_kind = "locker"`) | done |
| `level_6_breach/hiding_cabinet_front.png` | Cabinet front elevation (RGBA) | `hiding_spot.gd` (`prop_kind = "cabinet"`) — also THE NIGHTMARE's two hiding spots | done |
| `level_6_breach/hiding_desk_front.png` | Desk front elevation | `hiding_spot.gd` (`prop_kind = "desk"`) | done |
| `level_6_breach/object12_sign.png` | Facility warning sign plate | Level 6 — `_make_sign()` | done |
| `level_6_breach/level_6_jumpscare.jpg` | Level 6 fatal screamer (user-supplied; genuinely JPEG, hence the honest `.jpg`) | `screamer.gd` `LEVEL_SCREAMERS[6]` | done |
| `level_6_breach/screamer_breach.png` | Superseded generated screamer | Replaced by `level_6_jumpscare.jpg` | to_be_added |

### level_9_dungeon/  (Level 7 — THE NIGHTMARE)
⚠️ The folder number is the level's **identity** in the eventual 12-level order, not
its current index — it is level 7 today. Asset folder names already drift from level
numbers (`level_4_void/` holds level 8's art) and must not be renamed: it would break
every `.import` UID.

⚠️ **Everything generated for this level arrived as JPEG-in-a-`.png` and has no alpha
channel** — see ISSUES_SOLUTIONS Issue 42. All were re-encoded with `sips`. The only
two files here with real transparency are the two the user supplied.

| file_name | texture_description | where_used | status |
|-----------|---------------------|------------|--------|
| `level_9_dungeon/dungeon_wall_stone.png` | Damp grey castle stone blocks, dark mortar, black damp patches; seamless, value ≤ 0.30 | Level 7 — the base wall skin (`dungeon.gd:_build_geometry()`) | done |
| `level_9_dungeon/dungeon_floor.png` | Worn uneven flagstones, cracked, wet joints; seamless | Level 7 — all floors | done |
| `level_9_dungeon/dungeon_ceiling.png` | Rough vaulted stone from below, darker than the walls; seamless | Level 7 — all ceilings, and the corridor drop-ceilings (Issue 41) | done |
| `level_9_dungeon/dungeon_wall_brick.png` | Dark brown-red brick, crumbling mossy mortar; seamless | Level 7 — the middle wall tier, 4+ rooms from spawn | done |
| `level_9_dungeon/dungeon_door.png` | Heavy banded oak door, iron straps and studs, front elevation | Level 7 — both level doors via `Door.build_visual()` | done |
| `level_9_dungeon/dungeon_pillar.png` | Rough stone column, vertically tileable | Level 7 — **not currently loaded**; generated as a NICE-to-have for future chamber pillars | to_be_added |
| `level_9_dungeon/dungeon_grate.png` | Rusted iron grating, crossed bars | Level 7 — the sealed alcove's grate (`dungeon.gd:_build_grate()`). ⚠️ Opaque: the gaps could not be transparent (Issue 42), so it is a panel set into the wall and the teaching silhouette is drawn AT it | done |
| `level_9_dungeon/dn_cot.png` | Iron camp cot with stained mattress, seen from above (user-supplied) | Level 7 — the Antechamber cot and the bed (`dungeon_cot.gd`), on a flat quad sized to the FRAME. ⚠️ No emission: at 0.22 it rendered as a blown-out white slab (Issue 21) | done |
| `level_9_dungeon/dn_sconce.png` | Wrought-iron wall sconce, unlit (user-supplied) | **Superseded.** `wall_sconce.gd` is real geometry now — the art has its own pale background baked in and rendered as a framed picture bolted to the wall (Issue 35) | to_be_added |
| `level_9_dungeon/dn_sconce_lit.png` | The same sconce, burning | **Superseded** for the same reason | to_be_added |
| `level_9_dungeon/dn_hollow_figure.png` | Small child-shaped shadow with two dull red eye points; **real RGBA cutout**, alpha extrema (0, 255) (user-supplied) | Level 7 — the Hollow One's spark-reveal billboard (`creature_hollow.gd`), the Child (`dn_child.gd`) and the Kneeling Man (`kneeling_man.gd`), each tinted differently. ⚠️ Must stay a real cutout or it billboards as a solid rectangle | done |
| `level_9_dungeon/dn_tally_wall.png` | Gouged tally strokes; **real RGBA cutout** (user-supplied) | Level 7 — the Antechamber wall beside the scrawl | done |
| `level_9_dungeon/dn_note.png` | Aged handwritten diary page (user-supplied) | Level 7 — **not currently loaded**; notes use `shared/note_paper.png` via `note.gd:paper_material()` | to_be_added |
| `level_9_dungeon/dn_child_smear.png` | Wet blood handprint and drag smear across glass | Level 7 — the Child's sprint-past `flash_scare()`. Opaque, which is fine: a `flash_scare` payload is a FULLSCREEN overlay and needs no alpha (the `shared_screamer.png` precedent) | done |
| `level_9_dungeon/painting_matron.png` | Antique portrait, burned woman, elongated neck, eyes CLOSED, blood from the frame | Level 7 — the Weeping Frames' resting state (`weeping_frame.gd`) | done |
| `level_9_dungeon/painting_matron_open.png` | The same portrait with the eyes wide open and the canvas smouldering | Level 7 — the 5-sconce kill-state swap, shown during the ignition wind-up. ⚠️ Ignition emission is capped at 0.9 (Issue 21) | done |
| `level_9_dungeon/painting_witness.png` | Antique portrait, half-flesh half-skull figure in an explorer's coat | Level 7 — the second Weeping Frame variant | done |
| `level_9_dungeon/dn_stillone_face.png` | Fleshless skull, dried skin, jaw open, harsh underlight | Level 7 — **not currently loaded**; generated as a NICE-to-have `flash_scare` payload | to_be_added |
| `level_9_dungeon/screamer_dungeon.png` | Charred screaming woman lunging out of black | Level 7 — fatal screamer, `screamer.gd` `LEVEL_SCREAMERS[7]`. ⚠️ Lives HERE, not in `screamers/` — that folder is auto-scanned as the intro/ending fallback pool only | done |

### ui/
| file_name | texture_description | where_used | status |
|-----------|---------------------|------------|--------|
| `ui/main_menu_bg.png` | Dark atmospheric corridor silhouette — deep shadows, minimal detail | Main menu scene (`main_menu.gd` background image) | done |

## Notes

### ⚠️ Integrity rules — check these before blaming the art (Session 15)
Three separate "the texture looks wrong" reports turned out to be code or file problems, not art.
Check in this order:

1. **Is the file actually the format its extension claims?**
   ```bash
   file game/assets/textures/<path>.png     # must say "PNG image data"
   ```
   The Gemini/nano-banana pipeline returns **JPEG data even when the filename ends in `.png`**.
   Godot imports it with `valid=false` and produces no `.ctex`, so `load()` fails — but
   **`ResourceLoader.exists()` still returns `true`**, so the usual guard passes and the prop renders
   blank with no visible error (`lab_monitor_face.png`; Issues 1 and 25). Fix with
   `sips -s format png <path> --out <path>`, then delete the stale `.import` **and** the
   `game/.godot/imported/<name>-*` entries before re-importing, or the bad import is cached.
   A giveaway: the bad file is often far smaller than its siblings (287 KB vs ~3 MB).
2. **Watch for a doubled extension.** `lab_light_fitting.png.png` silently did nothing — the guard
   looked for `lab_light_fitting.png`, which did not exist.
3. **Is the art on a `QuadMesh`?** A `BoxMesh` does not map a whole texture onto each face, so a
   textured box renders a **magnified crop** of its own art — the exit doors showed one hinge and no
   window while the tray and monitor beside them, on quads with the same material, were fine
   (Issue 24). Use `door.gd:build_visual()` as the pattern: box for edge and depth, quad for art.
4. **Is it a wall decal placed with `wall_point()`?** Use `inset ≥ 0.16`, or **0.22** if anything
   hangs behind it. At 0.10 the prop is exactly on the wall face and the wall texture z-fights
   through the art, slicing it apart (Issue 26).
5. **Is the emission below 1.0?** No tonemapping and no glow anywhere in the project, so anything
   above 1.0 clamps to flat pure white, and on a dark level emission outweighs albedo — a red-tinted
   emissive door washed to salmon pink (Issue 21).

For a full symptom → cause table see the playbook at the top of `ISSUES_SOLUTIONS.md`.

### Flat-elevation prompt convention for prop textures
Prop art (doors, shutters, panels, trays, fittings) is generated as a **flat orthographic elevation,
filling the frame edge to edge, evenly lit, no cast shadows, no perspective, no background around the
object**. That is what lets it sit on a quad and read as the object rather than as a photo of one.
The Session-15 batch (`lab_door`, `house_door`, `lab_morgue_shutter`, `lab_surgical_tray`,
`lab_monitor_face`, `lab_light_fitting`) all use this wording — reuse it for new props.

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
`note_paper.png` had **zero references project-wide** until Session 15 — every note in the game was a
flat near-black emissive box, because `note.gd`'s `_style_mesh()` was commented out. It is now the
live path: `note.gd:paper_material(trap)` is the single source of a note's material and is used both
by `_ready()` (scene-placed notes) and by `level_1.gd`/`level_2.gd`'s `_make_note()` (procedural
ones). The emission is kept alongside the texture — albedo carries the paper, emission is what makes
a sheet findable in these dark levels.

### Procedural (untextured) Level 2 props — candidates for future textures
The pressure package builds several props in `level_2.gd` from plain `StandardMaterial3D` colors, no texture files: the living-room **window** frame (dark glass + wooden crossbars — note the pane now shows `forest.png` behind it) and the **tarnished mirror** (dark metallic quad). If texture budget allows, a `mirror_house.png` would upgrade the mirror — add a row above when generated. (The old window-glimpse silhouette capsule was removed; only the Forest scare remains at the window.)

### Session 11 — most expansion textures now wired
The Session-10 surface/decal batch was wired in Session 11 via `RoomBuilder`'s new per-room
`wall_mat`/`floor_mat` overrides (`level_*.gd:_rooms_with_skins()`) plus `_spawn_room_props()` and
the `Breaker`/cellar-ramp builders: `lab_morgue_wall`, `lab_floor_wet`, `lab_breaker_panel`,
`lab_warning_sign`, `house_kitchen_wall`, `house_bathroom_tile`, `house_wood_stairs`, `child_drawing`,
and the `tv_static_face` path fix are all live now. **Both former `requires_review` entries were
resolved in Session 15:** `lab_oneway_mirror` is wired into `living_mirror.gd`, and `blood_lab` was
confirmed dead (its scene node was being freed on load) and removed from `level_1.tscn`.

### ⚠️ The shared apparition figure must be a transparent PNG
`apparition.gd` and `living_mirror.gd` both billboard `screamers/shared_screamer_figure.png` (moved
from `level_1_lab/apparition_figure.png` — see that row). A `.jpg`, or a PNG with no alpha *channel*,
renders the cutout as a solid rectangle; `Apparition._resolve_tex()` prefers `.png` over `.jpg` but
that only helps if the `.png` actually has alpha. **A checkerboard pattern visible in an image
preview is not proof of real transparency** — an AI image generator asked for "transparent
background" can paint a fake checkerboard onto opaque RGB pixels instead of setting alpha. Verify
with PIL (`Image.open(path).mode` should include `'A'`, and `getchannel('A').getextrema()` should
NOT be `(255, 255)`), not by eyeballing the Read-tool preview — that renders real transparency the
same checkered way. Note this is a *different* failure from Integrity rule 1 above: there the file
is JPEG **data** wearing a `.png` name, which fails to load at all rather than losing its alpha.

### Draft textures
`level_1_lab/draft/`, `level_2_house/draft/` hold earlier/lower-quality versions (`wall_lab`, `floor_lab`, `wall_house`, etc.) kept for reference; the live textures are the `*_wall.png` / `*_floor.png` files in the parent folders. Not referenced by any script.
