#!/usr/bin/env python3
"""The FACE of the Corridor's entrance note — the Hotel Vesper night-audit page at d = 4 m.

    <pack>/.venv/bin/python3 tools/make_vesper_note.py
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import

WHY THIS EXISTS
---------------
Playtest capture, 2026-08-17: *"The note looks boring. Can we generate an image that will make
it look more like haunted-hotel style?"* — photographed at (0.50, 0.00, 3.50), 30 s into the
level. It was a `BoxMesh` 0.21 x 0.01 x 0.297 with **no texture at all**: albedo (0.05,0.05,
0.04), emission (0.55,0.50,0.35) at 0.6. A flat olive-cream slab on a grey box, and the very
first thing the player is asked to interact with in this level.

Exactly the same defect `make_vesper_plate.py` was written for, on the other page in the same
level, six weeks earlier. The plate's own header states the general rule and this is its
second application: a prop the player is meant to read has to LOOK like a document.

⚠️ THE NOTE TEXT IN `corridor.gd` IS UNCHANGED. The user's complaint was about the prop's
appearance, not its words. What is lettered here is the letterhead plus the FIRST PARAGRAPH
and the sign-off, **verbatim from `corridor.gd:NOTE_TEXT`** — nothing invented, nothing
paraphrased, and the full text is still what `NoteUI` shows and what the TAB journal archives.

TWO ENGINES, AND THAT IS THE POINT
----------------------------------
  * the PAPER is flux (`level-3-image-generator`) — foxing, damp blooms, torn deckle edges and
    the creases of a sheet folded in four. That is texture, which diffusion is good at, and
    the prompt asked for a BLANK sheet on purpose.
  * the WORDS are Pillow, deterministic. Flux cannot letter, and every note-like asset in this
    project that asked it to came back with dream-alphabet.
The raw generation is kept at `assets_src/textures/level_3_corridor/vesper_note_paper_raw.jpg`
because this script is the only thing that can rebuild the shipped file.

⚠️ DARKENED, NOT LEFT AS GENERATED. Cream paper is near-white, and near-white albedo is the
brightest paint obtainable in a project with no glow, no fog and light energy ~0.45 — that is
`lab_breaker_panel.png`'s failure (Issue 63) waiting to happen. The sheet is multiplied down
to `PAPER_GAIN` so the page reads as old paper in torchlight rather than as a lit rectangle,
and `corridor.gd` puts a LOW emission on it through `EMISSION_OP_MULTIPLY` (Issue 81) so what
glows is the paper's own tone rather than a flat wash over the type.
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(HERE, "assets_src", "textures", "level_3_corridor",
                   "vesper_note_paper_raw.jpg")
OUT = os.path.join(HERE, "game", "assets", "textures", "level_3_corridor", "vesper_note.png")

# The sheet inside the generation, found by scanning for the first mostly-bright row/column.
# The candle and the table it was generated on are cropped away — Issue 35: a prop's texture
# may not contain a picture of the thing it is lying on.
SHEET_BOX = (134, 127, 896, 929)          # 762 x 802 -> 0.9501
PAPER_GAIN = 0.66
# Anything dimmer than this, reached from the centre of the page, is not the page.
PAPER_MIN_LUMA = 46

INK = (58, 44, 28)
INK_FAINT = (86, 70, 48)
RULE = (104, 84, 56)

FONT_DIRS = [
    os.environ.get("IMAGE_PACK_FONTS", ""),
    os.path.expanduser(
        "~/Downloads/claude-image-generation-main/.claude/skills/"
        "level-1-image-generator/fonts"),
]

# ⚠️ VERBATIM from corridor.gd:NOTE_TEXT. Only the first paragraph and the sign-off, because
# at the size this renders in world (a 0.25 m sheet seen from about a metre) the body is
# texture rather than text — the READABLE copy is the NoteUI overlay, which is unchanged.
HEAD = "HOTEL VESPER"
SUB = "NIGHT AUDIT"
BODY = [
    "The corridor between floors does not appear",
    "on the building plans. The staff do not walk",
    "it after dark.",
    "",
    "You will.",
]
SIGN = "— The Management"


def _font(name, size):
    for d in FONT_DIRS:
        if not d:
            continue
        p = os.path.join(d, name)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    raise SystemExit("font %s not found; set IMAGE_PACK_FONTS" % name)


def main() -> int:
    sheet = Image.open(SRC).convert("RGB").crop(SHEET_BOX)
    w, h = sheet.size

    # Ink first, on its own layer, then composited at less than full opacity — old type on
    # old paper is never pure black and never fully opaque.
    ink = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(ink)

    serif = _font("CrimsonPro-Bold.ttf", int(h * 0.062))
    small = _font("CrimsonPro-Regular.ttf", int(h * 0.026))
    body = _font("CrimsonPro-Regular.ttf", int(h * 0.032))
    ital = _font("CrimsonPro-Italic.ttf", int(h * 0.034))

    def centred(y, text, font, colour, tracking=0):
        if tracking == 0:
            bb = d.textbbox((0, 0), text, font=font)
            d.text(((w - (bb[2] - bb[0])) / 2 - bb[0], y), text, font=font, fill=colour)
            return
        widths = [d.textbbox((0, 0), c, font=font)[2] for c in text]
        total = sum(widths) + tracking * (len(text) - 1)
        x = (w - total) / 2
        for c, cw in zip(text, widths):
            d.text((x, y), c, font=font, fill=colour)
            x += cw + tracking

    centred(int(h * 0.105), HEAD, serif, INK + (255,), tracking=int(h * 0.012))
    centred(int(h * 0.185), SUB, small, INK_FAINT + (255,), tracking=int(h * 0.010))
    d.line((w * 0.20, h * 0.235, w * 0.80, h * 0.235), fill=RULE + (255,),
           width=max(1, int(h * 0.004)))

    y = int(h * 0.315)
    for line in BODY:
        d.text((int(w * 0.145), y), line, font=body, fill=INK + (235,))
        y += int(h * 0.052)

    centred(int(h * 0.775), SIGN, ital, INK + (230,))

    out = Image.alpha_composite(sheet.convert("RGBA"), ink).convert("RGB")

    # ⚠️ AND THEN DARKEN THE WHOLE THING — see the header. Applied AFTER the type so the ink
    # keeps its contrast against the paper rather than being crushed into it.
    px = out.load()
    for yy in range(h):
        for xx in range(w):
            r, g, b = px[xx, yy]
            px[xx, yy] = (int(r * PAPER_GAIN), int(g * PAPER_GAIN), int(b * PAPER_GAIN))

    # ⚠️ AND AN ALPHA CUTOUT OF THE SHEET ITSELF. A rectangular crop of a torn deckle-edged
    # page keeps four triangles of the dark table — and, in this generation, the corner of the
    # candle it was lit by. That is Issue 35 in miniature: a prop's texture may not contain a
    # picture of the thing it is lying on. The mask is a FLOOD FILL of "bright enough" pixels
    # from the centre of the page, not a threshold: the candle is bright too, and only
    # connectivity tells the two apart. Same reachability idea as
    # `tools/flatten_alpha_checker.py`, which exists because a threshold alone got this wrong.
    lum = out.convert("L").load()
    mask = Image.new("L", (w, h), 0)
    mp = mask.load()
    stack = [(w // 2, h // 2)]
    seen = bytearray(w * h)
    while stack:
        x, y = stack.pop()
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        if lum[x, y] < PAPER_MIN_LUMA:
            continue
        mp[x, y] = 255
        if x > 0:
            stack.append((x - 1, y))
        if x < w - 1:
            stack.append((x + 1, y))
        if y > 0:
            stack.append((x, y - 1))
        if y < h - 1:
            stack.append((x, y + 1))
    mask = mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(1.2))
    # ⚠️ And blank the RGB wherever the alpha is, so bilinear filtering cannot fringe. The
    # masked-out corner of this generation is a lit CANDLE FLAME — the brightest pixels in the
    # file — and a fully transparent texel still contributes its colour to the filtered result
    # at the edge. Leaving it would put an orange halo along the torn edge of the page.
    for yy in range(h):
        for xx in range(w):
            if mp[xx, yy] < 8:
                px[xx, yy] = (10, 8, 6)
    out = out.convert("RGBA")
    out.putalpha(mask)
    opaque = sum(1 for v in mask.getdata() if v > 127)

    out.save(OUT)
    mean = sum(sum(px[x, y]) / 3.0 for y in range(0, h, 7) for x in range(0, w, 7))
    n = len(range(0, h, 7)) * len(range(0, w, 7))
    print("%s  %dx%d  aspect %.4f  mean luma %.1f/255  opaque %.1f%%"
          % (os.path.basename(OUT), w, h, w / h, mean / n, 100.0 * opaque / (w * h)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
