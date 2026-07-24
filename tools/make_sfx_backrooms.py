#!/usr/bin/env python3
"""Procedural SFX generator for the Backrooms level.

Pure-stdlib (wave/math/random) so it runs on any Python 3 — no numpy needed.
Outputs 16-bit mono 44.1 kHz .wav files into game/assets/audio/level_backrooms/.

Files:
  fluorescent_hum.wav  seamless looping 60 Hz electrical drone (background bed)
  light_pop.wav        sharp metallic electrical snap (failed turn / unlink)
  rotary_ring.wav      distant old telephone bell, ring-ring-pause pattern
  phone_whisper.wav    lo-fi distorted overlapping voices (trap-note bed)

Usage: python3 tools/make_sfx_backrooms.py
"""

import math
import os
import random
import struct
import wave

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "audio", "level_backrooms")

TAU = math.tau


def write_wav(name, samples):
    """samples: list of floats in [-1, 1]."""
    peak = max(1e-9, max(abs(s) for s in samples))
    norm = 0.89 / peak  # leave headroom
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.normpath(os.path.join(OUT_DIR, name))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            frames += struct.pack("<h", int(max(-1.0, min(1.0, s * norm)) * 32767))
        w.writeframes(bytes(frames))
    print(f"wrote {path} ({len(samples) / SR:.2f}s)")


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
    """Simple one-pole lowpass."""

    def __init__(self, cutoff_hz):
        self.a = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / SR)
        self.y = 0.0

    def tick(self, x):
        self.y += self.a * (x - self.y)
        return self.y


# --------------------------------------------------------------------- hum

def make_fluorescent_hum():
    """Seamless 4 s loop. Every partial is a multiple of 60 Hz, so a whole
    number of cycles fits in 4 s (240 fundamental cycles) — the buffer wraps
    with no click. Mains buzz (60/120/180) + a thin ballast whine (4200/8400)."""
    dur = 4.0
    n = int(SR * dur)
    out = [0.0] * n
    # [freq_hz, amplitude] — all multiples of 60 for seamless looping
    partials = [
        [60, 0.55], [120, 0.40], [180, 0.18], [240, 0.08],
        [4200, 0.05], [8400, 0.035],
    ]
    for i in range(n):
        s = 0.0
        for f, a in partials:
            s += a * math.sin(TAU * f * i / SR)
        # slow tonal shimmer at 6 Hz... but 6 isn't a /60 divisor of 4 s loop.
        # 5 Hz completes 20 cycles in 4 s -> seamless.
        shimmer = 0.85 + 0.15 * math.sin(TAU * 5.0 * i / SR)
        out[i] = s * shimmer * 0.5
    return out


# --------------------------------------------------------------------- sprawl hum

def make_sprawl_wall_hum():
    """Low, slightly irregular breathing drone — Zone 2's (the Sprawl) positive
    audible tell at the real glitch wall (BUG_FIX.md 3.5). Deliberately NOT built
    from mains-multiple partials like fluorescent_hum, so the two read as two
    different sounds rather than blending into one. Seamless 4 s loop."""
    dur = 4.0
    n = int(SR * dur)
    out = [0.0] * n
    # Two closely-detuned low oscillators beat softly against each other. Both
    # frequencies are multiples of 0.25 Hz so a whole number of cycles fits the
    # 4 s loop and the seam is silent.
    f1, f2 = 88.0, 88.5
    for i in range(n):
        t = i / SR
        s = 0.55 * math.sin(TAU * f1 * t) + 0.45 * math.sin(TAU * f2 * t)
        s += 0.12 * math.sin(TAU * f1 * 2.0 * t)
        # Slow organic swell, 0.5 Hz -> 2 whole cycles in 4 s.
        breathe = 0.75 + 0.25 * math.sin(TAU * 0.5 * t)
        out[i] = s * breathe * 0.5
    return out


# --------------------------------------------------------------------- pop

def make_light_pop():
    """Sharp electrical snap: an instant transient + a short bright crackle
    with a fast decay, lightly band-limited so it reads 'metallic'."""
    dur = 0.35
    n = int(SR * dur)
    out = [0.0] * n
    lp = OnePole(7000)
    # initial spike
    for i in range(n):
        t = i / SR
        env = math.exp(-t * 38.0)
        crackle = (random.uniform(-1, 1)) * env
        ring = math.sin(TAU * 2300 * t) * math.exp(-t * 55.0) * 0.6
        ring += math.sin(TAU * 5200 * t) * math.exp(-t * 70.0) * 0.3
        out[i] = lp.tick(crackle) * 0.8 + ring
    # hard click at sample 0
    out[0] += 0.9
    out[1] += 0.5
    return out


