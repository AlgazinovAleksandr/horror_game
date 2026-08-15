#!/usr/bin/env python3
"""Turn a one-shot .wav into a seamless loop: trim the fade-out, crossfade end into head.

WHY THIS EXISTS
---------------
⚠️ Every `.wav.import` in this project is `loop_mode=0`, so anything that has to loop is
restarted in code via `finished -> play` (backrooms.gd, dungeon.gd, level_1.gd, …). That
means the file itself must START and END at matching level, or the seam ticks once per
cycle — the gotcha `TODO_sounds.md` records and `CLAUDE.md` repeats.

`assets_src/audio/level_2_house/chase.wav` as supplied is a composed piece: 29.4 s at
-15.2 dBFS RMS overall, but its last 0.3 s tails off to -25.5 dBFS. Looped raw, the House maze would dip and re-attack every 29
seconds, which in a chase reads as a bug rather than as a musical phrase.

WHAT IT DOES
------------
  * finds where the fade-out starts, by walking back from the end until the window RMS
    returns to within `--tol` dB of the body of the track, and cuts there
  * crossfades the last `--xfade` seconds over the head with equal-power (sqrt) windows,
    so looped playback is continuous in both level and phase-incoherence terms
  * writes 16-bit PCM at the source rate and channel count

Stdlib only, matching tools/make_sfx*.py — no numpy in this project's tool scripts.

Usage:
    tools/make_loop.py IN.wav OUT.wav [--xfade 1.5] [--tol 3.0]
"""

import argparse
import array
import math
import sys
import wave


def read_wav(path: str) -> "tuple[array.array, int, int]":
    with wave.open(path, "rb") as w:
        if w.getsampwidth() != 2:
            sys.exit("error: %s is not 16-bit PCM (sampwidth=%d)" % (path, w.getsampwidth()))
        data = array.array("h")
        data.frombytes(w.readframes(w.getnframes()))
        return data, w.getnchannels(), w.getframerate()


def frame_rms(data: "array.array", ch: int, start: int, count: int) -> float:
    """RMS over `count` frames from frame `start`, across all channels."""
    lo, hi = start * ch, min(len(data), (start + count) * ch)
    if hi <= lo:
        return 0.0
    acc = 0.0
    for i in range(lo, hi):
        s = data[i] / 32768.0
        acc += s * s
    return math.sqrt(acc / (hi - lo))


def find_fade_start(data: "array.array", ch: int, rate: int, tol_db: float) -> int:
    """Last frame before the tail drops below the body level by more than `tol_db`."""
    frames = len(data) // ch
    win = max(1, rate // 20)                       # 50 ms windows
    body = frame_rms(data, ch, 0, frames)          # whole-file reference
    if body <= 0.0:
        return frames
    floor = body * (10.0 ** (-tol_db / 20.0))
    pos = frames - win
    while pos > frames // 2:
        if frame_rms(data, ch, pos, win) >= floor:
            return min(frames, pos + win)
        pos -= win
    return frames


def crossfade_loop(data: "array.array", ch: int, xfade_frames: int) -> "array.array":
    """out[i<L] = head[i]*fade_in + tail[i]*fade_out; out length = N - L."""
    frames = len(data) // ch
    L = max(1, min(xfade_frames, frames // 3))
    out = array.array("h", data[: (frames - L) * ch])
    for i in range(L):
        # Equal power: sin/cos pair keeps summed energy flat through the blend, which a
        # linear pair does not — a linear crossfade dips audibly in the middle.
        t = (i + 0.5) / L
        fin = math.sin(t * math.pi / 2.0)
        fout = math.cos(t * math.pi / 2.0)
        for c in range(ch):
            head = data[i * ch + c]
            tail = data[(frames - L + i) * ch + c]
            v = int(head * fin + tail * fout)
            out[i * ch + c] = max(-32768, min(32767, v))
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--xfade", type=float, default=1.5, help="crossfade seconds")
    ap.add_argument("--tol", type=float, default=3.0,
                    help="dB below the body RMS that counts as the fade-out")
    args = ap.parse_args()

    data, ch, rate = read_wav(args.src)
    frames = len(data) // ch
    cut = find_fade_start(data, ch, rate, args.tol)
    trimmed = array.array("h", data[: cut * ch])
    looped = crossfade_loop(trimmed, ch, int(args.xfade * rate))

    with wave.open(args.dst, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(looped.tobytes())

    out_frames = len(looped) // ch
    print("%s -> %s" % (args.src.split("/")[-1], args.dst.split("/")[-1]))
    print("  %.2fs -> trimmed %.2fs -> looped %.2fs  (%d ch @ %d Hz)"
          % (frames / rate, cut / rate, out_frames / rate, ch, rate))
    edge = max(1, rate // 10)
    head = frame_rms(looped, ch, 0, edge)
    tail = frame_rms(looped, ch, out_frames - edge, edge)
    to_db = lambda v: 20.0 * math.log10(v + 1e-9)
    print("  seam: head %.1f dBFS  tail %.1f dBFS  (gap %.1f dB)"
          % (to_db(head), to_db(tail), abs(to_db(head) - to_db(tail))))


if __name__ == "__main__":
    main()
