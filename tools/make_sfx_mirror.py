#!/usr/bin/env python3
"""`mirror_wake` — the sound the Corridor's turn mirrors make when the glass comes alive.

Pure-stdlib (wave/math/random), seeded and reproducible, 16-bit mono 44.1 kHz — the same
contract as tools/make_sfx.py. Writes ONE file into
game/assets/audio/level_3_corridor/mirror_wake.wav.

    python3 tools/make_sfx_mirror.py
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import

WHY A SEPARATE FILE RATHER THAN A FUNCTION IN make_sfx.py.
`make_sfx.py` regenerates all six shipped Corridor SFX on every run. They are seeded, but
re-emitting them rewrites six .wav files that are already imported and already balanced,
and forces a re-import of the lot for one new asset. This writes exactly what is new.

⚠️ THE BASE NAME MUST STAY GLOBALLY UNIQUE. `GameState.load_audio()` resolves by base name
across a hardcoded list of subdirs and the first hit wins — `door_slam` exists in two
folders and the wrong one silently wins. `mirror_wake` was checked against every .wav/.ogg
/.mp3 base name in the project on 2026-08-16 and collides with nothing (`glass_shatter`,
`glass_break` and `music_box` are the nearest neighbours).

WHAT IT IS, and why this shape.
The user asked for "a noisy sound ... so that it would scare the player", tied to the
moment the mirror appears. The beat it lands on is real and already in the build: the
reflection is proximity-gated (`MirrorSurface.ACTIVE_DIST` 14 m), so at 14 m the glass
stops being a dark rectangle and becomes a live corridor. That switch is what the user was
describing as "appears out of nowhere", and they said they LIKE it — so this reinforces the
existing beat rather than inventing a second one.

Four layers, all one-shot, no loop (every .wav.import here is loop_mode=0):
  1. a sub thud — the pane taking a hit from the other side
  2. a struck-glass ring, three inharmonic partials, detuned and beating against each other
  3. THE NOISE — a bandpass swell that opens fast and shuts fast, the "noisy" the user asked
     for; its centre frequency slides down, which reads as something large turning over
  4. a granular shimmer tail, decaying to nothing over ~1.1 s

⚠️ Peak-normalised to 0.89 exactly like make_sfx.py, so the LEVEL is not set here — it is
set at the call site from the file's own measured loudness. See MIRROR_WAKE_DB in
corridor.gd, which carries the measurement.
"""

import math
import os
import random
import struct
import wave

SR = 44100
SEED = 20260816
OUT_DIR = os.path.join(
    os.path.dirname(__file__), "..", "game", "assets", "audio", "level_3_corridor")
NAME = "mirror_wake.wav"
# Measured: the four layers are down 44 dB by 1.30 s and in true silence past 1.35 s.
# A one-shot AudioStreamPlayer3D lives until `finished`, so trailing silence is a node
# hanging around doing nothing.
DUR = 1.45


class OnePole:
    """One-pole lowpass; a bandpass is two of these differenced."""

    def __init__(self, cutoff_hz):
        self.set(cutoff_hz)
        self.y = 0.0

    def set(self, cutoff_hz):
        cutoff_hz = max(20.0, min(cutoff_hz, SR * 0.45))
        self.a = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / SR)

    def tick(self, x):
        self.y += self.a * (x - self.y)
        return self.y


DRIVE = 3.0   # see `saturate` — the constant that actually bought the loudness


def compress(samples, threshold=0.02, ratio=30.0, attack_ms=0.3, release_ms=12.0):
    """A deterministic feed-forward compressor, run on the mixed buffer before saturation.

    Stdlib, no numpy, single pass, no randomness — byte-identical across runs like the rest of
    this generator.
    """
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
            # Above the threshold, only 1/ratio of the excess survives.
            gain = (threshold + (env - threshold) / ratio) / env
        out.append(s * gain)
    return out


