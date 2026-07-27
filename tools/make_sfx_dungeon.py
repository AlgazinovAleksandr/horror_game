#!/usr/bin/env python3
"""Procedural SFX generator for THE NIGHTMARE (the dungeon level).

Pure-stdlib (wave/math/random) so it runs on any Python 3 — no numpy needed.
Outputs 16-bit mono 44.1 kHz .wav files into game/assets/audio/level_9_dungeon/.
Follows the exact structure of tools/make_sfx_level6.py.

Files:
  ambient_dungeon.wav   seamless loop — THE FILE THE WHOLE LEVEL DUCKS. Filtered
                         pink-noise wind, a slow amplitude drift, a barely-audible
                         44 Hz drone. Deliberately FEATURELESS: its job is to be
                         missed when it stops, not listened to.
  matron_theme.wav      seamless loop — inharmonic bell struck slowly through a
                         sweeping resonant band-pass. Ugly on purpose. The level
                         drives volume_db from her distance, so this is the sonar.
  matron_step.wav       damped low thud + dry cloth rustle; pitch-randomised per play
  matron_shriek.wav     the spot-you sting — formant-swept scream burst, hard attack
  hollow_knock.wav   ⭐ THE MOST IMPORTANT FILE IN THE LEVEL. A low, dry, very short
                         knuckle-on-wood knock. Must be genuinely confusable with a
                         settling door. Get this wrong and the finale is unfair.
  hollow_reveal.wav     sub-bass swell on the spark reveal
  bone_scrape.wav       seamless loop — comb-filtered noise, amplitude-gated: a dry
                         wooden drag. The Still Ones' tell.
  skeleton_fall.wav     a dud Still One toppling — scattered wood-block impacts
  candle_light.wav      match strike, then a soft flame whoosh
  candle_blow.wav       short breath of filtered noise
  candle_die.wav     ⭐ must be instantly learnable — a sputter, then a distinct
                         descending sigh. The player has to know from across a room
                         that they just went dark.
  spark_flint.wav       sharp short crackle burst, band-passed high
  sconce_light.wav      deep whoomph of oil catching + warm crackle tail. The
                         level's REWARD sound.
  child_laugh.wav       a short child's laugh — noise-excited formants
  child_peek.wav        very short high glissando
  frame_weep.wav        seamless loop — low breathy sobbing (the Weeping Frames)
  frame_ignite.wav      whoosh + crackle for the 5-sconce kill wind-up
  whisper_dungeon.wav   a bank of whispered lines (the Kneeling Man)
  cot_sleep.wav         long breath out + descending drone, under the fade to black

NOT generated here:
  screamer_dungeon      user-supplied (screamer_dungeon.ogg), already in place
  door_batter / door_break / blast_door_slam   reused from level_6_breach/
  heartbeat / footstep / pipe_groan            reused from shared/

⚠️ Base names must be globally unique — GameState.load_audio() resolves by base name
across EVERY audio subdir, and the extension loop is outermost, so a .wav anywhere
beats a .ogg in the right folder.

⚠️ write_wav peak-normalises every file to 0.89. Relative loudness between files is
therefore NOT set here — it is set by volume_db on each emitter in dungeon.gd. That
matters most for hollow_knock, which must play at about -12 dB.

Seeded, so re-running reproduces byte-identical output.

Usage: python3 tools/make_sfx_dungeon.py
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
    os.path.dirname(__file__), "..", "game", "assets", "audio", "level_9_dungeon"
)

random.seed(709)  # level 9, seven sconces


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


# ------------------------------------------------------------------ dsp helpers
#
# Everything below is one-pole / two-pole and runs sample-at-a-time, which is slow
# but keeps the file stdlib-only and readable. A 30 s bed is ~1.3 M samples; that is
# a couple of seconds of Python, which is fine for a build-time tool.


def lowpass(buf, cutoff):
    """One-pole lowpass, in place."""
    a = 1.0 - math.exp(-TAU * cutoff / SR)
    prev = 0.0
    for i, s in enumerate(buf):
        prev += a * (s - prev)
        buf[i] = prev
    return buf


def highpass(buf, cutoff):
    """One-pole highpass by subtracting a lowpassed copy."""
    a = 1.0 - math.exp(-TAU * cutoff / SR)
    prev = 0.0
    for i, s in enumerate(buf):
        prev += a * (s - prev)
        buf[i] = s - prev
    return buf


def resonator(buf, freq, q):
    """Two-pole resonant band-pass — the formant/bell workhorse."""
    r = math.exp(-math.pi * freq / (q * SR))
    c = 2.0 * r * math.cos(TAU * freq / SR)
    y1 = y2 = 0.0
    out = [0.0] * len(buf)
    for i, s in enumerate(buf):
        y = s + c * y1 - r * r * y2
        y2, y1 = y1, y
        out[i] = y
    return out


def sweep_resonator(buf, f0, f1, q):
    """Band-pass whose centre frequency sweeps f0 -> f1 across the buffer."""
    n = len(buf)
    y1 = y2 = 0.0
    out = [0.0] * n
    for i, s in enumerate(buf):
        f = f0 + (f1 - f0) * (i / max(1, n - 1))
        r = math.exp(-math.pi * f / (q * SR))
        c = 2.0 * r * math.cos(TAU * f / SR)
        y = s + c * y1 - r * r * y2
        y2, y1 = y1, y
        out[i] = y
    return out


def noise(n):
    return [random.uniform(-1.0, 1.0) for _ in range(n)]


def pink(n):
    """Voss-ish pink noise: a stack of lowpassed white at octave-spaced cutoffs."""
    out = [0.0] * n
    for cutoff, gain in ((40, 1.0), (160, 0.6), (640, 0.32), (2500, 0.16)):
        layer = lowpass(noise(n), cutoff)
        for i in range(n):
            out[i] += layer[i] * gain
    return out


def normalise(buf, peak=1.0):
    m = max(1e-9, max(abs(s) for s in buf))
    k = peak / m
    return [s * k for s in buf]


def mix_into(dst, src, at, gain=1.0):
    """Add src into dst starting at sample index `at`, clipped to dst's length."""
    for i, s in enumerate(src):
        j = at + i
        if 0 <= j < len(dst):
            dst[j] += s * gain
    return dst


