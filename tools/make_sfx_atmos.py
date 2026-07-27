#!/usr/bin/env python3
"""Procedural SFX for the four-level atmosphere pass ("scarier Intro/House/Corridor/Backrooms").

Pure-stdlib (wave/math/random/struct), same write_wav/OnePole conventions as
make_sfx_extra.py — copied rather than imported, matching how every other make_sfx_*.py
in this project stands alone.

  shared/           telegraph_groan.wav   the Corridor's false-ceiling telegraph (P4)
                    footstep_trail.wav    the decelerating stop-delayed echo step (P2)
  level_2_house/    fridge_hum.wav        the kitchen fridge's lure
  level_backrooms/  wade_distant.wav      the unseen thing in the Flood (P10)
                    wade_step.wav         the player's own wading step

⚠️ Base names must be GLOBALLY UNIQUE. GameState.load_audio() resolves a base name across
every audio subdir and returns the first hit, so a duplicate silently shadows the other —
`door_slam` already collides in two folders with the level_3_corridor copy winning.
Checked at the bottom of this file.

⚠️ Every .wav.import in this project is loop_mode=0, so anything that needs to loop is
restarted in code via `finished -> play`. The loops here are therefore written to start and
end near zero so that restart does not tick.

Usage: python3 tools/make_sfx_atmos.py
"""

import math
import os
import random
import struct
import wave

SR = 44100
AUDIO = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "audio")


def write_wav(subdir, name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    norm = 0.89 / peak
    out_dir = os.path.join(AUDIO, subdir)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.normpath(os.path.join(out_dir, name))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            frames += struct.pack("<h", int(max(-1.0, min(1.0, s * norm)) * 32767))
        w.writeframes(bytes(frames))
    print(f"wrote {path} ({len(samples)/SR:.2f}s)")


class OnePole:
    """One-pole low-pass. `tick` per sample; cutoff is fixed at construction."""

    def __init__(self, cutoff_hz):
        self.a = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / SR)
        self.y = 0.0

    def tick(self, x):
        self.y += self.a * (x - self.y)
        return self.y


def fade_ends(out, ms=12.0):
    """Taper both ends to zero so a self-restarted loop has no click at the seam."""
    n = int(SR * ms / 1000.0)
    n = min(n, len(out) // 2)
    for i in range(n):
        g = i / float(n)
        out[i] *= g
        out[-1 - i] *= g
    return out


# --------------------------------------------------------------------------- shared/

def make_telegraph_groan():
    """Three descending detuned partials — SCARY.md P4's false-ceiling telegraph.

    The point of this sound is that it MEANS NOTHING four times out of five. So it has to
    be distinctive enough to be learned and then dismissed, which is why it is a defined
    three-note fall rather than a texture: a texture cannot be recognised and therefore
    cannot be discounted.
    """
    random.seed(1701)
    dur = 3.2
    n = int(SR * dur)
    lp = OnePole(400.0)
    out = []
    # 110 -> 82 -> 61 Hz, each with a slow attack and a long tail.
    notes = [(110.0, 0.00), (82.0, 0.95), (61.0, 1.95)]
    for i in range(n):
        t = i / SR
        s = 0.0
        for base, start in notes:
            if t < start:
                continue
            local = t - start
            attack = min(1.0, local / 0.4)
            tail = math.exp(-local / 1.1)
            env = attack * tail
            # Two slightly detuned saw-ish stacks; the beat between them is the "wrong" part.
            for mult, det in ((1.0, 0.0), (1.0, 1.7), (2.0, -2.3)):
                f = base * mult + det
                ph = 2.0 * math.pi * f * local
                saw = (ph % (2.0 * math.pi)) / math.pi - 1.0
                s += saw * env * (0.5 if mult == 1.0 else 0.18)
        s += (random.random() - 0.5) * 0.02
        out.append(lp.tick(s))
    return fade_ends(out, 30.0)


def make_footstep_trail():
    """The decelerating trail step for SCARY.md P2's stop-delayed echo.

    Purpose-made rather than a pitch-shift of `footstep`, following the apparition_snarl
    precedent: a mechanically pitched-down copy of your own step reads as a glitch, while a
    slightly different sound reads as a different foot.
    """
    random.seed(1702)
    dur = 0.35
    n = int(SR * dur)
    lp = OnePole(1400.0)
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-t / 0.075)
        thud = math.sin(2.0 * math.pi * 58.0 * t) * env * 0.8
        grit = (random.random() - 0.5) * env * 0.5
        # A 250 ms tail: the scuff that keeps going after the weight lands.
        tail = (random.random() - 0.5) * math.exp(-t / 0.25) * 0.10
        out.append(lp.tick(thud + grit + tail))
    return fade_ends(out, 4.0)


