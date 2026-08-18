#!/usr/bin/env python3
"""KONTUR's ONE unredacted notice — the level stating its own rule, once, as a principle.

WHY THIS EXISTS
---------------
KONTUR's design is that six of its eight gates are answered by a hint planted in an
EARLIER level, and until 2026-08-18 nothing anywhere in the game said so. The only place
the principle was ever stated was the banishment scrawl — which fires *after* a wrong
door, i.e. only for the players who have already lost a level to it.

A player who arrived without the earlier levels' hints therefore had no way to tell the
difference between "I am missing something in this room" and "I should have read more",
and those two readings produce completely different behaviour: the first makes a player
search the room they are standing in until the panic bar kills them, the second makes
them accept the gate and think about where they have been. Nothing gets EASIER — this
notice contains no answer to anything. What changes is that the difficulty becomes
comprehensible instead of arbitrary.

⚠️ A PRINCIPLE, NEVER A PLACE. This is the hard constraint on the wording and it is
asserted, not merely intended: `tests/check_kontur_signs.gd` scans the notice's text for
every gate's operative word, every earlier level's name and every room name in this level
and fails on any of them. `kitchen_drawer.gd` states Gate 1's rule the same way, for the
same reason.

WHAT IT IS NOT
--------------
⚠️ NOT A NINTH GATE SIGN. The eight redacted notices in `tools/make_kontur_signs.py` each
carry a rule with its operative word struck out; this one withholds nothing and therefore
carries NO CENSOR BAR — which is also asserted, in both directions (the signs must have a
bar, this must not). It is a different form series (1-А, issued on admission) and a
different shape (landscape 1500x1300 against the signs' 1500x1000), so it cannot be
mistaken for a rule the player has failed to decode.

⚠️ THE HERO LINE IS THREE WORDS BECAUSE OF ARITHMETIC, NOT TASTE. The plate hangs on the
Landing's north wall and is read head-on from the player's very first frame, 7.1 m away.
Cap height in screen pixels is `cap_m / dist / (2 tan(fov/2)) * 1080`, and for a plate of
fixed WIDTH the achievable cap is `~1.06 * plate_width_m / longest_line_chars` — the
aspect is irrelevant, only the width and the character count bind. At 1.7 m wide, a
10-character longest line ("ELSEWHERE.") yields ~18 px at 7.1 m against the guard's 15 px
floor. A 16-character line ("YOU WERE BRIEFED") yields 12.6 px and would have been
unreadable from where it is meant to be read.

⚠️ CODE-BASED (Pillow via the image pack's `render` engine), never flux — the entire
payload is legible words.

USAGE
    bash <pack>/.claude/skills/level-1-image-generator/scripts/run.sh tools/make_kontur_notice.py
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import
"""

import os

from render import Design

# The house style is imported, not copied: this is the same institution issuing the same
# stationery as the eight gate notices, and a second copy of the palette would drift.
# ⚠️ That import is only safe because `make_kontur_signs.py` guards its `main()` — without
# the guard, building this notice would silently rewrite all eight signs' grain.
from make_kontur_signs import BAND, CARD, CARD_DK, INK, INK_SOFT, RULE

OUT_DIR = "game/assets/textures/level_5_kontur"

# 1500 x 1300 = 1.1538. `kontur.gd` sizes the quad from this aspect and
# `check_art_aspect.gd` sweeps this level, so changing it fails the suite.
W, H = 1500, 1300

FORM = "1-А"
KICKER = "NOTICE TO TRANSFERRED SUBJECTS"

# ⚠️ THE HERO, AND IT IS THE SENTENCE THE WHOLE ITEM EXISTS TO SAY. It names no gate, no
# level, no room, no object and no answer: "elsewhere" is the negation of a place, and
# "briefed" is a statement about WHEN the information was issued, not about where it is.
# The longest line is 10 characters — see the arithmetic in the module docstring.
HERO = ["YOU WERE", "BRIEFED", "ELSEWHERE."]
SUB = "NO COPY IS HELD ON THESE PREMISES."
FOOT_L = "СЕКТОР 1 · ЛЕСТНИЦА"
FOOT_R = "ЭКЗ. 1 · НЕ ВЫНОСИТЬ"

