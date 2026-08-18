#!/usr/bin/env python3
"""Procedural SFX for the two Backrooms puzzles added 2026-08-17.

    python3 tools/make_sfx_backrooms_puzzle.py     # stdlib only, then Godot --import

Writes into game/assets/audio/level_backrooms/:

  THE FLOOD — the plate table (backrooms_zone3.gd + flood_plate.gd)
    plate_hum.wav    FAR CUE, 8 s loop. The assembly point has to ANNOUNCE ITSELF or
                     "the middle of the level" becomes a second thing to hunt for with
                     no tell at all. unit_size 5 — big enough to carry across the wing,
                     small enough that it FALLS OFF across it, which is the difference
                     between a bearing and a wash.
    plate_ring.wav   NEAR CONFIRM, 4 s loop. unit_size 3 — drops below the water bed by
                     the far end, which is what makes the pair two layers, not two copies.
    plate_set.wav    One-shot: a fragment seated into the frame.
    plate_done.wav   One-shot: six of six. The only time this sound is ever heard.
    piece_lift.wav   One-shot: a fragment lifted out of a flooded object (B-R2's second
                     press — the piece is TAKEN, it does not read itself out at you).

  THE SPRAWL — the crate in the dark (backrooms_zone2.gd + sprawl_dweller.gd)
    sprawl_call_far.wav   FAR CUE, 8 s loop. The whisper that leads you to the crate.
    sprawl_call_near.wav  NEAR CONFIRM, 4 s loop.
    crate_shriek.wav      The scare itself. ⚠️ ITS OWN FILE, not a borrowed one: every
                          candidate already in the project belongs to another beat —
                          `nightmare_scream` is the MAIN MENU's cold open, `apparition_snarl`
                          is the telegraph of a HOLD apparition and this level has two of
                          those, and the per-level screamers are the FATAL ones. Reusing a
                          fatal scream for a survivable scare teaches the player the fatal
                          sound is free.

⚠️ EVERY GAIN IN THE GAME IS SET FROM THE RMS THIS SCRIPT PRINTS, never from a number
that reads as sensible. `water.wav` shipped at -6 dB for months and was inaudible
because the FILE is -39.6 dBFS. The constants in `backrooms_zone3.gd` /
`backrooms_zone2.gd` quote these figures; if they move, those move.

⚠️ SEPARATE FILE, SEEDED. `make_sfx_backrooms.py` calls `random.uniform` without
seeding, so re-running it to add one sound silently rewrites light_pop / rotary_ring /
phone_whisper with different noise (the lesson make_sfx_seam.py records). This one is
seeded, byte-reproducible, and touches only the eight files above.

⚠️ THE FOUR LOOPS ARE SEAMLESS BY CONSTRUCTION, not by crossfade: every modulation
frequency completes a whole number of cycles in the loop length, and the noise beds are
generated as circular buffers. Every .wav.import here is loop_mode=0, so the loops are
restarted in code by `finished -> play`, and any level mismatch at the seam ticks once
per cycle.

⚠️ THE TWO PAIRS MUST NOT SOUND LIKE EACH OTHER OR LIKE THE TELLS ALREADY IN THIS LEVEL.
Zone 2's real wall already speaks with `water` + `whisper`; zone 1's seam with
`seam_draw` + `seam_rip`. A new cue built out of the same partials would fuse into one
of them and point at the wrong thing. So: the plate is METALLIC AND PITCHED (a struck
bowl, partials 196/294/441 Hz), and the crate call is BREATH — unpitched, formant-
shaped noise with no tone in it at all.
"""

import math
import os
import random
import struct
import wave

SR = 44100
TAU = math.tau
SEED = 9153

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
    print("wrote %-24s %5.2fs  RMS %6.1f dBFS" % (name, len(samples) / SR, dbfs))
    return dbfs


class OnePole:
    def __init__(self, cutoff_hz):
        self.a = math.exp(-TAU * cutoff_hz / SR)
        self.z = 0.0

    def tick(self, x):
        self.z = x * (1.0 - self.a) + self.z * self.a
        return self.z


