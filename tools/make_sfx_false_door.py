#!/usr/bin/env python3
"""`false_door_scream` — what answers when you open the door marked 217 that is not room 217.

⚠️⚠️ SUPERSEDED 2026-08-18, AND THE .wav IS DELETED. DO NOT RE-RUN THIS TO "RESTORE" IT.

The user's verification replay of the false door: *"Use the sounds for shared screamers and
make it louder."* `corridor.gd:FALSE_DOOR_SCREAM` is now `all_levels_screamer` — the shared
screamer sting `Screamer.FALLBACK_AUDIO` pairs with the shared `screamers/` image pool — and
they are right about the level it delivers. Decoded and clamped to +/-1.0 as the mixer will:

    false_door_scream.wav   peak -1.01  RMS -6.37  loudest 300 ms -3.79 dBFS
    all_levels_screamer     peak +0.00  RMS -4.69  loudest 300 ms -0.16 dBFS   <- +3.63 dB

There was no gain left to add on top of that: `flash_scare` plays the stream at 0 dB on
`Screamer`'s own player and takes no volume argument. The reasoning below for why a NEW asset
was made is still sound as far as it goes — every other candidate is something else's voice —
but it weighed distinctiveness above recognition, and the shared sting is the one sound in the
game the player already flinches at. ⚠️ It is deliberately not this level's FATAL sting
(`screamer_corridor`), so the survivable trap still does not borrow the death sound; that pair
is asserted by `check_corridor_events.gd`.

The file is deleted rather than left on disk: an orphan asset nobody references is exactly the
trap `sprawl_wall_hum.wav` set in the Backrooms. This script still regenerates it byte-for-byte
if the decision is ever reversed.

    python3 tools/make_sfx_false_door.py
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import

Pure stdlib (wave/math/struct/random), seeded, byte-identical across runs — the same contract
as `tools/make_sfx.py` and `tools/make_sfx_mirror.py`. Writes ONE file into
game/assets/audio/level_3_corridor/.

WHY A NEW ASSET RATHER THAN REUSING ONE
---------------------------------------
Every existing candidate is already SOMETHING ELSE's voice, and this level is small enough
that the player will notice:
  * `screamer_manager` is the Corridor Manager's flash, 35-105 m earlier in the same walk
  * `jumpscare` has just been re-pointed at the running silhouette 34 m further on
  * `apparition_snarl` is the shared Apparition's rush sting, and this level arms one
  * `childe_scream` is the House cellar child; `screamer_hotel`/`screamer_corridor` are this
    level's FATAL pair and must keep meaning "you are dead"
  * `nightmare_scream` is an orphan, but it is 10.3 s and `flash_scare()` never stops its
    audio, so it would ring for ten seconds over a 0.9 s picture

⚠️ LOUD BY CONSTRUCTION, NOT BY GAIN. The user asked for this to be *"loud"*. The lesson from
`make_sfx_mirror.py` the same day: a peak-normalised transient measures ~20 dB below its own
peak, and there is no volume_db that fixes that — turning it up just clips. So the density is
built in here (compression, then a tanh drive) and the file is measured before the call site's
gain is chosen. Result, measured: **peak -1.01, RMS -6.37, loudest-300 ms -3.79 dBFS**, against
`shared/jumpscare.wav`'s -2.12 — i.e. it sits with the loudest asset in the project. The drive
was swept: 5 -> -8.04, 8 -> -5.40, **12 -> -3.79**, 20 -> -2.53; past 12 the voice layer stops
sounding like a throat and starts sounding like a fuzz pedal.

WHAT IT IS, in four layers:
  1. the door being flung — a sub drop plus a broadband crack
  2. a voice: a formant-filtered sawtooth that glides up and then collapses, with vibrato.
     Three formants is what makes a buzz read as a throat rather than as a synthesiser
  3. a metal shriek — detuned high partials with a fast tremolo, the hinge and the frame
  4. a long, dark reverse-swelling tail, so the corridor is left ringing rather than cut off
"""

import math
import os
import random
import struct
import wave

SR = 44100
SEED = 20260817
DUR = 1.60
DRIVE = 12.0
OUT_DIR = os.path.join(
    os.path.dirname(__file__), "..", "game", "assets", "audio", "level_3_corridor")
NAME = "false_door_scream.wav"


class OnePole:
    def __init__(self, cutoff_hz):
        self.set(cutoff_hz)
        self.y = 0.0

    def set(self, cutoff_hz):
        cutoff_hz = max(20.0, min(cutoff_hz, SR * 0.45))
        self.a = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / SR)

    def tick(self, x):
        self.y += self.a * (x - self.y)
        return self.y


class Reso:
    """A two-pole resonator — one formant."""

    def __init__(self, freq, q):
        self.set(freq, q)
        self.y1 = 0.0
        self.y2 = 0.0

    def set(self, freq, q):
        r = math.exp(-math.pi * freq / (q * SR))
        self.a1 = 2.0 * r * math.cos(2.0 * math.pi * freq / SR)
        self.a2 = -r * r
        self.g = (1.0 - r) * 0.9

    def tick(self, x):
        y = self.g * x + self.a1 * self.y1 + self.a2 * self.y2
        self.y2 = self.y1
        self.y1 = y
        return y