# ------------------------------------------------------------------ ambient bed

def ambient_dungeon(seconds=24.0):
    """The bed whose ABSENCE is the level's flagship tell.

    Deliberately featureless. Every periodic component completes a whole number of
    cycles across the clip so the loop point is seamless (the make_sfx_level6.py
    technique) — a bed with an audible seam ticks once per loop and would read as a
    positional event in a level about distinguishing events from ambience.
    """
    n = n_samples(seconds)
    air = lowpass(pink(n), 420.0)
    air = highpass(air, 55.0)
    air = normalise(air, 0.7)

    out = [0.0] * n
    for i in range(n):
        t = i / SR
        # Slow amplitude drift — 2 whole cycles over the clip (~0.08 Hz).
        drift = 0.62 + 0.38 * (0.5 + 0.5 * math.sin(TAU * 2.0 * t / seconds))
        # A second, slower drift beating against the first so it never repeats
        # audibly within one pass.
        drift *= 0.85 + 0.15 * math.sin(TAU * 3.0 * t / seconds + 1.1)
        out[i] = air[i] * drift

    # The 44 Hz drone: barely audible, whole-cycle, mostly felt.
    drone_cycles = round(44.0 * seconds)
    for i in range(n):
        t = i / SR
        out[i] += 0.10 * math.sin(TAU * drone_cycles * t / seconds)

    # A very distant, very occasional stone settle — low, dull, no attack.
    for k in range(3):
        at = int(n * (0.19 + 0.31 * k))
        dur = n_samples(1.6)
        thud = [0.0] * dur
        for i in range(dur):
            t = i / SR
            env = math.exp(-t * 2.2) * min(1.0, t * 6.0)
            thud[i] = env * math.sin(TAU * (38.0 + 5.0 * k) * t)
        mix_into(out, thud, at, 0.16)

    return fade_edges(out, ms=60)


# ------------------------------------------------------------------- the Matron