# Baselines as fractions of H. Explicit, like `make_kontur_signs._LAYOUT`: there are four
# text bands and a computed layout is one more thing that can drift silently.
BASELINES = [0.375, 0.555, 0.735]
# The largest type the three lines can carry before the leading closes up. 0.180 of a
# 1300 px card is 234 px of leading; at 215 px of type that is 1.09x, which is tight for
# body copy and correct for a poster set in caps with no descenders in it.
SIZE_CAP = 215


def build():
    d = Design("%dx%d" % (W, H), background=CARD)
    d.linear_gradient([(0.0, (162, 156, 140)), (0.5, CARD), (1.0, CARD_DK)], angle=108)
    d.overlay_glow((0.14, 0.82), (104, 88, 62), 0.30, strength=0.20, mode="blend")
    d.overlay_glow((0.88, 0.16), (104, 88, 62), 0.24, strength=0.16, mode="blend")

    # Head band — same oxblood, same Cyrillic, same institution.
    d.rect(0.0, 0.0, 1.0, 0.098, BAND)
    d.write(0.055, 0.068, "К.О.Н.Т.У.Р.", role="techno", weight="bold", size=40,
            color=(214, 200, 186), tracking=7)
    d.write(0.945, 0.068, "ФОРМА " + FORM, role="mono_alt", weight="bold", size=32,
            color=(206, 178, 170), align="right", tracking=4)

    # The kicker. Same demotion as the gate signs: the player does not need to read the
    # form's title to get the point, and the hero has to have the type.
    k_size = min(34, d.fit_size(KICKER, 0.88, role="mono_alt", weight="bold"))
    d.write(0.5, 0.160, KICKER, role="mono_alt", weight="bold", size=k_size,
            color=INK_SOFT, align="center", tracking=5)
    d.line(0.07, 0.196, 0.93, 0.196, 3, RULE)

    # THE HERO. Sized from the widest line by measurement, never typed.
    # ⚠️ 0.90 of the card width, not the gate signs' 0.88 or a comfortable 0.86. The hero
    # is WIDTH-bound, not leading-bound (measured: `fit_size` returns 198-212 px against a
    # SIZE_CAP of 215), so the target fraction is the only lever left on legibility once
    # the plate width is fixed by the wall it hangs on. Every 0.01 here is ~0.2 px of cap
    # height at the reading distance, and the floor is 15.
    size = min(min(d.fit_size(ln, 0.90, role="grotesque", weight="bold") for ln in HERO),
               SIZE_CAP)
    for i, ln in enumerate(HERO):
        d.write(0.5, BASELINES[i], ln, role="grotesque", weight="bold", size=size,
                color=INK, align="center", tracking=1)

    # ⚠️ NO CENSOR BAR. Every other printed notice in this level has one struck into it;
    # this is the one document the facility is not withholding anything from, and that
    # difference is the whole reason a player can tell it apart from a rule they failed
    # to answer. `check_kontur_signs.gd` asserts the absence.
    sub_size = min(46, d.fit_size(SUB, 0.80, role="mono_alt", weight="bold"))
    d.write(0.5, 0.835, SUB, role="mono_alt", weight="bold", size=sub_size,
            color=INK_SOFT, align="center", tracking=3)

    d.line(0.07, 0.888, 0.93, 0.888, 2, RULE)
    d.write(0.055, 0.952, FOOT_L, role="mono_alt", size=28, color=INK_SOFT, tracking=3)
    d.write(0.945, 0.952, FOOT_R, role="mono_alt", size=28, color=INK_SOFT,
            align="right", tracking=3)

    path = os.path.join(OUT_DIR, "kontur_notice_briefing.png")
    d.save(path, grain=4, chroma=1, saturation=0.92, contrast=1.06)
    return path, size


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    path, size = build()
    print("wrote", path)
    print("hero set at %d px on a %d px card (%.4f aspect); longest line %d chars"
          % (size, H, W / float(H), max(len(ln) for ln in HERO)))


if __name__ == "__main__":
    main()
