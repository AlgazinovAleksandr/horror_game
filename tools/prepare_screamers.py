#!/usr/bin/env python3
"""Prepare per-level screamer assets for the horror game.

Godot's `GameState.load_audio()` only resolves `.wav` / `.ogg`, and the Gemini
image pipeline occasionally writes JPEG bytes into a `.png` file (see
ISSUES_SOLUTIONS.md). This script makes the new screamer assets engine-ready:

  1. Convert any `screamer_*.mp3` to `.ogg` (ffmpeg) and drop the `.mp3`.
  2. Verify every screamer / special-scare PNG is a real PNG; re-encode with
     `sips` if it is secretly a JPEG.
  3. Print a checklist of which level expects which image + audio base name and
     whether the files are present, so missing wiring is obvious at a glance.

Pure orchestration around system tools (ffmpeg / sips / file) so it needs no
third-party Python packages. Reproducible — safe to re-run.

Usage:
    .venv/bin/python3 tools/prepare_screamers.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AUDIO = ROOT / "game" / "assets" / "audio"
TEX = ROOT / "game" / "assets" / "textures"

# level -> (image path relative to textures/, audio base name)
LEVEL_SCREAMERS = {
    "1 Lab": ("level_1_lab/screamer_lab.png", "screamer_lab"),
    "2 House": ("level_2_house/screamer_house.png", "screamer_house"),
    "3 Corridor": ("level_3_corridor/screamer_hotel.png", "screamer_corridor"),
    "4 Void": ("level_4_void/screamer_void.png", "screamer_void"),
}
# special survivable scares (image + audio base)
SPECIAL_SCARES = {
    "Forest (house window)": ("level_2_house/screamer_forest.png", "screamer_forest"),
    "Manager (corridor)": ("level_3_corridor/screamer_manager.png", "screamer_manager"),
}
AUDIO_EXTS = ("wav", "ogg")


def run(cmd: list[str]) -> str:
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout


def is_real_png(path: Path) -> bool:
    return path.read_bytes()[:8] == b"\x89PNG\r\n\x1a\n"


def find_audio(base: str) -> Path | None:
    for ext in AUDIO_EXTS:
        for sub in AUDIO.iterdir():
            if not sub.is_dir():
                continue
            candidate = sub / f"{base}.{ext}"
            if candidate.exists():
                return candidate
    return None


def convert_mp3s() -> None:
    print("== Converting stray .mp3 screamer audio to .ogg ==")
    mp3s = list(AUDIO.rglob("screamer_*.mp3"))
    if not mp3s:
        print("  (none)")
    for mp3 in mp3s:
        ogg = mp3.with_suffix(".ogg")
        run(["ffmpeg", "-y", "-i", str(mp3), "-c:a", "libvorbis", "-q:a", "6", str(ogg)])
        mp3.unlink()
        print(f"  {mp3.name} -> {ogg.name}  (removed .mp3)")


def validate_pngs() -> None:
    print("\n== Validating screamer / scare PNGs (JPEG-as-PNG guard) ==")
    images = {p for p, _ in LEVEL_SCREAMERS.values()} | {p for p, _ in SPECIAL_SCARES.values()}
    images |= {"level_2_house/forest.png", "level_3_corridor/mirror_with_creature.png",
               "level_3_corridor/ordinary_hotel_door.png"}
    for rel in sorted(images):
        path = TEX / rel
        if not path.exists():
            print(f"  MISSING  {rel}")
            continue
        if is_real_png(path):
            print(f"  ok       {rel}")
        else:
            run(["sips", "-s", "format", "png", str(path), "--out", str(path)])
            print(f"  fixed    {rel}  (re-encoded JPEG -> PNG)")


def checklist() -> None:
    print("\n== Per-level screamer wiring checklist ==")
    for label, (img, base) in {**LEVEL_SCREAMERS, **SPECIAL_SCARES}.items():
        img_ok = (TEX / img).exists()
        audio = find_audio(base)
        img_mark = "img:ok " if img_ok else "img:?? "
        audio_mark = f"audio:{audio.name}" if audio else "audio:MISSING"
        print(f"  [{img_mark}{audio_mark:>24}]  {label}")


def main() -> int:
    convert_mp3s()
    validate_pngs()
    checklist()
    print("\nDone. Now run the Godot import pass:")
    print("  /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --import")
    return 0


if __name__ == "__main__":
    sys.exit(main())
