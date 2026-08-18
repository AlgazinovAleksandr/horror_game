#!/usr/bin/env python3
"""Procedural SFX for THE SEAM — the Backrooms zone-1 exit tell (backlog 04 BS1).

    python3 tools/make_sfx_seam.py      # stdlib only, then Godot --import

Writes into game/assets/audio/level_backrooms/:

  seam_draw.wav   FAR CUE. Wide, low, slow. Carries the length of an arm and gives
                  a BEARING — "there is something at the end of this corridor".
  seam_rip.wav    NEAR CONFIRM. Fine, irregular, dry. Only resolves in the last few
                  metres and says "this surface, this one".

⚠️ SEPARATE FILE FROM make_sfx_backrooms.py ON PURPOSE. That script calls
`random.uniform` without seeding, so re-running it to add one sound rewrites
light_pop / rotary_ring / phone_whisper with different noise. This one is seeded and
touches nothing else.

WHY TWO LAYERS, AND WHY AUDIO AT ALL.
The level's win verb is "walk into a blank wall", and it is demanded three times —
twice at the loop-back caps and once at the utility room — before it is ever taught.
The playtester stood still for 86 seconds 5 m short of a loop-back cap writing
"players might get confused that you need to go through the wall".

The obvious answer (make the wall glow after a minute) was measured and declined:
the glitch wall is ALREADY the brightest surface in its room by 2.3x (132.7 lum
against side walls at 56.9). Luminance is not the missing channel; a statement of
the verb is. And a glow would not have helped at all at a loop-back cap, which is
where the capture was actually taken.

The two-layer far-cue / near-confirm shape is this project's own solved answer to
"a cue nobody can walk toward", twice:
  * backrooms_zone2.gd:_randomise_real_wall()  water @ unit_size 16 + whisper @ 9
  * level_1.gd's dark-wing beacon              breaker_hum @ 16 + breaker_buzz @ 9
Both replaced a single narrow-range emitter that was only audible once you had
already arrived. Do not collapse these two back into one.

⚠️ SEAMLESS BY CONSTRUCTION. Every .wav.import in this project is loop_mode=0, so
these are restarted in code by `finished -> play`; any level mismatch at the seam
ticks once per cycle. Every modulation frequency below completes a whole number of
cycles in the loop length, and the noise beds are generated as a circular buffer so
sample N-1 flows into sample 0.
"""

import math
import os
import random
import struct
import wave

SR = 44100
TAU = math.tau
SEED = 4041

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
    # ⚠️ PRINTED BECAUSE THE GAIN MUST BE SET FROM IT. `water.wav` sits ~20 dB below
    # every other asset here, and its shipped -6 dB was a number that read as
    # sensible and was inaudible. backrooms.gd quotes these figures next to the
    # SEAM_*_DB constants; if this number moves, those move.
    print("wrote %s  %.2fs  RMS %.1f dBFS" % (path, len(samples) / SR, dbfs))
    return dbfs


class OnePole:
    def __init__(self, cutoff_hz):
        self.a = math.exp(-TAU * cutoff_hz / SR)
        self.z = 0.0

    def tick(self, x):
        self.z = x * (1.0 - self.a) + self.z * self.a
        return self.z


def circular_noise(n, cutoff_hz, rng, warmup=8192):
    """Lowpassed noise whose end joins its start. The filter is primed by running
    it over the LAST `warmup` samples of the sequence before emitting, so its state
    at sample 0 is the state it will be in when the loop wraps."""
    raw = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    lp = OnePole(cutoff_hz)
    for i in range(n - warmup, n):
        lp.tick(raw[i])
    return [lp.tick(raw[i]) for i in range(n)]


def make_seam_draw():
    """FAR CUE — 8 s loop. Air being pulled through a gap that should not be there.

    Deliberately built from NON-MAINS frequencies (43.75 / 65.625 Hz, both exact
    multiples of 0.125 Hz so eight seconds is a whole number of cycles). The level's
    bed is `fluorescent_hum`, which is a 60 Hz harmonic stack; if this shared its
    partials the two would fuse into one sound and the tell would vanish into the
    room tone it is supposed to stand out of."""
    rng = random.Random(SEED)
    dur = 8.0
    n = int(SR * dur)
    body = circular_noise(n, 260.0, rng)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        # Two low partials, a fifth apart, both whole-cycle over 8 s.
        tone = 0.42 * math.sin(TAU * 43.75 * t) + 0.26 * math.sin(TAU * 65.625 * t)
        # The draw: a slow 0.125 Hz inhale (one whole cycle in the loop) with a
        # 0.375 Hz tremor on top (three whole cycles).
        breath = 0.55 + 0.45 * (0.5 - 0.5 * math.cos(TAU * 0.125 * t))
        tremor = 0.88 + 0.12 * math.sin(TAU * 0.375 * t)
        out[i] = (tone * 0.55 + body[i] * 0.85) * breath * tremor
    return out


def make_seam_rip():
    """NEAR CONFIRM — 4 s loop. The fabric of the wall giving, in fine irregular
    ticks. Dry, high, and low-energy, so distance attenuation kills it quickly: at
    the emitter's unit_size this is inaudible from the hub and unmistakable at the
    wall, which is the whole job of a near confirm."""
    rng = random.Random(SEED + 1)
    dur = 4.0
    n = int(SR * dur)
    out = [0.0] * n
    bed = circular_noise(n, 5200.0, rng)
    for i in range(n):
        t = i / SR
        # A quiet crackle floor, breathing at 0.5 Hz (two whole cycles in 4 s).
        out[i] = bed[i] * 0.16 * (0.6 + 0.4 * math.sin(TAU * 0.5 * t))

    # Ticks: short band-limited bursts scattered over the loop. Any burst whose tail
    # would run past the end is wrapped into the head, so the seam stays silent.
    for _ in range(34):
        at = rng.uniform(0.0, dur)
        length = rng.uniform(0.012, 0.045)
        freq = rng.uniform(900.0, 4200.0)
        amp = rng.uniform(0.25, 0.85)
        m = int(length * SR)
        start = int(at * SR)
        for k in range(m):
            env = math.exp(-k / SR * (28.0 / length))
            s = math.sin(TAU * freq * k / SR) * env * amp
            s += rng.uniform(-1.0, 1.0) * env * amp * 0.5
            out[(start + k) % n] += s * 0.35
    return out


def main():
    print("SEAM SFX -> %s" % OUT_DIR)
    write_wav("seam_draw.wav", make_seam_draw())
    write_wav("seam_rip.wav", make_seam_rip())


if __name__ == "__main__":
    main()
