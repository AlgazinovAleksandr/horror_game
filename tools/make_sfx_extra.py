#!/usr/bin/env python3
"""Procedural SFX for the expanded Lab + House content.

Pure-stdlib (wave/math/random), same conventions as make_sfx.py / make_sfx_house.py.
Outputs 16-bit mono 44.1 kHz .wav files into the right per-level audio folders:

  shared/         pipe_groan.wav, apparition_drone.wav
  level_1_lab/    breaker_throw.wav
  level_2_house/  tv_static.wav, music_box.wav, water_drip.wav

Usage: python3 tools/make_sfx_extra.py
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


def make_pipe_groan():
    """Low metallic stress moan — a pipe under pressure, bending and creaking."""
    random.seed(471)
    dur = 2.6
    n = int(SR * dur)
    lp = OnePole(900.0)
    out = []
    base = 72.0
    for i in range(n):
        t = i / SR
        # Slow upward pitch bend then settle — the groan of stressed metal.
        f = base + 18.0 * math.sin(2 * math.pi * 0.35 * t) + 6.0 * t
        # A few inharmonic metallic partials.
        s = math.sin(2 * math.pi * f * t)
        s += 0.5 * math.sin(2 * math.pi * f * 2.76 * t)
        s += 0.3 * math.sin(2 * math.pi * f * 5.1 * t)
        s += 0.18 * random.uniform(-1.0, 1.0)  # grain
        env = min(1.0, t / 0.5) * min(1.0, (dur - t) / 0.6)
        out.append(lp.tick(s) * env * 0.6)
    return out


def make_apparition_drone():
    """Rising sub-bass + detuned sting — something materialising in front of you."""
    dur = 2.0
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        # Sub bass sweeps up from 40 to 80 Hz.
        sub = math.sin(2 * math.pi * (40.0 + 40.0 * (t / dur)) * t)
        # Detuned high cluster that swells in.
        sting = (math.sin(2 * math.pi * 311.0 * t)
                 + math.sin(2 * math.pi * 317.0 * t)
                 + math.sin(2 * math.pi * 466.0 * t))
        sting_env = (t / dur) ** 2
        env = min(1.0, t / 0.05) * min(1.0, (dur - t) / 0.5)
        out.append((sub * 0.7 + sting * 0.18 * sting_env) * env)
    return out


def make_breaker_throw():
    """Heavy switch clunk + a brief electrical surge as power returns."""
    dur = 0.6
    n = int(SR * dur)
    lp = OnePole(2600.0)
    out = []
    for i in range(n):
        t = i / SR
        # Click transient.
        click = math.exp(-t * 320.0) * random.uniform(-1.0, 1.0)
        # Low mechanical thunk dropping in pitch.
        thunk_f = 130.0 * math.exp(-t * 6.0) + 45.0
        thunk = math.sin(2 * math.pi * thunk_f * t) * math.exp(-t * 14.0)
        # Electrical 60 Hz hum surge that fades up then off.
        hum_env = min(1.0, t / 0.05) * math.exp(-max(0.0, t - 0.12) * 9.0)
        hum = (math.sin(2 * math.pi * 60.0 * t) + 0.4 * math.sin(2 * math.pi * 120.0 * t)) * hum_env
        out.append(lp.tick(click * 0.7 + thunk * 0.9) + hum * 0.25)
    return out


def make_breaker_spark():
    """Brief electrical crackle — a few quick sputtering pops, under 0.5s. The
    audio tell for the Lab's hidden breaker (BUG_FIX.md 4.1): findable by ear
    without being immediately visible like the other two."""
    random.seed(4711)
    dur = 0.45
    n = int(SR * dur)
    out = [0.0] * n
    # 3-5 short arc pops scattered across the clip.
    t0 = 0.0
    while t0 < dur - 0.05:
        off = int(t0 * SR)
        plen = int(random.uniform(0.02, 0.06) * SR)
        for i in range(plen):
            if off + i >= n:
                break
            t = i / SR
            crackle = random.uniform(-1.0, 1.0) * math.exp(-t * 90.0)
            out[off + i] += crackle
        t0 += random.uniform(0.06, 0.14)
    fade = int(0.01 * SR)
    for i in range(fade):
        g = i / fade
        out[i] *= g
        out[n - 1 - i] *= g
    return out


def make_tv_static():
    """CRT hiss bed with a faint high whine — loopable."""
    random.seed(7)
    dur = 3.0
    n = int(SR * dur)
    hp = OnePole(6000.0)
    out = []
    for i in range(n):
        t = i / SR
        noise = random.uniform(-1.0, 1.0)
        # Crude high-pass: subtract a low-passed copy to keep the hiss bright.
        bright = noise - hp.tick(noise)
        whine = 0.05 * math.sin(2 * math.pi * 15600.0 * t)
        out.append(bright * 0.5 + whine)
    # Seam fade so the loop doesn't click.
    fade = int(0.04 * SR)
    for i in range(fade):
        g = i / fade
        out[i] *= g
        out[n - 1 - i] *= g
    return out


def make_music_box():
    """Slow, detuned child's lullaby — plucked bell notes, loopable."""
    # A simple descending creepy motif (semitone offsets from A4=440).
    semis = [7, 3, 5, 0, -2, 0, 3, -5]  # E5 C5 D5 A4 G4 A4 C5 E4
    dur = 6.0
    out = [0.0] * int(SR * dur)
    step = dur / len(semis)
    for k, semi in enumerate(semis):
        f = 440.0 * (2.0 ** (semi / 12.0)) * 1.0
        detune = 1.0 + random.uniform(-0.004, 0.004)
        f *= detune
        off = int(k * step * SR)
        note_n = int(step * 1.4 * SR)
        for i in range(note_n):
            t = i / SR
            # Bell: a few inharmonic partials, fast-decaying.
            s = (math.sin(2 * math.pi * f * t)
                 + 0.5 * math.sin(2 * math.pi * f * 2.01 * t)
                 + 0.25 * math.sin(2 * math.pi * f * 3.76 * t))
            env = math.exp(-t * 4.5)
            j = off + i
            if j < len(out):
                out[j] += s * env * 0.4
    fade = int(0.05 * SR)
    for i in range(fade):
        g = i / fade
        out[i] *= g
        out[len(out) - 1 - i] *= g
    return out


