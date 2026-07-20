#!/usr/bin/env python3
"""Procedural SFX generator for Level 5 — KONTUR.

Pure-stdlib (wave/math/random) so it runs on any Python 3 — no numpy needed.
Outputs 16-bit mono 44.1 kHz .wav files into game/assets/audio/level_5_kontur/.

Files:
  ambient_kontur.wav   seamless looping concrete-room bed (sub rumble + air + drips)
  breathing_behind.wav looping slow breath cycle — the Escort at your back (Gate 4)
  door_seal.wav        heavy steel door unlatching and swinging (Gate 1)
  acid_hiss.wav        vinegar eating through the fungal barrier (Gate 2)
  pedestal_alarm.wav   a cold two-tone institutional alert (Gate 3, taking the bait)
  kontur_flash.wav     the wrong-answer sting that rides every flash_scare
  screamer_kontur.wav  the fatal screamer for LEVEL_SCREAMERS[5]

Seeded, so re-running reproduces byte-identical output.

Usage: python3 tools/make_sfx_kontur.py
Then:  /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import
"""

import math
import os
import random
import struct
import wave

SR = 44100
TAU = math.tau
OUT_DIR = os.path.join(
    os.path.dirname(__file__), "..", "game", "assets", "audio", "level_5_kontur"
)

random.seed(4112)  # O-41 / Object 12


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


def n_samples(seconds):
    return int(seconds * SR)