# -------------------------------------------------------------------- level_2_house/

def make_fridge_hum():
    """A 4 s seamless compressor hum — the kitchen fridge's lure.

    Its whole job is to make an unremarkable box worth walking up to, so it is deliberately
    mains-flavoured (50 Hz + harmonics) rather than eerie. The scare is what happens when
    you open it; the hum only has to say "this thing is running".
    """
    random.seed(1703)
    dur = 4.0
    n = int(SR * dur)
    lp = OnePole(320.0)
    out = []
    for i in range(n):
        t = i / SR
        # Integer multiples of 1/dur keep every partial phase-continuous across the loop.
        s = 0.0
        for f, a in ((50.0, 0.55), (100.0, 0.22), (150.0, 0.10), (250.0, 0.05)):
            s += math.sin(2.0 * math.pi * f * t) * a
        # Slow amplitude wobble, also loop-exact (1 cycle over dur).
        s *= 0.88 + 0.12 * math.sin(2.0 * math.pi * t / dur)
        s += (random.random() - 0.5) * 0.03
        out.append(lp.tick(s))
    return fade_ends(out, 8.0)


# ------------------------------------------------------------------ level_backrooms/

def make_wade_distant():
    """SCARY.md P10 — a wading sound that is NOT the player's.

    Irregular by construction. A regular interval would read as a machine, and the entity
    this stands in for is never rendered, so the rhythm is the only characterisation it
    gets: uneven strides, heavy, always low-passed as if heard across water and rooms.
    """
    random.seed(1704)
    dur = 4.8
    n = int(SR * dur)
    lp = OnePole(900.0)
    out = [0.0] * n
    t = 0.35
    while t < dur - 0.5:
        start = int(t * SR)
        length = int(SR * 0.42)
        for i in range(length):
            if start + i >= n:
                break
            lt = i / SR
            env = math.exp(-lt / 0.10) * (1.0 - math.exp(-lt / 0.004))
            # A displacement thump plus the splash that follows it.
            body = math.sin(2.0 * math.pi * 46.0 * lt) * 0.7
            splash = (random.random() - 0.5) * 1.2
            out[start + i] += (body + splash) * env
        t += random.uniform(0.7, 1.3)
    # Slap-back delay ~180 ms: it is happening in a room that is not this one.
    d = int(SR * 0.18)
    for i in range(n - 1, d - 1, -1):
        out[i] += out[i - d] * 0.33
    return fade_ends([lp.tick(s) for s in out], 25.0)


def make_wade_step():
    """The player's OWN step through ankle-deep water.

    P10's anchor only works if what you hear in the distance is audibly the same ACT you
    are performing. Before this the Flood's four `water` loops were room tone and the
    player's own wading sounded like a boot on carpet.
    """
    random.seed(1705)
    dur = 0.40
    n = int(SR * dur)
    lp = OnePole(2200.0)
    out = []
    for i in range(n):
        t = i / SR
        # Splash first (the foot breaking the surface), thud second (it reaching the floor).
        splash_env = math.exp(-t / 0.055) * (1.0 - math.exp(-t / 0.002))
        splash = (random.random() - 0.5) * splash_env * 1.3
        thud_t = max(0.0, t - 0.045)
        thud = math.sin(2.0 * math.pi * 62.0 * thud_t) * math.exp(-thud_t / 0.05) * 0.55
        drip = (random.random() - 0.5) * math.exp(-t / 0.22) * 0.12
        out.append(lp.tick(splash + thud + drip))
    return fade_ends(out, 4.0)


TARGETS = [
    ("shared", "telegraph_groan.wav", make_telegraph_groan),
    ("shared", "footstep_trail.wav", make_footstep_trail),
    ("level_2_house", "fridge_hum.wav", make_fridge_hum),
    ("level_backrooms", "wade_distant.wav", make_wade_distant),
    ("level_backrooms", "wade_step.wav", make_wade_step),
]


def check_unique():
    """Refuse to shadow an existing base name in another subdir (see the module docstring)."""
    wanted = {os.path.splitext(name)[0]: subdir for subdir, name, _ in TARGETS}
    clashes = []
    for root, _dirs, files in os.walk(AUDIO):
        subdir = os.path.basename(root)
        for f in files:
            base, ext = os.path.splitext(f)
            if ext.lower() not in (".wav", ".ogg", ".mp3"):
                continue
            if base in wanted and subdir != wanted[base]:
                clashes.append(f"{base}: ours in {wanted[base]}/, existing in {subdir}/")
    if clashes:
        raise SystemExit("base-name collision, GameState.load_audio would shadow:\n  "
                         + "\n  ".join(clashes))


if __name__ == "__main__":
    check_unique()
    for subdir, name, fn in TARGETS:
        write_wav(subdir, name, fn())
