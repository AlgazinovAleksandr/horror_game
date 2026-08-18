#!/usr/bin/env python3
"""Turn a generated figure-on-a-pale-background image into a real RGBA cutout.

WHY THIS EXISTS
---------------
Every billboard in this game — the apparition, the Watcher, the Congregation, the Smiler,
the Perekozhnik — is an unshaded `QuadMesh` with `TRANSPARENCY_ALPHA`. If the texture has no
alpha channel the quad renders as a SOLID RECTANGLE. That is the `apparition_figure.jpg` bug,
and `SCARY.md` §7.1(2) warns about the exact trap that produced it: you ask the generator for
"a completely transparent background" and it hands back **opaque RGB** with the background
painted in — sometimes as a checkerboard, which looks like transparency in a preview and is
not.

Measured 2026-07-28 on five freshly generated images: all five came back `mode=RGB`, alpha
extrema `None`. The prompt said "transparent background - alpha cutout" four different ways.
It does not matter how the prompt is worded; verify and fix instead.

WHAT IT DOES
------------
The generator reliably puts a DARK figure on a PALE background (sampled: figure ~40/255,
background 200-255), so keying on luminance is unambiguous:

  * alpha = 255 below `--lo`, 0 above `--hi`, smooth ramp between (keeps the edge soft so the
    silhouette does not alias into a cut-out-with-scissors look)
  * crop to the alpha bounding box with a small margin, which also fixes the OTHER thing the
    generator ignores — it returns 16:9 landscape however loudly you ask for portrait, and
    `SCARY.md` §7.1(4) requires the texture aspect to match the mesh
  * write RGBA

Usage:
    tools/cutout_alpha.py FILE [FILE ...] [--lo 90] [--hi 170] [--margin 12]

⚠️ Run it AFTER `sips -s format png` (Issue 1/25: the API returns JPEG bytes inside a `.png`
and Godot imports it as invalid while `ResourceLoader.exists()` still returns true).
⚠️ Re-import afterwards, or Godot keeps serving the old `.ctex`.
"""

import argparse
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("error: Pillow is required. Use nano-banana-pro/.venv/bin/python3")


