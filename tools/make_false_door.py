#!/usr/bin/env python3
"""THE FALSE ROOM 217 — the leaf art for the Corridor's fake exit door.

    <pack>/.venv/bin/python3 tools/make_false_door.py
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import

WHY THIS ART AND NOT A NEW GENERATION
-------------------------------------
The user's brief was *"it would look like the image I generated for the exit and it would
have the correct number - the one the player thinks leads to the exit."*

That image already exists and is **currently unused**: `door.png` (1024x1536) is the original
room-217 exit door — dark panelled wood with a brass plate reading a legible **217** — which
stopped being the exit when d=320 was re-dressed with `backrooms_tear_door.png` (a door torn
open on a red-lit void). So the level's own history hands us exactly the right asset, and
nothing has to be generated at all.

⚠️ THIS IS ALSO THE ANSWER TO "WHICH DOOR WOULD THE PLAYER EXPECT 217 TO LOOK LIKE".
Established before drawing anything:
  * every ordinary door in the level wears `hotel_door_leaf.png`, cropped from
    `ordinary_hotel_door.png` — dark panelled wood with a brass number plate reading **307**;
  * the real 217 at d=320 wears the TORN door, and **the player has never seen it** when they
    meet the fake, because there is only one of it and it is the last thing in the level;
  * so the door vocabulary in the player's head at that moment is "dark wood, brass plate,
    three digits". `door.png` is in that vocabulary — same generation family, same palette,
    same plate at the same height — and it differs in the one respect that matters.
  * ⚠️ AND THE NUMBER IS NOWHERE ELSE. `217` appears in the objective line ("Find room 217"),
    in the entrance note, and on **no prop in the level**: the real exit's artwork carries no
    number at all. The first legible 217 a player ever sees is therefore this one, on the
    fake. That is reported rather than fixed — it makes the trap land, and changing the real
    exit's art is not this pass's call.

WHAT IS DRAWN
-------------
Only the number plate, and only because it is the payload. The original plate is legible at
2 m and unreadable at 5, so it is redrawn **1.55x larger** and crisp, in the same aged brass
sampled from the source (highlight 226,184,105 / mid 186,137,69), covering the old one
completely. Everything else in the image is the untouched photograph.

⚠️ Pillow, deterministic, no diffusion model. Flux cannot letter a sign, and here the text IS
the trap: a malformed "2l7" reads as an ordinary hotel door and the beat never happens.

⚠️ NON-DESTRUCTIVE, like `crop_corridor_art.py`: reads the shipped `door.png` and writes a
new file beside it. Re-runnable, byte-identical across runs.
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(HERE, "game", "assets", "textures", "level_3_corridor")

SRC = "door.png"
OUT = "hotel_door_217.png"
# The leaf, without its architrave or the wallpaper either side (Issue 35). Verified by
# cropping and viewing, exactly like crop_corridor_art.py's boxes.
LEAF_BOX = (287, 212, 779, 1348)          # 492 x 1136 -> 0.4331

# The original plate's extent inside the crop, found by locating the bright brass cluster.
OLD_PLATE = (165, 218, 310, 284)
PLATE_SCALE = 1.55

# Sampled off the source image, so the new plate sits in the same light as the wood.
BRASS_HI = (226, 184, 105)
BRASS_MID = (186, 137, 69)
BRASS_LO = (118, 84, 40)
FIELD = (54, 39, 20)
SHADOW = (14, 10, 6)
# How much of the drawn plate survives the ageing pass. 1.0 is the clean draft.
AGE = 0.62

FONT_DIRS = [
    os.environ.get("IMAGE_PACK_FONTS", ""),
    os.path.expanduser(
        "~/Downloads/claude-image-generation-main/.claude/skills/"
        "level-1-image-generator/fonts"),
]
FONT_NAME = "CrimsonPro-Bold.ttf"


def _font(size):
    for d in FONT_DIRS:
        if not d:
            continue
        p = os.path.join(d, FONT_NAME)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    raise SystemExit(
        "font %s not found; set IMAGE_PACK_FONTS to the image pack's fonts dir" % FONT_NAME)


def _notched(draw, box, radius, fill):
    """The plate's outline: a rectangle with its corners cut, which is what the original is."""
    x0, y0, x1, y1 = box
    draw.polygon([
        (x0 + radius, y0), (x1 - radius, y0), (x1, y0 + radius), (x1, y1 - radius),
        (x1 - radius, y1), (x0 + radius, y1), (x0, y1 - radius), (x0, y0 + radius),
    ], fill=fill)


