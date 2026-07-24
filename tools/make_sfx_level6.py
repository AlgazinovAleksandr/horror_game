#!/usr/bin/env python3
"""Procedural SFX generator for Level 6 — THE BREACH (Object 12, loose).

Pure-stdlib (wave/math/random) so it runs on any Python 3 — no numpy needed.
Outputs 16-bit mono 44.1 kHz .wav files into game/assets/audio/level_6_breach/.
Follows the exact structure of tools/make_sfx_kontur.py.

Files:
  ambient_breach.wav      seamless looping bed — wetter/dirtier than KONTUR's,
                           an irregular throb under the rumble (something alive)
  door_slam.wav           SlamDoor.interact() — sharp heavy slam + latch
  door_batter.wav         SlamDoor's periodic battering thud (replayed on a timer,
                           not a seamless loop)
  door_break.wav          SlamDoor giving way — wood/metal splintering burst
  blast_door_slam.wav     PurgeChamber's heavier, slower, more mechanical slam
  shield_stagger.wav      Object 12's wound-recoil sting (light-weapon stagger)
  shield_drain_loop.wav   low sizzling loop while sustained aimed light connects
  screamer_breach.wav     the fatal screamer for LEVEL_SCREAMERS[6]
  creature_growl_near.wav proximity stinger during CHASE

Seeded, so re-running reproduces byte-identical output.

Usage: python3 tools/make_sfx_level6.py
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
    os.path.dirname(__file__), "..", "game", "assets", "audio", "level_6_breach"
)

random.seed(612)  # level 6, containment Breach


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

def ambient_breach(seconds=14.0):
    """Wetter and dirtier than KONTUR's bed: sub rumble, filtered air, an
    irregular throb (something breathing under the floor) and more frequent,
    wetter drips. Every periodic component completes a whole number of cycles
    over the clip, so the loop point is seamless.
    """
    n = n_samples(seconds)
    buf = [0.0] * n
    partials = [(2, 0.30), (3, 0.22), (5, 0.16), (7, 0.09)]
    for cycles, amp in partials:
        f = cycles / seconds
        phase = random.random() * TAU
        for i in range(n):
            buf[i] += amp * math.sin(TAU * f * i / SR + phase)

    # A slow throb — two whole-cycle tones close enough in frequency to beat
    # against each other, reading as organic rather than mechanical, while each
    # still completes an integer number of cycles (keeps the loop seamless).
    for cycles, amp in [(4, 0.14), (9, 0.11)]:
        f = cycles / seconds
        phase = random.random() * TAU
        for i in range(n):
            buf[i] += amp * math.sin(TAU * f * i / SR + phase)

    prev = 0.0
    for i in range(n):
        white = random.uniform(-1.0, 1.0)
        prev += 0.003 * (white - prev)
        buf[i] += prev * 6.0

    # Frequent wet drips/plops, well inside the clip.
    for _ in range(9):
        start = random.randint(n_samples(0.3), n - n_samples(1.0))
        f0 = random.uniform(180.0, 520.0)
        dur = n_samples(random.uniform(0.08, 0.16))
        for j in range(dur):
            t = j / SR
            env = math.exp(-t * 34.0)
            f = f0 * (1.0 - 0.4 * (j / dur))
            buf[start + j] += 0.38 * env * math.sin(TAU * f * t)
    return fade_edges(buf, ms=25)


# ---------------------------------------------------------------- doors

def door_slam(seconds=0.9):
    """Sharp heavy slam + latch clack."""
    n = n_samples(seconds)
    buf = [0.0] * n
    for j in range(n_samples(0.28)):
        t = j / SR
        env = math.exp(-t * 22.0)
        f = 90.0 * math.exp(-t * 9.0) + 45.0
        buf[j] += env * (0.85 * math.sin(TAU * f * t) + 0.6 * random.uniform(-1.0, 1.0))
    # Latch clack right after the impact settles.
    start = n_samples(0.12)
    for j in range(n_samples(0.06)):
        t = j / SR
        env = math.exp(-t * 60.0)
        idx = start + j
        if idx < n:
            buf[idx] += env * (0.5 * math.sin(TAU * 2100.0 * t) + 0.4 * random.uniform(-1.0, 1.0))
    return buf


def door_batter(seconds=0.5):
    """A single heavy impact thud — replayed on a timer by slam_door.gd, not
    looped as an audio asset."""
    n = n_samples(seconds)
    buf = [0.0] * n
    for j in range(n):
        t = j / SR
        env = math.exp(-t * 14.0)
        f = 70.0 * math.exp(-t * 6.0) + 38.0
        buf[j] += env * (0.9 * math.sin(TAU * f * t) + 0.45 * random.uniform(-1.0, 1.0))
    return buf


def door_break(seconds=0.8):
    """Wood/metal splintering burst — bright noise with a falling metallic ring."""
    n = n_samples(seconds)
    buf = [0.0] * n
    prev = 0.0
    for i in range(n):
        x = i / n
        env = math.exp(-x * 6.0) * min(1.0, x * 40.0)
        white = random.uniform(-1.0, 1.0)
        prev += 0.5 * (white - prev)
        buf[i] += (white - prev) * 1.2 * env
    for f0 in (1800.0, 2600.0, 3300.0):
        for j in range(n_samples(0.35)):
            t = j / SR
            env = math.exp(-t * 18.0)
            buf[j] += 0.18 * env * math.sin(TAU * f0 * t)
    return buf


def blast_door_slam(seconds=1.8):
    """Heavier, slower, more mechanical than door_slam — the purge chamber's
    one-shot blast door."""
    n = n_samples(seconds)
    buf = [0.0] * n
    for j in range(n_samples(0.4)):
        t = j / SR
        env = math.exp(-t * 10.0)
        f = 55.0 * math.exp(-t * 5.0) + 28.0
        buf[j] += env * (0.9 * math.sin(TAU * f * t) + 0.5 * random.uniform(-1.0, 1.0))
    # A mechanical seal hiss/clunk tail.
    start = n_samples(0.35)
    dur = n - start
    prev = 0.0
    for j in range(dur):
        t = j / SR
        x = j / dur
        env = math.exp(-x * 3.0) * min(1.0, x * 20.0)
        white = random.uniform(-1.0, 1.0)
        prev += 0.08 * (white - prev)
        idx = start + j
        if idx < n:
            buf[idx] += prev * 3.0 * env
    return buf


# ---------------------------------------------------------------- creature

def shield_stagger(seconds=1.0):
    """A wet/electrical shriek-recoil sting — Object 12 buckling under sustained
    light."""
    n = n_samples(seconds)
    buf = [0.0] * n
    for i in range(n):
        t = i / SR
        x = i / n
        env = math.exp(-x * 5.0) * min(1.0, x * 60.0)
        f = 900.0 * math.exp(-x * 4.0) + 140.0
        buf[i] += 0.5 * env * (math.sin(TAU * f * t) + 0.4 * math.sin(TAU * f * 2.7 * t))
    prev = 0.0
    for i in range(n):
        x = i / n
        env = math.exp(-x * 4.0) * min(1.0, x * 30.0)
        white = random.uniform(-1.0, 1.0)
        prev += 0.4 * (white - prev)
        buf[i] += (white - prev) * 0.9 * env
    return buf


def shield_drain_loop(seconds=2.0):
    """Low sizzling loop — plays while the player holds sustained aimed light on
    the creature. Seamless loop (whole-cycle partials)."""
    n = n_samples(seconds)
    buf = [0.0] * n
    prev = 0.0
    for i in range(n):
        white = random.uniform(-1.0, 1.0)
        prev += 0.09 * (white - prev)
        buf[i] += prev * 4.5
    for cycles, amp in [(6, 0.10), (10, 0.06)]:
        f = cycles / seconds
        phase = random.random() * TAU
        for i in range(n):
            buf[i] += amp * math.sin(TAU * f * i / SR + phase)
    return fade_edges(buf, ms=30)


def creature_growl_near(seconds=1.4):
    """A low, close proximity stinger — played by the level as Object 12 closes
    distance during CHASE."""
    n = n_samples(seconds)
    buf = [0.0] * n
    for i in range(n):
        t = i / SR
        x = i / n
        env = math.sin(math.pi * min(1.0, x * 1.2)) ** 1.2
        f = 62.0 + 18.0 * math.sin(TAU * 3.2 * t)
        buf[i] += 0.55 * env * (math.sin(TAU * f * t) + 0.5 * math.sin(TAU * f * 1.5 * t))
    prev = 0.0
    for i in range(n):
        x = i / n
        env = math.sin(math.pi * min(1.0, x * 1.2)) ** 1.2
        white = random.uniform(-1.0, 1.0)
        prev += 0.05 * (white - prev)
        buf[i] += prev * 1.5 * env
    return buf


# ---------------------------------------------------------------- screamer

def screamer_breach(seconds=2.0):
    """Fatal screamer bed: a metallic shriek layered over a wet, guttural roar."""
    n = n_samples(seconds)
    buf = [0.0] * n
    for i in range(n):
        t = i / SR
        x = i / n
        env = min(1.0, x * 32.0) * math.exp(-x * 1.5)
        f = 340.0 + 760.0 * x
        s = 0.0
        for h, a in ((1.0, 1.0), (1.98, 0.5), (3.05, 0.3), (4.9, 0.2)):
            s += a * math.sin(TAU * f * h * t)
        buf[i] += 0.42 * env * s
    prev = 0.0
    for i in range(n):
        x = i / n
        env = min(1.0, x * 3.5) * math.exp(-x * 1.0)
        white = random.uniform(-1.0, 1.0)
        prev += 0.5 * (white - prev)
        buf[i] += (white - prev) * 1.5 * env
    return buf


# ---------------------------------------------------------------- main

def main():
    write_wav("ambient_breach.wav", ambient_breach())
    write_wav("door_slam.wav", door_slam())
    write_wav("door_batter.wav", door_batter())
    write_wav("door_break.wav", door_break())
    write_wav("blast_door_slam.wav", blast_door_slam())
    write_wav("shield_stagger.wav", shield_stagger())
    write_wav("shield_drain_loop.wav", shield_drain_loop())
    write_wav("screamer_breach.wav", screamer_breach())
    write_wav("creature_growl_near.wav", creature_growl_near())


if __name__ == "__main__":
    main()