def matron_theme(seconds=12.0):
    """Seamless loop. An inharmonic bell struck slowly through a sweeping
    resonant band-pass. Ugly on purpose — this is not music, it is a proximity
    readout the player learns to hate."""
    n = n_samples(seconds)
    out = [0.0] * n
    strikes = 8  # whole number over the clip -> seamless
    for k in range(strikes):
        at = int(n * k / strikes)
        dur = n_samples(seconds / strikes * 1.6)
        bell = [0.0] * dur
        base = 210.0 + 40.0 * math.sin(k * 1.7)
        # Inharmonic partials — deliberately not integer ratios.
        partials = ((1.0, 1.0), (2.41, 0.55), (3.83, 0.34), (5.17, 0.2), (7.06, 0.12))
        for i in range(dur):
            t = i / SR
            env = math.exp(-t * 1.9)
            s = 0.0
            for mult, amp in partials:
                s += amp * math.sin(TAU * base * mult * t)
            bell[i] = env * s
        bell = sweep_resonator(bell, 900.0, 2400.0, 5.0)
        bell = normalise(bell, 0.8)
        mix_into(out, bell, at, 0.55)

    # A continuous scraped-metal underlay so the gaps are not silent.
    bed = highpass(lowpass(noise(n), 3000.0), 700.0)
    for i in range(n):
        t = i / SR
        gate = 0.5 + 0.5 * math.sin(TAU * 6.0 * t / seconds)
        out[i] += bed[i] * 0.10 * gate

    return fade_edges(out, ms=45)


def matron_step(seconds=0.55):
    """Damped low thud + a dry cloth rustle. dungeon.gd pitch-randomises +-8%."""
    n = n_samples(seconds)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        env = math.exp(-t * 16.0) * min(1.0, t * 400.0)
        # Pitch-dropping body — the weight of the step.
        f = 92.0 * math.exp(-t * 9.0) + 46.0
        out[i] = env * math.sin(TAU * f * t) * 0.9

    rustle = highpass(lowpass(noise(n), 5200.0), 1400.0)
    for i in range(n):
        t = i / SR
        out[i] += rustle[i] * 0.32 * math.exp(-t * 11.0) * min(1.0, t * 90.0)
    return fade_edges(out, ms=6)


def matron_shriek(seconds=0.9):
    """The spot-you sting. Hard attack, formant-swept, no tail to speak of."""
    n = n_samples(seconds)
    src = [0.0] * n
    for i in range(n):
        t = i / SR
        env = math.exp(-t * 3.2) * min(1.0, t * 260.0)
        f = 430.0 + 300.0 * math.exp(-t * 4.0)
        # A rasping glottal source: saw-ish plus noise.
        ph = (f * t) % 1.0
        src[i] = env * ((ph * 2.0 - 1.0) * 0.7 + random.uniform(-0.3, 0.3))

    a = sweep_resonator(src, 700.0, 1900.0, 9.0)
    b = sweep_resonator(src, 1600.0, 3400.0, 11.0)
    out = [a[i] * 0.7 + b[i] * 0.45 for i in range(n)]
    return fade_edges(out, ms=8)


# --------------------------------------------------------------- the Hollow One

def hollow_knock(seconds=0.34):
    """⭐ The level's most important sound.

    DN's own description: "more like a door knocking, but with the hits coming at a
    low frequency... easily mistaken for a knocking sound coming from a chest nearby.
    It isn't loud."

    So: a LOW fundamental (~70 Hz), a VERY short body, almost no ring, and no
    high-frequency transient that would make it read as a deliberate stinger. The
    design requires that a player who is walking cannot reliably tell it from the
    building settling — the whole solution is to STOP and listen.
    """
    n = n_samples(seconds)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        # Short, dull, dry. Fast decay = knuckle on solid wood, not a drum.
        env = math.exp(-t * 26.0) * min(1.0, t * 900.0)
        body = math.sin(TAU * 70.0 * t) * 1.0
        body += 0.42 * math.sin(TAU * 113.0 * t)   # slight inharmonic ring
        body += 0.18 * math.sin(TAU * 186.0 * t)
        out[i] = env * body

    # A whisper of contact noise — enough to sound physical, not enough to sparkle.
    tick = lowpass(noise(n), 1100.0)
    for i in range(n):
        t = i / SR
        out[i] += tick[i] * 0.20 * math.exp(-t * 70.0)

    out = lowpass(out, 900.0)  # kill anything bright; it must not "announce"
    return fade_edges(out, ms=4)