class BandPass:
    """Two-pole resonator — the formant shaper the crate call is built from."""

    def __init__(self, freq, q):
        w = TAU * freq / SR
        r = math.exp(-w / (2.0 * q))
        self.a1 = 2.0 * r * math.cos(w)
        self.a2 = -r * r
        self.gain = (1.0 - r) * math.sqrt(1.0 - 2.0 * r * math.cos(2.0 * w) + r * r)
        self.z1 = 0.0
        self.z2 = 0.0

    def tick(self, x):
        y = self.gain * x + self.a1 * self.z1 + self.a2 * self.z2
        self.z2 = self.z1
        self.z1 = y
        return y


def circular_noise(n, cutoff_hz, rng, warmup=8192):
    """Lowpassed noise whose end joins its start: the filter is primed on the LAST
    `warmup` samples before emitting, so its state at sample 0 is the state it will be
    in when the loop wraps."""
    raw = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    lp = OnePole(cutoff_hz)
    for i in range(n - warmup, n):
        lp.tick(raw[i])
    return [lp.tick(raw[i]) for i in range(n)]


def circular_formant(n, freq, q, rng, warmup=16384):
    raw = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    bp = BandPass(freq, q)
    for i in range(n - warmup, n):
        bp.tick(raw[i])
    return [bp.tick(raw[i]) for i in range(n)]


# ----------------------------------------------------------------- the plate table

def make_plate_hum():
    """FAR CUE — 8 s loop. A struck bowl still ringing, wet. Partials 196 / 294 / 441
    (a fifth and a fifth again, none of them a 60 Hz harmonic, so it cannot fuse with
    `fluorescent_hum`), beating slowly against detuned twins. Every modulator is a
    whole number of cycles in 8 s."""
    rng = random.Random(SEED)
    dur = 8.0
    n = int(SR * dur)
    bed = circular_noise(n, 900.0, rng)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        tone = 0.0
        for f, a in ((196.0, 0.50), (294.0, 0.30), (441.0, 0.16)):
            # +/- 0.25 Hz detune = two whole beat cycles in 8 s.
            tone += a * (math.sin(TAU * f * t) + math.sin(TAU * (f + 0.25) * t)) * 0.5
        swell = 0.55 + 0.45 * (0.5 - 0.5 * math.cos(TAU * 0.125 * t))   # 1 cycle
        shimmer = 0.90 + 0.10 * math.sin(TAU * 0.5 * t)                 # 4 cycles
        out[i] = (tone * 0.42 + bed[i] * 0.30) * swell * shimmer
    return out


def make_plate_ring():
    """NEAR CONFIRM — 4 s loop. Fragments of enamel touching in the frame: sparse,
    bright, low-energy, so distance attenuation kills it fast."""
    rng = random.Random(SEED + 1)
    dur = 4.0
    n = int(SR * dur)
    out = [0.0] * n
    bed = circular_noise(n, 3000.0, rng)
    for i in range(n):
        t = i / SR
        out[i] = bed[i] * 0.10 * (0.6 + 0.4 * math.sin(TAU * 0.5 * t))
    for _ in range(18):
        at = rng.uniform(0.0, dur)
        freq = rng.choice([1568.0, 2093.0, 2637.0, 3136.0])
        amp = rng.uniform(0.30, 0.85)
        length = rng.uniform(0.06, 0.16)
        m = int(length * SR)
        start = int(at * SR)
        for k in range(m):
            env = math.exp(-k / SR * (26.0 / length))
            out[(start + k) % n] += math.sin(TAU * freq * k / SR) * env * amp * 0.30
    return out


def _clack(rng, out, start, freq, amp, length, noise=0.5):
    m = int(length * SR)
    n = len(out)
    for k in range(m):
        env = math.exp(-k / SR * (30.0 / length))
        s = math.sin(TAU * freq * k / SR) * env
        s += rng.uniform(-1.0, 1.0) * env * noise
        out[(start + k) % n] += s * amp


