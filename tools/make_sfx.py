#!/usr/bin/env python3
"""Procedural SFX generator for the Corridor level.

Pure-stdlib (wave/math/random) so it runs on any Python 3 — no numpy needed.
Outputs 16-bit mono 44.1 kHz .wav files into game/assets/audio/level_3_corridor/.

Usage: python3 tools/make_sfx.py
"""

import math
import os
import random
import struct
import wave

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "audio", "level_3_corridor")

def write_wav(name, samples):
    """samples: list of floats in [-1, 1]."""
    peak = max(1e-9, max(abs(s) for s in samples))
    norm = 0.89 / peak  # leave headroom
    path = os.path.normpath(os.path.join(OUT_DIR, name))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            frames += struct.pack("<h", int(max(-1.0, min(1.0, s * norm)) * 32767))
        w.writeframes(bytes(frames))
    print(f"wrote {path} ({len(samples)/SR:.2f}s)")


def silence(seconds):
    return [0.0] * int(SR * seconds)


def mix_into(dest, src, offset_s, gain=1.0):
    off = int(offset_s * SR)
    for i, s in enumerate(src):
        j = off + i
        if j >= len(dest):
            break
        dest[j] += s * gain


class OnePole:
    """Simple one-pole lowpass; bandpass built from two of these."""

    def __init__(self, cutoff_hz):
        self.a = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / SR)
        self.y = 0.0

    def tick(self, x):
        self.y += self.a * (x - self.y)
        return self.y


def bell_strike(freq, dur, brightness=1.0):
    """Inharmonic partials with exponential decay — grandfather-clock bell."""
    partials = [(1.0, 1.0, 1.0), (2.76, 0.55, 1.8), (5.4, 0.25, 2.6), (8.93, 0.12, 3.5)]
    n = int(SR * dur)
    out = [0.0] * n
    for ratio, amp, decay_mult in partials:
        f = freq * ratio
        if f > SR * 0.45:
            continue
        phase = random.uniform(0, math.tau)
        for i in range(n):
            t = i / SR
            env = math.exp(-t * 1.6 * decay_mult)
            out[i] += amp * brightness * env * math.sin(math.tau * f * t + phase)
    # soft attack to avoid click
    for i in range(min(120, n)):
        out[i] *= i / 120
    return out


def make_clock_chime():
    """Three slow, mournful strikes."""
    total = silence(5.5)
    for k in range(3):
        strike = bell_strike(196.0, 3.2, brightness=1.0 - k * 0.12)
        mix_into(total, strike, 0.15 + k * 1.5)
    return total


def make_glass_shatter():
    """Initial crack burst + cascade of high tinkles."""
    total = silence(1.6)
    # crack: short bright noise burst
    burst = []
    hp_prev = 0.0
    for i in range(int(SR * 0.09)):
        x = random.uniform(-1, 1)
        # crude highpass: differentiate
        y = x - hp_prev
        hp_prev = x
        burst.append(y * math.exp(-i / SR * 60))
    mix_into(total, burst, 0.0, 1.2)
    # tinkles: many short decaying high sines at random times
    for _ in range(46):
        f = random.uniform(2400, 9500)
        dur = random.uniform(0.05, 0.30)
        n = int(SR * dur)
        t0 = random.uniform(0.02, 0.9)
        tink = [math.sin(math.tau * f * i / SR) * math.exp(-i / SR * 22) for i in range(n)]
        mix_into(total, tink, t0, random.uniform(0.05, 0.22))
    return total


def make_beartrap_snap():
    """Metallic clack: click transient + ring + low thud."""
    total = silence(0.7)
    # click transient
    click = []
    for i in range(int(SR * 0.012)):
        click.append(random.uniform(-1, 1) * math.exp(-i / SR * 700))
    mix_into(total, click, 0.0, 1.4)
    # metallic ring: detuned high partials, fast decay
    for f, g in [(1370, 0.5), (2140, 0.35), (3290, 0.28), (4630, 0.16)]:
        n = int(SR * 0.45)
        ring = [math.sin(math.tau * f * i / SR) * math.exp(-i / SR * 16) for i in range(n)]
        mix_into(total, ring, 0.004, g)
    # low thud (jaws hitting)
    n = int(SR * 0.25)
    thud = []
    for i in range(n):
        t = i / SR
        f = 110 * math.exp(-t * 9) + 48
        thud.append(math.sin(math.tau * f * t) * math.exp(-t * 18))
    mix_into(total, thud, 0.002, 1.1)
    return total


def make_door_slam():
    """Heavy wooden slam: pitch-dropping thump + body noise + room rumble."""
    total = silence(1.4)
    # thump with falling pitch
    n = int(SR * 0.5)
    thump = []
    for i in range(n):
        t = i / SR
        f = 160 * math.exp(-t * 12) + 38
        thump.append(math.sin(math.tau * f * t) * math.exp(-t * 9))
    mix_into(total, thump, 0.0, 1.3)
    # wooden body: lowpassed noise burst
    lp = OnePole(450)
    body = []
    for i in range(int(SR * 0.22)):
        body.append(lp.tick(random.uniform(-1, 1)) * math.exp(-i / SR * 26))
    mix_into(total, body, 0.0, 1.6)
    # rumble tail
    lp2 = OnePole(90)
    rumble = []
    for i in range(int(SR * 1.1)):
        rumble.append(lp2.tick(random.uniform(-1, 1)) * math.exp(-i / SR * 3.5))
    mix_into(total, rumble, 0.05, 0.9)
    return total


def make_whispers():
    """Loopable bed of breathy syllables: band-limited noise with irregular envelopes."""
    dur = 8.0
    total = silence(dur)
    t = 0.15
    while t < dur - 0.6:
        syl = random.uniform(0.10, 0.34)
        center = random.uniform(1100, 3400)
        lp_hi = OnePole(center * 1.4)
        lp_lo = OnePole(center * 0.6)
        n = int(SR * syl)
        chunk = []
        for i in range(n):
            x = random.uniform(-1, 1)
            band = lp_hi.tick(x) - lp_lo.tick(x)  # crude bandpass
            ph = i / n
            env = math.sin(math.pi * ph) ** 1.6  # breath swell
            # consonant-ish flutter
            flutter = 0.75 + 0.25 * math.sin(math.tau * random.uniform(28, 40) * i / SR)
            chunk.append(band * env * flutter)
        mix_into(total, chunk, t, random.uniform(0.5, 1.0))
        t += syl + random.uniform(0.05, 0.45)
    # gentle loop fade at both ends
    fade = int(SR * 0.3)
    for i in range(fade):
        g = i / fade
        total[i] *= g
        total[-1 - i] *= g
    return total


def main():
    random.seed(217)  # room 217 — reproducible builds
    write_wav("clock_chime.wav", make_clock_chime())
    write_wav("glass_shatter.wav", make_glass_shatter())
    write_wav("beartrap_snap.wav", make_beartrap_snap())
    write_wav("door_slam.wav", make_door_slam())
    write_wav("whispers.wav", make_whispers())


if __name__ == "__main__":
    main()