def hollow_reveal(seconds=0.45):
    """Sub-bass swell on the spark reveal — one frame of truth, felt not heard."""
    n = n_samples(seconds)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        env = math.sin(math.pi * min(1.0, t / seconds)) ** 1.5
        f = 30.0 + 26.0 * (t / seconds)
        out[i] = env * (math.sin(TAU * f * t) + 0.35 * math.sin(TAU * f * 2.02 * t))
    return fade_edges(out, ms=12)


# --------------------------------------------------------------- the Still Ones

def bone_scrape(seconds=3.0):
    """Seamless loop: a dry wooden drag. Comb-filtered noise, amplitude-gated at
    about 1.4 Hz so it reads as a repeated haul rather than a hiss.

    This is the FAIRNESS UPGRADE over the Void's creatures, whose only tell is
    looking at them. Gated on ADVANCING in creature_stalker.gd.
    """
    n = n_samples(seconds)
    src = highpass(lowpass(noise(n), 4200.0), 250.0)

    # Comb filter at 180 Hz -> a dry, woody resonance.
    delay = int(SR / 180.0)
    combed = list(src)
    for i in range(delay, n):
        combed[i] += combed[i - delay] * 0.72

    out = [0.0] * n
    gate_cycles = 4  # whole cycles over 3 s -> ~1.33 Hz, and seamless
    for i in range(n):
        t = i / SR
        g = 0.5 + 0.5 * math.sin(TAU * gate_cycles * t / seconds - math.pi / 2.0)
        out[i] = combed[i] * (g ** 2.2) * 0.9
    return fade_edges(out, ms=50)


def skeleton_fall(seconds=1.1):
    """A dud toppling: nine pitched wood-block impacts scattered over ~0.6 s with a
    decaying envelope. The GOOD outcome — a fallen Still One can never stand up."""
    n = n_samples(seconds)
    out = [0.0] * n
    for k in range(9):
        frac = (k / 8.0) ** 0.7
        at = n_samples(0.02 + 0.58 * frac)
        dur = n_samples(0.22)
        amp = (1.0 - 0.75 * frac) * random.uniform(0.7, 1.0)
        f = random.uniform(190.0, 430.0)
        blk = [0.0] * dur
        for i in range(dur):
            t = i / SR
            env = math.exp(-t * 34.0) * min(1.0, t * 1200.0)
            blk[i] = env * (math.sin(TAU * f * t) + 0.5 * math.sin(TAU * f * 2.7 * t))
        blk = highpass(blk, 140.0)
        mix_into(out, blk, at, amp * 0.55)

    # A final heavier settle as the whole thing hits the flagstones.
    dur = n_samples(0.5)
    thud = [0.0] * dur
    for i in range(dur):
        t = i / SR
        env = math.exp(-t * 9.0) * min(1.0, t * 500.0)
        thud[i] = env * math.sin(TAU * (74.0 * math.exp(-t * 6.0) + 40.0) * t)
    mix_into(out, thud, n_samples(0.62), 0.8)
    return fade_edges(out, ms=8)


# ------------------------------------------------------------------- the candle

def candle_light(seconds=1.3):
    """Match strike: a noise burst through a rising band-pass, then a flame whoosh."""
    n = n_samples(seconds)
    strike_n = n_samples(0.14)
    strike = noise(strike_n)
    for i in range(strike_n):
        t = i / SR
        strike[i] *= math.exp(-t * 26.0) * min(1.0, t * 900.0)
    strike = sweep_resonator(strike, 1800.0, 5200.0, 3.0)
    strike = normalise(strike, 0.9)

    out = [0.0] * n
    mix_into(out, strike, 0, 1.0)

    whoosh = lowpass(noise(n), 1700.0)
    for i in range(n):
        t = i / SR
        env = 0.0
        if t > 0.10:
            u = t - 0.10
            env = math.exp(-u * 3.4) * min(1.0, u * 12.0)
        out[i] += whoosh[i] * 0.55 * env
    return fade_edges(out, ms=8)