def sample_background(path: str) -> "tuple[int, int, int]":
    """Median of the eight border samples — what the background ACTUALLY is.

    ⚠️ Never assume the generator honoured the colour you asked for. A spec demanding
    "#00FF00, perfectly flat uniform solid chroma-key green" came back as (30, 143, 74) —
    green, but 137 units away in RGB, which sailed straight past a fixed tolerance and left
    the whole image opaque (measured 2026-07-29, alpha extrema (127, 255) instead of (0, 255)).
    Sampling the border costs nothing and cannot be wrong about what is there.
    """
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    pts = [(3, 3), (w - 4, 3), (3, h - 4), (w - 4, h - 4),
           (3, h // 2), (w - 4, h // 2), (w // 2, 3), (w // 2, h - 4)]
    samples = [px[x, y] for x, y in pts]
    med = []
    for ch in range(3):
        vals = sorted(s[ch] for s in samples)
        med.append(int((vals[3] + vals[4]) / 2))
    return (med[0], med[1], med[2])


def cutout(path: str, lo: float, hi: float, margin: int,
           chroma: "tuple[int, int, int] | None" = None,
           tol_lo: float = 60.0, tol_hi: float = 130.0,
           despill: bool = True,
           green: "tuple[float, float] | None" = None) -> str:
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()

    alpha = Image.new("L", (w, h))
    ap = alpha.load()

    if green is not None:
        # GREENNESS KEY — for a green screen the generator did not paint flat.
        #
        # ⚠️ ADDED 2026-08-16, for the Corridor's mirror figure. `--chroma auto` samples ONE
        # background colour and keys on distance from it, which assumes the background is
        # uniform. Measured on that generation: the corners were (5, 128, 55) and the
        # mid-left was (60, 230, 139) — the two backgrounds are 142 apart in RGB, i.e.
        # further from each other than tol_hi, so no single centre could key both without
        # eating the figure.
        #
        # Hue is what is actually constant on a lit green screen, so key on how much greener
        # a pixel is than its own red and blue. Measured on the same image: background
        # scores 73-91, pale skin 2, dark gown 17, lit face -3, bare foot -23 — a gap so
        # wide the thresholds barely matter.
        g_lo, g_hi = green
        span = max(1e-6, g_hi - g_lo)
        for y in range(h):
            for x in range(w):
                r, g, b = px[x, y]
                score = g - max(r, b)
                if score <= g_lo:
                    ap[x, y] = 255
                elif score >= g_hi:
                    ap[x, y] = 0
                else:
                    ap[x, y] = int(255 * (1.0 - (score - g_lo) / span))
    elif chroma is not None:
        # CHROMA KEY — for subjects that are NOT reliably darker than their background.
        #
        # The luminance key below assumes a dark figure on a pale ground, which is how the
        # generator returns a silhouette. It cannot handle "bright and colourful": a pale
        # face on white keys away to nothing. Asking for a saturated background the subject
        # will never contain, and keying on distance from that colour, works for any subject.
        cr, cg, cb = chroma
        span = max(1e-6, tol_hi - tol_lo)
        for y in range(h):
            for x in range(w):
                r, g, b = px[x, y]
                d = ((r - cr) ** 2 + (g - cg) ** 2 + (b - cb) ** 2) ** 0.5
                if d <= tol_lo:
                    ap[x, y] = 0
                elif d >= tol_hi:
                    ap[x, y] = 255
                else:
                    ap[x, y] = int(255 * (d - tol_lo) / span)
    else:
        span = max(1e-6, hi - lo)
        for y in range(h):
            for x in range(w):
                r, g, b = px[x, y]
                # Rec. 601 luma — matches how the eye weights these channels, so a dark green
                # figure on a warm-white ground keys the same as a neutral one.
                lum = 0.299 * r + 0.587 * g + 0.114 * b
                if lum <= lo:
                    ap[x, y] = 255
                elif lum >= hi:
                    ap[x, y] = 0
                else:
                    ap[x, y] = int(255 * (1.0 - (lum - lo) / span))

    if (chroma is not None or green is not None) and despill:
        # GREEN SUPPRESSION. Alpha 0 hides the background, but the RGB underneath is still
        # green, and every partially-transparent edge pixel blends some of it back in. With
        # TRANSPARENCY_ALPHA (what `watcher.gd` uses) that shows as a green rim around the
        # figure; a hard ALPHA_SCISSOR would not, but not every caller uses one.
        # The standard fix: no pixel may be greener than its own red/blue by more than a
        # small margin. Leaves red dresses, blue shoes and white lace untouched.
        for y in range(h):
            for x in range(w):
                r, g, b = px[x, y]
                cap = max(r, b) + 12
                if g > cap:
                    px[x, y] = (r, cap, b)

    box = alpha.getbbox()
    if box is None:
        return f"FAIL {path}: nothing survived the key — is the figure pale?"

    im.putalpha(alpha)
    l, t, r, b = box
    l = max(0, l - margin)
    t = max(0, t - margin)
    r = min(w, r + margin)
    b = min(h, b + margin)
    out = im.crop((l, t, r, b))
    out.save(path)

    ex = out.getchannel("A").getextrema()
    ok = ex != (255, 255)
    return (f"{'OK  ' if ok else 'FAIL'} {path.split('/')[-1]:26} "
            f"{w}x{h} -> {out.size[0]}x{out.size[1]}  alpha_extrema={ex}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--lo", type=float, default=90.0,
                    help="luminance at or below which a pixel is fully opaque")
    ap.add_argument("--hi", type=float, default=170.0,
                    help="luminance at or above which a pixel is fully transparent")
    ap.add_argument("--margin", type=int, default=12)
    ap.add_argument("--chroma", default=None,
                    help='key on distance from a colour instead of luminance, e.g. "0,255,0". '
                         "Use for BRIGHT or multi-coloured subjects, where the luminance key "
                         "cannot separate figure from ground.")
    ap.add_argument("--tol-lo", type=float, default=60.0)
    ap.add_argument("--tol-hi", type=float, default=130.0)
    ap.add_argument("--no-despill", action="store_true",
                    help="skip green suppression (only if the subject is genuinely green)")
    ap.add_argument("--green", action="store_true",
                    help="key on GREENNESS (g - max(r, b)) rather than on a single colour. "
                         "Use when the green screen is lit unevenly, which is the normal "
                         "case with a generated background.")
    ap.add_argument("--green-lo", type=float, default=25.0)
    ap.add_argument("--green-hi", type=float, default=55.0)
    args = ap.parse_args()
    for f in args.files:
        chroma = None
        green = (args.green_lo, args.green_hi) if args.green else None
        if args.chroma == "auto":
            chroma = sample_background(f)
            print(f"     {f.split('/')[-1]}: background sampled as {chroma}")
        elif args.chroma:
            parts = [int(p) for p in args.chroma.split(",")]
            if len(parts) != 3:
                sys.exit("error: --chroma wants three values (e.g. 0,255,0) or 'auto'")
            chroma = (parts[0], parts[1], parts[2])
        print(cutout(f, args.lo, args.hi, args.margin, chroma, args.tol_lo, args.tol_hi,
                     not args.no_despill, green))


if __name__ == "__main__":
    main()