def make_water_drip():
    """Sparse echoing drips in a cellar — loopable."""
    random.seed(1971)
    dur = 4.0
    out = [0.0] * int(SR * dur)
    t0 = 0.4
    while t0 < dur - 0.5:
        f = random.uniform(900.0, 1600.0)
        off = int(t0 * SR)
        dlen = int(0.25 * SR)
        for i in range(dlen):
            t = i / SR
            # Drip: quick pitch-down ping with a short tail.
            ping = math.sin(2 * math.pi * (f * math.exp(-t * 30.0) + 300.0) * t)
            env = math.exp(-t * 18.0)
            j = off + i
            if j < len(out):
                out[j] += ping * env * random.uniform(0.5, 0.9)
        t0 += random.uniform(0.7, 1.4)
    fade = int(0.05 * SR)
    for i in range(fade):
        g = i / fade
        out[i] *= g
        out[len(out) - 1 - i] *= g
    return out


def main():
    write_wav("shared", "pipe_groan.wav", make_pipe_groan())
    write_wav("shared", "apparition_drone.wav", make_apparition_drone())
    write_wav("level_1_lab", "breaker_throw.wav", make_breaker_throw())
    write_wav("level_1_lab", "breaker_spark.wav", make_breaker_spark())
    write_wav("level_2_house", "tv_static.wav", make_tv_static())
    write_wav("level_2_house", "music_box.wav", make_music_box())
    write_wav("level_2_house", "water_drip.wav", make_water_drip())


if __name__ == "__main__":
    main()
