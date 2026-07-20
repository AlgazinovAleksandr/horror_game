#!/usr/bin/env python3
"""Synthesise the Lab's public-address announcement.

This is the spoken half of the LEVEL 4 HINT (the whiteboard in the observation room
is the other half — see tools/make_lab_whiteboard.py and CLAUDE.md). It fires once,
in level_1.gd:_restore_power(), because the PA can only wake up when the power does.

The line never says "wall" and never names the Backrooms. It describes the exit as
"the surface that will not hold still" and is cut off mid-sentence by the relay
dropping, so the player is left with a rule they have to recognise later rather than
an instruction they can follow now.

Voiced with macOS `say`, then degraded through ffmpeg into a 1970s tannoy: band-limited
to a telephone-ish 300-3000 Hz, lightly overdriven, laid over a mains hum, and topped
and tailed with relay clicks.

Run:  python3 tools/make_pa_voice.py     (no venv needed — stdlib + say + ffmpeg)
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game/assets/audio/level_1_lab/pa_trial4.wav"

VOICE = "Daniel"     # en_GB, dry and institutional — reads as a records clerk
RATE = 172           # words per minute; unhurried, bored, reading from a file

LINE = (
    "Addendum to trial four. "
    "Subjects continue to search for a door. "
    "Record shows there is no door. "
    "The way out is the surface that will not hold still. "
    "Through. Not around. "
    "Subject forty seven is not to be"
)


def need(binary):
    if shutil.which(binary) is None:
        sys.exit(f"error: {binary} not found on PATH")


def main():
    need("say")
    need("ffmpeg")

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        raw = tmp / "raw.aiff"
        subprocess.run(
            ["say", "-v", VOICE, "-r", str(RATE), "-o", str(raw), LINE],
            check=True,
        )

        # Voice chain, in order:
        #   highpass/lowpass  -> tannoy band-limiting, kills the "clean TTS" tell
        #   acrusher slightly -> cheap driver distortion
        #   atempo 0.97       -> a hair slow; tape-ish, subtly wrong
        #   aecho             -> short slapback = a hard-walled corridor
        #   afade out         -> the relay cuts the last word dead
        voice = tmp / "voice.wav"
        subprocess.run([
            "ffmpeg", "-y", "-loglevel", "error", "-i", str(raw),
            "-af",
            "atempo=0.97,"
            "highpass=f=320,lowpass=f=2900,"
            "acrusher=level_in=1:level_out=1:bits=10:mode=log:aa=0.4,"
            "aecho=0.7:0.6:55:0.28,"
            "volume=1.6,"
            # Softener on the attack only. NOTE: this must be t=in — an afade
            # t=out at st=0 silences the entire remainder of the stream.
            "afade=t=in:st=0:d=0.06",
            "-ar", "44100", "-ac", "1", str(voice),
        ], check=True)

        # Duration, so the hum bed and the trailing click line up with the speech.
        dur = float(subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=nw=1:nk=1", str(voice)],
            check=True, capture_output=True, text=True).stdout.strip())

        total = dur + 1.1   # 0.35 s of carrier before, ~0.75 s of dead air after

        # 50 Hz mains hum + its third harmonic = the sound of a live open channel.
        hum = tmp / "hum.wav"
        subprocess.run([
            "ffmpeg", "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", f"sine=frequency=50:duration={total:.3f}",
            "-f", "lavfi", "-i", f"sine=frequency=150:duration={total:.3f}",
            "-filter_complex",
            "[0:a]volume=0.055[a];[1:a]volume=0.022[b];[a][b]amix=inputs=2:normalize=0,"
            "highpass=f=40",
            "-ar", "44100", "-ac", "1", str(hum),
        ], check=True)

        # Relay clicks: a broadband tick at the head (channel opens) and one at the
        # very end (the cut). Built as filtered noise bursts.
        click = tmp / "click.wav"
        subprocess.run([
            "ffmpeg", "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", "anoisesrc=duration=0.05:color=white:amplitude=0.6",
            "-af", "highpass=f=900,lowpass=f=6000,afade=t=out:st=0:d=0.05",
            "-ar", "44100", "-ac", "1", str(click),
        ], check=True)

        subprocess.run([
            "ffmpeg", "-y", "-loglevel", "error",
            "-i", str(hum), "-i", str(voice), "-i", str(click),
            "-filter_complex",
            # voice starts after the opening click; closing click lands on the cut
            f"[1:a]adelay=350|350[v];"
            f"[2:a]adelay=60|60[c1];"
            f"[2:a]adelay={int((dur + 0.42) * 1000)}|{int((dur + 0.42) * 1000)}[c2];"
            f"[0:a][v][c1][c2]amix=inputs=4:normalize=0:duration=longest,"
            f"alimiter=limit=0.92,"
            f"afade=t=in:st=0:d=0.04,afade=t=out:st={total - 0.25:.3f}:d=0.25",
            "-ar", "44100", "-ac", "1", "-sample_fmt", "s16", str(OUT),
        ], check=True)

    print(f"wrote {OUT} ({OUT.stat().st_size} bytes, ~{total:.2f}s)")


if __name__ == "__main__":
    main()