def candle_blow(seconds=0.4):
    """A short breath. Blowing the candle BANKS the remaining seconds (§B11) — so
    this must not sound like a loss."""
    n = n_samples(seconds)
    br = lowpass(noise(n), 2600.0)
    br = highpass(br, 260.0)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        env = math.sin(math.pi * min(1.0, t / seconds)) ** 1.3
        out[i] = br[i] * env
    return fade_edges(out, ms=10)


def candle_die(seconds=1.0):
    """⭐ Must be instantly learnable.

    A tiny sputter, then a distinct descending sine sigh. The player has to know from
    across a room, with their back turned, that they just went dark — because the
    dark is the medium of this level, not its penalty, and being surprised by it is
    the only unfair version.
    """
    n = n_samples(seconds)
    out = [0.0] * n

    # Sputter: three quick irregular flutters.
    for k, at_s in enumerate((0.0, 0.07, 0.15)):
        dur = n_samples(0.09)
        sp = noise(dur)
        for i in range(dur):
            t = i / SR
            sp[i] *= math.exp(-t * 40.0) * min(1.0, t * 700.0)
        sp = resonator(sp, 900.0 + 260.0 * k, 4.0)
        sp = normalise(sp, 0.85)
        mix_into(out, sp, n_samples(at_s), 0.7 - 0.15 * k)

    # The sigh: a clean descending sine, unmistakable and unlike anything else here.
    sigh_at = n_samples(0.24)
    dur = n_samples(0.42)
    for i in range(dur):
        t = i / SR
        env = math.sin(math.pi * (i / dur)) ** 0.8
        f = 520.0 * math.exp(-t * 3.6) + 150.0
        j = sigh_at + i
        if j < n:
            out[j] += env * 0.85 * math.sin(TAU * f * t)

    # A last curl of smoke.
    tail_at = n_samples(0.55)
    tail_n = n - tail_at
    if tail_n > 0:
        tail = lowpass(noise(tail_n), 1200.0)
        for i in range(tail_n):
            t = i / SR
            out[tail_at + i] += tail[i] * 0.18 * math.exp(-t * 5.0)
    return fade_edges(out, ms=10)


def spark_flint(seconds=0.16):
    """Free, unlimited, no cooldown — so it must be SHORT and never fatiguing.
    The cost of sparking is the 1.2 s vision dip afterwards, not the sound."""
    n = n_samples(seconds)
    out = noise(n)
    for i in range(n):
        t = i / SR
        out[i] *= math.exp(-t * 90.0) * min(1.0, t * 3000.0)
    out = sweep_resonator(out, 2000.0, 6000.0, 2.2)
    return fade_edges(out, ms=3)


def sconce_light(seconds=1.8):
    """The level's REWARD sound. A deep whoomph of oil catching, then a warm crackle.
    One of only seven times the player will hear it, and the only unambiguously good
    thing that happens down here."""
    n = n_samples(seconds)
    out = [0.0] * n

    # The whoomph: a broad lowpassed noise swell with a falling body tone under it.
    whoomph = lowpass(noise(n), 900.0)
    for i in range(n):
        t = i / SR
        env = math.exp(-t * 2.1) * min(1.0, t * 9.0)
        out[i] = whoomph[i] * 0.85 * env
        f = 120.0 * math.exp(-t * 2.6) + 52.0
        out[i] += 0.35 * env * math.sin(TAU * f * t)

    # Warm crackle tail — sparse ticks, band-limited so it reads as fire not static.
    for _ in range(46):
        at = n_samples(random.uniform(0.25, seconds - 0.12))
        dur = n_samples(random.uniform(0.006, 0.022))
        tick = noise(dur)
        f = random.uniform(700.0, 2600.0)
        for i in range(dur):
            t = i / SR
            tick[i] *= math.exp(-t * 260.0)
        tick = resonator(tick, f, 3.0)
        tick = normalise(tick, 1.0)
        mix_into(out, tick, at, random.uniform(0.05, 0.16))
    return fade_edges(out, ms=12)


# -------------------------------------------------------------------- the Child

