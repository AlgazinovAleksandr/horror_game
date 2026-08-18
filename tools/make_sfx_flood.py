#!/usr/bin/env python3
"""Procedural SFX for THE DROWNED — the Backrooms Flood's submerged searchables.

    python3 tools/make_sfx_flood.py     # stdlib only, then Godot --import

Writes into game/assets/audio/level_backrooms/:

  flood_knock.wav  THE TELL. A dull, hollow bump — something heavy shifting against
                   something else, under water. One-shot, replayed on a 5-11 s
                   interval by each unsearched SunkenItem, at unit_size 6 so it only
                   resolves inside the room it is in. This is how the object is found
                   in a zone the player crosses with the flashlight OFF.
  flood_haul.wav   THE ANSWER. Water breaking and pouring off something being lifted
                   clear of it. Played once, when the item is searched. After that
                   the item is silent forever, so the wing gets QUIETER as it is
                   emptied — the knocking is a to-do list you clear by ear.

⚠️ SEPARATE FILE FROM make_sfx_backrooms.py ON PURPOSE, for the reason make_sfx_seam.py
gives: that script calls `random.uniform` without seeding, so re-running it to add one
sound rewrites light_pop / rotary_ring / phone_whisper with different noise. This one is
seeded and touches nothing else.

⚠️ WHY A KNOCK AND NOT A HUM. The Flood's own two-layer far-cue/near-confirm beacons
(`seam_draw`/`seam_rip`, `breaker_hum`/`breaker_buzz`) exist to give a BEARING down a
50 m corridor. These do the opposite job: six of them are live at once in a 28 m wing
that already carries eight water beds and the wader, so a continuous bed per item would
be a wall of noise with no direction in it. An intermittent transient is localisable by
the two events either side of it and leaves the room silent in between, which is where
the wader and the drips live.

⚠️ NEITHER SOUND IS A LOOP, so neither needs the circular-buffer treatment
make_sfx_seam.py uses; both are played as one-shots and both must END, or the "it went
quiet once I searched it" beat cannot be heard.
"""

import math
import os
import random
import struct
import wave

SR = 44100
TAU = math.tau
SEED = 4112

OUT_DIR = os.path.normpath(os.path.join(
    os.path.dirname(__file__), "..", "game", "assets", "audio", "level_backrooms"))