def make_plate_set():
    """One-shot — a fragment scraped into place and seated. Wet grit, then a clack."""
    rng = random.Random(SEED + 2)
    dur = 0.9
    n = int(SR * dur)
    out = [0.0] * n
    lp = OnePole(2600.0)
    for i in range(int(0.28 * SR)):
        t = i / SR
        env = min(1.0, t / 0.03) * math.exp(-t * 7.0)
        out[i] += lp.tick(rng.uniform(-1.0, 1.0)) * env * 0.55
    _clack(rng, out, int(0.30 * SR), 520.0, 0.75, 0.22, 0.35)
    _clack(rng, out, int(0.33 * SR), 1180.0, 0.35, 0.10, 0.20)
    return out


def make_plate_done():
    """One-shot — six of six, and the only time this is ever heard. A rising swell,
    a struck chord on the plate's own partials, and a long wet decay."""
    rng = random.Random(SEED + 3)
    dur = 3.4
    n = int(SR * dur)
    out = [0.0] * n
    # the swell in
    for i in range(int(0.75 * SR)):
        t = i / SR
        out[i] += rng.uniform(-1.0, 1.0) * (t / 0.75) ** 2 * 0.22
    strike = int(0.72 * SR)
    for f, a in ((196.0, 0.60), (294.0, 0.40), (441.0, 0.26), (588.0, 0.14)):
        for k in range(n - strike):
            t = k / SR
            out[strike + k] += a * math.sin(TAU * f * t) * math.exp(-t * 1.5)
    _clack(rng, out, strike, 300.0, 0.6, 0.30, 0.4)
    return out


def make_piece_lift():
    """One-shot — a wet fragment lifted clear of an object. Short: it is the answer to
    a press, not an event."""
    rng = random.Random(SEED + 4)
    dur = 0.7
    n = int(SR * dur)
    out = [0.0] * n
    lp = OnePole(1400.0)
    for i in range(int(0.35 * SR)):
        t = i / SR
        env = min(1.0, t / 0.02) * math.exp(-t * 9.0)
        out[i] += lp.tick(rng.uniform(-1.0, 1.0)) * env * 0.6
    _clack(rng, out, int(0.16 * SR), 1760.0, 0.30, 0.14, 0.25)
    return out


# ----------------------------------------------------------------- the crate call

def _breath_pair(seed, dur, freqs, rate_hz, rasp):
    """Formant-shaped noise breathing at `rate_hz` — whole cycles in `dur` by
    construction. NO tone anywhere in it: this is the thing that keeps the crate call
    from being mistaken for the real wall's `water` + `whisper`."""
    rng = random.Random(seed)
    n = int(SR * dur)
    layers = [circular_formant(n, f, q, rng) for f, q in freqs]
    hiss = circular_noise(n, 6000.0, rng)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        env = 0.18 + 0.82 * (0.5 - 0.5 * math.cos(TAU * rate_hz * t)) ** 1.6
        s = 0.0
        for a, layer in zip((1.0, 0.7, 0.45), layers):
            s += layer[i] * a
        out[i] = (s * 2.2 + hiss[i] * rasp) * env
    return out


def make_sprawl_call_far():
    """FAR CUE — 8 s loop. Someone breathing out words in the dark, too far off to be
    words. Two breaths in the loop (0.25 Hz)."""
    return _breath_pair(SEED + 10, 8.0,
                        ((320.0, 5.0), (860.0, 6.0), (2400.0, 8.0)), 0.25, 0.22)


def make_sprawl_call_near():
    """NEAR CONFIRM — 4 s loop. The same voice with the consonants in it. Higher
    formants and more rasp, so it only survives the last few metres."""
    return _breath_pair(SEED + 11, 4.0,
                        ((480.0, 7.0), (1500.0, 9.0), (3400.0, 11.0)), 0.5, 0.55)