def impact(dest, gain, rng):
    """Layer 1 — the door coming off its stop."""
    n = int(0.55 * SR)
    phase = 0.0
    lp = OnePole(2600.0)
    for i in range(n):
        t = i / SR
        f = 92.0 * math.exp(-7.0 * t) + 38.0
        phase += 2.0 * math.pi * f / SR
        sub = math.sin(phase) * math.exp(-8.0 * t)
        crack = lp.tick(rng.uniform(-1.0, 1.0)) * math.exp(-26.0 * t)
        dest[i] += (sub * 0.9 + crack * 1.1) * gain


def voice(dest, at, gain, rng):
    """Layer 2 — the scream. A sawtooth through three formants, gliding and collapsing."""
    n = int(1.05 * SR)
    off = int(at * SR)
    fs = [Reso(720.0, 11.0), Reso(1180.0, 13.0), Reso(2650.0, 9.0)]
    amps = [1.0, 0.72, 0.45]
    phase = 0.0
    for i in range(n):
        t = i / SR
        frac = t / (n / SR)
        # Up fast, hold, then fall away as the breath goes.
        base = 310.0 + 240.0 * math.sin(math.pi * min(1.0, frac * 1.7)) - 110.0 * frac
        base *= 1.0 + 0.035 * math.sin(2.0 * math.pi * 6.4 * t)      # vibrato
        phase += base / SR
        phase -= math.floor(phase)
        saw = 2.0 * phase - 1.0
        breath = rng.uniform(-1.0, 1.0) * 0.22
        src = saw + breath
        s = 0.0
        for f, a in zip(fs, amps):
            s += f.tick(src) * a
        env = min(1.0, t / 0.035) * math.exp(-2.1 * max(0.0, t - 0.20))
        j = off + i
        if j < len(dest):
            dest[j] += s * env * gain


def shriek(dest, at, gain, rng):
    """Layer 3 — hinge and frame: detuned high partials with a fast tremolo."""
    n = int(0.85 * SR)
    off = int(at * SR)
    voices = []
    for f in (2840.0, 3610.0, 4930.0, 6220.0):
        for det in (1.0, 1.0 + rng.uniform(0.004, 0.011)):
            voices.append([f * det, 0.0])
    for i in range(n):
        t = i / SR
        trem = 0.55 + 0.45 * math.sin(2.0 * math.pi * 23.0 * t)
        s = 0.0
        for v in voices:
            v[1] += 2.0 * math.pi * v[0] / SR
            s += math.sin(v[1])
        s /= len(voices)
        env = min(1.0, t / 0.012) * math.exp(-3.4 * t)
        j = off + i
        if j < len(dest):
            dest[j] += s * env * trem * gain


def tail(dest, at, gain, rng):
    """Layer 4 — a dark swell that outlives the picture."""
    n = int(0.85 * SR)
    off = int(at * SR)
    lo = OnePole(900.0)
    hi = OnePole(120.0)
    for i in range(n):
        t = i / SR
        frac = t / (n / SR)
        lo.set(900.0 * (1.0 - 0.7 * frac) + 160.0)
        x = rng.uniform(-1.0, 1.0)
        band = lo.tick(x) - hi.tick(x)
        env = math.sin(math.pi * frac) ** 1.5
        j = off + i
        if j < len(dest):
            dest[j] += band * env * gain


def compress(samples, threshold=0.02, ratio=30.0, attack_ms=0.3, release_ms=12.0):
    atk = math.exp(-1.0 / (attack_ms * 0.001 * SR))
    rel = math.exp(-1.0 / (release_ms * 0.001 * SR))
    env = 0.0
    out = []
    for s in samples:
        rect = abs(s)
        coeff = atk if rect > env else rel
        env = coeff * env + (1.0 - coeff) * rect
        gain = 1.0
        if env > threshold:
            gain = (threshold + (env - threshold) / ratio) / env
        out.append(s * gain)
    return out


def build():
    rng = random.Random(SEED)
    buf = [0.0] * int(DUR * SR)
    impact(buf, 0.95, rng)
    voice(buf, 0.045, 0.85, rng)
    shriek(buf, 0.02, 0.40, rng)
    tail(buf, 0.55, 0.55, rng)
    buf = compress(buf)
    p = max(1e-9, max(abs(s) for s in buf))
    buf = [math.tanh(s / p * DRIVE) for s in buf]
    fade = int(0.070 * SR)
    for i in range(fade):
        buf[len(buf) - fade + i] *= 1.0 - i / fade
    return buf


def write_wav(name, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    norm = 0.89 / peak
    path = os.path.normpath(os.path.join(OUT_DIR, name))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            frames += struct.pack("<h", int(max(-1.0, min(1.0, s * norm)) * 32767))
        w.writeframes(bytes(frames))
    print("wrote %s (%.2fs)" % (path, len(samples) / SR))


if __name__ == "__main__":
    os.makedirs(os.path.normpath(OUT_DIR), exist_ok=True)
    write_wav(NAME, build())
