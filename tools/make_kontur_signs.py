#!/usr/bin/env python3
"""KONTUR's eight redacted gate signs, as real printed notices.

WHY THIS EXISTS
---------------
These eight plates are the ONLY in-level help this level has. Every gate's rule is stated
on one of them with the operative word censored, so a player who missed the cross-level
hints still gets the shape of the question. Until 2026-08-18 they were a `Label3D` of raw
engine text floating 12 mm in front of a blank enamel rectangle, with a separate black
`QuadMesh` for the censor bar — i.e. the level's whole documentation was UI text stuck on
a wall, in the default font, at whatever size fitted.

They are now real documents: a Soviet institutional notice with a printed head, a form
number, a rule set in type, a genuine censor bar struck over the operative word, and a
counter-signature. `kontur.gd:_make_sign()` mounts the artwork and no longer draws any
text at all.

⚠️ THE REDACTION IS BAKED, WHICH IS THE STRONGEST FORM OF IT. The operative word is never
rendered into the image in the first place — there is no layer to peel, no `Label3D` whose
text a curious player could read out of a debug print, and nothing that can drift out of
alignment with the bar. The bar's job is to say *a word was removed here*, not to hide one.

⚠️ CODE-BASED (Pillow via the image pack's `render` engine), never flux. The entire payload
is legible words and a diffusion model cannot letter a sign.

⚠️ CYRILLIC IS FONT-LIMITED. Only four bundled faces carry Cyrillic — measured by rendering
"К"/"Ж" against .notdef: JetBrainsMono (`mono_alt`), Lora (`serif`), Tektur (`techno`) and
PixelifySans. So the Russian head/footer are set in `mono_alt`/`techno` and the English rule
in `grotesque`. Ask `grotesque` for Cyrillic and you get eight tofu boxes.

⚠️ 1500x1000 = 3:2, and `kontur.gd` sizes the sign quad from the artwork's own aspect.
`check_art_aspect.gd` sweeps this level, so a ratio change here fails the suite.

USAGE
    bash <pack>/.claude/skills/level-1-image-generator/scripts/run.sh tools/make_kontur_signs.py
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import
"""

import os

from render import Design

OUT_DIR = "game/assets/textures/level_5_kontur"

# Aged bone card with near-black ink and an oxblood head band.
#
# ⚠️ MID-TONE, NOT WHITE. `kontur.gd` gives these plates an emission texture so the rules
# stay readable in rooms this dark, and emission is most of a surface's colour here (no
# glow, no fog, no tonemapping — Issue 21). A white card at any usable emission is the
# brightest object in a KONTUR room; this one measures ~0.56 sRGB, which reads as paper
# under a torch and as a pale rectangle from across the room.
CARD = (150, 144, 128)
CARD_DK = (118, 112, 98)
INK = (26, 24, 21)
INK_SOFT = (62, 58, 50)
BAND = (96, 30, 26)
BAR = (14, 13, 12)
RULE = (86, 80, 70)

# name, form no., title, rule (English), tail after the bar (or ""), section footer
SIGNS = [
    ("gate1_doors", "4-Б", "K.O.N.T.U.R. — PROTOCOL 4-B",
     "EVACUATION ROUTE IS MARKED IN", "", "СЕКТОР 1 · ВЕСТИБЮЛЬ"),
    ("gate2_shelf", "11-В", "DECONTAMINATION — CLASS II",
     "APPROVED AGENT: DOMESTIC", "", "СЕКТОР 3 · КУХНЯ"),
    ("gate5_roster", "2-А", "PERSONNEL GATE — OBJECT 12",
     "THIS SUBJECT IS NUMBER", "", "СЕКТОР 4 · УЧЁТ"),
    ("gate3_offering", "19-Д", "RECOVERY LOG — OBJECT 12",
     "ITEMS RECOVERED FROM AN OBJECT ARE", "", "СЕКТОР 5 · АРХИВ"),
    ("gate6_phone", "7-Ж", "INTERNAL LINE — WING 4",
     "AN INCOMING CALL MUST BE", "", "СЕКТОР 6 · КОММУТАТОР"),
    ("gate7_dark", "9-З", "LIGHTING FAULT — SECTOR 9",
     "THE TRUE DOOR IS SEEN WHEN", "", "СЕКТОР 7 · АВАРИЯ"),
    ("gate8_airlock", "12-К", "DECONTAMINATION CYCLE",
     "TO CYCLE, THE SUBJECT MUST REMAIN", "", "СЕКТОР 8 · ШЛЮЗ"),
    ("gate4_escort", "7-Т", "TRANSIT PROTOCOL 7",
     "DO NOT", "THE ESCORT", "СЕКТОР 8 · ПЕРЕХОД"),
]


# n -> (baselines, censor-bar top). Explicit per line count: a computed layout is one more
# thing that can drift silently, and there are only three cases.
_LAYOUT = {
    1: ([0.400], 0.470),
    2: ([0.330, 0.480], 0.550),
    3: ([0.290, 0.428, 0.566], 0.636),
}
# The largest type each line count can carry before the lines start touching.
_SIZE_CAP = {1: 160, 2: 143, 3: 131}


def _split(words, n):
    """n roughly balanced runs of words, in order."""
    out, per = [], len(words) / float(n)
    for i in range(n):
        lo, hi = int(round(i * per)), int(round((i + 1) * per))
        out.append(" ".join(words[lo:hi]))
    return [ln for ln in out if ln]


