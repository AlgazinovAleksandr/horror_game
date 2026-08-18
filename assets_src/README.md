# assets_src — unprocessed originals

Source assets exactly as they were supplied, before any processing. **Nothing here is loaded
by the game.** The files the game actually uses live under `game/assets/`.

⚠️ The reverse is **not** true and this file used to claim it was: not every shipped asset comes
from here. Most of the SFX are generated from nothing by the `tools/make_sfx*.py` synths, the
Backrooms arrow is *drawn* by `tools/make_arrow_decal.py`, and a few supplied files
(`intro/wheelchair.wav`) ship byte-for-byte with no processing step and therefore no original to
keep. This folder holds the originals of the assets that **were** processed.

## ⚠️ Why this folder exists

The processing tools are **destructive and not idempotent**. `tools/restencil_door.py` says so
in its own header — *"Idempotent it is NOT. Run it once, on a copy."* It crops the image and
paints over the sign; running it twice crops the crop. `tools/make_loop.py` trims a fade-out
and crossfades the seam; running it on its own output trims again.

So the processed file in `game/assets/` **cannot be used to regenerate itself**. If these
originals are lost, the pipelines cannot be re-run at all — you could not change the door's
sign text, re-cut the loop at a different length, or redo a crop. On top of that the
generations are **stochastic**: `VIDEO_PROMPTS.md` records every prompt, but re-running one
produces a different clip, so a lost original is lost for good.

## ⚠️ Only PART of this folder is committed (2026-08-19)

Nothing here is loaded by the game — verified, not assumed: every `assets_src` mention inside
`game/` is a comment pointing at this file (`cutscene_player.gd:18`, `dungeon.gd:1333`,
`main_menu.gd:18`), never a `load()` and never a path constant. So the tracking rule is not
"is it precious" but **"does an automated step read it"**:

| Committed because it is an INPUT | Read by |
|---|---|
| `audio/level_2_house/chase.wav` | `tools/make_loop.py` |
| `textures/intro/door_from_intro_to_lab.png` | `cutout_alpha.py` → `restencil_door.py` |
| `textures/level_3_corridor/door_from_corridor_to_backrooms.png` | manual crop, recorded below |
| `textures/level_3_corridor/vesper_note_paper_raw.jpg` | `tools/make_vesper_note.py:48` |
| `textures/level_3_corridor/screamer_false_door_raw.jpg` | `tools/make_false_door_screamer.py:65` |
| `textures/level_backrooms/backrooms_note_paper_raw.jpg` | `tools/make_backrooms_note.py:61` |
| `textures/level_1_lab/lab_breaker_panel_raw.png` | `tools/flatten_alpha_checker.py` (⚠️ and `game/tests/check_nook_dark.gd:218` documents re-proving its checkerboard limits by restoring this file and re-running — a manual procedure, not something the test loads, but it needs the file to exist) |

Those three `make_*.py` scripts **hard-code their `SRC` path into this folder**, so gitignoring
them would break the generators on a fresh clone with a `FileNotFoundError`. Everything else is
local-only: still irreplaceable, but nothing automated needs it, and it does not belong in a
repo other people clone. The `.gitignore` block carries the same table.

⚠️ **An ignore pattern does not apply to a file git already tracks**, so untracking one takes an
explicit `git rm --cached`. That is how **all five video originals** ended up local-only:
`fall_scene.mp4` and `intro_scene.mp4` were committed for a while and were removed on
2026-08-19. ⚠️ That was a decision about what the repo *contains*, **not** about its size —
`git rm --cached` reclaims nothing, because the blobs stay in history permanently (which is why
`.git` is already 854 MB). Only a history rewrite changes that number.

⚠️ **The videos are therefore reconstructable from nothing.** The five `.mp4` originals are
local-only, and `VIDEO_PROMPTS.md` — the only record of the prompts that produced them — is
gitignored too. A fresh clone has the finished `.ogv` and no way to re-cut, re-fade or re-attempt
any of them. That is deliberate for a public repo; it is written down here because it is the one
place in this folder where "local-only" means genuinely unrecoverable rather than merely
inconvenient.

