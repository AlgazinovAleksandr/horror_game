#!/usr/bin/env python3
"""Generate images with Google's Nano Banana Pro (Gemini 3 Pro Image).

Defaults to the Gemini Developer API (auth via GEMINI_API_KEY).
To use Vertex AI instead, set GOOGLE_GENAI_USE_VERTEXAI=true plus
GOOGLE_CLOUD_PROJECT and GOOGLE_CLOUD_LOCATION, and authenticate with ADC.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

DEFAULT_MODEL = "gemini-3-pro-image-preview"
ASPECT_RATIOS = ["1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"]
SIZES = ["1K", "2K", "4K"]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Generate an image with Nano Banana Pro (Gemini 3 Pro Image).",
    )
    p.add_argument("prompt", help="Text prompt describing the image.")
    p.add_argument("-o", "--output", required=True, help="Output image file path (e.g. public/hero.png).")
    p.add_argument("--aspect-ratio", default="16:9", choices=ASPECT_RATIOS, help="Image aspect ratio (default: 16:9).")
    p.add_argument("--size", default="2K", choices=SIZES, help="Image resolution tier (default: 2K).")
    p.add_argument("--model", default=DEFAULT_MODEL, help=f"Model ID (default: {DEFAULT_MODEL}).")
    p.add_argument(
        "--input",
        action="append",
        default=[],
        metavar="PATH",
        help="Reference/input image to edit or compose. Repeatable.",
    )
    return p.parse_args()


def build_client():
    try:
        from google import genai
    except ImportError:
        sys.exit(
            "error: google-genai is not installed.\n"
            "run: bash ~/.claude/skills/nano-banana-pro/install.sh\n"
            "or:  pip install -r ~/.claude/skills/nano-banana-pro/requirements.txt"
        )

    use_vertex = os.environ.get("GOOGLE_GENAI_USE_VERTEXAI", "").lower() in ("true", "1", "yes")
    if use_vertex:
        project = os.environ.get("GOOGLE_CLOUD_PROJECT")
        location = os.environ.get("GOOGLE_CLOUD_LOCATION", "global")
        if not project:
            sys.exit("error: GOOGLE_GENAI_USE_VERTEXAI=true but GOOGLE_CLOUD_PROJECT is not set.")
        return genai.Client(vertexai=True, project=project, location=location)

    if not os.environ.get("GEMINI_API_KEY") and not os.environ.get("GOOGLE_API_KEY"):
        sys.exit(
            "error: GEMINI_API_KEY is not set.\n"
            "get a key at https://aistudio.google.com/apikey, then:\n"
            "  export GEMINI_API_KEY=your_key_here"
        )
    return genai.Client()


def load_input_image(path: str):
    from google.genai import types

    p = Path(path)
    if not p.is_file():
        sys.exit(f"error: input image not found: {path}")
    suffix = p.suffix.lower().lstrip(".")
    mime = {"jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "webp": "image/webp"}.get(
        suffix, f"image/{suffix or 'png'}"
    )
    return types.Part.from_bytes(data=p.read_bytes(), mime_type=mime)


def main() -> int:
    args = parse_args()
    out_path = Path(args.output).expanduser().resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)

    from google.genai import types

    client = build_client()

    contents: list = [args.prompt]
    for ref in args.input:
        contents.append(load_input_image(ref))

    print(f"generating with {args.model} ({args.aspect_ratio}, {args.size})...", file=sys.stderr)
    response = client.models.generate_content(
        model=args.model,
        contents=contents,
        config=types.GenerateContentConfig(
            response_modalities=["TEXT", "IMAGE"],
            image_config=types.ImageConfig(aspect_ratio=args.aspect_ratio, image_size=args.size),
        ),
    )

    saved = False
    for part in response.parts:
        if part.text:
            print(part.text, file=sys.stderr)
            continue
        image = part.as_image() if hasattr(part, "as_image") else None
        if image is not None:
            image.save(str(out_path))
            saved = True
            break
        inline = getattr(part, "inline_data", None)
        if inline and getattr(inline, "data", None):
            out_path.write_bytes(inline.data)
            saved = True
            break

    if not saved:
        feedback = getattr(response, "prompt_feedback", None)
        sys.exit(f"error: no image returned. prompt_feedback={feedback!r}")

    print(str(out_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
