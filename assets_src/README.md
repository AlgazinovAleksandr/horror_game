# assets_src — unprocessed originals

Source assets exactly as they were supplied, before any processing. **Nothing here is loaded
by the game.** The files the game actually uses live under `game/assets/`, and every one of
them is generated from something in this folder by a tool in `tools/`.

## ⚠️ Why this folder exists, and why it is tracked

The processing tools are **destructive and not idempotent**. `tools/restencil_door.py` says so
in its own header — *"Idempotent it is NOT. Run it once, on a copy."* It crops the image and
paints over the sign; running it twice crops the crop. `tools/make_loop.py` trims a fade-out
and crossfades the seam; running it on its own output trims again.

So the processed file in `game/assets/` **cannot be used to regenerate itself**. If these
originals are lost, the pipelines cannot be re-run at all — you could not change the door's
sign text, re-cut the loop at a different length, or redo a crop. That is why they are in git
rather than gitignored, and it is the whole justification for the 11 MB.

## ⚠️ Why it is OUTSIDE `game/`

Godot scans and imports **everything** under the project directory. Raw sources kept inside
`game/` would be imported as duplicate assets — extra `.import` files, extra `.godot/imported`
data, and a second copy of every byte in the exported build. Keeping them out of `game/` means
the engine never sees them.

## Layout

Mirrors the destination path, so it is obvious what each source becomes:

| Source | Becomes | Made by |
|---|---|---|
| `audio/level_2_house/chase.wav` | `game/assets/audio/level_2_house/chase.wav` | `tools/make_loop.py` |
| `textures/intro/door_from_intro_to_lab.png` | `game/assets/textures/intro/intro_lab_door.png` | `cutout_alpha.py` → `restencil_door.py` |
| `textures/level_3_corridor/door_from_corridor_to_backrooms.png` | `game/assets/textures/level_3_corridor/backrooms_tear_door.png` | manual crop (see below) |
| `video/intro_scene.mp4` | `game/assets/video/intro_scene.ogv` | `ffmpeg` (see below) |
| `video/fall_scene.mp4` | `game/assets/video/fall_scene.ogv` | `ffmpeg` (see below) |

## Regenerating

⚠️ Every command writes to a **copy** in `game/assets/`. Never run a tool against a file in
this folder — that would destroy the original, which is the one thing this folder is for.

```bash
# The House chase track: trims the fade-out, crossfades the seam into a clean loop.
# Measured on the supplied file: seam gap 10.2 dB -> 0.7 dB.
python3 tools/make_loop.py \
    assets_src/audio/level_2_house/chase.wav \
    game/assets/audio/level_2_house/chase.wav

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
path before processing it, and add a row to the table above. `TEXTURES.md` records what each
shipped texture *is*; this folder records where it *came from*.