## ⚠️ Why it is OUTSIDE `game/`

Godot scans and imports **everything** under the project directory. Raw sources kept inside
`game/` would be imported as duplicate assets — extra `.import` files, extra `.godot/imported`
data, and a second copy of every byte in the exported build. Keeping them out of `game/` means
the engine never sees them.

## Layout

Mirrors the destination path, so it is obvious what each source becomes:

`git` is **yes** where an automated step reads the file (see the section above), **local** otherwise.

| Source | Becomes | Made by | git |
|---|---|---|---|
| `audio/level_1_lab/metal_creak.flac` | `game/assets/audio/level_1_lab/metal_creak.ogg` | `ffmpeg` (see below) | local |
| `audio/level_2_house/chase.wav` | `game/assets/audio/level_2_house/chase.wav` | `tools/make_loop.py` | **yes** |
| `audio/level_2_house/music_box_source.flac` | `game/assets/audio/level_2_house/music_box_tune.ogg` | `ffmpeg` (see below) | local |
| `audio/level_2_house/music_box_generated_pre2026-08-16.wav` | *superseded* `music_box.wav` | — | local |
| `reference/monster_model.png` | *nothing — design input, see below* | — | local |
| `textures/intro/door_from_intro_to_lab.png` | `game/assets/textures/intro/intro_lab_door.png` | `cutout_alpha.py` → `restencil_door.py` | **yes** |
| `textures/intro/gurney_intro_pre2026-08-16.png` | *superseded* `gurney_intro.png` | — | local |
| `textures/level_1_lab/lab_breaker_panel_raw.png` | `game/assets/textures/level_1_lab/lab_breaker_panel.png` | `tools/flatten_alpha_checker.py` | **yes** |
| `textures/level_3_corridor/door_from_corridor_to_backrooms.png` | `game/assets/textures/level_3_corridor/backrooms_tear_door.png` | manual crop (see below) | **yes** |
| `textures/level_3_corridor/corridor_mirror_figure_raw.jpg` | `game/assets/textures/level_3_corridor/corridor_mirror_figure.png` | `tools/cutout_alpha.py --green` | local |
| `textures/level_3_corridor/screamer_false_door_raw.jpg` | `game/assets/textures/level_3_corridor/screamer_false_door.png` | `tools/make_false_door_screamer.py` | **yes** |
| `textures/level_3_corridor/vesper_note_paper_raw.jpg` | `game/assets/textures/level_3_corridor/vesper_note.png` | `tools/make_vesper_note.py` | **yes** |
| `textures/level_backrooms/backrooms_note_paper_raw.jpg` | `game/assets/textures/level_backrooms/backrooms_note.png` | `tools/make_backrooms_note.py` | **yes** |
| `textures/level_backrooms/sprawl_dweller_raw.jpg` | `game/assets/textures/level_backrooms/sprawl_dweller.png` | `tools/cutout_alpha.py` | local |
| `textures/level_backrooms/sprawl_dweller_face_raw.jpg` | `game/assets/textures/level_backrooms/sprawl_dweller_face.png` | `tools/cutout_alpha.py` | local |
| `video/intro_scene.mp4` | `game/assets/video/intro_scene.ogv` | `ffmpeg` (see below) | local |
| `video/fall_scene.mp4` | `game/assets/video/fall_scene.ogv` | `ffmpeg` (see below) | local |
| `video/menu_loop.mp4` | `game/assets/video/menu_loop.ogv` | `ffmpeg` (see below) | local |
| `video/ending_scene.mp4` | `game/assets/video/ending_scene.ogv` | `ffmpeg` (see below) | local |
| `video/dungeon_wake.mp4` | `game/assets/video/dungeon_wake.ogv` | `ffmpeg` (see below) | local |
| `video/seeds/*.png` | *nothing — Veo conditioning frames, `VIDEO_PROMPTS.md` §2* | — | local |

