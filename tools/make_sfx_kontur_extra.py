#!/usr/bin/env python3
"""Two extra KONTUR SFX, for the 2026-08-18 level pass.

  perekozhnik_shed.wav  the Perekozhnik dropping a disguise: a wet unfolding, a sharp
                        cartilage crack, and a long dry exhale that decays to nothing.
  object12_cell.wav     the containment cell's field: a seamless low hum with a slow
                        beat and a faint irregular wet motion inside it. LOOPS.

⚠️ A SEPARATE FILE FROM `make_sfx_kontur.py`, ON PURPOSE. That script seeds once at module
scope and writes seven files in order, so appending an eighth changes the RNG stream every
later call sees — the Backrooms learned this the expensive way (`make_sfx_seam.py`'s
header: re-running `make_sfx_backrooms.py` to add ONE sound silently rewrote three others).
This one is independently seeded and touches nothing that already exists.

⚠️ It PRINTS EACH FILE'S MEASURED RMS AND PEAK dBFS, and those numbers are where
`kontur.gd`'s gains come from. Set a gain from the file, never from a plausible number —
the Flood's water bed sat 20 dB below everything else in the game and was inaudible at a
volume_db that read as sensible.

⚠️ `object12_cell` is SEAMLESS BY CONSTRUCTION: every modulation frequency completes a
whole number of cycles in the loop length, and the noise bed is generated as a circular
buffer. Every `.wav.import` in this project is `loop_mode=0`, so loops are restarted in
code by `finished -> play` and any level mismatch at the seam ticks once per cycle.

Pure stdlib. Usage:
    python3 tools/make_sfx_kontur_extra.py
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import
"""

import math
import os
import random
import struct
import wave

SR = 44100
TAU = math.tau
OUT_DIR = os.path.normpath(os.path.join(
    os.path.dirname(__file__), "..", "game", "assets", "audio", "level_5_kontur"))

random.seed(120818)   # 2026-08-18, KONTUR pass


def measure(samples):
    peak = max(abs(s) for s in samples) or 1e-9
    rms = math.sqrt(sum(s * s for s in samples) / len(samples)) or 1e-9
    return 20 * math.log10(peak), 20 * math.log10(rms)


def write_wav(name, samples, headroom=0.89):
    peak = max(1e-9, max(abs(s) for s in samples))
    norm = headroom / peak
    out = [max(-1.0, min(1.0, s * norm)) for s in samples]
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in out))
    pk, rms = measure(out)
    print("%-24s %5.2f s   peak %6.2f dBFS   rms %6.2f dBFS"
          % (name, len(out) / SR, pk, rms))


def shed():
    """A wet unfolding -> a crack -> a dry exhale. 1.9 s, decays to silence."""
    n = int(1.9 * SR)
    buf = [0.0] * n
    # Layer 1: wet, low-passed noise swelling and collapsing (the disguise letting go).
    lp = 0.0
    for i in range(n):
        t = i / SR
        env = math.exp(-((t - 0.28) ** 2) / 0.020)
        raw = random.uniform(-1.0, 1.0)
        lp += (raw - lp) * 0.06
        buf[i] += lp * 3.2 * env
    # Layer 2: a descending, slightly detuned body tone — cartilage under tension.
    for i in range(n):
        t = i / SR
        f = 190.0 * math.exp(-1.6 * t)
        env = math.exp(-3.2 * t) * (1.0 - math.exp(-40.0 * t))
        buf[i] += 0.35 * env * (math.sin(TAU * f * t)
                                + 0.4 * math.sin(TAU * f * 1.51 * t + 0.7))
    # Layer 3: the crack, a band-passed burst at 0.42 s.
    crack_at = int(0.42 * SR)
    bp1 = bp2 = 0.0
    for i in range(crack_at, min(n, crack_at + int(0.09 * SR))):
        t = (i - crack_at) / SR
        raw = random.uniform(-1.0, 1.0) * math.exp(-55.0 * t)
        bp1 += (raw - bp1) * 0.55
        bp2 += (bp1 - bp2) * 0.55
        buf[i] += (bp1 - bp2) * 6.0
    # Layer 4: the exhale — noise through a slowly closing filter, 0.6 s .. end.
    ex_at = int(0.60 * SR)
    f1 = 0.0
    for i in range(ex_at, n):
        t = (i - ex_at) / SR
        env = math.exp(-2.1 * t) * min(1.0, t * 14.0)
        raw = random.uniform(-1.0, 1.0)
        f1 += (raw - f1) * (0.30 * math.exp(-1.2 * t) + 0.02)
        buf[i] += f1 * 1.5 * env
    # Hard tail fade, so nothing clicks at the end.
    tail = int(0.12 * SR)
    for k in range(tail):
        buf[n - tail + k] *= 1.0 - k / tail
    return buf


def cell(loop_s=6.0):
    """A containment field. Seamless: every partial completes whole cycles in loop_s."""
    n = int(loop_s * SR)
    buf = [0.0] * n
    # Circular pink-ish noise bed: generate, then cross-blend the ends against a copy
    # rotated by half the buffer, which is exact rather than a fade.
    raw = [random.uniform(-1.0, 1.0) for _ in range(n)]
    lp = 0.0
    bed = []
    for v in raw:
        lp += (v - lp) * 0.010
        bed.append(lp)
    half = n // 2
    bed = [(bed[i] * (1.0 - i / n) + bed[(i + half) % n] * (i / n)) for i in range(n)]
    bmax = max(abs(v) for v in bed) or 1e-9
    bed = [v / bmax for v in bed]

    # Whole-cycle partials only.
    def cycles(hz):
        return max(1, round(hz * loop_s)) / loop_s

    f_hum = cycles(47.0)
    f_hum2 = cycles(94.0)
    f_beat = cycles(0.5)        # the slow pulse of the field
    f_wet = cycles(0.1667)      # something inside it moving, once per loop
    for i in range(n):
        t = i / SR
        beat = 0.72 + 0.28 * math.sin(TAU * f_beat * t)
        buf[i] += 0.55 * beat * math.sin(TAU * f_hum * t)
        buf[i] += 0.16 * math.sin(TAU * f_hum2 * t + 1.1)
        buf[i] += 0.42 * bed[i] * (0.55 + 0.45 * math.sin(TAU * f_wet * t))
    return buf


def main():
    write_wav("perekozhnik_shed.wav", shed())
    write_wav("object12_cell.wav", cell())
    print("\nSet kontur.gd's gains from the rms figures above, not from taste.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