def child_laugh(seconds=1.0):
    """Harmless. Always. The Child has no fail state — this costs 6 panic and
    nothing else, and it is suppressed entirely while a candle burns."""
    n = n_samples(seconds)
    src = [0.0] * n
    # A laugh is a train of short voiced bursts on a falling pitch.
    bursts = ((0.00, 560.0), (0.16, 610.0), (0.31, 540.0), (0.45, 480.0), (0.60, 430.0))
    for at_s, f0 in bursts:
        at = n_samples(at_s)
        dur = n_samples(0.13)
        for i in range(dur):
            t = i / SR
            j = at + i
            if j >= n:
                break
            env = math.sin(math.pi * (i / dur)) ** 1.4
            f = f0 * (1.0 - 0.12 * (i / dur))
            ph = (f * t) % 1.0
            src[j] += env * ((ph * 2.0 - 1.0) * 0.6 + random.uniform(-0.12, 0.12))

    # Child formants: high F1/F2 pair.
    a = resonator(src, 850.0, 11.0)
    b = resonator(src, 2100.0, 13.0)
    c = resonator(src, 3200.0, 9.0)
    out = [a[i] * 0.8 + b[i] * 0.5 + c[i] * 0.22 for i in range(n)]
    return fade_edges(out, ms=10)


def child_peek(seconds=0.45):
    """The gone-when-you-look-again variant. Very short high glissando."""
    n = n_samples(seconds)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / SR
        u = t / seconds
        env = math.sin(math.pi * u) ** 1.6
        f = 900.0 + 1500.0 * u
        phase += TAU * f / SR
        out[i] = env * (math.sin(phase) * 0.7 + 0.25 * math.sin(phase * 2.01))
    return fade_edges(out, ms=8)


# ----------------------------------------------------------- the Weeping Frames

def frame_weep(seconds=6.0):
    """Seamless loop. Low breathy sobbing — an amplitude-modulated formant pair.

    Arrives at 3 sconces, one TIER BEFORE the Frames can kill (§B4.6). The sound
    arriving before the rule is the whole teaching structure: by the time staring is
    fatal the player already knows this object's silhouette, position class and voice.
    """
    n = n_samples(seconds)
    src = [0.0] * n
    sobs = 7  # whole number over the clip -> seamless
    for k in range(sobs):
        at = int(n * k / sobs)
        dur = int(n / sobs * 0.8)
        f0 = 150.0 + 22.0 * math.sin(k * 2.3)
        for i in range(dur):
            t = i / SR
            j = at + i
            if j >= n:
                break
            u = i / dur
            env = (math.sin(math.pi * u) ** 2.0) * (0.7 + 0.3 * math.sin(u * 9.0))
            f = f0 * (1.0 + 0.18 * math.sin(u * 5.0))
            ph = (f * t) % 1.0
            src[j] += env * ((ph * 2.0 - 1.0) * 0.5 + random.uniform(-0.2, 0.2))

    a = resonator(src, 300.0, 9.0)
    b = resonator(src, 900.0, 11.0)
    out = [a[i] * 0.9 + b[i] * 0.45 for i in range(n)]

    # Breath between the sobs, so the gaps are wet rather than empty.
    br = highpass(lowpass(noise(n), 2200.0), 400.0)
    for i in range(n):
        t = i / SR
        g = 0.5 + 0.5 * math.sin(TAU * sobs * t / seconds + math.pi)
        out[i] += br[i] * 0.10 * g
    return fade_edges(out, ms=55)


def frame_ignite(seconds=1.3):
    """The 5-sconce kill wind-up: the frame visibly ignites. Whoosh + crackle.
    ⚠️ The ignition TWEEN must keep emission <= 0.9 (Issue 21) or the frame renders
    as a flat white rectangle. This sound is the part that can be loud."""
    n = n_samples(seconds)
    out = lowpass(noise(n), 2200.0)
    for i in range(n):
        t = i / SR
        env = math.exp(-t * 2.4) * min(1.0, t * 22.0)
        out[i] *= env
        f = 160.0 * math.exp(-t * 3.0) + 60.0
        out[i] += 0.4 * env * math.sin(TAU * f * t)

    for _ in range(30):
        at = n_samples(random.uniform(0.1, seconds - 0.1))
        dur = n_samples(random.uniform(0.005, 0.018))
        tick = noise(dur)
        for i in range(dur):
            tick[i] *= math.exp(-(i / SR) * 300.0)
        tick = resonator(tick, random.uniform(900.0, 3400.0), 3.0)
        tick = normalise(tick, 1.0)
        mix_into(out, tick, at, random.uniform(0.06, 0.2))
    return fade_edges(out, ms=10)