# --------------------------------------------------------------------- ring

def make_rotary_ring():
    """Old electromechanical bell: two clappers striking a ~1100/1400 Hz bell
    in a fast trill. Playtest follow-up: the old 2 x 0.9s bursts (~2s of audible
    ring inside a 4s one-shot clip, retriggered every RING_INTERVAL=7s) read as
    too brief to register. Now 4 bursts back to back with short gaps between —
    ~5.3s of near-continuous ring, unmistakable. Not a seamless loop (this clip
    is one-shot per interval in rotary_phone.gd, never manually looped), so no
    trailing silence is needed."""
    bursts = [(0.10, 1.1), (1.40, 1.1), (2.70, 1.1), (4.00, 1.1)]  # (start_s, length_s)
    dur = 5.4
    n = int(SR * dur)
    out = [0.0] * n
    for start, length in bursts:
        bn = int(SR * length)
        chunk = [0.0] * bn
        for i in range(bn):
            t = i / SR
            # 20 Hz clapper trill gates the bell tone
            trill = 0.5 + 0.5 * math.sin(TAU * 20.0 * t)
            trill = trill ** 3
            env = math.exp(-((t - length / 2) ** 2) / (2 * (length / 3) ** 2))
            bell = math.sin(TAU * 1100 * t) * 0.6 + math.sin(TAU * 1420 * t) * 0.4
            bell += math.sin(TAU * 2200 * t) * 0.15  # bright partial
            chunk[i] = bell * trill * env
        mix_into(out, chunk, start, 0.9)
    # distance: gentle lowpass over the whole thing
    lp = OnePole(2600)
    for i in range(n):
        out[i] = lp.tick(out[i])
    # click-free start/end fade (one-shot clip, not a loop)
    fade = int(SR * 0.25)
    for i in range(fade):
        g = i / fade
        out[i] *= g
        out[-1 - i] *= g
    return out


# --------------------------------------------------------------------- whisper

def make_phone_whisper():
    """Lo-fi overlapping voices: several layers of formant-bandpassed noise
    bursts at speech cadence, detuned and bit-crushed to sound like distorted
    voices bleeding through a phone line."""
    dur = 5.0
    n = int(SR * dur)
    total = [0.0] * n
    # three overlapping 'speakers'
    for _layer in range(3):
        t = random.uniform(0.0, 0.4)
        while t < dur - 0.3:
            syl = random.uniform(0.10, 0.26)  # syllable length
            sn = int(SR * syl)
            chunk = [0.0] * sn
            # formant centre wanders per syllable
            f1 = random.uniform(350, 900)
            bp1 = OnePole(f1 * 1.4)
            bp2 = OnePole(f1 * 0.7)
            for i in range(sn):
                tt = i / SR
                env = math.sin(math.pi * i / sn) ** 1.5
                noise = random.uniform(-1, 1)
                band = bp1.tick(noise) - bp2.tick(noise)
                flutter = 0.7 + 0.3 * math.sin(TAU * random.uniform(24, 38) * tt)
                chunk[i] = band * env * flutter
            mix_into(total, chunk, t, random.uniform(0.5, 0.9))
            t += syl + random.uniform(0.04, 0.30)
    # phone-line band-limit + bit-crush
    lp = OnePole(3000)
    hp_prev = 0.0
    for i in range(n):
        v = lp.tick(total[i])
        # crude highpass to thin it
        hp = v - hp_prev
        hp_prev = v
        # bit-crush to 7-bit for lo-fi grit
        v = round(hp * 64) / 64
        total[i] = v
    # loop-safe fade
    fade = int(SR * 0.3)
    for i in range(fade):
        g = i / fade
        total[i] *= g
        total[-1 - i] *= g
    return total


def main():
    random.seed(404)  # the level not found — reproducible builds
    write_wav("fluorescent_hum.wav", make_fluorescent_hum())
    write_wav("sprawl_wall_hum.wav", make_sprawl_wall_hum())
    write_wav("light_pop.wav", make_light_pop())
    write_wav("rotary_ring.wav", make_rotary_ring())
    write_wav("phone_whisper.wav", make_phone_whisper())


if __name__ == "__main__":
    main()