## Regenerating

⚠️ Every command writes to a **copy** in `game/assets/`. Never run a tool against a file in
this folder — that would destroy the original, which is the one thing this folder is for.

```bash
# The House chase track: trims the fade-out, crossfades the seam into a clean loop.
# Measured on the supplied file: seam gap 10.2 dB -> 0.7 dB.
python3 tools/make_loop.py \
    assets_src/audio/level_2_house/chase.wav \
    game/assets/audio/level_2_house/chase.wav

# The two supplied FLACs -> Ogg Vorbis. Straight transcodes: no trim, no gain, no loop work.
# ⚠️ The original commands were never recorded, so these were RECONSTRUCTED from the shipped
# files' own measured parameters (ffprobe): metal_creak.ogg is 44.1 kHz stereo, 3.134694 s —
# bit-for-bit the source duration — at 164 kbps, which is Vorbis `-q:a 5`. Re-running these
# will not reproduce the existing bytes (Vorbis is not deterministic across encoder builds),
# but it reproduces the format, and nothing downstream depends on the exact bitstream.
ffmpeg -i assets_src/audio/level_1_lab/metal_creak.flac \
    -c:a libvorbis -q:a 5 game/assets/audio/level_1_lab/metal_creak.ogg -y
ffmpeg -i assets_src/audio/level_2_house/music_box_source.flac \
    -c:a libvorbis -q:a 5 game/assets/audio/level_2_house/music_box_tune.ogg -y

# The Intro -> Lab door. Two stages, in this order, and both need Pillow.
cp assets_src/textures/intro/door_from_intro_to_lab.png \
   game/assets/textures/intro/intro_lab_door.png
nano-banana-pro/.venv/bin/python3 tools/cutout_alpha.py \
    game/assets/textures/intro/intro_lab_door.png --chroma auto --no-despill
nano-banana-pro/.venv/bin/python3 tools/restencil_door.py \
    game/assets/textures/intro/intro_lab_door.png

# The Corridor -> Backrooms door. ⚠️ NOT cutout_alpha.py: this is a DARK door on a BLACK
# ground, so a chroma key erases the door itself (it was tried — the result was a faint
# outline). Cropped to the architrave instead, opaque RGB:
#   crop box (122, 31) -> (896, 1489) of the 1024x1536 original = 774x1458, aspect 1:1.884
# corridor.gd sizes its quad from that aspect, so re-cropping means updating _dress_exit_door.

# The two cutscenes (generated video, supplied as watermarked 1280x720 H.264 mp4).
# One command does three things, and all three are required:
#
#   delogo      removes the generator's sparkle watermark. The box is the watermark's
#               bounding rect + a few px of margin; it is STATIC in both clips, and delogo
#               interpolates the patch from the border, which is clean here because that
#               corner is near-black in one clip and flat plaster in the other.
#   libtheora   ⚠️ NOT optional. Godot 4's VideoStreamPlayer decodes Ogg Theora and nothing
#               else — an .mp4 will not play and will not import.
#   volume      -12 dB. The clips are generated at ~0 dBFS peak, far above this game's mix.
for n in intro fall; do
  ffmpeg -i assets_src/video/${n}_scene.mp4 \
      -vf "delogo=x=1132:y=569:w=56:h=62" \
      -c:v libtheora -q:v 8 \
      -af "volume=-12dB" -c:a libvorbis -q:a 4 \
      game/assets/video/${n}_scene.ogv -y
done

# ── The three Veo clips (2026-08-17) ───────────────────────────────────────────────────
# ⚠️ THE DELOGO BOX ABOVE IS UNCHANGED, AND THAT WAS MEASURED, NOT ASSUMED. VIDEO_PROMPTS.md
# §5.1 warned that Veo's watermark "sits elsewhere and may be a different size" and made
# re-measuring a prerequisite. It was re-measured — threshold the min brightness across three
# UNRELATED clips, which isolates the only thing they have in common — and Veo's sparkle
# occupies x 1137..1183, y 577..623 (47x47), static on every frame of all three. The box
# recorded above contains that with >=5 px of margin on all four sides. Do not re-derive it.
# Verified after encoding as CONTRAST, never as an absolute level: in each finished .ogv the
# patch's brightest pixel is now DIMMER than the brightest pixel of the ring of wall around it.

# menu_loop — the main menu background. Silent, full width, and PALINDROMED (forward then
# reversed), which is what makes VideoStreamPlayer.loop seamless: the last frame is the first
# frame, so the rejoin has nothing to match. 10 s in, 20 s out.
# ⚠️ q:v 8, not VIDEO_PROMPTS.md recipe B's 6. Recipe B's 6 assumes `scale=512`; this one keeps
#    its full 1280 AND is seen through main_menu.gd's 78%-opaque overlay, which compresses the
#    visible range — exactly where Theora blocking in dark gradients would show.
ffmpeg -i assets_src/video/menu_loop.mp4 \
    -filter_complex "[0:v]delogo=x=1132:y=569:w=56:h=62,split[a][b];[b]reverse[r];[a][r]concat=n=2:v=1[v]" \
    -map "[v]" -c:v libtheora -q:v 8 -an game/assets/video/menu_loop.ogv -y

# ending_scene — the twist ending's reveal, played by intro_room.gd:_on_ending_note_closed()
# with Screamer.trigger_to_menu() firing the instant it ends.
# ⚠️ `tpad` is load-bearing: the clip's own black tail measured only 0.70 s (it reaches
#    YAVG 16.1 — limited-range black — at t=9.3 of 10.0), against the ~2 s the screamer needs
#    somewhere to land in.
# ⚠️ IT BUYS LESS THAN THE ARITHMETIC SAYS, AND THIS IS THE PART WORTH KNOWING. The 31 cloned
#    frames are IDENTICAL and Theora run-length-codes duplicates, so the output decodes as 240
#    frames whose LAST pts is 10.375 while the CONTAINER reports 10.875. Godot stops at the last
#    decoded frame, not at the container duration — so the black actually on screen is
#    9.42 -> 10.375 = **0.96 s**, not the file's nominal 1.46 s. Measured in-engine by
#    game/tests/screenshot_ending_cutscene.gd, which keys its samples to
#    VideoStreamPlayer.get_stream_position() for exactly this reason.
#    That is enough — the requirement is "do not end on a lit frame" — but do NOT compute a
#    playback duration from `ffprobe` on a file with a padded tail. Forcing `-fps_mode cfr` was
#    tried and changes nothing; the collapse happens inside libtheora.
ffmpeg -i assets_src/video/ending_scene.mp4 \
    -vf "delogo=x=1132:y=569:w=56:h=62,tpad=stop_mode=clone:stop_duration=1.3" \
    -c:v libtheora -q:v 8 -af "volume=-12dB" -c:a libvorbis -q:a 4 \
    game/assets/video/ending_scene.ogv -y

# dungeon_wake — the crane up into THE NIGHTMARE's Antechamber, played on waking only.
# ⚠️ BOTH fades are load-bearing, and the raw clip has NEITHER — it opens lit and ends lit.
#   fade IN   the clip is supposed to rise out of darkness and does not: measured, YAVG 31 at
#             t=0 and 56 by t=0.5. It cuts from dungeon.gd's 1.6 s fade-to-black, so without
#             this it snaps from black straight to a lit room. This is exactly the fallback
#             VIDEO_PROMPTS.md §2's dungeon_wake entry specced, and it was in fact needed.
#   fade OUT  ⚠️ THE ONE THAT WAS NOT PREDICTED. The clip ends on a warm firelit stone room and
#             the live Antechamber it hands over to is near black — this level runs at ambient
#             0.045 with no flashlight and an unlit candle. Measured across the join by
#             game/tests/screenshot_wake_cutscene.gd: 0.171 mean luminance against 0.008, a 21x
#             snap. Fading to black lets it hand over ON BLACK, where dungeon.gd's own black
#             ColorRect is already sitting, and the level fades up from there.
#             The generator lights an interior like a film set; this game does not.
# The audio fades with the picture at both ends, or the fire crackle arrives at full level over
# a black frame and then stops dead.
ffmpeg -i assets_src/video/dungeon_wake.mp4 \
    -vf "delogo=x=1132:y=569:w=56:h=62,fade=t=in:st=0:d=0.7,fade=t=out:st=9.0:d=1.0" \
    -c:v libtheora -q:v 8 \
    -af "volume=-12dB,afade=t=in:st=0:d=0.7,afade=t=out:st=9.0:d=1.0" -c:a libvorbis -q:a 4 \
    game/assets/video/dungeon_wake.ogv -y
```