def write_wav(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    norm = 0.89 / peak
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    acc = 0.0
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = max(-1.0, min(1.0, s * norm))
            acc += v * v
            frames += struct.pack("<h", int(v * 32767))
        w.writeframes(bytes(frames))
    rms = math.sqrt(acc / len(samples))
    dbfs = 20.0 * math.log10(rms + 1e-12)
    # ⚠️ PRINTED BECAUSE THE GAIN MUST BE SET FROM IT, never from a number that reads as
    # sensible. `water.wav` sits ~20 dB below every other asset in this level and its
    # shipped -6 dB was inaudible for months. backrooms_zone3.gd quotes these figures
    # next to KNOCK_DB / HAUL_DB; if this number moves, those move.
    print("wrote %s  %.2fs  RMS %.1f dBFS" % (path, len(samples) / SR, dbfs))
    return dbfs


class OnePole:
    def __init__(self, cutoff_hz):
        self.a = math.exp(-TAU * cutoff_hz / SR)
        self.z = 0.0

    def tick(self, x):
        self.z = x * (1.0 - self.a) + self.z * self.a
        return self.z


class HighPass:
    def __init__(self, cutoff_hz):
        self.lp = OnePole(cutoff_hz)

    def tick(self, x):
        return x - self.lp.tick(x)


def make_knock():
    """1.6 s. Two hollow bumps and the water closing over them.

    The bumps are damped low sines (78 / 104 Hz) with a click transient, run through a
    low-pass: under water there is no high end, which is what stops this reading as a
    footstep on wood. The slosh is band-limited noise on a slow envelope, arriving a
    beat AFTER the second bump — the displaced water is the part that says `submerged`.
    """
    rng = random.Random(SEED)
    dur = 1.6
    n = int(SR * dur)
    out = [0.0] * n

    for at, freq, amp in ((0.02, 78.0, 1.0), (0.31, 104.0, 0.62)):
        start = int(at * SR)
        for k in range(n - start):
            t = k / SR
            env = math.exp(-t * 13.0)
            body = math.sin(TAU * freq * t) * env
            # A short wooden/steel click on the leading edge, immediately swallowed.
            click = math.sin(TAU * 640.0 * t) * math.exp(-t * 160.0) * 0.35
            out[start + k] += (body + click) * amp

    # The water closing back over it.
    lp = OnePole(1300.0)
    hp = HighPass(180.0)
    slosh_at = int(0.36 * SR)
    for k in range(n - slosh_at):
        t = k / SR
        env = (1.0 - math.exp(-t * 26.0)) * math.exp(-t * 3.4)
        s = hp.tick(lp.tick(rng.uniform(-1.0, 1.0)))
        out[slosh_at + k] += s * env * 0.55

    # Everything under water is dull. One more pole across the whole thing.
    dull = OnePole(2400.0)
    return [dull.tick(s) for s in out]


def make_haul():
    """2.4 s. Something big coming up out of standing water.

    Three parts, in order, because the ORDER is the readable part: a wet suck as the
    surface lets go, a low grinding drag while it moves, then a long pour as the water
    runs back off it. The pour outlasts the drag by a full second, which is what makes
    the object feel like it held water.
    """
    rng = random.Random(SEED + 1)
    dur = 2.4
    n = int(SR * dur)
    out = [0.0] * n

    # 1. The suck — a fast upward sweep of band-limited noise, 0.00-0.35 s.
    lp1 = OnePole(700.0)
    for k in range(int(0.42 * SR)):
        t = k / SR
        env = (1.0 - math.exp(-t * 40.0)) * math.exp(-t * 7.0)
        lp1.a = math.exp(-TAU * (700.0 + 2600.0 * t) / SR)
        out[k] += lp1.tick(rng.uniform(-1.0, 1.0)) * env * 0.9

    # 2. The drag — a low rumble with a slow tremor, 0.10-1.30 s.
    drag_at = int(0.10 * SR)
    lp2 = OnePole(320.0)
    for k in range(int(1.2 * SR)):
        t = k / SR
        env = min(1.0, t * 6.0) * math.exp(-t * 1.7)
        rumble = lp2.tick(rng.uniform(-1.0, 1.0))
        tone = math.sin(TAU * 58.0 * t) * 0.35
        tremor = 0.75 + 0.25 * math.sin(TAU * 7.5 * t)
        out[drag_at + k] += (rumble * 1.1 + tone) * env * tremor * 0.8

    # 3. The pour — a thinning stream of droplets, 0.55 s to the end.
    pour_at = int(0.55 * SR)
    hp = HighPass(420.0)
    lp3 = OnePole(5200.0)
    for k in range(n - pour_at):
        t = k / SR
        env = (1.0 - math.exp(-t * 18.0)) * math.exp(-t * 1.5)
        s = hp.tick(lp3.tick(rng.uniform(-1.0, 1.0)))
        out[pour_at + k] += s * env * 0.5
    # Discrete drips falling back in, scattered through the pour and never past the end.
    for _ in range(22):
        at = rng.uniform(0.7, dur - 0.35)
        start = int(at * SR)
        freq = rng.uniform(700.0, 2600.0)
        amp = rng.uniform(0.12, 0.4)
        for k in range(min(int(0.28 * SR), n - start)):
            t = k / SR
            # A drip is a short rising chirp: the cavity it leaves shrinks as it closes.
            out[start + k] += math.sin(TAU * (freq + 2400.0 * t) * t) \
                * math.exp(-t * 34.0) * amp * 0.35
    return out


def main():
    print("FLOOD SFX -> %s" % OUT_DIR)
    write_wav("flood_knock.wav", make_knock())
    write_wav("flood_haul.wav", make_haul())


if __name__ == "__main__":
    main()
