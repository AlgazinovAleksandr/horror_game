#!/usr/bin/env python3
"""Procedural SFX for Level 2 (The House).

Pure-stdlib (wave/math/random), same conventions as make_sfx.py.
Outputs 16-bit mono 44.1 kHz .wav files into game/assets/audio/level_2_house/.

Usage: python3 tools/make_sfx_house.py
"""

import math
import os
import random
import struct
import wave

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "audio", "level_2_house")


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


class OnePole:
    def __init__(self, cutoff_hz):
        self.a = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / SR)
        self.y = 0.0

    def tick(self, x):
        self.y += self.a * (x - self.y)
        return self.y


def make_lock_buzz():
    """Harsh electric 'wrong code' buzz: dissonant square pair, tremolo, hard stop."""
    dur = 0.45
    n = int(SR * dur)
    lp = OnePole(1400.0)
    out = []
    for i in range(n):
        t = i / SR
        sq1 = 1.0 if math.sin(2 * math.pi * 110.0 * t) > 0 else -1.0
        sq2 = 1.0 if math.sin(2 * math.pi * 148.5 * t) > 0 else -1.0
        trem = 0.6 + 0.4 * (1.0 if math.sin(2 * math.pi * 13.0 * t) > 0 else 0.0)
        env = min(1.0, t / 0.01) * (1.0 if t < dur - 0.04 else max(0.0, (dur - t) / 0.04))
        out.append(lp.tick((sq1 * 0.6 + sq2 * 0.5) * trem) * env)
    return out


def make_footsteps_above():
    """Slow muffled thumps overhead — someone pacing the floor above."""
    random.seed(47)
    dur = 4.0
    out = [0.0] * int(SR * dur)
    t0 = 0.3
    while t0 < dur - 0.6:
        thump_dur = 0.22
        nlen = int(SR * thump_dur)
        freq = random.uniform(52.0, 68.0)
        lp = OnePole(180.0)
        off = int(t0 * SR)
        for i in range(nlen):
            t = i / SR
            env = math.exp(-t * 22.0)
            x = math.sin(2 * math.pi * freq * t) + random.uniform(-0.25, 0.25)
            j = off + i
            if j < len(out):
                out[j] += lp.tick(x) * env * random.uniform(0.7, 1.0)
        t0 += random.uniform(0.55, 0.85)
    return out


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    write_wav("lock_buzz.wav", make_lock_buzz())
    write_wav("footsteps_above.wav", make_footsteps_above())


if __name__ == "__main__":
    main()