⚠️ **Checking the result: decode sequentially, never with `-ss`.** Seeking into a Theora file
lands mid-GOP and decodes garbage — spot-checking these with `ffmpeg -ss 6 -i out.ogv` produced
a lurid green band across the bottom of the frame that **is not in the file**. Use
`-vf "select=eq(n\,144)" -vsync 0` to pull a numbered frame, or decode the whole clip and scan
it. A scan of all 240 frames of each clip found zero corrupt frames.

Then re-import so Godot picks the new files up:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import
```

## Adding to this folder

When a new supplied asset arrives, put the untouched original here under its destination's
path before processing it, and add a row to the table above — **including the `git` column**,
which is decided by the rule at the top: does an automated step read this file? `TEXTURES.md`
records what each shipped texture *is*; this folder records where it *came from*.

⚠️ That rule was ignored for about a dozen files before 2026-08-19 — they were dropped in
correctly and never given a row, so the folder grew to 39 MB with an 8-row table describing it.
If you add something here, add the row in the same commit.

## `reference/`

Design input that informs an asset **without being processed into one**. Nothing here has a
destination, no tool reads it, and it is local-only.

| File | What it is |
|---|---|
| `monster_model.png` | Full-body character reference for the planned replacement creature — front orthographic, 1024×1536, opaque RGB on flat grey. See `backlogs/00-cross-level.md` **X61**: `Void_creature.glb` stands in a T-pose in both KONTUR and THE BREACH, and the decision (2026-08-18) is to **replace the asset rather than pose it**, so no rigging work should be spent on the current GLB. When the new model lands it must carry **no embedded textures** and **no `AnimationPlayer`**, and both levels must keep using **one** asset — meeting the creature behind glass in KONTUR and being hunted by it in THE BREACH have to read as the same thing |

⚠️ This is **not** a texture and must not be treated as one: it has no alpha, so billboarding it
would render a grey rectangle (the `apparition_figure.jpg` bug). Turning it into a cutout would
need a `tools/cutout_alpha.py` pass and a row in the Layout table above.

## `textures/superseded/`

Shipped assets that were **replaced rather than edited**, kept out of `game/` so Godot never
imports them and their `.import`/`.uid` siblings cannot go stale (`CLAUDE.md`: delete an
asset, delete its siblings — four orphans had accumulated once already).

| File | Was | Why it was retired |
|---|---|---|
| `backrooms_arrow_decal_superseded.png` | `game/assets/textures/level_backrooms/arrow_decal.png` | The Backrooms' only navigational sign, and a picture of **yellow wallpaper with a slightly darker arrow on it**: 2.2 % glyph-vs-panel contrast measured from real frames, RGB with no alpha on a `TRANSPARENCY_ALPHA` material, 1.556× stretch, emissive at 0.25. Replaced by `backrooms_arrow_glyph.png`, drawn by `tools/make_arrow_decal.py`. ISSUES_SOLUTIONS Issue 88, cross-level X24/X38 |

⚠️ A retired file is kept, not deleted: several of this project's pipelines are destructive and
the shipped file cannot regenerate itself. But it must live **here**, never in `game/`.