def saturate(samples, drive=DRIVE):
    """Soft clipping (tanh), applied after `compress` and before the peak normalise.

    ⚠️ WHY THE LOUDNESS COMES FROM HERE AND NOT FROM A GAIN, 2026-08-17. The user asked for
    this cue to be *"much louder"*. The shipped file was already peak-normalised to 0.89
    (-1.0 dBFS) and its LEVEL at the call site was +6 dB, which — measured — landed its peak
    at **+0.13 dBFS at the listener**, i.e. it was already fractionally clipping the master.
    There was no gain left to give it.

    So the problem was the file's CREST FACTOR, and this is what was measured while trying to
    fix it (loudest-300 ms window, at an unchanged -1.0 dBFS peak):

        shipped ................................. -14.03 dBFS
        + envelope compression alone, six settings swept .. -14.6 .. -12.0
        + tanh drive 3 .......................... **-5.69**
        + tanh drive 6 ...........................  -3.33
        + tanh drive 16 ..........................  -1.82

    Compression alone bought **2 dB in the best case and nothing in the worst**, and the
    reason is physical rather than a tuning miss: limiting an ENVELOPE does not raise a
    waveform's RMS toward its peak — filtered noise and ringing partials sit 10-12 dB below
    peak by construction. `shared/jumpscare.wav`, the densest asset in the project, has a
    crest factor of **2.1 dB**, which is only reachable with saturation.

    Drive 3 is the chosen point: +8.3 dB of loudness for moderate harmonic distortion. The
    higher settings are louder still and audibly buzz. The character does change — the ring
    gets grittier and the noise swell harder — and that was judged to suit a cue whose brief
    was "noisy ... so that it would scare the player". One constant to revert.
    """
    return [math.tanh(s * drive) for s in samples]


def write_wav(name, samples):
    samples = compress(samples)
    # ⚠️ Normalise BEFORE the drive, or `drive` means something different every time a layer
    # gain is touched: tanh is not scale-invariant, so its input has to be in a known range.
    p = max(1e-9, max(abs(s) for s in samples))
    samples = saturate([s / p for s in samples])
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


def sub_thud(dest, at, gain):
    """Layer 1. A short pitch-dropping sine — the pane taking a hit from behind."""
    n = int(0.45 * SR)
    off = int(at * SR)
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = 74.0 * math.exp(-5.0 * t) + 33.0
        phase += 2.0 * math.pi * f / SR
        env = math.exp(-9.0 * t)
        j = off + i
        if j < len(dest):
            dest[j] += math.sin(phase) * env * gain


def glass_ring(dest, at, gain, rng):
    """Layer 2. Struck glass: inharmonic partials, each detuned against a twin so the
    pair beats. A single clean sine reads as a bell, not as a pane."""
    partials = [(1470.0, 1.00, 2.6), (2310.0, 0.62, 3.4), (3790.0, 0.38, 4.8),
                (5240.0, 0.20, 6.5)]
    n = int(1.30 * SR)
    off = int(at * SR)
    voices = []
    for f, amp, decay in partials:
        for det in (1.0, 1.0 + rng.uniform(0.002, 0.006)):
            voices.append([f * det, amp * 0.5, decay, 0.0])
    for i in range(n):
        t = i / SR
        s = 0.0
        for v in voices:
            v[3] += 2.0 * math.pi * v[0] / SR
            s += math.sin(v[3]) * v[1] * math.exp(-v[2] * t)
        # A fast attack, or the ring sounds struck a frame late.
        s *= min(1.0, t / 0.004)
        j = off + i
        if j < len(dest):
            dest[j] += s * gain


def noise_swell(dest, at, gain, rng):
    """Layer 3 — THE NOISE. A bandpass that opens in 40 ms and shuts in 500, sliding its
    centre down 5.2 kHz -> 380 Hz. The slide is what stops it reading as a hiss."""
    n = int(0.75 * SR)
    off = int(at * SR)
    lo = OnePole(5200.0)
    hi = OnePole(2600.0)
    for i in range(n):
        t = i / SR
        frac = t / (n / SR)
        centre = 5200.0 * math.exp(-3.2 * frac) + 380.0
        lo.set(centre * 2.1)
        hi.set(centre * 0.45)
        x = rng.uniform(-1.0, 1.0)
        band = lo.tick(x) - hi.tick(x)
        # Open fast, shut fast. Asymmetric on purpose: a symmetric swell is a whoosh.
        env = min(1.0, t / 0.040) * math.exp(-4.6 * max(0.0, t - 0.040))
        j = off + i
        if j < len(dest):
            dest[j] += band * env * gain


