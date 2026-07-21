#!/usr/bin/env python3
"""Procedural SFX for the redesigned Intro Room (see INTRO.md).

Pure-stdlib (wave/math/random), same conventions as make_sfx_extra.py.
Outputs 16-bit mono 44.1 kHz .wav files into game/assets/audio/intro/:

  switch_clunk.wav          heavy old wall-switch throw + spark-crackle tail
  fluorescent_buzz_on.wav   ceiling tubes stuttering on
  emergency_hum.wav         very quiet loopable electrical hum (path-glow bed)
  gurney_creak.wav          short metal-frame creak, plays as the player sits up

Usage: python3 tools/make_sfx_intro.py
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
    def __init__(self, cutoff_hz):
        self.a = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / SR)
        self.y = 0.0

    def tick(self, x):
        self.y += self.a * (x - self.y)
        return self.y


def make_switch_clunk():
    """Heavy old asylum wall-switch throw — lower/heavier than the Lab's breaker
    clunk, with a short electrical spark-crackle tail instead of a hum surge."""
    random.seed(4702)
    dur = 0.75
    n = int(SR * dur)
    lp = OnePole(2600.0)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        # Click transient.
        click = math.exp(-t * 300.0) * random.uniform(-1.0, 1.0)
        # Low mechanical thunk, lower base + slower decay than breaker_throw's
        # 130 Hz/-6.0 so it reads heavier and older, not a duplicate.
        thunk_f = 110.0 * math.exp(-t * 5.0) + 40.0
        thunk = math.sin(2 * math.pi * thunk_f * t) * math.exp(-t * 12.0)
        out[i] = lp.tick(click * 0.7 + thunk * 0.9)
    # Spark-crackle tail: a handful of short noise bursts through a tight band,
    # in the last ~0.15s.
    tail_start = dur - 0.15
    bp = OnePole(3500.0)
    t0 = tail_start
    while t0 < dur:
        burst_len = int(0.012 * SR)
        off = int(t0 * SR)
        for i in range(burst_len):
            j = off + i
            if j >= n:
                break
            decay = math.exp(-i / burst_len * 5.0)
            spark = bp.tick(random.uniform(-1.0, 1.0)) * decay
            out[j] += spark * 0.5
        t0 += random.uniform(0.02, 0.045)
    return out


def make_fluorescent_buzz_on():
    """Ceiling tubes stuttering to life — 2-3 buzzy stutters then a steady tail."""
    random.seed(9142)
    stutters = [0.05, 0.08, 0.14]
    gaps = [0.09, 0.05]
    tail = 0.5
    dur = sum(stutters) + sum(gaps) + tail
    n = int(SR * dur)
    out = [0.0] * n

    def band_noise_gen():
        lo = OnePole(180.0)
        hi = OnePole(900.0)
        while True:
            noise = random.uniform(-1.0, 1.0)
            yield hi.tick(noise) - lo.tick(noise)

    gen = band_noise_gen()
    t_cursor = 0.0
    for k, s_len in enumerate(stutters):
        off = int(t_cursor * SR)
        s_n = int(s_len * SR)
        for i in range(s_n):
            j = off + i
            if j >= n:
                break
            t = i / SR
            env = min(1.0, t / 0.005) * min(1.0, (s_len - t) / 0.01)
            buzz = next(gen) * 0.6
            hum60 = 0.25 * math.sin(2 * math.pi * 60.0 * (off + i) / SR)
            out[j] = (buzz + hum60) * env
        t_cursor += s_len
        if k < len(gaps):
            t_cursor += gaps[k]

    # Steady tail: crossfades in right after the last stutter, decays to silence.
    tail_off = int(t_cursor * SR)
    tail_n = n - tail_off
    for i in range(tail_n):
        t = i / tail_n if tail_n > 0 else 0.0
        env = min(1.0, i / (0.02 * SR)) * (1.0 - t)
        hum = math.sin(2 * math.pi * 120.0 * (tail_off + i) / SR)
        noise = 0.06 * random.uniform(-1.0, 1.0)
        j = tail_off + i
        if 0 <= j < n:
            out[j] += (hum * 0.35 + noise) * env
    return out


def make_emergency_hum():
    """Very quiet, low, loopable electrical hum — the path-glow lights' bed."""
    random.seed(55)
    dur = 2.6
    n = int(SR * dur)
    lp = OnePole(150.0)
    out = []
    f1, f2 = 58.0, 63.0  # a few Hz apart -> slow beat throb
    for i in range(n):
        t = i / SR
        hum = math.sin(2 * math.pi * f1 * t) + math.sin(2 * math.pi * f2 * t)
        noise = 0.03 * random.uniform(-1.0, 1.0)
        out.append(lp.tick(hum * 0.5 + noise) * 0.35)
    fade = int(0.05 * SR)
    for i in range(fade):
        g = i / fade
        out[i] *= g
        out[n - 1 - i] *= g
    return out


def make_gurney_creak():
    """Short metal-frame creak/groan — a bed shifting under weight, not a pipe."""
    random.seed(1804)
    dur = 0.6
    n = int(SR * dur)
    lp = OnePole(1400.0)
    out = []
    base = 220.0
    for i in range(n):
        t = i / SR
        # Quick upward bend then settle, thinner/higher register than pipe_groan.
        f = base + 60.0 * math.exp(-t * 6.0) * math.sin(2 * math.pi * 4.0 * t)
        s = math.sin(2 * math.pi * f * t)
        s += 0.4 * math.sin(2 * math.pi * f * 1.9 * t)
        s += 0.22 * random.uniform(-1.0, 1.0)
        env = min(1.0, t / 0.03) * math.exp(-t * 3.2)
        out.append(lp.tick(s) * env * 0.65)
    return out


def main():
    write_wav("intro", "switch_clunk.wav", make_switch_clunk())
    write_wav("intro", "fluorescent_buzz_on.wav", make_fluorescent_buzz_on())
    write_wav("intro", "emergency_hum.wav", make_emergency_hum())
    write_wav("intro", "gurney_creak.wav", make_gurney_creak())


if __name__ == "__main__":
    main()