def build_plate(w, h):
    """A bevelled brass plate reading 217, on a transparent background."""
    ss = 4                                   # supersample, then downscale — clean edges
    W, H = w * ss, h * ss
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = int(H * 0.22)

    # Body: bright bevel, then the field inset inside it.
    _notched(d, (0, 0, W - 1, H - 1), r, BRASS_MID + (255,))
    bev = int(H * 0.055)
    _notched(d, (bev, bev, W - 1 - bev, H - 1 - bev), int(r * 0.85), BRASS_HI + (255,))
    inset = int(H * 0.115)
    _notched(d, (inset, inset, W - 1 - inset, H - 1 - inset), int(r * 0.7), FIELD + (255,))

    # A raised rule just inside the field, the way the source plate has one.
    rule = int(H * 0.16)
    d.rounded_rectangle((rule, rule, W - 1 - rule, H - 1 - rule),
                        radius=int(H * 0.06), outline=BRASS_LO + (255,),
                        width=max(1, int(H * 0.018)))

    # Two screws, at the height the source has them.
    sr = int(H * 0.045)
    for sx in (int(W * 0.085), int(W * 0.915)):
        d.ellipse((sx - sr, H // 2 - sr, sx + sr, H // 2 + sr), fill=BRASS_LO + (255,))

    # THE NUMBER. Drawn twice: a dark drop first, then the gold, so it reads as raised metal.
    f = _font(int(H * 0.58))
    text = "217"
    bb = d.textbbox((0, 0), text, font=f)
    tx = (W - (bb[2] - bb[0])) // 2 - bb[0]
    ty = (H - (bb[3] - bb[1])) // 2 - bb[1]
    off = max(1, int(H * 0.022))
    d.text((tx + off, ty + off), text, font=f, fill=(18, 12, 6, 255))
    d.text((tx, ty), text, font=f, fill=BRASS_HI + (255,))

    # ⚠️ AGEING, and it is not decoration. The first draft was drawn at full brass values and
    # rendered as a clean modern sticker on a hundred-year-old door — which in a level whose
    # whole trap is "this looks like the real thing" is the failure mode, not a polish note.
    # Two multiplies, both deterministic: a vertical light gradient (1.00 at the top down to
    # 0.66 at the bottom — the corridor is lit from above) and a global AGE factor, so the
    # plate can never be brighter than the source plate it replaces.
    grad = Image.new("L", (1, H))
    for y in range(H):
        f = y / max(1, H - 1)
        grad.putpixel((0, y), int(255 * (1.00 - 0.34 * f)))
    grad = grad.resize((W, H))
    rgb = img.convert("RGB")
    px = rgb.load()
    gp = grad.load()
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            k = gp[x, y] / 255.0 * AGE
            px[x, y] = (int(r * k), int(g * k), int(b * k))
    img = Image.merge("RGBA", list(rgb.split()) + [img.split()[3]])
    return img.resize((w, h), Image.LANCZOS)


def main() -> int:
    src = Image.open(os.path.join(TEX, SRC)).convert("RGB")
    leaf = src.crop(LEAF_BOX)

    ox0, oy0, ox1, oy1 = OLD_PLATE
    cx, cy = (ox0 + ox1) // 2, (oy0 + oy1) // 2
    pw = int((ox1 - ox0) * PLATE_SCALE)
    ph = int((oy1 - oy0) * PLATE_SCALE)
    plate = build_plate(pw, ph)

    # A soft cast shadow under the plate, or it looks pasted on rather than screwed on.
    shadow = Image.new("RGBA", leaf.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    _notched(sd, (cx - pw // 2 + 3, cy - ph // 2 + 4, cx + pw // 2 + 3, cy + ph // 2 + 4),
             int(ph * 0.30), SHADOW + (185,))
    shadow = shadow.filter(ImageFilter.GaussianBlur(4))

    out = leaf.convert("RGBA")
    out.alpha_composite(shadow)
    out.alpha_composite(plate, (cx - pw // 2, cy - ph // 2))
    out = out.convert("RGB")

    path = os.path.join(TEX, OUT)
    out.save(path)
    print("%s  %dx%d  aspect %.4f  plate %dx%d (%.2fx the original)"
          % (OUT, out.width, out.height, out.width / out.height, pw, ph, PLATE_SCALE))
    return 0


if __name__ == "__main__":
    sys.exit(main())
