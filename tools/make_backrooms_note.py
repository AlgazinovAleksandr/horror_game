#!/usr/bin/env python3
"""The FACE of the Backrooms' entry note — `ClueNote`, on the table 4 m into the entry arm.

    <pack>/.venv/bin/python3 tools/make_backrooms_note.py
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import

WHY THIS EXISTS
---------------
Playtest capture 003, 2026-08-18, taken at the spawn: *"Again, make the note more like the
backrooms atmosphere"* — the word "again" is the point. The Corridor's entrance note was
rebuilt the day before for the identical defect and `make_vesper_note.py` is this script's
direct parent; this is the same fix in a different register.

It was an **untextured** `BoxMesh` 0.21 x 0.01 x 0.297: albedo (0.85, 0.82, 0.60), emission
(0.50, 0.48, 0.35) at 0.3. A flat cream slab — and in a level whose walls are mono-yellow
wallpaper at mean luma **171.9/255**, a near-white self-lit rectangle is the brightest thing
in the room. Capture 003 shows exactly that: a blank pale card on a dark box.

⚠️ THE NOTE TEXT IN `backrooms.gd` IS UNCHANGED. The user's complaint was about the prop's
appearance. What is lettered here is the FIRST PARAGRAPH and the sign-off, **verbatim from
`backrooms.gd:NOTE_TEXT`** — nothing invented and nothing paraphrased. The full text is still
what `NoteUI` shows and what the TAB journal archives.

⚠️ AND NO INVENTED LETTERHEAD. The Corridor's page could carry `HOTEL VESPER / NIGHT AUDIT`
because the level names itself; this note is signed *"— someone who is still in here"* and has
no institution behind it. The pre-printed furniture on this sheet is therefore WORDLESS: rule
lines and an empty form box, which is paper, not lore.

TWO ENGINES, AND THAT IS THE POINT
----------------------------------
  * the PAPER is flux (`level-3-image-generator`) — a torn-edged sheet of damp office memo
    paper on a dark board, foxed and tide-marked. The prompt asked for a BLANK sheet: flux
    cannot letter, and every note-like asset in this project that asked it to came back with
    dream-alphabet.
  * the WORDS are Pillow, deterministic.
The raw generation is kept at
`assets_src/textures/level_backrooms/backrooms_note_paper_raw.jpg` because this script is the
only thing that can rebuild the shipped file.

⚠️ DARKER THAN THE WALLPAPER, AND THAT IS A MEASURED REQUIREMENT, not a taste call. Measured
from the shipped textures: `backrooms_wallpaper_albedo.png` is mean luma 171.9/255 and the
carpet 91.5. The raw sheet is 197.7 — brighter than both. `PAPER_GAIN` brings it to ~99, i.e.
under the wallpaper it is seen against and about the carpet it lies above. `check_backrooms_
note.gd` asserts the relationship against the wallpaper file rather than against a constant,
so re-skinning the level cannot silently break it. This is `lab_breaker_panel.png`'s Issue 63
in advance: near-white albedo is the brightest paint obtainable in a project with no glow, no
fog and light energy ~0.45.

⚠️ ALPHA CUTOUT BY FLOOD FILL, not by threshold. The generation is a sheet on a dark board on
a pale wall; a rectangular crop keeps four triangles of board, and a brightness threshold also
keeps the wall. Only connectivity from the centre of the page tells paper from everything else
— the same reachability idea as `tools/flatten_alpha_checker.py`.
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(HERE, "assets_src", "textures", "level_backrooms",
                   "backrooms_note_paper_raw.jpg")
OUT = os.path.join(HERE, "game", "assets", "textures", "level_backrooms",
                   "backrooms_note.png")

# The sheet inside the generation, found by scanning for yellow (r-b > 50) rows/columns —
# the dark board and the pale green wall both fail that test. 466 x 442 -> aspect 1.0543.
SHEET_BOX = (275, 323, 741, 765)
# 197.7 -> ~99, i.e. below the wallpaper's 171.9. See the header.
PAPER_GAIN = 0.50
# Anything dimmer than this, reached from the centre of the page, is not the page. The board
# under the sheet is near-black, so this has a wide margin either side.
PAPER_MIN_LUMA = 60

INK = (46, 38, 22)
INK_FAINT = (92, 82, 52)
RULE = (120, 108, 70)

FONT_DIRS = [
    os.environ.get("IMAGE_PACK_FONTS", ""),
    os.path.expanduser(
        "~/Downloads/claude-image-generation-main/.claude/skills/"
        "level-1-image-generator/fonts"),
]

# ⚠️ VERBATIM from backrooms.gd:NOTE_TEXT — the opening paragraph and the sign-off. At the
# size this renders in world (a 0.22 m sheet seen from about a metre) the rest is texture
# rather than text; the READABLE copy is the NoteUI overlay, which is unchanged.
BODY = [
    "I stopped trying to reach",
    "the door.",
    "",
    "There is no door.",
]
SIGN = "— someone who is still in here"


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

    ink = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(ink)

    # A typewriter face, not a serif: this is a memo out of a filing room, and the project
    # has no handwriting font (screen_text.gd records that, which is why its scrawls tilt).
    body = _font("DMMono-Regular.ttf", int(h * 0.046))
    small = _font("DMMono-Regular.ttf", int(h * 0.028))

    # --- wordless pre-printed furniture: an empty form box and the ruled lines it sits on.
    box_w, box_h = int(w * 0.26), int(h * 0.085)
    bx, by = int(w * 0.60), int(h * 0.085)
    d.rectangle((bx, by, bx + box_w, by + box_h), outline=RULE + (200,),
                width=max(1, int(h * 0.004)))
    d.line((bx + box_w * 0.5, by, bx + box_w * 0.5, by + box_h), fill=RULE + (160,),
           width=max(1, int(h * 0.003)))
    d.line((w * 0.10, h * 0.215, w * 0.90, h * 0.215), fill=RULE + (220,),
           width=max(1, int(h * 0.005)))
    for i in range(7):
        y = h * (0.285 + i * 0.083)
        d.line((w * 0.10, y, w * 0.90, y), fill=RULE + (70,), width=1)

    y = int(h * 0.295)
    for line in BODY:
        d.text((int(w * 0.115), y), line, font=body, fill=INK + (232,))
        y += int(h * 0.083)

    bb = d.textbbox((0, 0), SIGN, font=small)
    d.text((w * 0.88 - (bb[2] - bb[0]), int(h * 0.815)), SIGN, font=small,
           fill=INK_FAINT + (225,))

    out = Image.alpha_composite(sheet.convert("RGBA"), ink).convert("RGB")

    # ⚠️ DARKEN AFTER THE TYPE, never before — applied first, the ink would be crushed into
    # the paper instead of keeping its contrast against it.
    px = out.load()
    for yy in range(h):
        for xx in range(w):
            r, g, b = px[xx, yy]
            px[xx, yy] = (int(r * PAPER_GAIN), int(g * PAPER_GAIN), int(b * PAPER_GAIN))

    # --- the alpha cutout: flood fill of "bright enough" from the centre of the page.
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
        if lum[x, y] < PAPER_MIN_LUMA * PAPER_GAIN:
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
    # ⚠️ Blank the RGB wherever the alpha is: a fully transparent texel still contributes its
    # colour to a bilinear filtered edge, so the dark board would fringe the torn deckle.
    for yy in range(h):
        for xx in range(w):
            if mp[xx, yy] < 8:
                px[xx, yy] = (8, 8, 6)
    out = out.convert("RGBA")
    out.putalpha(mask)
    opaque = sum(1 for v in mask.getdata() if v > 127)

    out.save(OUT)
    # Mean luma over the OPAQUE pixels only — averaging in the blanked border would report a
    # page far darker than the one that renders, which is the number this file is judged on.
    lum2 = out.convert("L").load()
    acc, n = 0.0, 0
    for yy in range(0, h, 3):
        for xx in range(0, w, 3):
            if mp[xx, yy] > 127:
                acc += lum2[xx, yy]
                n += 1
    print("%s  %dx%d  aspect %.4f  mean luma (paper only) %.1f/255  opaque %.1f%%"
          % (os.path.basename(OUT), w, h, w / h, acc / max(1, n), 100.0 * opaque / (w * h)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