def fade_edges(buf, ms=40):
    """Taper both ends so a looped clip does not click at the seam."""
    k = min(int(SR * ms / 1000.0), len(buf) // 2)
    for i in range(k):
        g = i / k
        buf[i] *= g
        buf[-1 - i] *= g
    return buf


# ---------------------------------------------------------------- ambient bed

def ambient_kontur(seconds=12.0):
    """Concrete room tone: a sub rumble, a band of air, and occasional drips.

    Every periodic component completes a whole number of cycles over the clip, so
    the loop point is seamless without a crossfade.
    """
    n = n_samples(seconds)
    buf = [0.0] * n
    # Whole-cycle partials -> seamless loop.
    partials = [(2, 0.34), (3, 0.20), (5, 0.12), (8, 0.07)]
    for cycles, amp in partials:
        f = cycles / seconds
        phase = random.random() * TAU
        for i in range(n):
            buf[i] += amp * math.sin(TAU * f * i / SR + phase)

    # Filtered noise "air" — a slow one-pole lowpass over white noise.
    prev = 0.0
    for i in range(n):
        white = random.uniform(-1.0, 1.0)
        prev += 0.0025 * (white - prev)
        buf[i] += prev * 5.5

    # A few water drips, well inside the clip so they never straddle the seam.
    for _ in range(5):
        start = random.randint(n_samples(0.5), n - n_samples(1.2))
        f0 = random.uniform(900.0, 1700.0)
        dur = n_samples(random.uniform(0.10, 0.18))
        for j in range(dur):
            t = j / SR
            env = math.exp(-t * 42.0)
            # Falling pitch gives the hollow "plink into water" read.
            f = f0 * (1.0 - 0.35 * (j / dur))
            buf[start + j] += 0.35 * env * math.sin(TAU * f * t)

    return fade_edges(buf, ms=25)


# ---------------------------------------------------------------- gate 4

def breathing_behind(seconds=8.0):
    """Slow breath cycle: 4 breaths over 8 s, looping cleanly.

    Deliberately low and close-mic'd — it is meant to sit just behind the player's
    head and make turning around feel irresistible.
    """
    n = n_samples(seconds)
    buf = [0.0] * n
    breaths = 4
    period = n // breaths
    for b in range(breaths):
        base = b * period
        # Inhale: rising filtered noise. Exhale: longer, darker, falling.
        for phase_name, offset, dur, bright, gain in (
            ("in", 0.0, 0.34, 0.010, 0.85),
            ("out", 0.46, 0.44, 0.005, 1.0),
        ):
            start = base + int(period * offset)
            length = int(period * dur)
            prev = 0.0
            for j in range(length):
                x = j / length
                # Bell-shaped breath envelope.
                env = math.sin(math.pi * x) ** 1.4
                white = random.uniform(-1.0, 1.0)
                # Inhale brightens as it peaks; exhale darkens as it falls.
                cutoff = bright * (1.0 + (x if phase_name == "in" else 1.0 - x))
                prev += cutoff * (white - prev)
                idx = start + j
                if idx < n:
                    buf[idx] += prev * 7.0 * env * gain
    return fade_edges(buf, ms=60)


# ---------------------------------------------------------------- gate 1

def door_seal(seconds=2.2):
    """Heavy steel: a latch clack, then a long low groan of the door swinging."""
    n = n_samples(seconds)
    buf = [0.0] * n

    # Latch clack — short, bright, metallic.
    for j in range(n_samples(0.09)):
        t = j / SR
        env = math.exp(-t * 55.0)
        buf[j] += env * (
            0.5 * math.sin(TAU * 1850.0 * t)
            + 0.3 * math.sin(TAU * 2670.0 * t)
            + 0.35 * random.uniform(-1.0, 1.0)
        )

    # The swing: a descending groan with a slow tremolo (hinge stutter).
    start = n_samples(0.12)
    dur = n - start
    for j in range(dur):
        t = j / SR
        x = j / dur
        env = math.sin(math.pi * min(1.0, x * 1.15)) ** 0.7
        f = 148.0 * (1.0 - 0.42 * x)
        tremolo = 1.0 + 0.30 * math.sin(TAU * 7.5 * t)
        buf[start + j] += 0.55 * env * tremolo * (
            math.sin(TAU * f * t) + 0.45 * math.sin(TAU * f * 2.02 * t)
        )
    return buf


# ---------------------------------------------------------------- gate 2

def acid_hiss(seconds=2.6):
    """Vinegar on O-41: a bright fizz that swells, then collapses into wet pops."""
    n = n_samples(seconds)
    buf = [0.0] * n
    prev = 0.0
    for i in range(n):
        x = i / n
        # Swell in fast, decay slowly.
        env = min(1.0, x * 8.0) * math.exp(-x * 2.3)
        white = random.uniform(-1.0, 1.0)
        # Highpass-ish: keep the difference from a lowpassed copy.
        prev += 0.30 * (white - prev)
        buf[i] += (white - prev) * 0.9 * env

    # Wet pops as the mass gives way.
    for _ in range(14):
        start = random.randint(n_samples(0.2), n - n_samples(0.1))
        f0 = random.uniform(160.0, 520.0)
        dur = n_samples(random.uniform(0.02, 0.06))
        for j in range(dur):
            t = j / SR
            env = math.exp(-t * 90.0)
            buf[start + j] += 0.30 * env * math.sin(TAU * f0 * t)
    return buf


# ---------------------------------------------------------------- gate 3

def pedestal_alarm(seconds=2.4):
    """Two-tone institutional alert — cold, procedural, faintly disappointed."""
    n = n_samples(seconds)
    buf = [0.0] * n
    tones = [740.0, 560.0]
    beat = n_samples(0.3)
    for k in range(int(seconds / 0.6)):
        for ti, f in enumerate(tones):
            start = k * beat * 2 + ti * beat
            if start + beat >= n:
                break
            for j in range(beat):
                t = j / SR
                # Hard-ish gate with short edges — electronic, not musical.
                env = min(1.0, j / (SR * 0.006)) * min(
                    1.0, (beat - j) / (SR * 0.02)
                )
                buf[start + j] += 0.5 * env * (
                    math.sin(TAU * f * t) + 0.25 * math.sin(TAU * f * 3.0 * t)
                )
    return buf


# ---------------------------------------------------------------- stings

def kontur_flash(seconds=1.1):
    """Wrong-answer sting: an impact, then a fast downward spore-cloud whoosh."""
    n = n_samples(seconds)
    buf = [0.0] * n
    # Impact.
    for j in range(n_samples(0.22)):
        t = j / SR
        env = math.exp(-t * 26.0)
        f = 120.0 * math.exp(-t * 7.0) + 42.0
        buf[j] += env * (0.9 * math.sin(TAU * f * t) + 0.5 * random.uniform(-1.0, 1.0))
    # Downward whoosh.
    prev = 0.0
    for i in range(n):
        x = i / n
        env = math.exp(-x * 4.2) * min(1.0, x * 14.0)
        white = random.uniform(-1.0, 1.0)
        prev += (0.05 * (1.0 - x) + 0.004) * (white - prev)
        buf[i] += prev * 5.0 * env
    return buf


def screamer_kontur(seconds=2.0):
    """Fatal screamer bed: a shriek layered over a rising swarm of dry rustle."""
    n = n_samples(seconds)
    buf = [0.0] * n
    # Shriek — detuned saw-ish stack sliding upward.
    for i in range(n):
        t = i / SR
        x = i / n
        env = min(1.0, x * 30.0) * math.exp(-x * 1.6)
        f = 420.0 + 900.0 * x
        s = 0.0
        for h, a in ((1.0, 1.0), (2.01, 0.55), (3.02, 0.32), (4.97, 0.18)):
            s += a * math.sin(TAU * f * h * t)
        buf[i] += 0.42 * env * s
    # Spore swarm: dry, crackling noise that swells underneath.
    prev = 0.0
    for i in range(n):
        x = i / n
        env = min(1.0, x * 3.0) * math.exp(-x * 1.1)
        white = random.uniform(-1.0, 1.0)
        prev += 0.42 * (white - prev)
        buf[i] += (white - prev) * 1.4 * env
    return buf


# ---------------------------------------------------------------- main

def main():
    write_wav("ambient_kontur.wav", ambient_kontur())
    write_wav("breathing_behind.wav", breathing_behind())
    write_wav("door_seal.wav", door_seal())
    write_wav("acid_hiss.wav", acid_hiss())
    write_wav("pedestal_alarm.wav", pedestal_alarm())
    write_wav("kontur_flash.wav", kontur_flash())
    write_wav("screamer_kontur.wav", screamer_kontur())


if __name__ == "__main__":
    main()