def _best_split(d, rule):
    words = rule.split(" ")
    best = (1, [rule], 0)
    for n in (1, 2, 3):
        if n > len(words):
            break
        lines = _split(words, n)
        if len(lines) != n:
            continue
        size = min(min(d.fit_size(ln, 0.88, role="grotesque", weight="bold")
                       for ln in lines), _SIZE_CAP[n])
        if size > best[2]:
            best = (n, lines, size)
    return best


def build(name, form, title, rule, tail, footer):
    """⚠️ THE RULE IS THE HERO, and that is a MEASURED decision, not taste.

    The first layout gave the gate title the big type and set the rule at 58 px on a
    1000 px card. `check_kontur_signs.gd` measures the ink's real height on the imported
    texture and converts it to screen pixels at each sign's distance from its own room's
    walking line: **5.1 to 8.8 px of cap height on six of the eight** — i.e. the level's
    only documentation was, in the literal sense, unreadable while walking past it.

    So the hierarchy is inverted. The title drops to a small kicker (it is flavour: the
    player does not need to read "DECONTAMINATION — CLASS II" to play), the rule is
    wrapped over up to two lines and set as large as it will go, and the plate grew from
    1.0 to 1.2 m tall. Re-measured: worst sign **18.6 px**, best 58 px.
    """
    d = Design("1500x1000", background=CARD)
    # Card stock: a faint diagonal tone plus two age stains, all well under the ink.
    d.linear_gradient([(0.0, (162, 156, 140)), (0.5, CARD), (1.0, CARD_DK)], angle=108)
    d.overlay_glow((0.14, 0.82), (104, 88, 62), 0.30, strength=0.20, mode="blend")
    d.overlay_glow((0.88, 0.16), (104, 88, 62), 0.24, strength=0.16, mode="blend")

    # Head band — the one saturated element, and it is where the Russian lives.
    d.rect(0.0, 0.0, 1.0, 0.115, BAND)
    d.write(0.055, 0.079, "К.О.Н.Т.У.Р.", role="techno", weight="bold", size=40,
            color=(214, 200, 186), tracking=7)
    d.write(0.945, 0.079, "ФОРМА " + form, role="mono_alt", weight="bold", size=32,
            color=(206, 178, 170), align="right", tracking=4)

    # The gate title, demoted to a kicker.
    k_size = min(34, d.fit_size(title, 0.88, role="mono_alt", weight="bold"))
    d.write(0.5, 0.185, title, role="mono_alt", weight="bold", size=k_size,
            color=INK_SOFT, align="center", tracking=5)
    d.line(0.07, 0.225, 0.93, 0.225, 3, RULE)

    # THE RULE.
    #
    # ⚠️ THE LINE BREAK IS CHOSEN BY MEASUREMENT, not by a word count. The first version
    # split only when the rule ran to more than three words, which left
    # "APPROVED AGENT: DOMESTIC" on one 24-character line at 73 mm of cap height — 13.3 px
    # from the kitchen's walking line, under `check_kontur_signs.gd`'s 15 px floor, on the
    # sign for the gate whose answer is a word. It now tries 1, 2 and 3 balanced splits and
    # keeps whichever yields the LARGEST type that still fits its own leading.
    n_lines, lines, r_size = _best_split(d, rule)
    baselines, bar_y = _LAYOUT[n_lines]
    for i, ln in enumerate(lines):
        d.write(0.5, baselines[i], ln, role="grotesque", weight="bold", size=r_size,
                color=INK, align="center", tracking=1)

    # ⚠️ radius=0. A rounded bar reads as a UI pill; a redaction is a rectangle
    # somebody ran a marker over.
    # ⚠️ NO hairlines inside the bar. Two "struck through" lines at (46,42,38) were
    # tried, and at the size these plates are actually seen they read as a grey stripe
    # across the redaction rather than as texture — i.e. the one element whose whole job
    # is to be solid looked like it had a gap in it.
    d.rect(0.215, bar_y, 0.785, bar_y + 0.115, BAR, radius=0)

    if tail != "":
        d.write(0.5, bar_y + 0.115 + 0.115, tail, role="grotesque", weight="bold",
                size=r_size, color=INK, align="center", tracking=1)

    # Counter-signature.
    d.line(0.07, 0.885, 0.93, 0.885, 2, RULE)
    d.write(0.055, 0.950, footer, role="mono_alt", size=28, color=INK_SOFT, tracking=3)
    d.write(0.945, 0.950, "ЭКЗ. 1 · НЕ ВЫНОСИТЬ", role="mono_alt", size=28,
            color=INK_SOFT, align="right", tracking=3)

    path = os.path.join(OUT_DIR, "kontur_sign_%s.png" % name)
    d.save(path, grain=4, chroma=1, saturation=0.92, contrast=1.06)
    return path


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for row in SIGNS:
        p = build(*row)
        print("wrote", p)
    print("\n%d signs, 1500x1000 (1.5000). kontur.gd sizes the quad from this aspect."
          % len(SIGNS))


# ⚠️ GUARDED SINCE 2026-08-18 so `tools/make_kontur_notice.py` can import this module's
# palette (CARD / INK / BAND / …) without regenerating all eight signs as a side effect.
# `d.save(grain=4)` is not seeded, so an incidental re-run rewrites every sign's noise —
# and the worst sign clears `check_kontur_signs.gd`'s 15 px floor by 0.3 px, which is not
# a margin to spend on an accident. run.sh executes this file directly, so the eight signs
# still build exactly as they did.
if __name__ == "__main__":
    main()