def make_crate_shriek():
    """One-shot — the thing in the box. Violent, inharmonic and SHORT (1.1 s): it plays
    under a 0.9 s `flash_scare`, and a sting whose tail outlives the image reads as the
    room rather than as the thing.

    ⚠️ LOUDNESS IS RMS, NOT PEAK, AND THAT IS THE WHOLE OF THE 2026-08-18 CHANGE.
    Playtest: *"Make the jumpscare louder."* The file was already peak-normalised to
    -1.01 dBFS and could not be turned up — `screamer.gd:_audio` plays it at volume_db 0
    and `flash_scare()` takes no gain — so the only lever is the AVERAGE level. Measured,
    the original was **-20.0 dBFS RMS**, 19 dB below its own peak: one hard transient with
    a fast-decaying tail, i.e. a click. For scale, the shared fatal `jumpscare.wav` is
    -2.8 and the Lab nook's survivable payoff `nook_scream.wav` is -6.6, so this sting was
    13-17 dB quieter than every scare beside it in the game.

    Two changes, neither of which touches the peak:
      * the envelopes SUSTAIN rather than collapse — decays 3.4 -> 1.5 (stack) and
        2.6 -> 1.3 (breath), so the 1.1 s is full of sound instead of front-loaded;
      * a `tanh` soft-clip drives the sum into saturation, which raises the average and
        adds the inharmonic grit a shriek wants. It is a LIMITER, not a gain: nothing can
        exceed +-1 before `write_wav`'s 0.89 normalisation, so clipping is impossible by
        construction rather than by luck.
    Result: **-5.4 dBFS RMS, peak unchanged at -1.01, zero samples at full scale** — a
    +14.6 dB rise in average level, landing 1.2 dB above `nook_scream` and 2.6 dB under
    the fatal `jumpscare`, which is where a survivable scare belongs. The duration is
    deliberately NOT extended; the header rule above still holds.
    """
    rng = random.Random(SEED + 20)
    dur = 1.1
    n = int(SR * dur)
    out = [0.0] * n
    # A downward-swept inharmonic stack — no two partials in any simple ratio, so the ear
    # cannot resolve it into a note.
    for f0, a in ((830.0, 0.55), (1237.0, 0.40), (1913.0, 0.26), (2790.0, 0.15)):
        ph = 0.0
        for i in range(n):
            t = i / SR
            f = f0 * (1.0 - 0.55 * min(1.0, t / 0.75)) * (1.0 + 0.05 * math.sin(TAU * 23.0 * t))
            ph += TAU * f / SR
            env = min(1.0, t / 0.008) * math.exp(-t * 1.5)
            out[i] += a * math.sin(ph) * env
    # The impact under it, and a wash of breath over the top.
    _clack(rng, out, 0, 90.0, 0.9, 0.35, 0.8)
    lp = OnePole(4200.0)
    for i in range(n):
        t = i / SR
        out[i] += lp.tick(rng.uniform(-1.0, 1.0)) * math.exp(-t * 1.3) * 0.45
    # Soft-clip. `tanh` is bounded by +-1, so the output cannot exceed full scale whatever
    # the drive is; the ceiling is a property of the function, not of a tuned number.
    drive = 3.6
    for i in range(n):
        out[i] = math.tanh(out[i] * drive)
    return out


def main():
    print("BACKROOMS PUZZLE SFX -> %s" % OUT_DIR)
    write_wav("plate_hum.wav", make_plate_hum())
    write_wav("plate_ring.wav", make_plate_ring())
    write_wav("plate_set.wav", make_plate_set())
    write_wav("plate_done.wav", make_plate_done())
    write_wav("piece_lift.wav", make_piece_lift())
    write_wav("sprawl_call_far.wav", make_sprawl_call_far())
    write_wav("sprawl_call_near.wav", make_sprawl_call_near())
    write_wav("crate_shriek.wav", make_crate_shriek())


if __name__ == "__main__":
    main()