def shimmer_tail(dest, at, gain, rng):
    """Layer 4. Granular metal: short filtered noise grains at falling density, each
    one ringing a little. Decays into the room rather than stopping."""
    end = at + 1.15
    t = at + 0.05
    while t < end:
        frac = (t - at) / (end - at)
        f = rng.uniform(1800.0, 6400.0) * (1.0 - 0.55 * frac)
        dur = rng.uniform(0.020, 0.070)
        amp = gain * (1.0 - frac) ** 2 * rng.uniform(0.35, 1.0)
        n = int(dur * SR)
        off = int(t * SR)
        lp = OnePole(f * 1.5)
        phase = 0.0
        for i in range(n):
            tt = i / SR
            phase += 2.0 * math.pi * f / SR
            s = (math.sin(phase) * 0.6 + lp.tick(rng.uniform(-1.0, 1.0)) * 0.4)
            env = math.sin(math.pi * min(1.0, tt / dur)) ** 2
            j = off + i
            if j < len(dest):
                dest[j] += s * env * amp
        t += rng.uniform(0.018, 0.055) * (1.0 + 2.4 * frac)


def build():
    rng = random.Random(SEED)
    buf = [0.0] * int(DUR * SR)
    sub_thud(buf, 0.0, 0.85)
    glass_ring(buf, 0.006, 0.55, rng)
    noise_swell(buf, 0.0, 0.80, rng)
    shimmer_tail(buf, 0.10, 0.30, rng)
    # A hard silence on the last 60 ms so the one-shot cannot click at the end.
    fade = int(0.060 * SR)
    for i in range(fade):
        buf[len(buf) - fade + i] *= 1.0 - i / fade
    return buf


# --------------------------------------------------------------- mirror_stare
#
# ⭐ THE SECOND FILE: the sound the glass makes WHILE YOU STARE INTO IT (2026-08-17).
#
# WHY IT EXISTS. The playtest that produced it: the player stopped at the 275 m mirror and
# went 36 % -> 73 % -> 97 % -> dead in about fifteen seconds. That is the mirror's own
# `ScaryObject` at `scare_intensity` 2.2, i.e. 44 panic/s, and the user's ruling was
# *"Leave it - staring should be dangerous - but I guess adding heartbeat is a good idea."*
#
# So the COST does not change and no panic constant moves. What was missing is ATTRIBUTION:
# the heartbeat is real (measured: `heartbeat.ogg` is -18.4 dBFS mean and `player.gd` lerps
# it -20 -> 0 dB with panic, so at 72 % panic it plays at about -24 dBFS on the never-ducked
# BODY bus) but it is a GLOBAL panic meter — it says "you are in trouble" and never says
# "the thing in front of you is what is doing it". This does, because it comes out of the
# glass, only while you are looking into it, and stops the instant you look away.
#
# THE SHAPE: a seamless 3.0 s loop, ridden by `corridor.gd:_tick_mirror_stare()` on both
# volume (-26 -> -3 dB) and pitch (0.72 -> 1.35). Two things ride with the pitch:
#   * a detuned low drone pair that beats against itself — the tension bed
#   * a 2 Hz amplitude pulse, so pitch 0.72 -> 1.35 takes it from 1.44 Hz to 2.7 Hz. An
#     ACCELERATING pulse is the part that reads as a countdown rather than as atmosphere.
#
# ⚠️ SEAMLESS BY CONSTRUCTION, not by crossfade. Every `.wav.import` here is `loop_mode=0`
# and the level restarts the loop from `finished -> play`, so a seam ticks once per cycle.
# Every modulation frequency below completes a WHOLE NUMBER of cycles in STARE_DUR, and the
# noise layer is generated as a circular buffer. `tools/make_loop.py` is the retrofit for
# sourced audio; a generator should not need it.
#
# ⚠️ ZERO PANIC. It is a channel, not a term (GAME_MECHANICS_IDEAS' governing finding).
STARE_NAME = "mirror_stare.wav"
STARE_DUR = 3.0
STARE_SEED = 20260817