# ------------------------------------------------------------ the Kneeling Man

def whisper_dungeon(seconds=7.0):
    """A bank of whispered lines, played positionally from the Kneeling Man.

    Procedural whispering is noise through swept vowel formants; intelligibility is
    not required and is arguably worse. Two lines are deliberately load-bearing
    continuity and would be worth SOURCING later if they should be understood:
    "Look behind you" (the exact lie KONTUR's escort gate tells — a harmless ghost
    saying it retroactively makes KONTUR's version read as the same voice) and
    "Wake up".
    """
    n = n_samples(seconds)
    out = [0.0] * n
    # Six "lines", each a run of syllables on drifting vowel formants.
    at = n_samples(0.2)
    for _ in range(6):
        syllables = random.randint(3, 6)
        for _s in range(syllables):
            dur = n_samples(random.uniform(0.10, 0.20))
            src = noise(dur)
            for i in range(dur):
                u = i / dur
                src[i] *= math.sin(math.pi * u) ** 1.2
            # Vowel pair, swept a little within the syllable.
            f1 = random.uniform(320.0, 780.0)
            f2 = random.uniform(1100.0, 2300.0)
            a = sweep_resonator(src, f1, f1 * random.uniform(0.85, 1.2), 12.0)
            b = sweep_resonator(src, f2, f2 * random.uniform(0.85, 1.2), 14.0)
            syl = [a[i] * 0.8 + b[i] * 0.55 for i in range(dur)]
            syl = normalise(syl, 0.8)
            mix_into(out, syl, at, random.uniform(0.5, 0.9))
            at += dur + n_samples(random.uniform(0.02, 0.07))
        at += n_samples(random.uniform(0.35, 0.8))
        if at >= n:
            break

    out = highpass(out, 300.0)  # whispers have no chest
    return fade_edges(out, ms=25)


# ------------------------------------------------------------------- the cot

def cot_sleep(seconds=2.8):
    """Under the fade to black when the player chooses to go under. A long breath
    out and a low descending drone. This is the level's only voluntary transition —
    the player CHOOSES to sleep, which is why it is an interact() and not a trigger
    volume."""
    n = n_samples(seconds)
    out = [0.0] * n

    br = lowpass(noise(n), 1500.0)
    br = highpass(br, 180.0)
    for i in range(n):
        t = i / SR
        env = math.exp(-t * 1.05) * min(1.0, t * 3.5)
        out[i] = br[i] * 0.55 * env

    phase = 0.0
    for i in range(n):
        t = i / SR
        u = t / seconds
        env = math.sin(math.pi * u) ** 0.7
        f = 96.0 * math.exp(-t * 0.85) + 34.0
        phase += TAU * f / SR
        out[i] += env * 0.6 * (math.sin(phase) + 0.3 * math.sin(phase * 1.99))
    return fade_edges(out, ms=40)


def main():
    write_wav("ambient_dungeon.wav", ambient_dungeon())
    write_wav("matron_theme.wav", matron_theme())
    write_wav("matron_step.wav", matron_step())
    write_wav("matron_shriek.wav", matron_shriek())
    write_wav("hollow_knock.wav", hollow_knock())
    write_wav("hollow_reveal.wav", hollow_reveal())
    write_wav("bone_scrape.wav", bone_scrape())
    write_wav("skeleton_fall.wav", skeleton_fall())
    write_wav("candle_light.wav", candle_light())
    write_wav("candle_blow.wav", candle_blow())
    write_wav("candle_die.wav", candle_die())
    write_wav("spark_flint.wav", spark_flint())
    write_wav("sconce_light.wav", sconce_light())
    write_wav("child_laugh.wav", child_laugh())
    write_wav("child_peek.wav", child_peek())
    write_wav("frame_weep.wav", frame_weep())
    write_wav("frame_ignite.wav", frame_ignite())
    write_wav("whisper_dungeon.wav", whisper_dungeon())
    write_wav("cot_sleep.wav", cot_sleep())


if __name__ == "__main__":
    main()
