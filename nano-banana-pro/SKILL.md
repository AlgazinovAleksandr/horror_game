---
name: nano-banana-pro
description: Generate custom images for websites and apps using Google's Nano Banana Pro (Gemini 3 Pro Image). Use whenever the user asks for a hero image, OG/social image, illustration, icon, marketing visual, product mockup, background, or any custom image asset — also use when the user asks to edit, restyle, or compose an existing image. Triggers on phrases like "generate an image", "create a picture", "make a hero image", "design a banner", "I need an illustration of", "use nano banana", or any request that produces a PNG/JPG asset for the project.
---

# Nano Banana Pro image generation

This skill calls Google's Gemini 3 Pro Image model (codename "Nano Banana Pro") via the `generate_image.py` script bundled in this skill folder, and saves the result into the user's project.

## When to use

Invoke this skill any time the deliverable is an image file the user wants in their project — hero/landing images, OG images, blog headers, illustrations, icons, product photos, backgrounds, mockups. Also invoke when the user asks to edit/restyle/combine existing images (the model accepts input images).

Do NOT invoke for: logo design where the user expects vector/SVG output, charts/diagrams that should be code (Mermaid, D3), or screenshots of real apps.

## Prerequisites (check before first run)

The script needs one of:
1. `GEMINI_API_KEY` environment variable (preferred — get one at https://aistudio.google.com/apikey), OR
2. Vertex AI mode: `GOOGLE_GENAI_USE_VERTEXAI=true` plus `GOOGLE_CLOUD_PROJECT` and `GOOGLE_CLOUD_LOCATION`, with ADC configured (`gcloud auth application-default login`).

Plus Python deps: `google-genai` and `pillow`.

If the user runs this for the first time and either the env var or the deps are missing, run `bash ~/.claude/skills/nano-banana-pro/install.sh` and tell them to set `GEMINI_API_KEY` (point them at the README in this folder).

## How to invoke

Always use absolute paths. The script lives at `~/.claude/skills/nano-banana-pro/generate_image.py`.

Basic text-to-image:
```bash
python3 ~/.claude/skills/nano-banana-pro/generate_image.py \
  "A wide cinematic shot of a misty pine forest at sunrise, golden light, photorealistic" \
  -o public/images/hero.png \
  --aspect-ratio 16:9 \
  --size 2K
```

Edit or compose with existing images (pass one or more `--input`):
```bash
python3 ~/.claude/skills/nano-banana-pro/generate_image.py \
  "Place this logo centered on a deep navy background with subtle radial gradient" \
  -o public/og.png \
  --aspect-ratio 16:9 \
  --input assets/logo.png
```

## Choosing parameters

- **Aspect ratio** — pick what fits the slot:
  - `16:9` — hero banners, OG images, video thumbnails (default)
  - `1:1` — avatars, square cards, Instagram
  - `9:16` — mobile splash, phone hero, stories
  - `21:9` — ultra-wide cinematic banners
  - `3:2` / `4:3` — blog headers, product photos
  - Other supported: `2:3`, `3:4`, `4:5`, `5:4`
- **Size** — `1K`, `2K`, `4K`. Default `2K` is the right choice for most web work; only use `4K` when the user asks for print/large display.
- **Output path** — save into the project's static asset folder (`public/`, `static/`, `assets/`, `src/assets/`, etc.). Pick the existing convention by inspecting the repo.

## Prompting tips for great web visuals

Nano Banana Pro is strong at photorealism, typography, and following compositional instructions. For the best output:

1. Describe **subject, style, lighting, camera, mood** explicitly. "Photorealistic", "vector flat illustration", "isometric 3D render", "watercolor", etc.
2. Say what should be in **negative space** if the user will overlay text — e.g. "leave the right third uncluttered for headline text".
3. Specify **palette** when the site has a brand — e.g. "muted earth tones: #2A2A2A, #C9A36B, #F4EFE6".
4. For OG/social images, include "centered composition with generous margins" so cropping is safe.

If the user's prompt is vague, write a richer prompt yourself based on the site's existing style (peek at the repo's CSS/Tailwind config or existing imagery), then pass that detailed prompt to the script.

## After generation

1. Confirm the file exists at the output path.
2. Wire it into the page (e.g. `next/image`, `<img>`, CSS background) — don't just generate the file and stop.
3. If the user is iterating, regenerate with a refined prompt rather than asking them to re-prompt — show them the new image and ask whether to keep iterating.

## Errors

- `GEMINI_API_KEY not set` → tell the user to get a key at https://aistudio.google.com/apikey and `export GEMINI_API_KEY=...`.
- `No module named google.genai` → run `bash ~/.claude/skills/nano-banana-pro/install.sh`.
- `RAI filtered` / `safety` errors → soften the prompt (avoid named real people, violent imagery, branded characters) and retry once.
- 429 / quota → tell the user; do not silently retry in a loop.