def stare_loop():
    rng = random.Random(STARE_SEED)
    n = int(STARE_DUR * SR)
    buf = [0.0] * n

    # Whole cycles in the loop, or the seam ticks. base_hz values are chosen so that
    # base_hz * STARE_DUR is an integer.
    drones = [(58.0, 0.55), (58.0 + 1.0 / STARE_DUR * 2, 0.50), (87.0, 0.30), (116.0, 0.16)]
    for f, amp in drones:
        cycles = round(f * STARE_DUR)
        f = cycles / STARE_DUR
        for i in range(n):
            buf[i] += math.sin(2.0 * math.pi * f * i / SR) * amp

    # A high, thin glass partial — the thing in the pane, not the room.
    for f, amp in ((1470.0, 0.10), (2310.0, 0.055)):
        cycles = round(f * STARE_DUR)
        f = cycles / STARE_DUR
        # Slow tremolo, also a whole number of cycles.
        trem = 3.0 / STARE_DUR
        for i in range(n):
            t = i / SR
            g = 0.65 + 0.35 * math.sin(2.0 * math.pi * trem * t)
            buf[i] += math.sin(2.0 * math.pi * f * t) * amp * g

    # A circular noise bed: generate, then filter with the state carried around the wrap so
    # sample 0 continues from sample n-1.
    # ⚠️ TWO PASSES OVER THE **RAW** BUFFER, keeping only the second. Filtering an already
    # filtered buffer changes the spectrum; what is wanted is for the filter STATE at sample 0
    # to be the state it would have had if the loop had already been playing, which is exactly
    # what the first pass leaves behind. Measured: seam step 0.0317 -> 0.0009 of full scale.
    raw = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    lp = OnePole(420.0)
    for i in range(n):
        lp.tick(raw[i])                      # warm-up: discarded, state is what we want
    for i in range(n):
        buf[i] += lp.tick(raw[i]) * 0.9

    # THE PULSE. 2 Hz -> exactly 6 cycles in 3.0 s. Never goes to zero, or the loop reads as
    # a rhythm instead of as pressure.
    pulse_hz = round(2.0 * STARE_DUR) / STARE_DUR
    for i in range(n):
        t = i / SR
        buf[i] *= 0.55 + 0.45 * (0.5 - 0.5 * math.cos(2.0 * math.pi * pulse_hz * t)) ** 0.7
    return buf


def write_loop(name, samples):
    """Like `write_wav` but with NO fade at either end and no saturation — a fade is a seam."""
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
    # ⚠️ THE SEAM IS A ONE-SAMPLE STEP, so |first - last| on its own means nothing: a loud
    # waveform has large adjacent-sample deltas everywhere. What matters is whether the step
    # ACROSS the wrap is ordinary. Reported as a multiple of the 99th-percentile step inside
    # the file — anything at or under 1.0 is indistinguishable from the material itself.
    steps = sorted(abs(samples[i + 1] - samples[i]) for i in range(len(samples) - 1))
    p99 = steps[int(len(steps) * 0.99)]
    seam = abs(samples[0] - samples[-1])
    print("wrote %s (%.2fs)  seam step %.5f = %.2fx the p99 step inside the file"
          % (path, len(samples) / SR, seam * norm, seam / max(p99, 1e-9)))


if __name__ == "__main__":
    os.makedirs(os.path.normpath(OUT_DIR), exist_ok=True)
    write_wav(NAME, build())
    write_loop(STARE_NAME, stare_loop())
